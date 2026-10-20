class_name ShipSim
extends RefCounted
## Lantern's systems as numbers: reactor, electrical, thermal, life support, propulsion,
## attitude actuators. No nodes, no rendering: the panels write the control fields
## (the `c_` names below are what panel controls bind to) and read the state fields;
## `tick(dt)` advances it all by game time. Every dynamic is written in a form that stays
## stable with large steps (exponential relaxation or linearised implicit Euler), so the
## same code runs at 1x and at time compression.
##
## Units: seconds, kelvin, watts (kW where named), kPa, kg, newtons.

signal alarm(code: String, on: bool)

# --- Constants -----------------------------------------------------------------------

## Reactor thermal rating per mode: electric (closed Brayton loop) and propulsion
## (hydrogen through the core).
const RX_RATED := [400e3, 640e6]
## Core temperature the reactor is designed to run at, per mode.
const RX_NOMINAL := [1150.0, 2650.0]
const RX_HEAT_CAP := 6.0e4
const RX_MELT := 3050.0
## The core holds three fuel assemblies. A fresh load runs about an hour at a working power
## (burnup per second = power / FUEL_LIFE, the propulsion mode four times as greedy), the
## middle slot a little faster than the others.
const FUEL_SLOTS := 3
const FUEL_LIFE := 2400.0
const SLOT_SHARE := [0.95, 1.1, 0.95]
## The core head may be opened only when the core is shut down and this cool (K).
const HEAD_COOL := 650.0
## Overheat: past this the melt countdown runs (per mode), and how long it gives (s).
const MELT_START := [1700.0, 2950.0]
const MELT_SAFE := [1500.0, 2850.0]
const MELT_TIME := 150.0
## The primary loop's pressure (MPa): the relief valve lifts at P_RELIEF, the loop bursts at
## P_BURST. Cold coolant let into a dry core hotter than STEAM_T flashes to steam.
const P_RELIEF := 3.2
const P_BURST := 4.0
const STEAM_T := 900.0
## A power excursion: above EXCURSION_P for EXCURSION_T seconds the core blows apart.
const EXCURSION_P := 1.3
const EXCURSION_T := 3.0
## Which module each load lives in: cast that module off and the load is gone with it.
const BREAKER_HOME := {"water": "Life support",
	"rxpump": "Reactor", "galley": "Habitation", "lab": "Habitation", "dish": "Node",
	"turbo": "Stern", "cryo": "Stern", "torch": "Stern", "rcsheat": "Stern"}
## Primary loop conductance at full pump speed (W/K).
const LOOP_H := 533.0
const LOOP_HEAT_CAP := 4.0e5
## Radiator: emissivity x area x Stefan-Boltzmann, and the effective sink temperature.
const RAD_K := 2.0e-5
const SINK_T := 90.0
const H2_CP := 14300.0
## Main engine: full-throttle propellant flow and exhaust speed at nominal core heat.
const ENG_MDOT := 17.0
const ENG_VE := 8829.0
const DRY_MASS := 120000.0
const H2_MAX := 80000.0
const HYD_MAX := 1500.0
## Fusion torch: full thrust, exhaust speed, the fuel it can carry, and how long its
## magnetic nozzle takes to come up to field.
const TORCH_F := 90000.0
const TORCH_VE := 2.0e7
const DHE_MAX := 30000.0
const FIELD_TIME := 40.0
const RCS_ISP_VE := 2160.0
const BAT_CAP_KWH := 200.0
const SOLAR_KW := 7.0
## What a docked power module adds: battery cells (kWh) and solar wings (kW in full sun).
const POWER_MODULE_KWH := 200.0
const POWER_MODULE_KW := 5.0
## A greenhouse: one tray of food every two hours of the keeper's day.
const CROP_TIME := 7200.0
const CROP_MAX := 6.0
## PRESSURIZE fills what is docked at this many kPa a second.
const PORT_FILL := 2.5
## Cabin: kPa per mole-ish bookkeeping is folded into these rates (300 m3 at 295 K).
## The air never runs out (the game's licence): life support makes up what leaks, this fast
## (kPa a second); only a hole bigger than that (both airlock hatches open) outruns it.
const AIR_MAKEUP := 0.5
const CABIN_HEAT_CAP := 1.5e6
## Time runs at one second a second, so breathing, scrubbing and making oxygen run this many
## times faster than in life: a dead scrubber is felt in minutes, not days.
const LIFE_SCALE := 60.0
## Main engine: dose rate in the cabin at full propulsion power (mSv/h) through the shield.
const PROP_DOSE := 40.0

## Breakers: name -> [label, bus, trip rating kW].
const BREAKERS := {
	"lights": ["LIGHTS", "A", 3.0],
	"fans": ["CABIN FANS", "B", 1.5],
	"water": ["WATER REC", "B", 1.5],
	"heater": ["CABIN HEAT", "B", 4.0],
	"cabpump": ["CABIN LOOP", "A", 1.0],
	"rxpump": ["RX PUMP", "A", 8.0],
	"rods": ["ROD DRIVE", "A", 0.6],
	"turbo": ["TURBOPUMP", "A", 15.0],
	"cryo": ["H2 CRYO", "A", 3.5],
	"nav": ["NAV COMP", "A", 1.0],
	"tracker": ["STAR TRK", "A", 0.3],
	"cmg": ["CMG", "B", 3.0],
	"rcsheat": ["RCS HEAT", "B", 1.2],
	"dish": ["COMMS", "A", 3.5],
	"galley": ["GALLEY", "B", 2.5],
	"lab": ["LAB", "B", 2.0],
	"torch": ["TORCH FIELD", "A", 50.0],
}

