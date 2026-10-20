class_name Habitat
extends RefCounted
## The fittings of the habitation module that keep the keeper alive: the galley (rations and
## water), the medical locker and its screen, and the sleeping bag.

var station: Station
var sim: ShipSim
var body: Body
var bunk: Interactable
var med_screen: Terminal
## Set by main: what using each fitting does.
var on_eat: Callable
var on_drink: Callable
var on_pill: Callable
var on_sleep: Callable


func build(p_station: Station, p_sim: ShipSim, p_body: Body) -> void:
	station = p_station
	sim = p_sim
	body = p_body
	_galley()
	_medical()
	_bunk()


func _galley() -> void:
	var p := ControlPanel.make(station, sim, "GALLEY", Vector2(1.5, 0.9), station.face_xform(6, -5.95), Callable())
	station.panels["galley"] = p
	p.button("RATION", 0.2, 0.3, func() -> void: on_eat.call(), func() -> bool: return sim.food > 0, Ctl.GREEN)
	p.digits("PACKS LEFT", 0.2, 0.52, func() -> String: return "%4d" % sim.food)
	p.button("WATER", 0.5, 0.3, func() -> void: on_drink.call(), func() -> bool: return sim.water > 1.0, Ctl.WHITE)
	p.digits("TANK kg", 0.5, 0.52, func() -> String: return "%6d" % roundi(sim.water))
	# Rack of ration packs and a water bag behind a net.
	var rack := Geo.Builder.new()
	for k in 6:
		rack.box(p.at(0.95 + (k % 3) * 0.16, 0.3 + (k / 3) * 0.24) + Vector3(0, 0, 0.05), Vector3(0.13, 0.2, 0.09))
	Kit.mesh(p, rack.commit(Kit.matte(Color(0.75, 0.55, 0.28), 0.8)), null)
	var net := Geo.Builder.new()
	for k in 7:
		net.box(p.at(0.86 + k * 0.08, 0.42) + Vector3(0, 0, 0.1), Vector3(0.004, 0.55, 0.004))
	for k in 5:
		net.box(p.at(1.1, 0.17 + k * 0.12) + Vector3(0, 0, 0.1), Vector3(0.5, 0.004, 0.004))
	Kit.mesh(p, net.commit(Kit.matte(Color(0.15, 0.15, 0.15), 0.9)), null)
	Ctl.text(p, "Eat when hungry. Drink often.", p.at(0.35, 0.78), 0.011)


func _medical() -> void:
	var p := ControlPanel.make(station, sim, "MEDICAL", Vector2(1.5, 0.9), station.face_xform(2, -5.95), Callable())
	station.panels["medical"] = p
	p.button("RAD PILL", 0.18, 0.3, func() -> void: on_pill.call(), func() -> bool: return sim.pills > 0, Ctl.AMBER)
	p.digits("PILLS", 0.18, 0.52, func() -> String: return "%3d" % sim.pills)
	p.digits("DOSE mSv", 0.18, 0.72, func() -> String: return "%6d" % roundi(body.dose), Ctl.RED)
	med_screen = p.crt(0.95, 0.47, 0.9, 0.7, 14, 460.0)


func refresh() -> void:
	var l := PackedStringArray()
	l.append("KEEPER")
	l.append("HEALTH   " + _bar(body.health))
	l.append("FED      " + _bar(1.0 - body.hunger))
	l.append("WATER    " + _bar(1.0 - body.thirst))
	l.append("RESTED   " + _bar(1.0 - body.fatigue))
	l.append("FITNESS  " + _bar(body.fitness))
	l.append("")
	l.append("DOSE %6d mSv  %s" % [roundi(body.dose), "SICK" if body.sickness > 0.05 else ""])
	var c := body.complaints()
	l.append(", ".join(c) if not c.is_empty() else "NO COMPLAINTS")
	med_screen.text = "\n".join(l)


static func _bar(f: float) -> String:
	var n := 16
	var k := clampi(roundi(f * n), 0, n)
	return "[" + "#".repeat(k) + ".".repeat(n - k) + "]"


func _bunk() -> void:
	# A sleeping bag strapped flat to the starboard wall, a reading lamp over it.
	var xf := station.face_xform(2, -4.25)
	var root := Node3D.new()
	root.transform = xf
	station.add_child(root)
	var bag := Geo.Builder.new()
	bag.bevel = 0.04
	bag.box(Vector3(0, 0, 0.08), Vector3(1.55, 0.44, 0.14))
	bag.box(Vector3(-0.6, 0, 0.15), Vector3(0.28, 0.32, 0.05))
	Kit.mesh(root, bag.commit(Kit.matte(Color(0.2, 0.32, 0.5), 0.95)), null)
	var straps := Geo.Builder.new()
	for k in 3:
		straps.box(Vector3(-0.35 + k * 0.45, 0, 0.155), Vector3(0.05, 0.48, 0.012))
	Kit.mesh(root, straps.commit(Kit.matte(Color(0.1, 0.1, 0.1), 0.9)), null)
	var lamp := OmniLight3D.new()
	lamp.light_cull_mask = Station.INSIDE_LAYER
	lamp.light_color = Color(1.0, 0.8, 0.55)
	lamp.light_energy = 0.4
	lamp.omni_range = 1.4
	lamp.position = Vector3(-0.8, 0.35, 0.3)
	root.add_child(lamp)
	# On the cabin circuit: the light switch puts it out with the rest.
	station.lights.append(lamp)
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.55, 0.5, 0.26)
	bunk = Interactable.make(root, "Sleeping bag", "Sleep", shape, Vector3(0, 0, 0.12))
	bunk.on_use = func() -> void: on_sleep.call()
	bunk.verb_fn = func() -> String: return "Sleep" if body.can_sleep() else ""
	bunk.value_fn = func() -> String: return "tired" if body.can_sleep() else "not tired yet"

