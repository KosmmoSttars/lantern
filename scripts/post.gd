class_name Post
extends CanvasLayer
## Full-screen lens over the view: vignette, film grain, a touch of chromatic
## fringing and anamorphic streaks from the brightest light always; the helmet visor's dark rim when it is sealed; tunnel vision
## and grey-out with hypoxia; a slow throb with high CO2; frost when cold; and
## digital tearing for when the world stops making sense.

const SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
// The same picture without filtering: each big pixel takes exactly one rendered pixel.
uniform sampler2D screen_near : hint_screen_texture, filter_nearest;
uniform float hypoxia = 0.0;
uniform float co2 = 0.0;
uniform float helmet = 0.0;
uniform float glitch = 0.0;
uniform float cold = 0.0;
uniform float aspect = 1.7778;
uniform float flare = 1.0;
// Retro look: the view in big square pixels (this many screen pixels each), with ordered
// dithering into a limited number of shades. 0 = off.
uniform float pixel = 0.0;
// Shades per channel above black, and the dither: 4 = a 4x4 Bayer at partial strength over
// many shades, 2 = a full checkerboard between few (the hard, dotted look).
uniform float levels = 18.0;
uniform float dither = 4.0;
// Expedition: tiredness closes the eyes now and then; radiation sickness sways and sours the view.
uniform float tired = 0.0;
uniform float sick = 0.0;
uniform vec2 vp = vec2(1600.0, 900.0);
// Settings: picture brightness, and film grain (0 = clean).
uniform float brightness = 1.0;
uniform float grain = 1.0;

