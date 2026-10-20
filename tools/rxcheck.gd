extends SceneTree
## Headless check of the reactor's accidents: what each careless move or ignored fault leads
## to. godot --headless --path . -s tools/rxcheck.gd


func _settled() -> ShipSim:
	var s := ShipSim.new()
	s.rx_rod = s.c_rx_rods
	s.settle(4.0 * 3600.0)
	s.rx_fuel = [0.3, 0.3, 0.3]
	return s


func _line(s: ShipSim, t: float) -> String:
	var on := []
	for a: String in s.alarms:
		if s.alarms[a]:
			on.append(a)
	return "t %5.0f  P %.2f  T %5.0f  p %.2f MPa  cool %.2f  melt %s  boom '%s'  %s" % [t, s.rx_power, s.rx_t, s.rx_loop_p, s.rx_coolant, "--" if s.rx_melt_t == INF else "%.0f" % s.rx_melt_t, s.rx_boom, str(on)]


func _run(s: ShipSim, secs: float, every: float) -> void:
	var t := 0.0
	while t < secs and s.rx_boom == "":
		s.tick(1.0)
		t += 1.0
		if fmod(t, every) < 0.5:
			print(_line(s, t))
	if s.rx_boom != "":
		print(_line(s, t))


func _init() -> void:
	var s := _settled()
	print("--- settled")
	print(_line(s, 0))
	print("--- an ignored coolant leak (interlock on)")
	s.rx_leak = 0.004
	_run(s, 3600.0, 300.0)
	print("--- ...then FILL opened on the dry, hot core")
	s.rx_leak = 0.0
	s.c_rx_fill = true
	_run(s, 60.0, 5.0)

	s = _settled()
	print("--- pump trip")
	s.brk["rxpump"] = false
	_run(s, 240.0, 30.0)

	s = _settled()
	print("--- pump trip, interlock off, relief SHUT, rods by hand held out")
	s.brk["rxpump"] = false
	s.c_rx_interlock = false
	s.c_rx_relief = false
	s.c_rx_auto = false
	s.c_rx_rods = 0.6
	_run(s, 600.0, 30.0)

	for auto in [false, true]:
		s = _settled()
		print("--- cold restart on fresh fuel, rods yanked out, AUTO %s" % auto)
		s.rx_fuel = [0.0, 0.0, 0.0]
		s.press("rx_scram")
		for i in 1800:
			s.tick(1.0)
		s.c_rx_rods = 0.0
		s.press("rx_reset")
		s.c_rx_auto = auto
		s.c_rx_rods = 1.0
		_run(s, 120.0, 10.0)

	s = _settled()
	print("--- head opened hot under OVERRIDE")
	s.press("rx_scram")
	for i in 30:
		s.tick(1.0)
	s.c_rx_override = true
	s.open_head()
	print(_line(s, 30))

	s = _settled()
	print("--- fuel over a 10 min main engine burn (P 0.8 in PROP)")
	s.rx_fuel = [0.3, 0.3, 0.3]
	var b0 := s.fuel_burnup()
	print("burnup %.2f -> %.2f" % [b0, b0 + 600.0 * 0.8 * 0.6 / ShipSim.FUEL_LIFE])
	print("--- pump wear over an hour at the usual pump setting: %.2f" % (3600.0 * (0.5 + 0.25) / 6000.0))
	quit()
