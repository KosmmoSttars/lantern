class_name StationPanels
extends RefCounted

## Where the Engineering and Life support panels sit along the station.
const ENG_Z := -9.8
const LIFE_Z := -1.9
## Lays out every control panel aboard and wires it to the systems sim and the flight
## computer. Panel coordinates are metres from the panel's top-left corner.

var station: Station
var sim: ShipSim
var flight: Flight
var nav_screen: Terminal
var map_screen: Terminal
var map: MapScreen
var reactor_screen: Terminal
var power_screen: Terminal
var life_screen: Terminal
var star_screen: Terminal
var galaxy: Galaxy
## Called with a star id to set off for it.
var engage_star_fn: Callable


func build(p_station: Station, p_sim: ShipSim, p_flight: Flight, p_galaxy: Galaxy) -> void:
	station = p_station
	sim = p_sim
	flight = p_flight
	galaxy = p_galaxy
	_reactor()
	_electrical()
	_breakers()
	_thermal()
	_flight_desk()
	_propulsion()
	_gnc()
	_life()
	_tanks()
	_torch()
	_stars()


## Instrument power: lamps and displays live while either bus has volts.
func _inst() -> Callable:
	return func() -> bool: return sim.bus_a_v > 90.0 or sim.bus_b_v > 90.0


func _alarm(code: String) -> Callable:
	return func() -> bool: return bool(sim.alarms[code])


func _lamp(p: ControlPanel, code: String, x: float, y: float) -> void:
	var warn: bool = ShipSim.ALARMS[code][1]
	p.lamp(ShipSim.ALARMS[code][0], x, y, _alarm(code), Ctl.RED if warn else Ctl.AMBER)


# --- Engineering ---------------------------------------------------------------------------------

func _reactor() -> void:
	var p := ControlPanel.make(station, sim, "REACTOR", Vector2(2.5, 0.98), station.face_xform(2, ENG_Z), _inst())
	station.panels["reactor"] = p
	p.group("MODE", 0.04, 0.09, 0.22, 0.4)
	p.rotary("c_rx_mode", "REACTOR MODE", 0.15, 0.22, PackedStringArray(["POWER", "PROP"]))
	_lamp(p, "rx_mode", 0.15, 0.4)
	p.group("RODS", 0.3, 0.09, 0.82, 0.4)
	p.knob("c_rx_rods", "ROD DEMAND", 0.4, 0.21, 0.02)
	p.toggle("c_rx_auto", "ROD CONTROL", 0.54, 0.21, PackedStringArray(["MAN", "AUTO"]))
	p.knob("c_rx_temp_set", "TEMP SET", 0.68, 0.21, 0.02)
	p.toggle("c_rx_interlock", "FLOW INTERLOCK", 0.82, 0.21, PackedStringArray(["BYPASS", "NORM"]), true)
	p.press("rx_scram", "SCRAM", 0.98, 0.21, func() -> bool: return sim.rx_scrammed, Ctl.RED, true)
	p.press("rx_reset", "SCRAM RESET", 0.98, 0.37, Callable(), Ctl.WHITE)
	p.bar("ROD POS", 0.4, 0.4, func() -> float: return sim.rx_rod, Ctl.AMBER)
	p.digits("SET K", 0.62, 0.4, func() -> String: return "%5d" % roundi(sim.temp_setpoint()))
	p.digits("ROD %", 0.82, 0.44, func() -> String: return "%5.1f" % (sim.rx_rod * 100.0))
	p.group("CORE", 0.04, 0.52, 1.08, 0.42)
	p.gauge("CORE TEMP", 0.17, 0.7, func() -> float: return sim.rx_t, 0.0, 3200.0, "K", 2800.0)
	p.gauge("FISSION POWER", 0.37, 0.7, func() -> float: return sim.rx_power * 100.0, 0.0, 120.0, "%", 100.0)
	p.digits("THERMAL kW", 0.58, 0.64, func() -> String: return "%7.0f" % (sim.rx_q_w / 1000.0))
	p.digits("DECAY kW", 0.58, 0.78, func() -> String: return "%7.0f" % (sim.rx_decay_w / 1000.0))
	p.knob("c_rx_pump", "LOOP PUMP", 0.78, 0.66, 0.05)
	p.gauge("LOOP TEMP", 0.98, 0.7, func() -> float: return sim.loop_t, 100.0, 400.0, "K", 330.0)
	p.group("TURBINE", 1.16, 0.09, 0.3, 0.85)
	p.toggle("c_rx_turbine", "TURBINE", 1.31, 0.21, PackedStringArray(["TRIP", "RUN"]))
	p.gauge("GENERATOR", 1.31, 0.45, func() -> float: return sim.gen_kw, 0.0, 120.0, "kW", 110.0)
	p.digits("GEN kW", 1.31, 0.66, func() -> String: return "%6.1f" % sim.gen_kw)
	p.digits("DAMAGE %", 1.31, 0.82, func() -> String: return "%5.1f" % (sim.rx_damage * 100.0), Ctl.RED)
	var codes := ["rx_hot", "rx_scram", "rx_flow", "loop_hot"]
	for i in codes.size():
		_lamp(p, codes[i], 1.55, 0.14 + i * 0.045)
	reactor_screen = p.crt(2.0, 0.5, 0.78, 0.72, 15, 460.0)
	reactor_screen.draw_fn = _draw_reactor


