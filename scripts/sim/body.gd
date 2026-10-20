class_name Body
extends RefCounted
## The keeper's body. Time runs at one second a second, so the rates are a game's, not
## life's: hungry within the hour, thirsty sooner, tired after an hour or so awake.
##
## Radiation adds up as a dose (mSv, counted DOSE_SCALE times faster than the cabin
## dosimeter's rate); past SICK_DOSE the keeper sickens, past LETHAL_DOSE they die.
## The cabin air and temperature act on them through the systems sim.

signal died(cause: String)

const HUNGER_TIME := 2700.0
const THIRST_TIME := 1800.0
const AWAKE_TIME := 3600.0
const FITNESS_TIME := 7200.0
const DOSE_SCALE := 20.0
const SICK_DOSE := 1000.0
const LETHAL_DOSE := 6000.0

## 0 = fed / slaked / rested, 1 = starving / parched / exhausted.
var hunger := 0.15
var thirst := 0.15
var fatigue := 0.2
## 1 = strong, 0 = wasted.
var fitness := 1.0
## Accumulated dose (mSv) and how sick it has made the keeper (0..1).
var dose := 0.0
var sickness := 0.0
## 1 = well, 0 = dead.
var health := 1.0
var alive := true
## Effects for the view (0..1).
var cold := 0.0
## 1 at rest, ~3 hard at work: drives breathing in the sim.
var metabolism := 1.0
var cause := ""
var _exercise_t := 0.0


## `air`: the room round the keeper: 1 = the cabin, 0..1 = the cabin's air thinned to that
## fraction (the airlock; 0 = vacuum), -1 = on the hose outside. Breathing itself is a given
## (the game's licence): only the cabin's warmth reaches the body through the air.
func tick(dt: float, sim: ShipSim, dose_rate: float, air := 1.0) -> void:
	var breathing_cabin := air >= 0.0
	if not alive:
		return
	var working := _exercise_t > 0.0
	_exercise_t = maxf(_exercise_t - dt, 0.0)
	metabolism = 3.0 if working else 1.0
	hunger = minf(hunger + dt / HUNGER_TIME * (1.6 if working else 1.0), 1.0)
	thirst = minf(thirst + dt / THIRST_TIME * (2.0 if working else 1.0), 1.0)
	fatigue = minf(fatigue + dt / AWAKE_TIME * (2.0 if working else 1.0), 1.0)
	# Radiation: the station's dose rate plus the reactor's when it is driving the engine.
	var rate := dose_rate
	if sim.rx_mode == 1:
		rate += ShipSim.PROP_DOSE * sim.rx_power
	dose += rate * dt / 3600.0 * DOSE_SCALE
	var want_sick := clampf((dose - SICK_DOSE) / (LETHAL_DOSE - SICK_DOSE), 0.0, 1.0)
	sickness = move_toward(sickness, want_sick, dt / 120.0) if want_sick > sickness else move_toward(sickness, want_sick, dt / 1800.0)
	# The cold and the heat.
	cold = clampf((288.0 - sim.cab_t) / 25.0, 0.0, 1.0) if breathing_cabin and air > 0.5 else 0.0
	var heat := clampf((sim.cab_t - 310.0) / 15.0, 0.0, 1.0) if breathing_cabin else 0.0
	# Harm: each cause and what it does per second; the biggest names the death.
	var causes := [
		[1.0 / 600.0 if hunger >= 1.0 else 0.0, "starved"],
		[1.0 / 400.0 if thirst >= 1.0 else 0.0, "died of thirst"],
		[maxf(cold - 0.6, 0.0) / 120.0, "froze"],
		[heat / 200.0, "died of heat"],
		[sickness / 900.0, "died of radiation sickness"],
		[1.0 / 5.0 if dose > LETHAL_DOSE else 0.0, "killed by radiation"],
	]
	var harm := 0.0
	var top := 0.0
	for c: Array in causes:
		var rate_c: float = c[0]
		harm += rate_c * dt
		if rate_c > top:
			top = rate_c
			cause = c[1]
	if harm > 0.0:
		health -= harm
	elif hunger < 0.8 and thirst < 0.8 and fatigue < 0.95:
		health = minf(health + dt / 900.0, 1.0)
	if health <= 0.0:
		health = 0.0
		alive = false
		died.emit(cause)


## Killed outright (a blast).
func kill(cause: String) -> void:
	if not alive:
		return
	health = 0.0
	alive = false
	died.emit(cause)


# --- Things the keeper does --------------------------------------------------------------------

func eat() -> void:
	hunger = maxf(hunger - 0.55, 0.0)
	thirst = maxf(thirst - 0.1, 0.0)


func drink() -> void:
	thirst = maxf(thirst - 0.45, 0.0)


## Called every frame the keeper is hard at work.
func exercise(dt: float) -> void:
	_exercise_t = 0.5
	fitness = minf(fitness + dt / 90.0, 1.0)


## An anti-radiation pill: clears some of the dose and the sickness it brought.
func pill() -> void:
	dose = maxf(dose - 600.0, 0.0)
	sickness = maxf(sickness - 0.2, 0.0)


func can_sleep() -> bool:
	return fatigue > 0.3


## How hard the arms can pull and push (wasted muscles are weaker).
func strength() -> float:
	return lerpf(0.45, 1.0, fitness)


## The worst of the body's complaints, for the cuff readout.
func complaints() -> PackedStringArray:
	var out := PackedStringArray()
	if hunger > 0.6:
		out.append("STARVING" if hunger >= 1.0 else "HUNGRY")
	if thirst > 0.6:
		out.append("PARCHED" if thirst >= 1.0 else "THIRSTY")
	if fatigue > 0.7:
		out.append("EXHAUSTED" if fatigue > 0.95 else "TIRED")
	if fitness < 0.4:
		out.append("WEAK")
	if sickness > 0.05:
		out.append("RADIATION SICK")
	if cold > 0.3:
		out.append("COLD")
	return out


const SAVED := ["hunger", "thirst", "fatigue", "fitness", "dose", "sickness", "health"]


func to_dict() -> Dictionary:
	var d := {}
	for k: String in SAVED:
		d[k] = get(k)
	return d


func from_dict(d: Dictionary) -> void:
	for k: String in d:
		set(k, d[k])
