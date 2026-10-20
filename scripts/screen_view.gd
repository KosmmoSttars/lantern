class_name ScreenView
extends CanvasLayer
## A screen seen full size: E on any CRT aboard (held on to or just in reach) brings its
## picture up over the view, big, through the same tube (curve, scanlines, phosphor bleed),
## live as it changes. The mouse is free meanwhile: on a screen that can be worked (the map) a
## click picks, a drag turns it and the wheel zooms. E or Esc puts it away.

static var instance: ScreenView

const SHADER := """
shader_type canvas_item;
uniform vec3 tint : source_color = vec3(0.45, 1.0, 0.7);
uniform vec2 res = vec2(240.0, 160.0);
uniform float power = 1.0;

float lum(sampler2D tex, vec2 uv) {
	return texture(tex, uv).r;
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	c *= 1.0 + 0.015 * dot(c, c);
	vec2 uv = c * 0.5 + 0.5;
	float inside = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
	float t = lum(TEXTURE, uv);
	float b = 0.0;
	vec2 px = 1.0 / res;
	for (int i = -2; i <= 2; i++) {
		for (int j = -2; j <= 2; j++) {
			b += lum(TEXTURE, uv + vec2(float(i), float(j)) * px * 1.3);
		}
	}
	b /= 25.0;
	float scan = 0.72 + 0.28 * pow(abs(sin(uv.y * res.y * 3.14159)), 0.6);
	vec3 col = tint * (t * 1.35 + b * 0.9) * scan + tint * 0.035;
	float vig = smoothstep(1.35, 0.55, length(c));
	float flick = 0.98 + 0.02 * sin(TIME * 59.0);
	COLOR = vec4(col * vig * inside * flick * power * 1.25, 1.0);
}
"""

var player: Player
var hud: Hud
## Set by main: true when the view must go (asleep, dead, the game over, the pause menu).
var blocked_fn: Callable
## The screen shown (null: none).
var term: Terminal

var _root: Control
var _rect: TextureRect
var _bezel: ColorRect
var _title: Label
var _hint: Label
var _mat: ShaderMaterial
var _press := false
var _moved := 0.0
var _had_input := true
## The list beside a screen that has one (the map's CONTACTS): its title, its lines, and each
## line's id; polled now and then.
var _list_title: Label
var _rows: Array[Label] = []
var _row_ids: Array = []
var _list_t := 0.0
const LIST_W := 380.0
const ROW_H := 24.0


func _ready() -> void:
	instance = self
	layer = 3
	visible = false
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.78)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(shade)
	_bezel = ColorRect.new()
	_bezel.color = Color(0.07, 0.075, 0.07)
	_bezel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_bezel)
	_rect = TextureRect.new()
	_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = Shader.new()
	_mat.shader.code = SHADER
	_rect.material = _mat
	_root.add_child(_rect)
	_title = _label(20, Color(0.92, 0.88, 0.78, 0.95))
	_hint = _label(15, Color(1.0, 0.85, 0.55, 0.85))
	_list_title = _label(17, Color(0.92, 0.88, 0.78, 0.95))
	_list_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT


func _label(px: int, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", Ctl.font())
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(l)
	return l


func is_open() -> bool:
	return term != null


func open(t: Terminal) -> void:
	if t == null or not is_instance_valid(t):
		return
	term = t
	visible = true
	_rect.texture = t.texture()
	var c := t.modulate
	_mat.set_shader_parameter("tint", Color(c.r, c.g, c.b))
	_mat.set_shader_parameter("res", t.pixels())
	_title.text = Loc.t(t.it.display_name if t.it else "Screen")
	var hint := "Click  pick    Drag  turn    Wheel  zoom    E / Esc  put it away" if t.click_fn.is_valid() else "E / Esc  put it away"
	_hint.text = Loc.t(hint)
	_press = false
	_had_input = player.accept_input
	player.accept_input = false
	player.capture_mouse(false)
	hud.cinematic = true
	t.refresh()
	Sfx.play("click", -10.0, 1.2, "Station")
	_list_t = 0.0
	_fill_list()
	_layout()


## Put it away. `restore`: hand the controls back (not when something else took them).
func close(restore := true) -> void:
	if term == null:
		return
	term = null
	visible = false
	_press = false
	if restore:
		player.accept_input = _had_input
		player.capture_mouse(true)
		hud.cinematic = false
	Sfx.play("click", -12.0, 0.9, "Station")


func _process(_delta: float) -> void:
	if term == null:
		return
	if not is_instance_valid(term) or not term.is_visible_in_tree():
		close()
		return
	if blocked_fn.is_valid() and bool(blocked_fn.call()):
		close(false)
		return
	_mat.set_shader_parameter("power", 1.0 if term.powered else 0.0)
	_list_t += _delta
	if _list_t > 0.5:
		_list_t = 0.0
		_fill_list()
	_layout()
	# The line under the mouse lights up.
	var mp := get_viewport().get_mouse_position()
	for k in _rows.size():
		var hot := _rows[k].visible and _rows[k].get_global_rect().has_point(mp) and k < _row_ids.size()
		_rows[k].add_theme_color_override("font_color", Color(1.0, 0.92, 0.6) if hot else _tint())


func _tint() -> Color:
	var c := term.modulate if term else Color(0.45, 1.0, 0.7)
	return Color(c.r, c.g, c.b, 0.95)


## The list beside the screen, freshly from the screen's own list (distances change).
func _fill_list() -> void:
	var lines: Array = term.list_fn.call() if term and term.list_fn.is_valid() else []
	_list_title.visible = term != null and term.list_fn.is_valid()
	_list_title.text = Loc.t(term.list_title) if term else ""
	_row_ids.clear()
	if _list_title.visible and lines.is_empty():
		lines = [[null, Loc.t("NONE IN THIS SYSTEM")]]
	while _rows.size() < lines.size():
		var l := _label(15, _tint())
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		l.clip_text = true
		_rows.append(l)
	for k in _rows.size():
		_rows[k].visible = k < lines.size()
		if k < lines.size():
			_rows[k].text = String(lines[k][1])
			if lines[k][0] != null:
				_row_ids.append(lines[k][0])


## As big as the window allows, the screen's own shape, centred a little above the middle (and
## a little left of it when a list stands beside it).
func _layout() -> void:
	var vs := get_viewport().get_visible_rect().size
	var res := term.pixels()
	var side := LIST_W + 40.0 if _list_title.visible else 0.0
	var k := minf((vs.x * 0.86 - side) / res.x, vs.y * 0.76 / res.y)
	if k > 1.0:
		k = floorf(k * 2.0) / 2.0
	var sz := res * k
	var pos := Vector2((vs.x - sz.x - side) * 0.5, (vs.y - sz.y) * 0.5 - 6.0)
	var lx := pos.x + sz.x + 40.0
	_list_title.position = Vector2(lx, pos.y - 6.0)
	_list_title.size = Vector2(LIST_W, 26.0)
	for i in _rows.size():
		_rows[i].position = Vector2(lx, pos.y + 30.0 + i * ROW_H)
		_rows[i].size = Vector2(LIST_W, ROW_H)
	_rect.position = pos
	_rect.size = sz
	_bezel.position = pos - Vector2(14, 14)
	_bezel.size = sz + Vector2(28, 28)
	_title.position = Vector2(0, pos.y - 50.0)
	_title.size = Vector2(vs.x, 30.0)
	_hint.position = Vector2(0, pos.y + sz.y + 24.0)
	_hint.size = Vector2(vs.x, 24.0)


## Screen pixel under a point of the window (the tube's bulge undone), or (-1, -1) off it.
func pixel_at(p: Vector2) -> Vector2:
	var uv := (p - _rect.position) / _rect.size
	var c := uv * 2.0 - Vector2.ONE
	# Seen up close the tube curves less (the edges' text stays whole): as in the shader.
	c *= 1.0 + 0.015 * c.dot(c)
	uv = c * 0.5 + Vector2(0.5, 0.5)
	if uv.x < 0.0 or uv.y < 0.0 or uv.x > 1.0 or uv.y > 1.0:
		return Vector2(-1, -1)
	return uv * term.pixels()


## The list line under a point of the window, or -1.
func _row_at(p: Vector2) -> int:
	if not term or not term.pick_fn.is_valid():
		return -1
	for k in mini(_rows.size(), _row_ids.size()):
		if _rows[k].visible and _rows[k].get_global_rect().has_point(p):
			return k
	return -1


func _input(event: InputEvent) -> void:
	if term == null:
		return
	if event.is_action_pressed("use_item") or event.is_action_pressed("pause") or (event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE):
		get_viewport().set_input_as_handled()
		close()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			if term.wheel_fn.is_valid():
				term.wheel_fn.call(1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			# A line of the list beside the screen: picked.
			var row := _row_at(mb.position)
			if mb.pressed and row >= 0:
				term.pick_fn.call(_row_ids[row])
				Sfx.play("click", -12.0, 1.4, "Station")
				_fill_list()
			elif mb.pressed:
				_press = true
				_moved = 0.0
			elif _press:
				_press = false
				var px := pixel_at(mb.position)
				# Hardly moved: a touch.
				if _moved < 6.0 and px.x >= 0.0 and term.click_fn.is_valid():
					term.click_fn.call(px)
					Sfx.play("click", -12.0, 1.4, "Station")
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		if _press:
			_moved += (event as InputEventMouseMotion).relative.length()
			if term.drag_fn.is_valid():
				term.drag_fn.call((event as InputEventMouseMotion).relative)
		get_viewport().set_input_as_handled()
