class_name Ctl
extends Node3D
## One physical control or display on a panel. The panel's local frame: x right, y up,
## +z out of the panel face toward the keeper; a control sits at its origin on the face.
##
## Kinds:
##   toggle   two-way bat switch (bool); `guarded` puts a red flip cover over it
##   rotary   selector with N detents (int): LMB steps on, the wheel steps either way
##   knob     continuous pot (float 0..1): the wheel turns it
##   button   momentary push button: calls `on_press`; `lit_fn` lights it
##   breaker  push-pull circuit breaker (bool); pops out on a trip
##   lever    throttle on a slot (float 0..1): the wheel moves it, LMB snaps to idle
##   valve    handwheel valve (float 0..1): LMB turns it fully open or shut, slowly
##   gauge    needle dial reading `read_fn` between lo and hi
##   lamp     annunciator tile lit by `lit_fn`
##   digits   numeric readout showing `text_fn`
##   bar      vertical level bar reading `read_fn` (0..1)

const FACE := Color(0.17, 0.18, 0.18)
const LEGEND := Color(0.93, 0.92, 0.86)
const AMBER := Color(1.0, 0.62, 0.12)
const RED := Color(1.0, 0.16, 0.1)
const GREEN := Color(0.3, 1.0, 0.45)
const WHITE := Color(0.95, 0.95, 0.9)
## Every printed legend is this much bigger than its nominal size, so it reads at arm's length.
const LEGEND_SCALE := 1.35

static var _font: SystemFont
## Where the eye is (set by the player each frame): controls near it animate every frame.
static var eye := Vector3.ZERO
## Past this distance a control's small parts and every legend are not drawn (m).
const DRAW_RANGE := 9.0
const NEAR := 4.0
static var _mono: SystemFont
static var _mats := {}

var kind := ""
var title := ""
## Read and write the bound value (sim field, breaker...).
var get_fn: Callable
var set_fn: Callable
var on_press: Callable
var lit_fn: Callable
var read_fn: Callable
var text_fn: Callable
var guarded := false
var positions: PackedStringArray = []
var lo := 0.0
var hi := 1.0
var red_from := INF
var unit := ""
var color := AMBER
var step := 0.05
## Is the control live (its bus has power)? Lamps and displays go dark without it.
var power_fn: Callable

var it: Interactable
var _moving: Node3D
var _guard: Node3D
var _guard_open := 0.0
var _guard_t := 0.0
var _lamp_mat: StandardMaterial3D
## A rotary with too many positions to letter round it: the one selected, in a window under it.
var _readout: Label3D
var _sel_shown := -1
var _label: Label3D
var _needle: Node3D
var _shown := -INF
var _valve_target := -1.0
var _bar: MeshInstance3D
var _bar_h := 0.1
var _acc := 0.0
var _phase := 0


static func font() -> Font:
	if _font == null:
		_font = SystemFont.new()
		_font.font_names = PackedStringArray(["Bahnschrift", "Arial Narrow", "Arial", "sans-serif"])
		_font.font_weight = 600
		_font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	return _font


static func mono() -> Font:
	if _mono == null:
		_mono = SystemFont.new()
		_mono.font_names = PackedStringArray(["Consolas", "Lucida Console", "Courier New", "monospace"])
		_mono.font_weight = 700
	return _mono


