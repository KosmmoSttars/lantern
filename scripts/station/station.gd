class_name Station
extends Node3D
## Lantern, built in code. Station frame: the spine runs along Z with the bow toward -Z,
## +Y is the station's "up" (where labels and the keeper's head point), +X starboard.
##
## Pressurised modules, bow to stern:
##   Command deck  z -14 .. -11  flight desk, forward cupola of nine windows (a tight cockpit)
##   Engineering   z -11 .. -6   reactor, electrical, thermal panels
##   Node          z -6  .. -3   docking port to port (-X), airlock to starboard (+X)
##   Habitation    z -3  .. 3    galley, bunk, exercise, two windows
##   Life support  z 3   .. 7    air, water, tanks
## Outside, aft of the life support module: the truss, the hydrogen tank, solar wings,
## radiators, the reactor behind its shadow shield and the main engine.
##
## Every module is an octagonal prism (apothem A). Walls are batched per material; faces
## are numbered i = 0..7 counterclockwise seen from the bow, 0 = floor (-Y), 2 = starboard
## (+X), 4 = ceiling (+Y), 6 = port (-X).

## Apothem: 2.1 m across the flats, a narrow tube to live in.
const A := 0.68
const SKIN := 0.04
const HULL := 0.1
const HOLE := 0.27

## name -> [z0, z1] (spine modules).
const SPINE := {
	"Command deck": [-14.0, -11.2],
	"Engineering": [-11.2, -8.4],
	"Node": [-8.4, -6.8],
	"Habitation": [-6.8, -3.4],
	"Life support": [-3.4, -0.4],
	"Reactor": [-0.4, 2.4],
}
## The radiator panels: how far each reaches out from the hull, and its width.
const RAD_SPAN := 2.6
const RAD_W := 1.3
const SIDE_LEN := {"Airlock": 2.6, "Dock": 1.2}
const DOME_SHADER := """
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, specular_schlick_ggx;

varying vec3 lp;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	lp = VERTEX;
}

void fragment() {
	float fres = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 3.0);
	vec2 uv = lp.xy * 3.0 + vec2(lp.z * 2.0, -lp.z * 1.3);
	float smudge = smoothstep(0.45, 0.9, noise(uv * 2.2) * noise(uv * 0.9 + 7.3) * 2.0);
	float dust = step(0.992, hash(floor(uv * 90.0))) * 0.6;
	float lines = abs(sin((lp.x * 0.7 + lp.y * 0.7) * 160.0 + noise(uv * 3.0) * 9.0));
	float scratch = smoothstep(0.996, 1.0, lines) * step(0.62, noise(uv * 1.1 + 2.0));
	float rim = smoothstep(0.55, 0.79, length(lp.xy));
	// A faint blue-grey body to the sheet and a sheen that grows to the edges, so it reads as
	// glass from inside and out, and never as an open hole.
	ALBEDO = vec3(0.55, 0.66, 0.74);
	ALPHA = clamp(0.07 + fres * 0.55 + smudge * 0.06 + dust * 0.7 + scratch * 0.22 + rim * 0.12, 0.0, 0.8);
	EMISSION = vec3(0.05, 0.07, 0.09) * (0.3 + fres * 1.2);
	ROUGHNESS = 0.04 + smudge * 0.5;
	METALLIC = 0.0;
	SPECULAR = 0.9;
}
"""

## Render layers: the cabin, and the outside of the hull. Cabin lamps light only the first.
const INSIDE_LAYER := 1
const OUTSIDE_LAYER := 2
## Batches that are the outside of the hull.
const OUTSIDE_KEYS := ["mli", "handrail", "frame_out", "dark_out", "truss", "radiator"]
## How far an end wall stands out from its module's end.
const END_T := 0.12
## Where the cupola ends and how wide its front window is.
const BOW_Z := -14.85
const BOW_A := 0.72
## Where a new keeper starts, floating behind the flight desk.
const SPAWN := Vector3(0.0, 0.1, -12.6)

var sim: ShipSim
## Every module is built under its own node (with its own hull body) so that it can be cast
## off whole: module name -> node, and "Stern" for the truss, tank and engines aft.
var roots := {}
var _hulls := {}
## Modules cast off (or blown away).
var gone: Array[String] = []
## The reactor module's node (null once it is gone), and whether it has gone.
var reactor_root: Node3D
var reactor_gone := false
## Where lamps, strips and such go while a module is being built (that module's node).
var _parent: Node3D
var _saved: Array = []
var hull: StaticBody3D
var lights: Array[OmniLight3D] = []
var emergency: Array[OmniLight3D] = []
var strips: Array[StandardMaterial3D] = []
## Panels by name.
var panels := {}
## Exterior moving parts.
var radiators: Array[Node3D] = []
var wings: Array[Node3D] = []
var windows: Array[Transform3D] = []

var _b := {}
var _mats := {}


static func outward(i: int) -> Vector3:
	var th := -PI / 2.0 + PI / 4.0 * i
	return Vector3(cos(th), sin(th), 0.0)


static func tangent(i: int) -> Vector3:
	var th := -PI / 2.0 + PI / 4.0 * i
	return Vector3(-sin(th), cos(th), 0.0)


## Half the width of an octagon face.
static func half_face() -> float:
	return A * tan(PI / 8.0)


func build() -> void:
	hull = StaticBody3D.new()
	hull.name = "Hull"
	hull.collision_layer = Layers.WORLD
	hull.collision_mask = 0
	add_child(hull)
	# A working station, years out: dark painted metal, scuffed and grimy, bare steel trim.
	_mats["rack"] = Looks.panel(Color(0.36, 0.37, 0.34), 0.7, 0.05, 1.6, 1.0)
	_mats["rack_dark"] = Looks.panel(Color(0.2, 0.21, 0.2), 0.6, 0.15, 1.6, 1.0)
	_mats["frame"] = Looks.panel(Color(0.3, 0.31, 0.32), 0.42, 0.55, 1.0, 0.0)
	_mats["mli"] = Looks.mli(Color(0.52, 0.51, 0.48))
	_mats["mli_gold"] = Looks.mli(Color(0.86, 0.66, 0.32))
	_mats["glass"] = Looks.glass()
	# The cockpit's dome: one sheet of glass, seen from both sides. Clear face on, it catches
	# the light at a slant, and carries a little wear: smudges, specks of dust, fine scratches.
	var dome := ShaderMaterial.new()
	dome.shader = Shader.new()
	dome.shader.code = DOME_SHADER
	_mats["dome"] = dome
	_mats["rail"] = Kit.metal(Color(0.62, 0.64, 0.68), 0.35, 0.8)
	_mats["truss"] = Kit.metal(Color(0.7, 0.7, 0.68), 0.45, 0.8)
	_mats["dark"] = Kit.metal(Color(0.12, 0.12, 0.13), 0.5, 0.6)
	_mats["radiator"] = Kit.matte(Color(0.55, 0.56, 0.55), 0.45)
	_mats["handrail"] = Kit.matte(Color(0.9, 0.7, 0.12), 0.5)
	_mats["frame_out"] = _mats["frame"]
	_mats["dark_out"] = _mats["dark"]

	_parent = self
	for m: String in SPINE:
		var z0: float = SPINE[m][0]
		var z1: float = SPINE[m][1]
		_enter(m)
		_spine_module(m, z0, z1)
		if m == "Command deck":
			_cupola()
		if m == "Reactor":
			# The stern of the pressurised stack: a blank pressure wall and the hull's end cap.
			# The wall stands a hull's thickness proud of the module's end: the skin runs on
			# over it and the cap closes it at its outer face, so no slit shows the cabin.
			_end_wall(Transform3D.IDENTITY, z1, 1.0, false)
			_skin(Transform3D.IDENTITY, z1, z1 + END_T, {})
			_hull_cap(Transform3D.IDENTITY, z1 + END_T, 1.0)
		_leave()
	for m: String in SIDE_LEN:
		_enter(m)
		_side_module(m, side_of(m))
		_leave()
	_bulkheads()
	_exterior()
	_commit()
	reactor_root = roots["Reactor"]
	for r in radiators:
		outside(r)
	for w in wings:
		outside(w)