## Annunciators in panel order: code -> [label, warning (true) or caution].
const ALARMS := {
	"rx_hot": ["RX OVERTEMP", true],
	"rx_scram": ["RX SCRAM", true],
	"rx_flow": ["CORE FLOW", true],
	"rx_melt": ["CORE MELT", true],
	"rx_cool": ["COOLANT LOW", true],
	"rx_fuel": ["FUEL LOW", false],
	"rx_wear": ["PUMP WEAR", false],
	"rx_shield": ["SHIELD", true],
	"rx_press": ["LOOP PRESSURE", true],
	"rx_over": ["RX POWER HIGH", true],
	"rx_mode": ["MODE INHIBIT", false],
	"bus_a": ["BUS A UV", true],
	"bus_b": ["BUS B UV", true],
	"bat_low": ["BATT LOW", false],
	"loop_hot": ["LOOP HOT", false],
	"cab_temp": ["CABIN TEMP", false],
	"press": ["CABIN PRESS", true],
	"h2_press": ["H2 PRESS", false],
	"boiloff": ["H2 BOILOFF", false],
	"cav": ["PUMP CAVIT", true],
	"rcs_cold": ["RCS COLD", false],
	"cmg_sat": ["CMG SAT", false],
	"rad_stow": ["RAD STOW", true],
	"arr_stow": ["ARRAY STOW", false],
	"trip": ["BRK TRIP", false],
	"torch_out": ["TORCH FLAMEOUT", true],
	"dhe_low": ["D-HE3 LOW", false],
}

# --- Controls (written by the panels) -------------------------------------------------

## Reactor: 0 = POWER, 1 = PROPULSION (only takes effect below 2% power).
var c_rx_mode := 0
var c_rx_rods := 0.32
var c_rx_auto := true
var c_rx_temp_set := 0.75
var c_rx_pump := 0.25
var c_rx_interlock := true
var c_rx_turbine := true
## Coolant FILL valve: tops the loop up from the reserve.
var c_rx_fill := false
## The loop's RELIEF valve: AUTO lifts above P_RELIEF (venting coolant), SHUT holds it.
var c_rx_relief := true
## Core head interlock OVERRIDE (guarded): the head opens whatever the core is doing.
var c_rx_override := false
## MODULE SEPARATION panel: which module, and the ARM switch.
var c_sep := 5
var c_sep_arm := false
## What the waste recycler makes next (ReactorBay.RECIPES).
var c_rc_output := 0
# Electrical contactors.
var c_gen_a := true
var c_sol_b := true
var c_bat_a := true
var c_bat_b := true
var c_tie := false
var c_arrays := true
# Thermal.
var c_radiators := true
var c_cab_pump := true
var c_cab_set := 0.5
var c_heater := false
# Life support.
var c_fans := true
var c_water_rec := true
# Propulsion.
var c_eng_arm := false
var c_h2_feed := 0.0
var c_he_press := false
var c_cryo := true
var c_throttle := 0.0
## Cooldown bypass: tank pressure pushes a little hydrogen through the core, no pump needed.
var c_cool_valve := false
var c_rcs_mode := 1
var c_rcs_heat := true
var c_cmg := true
# Fusion torch.
var c_torch_arm := false
var c_torch_field := false
var c_torch_thr := 0.0
# Guidance and the rest.
var c_nav := true
var c_tracker := true
var c_lab := true
var c_dish := true
var c_lights := true

## Breaker positions: name -> closed. A tripped breaker pops open; pushing it back in
## (the panel) sets it true again.
var brk := {}

# --- State -----------------------------------------------------------------------------

var t := 0.0
var rx_mode := 0
var rx_rod := 0.0
var rx_power := 0.0
var rx_decay_w := 0.0
var rx_t := 300.0
var rx_scrammed := false
var rx_damage := 0.0
## Fuel in each core slot: burnup 0 (fresh) .. 1 (spent), or -1 for an empty slot.
var rx_fuel: Array = [0.38, 0.52, 0.44]
## The core head in the biological shield is open (refuelling): the reactor cannot run.
var rx_head_open := false
## Primary coolant in the loop (1 = full) and in reserve tanks (loop-fulls), and how fast a
## leak is draining it (per second).
var rx_coolant := 1.0
var rx_reserve := 2.0
var rx_leak := 0.0
## Wear on the coolant pumps and their seals (1 = worn out): trips and leaks come with it.
var rx_pump_wear := 0.15
## The biological shield (1 = whole): cracked, the reactor room is a hot place.
var rx_shield := 1.0
## Seconds left before the core melts (INF while it is not overheating).
var rx_melt_t := INF
## The reactor module has been cast off: no reactor any more.
var rx_jettisoned := false
## Fresh assemblies in the rack, and in the recycler: material and spent assemblies taken in.
var rx_fresh := 3
var rc_material := 0.0
var rc_spent := 0
## Primary loop pressure (MPa); seconds spent over the excursion power; and why the reactor
## blew up this tick ("" while it has not: main takes it from there).
var rx_loop_p := 1.0
var rx_excursion := 0.0
var rx_boom := ""
## Burnups of fuel assemblies out of the core and the rack (loose about the station).
var rx_loose: Array = []
## Modules cast off (and "Stern": the truss, tank and engines aft).
var lost: Array = []
var _settling := false
var rx_q_w := 0.0
var gen_kw := 0.0
var loop_t := 300.0
var loop_q_w := 0.0
var rad_deploy := 1.0
var arrays_deploy := 1.0
var sol_kw := 0.0
var bus_a_v := 120.0
var bus_b_v := 120.0
var bat_kwh := 170.0
var bat_kw := 0.0
var load_a_kw := 0.0
var load_b_kw := 0.0
var cab_t := 294.0
var pp_o2 := 21.0
var pp_co2 := 0.3
var pp_n2 := 79.0
var leak_area := 0.0
var water := 1500.0
## Airlock: its pressure (kPa), the pump mode (0 HOLD, 1 DEPRESS, 2 REPRESS), the hatches,
## and a valve opened by hand (0 none, 1 to the cabin, 2 to space).
var lock_p := 101.0
var c_lock_mode := 0
var lock_inner_open := false
var lock_outer_open := false
var lock_valve := 0
## The docking port: the air in what is docked there (kPa) and its volume (m3, 0 = nothing
## docked: vacuum beyond), the port's outer hatch, PRESSURIZE (fills what is docked from the O2
## and N2 tanks) and the hatch's own bleed valve (shares the cabin's air with it).
var port_p := 0.0
var port_vol := 0.0
var port_open := false
var c_port_press := false
var port_valve := false
var leak_port := 0.0
## Modules docked for good beyond the port, outward (their kinds: Universe.MODULE_KINDS).
var modules: Array = []
## The greenhouse's crop: trays ripe to pick (and the part of the next one grown).
var crop := 0.0
## Hull patch kits.
var patches := 4
## Ration packs in the galley.
var food := 40
## Anti-radiation pills in the medical locker.
var pills := 6
## Shots left in the instant camera's film pack.
var film := 10
var h2 := 62000.0
var h2_p := 0.22
var he := 180.0
var pump_spin := 0.0
var eng_mdot := 0.0
## Flow control valve position: follows the throttle lever at its own pace.
var fcv := 0.0
var thrust := 0.0
var torch_field := 0.0
var torch_lit := false
var torch_thrust := 0.0
var dhe := 18000.0
var hyd := 1200.0
var hyd_t := 290.0
var cmg_h := 0.15
## Sunlight on the arrays as a fraction of full sun at Saturn (0 in shadow): set by flight.
var sun := 1.0
## The ship is accelerating hard: radiators and arrays must be stowed.
var accel := 0.0
## Extra loads in kW requested this frame by things outside the sim (galley, dish TX...).
var extra_kw := {}
## Body: how hard the keeper is breathing (1 = rest, ~3 = exercise).
var metabolism := 1.0
var alarms := {}
var silenced := {}