static func mat(key: String) -> Material:
	if _mats.has(key):
		return _mats[key]
	var m: Material
	match key:
		"face":
			m = Looks.panel(FACE, 0.75, 0.0, 0.5, 0.0)
		"metal":
			m = Kit.metal(Color(0.78, 0.79, 0.8), 0.3, 0.9)
		"dark":
			m = Kit.metal(Color(0.09, 0.09, 0.1), 0.45, 0.6)
		"black":
			m = Kit.matte(Color(0.02, 0.02, 0.02), 0.6)
		"white":
			m = Kit.matte(Color(0.88, 0.87, 0.82), 0.6)
		"guard":
			m = Kit.matte(Color(0.75, 0.08, 0.05), 0.4)
		"yellow":
			m = Kit.matte(Color(0.95, 0.72, 0.1), 0.5)
		"black_yellow":
			m = Kit.matte(Color(0.12, 0.12, 0.1), 0.5)
		"needle":
			m = Kit.glow(Color(1.0, 0.55, 0.15), 0.6)
		"redline":
			m = Kit.matte(Color(0.8, 0.1, 0.06), 0.6)
		"glassface":
			m = Kit.matte(Color(0.06, 0.07, 0.065), 0.25)
		_:
			m = Kit.matte(Color.MAGENTA)
	_mats[key] = m
	return m


## Make a legend fit a w x h face (m): on one line if it can, else broken in two at the
## space that balances the lines best, and shrunk until the widest line and the height fit.
static func fit(l: Label3D, w: float, h: float) -> void:
	var font: Font = l.font
	var fs := l.font_size
	# From the legend's own size each time (a language change fits it again).
	if not l.has_meta("px0"):
		l.set_meta("px0", l.pixel_size)
	l.set_meta("fit", Vector2(w, h))
	var px: float = l.get_meta("px0")
	var width := func(t: String) -> float: return font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x * px
	var lines := PackedStringArray([l.text])
	var words := l.text.split(" ", false)
	if "\n" in l.text:
		# Already broken into lines by hand: keep them, only shrink.
		lines = l.text.split("\n")
	elif width.call(l.text) > w and words.size() > 1:
		var best := INF
		for k in range(1, words.size()):
			var a := " ".join(words.slice(0, k))
			var b := " ".join(words.slice(k))
			var m := maxf(width.call(a), width.call(b))
			if m < best:
				best = m
				lines = PackedStringArray([a, b])
	var widest := 0.0
	for t in lines:
		widest = maxf(widest, width.call(t))
	var tall := font.get_height(fs) * px * lines.size()
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.text = "\n".join(lines)
	l.pixel_size = px * minf(1.0, minf(w / maxf(widest, 1e-6), h / maxf(tall, 1e-6)))


## A control's name over it: kept within the control's own width (broken in two and shrunk if
## it must be), growing upward so it never runs into the control below it.
static func _title(l: Label3D) -> Label3D:
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	fit(l, 0.13, 0.034)
	return l


## Printed legend on a panel: `size` is the letter height in metres.
static func text(parent: Node3D, s: String, pos: Vector3, size := 0.016, col := LEGEND, align := HORIZONTAL_ALIGNMENT_CENTER, mono_font := false) -> Label3D:
	var l := Label3D.new()
	l.text = Loc.t(s)
	l.set_meta("en", s)
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.font = mono() if mono_font else font()
	l.font_size = 48
	l.pixel_size = size * LEGEND_SCALE / 34.0
	l.modulate = col
	l.outline_size = 0
	l.horizontal_alignment = align
	l.position = pos
	l.shaded = true
	l.double_sided = false
	# Anisotropic: lettering seen at a slant across a panel stays sharp instead of smearing.
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	# Printed legends cannot be read from the far end of the station: not drawn there.
	l.visibility_range_end = DRAW_RANGE
	l.visibility_range_end_margin = 1.0
	parent.add_child(l)
	return l


func _ready() -> void:
	_phase = randi() % 8
	_cull.call_deferred()
	match kind:
		"toggle":
			_build_toggle()
		"rotary":
			_build_rotary()
		"knob":
			_build_knob()
		"button":
			_build_button()
		"breaker":
			_build_breaker()
		"lever":
			_build_lever()
		"valve":
			_build_valve()
		"gauge":
			_build_gauge()
		"lamp":
			_build_lamp()
		"digits":
			_build_digits()
		"bar":
			_build_bar()


func _hit(size: Vector3, center := Vector3.ZERO) -> Interactable:
	var shape := BoxShape3D.new()
	shape.size = size
	it = Interactable.make(self, title, "", shape, center)
	return it