## Build into module `m`'s own node and hull body (made on first use) until _leave().
func _enter(m: String) -> void:
	if not roots.has(m):
		var r := Node3D.new()
		r.name = m.replace(" ", "") + "Module"
		add_child(r)
		roots[m] = r
		var h := StaticBody3D.new()
		h.name = "Hull"
		h.collision_layer = Layers.WORLD
		h.collision_mask = 0
		r.add_child(h)
		_hulls[m] = h
	_saved = [_b, hull, _parent]
	_b = {}
	hull = _hulls[m]
	_parent = roots[m]


func _leave() -> void:
	_commit_into(_parent)
	_b = _saved[0]
	hull = _saved[1]
	_parent = _saved[2]


# --- Frames ---------------------------------------------------------------------------------

## Transform of a panel on face i of a spine module, centred at z (and `s` along the face).
## The panel's +z faces into the cabin; its y is the face's "up".
func face_xform(i: int, z: float, s := 0.0, inset := 0.012) -> Transform3D:
	var d := outward(i)
	var u := tangent(i)
	if u.y < -0.01 or (absf(u.y) < 0.01 and u.x < 0.0):
		u = -u
	var zn := -d
	var x := u.cross(zn)
	return Transform3D(Basis(x, u, zn), d * (A - inset) + u * s + Vector3(0, 0, z))


## Which side of the Node a side module (or a module docked beyond the port) hangs on: the
## docking port to port (-1), the airlock to starboard (+1).
static func side_of(m: String) -> int:
	return 1 if m == "Airlock" else -1


## Frame of a side module (Dock or Airlock): its Z runs outward from the Node.
func side_xform(m: String) -> Transform3D:
	var node_z: float = (SPINE["Node"][0] + SPINE["Node"][1]) * 0.5
	var side := side_of(m)
	return Transform3D(Basis(Vector3(0, 0, -side), Vector3.UP, Vector3(side, 0, 0)), Vector3(0, 0, node_z))


## face_xform inside a side module (z measured outward from the Node's axis).
func side_face_xform(m: String, i: int, z: float, s := 0.0) -> Transform3D:
	var xf := side_xform(m)
	var local := face_xform(i, z, s)
	var t := xf * local
	# Keep the panel's "up" the station's up where the face allows.
	if t.basis.y.y < -0.01:
		t.basis = Basis(-t.basis.x, -t.basis.y, t.basis.z)
	return t


## Where a delivery's crate is left once a drone has docked at the airlock: on the airlock
## floor, clear of the hatches, the locker and the reel.
func cargo_spot() -> Vector3:
	var node_z: float = (SPINE["Node"][0] + SPINE["Node"][1]) * 0.5
	return Vector3(A + HULL + 1.25, -A + 0.3, node_z - 0.15)


# --- Walls -----------------------------------------------------------------------------------

func _builder(key: String) -> Geo.Builder:
	if not _b.has(key):
		_b[key] = Geo.Builder.new()
	return _b[key]


## A solid wall piece: inner skin, outer hull and a collider. `frame` maps the face's own
## coordinates (s along the face, z along the module, n outward) into station space.
func _wall_rect(frame: Transform3D, s0: float, s1: float, z0: float, z1: float, rack := "rack") -> void:
	if s1 - s0 < 0.002 or z1 - z0 < 0.002:
		return
	var c := Vector3((s0 + s1) * 0.5, (z0 + z1) * 0.5, 0.0)
	var size := Vector2(s1 - s0, z1 - z0)
	var basis := frame.basis
	var inner := frame * (c + Vector3(0, 0, SKIN * 0.5))
	_builder(rack).box(inner, Vector3(size.x, size.y, SKIN), basis)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(size.x, size.y, HULL)
	cs.shape = bs
	cs.transform = Transform3D(basis, frame * (c + Vector3(0, 0, HULL * 0.5)))
	hull.add_child(cs)


## One octagon face from z0 to z1 with rectangular holes (s0, s1, za, zb) cut out of it.
## Each hole in `windows` gets a window well; others stay open (tunnels to other modules).
func _face(module_xform: Transform3D, i: int, z0: float, z1: float, holes: Array, glazed: bool, rack := "rack") -> void:
	var d := outward(i)
	var u := tangent(i)
	# Face frame: x = s along the face, y = z along the module, z = outward.
	var frame := module_xform * Transform3D(Basis(u, Vector3(0, 0, 1), d), d * A)
	var hw := half_face()
	holes.sort_custom(func(a: Array, b: Array) -> bool: return a[2] < b[2])
	var z := z0
	for h: Array in holes:
		_wall_rect(frame, -hw, hw, z, h[2], rack)
		_wall_rect(frame, -hw, h[0], h[2], h[3], rack)
		_wall_rect(frame, h[1], hw, h[2], h[3], rack)
		if glazed:
			_window_well(frame, h[0], h[1], h[2], h[3])
		else:
			_tunnel(frame, h[0], h[1], h[2], h[3])
		z = h[3]
	_wall_rect(frame, -hw, hw, z, z1, rack)
	# Corner trim and a handrail along the face's edges.
	var e0 := frame * Vector3(-hw, z0, -0.01)
	var e1 := frame * Vector3(-hw, z1, -0.01)
	_builder("frame").box((e0 + e1) * 0.5, Vector3(0.05, 0.05, (z1 - z0)), module_xform.basis * Basis(Vector3.BACK, PI / 8.0 + PI / 4.0 * i))


func _window_well(frame: Transform3D, s0: float, s1: float, z0: float, z1: float) -> void:
	var w := s1 - s0
	var h := z1 - z0
	var c := Vector3((s0 + s1) * 0.5, (z0 + z1) * 0.5, 0.0)
	var b := _builder("frame")
	# Sides of the well through the wall.
	for side in [[Vector3(-w * 0.5 - 0.02, 0, HULL * 0.5), Vector3(0.04, h + 0.08, HULL)], [Vector3(w * 0.5 + 0.02, 0, HULL * 0.5), Vector3(0.04, h + 0.08, HULL)], [Vector3(0, -h * 0.5 - 0.02, HULL * 0.5), Vector3(w + 0.08, 0.04, HULL)], [Vector3(0, h * 0.5 + 0.02, HULL * 0.5), Vector3(w + 0.08, 0.04, HULL)]]:
		b.box(frame * (c + side[0]), side[1], frame.basis)
	# Bezel on the cabin side.
	var bz := 0.05
	for side in [[Vector3(-w * 0.5 - bz * 0.5, 0, -0.012), Vector3(bz, h + bz * 2.0, 0.024)], [Vector3(w * 0.5 + bz * 0.5, 0, -0.012), Vector3(bz, h + bz * 2.0, 0.024)], [Vector3(0, -h * 0.5 - bz * 0.5, -0.012), Vector3(w, bz, 0.024)], [Vector3(0, h * 0.5 + bz * 0.5, -0.012), Vector3(w, bz, 0.024)]]:
		_builder("dark").box(frame * (c + side[0]), side[1], frame.basis)
	# Two panes.
	_builder("glass").box(frame * (c + Vector3(0, 0, HULL * 0.25)), Vector3(w, h, 0.01), frame.basis)
	_builder("glass").box(frame * (c + Vector3(0, 0, HULL * 0.8)), Vector3(w, h, 0.01), frame.basis)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(w, h, 0.05)
	cs.shape = bs
	cs.transform = Transform3D(frame.basis, frame * (c + Vector3(0, 0, HULL * 0.25)))
	hull.add_child(cs)
	windows.append(Transform3D(frame.basis, frame * c))


