class_name Hud
extends CanvasLayer
## Drawn over the view: the hand cursor and what it is aimed at (name, live reading,
## what LMB and the wheel do), short messages, title cards and fades. Menus live in Menu.

const ICON_PX := 48.0

var player: Player
var debug_lines: Callable
var cinematic := false
## What the body is complaining about, shown small in the corner.
var complaints := PackedStringArray()
## The suit's readout while it is worn.
var suit_line := ""
## Asleep: how long so far, shown on the dark.
var night := ""
## The instant camera's finder: its line of text when the camera is up at the eye, else "".
var viewfinder_fn: Callable

var _canvas: Control
var _font: Font
var _debug := false
var _card := ""
var _card_sub := ""
var _card_t := 99.0
var _card_len := 6.0
var _toasts: Array = []
var _fade := 1.0
var _fade_target := 0.0
var _fade_speed := 0.6
var _shake := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 2
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_hud)
	_canvas.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(_canvas)
	_font = Ctl.font()


func _process(delta: float) -> void:
	_card_t += delta
	for t: Array in _toasts:
		t[1] += delta
	_toasts = _toasts.filter(func(t: Array) -> bool: return t[1] < 6.0)
	_fade = move_toward(_fade, _fade_target, delta * _fade_speed)
	if Input.is_action_just_pressed("debug"):
		_debug = not _debug
	if _shake > 0.0 and player:
		_shake = maxf(_shake - delta, 0.0)
		var k := minf(_shake, 1.0) * 0.01
		player.cam.h_offset = randf_range(-k, k)
		player.cam.v_offset = randf_range(-k, k)
	elif player:
		player.cam.h_offset = 0.0
		player.cam.v_offset = 0.0
	_canvas.queue_redraw()


# --- API ----------------------------------------------------------------------------------------

func card(text: String, sub := "", seconds := 6.0) -> void:
	_card = text
	_card_sub = sub
	_card_len = seconds
	_card_t = 0.0


func toast(text: String) -> void:
	_toasts.append([text, 0.0])
	if _toasts.size() > 4:
		_toasts.pop_front()


func fade_to(black: float, speed := 0.6) -> void:
	_fade_target = black
	_fade_speed = speed


func fade_value() -> float:
	return _fade


func shake(seconds: float) -> void:
	_shake = maxf(_shake, seconds * Settings.shake)


# --- Drawing ------------------------------------------------------------------------------------

func _draw_hud() -> void:
	var size := _canvas.size
	var c := size * 0.5
	var finder: String = viewfinder_fn.call() if viewfinder_fn.is_valid() else ""
	if finder != "" and not cinematic:
		_draw_finder(size, finder)
	elif player and not cinematic:
		_draw_cursor(c)
		if suit_line != "":
			var sl := Loc.t(suit_line)
			var w := _font.get_string_size(sl, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
			_canvas.draw_string(_font, Vector2(size.x - w - 24.0, size.y - 30.0), sl, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.6, 1.0, 0.75, 0.85))
		for k in complaints.size():
			_badge(Vector2(size.x - 24.0, 24.0 + k * 42.0), complaints[k])
	var y := size.y - 130.0
	for i in range(_toasts.size() - 1, -1, -1):
		var t: Array = _toasts[i]
		var a := clampf((6.0 - float(t[1])) / 1.0, 0.0, 1.0)
		_text(Vector2(c.x, y), String(t[0]), 18, Color(1.0, 0.86, 0.58, a))
		y -= 24.0
	if player and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and DisplayServer.get_name() != "headless" and not get_tree().paused and not cinematic:
		_text(c + Vector2(0, -70), "Click to take control", 22, Color(1, 1, 1, 0.85))
	# What the other hand carries, and the key for it.
	if player and not cinematic:
		var h := player.hand
		var oh := h.offhand if h.offhand and is_instance_valid(h.offhand) else null
		var line := ""
		var held_small := h.held != null and is_instance_valid(h.held) and h.held.kind in Hand.OFFHAND_KINDS
		if held_small:
			line = Loc.t("Q  to the other hand")
		elif oh:
			line = Loc.t("Other hand: %s") % Loc.t(oh.display_name) + "      " + Loc.t("Q  put away") + "      " + Loc.t("E  take")
		elif not h.pocket.is_empty() and is_instance_valid(h.pocket.back()):
			line = Loc.t("Pocket: %s") % Loc.t(h.pocket.back().display_name) + "      " + Loc.t("Q  take out")
		if line != "":
			_canvas.draw_string(_font, Vector2(24, size.y - 30.0), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.85, 0.85, 0.8, 0.8))
	if player and not cinematic and player.hand.held and is_instance_valid(player.hand.held) and player.hand.held.kind == "manual":
		_draw_manual(size, int(player.hand.held.get_meta("page", 0)), String(player.hand.held.get_meta("book", "station")))
	_canvas.draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, _fade))
	if night != "":
		var na := clampf((_fade - 0.8) / 0.2, 0.0, 1.0) * 0.7
		_text(Vector2(c.x, size.y * 0.5), night, 26, Color(0.75, 0.78, 0.82, na))
		_text(Vector2(c.x, size.y * 0.5 + 30), "asleep", 15, Color(0.55, 0.58, 0.62, na))
	if _card_t < _card_len:
		var a := clampf(_card_t / 1.2, 0.0, 1.0) * clampf((_card_len - _card_t) / 1.5, 0.0, 1.0)
		_text(Vector2(c.x, size.y * 0.42), _card, 46, Color(0.92, 0.9, 0.86, a))
		_text(Vector2(c.x, size.y * 0.42 + 40), _card_sub, 18, Color(0.75, 0.78, 0.82, a * 0.85))
	if _debug and debug_lines.is_valid():
		var yy := 24.0
		for line: String in debug_lines.call():
			_canvas.draw_string(_font, Vector2(16, yy), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.7, 1.0, 0.8))
			yy += 18.0


