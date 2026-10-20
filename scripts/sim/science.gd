class_name Science
extends RefCounted
## The lab's instruments, the data they gather, the uplink that sells it, and the supply
## drones it buys.
##
## A scan takes SCAN_TIME seconds and needs its instrument's conditions to hold the whole
## time. What it is worth depends on what was scanned (a pulsar is worth more than a moon
## of Saturn) and on how often it has been scanned before. Data waits on the drive until the
## dish sends it through a relay; each megabyte sent pays its share of credit. Credit buys
## deliveries, which come by drone to the airlock's cargo port, only where a relay answers.

signal note(text: String)

const SCAN_TIME := 45.0
const DRIVE_MB := 4000.0
const START_CREDIT := 120.0
## name -> [what the instrument needs, MB per scan]
const INSTRUMENTS := {
	"spectrometer": ["close to the target", 180.0],
	"magnetometer": ["in orbit round the target, boom out", 120.0],
	"telescope": ["pointed at the target (TARGET mode)", 260.0],
	"particles": ["nothing: it samples the radiation round the station", 60.0],
}
## Catalogue: [label, price, lead time (s), what it brings]
const CATALOGUE := [
	["RATIONS x10", 40.0, 180.0, {"food": 10}],
	["WATER 300 kg", 30.0, 180.0, {"water": 300.0}],
	["RAD PILLS x3", 60.0, 240.0, {"pills": 3}],
	["D-HE3 2000 kg", 220.0, 360.0, {"dhe": 2000.0}],
	["HYDROGEN 6 t", 160.0, 300.0, {"h2": 6000.0}],
	["HYDRAZINE 200 kg", 50.0, 240.0, {"hyd": 200.0}],
	["PATCH KITS x3", 45.0, 240.0, {"patches": 3}],
	["INSTANT FILM x10", 15.0, 180.0, {"film": 10}],
	["FUEL ASSEMBLY", 150.0, 420.0, {"rx_fresh": 1}],
]

var credit := START_CREDIT
## What the station's observatories add to every scan's worth (1 = none; set by main).
var bonus := 1.0
## Data on the drive: [{mb, credit}] (credit is what the whole packet will fetch).
var packets: Array = []
## "system:body:instrument" -> times scanned.
var scanned := {}
## The scan under way: {instrument, body, t}.
var scan := {}
var c_uplink := false
var c_boom := false
## How far the magnetometer boom is out (0 stowed, 1 out): its motor runs on lab power.
var boom := 0.0
const BOOM_TIME := 15.0
var c_dock_open := false
var c_item := 0
## Deliveries ordered: [{item, eta (s left), state: "flying" | "holding" | "docked"}].
var orders: Array = []
## A docked delivery's contents, waiting to be unpacked (empty = no crate).
var crate := {}
var last_result := ""
## False while the high-gain dish is broken (Damage).
var dish_ok := true


func drive_mb() -> float:
	var t := 0.0
	for p: Dictionary in packets:
		t += float(p.mb)
	return t


func drive_credit() -> float:
	var t := 0.0
	for p: Dictionary in packets:
		t += float(p.credit)
	return t


## How much a scan of body b with instrument `ins` would be worth now.
func value(u: Universe, b: int, ins: String) -> float:
	var bb := u.bodies[b] if b >= 0 else {}
	var base := 80.0
	match ins:
		"particles":
			base = 60.0
		"spectrometer":
			base = 120.0
		"magnetometer":
			base = 100.0 if bb.get("look", "") in ["giant", "saturn"] else 40.0
		"telescope":
			base = 100.0
	var kind: String = bb.get("kind", "")
	var look: String = bb.get("look", "")
	if kind == "star":
		base *= {"pulsar": 5.0, "black hole": 8.0, "brown dwarf": 2.5, "white dwarf": 3.0, "blue giant": 3.0}.get(String(bb.get("star", "")), 1.5)
	elif look in ["ocean", "lava"]:
		base *= 3.0
	elif look in ["giant", "saturn"]:
		base *= 1.8
	if u.kind == "rogue planet":
		base *= 2.0
	# The Solar System was charted long ago.
	if u.system_id == 0:
		base *= 0.5
	var n := int(scanned.get(_key(u, b, ins), 0))
	return base * bonus * [1.0, 0.3, 0.1, 0.0][mini(n, 3)]