func _live() -> bool:
	return not power_fn.is_valid() or bool(power_fn.call())


func _value() -> Variant:
	return get_fn.call() if get_fn.is_valid() else null


# --- Builders ----------------------------------------------------------------------------

func _build_toggle() -> void:
	Kit.mesh(self, Kit.cylinder(0.014, 0.008, 16), mat("metal"), Vector3(0, 0, 0.004), Basis(Vector3.RIGHT, PI / 2.0))
	Kit.mesh(self, Kit.cylinder(0.009, 0.006, 6), mat("dark"), Vector3(0, 0, 0.01), Basis(Vector3.RIGHT, PI / 2.0))
	_moving = Node3D.new()
	_moving.position = Vector3(0, 0, 0.012)
	add_child(_moving)
	Kit.mesh(_moving, Kit.cylinder(0.0035, 0.032, 10, 0.0045), mat("metal"), Vector3(0, 0, 0.016), Basis(Vector3.RIGHT, PI / 2.0))
	Kit.mesh(_moving, Kit.sphere(0.0055, 8), mat("metal"), Vector3(0, 0, 0.032))
	_title(text(self, title, Vector3(0, 0.05, 0.001), 0.012))
	var labels := positions if positions.size() == 2 else PackedStringArray(["OFF", "ON"])
	text(self, labels[1], Vector3(0, 0.026, 0.001), 0.009)
	text(self, labels[0], Vector3(0, -0.032, 0.001), 0.009)
	if guarded:
		_guard = Node3D.new()
		_guard.position = Vector3(0, -0.022, 0.004)
		add_child(_guard)
		var g := Kit.box(Vector3(0.036, 0.05, 0.004))
		Kit.mesh(_guard, g, mat("guard"), Vector3(0, 0.025, 0.04))
		Kit.mesh(_guard, Kit.box(Vector3(0.004, 0.05, 0.04)), mat("guard"), Vector3(-0.016, 0.025, 0.02))
		Kit.mesh(_guard, Kit.box(Vector3(0.004, 0.05, 0.04)), mat("guard"), Vector3(0.016, 0.025, 0.02))
	_hit(Vector3(0.05, 0.06, 0.05), Vector3(0, 0, 0.02))
	it.on_use = func() -> void:
		if guarded and _guard_open < 0.5:
			_guard_open = 1.0
			_guard_t = 4.0
			Sfx.play_at("latch", global_position, -14.0, 1.6)
			return
		set_fn.call(not bool(_value()))
		_guard_t = 4.0
		Sfx.play_at("switch", global_position, -6.0)
	it.verb_fn = func() -> String:
		if guarded and _guard_open < 0.5:
			return "Lift the cover"
		return "Switch " + (labels[0] if bool(_value()) else labels[1])
	it.value_fn = func() -> String: return labels[1] if bool(_value()) else labels[0]


