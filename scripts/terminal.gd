class_name Terminal
extends Node3D
## A CRT screen set into a panel. Its content is drawn small (a few hundred pixels across,
## in a hard-edged monospace font) into its own viewport, then shown on the glass through a
## tube shader: barrel curve, scanlines, a phosphor glow that bleeds round bright text, a
## faint base glow and a flicker. Set `text` like a label's; `draw_fn` adds pictures (an orbit,
## a bar) drawn on top in screen pixels.

const PX_PER_M := 320.0

const SHADER := """
shader_type spatial;
render_mode unshaded, shadows_disabled, cull_back;
uniform sampler2D screen : source_color, filter_nearest;
uniform vec3 tint : source_color = vec3(0.45, 1.0, 0.7);
uniform vec2 res = vec2(240.0, 160.0);
uniform float power = 1.0;
uniform float seed = 0.0;

float lum(vec2 uv) {
	return texture(screen, uv).r;
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	c *= 1.0 + 0.045 * dot(c, c);
	vec2 uv = c * 0.5 + 0.5;
	float inside = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
	float t = lum(uv);
	// Phosphor bleed: a soft halo round lit pixels.
	float b = 0.0;
	vec2 px = 1.0 / res;
	for (int i = -2; i <= 2; i++) {
		for (int j = -2; j <= 2; j++) {
			b += lum(uv + vec2(float(i), float(j)) * px * 1.3);
		}
	}
	b /= 25.0;
	float scan = 0.7 + 0.3 * pow(abs(sin(uv.y * res.y * 3.14159)), 0.6);
	float mask = 0.88 + 0.12 * step(0.5, fract(uv.x * res.x * 1.5));
	vec3 col = tint * (t * 1.35 + b * 0.9) * scan * mask;
	col += tint * 0.035;
	float vig = smoothstep(1.35, 0.55, length(c));
	float flick = 0.97 + 0.03 * sin(TIME * 59.0 + seed * 7.0);
	ALBEDO = col * vig * inside * flick * power * 1.6;
}
"""

static var _shader: Shader
static var _font: SystemFont

var size := Vector2(0.5, 0.3)
## Screen pixels per metre of glass: more for small text, so the phosphor bleed stays fine.
var px_per_m := PX_PER_M
var font_px := 12
var text := "":
	set(v):
		if v == _src:
			return
		_src = v
		text = Loc.lines(v)
		_dirty = true
## The text as the game wrote it (English); `text` is what is shown.
var _src := ""


## Show the same text again in the language now chosen.
func retranslate() -> void:
	var s := _src
	_src = ""
	if s != "":
		text = s


var modulate := Color(0.45, 1.0, 0.7):
	set(v):
		modulate = v
		if _mat:
			_mat.set_shader_parameter("tint", Color(v.r, v.g, v.b))
## Screen on or dark (no power).
var powered := true:
	set(v):
		if v == powered:
			return
		powered = v
		if _mat:
			_mat.set_shader_parameter("power", 1.0 if v else 0.0)
		if _glow:
			_glow.visible = v
## Called with (canvas: Control, pixels: Vector2) after the text, to draw pictures.
var draw_fn: Callable
## The glass is something to take hold of (LMB pulls you in); E opens it full size
## (ScreenView). A screen you can work sets these, in screen pixels: a click, a drag, the wheel.
var it: Interactable
var click_fn: Callable
var drag_fn: Callable
var wheel_fn: Callable
## Optional, for ScreenView: a list beside the screen ([[id, text], ...], polled), its title,
## and what picking a line does (called with its id).
var list_fn: Callable
var list_title := ""
var pick_fn: Callable

var _vp: SubViewport
var _label: Label
var _canvas: Control
var _mat: ShaderMaterial
var _dirty := true
var _glow: OmniLight3D


static func make(parent: Node, xform: Transform3D, p_size: Vector2, p_font_px: int, p_px_per_m := PX_PER_M) -> Terminal:
	var t := Terminal.new()
	t.px_per_m = p_px_per_m
	t.size = p_size
	t.font_px = p_font_px
	t.transform = xform
	parent.add_child(t)
	return t


func _ready() -> void:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	if _font == null:
		_font = SystemFont.new()
		_font.font_names = PackedStringArray(["Consolas", "Lucida Console", "Courier New", "monospace"])
		_font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		_font.hinting = TextServer.HINTING_NORMAL
		_font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	var res := Vector2i(maxi(int(size.x * px_per_m), 32), maxi(int(size.y * px_per_m), 24))
	_vp = SubViewport.new()
	_vp.size = res
	_vp.disable_3d = true
	_vp.transparent_bg = false
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(_vp)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.size = Vector2(res)
	_vp.add_child(bg)
	_label = Label.new()
	# Clear of the tube's curved, darkened edge (it pushes the corners out of sight).
	_label.position = Vector2(14, 9)
	_label.add_theme_font_override("font", _font)
	_label.add_theme_font_size_override("font_size", font_px)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_constant_override("line_spacing", -1)
	_vp.add_child(_label)
	_canvas = Control.new()
	_canvas.size = Vector2(res)
	_canvas.draw.connect(func() -> void:
		if draw_fn.is_valid():
			draw_fn.call(_canvas, Vector2(res)))
	_vp.add_child(_canvas)
	var quad := QuadMesh.new()
	quad.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mat = ShaderMaterial.new()
	_mat.shader = _shader
	_mat.set_shader_parameter("screen", _vp.get_texture())
	_mat.set_shader_parameter("res", Vector2(res))
	_mat.set_shader_parameter("tint", Color(modulate.r, modulate.g, modulate.b))
	_mat.set_shader_parameter("seed", randf() * 10.0)
	_mat.set_shader_parameter("power", 1.0 if powered else 0.0)
	mi.material_override = _mat
	add_child(mi)
	var shape := BoxShape3D.new()
	shape.size = Vector3(size.x, size.y, 0.02)
	var title := (get_parent() as ControlPanel).title if get_parent() is ControlPanel else "Screen"
	it = Interactable.make(self, title, "", shape, Vector3(0, 0, 0.005))
	it.grip = true
	it.on_open = func() -> void:
		if ScreenView.instance:
			ScreenView.instance.open(self)
	# The tube's glow spills onto the panel round it.
	_glow = OmniLight3D.new()
	_glow.light_cull_mask = Station.INSIDE_LAYER
	_glow.light_color = Color(modulate.r, modulate.g, modulate.b)
	_glow.light_energy = 0.05
	_glow.omni_range = maxf(size.x, size.y) * 1.1
	_glow.omni_attenuation = 2.6
	_glow.shadow_enabled = false
	_glow.position = Vector3(0, 0, 0.12)
	_glow.visible = powered
	add_child(_glow)


## The picture on the glass (what ScreenView shows full size), and its size in pixels.
func texture() -> Texture2D:
	return _vp.get_texture() if _vp else null


func pixels() -> Vector2:
	return Vector2(_vp.size) if _vp else Vector2.ONE


## Redraw the pictures (for screens whose `draw_fn` shows something that moves).
func refresh() -> void:
	_dirty = true


func _process(_delta: float) -> void:
	if _dirty and _vp:
		_dirty = false
		_label.text = text
		_canvas.queue_redraw()
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
