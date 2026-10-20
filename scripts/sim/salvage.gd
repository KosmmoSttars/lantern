class_name Salvage
extends RefCounted
## Derelicts and what is left in them. Every derelict (a body of kind "derelict" in its
## system) carries a load fixed by its seed and its class: water, rations, fuel canisters, patch kits, medicine, film. Taking a thing puts it in the
## station's stores; what has been taken is remembered per system and saved. One derelict at
## a time can be docked at the docking port. Whole modules (kind "module") are taken whole:
## docked once, they stay, and are gone from the map for good.

## What each class tends to carry: [kind, weight].
const MIX := {
	"CARGO MODULE": [["food", 4], ["water", 4], ["patches", 2]],
	"FUEL DEPOT": [["dhe", 4], ["rx_fresh", 3], ["hyd", 2]],
	"SURVEY TENDER": [["film", 2], ["pills", 2], ["patches", 2], ["food", 1]],
	"HAB MODULE": [["food", 3], ["water", 2], ["pills", 2], ["film", 1], ["patches", 1]],
	"RELAY POD": [["patches", 2], ["film", 1], ["dhe", 1]],
}

## The derelict docked at the port (body index in the current system), or -1.
var docked := -1
## The air in the docked derelict (kPa): none until PRESSURIZE fills it, and none again once it
## lets go (its hatchway has no hatch of its own).
var air := 0.0
## "system:body" -> [indices of the things already taken].
var taken := {}
## "system:body" of every module docked for good.
var modules := []


## Everything a derelict carried: [[kind, amount, label]].
static func loot(u: Universe, b: int) -> Array:
	var body := u.bodies[b]
	var rng := RandomNumberGenerator.new()
	rng.seed = int(body.get("loot_seed", b))
	var mix: Array = MIX.get(String(body.get("class", "CARGO MODULE")), MIX["CARGO MODULE"])
	var total := 0
	for m: Array in mix:
		total += int(m[1])
	var out := []
	for k in rng.randi_range(4, 7):
		var roll := rng.randi() % total
		var kind := "food"
		for m: Array in mix:
			roll -= int(m[1])
			if roll < 0:
				kind = String(m[0])
				break
		out.append(_thing(kind, rng))
	return out


static func _thing(kind: String, rng: RandomNumberGenerator) -> Array:
	match kind:
		"food":
			var n := rng.randi_range(3, 8)
			return [kind, n, "Ration trays x%d" % n]
		"water":
			var w := rng.randi_range(4, 10) * 10
			return [kind, w, "Water containers (%d kg)" % w]
		"dhe":
			var d := rng.randi_range(3, 12) * 100
			return [kind, d, "D-He3 canister (%d kg)" % d]
		"hyd":
			var h := rng.randi_range(4, 12) * 10
			return [kind, h, "Hydrazine cylinder (%d kg)" % h]
		"patches":
			var p := rng.randi_range(1, 3)
			return [kind, p, "Patch kit case x%d" % p]
		"pills":
			var q := rng.randi_range(1, 3)
			return [kind, q, "Medical kit: rad pills x%d" % q]
		"film":
			return [kind, 10, "Instant film pack x10"]
		"rx_fresh":
			var f := rng.randi_range(1, 2)
			return [kind, f, "Reactor fuel assembly x%d (to the rack)" % f]
	return ["food", 1, "Ration tray"]


func _key(u: Universe, b: int) -> String:
	return "%d:%d" % [u.system_id, b]


func is_taken(u: Universe, b: int, i: int) -> bool:
	return (taken.get(_key(u, b), []) as Array).has(i)


## Nothing left aboard.
func empty(u: Universe, b: int) -> bool:
	return (taken.get(_key(u, b), []) as Array).size() >= loot(u, b).size()


## Take thing i of derelict b into the station's stores; returns its label.
func take(sim: ShipSim, u: Universe, b: int, i: int) -> String:
	if is_taken(u, b, i):
		return ""
	var thing: Array = loot(u, b)[i]
	give(sim, String(thing[0]), thing[1])
	var list: Array = taken.get(_key(u, b), [])
	list.append(i)
	taken[_key(u, b)] = list
	return String(thing[2])


## Into the stores, as a supply crate would go.
static func give(sim: ShipSim, kind: String, amount: Variant) -> void:
	match kind:
		"food", "pills", "patches", "film", "rx_fresh":
			sim.set(kind, int(sim.get(kind)) + int(amount))
		"dhe":
			sim.dhe = minf(sim.dhe + float(amount), ShipSim.DHE_MAX)
		"hyd":
			sim.hyd = minf(sim.hyd + float(amount), ShipSim.HYD_MAX)
		_:
			sim.set(kind, float(sim.get(kind)) + float(amount))


## Module b is the station's now: off the map for good.
func take_module(u: Universe, b: int) -> void:
	if not modules.has(_key(u, b)):
		modules.append(_key(u, b))
	u.bodies[b]["gone"] = true


## Mark the modules already taken in a freshly made system, so nothing shows them.
func mark(u: Universe) -> void:
	for i in u.bodies.size():
		if u.bodies[i].kind == "module" and modules.has(_key(u, i)):
			u.bodies[i]["gone"] = true


func to_dict() -> Dictionary:
	return {"docked": docked, "taken": taken, "air": air, "modules": modules}


func from_dict(d: Dictionary) -> void:
	docked = int(d.get("docked", -1))
	taken = d.get("taken", {})
	air = float(d.get("air", 0.0))
	modules = d.get("modules", [])
