class_name Orbit
extends RefCounted
## Two-body orbital mechanics in double precision. Godot's Vector3 is single precision,
## too coarse for positions a billion metres out, so states are PackedFloat64Array
## [x, y, z, vx, vy, vz] and vectors [x, y, z].
##
## Frame: the system's inertial frame, the ring plane is XZ, +Y is north.


static func v3(x: float, y: float, z: float) -> PackedFloat64Array:
	return PackedFloat64Array([x, y, z])


static func state(r: PackedFloat64Array, v: PackedFloat64Array) -> PackedFloat64Array:
	return PackedFloat64Array([r[0], r[1], r[2], v[0], v[1], v[2]])


static func pos(st: PackedFloat64Array) -> PackedFloat64Array:
	return PackedFloat64Array([st[0], st[1], st[2]])


static func vel(st: PackedFloat64Array) -> PackedFloat64Array:
	return PackedFloat64Array([st[3], st[4], st[5]])


static func add(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	var r := PackedFloat64Array()
	r.resize(a.size())
	for i in a.size():
		r[i] = a[i] + b[i]
	return r


static func sub(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	var r := PackedFloat64Array()
	r.resize(a.size())
	for i in a.size():
		r[i] = a[i] - b[i]
	return r


static func scale(a: PackedFloat64Array, k: float) -> PackedFloat64Array:
	var r := PackedFloat64Array()
	r.resize(a.size())
	for i in a.size():
		r[i] = a[i] * k
	return r


static func dot(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


static func cross(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	return v3(a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


static func length(a: PackedFloat64Array) -> float:
	return sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2])


## Direction as a (single precision) Vector3.
static func dir(a: PackedFloat64Array) -> Vector3:
	var l := length(a)
	if l <= 0.0:
		return Vector3.ZERO
	return Vector3(a[0] / l, a[1] / l, a[2] / l)


static func to_vec(a: PackedFloat64Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


static func from_vec(v: Vector3) -> PackedFloat64Array:
	return v3(v.x, v.y, v.z)


# --- Kepler propagation (universal variables) ---------------------------------------------

static func _c(z: float) -> float:
	if z > 1e-6:
		var s := sqrt(z)
		return (1.0 - cos(s)) / z
	if z < -1e-6:
		var s := sqrt(-z)
		return (cosh(s) - 1.0) / (-z)
	return 0.5 - z / 24.0


static func _s(z: float) -> float:
	if z > 1e-6:
		var s := sqrt(z)
		return (s - sin(s)) / (s * s * s)
	if z < -1e-6:
		var s := sqrt(-z)
		return (sinh(s) - s) / (s * s * s)
	return 1.0 / 6.0 - z / 120.0


## The state after `dt` seconds of coasting under a point mass `mu`.
static func propagate(st: PackedFloat64Array, mu: float, dt: float) -> PackedFloat64Array:
	if dt == 0.0:
		return st.duplicate()
	var r0 := pos(st)
	var v0 := vel(st)
	var r0n := length(r0)
	var v0n2 := dot(v0, v0)
	var vr0 := dot(r0, v0) / r0n
	var alpha := 2.0 / r0n - v0n2 / mu
	var smu := sqrt(mu)
	# Whole revolutions of a closed orbit drop out.
	if alpha > 1e-15:
		var period := TAU / sqrt(mu * alpha * alpha * alpha)
		if absf(dt) > period:
			dt = fmod(dt, period)
	var chi := smu * absf(alpha) * dt if alpha > 1e-15 else smu * dt / r0n
	for i in 60:
		var z := alpha * chi * chi
		var c := _c(z)
		var s := _s(z)
		var f := r0n * vr0 / smu * chi * chi * c + (1.0 - alpha * r0n) * chi * chi * chi * s + r0n * chi - smu * dt
		var df := r0n * vr0 / smu * chi * (1.0 - alpha * chi * chi * s) + (1.0 - alpha * r0n) * chi * chi * c + r0n
		var step := f / df
		chi -= step
		if absf(step) < 1e-9 * maxf(absf(chi), 1.0):
			break
	var z2 := alpha * chi * chi
	var c2 := _c(z2)
	var s2 := _s(z2)
	var fl := 1.0 - chi * chi / r0n * c2
	var gl := dt - chi * chi * chi / smu * s2
	var r := add(scale(r0, fl), scale(v0, gl))
	var rn := length(r)
	var fdot := smu / (rn * r0n) * (alpha * chi * chi * chi * s2 - chi)
	var gdot := 1.0 - chi * chi / rn * c2
	var v := add(scale(r0, fdot), scale(v0, gdot))
	return state(r, v)


## Numerical step under a point mass plus a constant acceleration (thrust), RK4.
static func integrate(st: PackedFloat64Array, mu: float, acc: PackedFloat64Array, dt: float) -> PackedFloat64Array:
	var k1 := _deriv(st, mu, acc)
	var k2 := _deriv(add(st, scale(k1, dt * 0.5)), mu, acc)
	var k3 := _deriv(add(st, scale(k2, dt * 0.5)), mu, acc)
	var k4 := _deriv(add(st, scale(k3, dt)), mu, acc)
	var out := st.duplicate()
	for i in 6:
		out[i] += dt / 6.0 * (k1[i] + 2.0 * k2[i] + 2.0 * k3[i] + k4[i])
	return out


static func _deriv(st: PackedFloat64Array, mu: float, acc: PackedFloat64Array) -> PackedFloat64Array:
	var rn := sqrt(st[0] * st[0] + st[1] * st[1] + st[2] * st[2])
	var k := -mu / (rn * rn * rn)
	return PackedFloat64Array([st[3], st[4], st[5], st[0] * k + acc[0], st[1] * k + acc[1], st[2] * k + acc[2]])


# --- Elements ----------------------------------------------------------------------------------

## Shape of the orbit: semi-major axis, eccentricity, inclination, periapsis and apoapsis
## radii, period, true anomaly, time to periapsis and to apoapsis (INF when open).
static func elements(st: PackedFloat64Array, mu: float) -> Dictionary:
	var r := pos(st)
	var v := vel(st)
	var rn := length(r)
	var vn2 := dot(v, v)
	var h := cross(r, v)
	var hn := length(h)
	var energy := vn2 * 0.5 - mu / rn
	var a := -mu / (2.0 * energy) if absf(energy) > 1e-12 else INF
	var ev := sub(scale(r, vn2 / mu - 1.0 / rn), scale(v, dot(r, v) / mu))
	var e := length(ev)
	var inc := acos(clampf(h[1] / maxf(hn, 1e-9), -1.0, 1.0))
	var pe := a * (1.0 - e) if e < 1.0 else hn * hn / mu / (1.0 + e)
	var ap := a * (1.0 + e) if e < 1.0 else INF
	var nu := 0.0
	if e > 1e-9:
		nu = acos(clampf(dot(ev, r) / (e * rn), -1.0, 1.0))
		if dot(r, v) < 0.0:
			nu = TAU - nu
	var d := {"a": a, "e": e, "inc": inc, "pe": pe, "ap": ap, "nu": nu, "h": hn, "energy": energy}
	if e < 1.0 and a > 0.0:
		var n := sqrt(mu / (a * a * a))
		var period := TAU / n
		var ea := 2.0 * atan(sqrt((1.0 - e) / (1.0 + e)) * tan(nu * 0.5))
		var m := ea - e * sin(ea)
		m = fposmod(m, TAU)
		d["period"] = period
		d["t_pe"] = fposmod(TAU - m, TAU) / n
		d["t_ap"] = fposmod(PI - m, TAU) / n
	else:
		d["period"] = INF
		d["t_pe"] = INF if dot(r, v) > 0.0 else _hyper_t_pe(r, v, mu, e, nu)
		d["t_ap"] = INF
	return d


static func _hyper_t_pe(_r: PackedFloat64Array, _v: PackedFloat64Array, mu: float, e: float, nu: float) -> float:
	# Time from the current true anomaly (negative side) to periapsis on a hyperbola.
	var hh := 2.0 * atanh(sqrt((e - 1.0) / (e + 1.0)) * tan(nu * 0.5)) if e > 1.0 else 0.0
	var mh := e * sinh(hh) - hh
	var a := absf(_a_from(_r, _v, mu))
	return absf(mh) / sqrt(mu / (a * a * a))


static func _a_from(r: PackedFloat64Array, v: PackedFloat64Array, mu: float) -> float:
	var energy := dot(v, v) * 0.5 - mu / length(r)
	return -mu / (2.0 * energy)


## Circular orbit speed at radius r.
static func circular(mu: float, r: float) -> float:
	return sqrt(mu / r)