func _tunnel(frame: Transform3D, s0: float, s1: float, z0: float, z1: float) -> void:
	var w := s1 - s0
	var h := z1 - z0
	var c := Vector3((s0 + s1) * 0.5, (z0 + z1) * 0.5, 0.0)
	# Round in the cabin: a plate over the square tunnel mouth with a round hatchway in it.
	var half := minf(w, h) * 0.5
	var sq := Geo.square(half + 0.06)
	var plate := _builder("rack")
	var shape_b := Geo.Builder.new()
	var seg := 48
	var out_n := frame.basis * Vector3(0, 0, -1)
	for k in seg:
		var a0 := TAU * k / seg
		var a1 := TAU * (k + 1) / seg
		var p0: Vector2 = sq.call(a0)
		var p1: Vector2 = sq.call(a1)
		var q0 := Vector2(cos(a0), sin(a0)) * half
		var q1 := Vector2(cos(a1), sin(a1)) * half
		var v := [Vector3(p0.x, p0.y, -0.02), Vector3(p1.x, p1.y, -0.02), Vector3(q1.x, q1.y, -0.02), Vector3(q0.x, q0.y, -0.02)]
		for i in 4:
			v[i] = frame * (c + v[i])
		plate.quad(v[0], v[1], v[2], v[3], out_n)
		shape_b.quad(v[0], v[1], v[2], v[3], out_n)
	var pcs := CollisionShape3D.new()
	pcs.shape = shape_b.shape()
	hull.add_child(pcs)
	_round_collar(frame * Transform3D(Basis(), c), half, -0.04, HULL + 0.02)
	# A hair short of the far end, so the frame never shares a plane with the wall beyond.
	for side in [[Vector3(-w * 0.5 - 0.03, 0, (HULL - 0.005) * 0.5), Vector3(0.06, h + 0.12, HULL - 0.005)], [Vector3(w * 0.5 + 0.03, 0, (HULL - 0.005) * 0.5), Vector3(0.06, h + 0.12, HULL - 0.005)], [Vector3(0, -h * 0.5 - 0.03, (HULL - 0.005) * 0.5), Vector3(w + 0.12, 0.06, HULL - 0.005)], [Vector3(0, h * 0.5 + 0.03, (HULL - 0.005) * 0.5), Vector3(w + 0.12, 0.06, HULL - 0.005)]]:
		_builder("frame").box(frame * (c + side[0]), side[1], frame.basis)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = side[1]
		cs.shape = bs
		cs.transform = Transform3D(frame.basis, frame * (c + side[0]))
		hull.add_child(cs)


func _spine_module(m: String, z0: float, z1: float) -> void:
	var holes := {}
	var glazed := {}
	for i in 8:
		holes[i] = []
		glazed[i] = false
	match m:
		"Node":
			var zc := (z0 + z1) * 0.5
			holes[2] = [[-HOLE, HOLE, zc - HOLE, zc + HOLE]]
			holes[6] = [[-HOLE, HOLE, zc - HOLE, zc + HOLE]]
		"Command deck":
			holes[3] = [[-0.25, 0.25, -12.2, -11.6]]
			glazed[3] = true
			holes[5] = [[-0.25, 0.25, -12.2, -11.6]]
			glazed[5] = true
	for i in 8:
		var rack := "rack_dark" if m == "Engineering" and i in [1, 7] else "rack"
		_face(Transform3D.IDENTITY, i, z0, z1, holes[i], glazed[i], rack)
	_skin(Transform3D.IDENTITY, z0, z1, holes)
	# The command deck's upper windows sit on the strip lights' faces: break the strips there.
	_module_lights(Transform3D.IDENTITY, z0, z1, Vector2(-12.3, -11.5) if m == "Command deck" else Vector2.ZERO)


## The Dock (side = -1, port) and the Airlock (+1, starboard) run out along X from the Node.
func _side_module(m: String, side: int) -> void:
	var node_z: float = (SPINE["Node"][0] + SPINE["Node"][1]) * 0.5
	var start := A + HULL
	var length: float = SIDE_LEN[m]
	# Module frame: its Z runs outward along +-X, its Y stays up.
	var zaxis := Vector3(side, 0, 0)
	var basis := Basis(Vector3(0, 0, -side), Vector3.UP, zaxis)
	var xf := Transform3D(basis, Vector3(0, 0, node_z))
	var holes := {}
	var glazed := {}
	for i in 8:
		holes[i] = []
		glazed[i] = false
	for i in 8:
		_face(xf, i, start, start + length, holes[i], glazed[i])
	_skin(xf, start, start + length + END_T, holes)
	# The berthing adapter: a short drum from the Node's skin out to the module, round the
	# square tunnel through the wall, with a flange where they bolt together.
	var onto := xf * Transform3D(Basis(Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(-1, 0, 0)), Vector3.ZERO)
	var ad := _builder("frame_out")
	ad.xform = onto
	ad.tube_x(HOLE + 0.2, start - HULL - 0.08, start + 0.04, 40)
	ad.lathe_x(PackedVector2Array([Vector2(start - 0.1, HOLE + 0.2), Vector2(start - 0.09, HOLE + 0.26), Vector2(start - 0.01, HOLE + 0.26), Vector2(start, HOLE + 0.2)]), 40)
	ad.xform = Transform3D.IDENTITY
	# End wall, with the round opening for the airlock's EVA hatch or the docking port's.
	_end_wall(xf, start + length, 1.0, true)
	_end_wall(xf, start, -1.0, true)
	# Close the hull's thickness at both ends, outside.
	_hull_cap(xf, start, -1.0)
	_hull_cap(xf, start + length + END_T, 1.0)
	_module_lights(xf, start, start + length)


func _collide(p: Vector3, size: Vector3, basis := Basis()) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.transform = Transform3D(basis, p)
	hull.add_child(cs)


## A flat octagonal wall across a module at module-z `z`, `facing` = +1 or -1 picks which
## side it is thickened toward, with an optional round hatchway in the middle.
func _end_wall(xf: Transform3D, z: float, facing: float, opening: bool) -> void:
	var thick := 0.12
	var outer := Geo.octagon(A + 0.01, 2.0 * A - A * sqrt(2.0))
	var o := HOLE if opening else 0.0
	var inner := Geo.circle(o)
	var b := _builder("rack")
	var shape_b := Geo.Builder.new()
	var seg := 64
	for side in [0.0, 1.0]:
		var zz: float = z + facing * thick * side
		var n := Vector3(0, 0, -facing if side == 0.0 else facing)
		for k in seg:
			var a0 := TAU * k / seg
			var a1 := TAU * (k + 1) / seg
			var p0: Vector2 = outer.call(a0)
			var p1: Vector2 = outer.call(a1)
			var q0: Vector2 = inner.call(a0) if opening else Vector2.ZERO
			var q1: Vector2 = inner.call(a1) if opening else Vector2.ZERO
			var v := [Vector3(p0.x, p0.y, zz), Vector3(p1.x, p1.y, zz), Vector3(q1.x, q1.y, zz), Vector3(q0.x, q0.y, zz)]
			for i in 4:
				v[i] = xf * (v[i] as Vector3)
			var nn := xf.basis * n
			if opening:
				# Mapped flat across the wall, so the panel texture runs on unbroken round the hole.
				var uv := [p0, p1, q1, q0]
				b.tri(v[0], v[1], v[2], nn, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, uv[0], uv[1], uv[2])
				b.tri(v[0], v[2], v[3], nn, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, uv[0], uv[2], uv[3])
				shape_b.quad(v[0], v[1], v[2], v[3], nn)
			else:
				b.tri(v[0], v[1], v[2], nn)
				shape_b.tri(v[0], v[1], v[2], nn)
	var cs := CollisionShape3D.new()
	cs.shape = shape_b.shape()
	hull.add_child(cs)
	if opening:
		_round_collar(xf, o, z - facing * 0.04, z + facing * (thick + 0.04))


