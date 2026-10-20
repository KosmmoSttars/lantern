class_name ReactorBay
extends RefCounted
## The reactor module, aft of Life support behind its own hatch. The core sits in a vault
## behind the biological shield, seen glowing through a lead-glass window; its three fuel
## assemblies are reached through the core head, a heavy plug in the shield that may only be
## unsealed with the reactor shut down and cooled. Refuelling is done by hand: pull a spent
## assembly (hot: the dose climbs while it is out), carry it to the recycler's hopper, take a
## fresh one from the rack, push it home, seal the head, restart.
##
## In the front of the module: the CORE panel, the two coolant pumps (they wear; service
## them), the fresh fuel rack, and the waste recycler, which takes anything thrown in its
## hopper (spent fuel above all) and makes what its OUTPUT selector asks for. Things go wrong
## here: coolant leaks, pump trips, a cracked shield, and an overheating core counting down to
## a melt; the last way out is the JETTISON on the panel by the hatch in Life support.

const SHIELD_Z := 1.3
## Where the fittings in front of the shield are centred along the module.
const FRONT_Z := 0.45
const SHIELD_T := 0.3
## The core port in the shield (centre, x and y), its radius, and the slots' ring round it.
const PORT := Vector2(0.0, -0.08)
const PORT_R := 0.24
const SLOT_R := 0.105
## [name, material, spent assemblies, what it makes]
const RECIPES := [
	["WATER 10 kg", 6, 0, {"water": 10.0}],
	["PATCH KIT", 15, 0, {"patches": 1}],
	["FILM PACK", 8, 0, {"film": 10}],
	["COOLANT", 12, 0, {"rx_reserve": 0.25}],
	["FUEL ASSEMBLY", 30, 2, {"rx_fresh": 1}],
]
## What the hopper makes of each kind of thing (material); fuel is counted apart.
const SCRAP := {"photo": 1}

var station: Station
var sim: ShipSim
var main: Node
var toast: Callable
var root: Node3D
var hatch: Hatch
var core_panel: ControlPanel
var head: Node3D
var head_it: Interactable
var slots: Array[Interactable] = []
var _slot_meshes: Array[Node3D] = []
var _glow: OmniLight3D
var _window_mat: StandardMaterial3D
var _leak: Node3D
var _crack: Node3D
var _rack_rods: Array[Node3D] = []
var _rc_screen: Terminal
var _hum: AudioStreamPlayer3D
## Assemblies out of the core and the rack, wherever they float.
var loose: Array[Prop] = []
var _head_angle := 0.0


func build(p_station: Station, p_sim: ShipSim, p_main: Node) -> void:
	station = p_station
	sim = p_sim
	main = p_main
	root = station.reactor_root
	_hatch()
	_jettison_panel()
	if sim.rx_jettisoned or root == null:
		_gone()
		return
	_shield()
	_hum = Sfx.attach("reactor_hum", root, -60.0, 2.2)
	_hum.position = Vector3(0, -0.3, SHIELD_Z - 0.4)
	_core_panel()
	_loop_panel()
	_pumps()
	_rack()
	_recycler()
	_poster()
	# The reactor manual, floating by the CORE panel.
	var book := Manual.make_prop("reactor")
	station.add_child(book)
	book.position = Vector3(0.2, 0.12, 0.2)
	book.rotation = Vector3(0.5, -0.9, 0.3)
	book.angular_velocity = Vector3(0.03, -0.06, 0.02)
	# Assemblies that were out of the core and the rack when the game was saved: by the rack.
	var spot := station.face_xform(1, FRONT_Z)
	for k in sim.rx_loose.size():
		var a := make_assembly(float(sim.rx_loose[k]))
		station.add_child(a)
		a.global_position = spot * Vector3(0, -0.15 + 0.12 * k, 0.4)
		a.rotation.z = PI / 2.0
		loose.append(a)
	sim.rx_loose = []


## Note the assemblies out and about in the sim, for the save.
func save_loose() -> void:
	sim.rx_loose = []
	for a: Variant in loose:
		if is_instance_valid(a) and not (a as Prop).is_queued_for_deletion():
			sim.rx_loose.append(float((a as Prop).get_meta("burnup", 0.0)))


# --- Hatch and jettison ------------------------------------------------------------------------

func _hatch() -> void:
	hatch = Hatch.new()
	hatch.size = Station.HOLE * 2.0 + 0.14
	hatch.setup(station, Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(0, 0, Station.SPINE["Reactor"][0] - 0.12)), "Reactor hatch")
	hatch.is_open = true


func _jettison_panel() -> void:
	var p := ControlPanel.make(station, sim, "REACTOR MODULE", Vector2(0.7, 0.5), station.face_xform(7, -1.0), Callable())
	p.lamp("CORE MELT", 0.2, 0.22, func() -> bool: return sim.rx_melt_t != INF and int(Time.get_ticks_msec() / 300) % 2 == 0, Ctl.RED)
	p.digits("MELT IN", 0.45, 0.22, func() -> String: return " --:--" if sim.rx_melt_t == INF else " %02d:%02d" % [int(sim.rx_melt_t) / 60, int(sim.rx_melt_t) % 60], Ctl.RED)
	p.lamp("HATCH SHUT", 0.2, 0.4, func() -> bool: return not hatch.is_open, Ctl.GREEN)
	p.button("JETTISON", 0.5, 0.38, func() -> void: main.jettison_reactor(), func() -> bool: return sim.rx_melt_t != INF, Ctl.RED, true)


