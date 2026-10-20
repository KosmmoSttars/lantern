class_name DerelictView
extends Node3D
## The derelict the station is near, drawn for real: an old module, its foil faded and
## scorched, a broken solar wing, cold inside but for a red emergency lamp blinking, the things
## its crew left strapped to its walls. It hangs where its orbit puts it, turning slowly; the
## DOCKING PORT panel docks it: it comes in to the port off the Node (or the far end of the
## modules docked there) and stays. It is airless: PRESSURIZE it from the tanks
## until the port hatch will open. Hold LMB on a thing to take it into the station's stores.
## Undocked, it drifts back off to its own orbit, and its air goes with it.
##
## A whole module (kind "module") comes in the same way, sealed and lit, and once it is home it
## is part of the station for good (main hands it to PortModules).

## How near a derelict must be to be drawn, and to dock (m).
const SHOW_RANGE := 4000.0
const DOCK_RANGE := 300.0
const DOCK_TIME := 18.0
const UNDOCK_TIME := 40.0
## The module: inside radius, outside radius (m); its length comes from its seed.
const R_IN := 0.95
const R_OUT := 1.08
const COLLAR := 0.35

var flight: Flight
var sim: ShipSim
var salvage: Salvage
var player: Player
var station: Station
var toast: Callable
## Called when a whole module has come home at the port (main: it is the station's now).
var module_docked: Callable
## Called when the derelict lets go with the keeper still inside (main: the umbilical tears
## loose, they are on the belt's bottle now).
var carried_off: Callable

## The derelict shown (body index), -1 for none.
var shown := -1
var model: Node3D
var length := 4.0
## Docking (0..1 along the way in), and the pose it started from; undocking the same back out.
var _dock_s := -1.0
var _undock_s := -1.0
var _from := Transform3D()
var _lamp: OmniLight3D
var _items := {}


func setup(p_flight: Flight, p_sim: ShipSim, p_salvage: Salvage, p_player: Player, p_station: Station) -> void:
	flight = p_flight
	sim = p_sim
	salvage = p_salvage
	player = p_player
	station = p_station
	name = "DerelictView"
	if salvage.docked >= 0 and salvage.docked < flight.u.bodies.size() and flight.u.bodies[salvage.docked].kind == "derelict":
		_show(salvage.docked)
		flight.docked = true
		model.transform = dock_pose()
		sim.port_vol = volume()
		sim.port_p = salvage.air
	else:
		salvage.docked = -1
		salvage.air = 0.0


## Where the docked module sits: its collar on the docking port's outer face, its axis out
## along -X from the Node.
func dock_pose() -> Transform3D:
	return station.port_xform()


## The air space inside the derelict shown (m3).
func volume() -> float:
	return PI * R_IN * R_IN * length


## The derelict's own pose, station frame: where its orbit has it, turning slowly.
func free_pose(b: int) -> Transform3D:
	var u := flight.u
	var rel := Orbit.to_vec(Orbit.sub(u.position(b, flight.t), flight.world_pos()))
	var inv := flight.att.inverse()
	var seed_a := float(int(u.bodies[b].get("loot_seed", 1)) % 1000) * 0.0063
	var turn := Basis(Vector3(0.3, 1.0, 0.2).normalized(), seed_a + flight.t * 0.01) * Basis(Vector3.RIGHT, seed_a * 2.0)
	return Transform3D(inv * turn, inv * rel)


## The nearest derelict within range, or -1.
func nearest(max_range: float) -> int:
	var u := flight.u
	var best := -1
	var best_d := max_range
	var me := flight.world_pos()
	for i in u.bodies.size():
		if not u.bodies[i].kind in ["derelict", "module"] or u.bodies[i].get("gone", false):
			continue
		var d := Orbit.length(Orbit.sub(u.position(i, flight.t), me))
		if d < best_d:
			best_d = d
			best = i
	return best


func is_docked() -> bool:
	return salvage.docked >= 0 and _dock_s < 0.0


