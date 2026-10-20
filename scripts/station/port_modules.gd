class_name PortModules
extends RefCounted
## Modules taken on for good at the docking port, each docked onto the far end of the one
## before: a greenhouse (food every two hours of the day, a little CO2 back into oxygen), a
## power module (more battery and its own solar wings), an observatory (every scan worth half
## as much again). Each has air, lamps, its own fittings, and at its far end a hatch and a
## berthing ring for the next one: the port moves out with them.

## Each kind's length (m, end wall to end wall).
const LENGTH := {"GREENHOUSE": 2.4, "POWER MODULE": 2.0, "OBSERVATORY": 2.2}
## Windows: face -> [[s0, s1, z0, z1]] (z from the module's start).
const WINDOWS := {
	"OBSERVATORY": {
		0: [[-0.2, 0.2, 0.45, 0.95], [-0.2, 0.2, 1.15, 1.65]],
		1: [[-0.17, 0.17, 0.45, 0.95], [-0.17, 0.17, 1.15, 1.65]],
		7: [[-0.17, 0.17, 0.45, 0.95], [-0.17, 0.17, 1.15, 1.65]],
	},
}
const GROW := Color(0.92, 0.38, 1.0)

var station: Station
var sim: ShipSim
var dock: DockFit
var science: Science
## Set by main: pick the greenhouse's ripe trays.
var on_pick: Callable
var _ripe_nodes: Array[Node3D] = []


func build(p_station: Station, p_sim: ShipSim, p_dock: DockFit, p_science: Science) -> void:
	station = p_station
	sim = p_sim
	dock = p_dock
	science = p_science
	# The ones already aboard (a saved game), in order out from the port.
	var names := ShipSim.module_names(sim.modules)
	for i in sim.modules.size():
		_build(String(sim.modules[i]), names[i])


static func length_of(kind: String) -> float:
	return float(LENGTH.get(kind, 2.2))


## A module of `kind` docked at the port just now: it is the station's from here on.
func attach(kind: String) -> String:
	sim.modules.append(kind)
	var m: String = ShipSim.module_names(sim.modules)[-1]
	_build(kind, m)
	station.apply_quality(Settings.quality)
	return m


func _build(kind: String, m: String) -> void:
	var at := station.port_xform()
	var e := station.add_port_module(m, kind, length_of(kind), WINDOWS.get(kind, {}))
	var root: Node3D = station.roots[m]
	var node_z: float = (Station.SPINE["Node"][0] + Station.SPINE["Node"][1]) * 0.5
	# Its far end: the port's hatch from now on, swinging in on its aft hinge like the Dock's.
	var h := Hatch.new()
	h.size = Station.HOLE * 2.0 + 0.14
	h.setup(root, Transform3D(Basis(), Vector3(-(float(e.z1) - 0.12), 0, node_z)), "Port hatch")
	dock.add_hatch(h)
	# Outside: what this kind carries on its hull, in the module's own frame (+X out along it).
	var outside := Node3D.new()
	outside.name = "Outside"
	outside.transform = at
	root.add_child(outside)
	exterior(outside, kind, length_of(kind))
	Station.outside(outside)
	var sign := Ctl.text(root, kind, Vector3.ZERO, 0.03, Color(0.06, 0.05, 0.03))
	sign.transform = station.side_face_xform("Dock", 4, float(e.z0) + 0.35) * Transform3D(Basis(), Vector3(0, 0, 0.008))
	Ctl.fit(sign, 0.42, 0.05)
	Kit.mesh(root, Kit.box(Vector3(0.48, 0.075, 0.008)), Kit.matte(Color(0.75, 0.6, 0.15), 0.6), Vector3.ZERO).transform = station.side_face_xform("Dock", 4, float(e.z0) + 0.35)
	match kind:
		"GREENHOUSE":
			_greenhouse(root, e)
		"POWER MODULE":
			_power(root, e)
		"OBSERVATORY":
			_observatory(root, e)


## A fitting's frame on face i, `z` metres into module e.
func _at(e: Dictionary, i: int, z: float, s := 0.0) -> Transform3D:
	return station.side_face_xform("Dock", i, float(e.z0) + z, s)


func _power_fn() -> Callable:
	return func() -> bool: return sim.bus_a_v > 90.0 or sim.bus_b_v > 90.0


# --- The greenhouse --------------------------------------------------------------------------------

