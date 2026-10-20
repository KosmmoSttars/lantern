class_name Flight
extends RefCounted
## Where Lantern is and which way it points: patched conics among the bodies of a Universe,
## attitude control by gyros and RCS, the nav computer's plans and the delta-v counter, and
## the torch transit: a course picked on the map and flown at the torch's full fury,
## accelerating half way and braking the rest, into orbit round the body picked. Time runs
## at one second a second, always.
##
## Station frame: bow toward -Z, the main engine pushes the station bow-first.

signal event(kind: String, text: String)

const ATT_MODES := ["FREE", "HOLD", "PROGRADE", "RETRO", "NORMAL", "ANTI-NRM", "RAD OUT", "RAD IN", "TARGET", "TGT PRO", "TGT RETRO", "HORIZON", "SUN"]
const PROGRAMS := ["OFF", "CIRC AP", "CIRC PE", "CIRC NOW", "TRANSFER", "MATCH TGT", "INTERCEPT"]
## Torch transit: how long a crossing of distance d takes (s), and what it burns (kg).
const TRANSIT_BASE := 180.0
## How far off a derelict a transit leaves the station (m).
const DERELICT_STANDOFF := 70.0
const TRANSIT_MIN := 60.0
const TRANSIT_MAX := 2400.0
const INERTIA := 2.2e7
const RCS_LEVER := 20.0

var u: Universe
var t := 0.0
var soi := 0
var st := PackedFloat64Array([0, 0, 0, 0, 0, 0])
var att := Basis()
## Body rates in the station frame (rad/s).
var omega := Vector3.ZERO
var mass := 200000.0
## Everything pushing bow-first, and the part of it that is the main (nuclear) engine.
var thrust := 0.0
var ntr_thrust := 0.0

# Controls (the GNC panel binds to these).
var c_att_mode := 1
var c_target := 0
var c_program := 0

# Outputs.
var eclipsed := false
var dose_rate := 0.02
var plan := {}
var dv_counter := 0.0
var elements := {}
var target_dist := 0.0
var target_rel_v := 0.0
var att_error := 0.0
var rcs_active := false
## Light here: direction (system frame) and strength relative to sunlight at Saturn.
var light_dir := Vector3.FORWARD
var light_flux := 1.0
## A pulsar beam is crossing the station right now.
var beam_hit := false
## The delta-v counter just ran down to zero (main sounds it and drops time compression).
var counter_done := false
## Torch transit under way: {target, t0, dur, p0, v0, p1, v1, fuel} (relative to the target).
var transit := {}
## Something is docked at the docking port: nothing moves the station until it lets go.
var docked := false

var _hold := Basis()
var _last_mode := -1
var _elem_t := -1.0
var _ring_side := 0.0


func setup(p_u: Universe, start_body: int, radius: float, at_angle: float, inc_deg := 0.0) -> void:
	u = p_u
	soi = start_body
	var mu: float = u.bodies[soi].mu
	var v := Orbit.circular(mu, radius)
	var r := Vector3(cos(at_angle), 0.0, -sin(at_angle)).rotated(Vector3.RIGHT, deg_to_rad(inc_deg))
	var vd := Vector3(-sin(at_angle), 0.0, -cos(at_angle)).rotated(Vector3.RIGHT, deg_to_rad(inc_deg))
	st = PackedFloat64Array([r.x * radius, r.y * radius, r.z * radius, vd.x * v, vd.y * v, vd.z * v])
	# Bow along the velocity, crown toward the planet's north.
	att = _basis_toward(Orbit.dir(Orbit.vel(st)), Vector3.UP)
	_hold = att


func mu() -> float:
	return u.bodies[soi].mu


func body_name() -> String:
	return u.bodies[soi].name


## Ship position in the system frame.
func world_pos() -> PackedFloat64Array:
	return Orbit.add(u.position(soi, t), Orbit.pos(st))


func world_vel() -> PackedFloat64Array:
	return Orbit.add(u.velocity(soi, t), Orbit.vel(st))