## The round frame of a hatchway: a short tube lining the hole from module-z `za` to `zb`,
## with a rolled rim on each face.
func _round_collar(xf: Transform3D, r: float, za: float, zb: float, seg := 48) -> void:
	var f := _builder("frame")
	var shape_b := Geo.Builder.new()
	for k in seg:
		var a0 := TAU * k / seg
		var a1 := TAU * (k + 1) / seg
		var d0 := Vector3(cos(a0), sin(a0), 0)
		var d1 := Vector3(cos(a1), sin(a1), 0)
		var v := [xf * (d0 * r + Vector3(0, 0, za)), xf * (d1 * r + Vector3(0, 0, za)), xf * (d1 * r + Vector3(0, 0, zb)), xf * (d0 * r + Vector3(0, 0, zb))]
		var n := xf.basis * -(d0 + d1).normalized()
		f.quad(v[0], v[1], v[2], v[3], n)
		shape_b.quad(v[0], v[1], v[2], v[3], n)
	for zz in [za, zb]:
		var ring := PackedVector3Array()
		for k in seg + 1:
			var a := TAU * k / seg
			ring.append(xf * Vector3(cos(a) * (r + 0.015), sin(a) * (r + 0.015), zz))
		f.sweep(ring, 0.03, 8)
	var cs := CollisionShape3D.new()
	cs.shape = shape_b.shape()
	hull.add_child(cs)


## A module's round outer skin from z0 to z1 (module frame), cut where a face has a window or
## a hatchway (`holes`: face -> [[s0, s1, z0, z1], ...]).
func _skin(module_xf: Transform3D, z0: float, z1: float, holes: Dictionary) -> void:
	var b := _builder("mli")
	var onto := Transform3D(Basis(Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(-1, 0, 0)), Vector3.ZERO)
	b.xform = module_xf * onto
	var inv := module_xf.affine_inverse()
	var keep := func(p: Vector3) -> bool:
		var q := inv * p
		for i: int in holes:
			var d := outward(i)
			var depth := q.x * d.x + q.y * d.y
			if depth <= 0.1:
				continue
			var sv := (q.x * tangent(i).x + q.y * tangent(i).y) * A / depth
			for h: Array in holes[i]:
				if sv > float(h[0]) - 0.03 and sv < float(h[1]) + 0.03 and q.z > float(h[2]) - 0.03 and q.z < float(h[3]) + 0.03:
					return false
		return true
	b.tube_x_cut(A + HULL, z0, z1, 64, maxi(ceili((z1 - z0) / 0.05), 1), keep)
	b.xform = Transform3D.IDENTITY
	# The skin is solid from outside too (a coarser copy, with the same openings): a suited
	# keeper and the umbilical lie on it, they do not sink into it.
	var sb := Geo.Builder.new()
	sb.xform = module_xf * onto
	sb.tube_x_cut(A + HULL, z0, z1, 40, maxi(ceili((z1 - z0) / 0.12), 1), keep)
	var cs := CollisionShape3D.new()
	cs.shape = sb.shape()
	hull.add_child(cs)


## The ring of hull between the cabin wall and the outer skin, closed off at module-z `z`
## (facing +1 or -1 along the module), so the gap between the two skins never shows outside.
func _hull_cap(xf: Transform3D, z: float, facing: float) -> void:
	var outer := Geo.circle(A + HULL)
	var inner := Geo.octagon(A, 2.0 * A - A * sqrt(2.0))
	var b := _builder("mli")
	var cap_b := Geo.Builder.new()
	var n := xf.basis * Vector3(0, 0, facing)
	var seg := 64
	for k in seg:
		var a0 := TAU * k / seg
		var a1 := TAU * (k + 1) / seg
		var p0: Vector2 = outer.call(a0)
		var p1: Vector2 = outer.call(a1)
		var q0: Vector2 = inner.call(a0)
		var q1: Vector2 = inner.call(a1)
		b.quad(xf * Vector3(p0.x, p0.y, z), xf * Vector3(p1.x, p1.y, z), xf * Vector3(q1.x, q1.y, z), xf * Vector3(q0.x, q0.y, z), n)
		cap_b.quad(xf * Vector3(p0.x, p0.y, z), xf * Vector3(p1.x, p1.y, z), xf * Vector3(q1.x, q1.y, z), xf * Vector3(q0.x, q0.y, z), n)
	var cs := CollisionShape3D.new()
	cs.shape = cap_b.shape()
	hull.add_child(cs)


func _bulkheads() -> void:
	# Between spine modules: a ring wall with a hatchway. The Node's ends too.
	# Each wall belongs to the module forward of it: cast off what lies aft and the wall stays
	# (its hatchway sealed by the blast seal).
	var ident := Transform3D.IDENTITY
	for z: float in WALL_OWNER:
		_enter(WALL_OWNER[z])
		_end_wall(ident, z, 1.0, true)
		# A hull end cap too, for the day it is the stern.
		if z > -11.2:
			_hull_cap(ident, z, 1.0)
		_leave()
	# Signs over every hatchway naming where it leads.
	var order := ["Command deck", "Engineering", "Node", "Habitation", "Life support", "Reactor"]
	var walls := [-11.2, -8.4, -6.8, -3.4, -0.4]
	for k in walls.size():
		var z: float = walls[k]
		_sign(String(order[k + 1]).to_upper() + "  >", Vector3(0, HOLE + 0.17, z - 0.012), PI)
		_sign("<  " + String(order[k]).to_upper(), Vector3(0, HOLE + 0.17, z + 0.132), 0.0)
	var node_z: float = (SPINE["Node"][0] + SPINE["Node"][1]) * 0.5
	# The side walls are only as tall as their hatchways: these go on the diagonal above.
	_sign_at("AIRLOCK", face_xform(3, node_z, -0.13, 0.004))
	_sign_at("DOCKING PORT", face_xform(5, node_z, -0.13, 0.004))
	_sign("LIFE SUPPORT IS THE FLARE SHELTER", Vector3(0, -HOLE - 0.17, float(SPINE["Life support"][0]) - 0.012), PI)


func _sign(text: String, pos: Vector3, yaw: float) -> void:
	_sign_at(text, Transform3D(Basis(Vector3.UP, yaw), pos))


## A sign plate at `xf` (its +z facing the reader, +y up the plate).
func _sign_at(text: String, xf: Transform3D) -> void:
	var l := Ctl.text(self, text, Vector3.ZERO, 0.032, Color(0.06, 0.05, 0.03))
	l.transform = xf * Transform3D(Basis(), Vector3(0, -0.012, 0.006))
	# The plate as long as the legend in either language (as long as the wall allows), and
	# the legend never longer than the plate.
	var longest := 0.0
	for s: String in [text, Loc.t(text)]:
		longest = maxf(longest, l.font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, l.font_size).x * l.pixel_size)
	var w := minf(longest + 0.08, 2.0 * A * 0.92)
	Ctl.fit(l, w - 0.05, 0.06)
	var plate := Kit.mesh(self, Kit.box(Vector3(w, 0.075, 0.008)), Kit.matte(Color(0.75, 0.6, 0.15), 0.6), xf.origin, xf.basis)
	plate.name = "Sign"


# --- Command deck ------------------------------------------------------------------------------

func _cupola() -> void:
	# The nose is one round glass dome, no frame and no bars: the cabin's wall runs straight
	# into the glass.
	var z0: float = SPINE["Command deck"][0]
	var depth := z0 - BOW_Z
	# Round: as wide as the cabin's faces, the corners walled off round it.
	var r0 := A - 0.005
	var prof := PackedVector2Array()
	var steps := 16
	for k in steps + 1:
		var a := PI / 2.0 * k / steps
		prof.append(Vector2(z0 - sin(a) * depth, cos(a) * r0))
	var glass := _builder("dome")
	var onto := Transform3D(Basis(Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(-1, 0, 0)), Vector3.ZERO)
	glass.xform = onto
	glass.lathe_x(prof, 96, false)
	glass.xform = Transform3D.IDENTITY
	var shape_b := Geo.Builder.new()
	shape_b.xform = onto
	shape_b.lathe_x(prof, 32, false)
	var cs := CollisionShape3D.new()
	cs.shape = shape_b.shape()
	hull.add_child(cs)
	# Where the octagonal cabin meets the round glass: the wall closes the corners, flush.
	var oct := Geo.octagon(A, 2.0 * A - A * sqrt(2.0))
	var wall := _builder("rack")
	for k in 64:
		var a0 := TAU * k / 64.0
		var a1 := TAU * (k + 1) / 64.0
		var p0: Vector2 = oct.call(a0)
		var p1: Vector2 = oct.call(a1)
		var q0 := Vector2(cos(a0), sin(a0)) * r0
		var q1 := Vector2(cos(a1), sin(a1)) * r0
		wall.quad(Vector3(p0.x, p0.y, z0), Vector3(p1.x, p1.y, z0), Vector3(q1.x, q1.y, z0), Vector3(q0.x, q0.y, z0), Vector3.BACK)
		# Outside, the hull's end ring from the glass out to the skin.
		var o0 := Vector2(cos(a0), sin(a0)) * (A + HULL)
		var o1 := Vector2(cos(a1), sin(a1)) * (A + HULL)
		_builder("mli").quad(Vector3(o0.x, o0.y, z0 - 0.003), Vector3(o1.x, o1.y, z0 - 0.003), Vector3(q1.x, q1.y, z0 - 0.003), Vector3(q0.x, q0.y, z0 - 0.003), Vector3.FORWARD)
	windows.append(Transform3D(Basis.looking_at(Vector3.FORWARD), Vector3(0, 0, z0 - depth * 0.5)))


