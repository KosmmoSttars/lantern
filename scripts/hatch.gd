class_name Hatch
extends Node3D
## A round hatch that swings on a hinge at its rim. It is worked by hand: hold LMB on the
## handwheel in its middle (one on each face) and turn it; the latch dogs round the rim draw
## in, and the door swings open; turn it again on the open door to swing it shut and drive
## the dogs home. A small valve beside the wheel bleeds pressure across the hatch. The
## levers on the bulkhead work the same latches by motor. `locked_reason` (set by Systems)
## keeps the latches from moving while there is a pressure difference across the hatch.

signal equalize_requested

## Diameter of the door leaf (set before setup).
var size := 1.3
const OPEN_ANGLE := deg_to_rad(-100.0)

var is_open := false
var locked_reason := ""
var door: Interactable
var levers: Array[Interactable] = []
var wheels: Array[Interactable] = []
var valves: Array[Interactable] = []

## 1 = dogs driven home, 0 = drawn in.
var _latch := 1.0
var _wheel_nodes: Array[Node3D] = []
var _dog_nodes: Array[Node3D] = []
var _valve_nodes: Array[Node3D] = []

var _pivot: Node3D
var _angle := 0.0
## The keeper at the wheel when it opens: the door swings toward them, so it eases them back
## out of its way (and they watch it come) instead of passing through their head.
var _pushing: Player


## `xform`: the hatch plane is the local YZ plane, local +X points to the side
## the door swings into.
func setup(parent: Node3D, xform: Transform3D, title: String) -> void:
	name = title.replace(" ", "")
	transform = xform
	parent.add_child(self)
	_pivot = Node3D.new()
	_pivot.position = Vector3(0, 0, size * 0.5 - 0.02)
	add_child(_pivot)
	var r := size * 0.5
	door = Interactable.make(_pivot, title, "Open", _disc_shape(r), Vector3(0, 0, -r + 0.02))
	# The disc's axis along the hatch normal (X); the door itself stays unturned.
	(door.get_child(0) as CollisionShape3D).basis = Basis(Vector3.BACK, PI * 0.5)
	door.collision_layer = Layers.USE | Layers.WORLD
	door.enabled = false
	# Door leaf: a round bevelled plate with a raised boss, a round viewport, the central
	# drive hub with its handle, latch rods out to the dogs and an equalization valve, on both
	# faces.
	var plate := Geo.Builder.new()
	plate.lathe_x(PackedVector2Array([Vector2(-0.035, 0.0), Vector2(-0.035, r - 0.03), Vector2(-0.02, r), Vector2(0.02, r), Vector2(0.035, r - 0.03), Vector2(0.035, 0.0)]), 40)
	plate.lathe_x(PackedVector2Array([Vector2(-0.05, 0.0), Vector2(-0.05, r * 0.66), Vector2(-0.035, r * 0.7), Vector2(0.035, r * 0.7), Vector2(0.05, r * 0.66), Vector2(0.05, 0.0)]), 40)
	var pm := MeshInstance3D.new()
	pm.mesh = plate.commit(Looks.panel(Color(0.74, 0.75, 0.74), 0.4, 0.35, 0.7, 1.0))
	door.add_child(pm)
	var metal := Geo.Builder.new()
	metal.bevel = 0.006
	var dark := Geo.Builder.new()
	for s in [-1.0, 1.0]:
		var face: float = s * 0.05
		# Viewport ring, high on the door.
		metal.xform = Transform3D(Basis() if s > 0.0 else Basis(Vector3.UP, PI), Vector3(0, r * 0.62, 0))
		metal.lathe_x(PackedVector2Array([Vector2(0.0, 0.085), Vector2(0.03, 0.085), Vector2(0.03, 0.065), Vector2(0.0, 0.065)]), 28)
		metal.xform = Transform3D.IDENTITY
		# Drive hub, handle and four latch rods out to the dogs on the diagonals.
		var hub := Vector3(face + s * 0.02, 0, 0)
		metal.cylinder(Vector3(face, 0, 0), hub, 0.07, 18)
		dark.cylinder(hub, hub + Vector3(s * 0.015, 0, 0), 0.03, 12)
		for d: Vector3 in DOG_DIRS:
			metal.cylinder(hub + d * 0.06, Vector3(face + s * 0.012, 0, 0) + d * (r - 0.1), 0.01, 6)
		_add_wheel(title, hub + Vector3(s * 0.02, 0, 0), s)
		_add_dogs(Vector3(face + s * 0.012, 0, 0))
		_add_valve(title, Vector3(face, -r * 0.6, 0), s)
		metal.cylinder(Vector3(face, -r * 0.6, 0), Vector3(face + s * 0.03, -r * 0.6, 0), 0.03, 10)
	var mm := MeshInstance3D.new()
	mm.mesh = metal.commit(Looks.panel(Color(0.6, 0.61, 0.63), 0.25, 0.9, 0.3))
	door.add_child(mm)
	var dm := MeshInstance3D.new()
	dm.mesh = dark.commit(Looks.panel(Color(0.1, 0.1, 0.11), 0.5))
	door.add_child(dm)
	var glass := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.066
	cyl.bottom_radius = 0.066
	cyl.height = 0.075
	cyl.radial_segments = 24
	glass.mesh = cyl
	glass.material_override = Looks.glass(Color(0.4, 0.5, 0.6, 0.35))
	glass.rotation.z = PI * 0.5
	glass.position = Vector3(0, r * 0.62, 0)
	door.add_child(glass)