func _draw_cursor(c: Vector2) -> void:
	var hand := player.hand
	var kind := hand.hover_kind
	match kind:
		"anchor", "held", "working":
			var at := c
			var p := hand.cursor_world()
			if kind != "held" and not player.cam.is_position_behind(p):
				at = player.cam.unproject_position(p)
			_icon(HandIcons.fist(), at)
			if kind == "anchor":
				_canvas.draw_arc(c, 9.0, 0.0, TAU, 24, Color(1, 1, 1, 0.75), 1.5, true)
				_canvas.draw_circle(c, 1.6, Color(1, 1, 1, 0.9))
				var k := player.charge()
				if k >= 0.0:
					_canvas.draw_arc(c, 22.0, -PI * 0.5, -PI * 0.5 + TAU, 48, Color(1, 1, 1, 0.18), 3.0, true)
					_canvas.draw_arc(c, 22.0, -PI * 0.5, -PI * 0.5 + TAU * maxf(k, 0.04), 48, Color(1.0, 0.8, 0.4, 0.95), 3.0, true)
		"use", "prop", "surface":
			_icon(HandIcons.open_hand(), c)
		_:
			_canvas.draw_circle(c, 2.2, Color(1, 1, 1, 0.7))
	var y := c.y + ICON_PX * 0.5 + 22.0
	if hand.hover_name != "" and kind != "anchor":
		_text(Vector2(c.x, y), hand.hover_name, 17, Color(1, 1, 1, 0.9))
		y += 20.0
		var reading := hand.hover_value()
		if reading != "":
			_text(Vector2(c.x, y), reading, 16, Color(0.55, 1.0, 0.7, 0.9))
			y += 20.0
	if hand.hover_hint != "":
		_text(Vector2(c.x, y), hand.hover_hint, 14, Color(1.0, 0.85, 0.55, 0.85))
		y += 18.0


func _icon(tex: Texture2D, center: Vector2) -> void:
	# Drawn at its own size on whole pixels, so the big pixels stay crisp.
	var sz := Vector2(tex.get_width(), tex.get_height())
	_canvas.draw_texture(tex, (center - sz * 0.5).floor())


## The badges up in the right-hand corner: what is wrong with the keeper (or round them), an
## icon and its name, red and pulsing when it is killing them. `right_top`: the badge's
## top-right corner.
const SEVERE := ["STARVING", "PARCHED", "EXHAUSTED", "RADIATION SICK", "SHORT OF AIR", "HIGH RADIATION"]


func _badge(right_top: Vector2, what: String) -> void:
	var severe := what in SEVERE
	var pulse := 0.65 + 0.35 * sin(Time.get_ticks_msec() / 220.0) if severe else 1.0
	var col := Color(1.0, 0.36, 0.26, pulse) if severe else Color(1.0, 0.8, 0.45, 0.95)
	var label := Loc.t(what)
	var tw := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	var r := Rect2(right_top - Vector2(tw + 58.0, 0.0), Vector2(tw + 58.0, 34.0))
	_canvas.draw_rect(r, Color(0.02, 0.02, 0.03, 0.62))
	_canvas.draw_rect(r, Color(col.r, col.g, col.b, 0.75 * col.a), false, 1.5)
	_canvas.draw_rect(Rect2(r.position, Vector2(3.0, r.size.y)), col)
	_icon_for(what, r.position + Vector2(22.0, 17.0), col)
	_canvas.draw_string(_font, r.position + Vector2(42.0, 23.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.95, 0.93, 0.88, maxf(col.a, 0.8)))


