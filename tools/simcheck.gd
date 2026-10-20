extends SceneTree
## Headless check of the systems sim: settle a running station and print it.
## godot --headless --path . -s tools/simcheck.gd


func _init() -> void:
	var s := ShipSim.new()
	s.rx_rod = s.c_rx_rods
	s.settle(4.0 * 3600.0)
	_dump(s, "settled")
	for i in 6:
		# Fresh fuel each hour: this is about the rest of the station, not the fuel cycle.
		s.rx_fuel = [0.0, 0.0, 0.0]
		s.tick(3600.0)
	_dump(s, "+6 h")
	quit()


func _dump(s: ShipSim, label: String) -> void:
	print("--- ", label)
	print("rx rod %.2f P %.3f Q %.0f kW T %.0f K | loop %.0f K | gen %.1f kW" % [s.rx_rod, s.rx_power, s.rx_q_w / 1000.0, s.rx_t, s.loop_t, s.gen_kw])
	print("bus A %.0f V %.1f kW  B %.0f V %.1f kW  bat %.1f kWh (%.1f kW) sol %.1f" % [s.bus_a_v, s.load_a_kw, s.bus_b_v, s.load_b_kw, s.bat_kwh, s.bat_kw, s.sol_kw])
	print("cabin %.1f C  O2 %.2f CO2 %.2f N2 %.1f  water %.0f  h2 %.0f p %.3f" % [s.cab_t - 273.15, s.pp_o2, s.pp_co2, s.pp_n2, s.water, s.h2, s.h2_p])
	var on := []
	for a: String in s.alarms:
		if s.alarms[a]:
			on.append(a)
	print("alarms: ", on)