## The latch dogs sit on the diagonals, clear of the viewport and the valve.
const DOG_DIRS := [Vector3(0, 0.7071, 0.7071), Vector3(0, 0.7071, -0.7071), Vector3(0, -0.7071, 0.7071), Vector3(0, -0.7071, -0.7071)]


func _disc_shape(r: float) -> CylinderShape3D:
	var c := CylinderShape3D.new()
	c.radius = r
	c.height = 0.07
	return c

## The handwheel on one face: a rim on three spokes, turned by hand.
func _add_wheel(title: String, at: Vector3, s: float) -> void:
	var node := Node3D.new()
	node.position = at
	door.add_child(node)
	var b := Geo.Builder.new()
	var prof := PackedVector2Array()
	for k in 13:
		var a := TAU * k / 12.0
		prof.append(Vector2(cos(a) * 0.016 + s * 0.02, 0.15 + sin(a) * 0.016))
	b.lathe_x(prof, 28)
	for k in 3:
		var a := TAU * k / 3.0
		b.cylinder(Vector3.ZERO + Vector3(s * 0.01, 0, 0), Vector3(s * 0.02, cos(a) * 0.15, sin(a) * 0.15), 0.012, 6)
	b.cylinder(Vector3.ZERO, Vector3(s * 0.035, 0, 0), 0.03, 12)
	# A spinner knob on the rim to crank it with.
	b.cylinder(Vector3(s * 0.02, 0.15, 0), Vector3(s * 0.07, 0.15, 0), 0.014, 8)
	var mi := MeshInstance3D.new()
	mi.mesh = b.commit(Looks.panel(Color(0.85, 0.66, 0.16), 0.4))
	node.add_child(mi)
	_wheel_nodes.append(node)
	var it := Interactable.make(door, title + " handwheel", "Turn", Kit.box_shape(Vector3(0.1, 0.34, 0.34)), at + Vector3(s * 0.02, 0, 0))
	it.hold_time = 1.3
	it.set_meta("work_sound", "servo")
	it.verb_fn = func() -> String: return "Turn to close" if is_open else "Turn to open"
	it.on_use = toggle
	wheels.append(it)


## The four latch dogs round the rim on one face; they slide in when the wheel turns, and out
## past the rim into the frame when it is shut.
func _add_dogs(center: Vector3) -> void:
	var node := Node3D.new()
	node.position = center
	door.add_child(node)
	for d: Vector3 in DOG_DIRS:
		var m := MeshInstance3D.new()
		m.mesh = Kit.box(Vector3(0.025, 0.05, 0.05))
		m.material_override = Looks.panel(Color(0.6, 0.61, 0.63), 0.25, 0.9, 0.3)
		m.position = d * (size * 0.5 - 0.03)
		m.set_meta("dir", d)
		node.add_child(m)
	_dog_nodes.append(node)


## The pressure equalization valve on one face: a small quarter-turn handle.
func _add_valve(title: String, at: Vector3, s: float) -> void:
	var node := Node3D.new()
	node.position = at + Vector3(s * 0.035, 0, 0)
	door.add_child(node)
	var m := MeshInstance3D.new()
	m.mesh = Kit.box(Vector3(0.014, 0.1, 0.022))
	m.material_override = Looks.panel(Color(0.85, 0.66, 0.16), 0.4)
	node.add_child(m)
	_valve_nodes.append(node)
	var it := Interactable.make(door, title + " equalization valve", "Equalize pressure", Kit.box_shape(Vector3(0.08, 0.13, 0.13)), at + Vector3(s * 0.03, 0, 0))
	it.hold_time = 1.0
	it.set_meta("work_sound", "hiss")
	it.on_use = func() -> void:
		Sfx.play_at("airflow", it.global_position, -4.0)
		equalize_requested.emit()
	valves.append(it)