func _key(u: Universe, b: int, ins: String) -> String:
	return "%d:%d:%s" % [u.system_id, b, ins]


## Why instrument `ins` cannot scan the target now ("" when it can).
func blocker(ins: String, f: Flight, sim: ShipSim) -> String:
	if not sim.powered("lab"):
		return "LAB HAS NO POWER"
	if not scan.is_empty():
		return "SCAN UNDER WAY"
	if drive_mb() + float(INSTRUMENTS[ins][1]) > DRIVE_MB:
		return "DRIVE FULL: UPLINK FIRST"
	if not f.transit.is_empty():
		return "NOT DURING A TRANSIT"
	var b := f.c_target
	if ins != "particles" and f.u.bodies[b].kind in ["derelict", "module"]:
		return "NOTHING THERE TO STUDY"
	match ins:
		"spectrometer":
			var r: float = f.u.bodies[b].radius
			if f.target_dist > maxf(r * 60.0, 2.0e8):
				return "TOO FAR: GET CLOSER"
		"magnetometer":
			if not c_boom:
				return "BOOM NOT DEPLOYED"
			if boom < 1.0:
				return "BOOM STILL GOING OUT"
			if f.soi != b:
				# Say where the station is: picking a body on the map does not take you there.
				return "IN ORBIT ROUND %s: FLY TO %s FIRST" % [String(f.u.bodies[f.soi].name).to_upper(), String(f.u.bodies[b].name).to_upper()]
		"telescope":
			if Flight.ATT_MODES[f.c_att_mode] != "TARGET" or f.att_error > deg_to_rad(1.5):
				return "POINT AT THE TARGET (TARGET MODE)"
	return ""


func start_scan(ins: String, f: Flight, sim: ShipSim) -> String:
	var why := blocker(ins, f, sim)
	if why != "":
		return why
	scan = {"instrument": ins, "body": f.c_target if ins != "particles" else f.soi, "t": 0.0}
	return ""


func tick(dt: float, f: Flight, sim: ShipSim) -> void:
	if sim.powered("lab"):
		boom = move_toward(boom, 1.0 if c_boom else 0.0, dt / BOOM_TIME)
	_scan(dt, f, sim)
	_uplink(dt, f, sim)
	_orders(dt, f, sim)


func _scan(dt: float, f: Flight, sim: ShipSim) -> void:
	if scan.is_empty():
		return
	var ins: String = scan.instrument
	# Conditions must hold all through: check them as if starting again.
	var keep := scan
	scan = {}
	var why := blocker(ins, f, sim)
	scan = keep
	if why != "" or (ins != "particles" and f.c_target != int(scan.body)):
		scan = {}
		last_result = "SCAN LOST: " + (why if why != "" else "TARGET CHANGED")
		note.emit(last_result)
		return
	scan.t = float(scan.t) + dt
	if float(scan.t) >= SCAN_TIME:
		var b: int = scan.body
		var v := value(f.u, b, ins)
		var mb: float = INSTRUMENTS[ins][1]
		if ins == "particles":
			v *= clampf(f.dose_rate / 0.05, 0.5, 4.0)
		packets.append({"mb": mb, "credit": v})
		var k := _key(f.u, b, ins)
		scanned[k] = int(scanned.get(k, 0)) + 1
		last_result = "%s: %s, %d MB, worth %d" % [ins.to_upper(), String(f.u.bodies[b].name).to_upper(), roundi(mb), roundi(v)]
		note.emit("Scan done: " + last_result)
		scan = {}


