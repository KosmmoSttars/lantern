class_name Space
extends Node3D
## Everything beyond the hull, drawn round the station from the flight state: the starfield
## and the Sun in the sky shader, sunlight as a directional light, and every body of the
## system as a scaled stand-in. A body really d metres away is drawn at a distance
## squeezed into the camera's range (monotonic in d, so nearer stays nearer) and scaled
## by the same factor, so its size in the sky is exact.
##
## Bodies are built in the system frame (their mesh basis is the inverse of the station's
## attitude), so latitude bands and the ring plane stay put while the station turns.

const NEAR_DRAW := 2500.0
const FAR_DRAW := 12000.0
## Stand-ins never shrink below this angular radius (a dot you can still find).
const MIN_ANGLE := 0.0011

const SKY := """
shader_type sky;
render_mode use_debanding;
uniform mat3 to_system;
uniform vec3 sun_dir = vec3(0.0, 0.0, -1.0);
uniform float sun_on = 1.0;
uniform vec3 tint = vec3(0.16, 0.15, 0.19);
uniform float exposure = 1.0;
uniform float seed = 0.0;
// A black hole: its direction (station frame), distance in Schwarzschild radii, the disk.
uniform float bh_on = 0.0;
uniform vec3 bh_dir = vec3(0.0, 0.0, -1.0);
uniform vec3 disk_n = vec3(0.0, 1.0, 0.0);
uniform float bh_dist = 26.0;
uniform float disk_in = 3.0;
uniform float disk_out = 12.0;

float h13(vec3 p) {
	p = fract(p * 0.1031 + seed * 0.013);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float vn(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h13(i), h13(i + vec3(1, 0, 0)), f.x), mix(h13(i + vec3(0, 1, 0)), h13(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(h13(i + vec3(0, 0, 1)), h13(i + vec3(1, 0, 1)), f.x), mix(h13(i + vec3(0, 1, 1)), h13(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 5; i++) {
		s += vn(p) * a;
		p *= 2.03;
		a *= 0.5;
	}
	return s;
}

// The star field, looked up in the system frame so it stays put while the station turns.
vec3 stars(vec3 ds) {
	vec3 d = normalize(to_system * ds);
	vec3 col = vec3(0.0);
	for (int k = 0; k < 3; k++) {
		float sc = 110.0 * pow(2.2, float(k));
		vec3 p = d * sc;
		vec3 cell = floor(p);
		float h = h13(cell + float(k) * 17.0);
		if (h > 0.88) {
			vec3 jit = vec3(h13(cell + 1.3), h13(cell + 2.7), h13(cell + 5.1)) - 0.5;
			float dist = length(p - (cell + 0.5 + jit * 0.6));
			float b = pow(max(0.0, 1.0 - dist * 2.6), 8.0) * (h - 0.88) * 8.0;
			vec3 st = mix(vec3(1.0, 0.8, 0.62), vec3(0.72, 0.84, 1.0), h13(cell + 9.0));
			col += st * b * 2.6 / (1.0 + float(k) * 0.8);
		}
	}
	vec3 band_n = normalize(vec3(0.25, 0.88, -0.4));
	float band = exp(-pow(dot(d, band_n) * 3.0, 2.0));
	col += tint * band * pow(fbm(d * 4.0), 2.6) * 0.3;
	col += tint * 0.08 * pow(fbm(d * 1.6 + 7.0), 3.0);
	return col;
}

vec3 disk(vec3 hit, vec3 ray, out float a) {
	float r = length(hit);
	vec3 u = normalize(cross(disk_n, abs(disk_n.z) < 0.9 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0)));
	vec3 v = cross(disk_n, u);
	float ang = atan(dot(hit, v), dot(hit, u));
	float spin = ang + TIME * 1.4 / pow(r, 1.5);
	vec3 q = vec3(cos(spin) * r, sin(spin) * r, r * 0.7);
	float swirl = fbm(q * 0.9);
	float t = clamp((r - disk_in) / (disk_out - disk_in), 0.0, 1.0);
	float heat = pow(1.0 - t, 1.5);
	vec3 c = mix(vec3(0.55, 0.12, 0.04), vec3(1.0, 0.5, 0.18), smoothstep(0.0, 0.45, heat));
	c = mix(c, vec3(1.0, 0.93, 0.82), smoothstep(0.55, 0.95, heat));
	vec3 orbit = normalize(cross(disk_n, hit));
	float dop = max(1.0 + 0.7 * dot(orbit, -ray), 0.15);
	float density = smoothstep(0.0, 0.06, t) * (1.0 - smoothstep(0.7, 1.0, t)) * (0.35 + 1.1 * swirl);
	a = clamp(density * 1.3, 0.0, 0.95);
	return c * density * pow(dop, 3.0) * (0.45 + 2.6 * heat);
}

// Weak-field bending for a ray that starts at the camera (not at infinity).
vec3 bent(vec3 d) {
	float c = dot(d, bh_dir);
	float b = bh_dist * sqrt(max(1.0 - c * c, 1e-6));
	float x0 = bh_dist * c;
	float f = x0 * (2.0 * x0 * x0 + 3.0 * b * b) / (2.0 * pow(x0 * x0 + b * b, 1.5));
	float defl = min((1.0 + f) / b, 0.6);
	vec3 side = normalize(d - bh_dir * c);
	return normalize(d * cos(defl) - side * sin(defl));
}

void sky() {
	vec3 d = EYEDIR;
	vec3 col;
	if (bh_on < 0.5) {
		col = stars(d);
	} else {
		float c = dot(d, bh_dir);
		float near_cos = cos(atan(disk_out * 1.6, bh_dist));
		if (AT_CUBEMAP_PASS) {
			col = stars(d) + vec3(1.0, 0.55, 0.25) * pow(max(c, 0.0), 24.0) * 2.0;
		} else if (c < near_cos) {
			col = stars(bent(d));
		} else {
			// Trace the photon backwards through the hole's gravity
			// (x'' = -3/2 h^2 x / r^5, in Schwarzschild radii).
			vec3 pos = -bh_dir * bh_dist;
			vec3 vel = d;
			vec3 hv = cross(pos, vel);
			float h2 = dot(hv, hv);
			vec3 acc_col = vec3(0.0);
			float alpha = 0.0;
			bool captured = false;
			for (int i = 0; i < 260; i++) {
				float r = length(pos);
				float dt = clamp(0.07 * r, 0.015, 1e6);
				vec3 prev = pos;
				vel += -1.5 * h2 * pos / pow(r, 5.0) * dt;
				pos += vel * dt;
				float sa = dot(prev, disk_n);
				float sb = dot(pos, disk_n);
				if (sa * sb < 0.0) {
					vec3 hp = mix(prev, pos, sa / (sa - sb));
					float rr = length(hp);
					if (rr > disk_in && rr < disk_out) {
						float a;
						vec3 dc = disk(hp, normalize(vel), a);
						acc_col += (1.0 - alpha) * dc;
						alpha += (1.0 - alpha) * a;
					}
				}
				float rn = length(pos);
				if (rn < 1.0) { captured = true; break; }
				if (rn > bh_dist * 1.3 && dot(pos, vel) > 0.0) break;
				if (alpha > 0.98) break;
			}
			vec3 bg = captured ? vec3(0.0) : stars(normalize(vel));
			col = acc_col + (1.0 - alpha) * bg;
		}
		// From far off the whole disk is one fierce point of light.
		col += vec3(1.0, 0.72, 0.45) * pow(max(c, 0.0), 30000.0) * 30.0 * smoothstep(60.0, 400.0, bh_dist);
	}
	float sc = dot(d, sun_dir);
	// The Sun seen from Saturn: a small, fierce disc and a soft halo.
	col += vec3(1.0, 0.96, 0.9) * smoothstep(0.99996, 0.99999, sc) * 60.0 * sun_on;
	col += vec3(1.0, 0.85, 0.65) * pow(max(sc, 0.0), 900.0) * 1.2 * sun_on;
	COLOR = col * exposure;
}
"""

