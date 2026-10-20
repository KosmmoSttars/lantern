class_name Lab
extends RefCounted

## The science and comms panels sit low on Habitation's walls, this far along the station.
const LAB_Z := -5.1
## The laboratory's two panels (instruments, and comms with the supply catalogue) and the
## crate a docked supply drone leaves in the airlock.

const INS_ORDER := ["spectrometer", "magnetometer", "telescope", "particles"]
const INS_LABEL := {"spectrometer": "SPECTRO", "magnetometer": "MAGNETO", "telescope": "TELESCOPE", "particles": "PARTICLES"}

var station: Station
var sim: ShipSim
var flight: Flight
var science: Science
var sci_screen: Terminal
var comms_screen: Terminal
var story: Story
## Comms screen: 0 = supply catalogue, 1 = message log.
var screen_mode := 0
var crate_node: Node3D
var crate_it: Interactable
var dock_light: OmniLight3D
## Set by main: shows a message to the keeper.
var toast: Callable


func build(p_station: Station, p_sim: ShipSim, p_flight: Flight, p_science: Science) -> void:
	station = p_station
	sim = p_sim
	flight = p_flight
	science = p_science
	_science_panel()
	_comms_panel()
	_crate()
	_boom()


func _inst() -> Callable:
	return func() -> bool: return sim.bus_a_v > 90.0 or sim.bus_b_v > 90.0


## Bind a control to a field of some other object than the systems sim.
static func _bind(c: Ctl, obj: Object, key: String) -> Ctl:
	c.get_fn = func() -> Variant: return obj.get(key)
	c.set_fn = func(v: Variant) -> void: obj.set(key, v)
	return c


func _science_panel() -> void:
	var p := ControlPanel.make(station, sim, "SCIENCE", Vector2(2.4, 0.98), station.face_xform(1, LAB_Z), _inst())
	station.panels["science"] = p
	p.group("INSTRUMENTS", 0.04, 0.09, 0.96, 0.85)
	p.toggle("c_lab", "LAB POWER", 0.14, 0.2, PackedStringArray(["OFF", "ON"]))
	_bind(p.toggle("c_lab", "MAG BOOM", 0.3, 0.2, PackedStringArray(["STOWED", "OUT"])), science, "c_boom")
	# Lit steady once the boom is all the way out, blinking while its motor runs.
	p.lamp("BOOM OUT", 0.46, 0.2, func() -> bool:
		if science.boom >= 1.0:
			return true
		return science.boom > 0.0 and science.boom < 1.0 and int(Time.get_ticks_msec() / 300) % 2 == 0, Ctl.GREEN)
	for k in INS_ORDER.size():
		var ins: String = INS_ORDER[k]
		p.button(INS_LABEL[ins], 0.14 + k * 0.16, 0.44, func() -> void:
			var why := science.start_scan(ins, flight, sim)
			if why != "":
				Sfx.play("error", -8.0, 1.0, "Station")
				toast.call(why), func() -> bool: return science.scan.get("instrument", "") == ins, Ctl.GREEN)
	p.bar("SCAN", 0.86, 0.6, func() -> float: return science.scan_progress(), Ctl.GREEN)
	p.digits("DRIVE MB", 0.3, 0.66, func() -> String: return "%5d" % roundi(science.drive_mb()))
	p.digits("DATA VALUE", 0.3, 0.82, func() -> String: return "%5d" % roundi(science.drive_credit()))
	p.digits("NEXT SCAN", 0.6, 0.74, func() -> String: return "%5d" % roundi(science.value(flight.u, flight.c_target, "spectrometer")))
	sci_screen = p.crt(1.7, 0.5, 1.2, 0.76, 14, 440.0)