var _turbo_starting := 0.0
var _load_kw := {}
var _powered := {}


func _init() -> void:
	for b: String in BREAKERS:
		brk[b] = true
	for a: String in ALARMS:
		alarms[a] = false


# --- Queries ---------------------------------------------------------------------------

func mass() -> float:
	return DRY_MASS + h2 + hyd + water + dhe


## Everything pushing the station bow-first (N).
func total_thrust() -> float:
	return thrust + torch_thrust


func torch_ready() -> bool:
	return c_torch_arm and torch_field >= 1.0 and dhe > 1.0


func pressure() -> float:
	return pp_o2 + pp_co2 + pp_n2


## The battery's capacity (kWh): its own, and each power module's cells.
func bat_cap() -> float:
	return BAT_CAP_KWH + POWER_MODULE_KWH * modules.count("POWER MODULE")


## The solar wings' output in full sun, and each power module's own wings.
func solar_max() -> float:
	return SOLAR_KW + POWER_MODULE_KW * modules.count("POWER MODULE")


## Each module's names aboard, in order out from the port ("Greenhouse", "Greenhouse 2", ...).
static func module_names(kinds: Array) -> PackedStringArray:
	var out := PackedStringArray()
	var seen := {}
	for k: String in kinds:
		seen[k] = int(seen.get(k, 0)) + 1
		var nice := k.substr(0, 1) + k.substr(1).to_lower()
		out.append(nice if int(seen[k]) == 1 else "%s %d" % [nice, int(seen[k])])
	return out


## Is this breaker's load getting power right now?
func powered(name: String) -> bool:
	if lost.has(BREAKER_HOME.get(name, "")):
		return false
	return bool(_powered.get(name, false))


func load_kw(name: String) -> float:
	return float(_load_kw.get(name, 0.0))


func rcs_ok() -> bool:
	return c_rcs_mode > 0 and hyd > 0.5 and hyd_t > 275.0


func any_warning() -> bool:
	for a: String in alarms:
		if alarms[a] and ALARMS[a][1] and not silenced.get(a, false):
			return true
	return false


func any_caution() -> bool:
	for a: String in alarms:
		if alarms[a] and not ALARMS[a][1] and not silenced.get(a, false):
			return true
	return false


## Core temperature the reactor holds in AUTO, from the setpoint knob.
func temp_setpoint() -> float:
	return lerpf(600.0, 1300.0, c_rx_temp_set) if rx_mode == 0 else lerpf(1200.0, 2800.0, c_rx_temp_set)


func cabin_setpoint() -> float:
	return lerpf(291.0, 299.0, c_cab_set)


## Exhaust speed for the core's temperature now.
func exhaust_speed() -> float:
	return ENG_VE * sqrt(clampf(rx_t / RX_NOMINAL[1], 0.0, 1.08))


# --- Momentary controls ----------------------------------------------------------------

func press(button: String) -> void:
	match button:
		"rx_scram":
			rx_scrammed = true
			rx_rod = 0.0
			c_rx_auto = false
		"rx_reset":
			if c_rx_rods <= 0.01:
				rx_scrammed = false
		"torch_ignite":
			if torch_ready():
				torch_lit = true
		"torch_cut":
			torch_lit = false
		"eng_start":
			if c_eng_arm and powered("turbo") and c_h2_feed > 0.5:
				_turbo_starting = 18.0
		"cmg_desat":
			if rcs_ok():
				var used := cmg_h * 3.0
				hyd = maxf(hyd - used, 0.0)
				cmg_h = 0.0
		"silence":
			for a: String in alarms:
				silenced[a] = alarms[a]
		_:
			pass


## A torch transit takes its fuel up front.
func spend_dhe(kg: float) -> void:
	dhe = maxf(dhe - kg, 0.0)


## Running the torch flat out through a transit heats the loop like a long full burn.
func transit_heat(dt: float) -> void:
	loop_t += dt * TORCH_F * 0.25 / LOOP_HEAT_CAP


## Use RCS propellant for attitude or translation (impulse in N*s).
func spend_rcs(impulse: float) -> bool:
	if not rcs_ok():
		return false
	hyd = maxf(hyd - impulse / RCS_ISP_VE, 0.0)
	return true


## CMG momentum taken on by a slew (fraction of capacity).
func load_cmg(amount: float) -> void:
	cmg_h = clampf(cmg_h + amount, 0.0, 1.0)


# --- Simulation --------------------------------------------------------------------------

## Run quietly for a while so temperatures and charges start where a running station has them.
func settle(seconds: float) -> void:
	var keep := t
	var n := ceili(seconds / 2.0)
	# Warming the systems up to a steady state is not hours of running: no fuel burns, no wear.
	_settling = true
	for i in n:
		_step(2.0)
	_settling = false
	t = keep
	_update_alarms()


func tick(dt: float) -> void:
	if dt <= 0.0:
		return
	# Big steps are cut so each piece stays within its stable, accurate range.
	var steps := maxi(1, ceili(dt / 2.0))
	var h := dt / steps
	for i in steps:
		_step(h)
	_update_alarms()


