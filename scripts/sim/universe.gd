class_name Universe
extends RefCounted
## The bodies of the system Lantern is in, on rails: each body follows a circular orbit
## round its parent, so its position is a function of time. Body 0 is the primary at the
## origin. The Solar System is the real one; every star beyond it is generated from its id
## (see Galaxy), so there is no end to them and a system is the same on every visit.
## Every planet and moon has a sphere of influence, so any of them can be orbited.

const SUN_DIST := 1.433e12
const G_MSUN := 1.32712e20
const AU := 1.496e11
const C := 299792458.0

## Which system this is: 0 is the Solar System, every other id is generated from itself.
var system_id := 0
## Light years from the Sun.
var distance_ly := 0.0
var system_name := "Sol"
## What the primary is: "sun", "red dwarf", "pulsar", "black hole"...
var kind := "sun"
## Each body: {name, kind, parent, mu, radius, a, period, phase, inc, node, soi, look}.
var bodies: Array[Dictionary] = []
## Used only when nothing in the system shines: a fixed direction for the faint starlight.
var sun_dir := Vector3(0.83, 0.19, 0.52).normalized()
var sun_flux := 1.0
## Generated systems: the body that shines (-1: light comes from far away, or none), its
## luminosity in suns, and the planet a newcomer arrives at.
var star_index := -1
var luminosity := 0.0
var hub := 0
## A supply relay answers here.
var has_relay := true
## Sky: star field seed and a tint for the band of the galaxy.
var sky_seed := 0.0
var sky_tint := Color(0.16, 0.15, 0.19)
## Extra radiation everywhere in the system (mSv/h) and, for a pulsar, its beam.
var background_dose := 0.0
var pulsar := {}
## Black hole: Schwarzschild radius (m) and the disk.
var black_hole := {}
var description := ""