## A small drawn icon, centred at `c`.
func _icon_for(what: String, c: Vector2, col: Color) -> void:
	match what:
		"RADIATION", "HIGH RADIATION", "RADIATION SICK":
			for k in 3:
				var a0 := TAU * k / 3.0 - PI / 2.0 - 0.5
				var pts := PackedVector2Array([c + Vector2(cos(a0), sin(a0)) * 3.0])
				for f in 7:
					var a := a0 + float(f) / 6.0
					pts.append(c + Vector2(cos(a), sin(a)) * 11.0)
				pts.append(c + Vector2(cos(a0 + 1.0), sin(a0 + 1.0)) * 3.0)
				_canvas.draw_colored_polygon(pts, col)
			_canvas.draw_circle(c, 2.2, col)
		"HUNGRY", "STARVING":
			_canvas.draw_line(c + Vector2(-5, -10), c + Vector2(-5, 10), col, 2.0)
			for dx in [-8, -5, -2]:
				_canvas.draw_line(c + Vector2(dx, -10), c + Vector2(dx, -3), col, 1.5)
			_canvas.draw_line(c + Vector2(-8, -3), c + Vector2(-2, -3), col, 1.5)
			_canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(5, -10), c + Vector2(9, -4), c + Vector2(7, 0), c + Vector2(5, 0)]), col)
			_canvas.draw_line(c + Vector2(5, 0), c + Vector2(5, 10), col, 2.0)
		"THIRSTY", "PARCHED":
			_canvas.draw_circle(c + Vector2(0, 3), 6.5, col)
			_canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -11), c + Vector2(6.2, 1.5), c + Vector2(-6.2, 1.5)]), col)
		"TIRED", "EXHAUSTED":
			for z: Array in [[Vector2(-9, -2), 9.0], [Vector2(1, -10), 7.0]]:
				var o: Vector2 = c + (z[0] as Vector2)
				var s: float = z[1]
				_canvas.draw_polyline(PackedVector2Array([o, o + Vector2(s, 0), o + Vector2(0, s), o + Vector2(s, s)]), col, 2.0)
		"WEAK":
			_canvas.draw_line(c + Vector2(-8, 0), c + Vector2(8, 0), col, 2.0)
			for dx in [-9, 6]:
				_canvas.draw_rect(Rect2(c + Vector2(dx, -6), Vector2(3, 12)), col)
		"COLD":
			for k in 3:
				var a := PI / 3.0 * k
				var d := Vector2(cos(a), sin(a))
				_canvas.draw_line(c - d * 10.0, c + d * 10.0, col, 1.8)
				for s in [-1.0, 1.0]:
					var tip: Vector2 = c + d * 7.0 * s
					_canvas.draw_line(tip, tip + d.rotated(2.4 * s) * 3.5 * s, col, 1.5)
					_canvas.draw_line(tip, tip + d.rotated(-2.4 * s) * 3.5 * s, col, 1.5)
		"SHORT OF AIR":
			_canvas.draw_string(_font, c + Vector2(-11, 6), "O2", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, col)
		"HEADACHE":
			_canvas.draw_string(_font, c + Vector2(-14, 5), "CO2", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
		_:
			_canvas.draw_circle(c, 5.0, col)


func _text(center: Vector2, s0: String, font_size: int, color: Color) -> void:
	var s := Loc.t(s0)
	var w := _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var pos := Vector2(center.x - w * 0.5, center.y)
	_canvas.draw_string(_font, pos + Vector2(1, 1), s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0, 0, 0, color.a * 0.6))
	_canvas.draw_string(_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


## Through the instant camera: the square the print will show, the rest dimmed, corner marks,
## a centre cross and the film left.
func _draw_finder(size: Vector2, line: String) -> void:
	var s := minf(size.x, size.y)
	var r := Rect2((size - Vector2(s, s)) * 0.5, Vector2(s, s))
	var dim := Color(0, 0, 0, 0.62)
	_canvas.draw_rect(Rect2(0, 0, r.position.x, size.y), dim)
	_canvas.draw_rect(Rect2(r.end.x, 0, size.x - r.end.x, size.y), dim)
	var inner := r.grow(-s * 0.06)
	var white := Color(1, 1, 1, 0.85)
	var k := s * 0.07
	for corner in [inner.position, Vector2(inner.end.x, inner.position.y), inner.end, Vector2(inner.position.x, inner.end.y)]:
		var sx := 1.0 if corner.x < size.x * 0.5 else -1.0
		var sy := 1.0 if corner.y < size.y * 0.5 else -1.0
		_canvas.draw_line(corner, corner + Vector2(k * sx, 0), white, 2.0)
		_canvas.draw_line(corner, corner + Vector2(0, k * sy), white, 2.0)
	var c := size * 0.5
	_canvas.draw_line(c - Vector2(10, 0), c + Vector2(10, 0), Color(1, 1, 1, 0.6), 1.0)
	_canvas.draw_line(c - Vector2(0, 10), c + Vector2(0, 10), Color(1, 1, 1, 0.6), 1.0)
	_canvas.draw_rect(inner, Color(1, 1, 1, 0.15), false, 1.0)
	_text(Vector2(c.x, inner.end.y + 28.0), line, 15, Color(1.0, 0.86, 0.6, 0.9))


## The manual open in the hand: one page, paper on the right of the view.
## How tall a manual page's text runs at type scale `k`.
func _manual_height(pg: Array, tw: float, k: float) -> float:
	var h := _wrap(Loc.t(String(pg[0])), int(22 * k), tw).size() * 26.0 * k + 14.0 * k
	for step: String in pg[1]:
		h += _wrap(Loc.t(step), int(15 * k), tw - 26.0).size() * 20.0 * k + 9.0 * k
	return h


func _draw_manual(size: Vector2, page: int, book := "station") -> void:
	var pg_all := Manual.pages(book)
	var h := minf(size.y - 120.0, 640.0)
	var w := h * 0.74
	var r := Rect2(size.x - w - 60.0, (size.y - h) * 0.5, w, h)
	var paper := Color(0.88, 0.85, 0.76)
	var ink := Color(0.12, 0.1, 0.08)
	var faint := Color(0.12, 0.1, 0.08, 0.55)
	var amber := Color(0.72, 0.36, 0.08)
	_canvas.draw_rect(Rect2(r.position + Vector2(8, 8), r.size), Color(0, 0, 0, 0.5))
	_canvas.draw_rect(r, paper)
	_canvas.draw_rect(r.grow(-10.0), Color(ink, 0.25), false, 1.0)
	var mono := Ctl.mono()
	var x := r.position.x + 30.0
	var y := r.position.y + 50.0
	var tw := w - 60.0
	if page <= 0:
		_canvas.draw_string(mono, Vector2(x, y), "LANTERN", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, amber)
		y += 38.0
		_canvas.draw_string(_font, Vector2(x, y), Loc.t(Manual.title(book)), HORIZONTAL_ALIGNMENT_LEFT, -1, 30, ink)
		y += 26.0
		_canvas.draw_string(_font, Vector2(x, y), Loc.t("Keep it aboard. Turn the pages with the wheel."), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, faint)
		y += 44.0
		_canvas.draw_string(mono, Vector2(x, y), Loc.t("CONTENTS"), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, amber)
		y += 26.0
		# The contents close up (and the type comes down) to keep the list on the sheet.
		var step_y := minf(22.0, (r.end.y - 44.0 - y) / maxf(pg_all.size(), 1))
		var cs := clampi(int(step_y * 0.66), 9, 14)
		for k in pg_all.size():
			var title := Loc.t(String(pg_all[k][0]))
			_canvas.draw_string(mono, Vector2(x, y), "%2d  %s" % [k + 1, title], HORIZONTAL_ALIGNMENT_LEFT, tw, cs, ink)
			y += step_y
	else:
		var pg: Array = pg_all[mini(page, pg_all.size()) - 1]
		_canvas.draw_string(mono, Vector2(x, y), "%d" % page, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, amber)
		y += 30.0
		# The type shrinks until the page fits on the sheet, above the footer.
		var room := r.end.y - 44.0 - y
		var k := 1.0
		while k > 0.55 and _manual_height(pg, tw, k) > room:
			k -= 0.05
		var ts := int(22 * k)
		var bs := int(15 * k)
		for line in _wrap(Loc.t(String(pg[0])), ts, tw):
			_canvas.draw_string(_font, Vector2(x, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, ts, ink)
			y += 26.0 * k
		y += 14.0 * k
		var n := 1
		for step: String in pg[1]:
			_canvas.draw_string(mono, Vector2(x, y), "%d." % n, HORIZONTAL_ALIGNMENT_LEFT, -1, int(14 * k), amber)
			for line in _wrap(Loc.t(step), bs, tw - 26.0):
				_canvas.draw_string(_font, Vector2(x + 26.0, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, bs, ink)
				y += 20.0 * k
			y += 9.0 * k
			n += 1
	_canvas.draw_string(mono, Vector2(x, r.end.y - 26.0), Loc.t("PAGE %d / %d     WHEEL  TURN" % [page + 1, Manual.count(book)]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, faint)


func _wrap(text: String, font_size: int, width: float) -> PackedStringArray:
	var out := PackedStringArray()
	var line := ""
	for w in text.split(" "):
		var t := w if line == "" else line + " " + w
		if _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width - 20.0 and line != "":
			out.append(line)
			line = w
		else:
			line = t
	if line != "":
		out.append(line)
	return out