func _step(dt: float) -> void:
	t += dt
	_electrical(dt)
	_reactor(dt)
	_thermal(dt)
	_life(dt)
	_propulsion(dt)


func _electrical(dt: float) -> void:
	# Mechanisms.
	arrays_deploy = move_toward(arrays_deploy, 1.0 if c_arrays else 0.0, dt / 60.0)
	rad_deploy = move_toward(rad_deploy, 1.0 if c_radiators else 0.0, dt / 90.0)
	# What each load wants.
	var want := {}
	want["lights"] = 1.6 if c_lights else 0.05
	want["fans"] = 0.6 if c_fans else 0.0
	want["water"] = 0.9 if c_water_rec else 0.0
	want["heater"] = 3.0 if c_heater else 0.0
	want["cabpump"] = 0.4 if c_cab_pump else 0.0
	want["rxpump"] = 6.0 * c_rx_pump
	want["rods"] = 0.3
	want["turbo"] = 12.0 if _turbo_starting > 0.0 else 0.2 * pump_spin
	want["cryo"] = 2.5 if c_cryo else 0.0
	want["nav"] = 0.5 if c_nav else 0.0
	want["tracker"] = 0.1 if c_tracker else 0.0
	want["cmg"] = 1.2 if c_cmg else 0.0
	want["rcsheat"] = (0.6 if hyd_t < 292.0 else 0.15) if c_rcs_heat else 0.0
	want["dish"] = 0.4 if c_dish else 0.0
	want["galley"] = 0.0
	want["lab"] = 1.0 if c_lab else 0.0
	want["torch"] = (40.0 if torch_field < 1.0 else 18.0) if c_torch_field else 0.0
	for k: String in extra_kw:
		want[k] = float(want.get(k, 0.0)) + float(extra_kw[k])
	# Shorted by a hit: out, however often it is pushed back in, until the hole is patched.
	for b: String in shorted:
		if brk.has(b):
			brk[b] = false
	# Breakers trip on overload.
	for b: String in BREAKERS:
		if brk[b] and float(want.get(b, 0.0)) > BREAKERS[b][2]:
			brk[b] = false
	# Sources.
	sol_kw = solar_max() * arrays_deploy * sun * solar_factor
	var gen := gen_kw if c_rx_turbine else 0.0
	var dem_a := 0.0
	var dem_b := 0.0
	for b: String in BREAKERS:
		if not brk[b]:
			continue
		if BREAKERS[b][1] == "A":
			dem_a += float(want.get(b, 0.0))
		else:
			dem_b += float(want.get(b, 0.0))
	var sup_a := gen if c_gen_a else 0.0
	var sup_b := sol_kw if c_sol_b else 0.0
	var bat_on_a := c_bat_a
	var bat_on_b := c_bat_b
	var ok_a := true
	var ok_b := true
	bat_kw = 0.0
	if c_tie:
		var r := _bus(sup_a + sup_b, dem_a + dem_b, bat_on_a or bat_on_b, dt)
		ok_a = r[0]
		ok_b = r[0]
		bus_a_v = r[1]
		bus_b_v = r[1]
	else:
		var ra := _bus(sup_a, dem_a, bat_on_a, dt)
		var rb := _bus(sup_b, dem_b, bat_on_b, dt)
		ok_a = ra[0]
		ok_b = rb[0]
		bus_a_v = ra[1]
		bus_b_v = rb[1]
	load_a_kw = dem_a if ok_a else 0.0
	load_b_kw = dem_b if ok_b else 0.0
	_load_kw.clear()
	_powered.clear()
	for b: String in BREAKERS:
		var on: bool = brk[b] and (ok_a if BREAKERS[b][1] == "A" else ok_b)
		_powered[b] = on
		_load_kw[b] = float(want.get(b, 0.0)) if on else 0.0


## One bus: sources, demand and maybe the battery. Returns [powered, volts].
func _bus(supply: float, demand: float, battery: bool, dt: float) -> Array:
	var net := supply - demand
	if battery:
		if net < 0.0:
			var draw := minf(-net, 60.0)
			if bat_kwh <= 0.0:
				draw = 0.0
			bat_kwh = maxf(bat_kwh - draw * dt / 3600.0, 0.0)
			bat_kw -= draw
			net += draw
		else:
			var put := minf(net, 40.0)
			if bat_kwh >= bat_cap():
				put = 0.0
			bat_kwh = minf(bat_kwh + put * dt / 3600.0 * 0.92, bat_cap())
			bat_kw += put
	if demand <= 0.01:
		return [supply > 0.0 or (battery and bat_kwh > 0.0), 124.0 if supply > 0.0 or (battery and bat_kwh > 0.0) else 0.0]
	var sag := 120.0 + clampf(net / maxf(demand, 1.0), -1.0, 0.05) * 80.0
	if net < -0.05:
		return [false, maxf(sag, 0.0)]
	return [true, minf(sag + (2.0 if battery else 0.0), 126.0)]


