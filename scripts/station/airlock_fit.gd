class_name AirlockFit
extends RefCounted
## The airlock's fittings: the inner hatch from the Node, the outer hatch to space, the
## airlock panel (pump mode, pressure) and the umbilical's reel with its CLIP ON button.
##
## The inner hatch will not open while the airlock and the cabin differ in pressure. The
## outer one has no interlock: open it with air still in the airlock and the air goes out
## through it all at once, taking whatever is loose (the keeper too) with it. Each hatch's
## equalisation valve (hold LMB) bleeds the airlock to the cabin (inner) or to space (outer).
## The hose reel by the outer hatch: its button clips the umbilical on (air down the hose) and
## off again. The reel is solid: the body and the hose meet it.

var station: Station
var sim: ShipSim
var suit: Suit
var inner: Hatch
var outer: Hatch
## The reel's button, and (set by main) what it does: clip the umbilical on / off.
var reel_it: Interactable
var reel_body: StaticBody3D
var on_clip: Callable
## Set by main: the outer hatch opened on a full airlock (called with pressure / 101 kPa).
var on_blowout: Callable
## Where the hose leaves its reel (station space), and which way it pays out.
var reel_pos := Vector3.ZERO
var toast: Callable
var reel_out := Vector3.RIGHT
var _knob: MeshInstance3D


func build(p_station: Station, p_sim: ShipSim, p_suit: Suit) -> void:
	station = p_station
	sim = p_sim
	suit = p_suit
	var node_z: float = (Station.SPINE["Node"][0] + Station.SPINE["Node"][1]) * 0.5
	var start := Station.A + Station.HULL
	var end_x := start + float(Station.SIDE_LEN["Airlock"])
	inner = Hatch.new()
	inner.size = Station.HOLE * 2.0 + 0.14
	inner.setup(station, Transform3D(Basis(), Vector3(start + 0.12, 0, node_z)), "Inner hatch")
	outer = Hatch.new()
	outer.size = Station.HOLE * 2.0 + 0.14
	outer.setup(station, Transform3D(Basis(Vector3.UP, PI), Vector3(end_x - 0.12, 0, node_z)), "Outer hatch")
	reel_pos = Vector3(end_x - 0.45, -Station.A + 0.25, node_z + 0.28)
	inner.equalize_requested.connect(func() -> void: sim.lock_valve = 1)
	outer.equalize_requested.connect(func() -> void: sim.lock_valve = 2)
	_panel()
	_reel()


func _panel() -> void:
	var p := ControlPanel.make(station, sim, "AIRLOCK", Vector2(1.3, 0.9), station.side_face_xform("Airlock", 6, 2.25), func() -> bool: return sim.bus_a_v > 90.0 or sim.bus_b_v > 90.0)
	station.panels["airlock"] = p
	p.rotary("c_lock_mode", "PUMP", 0.2, 0.3, PackedStringArray(["HOLD", "DEPRESS", "REPRESS"]))
	p.gauge("LOCK PRESS", 0.5, 0.36, func() -> float: return sim.lock_p, 0.0, 110.0, "kPa")
	p.digits("LOCK kPa", 0.5, 0.66, func() -> String: return "%5.1f" % sim.lock_p)
	p.lamp("EQUAL", 0.84, 0.22, func() -> bool: return sim.lock_equal(), Ctl.GREEN)
	p.lamp("VACUUM", 0.84, 0.3, func() -> bool: return sim.lock_p < 1.0, Ctl.AMBER)
	p.lamp("INNER OPEN", 0.84, 0.42, func() -> bool: return sim.lock_inner_open, Ctl.AMBER)
	p.lamp("OUTER OPEN", 0.84, 0.5, func() -> bool: return sim.lock_outer_open, Ctl.RED)
	p.digits("CABIN kPa", 1.12, 0.3, func() -> String: return "%5.1f" % sim.pressure())
	Ctl.text(p, "DEPRESS TO 0 BEFORE THE OUTER HATCH. IT HAS NO INTERLOCK.", p.at(0.65, 0.84), 0.011, Ctl.RED)


