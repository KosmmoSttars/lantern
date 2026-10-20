class_name Hose
extends MeshInstance3D
## The EVA umbilical from its reel in the airlock to the keeper's waist: a rope of beads joined
## end to end (Verlet), each one kept out of the station's hull, so the hose runs out through
## the hatch, lies along the hull and wraps round what it meets instead of passing through it.
## The reel pays it out as the keeper pulls and winds the slack back in. The hand can take
## hold of it anywhere (Layers.HOSE): that bead stays in the hand.

const RADIUS := 0.022
## The hand ray's target round the tube: a little fatter than the tube, so it is easy to catch.
const GRAB_RADIUS := 0.07
const SHAPES := 24
## Beads along the hose, and how far a bead keeps off a surface.
const BEADS := 72
const STANDOFF := 0.035
const ITERATIONS := 10
## The reel: pays out as fast as it is pulled; winds slack in at this speed.
const WIND := 0.8

var body: StaticBody3D
## What the hose does not meet: the reel it comes off (set by main).
var ignore: Array[RID] = []
## The hose's length now paid out, and the length its beads actually run (taut when equal).
var paid := 2.0
var path_len := 0.0
## From the waist back along the hose: the way it pulls when it is taut.
var pull_dir := Vector3.ZERO

var _shapes: Array[CollisionShape3D] = []
var _p := PackedVector3Array()
var _prev := PackedVector3Array()
var _live := false


func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	material_override = Kit.matte(Color(0.85, 0.62, 0.18), 0.7)
	visible = false
	body = StaticBody3D.new()
	body.name = "Grip"
	body.collision_layer = Layers.HOSE
	body.collision_mask = 0
	body.add_to_group("hose")
	add_child(body)
	for i in SHAPES:
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = GRAB_RADIUS
		cs.shape = cap
		cs.disabled = true
		body.add_child(cs)
		_shapes.append(cs)


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and body:
		for cs in _shapes:
			cs.disabled = not is_visible_in_tree()
		if not is_visible_in_tree():
			_live = false


## Lay the hose out straight from the reel to the suit (clipping on).
func reset(from: Vector3, to: Vector3) -> void:
	_p.resize(BEADS)
	_prev.resize(BEADS)
	for i in BEADS:
		var q := from.lerp(to, float(i) / (BEADS - 1))
		_p[i] = q
		_prev[i] = q
	paid = clampf(from.distance_to(to) * 1.1, 1.0, Suit.HOSE_LEN)
	_live = true


## Step the hose from `from` (the reel, leaving along `out`) to `to` (the suit) and redraw it.
## `via`: where the hand holds it (INF = not held). `taut` is kept for the callers' sake.
func draw(from: Vector3, out: Vector3, to: Vector3, _taut: float, delta: float, via := Vector3.INF) -> void:
	# Clipping on, or the suit somewhere else all at once (a reload): laid out afresh.
	if not _live or _p.size() != BEADS or _p[BEADS - 1].distance_to(to) > 3.0:
		reset(from, to)
	var space := get_world_3d().direct_space_state
	var dt := minf(delta, 1.0 / 30.0)
	# The bead the hand has, if any: the nearest to the hand.
	var held := -1
	if via != Vector3.INF:
		var best := INF
		for i in range(1, BEADS - 1):
			var dd := _p[i].distance_squared_to(via)
			if dd < best:
				best = dd
				held = i
	# Move: what each bead was doing, a little damped (it is a heavy, stiff hose).
	for i in range(1, BEADS - 1):
		var v := (_p[i] - _prev[i]) * 0.96
		_prev[i] = _p[i]
		_p[i] += v
	var seg := paid / (BEADS - 1)
	for it in ITERATIONS:
		_p[0] = from
		_p[1] = from + out * minf(seg, 0.3)
		_p[BEADS - 1] = to
		if held > 0:
			_p[held] = via
		for i in BEADS - 1:
			var a := _p[i]
			var b := _p[i + 1]
			var d := b - a
			var l := d.length()
			if l < 1e-5:
				continue
			# A rope: it can go slack, but not stretch.
			if l <= seg:
				continue
			var corr := d * ((l - seg) / l)
			var a_fixed := i <= 1 or i == held
			var b_fixed := i + 1 == BEADS - 1 or i + 1 == held
			if a_fixed and b_fixed:
				continue
			if a_fixed:
				_p[i + 1] = b - corr
			elif b_fixed:
				_p[i] = a + corr
			else:
				_p[i] = a + corr * 0.5
				_p[i + 1] = b - corr * 0.5
	_collide(space)
	# A few more passes so the hose straightens round what it now lies on, then a last check.
	for it in 3:
		for i in BEADS - 1:
			var d := _p[i + 1] - _p[i]
			var l := d.length()
			if l <= seg or l < 1e-5:
				continue
			var corr := d * ((l - seg) / l)
			if i <= 1:
				if i + 1 < BEADS - 1:
					_p[i + 1] -= corr
			elif i + 1 >= BEADS - 1:
				_p[i] += corr
			else:
				_p[i] += corr * 0.5
				_p[i + 1] -= corr * 0.5
	_collide(space)
	_p[0] = from
	_p[BEADS - 1] = to
	if held > 0:
		_p[held] = via
	# The reel: pulled, it pays out (up to the full length); slack, it winds in.
	path_len = 0.0
	for i in BEADS - 1:
		path_len += _p[i].distance_to(_p[i + 1])
	if path_len > paid * 0.97:
		paid = minf(maxf(paid, path_len * 1.08), Suit.HOSE_LEN)
	elif path_len < paid * 0.85:
		# Wound in only as far as the hose really runs (round the hull, not straight through).
		paid = maxf(paid - WIND * dt, path_len * 1.05)
	pull_dir = (_p[BEADS - 2] - to).normalized() if _p[BEADS - 2].distance_to(to) > 1e-4 else (from - to).normalized()
	var path := _smooth(_p)
	var radii := PackedFloat32Array()
	radii.resize(path.size())
	radii.fill(RADIUS)
	mesh = Kit.sweep(path, radii, 8)
	_fit_shapes(path)