## The Solar System: the Sun, the planets on their real orbits (circular, at their real
## distances and tilts) and their larger moons.
static func solar(seed_value: int) -> Universe:
	var u := Universe.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	u.system_id = 0
	u.system_name = "Sol"
	u.kind = "sun"
	u.description = "the Solar System: home"
	u.sky_seed = 0.0
	u._add({"name": "Sun", "kind": "star", "star": "yellow star", "parent": -1, "mu": G_MSUN, "radius": 6.957e8,
		"look": "star", "color": Color(1.0, 0.95, 0.86), "lum": 1.0})
	u.star_index = 0
	u.luminosity = 1.0
	# name, a (m), mu, radius, inclination (deg), look, colour, extras
	var planets := [
		["Mercury", 5.791e10, 2.2032e13, 2.4397e6, 7.0, "rock", Color(0.55, 0.52, 0.5), {}],
		["Venus", 1.0821e11, 3.24859e14, 6.0518e6, 3.39, "titan", Color(0.93, 0.86, 0.66), {"alt": Color(0.86, 0.78, 0.55)}],
		["Earth", 1.496e11, 3.986e14, 6.371e6, 0.0, "ocean", Color(0.12, 0.3, 0.62), {}],
		["Mars", 2.2794e11, 4.2828e13, 3.3895e6, 1.85, "rock", Color(0.74, 0.38, 0.22), {}],
		["Jupiter", 7.7857e11, 1.26687e17, 6.9911e7, 1.3, "giant", Color(0.86, 0.76, 0.62), {"alt": Color(0.72, 0.5, 0.34)}],
		["Saturn", 1.43353e12, 3.7931187e16, 5.8232e7, 2.49, "saturn", Color(0.86, 0.76, 0.56), {"rings": [74.5e6, 140.2e6]}],
		["Uranus", 2.87246e12, 5.794e15, 2.5362e7, 0.77, "giant", Color(0.68, 0.86, 0.88), {"alt": Color(0.62, 0.8, 0.84), "rings": [3.8e7, 5.1e7]}],
		["Neptune", 4.49506e12, 6.8365e15, 2.4622e7, 1.77, "giant", Color(0.3, 0.46, 0.85), {"alt": Color(0.24, 0.36, 0.72)}],
		["Pluto", 5.90638e12, 8.696e11, 1.1883e6, 17.2, "ice", Color(0.8, 0.72, 0.62), {}],
	]
	for pl: Array in planets:
		var d := {"name": pl[0], "kind": "planet", "parent": 0, "mu": pl[2], "radius": pl[3], "a": pl[1],
			"phase": rng.randf() * TAU, "inc": deg_to_rad(pl[4]), "node": rng.randf() * TAU, "look": pl[5], "color": pl[6],
			"atmo": pl[5] in ["giant", "saturn", "titan", "ocean"]}
		d.merge(pl[7])
		u._add(d)
	# parent, name, a (m), mu, radius, inclination (deg), look, colour
	var moons := [
		["Earth", "Moon", 3.844e8, 4.9028e12, 1.7374e6, 5.1, "rock", Color(0.6, 0.6, 0.58)],
		["Mars", "Phobos", 9.376e6, 7.087e5, 11.1e3, 1.1, "rock", Color(0.45, 0.4, 0.36)],
		["Mars", "Deimos", 2.3463e7, 9.6e4, 6.2e3, 1.8, "rock", Color(0.5, 0.45, 0.4)],
		["Jupiter", "Io", 4.217e8, 5.959e12, 1.8216e6, 0.05, "lava", Color(0.85, 0.75, 0.3)],
		["Jupiter", "Europa", 6.709e8, 3.2027e12, 1.5608e6, 0.47, "ice", Color(0.88, 0.84, 0.76)],
		["Jupiter", "Ganymede", 1.0704e9, 9.887e12, 2.6341e6, 0.2, "rock", Color(0.6, 0.57, 0.52)],
		["Jupiter", "Callisto", 1.8827e9, 7.179e12, 2.4103e6, 0.19, "rock", Color(0.42, 0.38, 0.34)],
		["Saturn", "Mimas", 185.54e6, 2.503e9, 198e3, 1.57, "ice", Color(0.8, 0.8, 0.8)],
		["Saturn", "Enceladus", 238.04e6, 7.211e9, 252e3, 0.02, "snow", Color(0.97, 0.97, 0.98)],
		["Saturn", "Tethys", 294.67e6, 41.21e9, 531e3, 1.12, "ice", Color(0.85, 0.85, 0.84)],
		["Saturn", "Dione", 377.42e6, 73.11e9, 561e3, 0.02, "ice", Color(0.8, 0.8, 0.79)],
		["Saturn", "Rhea", 527.07e6, 153.94e9, 764e3, 0.35, "ice", Color(0.8, 0.79, 0.77)],
		["Saturn", "Titan", 1221.87e6, 8978.1e9, 2575e3, 0.33, "titan", Color(0.86, 0.6, 0.28)],
		["Saturn", "Iapetus", 3560.8e6, 120.5e9, 735e3, 15.47, "iapetus", Color(0.85, 0.83, 0.8)],
		["Uranus", "Miranda", 1.299e8, 4.4e9, 2.358e5, 4.2, "ice", Color(0.7, 0.7, 0.72)],
		["Uranus", "Ariel", 1.909e8, 8.3e10, 5.789e5, 0.3, "ice", Color(0.75, 0.75, 0.76)],
		["Uranus", "Umbriel", 2.66e8, 8.5e10, 5.847e5, 0.13, "rock", Color(0.4, 0.4, 0.42)],
		["Uranus", "Titania", 4.363e8, 2.26e11, 7.884e5, 0.08, "ice", Color(0.68, 0.66, 0.66)],
		["Uranus", "Oberon", 5.835e8, 2.05e11, 7.614e5, 0.07, "rock", Color(0.6, 0.56, 0.54)],
		["Neptune", "Triton", 3.548e8, 1.428e12, 1.3534e6, 156.9, "ice", Color(0.85, 0.8, 0.78)],
		["Pluto", "Charon", 1.9591e7, 1.058e11, 6.06e5, 0.0, "ice", Color(0.62, 0.6, 0.58)],
	]
	for m: Array in moons:
		u._add({"name": m[1], "kind": "moon", "parent": u.find(m[0]), "mu": m[3], "radius": m[4], "a": m[2],
			"phase": rng.randf() * TAU, "inc": deg_to_rad(m[5]), "node": rng.randf() * TAU, "look": m[6], "color": m[7],
			"alt": Color(0.12, 0.09, 0.07) if m[1] == "Iapetus" else Color(0.72, 0.48, 0.22)})
	u.hub = u.find("Saturn")
	_derelicts(u, ["Saturn", "Titan", "Rhea", "Mars", "Moon"].map(func(n: String) -> int: return u.find(n)))
	_modules(u, [[u.find("Enceladus"), "GREENHOUSE"], [u.find("Europa"), "OBSERVATORY"], [u.find("Phobos"), "POWER MODULE"]])
	return u