const BODY := """
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;
uniform vec3 sun_local = vec3(1.0, 0.0, 0.0);
uniform vec3 base : source_color = vec3(0.7, 0.7, 0.7);
uniform vec3 alt : source_color = vec3(0.5, 0.5, 0.5);
uniform int look = 0;
uniform float seed = 0.0;
uniform vec2 rings = vec2(0.0, 0.0);
uniform float ring_body = 1.0;
uniform float lit = 1.0;
varying vec3 lp;

float h13(vec3 p) {
	p = fract(p * 0.1031 + seed);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}
float vn(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h13(i), h13(i + vec3(1, 0, 0)), f.x), mix(h13(i + vec3(0, 1, 0)), h13(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(h13(i + vec3(0, 0, 1)), h13(i + vec3(1, 0, 1)), f.x), mix(h13(i + vec3(0, 1, 1)), h13(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
float fbm(vec3 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 6; i++) {
		s += vn(p) * a;
		p *= 2.07;
		a *= 0.5;
	}
	return s;
}

void vertex() {
	lp = VERTEX;
}

void fragment() {
	vec3 n = normalize(lp);
	float lam = dot(n, normalize(sun_local));
	vec3 c = base;
	vec3 glow = vec3(0.0);
	if (look == 1) {
		// Saturn: soft latitude bands, a little turbulence, the pale polar hexagon cap.
		float lat = n.y;
		float w = fbm(vec3(n.x * 3.0, lat * 22.0, n.z * 3.0)) * 0.06;
		float bands = sin((lat + w) * 38.0) * 0.5 + 0.5;
		float fine = sin((lat + w * 2.0) * 120.0) * 0.5 + 0.5;
		c = mix(base, alt, bands * 0.55 + fine * 0.12);
		c = mix(c, vec3(0.62, 0.66, 0.6), smoothstep(0.82, 0.96, abs(lat)) * 0.5);
		// Shadow of the rings on the cloud tops.
		vec3 s = normalize(sun_local);
		if (rings.y > 0.0 && abs(s.y) > 1e-3 && lat * s.y < 0.0) {
			float tt = -n.y / s.y;
			vec3 hit = n + s * tt;
			float r = length(hit.xz) * ring_body;
			float dense = smoothstep(rings.x, rings.x + 0.08, r) * (1.0 - smoothstep(rings.y - 0.05, rings.y, r));
			c *= 1.0 - dense * 0.55;
		}
	} else if (look == 2) {
		// Ice moon: cratered grey-white.
		float f = fbm(n * 9.0);
		float cr = smoothstep(0.62, 0.7, fbm(n * 22.0 + 3.0));
		c = base * (0.75 + 0.4 * f) - cr * 0.12;
	} else if (look == 3) {
		// Titan: featureless orange haze, a darker band of dunes barely showing.
		float f = fbm(n * 4.0);
		c = mix(base, alt, smoothstep(-0.3, 0.3, n.y + (f - 0.5) * 0.3));
		float rim = pow(1.0 - abs(dot(n, normalize(-lp))), 3.0);
		c += vec3(0.25, 0.16, 0.05) * rim;
	} else if (look == 4) {
		// Iapetus: one hemisphere coal-dark, the other snow.
		float f = fbm(n * 7.0);
		c = mix(alt, base, smoothstep(-0.25, 0.25, n.x + (f - 0.5) * 0.6));
	} else if (look == 5) {
		// The Gate: a sphere that shows another sky, rimmed with bent light.
		vec3 v = n;
		float sw = fbm(v * 5.0 + TIME * 0.05);
		c = mix(vec3(0.02, 0.03, 0.06), vec3(0.4, 0.5, 1.0), pow(sw, 3.0));
		float star = step(0.985, h13(floor(v * 60.0)));
		c += vec3(star);
	} else if (look == 6 || look == 9) {
		// A star: limb-darkened, granulated, far brighter than anything it lights.
		float mu = abs(dot(n, normalize(CAMERA_POSITION_WORLD - (MODEL_MATRIX * vec4(lp, 1.0)).xyz)));
		float gran = fbm(n * 40.0 + TIME * 0.02);
		c = base * (0.55 + 0.45 * sqrt(mu)) * (0.9 + 0.2 * gran) * (look == 9 ? 8.0 : 4.0);
	} else if (look == 7) {
		// Lava world: black crust, glowing seams.
		float f = fbm(n * 6.0);
		float crack = 1.0 - smoothstep(0.0, 0.035, abs(f - 0.5));
		c = base * (0.6 + 0.6 * fbm(n * 18.0));
		glow = vec3(1.0, 0.32, 0.05) * crack * 2.5;
	} else if (look == 8) {
		// Ocean world: deep water, bright swirls of cloud.
		float cl = smoothstep(0.52, 0.7, fbm(n * 5.0 + vec3(0.0, TIME * 0.003, 0.0)));
		c = mix(base * 0.7, vec3(0.95), cl);
	} else if (look == 10) {
		// Brown dwarf: banded like a giant, glowing a dull red of its own.
		float w = fbm(vec3(n.x * 3.0, n.y * 18.0, n.z * 3.0)) * 0.08;
		float bands = sin((n.y + w) * 30.0) * 0.5 + 0.5;
		c = mix(base, base * 0.5, bands);
		glow = base * (0.25 + 0.2 * bands);
	}
	float shade = clamp(lam * 1.1, 0.0, 1.0);
	// A thin atmosphere softens the terminator.
	shade = smoothstep(-0.08, 0.35, lam) * 0.9 + shade * 0.1;
	bool own_light = look == 5 || look == 6 || look == 9;
	ALBEDO = own_light ? c : c * shade * lit + glow;
}
"""