func _reactor(dt: float) -> void:
	# Mode changes only near zero power.
	if c_rx_mode != rx_mode and rx_power < 0.02:
		rx_mode = c_rx_mode
	var rated: float = RX_RATED[rx_mode]
	var nominal: float = RX_NOMINAL[rx_mode]
	if rx_jettisoned:
		rx_scrammed = false
		rx_power = 0.0
		rx_decay_w = 0.0
		rx_q_w = 0.0
		rx_t = lerpf(SINK_T, rx_t, exp(-dt / 100.0))
		gen_kw = 0.0
		rx_melt_t = INF
		return
	# The loop: a leak drains it, the FILL valve tops it up from the reserve.
	rx_coolant = maxf(rx_coolant - rx_leak * dt, 0.0)
	var flash := 0.0
	if c_rx_fill and rx_reserve > 0.0 and rx_coolant < 1.0:
		var add := minf(minf(dt * 0.01, 1.0 - rx_coolant), rx_reserve)
		# Cold coolant onto a dry, hot core flashes to steam all at once.
		if rx_coolant < 0.3 and rx_t > STEAM_T:
			flash = add * (rx_t - STEAM_T) * 1.2
		rx_coolant += add
		rx_reserve -= add
	# An open core head keeps the reactor shut down.
	if rx_head_open:
		rx_scrammed = true
	# Coolant available to carry heat away: as much as the pumps and the loop's fill allow.
	var pump := c_rx_pump if powered("rxpump") else 0.0
	var fill := clampf((rx_coolant - 0.2) / 0.6, 0.0, 1.0)
	var h_loop := LOOP_H * pump * fill
	var h_h2 := eng_mdot * H2_CP
	var flow_ok := (rx_mode == 0 and pump >= 0.2 and fill > 0.3) or (rx_mode == 1 and eng_mdot >= ENG_MDOT * 0.08)
	# The pumps wear as they run (worn out in a couple of hours), faster when pushed.
	if not _settling and pump > 0.01:
		rx_pump_wear = minf(rx_pump_wear + dt * (0.5 + pump) / 6000.0, 1.0)
	# Loop pressure: flowing, it sits near 1 MPa; stagnant in a hot core the coolant boils and
	# it climbs; dry, there is nothing left to press. RELIEF vents it (and the coolant with it)
	# above P_RELIEF; shut, nothing stops it bursting. The open head lets it all out.
	var pr_eq := 0.1
	if rx_head_open or rx_coolant < 0.05:
		pr_eq = 0.1
	elif flow_ok:
		pr_eq = 0.3 + 0.7 * clampf((rx_t - 400.0) / 725.0, 0.0, 2.0)
	else:
		pr_eq = 0.4 + 2.6 * clampf((rx_t - 600.0) / 500.0, 0.0, 3.0)
	rx_loop_p = lerpf(pr_eq, rx_loop_p, exp(-dt / 5.0)) + flash
	if c_rx_relief and rx_loop_p > P_RELIEF:
		var vent := minf(rx_loop_p - P_RELIEF, 2.0 * dt)
		rx_loop_p -= vent
		rx_coolant = maxf(rx_coolant - vent * 0.003, 0.0)
	if rx_loop_p > P_BURST and not _settling:
		explode("THE PRIMARY LOOP BURST")
	# Rods: driven toward the demand (or the auto controller), at the drive's speed.
	var target := c_rx_rods
	if c_rx_auto and not rx_scrammed:
		target = _auto_rods(h_loop, h_h2, rated, nominal)
	if rx_scrammed:
		target = 0.0
	if c_rx_interlock and not flow_ok:
		target = minf(target, 0.12)
	var rod_was := rx_rod
	if powered("rods") or target < rx_rod:
		rx_rod = move_toward(rx_rod, target, dt * (0.03 if rx_mode == 0 else 0.07))
	# Rods drawn out by hand at full speed put reactivity in faster than the core settles:
	# the power overshoots (AUTO never pulls them that hard).
	var prompt := 1.0
	if not c_rx_auto and rx_rod > rod_was and dt > 0.0:
		prompt = 1.0 + 8.0 * (rx_rod - rod_was) / dt
	# Power follows reactivity, which falls as the core runs hotter than designed.
	var feedback := 1.0 - 0.35 * clampf((rx_t - nominal) / nominal, -1.0, 1.0)
	var p_eq := pow(clampf((rx_rod - 0.1) / 0.75, 0.0, 1.4), 1.2) * feedback * fuel_reactivity() * prompt
	if rx_scrammed:
		p_eq = 0.0
	rx_power = lerpf(p_eq, rx_power, exp(-dt / 3.0))
	# Too much power for too long: the fuel vaporises and the core comes apart.
	if rx_power > EXCURSION_P:
		rx_excursion += dt
		if rx_excursion > EXCURSION_T and not _settling:
			explode("A POWER EXCURSION")
	else:
		rx_excursion = maxf(rx_excursion - dt, 0.0)
	# The fuel burns with the power made.
	for k in FUEL_SLOTS if not _settling else 0:
		if float(rx_fuel[k]) >= 0.0:
			rx_fuel[k] = minf(float(rx_fuel[k]) + dt * rx_power * float(SLOT_SHARE[k]) * (0.6 if rx_mode == 1 else 1.0) / FUEL_LIFE, 1.0)
	# Fission products keep heating a core after it is shut down.
	# (The small power core's share is larger and lasts longer; the propulsion core's is a
	# share of hundreds of megawatts, carried off by the cooldown bypass.)
	var decay_target := (0.06 if rx_mode == 0 else 0.02) * rx_power * rated
	if decay_target > rx_decay_w:
		rx_decay_w = lerpf(decay_target, rx_decay_w, exp(-dt / 60.0))
	else:
		rx_decay_w = lerpf(decay_target, rx_decay_w, exp(-dt / (1200.0 if rx_mode == 0 else 400.0)))
	rx_q_w = rx_power * rated + rx_decay_w
	# Core temperature: heat in, carried off by the loop, the hydrogen and a little radiation.
	# Passive cooling: the coolant standing in the core carries some heat off by itself; a dry
	# core only radiates, and its decay heat cooks it.
	var h_pass := 8.0 + 17.0 * clampf(rx_coolant / 0.5, 0.0, 1.0)
	var h_sum := h_loop + h_h2 + h_pass
	var t_eq := (rx_q_w + h_loop * loop_t + h_h2 * 30.0 + h_pass * 300.0) / h_sum
	rx_t = lerpf(t_eq, rx_t, exp(-dt * h_sum / RX_HEAT_CAP))
	loop_q_w = h_loop * maxf(rx_t - loop_t, 0.0)
	# Turbine-generator on the hot leg.
	if c_rx_turbine and rx_mode == 0 and rx_t > 800.0 and rx_t < 1450.0:
		var eff := 0.27 * clampf((rx_t - 800.0) / 350.0, 0.0, 1.0)
		gen_kw = minf(loop_q_w * eff / 1000.0, 110.0)
	else:
		gen_kw = 0.0
	var limit := 1500.0 if rx_mode == 0 else 2900.0
	if rx_t > limit:
		rx_damage = minf(rx_damage + dt * (rx_t - limit) / 2.0e5, 1.0)
	if rx_t > 1550.0 and rx_mode == 0 or rx_t > RX_MELT:
		# The safety system drops the rods on its own when the core is cooking.
		rx_scrammed = true
	# Too hot for too long and the core melts: the countdown runs while it is over the line
	# and stops once it is back under the safe one.
	if rx_t > float(MELT_START[rx_mode]):
		rx_melt_t = MELT_TIME if rx_melt_t == INF else maxf(rx_melt_t - dt, 0.0)
	elif rx_t < float(MELT_SAFE[rx_mode]):
		rx_melt_t = INF