func _build_rotary() -> void:
	Kit.mesh(self, Kit.cylinder(0.022, 0.006, 24), mat("dark"), Vector3(0, 0, 0.003), Basis(Vector3.RIGHT, PI / 2.0))
	_moving = Node3D.new()
	_moving.position = Vector3(0, 0, 0.006)
	add_child(_moving)
	Kit.mesh(_moving, Kit.box(Vector3(0.012, 0.04, 0.018)), mat("black"), Vector3(0, 0, 0.009))
	Kit.mesh(_moving, Kit.box(Vector3(0.003, 0.016, 0.004)), mat("white"), Vector3(0, 0.011, 0.019))
	var n := positions.size()
	var crowded := n > 6
	for i in n:
		var a := _rotary_angle(i, n)
		Kit.mesh(self, Kit.box(Vector3(0.002, 0.007, 0.001)), mat("white"), Vector3(-sin(a), cos(a), 0.0) * 0.027 + Vector3(0, 0, 0.001), Basis(Vector3.BACK, a))
		if crowded:
			continue
		# Lettered round the dial, each kept to its own room: out to the side on the flanks.
		var p := Vector3(-sin(a), cos(a), 0.0) * 0.042
		var side := -sin(a)
		var align := HORIZONTAL_ALIGNMENT_CENTER
		if side < -0.4:
			align = HORIZONTAL_ALIGNMENT_RIGHT
			p.x += 0.012
		elif side > 0.4:
			align = HORIZONTAL_ALIGNMENT_LEFT
			p.x -= 0.012
		var room := 0.044 if absf(side) > 0.4 else 0.034
		var l := text(self, positions[i], p + Vector3(0, -0.004, 0.001), 0.0085, LEGEND, align)
		fit(l, room, 0.011)
	if crowded:
		# Too many to letter: a backlit window under the dial shows the one selected.
		Kit.mesh(self, Kit.box(Vector3(0.1, 0.024, 0.002)), mat("black"), Vector3(0, -0.046, 0.001))
		_readout = text(self, positions[0], Vector3(0, -0.046, 0.0025), 0.014, Color(0.55, 1.0, 0.7), HORIZONTAL_ALIGNMENT_CENTER, true)
		_readout.shaded = false
		fit(_readout, 0.094, 0.019)
	_title(text(self, title, Vector3(0, 0.072, 0.001), 0.012))
	_hit(Vector3(0.05, 0.05, 0.04), Vector3(0, 0, 0.015))
	it.on_use = func() -> void:
		set_fn.call((int(_value()) + 1) % n)
		Sfx.play_at("click", global_position, -6.0, 0.8)
	it.on_wheel = func(dir: int) -> void:
		var v := clampi(int(_value()) + dir, 0, n - 1)
		if v != int(_value()):
			set_fn.call(v)
			Sfx.play_at("click", global_position, -6.0, 0.8)
	it.verb_fn = func() -> String: return "Turn"
	it.value_fn = func() -> String: return positions[clampi(int(_value()), 0, n - 1)]


func _rotary_angle(i: int, n: int) -> float:
	var span := deg_to_rad(minf(60.0 * (n - 1), 270.0))
	return span * 0.5 - span * float(i) / maxf(n - 1, 1)


func _build_knob() -> void:
	Kit.mesh(self, Kit.cylinder(0.016, 0.022, 20, 0.014), mat("black"), Vector3(0, 0, 0.011), Basis(Vector3.RIGHT, PI / 2.0))
	_moving = Node3D.new()
	_moving.position = Vector3(0, 0, 0.022)
	add_child(_moving)
	Kit.mesh(_moving, Kit.box(Vector3(0.0025, 0.012, 0.002)), mat("white"), Vector3(0, 0.007, 0.0))
	for i in 11:
		var a := deg_to_rad(135.0 - 27.0 * i)
		var len := 0.007 if i % 5 == 0 else 0.004
		Kit.mesh(self, Kit.box(Vector3(0.0015, len, 0.001)), mat("white"), Vector3(-sin(a), cos(a), 0.0) * (0.024 + len * 0.5) + Vector3(0, 0, 0.001), Basis(Vector3.BACK, a))
	text(self, "0", Vector3(-0.026, -0.03, 0.001), 0.008)
	text(self, "10", Vector3(0.026, -0.03, 0.001), 0.008)
	_title(text(self, title, Vector3(0, 0.05, 0.001), 0.012))
	_hit(Vector3(0.05, 0.05, 0.05), Vector3(0, 0, 0.015))
	it.on_wheel = func(dir: int) -> void:
		set_fn.call(clampf(float(_value()) + dir * step, 0.0, 1.0))
		Sfx.play_at("click", global_position, -16.0, 1.5)
	it.value_fn = func() -> String: return "%.1f" % (float(_value()) * 10.0)