func radius() -> float:
	return Orbit.length(Orbit.pos(st))


func altitude() -> float:
	return radius() - float(u.bodies[soi].radius)


func speed() -> float:
	return Orbit.length(Orbit.vel(st))


## Direction (system frame) of the bow.
func bow() -> Vector3:
	return att * Vector3.FORWARD


func light() -> Array:
	return [light_dir, light_flux]


# --- Step ---------------------------------------------------------------------------------------

## Advance `dt` game seconds. `sim` pays for RCS and gyro work.
func tick(dt: float, sim: ShipSim) -> void:
	if dt <= 0.0:
		return
	if not transit.is_empty() and transit.has("interstellar"):
		_interstellar_step(dt, sim)
		_environment()
		elements = Orbit.elements(st, mu())
		return
	if not transit.is_empty():
		_transit_step(dt, sim)
		_environment()
		elements = Orbit.elements(st, mu())
		_update_plan()
		return
	var acc_mag := thrust / mass
	if acc_mag > 0.0:
		# Under power: integrate in steps (the main engine is brief and hard, the torch long
		# and gentle), turning the station as it goes.
		var limit := 1.0 if ntr_thrust > 0.0 else 30.0
		var steps := maxi(1, ceili(dt / limit))
		var h := dt / steps
		for i in steps:
			_attitude(h, sim)
			var a := Orbit.from_vec(bow() * acc_mag)
			st = Orbit.integrate(st, mu(), a, h)
			t += h
			_check_soi()
		var before := dv_counter
		dv_counter -= acc_mag * dt
		if before > 0.0 and dv_counter <= 0.0:
			counter_done = true
	else:
		_attitude(dt, sim)
		# Coasting: exact, in pieces so sphere-of-influence changes are not jumped over.
		var left := dt
		var piece := _coast_piece()
		while left > 0.0:
			var h := minf(left, piece)
			st = Orbit.propagate(st, mu(), h)
			t += h
			left -= h
			_check_soi()
	_environment()
	if t - _elem_t > 0.2 or dt > 1.0:
		_elem_t = t
		elements = Orbit.elements(st, mu())
		_update_plan()


func _coast_piece() -> float:
	# Small enough to notice entering a moon's sphere of influence.
	var smallest := INF
	for c in u.children(soi):
		smallest = minf(smallest, float(u.bodies[c].soi))
	if soi != 0:
		smallest = minf(smallest, float(u.bodies[soi].soi))
	if smallest == INF:
		return 3600.0
	return clampf(smallest / maxf(speed(), 1.0) * 0.25, 5.0, 3600.0)


func _check_soi() -> void:
	var r := radius()
	if soi != 0 and r > float(u.bodies[soi].soi):
		var old := soi
		var parent: int = u.bodies[soi].parent
		var body_st := Orbit.state(Orbit.sub(u.position(old, t), u.position(parent, t)), Orbit.sub(u.velocity(old, t), u.velocity(parent, t)))
		st = Orbit.add(st, body_st)
		soi = parent
		event.emit("soi", "Left %s's sphere of influence" % u.bodies[old].name)
		return
	for c in u.children(soi):
		var rel_r := Orbit.sub(Orbit.sub(u.position(c, t), u.position(soi, t)), Orbit.pos(st))
		if Orbit.length(rel_r) < float(u.bodies[c].soi):
			var body_st := Orbit.state(Orbit.sub(u.position(c, t), u.position(soi, t)), Orbit.sub(u.velocity(c, t), u.velocity(soi, t)))
			st = Orbit.sub(st, body_st)
			soi = c
			event.emit("soi", "Entered %s's sphere of influence" % u.bodies[c].name)
			return
	if r < float(u.bodies[soi].radius):
		event.emit("crash", "Impact on %s" % u.bodies[soi].name)


# --- Attitude --------------------------------------------------------------------------------

static func _basis_toward(fwd: Vector3, up_hint: Vector3) -> Basis:
	var z := -fwd.normalized()
	var x := up_hint.cross(z)
	if x.length() < 1e-4:
		x = Vector3.RIGHT.cross(z) if absf(z.x) < 0.9 else Vector3.UP.cross(z)
	x = x.normalized()
	var y := z.cross(x).normalized()
	return Basis(x, y, z)