func _electrical() -> void:
	var p := ControlPanel.make(station, sim, "ELECTRICAL POWER", Vector2(2.5, 0.98), station.face_xform(6, ENG_Z), _inst())
	station.panels["electrical"] = p
	p.group("BUS A", 0.04, 0.09, 0.5, 0.42)
	p.toggle("c_gen_a", "GENERATOR > A", 0.14, 0.2, PackedStringArray(["OPEN", "CLOSE"]))
	p.toggle("c_bat_a", "BATTERY > A", 0.28, 0.2, PackedStringArray(["OPEN", "CLOSE"]))
	p.digits("BUS A V", 0.44, 0.19, func() -> String: return "%5.1f" % sim.bus_a_v)
	p.gauge("LOAD A", 0.22, 0.4, func() -> float: return sim.load_a_kw, 0.0, 100.0, "kW", 90.0)
	_lamp(p, "bus_a", 0.44, 0.33)
	p.group("BUS B", 0.58, 0.09, 0.5, 0.42)
	p.toggle("c_sol_b", "SOLAR > B", 0.68, 0.2, PackedStringArray(["OPEN", "CLOSE"]))
	p.toggle("c_bat_b", "BATTERY > B", 0.82, 0.2, PackedStringArray(["OPEN", "CLOSE"]))
	p.digits("BUS B V", 0.98, 0.19, func() -> String: return "%5.1f" % sim.bus_b_v)
	p.gauge("LOAD B", 0.76, 0.4, func() -> float: return sim.load_b_kw, 0.0, 40.0, "kW", 35.0)
	_lamp(p, "bus_b", 0.98, 0.33)
	p.toggle("c_tie", "BUS TIE", 1.2, 0.2, PackedStringArray(["OPEN", "CLOSE"]), true)
	p.toggle("c_lights", "CABIN LIGHTS", 1.2, 0.42, PackedStringArray(["OFF", "ON"]))
	p.group("BATTERY", 0.04, 0.55, 0.5, 0.39)
	p.bar("CHARGE", 0.12, 0.76, func() -> float: return sim.bat_kwh / sim.bat_cap(), Ctl.GREEN)
	p.digits("BATT kWh", 0.32, 0.66, func() -> String: return "%6.1f" % sim.bat_kwh)
	p.digits("BATT kW", 0.32, 0.82, func() -> String: return "%+6.1f" % sim.bat_kw)
	_lamp(p, "bat_low", 0.47, 0.66)
	p.group("SOLAR ARRAYS", 0.58, 0.55, 0.5, 0.39)
	p.toggle("c_arrays", "ARRAYS", 0.68, 0.68, PackedStringArray(["STOW", "DEPLOY"]))
	p.bar("DEPLOYED", 0.8, 0.76, func() -> float: return sim.arrays_deploy, Ctl.AMBER)
	p.gauge("ARRAY OUT", 0.96, 0.76, func() -> float: return sim.sol_kw, 0.0, 8.0, "kW")
	_lamp(p, "arr_stow", 1.2, 0.66)
	_lamp(p, "trip", 1.2, 0.72)
	power_screen = p.crt(1.87, 0.5, 1.05, 0.72, 14, 480.0)


func _breakers() -> void:
	for bus in ["A", "B"]:
		var names: Array[String] = []
		for b: String in ShipSim.BREAKERS:
			if ShipSim.BREAKERS[b][1] == bus:
				names.append(b)
		var face := 3 if bus == "A" else 5
		var p := ControlPanel.make(station, sim, "CIRCUIT BREAKERS  BUS " + bus, Vector2(2.5, 0.42), station.face_xform(face, ENG_Z), Callable())
		station.panels["breakers_" + bus] = p
		var span := 2.3 / names.size()
		for i in names.size():
			p.breaker(names[i], 0.12 + span * (i + 0.5) - span * 0.5 + 0.05, 0.24)