float h21(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 cellpos = floor(SCREEN_UV * vp / max(pixel, 1.0));
	if (pixel > 1.0) {
		vec2 grid = vp / pixel;
		uv = (cellpos + 0.5) / grid;
	}
	if (glitch > 0.0) {
		float row = floor(uv.y * 48.0);
		float n = h21(vec2(row, floor(TIME * 24.0)));
		if (n < glitch * 0.45) {
			uv.x += (h21(vec2(row, 3.0)) - 0.5) * 0.12 * glitch;
		}
	}
	if (sick > 0.0) {
		uv += vec2(sin(TIME * 0.7 + uv.y * 3.0), cos(TIME * 0.53 + uv.x * 2.0)) * 0.006 * sick;
	}
	vec2 dir = uv - 0.5;
	float throb = 0.5 + 0.5 * sin(TIME * 1.9);
	float ca = 0.0004 + glitch * 0.012 + co2 * 0.004 * throb;
	vec3 col;
	if (pixel > 1.0) {
		// Each big pixel is the average of the rendered pixels under it (not just one of
		// them): edges stay hard, but thin strokes, like distant lettering, still show.
		int np = int(pixel);
		vec3 acc = vec3(0.0);
		float cnt = 0.0;
		for (int j = 0; j < 4; j++) {
			for (int i = 0; i < 4; i++) {
				if (i < np && j < np) {
					acc += textureLod(screen_near, (cellpos * pixel + vec2(float(i), float(j)) + 0.5) / vp, 0.0).rgb;
					cnt += 1.0;
				}
			}
		}
		col = acc / max(cnt, 1.0);
	} else {
		col.r = textureLod(screen_tex, uv + dir * ca, 0.0).r;
		col.g = textureLod(screen_tex, uv, 0.0).g;
		col.b = textureLod(screen_tex, uv - dir * ca, 0.0).b;
	}
	if (pixel <= 1.0) {
		// Unsharp mask: undo the softness that anti-aliasing and the lighting passes leave.
		vec2 px = 1.0 / vp;
		vec3 nb = textureLod(screen_tex, uv + vec2(px.x, 0.0), 0.0).rgb + textureLod(screen_tex, uv - vec2(px.x, 0.0), 0.0).rgb
			+ textureLod(screen_tex, uv + vec2(0.0, px.y), 0.0).rgb + textureLod(screen_tex, uv - vec2(0.0, px.y), 0.0).rgb;
		col += (col - nb * 0.25) * 0.45;
	}
	if (co2 > 0.0) {
		col = mix(col, textureLod(screen_tex, uv, 2.5).rgb, co2 * 0.55 * throb);
	}
	float r = length(dir * vec2(aspect, 1.0)) / aspect * 1.6;
	col *= mix(1.0, smoothstep(1.05, 0.25, r), 0.55 + helmet * 0.2);
	// (Kept apart: with the edges equal at full hypoxia, smoothstep is undefined and a black
	// disc showed in the middle of the view.)
	float t_in = 0.3 - hypoxia * 0.25;
	float tunnel = smoothstep(max(0.85 - hypoxia * 0.8, t_in + 0.04), t_in, r);
	col *= mix(1.0, tunnel, clamp(hypoxia * 1.3, 0.0, 1.0));
	float grey = dot(col, vec3(0.3, 0.59, 0.11));
	col = mix(col, vec3(grey), hypoxia * 0.75);
	col = mix(col, vec3(0.78, 0.86, 0.95) * (grey + 0.25), cold * smoothstep(0.35, 1.0, r) * 0.65);
	if (helmet > 0.0) {
		float rim = smoothstep(0.62, 0.98, r);
		col = mix(col, col * 0.18, rim * helmet);
		// A broad, faint sheen on the visor glass.
		float sheen = smoothstep(0.22, 0.0, abs(uv.x * 0.8 + uv.y * 0.45 - 0.3)) * smoothstep(0.9, 0.0, uv.y);
		col += vec3(0.02, 0.025, 0.03) * helmet * sheen;
	}
	if (flare > 0.0) {
		// Anamorphic streak: the brightest light smeared sideways through a wide lens, blue.
		vec3 streak = vec3(0.0);
		for (int i = -12; i <= 12; i++) {
			float x = float(i) / 12.0;
			vec3 s = textureLod(screen_tex, vec2(uv.x + x * 0.55, uv.y), 2.0).rgb;
			float l = max(max(s.r, s.g), s.b);
			streak += s * smoothstep(0.8, 1.0, l) * pow(1.0 - abs(x), 2.2);
		}
		col += streak / 12.0 * vec3(0.3, 0.45, 1.0) * 2.0 * flare;
	}
	if (tired > 0.0) {
		col *= mix(1.0, smoothstep(0.95, 0.2, r), tired * 0.6);
		// A slow blink every few seconds, longer the more tired.
		float ph = fract(TIME / 5.5);
		float lid = smoothstep(0.0, 0.08 + tired * 0.25, ph) * smoothstep(0.35 * tired + 0.12, 0.08 + tired * 0.25, ph);
		float edge = abs(SCREEN_UV.y - 0.5) * 2.0;
		col *= 1.0 - step(1.0 - lid * tired, edge);
	}
	if (sick > 0.0) {
		float gg = dot(col, vec3(0.3, 0.59, 0.11));
		col = mix(col, vec3(gg * 0.9, gg * 1.05, gg * 0.7), sick * 0.45);
	}
	float g = h21((pixel > 1.0 ? cellpos * 0.013 : uv) * 913.0 + fract(TIME * 7.13));
	col *= brightness;
	col += (g - 0.5) * (0.028 * grain + glitch * 0.1);
	if (pixel > 1.0) {
		float d;
		if (dither < 3.0) {
			// 2x2: a checkerboard between neighbouring shades, at full strength.
			int bx = int(mod(cellpos.x, 2.0));
			int by = int(mod(cellpos.y, 2.0));
			float b2[4] = float[4](0.0, 2.0, 3.0, 1.0);
			d = (b2[by * 2 + bx] + 0.5) / 4.0 - 0.5;
		} else {
			// 4x4 Bayer threshold on the big pixels, at partial strength.
			int bx = int(mod(cellpos.x, 4.0));
			int by = int(mod(cellpos.y, 4.0));
			float bayer[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
			d = ((bayer[by * 4 + bx] + 0.5) / 16.0 - 0.5) * 0.7;
		}
		col = floor(clamp(col, vec3(0.0), vec3(1.0)) * levels + d + 0.5) / levels;
	}
	COLOR = vec4(col, 1.0);
}
"""

var rect: ColorRect
var mat: ShaderMaterial
var glitch := 0.0


func _ready() -> void:
	layer = 1
	rect = ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER
	mat.shader = sh
	rect.material = mat
	add_child(rect)


## Retro look: 0 off, 1 PSX (about 540 big pixels down the screen), 2 chunky (about 360),
## 3 dithered (about 480 across, eight shades a channel, checkerboard dither).
var _retro_lines := 0.0
var _retro_mode := 0


func set_retro(mode: int) -> void:
	_retro_mode = clampi(mode, 0, 3)
	_retro_lines = [0.0, 540.0, 360.0, 0.0][_retro_mode]
	mat.set_shader_parameter("levels", 8.0 if _retro_mode == 3 else 18.0)
	mat.set_shader_parameter("dither", 2.0 if _retro_mode == 3 else 4.0)
	_update_pixel()


func _update_pixel() -> void:
	var size := get_viewport().get_visible_rect().size
	var px := 0.0
	if _retro_mode == 3:
		px = maxf(roundf(size.x / 480.0), 2.0)
	elif _retro_lines > 0.0:
		px = maxf(roundf(size.y / _retro_lines), 2.0)
	mat.set_shader_parameter("pixel", px)


func set_body(tired: float, sick: float) -> void:
	mat.set_shader_parameter("tired", tired)
	mat.set_shader_parameter("sick", sick)


func set_look(p_brightness: float, p_grain: bool) -> void:
	mat.set_shader_parameter("brightness", p_brightness)
	mat.set_shader_parameter("grain", 1.0 if p_grain else 0.0)


func set_flare(on: bool) -> void:
	mat.set_shader_parameter("flare", 0.3 if on else 0.0)


func set_state(hypoxia: float, co2: float, helmet: float, cold: float) -> void:
	mat.set_shader_parameter("hypoxia", hypoxia)
	mat.set_shader_parameter("co2", co2)
	mat.set_shader_parameter("helmet", helmet)
	mat.set_shader_parameter("cold", cold)
	mat.set_shader_parameter("glitch", glitch)
	var vp := get_viewport().get_visible_rect().size
	mat.set_shader_parameter("aspect", vp.x / maxf(vp.y, 1.0))
	mat.set_shader_parameter("vp", vp)
	_update_pixel()