## The orientation the current attitude mode wants (system frame), or null in FREE.
func target_basis() -> Variant:
	var r := Orbit.dir(Orbit.pos(st))
	var v := Orbit.dir(Orbit.vel(st))
	var n := r.cross(v).normalized()
	match ATT_MODES[c_att_mode]:
		"FREE":
			return null
		"HOLD":
			return _hold
		"PROGRADE":
			return _basis_toward(v, r)
		"RETRO":
			return _basis_toward(-v, r)
		"NORMAL":
			return _basis_toward(n, r)
		"ANTI-NRM":
			return _basis_toward(-n, r)
		"RAD OUT":
			return _basis_toward(r, n)
		"RAD IN":
			return _basis_toward(-r, n)
		"TARGET":
			var d := Orbit.dir(Orbit.sub(u.position(c_target, t), world_pos()))
			return _basis_toward(d, n)
		"SUN":
			return _basis_toward(light_dir, n)
		"HORIZON":
			return _basis_toward(_horizon(), r)
		"TGT PRO", "TGT RETRO":
			# Along (or against) the velocity relative to the target: burn TGT RETRO to
			# stop beside it.
			var rv := Orbit.dir(Orbit.sub(world_vel(), u.velocity(c_target, t)))
			if rv == Vector3.ZERO:
				return _hold
			return _basis_toward(rv if ATT_MODES[c_att_mode] == "TGT PRO" else -rv, n)
	return null


func _attitude(dt: float, sim: ShipSim) -> void:
	if c_att_mode != _last_mode:
		_last_mode = c_att_mode
		_hold = att
	rcs_active = false
	var want: Variant = target_basis()
	var have_rcs := sim.rcs_ok()
	var have_cmg := sim.powered("cmg") and sim.cmg_h < 1.0
	var nav_ok := sim.powered("nav")
	var max_rate := deg_to_rad(1.0) if have_rcs else (deg_to_rad(0.15) if have_cmg else 0.0)
	var max_acc := deg_to_rad(0.2) if have_rcs else (deg_to_rad(0.01) if have_cmg else 0.0)
	if want == null or not nav_ok or max_rate <= 0.0:
		att_error = 0.0
		att = (att * Basis(omega.normalized(), omega.length() * dt)).orthonormalized() if omega.length() > 1e-9 else att
		return
	var wb: Basis = want
	var q := Quaternion(wb.orthonormalized()) * Quaternion(att.orthonormalized()).inverse()
	var angle := q.get_angle()
	if angle > PI:
		angle -= TAU
	var axis := q.get_axis() if absf(angle) > 1e-6 else Vector3.UP
	att_error = absf(angle)
	if dt > 30.0:
		# Long time compression: the controller is assumed to have held the attitude.
		att = wb.orthonormalized()
		omega = Vector3.ZERO
		return
	var local_axis := (att.inverse() * axis).normalized()
	var want_omega := local_axis * clampf(angle * 0.25, -max_rate, max_rate)
	var d := want_omega - omega
	var dmax := max_acc * dt
	if d.length() > dmax:
		d = d.normalized() * dmax
	omega += d
	var used := d.length()
	if used > 1e-7:
		if have_rcs:
			rcs_active = used > dmax * 0.3
			sim.spend_rcs(used * INERTIA / RCS_LEVER * 0.02)
		else:
			sim.load_cmg(used * 2.0)
	att = (att * Basis(omega.normalized(), omega.length() * dt)).orthonormalized() if omega.length() > 1e-9 else att


# --- Environment ---------------------------------------------------------------------------------