func _thermal() -> void:
	var p := ControlPanel.make(station, sim, "THERMAL CONTROL", Vector2(2.2, 0.9), station.face_xform(7, ENG_Z), _inst())
	station.panels["thermal"] = p
	p.group("RADIATORS", 0.04, 0.09, 0.62, 0.78)
	p.toggle("c_radiators", "RADIATORS", 0.16, 0.22, PackedStringArray(["STOW", "DEPLOY"]))
	p.bar("DEPLOYED", 0.32, 0.3, func() -> float: return sim.rad_deploy, Ctl.AMBER)
	p.gauge("LOOP TEMP", 0.5, 0.26, func() -> float: return sim.loop_t, 100.0, 400.0, "K", 330.0)
	_lamp(p, "rad_stow", 0.18, 0.5)
	_lamp(p, "loop_hot", 0.18, 0.56)
	p.digits("REJECT kW", 0.46, 0.55, func() -> String: return "%6.0f" % (ShipSim.RAD_K * (0.08 + 0.92 * sim.rad_deploy) * (pow(sim.loop_t, 4.0) - pow(ShipSim.SINK_T, 4.0)) / 1000.0))
	p.group("CABIN", 0.72, 0.09, 0.9, 0.78)
	p.toggle("c_cab_pump", "CABIN LOOP", 0.84, 0.22, PackedStringArray(["OFF", "ON"]))
	p.knob("c_cab_set", "CABIN SET", 1.0, 0.22, 0.05)
	p.toggle("c_heater", "HEATERS", 1.16, 0.22, PackedStringArray(["OFF", "ON"]))
	p.gauge("CABIN TEMP", 0.9, 0.55, func() -> float: return sim.cab_t - 273.15, 0.0, 40.0, "C", 30.0)
	p.digits("CABIN C", 1.2, 0.5, func() -> String: return "%5.1f" % (sim.cab_t - 273.15))
	p.digits("SET C", 1.2, 0.64, func() -> String: return "%5.1f" % (sim.cabin_setpoint() - 273.15))
	_lamp(p, "cab_temp", 1.45, 0.24)


# --- Command deck --------------------------------------------------------------------------------

## The flight panel is set flush into the command deck's floor (in free fall, as good a wall as
## any), reading the right way up for a keeper facing the bow: the map at the top, the nav
## screen under it, the master alarms and ENGAGE down the left.
func _flight_desk() -> void:
	var xf := Transform3D(Basis(Vector3.RIGHT, Vector3.FORWARD, Vector3.UP), Vector3(0, -Station.A + 0.012, -12.55))
	var p := ControlPanel.make(station, sim, "FLIGHT", Vector2(0.82, 1.36), xf, _inst())
	# It lies along the module, not across a face: no shrinking to fit a face's height.
	p.scale = Vector3.ONE
	station.panels["desk"] = p
	map_screen = p.crt(0.41, 0.4, 0.72, 0.6, 12, 600.0)
	nav_screen = p.crt(0.52, 1.0, 0.54, 0.5, 12, 640.0)
	# The navigation displays glow blue, apart from the green engineering screens.
	map_screen.modulate = Color(0.35, 0.82, 1.0)
	nav_screen.modulate = Color(0.35, 0.82, 1.0)
	map = MapScreen.new()
	map.galaxy = galaxy
	map.setup(flight, sim, map_screen)
	p.button("MASTER WARN", 0.1, 0.8, func() -> void: sim.press("silence"), func() -> bool: return sim.any_warning() and int(Time.get_ticks_msec() / 400) % 2 == 0, Ctl.RED)
	p.button("MASTER CAUT", 0.1, 0.92, func() -> void: sim.press("silence"), func() -> bool: return sim.any_caution(), Ctl.AMBER)
	p.button("ENGAGE", 0.1, 1.08, func() -> void:
		if map.mode == "galaxy" and map.star_target >= 0:
			engage_star_fn.call(map.star_target)
			return
		var why := flight.transit_blocker(flight.c_target, sim)
		if why != "":
			Sfx.play("error", -8.0, 1.0, "Station")
		flight.start_transit(flight.c_target, sim), func() -> bool: return not flight.transit.is_empty() or (map.mode == "system" and flight.transit_blocker(flight.c_target, sim) == ""), Ctl.GREEN)
	p.button("BREAK OFF", 0.1, 1.2, func() -> void: flight.abort_transit(), func() -> bool: return not flight.transit.is_empty(), Ctl.RED)


func _flight_ctl(p: ControlPanel, kind: String, key: String, label: String, x: float, y: float, positions: PackedStringArray) -> Ctl:
	var c: Ctl
	if kind == "rotary":
		c = p.rotary(key, label, x, y, positions)
	c.get_fn = func() -> Variant: return flight.get(key)
	c.set_fn = func(v: Variant) -> void: flight.set(key, v)
	return c