## Why docking cannot start now ("" when it can).
func dock_blocker() -> String:
	if station.gone.has("Dock"):
		return "NO DOCKING PORT"
	if salvage.docked >= 0 or _dock_s >= 0.0:
		return "ALREADY DOCKED"
	if not flight.transit.is_empty():
		return "NOT DURING A TRANSIT"
	if sim.port_open:
		return "SHUT THE PORT HATCH"
	if nearest(DOCK_RANGE) < 0:
		return "NOTHING IN RANGE"
	return ""


func dock() -> String:
	var why := dock_blocker()
	if why != "":
		return why
	var b := nearest(DOCK_RANGE)
	_show(b)
	_from = free_pose(b)
	_dock_s = 0.0
	salvage.docked = b
	flight.docked = true
	return ""


## Undocking is the keeper's call, but never with the port hatch open (the port would be left
## open to space); anyone still in the derelict behind a shut hatch goes with it.
func undock_blocker() -> String:
	if salvage.docked < 0 or _dock_s >= 0.0:
		return "NOTHING DOCKED"
	if sim.port_open:
		return "SHUT THE PORT HATCH FIRST"
	return ""


func undock() -> String:
	var why := undock_blocker()
	if why != "":
		return why
	_undock_s = 0.0
	salvage.docked = -1
	flight.docked = false
	# Its hatchway has no hatch of its own: whatever air it was given goes as it lets go.
	if sim.port_p > 5.0:
		Sfx.play("hiss", -6.0, 0.7, "Station")
	salvage.air = 0.0
	sim.port_vol = 0.0
	sim.port_p = 0.0
	if aboard(player.global_position) and carried_off.is_valid():
		carried_off.call()
	return ""


## Is point p (station frame) inside the docked module?
func aboard(p: Vector3) -> bool:
	if model == null or not model.visible or _module_kind() != "":
		return false
	var l := model.transform.affine_inverse() * p
	return l.x > 0.0 and l.x < COLLAR + length + 0.2 and Vector2(l.y, l.z).length() < R_OUT + 0.3


func _process(delta: float) -> void:
	if flight == null:
		return
	# Whoever is inside goes where the module goes.
	var before := model.transform if model else Transform3D()
	var riding := model != null and aboard(player.global_position)
	_move(delta)
	if riding and salvage.docked < 0 and carried_off.is_valid():
		carried_off.call()
	if riding and model != null and not model.transform.is_equal_approx(before):
		var carry := model.transform * before.affine_inverse()
		player.global_position = carry * player.global_position
		if player.anchored:
			player.anchor = carry * player.anchor
	# The emergency lamp, blinking on its last power.
	if _lamp:
		_lamp.light_energy = 0.55 if fmod(Time.get_ticks_msec() / 1000.0, 2.2) < 0.25 else 0.08


func _move(delta: float) -> void:
	if salvage.docked >= 0:
		if shown != salvage.docked:
			_show(salvage.docked)
		if _dock_s >= 0.0:
			_dock_s = minf(_dock_s + delta / DOCK_TIME, 1.0)
			var k := smoothstep(0.0, 1.0, _dock_s)
			_from = free_pose(shown) if _dock_s < 0.02 else _from
			model.transform = _from.interpolate_with(dock_pose(), k)
			if _dock_s >= 1.0:
				_dock_s = -1.0
				Sfx.play("clunk", -2.0, 0.6, "Station")
				Sfx.play("latch", -4.0, 0.8, "Station")
				if _module_kind() != "":
					# A whole module: home for good. The station builds it where it now sits.
					var b := shown
					salvage.docked = -1
					flight.docked = false
					_show(-1)
					if module_docked.is_valid():
						module_docked.call(b)
					return
				sim.port_vol = volume()
				sim.port_p = salvage.air
				if toast.is_valid():
					toast.call("Docked: %s. It is airless: PRESSURIZE it from the DOCKING PORT panel before the port hatch will open." % flight.u.bodies[shown].name)
		else:
			model.transform = dock_pose()
			salvage.air = sim.port_p
	elif _undock_s >= 0.0 and shown >= 0:
		_undock_s = minf(_undock_s + delta / UNDOCK_TIME, 1.0)
		model.transform = dock_pose().interpolate_with(free_pose(shown), smoothstep(0.0, 1.0, _undock_s))
		if _undock_s >= 1.0:
			_undock_s = -1.0
	else:
		var b := nearest(SHOW_RANGE)
		if b != shown:
			_show(b)
		if shown >= 0:
			model.transform = free_pose(shown)