# --- Lights ----------------------------------------------------------------------------------

func _module_lights(xf: Transform3D, z0: float, z1: float, gap := Vector2.ZERO) -> void:
	var length := z1 - z0
	var n := maxi(1, roundi(length / 2.6))
	for k in n:
		var z := z0 + length * (k + 0.5) / n
		var l := OmniLight3D.new()
		# Warm, dim cabin lamps with hard falloff: pools of light and deep shadow between.
		l.light_color = Color(1.0, 0.8, 0.58)
		l.light_energy = 0.62
		l.omni_range = 3.8
		l.omni_attenuation = 1.8
		l.shadow_enabled = true
		l.set_meta("shadow_wanted", true)
		l.distance_fade_enabled = true
		l.distance_fade_begin = 14.0
		l.distance_fade_shadow = 6.0
		l.distance_fade_length = 3.0
		l.shadow_bias = 0.04
		# The cabin's lamps light the cabin only: never the hull outside through the walls.
		l.light_cull_mask = INSIDE_LAYER
		l.position = xf * Vector3(0, A - 0.25, z)
		_parent.add_child(l)
		lights.append(l)
		var e := OmniLight3D.new()
		e.light_color = Color(1.0, 0.18, 0.1)
		e.light_energy = 0.0
		e.omni_range = 3.0
		e.light_cull_mask = INSIDE_LAYER
		e.position = xf * Vector3(0, -A + 0.3, z)
		_parent.add_child(e)
		emergency.append(e)
	# Light strips along the two upper diagonals.
	for i in [3, 5]:
		var d := outward(i)
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.55, 0.53, 0.5)
		m.emission_enabled = true
		m.emission = Color(1.0, 0.82, 0.6)
		m.emission_energy_multiplier = 0.16
		strips.append(m)
		var basis := Basis(Vector3.BACK, PI / 2.0 + atan2(d.y, d.x))
		var runs := [Vector2(z0 + 0.45, z1 - 0.45)]
		if gap != Vector2.ZERO:
			runs = [Vector2(z0 + 0.45, gap.x), Vector2(gap.y, z1 - 0.45)]
		for r: Vector2 in runs:
			if r.y - r.x < 0.1:
				continue
			var mi := MeshInstance3D.new()
			mi.mesh = Kit.box(Vector3(0.05, 0.012, r.y - r.x))
			mi.material_override = m
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.transform = xf * Transform3D(basis, d * (A - 0.006) + Vector3(0, 0, (r.x + r.y) * 0.5))
			_parent.add_child(mi)


## Cabin lights follow the lights breaker; the red emergency lamps run off the battery.
## The reactor module's own shell, lamps and colliders, under `reactor_root`: its faces, its
## aft pressure wall and the hull's end cap. (Its fittings come from ReactorBay.)
# --- Casting modules off ------------------------------------------------------------------------

## The spine from the bow aft; the side modules hang off the Node, the stern (truss, tank,
## engines) off Life support on its longerons.
const CHAIN := ["Command deck", "Engineering", "Node", "Habitation", "Life support", "Reactor"]
## Each bulkhead and the module it belongs to (the one forward of it).
const WALL_OWNER := {-11.2: "Command deck", -8.4: "Engineering", -6.8: "Node", -3.4: "Habitation", -0.4: "Life support"}


## What goes when `m` is cast off: it and everything that hangs beyond it. The command deck
## (where it is done from) never goes.
func cast_set(m: String) -> Array[String]:
	var out: Array[String] = []
	if gone.has(m):
		return out
	if SIDE_LEN.has(m) or port_index(m) >= 0:
		if SIDE_LEN.has(m):
			out.append(m)
		# The docking port takes everything docked beyond it; a docked module, what is beyond it.
		if m == "Dock" or port_index(m) >= 0:
			for k in range(maxi(port_index(m), 0), port_chain.size()):
				if not gone.has(String(port_chain[k].name)):
					out.append(String(port_chain[k].name))
		return out
	var i := CHAIN.find(m)
	if i <= 0:
		return out
	for k in range(i, CHAIN.size()):
		if not gone.has(CHAIN[k]):
			out.append(CHAIN[k])
	if out.has("Node"):
		for sm: String in SIDE_LEN:
			if not gone.has(sm):
				out.append(sm)
		for e: Dictionary in port_chain:
			if not gone.has(String(e.name)):
				out.append(String(e.name))
	if out.has("Life support") and not gone.has("Stern"):
		out.append("Stern")
	return out


## Which module's space a point (station frame) lies in, walls and hull included, for
## sorting the fittings when a module goes: "" for none.
func region_of(p: Vector3) -> String:
	var node_z: float = (SPINE["Node"][0] + SPINE["Node"][1]) * 0.5
	var r := A + HULL + 0.6
	if absf(p.x) > A - 0.02 and absf(p.z - node_z) < A + HULL and absf(p.y) < A + HULL:
		if p.x > 0.0:
			return "Airlock"
		return port_region(-p.x)
	if p.z < SPINE["Command deck"][0]:
		return "Command deck"
	if p.z >= SPINE["Reactor"][1] + 0.2:
		return "Stern"
	if Vector2(p.x, p.y).length() > r:
		# Outside the hull: the longerons and the dish mast belong to what they hang on.
		if absf(p.x) > 1.5 and p.z > 6.0:
			return "Stern"
		if p.y < 0.0 and absf(p.z - node_z) < 1.5:
			return "Node"
	for m: String in SPINE:
		if p.z >= float(SPINE[m][0]) - 0.001 and p.z < float(SPINE[m][1]) - 0.001:
			return m
	return "Reactor" if p.z < SPINE["Reactor"][1] + 0.2 else ""


## Cast module `m` off, and with it all that hangs beyond it (see cast_set). Everything of
## theirs goes under one node, returned for main to send drifting; the hatchway left open in
## the station is closed by a blast seal. Loose things inside are lost.
func separate(m: String) -> Node3D:
	var set := cast_set(m)
	if set.is_empty():
		return null
	var docked_on := port_index(m) >= 0
	var cast := Node3D.new()
	cast.name = "Cast" + m.replace(" ", "")
	add_child(cast)
	for k: String in set:
		gone.append(k)
		if roots.has(k):
			(roots[k] as Node3D).reparent(cast, true)
	for c in get_children():
		if c == cast or c is CollisionObject3D and c.get_parent() != self or not c is Node3D:
			continue
		if roots.values().has(c) or String(c.name).begins_with("Cast") or c.name == "Umbilical":
			continue
		var n := c as Node3D
		if not set.has(region_of(n.position)):
			continue
		if n is RigidBody3D:
			n.queue_free()
		else:
			n.reparent(cast, true)
	lights = lights.filter(func(l: OmniLight3D) -> bool: return not cast.is_ancestor_of(l))
	emergency = emergency.filter(func(l: OmniLight3D) -> bool: return not cast.is_ancestor_of(l))
	wings = wings.filter(func(w: Node3D) -> bool: return not cast.is_ancestor_of(w))
	radiators = radiators.filter(func(w: Node3D) -> bool: return not cast.is_ancestor_of(w))
	if set.has("Reactor"):
		reactor_gone = true
		reactor_root = null
	# A module docked at the port leaves its hatch behind to shut the way: no blast seal. Its
	# name is free again for the next one docked there.
	for k: String in set:
		if port_index(k) >= 0:
			port_chain.remove_at(port_index(k))
			roots.erase(k)
			_hulls.erase(k)
			gone.erase(k)
	if not docked_on:
		_blast_seal(m)
	return cast