const RING := """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, blend_mix;
uniform vec3 sun_local = vec3(1.0, 0.0, 0.0);
uniform vec2 radii = vec2(0.53, 1.0);
uniform float planet_r = 0.415;
varying vec3 lp;

float h11(float x) {
	return fract(sin(x * 127.1) * 43758.5453);
}

void vertex() {
	lp = VERTEX;
}

void fragment() {
	float r = length(lp.xz);
	if (r < radii.x || r > radii.y) {
		discard;
	}
	float t = (r - radii.x) / (radii.y - radii.x);
	// Ring density across the span: faint C ring, dense B, the Cassini Division, the A ring
	// with its gap, the thin F ring outside.
	float d = 0.18;
	d = mix(d, 0.95, smoothstep(0.22, 0.27, t));
	d *= 1.0 - smoothstep(0.62, 0.635, t) * (1.0 - smoothstep(0.695, 0.71, t)) * 0.92;
	d = mix(d, 0.6, smoothstep(0.7, 0.72, t));
	d *= 1.0 - smoothstep(0.905, 0.91, t) * (1.0 - smoothstep(0.915, 0.92, t)) * 0.8;
	d *= 1.0 - smoothstep(0.955, 0.965, t);
	d += smoothstep(0.985, 0.99, t) * (1.0 - smoothstep(0.993, 0.998, t)) * 0.5;
	float grain = h11(floor(r * 3000.0)) * 0.3 + h11(floor(r * 700.0)) * 0.3;
	d *= 0.7 + grain;
	vec3 col = mix(vec3(0.58, 0.52, 0.44), vec3(0.86, 0.8, 0.68), smoothstep(0.2, 0.9, t));
	// The planet's shadow falls across the rings.
	vec3 s = normalize(sun_local);
	vec3 p = lp;
	float along = dot(p, s);
	float perp = length(p - s * along);
	float shadow = (along < 0.0 && perp < planet_r) ? 0.08 : 1.0;
	float lit = mix(0.35, 1.0, abs(s.y) * 4.0);
	ALBEDO = col * shadow * clamp(lit, 0.0, 1.0);
	ALPHA = clamp(d, 0.0, 0.97);
}
"""

