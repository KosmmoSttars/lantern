class_name Damage
extends RefCounted
## Harm to the station: hull breaches (holes in a module's wall, patched from inside with a
## kit) and broken parts outside (the dish, the solar wings, the radiators), mended by hand on a
## spacewalk. The air never runs out, but a hole bleeds the cabin's warmth away, and the hit
## that made it may have shorted the gear beside it: that breaker will not stay in until the
## hole is patched.

signal changed

const PARTS := ["dish", "wing_0", "wing_1", "radiator_0", "radiator_1", "radiator_2", "radiator_3"]
const PART_NAMES := {"dish": "high-gain dish", "wing_0": "port solar wing", "wing_1": "starboard solar wing",
	"radiator_0": "radiator 1", "radiator_1": "radiator 2", "radiator_2": "radiator 3", "radiator_3": "radiator 4"}

## [{id, module, pos (Vector3, station frame), normal (into the cabin), area (m2), breaker
## (shorted by the hit, "" for none)}]
var breaches: Array = []
## part -> true when broken.
var broken := {}
var _next_id := 1


func leak_area() -> float:
	var a := 0.0
	for b: Dictionary in breaches:
		a += float(b.area)
	return a


## What a hit in each module can short: the gear that lives there (nothing that would take the
## reactor with it).
const HIT_BREAKERS := {
	"Command deck": ["nav", "tracker", "cmg"],
	"Engineering": ["cabpump", "lights"],
	"Node": ["dish"],
	"Habitation": ["galley", "lab"],
	"Life support": ["water", "fans"],
}


func add_breach(module: String, pos: Vector3, normal: Vector3, area: float, breaker := "") -> void:
	breaches.append({"id": _next_id, "module": module, "pos": pos, "normal": normal, "area": area, "breaker": breaker})
	_next_id += 1
	changed.emit()


func patch(id: int) -> void:
	for b: Dictionary in breaches:
		if int(b.id) == id:
			breaches.erase(b)
			changed.emit()
			return


func break_part(part: String) -> void:
	broken[part] = true
	changed.emit()


func repair(part: String) -> void:
	broken.erase(part)
	changed.emit()


func is_broken(part: String) -> bool:
	return bool(broken.get(part, false))


## Solar output left (each wing is half of it) and radiator area left.
func solar_factor() -> float:
	var f := 1.0
	for k in 2:
		if is_broken("wing_%d" % k):
			f -= 0.5
	return f


func radiator_factor() -> float:
	var f := 1.0
	for k in 4:
		if is_broken("radiator_%d" % k):
			f -= 0.25
	return f


## The breakers shorted by holes not yet patched.
func shorted() -> Array:
	var out := []
	for b: Dictionary in breaches:
		if String(b.get("breaker", "")) != "":
			out.append(String(b.breaker))
	return out


## Push the effects into the systems sim each frame.
func apply(sim: ShipSim) -> void:
	sim.leak_area = leak_area()
	sim.shorted = shorted()
	sim.solar_factor = solar_factor()
	sim.radiator_factor = radiator_factor()


func to_dict() -> Dictionary:
	var bs := []
	for b: Dictionary in breaches:
		bs.append({"id": b.id, "module": b.module, "pos": [b.pos.x, b.pos.y, b.pos.z], "normal": [b.normal.x, b.normal.y, b.normal.z], "area": b.area, "breaker": b.get("breaker", "")})
	return {"breaches": bs, "broken": broken, "next": _next_id}


func from_dict(d: Dictionary) -> void:
	breaches.clear()
	for b: Dictionary in d.get("breaches", []):
		breaches.append({"id": int(b.id), "module": b.module, "pos": Vector3(b.pos[0], b.pos[1], b.pos[2]),
			"normal": Vector3(b.normal[0], b.normal[1], b.normal[2]), "area": float(b.area), "breaker": String(b.get("breaker", ""))})
	broken = d.get("broken", {})
	_next_id = int(d.get("next", 1))
