extends SceneTree
## Headless check: switch the reactor to propulsion, light the engine, burn, shut down, cool.


func _init() -> void:
	var s := ShipSim.new()
	s.rx_rod = s.c_rx_rods
	s.settle(4.0 * 3600.0)
	s.c_radiators = false
	s.c_arrays = false
	s.c_rx_auto = false
	s.c_rx_rods = 0.0
	_run(s, 120.0, "rods in")
	s.c_rx_mode = 1
	s.c_he_press = true
	s.c_eng_arm = true
	s.c_h2_feed = 1.0
	_run(s, 5.0, "mode prop")
	s.press("eng_start")
	_run(s, 10.0, "pump spin")
	s.c_throttle = 0.1
	s.c_rx_auto = true
	_run(s, 20.0, "throttle 10%, auto")
	s.c_throttle = 1.0
	for i in 10:
		_run(s, 3.0, "full")
	for i in 5:
		_run(s, 20.0, "full")
	_run(s, 600.0, "burn 10 min")
	s.c_throttle = 0.0
	s.c_rx_auto = false
	s.c_rx_rods = 0.0
	_run(s, 30.0, "cut")
	s.c_cool_valve = true
	for i in 6:
		_run(s, 300.0, "cooldown")
	quit()


func _run(s: ShipSim, secs: float, label: String) -> void:
	var n := int(secs / 0.5)
	for i in n:
		s.tick(0.5)
	var on := []
	for a: String in s.alarms:
		if s.alarms[a]:
			on.append(a)
	print("%-18s mode %d rod %.2f P %.3f T %5.0f spin %.2f mdot %5.2f F %6.0f N ve %4.0f h2 %6.0f p %.3f bat %5.1f dmg %.3f %s" % [label, s.rx_mode, s.rx_rod, s.rx_power, s.rx_t, s.pump_spin, s.eng_mdot, s.thrust, s.exhaust_speed(), s.h2, s.h2_p, s.bat_kwh, s.rx_damage, on])