var flight: Flight
var env: Environment
var sky_mat: ShaderMaterial
var sun: DirectionalLight3D
## Stand-in per body index.
var stand_ins := {}
## Ring per body index (child of its stand-in).
var rings := {}
## Pulsar beams (two cones), when the system has a pulsar.
var beams: Array[MeshInstance3D] = []

var _body_shader: Shader
var _ring_shader: Shader
var _beam_mat: ShaderMaterial
var _system := -1

const LOOKS := {"saturn": 1, "giant": 1, "ice": 2, "snow": 2, "rock": 2, "titan": 3, "iapetus": 4, "gate": 5,
	"star": 6, "lava": 7, "ocean": 8, "pulsar": 9, "brown dwarf": 10, "black hole": 0}

const BEAM := """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, blend_add, depth_draw_never;
uniform vec4 color : source_color = vec4(0.55, 0.7, 1.0, 1.0);
varying vec3 lp;
void vertex() {
	lp = VERTEX;
}
void fragment() {
	// Bright down the middle of the cone, fading along it.
	float along = clamp(lp.y + 0.5, 0.0, 1.0);
	float edge = pow(clamp(dot(NORMAL, VIEW), 0.0, 1.0), 1.5);
	ALBEDO = color.rgb * edge * (1.0 - along * 0.7) * 0.6;
}
"""


func build(f: Flight) -> void:
	flight = f
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SKY
	sky_mat.shader = sh
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.52, 0.58)
	env.ambient_light_energy = 0.04
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.2
	env.ssao_enabled = true
	env.ssao_radius = 0.8
	env.ssao_intensity = 2.4
	env.ssil_radius = 2.0
	env.ssil_intensity = 0.8
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.12
	env.adjustment_saturation = 0.85
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(1.0, 0.97, 0.92)
	sun.light_energy = 2.2
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 80.0
	sun.shadow_bias = 0.03
	add_child(sun)
	_body_shader = Shader.new()
	_body_shader.code = BODY
	_ring_shader = Shader.new()
	_ring_shader.code = RING
	var bs := Shader.new()
	bs.code = BEAM
	_beam_mat = ShaderMaterial.new()
	_beam_mat.shader = bs
	rebuild()