func _propulsion() -> void:
	var p := ControlPanel.make(station, sim, "MAIN ENGINE", Vector2(2.2, 0.98), station.face_xform(1, -12.6), _inst())
	station.panels["engine"] = p
	p.group("FEED", 0.04, 0.09, 0.66, 0.85)
	p.toggle("c_cryo", "H2 CRYOCOOLER", 0.14, 0.2, PackedStringArray(["OFF", "ON"]))
	p.toggle("c_he_press", "HE PRESS", 0.3, 0.2, PackedStringArray(["OFF", "ON"]))
	p.valve("c_h2_feed", "H2 FEED", 0.5, 0.21)
	p.gauge("TANK PRESS", 0.18, 0.46, func() -> float: return sim.h2_p * 1000.0, 0.0, 400.0, "kPa", 320.0)
	p.bar("H2", 0.36, 0.48, func() -> float: return sim.h2 / ShipSim.H2_MAX, Ctl.GREEN)
	p.digits("H2 kg", 0.54, 0.43, func() -> String: return "%6d" % roundi(sim.h2))
	p.toggle("c_cool_valve", "COOLDOWN BYPASS", 0.16, 0.74, PackedStringArray(["SHUT", "OPEN"]), true)
	_lamp(p, "h2_press", 0.36, 0.66)
	_lamp(p, "boiloff", 0.36, 0.71)
	_lamp(p, "cav", 0.36, 0.76)
	p.digits("BYPASS kg/s", 0.56, 0.74, func() -> String: return "%5.2f" % (0.6 * clampf(sim.h2_p / 0.2, 0.0, 1.0) if sim.c_cool_valve else 0.0))
	p.group("ENGINE", 0.74, 0.09, 0.86, 0.85)
	p.toggle("c_eng_arm", "ENGINE ARM", 0.84, 0.2, PackedStringArray(["SAFE", "ARM"]), true)
	p.press("eng_start", "TURBO START", 1.0, 0.2, func() -> bool: return sim.pump_spin > 0.05, Ctl.GREEN)
	p.gauge("TURBOPUMP", 1.18, 0.22, func() -> float: return sim.pump_spin * 100.0, 0.0, 110.0, "%")
	p.gauge("THRUST", 0.86, 0.48, func() -> float: return sim.thrust / 1000.0, 0.0, 160.0, "kN")
	p.gauge("EXHAUST", 1.06, 0.48, func() -> float: return sim.exhaust_speed() if sim.eng_mdot > 0.0 else 0.0, 0.0, 10000.0, "m/s")
	p.digits("FLOW kg/s", 1.32, 0.44, func() -> String: return "%5.2f" % sim.eng_mdot)
	p.digits("ACCEL m/s2", 0.9, 0.74, func() -> String: return "%5.2f" % (sim.thrust / sim.mass()))
	p.digits("CORE K", 1.12, 0.74, func() -> String: return "%5d" % roundi(sim.rx_t))
	p.lever("c_throttle", "THROTTLE", 1.85, 0.52)


func _gnc() -> void:
	var p := ControlPanel.make(station, sim, "GUIDANCE  NAVIGATION  CONTROL", Vector2(2.2, 0.98), station.face_xform(7, -12.6), _inst())
	station.panels["gnc"] = p
	p.group("COMPUTER", 0.04, 0.09, 1.1, 0.42)
	p.toggle("c_nav", "NAV COMPUTER", 0.14, 0.2, PackedStringArray(["OFF", "ON"]))
	p.toggle("c_tracker", "STAR TRACKER", 0.28, 0.2, PackedStringArray(["OFF", "ON"]))
	_flight_ctl(p, "rotary", "c_att_mode", "ATTITUDE", 0.48, 0.22, PackedStringArray(Flight.ATT_MODES))
	# The bodies change from system to system: the target is stepped through with buttons.
	p.button("TGT PREV", 0.66, 0.2, func() -> void: flight.next_target(-1), Callable(), Ctl.WHITE)
	p.button("TGT NEXT", 0.78, 0.2, func() -> void: flight.next_target(1), Callable(), Ctl.WHITE)
	p.digits("TARGET No", 0.72, 0.38, func() -> String: return "%2d/%2d" % [flight.c_target + 1, flight.u.bodies.size()])
	_flight_ctl(p, "rotary", "c_program", "PROGRAM", 0.96, 0.22, PackedStringArray(Flight.PROGRAMS))
	p.digits("ATT ERR deg", 0.2, 0.42, func() -> String: return "%5.1f" % rad_to_deg(flight.att_error))
	p.group("GYROS", 1.2, 0.09, 0.4, 0.42)
	p.toggle("c_cmg", "CMG", 1.28, 0.2, PackedStringArray(["OFF", "ON"]))
	p.press("cmg_desat", "DESAT", 1.42, 0.2, Callable(), Ctl.WHITE)
	p.bar("MOMENTUM", 1.53, 0.32, func() -> float: return sim.cmg_h, Ctl.AMBER)
	_lamp(p, "cmg_sat", 1.34, 0.42)
	p.group("RCS", 0.04, 0.55, 1.56, 0.39)
	p.rotary("c_rcs_mode", "RCS MODE", 0.16, 0.72, PackedStringArray(["OFF", "ATT", "ATT+TRN"]))
	p.toggle("c_rcs_heat", "RCS HEATERS", 0.38, 0.7, PackedStringArray(["OFF", "ON"]))
	p.bar("N2H4", 0.54, 0.76, func() -> float: return sim.hyd / ShipSim.HYD_MAX, Ctl.GREEN)
	p.gauge("PROP TEMP", 0.72, 0.76, func() -> float: return sim.hyd_t - 273.15, -60.0, 40.0, "C")
	p.digits("N2H4 kg", 0.94, 0.68, func() -> String: return "%6.1f" % sim.hyd)
	_lamp(p, "rcs_cold", 0.94, 0.82)
	p.lamp("RCS FIRING", 1.2, 0.7, func() -> bool: return flight.rcs_active, Ctl.GREEN)


