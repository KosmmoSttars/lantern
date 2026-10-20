extends SceneTree
## Headless check of orbits: a circular orbit stays circular, a transfer burn reaches Titan.


func _init() -> void:
	var u := Universe.solar(7)
	var saturn := u.find("Saturn")
	var f := Flight.new()
	f.setup(u, saturn, 500e6, 0.3)
	var s := ShipSim.new()
	s.rx_rod = s.c_rx_rods
	s.settle(3600.0)
	f.tick(1.0, s)
	print("start r %.0f km v %.1f m/s e %.5f period %.2f d" % [f.radius() / 1000.0, f.speed(), f.elements.e, f.elements.period / 86400.0])
	for i in 50:
		f.tick(86400.0 * 0.1, s)
	print("+5 d  r %.0f km v %.1f m/s e %.5f" % [f.radius() / 1000.0, f.speed(), f.elements.e])
	f.c_target = u.find("Titan")
	f.c_program = Flight.PROGRAMS.find("TRANSFER")
	f.tick(1.0, s)
	print("plan ", f.plan.name, " dv %.0f wait %.2f d coast %.2f d" % [f.plan.dv, f.plan.t / 86400.0, f.plan.coast / 86400.0])
	# Coast to the burn, point prograde, burn the planned dv.
	var wait: float = f.plan.t
	f.tick(wait, s)
	f.c_att_mode = Flight.ATT_MODES.find("PROGRADE")
	for i in 400:
		f.tick(1.0, s)
	print("attitude error %.2f deg" % rad_to_deg(f.att_error))
	f.load_counter()
	f.mass = s.mass()
	f.thrust = 140000.0
	var burnt := 0.0
	while f.dv_counter > 0.0:
		f.tick(1.0, s)
		burnt += 1.0
	f.thrust = 0.0
	f.tick(1.0, s)
	print("burn %.0f s, ap %.0f km (Titan a %.0f km)" % [burnt, f.elements.ap / 1000.0, u.bodies[u.find("Titan")].a / 1000.0])
	var coast: float = f.plan.get("coast", 0.0)
	var best := INF
	var tt := 0.0
	while tt < 6.0 * 86400.0:
		f.tick(600.0, s)
		tt += 600.0
		if f.soi != saturn:
			print("entered ", f.body_name(), " after %.2f d, r %.0f km" % [tt / 86400.0, f.radius() / 1000.0])
			break
		best = minf(best, f.target_dist)
	print("closest to Titan %.0f km, soi %s" % [best / 1000.0, f.body_name()])
	quit()