func _environment() -> void:
	var p := world_pos()
	var l := u.light_at(p, t)
	light_dir = l[0]
	light_flux = l[1]
	eclipsed = false
	for i in u.bodies.size():
		var b := u.bodies[i]
		if float(b.radius) < 50e3 or i == u.star_index or b.kind == "gate":
			continue
		var d := Orbit.sub(u.position(i, t), p)
		var along := Orbit.dot(d, Orbit.from_vec(light_dir))
		if along <= 0.0:
			continue
		var perp2 := Orbit.dot(d, d) - along * along
		if perp2 < pow(float(b.radius), 2.0):
			eclipsed = true
			break
	# Galactic cosmic rays everywhere, whatever the system adds, and the radiation belts of
	# Saturn and (far worse) Jupiter.
	dose_rate = 0.021 + u.background_dose
	if u.system_id == 0:
		var sat := u.find("Saturn")
		var rs := Orbit.length(Orbit.sub(p, u.position(sat, t))) / 58232e3
		dose_rate += 0.35 * exp(-pow((rs - 5.0) / 1.6, 2.0)) if rs > 2.3 else 0.0
		var jup := u.find("Jupiter")
		var rj := Orbit.length(Orbit.sub(p, u.position(jup, t))) / 6.9911e7
		dose_rate += 1500.0 * exp(-pow((rj - 6.0) / 3.0, 2.0)) if rj > 1.2 else 0.0
	beam_hit = false
	if not u.pulsar.is_empty():
		# The beams sweep round the pulsar's spin axis on a 50-degree cone that passes
		# through the station: one crossing per turn, as wide as the beam.
		var frac: float = float(u.pulsar.angle) / (PI * sin(deg_to_rad(50.0)))
		var phase := pulsar_phase()
		beam_hit = phase < frac * 0.5 or phase > 1.0 - frac * 0.5
		var spike: float = u.pulsar.spike
		dose_rate += spike if beam_hit else 0.0
	# Close to a black hole the disk's X-rays and the tides get serious.
	if not u.black_hole.is_empty():
		var n := Orbit.length(Orbit.sub(p, u.position(0, t))) / float(u.black_hole.rs)
		dose_rate += 400.0 / maxf(n, 1.0)
		if n < 6.0:
			event.emit("crash", "Torn apart by the tides of the singularity")
	# Crossing Saturn's ring plane inside the rings.
	var rel_sat := Orbit.sub(p, u.position(u.find("Saturn"), t)) if u.system_id == 0 else p
	var side := signf(rel_sat[1])
	if _ring_side != 0.0 and side != _ring_side and u.system_id == 0:
		var rr := sqrt(rel_sat[0] * rel_sat[0] + rel_sat[2] * rel_sat[2])
		if rr > 74.5e6 and rr < 140.2e6 and not (rr > 117.58e6 and rr < 122.17e6):
			event.emit("rings", "Crossed the rings at %d km" % roundi(rr / 1000.0))
	_ring_side = side
	# Target.
	var tp := u.position(c_target, t)
	target_dist = Orbit.length(Orbit.sub(tp, p))
	target_rel_v = Orbit.length(Orbit.sub(u.velocity(c_target, t), world_vel()))


## Where the pulsar's beams are in their turn (0..1), by real time so they sweep visibly
## whatever the time compression.
func pulsar_phase() -> float:
	if u.pulsar.is_empty():
		return 0.0
	return fposmod(Time.get_ticks_msec() / 1000.0 / float(u.pulsar.period), 1.0)


func sun_flux() -> float:
	return 0.0 if eclipsed else light_flux


# --- Nav computer ------------------------------------------------------------------------------

