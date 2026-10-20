# Lantern: design

Rebuild started 2026-10-14. The previous prototype is kept under the git tag `legacy-v0`.

## Premise

You are the last person aboard **Lantern**, a research station-ship in orbit round Saturn.
The crew left on the return vehicle; you stayed. There is no station AI: only the station,
its panels, and a slow text link to the **Office** back home, which buys your science data
and ships supplies by drone while a relay can hear you.

Lantern can fly: a bimodal fission reactor, a nuclear thermal main engine for hard local
burns, a fusion torch for long crossings, attitude thrusters and gyros. Home is the real
Solar System; beyond it the stars are generated without end.

Everything (name, story, station, interface, text, art, sound) is made for this game, most
of it in code.

## Pillars

1. **You run the whole station by hand.** Switches, covers, breakers, knobs, levers and
   valves on physical panels; the procedures in a manual that floats about the cockpit
   (page one: bringing the station up from cold). No autopilot: the computer points the
   station and reads out, the keeper does everything else.
2. **Real space, played in real time.** Patched-conic orbits round real bodies; there is
   no time warp. Long trips are torch transits picked on the map: minutes inside a
   system, twenty to forty minutes between stars. One second of play is one minute of
   the keeper's day; only sleep runs the clock on (see Staying alive).
3. **Alone and fragile.** Hunger, thirst, sleep, fitness, radiation and cold. Breathing is
   a given (the game's licence): the air matters only as pressure, for hatches and leaks.
   The station breaks; you fix it, inside or out on the hose.
4. **The unknown out there.** Every star is a new system with planets, moons and rings to
   orbit and study. A pulsar is the first, and its timing is what opens the rest.

## Moving

- Inside: hands only. Hold LMB on a surface and the arm pulls you in to it; let go on the
  way and fly on. RMB pushes off. First-person look: yaw round the station's up, pitch
  limited, no roll.
- Screens are surfaces too: LMB on one pulls you in to it. E brings any screen up full size
  (ScreenView), live, through the same tube; the mouse is free there, and on the map a click
  picks a destination, a drag turns the view and the wheel zooms; CONTACTS beside it lists the
  derelicts and modules in the system, nearest first. E or Esc puts it away.
- The nav screen under the map ticks off the torch's steps for the destination picked (ARM,
  NOZZLE FIELD, IGNITE, THROTTLE, ENGAGE), with the fuel it takes and where the station is.
- Outside: hands along the hull, truss, tank and reactor, on a 60 m umbilical clipped on
  in the airlock with the button on its reel (there is no suit to put on); it stops you hard at its full
  length, the hand can take hold of it like any surface, and R hauls you back along it. The
  outer hatch has no interlock: open it with air in the airlock and the air, and you, go
  out with it.

## The station

| Module | What is there |
| --- | --- |
| Command deck | Flight panel flush in the floor (touch map, nav screen, ENGAGE), main engine and GNC panels, Fusion Torch and Star Navigation panels, the nine-window cupola |
| Engineering | Reactor, electrical, two breaker panels, thermal |
| Node | Hatchways to the Docking port (port) and Airlock (starboard) |
| Habitation | Galley, medical locker and screen, sleeping bag, photo board; the Science and Comms-and-Supply panels low on the walls |
| Life support | Life support and stores panels; the flare shelter; the reactor hatch, the JETTISON panel and the Geiger counter |
| Reactor | The shield wall with the core head, three fuel slots and a window on the core; CORE panel, two coolant pumps, the fresh fuel rack, the waste recycler |
| Dock | A short vestibule open to the Node; the port hatch (pressure interlock) and the DOCKING PORT panel |
| Airlock | Inner hatch with an interlock, outer hatch without one, bleed valves, pump panel, the umbilical reel (solid) with its CLIP ON button |

Outside, a compact slim stack: the round modules, two sun-tracking solar wings on a mast
over Engineering, four folding radiators off Life support, the dish under the Node, yellow
EVA handrails. No truss, tank or engine: the station flies by the game's own licence. The
cabin lamps light the cabin only (their own render layer), never the hull outside.

## The reactor

One fission core in its own module aft of Life support makes the electricity and drives the
main engine. Its three fuel assemblies burn out in about an hour of play. Refuelling is by
hand: SCRAM, let the core cool below 650 K, unseal the core head, pull each assembly (hot:
the dose climbs while one is out, and one in the arms counts), carry it to the recycler,
push a fresh one home from the rack, seal and restart. Fresh fuel comes from the rack, the
supply catalogue, fuel depots, or the recycler (two spent assemblies and material).

The recycler takes anything let go over its hopper and makes what its OUTPUT selector asks:
water, a patch kit, film, coolant, a fuel assembly.

Things go wrong, more often the more worn the pumps are: coolant leaks (patch, then FILL from
the reserve), pump trips, false SCRAMs, a cracked shield that turns the room hot. A core too
hot for too long runs a 150 s melt clock; brought back under the safe line it stops. If it
cannot be, shut the hatch and JETTISON the module: the station lives on batteries and solar
alone. Otherwise the meltdown ends the game.

