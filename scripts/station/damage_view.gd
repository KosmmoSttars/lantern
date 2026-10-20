class_name DamageView
extends RefCounted
## Damage made visible and mendable: each hull breach is a torn dark hole hissing air, patched
## by holding LMB on it (one kit); each broken part outside wears a blinking red beacon and is
## mended by holding LMB on it on a spacewalk.

const PATCH_TIME := 4.0
const REPAIR_TIME := 6.0

var station: Station
var sim: ShipSim
var damage: Damage
## Set by main: a message to the keeper.
var toast: Callable

var _breach_nodes := {}
var _part_nodes := {}
var _blink := 0.0


func build(p_station: Station, p_sim: ShipSim, p_damage: Damage) -> void:
	station = p_station
	sim = p_sim
	damage = p_damage
	damage.changed.connect(sync)
	sync()


## Where a broken part is mended from, outside (station frame).
func part_spot(part: String) -> Vector3:
	var node_z: float = (Station.SPINE["Node"][0] + Station.SPINE["Node"][1]) * 0.5
	match part:
		"dish":
			return Vector3(0, -Station.A - 2.2, node_z)
		"wing_0":
			return Vector3(-Station.WING_X0 - 0.6, Station.WING_Y + 0.3, Station.WING_Z)
		"wing_1":
			return Vector3(Station.WING_X0 + 0.6, Station.WING_Y + 0.3, Station.WING_Z)
	var k := int(part.substr(9))
	var sy := -1.0 if k < 2 else 1.0
	var lz: float = (float(Station.SPINE["Life support"][0]) + float(Station.SPINE["Life support"][1])) * 0.5
	return Vector3(0.1, sy * (Station.A + Station.HULL + 1.4), lz - Station.RAD_W * 0.55 + (k % 2) * Station.RAD_W * 1.1)


func sync() -> void:
	# Breaches.
	var want := {}
	for b: Dictionary in damage.breaches:
		want[int(b.id)] = b
	for id: int in _breach_nodes.keys():
		if not want.has(id):
			(_breach_nodes[id] as Node).queue_free()
			_breach_nodes.erase(id)
	for id: int in want:
		if not _breach_nodes.has(id):
			_breach_nodes[id] = _make_breach(want[id])
	# Broken parts.
	for part: String in _part_nodes.keys():
		if not damage.is_broken(part):
			(_part_nodes[part] as Node).queue_free()
			_part_nodes.erase(part)
	for part: String in Damage.PARTS:
		if damage.is_broken(part) and not _part_nodes.has(part):
			_part_nodes[part] = _make_part(part)


func _make_breach(b: Dictionary) -> Node3D:
	var root := Node3D.new()
	var n: Vector3 = b.normal
	root.transform = Transform3D(Basis.looking_at(-n, Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT), b.pos + n * 0.035)
	station.add_child(root)
	# A torn, blackened hole: a dark disc, a ragged rim of bent metal petals.
	Kit.mesh(root, Kit.cylinder(0.07, 0.01, 12), Kit.matte(Color(0.02, 0.02, 0.02), 1.0), Vector3.ZERO, Basis(Vector3.RIGHT, PI / 2.0))
	var petals := Geo.Builder.new()
	for k in 7:
		var a := TAU * k / 7.0 + randf() * 0.4
		petals.box(Vector3(cos(a), sin(a), 0.0) * 0.085 + Vector3(0, 0, 0.012), Vector3(0.05, 0.02, 0.008), Basis(Vector3.BACK, a))
	Kit.mesh(root, petals.commit(Kit.metal(Color(0.5, 0.48, 0.45), 0.5, 0.7)), null)
	var scorch := Kit.mesh(root, Kit.cylinder(0.16, 0.002, 16), Kit.matte(Color(0.12, 0.1, 0.08), 1.0), Vector3(0, 0, -0.004), Basis(Vector3.RIGHT, PI / 2.0))
	scorch.transparency = 0.4
	var hiss := Sfx.attach("hiss", root, -4.0, 2.5)
	hiss.name = "Hiss"
	var shape := SphereShape3D.new()
	shape.radius = 0.16
	var it := Interactable.make(root, "Hull breach", "Patch", shape)
	it.hold_time = PATCH_TIME
	it.keep_progress = true
	it.set_meta("work_sound", "spray")
	it.value_fn = func() -> String: return "leaking  -  %d patch kits" % sim.patches
	it.disabled_hint = "No patch kits"
	var id: int = b.id
	it.on_use = func() -> void:
		if sim.patches <= 0:
			toast.call("No patch kits left")
			return
		sim.patches -= 1
		damage.patch(id)
		toast.call("Breach patched  (%d kits left)" % sim.patches)
	root.set_meta("it", it)
	return root


func _make_part(part: String) -> Node3D:
	var root := Node3D.new()
	root.position = part_spot(part)
	station.add_child(root)
	var beacon := OmniLight3D.new()
	beacon.light_color = Color(1.0, 0.15, 0.1)
	beacon.light_energy = 1.5
	beacon.omni_range = 3.0
	root.add_child(beacon)
	Kit.mesh(root, Kit.sphere(0.06, 8), Kit.glow(Color(1.0, 0.2, 0.1), 3.0))
	# Torn wiring and a cracked housing to work on.
	var b := Geo.Builder.new()
	b.box(Vector3(0, 0, 0.1), Vector3(0.35, 0.25, 0.12))
	for k in 4:
		b.cylinder(Vector3(0.1 - k * 0.06, 0.12, 0.1), Vector3(0.14 - k * 0.07, 0.3 + k * 0.03, 0.18), 0.008, 5)
	Kit.mesh(root, b.commit(Kit.matte(Color(0.3, 0.3, 0.32), 0.7)), null)
	var shape := SphereShape3D.new()
	shape.radius = 0.35
	var it := Interactable.make(root, "Broken %s" % Damage.PART_NAMES[part], "Repair", shape, Vector3(0, 0, 0.1))
	it.hold_time = REPAIR_TIME
	it.keep_progress = true
	it.set_meta("work_sound", "servo")
	it.on_use = func() -> void:
		damage.repair(part)
		toast.call("%s repaired" % String(Damage.PART_NAMES[part]).capitalize())
	root.set_meta("beacon", beacon)
	return root


func update(delta: float) -> void:
	_blink += delta
	for part: String in _part_nodes:
		var bl: OmniLight3D = (_part_nodes[part] as Node3D).get_meta("beacon")
		bl.light_energy = 1.5 if fmod(_blink, 1.0) < 0.5 else 0.1
	for id: int in _breach_nodes:
		var it: Interactable = (_breach_nodes[id] as Node3D).get_meta("it")
		it.enabled = sim.patches > 0


## A random spot on a module wall for a new breach: [module, position, normal into the cabin].
func random_spot(rng: RandomNumberGenerator) -> Array:
	# Only modules still aboard: a hole in one cast off would leak for ever, out of reach.
	var spine := ["Command deck", "Engineering", "Node", "Habitation", "Life support"].filter(func(k: String) -> bool: return not station.gone.has(k))
	var m: String = spine[rng.randi() % spine.size()]
	var z0: float = Station.SPINE[m][0]
	var z1: float = Station.SPINE[m][1]
	# The diagonal faces carry no windows or panels in the middle of their span.
	var i: int = [1, 3, 5, 7][rng.randi() % 4]
	var z := rng.randf_range(z0 + 0.6, z1 - 0.6)
	var xf := station.face_xform(i, z, rng.randf_range(-0.3, 0.3), 0.0)
	return [m, xf.origin, xf.basis.z]