func _build_button() -> void:
	Kit.mesh(self, Kit.box(Vector3(0.04, 0.04, 0.006)), mat("dark"), Vector3(0, 0, 0.003))
	_moving = Node3D.new()
	add_child(_moving)
	_lamp_mat = Kit.glow(color, 0.0)
	_lamp_mat.albedo_color = color.darkened(0.6)
	Kit.mesh(_moving, Kit.box(Vector3(0.032, 0.032, 0.012)), _lamp_mat, Vector3(0, 0, 0.012))
	var cap := text(_moving, title, Vector3(0, 0, 0.0185), 0.0075, Color(0.05, 0.05, 0.05))
	fit(cap, 0.028, 0.027)
	if guarded:
		_guard = Node3D.new()
		_guard.position = Vector3(0, -0.024, 0.006)
		add_child(_guard)
		var gm := Kit.glass(Color(1.0, 0.25, 0.1, 0.35), 0.15)
		Kit.mesh(_guard, Kit.box(Vector3(0.044, 0.048, 0.003)), gm, Vector3(0, 0.024, 0.026))
		Kit.mesh(_guard, Kit.box(Vector3(0.003, 0.048, 0.026)), mat("guard"), Vector3(-0.021, 0.024, 0.013))
		Kit.mesh(_guard, Kit.box(Vector3(0.003, 0.048, 0.026)), mat("guard"), Vector3(0.021, 0.024, 0.013))
	_hit(Vector3(0.045, 0.045, 0.04), Vector3(0, 0, 0.015))
	it.on_use = func() -> void:
		if guarded and _guard_open < 0.5:
			_guard_open = 1.0
			_guard_t = 5.0
			Sfx.play_at("latch", global_position, -14.0, 1.6)
			return
		_moving.position.z = -0.006
		Sfx.play_at("click", global_position, -4.0, 1.1)
		_guard_t = 5.0
		if on_press.is_valid():
			on_press.call()
	it.verb_fn = func() -> String: return "Lift the cover" if guarded and _guard_open < 0.5 else "Press"


func _build_breaker() -> void:
	Kit.mesh(self, Kit.cylinder(0.009, 0.004, 12), mat("dark"), Vector3(0, 0, 0.002), Basis(Vector3.RIGHT, PI / 2.0))
	_moving = Node3D.new()
	add_child(_moving)
	# White collar shows when the breaker is out.
	Kit.mesh(_moving, Kit.cylinder(0.0058, 0.008, 12), mat("white"), Vector3(0, 0, 0.004), Basis(Vector3.RIGHT, PI / 2.0))
	Kit.mesh(_moving, Kit.cylinder(0.0065, 0.008, 12), mat("black"), Vector3(0, 0, 0.012), Basis(Vector3.RIGHT, PI / 2.0))
	var t := _title(text(self, title, Vector3(0, 0.017, 0.001), 0.0075))
	t.autowrap_mode = TextServer.AUTOWRAP_OFF
	_hit(Vector3(0.026, 0.026, 0.03), Vector3(0, 0, 0.01))
	it.on_use = func() -> void:
		set_fn.call(not bool(_value()))
		Sfx.play_at("latch", global_position, -8.0, 1.3)
	it.verb_fn = func() -> String: return "Pull out" if bool(_value()) else "Push in"
	it.value_fn = func() -> String: return "IN" if bool(_value()) else "OUT"