Carelessness blows it up: rods drawn out by hand on a cold core (a power excursion past
130 % for three seconds), the pumps stopped on a hot core with RELIEF shut (the loop bursts at
4 MPa), FILL opened on a dry core over about 1000 K (a steam flash), or the core head opened
with the HEAD LOCK switch beside it on FREE, on a hot or pressurised core. The blast tears the module off, holes Life
support, and fills the station with a short radioactive cloud; anyone in the module dies.
`tools/rxcheck.gd` plays each accident through the sim.

A hand-held Geiger counter (Life support, by the reactor hatch) clicks for the dose rate where
it is and reads it out in mSv/h.

## Module separation

Every module is built under its own node, so any of them can be cast off from the MODULE
SEPARATION panel overhead in the command deck (arm, then separate, both guarded). A module
goes with everything that hangs beyond it: the Node takes the airlock and the docking port with
all docked there, a docked module those beyond it (its hatch, not a blast seal, shuts the way),
Habitation takes Life support, the reactor and the stern (truss, tank, engines, fuel). A blast
seal shuts the hatchway left open; the loads and stores that lived there are lost
(`ShipSim.lose`). Never with the keeper inside; the command deck never goes.

## Systems

`scripts/sim/`: `ship_sim.gd` (reactor, buses, thermal, life support sixty times life
speed, airlock, propulsion, torch), `flight.gd` + `orbit.gd` (orbits, attitude, plans,
transits), `universe.gd` (the Solar System and generated systems), `galaxy.gd` (stars by
sector round the Sun), `body.gd`, `suit.gd`, `science.gd`, `damage.gd`, `events.gd`,
`story.gd`. All pure data, ticked with game time, checked by `--selftest`.

## Staying alive

Hunger, thirst, fatigue, radiation dose and sickness, and the cabin's warmth. Oxygen is a
given and the air never runs out: nobody suffocates, there is no oxygen plant, scrubber or
air tank to run; life support makes up whatever leaks (only a big hole outruns it). Sleep in the bag in Habitation: two to nine hours by how tired you are, passed
in a few real seconds while the station runs on at full speed. Not hungry, thirsty or with
alarms going; an alarm, a bang on the hull, a flare warning, hunger or the end of a transit
wakes you early. Too tired for too long and you pass out where you are.

## Science and supplies

Spectrometer (get close), magnetometer (in orbit, boom out), telescope (point at it),
particle counter (anywhere). Novelty pays; the Solar System pays half. Data is sent through
a relay for credit; credit buys rations, water, pills, D-He3, hydrogen, hydrazine,
patch kits, film and fuel assemblies, delivered by drone to the airlock's cargo port as a crate to unpack.

## Salvage

Abandoned modules (cargo modules, fuel depots, survey tenders, hab modules, relay pods) ride
round planets and moons, five in the Solar System and one or two in every other system, each
with a load fixed by its seed and class. A map transit stops beside one; the DOCKING PORT
panel docks it at the port off the Node. It is airless: the port hatch will not open on it
until PRESSURIZE has filled it (or the hatch's bleed valve has lent it
the cabin's air). Inside, dark but for a blinking red lamp, the things are strapped to the
walls; taken, they go into the stores. Nothing flies while one is docked, and it cannot be let
go with the port hatch open; undocked, it drifts back to its orbit with its air, and what was
taken stays taken.

## Docking modules

Whole modules wait in orbit too, sealed and lit: a greenhouse round Enceladus, an observatory
round Europa, a power module round Phobos, and now and then one round a planet of another
system. Docked at the port, a module is the station's for good (`PortModules`): air, lamps,
its own fittings, and a hatch and berthing ring at its far end, which is the port from then
on, so modules dock on one after another. It is gone from the map.

- **Greenhouse**: grow trays under magenta lamps; a tray of food every two hours of the
  keeper's day (picked by hand into the galley).
- **Power module**: four cell banks, +200 kWh of battery, and its own wings under the keel
  for +5 kW.
- **Observatory**: windows in the floor, a telescope on the wall; every scan worth half as
  much again.

## Events

Micrometeoroids (hull breaches: the air is made up, but the station grows cold until the hole
is patched, and the hit often shorts the gear beside it, its breaker held out until then;
broken parts outside), solar flares with a minute's warning
(shelter in Life support), equipment faults (breakers trip), reactor trouble (coolant
leaks, pump trips, false SCRAMs, a cracked shield), and the Office's messages at the
milestones of the journey.

## Endings

- **Come home**: after five star systems, back in orbit round Earth.
- **Beyond the horizon**: too close to a black hole to come back.
- **A lantern among the stars**: after twelve systems, sign off and go on.
- **Meltdown**: the core melts through and takes the station with it.
- And every way to die.

## Look

A working station years out: dark painted metal, grime, warm dim lamps with hard shadows,
haze in the air, green CRT screens glowing onto their panels, chunky pixels with ordered
dithering and film grain, PSX-sharp: each big pixel is the average of the frame under it,
so edges stay hard and distant lettering still reads. Round hatches and hatchways. The hand
cursors are drawn flat in the same pixels. No suit, no helmet frame over the view. No clutter: the walls carry the
panels, the safety posters and the pipe runs in the corners, and the only loose things are the
ones that do something (the manual, the camera and its prints, the Geiger counter, fuel).

## Status (2026-10-20)

All of the above is built and covered by `--selftest`. Next: polish from play-testing,
then (with the user's go-ahead) publishing.