func scan_progress() -> float:
	return clampf(float(scan.get("t", 0.0)) / SCAN_TIME, 0.0, 1.0) if not scan.is_empty() else 0.0


## Is there a relay to talk to here? (The Solar System always has Earth.)
func link_ok(f: Flight, sim: ShipSim) -> bool:
	return f.u.has_relay and sim.powered("dish") and dish_ok


func link_rate(f: Flight) -> float:
	return 6.0 if f.u.system_id == 0 else 2.5


func _uplink(dt: float, f: Flight, sim: ShipSim) -> void:
	sim.extra_kw["dish"] = 2.0 if c_uplink and link_ok(f, sim) and not packets.is_empty() else 0.0
	if not c_uplink or not link_ok(f, sim) or packets.is_empty():
		return
	var left := link_rate(f) * dt
	while left > 0.0 and not packets.is_empty():
		var p: Dictionary = packets[0]
		var take := minf(left, float(p.mb))
		var share := float(p.credit) * take / float(p.mb)
		credit += share
		p.credit = float(p.credit) - share
		p.mb = float(p.mb) - take
		left -= take
		if float(p.mb) <= 0.001:
			packets.pop_front()


func order(item: int, f: Flight, sim: ShipSim) -> String:
	if not link_ok(f, sim):
		return "NO RELAY: CANNOT ORDER HERE"
	var it: Array = CATALOGUE[item]
	if credit < float(it[1]):
		return "NOT ENOUGH CREDIT"
	credit -= float(it[1])
	orders.append({"item": item, "eta": float(it[2]), "state": "flying", "system": f.u.system_id})
	return ""


func _orders(dt: float, f: Flight, sim: ShipSim) -> void:
	for o: Dictionary in orders.duplicate():
		if int(o.system) != f.u.system_id:
			# The drone cannot follow the station between the stars: the order is refunded.
			credit += float(CATALOGUE[int(o.item)][1])
			orders.erase(o)
			note.emit("Delivery cancelled: the station left the system")
			continue
		if o.state == "flying":
			o.eta = maxf(float(o.eta) - dt, 0.0)
			if float(o.eta) <= 0.0:
				o.state = "holding"
				note.emit("Supply drone alongside: open the CARGO PORT (comms panel, lab)")
		if o.state == "holding" and crate.is_empty() and c_dock_open and f.transit.is_empty() and sim.total_thrust() <= 0.0:
			crate = (CATALOGUE[int(o.item)][3] as Dictionary).duplicate()
			crate["label"] = CATALOGUE[int(o.item)][0]
			orders.erase(o)
			note.emit("Drone docked at the airlock: a crate in the airlock")


## Open the crate in the airlock: its contents go to the stores.
func unpack(sim: ShipSim) -> String:
	if crate.is_empty():
		return ""
	var label: String = crate.get("label", "")
	for k: String in crate:
		if k == "label":
			continue
		var v: Variant = crate[k]
		match k:
			"food", "pills", "patches", "film", "rx_fresh":
				sim.set(k, int(sim.get(k)) + int(v))
			"dhe":
				sim.dhe = minf(sim.dhe + float(v), ShipSim.DHE_MAX)
			"h2":
				sim.h2 = minf(sim.h2 + float(v), ShipSim.H2_MAX)
			"hyd":
				sim.hyd = minf(sim.hyd + float(v), ShipSim.HYD_MAX)
			_:
				sim.set(k, float(sim.get(k)) + float(v))
	crate = {}
	return label


const SAVED := ["credit", "packets", "scanned", "c_uplink", "c_boom", "boom", "c_dock_open", "c_item", "orders", "crate"]


func to_dict() -> Dictionary:
	var d := {}
	for k: String in SAVED:
		d[k] = get(k)
	return d


func from_dict(d: Dictionary) -> void:
	for k: String in d:
		set(k, d[k])