func _update_plan() -> void:
	plan = {}
	var e := elements
	match PROGRAMS[c_program]:
		"CIRC AP":
			if e.e < 1.0:
				var r: float = e.ap
				var v_now := sqrt(mu() * (2.0 / r - 1.0 / e.a))
				plan = {"name": "CIRCULARISE AT AP", "dv": Orbit.circular(mu(), r) - v_now, "t": e.t_ap, "dir": "PROGRADE"}
		"CIRC PE":
			var r: float = e.pe
			var v_now := sqrt(mu() * (2.0 / r - 1.0 / e.a)) if e.a != INF else sqrt(2.0 * mu() / r)
			var dv := Orbit.circular(mu(), r) - v_now
			plan = {"name": "CIRCULARISE AT PE", "dv": dv, "t": e.t_pe, "dir": "PROGRADE" if dv > 0.0 else "RETRO"}
		"TRANSFER":
			_plan_transfer()
		"MATCH TGT":
			plan = {"name": "MATCH TARGET VELOCITY", "dv": -target_rel_v, "t": 0.0, "dir": "RETRO (TGT)"}
		"CIRC NOW":
			var hz := Orbit.from_vec(_horizon())
			var v_now := Orbit.dot(Orbit.vel(st), hz)
			plan = {"name": "CIRCULARISE HERE", "dv": Orbit.circular(mu(), radius()) - v_now, "t": 0.0, "dir": "HORIZON"}
		"INTERCEPT":
			_plan_intercept()


## Hohmann transfer to the target's orbit round the same primary, timed for the meeting.
func _plan_transfer() -> void:
	if c_target == soi or int(u.bodies[c_target].parent) != soi:
		plan = {"name": "NO TRANSFER: TARGET NOT IN THIS ORBIT", "dv": 0.0, "t": 0.0, "dir": "-"}
		return
	var r1 := radius()
	var r2: float = u.bodies[c_target].a
	var m := mu()
	var at := (r1 + r2) * 0.5
	var tt := PI * sqrt(at * at * at / m)
	var n1 := sqrt(m / pow(r1, 3.0))
	var n2 := TAU / float(u.bodies[c_target].period)
	var want_phase := PI - n2 * tt
	var ship_ang := _angle_of(Orbit.pos(st))
	var tgt_ang := _angle_of(Orbit.sub(u.position(c_target, t), u.position(soi, t)))
	var now_phase := wrapf(tgt_ang - ship_ang, -PI, PI)
	var rate := n2 - n1
	var wait := wrapf(want_phase - now_phase, -PI, PI) / rate if absf(rate) > 1e-12 else 0.0
	if wait < 0.0:
		wait += TAU / absf(rate)
	var dv1 := sqrt(m / r1) * (sqrt(2.0 * r2 / (r1 + r2)) - 1.0)
	plan = {"name": "TRANSFER TO " + String(u.bodies[c_target].name).to_upper(), "dv": dv1, "t": wait, "dir": "PROGRADE" if dv1 > 0.0 else "RETRO", "coast": tt}


func _angle_of(v: PackedFloat64Array) -> float:
	return atan2(-v[2], v[0])


## Level with the body below, along the way the station is already going round it (or, at
## rest, round its north).
func _horizon() -> Vector3:
	var r := Orbit.dir(Orbit.pos(st))
	var h := Orbit.cross(Orbit.pos(st), Orbit.vel(st))
	var n := Orbit.dir(h) if Orbit.length(h) > radius() * 50.0 else Vector3.UP
	var hz := n.cross(r)
	if hz.length() < 0.1:
		hz = Vector3.RIGHT.cross(r)
	return hz.normalized()


## Where to stop short of a body to orbit it: high enough that its pull is a tenth of what
## the torch can push, so there is time to turn and speed up along the horizon.
func standoff(b: int) -> float:
	var bb := u.bodies[b]
	var mu_b: float = bb.mu
	if mu_b <= 0.0:
		return 20e3
	var a := ShipSim.TORCH_F / mass
	return clampf(sqrt(mu_b / (0.1 * a)), float(bb.radius) * 3.0, maxf(float(bb.soi) * 0.4, float(bb.radius) * 3.0))