## The module is gone (cast off before a loaded game, or just now): nothing aft of the hatch.
func _gone() -> void:
	root = null
	hatch.is_open = false
	hatch.locked_reason = "Nothing beyond: the reactor module is gone"
	if _leak:
		_leak.queue_free()
		_leak = null


# --- The shield, the core head and the slots ------------------------------------------------------

func _shield() -> void:
	# The shield: a thick wall across the module, the core port through it a little off its
	# centre, both faces and the port's lining.
	var outer := Geo.octagon(Station.A + 0.005, 2.0 * Station.A - Station.A * sqrt(2.0))
	var wall := Geo.Builder.new()
	var solid_b := Geo.Builder.new()
	var seg := 64
	for side in [0.0, 1.0]:
		var z: float = SHIELD_Z + SHIELD_T * side
		var n := Vector3(0, 0, -1.0 if side == 0.0 else 1.0)
		for k in seg:
			var a0 := TAU * k / seg
			var a1 := TAU * (k + 1) / seg
			var p0: Vector2 = outer.call(a0)
			var p1: Vector2 = outer.call(a1)
			var q0 := PORT + Vector2(cos(a0), sin(a0)) * PORT_R
			var q1 := PORT + Vector2(cos(a1), sin(a1)) * PORT_R
			var v := [Vector3(p0.x, p0.y, z), Vector3(p1.x, p1.y, z), Vector3(q1.x, q1.y, z), Vector3(q0.x, q0.y, z)]
			wall.tri(v[0], v[1], v[2], n, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, p0, p1, q1)
			wall.tri(v[0], v[2], v[3], n, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, p0, q1, q0)
			solid_b.quad(v[0], v[1], v[2], v[3], n)
	wall.xform = Transform3D(Basis(Vector3.UP, -PI / 2.0), Vector3(PORT.x, PORT.y, SHIELD_Z))
	wall.tube_x(PORT_R, 0.0, SHIELD_T, 32, true)
	wall.xform = Transform3D.IDENTITY
	Kit.mesh(root, wall.commit(Looks.panel(Color(0.36, 0.36, 0.33), 0.6, 0.2, 1.0, 1.0)), null)
	var solid := StaticBody3D.new()
	solid.collision_layer = Layers.WORLD
	solid.collision_mask = 0
	root.add_child(solid)
	Kit.collider(solid, solid_b.shape())
	# Hazard paint round the port.
	var stripes := Geo.Builder.new()
	for k in 16:
		var a := TAU * k / 16.0
		var c := Vector3(PORT.x + cos(a) * (PORT_R + 0.07), PORT.y + sin(a) * (PORT_R + 0.07), SHIELD_Z - 0.003)
		stripes.box(c, Vector3(0.05, 0.03, 0.002), Basis(Vector3.BACK, a + 0.6))
	Kit.mesh(root, stripes.commit(Kit.matte(Color(0.95, 0.75, 0.12), 0.6)), null)
	# The lead-glass window up to the right, the vault behind it lit by the core.
	var win := Vector3(0.3, 0.26, SHIELD_Z)
	var frame := Geo.Builder.new()
	frame.bevel = 0.01
	for s in [[Vector3(0, 0.1, 0), Vector3(0.34, 0.04, 0.06)], [Vector3(0, -0.1, 0), Vector3(0.34, 0.04, 0.06)], [Vector3(-0.15, 0, 0), Vector3(0.04, 0.16, 0.06)], [Vector3(0.15, 0, 0), Vector3(0.04, 0.16, 0.06)]]:
		frame.box(win + (s[0] as Vector3) - Vector3(0, 0, 0.03), s[1])
	Kit.mesh(root, frame.commit(Kit.metal(Color(0.25, 0.25, 0.27), 0.4, 0.7)), null)
	_window_mat = StandardMaterial3D.new()
	_window_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_window_mat.albedo_color = Color(0.35, 0.5, 0.45, 0.55)
	_window_mat.emission_enabled = true
	_window_mat.emission = Color(1.0, 0.45, 0.15)
	Kit.mesh(root, Kit.box(Vector3(0.27, 0.16, 0.004)), _window_mat, win - Vector3(0, 0, 0.004))
	# The core face at the back of the port, and the glow of the core spilling out of the
	# window into the room.
	Kit.mesh(root, Kit.cylinder(PORT_R, 0.01, 32), _window_mat, Vector3(PORT.x, PORT.y, SHIELD_Z + SHIELD_T - 0.01), Basis(Vector3.RIGHT, PI / 2.0))
	_glow = OmniLight3D.new()
	_glow.light_color = Color(1.0, 0.5, 0.2)
	_glow.omni_range = 1.6
	_glow.light_cull_mask = Station.INSIDE_LAYER
	_glow.position = win - Vector3(0, 0, 0.3)
	root.add_child(_glow)
	_head()
	_head_lock()
	_slots()


