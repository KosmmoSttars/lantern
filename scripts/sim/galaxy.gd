class_name Galaxy
extends RefCounted
## The stars round the Sun, generated on demand: space is cut into cubes SECTOR light
## years on a side, and each cube's stars (how many, where, which ids) come from a hash
## of its coordinates, so the same stars are always in the same places and there is no
## end to them. What each star is comes from Universe.header(id).
##
## The nearest star to the Sun is always a pulsar. Its ticks are the clock the navigation
## computer needs to plot crossings longer than FREE_RANGE light years.

const SECTOR := 8.0
const LY := 9.4607e15
## How far the computer can plot without a pulsar timing fix (light years).
const FREE_RANGE := 10.0
const TIMING_TIME := 300.0

var solar_seed := 1
## The system the station is in (0 = Sol) and where it is (light years from the Sun).
var here := 0
var here_pos := Vector3.ZERO
var pulsar_fix := false
var timing := 0.0
var timing_on := false
## id -> [name, kind] of every system the station has been to.
var visited := {0: ["Sol", "sun"]}

var _pulsar_id := -1
var _pulsar_pos := Vector3.ZERO
## id -> {id, pos, name, kind}
var _known := {}


## The stars of one sector.
static func sector_stars(ix: int, iy: int, iz: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([ix, iy, iz, 4127])
	var n := rng.randi_range(1, 4)
	for k in n:
		var pos := (Vector3(ix, iy, iz) + Vector3(rng.randf(), rng.randf() * 0.5 + 0.25, rng.randf())) * SECTOR
		# The galaxy is a disk: stars thin out above and below the plane.
		pos.y = (pos.y - SECTOR * 0.5) * 0.35 + float(iy) * SECTOR * 0.35
		if pos.length() < 3.0:
			continue
		out.append({"id": absi(hash([ix, iy, iz, k, 977])) % 2000000000 + 1, "pos": pos})
	return out


## Every star within `radius` light years of `center` (Sol included), nearest first.
func stars_near(center: Vector3, radius: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if center.length() <= radius:
		out.append(_entry(0, Vector3.ZERO))
	var lo := ((center - Vector3.ONE * radius) / SECTOR).floor()
	var hi := ((center + Vector3.ONE * radius) / SECTOR).floor()
	for ix in range(int(lo.x), int(hi.x) + 1):
		for iy in range(maxi(int(lo.y), -2), mini(int(hi.y), 2) + 1):
			for iz in range(int(lo.z), int(hi.z) + 1):
				for st in sector_stars(ix, iy, iz):
					var pos: Vector3 = st.pos
					if pos.distance_to(center) <= radius:
						out.append(_entry(int(st.id), pos))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a.pos as Vector3).distance_to(center) < (b.pos as Vector3).distance_to(center))
	return out


func _entry(id: int, pos: Vector3) -> Dictionary:
	if _known.has(id):
		return _known[id]
	var e := {"id": id, "pos": pos}
	if id == 0:
		e.name = "Sol"
		e.kind = "sun"
	else:
		var h := Universe.header(id, pos.length(), "pulsar" if id == pulsar_id() else "")
		e.name = h.name
		e.kind = h.kind
	_known[id] = e
	return e


## The star nearest the Sun: always a pulsar.
func pulsar_id() -> int:
	if _pulsar_id < 0:
		var best := INF
		for r in [12.0, 24.0]:
			var lo := int(floor(-r / SECTOR))
			var hi := int(floor(r / SECTOR))
			for ix in range(lo, hi + 1):
				for iy in range(-2, 3):
					for iz in range(lo, hi + 1):
						for st in sector_stars(ix, iy, iz):
							var d: float = (st.pos as Vector3).length()
							if d < best:
								best = d
								_pulsar_id = st.id
								_pulsar_pos = st.pos
			if _pulsar_id > 0:
				break
	return _pulsar_id


func star(id: int) -> Dictionary:
	if id == 0:
		return _entry(0, Vector3.ZERO)
	if _known.has(id):
		return _known[id]
	if id == pulsar_id():
		return _entry(id, _pulsar_pos)
	return {}


func distance(id: int) -> float:
	var e := star(id)
	return here_pos.distance_to(e.pos) if not e.is_empty() else INF


## Real seconds a crossing of d light years takes: twenty minutes to the nearest stars,
## never more than forty.
static func travel_time(d_ly: float) -> float:
	return clampf(600.0 + 360.0 * sqrt(d_ly), 900.0, 2400.0)


## D-He3 a crossing burns (kg).
static func travel_fuel(d_ly: float) -> float:
	return 350.0 * d_ly


## Why the computer cannot plot a crossing to star id ("" when it can).
func plot_blocker(id: int) -> String:
	if id == here:
		return "YOU ARE HERE"
	var e := star(id)
	if e.is_empty():
		return "NO SUCH STAR"
	if distance(id) > FREE_RANGE and not pulsar_fix and id != pulsar_id():
		return "BEYOND %d LY: NEEDS A PULSAR TIMING FIX" % int(FREE_RANGE)
	return ""


## The system the station is in.
func current() -> Universe:
	return build(here)


func build(id: int) -> Universe:
	if id == 0:
		return Universe.solar(solar_seed)
	var e := star(id)
	return Universe.generate(id, (e.pos as Vector3).length(), "pulsar" if id == pulsar_id() else "")


## Arrive at star id: returns its system.
func arrive(id: int) -> Universe:
	var e := star(id)
	here = id
	here_pos = e.pos
	var u := build(id)
	if not visited.has(id):
		visited[id] = [u.system_name, u.kind]
	return u


## Pulsar timing run: needs the dish and the nav computer, and a pulsar in the sky.
func tick(dt: float, u: Universe, sim: ShipSim) -> void:
	if not timing_on:
		return
	if u.pulsar.is_empty():
		timing_on = false
		return
	if sim.powered("dish") and sim.powered("nav"):
		timing = minf(timing + dt / TIMING_TIME, 1.0)
		if timing >= 1.0:
			pulsar_fix = true
			timing_on = false


func start_timing(u: Universe) -> bool:
	if u.pulsar.is_empty() or pulsar_fix:
		return false
	timing_on = true
	return true


func to_dict() -> Dictionary:
	# Only the stars a save can name: the ones been to and the one here. The rest of the
	# catalogue comes back from the sectors' seeds (all of it was some 9 MB, written every
	# minute).
	var keep := {}
	for id: int in visited:
		if _known.has(id):
			keep[id] = _known[id]
	if _known.has(here):
		keep[here] = _known[here]
	return {"solar_seed": solar_seed, "here": here, "here_pos": here_pos, "pulsar_fix": pulsar_fix,
		"timing": timing, "timing_on": timing_on, "visited": visited, "known": keep}


func from_dict(d: Dictionary) -> void:
	solar_seed = int(d.get("solar_seed", 1))
	here = int(d.get("here", 0))
	here_pos = d.get("here_pos", Vector3.ZERO)
	pulsar_fix = bool(d.get("pulsar_fix", false))
	timing = float(d.get("timing", 0.0))
	timing_on = bool(d.get("timing_on", false))
	visited = d.get("visited", visited)
	_known = d.get("known", {})