# --- Building it --------------------------------------------------------------------------------

func _show(b: int) -> void:
	if model:
		model.queue_free()
		model = null
	_lamp = null
	_items.clear()
	shown = b
	if b < 0:
		return
	var body := flight.u.bodies[b]
	var rng := RandomNumberGenerator.new()
	rng.seed = int(body.get("loot_seed", b))
	length = rng.randf_range(3.4, 4.4)
	model = Node3D.new()
	model.name = "Derelict"
	add_child(model)
	if body.kind == "module":
		_module_look(String(body.get("class", "GREENHOUSE")))
		return
	_hull(rng)
	_inside(rng)
	_loot(b)


## The kind of whole module shown ("" for a derelict or nothing).
func _module_kind() -> String:
	if shown < 0 or shown >= flight.u.bodies.size() or flight.u.bodies[shown].kind != "module":
		return ""
	return String(flight.u.bodies[shown].get("class", "GREENHOUSE"))


## A whole module in orbit: sealed, its foil clean, a green beacon blinking, as it will look
## once docked (the same round hull, berthing ring, handrails and fittings outside).
func _module_look(kind: String) -> void:
	length = PortModules.length_of(kind)
	var r := Station.A + Station.HULL
	var x1 := length + Station.END_T
	var shell := Geo.Builder.new()
	shell.tube_x(r, 0.0, x1, 48, false, 0.6)
	shell.ring_x(x1, Geo.circle(r), Geo.circle(0.0), 1.0, 48)
	shell.ring_x(0.0, Geo.circle(r), Geo.circle(Station.HOLE + 0.08), -1.0, 48)
	Kit.mesh(model, shell.commit(Looks.mli(Color(0.86, 0.85, 0.8))), null)
	var metal := Geo.Builder.new()
	# The berthing ring at the docking end, its hatch shut behind it, and bands round the hull.
	metal.tube_x(Station.HOLE + 0.08, -0.02, 0.06, 32, false)
	metal.ring_x(-0.02, Geo.circle(Station.HOLE + 0.14), Geo.circle(0.0), -1.0, 32)
	for bx in [0.08, x1 - 0.08]:
		metal.tube_x(r + 0.035, bx - 0.07, bx + 0.07, 48, false)
	for i in [1, 4, 7]:
		var th: float = -PI / 2.0 + PI / 4.0 * i
		# Station frame face i (cos, sin) is the module's (-z, y).
		var d := Vector3(0, sin(th), -cos(th))
		var tng := Vector3(0, cos(th), sin(th))
		for s in [-0.22, 0.22]:
			var base: Vector3 = d * (r + 0.11) + tng * s
			metal.cylinder(base + Vector3(0.35, 0, 0), base + Vector3(length - 0.2, 0, 0), 0.018, 6)
	Kit.mesh(model, metal.commit(Kit.metal(Color(0.5, 0.5, 0.52), 0.45, 0.7)), null)
	# Its windows, dark from outside.
	var glass := Geo.Builder.new()
	var w: Dictionary = PortModules.WINDOWS.get(kind, {})
	for i: int in w:
		var th: float = -PI / 2.0 + PI / 4.0 * i
		var d := Vector3(0, sin(th), -cos(th))
		var tng := Vector3(0, cos(th), sin(th))
		for h: Array in w[i]:
			var c := Vector3((float(h[2]) + float(h[3])) * 0.5, 0, 0) + d * (r + 0.004) + tng * (float(h[0]) + float(h[1])) * 0.5
			glass.box(c, Vector3(float(h[3]) - float(h[2]), float(h[1]) - float(h[0]), 0.006), Basis(Vector3(1, 0, 0), tng, d))
	if not glass.is_empty():
		Kit.mesh(model, glass.commit(Kit.metal(Color(0.04, 0.05, 0.07), 0.08, 0.9)), null)
	PortModules.exterior(model, kind, length)
	_lamp = OmniLight3D.new()
	_lamp.light_color = Color(0.3, 1.0, 0.4)
	_lamp.omni_range = 3.0
	_lamp.light_energy = 0.3
	_lamp.position = Vector3(length * 0.5, r + 0.12, 0)
	model.add_child(_lamp)
	Kit.mesh(model, Kit.box(Vector3(0.08, 0.04, 0.08)), Kit.glow(Color(0.3, 1.0, 0.4), 0.8), Vector3(length * 0.5, r + 0.02, 0))
	var solid := StaticBody3D.new()
	solid.collision_layer = Layers.WORLD
	solid.collision_mask = 0
	model.add_child(solid)
	var shape_b := Geo.Builder.new()
	shape_b.tube_x(r, 0.0, x1, 28, false)
	shape_b.ring_x(x1, Geo.circle(r), Geo.circle(0.0), 1.0, 28)
	shape_b.ring_x(0.0, Geo.circle(r), Geo.circle(0.0), -1.0, 28)
	Kit.collider(solid, shape_b.shape())


