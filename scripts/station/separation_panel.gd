class_name SeparationPanel
extends RefCounted
## MODULE SEPARATION, overhead in the command deck: pick a module, arm, and fire the bolts. It
## goes, and everything that hangs beyond it goes with it (the screen says what), drifting off;
## the hatchway left open in the station is closed by a blast seal. The command deck stays:
## this is where it is done from.

## [selector label, module]
const OPTIONS := [["ENG", "Engineering"], ["NODE", "Node"], ["AIRLOCK", "Airlock"], ["PORT", "Dock"],
	["HAB", "Habitation"], ["LIFE", "Life support"], ["RX", "Reactor"]]
## What each module takes with it, for the screen.
const TAKES := {
	"Engineering": "REACTOR CONTROL, POWER, BREAKERS",
	"Node": "COMMS DISH",
	"Airlock": "UMBILICAL, EVA, CARGO PORT",
	"Dock": "DOCKING PORT, ALL DOCKED THERE",
	"Habitation": "GALLEY, MEDICINE, BED, SCIENCE, COMMS",
	"Life support": "AIR, WATER, STORES",
	"Reactor": "BATTERY AND SOLAR ONLY AFTER",
	"Stern": "MAIN ENGINE, TORCH, ALL FUEL",
}

var station: Station
var sim: ShipSim
var main: Node
var panel: ControlPanel
var _screen: Terminal


func build(p_station: Station, p_sim: ShipSim, p_main: Node) -> void:
	station = p_station
	sim = p_sim
	main = p_main
	var p := ControlPanel.make(station, sim, "MODULE SEPARATION", Vector2(1.5, 0.8), station.face_xform(4, -12.5), func() -> bool: return sim.bat_kwh > 0.0)
	panel = p
	_screen = p.crt(0.48, 0.42, 0.78, 0.5, 10, 420.0)
	var names := PackedStringArray()
	for o: Array in OPTIONS:
		names.append(String(o[0]))
	p.rotary("c_sep", "MODULE", 1.06, 0.26, names)
	p.toggle("c_sep_arm", "ARM", 1.32, 0.26, PackedStringArray(["SAFE", "ARM"]), true)
	p.lamp("ARMED", 1.06, 0.56, func() -> bool: return sim.c_sep_arm, Ctl.RED)
	p.button("SEPARATE", 1.32, 0.56, fire, func() -> bool: return sim.c_sep_arm, Ctl.RED, true)


func module() -> String:
	return String(OPTIONS[clampi(sim.c_sep, 0, OPTIONS.size() - 1)][1])


func fire() -> void:
	if not sim.c_sep_arm:
		Sfx.play("error", -8.0, 1.0, "Station")
		main.hud.toast("ARM first")
		return
	var why: String = main.separate_module(module())
	if why != "":
		Sfx.play("error", -8.0, 1.0, "Station")
		main.hud.toast(why)
		return
	sim.c_sep_arm = false


func update() -> void:
	if _screen == null:
		return
	var m := module()
	var l := PackedStringArray()
	l.append("  SEPARATE: %s" % m.to_upper())
	var set := station.cast_set(m)
	if set.is_empty():
		l.append("")
		l.append("  ALREADY GONE" if station.gone.has(m) else "  CANNOT")
	else:
		l.append("")
		l.append("  GOES WITH IT:")
		for k: String in set:
			l.append("   " + k.to_upper())
			l.append("      " + String(TAKES.get(k, "")))
		var why: String = main.separation_blocker(m)
		l.append("")
		l.append("  " + (why if why != "" else ("ARMED: READY" if sim.c_sep_arm else "SAFE")))
	_screen.text = "\n".join(l)