## The umbilical's reel, bolted to the airlock floor by the outer hatch.
func _reel() -> void:
	var root := Node3D.new()
	root.position = reel_pos
	station.add_child(root)
	# A floor plate and two A-frame stands, the drum between them on its axle (across the
	# airlock), the hose wound on in neat turns, a crank to wind it, its end led off to the hatch.
	var steel := Geo.Builder.new()
	var dark := Geo.Builder.new()
	var hose := Geo.Builder.new()
	var floor_y := -0.24
	steel.box(Vector3(0, floor_y, 0), Vector3(0.34, 0.02, 0.3))
	for sz in [-0.12, 0.12]:
		steel.cylinder(Vector3(-0.12, floor_y, sz), Vector3(0, 0, sz), 0.012, 6)
		steel.cylinder(Vector3(0.12, floor_y, sz), Vector3(0, 0, sz), 0.012, 6)
		dark.cylinder(Vector3(0, 0, sz - 0.012), Vector3(0, 0, sz + 0.012), 0.03, 12)
	dark.cylinder(Vector3(0, 0, -0.14), Vector3(0, 0, 0.14), 0.012, 8)
	# Drum and flanges.
	for sz in [-0.095, 0.095]:
		steel.cylinder(Vector3(0, 0, sz - 0.004), Vector3(0, 0, sz + 0.004), 0.17, 28)
	dark.cylinder(Vector3(0, 0, -0.09), Vector3(0, 0, 0.09), 0.07, 20)
	# The hose: turns of it, two layers, slightly staggered.
	for layer in 2:
		var rr := 0.085 + layer * 0.024
		for k in 6:
			var zz := -0.075 + k * 0.03 + layer * 0.012
			if zz > 0.08:
				continue
			var ring := PackedVector3Array()
			for f in 25:
				var a := TAU * f / 24.0
				ring.append(Vector3(cos(a) * rr, sin(a) * rr, zz))
			hose.sweep(ring, 0.012, 6)
	# The hose's end off the top of the drum toward the hatch.
	hose.sweep(PackedVector3Array([Vector3(0.0, 0.11, 0.0), Vector3(0.12, 0.13, 0.0), Vector3(0.26, 0.08, 0.0)]), 0.012, 6)
	# The crank.
	dark.cylinder(Vector3(0, 0, 0.15), Vector3(0, 0, 0.17), 0.01, 8)
	steel.cylinder(Vector3(0, 0, 0.165), Vector3(0, 0.09, 0.165), 0.008, 6)
	dark.cylinder(Vector3(0, 0.09, 0.165), Vector3(0, 0.09, 0.21), 0.012, 8)
	Kit.mesh(root, steel.commit(Kit.metal(Color(0.55, 0.57, 0.6), 0.4, 0.75)), null)
	Kit.mesh(root, dark.commit(Kit.metal(Color(0.2, 0.21, 0.23), 0.5, 0.6)), null)
	Kit.mesh(root, hose.commit(Kit.matte(Color(0.88, 0.64, 0.16), 0.65)), null)
	Ctl.fit(Ctl.text(root, "UMBILICAL", Vector3(0, 0.22, 0.0), 0.014), 0.3, 0.025)
	# The button box on its post beside the drum, facing back into the airlock (the way the
	# keeper comes): amber while the hose is on the reel, green once it is clipped on.
	var box := Geo.Builder.new()
	box.bevel = 0.005
	box.cylinder(Vector3(-0.25, -0.24, 0.08), Vector3(-0.25, 0.12, 0.08), 0.012, 6)
	box.box(Vector3(-0.25, 0.17, 0.08), Vector3(0.05, 0.1, 0.13))
	Kit.mesh(root, box.commit(Kit.matte(Color(0.85, 0.62, 0.12), 0.6)), null)
	var lit := Kit.glow(Color(0.3, 1.0, 0.45), 1.8)
	var ready := Kit.glow(Color(1.0, 0.62, 0.15), 0.9)
	var knob := Kit.mesh(root, Kit.cylinder(0.03, 0.02, 18), ready, Vector3(-0.28, 0.16, 0.08), Basis(Vector3.BACK, PI / 2.0))
	knob.name = "ClipButton"
	knob.set_meta("lit", lit)
	knob.set_meta("dark", ready)
	var tag := Ctl.text(root, "CLIP ON", Vector3(-0.2755, 0.207, 0.08), 0.011, Color(0.06, 0.05, 0.03))
	tag.rotation.y = -PI / 2.0
	Ctl.fit(tag, 0.12, 0.016)
	# Solid: the keeper and the hose meet it, not pass through it.
	var solid := StaticBody3D.new()
	solid.name = "ReelBody"
	solid.collision_layer = Layers.FURNITURE
	solid.collision_mask = 0
	root.add_child(solid)
	Kit.collider(solid, Kit.box_shape(Vector3(0.46, 0.46, 0.44)), Vector3(-0.05, -0.02, 0))
	reel_body = solid
	# The whole reel takes the hand: LMB clips on or off.
	reel_it = Interactable.make(root, "Umbilical reel", "Clip on", Kit.box_shape(Vector3(0.54, 0.52, 0.5)), Vector3(-0.06, -0.01, 0.01))
	reel_it.on_use = func() -> void: on_clip.call()
	reel_it.verb_fn = func() -> String: return "Unclip" if suit.clipped else "Clip on"
	reel_it.value_fn = func() -> String: return "CLIPPED ON" if suit.clipped else ""
	_knob = knob


## Each frame: the inner hatch's interlock, a blowout if the outer hatch has just opened on
## air, and the hatches' state into the sim.
func update() -> void:
	inner.locked_reason = "" if sim.lock_equal() or inner.is_open else "Pressure differs: turn the small valve under the wheel, or REPRESS on the AIRLOCK panel"
	outer.locked_reason = ""
	if outer.is_open and not sim.lock_outer_open and sim.lock_p > 2.0 and on_blowout.is_valid():
		on_blowout.call(sim.lock_p / 101.0)
	sim.lock_inner_open = inner.is_open
	sim.lock_outer_open = outer.is_open
	# A bleed valve runs until the two sides are equal.
	if sim.lock_valve == 1 and sim.lock_equal():
		sim.lock_valve = 0
	if sim.lock_valve == 2 and sim.lock_p < 0.5:
		sim.lock_valve = 0
	if _knob:
		_knob.material_override = _knob.get_meta("lit") if suit.clipped else _knob.get_meta("dark")