func _hull(rng: RandomNumberGenerator) -> void:
	var x0 := COLLAR
	var x1 := COLLAR + length
	var foil := Looks.mli([Color(0.86, 0.85, 0.8), Color(0.82, 0.68, 0.38), Color(0.62, 0.63, 0.62)][rng.randi() % 3])
	var shell := Geo.Builder.new()
	shell.tube_x(R_OUT, x0, x1, 32, false, 0.6)
	shell.ring_x(x1, Geo.circle(R_OUT), Geo.circle(0.0), 1.0, 32)
	shell.ring_x(x0, Geo.circle(R_OUT), Geo.circle(0.45), -1.0, 32)
	Kit.mesh(model, shell.commit(foil), null)
	var metal := Geo.Builder.new()
	# The docking collar and its ring, bands round the hull, an antenna, handrails.
	metal.tube_x(0.55, 0.0, x0, 24, false)
	metal.ring_x(0.0, Geo.circle(0.62), Geo.circle(0.45), -1.0, 24)
	metal.tube_x(0.45, 0.0, x0 + 0.13, 24, true)
	for k in 3:
		var bx := x0 + 0.2 + k * (length - 0.4) / 2.0
		metal.tube_x(R_OUT + 0.02, bx - 0.04, bx + 0.04, 32, false)
	metal.cylinder(Vector3(x1 - 0.6, R_OUT, 0), Vector3(x1 - 0.6, R_OUT + 1.2, 0.2), 0.015, 6)
	metal.cylinder(Vector3(x1 - 0.6, R_OUT + 1.2, 0.2), Vector3(x1 - 0.5, R_OUT + 1.2, 0.2), 0.05, 8)
	for side in [-1.0, 1.0]:
		metal.cylinder(Vector3(x0 + 0.5, 0, side * (R_OUT + 0.07)), Vector3(x1 - 0.5, 0, side * (R_OUT + 0.07)), 0.014, 6)
	Kit.mesh(model, metal.commit(Kit.metal(Color(0.5, 0.5, 0.52), 0.45, 0.7)), null)
	# Scorch and grime on the foil.
	var scorch := Geo.Builder.new()
	for k in 4:
		var a := rng.randf() * TAU
		var x := rng.randf_range(x0 + 0.3, x1 - 0.3)
		var d := Vector3(0, cos(a), sin(a))
		scorch.box(Vector3(x, 0, 0) + d * (R_OUT + 0.004), Vector3(rng.randf_range(0.3, 0.9), 0.006, rng.randf_range(0.2, 0.5)), Basis(Vector3.RIGHT, a))
	Kit.mesh(model, scorch.commit(Kit.matte(Color(0.12, 0.1, 0.09), 0.9)), null)
	# One solar wing, broken off half way and bent.
	var wing := Node3D.new()
	wing.position = Vector3(x0 + length * 0.5, -R_OUT, 0)
	wing.rotation = Vector3(0.2, 0.0, -0.5 + rng.randf_range(-0.3, 0.3))
	model.add_child(wing)
	Kit.mesh(wing, Kit.box(Vector3(1.2, 0.03, 2.4)), Looks.solar(), Vector3(0, -0.8, 0))
	Kit.mesh(wing, Kit.cylinder(0.03, 0.8, 6), Kit.metal(Color(0.5, 0.5, 0.52)), Vector3(0, -0.4, 0))