## The core head: a heavy plug in the port with a handwheel, swung aside to open.
func _head() -> void:
	var hinge := Node3D.new()
	hinge.position = Vector3(PORT.x - PORT_R - 0.03, PORT.y, SHIELD_Z - 0.02)
	root.add_child(hinge)
	head = hinge
	var plug := Geo.Builder.new()
	plug.xform = Transform3D(Basis(Vector3.UP, -PI / 2.0), Vector3(PORT_R + 0.03, 0, 0))
	# A stepped plug: chamfered rim, a raised boss in the middle.
	plug.lathe_x(PackedVector2Array([Vector2(-0.085, 0.0), Vector2(-0.085, 0.1), Vector2(-0.07, 0.12), Vector2(-0.06, 0.12), Vector2(-0.06, PORT_R - 0.02), Vector2(-0.045, PORT_R + 0.05), Vector2(0.0, PORT_R + 0.05), Vector2(0.0, 0.0)]), 32)
	plug.xform = Transform3D.IDENTITY
	Kit.mesh(hinge, plug.commit(Kit.metal(Color(0.5, 0.5, 0.52), 0.35, 0.85)), null)
	# The bolt circle and two lifting lugs.
	var bolts := Geo.Builder.new()
	var centre := Vector3(PORT_R + 0.03, 0, 0)
	for k in 12:
		var a := TAU * k / 12.0 + PI / 12.0
		var at := centre + Vector3(cos(a), sin(a), 0) * (PORT_R - 0.005)
		bolts.cylinder(at + Vector3(0, 0, -0.045), at + Vector3(0, 0, -0.07), 0.016, 6)
	for sy in [-1.0, 1.0]:
		bolts.box(centre + Vector3(0, sy * 0.19, -0.075), Vector3(0.06, 0.02, 0.035))
	Kit.mesh(hinge, bolts.commit(Kit.metal(Color(0.25, 0.25, 0.27), 0.5, 0.8)), null)
	var wheel := Geo.Builder.new()
	var c := Vector3(PORT_R + 0.03, 0, -0.08)
	for k in 20:
		var a0 := TAU * k / 20.0
		var a1 := TAU * (k + 1) / 20.0
		wheel.cylinder(c + Vector3(cos(a0), sin(a0), 0) * 0.12, c + Vector3(cos(a1), sin(a1), 0) * 0.12, 0.012, 6)
	for k in 3:
		var a := TAU * k / 3.0
		wheel.cylinder(c, c + Vector3(cos(a), sin(a), 0) * 0.12, 0.01, 6)
	wheel.cylinder(c, c + Vector3(0, 0, 0.06), 0.03, 10)
	Kit.mesh(hinge, wheel.commit(Looks.panel(Color(0.85, 0.66, 0.16), 0.4)), null)
	head_it = Interactable.make(hinge, "Core head", "Unseal", Kit.box_shape(Vector3(0.6, 0.6, 0.16)), Vector3(PORT_R + 0.03, 0, -0.05))
	head_it.hold_time = 3.0
	head_it.set_meta("work_sound", "servo")
	head_it.verb_fn = func() -> String: return "Seal the core head" if sim.rx_head_open else "Unseal the core head"
	head_it.value_fn = func() -> String: return "OPEN" if sim.rx_head_open else "sealed"
	head_it.on_use = func() -> void:
		if sim.rx_head_open:
			sim.rx_head_open = false
			Sfx.play_at("clunk", head.global_position, -2.0, 0.6)
		else:
			var why := sim.head_blocker()
			if why != "":
				_say(why + ". Or free it: the HEAD LOCK switch beside the head")
				Sfx.play_at("error", head.global_position, -6.0)
				return
			sim.open_head()
			Sfx.play_at("airflow", head.global_position, -6.0, 0.7)
			if sim.rx_boom == "":
				_say("Core head open: the room is hot. Be quick." if sim.rx_t <= ShipSim.HEAD_COOL else "Core head open HOT: get out!")


## HEAD LOCK, on the shield beside the head, under its cover: LOCKED, the head only opens on
## a shut-down, cooled core; FREE, it opens whenever it is told to, whatever that does.
func _head_lock() -> void:
	var xf := Transform3D(Basis(Vector3.UP, PI), Vector3(0.33, -0.33, SHIELD_Z - 0.004))
	var p := ControlPanel.make(root, sim, "HEAD LOCK", Vector2(0.24, 0.2), xf, Callable())
	p.toggle("c_rx_override", "", 0.12, 0.12, PackedStringArray(["LOCKED", "FREE"]), true)
	p.lamp("", 0.2, 0.06, func() -> bool: return sim.c_rx_override, Ctl.RED)


## Three slots in a ring inside the port: pull a spent assembly, push a fresh one home.
func _slots() -> void:
	for k in ShipSim.FUEL_SLOTS:
		var a := TAU * k / ShipSim.FUEL_SLOTS + PI / 2.0
		var at := Vector3(PORT.x + cos(a) * SLOT_R, PORT.y + sin(a) * SLOT_R, SHIELD_Z + 0.12)
		# The assembly seated in the slot: its top nozzle and bail toward the port, the rest
		# down in the core (rebuilt when its burnup moves on).
		var end := Node3D.new()
		end.position = at + Vector3(0, 0, 0.5)
		end.basis = Basis(Vector3.RIGHT, -PI / 2.0)
		root.add_child(end)
		_slot_meshes.append(end)
		var it := Interactable.make(root, "Fuel slot %d" % (k + 1), "Pull out", Kit.box_shape(Vector3(0.1, 0.1, 0.12)), at)
		it.hold_time = 1.5
		it.keep_progress = false
		var idx := k
		it.verb_fn = func() -> String: return "Pull the assembly out" if float(sim.rx_fuel[idx]) >= 0.0 else "Push a fresh one home (let go of it here)"
		it.value_fn = func() -> String: return ("fuel %d %%" % roundi((1.0 - float(sim.rx_fuel[idx])) * 100.0)) if float(sim.rx_fuel[idx]) >= 0.0 else "empty"
		it.on_use = func() -> void: _slot_used(idx)
		slots.append(it)