func _build_lever() -> void:
	Kit.mesh(self, Kit.box(Vector3(0.05, 0.24, 0.01)), mat("dark"), Vector3(0, 0, 0.005))
	Kit.mesh(self, Kit.box(Vector3(0.012, 0.21, 0.004)), mat("black"), Vector3(0, 0, 0.011))
	for i in 5:
		var y := -0.1 + 0.05 * i
		Kit.mesh(self, Kit.box(Vector3(0.012, 0.0018, 0.001)), mat("white"), Vector3(0.024, y, 0.011))
		text(self, "%d" % (i * 25), Vector3(0.044, y - 0.004, 0.001), 0.008)
	_moving = Node3D.new()
	add_child(_moving)
	Kit.mesh(_moving, Kit.box(Vector3(0.008, 0.008, 0.07)), mat("metal"), Vector3(0, 0, 0.045))
	Kit.mesh(_moving, Kit.box(Vector3(0.06, 0.026, 0.024)), mat("black"), Vector3(0, 0, 0.085))
	_title(text(self, title, Vector3(0, 0.135, 0.001), 0.013))
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.07, 0.04, 0.05)
	it = Interactable.make(_moving, title, "", shape, Vector3(0, 0, 0.08))
	it.on_wheel = func(dir: int) -> void:
		set_fn.call(clampf(float(_value()) + dir * step, 0.0, 1.0))
		Sfx.play_at("click", global_position, -18.0, 0.6)
	it.on_use = func() -> void:
		set_fn.call(0.0)
		Sfx.play_at("clunk", global_position, -10.0, 1.2)
	it.verb_fn = func() -> String: return "Pull to idle"
	it.value_fn = func() -> String: return "%d %%" % roundi(float(_value()) * 100.0)


func _build_valve() -> void:
	Kit.mesh(self, Kit.cylinder(0.012, 0.03, 12), mat("metal"), Vector3(0, 0, 0.015), Basis(Vector3.RIGHT, PI / 2.0))
	_moving = Node3D.new()
	_moving.position = Vector3(0, 0, 0.034)
	add_child(_moving)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.034
	ring.outer_radius = 0.042
	ring.rings = 24
	ring.ring_segments = 8
	Kit.mesh(_moving, ring, mat("guard"), Vector3.ZERO, Basis(Vector3.RIGHT, PI / 2.0))
	for i in 3:
		var a := TAU * i / 3.0
		Kit.mesh(_moving, Kit.box(Vector3(0.006, 0.038, 0.005)), mat("guard"), Vector3(-sin(a), cos(a), 0) * 0.019, Basis(Vector3.BACK, a))
	_title(text(self, title, Vector3(0, 0.06, 0.001), 0.012))
	text(self, "OPEN %s" % "↺", Vector3(-0.055, -0.004, 0.001), 0.008)
	_hit(Vector3(0.09, 0.09, 0.05), Vector3(0, 0, 0.03))
	it.on_use = func() -> void:
		_valve_target = 0.0 if float(_value()) > 0.5 else 1.0
		Sfx.play_at("servo", global_position, -14.0, 1.4)
	it.on_wheel = func(dir: int) -> void:
		_valve_target = -1.0
		set_fn.call(clampf(float(_value()) + dir * 0.1, 0.0, 1.0))
	it.verb_fn = func() -> String: return "Close" if float(_value()) > 0.5 else "Open"
	it.value_fn = func() -> String: return "%d %% open" % roundi(float(_value()) * 100.0)