# --- Torch and gate -------------------------------------------------------------------------------

func _torch() -> void:
	var p := ControlPanel.make(station, sim, "FUSION TORCH", Vector2(2.4, 0.98), station.face_xform(2, -12.6), _inst())
	station.panels["torch"] = p
	p.group("IGNITION", 0.04, 0.09, 0.9, 0.85)
	p.toggle("c_torch_arm", "TORCH ARM", 0.14, 0.2, PackedStringArray(["SAFE", "ARM"]), true)
	p.toggle("c_torch_field", "NOZZLE FIELD", 0.3, 0.2, PackedStringArray(["OFF", "ON"]))
	p.bar("FIELD", 0.46, 0.28, func() -> float: return sim.torch_field, Ctl.AMBER)
	p.press("torch_ignite", "IGNITE", 0.62, 0.2, func() -> bool: return sim.torch_lit, Ctl.GREEN)
	p.press("torch_cut", "CUT OFF", 0.78, 0.2, Callable(), Ctl.RED)
	p.lamp("READY", 0.62, 0.38, func() -> bool: return sim.torch_ready() and not sim.torch_lit, Ctl.GREEN)
	_lamp(p, "torch_out", 0.24, 0.5)
	_lamp(p, "dhe_low", 0.24, 0.56)
	p.gauge("THRUST", 0.5, 0.66, func() -> float: return sim.torch_thrust / 1000.0, 0.0, 100.0, "kN")
	p.digits("ACCEL m/s2", 0.76, 0.6, func() -> String: return "%5.3f" % (sim.total_thrust() / sim.mass()))
	p.digits("FIELD kW", 0.76, 0.76, func() -> String: return "%5.1f" % sim.load_kw("torch"))
	p.group("FUEL", 0.98, 0.09, 0.42, 0.85)
	p.bar("D-HE3", 1.08, 0.36, func() -> float: return sim.dhe / ShipSim.DHE_MAX, Ctl.GREEN)
	p.digits("D-HE3 kg", 1.27, 0.26, func() -> String: return "%6d" % roundi(sim.dhe))
	p.digits("FLOW g/s", 1.27, 0.44, func() -> String: return "%5.2f" % (sim.torch_thrust / ShipSim.TORCH_VE * 1000.0))
	p.digits("DAYS FULL", 1.2, 0.7, func() -> String: return "%5.1f" % (sim.dhe / (ShipSim.TORCH_F / ShipSim.TORCH_VE) / 86400.0))
	p.lever("c_torch_thr", "TORCH THROTTLE", 1.6, 0.52)
	p.digits("DV COUNTER", 2.05, 0.3, func() -> String: return "%7d" % roundi(flight.dv_counter))
	p.button("LOAD DV", 2.05, 0.5, func() -> void: flight.load_counter(), Callable(), Ctl.WHITE)
	p.digits("REL V TGT", 2.05, 0.72, func() -> String: return "%7.0f" % flight.target_rel_v)