func _comms_panel() -> void:
	var p := ControlPanel.make(station, sim, "COMMS AND SUPPLY", Vector2(2.4, 0.98), station.face_xform(7, LAB_Z), _inst())
	station.panels["comms"] = p
	p.group("LINK", 0.04, 0.09, 0.5, 0.85)
	p.toggle("c_dish", "DISH", 0.14, 0.2, PackedStringArray(["OFF", "ON"]))
	_bind(p.toggle("c_dish", "UPLINK", 0.3, 0.2, PackedStringArray(["OFF", "SEND"])), science, "c_uplink")
	p.lamp("RELAY", 0.44, 0.2, func() -> bool: return science.link_ok(flight, sim), Ctl.GREEN)
	p.digits("CREDIT", 0.22, 0.46, func() -> String: return "%6d" % roundi(science.credit))
	p.digits("TO SEND MB", 0.22, 0.64, func() -> String: return "%6d" % roundi(science.drive_mb()))
	p.lamp("SENDING", 0.44, 0.64, func() -> bool: return science.c_uplink and science.link_ok(flight, sim) and not science.packets.is_empty(), Ctl.AMBER)
	p.group("SUPPLY", 0.58, 0.09, 0.64, 0.85)
	var items := PackedStringArray()
	for k in Science.CATALOGUE.size():
		items.append(str(k + 1))
	_bind(p.rotary("c_lab", "ITEM", 0.72, 0.24, items), science, "c_item")
	p.button("ORDER", 0.94, 0.22, func() -> void:
		var why := science.order(science.c_item, flight, sim)
		if why != "":
			Sfx.play("error", -8.0, 1.0, "Station")
			toast.call(why)
		else:
			Sfx.play("chime", -8.0, 1.2, "Station")
			toast.call("Ordered: %s" % Science.CATALOGUE[science.c_item][0]), Callable(), Ctl.WHITE)
	_bind(p.toggle("c_dish", "CARGO PORT", 0.72, 0.56, PackedStringArray(["SHUT", "OPEN"])), science, "c_dock_open")
	p.lamp("DRONE WAITING", 0.98, 0.5, func() -> bool:
		for o: Dictionary in science.orders:
			if o.state == "holding":
				return true
		return false, Ctl.AMBER)
	p.lamp("CRATE ABOARD", 0.98, 0.58, func() -> bool: return not science.crate.is_empty(), Ctl.GREEN)
	_bind(p.rotary("c_lab", "SCREEN", 0.22, 0.84, PackedStringArray(["SUPPLY", "LOG"])), self, "screen_mode")
	p.button("SIGN OFF", 1.14, 0.84, func() -> void:
		if story.can_sign_off():
			story.sign_off()
		else:
			Sfx.play("error", -8.0, 1.0, "Station")
			toast.call("Not yet"), func() -> bool: return story.can_sign_off(), Ctl.RED, true)
	comms_screen = p.crt(1.72, 0.5, 1.15, 0.76, 13, 440.0)


func _crate() -> void:
	crate_node = Node3D.new()
	crate_node.position = station.cargo_spot()
	station.add_child(crate_node)
	var b := Geo.Builder.new()
	b.bevel = 0.02
	b.box(Vector3.ZERO, Vector3(0.6, 0.5, 0.6))
	Kit.mesh(crate_node, b.commit(Kit.matte(Color(0.85, 0.6, 0.18), 0.6)), null)
	var bands := Geo.Builder.new()
	for k in 2:
		bands.box(Vector3(0, 0, -0.15 + k * 0.3), Vector3(0.62, 0.52, 0.04))
	Kit.mesh(crate_node, bands.commit(Kit.matte(Color(0.12, 0.12, 0.12), 0.7)), null)
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.6, 0.5, 0.6)
	crate_it = Interactable.make(crate_node, "Supply crate", "Unpack", shape)
	crate_it.hold_time = 2.5
	crate_it.on_use = func() -> void:
		var what := science.unpack(sim)
		if what != "":
			Sfx.play("latch", -4.0, 0.9, "Station")
			toast.call("Unpacked: %s" % what)
	crate_it.value_fn = func() -> String: return String(science.crate.get("label", ""))
	crate_node.visible = false
	dock_light = OmniLight3D.new()
	dock_light.light_cull_mask = Station.INSIDE_LAYER
	dock_light.light_color = Color(0.3, 1.0, 0.4)
	dock_light.light_energy = 0.0
	dock_light.omni_range = 2.0
	dock_light.position = station.cargo_spot() + Vector3(0, 0.5, 0)
	station.add_child(dock_light)


## The magnetometer boom: a slim lattice mast up off Habitation's upper starboard flank with the
## sensor at its tip, kept well clear of the hull's own field. It runs out (and back) on its
## motor; the mesh is built full length and drawn out as far as it has gone.
const BOOM_LEN := 3.2
var _boom_mast: Node3D
var _boom_tip: Node3D
var _boom_shape: CapsuleShape3D
var _boom_body: CollisionShape3D
var _boom_was := -1.0


func _boom() -> void:
	var root := Node3D.new()
	root.name = "MagBoom"
	var d := Station.outward(3)
	var base := d * (Station.A + Station.HULL) + Vector3(0, 0, -4.5)
	# Its frame: +Y out along the boom.
	root.transform = Transform3D(Kit.basis_y_to(d), base)
	(station.roots["Habitation"] as Node3D).add_child(root)
	var metal := Kit.metal(Color(0.72, 0.72, 0.7), 0.45, 0.8)
	var dark := Kit.metal(Color(0.15, 0.15, 0.16), 0.5, 0.6)
	var foot := Geo.Builder.new()
	foot.cylinder(Vector3(0, -0.02, 0), Vector3(0, 0.12, 0), 0.09, 12)
	Kit.mesh(root, foot.commit(dark), null)
	_boom_mast = Node3D.new()
	root.add_child(_boom_mast)
	var lattice := Geo.Builder.new()
	for k in 3:
		var a := TAU * k / 3.0
		var off := Vector3(cos(a), 0, sin(a)) * 0.045
		lattice.cylinder(off, off + Vector3(0, BOOM_LEN, 0), 0.008, 5)
	var y := 0.0
	while y < BOOM_LEN:
		for k in 3:
			var a0 := TAU * k / 3.0
			var a1 := TAU * (k + 1) / 3.0
			lattice.cylinder(Vector3(cos(a0), 0, sin(a0)) * 0.045 + Vector3(0, y, 0), Vector3(cos(a1), 0, sin(a1)) * 0.045 + Vector3(0, y + 0.2, 0), 0.005, 4)
		y += 0.2
	Kit.mesh(_boom_mast, lattice.commit(metal), null)
	_boom_tip = Node3D.new()
	root.add_child(_boom_tip)
	var sensor := Geo.Builder.new()
	sensor.cylinder(Vector3(0, 0, 0), Vector3(0, 0.22, 0), 0.05, 12)
	sensor.cylinder(Vector3(0, 0.22, 0), Vector3(0, 0.25, 0), 0.03, 10)
	Kit.mesh(_boom_tip, sensor.commit(Kit.matte(Color(0.9, 0.9, 0.86), 0.5)), null)
	Kit.mesh(_boom_tip, Kit.box(Vector3(0.11, 0.03, 0.11)), dark, Vector3(0, 0.1, 0))
	Station.outside(root)
	# Solid for a keeper outside, as far as it is out.
	var solid := StaticBody3D.new()
	solid.collision_layer = Layers.WORLD
	solid.collision_mask = 0
	root.add_child(solid)
	_boom_shape = CapsuleShape3D.new()
	_boom_shape.radius = 0.07
	_boom_body = Kit.collider(solid, _boom_shape)
	update_boom()