## Build stand-ins for every body of the flight's current system.
func rebuild() -> void:
	for i: int in stand_ins:
		(stand_ins[i] as Node).queue_free()
	stand_ins.clear()
	rings.clear()
	beams.clear()
	var u := flight.u
	_system = u.system_id
	for i in u.bodies.size():
		var b := u.bodies[i]
		# Derelicts and modules are drawn up close by the derelict view, not as far-off spheres.
		if b.kind in ["derelict", "module"]:
			continue
		var look: String = b.get("look", "rock")
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 1.0
		sm.height = 2.0
		var big: bool = b.kind in ["planet", "star"]
		sm.radial_segments = 96 if big else 40
		sm.rings = 48 if big else 20
		mi.mesh = sm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		var m := ShaderMaterial.new()
		m.shader = _body_shader
		m.set_shader_parameter("look", LOOKS.get(look, 2))
		m.set_shader_parameter("seed", float(i) * 0.37 + u.sky_seed)
		var base: Color = b.get("color", Color(0.78, 0.77, 0.75))
		var alt: Color = b.get("alt", base.darkened(0.25))
		match look:
			"saturn":
				base = Color(0.86, 0.76, 0.56)
				alt = Color(0.7, 0.58, 0.4)
			"snow":
				base = Color(0.97, 0.97, 0.98)
			"titan":
				base = Color(0.86, 0.6, 0.28)
				alt = Color(0.72, 0.48, 0.22)
			"iapetus":
				base = Color(0.85, 0.83, 0.8)
				alt = Color(0.12, 0.09, 0.07)
		m.set_shader_parameter("base", base)
		m.set_shader_parameter("alt", alt)
		if b.has("rings"):
			var rr: Array = b.rings
			m.set_shader_parameter("rings", Vector2(float(rr[0]) / float(rr[1]), 1.0))
			m.set_shader_parameter("ring_body", float(b.radius) / float(rr[1]))
		mi.material_override = m
		mi.visible = look != "black hole"
		add_child(mi)
		stand_ins[i] = mi
		if b.has("rings"):
			var ring := MeshInstance3D.new()
			var pm := PlaneMesh.new()
			pm.size = Vector2(2.0, 2.0)
			ring.mesh = pm
			ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var rm := ShaderMaterial.new()
			rm.shader = _ring_shader
			var rr2: Array = b.rings
			rm.set_shader_parameter("radii", Vector2(float(rr2[0]) / float(rr2[1]), 1.0))
			rm.set_shader_parameter("planet_r", float(b.radius) / float(rr2[1]))
			ring.material_override = rm
			ring.scale = Vector3.ONE * float(rr2[1]) / float(b.radius)
			mi.add_child(ring)
			rings[i] = ring
		if look == "pulsar":
			for k in 2:
				var beam := MeshInstance3D.new()
				var cone := CylinderMesh.new()
				cone.top_radius = 0.0
				cone.bottom_radius = 1.0
				cone.height = 1.0
				cone.radial_segments = 24
				cone.cap_bottom = false
				cone.cap_top = false
				beam.mesh = cone
				beam.material_override = _beam_mat
				beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				add_child(beam)
				beams.append(beam)
	sky_mat.set_shader_parameter("seed", u.sky_seed)
	sky_mat.set_shader_parameter("tint", u.sky_tint)
	sky_mat.set_shader_parameter("bh_on", 0.0 if u.black_hole.is_empty() else 1.0)
	if not u.black_hole.is_empty():
		sky_mat.set_shader_parameter("disk_in", float(u.black_hole.disk_in))
		sky_mat.set_shader_parameter("disk_out", float(u.black_hole.disk_out))
	if u.star_index >= 0:
		sun.light_color = u.bodies[u.star_index].get("color", Color.WHITE)
	else:
		sun.light_color = Color(1.0, 0.97, 0.92)


## Squeeze a real distance into the drawable range, keeping order.
static func draw_distance(d: float) -> float:
	return NEAR_DRAW + (FAR_DRAW - NEAR_DRAW) * (1.0 - exp(-d / 4.0e8))