func _greenhouse(root: Node3D, e: Dictionary) -> void:
	# Trays down both walls and the floor, clear of the far hatch's swing, under grow lamps.
	var trays := [[6, 0.9], [2, 0.9], [0, 0.9]]
	for t: Array in trays:
		var xf := _at(e, int(t[0]), float(t[1]))
		_tray(root, xf, 1.2, 0.4, e)
	var lamp_mat := Kit.glow(GROW, 2.4)
	for s in [-0.12, 0.12]:
		Kit.mesh(root, Kit.box(Vector3(1.2, 0.035, 0.02)), lamp_mat, Vector3.ZERO).transform = _at(e, 4, 0.9, s) * Transform3D(Basis(), Vector3(0, 0, 0.012))
	var l := OmniLight3D.new()
	l.light_color = GROW
	l.light_energy = 0.55
	l.omni_range = 2.6
	l.light_cull_mask = Station.INSIDE_LAYER
	l.transform = _at(e, 4, 0.9) * Transform3D(Basis(), Vector3(0, 0, 0.25))
	root.add_child(l)
	station.lights.append(l)
	# Picking: hold LMB on the floor tray.
	var floor_xf := _at(e, 0, 0.9)
	var pick := Node3D.new()
	pick.transform = floor_xf
	root.add_child(pick)
	var it := Interactable.make(pick, "Greenhouse trays", "Pick", Kit.box_shape(Vector3(1.2, 0.42, 0.24)), Vector3(0, 0, 0.12))
	it.hold_time = 0.6
	it.on_use = func() -> void: on_pick.call()
	it.value_fn = func() -> String: return Loc.t("%d ripe") % int(sim.crop)
	var p := ControlPanel.make(root, sim, "GREENHOUSE", Vector2(0.7, 0.6), _at(e, 6, 1.95), _power_fn())
	p.lamp("GROW LAMPS", 0.18, 0.24, func() -> bool: return sim.powered("lights"), Ctl.GREEN)
	p.lamp("RIPE", 0.18, 0.4, func() -> bool: return sim.crop >= 1.0, Ctl.AMBER)
	p.digits("TRAYS", 0.5, 0.3, func() -> String: return "%d" % int(sim.crop))
	p.bar("NEXT", 0.5, 0.48, func() -> float: return sim.crop - floorf(sim.crop), Ctl.GREEN)


## A grow tray on a face (frame xf: x along the module, y across, z into the cabin): a dark
## trough of growing medium and rows of leafy rosettes; the ripe ones show red.
func _tray(root: Node3D, xf: Transform3D, length: float, width: float, e: Dictionary) -> void:
	var frame := Geo.Builder.new()
	frame.xform = xf
	frame.box(Vector3(0, 0, 0.02), Vector3(length, width, 0.04))
	for sy in [-1.0, 1.0]:
		frame.box(Vector3(0, sy * (width * 0.5 - 0.01), 0.06), Vector3(length, 0.02, 0.06))
	for sx in [-1.0, 1.0]:
		frame.box(Vector3(sx * (length * 0.5 - 0.01), 0, 0.06), Vector3(0.02, width, 0.06))
	Kit.mesh(root, frame.commit(Kit.metal(Color(0.32, 0.33, 0.35), 0.5, 0.6)), null)
	var soil := Geo.Builder.new()
	soil.xform = xf
	soil.box(Vector3(0, 0, 0.065), Vector3(length - 0.04, width - 0.04, 0.05))
	Kit.mesh(root, soil.commit(Kit.matte(Color(0.16, 0.11, 0.08), 0.95)), null)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([xf.origin.snapped(Vector3.ONE * 0.01), e.name])
	var leaves := Geo.Builder.new()
	var pale := Geo.Builder.new()
	leaves.xform = xf
	pale.xform = xf
	var cols := 7
	for row in 2:
		for k in cols:
			var c := Vector3(-length * 0.5 + length * (k + 0.5) / cols, (row - 0.5) * width * 0.48, 0.09)
			var turn := rng.randf() * TAU
			var n := rng.randi_range(5, 7)
			for j in n:
				var a := turn + TAU * j / n
				var size := rng.randf_range(0.05, 0.075)
				var dir := Vector3(cos(a), sin(a), 0)
				var b := Basis(Vector3.BACK, a) * Basis(Vector3.UP, -0.75)
				var target := leaves if j % 2 == 0 else pale
				target.box(c + dir * size * 0.45 + Vector3(0, 0, size * 0.32), Vector3(size, size * 0.55, 0.004), b)
	Kit.mesh(root, leaves.commit(Kit.matte(Color(0.2, 0.46, 0.16), 0.75)), null)
	Kit.mesh(root, pale.commit(Kit.matte(Color(0.42, 0.62, 0.24), 0.75)), null)
	# Ripe ones: a few small red fruit among the leaves, shown while there is something to pick.
	var ripe := Node3D.new()
	ripe.transform = xf
	root.add_child(ripe)
	var fruit := Geo.Builder.new()
	for k in 5:
		fruit.box(Vector3(rng.randf_range(-length * 0.45, length * 0.45), rng.randf_range(-width * 0.3, width * 0.3), 0.13), Vector3(0.028, 0.028, 0.028), Basis(Vector3.BACK, rng.randf() * TAU))
	Kit.mesh(ripe, fruit.commit(Kit.matte(Color(0.78, 0.12, 0.08), 0.5)), null)
	_ripe_nodes.append(ripe)


