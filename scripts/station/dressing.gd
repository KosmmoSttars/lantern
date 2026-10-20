class_name Dressing
extends RefCounted
## What is laid on once everything else is fitted: the safety posters, and pipe and cable runs
## along the corners of every module. No loose clutter: the only things about the station are
## the ones that do something.
##
## Nothing may overlap anything: a poster or a pipe run only goes where it clears the bounds
## of every fitting already there (panels, lockers, signs, strip lights, hatch swings) and every
## window. Each module's pipes are batched into its own node, so they go with it if it is cast
## off.

var station: Station
var _rng := RandomNumberGenerator.new()
var _obstacles: Array[AABB] = []
var _b := {}
var _mats := {}


func build(p_station: Station) -> void:
	station = p_station
	_rng.seed = 7741
	_mats = {
		"metal": Kit.metal(Color(0.55, 0.56, 0.58), 0.4, 0.8),
		"pipe_a": Kit.metal(Color(0.62, 0.63, 0.64), 0.35, 0.7),
		"pipe_b": Looks.panel(Color(0.3, 0.42, 0.55), 0.5),
		"cable": Kit.matte(Color(0.1, 0.1, 0.1), 0.7),
	}
	_gather_obstacles()
	_posters()
	for m: String in Station.SPINE:
		# The reactor module is fitted out by ReactorBay.
		if m == "Reactor":
			continue
		_corner_runs(Transform3D.IDENTITY, float(Station.SPINE[m][0]), float(Station.SPINE[m][1]))
		_commit(m)
	for m: String in Station.SIDE_LEN:
		var start := Station.A + Station.HULL
		_corner_runs(station.side_xform(m), start, start + float(Station.SIDE_LEN[m]))
		_commit(m)


# --- What is already there ---------------------------------------------------------------------

func _gather_obstacles() -> void:
	for n in station.find_children("*", "VisualInstance3D", true, false):
		var vi := n as VisualInstance3D
		if vi.name.begins_with("Batch_") or vi is Light3D:
			continue
		var bb := vi.global_transform * vi.get_aabb()
		# The hull, the cupola and the exterior are huge; only fittings count.
		if bb.size.length() > 4.5:
			continue
		_obstacles.append(bb)
	for w: Transform3D in station.windows:
		_obstacles.append(AABB(w.origin - Vector3.ONE * 0.45, Vector3.ONE * 0.9))
	# The Node's open hatchway to the docking port (it has no hatch to keep things off it).
	var node_z: float = (Station.SPINE["Node"][0] + Station.SPINE["Node"][1]) * 0.5
	_obstacles.append(AABB(Vector3(-Station.A - 0.2, -0.45, node_z - 0.45), Vector3(0.4, 0.9, 0.9)))
	# Every hatch door's swing: shut in its frame, it swings out a door's width to the side it
	# opens to, and nothing may be in the way there.
	for n in station.find_children("*", "Node3D", true, false):
		if n is Hatch:
			var h := n as Hatch
			var r := h.size * 0.5
			var xf := h.global_transform
			_obstacles.append(_box_aabb(xf, Vector3(h.size * 0.5 - 0.05, 0, 0.05), Vector3(h.size + 0.3, h.size + 0.1, h.size + 0.3)))
			# And a little on the other face, for the handwheel and the valve.
			_obstacles.append(_box_aabb(xf, Vector3(-0.15, 0, 0), Vector3(0.3, r * 2.0, r * 2.0)))


func _clear(bb: AABB) -> bool:
	for o in _obstacles:
		if o.intersects(bb):
			return false
	return true


func _builder(key: String) -> Geo.Builder:
	if not _b.has(key):
		_b[key] = Geo.Builder.new()
	return _b[key]


func _commit(m: String) -> void:
	var root := Node3D.new()
	root.name = "Pipes"
	(station.roots[m] as Node3D).add_child(root)
	for key: String in _b:
		var mi := MeshInstance3D.new()
		mi.mesh = (_b[key] as Geo.Builder).commit(_mats[key])
		root.add_child(mi)
	_b.clear()


# --- Posters ---------------------------------------------------------------------------------------

