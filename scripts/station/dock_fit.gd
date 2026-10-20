class_name DockFit
extends RefCounted
## The docking port off the Node's port side: a short vestibule open to the Node, a round
## hatch at its outer end and the DOCKING PORT panel beside it. Beyond the hatch is vacuum, or
## what is docked there: a derelict (cold and airless until PRESSURIZE fills it from the O2 and
## N2 tanks), or a module taken on for good, which carries the port on at its own far end.
## The hatch at the end of that chain is the port's: it will not open while the air either
## side of it differs (its small valve lends the cabin's air to what is docked).

var station: Station
var sim: ShipSim
## The Dock's own hatch, then the one at each docked module's far end: the last is the port.
var hatches: Array[Hatch] = []
var panel: ControlPanel
## Set by main: docking at the port and letting go (each returns why not, or "").
var dock_fn: Callable
var undock_fn: Callable
var in_range_fn: Callable
var docked_fn: Callable
var toast: Callable


func build(p_station: Station, p_sim: ShipSim) -> void:
	station = p_station
	sim = p_sim
	var node_z: float = (Station.SPINE["Node"][0] + Station.SPINE["Node"][1]) * 0.5
	var end_x := Station.A + Station.HULL + float(Station.SIDE_LEN["Dock"])
	# It swings in toward the Node, on its hinge on the aft (+Z) side.
	var h := Hatch.new()
	h.size = Station.HOLE * 2.0 + 0.14
	h.setup(station, Transform3D(Basis(), Vector3(-(end_x - 0.12), 0, node_z)), "Port hatch")
	add_hatch(h)
	_panel()


## The hatch at the far end of a module just docked for good: the port from now on.
func add_hatch(h: Hatch) -> void:
	hatches.append(h)
	h.equalize_requested.connect(func() -> void:
		if h == port_hatch():
			sim.port_valve = sim.port_vol > 0.0)


## The port's hatch now: the last one out (null once the Dock has gone).
func port_hatch() -> Hatch:
	return hatches[-1] if not hatches.is_empty() else null


## Hatches gone with a module cast off are the port's no longer.
func prune() -> void:
	hatches = hatches.filter(func(h: Hatch) -> bool: return is_instance_valid(h) and not _cast_off(h))


static func _cast_off(n: Node) -> bool:
	var p := n.get_parent()
	while p:
		if String(p.name).begins_with("Cast"):
			return true
		p = p.get_parent()
	return false


func _panel() -> void:
	var s0 := Station.A + Station.HULL
	var p := ControlPanel.make(station, sim, "DOCKING PORT", Vector2(1.0, 0.9), station.side_face_xform("Dock", 6, s0 + 0.5), func() -> bool: return sim.bus_a_v > 90.0 or sim.bus_b_v > 90.0)
	panel = p
	station.panels["dock"] = p
	var press := func(fn_name: String) -> void:
		var fn: Callable = get(fn_name)
		var why: String = fn.call() if fn.is_valid() else "NOTHING IN RANGE"
		if why != "":
			Sfx.play("error", -8.0, 1.0, "Station")
			if toast.is_valid():
				toast.call(why)
	p.gauge("BEYOND", 0.24, 0.34, func() -> float: return sim.port_p, 0.0, 110.0, "kPa")
	p.digits("PORT kPa", 0.24, 0.62, func() -> String: return "%5.1f" % sim.port_p)
	p.toggle("c_port_press", "PRESSURIZE", 0.52, 0.34, PackedStringArray(["OFF", "ON"]))
	p.button("DOCK", 0.42, 0.72, press.bind("dock_fn"), func() -> bool: return in_range_fn.is_valid() and bool(in_range_fn.call()) and not (docked_fn.is_valid() and bool(docked_fn.call())), Ctl.GREEN)
	p.button("UNDOCK", 0.6, 0.72, press.bind("undock_fn"), func() -> bool: return docked_fn.is_valid() and bool(docked_fn.call()), Ctl.AMBER, true)
	p.lamp("IN RANGE", 0.84, 0.22, func() -> bool: return in_range_fn.is_valid() and bool(in_range_fn.call()), Ctl.AMBER)
	p.lamp("DOCKED", 0.84, 0.32, func() -> bool: return docked_fn.is_valid() and bool(docked_fn.call()), Ctl.GREEN)
	p.lamp("EQUAL", 0.84, 0.42, func() -> bool: return sim.port_vol > 0.0 and sim.port_equal(), Ctl.GREEN)
	p.lamp("HATCH OPEN", 0.84, 0.52, func() -> bool: return sim.port_open, Ctl.RED)
	Ctl.fit(Ctl.text(p, "SHUT THE HATCH BEFORE YOU UNDOCK.", p.at(0.5, 0.86), 0.011, Ctl.RED), 0.9, 0.02)


## Each frame: the port hatch's interlock (vacuum or a derelict's air beyond it), the hatches
## between docked modules free (air both sides), and the port's state into the sim.
func update() -> void:
	var ph := port_hatch()
	for h in hatches:
		if h != ph or h.is_open or absf(sim.port_p - sim.pressure()) < 3.0:
			h.locked_reason = ""
		elif sim.port_vol <= 0.0:
			h.locked_reason = "Vacuum beyond: nothing docked at the port"
		else:
			h.locked_reason = "Pressure differs: PRESSURIZE on the DOCKING PORT panel, or the small valve under the wheel"
	sim.port_open = ph != null and ph.is_open