func _stars() -> void:
	var p := ControlPanel.make(station, sim, "STAR NAVIGATION", Vector2(2.4, 0.98), station.face_xform(6, -12.6), _inst())
	station.panels["stars"] = p
	p.group("PULSAR TIMING", 0.04, 0.09, 0.62, 0.85)
	p.lamp("PULSAR FIX", 0.2, 0.2, func() -> bool: return galaxy.pulsar_fix, Ctl.GREEN)
	p.lamp("PULSAR IN SKY", 0.48, 0.2, func() -> bool: return not flight.u.pulsar.is_empty(), Ctl.AMBER)
	p.button("START TIMING", 0.2, 0.42, func() -> void:
		if not galaxy.start_timing(flight.u):
			Sfx.play("error", -8.0, 1.0, "Station"), func() -> bool: return galaxy.timing_on, Ctl.AMBER)
	p.digits("TIMING %", 0.48, 0.42, func() -> String: return "%5.1f" % (galaxy.timing * 100.0))
	p.bar("TIMING", 0.34, 0.72, func() -> float: return galaxy.timing, Ctl.GREEN)
	p.group("POSITION", 0.7, 0.09, 0.56, 0.85)
	p.digits("LY FROM SOL", 0.98, 0.22, func() -> String: return "%6.2f" % galaxy.here_pos.length())
	p.digits("STARS SEEN", 0.98, 0.42, func() -> String: return "%5d" % galaxy.visited.size())
	p.digits("RANGE LY", 0.98, 0.62, func() -> String: return "  ANY" if galaxy.pulsar_fix else "%5d" % int(Galaxy.FREE_RANGE))
	star_screen = p.crt(1.82, 0.5, 1.0, 0.75, 14, 480.0)


func _star_text() -> String:
	var l := PackedStringArray()
	var u := flight.u
	l.append("STAR NAVIGATION")
	l.append("HERE  %s" % u.system_name.to_upper())
	l.append("      %s" % u.kind.to_upper())
	l.append("      %.2f LY FROM SOL" % galaxy.here_pos.length())
	l.append("RELAY %s" % ("IN CONTACT" if u.has_relay else "NONE"))
	l.append("")
	if map.mode == "galaxy" and map.star_target >= 0:
		var e := galaxy.star(map.star_target)
		var d := galaxy.distance(map.star_target)
		# A star never visited is only a guess until the station gets there.
		var known := galaxy.visited.has(map.star_target)
		l.append("DEST  %s" % (String(e.name).to_upper() if known else ("UNCHARTED" if map.aim_pos != Vector3.INF else "RADIO SOURCE")))
		l.append("      %s" % (String(e.kind).to_upper() if known else "UNKNOWN"))
		l.append(("      %.2f LY" % d) if known else ("      ~%d LY" % roundi(d)))
		l.append("TIME  %s" % Flight.game_duration(Galaxy.travel_time(d)))
		l.append("FUEL  %d kg" % roundi(Galaxy.travel_fuel(d)))
		var why := galaxy.plot_blocker(map.star_target)
		l.append("ROUTE PLOTTED" if why == "" else why)
	else:
		l.append("ZOOM THE MAP OUT TO THE STARS")
		l.append("TO PICK A STAR")
	if not flight.transit.is_empty() and flight.transit.has("interstellar"):
		l.append("")
		l.append("BETWEEN THE STARS")
		l.append("ARRIVE IN %s" % Flight.game_duration(flight.transit_left()))
	return "\n".join(l)


# --- Life support ---------------------------------------------------------------------------------

func _life() -> void:
	var p := ControlPanel.make(station, sim, "LIFE SUPPORT", Vector2(1.9, 0.98), station.face_xform(2, LIFE_Z), _inst())
	station.panels["life"] = p
	p.group("AIR", 0.04, 0.09, 0.66, 0.85)
	p.toggle("c_fans", "CABIN FANS", 0.14, 0.2, PackedStringArray(["OFF", "ON"]))
	p.gauge("CABIN", 0.2, 0.5, func() -> float: return sim.pressure(), 0.0, 120.0, "kPa")
	p.digits("TOTAL kPa", 0.5, 0.46, func() -> String: return "%5.1f" % sim.pressure())
	_lamp(p, "press", 0.5, 0.6)
	p.group("WATER", 0.76, 0.09, 0.4, 0.85)
	p.toggle("c_water_rec", "RECYCLER", 0.96, 0.2, PackedStringArray(["OFF", "ON"]))
	p.digits("WATER kg", 0.96, 0.46, func() -> String: return "%6.0f" % sim.water)
	life_screen = p.crt(1.55, 0.5, 0.56, 0.72, 11)


func _tanks() -> void:
	var p := ControlPanel.make(station, sim, "STORES", Vector2(1.6, 0.9), station.face_xform(6, LIFE_Z), _inst())
	station.panels["tanks"] = p
	p.bar("WATER", 0.2, 0.36, func() -> float: return sim.water / 1500.0, Ctl.GREEN)
	p.digits("WATER kg", 0.3, 0.66, func() -> String: return "%6.0f" % sim.water)
	p.digits("RATIONS", 0.65, 0.36, func() -> String: return "%4d" % sim.food)
	p.digits("PATCH KITS", 0.65, 0.66, func() -> String: return "%4d" % sim.patches)
	p.digits("PILLS", 1.1, 0.36, func() -> String: return "%4d" % sim.pills)
	p.digits("FILM", 1.1, 0.66, func() -> String: return "%4d" % sim.film)


