class_name ControlPanel
extends Node3D
## A panel plate with controls on it, bound to the systems sim. Positions are given in
## metres from the panel's top-left corner (x right, y down); the face is at z = 0 and the
## keeper is on the +z side.

var sim: ShipSim
var size := Vector2(1.0, 0.6)
var title := ""
## Is the panel's instrumentation powered? Lamps, gauges and readouts go dark without it.
var power: Callable


static func make(parent: Node3D, p_sim: ShipSim, p_title: String, p_size: Vector2, xform: Transform3D, p_power: Callable = Callable()) -> ControlPanel:
	var p := ControlPanel.new()
	p.sim = p_sim
	p.title = p_title
	p.size = p_size
	p.transform = xform
	p.power = p_power
	# A panel taller than the face it hangs on is shrunk to fit, controls and all.
	var room := Station.half_face() * 2.0 - 0.04
	if p_size.y > room:
		p.scale = Vector3.ONE * room / p_size.y
	p.name = p_title.replace(" ", "_")
	parent.add_child(p)
	p._build()
	return p


func _build() -> void:
	var plate := Kit.mesh(self, Kit.box(Vector3(size.x, size.y, 0.02)), Ctl.mat("face"), Vector3(0, 0, -0.01))
	plate.name = "Plate"
	# Frame lip and the title strip along the top.
	var frame := Geo.Builder.new()
	var w := 0.012
	frame.box(Vector3(0, size.y * 0.5 - w * 0.5, 0.004), Vector3(size.x, w, 0.008))
	frame.box(Vector3(0, -size.y * 0.5 + w * 0.5, 0.004), Vector3(size.x, w, 0.008))
	frame.box(Vector3(-size.x * 0.5 + w * 0.5, 0, 0.004), Vector3(w, size.y, 0.008))
	frame.box(Vector3(size.x * 0.5 - w * 0.5, 0, 0.004), Vector3(w, size.y, 0.008))
	Kit.mesh(self, frame.commit(Ctl.mat("dark")), null)
	if title != "":
		Kit.mesh(self, Kit.box(Vector3(size.x - 0.03, 0.03, 0.002)), Ctl.mat("black"), Vector3(0, size.y * 0.5 - 0.03, 0.001))
		var t := Ctl.text(self, title, Vector3(0, size.y * 0.5 - 0.036, 0.0025), 0.016, Ctl.LEGEND)
		t.shaded = true
		Ctl.fit(t, size.x - 0.1, 0.028)
	# Screw heads in the corners.
	for sx in [-1, 1]:
		for sy in [-1, 1]:
			Kit.mesh(self, Kit.cylinder(0.005, 0.003, 8), Ctl.mat("metal"), Vector3(sx * (size.x * 0.5 - 0.02), sy * (size.y * 0.5 - 0.02), 0.0015), Basis(Vector3.RIGHT, PI / 2.0))


func at(x: float, y: float) -> Vector3:
	return Vector3(x - size.x * 0.5, size.y * 0.5 - y, 0.0)


func _add(c: Ctl, x: float, y: float) -> Ctl:
	c.position = at(x, y)
	if power.is_valid():
		c.power_fn = power
	add_child(c)
	return c


func _bind(c: Ctl, key: String) -> void:
	if key.begins_with("brk."):
		var b := key.substr(4)
		c.get_fn = func() -> Variant: return sim.brk[b]
		c.set_fn = func(v: Variant) -> void: sim.brk[b] = bool(v)
	else:
		c.get_fn = func() -> Variant: return sim.get(key)
		c.set_fn = func(v: Variant) -> void: sim.set(key, v)


# --- Controls ----------------------------------------------------------------------------

func toggle(key: String, label: String, x: float, y: float, pos_labels := PackedStringArray(), guarded := false) -> Ctl:
	var c := Ctl.new()
	c.kind = "toggle"
	c.title = label
	c.positions = pos_labels
	c.guarded = guarded
	_bind(c, key)
	return _add(c, x, y)


func rotary(key: String, label: String, x: float, y: float, pos_labels: PackedStringArray) -> Ctl:
	var c := Ctl.new()
	c.kind = "rotary"
	c.title = label
	c.positions = pos_labels
	_bind(c, key)
	return _add(c, x, y)


func knob(key: String, label: String, x: float, y: float, step := 0.05) -> Ctl:
	var c := Ctl.new()
	c.kind = "knob"
	c.title = label
	c.step = step
	_bind(c, key)
	return _add(c, x, y)


