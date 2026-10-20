class_name Looks
extends RefCounted
## Shared materials and shaders. All surface detail is procedural (world-space
## noise), so the project ships no textures.

const NOISE_LIB := """
float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}
float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash13(i), hash13(i + vec3(1,0,0)), f.x),
				   mix(hash13(i + vec3(0,1,0)), hash13(i + vec3(1,1,0)), f.x), f.y),
			   mix(mix(hash13(i + vec3(0,0,1)), hash13(i + vec3(1,0,1)), f.x),
				   mix(hash13(i + vec3(0,1,1)), hash13(i + vec3(1,1,1)), f.x), f.y), f.z);
}
float fbm(vec3 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 5; i++) {
		s += a * vnoise(p);
		p = p * 2.03 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return s;
}
vec3 hash33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}
// Impact craters: about half the cells of a unit grid hold one. Returns the height change
// (bowls negative, rims positive, in cell units) and, in rim_out, how much this point sits on
// fresh ejecta (bright).
float craters(vec3 p, out float rim_out) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	float h = 0.0;
	rim_out = 0.0;
	for (int x = -1; x <= 1; x++)
	for (int y = -1; y <= 1; y++)
	for (int z = -1; z <= 1; z++) {
		vec3 o = vec3(float(x), float(y), float(z));
		vec3 r = hash33(i + o);
		if (r.x > 0.5) continue;
		vec3 c = o + r - f;
		float rad = 0.18 + 0.32 * r.y;
		float d = length(c) / rad;
		if (d > 2.2) continue;
		float bowl = d < 1.0 ? (d * d - 1.0) * 0.55 : 0.0;
		float rim = exp(-pow((d - 1.0) * 3.5, 2.0)) * 0.25;
		h += (bowl + rim) * rad;
		rim_out = max(rim_out, (1.0 - smoothstep(1.0, 2.2, d)) * step(0.9, d) * r.z);
	}
	return h;
}
"""

## Painted interior panels. Everything is procedural in world space: the panel
## grid with recessed seams and rivets (bump-mapped from screen derivatives),
## grime gathering in blotches and along seams, scuffs and fine paint texture.
const BUMP := """
// Perturb the view-space normal by a height field h (meters) - Mikkelsen's
// derivative bump mapping, no tangents needed.
vec3 bump_normal(vec3 n, vec3 p, float h, float strength) {
	vec3 dpdx = dFdx(p);
	vec3 dpdy = dFdy(p);
	vec3 r1 = cross(dpdy, n);
	vec3 r2 = cross(n, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dFdx(h) * r1 + dFdy(h) * r2);
	return normalize(abs(det) * n - grad * strength);
}
"""

