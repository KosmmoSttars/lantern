class_name Story
extends RefCounted
## The thread through the game: messages from the Office (the mission office back home,
## reached through the relays) at the milestones of the keeper's journey, the signal from
## deep in the galaxy, and the three endings that are not death:
##   home     after five star systems, back in orbit round Earth
##   horizon  close enough to a black hole that there is no coming back
##   stay     after twelve systems, the keeper signs off and goes on alone

signal message(text: String)
signal ending(kind: String)

const HOME_SYSTEMS := 5
const STAY_SYSTEMS := 12
## Within this many Schwarzschild radii of a black hole the keeper has gone too far.
const HORIZON_RS := 30.0

const LINES := {
	"start": "LANTERN, OFFICE. The crew landed this morning, all well. They asked us to thank you. You chose to stay with her; she is yours to run. Send us what you find out there and we will keep you fed.",
	"first_data": "Data received, clean and complete. Credit posted. Keep it coming.",
	"first_star": "We watched you leave the Sun behind. Nobody has gone where you are. Mind the D-He3: the drones cannot follow you between the stars.",
	"pulsar": "Timing fix confirmed. Your navigation computer can plot the long crossings now. Be careful with that.",
	"home_open": "Five systems. The board would like you home; we would like you to do what you think is right. If you come back, we will meet you in orbit round Earth.",
	"signal": "There is something in your last uplink we cannot explain: a pulse train, very regular, very old. It repeats from deeper in.",
	"stay_open": "You are past anything we could send after you in our lifetimes. If you go on, we will keep listening for as long as the relays carry you. The SIGN OFF switch is on the comms panel, under its cover.",
}

## Lines already delivered, in order, for the log screen.
var log: Array = []
var sent := {}
var ended := ""


func say(key: String) -> void:
	if sent.has(key):
		return
	sent[key] = true
	log.append(LINES[key])
	message.emit(LINES[key])


func tick(f: Flight, g: Galaxy, sc: Science) -> void:
	if ended != "":
		return
	say("start")
	if sc.credit > Science.START_CREDIT + 0.5:
		say("first_data")
	var stars := g.visited.size() - 1
	if stars >= 1:
		say("first_star")
	if g.pulsar_fix:
		say("pulsar")
	if stars >= HOME_SYSTEMS:
		say("home_open")
	if stars >= 8 or (sent.has("first_star") and not f.u.black_hole.is_empty()):
		say("signal")
	if stars >= STAY_SYSTEMS:
		say("stay_open")
	# Endings.
	if sent.has("home_open") and f.u.system_id == 0 and f.soi == f.u.find("Earth") and f.transit.is_empty():
		_end("home")
	if not f.u.black_hole.is_empty():
		var d := Orbit.length(Orbit.sub(f.world_pos(), f.u.position(0, f.t))) / float(f.u.black_hole.rs)
		if d < HORIZON_RS:
			_end("horizon")


func can_sign_off() -> bool:
	return sent.has("stay_open") and ended == ""


func sign_off() -> void:
	if can_sign_off():
		_end("stay")


func _end(kind: String) -> void:
	if ended != "":
		return
	ended = kind
	ending.emit(kind)


## The words over black for each ending.
static func epilogue(kind: String) -> PackedStringArray:
	match kind:
		"home":
			return PackedStringArray([
				"Earth fills the cupola, blue and ordinary and impossible.",
				"The Office sends a ship up to meet you. Somebody has painted your name on it.",
				"You bring Lantern home with her tanks nearly dry and her drives full of the sky.",
				"COME HOME",
			])
		"horizon":
			return PackedStringArray([
				"The disk wraps round the cupola and the stars behind you crowd into a ring of light.",
				"The uplink still runs. Every second you send is worth more than the station.",
				"Then the light is everywhere, and then it is not anywhere at all.",
				"BEYOND THE HORIZON",
			])
		"stay":
			return PackedStringArray([
				"You close the cover over the switch and the relay's carrier fades to hiss.",
				"Lantern turns her bow to the next star. The torch lights, steady and blue.",
				"Somewhere far behind you, people keep listening.",
				"A LANTERN AMONG THE STARS",
			])
		"meltdown":
			return PackedStringArray([
				"The core slumps through its vessel and the shield glows from the inside.",
				"The hull aft of Life support opens like a flower. Lantern rolls, and keeps rolling.",
				"Somewhere a beacon goes on blinking a name nobody is left to answer to.",
				"MELTDOWN",
			])
	return PackedStringArray()


func to_dict() -> Dictionary:
	return {"log": log, "sent": sent, "ended": ended}


func from_dict(d: Dictionary) -> void:
	log = d.get("log", [])
	sent = d.get("sent", {})
	ended = d.get("ended", "")