func _slot_used(k: int) -> void:
	var hand: Hand = main.player.hand
	if float(sim.rx_fuel[k]) >= 0.0:
		if hand.held:
			return
		var p := make_assembly(float(sim.rx_fuel[k]))
		station.add_child(p)
		loose.append(p)
		p.global_position = slots[k].global_position + Vector3(0, 0, -0.35)
		sim.rx_fuel[k] = -1.0
		hand._pick(p, p.global_position)
		Sfx.play_at("latch", p.global_position, -4.0, 0.7)
		return
	var held := hand.held
	if held and held.kind == "fuel":
		sim.rx_fuel[k] = float(held.get_meta("burnup", 0.0))
		hand.drop()
		held.queue_free()
		Sfx.play_at("clunk", slots[k].global_position, -3.0, 0.9)
		_say("Assembly home in slot %d" % (k + 1))


## A fuel assembly to carry: a long hexagonal bundle, a handle on its top. `burnup` 0 is a
## fresh one (bright steel), 1 spent (dark, faintly blue, hot).
static func make_assembly(burnup: float) -> Prop:
	var name := "Fresh fuel assembly" if burnup < 0.05 else "Spent fuel assembly (%d %% burnt)" % roundi(burnup * 100.0)
	var p := Prop.make("fuel", name, assembly_mesh(burnup), Kit.box_shape(Vector3(0.1, 0.95, 0.1)), 25.0)
	p.set_meta("burnup", burnup)
	return p


## The look of an assembly, its long axis along y.
## Seven fuel rods in a hexagonal bundle held by spacer grids, a top nozzle with its lifting
## bail, a bottom nozzle.
static func assembly_mesh(burnup: float) -> Node3D:
	var r := Node3D.new()
	var rods := Geo.Builder.new()
	var pitch := 0.03
	var spots: Array[Vector2] = [Vector2.ZERO]
	for k in 6:
		var a := TAU * k / 6.0
		spots.append(Vector2(cos(a), sin(a)) * pitch)
	for s: Vector2 in spots:
		rods.cylinder(Vector3(s.x, -0.38, s.y), Vector3(s.x, 0.38, s.y), 0.012, 8)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.72, 0.7, 0.62).lerp(Color(0.2, 0.2, 0.26), burnup)
	mat.metallic = 0.7
	mat.roughness = 0.35
	if burnup > 0.3:
		mat.emission_enabled = true
		mat.emission = Color(0.3, 0.55, 1.0)
		mat.emission_energy_multiplier = burnup * 0.7
	Kit.mesh(r, rods.commit(mat), null)
	var steel := Geo.Builder.new()
	# Spacer grids: hexagonal bands round the bundle.
	for y in [-0.27, 0.0, 0.27]:
		for k in 6:
			var a0 := TAU * k / 6.0 + PI / 6.0
			var a1 := a0 + TAU / 6.0
			var p0 := Vector3(cos(a0), 0, sin(a0)) * 0.05
			var p1 := Vector3(cos(a1), 0, sin(a1)) * 0.05
			var mid := (p0 + p1) * 0.5 + Vector3(0, y, 0)
			steel.box(mid, Vector3((p1 - p0).length(), 0.025, 0.004), Basis(Vector3.UP, -(a0 + a1) * 0.5 + PI / 2.0))
	# Nozzles at the ends, the bail on top.
	steel.cylinder(Vector3(0, 0.38, 0), Vector3(0, 0.44, 0), 0.052, 6)
	steel.cylinder(Vector3(0, -0.44, 0), Vector3(0, -0.38, 0), 0.05, 6)
	steel.cylinder(Vector3(0, -0.47, 0), Vector3(0, -0.44, 0), 0.025, 8)
	steel.cylinder(Vector3(-0.035, 0.44, 0), Vector3(-0.035, 0.49, 0), 0.008, 6)
	steel.cylinder(Vector3(0.035, 0.44, 0), Vector3(0.035, 0.49, 0), 0.008, 6)
	steel.cylinder(Vector3(-0.04, 0.49, 0), Vector3(0.04, 0.49, 0), 0.01, 6)
	Kit.mesh(r, steel.commit(Kit.metal(Color(0.62, 0.63, 0.65), 0.3, 0.9)), null)
	return r


# --- The front of the module ------------------------------------------------------------------