## Where the light falls on body i from (system frame).
func _light_on(i: int) -> Vector3:
	var u := flight.u
	if u.star_index < 0:
		return u.sun_dir
	if i == u.star_index:
		return Vector3.UP
	return Orbit.dir(Orbit.sub(u.position(u.star_index, flight.t), u.position(i, flight.t)))


func _process(_delta: float) -> void:
	if flight == null:
		return
	var u := flight.u
	if u.system_id != _system:
		rebuild()
	var inv := flight.att.inverse()
	sky_mat.set_shader_parameter("to_system", flight.att)
	var light_station := (inv * flight.light_dir).normalized()
	sky_mat.set_shader_parameter("sun_dir", light_station)
	sky_mat.set_shader_parameter("sun_on", 0.0)
	var lit := not flight.eclipsed and flight.light_flux > 0.0005
	sun.visible = lit
	sun.light_energy = 2.2 * clampf(pow(flight.light_flux, 0.3), 0.05, 2.2)
	sun.look_at_from_position(Vector3.ZERO, -light_station, Vector3.UP if absf(light_station.y) < 0.95 else Vector3.RIGHT)
	var me := flight.world_pos()
	if not u.black_hole.is_empty():
		var rel_bh := Orbit.sub(u.position(0, flight.t), me)
		sky_mat.set_shader_parameter("bh_dir", inv * Orbit.dir(rel_bh))
		sky_mat.set_shader_parameter("bh_dist", Orbit.length(rel_bh) / float(u.black_hole.rs))
		sky_mat.set_shader_parameter("disk_n", (inv * Vector3(u.black_hole.disk_n)).normalized())
	for i: int in stand_ins:
		var mi: MeshInstance3D = stand_ins[i]
		var b := u.bodies[i]
		var rel := Orbit.sub(u.position(i, flight.t), me)
		var d := Orbit.length(rel)
		var dd := draw_distance(d)
		var k := dd / d
		var r: float = maxf(float(b.radius) * k, dd * MIN_ANGLE)
		var dir_sys := Orbit.dir(rel)
		mi.transform = Transform3D(inv * Basis().scaled(Vector3.ONE * r), inv * dir_sys * dd)
		var light_sys := _light_on(i)
		(mi.material_override as ShaderMaterial).set_shader_parameter("sun_local", light_sys)
		(mi.material_override as ShaderMaterial).set_shader_parameter("lit", 1.0 if u.star_index >= 0 else 0.08)
		if rings.has(i):
			((rings[i] as MeshInstance3D).material_override as ShaderMaterial).set_shader_parameter("sun_local", light_sys)
		if b.look == "pulsar" and beams.size() == 2:
			_aim_beams(mi.position, dd, -dir_sys, inv)


## The pulsar's two beams sweep round its spin axis; the axis is set so the cone they
## sweep passes through the station, as the radiation readings say it does.
func _aim_beams(at: Vector3, dd: float, to_ship: Vector3, inv: Basis) -> void:
	var perp := to_ship.cross(Vector3.UP)
	if perp.length() < 0.1:
		perp = to_ship.cross(Vector3.RIGHT)
	perp = perp.normalized()
	var alpha := deg_to_rad(50.0)
	var spin := (to_ship * cos(alpha) + perp * sin(alpha)).normalized()
	var phase := flight.pulsar_phase()
	var beam_dir := to_ship.rotated(spin, TAU * phase)
	var half: float = float(flight.u.pulsar.get("angle", 0.08))
	for k in 2:
		var dir := beam_dir if k == 0 else -beam_dir
		var length := dd * 1.4
		var bi := beams[k]
		var y := (inv * dir).normalized()
		var x := y.cross(Vector3.UP if absf(y.y) < 0.9 else Vector3.RIGHT).normalized()
		var z := x.cross(y)
		var width := length * tan(half)
		bi.transform = Transform3D(Basis(x * width, y * length, z * width), at + y * length * 0.5)


func apply_quality(q: int) -> void:
	env.ssao_enabled = q >= 1
	env.ssil_enabled = q >= 2
	env.sdfgi_enabled = q >= 3
	# A faint haze in the cabin air: shafts of light from the windows and the lamps.
	env.volumetric_fog_enabled = q >= 2
	env.volumetric_fog_density = 0.012
	env.volumetric_fog_albedo = Color(0.8, 0.78, 0.74)
	env.volumetric_fog_anisotropy = 0.55
	env.volumetric_fog_length = 40.0
	sun.shadow_enabled = q >= 1
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if q >= 2 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