## Readouts for flying to the target by hand with the torch: how fast it is closing, how far
## the station would coast before stopping if it turned round and braked now at full torch,
## and how long until that turn is due.
func _plan_intercept() -> void:
	var p := world_pos()
	var r := Orbit.sub(u.position(c_target, t), p)
	var v := Orbit.sub(world_vel(), u.velocity(c_target, t))
	var dist := Orbit.length(r)
	var closing := Orbit.dot(v, r) / maxf(dist, 1.0)
	var a := ShipSim.TORCH_F / mass
	var stop := closing * closing / (2.0 * a) if closing > 0.0 else 0.0
	var keep := standoff(c_target)
	var turn_in := (dist - keep - stop) / closing if closing > 1.0 else INF
	plan = {"name": "INTERCEPT " + String(u.bodies[c_target].name).to_upper(), "dv": closing, "t": maxf(turn_in, 0.0),
		"dir": "TURN, BRAKE" if turn_in <= 0.0 else "CLOSING", "stop": stop, "closing": closing, "standoff": keep}


# --- Torch transit ------------------------------------------------------------------------------

## Where a transit to body b ends: an orbit high enough to be safe (or right beside a gate).
func transit_radius(b: int) -> float:
	var bb := u.bodies[b]
	# A derelict or a module: come to rest a stone's throw off it, where it can be docked.
	if bb.kind in ["derelict", "module"]:
		return DERELICT_STANDOFF
	if float(bb.mu) <= 0.0:
		return 25e3
	var lo: float = float(bb.radius) * 4.0
	var hi: float = maxf(float(bb.soi) * 0.25, lo)
	return clampf(float(bb.radius) * 6.0, lo, hi)


## Straight-line distance to where a transit to b would end.
func transit_distance(b: int) -> float:
	var rel := Orbit.sub(world_pos(), u.position(b, t))
	return maxf(Orbit.length(rel) - transit_radius(b), 0.0)


## Seconds a transit to b would take: short hops a few minutes, across a system half an hour.
func transit_duration(b: int) -> float:
	return clampf(TRANSIT_BASE * pow(maxf(transit_distance(b), 1.0) / 1.0e8, 0.25), TRANSIT_MIN, TRANSIT_MAX)


## D-He3 a transit to b would burn (kg).
func transit_fuel(b: int) -> float:
	return 60.0 + transit_distance(b) / 1.0e9 * 12.0


## Why a transit to b cannot start ("" when it can).
func transit_blocker(b: int, sim: ShipSim) -> String:
	if docked:
		return "UNDOCK FIRST"
	if u.bodies[b].get("gone", false):
		return "ALREADY PART OF THE STATION"
	if u.bodies[b].kind in ["derelict", "module"] and Orbit.length(Orbit.sub(world_pos(), u.position(b, t))) < 400.0:
		return "ALONGSIDE: DOCK AT THE PORT"
	if b == soi and transit_distance(b) < transit_radius(b) * 0.5:
		return "ALREADY THERE"
	if not sim.torch_lit:
		return "TORCH NOT LIT"
	if sim.c_torch_thr < 0.9:
		return "THROTTLE TO FULL"
	if sim.dhe < transit_fuel(b):
		return "NOT ENOUGH D-HE3"
	return ""


func start_transit(b: int, sim: ShipSim) -> bool:
	if transit_blocker(b, sim) != "":
		return false
	var tp := u.position(b, t)
	var tv := u.velocity(b, t)
	var p0 := Orbit.sub(world_pos(), tp)
	var v0 := Orbit.sub(world_vel(), tv)
	var r1 := transit_radius(b)
	var side := Orbit.dir(p0)
	if side == Vector3.ZERO:
		side = Vector3.RIGHT
	var p1 := Orbit.scale(Orbit.from_vec(side), r1)
	var v1 := Orbit.v3(0, 0, 0)
	var mu_b: float = u.bodies[b].mu
	if mu_b > 0.0:
		# Arrive moving along a circular orbit, prograde round the body's north.
		var tan := Vector3.UP.cross(side)
		if tan.length() < 0.1:
			tan = Vector3.RIGHT.cross(side)
		v1 = Orbit.scale(Orbit.from_vec(tan.normalized()), sqrt(mu_b / r1))
	transit = {"target": b, "t0": t, "dur": transit_duration(b), "p0": p0, "v0": v0, "p1": p1, "v1": v1}
	sim.spend_dhe(transit_fuel(b))
	c_target = b
	event.emit("transit", "Transit to %s: %s" % [u.bodies[b].name, Flight.game_duration(float(transit.dur))])
	return true


