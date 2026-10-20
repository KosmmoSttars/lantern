class_name SelfTest
extends Node
## Scripted checks inside the running game (`-- --selftest`): every control on every panel
## does something to the sim and puts it back, the hand pulls the keeper in to a grip and
## letting go keeps the speed, the view never rolls. Exit code 0 when all pass.

var main: Node
var failures := 0


func _ready() -> void:
	_run.call_deferred()


func check(ok: bool, what: String) -> void:
	if ok:
		print("  ok   ", what)
	else:
		failures += 1
		print("  FAIL ", what)


func _run() -> void:
	await get_tree().process_frame
	# `-- --selftest --only sleep` runs just the sections named (comma-separated).
	var args := OS.get_cmdline_user_args()
	var i := args.find("--only")
	var only: PackedStringArray = args[i + 1].split(",") if i >= 0 and i + 1 < args.size() else PackedStringArray()
	var sections := [
		["controls", _controls], ["movement", _movement], ["camera", _camera],
		["torch is not felt", _torch_push], ["map and transit", _transit], ["stars", _stars],
		["body", _body], ["science and supply", _science], ["airlock and EVA", _eva],
		["sleep", _sleep], ["props", _props], ["reach", _reach], ["screens", _screens], ["passages", _passages], ["legends", _legends], ["flashlight", _flashlight], ["salvage", _salvage], ["docking", _docking], ["events and story", _events], ["reactor", _reactor], ["separation", _separation]]
	for sec: Array in sections:
		var name: String = sec[0]
		if not only.is_empty() and not only.has(name.get_slice(" ", 0)):
			continue
		print("--- ", name)
		await (sec[1] as Callable).call()
	print("--- %d failure(s)" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _controls() -> void:
	var count := 0
	for c in _all_ctls(main.station):
		match c.kind:
			"toggle":
				var before: bool = bool(c.get_fn.call())
				c.it.on_use.call()
				if c.guarded:
					c.it.on_use.call()
				var after: bool = bool(c.get_fn.call())
				c.it.on_use.call()
				if c.guarded and c._guard_open < 0.5:
					c.it.on_use.call()
				check(after != before and bool(c.get_fn.call()) == before, "toggle %s flips and back" % c.title)
				count += 1
			"rotary":
				var before := int(c.get_fn.call())
				c.it.on_wheel.call(1 if before == 0 else -1)
				var after := int(c.get_fn.call())
				c.it.on_wheel.call(-1 if before == 0 else 1)
				check(after != before and int(c.get_fn.call()) == before, "rotary %s steps and back" % c.title)
				count += 1
			"knob", "lever":
				var before := float(c.get_fn.call())
				var dir := 1 if before < 0.5 else -1
				c.it.on_wheel.call(dir)
				var after := float(c.get_fn.call())
				c.it.on_wheel.call(-dir)
				check(not is_equal_approx(after, before) and absf(float(c.get_fn.call()) - before) < 1e-4, "%s %s turns and back" % [c.kind, c.title])
				count += 1
			"breaker":
				c.it.on_use.call()
				var out := not bool(c.get_fn.call())
				c.it.on_use.call()
				check(out and bool(c.get_fn.call()), "breaker %s pulls and pushes" % c.title)
				count += 1
			"valve":
				var before := float(c.get_fn.call())
				c.it.on_wheel.call(1 if before < 0.5 else -1)
				var after := float(c.get_fn.call())
				c.set_fn.call(before)
				check(not is_equal_approx(after, before), "valve %s turns" % c.title)
				count += 1
			"gauge", "bar":
				var v: Variant = c.read_fn.call()
				check(v is float or v is int, "%s %s reads a number" % [c.kind, c.title])
			"digits":
				check(String(c.text_fn.call()) != "", "digits %s shows text" % c.title)
	check(count > 40, "found %d working controls" % count)
	# The scram really drops the rods, the reset needs the rod demand at zero.
	var sim: ShipSim = main.sim
	sim.press("rx_scram")
	check(sim.rx_scrammed and sim.rx_rod == 0.0, "scram drops the rods")
	sim.press("rx_reset")
	check(sim.rx_scrammed, "reset refused with rods demanded")
	var keep := sim.c_rx_rods
	sim.c_rx_rods = 0.0
	sim.press("rx_reset")
	check(not sim.rx_scrammed, "reset with rods at zero")
	sim.c_rx_rods = keep


func _all_ctls(n: Node) -> Array[Ctl]:
	var out: Array[Ctl] = []
	for c in n.get_children():
		if c is Ctl:
			out.append(c)
		out.append_array(_all_ctls(c))
	return out


func _camera() -> void:
	var p: Player = main.player
	p.look_at_point(p.global_position + Vector3.FORWARD)
	for i in 400:
		p.look(Vector2(3.0, -9.0))
	var up := p.global_basis.y
	check(absf(p.pitch) <= Player.PITCH_LIMIT + 1e-4, "pitch stays clamped (%.2f)" % p.pitch)
	check(absf(p.global_basis.x.y) < 1e-4, "no roll: the view's right stays level")
	check(up.y > 0.0, "the view never goes upside down")


func _movement() -> void:
	var p: Player = main.player
	p.accept_input = false
	Settings.pull_grab = true
	# Float in the habitation, grab the starboard wall two metres away.
	p.global_position = Vector3(-0.4, 0.0, -4.3)
	p.velocity = Vector3.ZERO
	# Grab whatever surface really is there, as the hand's ray would.
	var q := PhysicsRayQueryParameters3D.create(p.global_position, p.global_position + Vector3(3.0, 0, 0), p.collision_mask)
	q.exclude = [p.get_rid()]
	var hit := p.get_world_3d().direct_space_state.intersect_ray(q)
	var grip: Vector3 = hit.position if not hit.is_empty() else Vector3(Station.A, 0.0, -4.3)
	var grip_n: Vector3 = hit.normal if not hit.is_empty() else Vector3.LEFT
	p.grab_surface(grip, grip_n)
	var d0 := p.global_position.distance_to(grip)
	for i in 30:
		await get_tree().physics_frame
	var v_mid := p.velocity.length()
	check(v_mid > 0.5 and p.velocity.x > 0.0, "pulled toward the grip (%.2f m/s)" % v_mid)
	for i in 240:
		await get_tree().physics_frame
	var d1 := p.global_position.distance_to(grip)
	check(d1 < d0 and absf(d1 - Player.HANG) < 0.15, "comes to hang %.2f m off the grip" % d1)
	check(p.velocity.length() < 0.2, "settles while holding on")
	# Again, but let go half way: the speed carries on.
	p.release_grip()
	p.global_position = Vector3(-0.4, 0.0, -4.3)
	p.velocity = Vector3.ZERO
	p.grab_surface(grip, grip_n)
	for i in 40:
		await get_tree().physics_frame
	var v_go := p.velocity
	p.release_grip()
	check(not p.anchored, "let go")
	for i in 10:
		await get_tree().physics_frame
	check(p.velocity.length() > v_go.length() * 0.8 and p.velocity.x > 0.3, "flies on after letting go (%.2f m/s)" % p.velocity.length())


## From the Solar System to the nearest star (always a pulsar) and back.
func _stars() -> void:
	var f: Flight = main.flight
	var sim: ShipSim = main.sim
	var g: Galaxy = main.galaxy
	var map: MapScreen = main.panels.map
	check(f.u.system_id == 0 and f.u.find("Jupiter") > 0 and f.u.find("Titan") > 0, "home is the Solar System")
	var near := g.stars_near(Vector3.ZERO, 30.0)
	check(near.size() > 5, "%d stars within 30 ly" % near.size())
	var pid := g.pulsar_id()
	check(g.star(pid).kind == "pulsar", "the nearest star (%s, %.1f ly) is a pulsar" % [g.star(pid).name, g.distance(pid)])
	var far := -1
	for e in near:
		if g.distance(e.id) > Galaxy.FREE_RANGE + 1.0:
			far = e.id
			break
	check(far < 0 or g.plot_blocker(far) != "", "stars past %d ly need a pulsar fix" % int(Galaxy.FREE_RANGE))
	# Pick the pulsar on the star map.
	var notches := 0
	while map.mode != "galaxy" and notches < 30:
		map.zoom(-1)
		notches += 1
	check(map.mode == "galaxy", "zoomed out to the stars in %d notches" % notches)
	# Fog of war: a touch out in the dark sets a course for an uncharted star.
	map._click_star(map._res() * 0.5 + Vector2(6.0, -3.0) / map.lpp)
	check(map.star_target >= 0 and not g.visited.has(map.star_target) and map.aim_pos != Vector3.INF, "a touch in the dark: course for an uncharted star (~%d ly)" % roundi(g.distance(map.star_target)))
	check(map.charted(pid) and not map.charted(map.star_target), "the pulsar is heard through the fog, the rest is dark")
	map.star_target = pid
	map.aim_pos = Vector3.INF
	sim.c_torch_arm = true
	sim.c_torch_field = true
	for i in 60:
		sim.tick(1.0)
	sim.press("torch_ignite")
	sim.c_torch_thr = 1.0
	main.engage_star(pid)
	check(not f.transit.is_empty() and f.transit.has("interstellar"), "set off for the pulsar (%s)" % Flight.duration(Galaxy.travel_time(g.distance(pid))))
	var n := 0
	while not f.transit.is_empty() and n < 3000:
		n += 1
		sim.tick(1.0)
		f.tick(1.0, sim)
	check(f.u.kind == "pulsar" and g.here == pid, "arrived at %s after %d s" % [f.u.system_name, n])
	check(f.soi == f.u.hub and f.elements.e < 0.05, "in orbit round %s" % f.u.bodies[f.u.hub].name)
	check(g.start_timing(f.u), "pulsar timing run started")
	g.tick(Galaxy.TIMING_TIME + 1.0, f.u, sim)
	check(g.pulsar_fix, "pulsar fix taken")
	main.engage_star(0)
	var m := 0
	while not f.transit.is_empty() and m < 3000:
		m += 1
		sim.tick(1.0)
		f.tick(1.0, sim)
	check(f.u.system_id == 0, "home again")
	var again := Universe.header(pid, 4.0, "pulsar")
	check(again.name == g.star(pid).name, "a star is the same on every visit")
	sim.c_torch_thr = 0.0
	sim.press("torch_cut")


## Pick Titan by touching the map, light the torch, engage, and arrive in orbit.
func _transit() -> void:
	var f: Flight = main.flight
	var sim: ShipSim = main.sim
	var map: MapScreen = main.panels.map
	var titan := f.u.find("Titan")
	map.mode = "system"
	map.focus(titan)
	map.click(map.screen.global_transform * Vector3.ZERO)
	check(f.c_target == titan, "touching the map's middle picks Titan")
	var secs := f.transit_duration(titan)
	check(secs >= Flight.TRANSIT_MIN and secs <= Flight.TRANSIT_MAX, "flight time to Titan %s" % Flight.duration(secs))
	check(f.transit_blocker(titan, sim) == "TORCH NOT LIT", "will not engage with the torch cold")
	sim.c_torch_arm = true
	sim.c_torch_field = true
	for i in 60:
		sim.tick(1.0)
	sim.press("torch_ignite")
	sim.c_torch_thr = 1.0
	check(sim.torch_lit, "torch lit")
	var fuel := sim.dhe
	check(f.start_transit(titan, sim), "transit engaged")
	var n := 0
	while not f.transit.is_empty() and n < 5000:
		n += 1
		sim.tick(1.0)
		f.tick(1.0, sim)
	check(f.soi == titan, "arrived in Titan's sphere (%d s)" % n)
	sim.c_torch_thr = 0.0
	sim.press("torch_cut")
	f.thrust = 0.0
	for i in 10:
		f.tick(1.0, sim)
	var e := f.elements
	check(e.e < 0.05 and e.pe > float(f.u.bodies[titan].radius), "in a round orbit, ecc %.3f, alt %.0f km" % [e.e, f.altitude() / 1000.0])
	check(sim.dhe < fuel, "the transit burned %.0f kg of D-He3" % (fuel - sim.dhe))


## With the torch lit at full throttle the keeper floats where they are.
func _torch_push() -> void:
	var sim: ShipSim = main.sim
	var p: Player = main.player
	sim.c_torch_arm = true
	sim.c_torch_field = true
	for i in 60:
		sim.tick(1.0)
	sim.press("torch_ignite")
	sim.c_torch_thr = 1.0
	p.release_grip()
	p.global_position = Vector3(0, 0, -5.1)
	p.velocity = Vector3.ZERO
	for i in 120:
		await get_tree().physics_frame
	check(sim.torch_thrust > 0.0 and p.velocity.length() < 0.05, "torch burning, keeper not pushed (%.2f m/s)" % p.velocity.length())
	sim.c_torch_thr = 0.0
	sim.press("torch_cut")
	sim.c_torch_arm = false


func _body() -> void:
	var sim: ShipSim = main.sim
	var b: Body = main.body
	b.hunger = 0.7
	b.thirst = 0.7
	var food := sim.food
	main.eat()
	main.drink()
	check(sim.food == food - 1 and b.hunger < 0.3 and b.thirst < 0.3, "ate a ration and drank")
	_calm()
	main.events.next_t = INF
	b.fatigue = 0.8
	main.sleep()
	for i in 3000:
		await get_tree().physics_frame
		if main._sleep_t < 0.0:
			break
	check(b.fatigue < 0.05, "slept it off")
	_calm()
	main.events.next_t = Events.FIRST
	# Breathing is a given: a cabin with no air left harms nobody (only the hatches care).
	var t := Body.new()
	var s2 := ShipSim.new()
	s2.pp_o2 = 0.0
	s2.pp_n2 = 0.0
	for i in 600:
		t.tick(1.0, s2, 0.02, 0.0)
	check(t.alive and t.health > 0.95 and not t.complaints().has("SHORT OF AIR"), "no air: still breathing (the game's licence)")
	# Jupiter's belts.
	var u: Universe = Universe.solar(3)
	var f := Flight.new()
	f.setup(u, u.find("Jupiter"), 6.9911e7 * 6.0, 0.0)
	f.tick(1.0, s2)
	var r := Body.new()
	var s3 := ShipSim.new()
	var secs := 0
	while r.alive and secs < 3600:
		r.tick(1.0, s3, f.dose_rate)
		secs += 1
	check(not r.alive and secs < 1200, "Jupiter's belts (%.0f mSv/h) kill in %d s: %s" % [f.dose_rate, secs, r.cause])
	var u_ok := Body.new()
	var s4 := ShipSim.new()
	for i in 600:
		u_ok.tick(1.0, s4, 0.03)
	check(u_ok.alive and u_ok.health > 0.9, "ten quiet minutes do no harm")


## Scan Titan from orbit, sell the data, order rations, dock the drone, unpack the crate.
func _science() -> void:
	var f: Flight = main.flight
	var sim: ShipSim = main.sim
	var sc: Science = main.science
	var u: Universe = main.galaxy.current()
	main.universe = u
	f.arrive_at(u, u.find("Titan"))
	f.tick(1.0, sim)
	sim.c_lab = true
	sim.c_dish = true
	sim.tick(1.0)
	check(sc.blocker("magnetometer", f, sim) == "BOOM NOT DEPLOYED", "magnetometer wants its boom out")
	sc.c_boom = true
	sc.tick(1.0, f, sim)
	check(sc.boom > 0.0 and sc.boom < 1.0 and sc.blocker("magnetometer", f, sim) == "BOOM STILL GOING OUT", "the boom runs out on its motor (%.2f)" % sc.boom)
	for i in int(Science.BOOM_TIME) + 1:
		sc.tick(1.0, f, sim)
	main.lab.update_boom()
	var tip: Node3D = main.lab._boom_tip
	check(sc.boom >= 1.0 and tip.position.y > Lab.BOOM_LEN * 0.95, "and is all the way out, the sensor %.1f m off the hull" % tip.position.y)
	await _shot("mag_boom", Vector3(4.0, 2.2, -1.0), Vector3(1.2, 1.4, -4.5), 15, true)
	# Picked on the map is not where the station is.
	f.c_target = u.find("Jupiter")
	check(sc.blocker("magnetometer", f, sim) == "IN ORBIT ROUND TITAN: FLY TO JUPITER FIRST", "a body picked on the map elsewhere: the magnetometer says where you are (%s)" % sc.blocker("magnetometer", f, sim))
	f.c_target = u.find("Titan")
	var v := sc.value(u, f.c_target, "magnetometer")
	check(sc.start_scan("magnetometer", f, sim) == "", "magnetometer scan started over Titan")
	for i in int(Science.SCAN_TIME) + 2:
		sc.tick(1.0, f, sim)
	check(sc.packets.size() == 1 and absf(sc.drive_credit() - v) < 0.01, "scan stored: %d MB worth %.1f" % [roundi(sc.drive_mb()), v])
	check(sc.value(u, f.c_target, "magnetometer") < v * 0.5, "the same scan again is worth less")
	f.c_target = u.find("Jupiter")
	f.tick(1.0, sim)
	check(sc.blocker("spectrometer", f, sim) == "TOO FAR: GET CLOSER", "spectrometer cannot see Jupiter from Saturn")
	var c0 := sc.credit
	sc.c_uplink = true
	for i in 120:
		sim.tick(1.0)
		sc.tick(1.0, f, sim)
	check(sc.packets.is_empty() and sc.credit > c0, "uplinked: credit %.1f -> %.1f" % [c0, sc.credit])
	sc.credit = 200.0
	var food := sim.food
	check(sc.order(0, f, sim) == "", "ordered rations")
	sc.c_dock_open = false
	for i in 200:
		sc.tick(1.0, f, sim)
	check(sc.orders.size() == 1 and sc.orders[0].state == "holding", "the drone waits for the port to open")
	sc.c_dock_open = true
	sc.tick(1.0, f, sim)
	check(not sc.crate.is_empty(), "docked at the airlock: a crate in the airlock")
	main.lab.refresh()
	check(main.lab.crate_node.visible, "the crate is there to see")
	sc.unpack(sim)
	check(sim.food == food + 10 and sc.crate.is_empty(), "unpacked ten rations")


func _eva() -> void:
	var sim: ShipSim = main.sim
	var al: AirlockFit = main.airlock
	var su: Suit = main.suit
	var p: Player = main.player
	p.accept_input = true
	# No suit to put on: in the airlock, the button on the reel clips the hose on.
	var lock_z: float = (Station.SPINE["Node"][0] + Station.SPINE["Node"][1]) * 0.5
	p.global_position = Vector3(Station.A + Station.HULL + 1.0, 0, lock_z)
	check(al.reel_it != null and al.reel_it.current_verb() == "Clip on", "the reel's button says CLIP ON")
	await _shot("reel", al.reel_pos + Vector3(-0.75, 0.3, 0.05), al.reel_pos + Vector3(-0.2, 0.05, 0.05))
	p.global_position = Vector3(Station.A + Station.HULL + 1.0, 0, lock_z)
	al.reel_it.complete()
	check(su.clipped and su.worn and al.reel_it.current_verb() == "Unclip", "pressed: clipped on, air down the hose")
	var rq := PhysicsRayQueryParameters3D.create(al.reel_pos + Vector3(0, 0.8, 0), al.reel_pos + Vector3(0, -0.5, 0), Layers.FURNITURE)
	var rh := p.get_world_3d().direct_space_state.intersect_ray(rq)
	check(not rh.is_empty() and (rh.collider as Node).name == "ReelBody", "the hose reel is solid")

	check(al.outer.locked_reason == "", "the outer hatch has no interlock, air or not")
	al.inner.toggle()
	al.update()
	check(al.inner.is_open, "inner hatch opens (pressures equal)")
	al.inner.toggle()
	al.update()
	var cabin := sim.pressure()
	sim.c_lock_mode = 1
	var secs := 0
	while sim.lock_p > 1.0 and secs < 300:
		sim.tick(1.0)
		al.update()
		secs += 1
	check(sim.lock_p <= 1.0, "airlock pumped down in %d s" % secs)
	check(absf(sim.pressure() - cabin - 101.0 * 8.0 / 300.0) < 0.8, "the airlock's air went back into the cabin (%.1f -> %.1f kPa)" % [cabin, sim.pressure()])
	al.update()
	check(al.outer.locked_reason == "", "outer hatch free to open in vacuum")
	al.outer.toggle()
	al.update()
	check(sim.lock_outer_open, "outer hatch open")
	# Outside, suited and clipped on: the hose stops you at its full length, R hauls you in.
	p.release_grip()
	p.global_position = al.reel_pos + Vector3(-1.0, 0.6, 0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(su.clipped, "the umbilical clips on in the airlock")
	p.global_position = al.reel_pos + Vector3(Suit.HOSE_LEN - 3.0, 0.35, 0)
	p.velocity = Vector3(6.0, 0, 0)
	for i in 120:
		await get_tree().physics_frame
	check(not p.in_air, "outside: no air")
	var reach := p.global_position.distance_to(al.reel_pos)
	check(reach < Suit.HOSE_LEN + 1.0 and p.velocity.x <= 0.5, "the hose stops you at its length (%.1f m)" % reach)
	# The rope settles round the hull for a moment first; then the haul runs along it.
	p.velocity = Vector3.ZERO
	for i in 20:
		await get_tree().physics_frame
	reach = p.global_position.distance_to(al.reel_pos)
	Input.action_press("reel")
	for i in 180:
		await get_tree().physics_frame
	Input.action_release("reel")
	var hauled := p.global_position.distance_to(al.reel_pos)
	check(hauled < reach - 1.0, "R hauls you back along the hose (%.1f -> %.1f m)" % [reach, hauled])
	p.velocity = Vector3.ZERO
	# A grip past the hose's reach cannot hold you there: the hose is not endless.
	var far := al.reel_pos + Vector3(Suit.HOSE_LEN + 8.0, 0.35, 0)
	p.global_position = al.reel_pos + Vector3(Suit.HOSE_LEN - 1.0, 0.35, 0)
	p.grab_surface(far, Vector3(-1, 0, 0))
	var worst := 0.0
	for i in 240:
		await get_tree().physics_frame
		worst = maxf(worst, p.global_position.distance_to(al.reel_pos))
	check(worst < Suit.HOSE_LEN + 1.0 and not p.anchored, "pulling at a grip past the hose's length: the hose wins (%.1f m)" % worst)
	# The hose itself is something to take hold of.
	p.velocity = Vector3.ZERO
	p.global_position = al.reel_pos + Vector3(6.0, 1.5, 0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var mid: Vector3 = al.reel_pos
	for cs: CollisionShape3D in main.hose._shapes:
		if not cs.disabled and cs.global_position.distance_to(p.global_position) < 2.2:
			mid = cs.global_position
	var q := PhysicsRayQueryParameters3D.create(p.global_position, p.global_position + (mid - p.global_position) * 3.0, Layers.HOSE)
	var hh := p.get_world_3d().direct_space_state.intersect_ray(q)
	check(not hh.is_empty() and (hh.collider as Node).is_in_group("hose"), "the hand can catch the umbilical")
	if not hh.is_empty():
		p.grab_surface(hh.position, hh.normal, hh.collider)
		# A heavy body: it takes a while to come in from a few metres off.
		for i in 300:
			await get_tree().physics_frame
		check(p.anchored and p.global_position.distance_to(hh.position) < 0.8, "pulled in to the hose (%.2f m off)" % p.global_position.distance_to(hh.position))
		p.release_grip()
	p.velocity = Vector3.ZERO
	# The solar wings are solid: a hand reaching for one finds it.
	for sx in [-1.0, 1.0]:
		var top := Vector3(sx * (Station.WING_X0 + 5.0), Station.WING_Y + 4.0, Station.WING_Z + 0.6)
		var wq := PhysicsRayQueryParameters3D.create(top, top + Vector3(0, -8.0, 0), Layers.HAND_RAY)
		var wh := p.get_world_3d().direct_space_state.intersect_ray(wq)
		check(not wh.is_empty() and absf(wh.position.y - Station.WING_Y) < 3.0, "the %s solar wing is solid" % ("port" if sx < 0.0 else "starboard"))
	main.toggle_clip()
	check(not su.clipped, "the hose unclips anywhere")
	main.toggle_clip()
	# Back in: close the outer hatch, repress, take the suit off.
	al.outer.toggle()
	al.update()
	# Open the outer hatch on a full airlock: the air takes the keeper with it.
	sim.c_lock_mode = 2
	for i in 120:
		sim.tick(1.0)
		al.update()
	check(sim.lock_p > 90.0, "airlock full of air again")
	var node_z: float = (Station.SPINE["Node"][0] + Station.SPINE["Node"][1]) * 0.5
	p.global_position = Vector3(Station.A + Station.HULL + 1.5, 0, node_z)
	p.velocity = Vector3.ZERO
	check(al.outer.locked_reason == "", "no interlock on the outer hatch")
	al.outer.toggle()
	al.update()
	check(p.velocity.x > 8.0 and p.surge_t > 0.0, "blown out toward the hatch at %.1f m/s" % p.velocity.length())
	sim.tick(1.0)
	al.update()
	check(sim.lock_p < 1.0, "the airlock is empty")
	al.outer.toggle()
	al.update()
	p.velocity = Vector3.ZERO
	p.global_position = Vector3(Station.A + Station.HULL + 1.5, 0, node_z)
	sim.c_lock_mode = 2
	for i in 120:
		sim.tick(1.0)
		al.update()
	check(sim.lock_equal(), "repressed (%.1f kPa)" % sim.lock_p)
	p.global_position = Vector3(2.1, 0, -7.6)
	p.velocity = Vector3.ZERO
	if su.clipped:
		main.toggle_clip()
	check(not su.worn and not su.clipped, "unclipped in the repressed airlock")
	sim.c_lock_mode = 0
	# Both hatches open empties the station; shutting the outer one stops it. (In the sim
	# only: the real hatches would blow the unsuited keeper out of the Node.)
	sim.lock_inner_open = true
	sim.lock_outer_open = true
	sim.tick(1.0)
	check(sim.leak_area_extra > 0.0, "both hatches open: the station is leaking")
	sim.lock_outer_open = false
	sim.tick(1.0)
	var p0 := sim.pressure()
	for i in 30:
		sim.tick(1.0)
	check(sim.leak_area_extra == 0.0 and sim.pressure() >= p0 - 0.05, "outer hatch shut: the leak stops (%.1f -> %.1f kPa)" % [p0, sim.pressure()])
	sim.lock_inner_open = false
	al.update()
	sim.pp_o2 = 21.0
	sim.pp_n2 = 79.0
	sim.tick(1.0)


func _events() -> void:
	var sim: ShipSim = main.sim
	var ev: Events = main.events
	var dmg: Damage = main.damage
	ev._fire("micrometeoroid", sim)
	await get_tree().process_frame
	dmg.apply(sim)
	check(dmg.breaches.size() == 1 and sim.leak_area > 0.0, "a micrometeoroid holed the hull")
	# The hole bleeds the warmth away; and say the hit shorted the gear beside it.
	dmg.breaches[0]["breaker"] = "galley"
	dmg.apply(sim)
	var warm := sim.cab_t
	for i in 120:
		sim.tick(1.0)
	check(sim.pressure() > 98.0, "it hisses, but life support makes up the air (%.1f kPa after two minutes)" % sim.pressure())
	check(sim.cab_t < warm - 2.0, "but the station grows cold (%.1f -> %.1f C)" % [warm - 273.15, sim.cab_t - 273.15])
	sim.brk["galley"] = true
	sim.tick(1.0)
	check(not sim.brk["galley"], "the shorted breaker will not stay in while the hole is open")
	var node: Node3D = main.damage_view._breach_nodes.values()[0]
	var kits := sim.patches
	(node.get_meta("it") as Interactable).on_use.call()
	dmg.apply(sim)
	check(dmg.breaches.is_empty() and sim.patches == kits - 1 and sim.leak_area == 0.0, "patched with a kit")
	sim.brk["galley"] = true
	sim.tick(1.0)
	check(sim.brk["galley"], "patched: the breaker stays in again")
	sim.cab_t = warm
	dmg.break_part("dish")
	main.science.dish_ok = not dmg.is_broken("dish")
	check(not main.science.link_ok(main.flight, sim), "a broken dish cuts the link")
	await get_tree().process_frame
	(main.damage_view._part_nodes["dish"].get_child(main.damage_view._part_nodes["dish"].get_child_count() - 1) as Interactable).on_use.call()
	check(not dmg.is_broken("dish"), "the dish mended on a spacewalk")
	ev.flare = -1.0
	check(ev.flare_dose("Life support") < ev.flare_dose("Habitation") * 0.2, "the shelter keeps most of a flare out")
	ev.flare = INF
	ev._fire("failure", sim)
	var tripped := false
	for b: String in sim.brk:
		if not sim.brk[b]:
			tripped = true
			sim.brk[b] = true
	check(tripped, "a failure trips a breaker")
	# The Office and the way home.
	var st: Story = main.story
	st.tick(main.flight, main.galaxy, main.science)
	check(st.log.size() >= 1, "the Office has written")
	# Only listen for the ending: the real one would end the game, clear the save and reload.
	var ended := [""]
	st.ending.disconnect(main._on_ending)
	st.ending.connect(func(k: String) -> void: ended[0] = k)
	for k in 6:
		main.galaxy.visited[100 + k] = ["test", "red dwarf"]
	var f: Flight = main.flight
	var u := Universe.solar(1)
	f.arrive_at(u, u.find("Earth"))
	st.tick(f, main.galaxy, main.science)
	check(ended[0] == "home", "five stars and back in Earth orbit: the way home")
	st.ending.connect(main._on_ending)
	check(Story.epilogue("horizon").size() > 0 and Story.epilogue("stay").size() > 0, "every ending has its epilogue")


## Sleep passes hours at a gallop, rests the keeper, costs food and water; an alarm wakes.
func _sleep() -> void:
	var b: Body = main.body
	var sim: ShipSim = main.sim
	main.events.next_t = INF
	_calm()
	var on := []
	for k: String in sim.alarms:
		if sim.alarms[k] and ShipSim.ALARMS[k][1]:
			on.append(k)
	check(on.is_empty(), "no warnings before bed %s" % str(on))
	b.fatigue = 0.1
	main.sleep()
	check(main._sleep_t < 0.0, "not tired: no sleep")
	b.fatigue = 0.8
	b.hunger = 0.2
	b.thirst = 0.2
	var t0: float = main.flight.t
	main.sleep()
	var frames := 0
	while main._sleep_t >= 0.0 and frames < 3000:
		await get_tree().physics_frame
		frames += 1
	var slept: float = main.flight.t - t0
	check(slept > 300.0, "slept %s of game time in %d frames" % [Flight.game_duration(slept), frames])
	check(b.fatigue < 0.15, "rested (fatigue %.2f)" % b.fatigue)
	check(b.hunger > 0.3 and b.thirst > 0.3, "hungrier and thirstier on waking (%.2f, %.2f)" % [b.hunger, b.thirst])
	_calm()
	# An alarm cuts the night short.
	b.fatigue = 0.9
	b.hunger = 0.1
	b.thirst = 0.1
	t0 = main.flight.t
	main.sleep()
	while main._sleep_t < 2.0:
		await get_tree().physics_frame
	for i in 20:
		await get_tree().physics_frame
	check(main._sleep_left > 0.0 and main.flight.t - t0 > 60.0, "the hours go by (%s)" % Flight.game_duration(main.flight.t - t0))
	check(main.hud.night != "", "the dark shows how long you have slept (%s)" % main.hud.night)
	if "--shots" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://screenshots/rebuild/asleep.png")
	# A warning: the cabin pressure falls (CABIN PRESS).
	sim.pp_n2 = 40.0
	frames = 0
	while main._sleep_t >= 0.0 and frames < 3000:
		await get_tree().physics_frame
		frames += 1
		if main._wake != "":
			sim.pp_n2 = 79.0
	check(main._wake == "The alarm woke you" and main.flight.t - t0 < 0.9 * 540.0, "the alarm woke the keeper early (%s)" % Flight.game_duration(main.flight.t - t0))
	_calm()
	# So does a micrometeoroid on the hull.
	b.fatigue = 0.9
	main.sleep()
	while main._sleep_t < 2.0:
		await get_tree().physics_frame
	for i in 20:
		await get_tree().physics_frame
	main.events._fire("micrometeoroid", sim)
	frames = 0
	while main._sleep_t >= 0.0 and frames < 3000:
		await get_tree().physics_frame
		frames += 1
	check(main._wake == "A bang on the hull woke you", "a bang on the hull woke the keeper (%s)" % main._wake)
	_calm()
	main.events.next_t = Events.FIRST


## Whatever the hours asleep did to the station (a stray micrometeoroid, a little air
## lost), put right so the next checks start from a sound station.
func _calm() -> void:
	var sim: ShipSim = main.sim
	main.damage.breaches.clear()
	main.damage.broken.clear()
	main.damage.apply(sim)
	sim.leak_area = 0.0
	sim.pp_o2 = 21.0
	sim.pp_n2 = 79.0
	sim.pp_co2 = 0.3
	sim.tick(1.0)
	main.body.hunger = 0.2
	main.body.thirst = 0.2
	main.body.health = 1.0
	for k: String in sim.brk:
		sim.brk[k] = true
	sim.tick(1.0)


## The manual floats in the cockpit and turns its pages; the camera takes a photo that comes
## out as a print; the print pins up on the board in Habitation.
func _props() -> void:
	var hand: Hand = main.player.hand
	var p: Player = main.player
	var manual: Prop = null
	var cam: Prop = main.photos.camera
	for n in get_tree().get_nodes_in_group("props"):
		if n is Prop and (n as Prop).kind == "manual":
			manual = n
	check(manual != null and main.station.module_at(manual.global_position) == "Command deck", "the station manual floats in the command deck")
	# Small loose things throw no shadow (by a lamp, a book's covered half a module in black).
	var shady := 0
	for pr in get_tree().get_nodes_in_group("props"):
		if (pr as Prop).kind in Prop.NO_SHADOW:
			for g in (pr as Node).find_children("*", "GeometryInstance3D", true, false):
				if (g as GeometryInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
					shady += 1
	check(shady == 0, "the manual, torch, Geiger counter, camera and prints cast no shadow (%d meshes do)" % shady)
	if manual:
		p.release_grip()
		p.global_position = manual.global_position + Vector3(0, 0, 0.6)
		p.look_at_point(manual.global_position)
		hand._pick(manual, manual.global_position)
		hand.adjust_hold(-0.06)
		hand.adjust_hold(-0.06)
		check(int(manual.get_meta("page")) == 2, "the wheel turns the manual's pages (page %d)" % int(manual.get_meta("page")))
		if "--shots" in OS.get_cmdline_user_args():
			hand.adjust_hold(0.06)
			for i in 10:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://screenshots/rebuild/manual.png")
		hand.drop()
	# The camera: a photo costs a shot and comes out as a print.
	var film: int = main.sim.film
	p.global_position = Vector3(0, 0, -4.3)
	p.look_at_point(Vector3(0, 0, -7.0))
	if "--shots" in OS.get_cmdline_user_args():
		cam.freeze = true
		cam.global_position = p.global_position + Vector3(0.12, -0.05, -0.42)
		cam.global_basis = Basis(Vector3.UP, 0.5) * Basis(Vector3.RIGHT, 0.25)
		for i in 12:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://screenshots/rebuild/camera.png")
		cam.freeze = false
	hand._pick(cam, cam.global_position)
	check(hand.held == cam, "LMB on the camera: in the hand")
	main.photos.use(cam)
	check(main.photos.aiming and hand.aiming, "E: the camera up at the eye, the finder on")
	if "--shots" in OS.get_cmdline_user_args():
		for i in 20:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://screenshots/rebuild/viewfinder.png")
	hand.press()
	for i in 6:
		await get_tree().process_frame
	while main.photos._busy:
		await get_tree().process_frame
	hand.unpress()
	check(hand.held == cam, "up at the eye the hand keeps hold without the button")
	main.photos.use(cam)
	check(not main.photos.aiming and hand.held == null, "E again: down it comes, and with LMB not held it is let go")
	var print_prop: Prop = null
	for n in get_tree().get_nodes_in_group("props"):
		if n is Prop and (n as Prop).kind == "photo":
			print_prop = n
	check(main.sim.film == film - 1 and print_prop != null and FileAccess.file_exists(String(print_prop.get_meta("file"))), "click: a print slides out (%d shots left)" % main.sim.film)
	hand.drop()
	if print_prop:
		hand._pick(print_prop, print_prop.global_position)
		var before: int = main.photos.pinned.size()
		var bt0: Transform3D = main.photos.board.global_transform
		p.global_position = bt0.origin + bt0.basis.z * 0.7
		p.look_at_point(bt0.origin)
		hand.unpress()
		check(main.photos.pinned.size() == before + 1 and hand.held == null, "let go over the board: the print pins up in Habitation")
		if "--shots" in OS.get_cmdline_user_args():
			var bt: Transform3D = main.photos.board.global_transform
			p.global_position = bt.origin + bt.basis.z * 0.9
			p.look_at_point(bt.origin)
			for i in 20:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://screenshots/rebuild/photo_board.png")
	main.sim.film = film
	# Leave no test prints behind on disk.
	for e: Dictionary in main.photos.pinned:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(String(e.file)))


## A derelict: the station comes up beside it, docks it at the docking port, PRESSURIZE fills it
## until the port hatch will open, a thing aboard is taken into the stores, and it is let go.
func _salvage() -> void:
	var f: Flight = main.flight
	var sim: ShipSim = main.sim
	var dv: DerelictView = main.derelict_view
	var dk: DockFit = main.dock
	var st: Station = main.station
	var u := f.u
	var ds: Array[int] = []
	for i in u.bodies.size():
		if u.bodies[i].kind == "derelict":
			ds.append(i)
	check(ds.size() == 5, "five derelicts in the Solar System (%d)" % ds.size())
	var d := -1
	for i in ds:
		if u.bodies[u.bodies[i].parent].name == "Titan":
			d = i
	check(d >= 0 and is_equal_approx(f.transit_radius(d), Flight.DERELICT_STANDOFF), "one round Titan; a transit stops %d m off it" % roundi(Flight.DERELICT_STANDOFF))
	if d < 0:
		return
	# Beside it, as a transit leaves the station.
	_alongside(d)
	for i in 4:
		await get_tree().process_frame
	check(dv.shown == d and dv.model != null, "it is there to see, %d m off" % roundi(Orbit.length(Orbit.sub(u.position(d, f.t), f.world_pos()))))
	check(f.transit_blocker(d, sim) == "ALONGSIDE: DOCK AT THE PORT", "the map says: dock at the port")
	var shots := "--shots" in OS.get_cmdline_user_args()
	var p: Player = main.player
	if shots:
		var at: Vector3 = dv.model.global_position
		p.global_position = at + Vector3(9.0, 4.0, 7.0)
		p.look_at_point(at + Vector3(2.0, 0, 0))
		for i in 15:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://screenshots/rebuild/derelict_out.png")
	var ph := dk.port_hatch()
	var nz: float = (Station.SPINE["Node"][0] + Station.SPINE["Node"][1]) * 0.5
	await _shot("dock_from_node", Vector3(0.45, 0.05, nz), Vector3(-2.0, 0.0, nz))
	await _shot("dock_panel", Vector3(-1.28, 0.05, nz + 0.3), dk.panel.global_position)
	p.release_grip()
	p.global_position = Vector3(0, 0, -7.6)
	dk.update()
	check(ph.locked_reason.begins_with("Vacuum"), "nothing docked: the port hatch stays shut on vacuum")
	check(dv.dock() == "" and f.docked and f.transit_blocker(f.c_target, sim) == "UNDOCK FIRST", "DOCK: it comes in; no transit while it is on")
	dv._dock_s = 0.995
	for i in 120:
		await get_tree().process_frame
		if dv.is_docked():
			break
	var pose := dv.dock_pose()
	check(dv.is_docked() and dv.model.transform.origin.distance_to(pose.origin) < 0.01 and pose.origin.x < -Station.A, "docked at the port, off the Node's port side")
	check(sim.port_vol > 5.0 and sim.port_p < 0.5, "it is airless (%.1f m3, %.1f kPa)" % [sim.port_vol, sim.port_p])
	dk.update()
	check(ph.locked_reason.begins_with("Pressure"), "the port hatch will not open on it: the pressure differs")
	# PRESSURIZE: air from the tanks until it is the cabin's.
	sim.c_port_press = true
	var secs := 0
	while not sim.port_equal() and secs < 200:
		sim.tick(1.0)
		secs += 1
	sim.c_port_press = false
	check(sim.port_equal(), "PRESSURIZE fills it in %d s" % secs)
	dk.update()
	check(ph.locked_reason == "", "equal: the port hatch is free")
	ph.toggle()
	dk.update()
	check(ph.is_open and sim.port_open, "the port hatch opens into it")
	check(dv.undock_blocker() == "SHUT THE PORT HATCH FIRST", "no UNDOCK with the hatch open")
	for i in 150:
		await get_tree().physics_frame
	# Through the hatch and into it, breathing its air.
	var axis := -ph.global_basis.x.normalized()
	p.release_grip()
	p.global_position = ph.global_position - axis * 0.6 - Vector3(0, p.cam.position.y, 0)
	for i in 150:
		p.velocity = axis * 1.2
		await get_tree().physics_frame
	check(dv.aboard(p.global_position), "a keeper drifts through the port hatch into the derelict")
	check(main.pressure_here() > 90.0 and p.in_air, "aboard it there is air to breathe (%.1f kPa)" % main.pressure_here())
	if shots:
		p.global_position = pose * Vector3(DerelictView.COLLAR + 0.5, 0.1, 0.0)
		p.look_at_point(pose * Vector3(DerelictView.COLLAR + 3.0, 0.0, 0.0))
		for i in 15:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://screenshots/rebuild/derelict_in.png")
		await _shot("derelict_docked", pose.origin + Vector3(-1.0, 3.0, 5.5), pose.origin + Vector3(-1.5, 0, 0), 15, true)
	# Take the first thing aboard.
	var first: Interactable = null
	for n in dv.model.find_children("*", "Interactable", true, false):
		first = n
		break
	var before: Dictionary = sim.to_dict()
	var taken := 0
	if first:
		first.complete()
		taken = (main.salvage.taken.get("0:%d" % d, []) as Array).size()
	var changed := false
	var after: Dictionary = sim.to_dict()
	for k: String in ["food", "water", "dhe", "hyd", "patches", "pills", "film", "rx_fresh"]:
		if after.get(k) != before.get(k):
			changed = true
	check(taken == 1 and changed, "a thing taken aboard goes into the stores")
	p.release_grip()
	p.velocity = Vector3.ZERO
	p.global_position = Vector3(0, 0, -7.6)
	ph.is_open = false
	dk.update()
	check(dv.undock() == "" and not f.docked and sim.port_vol == 0.0 and main.salvage.air == 0.0, "UNDOCK (hatch shut): it lets go, its air with it")
	dk.update()
	check(ph.locked_reason.begins_with("Vacuum"), "vacuum beyond the port again")
	# Dock again, go aboard behind a shut hatch, and let go with the keeper inside: carried off.
	dv._undock_s = -1.0
	main.salvage.docked = d
	f.docked = true
	dv._dock_s = -1.0
	sim.port_vol = dv.volume()
	await get_tree().process_frame
	main.suit.worn = true
	p.release_grip()
	p.velocity = Vector3.ZERO
	p.global_position = dv.dock_pose() * Vector3(1.8, 0, 0)
	check(dv.undock() == "", "UNDOCK with the keeper aboard behind a shut hatch: allowed")
	dv._undock_s = 0.4
	for i in 10:
		await get_tree().process_frame
	check(dv.aboard(p.global_position) and p.global_position.distance_to(dv.dock_pose().origin) > 2.5 and main.pressure_here() == 0.0, "the keeper is carried off inside it, in vacuum (%.1f m out)" % p.global_position.distance_to(dv.dock_pose().origin))
	p.global_position = Vector3(0, 0, -7.6)
	p.velocity = Vector3.ZERO
	main.suit.worn = false
	main.salvage.taken.clear()
	main.salvage.docked = -1
	dv._undock_s = -1.0


## Put the station a stone's throw off body b, as a transit would leave it.
func _alongside(b: int) -> void:
	var f: Flight = main.flight
	var u := f.u
	var par: int = u.bodies[b].parent
	var rel := Orbit.sub(u.position(b, f.t), u.position(par, f.t))
	var rv := Orbit.sub(u.velocity(b, f.t), u.velocity(par, f.t))
	f.transit = {}
	f.soi = par
	f.st = Orbit.state(Orbit.add(rel, Orbit.v3(60.0, 20.0, 0.0)), rv)
	f.c_target = b


## Whole modules: one waits round Enceladus, Europa and Phobos each. Docked at the port, a
## module is the station's for good: its air, its hatch, the port moved out to its far end,
## gone from the map; its effects on the station; and cast off again, it takes those beyond it.
func _docking() -> void:
	var f: Flight = main.flight
	var sim: ShipSim = main.sim
	var dv: DerelictView = main.derelict_view
	var dk: DockFit = main.dock
	var st: Station = main.station
	var p: Player = main.player
	var u := f.u
	# Put the station back where it was afterwards (Enceladus is deep in Saturn's belts).
	var was := [f.soi, f.st, f.c_target]
	var mods := {}
	for i in u.bodies.size():
		if u.bodies[i].kind == "module":
			mods[String(u.bodies[i].get("class", ""))] = i
			check(String(u.bodies[u.bodies[i].parent].name) in ["Enceladus", "Europa", "Phobos"], "%s waits round %s" % [u.bodies[i].get("class", ""), u.bodies[u.bodies[i].parent].name])
	check(mods.size() == 3, "three whole modules in the Solar System (%d)" % mods.size())
	if mods.size() < 3:
		return
	var g: int = mods["GREENHOUSE"]
	check(is_equal_approx(f.transit_radius(g), Flight.DERELICT_STANDOFF), "a transit stops beside a module too")
	_alongside(g)
	for i in 4:
		await get_tree().process_frame
	check(dv.shown == g and dv.model != null and not dv.aboard(dv.model.global_position + Vector3(0, 0, 0)), "the greenhouse is there to see, sealed")
	await _shot("module_out", dv.model.global_position + Vector3(4.0, 3.0, 5.0), dv.model.global_position + Vector3(-1.0, 0, 0), 15, true)
	p.release_grip()
	p.global_position = Vector3(0, 0, -7.6)
	var face0 := st.port_face()
	var food := sim.food
	check(dv.dock() == "", "DOCK the greenhouse")
	dv._dock_s = 0.995
	for i in 60:
		await get_tree().process_frame
		if sim.modules.size() > 0:
			break
	check(sim.modules == ["GREENHOUSE"] and st.port_chain.size() == 1 and not f.docked and main.salvage.docked == -1, "it is part of the station now (%s)" % str(sim.modules))
	check(u.bodies[g].get("gone", false) and f.transit_blocker(g, sim) == "ALREADY PART OF THE STATION" and dv.nearest(DerelictView.SHOW_RANGE) != g, "and gone from the map")
	check(is_equal_approx(st.port_face(), face0 + PortModules.length_of("GREENHOUSE") + Station.END_T) and dk.hatches.size() == 2, "the port is at its far end now")
	var node_z: float = (Station.SPINE["Node"][0] + Station.SPINE["Node"][1]) * 0.5
	var inside := Vector3(-(face0 + 1.0), 0, node_z)
	check(st.module_at(inside) == "Greenhouse", "inside it is the Greenhouse (%s)" % st.module_at(inside))
	p.global_position = inside
	check(main.pressure_here() > 90.0, "with the cabin's air in it")
	# The Dock's hatch is between air and air now; the port's is the greenhouse's far one.
	dk.update()
	check(dk.hatches[0].locked_reason == "" and dk.port_hatch().locked_reason.begins_with("Vacuum"), "the Dock's hatch is free; the new port hatch holds the vacuum")
	# Its trays: ripe in two hours of the day, picked by hand.
	sim.crop = 0.0
	for i in 125:
		sim.tick(1.0)
	check(sim.crop >= 1.0, "a tray ripe after two hours (%.2f)" % sim.crop)
	main.pick_crop()
	check(sim.food > food and sim.crop < 1.0, "picked: food %d -> %d" % [food, sim.food])
	await _shot("module_greenhouse", Vector3(-(face0 + 0.25), 0.1, node_z), Vector3(-(face0 + 2.2), -0.2, node_z))
	# The other two, docked on the end one after the other.
	var cap := sim.bat_cap()
	var sol := sim.solar_max()
	main._module_home(mods["POWER MODULE"])
	main._module_home(mods["OBSERVATORY"])
	await get_tree().process_frame
	check(sim.modules == ["GREENHOUSE", "POWER MODULE", "OBSERVATORY"] and st.port_chain.size() == 3 and dk.hatches.size() == 4, "three modules out from the port in a row")
	check(is_equal_approx(sim.bat_cap(), cap + ShipSim.POWER_MODULE_KWH) and is_equal_approx(sim.solar_max(), sol + ShipSim.POWER_MODULE_KW), "the power module: battery %d -> %d kWh, solar %.0f -> %.0f kW" % [cap, sim.bat_cap(), sol, sim.solar_max()])
	check(is_equal_approx(main.science.bonus, 1.5) and main.science.value(u, u.find("Titan"), "telescope") > 0.0, "the observatory: every scan worth x%.1f" % main.science.bonus)
	check(dv.dock_pose().origin.distance_to(st.port_xform().origin) < 0.001 and st.port_xform().origin.x < -(face0 + 6.0), "the next thing docks at the observatory's far end")
	# Saved and loaded (into copies: never the keeper's own save): the same modules, still off the map.
	var s2 := ShipSim.new()
	s2.from_dict(sim.to_dict())
	var sv2 := Salvage.new()
	sv2.from_dict(main.salvage.to_dict())
	var u2 := Universe.solar(0)
	sv2.mark(u2)
	var gone2 := 0
	for b in u2.bodies:
		if b.get("gone", false):
			gone2 += 1
	check(s2.modules == sim.modules and ShipSim.module_names(s2.modules) == PackedStringArray(["Greenhouse", "Power module", "Observatory"]) and gone2 == 3, "saved and loaded: %s, %d gone from the map" % [str(s2.modules), gone2])
	await _shot("module_power", Vector3(-(st.port_chain[1].z0 + 0.25), 0.1, node_z), Vector3(-(st.port_chain[1].z1), -0.2, node_z))
	await _shot("module_observatory", Vector3(-(st.port_chain[2].z0 + 0.25), 0.1, node_z), Vector3(-(st.port_chain[2].z1), -0.3, node_z))
	await _shot("modules_outside", Vector3(-4.0, 4.0, node_z + 7.0), Vector3(-5.0, 0, node_z), 15, true)
	await _shot("modules_below", Vector3(-3.0, -5.0, node_z - 6.0), Vector3(-5.0, 0, node_z), 15, true)
	# Its panels' legends fit as well as the station's.
	await _legends()
	# Cast off the power module: the observatory goes with it; the greenhouse's hatch holds.
	dk.hatches[1].is_open = true
	check(main.separation_blocker("Power module") == "SHUT THE HATCH TO IT FIRST", "not with the hatch to it open")
	dk.hatches[1].is_open = false
	p.global_position = Vector3(0, 0, -7.6)
	check(main.separate_module("Power module") == "", "separate the power module")
	check(sim.modules == ["GREENHOUSE"] and st.port_chain.size() == 1 and dk.hatches.size() == 2 and is_equal_approx(sim.bat_cap(), cap), "it went, and the observatory with it (%s)" % str(sim.modules))
	dk.update()
	check(dk.port_hatch() == dk.hatches[1] and dk.port_hatch().locked_reason.begins_with("Vacuum"), "the greenhouse's far hatch is the port again")
	check(main.separate_module("Greenhouse") == "" and sim.modules.is_empty() and dk.hatches.size() == 1 and is_equal_approx(st.port_face(), face0), "and the greenhouse: the port is the Dock's own again")
	p.global_position = Vector3(0, 0, -7.6)
	f.soi = was[0]
	f.st = was[1]
	f.c_target = was[2]


## Screens: every CRT aboard is something to take hold of (LMB pulls the keeper in to it) and
## E brings it up full size; on the map a click picks, the wheel zooms, a drag turns it; E again
## puts it away and hands the controls back.
func _screens() -> void:
	var p: Player = main.player
	var hand: Hand = p.hand
	var sv: ScreenView = main.screen_view
	var map: MapScreen = main.panels.map
	var f: Flight = main.flight
	var terms: Array = main.station.find_children("*", "Terminal", true, false)
	var ready := terms.filter(func(t: Terminal) -> bool: return t.it != null and t.it.grip and t.it.on_open.is_valid())
	check(terms.size() >= 8 and ready.size() == terms.size(), "every screen can be held on to and opened (%d of %d)" % [ready.size(), terms.size()])
	# Hold LMB on the map: pulled in to it.
	var at: Vector3 = map.screen.global_position
	p.release_grip()
	p.velocity = Vector3.ZERO
	p.global_position = at + Vector3(0, 0.75, 0.15) - Vector3(0, p.cam.position.y, 0)
	p.look_at_point(at)
	await get_tree().physics_frame
	await get_tree().physics_frame
	hand.press()
	check(p.anchored and p.anchor_body == map.touch, "LMB on the map takes hold of it")
	var d0 := p.cam.global_position.distance_to(at)
	for i in 90:
		await get_tree().physics_frame
	var d1 := p.cam.global_position.distance_to(at)
	check(d1 < d0 - 0.2, "and pulls the keeper in to it (%.2f -> %.2f m)" % [d0, d1])
	p.look_at_point(at)
	await get_tree().physics_frame
	check(hand.screen_in_view() == map.touch, "the map is the screen in view")
	# E: full size.
	check(hand.open_screen() and sv.is_open() and sv.term == map.screen and not p.accept_input, "E brings the map up full size")
	await get_tree().process_frame
	await _shot("screen_full_map", p.global_position, at, 4)
	# A click in the middle picks what the map is centred on.
	var titan := f.u.find("Titan")
	map.mode = "system"
	map.focus(titan)
	var mid := sv._rect.position + sv._rect.size * 0.5
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = mid
	sv._input(down)
	var up := down.duplicate() as InputEventMouseButton
	up.pressed = false
	sv._input(up)
	check(f.c_target == titan, "a click in the middle of it picks Titan")
	var mpp := map.mpp
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	sv._input(wheel)
	check(map.mpp < mpp, "the wheel zooms in")
	var yaw := map.yaw
	sv._input(down)
	var mv := InputEventMouseMotion.new()
	mv.relative = Vector2(40, 0)
	sv._input(mv)
	sv._input(up)
	check(not is_equal_approx(map.yaw, yaw) and f.c_target == titan, "a drag turns it (and picks nothing)")
	# Click another body where it shows: the map centres on it, and the wheel zooms in on it.
	map.focus(f.u.find("Saturn"))
	for i in 40:
		await get_tree().process_frame
	var rhea := f.u.find("Rhea")
	var rpx := map._to_px(rhea)
	var res := sv.term.pixels()
	var win := sv._rect.position + rpx / res * sv._rect.size
	var mpp0 := map.mpp
	down.position = win
	up.position = win
	sv._input(down)
	sv._input(up)
	for i in 40:
		await get_tree().process_frame
	check(f.c_target == rhea and map.center == rhea and is_equal_approx(map.mpp, mpp0), "a click on Rhea picks it and centres the map on it, at the same scale")
	for i in 3:
		sv._input(wheel)
	for i in 40:
		await get_tree().process_frame
	var mid_px := map._to_px(rhea)
	if "--shots" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://screenshots/rebuild/screen_full_rhea.png")
	check(mid_px.distance_to(res * 0.5) < 2.0, "zoomed in, Rhea stays in the middle (%s)" % str(mid_px))
	# E again: put away, the controls back.
	var e := InputEventAction.new()
	e.action = "use_item"
	e.pressed = true
	sv._input(e)
	check(not sv.is_open() and p.accept_input, "E puts it away and the controls come back")
	p.release_grip()
	# Any other screen opens too (just looked at, not held on to).
	var rs: Terminal = main.panels.reactor_screen
	rs.it.on_open.call()
	check(sv.is_open() and sv.term == rs and sv.term.click_fn.is_valid() == false, "the reactor screen opens full size too")
	await _shot("screen_full_reactor", p.global_position, at, 4)
	sv.close()
	check(not sv.is_open() and p.accept_input, "and is put away")
	# CONTACTS beside the map: the derelicts and modules here, nearest first; a line picks one.
	map.screen.it.on_open.call()
	await get_tree().process_frame
	var cs: Array = map.contacts()
	check(cs.size() >= 3 and sv._list_title.visible and sv._row_ids.size() == cs.size(), "CONTACTS beside the map: %d in this system" % cs.size())
	var first: int = cs[0][0]
	var row_at := sv._rows[0].get_global_rect().get_center()
	var pick := InputEventMouseButton.new()
	pick.button_index = MOUSE_BUTTON_LEFT
	pick.pressed = true
	pick.position = row_at
	sv._input(pick)
	check(f.c_target == first and map.center == first, "a line picked: %s is the destination, the map on it" % f.u.bodies[first].name)
	for i in 40:
		await get_tree().process_frame
	await _shot("screen_full_contacts", p.global_position, at, 4)
	sv.close()
	# The nav screen under the map: what to do next to fly where the map points.
	var f2: Flight = main.flight
	f2.c_target = f2.u.find("Titan") if f2.soi != f2.u.find("Titan") else f2.u.find("Rhea")
	f2.transit = {}
	f2.docked = false
	# Whatever the earlier sections left: nav powered, fuel aboard, the torch cold.
	main.sim.c_nav = true
	main.sim.brk["nav"] = true
	main.sim.dhe = 18000.0
	main.sim.torch_field = 0.0
	main.sim.torch_lit = false
	main.sim.c_torch_thr = 0.0
	main.sim.c_torch_arm = true
	main.sim.tick(0.1)
	main.panels.refresh()
	var nav: String = main.panels.nav_screen._src
	check(nav.contains("[X] 1 TORCH ARM") and nav.contains("--> 2 NOZZLE FIELD"), "the nav screen ticks off the torch's steps (ARM done, FIELD next)%s" % ("" if nav.contains("--> 2") else ": " + nav.right(240).replace("
", " | ")))
	main.panels.nav_screen.it.on_open.call()
	await _shot("screen_full_nav", p.global_position, at, 4)
	sv.close()
	main.sim.c_torch_arm = false


func _shot(name: String, at: Vector3, look: Vector3, frames := 15, floodlit := false) -> void:
	if not "--shots" in OS.get_cmdline_user_args():
		return
	var flood: OmniLight3D = null
	var suited: bool = main.suit.worn
	if floodlit:
		# Outside: suited (no tunnel vision from the vacuum), and a work light for the picture.
		flood = OmniLight3D.new()
		flood.omni_range = 40.0
		flood.light_energy = 2.5
		flood.omni_attenuation = 0.6
		flood.position = at + Vector3(0, 2.0, 0)
		main.add_child(flood)
	var p: Player = main.player
	p.release_grip()
	p.global_position = at
	p.velocity = Vector3.ZERO
	p.look_at_point(look)
	# A clean picture: no messages, no cursor or hints over it.
	var was_cinematic: bool = main.hud.cinematic
	main.hud.cinematic = true
	main.hud._toasts.clear()
	for i in frames:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://screenshots/rebuild/%s.png" % name)
	main.hud.cinematic = was_cinematic
	if flood:
		flood.queue_free()
		main.suit.worn = suited


## The reactor module: a refuel by hand from SCRAM to sealed head, the recycler, a leak, the
## Geiger counter's clicks, the melt clock and, last of all, casting the module off.
func _reactor() -> void:
	var sim: ShipSim = main.sim
	var rb: ReactorBay = main.reactor
	var st: Station = main.station
	var hand: Hand = main.player.hand
	var p: Player = main.player
	check(st.module_at(Vector3(0, 0, 1.0)) == "Reactor" and rb.root != null, "the reactor module is aft of Life support")
	check(st.module_at(main.geiger.prop.global_position) == "Life support", "the Geiger counter waits in Life support")
	var rbook: Prop = null
	for n in get_tree().get_nodes_in_group("props"):
		if n is Prop and (n as Prop).kind == "manual" and n.get_meta("book", "") == "reactor":
			rbook = n
	check(rbook != null and st.module_at(rbook.global_position) == "Reactor" and Manual.count("reactor") > 10, "the reactor manual floats in the reactor module (%d pages)" % Manual.count("reactor"))
	if rbook and "--shots" in OS.get_cmdline_user_args():
		var hand0: Hand = main.player.hand
		main.player.release_grip()
		main.player.global_position = rbook.global_position + Vector3(0, 0, -0.6)
		main.player.look_at_point(rbook.global_position)
		hand0._pick(rbook, rbook.global_position)
		rbook.set_meta("page", 2)
		await _shot("reactor_manual", main.player.global_position, rbook.global_position, 20)
		rbook.set_meta("page", 0)
		await _shot("reactor_manual_cover", main.player.global_position, rbook.global_position, 5)
		hand0.drop()
	await _shot("reactor_room", Vector3(0.25, 0.2, -0.15), Vector3(0, -0.05, ReactorBay.SHIELD_Z))
	# The counter: a trickle in the cabin, a crackle by the shield with the core running.
	var calm := main.dose_at(Vector3(0, 0, -7.6)) as float
	check(Geiger.cps(calm) < 4.0, "the counter ticks slowly in Habitation (%.1f/s at %.3f mSv/h)" % [Geiger.cps(calm), calm])
	# Refuel: the head will not open with the reactor running.
	sim.rx_scrammed = false
	sim.rx_power = 0.3
	check(sim.head_blocker() != "", "the core head stays shut while the reactor runs: %s" % sim.head_blocker())
	sim.press("rx_scram")
	sim.rx_power = 0.0
	sim.rx_t = 500.0
	sim.rx_loop_p = 0.5
	check(sim.head_blocker() == "", "scrammed and cool: the head may be opened")
	sim.rx_fuel = [0.97, 0.99, 0.96]
	check(sim.fuel_reactivity() < 0.3, "a spent load: FUEL LOW (%.2f)" % sim.fuel_reactivity())
	rb.head_it.complete()
	rb.update(0.1)
	check(sim.rx_head_open and rb.slots[0].enabled and sim.rx_boom == "", "the head unseals; the slots are open to the hand")
	p.global_position = Vector3(0, 0, 1.0)
	var room := rb.dose_here(p.global_position)
	check(room > 50.0, "the room is hot with the head open (%d mSv/h)" % roundi(room))
	check(Geiger.cps(room) > 30.0, "and the counter roars there (%.0f/s)" % Geiger.cps(room))
	hand.drop()
	rb.slots[0].complete()
	var a := hand.held
	check(a != null and a.kind == "fuel" and float(sim.rx_fuel[0]) < 0.0, "hold on a slot: the spent assembly comes out into the hand")
	check(rb.dose_here(p.global_position) > room, "one in the arms adds its own dose")
	rb._feed()
	check(hand.held == null and sim.rc_spent == 1 and sim.rc_material > 10.0, "let go over the hopper: the recycler takes it")
	var rack: Interactable = null
	for n in rb.root.find_children("*", "Interactable", true, false):
		if (n as Interactable).display_name == "Fresh fuel rack":
			rack = n
	var fresh := sim.rx_fresh
	if rack:
		rack.complete()
	check(hand.held != null and hand.held.kind == "fuel" and sim.rx_fresh == fresh - 1, "a fresh one from the rack")
	rb.update(0.1)
	check(rb.slots[0].tool == "fuel" and rb.slots[0].usable_with("fuel"), "the empty slot takes an assembly")
	rb.slots[0].complete()
	check(hand.held == null and is_zero_approx(float(sim.rx_fuel[0])), "let go over the slot: it goes home")
	await _shot("reactor_head", Vector3(0.2, 0.1, 0.8), Vector3(0, -0.08, ReactorBay.SHIELD_Z))
	rb.head_it.complete()
	check(not sim.rx_head_open, "the head sealed again")
	check(sim.fuel_reactivity() > 0.3, "one fresh assembly lifts the core (%.2f)" % sim.fuel_reactivity())
	sim.rx_fuel = [0.3, 0.3, 0.3]
	# The recycler makes what OUTPUT asks for.
	sim.rc_material = 40.0
	sim.rc_spent = 2
	sim.c_rc_output = ReactorBay.RECIPES.size() - 1
	fresh = sim.rx_fresh
	rb.process()
	check(sim.rx_fresh == fresh + 1 and sim.rc_spent == 0 and is_equal_approx(sim.rc_material, 10.0), "the recycler makes a fuel assembly from two spent ones")
	sim.c_rc_output = 0
	var w := sim.water
	rb.process()
	check(sim.water > w and sim.rc_material < 10.0, "and water from scrap")
	await _shot("recycler", Vector3(-0.2, 0.1, 0.5), st.face_xform(6, ReactorBay.FRONT_Z).origin)
	# A coolant leak: it drains the loop; a patch kit seals it.
	main.events._fire("coolant_leak", sim)
	check(sim.rx_leak > 0.0, "a coolant leak")
	rb.update(0.1)
	var kits := sim.patches
	var leak_it: Interactable = null
	if rb._leak:
		for n in rb._leak.find_children("*", "Interactable", true, false):
			leak_it = n
	if leak_it:
		leak_it.complete()
	check(sim.rx_leak == 0.0 and sim.patches == kits - 1, "sealed with a patch kit")
	sim.patches = kits
	# Too hot: the melt clock runs, and stops once it is back under.
	sim.rx_mode = 0
	sim.rx_t = 1800.0
	sim.rx_melt_t = INF
	sim.tick(1.0)
	check(sim.rx_melt_t <= ShipSim.MELT_TIME and sim.alarms.get("rx_melt", false), "an overheating core starts the melt clock (%.0f s)" % sim.rx_melt_t)
	sim.rx_t = 900.0
	sim.tick(1.0)
	check(sim.rx_melt_t == INF, "under the safe line it stops")
	check(Story.epilogue("meltdown").size() > 0, "a meltdown has its epilogue")
	if "--shots" in OS.get_cmdline_user_args():
		var g: Prop = main.geiger.prop
		p.global_position = Vector3(0.1, 0.0, -1.4)
		hand._pick(g, g.global_position)
		await _shot("geiger", Vector3(0.1, 0.0, -1.4), Vector3(-0.2, -0.3, -0.5), 40)
		hand.drop()
		await _shot("jettison_panel", Vector3(0.2, 0.0, -1.4), st.face_xform(7, -1.0).origin)
		var sun: Vector3 = main.space.sun.global_basis.z
		var side := sun.cross(Vector3.BACK).normalized()
		await _shot("stern_outside", Vector3(0, 0, 5.4) + sun * 6.0 + side * 18.0, Vector3(0, 0, 5.4))
	# Cast off: not with the hatch open or anyone inside.
	rb.hatch.is_open = true
	check(rb.jettison_blocker(Vector3(0, 0, 0)) != "", "JETTISON refuses with the hatch open")
	rb.hatch.is_open = false
	check(rb.jettison_blocker(Vector3(0, 0, 1.0)) != "", "and with the keeper still inside")
	# Carelessness: the rods drawn out by hand at full speed on a cold core of fresh fuel.
	p.global_position = Vector3(0, 0, -1.9)
	sim.rx_head_open = false
	sim.rx_fuel = [0.0, 0.0, 0.0]
	sim.press("rx_scram")
	sim.rx_t = 400.0
	sim.rx_power = 0.0
	sim.rx_decay_w = 0.0
	sim.c_rx_rods = 0.0
	sim.rx_rod = 0.0
	sim.press("rx_reset")
	sim.c_rx_auto = false
	sim.c_rx_rods = 1.0
	var t := 0
	while sim.rx_boom == "" and t < 120:
		sim.tick(1.0)
		t += 1
	check(sim.rx_boom.contains("EXCURSION"), "rods yanked out by hand on a cold, fresh core: %s after %d s" % [sim.rx_boom.to_lower(), t])
	for i in 10:
		await get_tree().physics_frame
	check(sim.rx_jettisoned and st.module_at(Vector3(0, 0, 1.0)) != "Reactor" and not main._casts.is_empty(), "the blast tears the reactor module off")
	var holed := false
	for b: Dictionary in main.damage.breaches:
		holed = holed or b.module == "Life support"
	check(holed, "and holes Life support")
	check(main.dose_at(Vector3(0, 0, -1.9)) > 500.0, "a cloud through the station (%d mSv/h in Life support)" % roundi(main.dose_at(Vector3(0, 0, -1.9))))
	check(main.body.alive, "the keeper, in Habitation, lives through it")
	check(st.has_node("BlastSealReactor"), "a blast seal shuts the hatchway")
	main._blast_t = 0.0
	main.damage.breaches.clear()
	main.damage.apply(sim)
	sim.leak_area = 0.0
	sim.c_rx_auto = true
	main._casts[-1].t = 8.0
	for i in 60:
		await get_tree().process_frame
	if "--shots" in OS.get_cmdline_user_args():
		var sun2: Vector3 = main.space.sun.global_basis.z
		var side2 := sun2.cross(Vector3.BACK).normalized()
		await _shot("cast_off", Vector3(0, 0, 5.4) + sun2 * 6.0 + side2 * 18.0, Vector3(0, 0, 1.4))
	sim.tick(1.0)
	check(sim.gen_kw == 0.0 and sim.rx_power == 0.0, "no reactor: no generator")
	check(sim.head_blocker() != "" and rb.dose_here(Vector3(0, 0, 1.0)) == 0.0, "nothing left of it aboard")


## MODULE SEPARATION: cast the airlock off, then Habitation and all aft of it; never with
## the keeper inside; blast seals shut the hatchways; what lived there is gone.
func _separation() -> void:
	var sim: ShipSim = main.sim
	var st: Station = main.station
	var p: Player = main.player
	var sp: SeparationPanel = main.separation
	check(sp.panel != null and st.module_at(sp.panel.global_position) == "Command deck", "MODULE SEPARATION panel in the command deck")
	await _shot("separation_panel", Vector3(0.05, 0.1, -12.5), sp.panel.global_position, 40)
	var lock_x := Station.A + Station.HULL + 1.3
	var node_z: float = (Station.SPINE["Node"][0] + Station.SPINE["Node"][1]) * 0.5
	p.release_grip()
	p.global_position = Vector3(lock_x, 0, node_z)
	check(main.separation_blocker("Airlock") == "YOU ARE IN IT", "not with the keeper inside")
	p.global_position = Vector3(0, 0, -12.5)
	sim.c_sep = SeparationPanel.OPTIONS.find(["AIRLOCK", "Airlock"])
	sp.fire()
	check(st.module_at(Vector3(lock_x, 0, node_z)) == "Airlock", "SEPARATE does nothing unarmed")
	sim.c_sep_arm = true
	sp.fire()
	check(st.module_at(Vector3(lock_x, 0, node_z)) == "" and sim.lost.has("Airlock") and not sim.c_sep_arm, "ARM, SEPARATE: the airlock goes")
	check(st.has_node("BlastSealAirlock"), "a blast seal on the Node")
	await _shot("separated_airlock", Vector3(-0.3, 0.0, node_z), Vector3(Station.A, 0, node_z))
	# Habitation, and with it Life support and the stern.
	sim.c_sep = SeparationPanel.OPTIONS.find(["HAB", "Habitation"])
	var set := st.cast_set("Habitation")
	check(set.has("Life support") and set.has("Stern") and not set.has("Node"), "Habitation takes all aft of it: %s" % ", ".join(set))
	p.global_position = Vector3(0, 0, -7.6)
	sim.c_sep_arm = true
	sp.fire()
	for i in 10:
		await get_tree().physics_frame
	check(st.module_at(Vector3(0, 0, -5.1)) == "" and st.module_at(Vector3(0, 0, -7.6)) == "Node", "Habitation and aft are gone; the Node stays")
	check(sim.h2 == 0.0 and sim.dhe == 0.0 and sim.food == 0, "the fuel and the galley went with them")
	check(st.has_node("BlastSealHabitation"), "the Node's aft hatchway sealed")
	sp.update()
	check(st.cast_set("Command deck").is_empty(), "the command deck never goes")
	# A meteoroid never holes a module that has gone (that hole would leak for ever).
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var bad := 0
	for i in 200:
		if st.gone.has(String(main.damage_view.random_spot(rng)[0])):
			bad += 1
	check(bad == 0, "breaches only in modules still aboard (%d of 200 in gone ones)" % bad)
	# REPRESS brings the airlock to the cabin's pressure from above too (the cabin lost air).
	sim.lock_inner_open = false
	sim.lock_outer_open = false
	sim.lock_p = sim.pressure() + 15.0
	sim.c_lock_mode = 2
	for i in 20:
		sim.tick(1.0)
	sim.c_lock_mode = 0
	check(sim.lock_equal(), "REPRESS with more air in the airlock than the cabin: equal again (%.1f / %.1f kPa)" % [sim.lock_p, sim.pressure()])


## What the hand's ray meets when the keeper looks at each thing they must work by hand:
## every hatch's handwheel from both sides, the suit locker. Nothing may be in the way.
func _reach() -> void:
	var p: Player = main.player
	var hand: Hand = main.player.hand
	var al: AirlockFit = main.airlock
	# Shut, so both its wheels face their rooms (open, one is behind the door).
	main.reactor.hatch.is_open = false
	for i in 120:
		await get_tree().physics_frame
	# The face of each hatch toward the cabin (the outer hatch's other wheel is outside).
	var targets: Array = []
	for h: Hatch in [al.inner, al.outer, main.reactor.hatch, main.dock.port_hatch()]:
		var inside := 1 if h == al.outer or h == main.dock.port_hatch() else 0
		targets.append([h.wheels[inside].display_name + " (cabin side)", h.wheels[inside]])
		if h != al.outer and h != main.dock.port_hatch():
			targets.append([h.wheels[1].display_name + " (other side)", h.wheels[1]])
	targets.append(["hose reel button", al.reel_it])
	for t: Array in targets:
		var it: Interactable = t[1]
		var at := it.global_position
		# Stand back along the way the wheel faces, inside the station.
		var best := ""
		for d: Vector3 in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
			var from := at + d * 0.85
			if main.station.module_at(from) == "":
				continue
			p.release_grip()
			p.global_position = from - Vector3(0, p.cam.position.y if p.cam else 0.0, 0)
			p.look_at_point(at)
			await get_tree().physics_frame
			await get_tree().physics_frame
			var hit := hand._ray()
			var name := "nothing" if hit.is_empty() else String((hit.collider as Node).name)
			if not hit.is_empty() and hit.collider == it:
				best = "ok"
				break
			best = "blocked by %s" % name
		check(best == "ok", "the hand reaches %s (%s)" % [t[0], best])
	main.reactor.hatch.is_open = true


## Every printed legend on every panel stays on its panel and clear of the others (in the
## language this run is in): the box each one covers, from its font, against the panel's edges.
func _legends() -> void:
	var stack: Array[Node] = [main.station]
	var panels: Array[ControlPanel] = []
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is ControlPanel:
			panels.append(n)
	var bad_total := 0
	for cp in panels:
		var boxes: Array = []
		var out: Array[String] = []
		var ls: Array[Node] = [cp]
		while not ls.is_empty():
			var n: Node = ls.pop_back()
			# Screens draw their own text.
			if n is Terminal:
				continue
			ls.append_array(n.get_children())
			if not (n is Label3D) or not (n as Label3D).visible or (n as Label3D).text.strip_edges() == "":
				continue
			var l := n as Label3D
			var w := 0.0
			var lines := l.text.split("
")
			for line in lines:
				w = maxf(w, l.font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, l.font_size).x)
			var sc := l.global_basis.get_scale().x / cp.global_basis.get_scale().x
			w *= l.pixel_size * sc
			var h := l.font.get_height(l.font_size) * lines.size() * l.pixel_size * sc
			var c := cp.to_local(l.global_position)
			var x0 := c.x - w * 0.5
			if l.horizontal_alignment == HORIZONTAL_ALIGNMENT_LEFT:
				x0 = c.x
			elif l.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT:
				x0 = c.x - w
			var rect := Rect2(x0, c.y - h * 0.5, w, h)
			var half := cp.size * 0.5
			if rect.position.x < -half.x - 0.004 or rect.end.x > half.x + 0.004 or rect.position.y < -half.y - 0.004 or rect.end.y > half.y + 0.004:
				out.append("off the panel: '%s'" % l.text.replace("
", " "))
			boxes.append([rect.grow(-0.0015), l.text.replace("
", " ")])
		for i in boxes.size():
			for j in range(i + 1, boxes.size()):
				var a2: Rect2 = boxes[i][0]
				var b2: Rect2 = boxes[j][0]
				if a2.intersects(b2):
					var ov := a2.intersection(b2)
					if ov.size.x > 0.003 and ov.size.y > 0.002:
						out.append("'%s' over '%s'" % [boxes[i][1], boxes[j][1]])
		bad_total += out.size()
		check(out.is_empty(), "%s: legends clear (%s)" % [cp.title, ", ".join(out.slice(0, 6))])
	# Everywhere else (signs, posters, labels on things): a legend fitted to its room stays in it.
	var wide: Array[String] = []
	var all: Array[Node] = [main.station]
	while not all.is_empty():
		var n: Node = all.pop_back()
		if n is Terminal:
			continue
		all.append_array(n.get_children())
		if n is Label3D and n.has_meta("fit") and (n as Label3D).visible:
			var l := n as Label3D
			var room: Vector2 = l.get_meta("fit")
			var w := 0.0
			for line in l.text.split("
"):
				w = maxf(w, l.font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, l.font_size).x)
			w *= l.pixel_size
			if w > room.x + 0.004:
				wide.append("'%s' %.3f > %.3f" % [l.text.replace("
", " "), w, room.x])
	check(wide.is_empty(), "every fitted legend within its room (%s)" % ", ".join(wide.slice(0, 8)))


## The torch: picked up, switched with E, shining where you look from either hand; F works it;
## the helmet lamp needs the suit; the light switch off is simply dark.
func _flashlight() -> void:
	var p: Player = main.player
	var hand: Hand = p.hand
	var fl: Flashlight = main.flashlight
	main.suit.worn = false
	main.suit.clipped = false
	hand.drop()
	if hand.offhand:
		hand.swap_offhand()
		hand.drop()
	p.release_grip()
	p.velocity = Vector3.ZERO
	p.global_position = Vector3(0, 0, -12.6)
	fl.prop.global_position = Vector3(0.0, 0.1, -12.2)
	fl.on = false
	await get_tree().physics_frame
	hand._pick(fl.prop, fl.prop.global_position)
	hand.use()
	for i in 3:
		await get_tree().process_frame
	check(fl.on and fl.beam.visible, "E switches the torch on")
	p.look_at_point(Vector3(0.5, -0.3, -14.0))
	for i in 3:
		await get_tree().process_frame
	check((-fl.beam.global_basis.z).dot(-p.cam.global_basis.z) > 0.99, "the beam goes where you look")
	hand.swap_offhand()
	for i in 3:
		await get_tree().process_frame
	check(hand.offhand == fl.prop and fl.beam.visible and (-fl.beam.global_basis.z).dot(-p.cam.global_basis.z) > 0.99, "in the other hand it still lights the way")
	p.toggle_lamp()
	await get_tree().process_frame
	check(not fl.on and not fl.beam.visible, "F switches the torch in the other hand")
	# Q again: away in the pocket, out of sight and dark; Q once more: back in the other hand.
	fl.toggle()
	hand.swap_offhand()
	await get_tree().process_frame
	check(hand.offhand == null and hand.pocket.has(fl.prop) and not fl.prop.is_visible_in_tree() and not fl.beam.visible, "Q again puts it away in the pocket, dark")
	hand.swap_offhand()
	await get_tree().process_frame
	check(hand.offhand == fl.prop and fl.prop.is_visible_in_tree() and fl.beam.visible, "Q once more takes it out, still lit")
	fl.toggle()
	hand.take_offhand()
	check(hand.held == fl.prop and fl.prop.get_child(0).scale == Vector3.ONE, "taken back into the hand, its own size")
	hand.drop()
	fl.prop.global_position = Vector3(0.3, -0.1, -12.2)
	p.toggle_lamp()
	await get_tree().process_frame
	check(not p.lamp.visible, "no torch in hand, no suit: F lights nothing")
	# The lights switched off: dark, no red battery lamps.
	main.sim.c_lights = false
	for i in 3:
		await get_tree().process_frame
	var lit: int = main.station.lights.filter(func(l: Light3D) -> bool: return l.visible).size()
	var red: int = main.station.emergency.filter(func(l: Light3D) -> bool: return l.light_energy > 0.0).size()
	check(lit == 0 and red == 0, "lights switched off: dark (%d lamps, %d red)" % [lit, red])
	main.sim.c_lights = true


## Every hatch swings open where you can see it (not in one frame) and a keeper fits through.
func _passages() -> void:
	var p: Player = main.player
	var al: AirlockFit = main.airlock
	var blowout := al.on_blowout
	al.on_blowout = Callable()
	# Air in the airlock as in the cabin, so the inner hatch's interlock lets it open.
	main.sim.c_lock_mode = 0
	main.sim.lock_p = main.sim.pressure()
	al.update()
	for h: Hatch in [main.reactor.hatch, al.inner, al.outer]:
		h.is_open = false
		for i in 150:
			await get_tree().physics_frame
		# The keeper right at the wheel, on the side the door swings into.
		var axis := h.global_basis.x.normalized()
		var stand := h.global_position + axis * 0.3
		p.release_grip()
		p.velocity = Vector3.ZERO
		p.global_position = stand - Vector3(0, p.cam.position.y, 0)
		await get_tree().physics_frame
		h.toggle()
		var through := 0
		var part := 0.0
		for i in 158:
			await get_tree().physics_frame
			if i == 7:
				part = absf(h._angle)
			# The head inside the leaf's disc?
			var leaf_n := h._pivot.global_basis.x.normalized()
			var rel := p.cam.global_position - h.door.global_position
			if absf(rel.dot(leaf_n)) < 0.12 and (rel - leaf_n * rel.dot(leaf_n)).length() < h.size * 0.5:
				through += 1
		check(h.is_open and part > 0.05 and part < absf(Hatch.OPEN_ANGLE) - 0.1, "%s swings open over time (%.2f rad after 8 frames)" % [h.door.display_name, part])
		check(absf(absf(h._angle) - absf(Hatch.OPEN_ANGLE)) < 0.01, "%s fully open (%.2f rad)" % [h.door.display_name, h._angle])
		check(through == 0, "%s never swings through the keeper's head (%d frames)" % [h.door.display_name, through])
		# Drift through it along its axis, both ways.
		var n := h.global_basis.x.normalized()
		for s: float in [1.0, -1.0]:
			p.release_grip()
			p.global_position = h.global_position - n * s * 0.7 - Vector3(0, p.cam.position.y, 0)
			p.velocity = n * s * 1.2
			for i in 150:
				await get_tree().physics_frame
				p.velocity = n * s * 1.2
			var past := (p.global_position + Vector3(0, p.cam.position.y, 0) - h.global_position).dot(n * s)
			check(past > 0.4, "%s: a keeper drifts through %s (%.2f m past)" % [h.door.display_name, "with the swing" if s > 0.0 else "against it", past])
		# The inner hatch shut again before the outer one opens: the station keeps its air.
		if h == al.inner:
			h.is_open = false
			for i in 150:
				await get_tree().physics_frame
	# Out through the open outer hatch on the umbilical, up over the station and down the far
	# side: the hose runs out of the hatch and over the hull, never through it.
	var node_z: float = (Station.SPINE["Node"][0] + Station.SPINE["Node"][1]) * 0.5
	var end_x := Station.A + Station.HULL + float(Station.SIDE_LEN["Airlock"])
	# (Down past the docking port's flank, not through it.)
	var route := [al.reel_pos + Vector3(-0.6, 0.5, 0), Vector3(end_x + 1.2, 0.0, node_z), Vector3(end_x + 1.2, 2.2, node_z), Vector3(0.0, 2.4, node_z), Vector3(-1.4, 1.6, node_z + 1.4), Vector3(-1.6, 0.0, node_z + 1.5)]
	p.release_grip()
	p.velocity = Vector3.ZERO
	p.global_position = route[0]
	if not main.suit.clipped:
		main.toggle_clip()
	for i in 4:
		await get_tree().physics_frame
	check(main.suit.clipped, "clipped on to go out")
	for k in range(1, route.size()):
		var a3: Vector3 = route[k - 1]
		var b3: Vector3 = route[k]
		var steps := ceili(a3.distance_to(b3) / 0.05)
		for j in steps:
			p.velocity = Vector3.ZERO
			p.global_position = a3.lerp(b3, float(j + 1) / steps)
			await get_tree().physics_frame
	for i in 60:
		p.velocity = Vector3.ZERO
		await get_tree().physics_frame
	var through := 0
	var space := p.get_world_3d().direct_space_state
	for i in Hose.BEADS - 1:
		var q := PhysicsRayQueryParameters3D.create(main.hose._p[i], main.hose._p[i + 1], Layers.WORLD)
		if not space.intersect_ray(q).is_empty():
			through += 1
	var straight := al.reel_pos.distance_to(p.global_position)
	check(through == 0 and main.hose.path_len > straight + 1.0, "the hose runs round the hull, not through it (%d stretches through, %.1f m of hose for %.1f m straight)" % [through, main.hose.path_len, straight])
	p.global_position = al.reel_pos + Vector3(-0.6, 0.3, 0)
	main.hose.visible = false
	main.suit.clipped = false
	al.outer.is_open = false
	for i in 120:
		await get_tree().physics_frame
	main.sim.lock_p = 101.0
	al.on_blowout = blowout
	# Back aboard with air round you: the suit comes off.
	p.global_position = Vector3(0, 0, -7.6)
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(not main.suit.worn and not main.suit.clipped, "off the hose and breathing the cabin again aboard")
	main.reactor.hatch.is_open = true
	p.velocity = Vector3.ZERO
	p.global_position = Vector3(-0.4, 0, -4.3)