## The ripe fruit show while there is something to pick.
func update() -> void:
	for n in _ripe_nodes:
		if is_instance_valid(n):
			n.visible = sim.crop >= 1.0


# --- The power module ------------------------------------------------------------------------------

func _power(root: Node3D, e: Dictionary) -> void:
	for i in [2, 1, 7, 6]:
		_cells(root, _at(e, i, 0.7), 0.8, 0.46, "CELL BANK %s" % ["A", "B", "C", "D"][[2, 1, 7, 6].find(i)])
	# Cable runs along the floor to the far wall's busbars.
	var cables := Geo.Builder.new()
	var half := length_of("POWER MODULE") * 0.5
	cables.xform = _at(e, 0, half)
	for s in [-0.16, 0.16]:
		cables.cylinder(Vector3(-half + 0.25, s, 0.03), Vector3(half - 0.25, s, 0.03), 0.022, 8)
	Kit.mesh(root, cables.commit(Kit.matte(Color(0.1, 0.1, 0.1), 0.7)), null)
	var p := ControlPanel.make(root, sim, "POWER MODULE", Vector2(0.7, 0.6), _at(e, 6, 1.55), _power_fn())
	p.digits("BATT kWh", 0.35, 0.22, func() -> String: return "%4d" % roundi(sim.bat_kwh))
	p.bar("CHARGE", 0.35, 0.4, func() -> float: return sim.bat_kwh / sim.bat_cap(), Ctl.GREEN)
	p.digits("WINGS kW", 0.35, 0.52, func() -> String: return "%4.1f" % (ShipSim.POWER_MODULE_KW * sim.arrays_deploy * sim.sun * sim.solar_factor))


## A cabinet of battery cells on a face: a row of cell packs, each with its status lamp.
func _cells(root: Node3D, xf: Transform3D, length: float, width: float, label: String) -> void:
	var body := Geo.Builder.new()
	body.xform = xf
	body.bevel = 0.006
	body.box(Vector3(0, 0, 0.05), Vector3(length, width, 0.1))
	Kit.mesh(root, body.commit(Looks.panel(Color(0.3, 0.32, 0.34), 0.5, 0.3, 1.0, 1.0)), null)
	var packs := Geo.Builder.new()
	var leds := Geo.Builder.new()
	packs.xform = xf
	leds.xform = xf
	var n := 6
	for k in n:
		var x := -length * 0.5 + length * (k + 0.5) / n
		packs.box(Vector3(x, -0.02, 0.105), Vector3(length / n - 0.02, width - 0.16, 0.012))
		leds.box(Vector3(x, -width * 0.5 + 0.045, 0.104), Vector3(0.016, 0.016, 0.006))
	Kit.mesh(root, packs.commit(Kit.matte(Color(0.12, 0.13, 0.14), 0.6)), null)
	Kit.mesh(root, leds.commit(Kit.glow(Color(0.3, 1.0, 0.4), 1.6)), null)
	var t := Ctl.text(root, label, Vector3.ZERO, 0.016)
	t.transform = xf * Transform3D(Basis(), Vector3(0, width * 0.5 - 0.035, 0.102))
	Ctl.fit(t, length - 0.1, 0.025)


# --- The observatory -------------------------------------------------------------------------------