## Pull out of a transit: the station flies on at whatever speed it has.
func abort_transit() -> void:
	if transit.is_empty():
		return
	transit = {}
	_check_soi()
	event.emit("transit", "Transit broken off")


func transit_left() -> float:
	if transit.is_empty():
		return 0.0
	return maxf(float(transit.t0) + float(transit.dur) - t, 0.0)


func _transit_step(dt: float, sim: ShipSim) -> void:
	if not sim.torch_lit or sim.c_torch_thr < 0.5:
		abort_transit()
		return
	t += dt
	var b: int = transit.target
	var dur: float = transit.dur
	var s := clampf((t - float(transit.t0)) / dur, 0.0, 1.0)
	var p0: PackedFloat64Array = transit.p0
	var v0: PackedFloat64Array = transit.v0
	var p1: PackedFloat64Array = transit.p1
	var v1: PackedFloat64Array = transit.v1
	# Cubic Hermite from where we were to the orbit: position and velocity both match at the ends.
	var s2 := s * s
	var s3 := s2 * s
	var pos := Orbit.add(Orbit.add(Orbit.scale(p0, 2.0 * s3 - 3.0 * s2 + 1.0), Orbit.scale(v0, (s3 - 2.0 * s2 + s) * dur)),
		Orbit.add(Orbit.scale(p1, -2.0 * s3 + 3.0 * s2), Orbit.scale(v1, (s3 - s2) * dur)))
	var vel := Orbit.scale(Orbit.add(Orbit.add(Orbit.scale(p0, 6.0 * s2 - 6.0 * s), Orbit.scale(v0, (3.0 * s2 - 4.0 * s + 1.0) * dur)),
		Orbit.add(Orbit.scale(p1, -6.0 * s2 + 6.0 * s), Orbit.scale(v1, (3.0 * s2 - 2.0 * s) * dur))), 1.0 / dur)
	var acc := Orbit.add(Orbit.add(Orbit.scale(p0, 12.0 * s - 6.0), Orbit.scale(v0, (6.0 * s - 4.0) * dur)),
		Orbit.add(Orbit.scale(p1, -12.0 * s + 6.0), Orbit.scale(v1, (6.0 * s - 2.0) * dur)))
	# The bow leads while speeding up and the stern leads while braking.
	var push := Orbit.dir(acc)
	if push != Vector3.ZERO:
		att = att.slerp(_basis_toward(push, Vector3.UP if absf(push.y) < 0.95 else Vector3.RIGHT), minf(dt * 0.5, 1.0)).orthonormalized()
	omega = Vector3.ZERO
	var mu_b: float = u.bodies[b].mu
	if mu_b > 0.0:
		soi = b
		st = Orbit.state(pos, vel)
	else:
		# A gate has no well: ride in its parent's frame beside it.
		var par: int = u.bodies[b].parent
		soi = par
		var gp := Orbit.sub(u.position(b, t), u.position(par, t))
		var gv := Orbit.sub(u.velocity(b, t), u.velocity(par, t))
		st = Orbit.state(Orbit.add(gp, pos), Orbit.add(gv, vel))
	sim.transit_heat(dt)
	if s >= 1.0:
		transit = {}
		c_att_mode = ATT_MODES.find("HOLD")
		_hold = att
		event.emit("arrived", "In orbit round %s" % u.bodies[b].name if mu_b > 0.0 else "Holding beside %s" % u.bodies[b].name)


## Cycle the target through every body and gate of the system.
func next_target(step: int) -> void:
	c_target = posmod(c_target + step, u.bodies.size())


## Arrive in a new system beside gate `gate` (the one leading back where we came from).
## Arrive in a system in a circular orbit round body b.
func arrive_at(p_u: Universe, b: int) -> void:
	u = p_u
	soi = b
	var r := transit_radius(b)
	var ang := randf() * TAU
	var mu_b: float = u.bodies[b].mu
	var v := sqrt(mu_b / r)
	st = PackedFloat64Array([r * cos(ang), 0.0, -r * sin(ang), -v * sin(ang), 0.0, -v * cos(ang)])
	c_target = b
	c_program = 0
	transit = {}
	omega = Vector3.ZERO
	_hold = att
	elements = Orbit.elements(st, mu())
	plan = {}