## A hatch lever on the bulkhead beside the opening, `x` along the hatch normal
## (negative = the side the door does not swing into).
func add_lever(x: float) -> Interactable:
	var facing := signf(x)
	var it := Interactable.make(self, door.display_name + " lever", "Open", Kit.box_shape(Vector3(0.12, 0.26, 0.14)), Vector3(x, 0.0, -size * 0.5 - 0.2))
	it.verb_fn = func() -> String: return "Close" if is_open else "Open"
	it.on_use = toggle
	var b := Geo.Builder.new()
	b.box(Vector3(-facing * 0.02, 0, 0), Vector3(0.03, 0.24, 0.12))
	var base := MeshInstance3D.new()
	base.mesh = b.commit(Looks.panel(Color(0.25, 0.26, 0.27), 0.5, 0.3))
	it.add_child(base)
	var h := Geo.Builder.new()
	h.cylinder(Vector3(0, -0.07, 0), Vector3(facing * 0.06, -0.07, 0), 0.012, 8)
	h.cylinder(Vector3(0, 0.07, 0), Vector3(facing * 0.06, 0.07, 0), 0.012, 8)
	h.cylinder(Vector3(facing * 0.06, -0.08, 0), Vector3(facing * 0.06, 0.08, 0), 0.016, 8)
	var hm := MeshInstance3D.new()
	hm.mesh = h.commit(Looks.panel(Color(0.85, 0.66, 0.16), 0.4))
	it.add_child(hm)
	levers.append(it)
	return it


func toggle() -> void:
	if locked_reason != "":
		Sfx.play_at("error", door.global_position, -6.0)
		return
	is_open = not is_open
	if is_open and is_inside_tree():
		var p := get_tree().get_first_node_in_group("player") as Player
		if p and _in_swing(p):
			p.let_go()
			_pushing = p
	Sfx.play_at("servo", door.global_position, -2.0)


## Is the keeper's head where the door leaf sweeps as it opens?
func _in_swing(p: Player) -> bool:
	var rel := p.cam.global_position - global_position
	var nx := global_basis.x.normalized()
	var along := rel.dot(nx)
	var side := (rel - nx * along).length()
	return along > -0.05 and along < size + 0.25 and side < size * 0.5 + 0.4


func _ease_back(p: Player) -> void:
	if not is_instance_valid(p) or p.anchored or not is_open:
		_pushing = null
		return
	var nx := global_basis.x.normalized()
	var v_along := p.velocity.dot(nx)
	if _in_swing(p):
		p.velocity += nx * (maxf(v_along, 0.7) - v_along)
	else:
		p.velocity -= nx * maxf(v_along - 0.1, 0.0)
		_pushing = null


func _physics_process(delta: float) -> void:
	for it in wheels + levers:
		it.enabled = locked_reason == ""
		it.disabled_hint = locked_reason
	door.disabled_hint = locked_reason if locked_reason != "" else "Turn the handwheel"
	var pressure_held := locked_reason.contains("ressur")
	for v in valves:
		v.enabled = pressure_held
		v.disabled_hint = "Pressure is equal on both sides"
	# The wheel turns with the work on it; the dogs follow it in, or home again once shut.
	var turning := 0.0
	for w in wheels:
		turning = maxf(turning, w.progress)
	for n in _wheel_nodes:
		n.rotation.x = turning * TAU * 1.25 * (1.0 if is_open else -1.0)
	var target := OPEN_ANGLE if is_open else 0.0
	if _pushing:
		_ease_back(_pushing)
	_angle = move_toward(_angle, target, delta * 1.4)
	_pivot.rotation.y = _angle
	var want := 0.0 if is_open else (1.0 if absf(_angle) < 0.02 else 0.0)
	if not is_open and turning > 0.0:
		want = 1.0 - turning
	_latch = move_toward(_latch, want, delta * 3.0)
	for n in _dog_nodes:
		for m in n.get_children():
			m.position = (m.get_meta("dir") as Vector3) * lerpf(size * 0.5 - 0.11, size * 0.5 - 0.03, _latch)
	for n in _valve_nodes:
		var vp := 0.0
		for v in valves:
			vp = maxf(vp, v.progress)
		n.rotation.x = vp * PI * 0.5