## The blast seal: a thick plate driven across the hatchway left open by a cast-off module.
func _blast_seal(m: String) -> void:
	var xf: Transform3D
	var node_z: float = (SPINE["Node"][0] + SPINE["Node"][1]) * 0.5
	if port_index(m) >= 0:
		# Across the hatchway it was docked to, in the wall before it.
		xf = Transform3D(Basis(Vector3.UP, -PI / 2.0), Vector3(-float(port_chain[port_index(m)].z0) + 0.06, 0, node_z))
	elif SIDE_LEN.has(m):
		var side := float(side_of(m))
		xf = Transform3D(Basis(Vector3.UP, side * PI / 2.0), Vector3(side * (A + 0.04), 0, node_z))
	else:
		xf = Transform3D(Basis(), Vector3(0, 0, float(SPINE[m][0]) + 0.06))
	var seal := StaticBody3D.new()
	seal.name = "BlastSeal" + m.replace(" ", "")
	seal.collision_layer = Layers.WORLD
	seal.collision_mask = 0
	seal.transform = xf
	add_child(seal)
	var r := HOLE + 0.05
	Kit.mesh(seal, Kit.cylinder(r, 0.06, 32), Kit.metal(Color(0.42, 0.42, 0.4), 0.5, 0.7), Vector3.ZERO, Basis(Vector3.RIGHT, PI / 2.0))
	var stripes := Geo.Builder.new()
	for k in 12:
		var a := TAU * k / 12.0
		for s in [-1.0, 1.0]:
			stripes.box(Vector3(cos(a), sin(a), 0) * (r - 0.06) + Vector3(0, 0, s * 0.032), Vector3(0.07, 0.035, 0.004), Basis(Vector3.BACK, a + 0.7))
	Kit.mesh(seal, stripes.commit(Kit.matte(Color(0.95, 0.75, 0.12), 0.6)), null)
	for s in [-1.0, 1.0]:
		var l := Ctl.text(seal, "BLAST SEAL", Vector3(0, 0, s * 0.034), 0.04, Color(0.08, 0.08, 0.08))
		l.rotation.y = 0.0 if s > 0.0 else PI
		Ctl.fit(l, r * 1.5, 0.06)
	var shape := CylinderShape3D.new()
	shape.radius = r
	shape.height = 0.08
	Kit.collider(seal, shape, Vector3.ZERO, Basis(Vector3.RIGHT, PI / 2.0))


## Cast the reactor module off (the JETTISON by its hatch).
func jettison_reactor() -> Node3D:
	return separate("Reactor")


func set_power(lit: bool, emergency_on: bool) -> void:
	for l in lights:
		l.visible = lit
	for m in strips:
		m.emission_energy_multiplier = 0.16 if lit else 0.0
	for e in emergency:
		e.light_energy = 0.35 if emergency_on else 0.0


# --- Outside ----------------------------------------------------------------------------------

func _exterior() -> void:
	# No truss, tank or engine: the station flies by the game's own licence. What hangs off
	# the stack is what keeps it alive: the radiators off Life support (with "Stern", they go
	# when Life support goes), the solar wings, the dish.
	_enter("Stern")
	var lz: float = (float(SPINE["Life support"][0]) + float(SPINE["Life support"][1])) * 0.5
	for sy in [-1.0, 1.0]:
		for k in 2:
			var hinge := Node3D.new()
			hinge.position = Vector3(0, sy * (A + HULL + 0.04), lz - RAD_W * 0.55 + k * RAD_W * 1.1)
			_parent.add_child(hinge)
			_radiator_panel(hinge, sy)
			hinge.set_meta("side", sy)
			radiators.append(hinge)
	_leave()
	_enter("Engineering")
	_solar_wings()
	_leave()
	# Hull exterior bands where modules meet: a ring of plates round the outside.
	for zband: float in [-11.2, -8.4, -6.8, -3.4, -0.4, 2.4]:
		_enter(WALL_OWNER.get(zband, "Reactor"))
		var ring := _builder("dark_out")
		ring.xform = Transform3D(Basis(Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(-1, 0, 0)), Vector3.ZERO)
		ring.lathe_x(PackedVector2Array([Vector2(zband - 0.08, A + HULL), Vector2(zband - 0.07, A + HULL + 0.035), Vector2(zband + 0.07, A + HULL + 0.035), Vector2(zband + 0.08, A + HULL)]), 48)
		ring.xform = Transform3D.IDENTITY
		_leave()
	# EVA handrails along every spine module, on both flanks and the top, ISS fashion.
	for m: String in SPINE:
		_enter(m)
		var mz0: float = SPINE[m][0] + 0.35
		var mz1: float = SPINE[m][1] - 0.35
		for i in [1, 4, 7]:
			var d := outward(i)
			var t := tangent(i)
			for s in [-0.22, 0.22]:
				var base: Vector3 = d * (A + HULL + 0.11) + t * s
				_builder("handrail").cylinder(base + Vector3(0, 0, mz0), base + Vector3(0, 0, mz1), 0.018, 6)
				var zz := mz0
				while zz <= mz1 + 0.01:
					_builder("handrail").cylinder(d * (A + HULL) + t * s + Vector3(0, 0, zz), base + Vector3(0, 0, zz), 0.014, 5)
					zz += (mz1 - mz0) / maxf(roundf((mz1 - mz0) / 0.9), 1.0)
		_leave()
	_hull_lights()
	# High-gain dish on a mast off the node: a shallow bowl, a feed horn on three struts.
	_enter("Node")
	var node_z: float = (SPINE["Node"][0] + SPINE["Node"][1]) * 0.5
	var mast := Geo.Builder.new()
	mast.cylinder(Vector3(0, -A - HULL, node_z), Vector3(0, -A - 2.0, node_z), 0.06, 8)
	mast.cylinder(Vector3(0, -A - 1.9, node_z), Vector3(0, -A - 2.15, node_z), 0.12, 12)
	outside(Kit.mesh(_parent, mast.commit(_mats["truss"]), null))
	var bowl := Geo.Builder.new()
	var bp := PackedVector2Array()
	for k in 9:
		var r := 0.6 * k / 8.0
		bp.append(Vector2(-0.17 * (r / 0.6) * (r / 0.6), r))
	bowl.lathe_x(bp, 32, false)
	bowl.lathe_x(bp, 32, true)
	var dish := MeshInstance3D.new()
	dish.name = "Dish"
	dish.mesh = bowl.commit(_mats["radiator"])
	dish.transform = Transform3D(Basis(Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)), Vector3(0, -A - 2.15, node_z))
	_parent.add_child(dish)
	outside(dish)
	var horn := Geo.Builder.new()
	var focus := Vector3(0, -A - 2.15 - 0.42, node_z)
	for k in 3:
		var a := TAU * k / 3.0
		horn.cylinder(Vector3(cos(a) * 0.46, -A - 2.15 - 0.1, node_z + sin(a) * 0.46), focus, 0.012, 5)
	horn.cylinder(focus, focus + Vector3(0, 0.12, 0), 0.05, 10)
	outside(Kit.mesh(_parent, horn.commit(_mats["dark"]), null))
	_leave()