func button(label: String, x: float, y: float, on_press: Callable, lit: Callable = Callable(), col := Ctl.AMBER, guarded := false) -> Ctl:
	var c := Ctl.new()
	c.kind = "button"
	c.title = label
	c.on_press = on_press
	c.lit_fn = lit
	c.color = col
	c.guarded = guarded
	return _add(c, x, y)


## A sim momentary command (ShipSim.press).
func press(cmd: String, label: String, x: float, y: float, lit: Callable = Callable(), col := Ctl.AMBER, guarded := false) -> Ctl:
	return button(label, x, y, func() -> void: sim.press(cmd), lit, col, guarded)


func breaker(name_key: String, x: float, y: float) -> Ctl:
	var c := Ctl.new()
	c.kind = "breaker"
	c.title = ShipSim.BREAKERS[name_key][0]
	_bind(c, "brk." + name_key)
	# Breakers are mechanical: they show their state with or without power.
	c.position = at(x, y)
	add_child(c)
	return c


func lever(key: String, label: String, x: float, y: float) -> Ctl:
	var c := Ctl.new()
	c.kind = "lever"
	c.title = label
	_bind(c, key)
	return _add(c, x, y)


func valve(key: String, label: String, x: float, y: float) -> Ctl:
	var c := Ctl.new()
	c.kind = "valve"
	c.title = label
	_bind(c, key)
	c.position = at(x, y)
	add_child(c)
	return c


func gauge(label: String, x: float, y: float, read: Callable, lo: float, hi: float, unit := "", red_from := INF) -> Ctl:
	var c := Ctl.new()
	c.kind = "gauge"
	c.title = label
	c.read_fn = read
	c.lo = lo
	c.hi = hi
	c.unit = unit
	c.red_from = red_from
	return _add(c, x, y)


func lamp(label: String, x: float, y: float, lit: Callable, col := Ctl.AMBER) -> Ctl:
	var c := Ctl.new()
	c.kind = "lamp"
	c.title = label
	c.lit_fn = lit
	c.color = col
	return _add(c, x, y)


func digits(label: String, x: float, y: float, text_fn: Callable, col := Ctl.AMBER) -> Ctl:
	var c := Ctl.new()
	c.kind = "digits"
	c.title = label
	c.text_fn = text_fn
	c.color = col
	return _add(c, x, y)


func bar(label: String, x: float, y: float, read: Callable, col := Ctl.GREEN) -> Ctl:
	var c := Ctl.new()
	c.kind = "bar"
	c.title = label
	c.read_fn = read
	c.color = col
	return _add(c, x, y)


## A thin printed frame grouping controls, with its name on the top edge.
func group(label: String, x: float, y: float, w: float, h: float) -> void:
	var b := Geo.Builder.new()
	var o := at(x, y)
	var lw := 0.002
	b.box(o + Vector3(w * 0.5, 0, 0.0006), Vector3(w, lw, 0.001))
	b.box(o + Vector3(w * 0.5, -h, 0.0006), Vector3(w, lw, 0.001))
	b.box(o + Vector3(0, -h * 0.5, 0.0006), Vector3(lw, h, 0.001))
	b.box(o + Vector3(w, -h * 0.5, 0.0006), Vector3(lw, h, 0.001))
	Kit.mesh(self, b.commit(Ctl.mat("white")), null)
	# The legend sits in a gap in the top line, as wide as the legend itself, in either
	# language, and never wider than the group.
	var l := Ctl.text(self, label, o + Vector3(w * 0.5, -0.004, 0.0016), 0.0095)
	Ctl.fit(l, w - 0.03, 0.012)
	var bg_w := 0.0
	for s: String in [label, Loc.t(label)]:
		bg_w = maxf(bg_w, l.font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, l.font_size).x * l.pixel_size)
	bg_w = minf(bg_w + 0.014, w - 0.01)
	Kit.mesh(self, Kit.box(Vector3(bg_w, 0.014, 0.001)), Ctl.mat("face"), o + Vector3(w * 0.5, 0, 0.001))


## A CRT set into the panel (centre at x, y; size in metres).
func crt(x: float, y: float, w: float, h: float, font_px := 11, px_per_m := 320.0) -> Terminal:
	Kit.mesh(self, Kit.box(Vector3(w + 0.03, h + 0.03, 0.02)), Ctl.mat("dark"), at(x, y) + Vector3(0, 0, 0.004))
	var t := Terminal.make(self, Transform3D(Basis(), at(x, y) + Vector3(0, 0, 0.0145)), Vector2(w, h), font_px, px_per_m)
	return t