func _core_panel() -> void:
	var p := ControlPanel.make(root, sim, "CORE", Vector2(1.4, 0.9), station.face_xform(2, FRONT_Z), func() -> bool: return sim.bus_a_v > 90.0 or sim.bus_b_v > 90.0)
	core_panel = p
	p.group("FUEL", 0.04, 0.09, 0.42, 0.62)
	for k in ShipSim.FUEL_SLOTS:
		var idx := k
		p.bar("SLOT %d" % (k + 1), 0.12 + k * 0.12, 0.38, func() -> float: return maxf(1.0 - float(sim.rx_fuel[idx]), 0.0) if float(sim.rx_fuel[idx]) >= 0.0 else 0.0)
	p.lamp("FUEL LOW", 0.25, 0.64, func() -> bool: return sim.fuel_reactivity() < 0.3, Ctl.AMBER)
	p.group("CORE", 0.5, 0.09, 0.46, 0.62)
	p.gauge("CORE TEMP", 0.62, 0.3, func() -> float: return sim.rx_t, 0.0, 3200.0, "K", 1500.0)
	p.digits("DECAY kW", 0.84, 0.24, func() -> String: return "%5.1f" % (sim.rx_decay_w / 1000.0))
	p.lamp("HEAD OPEN", 0.84, 0.4, func() -> bool: return sim.rx_head_open, Ctl.RED)
	p.digits("MELT IN", 0.84, 0.56, func() -> String: return " --:--" if sim.rx_melt_t == INF else " %02d:%02d" % [int(sim.rx_melt_t) / 60, int(sim.rx_melt_t) % 60], Ctl.RED)
	p.press("rx_scram", "SCRAM", 0.62, 0.6, func() -> bool: return sim.rx_scrammed, Ctl.RED, true)
	p.group("LOOP", 1.0, 0.09, 0.36, 0.62)
	p.digits("COOLANT %", 1.1, 0.24, func() -> String: return "%5d" % roundi(sim.rx_coolant * 100.0))
	p.digits("RESERVE", 1.26, 0.24, func() -> String: return "%5.2f" % sim.rx_reserve)
	p.toggle("c_rx_fill", "FILL", 1.1, 0.46, PackedStringArray(["SHUT", "OPEN"]))
	p.digits("PUMP WEAR %", 1.26, 0.46, func() -> String: return "%5d" % roundi(sim.rx_pump_wear * 100.0))
	p.digits("SHIELD %", 1.1, 0.64, func() -> String: return "%5d" % roundi(sim.rx_shield * 100.0))
	p.digits("DOSE mSv/h", 1.26, 0.64, func() -> String: return "%5d" % roundi(dose_here(main.player.global_position)))
	Ctl.text(p, "REFUEL: SCRAM, COOL BELOW 650 K, UNSEAL THE HEAD, SWAP, SEAL, RESET.", p.at(0.7, 0.82), 0.011, Ctl.RED)


## LOOP PRESSURE, lower left wall: the gauge, the RELIEF valve and, under its cover, the core
## head interlock OVERRIDE.
func _loop_panel() -> void:
	var p := ControlPanel.make(root, sim, "LOOP PRESSURE", Vector2(1.2, 0.62), station.face_xform(7, FRONT_Z), func() -> bool: return sim.bus_a_v > 90.0 or sim.bus_b_v > 90.0)
	p.gauge("LOOP MPa", 0.2, 0.34, func() -> float: return sim.rx_loop_p, 0.0, 5.0, "MPa", ShipSim.P_RELIEF)
	p.lamp("PRESS HIGH", 0.44, 0.22, func() -> bool: return sim.rx_loop_p > 2.8, Ctl.RED)
	p.lamp("VENTING", 0.44, 0.44, func() -> bool: return sim.c_rx_relief and sim.rx_loop_p >= ShipSim.P_RELIEF - 0.02, Ctl.AMBER)
	p.toggle("c_rx_relief", "RELIEF", 0.66, 0.3, PackedStringArray(["SHUT", "AUTO"]))
	Ctl.text(p, "NEVER FILL A DRY CORE ABOVE 1000 K", p.at(0.6, 0.52), 0.011, Ctl.RED)