## A radiator wing on its hinge: a framed panel of tubes with the coolant header along the
## hinge edge. Built along the hinge's +y (or -y): the hinge scales it to fold it flat.
func _radiator_panel(hinge: Node3D, sy: float) -> void:
	var span := RAD_SPAN
	var width := RAD_W
	var panel := Geo.Builder.new()
	panel.box(Vector3(0, sy * (span * 0.5 + 0.15), 0), Vector3(0.035, span, width))
	Kit.mesh(hinge, panel.commit(_mats["radiator"]), null)
	var frame := Geo.Builder.new()
	for s in [-1.0, 1.0]:
		frame.box(Vector3(0, sy * (span * 0.5 + 0.15), s * width * 0.5), Vector3(0.06, span, 0.05))
	for k in 6:
		var y: float = sy * (0.15 + span * k / 5.0)
		frame.box(Vector3(0, y, 0), Vector3(0.055, 0.04, width))
	# Flow tubes down the panel, and the header they feed from.
	for k in 9:
		var zt := -width * 0.5 + width * (k + 0.5) / 9.0
		frame.box(Vector3(0.025, sy * (span * 0.5 + 0.15), zt), Vector3(0.012, span, 0.018))
	frame.cylinder(Vector3(0, sy * 0.12, -width * 0.5), Vector3(0, sy * 0.12, width * 0.5), 0.05, 10)
	Kit.mesh(hinge, frame.commit(_mats["dark"]), null)


## The solar wings: a mast up off the Engineering module and a cross boom, and on each side
## a wing of two big blankets either side of its spar, ISS fashion. Each wing turns on its
## boom to face the Sun (as far as clears the hull) and folds up along it when stowed.
func _solar_wings() -> void:
	var top := A + HULL
	var mast := Geo.Builder.new()
	mast.cylinder(Vector3(0, top, WING_Z), Vector3(0, WING_Y, WING_Z), 0.09, 10)
	mast.cylinder(Vector3(-WING_X0, WING_Y, WING_Z), Vector3(WING_X0, WING_Y, WING_Z), 0.11, 12)
	for sx in [-1.0, 1.0]:
		mast.cylinder(Vector3(sx * WING_X0, WING_Y - 0.18, WING_Z), Vector3(sx * WING_X0, WING_Y + 0.18, WING_Z), 0.16, 12)
	outside(Kit.mesh(_parent, mast.commit(_mats["truss"]), null))
	_collide(Vector3(0, (top + WING_Y) * 0.5, WING_Z), Vector3(0.18, WING_Y - top, 0.18))
	_collide(Vector3(0, WING_Y, WING_Z), Vector3(WING_X0 * 2.0, 0.22, 0.22))
	for sx in [-1.0, 1.0]:
		var hinge := Node3D.new()
		hinge.position = Vector3(sx * WING_X0, WING_Y, WING_Z)
		_parent.add_child(hinge)
		# What folds up (the meshes, scaled along the spar) and what the hand and body meet (a
		# solid that turns with the wing, its boxes resized as it folds).
		var fold := Node3D.new()
		hinge.add_child(fold)
		var solid := AnimatableBody3D.new()
		solid.sync_to_physics = false
		solid.collision_layer = Layers.WORLD
		solid.collision_mask = 0
		hinge.add_child(solid)
		var boxes: Array[CollisionShape3D] = []
		var spar := Geo.Builder.new()
		spar.cylinder(Vector3.ZERO, Vector3(sx * WING_LEN, 0, 0), 0.05, 8)
		var frame := Geo.Builder.new()
		for sz in [-1.0, 1.0]:
			var zc: float = sz * (WING_W * 0.5 + 0.15)
			# Blanket: panels in a row with a hair of dark frame between them.
			var blanket := Kit.mesh(fold, Kit.box(Vector3(WING_LEN - 0.3, 0.03, WING_W)), Looks.solar(), Vector3(sx * (WING_LEN * 0.5 + 0.15), 0, zc))
			blanket.name = "Wing"
			var bs := BoxShape3D.new()
			bs.size = Vector3(WING_LEN - 0.3, 0.08, WING_W + 0.08)
			boxes.append(Kit.collider(solid, bs, Vector3(sx * (WING_LEN * 0.5 + 0.15), 0, zc)))
			for k in 7:
				var x: float = sx * (0.15 + (WING_LEN - 0.3) * k / 6.0)
				frame.box(Vector3(x, 0, zc), Vector3(0.05, 0.05, WING_W + 0.04))
			frame.box(Vector3(sx * (WING_LEN * 0.5 + 0.15), 0, zc + sz * (WING_W * 0.5 + 0.02)), Vector3(WING_LEN - 0.3, 0.05, 0.05))
			frame.box(Vector3(sx * (WING_LEN * 0.5 + 0.15), 0, zc - sz * (WING_W * 0.5 + 0.02)), Vector3(WING_LEN - 0.3, 0.05, 0.05))
		Kit.mesh(fold, spar.commit(_mats["truss"]), null)
		Kit.mesh(fold, frame.commit(_mats["dark"]), null)
		var spar_shape := CylinderShape3D.new()
		spar_shape.radius = 0.08
		spar_shape.height = WING_LEN
		boxes.append(Kit.collider(solid, spar_shape, Vector3(sx * WING_LEN * 0.5, 0, 0), Basis(Vector3.BACK, PI / 2.0)))
		hinge.set_meta("side", sx)
		hinge.set_meta("fold", fold)
		hinge.set_meta("boxes", boxes)
		wings.append(hinge)


## Where the wings sit: the mast off Engineering, the boom's half length, wing size (m).
const WING_Z := -9.8
const WING_Y := A + HULL + 1.1
const WING_X0 := 1.1
const WING_LEN := 6.0
const WING_W := 1.6
## Toward the Sun in station space (set by main); the wings turn to face it.
var sun_dir := Vector3.UP
var _wings_set := false


func _process(delta: float) -> void:
	if sim == null:
		return
	# The blankets work on either face: turn whichever is nearer to the Sun, within what clears
	# the hull below.
	var s := Vector2(sun_dir.y, sun_dir.z)
	if s.x < 0.0:
		s = -s
	var want := clampf(atan2(s.y, s.x), -1.2, 1.2) if s.length() > 0.05 else 0.0
	for w in wings:
		# Already facing the Sun when the station first appears; slow tracking after that.
		w.rotation.x = move_toward(w.rotation.x, want, delta * 0.15) if _wings_set else want
		var k := lerpf(0.08, 1.0, sim.arrays_deploy)
		(w.get_meta("fold") as Node3D).scale.x = k
		var sx: float = w.get_meta("side")
		for cs: CollisionShape3D in w.get_meta("boxes"):
			if cs.shape is BoxShape3D:
				(cs.shape as BoxShape3D).size.x = (WING_LEN - 0.3) * k
				cs.position.x = sx * (WING_LEN * 0.5 + 0.15) * k
			else:
				(cs.shape as CylinderShape3D).height = WING_LEN * k
				cs.position.x = sx * WING_LEN * 0.5 * k
	_wings_set = _wings_set or sun_dir != Vector3.UP
	for r in radiators:
		r.scale.y = lerpf(0.06, 1.0, sim.rad_deploy)



# --- Queries --------------------------------------------------------------------------------

## Which module a point (station space) is in, or "" outside the pressure hull.
func module_at(p: Vector3) -> String:
	var r := A + 0.02
	var inside_oct := func(x: float, y: float) -> bool:
		return absf(x) <= r and absf(y) <= r and absf(x) + absf(y) <= r * sqrt(2.0)
	for m: String in SPINE:
		if gone.has(m):
			continue
		var z0: float = SPINE[m][0]
		var z1: float = SPINE[m][1]
		if p.z >= z0 and p.z <= z1 and inside_oct.call(p.x, p.y):
			return m
	if p.z < SPINE["Command deck"][0] and p.z > BOW_Z and absf(p.x) < A and absf(p.y) < A:
		return "Command deck"
	var node_z: float = (SPINE["Node"][0] + SPINE["Node"][1]) * 0.5
	for m: String in SIDE_LEN:
		if gone.has(m):
			continue
		var side := float(side_of(m))
		var x := p.x * side
		var start := A
		# The docking port reaches out through its end wall to whatever is docked there.
		var reach: float = HULL + SIDE_LEN[m] + (END_T if m == "Dock" else 0.0)
		if x >= start and x <= start + reach and inside_oct.call(p.z - node_z, p.y):
			return m
	for e: Dictionary in port_chain:
		if gone.has(String(e.name)):
			continue
		if -p.x >= float(e.z0) and -p.x <= float(e.z1) + END_T and inside_oct.call(p.z - node_z, p.y):
			return String(e.name)
	return ""