# --- Screens ----------------------------------------------------------------------------------------

func refresh() -> void:
	var on := sim.powered("nav")
	star_screen.powered = on
	if on:
		star_screen.text = _star_text()
	nav_screen.powered = on
	map_screen.powered = on
	if on:
		nav_screen.text = _nav_text()
		map_screen.refresh()
	var inst: bool = _inst().call()
	reactor_screen.powered = inst
	power_screen.powered = inst
	life_screen.powered = inst
	reactor_screen.text = _reactor_text()
	reactor_screen.refresh()
	power_screen.text = _power_text()
	life_screen.text = _life_text()


static func clock(secs: float) -> String:
	if secs == INF or is_nan(secs):
		return "--:--:--:--"
	var s := int(secs)
	return "%03d:%02d:%02d:%02d" % [s / 86400, (s / 3600) % 24, (s / 60) % 60, s % 60]


static func km(m: float) -> String:
	if m == INF:
		return "    ---- km"
	if absf(m) > 1.0e10:
		return "%11.3f AU" % (m / Universe.AU)
	return "%11s km" % _thousands(roundi(m / 1000.0))


static func _thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = " " + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


func _nav_text() -> String:
	var e := flight.elements
	if e.is_empty():
		return "NAV  INITIALISING"
	var rb: float = flight.u.bodies[flight.soi].radius
	var l := PackedStringArray()
	l.append("NAV        MET %s" % clock(flight.t))
	l.append("%-9s ALT%s" % [flight.body_name().to_upper(), km(flight.altitude())])
	l.append("SPD %10.1f m/s  INC %4.1f" % [flight.speed(), rad_to_deg(e.inc)])
	l.append("PE %s  %s" % [km(e.pe - rb), clock(e.t_pe)])
	l.append("AP %s  %s" % [km(e.ap - rb) if e.ap != INF else "     ESCAPE   ", clock(e.t_ap)])
	l.append("ECC %.4f PER %s" % [e.e, clock(e.period)])
	l.append("ATT %-9s ERR %5.1f %s" % [Flight.ATT_MODES[flight.c_att_mode], rad_to_deg(flight.att_error), "RCS" if flight.rcs_active else ""])
	l.append("TGT %-9s%s" % [String(flight.u.bodies[flight.c_target].name).to_upper().left(9), km(flight.target_dist)])
	l.append("    REL V %10.1f m/s" % flight.target_rel_v)
	if flight.plan.has("closing"):
		l.append("PRG " + String(flight.plan.name).left(27))
		l.append("    CLOSING %9.1f m/s" % float(flight.plan.closing))
		l.append("    STOP IN %s" % km(float(flight.plan.stop)))
		l.append("    HOLD AT %s" % km(float(flight.plan.standoff)))
		l.append("    TURN IN %s %s" % [clock(float(flight.plan.t)), "BRAKE!" if float(flight.plan.t) <= 0.0 else ""])
	elif not flight.plan.is_empty():
		l.append("PRG " + String(flight.plan.name).left(27))
		l.append("    DV %5d m/s %s" % [roundi(absf(float(flight.plan.dv))), flight.plan.dir])
		l.append("    BURN IN %s" % clock(float(flight.plan.t)))
	else:
		l.append("PRG OFF")
	if not flight.transit.is_empty():
		l.append("TRANSIT  ARRIVE %s" % Flight.duration(flight.transit_left()))
	l.append("%-6s %.3f mSv/h" % ["SUN" if not flight.eclipsed else "SHADOW", flight.dose_rate])
	l.append("")
	l.append_array(_flight_steps())
	return "\n".join(l)