## Inside: a cold tube, ribs, a dead panel, the red lamp, and walls the hand can hold.
func _inside(rng: RandomNumberGenerator) -> void:
	var x0 := COLLAR
	var x1 := COLLAR + length
	var walls := Geo.Builder.new()
	walls.tube_x(R_IN, x0, x1, 28, true, 1.4)
	walls.ring_x(x1 - 0.002, Geo.circle(R_IN), Geo.circle(0.0), -1.0, 28)
	walls.ring_x(x0 + 0.002, Geo.circle(R_IN), Geo.circle(0.45), 1.0, 28)
	Kit.mesh(model, walls.commit(Looks.panel(Color(0.36, 0.37, 0.37), 0.7)), null)
	var ribs := Geo.Builder.new()
	var x := x0 + 0.6
	while x < x1 - 0.3:
		var ring := PackedVector3Array()
		for k in 29:
			var a := TAU * k / 28.0
			ring.append(Vector3(x, cos(a) * (R_IN - 0.02), sin(a) * (R_IN - 0.02)))
		ribs.sweep(ring, 0.025, 6)
		x += 0.9
	# A dead control panel and a strip light that has gone out.
	ribs.box(Vector3(x0 + length * 0.5, R_IN - 0.06, 0), Vector3(0.9, 0.04, 0.08))
	Kit.mesh(model, ribs.commit(Kit.metal(Color(0.42, 0.42, 0.44), 0.5, 0.6)), null)
	var a2 := PI * 0.5
	var panel_at := Vector3(x0 + length * 0.55, cos(a2) * (R_IN - 0.03), sin(a2) * (R_IN - 0.03))
	Kit.mesh(model, Kit.box(Vector3(0.6, 0.4, 0.04)), Kit.matte(Color(0.08, 0.08, 0.09), 0.6), panel_at, Basis(Vector3.RIGHT, a2 + PI) * Basis(Vector3.RIGHT, -PI / 2.0))
	_lamp = OmniLight3D.new()
	_lamp.light_color = Color(1.0, 0.15, 0.08)
	_lamp.omni_range = 4.5
	_lamp.light_energy = 0.3
	_lamp.position = Vector3(x0 + length * 0.4, R_IN - 0.1, 0)
	model.add_child(_lamp)
	Kit.mesh(model, Kit.box(Vector3(0.1, 0.03, 0.06)), Kit.glow(Color(1.0, 0.15, 0.08), 0.8), _lamp.position + Vector3(0, 0.07, 0))
	# An old poster by the hatch, faded by years of sun through the open hatchway.
	var pa := PI
	var pout := Vector3(0, cos(pa), sin(pa))
	var pz := -pout
	var py := pz.cross(Vector3.RIGHT).normalized()
	var pxf := Transform3D(Basis(Vector3.RIGHT, py, pz), Vector3(x0 + 0.45, 0, 0) + pout * (R_IN - 0.01))
	var line: Array = [["LAST ONE OUT", "Lights off. Oxygen off.\nHatch open for the next crew."], ["KEEP THIS MODULE TIDY", "Everything strapped down.\nEverything."], ["CREW OF FOUR", "Back by Christmas.\nWe promise."]][rng.randi() % 3]
	Posters.make(model, pxf, "NOTICE" if rng.randf() < 0.5 else "CAUTION", String(line[0]), String(line[1]), "warn", true, rng.randf_range(-0.12, 0.12))
	# The walls, inside and out, are something to hold on to.
	var solid := StaticBody3D.new()
	solid.collision_layer = Layers.WORLD
	solid.collision_mask = 0
	model.add_child(solid)
	var shape_b := Geo.Builder.new()
	shape_b.tube_x(R_IN, x0, x1, 28, true)
	shape_b.ring_x(x1, Geo.circle(R_IN), Geo.circle(0.0), -1.0, 28)
	shape_b.ring_x(x0, Geo.circle(R_IN), Geo.circle(0.45), 1.0, 28)
	shape_b.tube_x(R_OUT, x0, x1, 28, false)
	shape_b.tube_x(0.45, 0.0, x0, 20, true)
	var shape := shape_b.shape()
	shape.backface_collision = true
	Kit.collider(solid, shape)