# --- Beyond the docking port ----------------------------------------------------------------------

## Modules docked for good beyond the docking port, outward: [{name, kind, z0, z1}], z measured
## out along the Dock's frame (as for the side modules) from the Node's axis.
var port_chain: Array[Dictionary] = []


func port_index(m: String) -> int:
	for k in port_chain.size():
		if String(port_chain[k].name) == m:
			return k
	return -1


## Where the next thing docks: the outer face of the last end wall out from the Node.
func port_face() -> float:
	if not port_chain.is_empty():
		return float(port_chain[-1].z1) + END_T
	return A + HULL + float(SIDE_LEN["Dock"]) + END_T


## The docking face in station space: its origin on the port's axis, +X pointing out of it
## (toward the station: a docked module's own +X runs away from it along -X).
func port_xform() -> Transform3D:
	var node_z: float = (SPINE["Node"][0] + SPINE["Node"][1]) * 0.5
	return Transform3D(Basis(Vector3.UP, PI), Vector3(-port_face() - 0.005, 0, node_z))


## Which part of the port side point x (out from the axis along -X) lies in.
func port_region(x: float) -> String:
	for k in range(port_chain.size() - 1, -1, -1):
		if x >= float(port_chain[k].z0):
			return String(port_chain[k].name)
	return "Dock"


## Build a module docked for good at the port: its own node and hull body, faces, round skin,
## an end wall at each end with a hatchway (the inner one against the wall it docked to), its
## lamps and handrails. `holes`: face -> [[s0, s1, z0, z1]] windows, z from the module's start.
## Its fittings are the caller's (PortModules). Returns its entry in port_chain.
func add_port_module(m: String, kind: String, length: float, holes := {}) -> Dictionary:
	var z0 := port_face()
	var z1 := z0 + length
	var e := {"name": m, "kind": kind, "z0": z0, "z1": z1}
	_enter(m)
	var xf := side_xform("Dock")
	var cut := {}
	for i in 8:
		cut[i] = []
		for h: Array in holes.get(i, []):
			cut[i].append([h[0], h[1], z0 + float(h[2]), z0 + float(h[3])])
	for i in 8:
		_face(xf, i, z0 + END_T, z1, (cut[i] as Array).duplicate(), not (cut[i] as Array).is_empty())
	_skin(xf, z0, z1 + END_T, cut)
	_end_wall(xf, z0, 1.0, true)
	_end_wall(xf, z1, 1.0, true)
	_hull_cap(xf, z1 + END_T, 1.0)
	_module_lights(xf, z0 + END_T, z1)
	# The berthing ring where it bolts on, and the EVA handrails along its top and flanks.
	var onto := xf * Transform3D(Basis(Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(-1, 0, 0)), Vector3.ZERO)
	var ring := _builder("dark_out")
	ring.xform = onto
	ring.lathe_x(PackedVector2Array([Vector2(z0 - 0.08, A + HULL), Vector2(z0 - 0.07, A + HULL + 0.035), Vector2(z0 + 0.07, A + HULL + 0.035), Vector2(z0 + 0.08, A + HULL)]), 48)
	ring.xform = Transform3D.IDENTITY
	var rz0 := z0 + 0.35
	var rz1 := z1 - 0.2
	for i in [1, 4, 7]:
		var d := outward(i)
		var t := tangent(i)
		for s in [-0.22, 0.22]:
			var base: Vector3 = d * (A + HULL + 0.11) + t * s
			_builder("handrail").cylinder(xf * (base + Vector3(0, 0, rz0)), xf * (base + Vector3(0, 0, rz1)), 0.018, 6)
			for zz in [rz0, rz1]:
				_builder("handrail").cylinder(xf * (d * (A + HULL) + t * s + Vector3(0, 0, zz)), xf * (base + Vector3(0, 0, zz)), 0.014, 5)
	_leave()
	port_chain.append(e)
	return e


func _commit() -> void:
	_commit_into(self)


func _commit_into(parent: Node3D) -> void:
	for key: String in _b:
		var b: Geo.Builder = _b[key]
		if b.is_empty():
			continue
		var mi := MeshInstance3D.new()
		mi.name = "Batch_" + key
		mi.mesh = b.commit(_mats[key])
		if key == "glass" or key == "dome":
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if key in OUTSIDE_KEYS:
			mi.layers = OUTSIDE_LAYER
		parent.add_child(mi)
	_b.clear()


## Lamps on the hull, so the dark side is not a void: a dim work light on top of every module
## and a pair of floodlights round the airlock's outer hatch to find the way back in by.
func _hull_lights() -> void:
	var lamp_mat := Kit.glow(Color(1.0, 0.86, 0.62), 3.0)
	var housing_mat := Kit.metal(Color(0.2, 0.21, 0.23), 0.5, 0.6)
	var add := func(at: Vector3, normal: Vector3, energy: float, reach: float, color: Color) -> void:
		var l := OmniLight3D.new()
		l.light_color = color
		l.light_energy = energy
		l.omni_range = reach
		l.omni_attenuation = 1.4
		l.light_cull_mask = OUTSIDE_LAYER
		l.position = at + normal * 0.12
		_parent.add_child(l)
		lights.append(l)
		var h := Geo.Builder.new()
		var base := Basis.looking_at(normal, Vector3.FORWARD if absf(normal.dot(Vector3.UP)) > 0.9 else Vector3.UP)
		h.xform = Transform3D(base, at)
		h.box(Vector3(0, 0, -0.03), Vector3(0.14, 0.07, 0.06))
		var g := Geo.Builder.new()
		g.xform = Transform3D(base, at)
		g.box(Vector3(0, 0, -0.065), Vector3(0.11, 0.045, 0.01))
		outside(Kit.mesh(_parent, h.commit(housing_mat), null))
		outside(Kit.mesh(_parent, g.commit(lamp_mat), null))
	for m: String in SPINE:
		if m == "Command deck":
			continue
		_enter(m)
		var mz: float = (float(SPINE[m][0]) + float(SPINE[m][1])) * 0.5
		# Top and keel (the Node's keel carries the dish mast).
		for i in ([4] if m == "Node" else [4, 0]):
			var d := outward(i)
			add.call(d * (A + HULL) + Vector3(0, 0, mz), d, 0.7, 3.2, Color(1.0, 0.86, 0.62))
		_leave()
	_enter("Airlock")
	var node_z: float = (SPINE["Node"][0] + SPINE["Node"][1]) * 0.5
	var end_x := A + HULL + float(SIDE_LEN["Airlock"])
	for sy in [-1.0, 1.0]:
		add.call(Vector3(end_x + END_T + 0.005, sy * (HOLE + 0.17), node_z), Vector3.RIGHT, 1.1, 3.5, Color(1.0, 0.8, 0.5))
	# Along the airlock's top, lighting the way from the hatch back over the hull.
	add.call(Vector3((A + end_x) * 0.5, A + HULL, node_z), Vector3.UP, 0.8, 3.0, Color(1.0, 0.86, 0.62))
	_leave()
	# The docking port: a lamp on its top and one under it, to come in to it by.
	_enter("Dock")
	var dock_x := A + HULL + float(SIDE_LEN["Dock"]) * 0.5
	for i in [4, 0]:
		var d := outward(i)
		add.call(Vector3(-dock_x, d.y * (A + HULL), node_z), d, 0.9, 3.2, Color(1.0, 0.86, 0.62))
	_leave()


## Everything under `n` is outside the hull: only the Sun and the helmet lamp light it.
static func outside(n: Node) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).layers = OUTSIDE_LAYER
	for c in n.get_children():
		outside(c)


## Cabin lamps cast shadows from Medium up (soft shadows are the expensive part).
func apply_quality(q: int) -> void:
	for l in lights:
		l.shadow_enabled = q >= 1