## How much the fuel in the core can give (1 with three fresh assemblies, 0 when spent or
## empty): what is left of each, the burnt end of the cycle worth less than its share.
func fuel_reactivity() -> float:
	var k := 0.0
	for f: Variant in rx_fuel:
		if float(f) >= 0.0:
			k += pow(1.0 - float(f), 0.7)
	return k / FUEL_SLOTS


## How spent the load is on the whole (0..1), counting empty slots as spent.
func fuel_burnup() -> float:
	var b := 0.0
	for f: Variant in rx_fuel:
		b += float(f) if float(f) >= 0.0 else 1.0
	return b / FUEL_SLOTS


## Why the core head cannot be opened ("" when it can). The OVERRIDE lets it open anyway.
func head_blocker() -> String:
	if rx_jettisoned:
		return "NO REACTOR"
	if c_rx_override:
		return ""
	if rx_power > 0.01 or not rx_scrammed:
		return "SHUT THE REACTOR DOWN (SCRAM)"
	if rx_t > HEAD_COOL:
		return "CORE TOO HOT: %d K, WAIT FOR %d" % [roundi(rx_t), roundi(HEAD_COOL)]
	return ""


## Unseal the core head. Under a running or pressurised core (the interlock overridden) the
## head blows out and the core with it.
func open_head() -> void:
	rx_head_open = true
	if rx_power > 0.02 or rx_loop_p > 0.8 or rx_t > 1000.0:
		explode("THE CORE HEAD BLEW OUT")


## The reactor blows up: main tears the module off the station.
func explode(cause: String) -> void:
	if rx_jettisoned or rx_boom != "":
		return
	rx_boom = cause


## A module cast off (or blown away): what lived in it goes with it.
func lose(m: String) -> void:
	if lost.has(m):
		return
	# A module docked beyond the port goes with all docked beyond it. The list of modules aboard
	# is its record (not `lost`: the next one docked may well have the same name).
	var i := module_names(modules).find(m)
	if i >= 0:
		modules.resize(i)
		bat_kwh = minf(bat_kwh, bat_cap())
		if not modules.has("GREENHOUSE"):
			crop = 0.0
		return
	# (One beyond it, gone with it a moment ago.)
	for k: String in Universe.MODULE_KINDS:
		if m.begins_with(module_names([k])[0]):
			return
	lost.append(m)
	match m:
		"Reactor":
			rx_jettisoned = true
			rx_head_open = false
			rx_leak = 0.0
			rx_melt_t = INF
			rx_loop_p = 0.0
		"Life support":
			# The water tank was here.
			water = 0.0
		"Habitation":
			food = 0
			pills = 0
		"Stern":
			h2 = 0.0
			dhe = 0.0
			torch_lit = false
		"Dock":
			modules.clear()
			port_vol = 0.0
			port_p = 0.0


## AUTO: the rod position whose power would hold the core at the setpoint with today's
## cooling (a model-based controller: no hunting), plus a small trim on the error.
func _auto_rods(h_loop: float, h_h2: float, rated: float, nominal: float) -> float:
	var ts := temp_setpoint()
	var q_need := h_loop * (ts - loop_t) + h_h2 * (ts - 30.0) + (8.0 + 17.0 * clampf(rx_coolant / 0.5, 0.0, 1.0)) * (ts - 300.0) - rx_decay_w
	var p_need := maxf(q_need / rated, 0.0)
	var feedback := 1.0 - 0.35 * clampf((ts - nominal) / nominal, -1.0, 1.0)
	var rod := 0.1 + 0.75 * pow(p_need / maxf(feedback * fuel_reactivity(), 0.05), 1.0 / 1.2)
	rod += clampf((ts - rx_t) / nominal, -0.2, 0.2) * 0.3
	return clampf(rod, 0.0, 1.0)


func _thermal(dt: float) -> void:
	# Cabin: electrical loads end up as heat; the hull leaks a little to space; the cabin
	# loop pumps the rest to the radiators if they can take it.
	var cab_in := (load_a_kw + load_b_kw) * 0.85 * 1000.0 + 120.0 * metabolism
	if powered("heater"):
		cab_in += 3000.0
	var take := clampf((330.0 - loop_t) / 30.0, 0.0, 1.0)
	var cool := 0.0
	if powered("cabpump"):
		cool = clampf((cab_t - cabin_setpoint()) * 8000.0, 0.0, 25000.0) * take
	# A hole in the hull bleeds the warmth away (the air is made up; the heat is not).
	var k_hull := 80.0 + leak_area * HOLE_COLD
	var net := cab_in - cool - k_hull * (cab_t - 150.0)
	# Implicit in the hull leak and the controller's gain.
	var stiff := k_hull + (8000.0 * take if powered("cabpump") and cool > 0.0 and cool < 25000.0 * take else 0.0)
	cab_t += net * dt / (CABIN_HEAT_CAP + stiff * dt)
	# Radiator loop: waste heat from the generator side and the cabin, out to space.
	var waste := maxf(loop_q_w - gen_kw * 1000.0, 0.0) + cool
	var area := (0.08 + 0.92 * rad_deploy) * radiator_factor
	var t0 := loop_t
	var q_rad := RAD_K * area * (pow(t0, 4.0) - pow(SINK_T, 4.0))
	var d_rad := 4.0 * RAD_K * area * pow(t0, 3.0)
	var h_core := LOOP_H * (c_rx_pump if powered("rxpump") else 0.0)
	# The core's pull on the loop was counted in loop_q_w; linearise it as well.
	loop_t = t0 + dt * (waste - q_rad) / (LOOP_HEAT_CAP + dt * (d_rad + h_core * 0.2))
	loop_t = maxf(loop_t, SINK_T)


