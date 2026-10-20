class_name Manual
extends RefCounted
## The station manual: a booklet that floats about the command deck (and the reactor manual, a
## yellow one in the reactor module). Catch it and it opens in
## your hand; the wheel turns its pages. Page one is how to bring the station up from cold,
## step by step; the rest are the procedures for everything else aboard.

## [title, [steps...]] per page; the cover has no steps but the contents.
const PAGES := [
	["WAKING THE STATION", [
		"Engineering, REACTOR panel: REACTOR MODE to POWER, ROD CONTROL to AUTO, LOOP PUMP a quarter up, TURBINE to RUN.",
		"ELECTRICAL POWER: GENERATOR > A, BATTERY > A, SOLAR > B and BATTERY > B all to CLOSE. CABIN LIGHTS on.",
		"Both CIRCUIT BREAKERS panels: push in every breaker that has popped out.",
		"THERMAL CONTROL: RADIATORS to DEPLOY, CABIN LOOP on; HEATERS on if the cabin is cold.",
		"Life support module, LIFE SUPPORT panel: CABIN FANS and RECYCLER on.",
		"ELECTRICAL POWER: ARRAYS to DEPLOY. The wings turn to the Sun by themselves.",
		"Command deck, GNC panel: NAV COMPUTER, STAR TRACKER and CMG on, RCS HEATERS on, RCS MODE to ATT.",
		"Flight panel (in the command deck floor): MASTER WARN and MASTER CAUT should be dark. If one is lit, its panel shows why.",
	]],
	["TO A PLANET", [
		"Command deck, right-hand wall: the FUSION TORCH panel. Lift the red cover, TORCH ARM to ARM.",
		"NOZZLE FIELD on and wait about 40 seconds: the FIELD bar fills and the green READY lamp lights.",
		"Press IGNITE. The torch is burning, but there is no thrust yet.",
		"Flight desk in the command deck floor: E on the map, then click the planet or moon you want. The map shows the distance, the flight time and the D-He3 the trip takes.",
		"TORCH THROTTLE lever all the way up.",
		"Press ENGAGE on the flight desk. The station turns, speeds up and brakes into orbit round the target by itself: a minute to forty minutes within a system.",
		"Arrived: throttle down, CUT OFF, NOZZLE FIELD off, TORCH ARM to SAFE.",
	]],
	["FUSION TORCH 1/2: LIGHTING IT", [
		"Command deck, right-hand wall: the FUSION TORCH panel. D-HE3 must not be empty.",
		"The torch's field coils draw 50 kW: the reactor running, or charged batteries (ELECTRICAL POWER).",
		"Lift the red cover. TORCH ARM to ARM.",
		"NOZZLE FIELD to ON. The FIELD bar fills in about 40 seconds.",
		"FIELD full: the green READY lamp lights.",
		"Press IGNITE. It stays lit green: the torch is burning, but gives no thrust until the throttle comes up.",
	]],
	["FUSION TORCH 2/2: FLYING", [
		"Flight desk, in the command deck floor: E on the map brings it up full size. Click a planet or moon to pick it: the map centres on it, and the wheel zooms in on it. Dragging turns the view. E again puts it away.",
		"The map shows the distance, the flight time and the D-He3 the trip takes. The nav screen under it ticks off the torch's steps as you go.",
		"Seen full size, the map has CONTACTS beside it: the derelicts and modules here, nearest first. Click one to pick it.",
		"FUSION TORCH panel: TORCH THROTTLE lever all the way up.",
		"Flight desk: press ENGAGE. The station turns, burns and brakes into orbit by itself.",
		"ENGAGE stays dark? The map says why: TORCH NOT LIT, THROTTLE TO FULL, NOT ENOUGH D-HE3, UNDOCK FIRST.",
		"To stop on the way: BREAK OFF, or the throttle down.",
		"Arrived: throttle down, CUT OFF, NOZZLE FIELD to OFF, TORCH ARM to SAFE.",
	]],
	["TO THE STARS", [
		"Wheel the map out past the edge of the system: the star map.",
		"Only the systems you have been to are charted. The rest is dark.",
		"The nearest pulsar shows through the dark as RADIO PULSES.",
		"Touch a charted star, or anywhere in the dark: the computer plots a course for the star nearest that point. What it is, you find out when you get there.",
		"Light the torch (FUSION TORCH pages), throttle up, then ENGAGE. A crossing takes twenty to forty minutes.",
		"Past 10 light years you need a pulsar timing fix: STAR NAVIGATION panel, in a pulsar system.",
	]],
	["NUCLEAR ENGINE 1/2: READYING", [
		"The MAIN ENGINE pushes hydrogen through the reactor core. The reactor must be running first (reactor manual).",
		"THERMAL CONTROL: RADIATORS to STOW. ELECTRICAL POWER: ARRAYS to STOW.",
		"Command deck, lower right wall: MAIN ENGINE panel. H2 CRYOCOOLER and HE PRESS to ON.",
		"Wait for TANK PRESS to reach about 250 kPa.",
		"Hold LMB on the H2 FEED valve until it is fully open.",
		"Engineering, REACTOR panel: ROD CONTROL to MAN, ROD DEMAND to 0. Wait for FISSION POWER to read 0.",
		"REACTOR MODE to PROP. MODE INHIBIT goes out once the power is down.",
	]],
	["NUCLEAR ENGINE 2/2: THE BURN", [
		"Be quick: the core must still be hot, above 900 K (CORE K on the MAIN ENGINE panel).",
		"Lift the cover, ENGINE ARM to ARM. Press TURBO START: TURBOPUMP climbs for 18 seconds.",
		"REACTOR panel: ROD CONTROL to AUTO.",
		"MAIN ENGINE: THROTTLE up slowly. Hydrogen flows, the rods come out, THRUST climbs.",
		"To stop: COOLDOWN BYPASS to OPEN first, then THROTTLE down, ENGINE ARM to SAFE.",
		"Back to power: ROD DEMAND to 0, wait for zero power, REACTOR MODE to POWER, then COOLDOWN BYPASS to SHUT.",
		"RADIATORS and ARRAYS to DEPLOY again.",
	]],
	["AIRLOCK OUT", [
		"At the hose reel by the outer hatch, press CLIP ON: 60 m of hose holding you to the station.",
		"Close the inner hatch (hold LMB on its handwheel).",
		"AIRLOCK panel: PUMP to DEPRESS, wait for VACUUM.",
		"Turn the outer hatch wheel. It has no interlock: never open it with air in the airlock.",
		"Outside: pull yourself along the hull or the hose itself. Hold R to haul yourself back.",
	]],
	["AIRLOCK IN", [
		"Close the outer hatch.",
		"PUMP to REPRESS until EQUAL lights.",
		"Open the inner hatch.",
		"Press the reel's button again to unclip. Going on into the Node, the hose stays on its reel by itself.",
	]],
	["HULL BREACH", [
		"Listen for the hiss and find the hole.",
		"Hold LMB on it with patch kits aboard.",
		"Until it is patched the station grows cold (CABIN TEMP; cold harms you in the end).",
		"The hit may have shorted the gear beside it: that breaker will not stay in until the hole is patched.",
		"Life support makes up the air that leaks: only a big hole (both airlock hatches open) outruns it.",
		"With both airlock hatches open the station empties: shut the outer one.",
	]],
	["SCIENCE AND SUPPLIES", [
		"Habitation, low on the walls: the SCIENCE panel. LAB POWER on. Pick a target on the map.",
		"Spectrometer: get close. Magnetometer: orbit it, boom out. Telescope: ATTITUDE to TARGET.",
		"COMMS AND SUPPLY: DISH on, UPLINK to SEND. A relay must be in range.",
		"Spend the credit on the same panel. A drone brings the order.",
		"When the drone is alongside, open the CARGO PORT on the same panel. It docks at the airlock and leaves the crate inside: hold LMB on it to unpack.",
	]],
	["SALVAGE", [
		"Derelicts drift round some planets and moons: the small squares on the map, shown once you zoom in close to their world (click it, then the wheel). Pick one and fly to it like any body; the station stops some seventy metres off it.",
		"The Node, port side: the DOCKING PORT panel. IN RANGE lights for one near. Shut the port hatch and press DOCK: it comes in and DOCKED lights.",
		"It has no air. PRESSURIZE on until EQUAL lights, or bleed the cabin's own air into it with the small valve under the wheel. Until then the port hatch stays shut.",
		"Inside it is dark: a torch or the helmet lamp (F). Hold LMB on a thing to take it into the stores: water, rations, fuel, patch kits, medicine, film.",
		"Shut the port hatch, then UNDOCK (lift the cover). Anyone still inside goes with it, and so does its air. An empty one is crossed out on the map. Nothing flies while one is docked.",
	]],
	["DOCKING MODULES", [
		"Whole modules wait in orbit too, sealed and lit: a greenhouse round Enceladus, an observatory round Europa, a power module round Phobos, now and then one round a far planet. A square with a bar on the map.",
		"Fly to one and DOCK it at the DOCKING PORT like a derelict. Once in, it is part of the station for good, with its air and lamps, and it is gone from the map.",
		"Its far hatch is the port from then on: the next one docks there. The hatches between modules are free; the last one holds the vacuum.",
		"GREENHOUSE: a tray of food every two hours under its grow lamps (hold LMB on the floor tray to pick).",
		"POWER MODULE: 200 kWh more battery, 5 kW from its own wings. OBSERVATORY: every scan worth half as much again.",
	]],
	["THE REACTOR", [
		"The reactor has a manual of its own: the yellow book in the reactor module, aft of Life support.",
		"Start-up, running, refuelling, the loop, the alarms, and what blows a reactor up are all in it. Read it before you touch the rods.",
		"A Geiger counter waits by the reactor hatch. Take it with you.",
	]],
	["MODULE SEPARATION", [
		"Overhead in the command deck. MODULE picks one; lift the cover, ARM; lift the cover, SEPARATE.",
		"It goes, and all that hangs beyond it: the screen lists what. A blast seal shuts the hatchway left open.",
		"Habitation takes Life support, the reactor, the engines and the fuel with it. The Node takes the airlock and the docking port too, and all docked there.",
		"Never with you inside what goes. What was in it, stores and all, is gone for good.",
	]],
	["STAYING ALIVE", [
		"Habitation: eat and drink at the galley, pills and dressings at the medical locker.",
		"Sleep in the bag when you are tired: the hours go by fast; an alarm wakes you.",
		"Solar flare warning: get to the Life support module and stay there until it passes.",
	]],
	["THE CAMERA", [
		"The instant camera floats in Habitation. Catch it, aim, press E.",
		"Out comes a print. Catch it, carry it to the board in Habitation and let go of it there: it pins up.",
		"A pack holds ten shots. More film comes from the supply catalogue.",
	]],
]