func _pumps() -> void:
	for k in 2:
		var z := 0.0 + k * 0.82
		var xf := station.face_xform(0, z)
		var root2 := Node3D.new()
		root2.transform = xf
		root.add_child(root2)
		# A skid, the motor with its cooling fins and fan cowl, the coupling guard, and the
		# volute with its suction and discharge flanges.
		var b := Geo.Builder.new()
		b.box(Vector3(0, 0, 0.012), Vector3(0.56, 0.3, 0.024))
		b.box(Vector3(0.08, 0.1, 0.04), Vector3(0.36, 0.03, 0.03))
		b.box(Vector3(0.08, -0.1, 0.04), Vector3(0.36, 0.03, 0.03))
		b.cylinder(Vector3(0.0, 0, 0.13), Vector3(0.22, 0, 0.13), 0.085, 16)
		b.cylinder(Vector3(0.22, 0, 0.13), Vector3(0.27, 0, 0.13), 0.075, 16)
		Kit.mesh(root2, b.commit(Looks.panel(Color(0.32, 0.4, 0.5), 0.5)), null)
		var fins := Geo.Builder.new()
		for f in 8:
			var a := TAU * f / 8.0
			fins.box(Vector3(0.11, cos(a) * 0.09, 0.13 + sin(a) * 0.09), Vector3(0.2, 0.012, 0.012), Basis(Vector3.RIGHT, a))
		fins.cylinder(Vector3(-0.06, 0, 0.13), Vector3(0.0, 0, 0.13), 0.05, 12)
		var volute_c := Vector3(-0.15, 0, 0.13)
		fins.cylinder(volute_c - Vector3(0.05, 0, 0), volute_c + Vector3(0.05, 0, 0), 0.1, 18)
		for f in 8:
			var a := TAU * f / 8.0
			fins.cylinder(volute_c + Vector3(-0.055, cos(a) * 0.08, sin(a) * 0.08), volute_c + Vector3(0.055, cos(a) * 0.08, sin(a) * 0.08), 0.008, 6)
		Kit.mesh(root2, fins.commit(Kit.metal(Color(0.3, 0.32, 0.35), 0.45, 0.7)), null)
		var pipe := Geo.Builder.new()
		pipe.cylinder(volute_c - Vector3(0.05, 0, 0), Vector3(-0.38, 0, 0.13), 0.04, 10)
		pipe.cylinder(volute_c + Vector3(0, 0.1, 0), volute_c + Vector3(0, 0.16, 0), 0.035, 10)
		for at: Vector3 in [Vector3(-0.3, 0, 0.13), volute_c + Vector3(0, 0.14, 0)]:
			pipe.cylinder(at - Vector3(0.01, 0, 0) if at.y == 0.0 else at - Vector3(0, 0.01, 0), at + Vector3(0.01, 0, 0) if at.y == 0.0 else at + Vector3(0, 0.01, 0), 0.06, 10)
		Kit.mesh(root2, pipe.commit(Looks.panel(Color(0.85, 0.45, 0.1), 0.5)), null)
		Ctl.fit(Ctl.text(root2, "PUMP %s" % ["A", "B"][k], Vector3(0.11, 0, 0.226), 0.018, Color(0.9, 0.9, 0.85)), 0.2, 0.03)
		var it := Interactable.make(root2, "Coolant pump %s" % ["A", "B"][k], "Service", Kit.box_shape(Vector3(0.5, 0.3, 0.26)), Vector3(0, 0, 0.13))
		it.hold_time = 8.0
		it.keep_progress = true
		it.set_meta("work_sound", "servo")
		it.value_fn = func() -> String: return "wear %d %%" % roundi(sim.rx_pump_wear * 100.0)
		it.on_use = func() -> void:
			sim.rx_pump_wear = maxf(sim.rx_pump_wear - 0.5, 0.0)
			_say("Pump serviced: seals and bearings renewed")
	# Coolant lines from the pumps into the shield.
	var lines := Geo.Builder.new()
	for sx in [-0.25, 0.25]:
		lines.cylinder(Vector3(sx, -Station.A + 0.14, -0.25), Vector3(sx, -Station.A + 0.14, SHIELD_Z), 0.035, 10)
	Kit.mesh(root, lines.commit(Looks.panel(Color(0.85, 0.45, 0.1), 0.5)), null)


func _rack() -> void:
	var xf := station.face_xform(1, FRONT_Z)
	var r := Node3D.new()
	r.transform = xf
	root.add_child(r)
	var frame := Geo.Builder.new()
	frame.box(Vector3(0, 0, 0.01), Vector3(1.1, 0.5, 0.02))
	for x in [-0.32, 0.32]:
		frame.box(Vector3(x, -0.02, 0.06), Vector3(0.04, 0.42, 0.06))
	Kit.mesh(r, frame.commit(Kit.metal(Color(0.4, 0.4, 0.42), 0.45, 0.7)), null)
	Ctl.fit(Ctl.text(r, "FRESH FUEL", Vector3(0, 0.215, 0.022), 0.018), 0.6, 0.03)
	for k in 4:
		var rod := Node3D.new()
		rod.position = Vector3(0, -0.17 + k * 0.1, 0.08)
		rod.rotation.z = PI / 2.0
		r.add_child(rod)
		rod.add_child(assembly_mesh(0.0))
		_rack_rods.append(rod)
	var it := Interactable.make(r, "Fresh fuel rack", "Take one", Kit.box_shape(Vector3(1.1, 0.5, 0.16)), Vector3(0, 0, 0.08))
	it.hold_time = 0.6
	it.value_fn = func() -> String: return "%d left" % sim.rx_fresh
	it.on_use = func() -> void:
		var hand: Hand = main.player.hand
		if hand.held:
			return
		if sim.rx_fresh <= 0:
			_say("No fresh fuel. More from the supply catalogue, the recycler, or a fuel depot")
			return
		sim.rx_fresh -= 1
		var p := make_assembly(0.0)
		station.add_child(p)
		loose.append(p)
		p.global_position = it.global_position + it.global_basis.z * 0.3
		hand._pick(p, p.global_position)