## The airlock's 8 m3 against the cabin's 300: what moves between them, and to space.
func _airlock(dt: float) -> void:
	var cab := pressure()
	if lock_inner_open:
		# One volume with the cabin; with the outer hatch open too, the station empties.
		lock_p = cab
		# Shut the outer hatch again and the leak is over (it used to go on for ever).
		leak_area_extra = 0.08 if lock_outer_open else 0.0
		return
	leak_area_extra = 0.0
	if lock_outer_open:
		lock_p = 0.0
		return
	if lock_valve == 1:
		lock_p = move_toward(lock_p, cab, dt * 25.0)
	elif lock_valve == 2:
		lock_p = move_toward(lock_p, 0.0, dt * 25.0)
	match c_lock_mode:
		1:
			# The pump draws the air back into the cabin, slower as the lock empties.
			if powered("fans"):
				var moved := minf(lock_p, dt * maxf(lock_p * 0.08, 0.6))
				lock_p -= moved
				_add_air(moved * 8.0 / 300.0)
		2:
			# To the cabin's pressure, whichever way: more than the cabin's goes back into it.
			var moved2 := clampf(cab - lock_p, -dt * 4.0, dt * 4.0)
			lock_p += moved2
			_add_air(-moved2 * 8.0 / 300.0)
	lock_p = maxf(lock_p, 0.0)


## The docking port's outer hatch and what is beyond it. Nothing docked: vacuum, and an open
## hatch empties the station. Something docked: open, it is one volume with the cabin; shut,
## PRESSURIZE fills it from the tanks, or the hatch's bleed valve lends it the cabin's air.
func _port(dt: float) -> void:
	var cab := pressure()
	if port_vol <= 0.0:
		port_p = 0.0
		leak_port = 0.08 if port_open else 0.0
		port_valve = false
		return
	leak_port = 0.0
	if port_open:
		# The cabin's 300 m3 and what is docked share their air at once.
		var p := (cab * 300.0 + port_p * port_vol) / (300.0 + port_vol)
		_add_air(p - cab)
		port_p = p
		port_valve = false
		return
	if port_valve:
		var moved := minf(cab - port_p, dt * 25.0)
		if moved > 0.0:
			port_p += moved
			_add_air(-moved * port_vol / 300.0)
		if absf(cab - port_p) < 0.5:
			port_valve = false
	if c_port_press and port_p < minf(cab, 101.0):
		port_p += minf(dt * PORT_FILL, minf(cab, 101.0) - port_p)


## Is the air either side of the docking port's outer hatch the same?
func port_equal() -> bool:
	return absf(port_p - pressure()) < 3.0


## The greenhouse's ripe trays into the galley's stores; returns how many.
func pick_crop() -> int:
	var n := int(crop)
	crop -= n
	food += n
	return n


## Air in (+) or out (-) of the cabin, in kPa of cabin pressure, mixed as the cabin is.
func _add_air(dp: float) -> void:
	var p := pressure()
	if p <= 0.0:
		return
	var k := 1.0 + dp / p
	pp_o2 *= k
	pp_n2 *= k
	pp_co2 *= k


var leak_area_extra := 0.0
## What damage leaves of the solar wings' output and the radiators' area (Damage sets them).
var solar_factor := 1.0
## Breakers shorted by a hit, held out until its hole is patched (Damage sets them).
var shorted: Array = []
## Warmth lost through hull breaches (W per kelvin per m2 of hole).
const HOLE_COLD := 1.5e5
var radiator_factor := 1.0


func lock_equal() -> bool:
	return absf(lock_p - pressure()) < 3.0


func _life(dt: float) -> void:
	_airlock(dt)
	_port(dt)
	var p := pressure()
	# Leaks take every gas in proportion.
	var holes := leak_area + leak_area_extra + leak_port
	if holes > 0.0 and p > 0.0:
		var f := exp(-dt * holes * 150.0 / 300.0)
		pp_o2 *= f
		pp_co2 *= f
		pp_n2 *= f
	# Breathing is a given and the air never runs out (the game's licence): it matters only as
	# pressure, for the hatches and the leaks, and life support makes up whatever leaks away.
	if pressure() < 101.0:
		var a := minf(AIR_MAKEUP * dt, 101.0 - pressure())
		pp_o2 += a * 0.21
		pp_n2 += a * 0.79
	dt *= LIFE_SCALE
	# The greenhouse under its grow lamps: food growing.
	var houses := modules.count("GREENHOUSE")
	if houses > 0 and powered("lights"):
		crop = minf(crop + dt * houses / CROP_TIME, CROP_MAX)
	# Washing and the recycler's losses (drinking is the keeper's own doing).
	var day_frac := dt / 86400.0
	water -= 1.0 * day_frac * (0.15 if powered("water") else 1.0)
	water = maxf(water, 0.0)


func _torch(dt: float) -> void:
	# The nozzle field comes up while its coils have power; without it the plasma has
	# nothing to push on and the torch goes out at once.
	if c_torch_field and powered("torch"):
		torch_field = move_toward(torch_field, 1.0, dt / FIELD_TIME)
	else:
		torch_field = move_toward(torch_field, 0.0, dt / 3.0)
	var was_lit := torch_lit
	if torch_lit and (torch_field < 0.95 or not c_torch_arm or dhe <= 0.0):
		torch_lit = false
	if was_lit and not torch_lit and (torch_field < 0.95 or dhe <= 0.0):
		_set_alarm("torch_out", true)
	var thr := clampf(c_torch_thr, 0.0, 1.0)
	torch_thrust = TORCH_F * thr if torch_lit else 0.0
	if torch_thrust > 0.0:
		dhe = maxf(dhe - torch_thrust / TORCH_VE * dt, 0.0)
		# Neutron and X-ray heat soaks into the structure and the loop.
		loop_t += dt * torch_thrust * 0.25 / LOOP_HEAT_CAP