## Abandoned modules left in orbit: no well of their own, they ride round a planet or moon
## a few radii up, each with whatever its crew left behind (Salvage.loot). Appended after
## everything else, from their own seed, so the system's bodies keep their indices.
const DERELICT_NAMES := ["KESTREL", "MARTA", "ILYA", "OKEANOS", "VESTA", "TERN", "ORLA", "PETREL", "HALCYON", "NADIR", "ARGO", "SOYA", "BERGEN", "LUMEN"]
const DERELICT_CLASSES := ["CARGO MODULE", "FUEL DEPOT", "SURVEY TENDER", "HAB MODULE", "RELAY POD"]


static func _derelicts(u: Universe, parents: Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([u.system_id, 5521])
	for parent: int in parents:
		if parent < 0:
			continue
		var pb := u.bodies[parent]
		var r: float = pb.radius
		var a := r * rng.randf_range(2.2, 4.0)
		if float(pb.soi) > 0.0:
			a = minf(a, float(pb.soi) * 0.4)
		u._add({"name": "%s-%d" % [DERELICT_NAMES[rng.randi() % DERELICT_NAMES.size()], rng.randi_range(2, 19)],
			"kind": "derelict", "class": DERELICT_CLASSES[rng.randi() % DERELICT_CLASSES.size()],
			"parent": parent, "mu": 0.0, "radius": 6.0, "a": a, "phase": rng.randf() * TAU,
			"inc": deg_to_rad(rng.randf_range(0.0, 8.0)), "node": rng.randf() * TAU, "look": "derelict",
			"color": Color(0.7, 0.7, 0.7), "loot_seed": rng.randi()})


## Whole modules, still sealed and sound, waiting in orbit for a station to take them on: dock
## one at the docking port and it is part of Lantern for good. After the derelicts, their own seed.
const MODULE_KINDS := ["GREENHOUSE", "POWER MODULE", "OBSERVATORY"]
const MODULE_NAMES := ["AURORA", "CEDAR", "HELIOS", "LYRA", "MERIDIAN", "SOLACE", "ZARYA", "HARBOUR", "LINDEN", "VEGA"]


## [[parent body, kind], ...]
static func _modules(u: Universe, hosts: Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([u.system_id, 9133])
	for h: Array in hosts:
		var parent: int = h[0]
		if parent < 0:
			continue
		var pb := u.bodies[parent]
		var a := float(pb.radius) * rng.randf_range(2.4, 3.6)
		if float(pb.soi) > 0.0:
			a = minf(a, float(pb.soi) * 0.4)
		u._add({"name": "%s-%d" % [MODULE_NAMES[rng.randi() % MODULE_NAMES.size()], rng.randi_range(1, 9)],
			"kind": "module", "class": String(h[1]),
			"parent": parent, "mu": 0.0, "radius": 6.0, "a": a, "phase": rng.randf() * TAU,
			"inc": deg_to_rad(rng.randf_range(0.0, 6.0)), "node": rng.randf() * TAU, "look": "module",
			"color": Color(0.8, 0.8, 0.8), "loot_seed": rng.randi()})


const SYLLABLES := ["ka", "ve", "ro", "sin", "tal", "mir", "o", "an", "du", "rek", "si", "lo", "ther", "va", "nu", "ix", "el", "or", "ba", "quel", "ty", "zo", "ar", "em"]
const KINDS := [
	["red dwarf", 26], ["yellow star", 12], ["white dwarf", 10], ["brown dwarf", 10],
	["pulsar", 9], ["black hole", 9], ["rogue planet", 10], ["blue giant", 6], ["orange star", 8],
]
const ROMAN := ["I", "II", "III", "IV", "V", "VI"]


static func make_name(rng: RandomNumberGenerator) -> String:
	var n := ""
	for i in rng.randi_range(2, 3):
		n += SYLLABLES[rng.randi() % SYLLABLES.size()]
	return n.capitalize()


## What a star is called and what it is, without building its system (for the star map).
## Draws exactly what generate() draws first, so the two always agree.
static func header(id: int, dist_ly: float, force_kind := "") -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = id
	return _header(rng, dist_ly, force_kind)


static func _header(rng: RandomNumberGenerator, dist_ly: float, force_kind: String) -> Dictionary:
	var tint := Color.from_hsv(rng.randf(), rng.randf_range(0.2, 0.55), rng.randf_range(0.1, 0.2))
	var star_name := make_name(rng)
	var kind: String = force_kind
	# Black holes grow commoner the further from home.
	var bh_extra := int(dist_ly / 6.0)
	var total := 0
	for k: Array in KINDS:
		total += int(k[1]) + (bh_extra if k[0] == "black hole" else 0)
	var roll := rng.randi() % total
	for k: Array in KINDS:
		roll -= int(k[1]) + (bh_extra if k[0] == "black hole" else 0)
		if roll < 0:
			if kind == "":
				kind = k[0]
			break
	return {"name": star_name, "kind": kind, "tint": tint}


## A star system nobody has seen: what shines in it and its planets, each with moons and
## some with rings. The station arrives at the "hub" planet.
static func generate(id: int, dist_ly: float, force_kind := "") -> Universe:
	var u := Universe.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = id
	u.system_id = id
	u.distance_ly = dist_ly
	u.sky_seed = float(id % 997) * 0.731
	var h := _header(rng, dist_ly, force_kind)
	u.sky_tint = h.tint
	u.system_name = h.name
	u.kind = h.kind
	u.has_relay = rng.randf() < maxf(0.7 - dist_ly * 0.02, 0.1) and u.kind != "black hole"
	if u.kind == "rogue planet":
		# No star: a lone giant and its moons, lit only by the stars.
		u.star_index = -1
		u.sun_flux = 0.0
		u.description = "a rogue planet: no star, only the dark between"
		var giant := _planet(rng, u.system_name, -1, 0.0, "giant")
		u._add(giant)
		u.hub = 0
		_moons(u, rng, 0, rng.randi_range(2, 5))
	else:
		var star := _star(rng, u.kind, u.system_name)
		u._add(star)
		u.star_index = 0
		u.luminosity = star.lum
		u.description = star.blurb
		var mu_star: float = star.mu
		var hub_r: float
		match u.kind:
			"black hole":
				var rs: float = star.radius
				u.black_hole = {"rs": rs, "disk_in": 3.0, "disk_out": rng.randf_range(10.0, 16.0),
					"disk_n": Vector3(rng.randf_range(-0.4, 0.4), 1.0, rng.randf_range(-0.4, 0.4)).normalized()}
				hub_r = AU * rng.randf_range(4.0, 12.0)
				u.background_dose = 0.08
			"pulsar":
				hub_r = AU * rng.randf_range(0.6, 1.6)
				u.background_dose = 0.06
				u.pulsar = {"period": rng.randf_range(0.7, 2.4), "angle": deg_to_rad(rng.randf_range(4.0, 7.0)), "spike": rng.randf_range(2.0, 5.0)}
			_:
				# Cold places: the hub gets a few hundredths of Earth's sunlight at most.
				var f := rng.randf_range(0.004, 0.06)
				hub_r = AU * clampf(sqrt(u.luminosity / f), 0.05, 40.0)
				if u.kind == "blue giant":
					u.background_dose = 0.04
		# Planets on orbits spaced out from the hub's, inward and outward.
		var n_in := rng.randi_range(0, 3)
		var n_out := rng.randi_range(1, 4)
		var radii: Array[float] = []
		var a := hub_r
		for k in n_in:
			a /= rng.randf_range(1.5, 2.2)
			if a < float(star.radius) * 20.0 + AU * 0.02:
				break
			radii.append(a)
		radii.reverse()
		var hub_slot := radii.size()
		radii.append(hub_r)
		a = hub_r
		for k in n_out:
			a *= rng.randf_range(1.5, 2.2)
			radii.append(a)
		var letters := "bcdefghij"
		for k in radii.size():
			var near_star := radii[k] < hub_r * 0.5
			var types := ["rock", "lava", "rock", "ocean"] if near_star else ["giant", "giant", "ice giant", "rock", "frozen", "ocean"]
			var type: String = types[rng.randi() % types.size()]
			if k == hub_slot and u.kind in ["black hole", "pulsar"]:
				type = "giant"
			var pl := _planet(rng, "%s %s" % [u.system_name, letters[k]], 0, radii[k], type)
			u._add(pl)
			var idx := u.bodies.size() - 1
			if k == hub_slot:
				u.hub = idx
			var max_moons := 4 if type in ["giant", "ice giant"] else 2
			_moons(u, rng, idx, rng.randi_range(0 if k != hub_slot else 1, max_moons))
	# One or two derelicts, round the hub and maybe round something else.
	var drng := RandomNumberGenerator.new()
	drng.seed = hash([id, 77])
	var hosts: Array = [u.hub]
	if drng.randf() < 0.6 and u.bodies.size() > 2:
		var other := drng.randi_range(1, u.bodies.size() - 1)
		if other != u.hub and String(u.bodies[other].kind) in ["planet", "moon"]:
			hosts.append(other)
	_derelicts(u, hosts)
	# Now and then a whole module, round one of the planets or moons.
	if drng.randf() < 0.35:
		var at := drng.randi_range(1, u.bodies.size() - 1)
		if String(u.bodies[at].kind) in ["planet", "moon"]:
			_modules(u, [[at, MODULE_KINDS[drng.randi() % MODULE_KINDS.size()]]])
	return u


## Moons for body `parent`, spaced out within its sphere of influence.
static func _moons(u: Universe, rng: RandomNumberGenerator, parent: int, n: int) -> void:
	var p := u.bodies[parent]
	var lim: float = minf(float(p.soi) * 0.35, float(p.radius) * 90.0)
	var a_m: float = float(p.radius) * rng.randf_range(2.5, 4.0)
	for k in n:
		a_m *= rng.randf_range(1.5, 2.4)
		if a_m > lim:
			break
		var m_r := rng.randf_range(150e3, 2600e3) * (0.4 if float(p.radius) < 1.2e7 else 1.0)
		var dens := rng.randf_range(1500.0, 3500.0)
		var m_mu := 6.674e-11 * dens * 4.18879 * pow(m_r, 3.0)
		var look: String = ["ice", "rock", "rock", "lava", "ice", "titan"][rng.randi() % 6]
		u._add({"name": "%s %s" % [p.name, ROMAN[k]], "kind": "moon", "parent": parent, "mu": m_mu, "radius": m_r, "a": a_m,
			"phase": rng.randf() * TAU, "inc": deg_to_rad(rng.randf_range(0.0, 8.0)), "node": rng.randf() * TAU,
			"look": look, "color": _rock_color(rng) if look != "ice" else Color(0.85, 0.87, 0.9)})


static func _star(rng: RandomNumberGenerator, kind: String, sys_name: String) -> Dictionary:
	var m := 1.0
	var r := 1.0
	var lum := 1.0
	var col := Color(1.0, 0.95, 0.85)
	var blurb := ""
	match kind:
		"red dwarf":
			m = rng.randf_range(0.1, 0.5)
			r = m * 0.9
			lum = pow(m, 3.5) * 0.6
			col = Color(1.0, 0.42, 0.2)
			blurb = "a red dwarf, dim and patient"
		"orange star":
			m = rng.randf_range(0.6, 0.85)
			r = m
			lum = pow(m, 4.0)
			col = Color(1.0, 0.72, 0.42)
			blurb = "an orange star"
		"yellow star":
			m = rng.randf_range(0.9, 1.2)
			r = m
			lum = pow(m, 4.0)
			col = Color(1.0, 0.95, 0.82)
			blurb = "a yellow star like the Sun"
		"blue giant":
			m = rng.randf_range(8.0, 20.0)
			r = m * 0.8
			lum = pow(m, 3.2)
			col = Color(0.62, 0.74, 1.0)
			blurb = "a blue giant, burning fast"
		"white dwarf":
			m = rng.randf_range(0.5, 1.1)
			r = 0.012
			lum = rng.randf_range(0.001, 0.02)
			col = Color(0.85, 0.9, 1.0)
			blurb = "a white dwarf, the cooling ember of a star"
		"brown dwarf":
			m = rng.randf_range(0.02, 0.07)
			r = 0.1
			lum = rng.randf_range(1e-5, 1e-4)
			col = Color(0.75, 0.25, 0.12)
			blurb = "a brown dwarf, too small to shine"
		"pulsar":
			m = rng.randf_range(1.3, 2.0)
			r = 12e3 / 6.957e8
			lum = 0.0005
			col = Color(0.7, 0.82, 1.0)
			blurb = "a pulsar: a spinning neutron star sweeping the sky with its beams"
		"black hole":
			m = rng.randf_range(8.0, 25.0)
			r = 0.0
			lum = rng.randf_range(2.0, 8.0)
			col = Color(1.0, 0.7, 0.4)
			blurb = "a black hole: a singularity in a burning disk"
	var radius := r * 6.957e8
	if kind == "black hole":
		radius = 2.0 * m * G_MSUN / (C * C)
	var looks := {"brown dwarf": "brown dwarf", "pulsar": "pulsar", "black hole": "black hole"}
	return {"name": sys_name, "kind": "star", "star": kind, "parent": -1, "mu": m * G_MSUN, "radius": radius,
		"look": looks.get(kind, "star"), "color": col, "lum": lum, "blurb": blurb}


static func _rock_color(rng: RandomNumberGenerator) -> Color:
	return Color.from_hsv(rng.randf_range(0.02, 0.14), rng.randf_range(0.05, 0.4), rng.randf_range(0.35, 0.8))


## A planet of a type orbiting body `parent` at distance a.
static func _planet(rng: RandomNumberGenerator, p_name: String, parent: int, a: float, type: String) -> Dictionary:
	var d := {"name": p_name, "kind": "planet", "parent": parent, "a": a, "phase": rng.randf() * TAU,
		"inc": deg_to_rad(rng.randf_range(0.0, 6.0)), "node": rng.randf() * TAU, "type": type}
	match type:
		"giant":
			d.mu = rng.randf_range(2e16, 1.6e17)
			d.radius = rng.randf_range(4.5e7, 7.5e7)
			d.look = "giant"
			var col := Color.from_hsv(rng.randf_range(0.0, 0.16), rng.randf_range(0.2, 0.55), rng.randf_range(0.6, 0.9))
			d.color = col
			d.alt = Color.from_hsv(fposmod(col.h + rng.randf_range(-0.08, 0.08), 1.0), rng.randf_range(0.3, 0.7), rng.randf_range(0.4, 0.7))
			if rng.randf() < 0.4:
				var ri: float = float(d.radius) * rng.randf_range(1.3, 1.8)
				d.rings = [ri, ri * rng.randf_range(1.5, 2.3)]
		"ice giant":
			d.mu = rng.randf_range(4e15, 9e15)
			d.radius = rng.randf_range(2.3e7, 2.6e7)
			d.look = "giant"
			var col2 := Color.from_hsv(rng.randf_range(0.48, 0.62), rng.randf_range(0.25, 0.5), rng.randf_range(0.6, 0.85))
			d.color = col2
			d.alt = col2.darkened(0.15)
			if rng.randf() < 0.3:
				var ri2: float = float(d.radius) * rng.randf_range(1.5, 2.0)
				d.rings = [ri2, ri2 * rng.randf_range(1.2, 1.6)]
		"ocean":
			d.mu = rng.randf_range(3e14, 2e15)
			d.radius = rng.randf_range(6e6, 1.1e7)
			d.look = "ocean"
			d.color = Color.from_hsv(rng.randf_range(0.5, 0.62), 0.6, 0.5)
		"lava":
			d.mu = rng.randf_range(2e14, 1.5e15)
			d.radius = rng.randf_range(4e6, 9e6)
			d.look = "lava"
			d.color = Color(0.12, 0.1, 0.09)
		"frozen":
			d.mu = rng.randf_range(1e14, 1e15)
			d.radius = rng.randf_range(3e6, 8e6)
			d.look = "ice"
			d.color = Color.from_hsv(rng.randf_range(0.5, 0.6), rng.randf_range(0.0, 0.15), rng.randf_range(0.75, 0.95))
		_:
			d.mu = rng.randf_range(1e14, 2e15)
			d.radius = rng.randf_range(3e6, 1e7)
			d.look = "rock"
			d.color = _rock_color(rng)
	d.atmo = type in ["giant", "ice giant", "ocean"]
	return d


func _add(b: Dictionary) -> void:
	var p: int = b.get("parent", -1)
	if p >= 0:
		var pm: float = bodies[p].mu
		b["period"] = TAU * sqrt(pow(b.a, 3.0) / pm)
		# Never smaller than a few radii, so every body can be orbited.
		b["soi"] = maxf(b.a * pow(maxf(b.mu, 1.0) / pm, 0.4), float(b.radius) * 15.0) if b.mu > 0.0 else 0.0
	else:
		b["soi"] = INF
	bodies.append(b)


func find(n: String) -> int:
	for i in bodies.size():
		if bodies[i].name == n:
			return i
	return -1


## Position of body i in the system frame at time t (the primary at the origin).
func position(i: int, t: float) -> PackedFloat64Array:
	var b := bodies[i]
	if b.parent < 0:
		return Orbit.v3(0, 0, 0)
	var th: float = b.phase + TAU * t / b.period
	var local := Vector3(cos(th), 0.0, -sin(th))
	var p := _tilt(b, local)
	var r := Orbit.v3(p.x * b.a, p.y * b.a, p.z * b.a)
	return Orbit.add(position(b.parent, t), r)


func velocity(i: int, t: float) -> PackedFloat64Array:
	var b := bodies[i]
	if b.parent < 0:
		return Orbit.v3(0, 0, 0)
	var th: float = b.phase + TAU * t / b.period
	var w: float = TAU / b.period
	var local := Vector3(-sin(th), 0.0, -cos(th))
	var v := _tilt(b, local)
	var s: float = b.a * w
	return Orbit.add(velocity(b.parent, t), Orbit.v3(v.x * s, v.y * s, v.z * s))


func _tilt(b: Dictionary, v: Vector3) -> Vector3:
	var node_axis := Vector3(cos(b.node), 0.0, -sin(b.node))
	return v.rotated(node_axis, b.inc) if b.inc != 0.0 else v


## Bodies whose sphere of influence sits inside body i's.
func children(i: int) -> Array[int]:
	var out: Array[int] = []
	for k in bodies.size():
		if bodies[k].parent == i and bodies[k].mu > 0.0:
			out.append(k)
	return out


## Direction (system frame) from a point to the light, and how strong the light is there
## relative to sunlight at Saturn.
func light_at(p: PackedFloat64Array, t: float) -> Array:
	if star_index < 0:
		return [sun_dir, sun_flux]
	var d := Orbit.sub(position(star_index, t), p)
	var dist := Orbit.length(d) / AU
	var flux := luminosity / maxf(dist * dist, 1e-6) / 0.011
	return [Orbit.dir(d), clampf(flux, 0.0, 30.0)]


## The chain of parents of body i, nearest first (i itself included).
func lineage(i: int) -> Array[int]:
	var out: Array[int] = []
	while i >= 0:
		out.append(i)
		i = bodies[i].parent
	return out