func _build_gauge() -> void:
	var r := 0.045
	Kit.mesh(self, Kit.cylinder(r + 0.006, 0.012, 32), mat("dark"), Vector3(0, 0, 0.006), Basis(Vector3.RIGHT, PI / 2.0))
	Kit.mesh(self, Kit.cylinder(r, 0.002, 32), mat("glassface"), Vector3(0, 0, 0.0125), Basis(Vector3.RIGHT, PI / 2.0))
	var b := Geo.Builder.new()
	var red := Geo.Builder.new()
	for i in 21:
		var f := i / 20.0
		var a := deg_to_rad(120.0 - 240.0 * f)
		var len := 0.009 if i % 5 == 0 else 0.005
		var v := lerpf(lo, hi, f)
		var target := red if v >= red_from else b
		target.box(Vector3(-sin(a), cos(a), 0.0) * (r - 0.004 - len * 0.5) + Vector3(0, 0, 0.0135), Vector3(0.0016, len, 0.001), Basis(Vector3.BACK, a))
		if i % 5 == 0:
			var p := Vector3(-sin(a), cos(a), 0.0) * (r - 0.02)
			text(self, _fmt_scale(v), p + Vector3(0, -0.003, 0.0135), 0.0065, Color(0.85, 0.85, 0.8))
	Kit.mesh(self, b.commit(mat("white")), null)
	if not red.is_empty():
		Kit.mesh(self, red.commit(mat("redline")), null)
	_needle = Node3D.new()
	_needle.position = Vector3(0, 0, 0.016)
	add_child(_needle)
	Kit.mesh(_needle, Kit.box(Vector3(0.002, r * 0.85, 0.001)), mat("needle"), Vector3(0, r * 0.38, 0))
	Kit.mesh(self, Kit.cylinder(0.004, 0.004, 10), mat("black"), Vector3(0, 0, 0.017), Basis(Vector3.RIGHT, PI / 2.0))
	text(self, unit, Vector3(0, -0.026, 0.0135), 0.0075, Color(0.85, 0.85, 0.8))
	_title(text(self, title, Vector3(0, r + 0.016, 0.001), 0.012))
	_hit(Vector3(0.1, 0.1, 0.02), Vector3(0, 0, 0.01))
	it.value_fn = func() -> String: return _fmt_value(float(read_fn.call())) + " " + unit


func _fmt_scale(v: float) -> String:
	if absf(hi - lo) >= 1000.0:
		return "%d" % roundi(v / 1000.0)
	if absf(hi - lo) >= 10.0:
		return "%d" % roundi(v)
	return "%.1f" % v


func _fmt_value(v: float) -> String:
	if absf(v) >= 100.0:
		return "%d" % roundi(v)
	return "%.2f" % v


func _build_lamp() -> void:
	_lamp_mat = Kit.glow(color, 0.0)
	_lamp_mat.albedo_color = Color(0.1, 0.1, 0.1)
	Kit.mesh(self, Kit.box(Vector3(0.064, 0.03, 0.006)), mat("black"), Vector3(0, 0, 0.003))
	Kit.mesh(self, Kit.box(Vector3(0.058, 0.025, 0.004)), _lamp_mat, Vector3(0, 0, 0.007))
	_label = text(self, title, Vector3(0, 0, 0.0095), 0.0078, Color(0.4, 0.4, 0.38))
	fit(_label, 0.052, 0.021)
	_label.shaded = false
	_hit(Vector3(0.064, 0.03, 0.01), Vector3(0, 0, 0.005))
	it.value_fn = func() -> String: return "LIT" if bool(lit_fn.call()) else "dark"


func _build_digits() -> void:
	Kit.mesh(self, Kit.box(Vector3(0.11, 0.034, 0.008)), mat("black"), Vector3(0, 0, 0.004))
	_label = text(self, "", Vector3(0.048, -0.008, 0.0085), 0.017, color, HORIZONTAL_ALIGNMENT_RIGHT, true)
	_label.shaded = false
	_title(text(self, title, Vector3(0, 0.026, 0.001), 0.0095))
	_hit(Vector3(0.11, 0.034, 0.01), Vector3(0, 0, 0.005))


func _build_bar() -> void:
	_bar_h = 0.12
	Kit.mesh(self, Kit.box(Vector3(0.026, _bar_h + 0.008, 0.008)), mat("black"), Vector3(0, 0, 0.004))
	var m := Kit.glow(color, 1.2)
	_bar = Kit.mesh(self, Kit.box(Vector3(0.016, _bar_h, 0.002)), m, Vector3(0, 0, 0.009))
	for i in 5:
		Kit.mesh(self, Kit.box(Vector3(0.006, 0.0015, 0.001)), mat("white"), Vector3(0.017, -_bar_h * 0.5 + _bar_h * i / 4.0, 0.001))
	_title(text(self, title, Vector3(0, _bar_h * 0.5 + 0.016, 0.001), 0.0095))
	_hit(Vector3(0.03, _bar_h, 0.01), Vector3(0, 0, 0.005))
	it.value_fn = func() -> String: return "%d %%" % roundi(clampf(float(read_fn.call()), 0.0, 1.0) * 100.0)