# --- What is aboard -----------------------------------------------------------------------------

## Each thing left aboard, strapped to the wall round the tube, there to take.
func _loot(b: int) -> void:
	var u := flight.u
	var things := Salvage.loot(u, b)
	var n := things.size()
	for i in n:
		if salvage.is_taken(u, b, i):
			continue
		var thing: Array = things[i]
		var x := COLLAR + 0.7 + (length - 1.2) * (float(i) + 0.5) / n
		var a: float = [PI * 0.75, PI * 1.25, PI * 0.25, PI * 1.75][i % 4]
		var out := Vector3(0, cos(a), sin(a))
		# Item frame: x along the module, z out of the wall toward the axis.
		var z := -out
		var y := z.cross(Vector3.RIGHT).normalized()
		var xf := Transform3D(Basis(Vector3.RIGHT, y, z), Vector3(x, 0, 0) + out * R_IN)
		var root := Node3D.new()
		root.transform = xf
		model.add_child(root)
		_thing_mesh(root, String(thing[0]))
		var it := Interactable.make(root, String(thing[2]), "Take", Kit.box_shape(Vector3(0.46, 0.34, 0.24)), Vector3(0, 0, 0.12))
		it.hold_time = 1.0
		var idx := i
		it.on_use = func() -> void: _take(idx)
		_items[i] = root


func _take(i: int) -> void:
	if shown < 0:
		return
	var label := salvage.take(sim, flight.u, shown, i)
	if label == "":
		return
	if _items.has(i):
		(_items[i] as Node).queue_free()
		_items.erase(i)
	Sfx.play("latch", -6.0, 1.1, "Suit")
	if toast.is_valid():
		var left := Salvage.loot(flight.u, shown).size() - (salvage.taken.get("%d:%d" % [flight.u.system_id, shown], []) as Array).size()
		toast.call("Taken aboard: %s%s" % [label, "   (nothing else left)" if left <= 0 else ""])


