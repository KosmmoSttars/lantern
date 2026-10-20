class_name Events
extends RefCounted
## What happens to the station while the keeper lives aboard: every few minutes something.
##   micrometeoroid  a hole in a module's wall, sometimes a part outside broken too
##   flare           a star throws a storm of protons: a minute's warning, then a few minutes
##                   of heavy dose everywhere but the shelter (Life support, behind the water)
##   failure         a breaker on something that matters trips
## and from the reactor module, the more often the more worn its pumps are:
##   coolant_leak    a seal lets go and the primary loop drains (patch it, top it up)
##   pump_trip       the coolant pumps' breaker trips: the core heats with no flow
##   scram           the protection system drops the rods on a false signal
##   shield_crack    the biological shield cracks: the reactor room grows hot
## Main turns these into holes, sounds and messages.

signal happened(kind: String, data: Dictionary)

const FIRST := 300.0
const GAP_MIN := 240.0
const GAP_MAX := 480.0
const FLARE_WARNING := 60.0
const FLARE_TIME := 150.0
## Dose rate of a flare (mSv/h, before the body's scaling) and how much the shelter keeps out.
const FLARE_DOSE := 600.0
const SHELTER_FACTOR := 0.1
const SHELTER := "Life support"

var next_t := FIRST
## Flare: seconds to its arrival (>0 = warning), or seconds into it (<0), or INF when none.
var flare := INF
var rng := RandomNumberGenerator.new()


func _init() -> void:
	rng.randomize()


func tick(dt: float, u: Universe, sim: ShipSim) -> void:
	if flare != INF:
		if flare > 0.0:
			flare -= dt
			if flare <= 0.0:
				flare = -0.001
				happened.emit("flare_start", {})
		else:
			flare -= dt
			if -flare > FLARE_TIME:
				flare = INF
				happened.emit("flare_end", {})
	next_t -= dt
	if next_t > 0.0:
		return
	next_t = rng.randf_range(GAP_MIN, GAP_MAX)
	var options := [["micrometeoroid", 5.0], ["failure", 3.0]]
	if not sim.rx_jettisoned:
		var w := sim.rx_pump_wear
		if sim.rx_leak <= 0.0:
			options.append(["coolant_leak", 0.8 + 3.0 * w])
		if sim.brk["rxpump"]:
			options.append(["pump_trip", 0.5 + 2.5 * w])
		if not sim.rx_scrammed:
			options.append(["scram", 0.8])
		if sim.rx_shield >= 0.7:
			options.append(["shield_crack", 0.5])
	if u.star_index >= 0 and u.pulsar.is_empty() and u.black_hole.is_empty() and flare == INF:
		options.append(["flare", 2.5 if u.kind in ["red dwarf", "sun", "yellow star", "orange star", "blue giant"] else 1.0])
	var total := 0.0
	for o: Array in options:
		total += float(o[1])
	var roll := rng.randf() * total
	for o: Array in options:
		roll -= float(o[1])
		if roll <= 0.0:
			_fire(String(o[0]), sim)
			return


func _fire(kind: String, sim: ShipSim) -> void:
	match kind:
		"micrometeoroid":
			happened.emit("micrometeoroid", {"outside": rng.randf() < 0.35, "part": Damage.PARTS[rng.randi() % Damage.PARTS.size()]})
		"flare":
			flare = FLARE_WARNING
			happened.emit("flare_warning", {})
		"failure":
			var choices := ["rxpump", "water", "cryo", "fans", "cabpump", "cmg"]
			var b: String = choices[rng.randi() % choices.size()]
			sim.brk[b] = false
			happened.emit("failure", {"breaker": b})
		"coolant_leak":
			sim.rx_leak = rng.randf_range(0.0015, 0.004)
			happened.emit("coolant_leak", {})
		"pump_trip":
			sim.brk["rxpump"] = false
			happened.emit("pump_trip", {})
		"scram":
			sim.press("rx_scram")
			happened.emit("scram", {})
		"shield_crack":
			sim.rx_shield = rng.randf_range(0.45, 0.65)
			happened.emit("shield_crack", {})


## Extra dose rate (mSv/h) a flare puts on the keeper in `module`.
func flare_dose(module: String) -> float:
	if flare == INF or flare > 0.0:
		return 0.0
	return FLARE_DOSE * (SHELTER_FACTOR if module == SHELTER else 1.0)


func to_dict() -> Dictionary:
	return {"next_t": next_t, "flare": flare if flare != INF else 1e30}


func from_dict(d: Dictionary) -> void:
	next_t = float(d.get("next_t", FIRST))
	var f := float(d.get("flare", 1e30))
	flare = INF if f > 1e29 else f