func _recycler() -> void:
	var xf := station.face_xform(6, FRONT_Z)
	var p := ControlPanel.make(root, sim, "WASTE RECYCLER", Vector2(1.4, 0.9), xf, func() -> bool: return sim.bus_b_v > 90.0)
	_rc_screen = p.crt(0.5, 0.42, 0.7, 0.52, 12, 420.0)
	var names := PackedStringArray()
	for k in RECIPES.size():
		names.append(str(k + 1))
	p.rotary("c_rc_output", "OUTPUT", 1.0, 0.3, names)
	p.button("PROCESS", 1.2, 0.3, process, func() -> bool: return _can_make(sim.c_rc_output), Ctl.GREEN)
	# The hopper: a hatch in a chute on the panel's right; let go of a thing over it.
	var hop := Geo.Builder.new()
	hop.box(p.at(1.12, 0.66) + Vector3(0, 0, 0.05), Vector3(0.36, 0.26, 0.1))
	Kit.mesh(p, hop.commit(Kit.metal(Color(0.3, 0.3, 0.32), 0.5, 0.7)), null)
	Kit.mesh(p, Kit.box(Vector3(0.28, 0.18, 0.004)), Kit.matte(Color(0.02, 0.02, 0.02), 0.9), p.at(1.12, 0.66) + Vector3(0, 0, 0.102))
	Ctl.text(p, "HOPPER: LET GO OF IT HERE", p.at(1.12, 0.47), 0.011)
	var it := Interactable.make(p, "Recycler hopper", "Drop it in", Kit.box_shape(Vector3(0.36, 0.26, 0.2)), p.at(1.12, 0.66) + Vector3(0, 0, 0.1))
	it.tool = "*"
	it.tool_name = "something to recycle (carry it here and let go)"
	it.on_use = func() -> void: _feed()


func _feed() -> void:
	var hand: Hand = main.player.hand
	var held := hand.held
	if held == null:
		return
	if held.kind in ["manual", "camera", "geiger"]:
		_say("Not that: you will want it")
		return
	var what := held.display_name
	if held.kind == "fuel":
		var burn := float(held.get_meta("burnup", 0.0))
		if burn < 0.05:
			sim.rx_fresh += 1
			what = "a fresh assembly (back to the rack)"
		else:
			sim.rc_spent += 1
			sim.rc_material += 20.0 * burn
	else:
		sim.rc_material += float(SCRAP.get(held.kind, 2))
	hand.drop()
	held.queue_free()
	Sfx.play("servo", -6.0, 0.5, "Station")
	_say("Recycled: %s" % what)


func _can_make(k: int) -> bool:
	var r: Array = RECIPES[clampi(k, 0, RECIPES.size() - 1)]
	return sim.rc_material >= float(r[1]) and sim.rc_spent >= int(r[2])


func process() -> void:
	var k := clampi(sim.c_rc_output, 0, RECIPES.size() - 1)
	var r: Array = RECIPES[k]
	if not _can_make(k):
		Sfx.play("error", -8.0, 1.0, "Station")
		_say("Not enough to make %s" % r[0])
		return
	sim.rc_material -= float(r[1])
	sim.rc_spent -= int(r[2])
	var gives: Dictionary = r[3]
	for key: String in gives:
		if key in ["rx_fresh", "patches", "film"]:
			sim.set(key, int(sim.get(key)) + int(gives[key]))
		else:
			sim.set(key, float(sim.get(key)) + float(gives[key]))
	Sfx.play("chime", -8.0, 0.8, "Station")
	_say("Recycler made: %s" % r[0])


func _poster() -> void:
	var xf := Transform3D(Basis(Vector3.UP, PI), Vector3(-0.4, 0.08, SHIELD_Z - 0.004))
	Posters.make(root, xf, "DANGER", "CORE HEAD", "Shut down and cool it first.\nOpen, the room is lethal.", "rad", false, 0.03)


# --- Each frame -------------------------------------------------------------------------------

func update(delta: float) -> void:
	loose.assign(loose.filter(func(a: Variant) -> bool: return is_instance_valid(a) and not (a as Prop).is_queued_for_deletion()))
	if root == null:
		return
	# The head swings aside when it is open.
	_head_angle = move_toward(_head_angle, PI * 0.92 if sim.rx_head_open else 0.0, delta * 1.2)
	head.rotation.y = _head_angle
	for k in slots.size():
		var f := float(sim.rx_fuel[k])
		var it := slots[k]
		it.enabled = sim.rx_head_open
		it.disabled_hint = "Core head sealed"
		it.tool = "" if f >= 0.0 else "fuel"
		it.tool_name = "a fuel assembly"
		var shown := _slot_meshes[k]
		var key := -1.0 if f < 0.0 else snappedf(f, 0.1)
		if float(shown.get_meta("b", -2.0)) != key:
			shown.set_meta("b", key)
			for c in shown.get_children():
				c.queue_free()
			if f >= 0.0:
				shown.add_child(assembly_mesh(key))
	for k in _rack_rods.size():
		_rack_rods[k].visible = k < sim.rx_fresh
	# The pumps and the core: a thrum that grows with them.
	if _hum:
		var run := clampf(sim.rx_power * 2.0, 0.0, 1.0) * 0.6 + (0.4 if sim.powered("rxpump") and sim.c_rx_pump > 0.05 else 0.0)
		_hum.volume_db = lerpf(-40.0, -14.0, run)
	# The core's glow through the window, with its power and heat.
	var heat := clampf((sim.rx_t - 400.0) / 1400.0, 0.0, 1.5)
	_glow.light_energy = 0.2 + sim.rx_power * 2.5 + heat * 0.8
	_window_mat.emission_energy_multiplier = 0.2 + sim.rx_power * 2.0 + heat
	if _rc_screen:
		_rc_screen.text = _recycler_text()
	# A coolant leak: a jet of vapour off a line, to seal with a patch kit.
	if sim.rx_leak > 0.0 and _leak == null:
		_leak = _make_leak()
	elif sim.rx_leak <= 0.0 and _leak != null:
		_leak.queue_free()
		_leak = null
	if sim.rx_shield < 0.7 and _crack == null:
		_crack = _make_crack()
	elif sim.rx_shield >= 0.7 and _crack != null:
		_crack.queue_free()
		_crack = null