## What to do next to fly to the body picked on the map: the torch's steps, ticked off live,
## the next one marked, and what stands in the way.
func _flight_steps() -> PackedStringArray:
	var l := PackedStringArray()
	var b := flight.c_target
	var name := String(flight.u.bodies[b].name).to_upper()
	if not flight.transit.is_empty():
		l.append("FLYING TO %s" % name)
		l.append("ON ARRIVAL: THROTTLE DOWN, CUT OFF,")
		l.append("NOZZLE FIELD OFF, TORCH ARM SAFE")
		return l
	var why := flight.transit_blocker(b, sim)
	if why == "ALREADY THERE" or b == flight.soi:
		l.append("IN ORBIT ROUND %s" % name)
		if sim.torch_lit or sim.c_torch_arm:
			l.append("TORCH: THROTTLE DOWN, CUT OFF, SAFE")
		else:
			l.append("PICK WHERE TO GO ON THE MAP")
		return l
	if why in ["UNDOCK FIRST", "ALONGSIDE: DOCK AT THE PORT", "ALREADY PART OF THE STATION"]:
		l.append(why)
		return l
	l.append("TO %s  %s" % [name, Flight.game_duration(flight.transit_duration(b))])
	var need := roundi(flight.transit_fuel(b))
	if sim.dhe < flight.transit_fuel(b):
		l.append("D-HE3 %d kg  NEEDS %d kg" % [roundi(sim.dhe), need])
		l.append("SHORT: BUY D-HE3 (COMMS AND SUPPLY)")
		return l
	l.append("D-HE3 %d kg  NEEDS %d kg  OK" % [roundi(sim.dhe), need])
	# Each line its own template (so it translates whole), the mark in front: done, next, to do.
	var done := [sim.c_torch_arm, sim.torch_field >= 1.0, sim.torch_lit, sim.c_torch_thr >= 0.9, false]
	var marks := []
	var next_found := false
	for k in done.size():
		marks.append("[X]" if done[k] else ("-->" if not next_found else "[ ]"))
		if not done[k]:
			next_found = true
	l.append("%s 1 TORCH ARM (FUSION TORCH PANEL)" % marks[0])
	l.append("%s 2 NOZZLE FIELD ON  %d%%" % [marks[1], roundi(sim.torch_field * 100.0)])
	l.append("%s 3 IGNITE" % marks[2])
	l.append("%s 4 THROTTLE FULL" % marks[3])
	l.append("%s 5 ENGAGE (THIS PANEL)" % marks[4])
	return l


func _reactor_text() -> String:
	var mode := "POWER" if sim.rx_mode == 0 else "PROPULSION"
	var l := PackedStringArray()
	l.append("REACTOR  %s%s" % [mode, "  SCRAM" if sim.rx_scrammed else ""])
	l.append("RODS %5.1f%%  DEM %5.1f%%  %s" % [sim.rx_rod * 100.0, sim.c_rx_rods * 100.0, "AUTO" if sim.c_rx_auto else "MAN"])
	l.append("POWER %6.2f%%  Q %8.0f kW" % [sim.rx_power * 100.0, sim.rx_q_w / 1000.0])
	l.append("CORE %5d K  SET %5d K" % [roundi(sim.rx_t), roundi(sim.temp_setpoint())])
	l.append("LOOP %5d K  PUMP %3d%%" % [roundi(sim.loop_t), roundi(sim.c_rx_pump * 100.0)])
	l.append("H2 FLOW %5.2f kg/s" % sim.eng_mdot)
	l.append("GEN %6.1f kW %s" % [sim.gen_kw, "RUN" if sim.c_rx_turbine else "TRIP"])
	l.append("")
	l.append("CORE " + _bar(sim.rx_t / 3200.0, 20))
	l.append("PWR  " + _bar(sim.rx_power / 1.2, 20))
	l.append("RODS " + _bar(sim.rx_rod, 20))
	return "\n".join(l)


func _power_text() -> String:
	var l := PackedStringArray()
	l.append("POWER DISTRIBUTION")
	l.append("GEN %6.1f kW %s  SOLAR %5.1f kW %s" % [sim.gen_kw, ">A" if sim.c_gen_a else "  ", sim.sol_kw, ">B" if sim.c_sol_b else "  "])
	l.append("BUS A %5.1f V %6.1f kW   BUS B %5.1f V %6.1f kW" % [sim.bus_a_v, sim.load_a_kw, sim.bus_b_v, sim.load_b_kw])
	l.append("TIE %s   BATT %6.1f kWh %+6.1f kW" % ["CLOSED" if sim.c_tie else "OPEN  ", sim.bat_kwh, sim.bat_kw])
	l.append("")
	var row := ""
	var k := 0
	for b: String in ShipSim.BREAKERS:
		var on := sim.powered(b)
		row += "%-10s %s %5.1f   " % [ShipSim.BREAKERS[b][0], ShipSim.BREAKERS[b][1], sim.load_kw(b)] if on else "%-10s %s  ---    " % [ShipSim.BREAKERS[b][0], ShipSim.BREAKERS[b][1]]
		k += 1
		if k % 2 == 0:
			l.append(row)
			row = ""
	if row != "":
		l.append(row)
	return "\n".join(l)


func _life_text() -> String:
	var l := PackedStringArray()
	l.append("CABIN AIR")
	l.append("PRESS %5.1f" % sim.pressure())
	l.append("")
	l.append("CABIN %4.1f C" % (sim.cab_t - 273.15))
	l.append("LEAK %s" % ("YES" if sim.leak_area > 0.0 else "NO"))
	return "\n".join(l)


static func _bar(f: float, n: int) -> String:
	var k := clampi(roundi(f * n), 0, n)
	return "[" + "#".repeat(k) + ".".repeat(n - k) + "]"


func _draw_reactor(_c: Control, _size: Vector2) -> void:
	pass