## The reactor's own manual: the yellow book in the reactor module.
const REACTOR_PAGES := [
	["THE PLANT", [
		"One fission core makes the station's electricity (POWER mode) and drives the main engine (PROP mode).",
		"Engineering, REACTOR panel: the mode, the rods, the core and the turbine. The reactor module aft of Life support: the core itself behind its shield, the CORE and LOOP PRESSURE panels, the pumps, the fuel rack, the recycler.",
		"The core holds three fuel assemblies. A load lasts about an hour of running.",
		"Everything here can kill you, and most of it the station too. Go slowly.",
	]],
	["START-UP 1/2: CHECKS", [
		"Engineering, right-hand wall: the REACTOR panel. Both CIRCUIT BREAKERS panels: ROD DRIVE and RX PUMP pushed in.",
		"Reactor module, CORE panel: coolant above 60 %. If not, FILL to OPEN until it is, then SHUT.",
		"Reactor module, LOOP PRESSURE panel: RELIEF to AUTO.",
		"Beside the core head: HEAD LOCK to LOCKED. The core head sealed.",
		"REACTOR panel: REACTOR MODE to POWER. FLOW INTERLOCK to NORM.",
	]],
	["START-UP 2/2: BRINGING IT UP", [
		"ROD DEMAND to 0 (turn the knob with the wheel). Press SCRAM RESET: the SCRAM lamp goes out.",
		"LOOP PUMP to a quarter or more. Under a fifth the core counts as uncooled and the rods stay in.",
		"TEMP SET to about three quarters: SET K reads about 1100.",
		"ROD CONTROL to AUTO. ROD POS climbs slowly, FISSION POWER and CORE TEMP follow.",
		"CORE TEMP above 800 K: TURBINE to RUN.",
		"ELECTRICAL POWER: GENERATOR > A to CLOSE. GEN kW shows what it makes.",
		"Never pull the rods out by hand on a cold core: see WHAT BLOWS IT UP.",
	]],
	["RUNNING", [
		"AUTO holds the temperature as the fuel burns down. FUEL LOW: refuel within minutes.",
		"Keep an eye on PUMP WEAR (CORE panel): service a pump before it reaches 80 %. Hold LMB on it.",
		"Coolant under 60 %: COOLANT LOW. Find the leak, seal it, then FILL.",
		"Do not stand in the reactor module longer than you need to. The dose there is on the CORE panel.",
	]],
	["SHUTDOWN AND COOLDOWN", [
		"Press SCRAM (lift its cover): the rods drop at once and FISSION POWER falls to 0.",
		"The heat stays: DECAY kW. Leave the LOOP PUMP running until CORE TEMP is under 650 K.",
		"TURBINE to TRIP when GEN kW reaches 0.",
		"To restart: ROD DEMAND to 0, SCRAM RESET, ROD CONTROL to AUTO (START-UP 2/2).",
	]],
	["REFUELLING", [
		"SCRAM. Wait for the core to cool below 650 K.",
		"Reactor module: hold LMB on the core head to unseal it. The room is hot while it is open: be quick.",
		"Hold LMB on a slot to pull its assembly. It is hot: carry it straight to the recycler's hopper and let go there.",
		"Take a fresh one from the rack (right wall), let go of it over the empty slot. All three.",
		"Seal the head, then restart. More fuel: the supply catalogue, fuel depots, or the recycler.",
	]],
	["THE LOOP", [
		"The primary loop carries the core's heat to the turbine. Its pressure is on the LOOP PRESSURE panel: about 1 MPa running.",
		"Pumps stopped on a hot core: the coolant boils and the pressure climbs. RELIEF on AUTO vents it above 3.2 MPa, and some coolant with it.",
		"A leak hisses from a line on the floor. Seal it with a patch kit, then FILL (CORE panel) until the loop is full.",
		"A dry core must cool below 1000 K before you FILL it.",
	]],
	["ALARMS", [
		"RX OVERTEMP / CORE FLOW: the core is too hot or not cooled. Pumps, coolant, or SCRAM.",
		"COOLANT LOW: a leak. LOOP PRESSURE: pumps stopped or a dry core being filled. Get flow back.",
		"RX POWER HIGH: SCRAM now, not in a moment.",
		"CORE MELT: the MELT IN clock runs. Get the core under the line and it stops. If not: CASTING IT OFF.",
		"PUMP WEAR, FUEL LOW, SHIELD: service, refuel, patch.",
	]],
	["WHAT BLOWS IT UP", [
		"Rods drawn out by hand (ROD CONTROL to MAN) all the way on a cold core: the power runs away in seconds.",
		"The pumps stopped with the core making heat and RELIEF shut: the loop bursts at 4 MPa.",
		"FILL opened on a dry core above 1000 K: the coolant flashes to steam.",
		"The core head opened with its HEAD LOCK switch on FREE while the core is hot or pressurised.",
		"The blast tears the module off and holes Life support. Inside the module, nobody lives through it.",
	]],
	["PROPULSION MODE", [
		"In PROP the reactor heats hydrogen for the MAIN ENGINE instead of making power: the steps are in the station manual, NUCLEAR ENGINE.",
		"The hydrogen is the coolant now: no flow, no cooling. The FLOW INTERLOCK keeps the rods in until it flows.",
		"After the burn: COOLDOWN BYPASS open before the throttle comes down.",
	]],
	["RADIATION", [
		"Through the shield while it runs: a few mSv/h in the module. With the head open: hundreds.",
		"A spent assembly in your arms is a source of its own. A cracked shield (it glows green) makes the whole room hot: patch it.",
		"The Geiger counter clicks for the dose where it is. A crackle means leave.",
		"Rad pills in the medical locker. The dose does not wash out.",
	]],
	["THE RECYCLER", [
		"Reactor module, right wall. Let go of a spent assembly over its hopper (old prints go in too).",
		"OUTPUT picks what to make: oxygen, water, a patch kit, film, coolant, a fuel assembly. PROCESS makes it.",
		"Two spent assemblies and enough material make a fresh one.",
	]],
	["CASTING IT OFF", [
		"When the core cannot be saved: get out of the module and shut the reactor hatch.",
		"Life support, by the hatch: lift the cover and press JETTISON. Or MODULE SEPARATION in the command deck.",
		"The module goes for good: batteries and the solar arrays only from then on.",
	]],
]