func _recycler_text() -> String:
	var l := PackedStringArray()
	l.append("MATERIAL %4d   SPENT FUEL %d" % [roundi(sim.rc_material), sim.rc_spent])
	l.append("")
	for k in RECIPES.size():
		var r: Array = RECIPES[k]
		var need := "%d" % int(r[1]) + (" +%d SPENT" % int(r[2]) if int(r[2]) > 0 else "")
		l.append("%s%d %-13s %s" % ["> " if k == sim.c_rc_output else "  ", k + 1, String(r[0]), need])
	for k in l.size():
		l[k] = " " + l[k]
	return "\n".join(l)


func _make_leak() -> Node3D:
	var n := Node3D.new()
	n.position = Vector3([-0.25, 0.25][randi() % 2], -Station.A + 0.14, randf_range(0.1, 1.0))
	root.add_child(n)
	var puff := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.08
	sm.height = 0.16
	puff.mesh = sm
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.9, 0.92, 0.95, 0.35)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff.material_override = m
	puff.position = Vector3(0, 0.08, 0)
	n.add_child(puff)
	Sfx.attach("hiss", n, -6.0, 2.0)
	var it := Interactable.make(n, "Coolant leak", "Seal it (patch kit)", Kit.box_shape(Vector3(0.2, 0.2, 0.25)), Vector3.ZERO)
	it.hold_time = 4.0
	it.keep_progress = true
	it.set_meta("work_sound", "spray")
	it.verb_fn = func() -> String: return "Seal it (patch kit)" if sim.patches > 0 else ""
	it.disabled_hint = "No patch kits aboard"
	it.on_use = func() -> void:
		if sim.patches <= 0:
			return
		sim.patches -= 1
		sim.rx_leak = 0.0
		_say("Leak sealed. Top the loop up: FILL on the CORE panel")
	return n


func _make_crack() -> Node3D:
	var n := Node3D.new()
	n.position = Vector3(-0.45, -0.35, SHIELD_Z - 0.01)
	root.add_child(n)
	var b := Geo.Builder.new()
	var p := Vector2.ZERO
	for k in 7:
		var q := p + Vector2(randf_range(0.03, 0.08), randf_range(-0.06, 0.06))
		var mid := (p + q) * 0.5
		b.box(Vector3(mid.x, mid.y, 0), Vector3((q - p).length(), 0.012, 0.004), Basis(Vector3.BACK, (q - p).angle()))
		p = q
	Kit.mesh(n, b.commit(Kit.glow(Color(0.5, 1.0, 0.6), 0.6)), null)
	var it := Interactable.make(n, "Cracked shield", "Patch the shield (patch kit)", Kit.box_shape(Vector3(0.5, 0.2, 0.1)), Vector3(0.25, 0, 0))
	it.hold_time = 8.0
	it.keep_progress = true
	it.set_meta("work_sound", "spray")
	it.on_use = func() -> void:
		if sim.patches <= 0:
			_say("No patch kits aboard")
			return
		sim.patches -= 1
		sim.rx_shield = 1.0
		_say("Shield patched")
	return n


## Dose rate at a point (mSv/h) from the reactor: through the shield while it runs, far more
## with the head open or the shield cracked, and from spent assemblies out of the core (one in
## the hand is close enough to matter).
func dose_here(p: Vector3) -> float:
	var rate := 0.0
	if root != null and station.module_at(p) == "Reactor":
		var leak_through := 1.0 + (1.0 - sim.rx_shield) * 200.0
		rate += (0.3 + sim.rx_power * 6.0 + sim.rx_decay_w / 2000.0) * leak_through
		if sim.rx_head_open:
			var spent := 0.0
			for f: Variant in sim.rx_fuel:
				spent += maxf(float(f), 0.0)
			rate += 120.0 + 150.0 * spent + sim.rx_decay_w / 100.0 + maxf(sim.rx_t - ShipSim.HEAD_COOL, 0.0) * 6.0
	for a: Variant in loose:
		if is_instance_valid(a):
			var ap := a as Prop
			var d2 := ap.global_position.distance_squared_to(p)
			rate += 250.0 * float(ap.get_meta("burnup", 0.0)) * 0.5 / (d2 + 0.5)
	return rate


func _say(text: String) -> void:
	if toast.is_valid():
		toast.call(text)


# --- Casting the module off --------------------------------------------------------------------

## Why the module cannot be cast off now ("" when it can).
func jettison_blocker(player_pos: Vector3) -> String:
	if root == null:
		return "ALREADY GONE"
	if hatch.is_open:
		return "SHUT THE REACTOR HATCH FIRST"
	if station.module_at(player_pos) == "Reactor":
		return "GET OUT OF THE MODULE FIRST"
	return ""