# --- Per frame -----------------------------------------------------------------------------

## Small parts are not drawn from far off (they would be a few pixels at most).
func _cull() -> void:
	for n in find_children("*", "GeometryInstance3D", true, false):
		(n as GeometryInstance3D).visibility_range_end = DRAW_RANGE
		(n as GeometryInstance3D).visibility_range_end_margin = 1.0


func _process(delta: float) -> void:
	# Hundreds of these on the panels: the ones out of reach catch up every eighth frame.
	_acc += delta
	if _valve_target < 0.0 and global_position.distance_squared_to(eye) > NEAR * NEAR and (Engine.get_process_frames() + _phase) % 8 != 0:
		return
	delta = _acc
	_acc = 0.0
	if _guard:
		_guard_t -= delta
		if _guard_t <= 0.0:
			_guard_open = 0.0
		_guard.rotation.x = lerpf(_guard.rotation.x, -1.9 * _guard_open, minf(delta * 10.0, 1.0))
	match kind:
		"toggle":
			_moving.rotation.x = lerpf(_moving.rotation.x, -0.45 if bool(_value()) else 0.45, minf(delta * 25.0, 1.0))
		"rotary":
			_moving.rotation.z = lerpf(_moving.rotation.z, _rotary_angle(int(_value()), positions.size()), minf(delta * 20.0, 1.0))
			var sel := clampi(int(_value()), 0, positions.size() - 1)
			if _readout and sel != _sel_shown:
				_sel_shown = sel
				_readout.set_meta("en", positions[sel])
				_readout.text = Loc.t(positions[sel])
				fit(_readout, 0.094, 0.019)
		"knob":
			_moving.rotation.z = deg_to_rad(135.0 - 270.0 * float(_value()))
		"button":
			_moving.position.z = lerpf(_moving.position.z, 0.0, minf(delta * 12.0, 1.0))
			var on := _live() and lit_fn.is_valid() and bool(lit_fn.call())
			_lamp_mat.emission_energy_multiplier = 2.2 if on else 0.0
			_lamp_mat.albedo_color = color if on else color.darkened(0.65)
		"breaker":
			_moving.position.z = lerpf(_moving.position.z, 0.0 if bool(_value()) else 0.007, minf(delta * 20.0, 1.0))
		"lever":
			_moving.position.y = lerpf(-0.1, 0.1, float(_value()))
		"valve":
			if _valve_target >= 0.0:
				var v := move_toward(float(_value()), _valve_target, delta * 0.35)
				set_fn.call(v)
				if is_equal_approx(v, _valve_target):
					_valve_target = -1.0
			_moving.rotation.z = float(_value()) * TAU * 2.5
		"gauge":
			var v := clampf(float(read_fn.call()) if _live() else lo, lo - (hi - lo) * 0.03, hi + (hi - lo) * 0.03)
			var f := (v - lo) / (hi - lo)
			_needle.rotation.z = lerpf(_needle.rotation.z, deg_to_rad(120.0 - 240.0 * f), minf(delta * 6.0, 1.0))
		"lamp":
			var on := _live() and bool(lit_fn.call())
			_lamp_mat.emission_energy_multiplier = 1.8 if on else 0.0
			_lamp_mat.albedo_color = color if on else Color(0.1, 0.1, 0.1)
			_label.modulate = Color(0.06, 0.04, 0.02) if on else Color(0.38, 0.38, 0.36)
		"digits":
			# Setting a label's text reshapes it: only when it changes.
			var t := String(text_fn.call()) if _live() else ""
			if _label.text != t:
				_label.text = t
		"bar":
			var f := clampf(float(read_fn.call()), 0.0, 1.0) if _live() else 0.0
			_bar.scale.y = maxf(f, 0.001)
			_bar.position.y = -_bar_h * 0.5 * (1.0 - f)