## Keep every bead, and every stretch between two beads, out of the hull and the fittings.
## Surfaces are met from either side (a ray can strike a face from behind), so the normal is
## always turned to face where the hose came from; and each bead is kept on the same side of a
## wall as the one before it, from the reel outward, so the hose can only wrap, never cut.
func _collide(space: PhysicsDirectSpaceState3D) -> void:
	var mask := Layers.WORLD | Layers.FURNITURE
	for i in range(2, BEADS - 1):
		# Where the bead went since last step: a wall in the way stops it on the wall.
		if _prev[i].distance_squared_to(_p[i]) > 1e-8:
			var q := PhysicsRayQueryParameters3D.create(_prev[i], _p[i], mask, ignore)
			var hit := space.intersect_ray(q)
			if not hit.is_empty():
				var n := _facing(hit.normal, _p[i] - _prev[i])
				_p[i] = hit.position + n * STANDOFF
				var v := _p[i] - _prev[i]
				_prev[i] = _p[i] - (v - n * v.dot(n)) * 0.5
	for i in range(1, BEADS - 1):
		# The stretch to the next bead cuts a wall: that bead goes back to this one's side.
		var q := PhysicsRayQueryParameters3D.create(_p[i], _p[i + 1], mask, ignore)
		var hit := space.intersect_ray(q)
		if hit.is_empty() or i + 1 >= BEADS - 1:
			continue
		var n := _facing(hit.normal, _p[i + 1] - _p[i])
		_p[i + 1] = hit.position + n * STANDOFF
		_prev[i + 1] = _p[i + 1]
	# The suit end is where it is: if the last stretch cuts a wall, walk back from the suit
	# bringing beads round to its side until the hose is whole.
	var last := PhysicsRayQueryParameters3D.create(_p[BEADS - 2], _p[BEADS - 1], mask, ignore)
	if space.intersect_ray(last).is_empty():
		return
	for i in range(BEADS - 2, 1, -1):
		var q := PhysicsRayQueryParameters3D.create(_p[i + 1], _p[i], mask, ignore)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			break
		var n := _facing(hit.normal, _p[i] - _p[i + 1])
		_p[i] = hit.position + n * STANDOFF
		_prev[i] = _p[i]


## A surface normal turned to face against `dir` (back toward where the ray came from).
static func _facing(n: Vector3, dir: Vector3) -> Vector3:
	return -n if n.dot(dir) > 0.0 else n


## A smooth line through the beads (Catmull-Rom, two points per stretch).
func _smooth(p: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	var n := p.size()
	for i in n - 1:
		var p0 := p[maxi(i - 1, 0)]
		var p1 := p[i]
		var p2 := p[i + 1]
		var p3 := p[mini(i + 2, n - 1)]
		out.append(p1)
		var t := 0.5
		var t2 := t * t
		var t3 := t2 * t
		out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	out.append(p[n - 1])
	return out


## Capsules along the path for the hand ray (not the last half metre: that is at your waist).
func _fit_shapes(path: PackedVector3Array) -> void:
	var n := path.size()
	var step := maxi(1, ceili(float(n - 1) / SHAPES))
	var k := 0
	var i := 0
	while i < n - 1 and k < SHAPES:
		var a := path[i]
		var b := path[mini(i + step, n - 1)]
		var cs := _shapes[k]
		var seg_len := a.distance_to(b)
		var to_waist := b.distance_to(path[n - 1])
		cs.disabled = seg_len < 0.01 or to_waist < 0.5 or not visible
		if not cs.disabled:
			(cs.shape as CapsuleShape3D).height = seg_len + GRAB_RADIUS * 2.0
			var y := (b - a) / seg_len
			var x := y.cross(Vector3.UP if absf(y.y) < 0.9 else Vector3.RIGHT).normalized()
			cs.transform = Transform3D(Basis(x, y, x.cross(y)), (a + b) * 0.5)
		k += 1
		i += step
	while k < SHAPES:
		_shapes[k].disabled = true
		k += 1