## Draw the boom out as far as its motor has run it; a whir from the panel while it moves.
func update_boom() -> void:
	if _boom_mast == null or not is_instance_valid(_boom_mast):
		return
	var k := 0.06 + 0.94 * science.boom
	_boom_mast.scale = Vector3(1, k, 1)
	_boom_tip.position = Vector3(0, BOOM_LEN * k, 0)
	_boom_shape.height = maxf(BOOM_LEN * k + 0.25, 0.3)
	_boom_body.position = Vector3(0, (BOOM_LEN * k + 0.25) * 0.5, 0)
	var moving := science.boom > 0.0 and science.boom < 1.0
	if moving and _boom_was >= 0.0 and not is_equal_approx(_boom_was, science.boom) and (is_equal_approx(_boom_was, 0.0) or is_equal_approx(_boom_was, 1.0)):
		Sfx.play_at("servo", station.panels["science"].global_position, -10.0, 0.8)
	_boom_was = science.boom


func refresh() -> void:
	var has_crate := not science.crate.is_empty()
	crate_node.visible = has_crate
	crate_it.enabled = has_crate
	(crate_it.get_child(0) as CollisionShape3D).disabled = not has_crate
	dock_light.light_energy = 0.8 if science.c_dock_open else 0.0
	var on := sim.powered("lab")
	sci_screen.powered = on
	comms_screen.powered = sim.powered("dish")
	if on:
		sci_screen.text = _sci_text()
	comms_screen.text = _comms_text()


func _sci_text() -> String:
	var u := flight.u
	var b := flight.c_target
	var l := PackedStringArray()
	l.append("TARGET %s" % String(u.bodies[b].name).to_upper())
	l.append("       %.0f km" % (flight.target_dist / 1000.0))
	l.append("")
	for ins: String in INS_ORDER:
		var why := science.blocker(ins, flight, sim) if science.scan.is_empty() else ("SCANNING %d%%" % roundi(science.scan_progress() * 100.0) if science.scan.instrument == ins else "")
		var target := b if ins != "particles" else flight.soi
		l.append("%-10s %4d  %s" % [INS_LABEL[ins], roundi(science.value(u, target, ins)), "READY" if why == "" else why.left(26)])
	l.append("")
	l.append(science.last_result.left(40))
	return "\n".join(l)


func _comms_text() -> String:
	if screen_mode == 1:
		return _log_text()
	var l := PackedStringArray()
	l.append("SUPPLY  CREDIT %d" % roundi(science.credit))
	for k in Science.CATALOGUE.size():
		var it: Array = Science.CATALOGUE[k]
		l.append("%s%d %-16s %4d" % [">" if k == science.c_item else " ", k + 1, it[0], roundi(float(it[1]))])
	l.append("")
	if science.orders.is_empty():
		l.append("NO DELIVERIES")
	for o: Dictionary in science.orders:
		var name: String = Science.CATALOGUE[int(o.item)][0]
		l.append("%-16s %s" % [name, "WAITING" if o.state == "holding" else Flight.game_duration(float(o.eta))])
	return "\n".join(l)


## The last messages from the Office, wrapped to the screen.
func _log_text() -> String:
	var lines := PackedStringArray(["MESSAGES FROM THE OFFICE", ""])
	var msgs: Array = story.log.slice(maxi(story.log.size() - 3, 0))
	for m: String in msgs:
		var line := ""
		for w in Loc.t(m).split(" "):
			if line.length() + w.length() + 1 > 38:
				lines.append(line)
				line = w
			else:
				line = w if line == "" else line + " " + w
		if line != "":
			lines.append(line)
		lines.append("")
	return "
".join(lines.slice(maxi(lines.size() - 16, 0)))