const PANEL := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform vec4 color : source_color = vec4(0.8, 0.8, 0.77, 1.0);
uniform float roughness = 0.6;
uniform float metallic = 0.0;
uniform float grime = 1.0;
uniform float seams = 1.0;
uniform vec2 cell = vec2(0.62, 0.48);
varying vec3 wpos;
varying vec3 wnrm;
%s
%s
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	vec3 an = abs(wnrm);
	vec2 q = an.x > an.y && an.x > an.z ? wpos.zy : (an.y > an.z ? wpos.xz : wpos.xy);
	vec2 f = fract(q / cell);
	vec2 d = min(f, 1.0 - f) * cell;
	// Each panel its own: a slightly different shade and warmth, as if replaced over the years.
	vec2 ci = floor(q / cell);
	float pick = hash13(vec3(ci, floor(wpos.x * 0.37) + 3.7));
	float pick2 = hash13(vec3(ci.yx, 11.3));
	float e = min(d.x, d.y);
	float dist = length(VERTEX);
	float lod = 1.0 - smoothstep(4.0, 12.0, dist);
	float groove = (1.0 - smoothstep(0.0012, 0.0035, e)) * seams;
	vec2 rq = fract(q / 0.11) - 0.5;
	float r1 = length(vec2(d.x - 0.02, rq.y * 0.11));
	float r2 = length(vec2(d.y - 0.02, rq.x * 0.11));
	float rivet = (1.0 - smoothstep(0.0035, 0.0055, min(r1, r2))) * seams;
	float blotch = fbm(wpos * 2.6);
	float fine = vnoise(wpos * 38.0);
	float scratch = smoothstep(0.82, 0.95, vnoise(vec3(q.x * 40.0, q.y * 2.0, wpos.x + wpos.z))) * 0.5;
	float near_seam = (1.0 - smoothstep(0.0, 0.05, e)) * seams;
	float g = smoothstep(0.5, 0.8, blotch) * 0.18 + fine * 0.05 + near_seam * 0.22;
	vec3 c = color.rgb * mix(0.9, 1.07, pick) * mix(vec3(1.0), vec3(1.03, 1.0, 0.94), pick2 * 0.6);
	c *= 1.0 - g * grime;
	c = mix(c, c * vec3(0.92, 0.86, 0.74), smoothstep(0.55, 0.75, blotch) * 0.5 * grime);
	c *= 1.0 - groove * 0.55;
	c = mix(c, color.rgb * 1.15, scratch * grime * 0.4);
	// Paint chipped off along the panel edges where boots and tools knock it: bare steel.
	float chip = step(0.74, vnoise(wpos * 26.0)) * (1.0 - smoothstep(0.004, 0.028, e)) * seams * grime;
	c = mix(c, vec3(0.6, 0.61, 0.62), chip * 0.85);
	// Hands polish the paint in the middle of the panels: a faint sheen there.
	float worn = smoothstep(0.35, 0.0, length(f - 0.5)) * smoothstep(0.55, 0.8, vnoise(wpos * 3.1 + 5.0)) * grime;
	// Stencilled markings on one panel in six: a code block in a corner and a short rule.
	float stencil = 0.0;
	if (pick > 0.83 && seams > 0.5) {
		vec2 sf = f;
		float blockx = step(0.07, sf.x) * step(sf.x, 0.27);
		float blocky = step(0.8, sf.y) * step(sf.y, 0.87);
		float dashes = step(0.5, fract(sf.x * 22.0));
		stencil = blockx * blocky * dashes;
		stencil += step(0.07, sf.x) * step(sf.x, 0.42) * step(0.76, sf.y) * step(sf.y, 0.77);
	}
	c = mix(c, c * 0.32, clamp(stencil, 0.0, 1.0) * 0.8);
	// Rivet heads take the panel's own paint, a shade darker: bare steel dots read as stars on dark panels.
	c = mix(c, color.rgb * 0.8 + 0.04, rivet * 0.6);
	ALBEDO = c;
	ROUGHNESS = clamp(roughness + (fine - 0.5) * 0.08 + g * 0.3 - scratch * 0.25 - rivet * 0.15 - worn * 0.2 - chip * 0.2, 0.05, 1.0);
	METALLIC = mix(mix(metallic, 0.5, rivet), 0.7, chip);
	// Only seams and rivets go into the bump: fine noise through screen derivatives turns into
	// blocky sparkle.
	float h = (rivet * 0.0012 - groove * 0.0018) * lod;
	NORMAL = bump_normal(NORMAL, VERTEX, h, 1.0);
}
"""

## Multi-layer insulation blankets on the hull: quilted pillows sewn into a grid,
## crinkled foil showing at the seams, a satin sheen.
const MLI := """
shader_type spatial;
render_mode specular_schlick_ggx;
uniform vec4 color : source_color = vec4(0.86, 0.85, 0.8, 1.0);
varying vec3 lpos;
%s
%s
void vertex() {
	lpos = VERTEX;
}
void fragment() {
	vec2 q = UV * vec2(1.6, 1.6);
	vec2 cellp = fract(q) - 0.5;
	float edge = max(abs(cellp.x), abs(cellp.y));
	float seam = smoothstep(0.46, 0.5, edge);
	float pillow = cos(cellp.x * 3.1) * cos(cellp.y * 3.1);
	float crinkle = fbm(lpos * 7.0);
	float stitch = seam * step(0.5, fract((cellp.x + cellp.y) * 30.0));
	vec3 c = color.rgb * (0.84 + 0.22 * crinkle) * (0.9 + 0.1 * pillow);
	c = mix(c, vec3(0.55, 0.5, 0.42), seam * 0.6);
	ALBEDO = c * (1.0 - stitch * 0.3);
	ROUGHNESS = 0.32 + 0.38 * crinkle + seam * 0.3;
	METALLIC = 0.2 + seam * 0.5;
	float h = pillow * 0.012 - seam * 0.01 + (vnoise(lpos * 26.0) - 0.5) * 0.002;
	NORMAL = bump_normal(NORMAL, VERTEX, h, 1.0);
}
"""

## Solar wing: a grid of dark cells with copper bus lines. `damage` blackens and
## cracks the panel around `damage_center` (wing-local).
const SOLAR := """
shader_type spatial;
uniform vec4 cell_color : source_color = vec4(0.035, 0.05, 0.13, 1.0);
uniform vec4 line_color : source_color = vec4(0.7, 0.72, 0.76, 1.0);
uniform float damage = 0.0;
uniform vec3 damage_center = vec3(0.0);
varying vec3 lpos;
%s
void vertex() {
	lpos = VERTEX;
}
void fragment() {
	// Cells half a metre square however big the blanket is.
	vec2 q = lpos.xz / 0.5;
	vec2 c = abs(fract(q) - 0.5);
	float line = smoothstep(0.43, 0.47, max(c.x, c.y));
	float n = vnoise(vec3(floor(q), 0.0) * 1.7);
	vec3 col = mix(cell_color.rgb * (0.8 + 0.4 * n), line_color.rgb, line);
	float d = length(lpos - damage_center);
	float burn = damage * (1.0 - smoothstep(0.4, 2.2, d + (fbm(lpos * 3.0) - 0.5) * 1.5));
	col = mix(col, vec3(0.02), burn);
	ALBEDO = col;
	METALLIC = mix(0.35, 0.8, line);
	ROUGHNESS = mix(0.12, 0.35, line) + burn * 0.5;
	SPECULAR = 0.9;
	// Anti-reflective coating: a faint violet sheen at grazing angles.
	float graze = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO += vec3(0.08, 0.04, 0.14) * graze * (1.0 - line) * (1.0 - burn);
}
"""

## Asteroids: broken stone under a coat of dust, cratered at two scales; crater floors
## darker, fresh ejecta and broken edges brighter.
const ROCK := """
shader_type spatial;
uniform vec4 color : source_color = vec4(0.36, 0.35, 0.34, 1.0);
varying vec3 lpos;
varying vec3 tint;
%s
%s
void vertex() {
	lpos = VERTEX;
	tint = COLOR.rgb;
}
void fragment() {
	vec3 p = lpos;
	float n = fbm(p * 1.6);
	float fine = fbm(p * 9.0 + vec3(4.0));
	float grit = vnoise(p * 40.0);
	float ej1;
	float ej2;
	float c1 = craters(p * 1.3, ej1);
	float c2 = craters(p * 4.2 + vec3(7.0), ej2);
	float h = n * 0.1 + fine * 0.03 + grit * 0.004 + c1 * 0.22 + c2 * 0.05;
	float shade = 0.55 + 0.6 * n;
	shade *= 1.0 + clamp(c1, -0.3, 0.0) * 0.8;      // dusty, darker crater floors
	shade *= 1.0 + (ej1 + ej2 * 0.6) * 0.35;         // bright fresh ejecta
	shade *= 0.9 + 0.2 * grit;
	vec3 col = color.rgb * tint * shade;
	// Iron staining in streaks.
	col = mix(col, col * vec3(1.25, 0.9, 0.7), smoothstep(0.55, 0.75, fbm(p * 2.7 + vec3(11.0))) * 0.6);
	ALBEDO = col;
	ROUGHNESS = 0.92;
	SPECULAR = 0.35;
	NORMAL = bump_normal(NORMAL, VERTEX, h * 0.35, 1.0);
}
"""

## The rust world: banded deserts, dark seas of old lava and a thin dusty rim.
const PLANET := """
shader_type spatial;
render_mode diffuse_lambert, ambient_light_disabled;
uniform vec3 light_dir = vec3(1.0, 0.0, 0.0);
varying vec3 lpos;
%s
%s
void vertex() {
	lpos = normalize(VERTEX);
}
void fragment() {
	vec3 p = lpos;
	float n = fbm(p * 3.0);
	float m = fbm(p * 6.0 + vec3(3.0));
	float e1;
	float e2;
	float e3;
	float c1 = craters(p * 5.0, e1);
	float c2 = craters(p * 17.0 + vec3(5.0), e2);
	float c3 = craters(p * 55.0 + vec3(9.0), e3);
	vec3 rust = mix(vec3(0.3, 0.12, 0.05), vec3(0.72, 0.4, 0.2), n);
	float mare = smoothstep(0.52, 0.6, m);
	rust = mix(rust, vec3(0.14, 0.09, 0.07), mare);                  // old lava plains
	rust *= 1.0 + clamp(c1 * 2.0 + c2 + c3 * 0.5, -0.45, 0.25);       // crater floors and walls
	rust = mix(rust, vec3(0.9, 0.72, 0.52), clamp(e1 * 0.3 + e2 * 0.2 + e3 * 0.1, 0.0, 0.35)); // ejecta
	ALBEDO = rust;
	ROUGHNESS = 0.95;
	float h = c1 * 0.02 + c2 * 0.006 + c3 * 0.002 + n * 0.01;
	NORMAL = bump_normal(NORMAL, VERTEX, h * 1500.0 * 0.25, 1.0);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	EMISSION = vec3(0.9, 0.5, 0.25) * rim * 0.08;
}
"""

static var _cache: Dictionary = {}


static func _shader(key: String, code: String) -> Shader:
	if not _cache.has(key):
		var sh := Shader.new()
		var parts := code.count("%s")
		sh.code = code % ([NOISE_LIB, BUMP] if parts == 2 else [NOISE_LIB]) if parts > 0 else code
		_cache[key] = sh
	return _cache[key]


static func panel(color: Color, roughness := 0.6, metallic := 0.0, grime := 1.0, seams := 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader("panel", PANEL)
	m.set_shader_parameter("color", color)
	m.set_shader_parameter("roughness", roughness)
	m.set_shader_parameter("metallic", metallic)
	m.set_shader_parameter("grime", grime)
	m.set_shader_parameter("seams", seams)
	return m


static func mli(color := Color(0.86, 0.85, 0.8)) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader("mli", MLI)
	m.set_shader_parameter("color", color)
	return m


static func solar() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader("solar", SOLAR)
	return m


static func rock(color := Color(0.32, 0.29, 0.27)) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader("rock", ROCK)
	m.set_shader_parameter("color", color)
	return m


static func planet() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader("planet", PLANET)
	return m


static func glow(color: Color, energy := 2.0) -> StandardMaterial3D:
	return Kit.glow(color, energy)


static func glass(tint := Color(0.6, 0.7, 0.8, 0.12)) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = tint
	m.roughness = 0.08
	m.metallic_specular = 0.3
	# No lamp highlights: on a window they sit as white discs right over the view.
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## Frost on the sealed cryo pods' windows, lit faintly from inside.
static func frost() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.5, 0.58, 0.66, 0.72)
	m.roughness = 0.85
	m.metallic_specular = 0.8
	m.emission_enabled = true
	m.emission = Color(0.2, 0.35, 0.55)
	m.emission_energy_multiplier = 0.18
	return m