## Each book: [cover title, pages, cover colour, name on the prop].
const BOOKS := {
	"station": ["STATION MANUAL", PAGES, Color(0.82, 0.42, 0.12), "Station manual"],
	"reactor": ["REACTOR MANUAL", REACTOR_PAGES, Color(0.92, 0.74, 0.12), "Reactor manual"],
}


static func pages(book := "station") -> Array:
	return BOOKS.get(book, BOOKS["station"])[1]


static func title(book := "station") -> String:
	return BOOKS.get(book, BOOKS["station"])[0]


static func count(book := "station") -> int:
	return pages(book).size() + 1


## The mesh of the booklet: a cover with its title, the pages' edge, a spine.
static func make_prop(book := "station") -> Prop:
	# A ring-bound flight book: two stiff covers, the page block between them, binder rings
	# through the spine, steel corners, coloured section tabs, a tether eyelet.
	var root := Node3D.new()
	var cover := Geo.Builder.new()
	cover.bevel = 0.003
	for zc in [0.0095, -0.0095]:
		cover.box(Vector3(0.002, 0, zc), Vector3(0.17, 0.235, 0.004))
	cover.box(Vector3(-0.084, 0, 0), Vector3(0.006, 0.235, 0.023))
	Kit.mesh(root, cover.commit(Looks.panel(BOOKS[book][2], 0.6)), null)
	# A band across the front cover.
	Kit.mesh(root, Kit.box(Vector3(0.166, 0.03, 0.001)), Kit.matte(Color(0.12, 0.1, 0.09), 0.7), Vector3(0.002, -0.035, 0.0118))
	Kit.mesh(root, Kit.box(Vector3(0.156, 0.226, 0.015)), Kit.matte(Color(0.9, 0.87, 0.78), 0.9), Vector3(0.005, 0, 0))
	var steel := Geo.Builder.new()
	for k in 3:
		var y := -0.08 + k * 0.08
		for f in 10:
			var a0 := PI * f / 10.0 - PI / 2.0
			var a1 := PI * (f + 1) / 10.0 - PI / 2.0
			steel.cylinder(Vector3(-0.072 - cos(a0) * 0.016, y, sin(a0) * 0.016), Vector3(-0.072 - cos(a1) * 0.016, y, sin(a1) * 0.016), 0.0025, 5)
	for sy in [-1.0, 1.0]:
		steel.box(Vector3(0.081, sy * 0.111, 0.0), Vector3(0.012, 0.016, 0.025))
	steel.cylinder(Vector3(-0.084, 0.122, 0), Vector3(-0.084, 0.13, 0), 0.008, 10)
	Kit.mesh(root, steel.commit(Kit.metal(Color(0.7, 0.71, 0.73), 0.3, 0.9)), null)
	var tabs := [Color(0.85, 0.2, 0.15), Color(0.2, 0.55, 0.85), Color(0.25, 0.7, 0.3), Color(0.95, 0.8, 0.2)]
	for k in tabs.size():
		Kit.mesh(root, Kit.box(Vector3(0.012, 0.022, 0.002)), Kit.matte(tabs[k], 0.7), Vector3(0.087, 0.075 - k * 0.04, 0.004 - k * 0.003))
	var t := Ctl.text(root, Loc.t(String(BOOKS[book][0])).replace(" ", "\n"), Vector3(0.008, 0.05, 0.0125), 0.018, Color(0.08, 0.05, 0.02))
	t.name = "Title"
	# Kept on the cover whatever the language.
	Ctl.fit(t, 0.14, 0.11)
	var t2 := Ctl.text(root, "LANTERN", Vector3(0.008, -0.08, 0.0125), 0.011, Color(0.08, 0.05, 0.02))
	t2.name = "Name"
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.17, 0.235, 0.03)
	var p := Prop.make("manual", String(BOOKS[book][3]), root, shape, 0.4)
	p.set_meta("page", 0)
	p.set_meta("book", book)
	if book == "reactor":
		# The trefoil on the cover.
		var tre := Geo.Builder.new()
		for k in 3:
			var a := TAU * k / 3.0 + PI / 2.0
			for f in 6:
				var a0 := a - 0.5 + f / 6.0
				var a1 := a - 0.5 + (f + 1) / 6.0
				var c0 := Vector3(cos(a0), sin(a0), 0)
				var c1 := Vector3(cos(a1), sin(a1), 0)
				tre.tri(c0 * 0.012, c0 * 0.032, c1 * 0.032, Vector3.BACK)
				tre.tri(c0 * 0.012, c1 * 0.032, c1 * 0.012, Vector3.BACK)
		tre.cylinder(Vector3(0, 0, -0.0005), Vector3(0, 0, 0.0005), 0.008, 12)
		var tm := Kit.mesh(root, tre.commit(Kit.matte(Color(0.08, 0.07, 0.05), 0.7)), null)
		tm.position = Vector3(0.008, -0.075, 0.0122)
	return p