func _observatory(root: Node3D, e: Dictionary) -> void:
	# A compact telescope in a cradle on the upper wall, out of the way down the middle.
	var xf := _at(e, 3, 0.85)
	var cradle := Geo.Builder.new()
	cradle.xform = xf
	for x in [-0.16, 0.16]:
		cradle.box(Vector3(x, 0, 0.05), Vector3(0.04, 0.16, 0.1))
	cradle.box(Vector3(0, 0, 0.012), Vector3(0.5, 0.2, 0.024))
	Kit.mesh(root, cradle.commit(Kit.metal(Color(0.25, 0.26, 0.28), 0.5, 0.7)), null)
	var tube := Geo.Builder.new()
	tube.xform = xf
	tube.cylinder(Vector3(-0.3, 0, 0.13), Vector3(0.26, 0, 0.13), 0.06, 16)
	tube.cylinder(Vector3(-0.34, 0, 0.13), Vector3(-0.3, 0, 0.13), 0.068, 16)
	Kit.mesh(root, tube.commit(Kit.matte(Color(0.88, 0.88, 0.85), 0.5)), null)
	var dark := Geo.Builder.new()
	dark.xform = xf
	dark.cylinder(Vector3(0.26, 0, 0.13), Vector3(0.32, 0, 0.13), 0.025, 10)
	dark.cylinder(Vector3(0.2, 0, 0.13), Vector3(0.2, 0, 0.22), 0.018, 8)
	for x in [-0.16, 0.16]:
		dark.box(Vector3(x, 0, 0.13), Vector3(0.03, 0.15, 0.13))
	Kit.mesh(root, dark.commit(Kit.metal(Color(0.1, 0.1, 0.11), 0.5, 0.6)), null)
	var solid := StaticBody3D.new()
	solid.collision_layer = Layers.FURNITURE
	solid.collision_mask = 0
	root.add_child(solid)
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.68, 0.2, 0.26)
	Kit.collider(solid, bs, xf * Vector3(0, 0, 0.13), xf.basis)
	var p := ControlPanel.make(root, sim, "OBSERVATORY", Vector2(0.7, 0.6), _at(e, 6, 1.75), _power_fn())
	p.lamp("TRACKER", 0.18, 0.26, func() -> bool: return sim.powered("lab"), Ctl.GREEN)
	p.digits("SCAN WORTH", 0.48, 0.3, func() -> String: return "x%.1f" % science.bonus)
	Ctl.fit(Ctl.text(p, "EVERY SCAN FROM LANTERN IS WORTH MORE", p.at(0.35, 0.5), 0.012), 0.6, 0.02)


# --- Outside ---------------------------------------------------------------------------------------

## What a kind carries on its hull, in the module's frame: +X out along it from the docking
## face, +Y up. Shared by the module in orbit (DerelictView) and the one docked for good.
static func exterior(parent: Node3D, kind: String, length: float) -> void:
	var r := Station.A + Station.HULL
	match kind:
		"POWER MODULE":
			# A mast down off the keel and two fixed wings across it, clear of the station's own.
			var mx := length * 0.5
			var truss := Geo.Builder.new()
			truss.cylinder(Vector3(mx, -r, 0), Vector3(mx, -r - 0.7, 0), 0.05, 8)
			truss.cylinder(Vector3(mx, -r - 0.7, -0.45), Vector3(mx, -r - 0.7, 0.45), 0.06, 8)
			Kit.mesh(parent, truss.commit(Kit.metal(Color(0.7, 0.7, 0.68), 0.45, 0.8)), null)
			var solid := StaticBody3D.new()
			solid.collision_layer = Layers.WORLD
			solid.collision_mask = 0
			parent.add_child(solid)
			for sz in [-1.0, 1.0]:
				var c := Vector3(mx, -r - 0.7, sz * (0.45 + 1.3))
				Kit.mesh(parent, Kit.box(Vector3(0.9, 0.03, 2.6)), Looks.solar(), c)
				var fr := Geo.Builder.new()
				for k in 5:
					fr.box(c + Vector3(0, 0, -1.3 + 2.6 * k / 4.0), Vector3(0.94, 0.045, 0.04))
				fr.box(c + Vector3(0.47, 0, 0), Vector3(0.04, 0.045, 2.6))
				fr.box(c + Vector3(-0.47, 0, 0), Vector3(0.04, 0.045, 2.6))
				Kit.mesh(parent, fr.commit(Kit.metal(Color(0.12, 0.12, 0.13), 0.5, 0.6)), null)
				var bs := BoxShape3D.new()
				bs.size = Vector3(0.95, 0.08, 2.65)
				Kit.collider(solid, bs, c)
		"GREENHOUSE":
			# Radiators for the grow lamps' heat, two short fins along the top.
			var fins := Geo.Builder.new()
			for s in [-0.25, 0.25]:
				fins.box(Vector3(length * 0.5, r + 0.2, s), Vector3(length - 0.6, 0.4, 0.02))
				fins.cylinder(Vector3(0.3, r + 0.02, s), Vector3(length - 0.3, r + 0.02, s), 0.025, 8)
			Kit.mesh(parent, fins.commit(Kit.matte(Color(0.6, 0.61, 0.6), 0.45)), null)
		"OBSERVATORY":
			# A sunshade ring round the windows underneath.
			var shade := Geo.Builder.new()
			for x in [0.4, 1.7]:
				shade.cylinder(Vector3(x, -r - 0.02, -0.5), Vector3(x, -r - 0.02, 0.5), 0.02, 6)
			Kit.mesh(parent, shade.commit(Kit.metal(Color(0.12, 0.12, 0.13), 0.5, 0.6)), null)