## The safety posters go up first, each in a module it belongs in, on the first stretch of
## upright wall a sheet will fit.
func _posters() -> void:
	var size := Vector3(Posters.W + 0.04, Posters.H + 0.04, 0.02)
	for entry: Array in Posters.SET:
		var placed := false
		for m: String in entry[4]:
			if placed:
				break
			var side := Station.SIDE_LEN.has(m)
			var z0: float = Station.A + Station.HULL if side else float(Station.SPINE[m][0])
			var z1: float = z0 + float(Station.SIDE_LEN[m]) if side else float(Station.SPINE[m][1])
			for i in [2, 6, 1, 7]:
				if placed:
					break
				var z := z0 + 0.4
				while z < z1 - 0.4:
					var xf := station.side_face_xform(m, i, z) if side else station.face_xform(i, z)
					var bb := _box_aabb(xf, Vector3(0, 0, 0.01), size)
					if _clear(bb):
						Posters.make(station, xf, String(entry[0]), String(entry[1]), String(entry[2]), String(entry[3]), false, _rng.randf_range(-0.04, 0.04))
						_obstacles.append(bb)
						placed = true
						break
					z += 0.2


# --- Pipes and cables along the corners ----------------------------------------------------------

## A bundle along each corner where two faces meet, clamped every metre or so.
func _corner_runs(xf: Transform3D, z0: float, z1: float) -> void:
	var r := Station.A / cos(PI / 8.0) - 0.05
	for k in 8:
		# Corners between faces k and k+1; the ones by the strip lights (3, 4, 5) stay clean.
		if k in [2, 3, 4]:
			continue
		var a := -PI / 2.0 + PI / 4.0 * k + PI / 8.0
		var c := Vector3(cos(a), sin(a), 0.0) * r
		var out := Vector3(cos(a), sin(a), 0.0)
		var side := Vector3(-sin(a), cos(a), 0.0)
		var zs := z0 + 0.25
		var ze := z1 - 0.25
		var pipes := [[side * 0.022, 0.016, "pipe_a"], [-side * 0.022, 0.013, "pipe_b" if k % 2 == 0 else "pipe_a"], [-out * 0.025, 0.009, "cable"]]
		# The bundle runs where nothing is fitted over the corner; it stops short of a panel or
		# a fitting and picks up again past it.
		var step := 0.1
		var runs: Array[Vector2] = []
		var open_at := -1.0
		var z := zs
		while z <= ze + 0.001:
			var bb := AABB(xf * Vector3(c.x, c.y, z), Vector3.ZERO).grow(0.06)
			bb = bb.merge(AABB(xf * Vector3(c.x, c.y, minf(z + step, ze)), Vector3.ZERO).grow(0.06))
			var free := _clear(bb)
			if free and open_at < 0.0:
				open_at = z
			elif not free and open_at >= 0.0:
				runs.append(Vector2(open_at, z - 0.04))
				open_at = -1.0
			z += step
		if open_at >= 0.0:
			runs.append(Vector2(open_at, ze))
		for run in runs:
			if run.y - run.x < 0.3:
				continue
			for p: Array in pipes:
				var o: Vector3 = c + (p[0] as Vector3)
				_builder(String(p[2])).cylinder(xf * Vector3(o.x, o.y, run.x), xf * Vector3(o.x, o.y, run.y), float(p[1]), 8, true)
			var zc := run.x + 0.2
			while zc < run.y - 0.15:
				_builder("metal").box(xf * Vector3(c.x, c.y, zc), Vector3(0.09, 0.05, 0.025), xf.basis * Basis(Vector3.BACK, a + PI / 2.0))
				zc += 1.1


# --- Things on the walls -------------------------------------------------------------------------

## What goes on a free stretch of wall, and how often (weights).
const KINDS := [
	["rail", 18], ["vent", 8], ["laptop", 12], ["intercom", 9], ["extinguisher", 7],
	["breather", 6], ["first_aid", 6], ["tool_strip", 9], ["fan", 6], ["plants", 6], ["clock", 6],
]


func _box_aabb(xf: Transform3D, center: Vector3, size: Vector3) -> AABB:
	var bb := AABB(xf * center, Vector3.ZERO)
	for c in 8:
		var corner := Vector3(size.x * (0.5 if c & 1 else -0.5), size.y * (0.5 if c & 2 else -0.5), size.z * (0.5 if c & 4 else -0.5))
		bb = bb.expand(xf * (center + corner))
	return bb