## Leave for another star: out of the system along the way to it, the torch flat out,
## turning half way to brake. `dir` is the star's direction (the galaxy and the system
## share their axes). Main swaps the system in when the crossing is done.
func start_interstellar(dest: int, dir: Vector3, dur: float, sim: ShipSim, fuel: float) -> void:
	transit = {"interstellar": true, "dest": dest, "dir": dir.normalized(), "t0": t, "dur": dur,
		"p0": world_pos(), "v0": world_vel()}
	sim.spend_dhe(fuel)
	event.emit("transit", "Leaving for the stars: %s" % game_duration(dur))


## How far out of the system the station is seen to go before the stars swallow it.
const INTERSTELLAR_SHOW := 1.5e14


func _interstellar_step(dt: float, sim: ShipSim) -> void:
	if not sim.torch_lit or sim.c_torch_thr < 0.5:
		abort_transit()
		return
	t += dt
	var dur: float = transit.dur
	var s := clampf((t - float(transit.t0)) / dur, 0.0, 1.0)
	var dir: Vector3 = transit.dir
	# Out along the line to the star, faster and faster; past half way the station is
	# braking toward the new system, so the old one recedes ever slower.
	var x := INTERSTELLAR_SHOW * s * s * (3.0 - 2.0 * s)
	var xv := INTERSTELLAR_SHOW * 6.0 * s * (1.0 - s) / dur
	var p0: PackedFloat64Array = transit.p0
	soi = 0
	st = Orbit.state(Orbit.add(p0, Orbit.from_vec(dir * x)), Orbit.from_vec(dir * xv))
	var push := dir if s < 0.5 else -dir
	att = att.slerp(_basis_toward(push, Vector3.UP if absf(push.y) < 0.95 else Vector3.RIGHT), minf(dt * 0.3, 1.0)).orthonormalized()
	omega = Vector3.ZERO
	sim.transit_heat(dt)
	if s >= 1.0:
		var dest: int = transit.dest
		transit = {}
		event.emit("star", str(dest))


## Real seconds as the keeper's time: one second of play is one minute of their day.
const GAME_MINUTE := 60.0


static func game_duration(real_secs: float) -> String:
	if real_secs == INF or is_nan(real_secs):
		return "--"
	var m := roundi(real_secs * GAME_MINUTE / 60.0)
	var d := m / 1440
	var h := (m / 60) % 24
	if d > 0:
		return "%d d %d h" % [d, h]
	if h > 0:
		return "%d h %02d min" % [h, m % 60]
	return "%d min" % m


## "1 d 04 h 12 min" style.
static func duration(secs: float) -> String:
	if secs == INF or is_nan(secs):
		return "--"
	var s := int(secs)
	var d := s / 86400
	var h := (s / 3600) % 24
	var m := (s / 60) % 60
	if d > 0:
		return "%d d %02d h %02d min" % [d, h, m]
	if h > 0:
		return "%d h %02d min" % [h, m]
	return "%d min %02d s" % [m, s % 60]


func load_counter() -> void:
	dv_counter = absf(float(plan.get("dv", 0.0)))


# --- Save --------------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"t": t, "soi": soi, "st": Array(st), "att": [att.x, att.y, att.z], "omega": omega,
		"c_att_mode": c_att_mode, "c_target": c_target, "c_program": c_program, "dv_counter": dv_counter}


func from_dict(d: Dictionary) -> void:
	t = d.t
	soi = d.soi
	st = PackedFloat64Array(d.st)
	att = Basis(d.att[0], d.att[1], d.att[2])
	omega = d.omega
	c_att_mode = d.c_att_mode
	c_target = d.c_target
	c_program = d.c_program
	dv_counter = d.dv_counter
	_hold = att