## What each thing looks like (x along the module, y across, z out of the wall).
func _thing_mesh(root: Node3D, kind: String) -> void:
	var b := Geo.Builder.new()
	var strap := Kit.matte(Color(0.12, 0.12, 0.13), 0.8)
	match kind:
		"water":
			b.bevel = 0.02
			for sx in [-0.12, 0.12]:
				b.box(Vector3(sx, 0, 0.09), Vector3(0.2, 0.26, 0.18))
			Kit.mesh(root, b.commit(Kit.matte(Color(0.9, 0.9, 0.88), 0.5)), null)
			var caps := Geo.Builder.new()
			for sx in [-0.12, 0.12]:
				caps.cylinder(Vector3(sx, 0.13, 0.09), Vector3(sx, 0.16, 0.09), 0.025, 10)
			Kit.mesh(root, caps.commit(Kit.matte(Color(0.2, 0.4, 0.8), 0.4)), null)
		"food":
			var rack := Geo.Builder.new()
			for k in 4:
				b.box(Vector3(0, 0, 0.02 + k * 0.035), Vector3(0.34, 0.24, 0.026))
			for c in [Vector2(-0.18, -0.13), Vector2(0.18, -0.13), Vector2(-0.18, 0.13), Vector2(0.18, 0.13)]:
				rack.cylinder(Vector3(c.x, c.y, 0.0), Vector3(c.x, c.y, 0.16), 0.008, 6)
			Kit.mesh(root, b.commit(Kit.matte(Color(0.78, 0.7, 0.52), 0.8)), null)
			Kit.mesh(root, rack.commit(Kit.metal(Color(0.6, 0.6, 0.62))), null)
		"dhe":
			b.cylinder(Vector3(-0.22, 0, 0.1), Vector3(0.2, 0, 0.1), 0.09, 16)
			Kit.mesh(root, b.commit(Looks.panel(Color(0.92, 0.72, 0.12), 0.4)), null)
			var bands := Geo.Builder.new()
			for bx in [-0.15, 0.0, 0.13]:
				bands.cylinder(Vector3(bx - 0.02, 0, 0.1), Vector3(bx + 0.02, 0, 0.1), 0.092, 16)
			bands.cylinder(Vector3(0.2, 0, 0.1), Vector3(0.25, 0, 0.1), 0.025, 10)
			Kit.mesh(root, bands.commit(strap), null)
		"hyd":
			b.cylinder(Vector3(-0.18, 0, 0.08), Vector3(0.18, 0, 0.08), 0.07, 14)
			Kit.mesh(root, b.commit(Looks.panel(Color(0.85, 0.32, 0.1), 0.4)), null)
			Ctl.text(root, "N2H4", Vector3(0, 0, 0.152), 0.03, Color(0.05, 0.05, 0.05))
		"patches":
			b.bevel = 0.015
			b.box(Vector3(0, 0, 0.05), Vector3(0.32, 0.22, 0.1))
			Kit.mesh(root, b.commit(Looks.panel(Color(0.9, 0.45, 0.08), 0.4)), null)
			Kit.mesh(root, Kit.box(Vector3(0.12, 0.02, 0.03)), strap, Vector3(0, 0.12, 0.05))
			Ctl.text(root, "PATCH KIT", Vector3(0, 0, 0.101), 0.022, Color(0.05, 0.05, 0.05))
		"pills":
			b.bevel = 0.01
			b.box(Vector3(0, 0, 0.04), Vector3(0.24, 0.17, 0.08))
			Kit.mesh(root, b.commit(Kit.matte(Color(0.93, 0.93, 0.9), 0.5)), null)
			var cross := Geo.Builder.new()
			cross.box(Vector3(0, 0, 0.081), Vector3(0.08, 0.025, 0.003))
			cross.box(Vector3(0, 0, 0.081), Vector3(0.025, 0.08, 0.003))
			Kit.mesh(root, cross.commit(Kit.matte(Color(0.8, 0.1, 0.08), 0.5)), null)
		"film":
			for sx in [-0.07, 0.07]:
				b.box(Vector3(sx, 0, 0.012), Vector3(0.11, 0.1, 0.024))
			Kit.mesh(root, b.commit(Kit.matte(Color(0.06, 0.06, 0.07), 0.4)), null)
			Kit.mesh(root, Kit.box(Vector3(0.3, 0.04, 0.004)), Kit.matte(Color(0.2, 0.2, 0.2), 1.0), Vector3(0, 0, 0.002))