func _propulsion(dt: float) -> void:
	_torch(dt)
	# Tank: helium keeps it pressed; without the cryocooler the hydrogen boils.
	if c_he_press and he > 0.0:
		var dp := clampf(0.25 - h2_p, 0.0, 0.05 * dt)
		h2_p += dp
		he = maxf(he - dp * 6.0, 0.0)
	if not powered("cryo") and h2 > 0.0:
		h2_p += dt * 2.0e-6
		if h2_p > 0.32:
			# Relief valve: the boil-off goes overboard.
			h2 = maxf(h2 - dt * 216.0 / 86400.0 * 1.0, 0.0)
			h2_p = 0.32
	# Turbopump: spun up by the start motor, kept turning by hot hydrogen off the core.
	var drive := rx_mode == 1 and rx_t > 900.0 and c_h2_feed > 0.5 and c_eng_arm
	if _turbo_starting > 0.0:
		_turbo_starting -= dt
		if powered("turbo"):
			pump_spin = move_toward(pump_spin, 1.0, dt / 15.0)
	elif drive and pump_spin > 0.6:
		pump_spin = move_toward(pump_spin, 1.0, dt / 5.0)
	else:
		pump_spin = lerpf(0.0, pump_spin, exp(-dt / 20.0))
	# Feed: suction needs tank pressure, or the pump cavitates.
	var inlet := clampf((h2_p - 0.12) / 0.06, 0.0, 1.0)
	fcv = move_toward(fcv, c_throttle if c_eng_arm else 0.0, dt * 0.06)
	var flow := fcv * pump_spin * c_h2_feed * inlet
	eng_mdot = ENG_MDOT * flow
	# The bypass bleeds a trickle through a shut-down core to carry its decay heat away.
	if c_cool_valve:
		eng_mdot += 0.6 * clampf(h2_p / 0.2, 0.0, 1.0)
	if h2 <= 0.0:
		eng_mdot = 0.0
	h2 = maxf(h2 - eng_mdot * dt, 0.0)
	if eng_mdot > 0.0:
		h2_p = maxf(h2_p - dt * eng_mdot * 2.0e-6, 0.0)
	thrust = eng_mdot * exhaust_speed()
	# RCS propellant: cold without its heaters.
	var hyd_eq := 292.0 if powered("rcsheat") else 205.0
	hyd_t = lerpf(hyd_eq, hyd_t, exp(-dt / (3600.0 * 6.0)))
	# The gyros soak up small disturbance torques until they saturate.
	if powered("cmg"):
		cmg_h = minf(cmg_h + dt * 1.0e-5, 1.0)


func _update_alarms() -> void:
	_set_alarm("rx_hot", rx_t > (1300.0 if rx_mode == 0 else 2800.0))
	_set_alarm("rx_scram", rx_scrammed)
	var pump := c_rx_pump if powered("rxpump") else 0.0
	_set_alarm("rx_flow", rx_power > 0.03 and ((rx_mode == 0 and pump < 0.2) or (rx_mode == 1 and eng_mdot < ENG_MDOT * 0.08 * rx_power)))
	_set_alarm("rx_melt", rx_melt_t != INF and not rx_jettisoned)
	_set_alarm("rx_cool", rx_coolant < 0.6 and not rx_jettisoned)
	_set_alarm("rx_fuel", fuel_reactivity() < 0.3 and not rx_jettisoned)
	_set_alarm("rx_wear", rx_pump_wear > 0.8 and not rx_jettisoned)
	_set_alarm("rx_shield", rx_shield < 0.7 and not rx_jettisoned)
	_set_alarm("rx_press", rx_loop_p > 2.8 and not rx_jettisoned)
	_set_alarm("rx_over", rx_power > 1.12 and not rx_jettisoned)
	_set_alarm("rx_mode", c_rx_mode != rx_mode)
	_set_alarm("bus_a", bus_a_v < 105.0)
	_set_alarm("bus_b", bus_b_v < 105.0)
	_set_alarm("bat_low", bat_kwh < bat_cap() * 0.2)
	_set_alarm("loop_hot", loop_t > 330.0)
	_set_alarm("cab_temp", cab_t < 288.0 or cab_t > 302.0)
	_set_alarm("press", pressure() < 90.0)
	_set_alarm("h2_press", c_eng_arm and h2_p < 0.18)
	_set_alarm("boiloff", h2_p >= 0.32)
	_set_alarm("cav", eng_mdot > 0.0 and h2_p < 0.16)
	_set_alarm("rcs_cold", hyd_t < 280.0)
	_set_alarm("cmg_sat", cmg_h > 0.85)
	# Deployed radiators and arrays take the torch's gentle push, not the main engine's shove.
	_set_alarm("rad_stow", accel > 0.62 and rad_deploy > 0.05)
	_set_alarm("arr_stow", accel > 0.62 and arrays_deploy > 0.05)
	if alarms["torch_out"] and torch_lit:
		_set_alarm("torch_out", false)
	_set_alarm("dhe_low", dhe < DHE_MAX * 0.1)
	var tripped := false
	for b: String in brk:
		if not brk[b]:
			tripped = true
	_set_alarm("trip", tripped)


func _set_alarm(code: String, on: bool) -> void:
	if alarms[code] == on:
		return
	alarms[code] = on
	if not on:
		silenced.erase(code)
	alarm.emit(code, on)


# --- Save --------------------------------------------------------------------------------

const SAVED := ["t", "rx_mode", "rx_rod", "rx_power", "fcv", "pump_spin", "rx_decay_w", "rx_t", "rx_scrammed", "rx_damage",
	"rx_fuel", "rx_head_open", "rx_coolant", "rx_reserve", "rx_leak", "rx_pump_wear", "rx_shield", "rx_melt_t", "rx_jettisoned",
	"rx_fresh", "rc_material", "rc_spent", "rx_loop_p", "rx_loose", "lost",
	"loop_t", "rad_deploy", "arrays_deploy", "bat_kwh", "cab_t", "pp_o2", "pp_co2", "pp_n2", "leak_area",
	"water", "food", "pills", "patches", "film", "lock_p", "modules", "crop", "h2", "h2_p", "he", "hyd", "hyd_t", "cmg_h", "dhe", "torch_field", "torch_lit"]


func to_dict() -> Dictionary:
	var d := {}
	for k: String in SAVED:
		d[k] = get(k)
	for p in get_property_list():
		var n: String = p.name
		if n.begins_with("c_"):
			d[n] = get(n)
	d["brk"] = brk.duplicate()
	return d


func from_dict(d: Dictionary) -> void:
	for k: String in d:
		if k == "brk":
			brk = (d[k] as Dictionary).duplicate()
		else:
			set(k, d[k])
