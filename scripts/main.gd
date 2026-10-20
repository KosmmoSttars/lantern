extends Node3D
## Lantern: wires the systems sim, the flight, the station, the keeper and the view
## together; runs the title screen, time compression, saves and the screenshot tour.
##
## Command line (after `--`):
##   --new          skip the title screen, start a new game
##   --shots        save screenshots from fixed viewpoints to screenshots/ and quit
##   --menu-shots   save screenshots of the title, settings pages and pause menu, and quit
##   --seed N       universe seed for a new game

const SAVE_PATH := "user://save.cfg"

static var boot := ""

var sim: ShipSim
var universe: Universe
var galaxy: Galaxy
var body: Body
var habitat: Habitat
var science: Science
var lab: Lab
var suit: Suit
var airlock: AirlockFit
## The docking port off the Node, and the modules docked there for good.
var dock: DockFit
var port_modules: PortModules
## The reactor module's fittings, and the module itself drifting away once cast off.
var reactor: ReactorBay
var geiger: Geiger
var flashlight: Flashlight
## Modules cast off and drifting away: [{node, t, v (m/s), spin (rad/s)}].
var _casts: Array = []
var separation: SeparationPanel
## Seconds left of the radiation from a reactor blast spreading through the station.
var _blast_t := 0.0
var damage: Damage
var damage_view: DamageView
var events: Events
var story: Story
var flight: Flight
var space: Space
var station: Station
var panels: StationPanels
var player: Player
var hud: Hud
var menu: Menu
var post: Post
## A screen brought up full size (E).
var screen_view: ScreenView
var music: Music

var playing := false

var _args := PackedStringArray()
var _screens_t := 0.0
var _screens_sep := 0.0
var _save_t := 0.0
var _alarm: AudioStreamPlayer
var _hum: AudioStreamPlayer
var _burn: AudioStreamPlayer
var _jump_t := -1.0
## Sleeping: seconds into the dark (-1 = awake). Dead: seconds since.
var _sleep_t := -1.0
## Sleep under way: game-seconds of it still to pass, how long it was meant to be, the
## fatigue it started from, and what woke the keeper early ("" if nothing yet).
var _sleep_left := 0.0
var _sleep_plan := 0.0
var _sleep_fat0 := 0.0
var _wake := ""
var _was_transit := false
var _was_leaking := false
## Seconds before the hose's full-length note may show again.
var _hose_note_t := 0.0
var _slept := 0.0
var hose: Hose
## The instant camera, its prints and the photo board; the board's state from the save.
var photos: Photos
var _photos_state := {}
## Derelicts: what has been taken from them and which is docked, and the one drawn nearby.
var salvage := Salvage.new()
var derelict_view: DerelictView
## Seconds of air still rushing out through both open airlock hatches.
var _gale := 0.0
var _dead_t := -1.0
## Ending: seconds into the epilogue (-1 = none), and its lines.
var _end_t := -1.0
var _end_lines := PackedStringArray()
var _end_kind := ""


func _ready() -> void:
	_args = OS.get_cmdline_user_args()
	# `-- --lang ru`: this run in another language (the shots, the checks).
	var li := _args.find("--lang")
	if li >= 0 and li + 1 < _args.size():
		Loc.set_lang(_args[li + 1])
	DisplayServer.window_set_title("Lantern")
	var seed_value := _arg_int("--seed", randi() % 100000)
	sim = ShipSim.new()
	sim.rx_rod = sim.c_rx_rods
	sim.settle(4.0 * 3600.0)
	galaxy = Galaxy.new()
	galaxy.solar_seed = seed_value
	universe = galaxy.current()
	flight = Flight.new()
	flight.setup(universe, universe.find("Saturn"), 500e6, 1.0, 14.0)
	flight.c_att_mode = Flight.ATT_MODES.find("RAD IN")
	flight.c_target = universe.find("Titan")
	var tb: Variant = flight.target_basis()
	if tb != null:
		flight.att = tb
	flight.event.connect(_on_flight_event)
	sim.alarm.connect(_on_alarm)
	if boot == "continue" or ("--continue" in _args):
		_load()

	space = Space.new()
	space.name = "Space"
	add_child(space)
	space.build(flight)
	station = Station.new()
	station.name = "Station"
	station.sim = sim
	add_child(station)
	station.build()
	panels = StationPanels.new()
	panels.build(station, sim, flight, galaxy)
	panels.engage_star_fn = engage_star
	body = Body.new() if body == null else body
	body.died.connect(_on_died)
	habitat = Habitat.new()
	habitat.build(station, sim, body)
	habitat.on_eat = eat
	habitat.on_drink = drink
	habitat.on_pill = take_pill
	habitat.on_sleep = sleep
	science = Science.new() if science == null else science
	lab = Lab.new()
	lab.build(station, sim, flight, science)
	suit = Suit.new() if suit == null else suit
	airlock = AirlockFit.new()
	airlock.build(station, sim, suit)
	airlock.on_clip = toggle_clip
	airlock.on_blowout = blowout
	dock = DockFit.new()
	dock.build(station, sim)
	# The modules taken on at the port in this game, out from the Dock in order.
	port_modules = PortModules.new()
	port_modules.on_pick = pick_crop
	port_modules.build(station, sim, dock, science)
	salvage.mark(universe)
	reactor = ReactorBay.new()
	reactor.build(station, sim, self)
	separation = SeparationPanel.new()
	separation.build(station, sim, self)
	geiger = Geiger.new()
	geiger.build(station)
	geiger.rate_fn = dose_at
	flashlight = Flashlight.new()
	flashlight.build(station)
	hose = Hose.new()
	hose.name = "Umbilical"
	station.add_child(hose)
	hose.ignore = [airlock.reel_body.get_rid()]
	damage = Damage.new() if damage == null else damage
	damage_view = DamageView.new()
	damage_view.build(station, sim, damage)
	events = Events.new() if events == null else events
	events.happened.connect(_on_event)
	story = Story.new() if story == null else story
	lab.story = story

	player = Player.new()
	player.name = "Player"
	add_child(player)
	post = Post.new()
	add_child(post)
	music = Music.new()
	music.name = "Music"
	add_child(music)
	hud = Hud.new()
	hud.player = player
	hud.debug_lines = _debug_lines
	add_child(hud)
	lab.toast = hud.toast
	science.note.connect(hud.toast)
	damage_view.toast = hud.toast
	story.message.connect(_on_message)
	story.ending.connect(_on_ending)
	menu = Menu.new()
	add_child(menu)
	screen_view = ScreenView.new()
	screen_view.player = player
	screen_view.hud = hud
	screen_view.blocked_fn = func() -> bool: return not playing or _sleep_t >= 0.0 or _dead_t >= 0.0 or get_tree().paused
	add_child(screen_view)
	photos = Photos.new()
	add_child(photos)
	photos.build(self, station, sim)
	photos.from_dict(_photos_state)
	derelict_view = DerelictView.new()
	add_child(derelict_view)
	derelict_view.setup(flight, sim, salvage, player, station)
	derelict_view.toast = hud.toast
	derelict_view.module_docked = _module_home
	panels.map.salvage = salvage
	dock.dock_fn = derelict_view.dock
	dock.undock_fn = derelict_view.undock
	dock.in_range_fn = func() -> bool: return derelict_view.nearest(DerelictView.DOCK_RANGE) >= 0
	dock.docked_fn = derelict_view.is_docked
	dock.toast = hud.toast
	derelict_view.carried_off = func() -> void:
		if suit.clipped:
			suit.clipped = false
			hud.toast("The derelict lets go with you aboard: the umbilical tears loose. Push off for the station!")
			Sfx.play("thud", -4.0, 0.6, "Suit")
	airlock.toast = hud.toast
	reactor.toast = hud.toast
	photos.connect_hand(player.hand)
	player.hand.use_held.connect(func(p: Prop) -> void:
		if p == flashlight.prop:
			flashlight.toggle())
	player.lamp_fn = _lamp_key
	hud.viewfinder_fn = photos.viewfinder
	# Last of all, once every fitting is in place: the clutter, round them.
	Dressing.new().build(station)
	# Modules cast off in this game before: gone again, out of sight at once.
	if sim.rx_jettisoned and not sim.lost.has("Reactor"):
		sim.lost.append("Reactor")
	for m: String in sim.lost.duplicate():
		var gone_node := station.separate(m)
		if gone_node:
			gone_node.visible = false
			gone_node.process_mode = Node.PROCESS_MODE_DISABLED
	if sim.lost.has("Reactor"):
		reactor._gone()
	dock.prune()
	# Holes left in modules that have gone (older saves): they leaked for ever, out of reach.
	damage.breaches = damage.breaches.filter(func(b: Dictionary) -> bool: return not station.gone.has(String(b.module)))
	damage.changed.emit()
	damage.apply(sim)
	menu.choice.connect(_on_menu)
	menu.status_fn = _menu_status
	Settings.changed.connect(_apply_settings)
	_apply_settings()
	_hum = Sfx.ambient("hum", -22.0)
	# Life support's fans breathe softly where they are.
	var lsz: float = (float(Station.SPINE["Life support"][0]) + float(Station.SPINE["Life support"][1])) * 0.5
	var fans := Sfx.attach("vent", station.roots["Life support"], -24.0, 1.6)
	fans.position = Vector3(0, Station.A - 0.15, lsz)
	_burn = Sfx.ambient("burn", -80.0)
	_alarm = Sfx.ambient("alarm", -80.0)
	player.global_position = Station.SPAWN
	player.look_at_point(Station.SPAWN + Vector3.FORWARD)

	if "--selftest" in _args:
		# The checks run out of the way: off the screen and never taking the focus (screenshots
		# come from the frame itself). Not minimised: a minimised window draws no frames, and the
		# checks that wait for a frame drawn would wait for ever.
		if DisplayServer.get_name() != "headless":
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
			DisplayServer.window_set_position(Vector2i(-8000, -8000))
		playing = true
		var t := SelfTest.new()
		t.main = self
		add_child(t)
		return
	if "--fps" in _args:
		_fps_probe.call_deferred()
		return
	if "--shots" in _args:
		_shots.call_deferred()
		return
	if "--menu-shots" in _args:
		_menu_shots.call_deferred()
		return
	if boot != "" or "--new" in _args or "--continue" in _args:
		_start()
	else:
		_title()


func _arg_int(flag: String, fallback: int) -> int:
	var i := _args.find(flag)
	if i >= 0 and i + 1 < _args.size():
		return _args[i + 1].to_int()
	return fallback


func _apply_settings() -> void:
	space.apply_quality(Settings.quality)
	station.apply_quality(Settings.quality)
	post.set_flare(Settings.quality >= 1 and Settings.grain)
	post.set_retro(Settings.retro_pixel)
	post.set_look(Settings.brightness, Settings.grain)


# --- Title and flow -----------------------------------------------------------------------------

func _title() -> void:
	playing = false
	hud.cinematic = true
	menu.show_title(1 if FileAccess.file_exists(SAVE_PATH) else 0)
	hud.fade_to(0.0, 0.4)
	player.accept_input = false
	player.capture_mouse(false)
	# Behind the title: a slow orbit round the station outside, Saturn beyond.
	_title_cam = Camera3D.new()
	_title_cam.fov = 55.0
	_title_cam.near = 0.1
	_title_cam.far = 20000.0
	add_child(_title_cam)
	_title_cam.current = true
	_title_orbit(0.0)


var _title_cam: Camera3D
var _title_a := INF
var _title_t := 0.0


## Always from the sunlit side (the Sun's direction is only known once the sky has been set
## up, and moves as the station turns), swinging slowly to and fro round it, so the hull and
## the wings are lit three-quarters on.
func _title_orbit(delta: float) -> void:
	_title_t += delta
	var s := space.sun.global_basis.z if space.sun else Vector3(1, 0, 0)
	# Broadside on, from whichever flank the Sun is on, leaning toward it fore or aft (never
	# end on, where the tank would fill the view).
	var side := 1.0 if s.x >= 0.0 else -1.0
	var want := (0.0 if side > 0.0 else PI) + side * (clampf(s.z, -1.0, 1.0) * 0.6 + 0.25 * sin(_title_t * 0.05))
	_title_a = want if _title_a == INF or _title_t < 0.5 else lerp_angle(_title_a, want, minf(delta * 0.5, 1.0))
	var r := 33.0
	var at := Vector3(0, 2.0, -5.0)
	_title_cam.position = at + Vector3(cos(_title_a) * r, 5.0 + clampf(s.y, -0.5, 1.0) * 5.0 + sin(_title_t * 0.04) * 2.0, sin(_title_a) * r)
	_title_cam.look_at(at, Vector3.UP)
	# The station sits a little right of centre, clear of the menu on the left.
	_title_cam.h_offset = -5.5


## The title's telemetry corner: live from the running sim.
func _menu_status() -> PackedStringArray:
	var l := PackedStringArray()
	l.append("LANTERN  //  %s" % flight.body_name().to_upper())
	l.append("ALT %s    V %.2f km/s" % [StationPanels.km(flight.altitude()).strip_edges(), flight.speed() / 1000.0])
	l.append("CABIN %.1f kPa" % sim.pressure())
	l.append("REACTOR %3d %%    BATT %3d %%" % [roundi(sim.rx_power * 100.0), roundi(sim.bat_kwh / sim.bat_cap() * 100.0)])
	l.append("CLOCK  %s" % Flight.game_duration(flight.t))
	return l


## First-time hints: [seconds into play, key, text]. Each is shown once per game.
const HINTS := [
	[4.0, "hint_move", "Hold LMB on any surface: your arm pulls you to it. Let go on the way to fly on."],
	[18.0, "hint_push", "RMB while holding on pushes off where you look. The wheel turns knobs, selectors and levers."],
	[32.0, "hint_tab", "The station manual floats about the cockpit: catch it, and the wheel turns its pages."],
	[48.0, "hint_map", "The map is set into the floor ahead of you, under the cupola: E on it opens it full size. Click a body to pick it, the wheel zooms."],
	[62.0, "hint_screens", "Any screen aboard: hold LMB to pull yourself to it, E to see it full size."],
	[75.0, "hint_hab", "Galley, medicine and the sleeping bag are in Habitation: aft, past Engineering and the Node."],
	[105.0, "hint_lab", "Science pays for supplies: the SCIENCE and COMMS panels are low on Habitation's walls. The airlock and the docking port are off the Node."],
]
var _play_t := 0.0


func _hints(delta: float) -> void:
	if not playing or story == null or not Settings.hints:
		return
	_play_t += delta
	for h: Array in HINTS:
		if _play_t >= float(h[0]) and not story.sent.has(h[1]):
			story.sent[h[1]] = true
			hud.toast(String(h[2]))
			return


func _start() -> void:
	if _title_cam:
		_title_cam.queue_free()
		_title_cam = null
		player.cam.current = true
	playing = true
	hud.cinematic = false
	menu.hide_all()
	player.accept_input = true
	player.capture_mouse(true)
	hud.fade_to(0.0, 0.5)
	if boot != "continue":
		hud.card("LANTERN", "Saturn orbit. The crew has gone home. You stayed.", 7.0)
	boot = ""


func _on_menu(choice: String) -> void:
	match choice:
		"new":
			if FileAccess.file_exists(SAVE_PATH):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
			boot = "new"
			get_tree().reload_current_scene()
		"continue":
			boot = "continue"
			get_tree().reload_current_scene()
		"resume":
			menu.hide_all()
			hud.cinematic = false
			get_tree().paused = false
			player.capture_mouse(true)
		"title":
			get_tree().paused = false
			save_game()
			boot = ""
			get_tree().reload_current_scene()
		"quit":
			if playing:
				save_game()
			get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if not playing:
		return
	if event.is_action_pressed("pause") or (event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE):
		if menu.mode == "":
			get_tree().paused = true
			# The hand and its hints would show through the pause menu's shade.
			hud.cinematic = true
			menu.show_pause()
			player.capture_mouse(false)
			get_viewport().set_input_as_handled()


# --- Per frame ---------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not playing:
		# The title screen still turns the sky and the systems tick over.
		_advance(delta)
		return
	_advance(delta)
	if _sleep_t >= 2.0 and _sleep_left > 0.0:
		_sleep_hours()
	# The structure feels every engine (radiators and arrays must be stowed for hard burns),
	# but only the main engine's short shove throws loose things, and the keeper, toward the
	# stern. The torch's field cushions the cabin: its long pushes and the map transits are
	# not felt inside.
	sim.accel = sim.total_thrust() / sim.mass()
	var felt := sim.thrust / sim.mass()
	if not player.anchored and felt > 0.0:
		player.velocity += Vector3(0, 0, felt) * delta
	_umbilical(delta)
	_wind(delta)
	_leak_watch()
	# The core melts through: the end of the station, unless the module was cast off in time.
	if sim.rx_melt_t <= 0.0 and not sim.rx_jettisoned and story.ended == "":
		story._end("meltdown")
	if sim.rx_boom != "" and not sim.rx_jettisoned:
		_reactor_explosion(sim.rx_boom)
	PhysicsServer3D.area_set_param(get_world_3d().space, PhysicsServer3D.AREA_PARAM_GRAVITY_VECTOR, Vector3(0, 0, 1))
	PhysicsServer3D.area_set_param(get_world_3d().space, PhysicsServer3D.AREA_PARAM_GRAVITY, felt)


func _advance(delta: float) -> void:
	var gdt := delta
	sim.sun = flight.sun_flux()
	flight.thrust = sim.total_thrust()
	flight.ntr_thrust = sim.thrust
	flight.mass = sim.mass()
	sim.tick(gdt)
	flight.tick(gdt, sim)
	galaxy.tick(gdt, flight.u, sim)
	science.tick(gdt, flight, sim)
	if playing:
		damage.apply(sim)
		science.dish_ok = not damage.is_broken("dish")
		events.tick(gdt, flight.u, sim)
		story.tick(flight, galaxy, science)
	if playing:
		var here := pressure_here()
		var rate := flight.dose_rate + events.flare_dose(station.module_at(player.global_position)) + reactor.dose_here(player.global_position)
		body.tick(gdt, sim, rate, -1.0 if suit.clipped else here / maxf(sim.pressure(), 1.0))
		suit.tick(gdt, sim)
		player.in_air = here > 30.0
		sim.metabolism = body.metabolism
		player.push_scale = body.strength()
		if body.fatigue >= 1.0 and _sleep_t < 0.0 and body.alive:
			hud.toast("You pass out")
			sleep(true)
	if flight.counter_done:
		flight.counter_done = false
		Sfx.play("chime", -6.0, 1.0, "Station")
		if hud:
			hud.toast("DV COUNTER ZERO")


## F: the torch if a hand has it, else the helmet lamp if the suit is on.
func _lamp_key() -> void:
	var h := player.hand
	if flashlight.prop and is_instance_valid(flashlight.prop) and (h.held == flashlight.prop or h.offhand == flashlight.prop):
		flashlight.toggle()
	elif suit.worn:
		player.lamp.visible = not player.lamp.visible
		Sfx.play("click", -8.0, 0.8, "Suit")
	else:
		hud.toast("No light in hand: the flashlight floats by the flight desk")
		Sfx.play("error", -10.0, 1.0, "Suit")


func _process(delta: float) -> void:
	if _title_cam:
		_title_orbit(delta)
	reactor.update(delta)
	if playing:
		geiger.update(delta)
	flashlight.update(player.hand)
	# The helmet lamp is the suit's: off with the suit.
	if player.lamp.visible and not suit.worn:
		player.lamp.visible = false
	_drift_off(delta)
	_blast_t = maxf(_blast_t - delta, 0.0)
	_screens_sep -= delta
	if _screens_sep <= 0.0:
		_screens_sep = 0.5
		separation.update()
	_body_frame(delta)
	if space.sun:
		station.sun_dir = space.sun.global_basis.z
	_screens_t -= delta
	if _screens_t <= 0.0:
		_screens_t = 0.25
		panels.refresh()
	var lit := sim.powered("lights") and sim.c_lights
	# The switch off is simply dark; only a power failure brings up the red battery lamps.
	station.set_power(lit, not sim.powered("lights") and sim.bat_kwh > 0.0)
	Sfx.set_room(station.module_at(player.global_position))
	var warn := sim.any_warning()
	_alarm.volume_db = -14.0 if warn else -80.0
	_burn.volume_db = lerpf(-60.0, -6.0, clampf(sim.thrust / 140000.0, 0.0, 1.0)) if sim.thrust > 0.0 else -80.0
	_hum.volume_db = -20.0 if sim.bus_a_v > 90.0 or sim.bus_b_v > 90.0 else -60.0
	music.state = "tense" if warn or events.flare != INF else ("void" if station.module_at(player.global_position) == "" else "calm")
	if sim.thrust > 0.0:
		hud.shake(0.1 * clampf(sim.thrust / 140000.0, 0.0, 1.0))
	# A pulsar beam sweeping across the hull: the instruments crackle, the view tears.
	if flight.beam_hit:
		post.glitch = 0.35
	elif _jump_t < 0.0:
		post.glitch = move_toward(post.glitch, 0.0, delta * 3.0)
	if _jump_t >= 0.0:
		_jump_t += delta
		post.glitch = clampf(1.0 - _jump_t / 3.0, 0.0, 1.0)
		if _jump_t > 3.0:
			_jump_t = -1.0
	if playing:
		_save_t += delta
		if _save_t > 60.0:
			_save_t = 0.0
			save_game()


## The dose rate (mSv/h) at a point aboard: the sky through the hull, a flare, the torch's
## reactor driving the engine, and the reactor module's own.
func dose_at(p: Vector3) -> float:
	var r := flight.dose_rate + events.flare_dose(station.module_at(p)) + reactor.dose_here(p)
	if sim.rx_mode == 1:
		r += ShipSim.PROP_DOSE * sim.rx_power
	# The cloud from a reactor blast, thickest by the hole it left.
	if _blast_t > 0.0:
		r += (1500.0 if station.module_at(p) == "Life support" else 300.0) * _blast_t / BLAST_TIME
	return r


const BLAST_TIME := 120.0


## The JETTISON button: the reactor module is cast off (the hatch shut, nobody inside).
func jettison_reactor() -> void:
	var why := reactor.jettison_blocker(player.global_position)
	if why == "":
		why = separate_module("Reactor")
	if why != "":
		hud.toast(why)
		Sfx.play("error", -6.0, 1.0, "Station")


## Why module `m` cannot be cast off now ("" when it can).
func separation_blocker(m: String) -> String:
	var set := station.cast_set(m)
	if set.is_empty():
		return "CANNOT" if not station.gone.has(m) else "ALREADY GONE"
	if set.has(station.module_at(player.global_position)):
		return "YOU ARE IN IT"
	if set.has("Dock") and flight.docked:
		return "UNDOCK THE DERELICT FIRST"
	if station.port_index(m) >= 0:
		# Its own hatch is the only thing between the cabin and space once it goes.
		var k := station.port_index(m)
		if k < dock.hatches.size() and dock.hatches[k].is_open:
			return "SHUT THE HATCH TO IT FIRST"
	return ""


## Fire the bolts on module `m` (and all that hangs beyond it): it drifts away and whatever
## was in it is gone. `violent`: blown off by the reactor, no checks.
func separate_module(m: String, violent := false) -> String:
	if not violent:
		var why := separation_blocker(m)
		if why != "":
			return why
	var set := station.cast_set(m)
	if set.is_empty():
		return "CANNOT"
	var port_side := m == "Dock" or station.port_index(m) >= 0
	var node := station.separate(m)
	for k: String in set:
		sim.lose(k)
	if set.has("Reactor"):
		reactor._gone()
	dock.prune()
	if set.has("Airlock") and suit.clipped:
		suit.clipped = false
		hud.toast("The umbilical goes with the airlock")
	damage.breaches = damage.breaches.filter(func(b: Dictionary) -> bool: return not set.has(String(b.module)))
	damage.changed.emit()
	damage.apply(sim)
	# Away from the station: aft along the spine, or out to the side.
	var dir := Vector3(0, 0.25, 1)
	if m == "Airlock":
		dir = Vector3(1, 0.2, 0)
	elif port_side:
		dir = Vector3(-1, 0.2, 0)
	elif m == "Reactor":
		dir = Vector3(0, 1, 0.2)
	var speed := 3.0 if violent else 0.5
	_casts.append({"node": node, "t": 0.0, "v": dir.normalized() * speed, "spin": (Vector3(1, 0.3, 0.1) * (0.4 if violent else 0.05))})
	Sfx.play("impact", 0.0, 0.6, "Station")
	Sfx.play("thud", -2.0, 0.5, "Station")
	hud.shake(3.0 if violent else 1.5)
	if not violent:
		hud.toast("Bolts fired: %s away. %s" % [", ".join(PackedStringArray(set.map(func(k: String) -> String: return Loc.t(k)))).to_lower(), "Batteries and solar only from now on" if set.has("Reactor") else "Blast seal shut"])
	return ""


func _drift_off(delta: float) -> void:
	for c: Dictionary in _casts:
		if c.node == null or not is_instance_valid(c.node) or not (c.node as Node3D).visible:
			continue
		var n: Node3D = c.node
		c.t = float(c.t) + delta
		var ramp := minf(float(c.t) / 2.0, 1.0)
		n.position += (c.v as Vector3) * ramp * delta
		var spin: Vector3 = c.spin
		if spin.length() > 0.0:
			n.rotate(spin.normalized(), spin.length() * ramp * delta)
		# Out of sight: kept (things still point at what was in it), just put to sleep.
		if float(c.t) > 120.0:
			n.visible = false
			n.process_mode = Node.PROCESS_MODE_DISABLED


## The reactor blows up: the module is torn off, the blast holes Life support, the cloud
## spreads through the station, and anyone in the module dies with it.
func _reactor_explosion(cause: String) -> void:
	var inside := station.module_at(player.global_position) == "Reactor"
	var hatch_open := reactor.hatch.is_open
	sim.rx_boom = ""
	var at := Vector3(0, 0, 1.0)
	separate_module("Reactor", true)
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.85, 0.6)
	flash.light_energy = 40.0
	flash.omni_range = 40.0
	flash.position = at
	station.add_child(flash)
	var tw := create_tween()
	tw.tween_property(flash, "light_energy", 0.0, 1.6)
	tw.tween_callback(flash.queue_free)
	Sfx.play("impact", 4.0, 0.4, "Station")
	Sfx.play("deep", 0.0, 0.5, "Station")
	post.glitch = 0.6
	_blast_t = BLAST_TIME
	if inside:
		body.kill("blown apart by the reactor")
		return
	damage.add_breach("Life support", Vector3(0.25, -0.2, -0.55), Vector3(0, 0, -1), 0.02 if hatch_open else 0.005)
	damage.break_part("radiator_0")
	damage.break_part("radiator_2")
	damage.apply(sim)
	hud.toast("REACTOR EXPLOSION: %s. The module is gone; Life support is holed. Patch it, and get clear of the cloud" % cause.to_lower())


func _on_flight_event(kind: String, text: String) -> void:
	if hud:
		hud.toast(text)
	if kind == "rings":
		sim.leak_area += 2e-5
		if hud:
			hud.shake(1.5)
			hud.toast("Ring particles hit the hull")
	if kind == "arrived" or kind == "transit":
		Sfx.play("chime", -6.0, 0.9, "Station")
	if kind == "star":
		_arrive_star(int(text))


func _on_alarm(code: String, on: bool) -> void:
	if on and hud and playing:
		hud.toast("%s  %s" % [Loc.t("WARNING" if ShipSim.ALARMS[code][1] else "CAUTION"), Loc.t(ShipSim.ALARMS[code][0])])


## Set off for star id: the torch must be lit and at full throttle, the computer able to
## plot the crossing, and enough D-He3 aboard.
func engage_star(id: int) -> void:
	var why := "UNDOCK FIRST" if flight.docked else galaxy.plot_blocker(id)
	var d := galaxy.distance(id)
	if why == "" and not sim.torch_lit:
		why = "TORCH NOT LIT"
	elif why == "" and sim.c_torch_thr < 0.9:
		why = "THROTTLE TO FULL"
	elif why == "" and sim.dhe < Galaxy.travel_fuel(d):
		why = "NOT ENOUGH D-HE3"
	if why != "":
		hud.toast(why)
		Sfx.play("error", -6.0, 1.0, "Station")
		return
	var dir := (galaxy.star(id).pos as Vector3) - galaxy.here_pos
	flight.start_interstellar(id, dir, Galaxy.travel_time(d), sim, Galaxy.travel_fuel(d))
	hud.shake(1.5)
	Sfx.play("deep", -4.0, 0.7, "Station")


func _arrive_star(id: int) -> void:
	universe = galaxy.arrive(id)
	salvage.mark(universe)
	flight.arrive_at(universe, universe.hub)
	_jump_t = 0.0
	hud.shake(2.0)
	Sfx.play("deep", 0.0, 0.8, "Station")
	hud.card(universe.system_name.to_upper(), universe.description, 8.0)
	save_game()


# --- The keeper's body ----------------------------------------------------------------------------

func _body_frame(delta: float) -> void:
	if habitat == null:
		return
	_hints(delta)
	airlock.update()
	dock.update()
	port_modules.update()
	science.bonus = 1.0 + 0.5 * sim.modules.count("OBSERVATORY")
	damage_view.update(delta)
	var here := pressure_here()
	Sfx.set_vacuum(clampf(1.0 - here / 60.0, 0.0, 1.0) if not suit.worn else clampf(1.0 - here / 60.0, 0.0, 1.0) * 0.8)
	hud.suit_line = ""
	if suit.worn:
		hud.suit_line = "HOSE %d / %d m" % [roundi(hose.paid), roundi(Suit.HOSE_LEN)] if suit.clipped else ""
		if station.module_at(player.global_position) == "":
			hud.suit_line += "   DRIFT %.1f m/s" % player.velocity.length()
	lab.update_boom()
	if _screens_t >= 0.24:
		habitat.refresh()
		lab.refresh()
	# No helmet frame over the view: the suit's readout in the corner is all that shows.
	post.set_state(0.0, 0.0, 0.0, body.cold)
	post.set_body(clampf((body.fatigue - 0.7) / 0.3, 0.0, 1.0), body.sickness)
	# The body's complaints, and the radiation where the keeper is, for the badges.
	var badges := body.complaints()
	if playing:
		var rate := dose_at(player.global_position)
		if rate > 100.0:
			badges.insert(0, "HIGH RADIATION")
		elif rate > 2.0:
			badges.insert(0, "RADIATION")
	hud.complaints = badges
	# Sleep: down into the dark, the hours go by (see _sleep_hours), and up again.
	hud.night = Flight.game_duration(_slept) if _sleep_t >= 2.0 and _sleep_left > 0.0 else ""
	if _sleep_t >= 0.0:
		if _sleep_t < 2.0 or _sleep_left <= 0.0:
			_sleep_t += delta
		if _sleep_t > 5.0:
			_sleep_t = -1.0
			hud.fade_to(0.0, 0.6)
			player.accept_input = true
	if _end_t >= 0.0:
		_end_t += delta
		var shown := mini(int(_end_t / 5.0), _end_lines.size() - 1)
		if int((_end_t - delta) / 5.0) != int(_end_t / 5.0) and shown < _end_lines.size():
			var last := shown == _end_lines.size() - 1
			hud.card(_end_lines[shown], _end_stats() if last else "", 9.0 if last else 5.0)
		if _end_t > _end_lines.size() * 5.0 + 6.0:
			_end_t = -1.0
			boot = ""
			get_tree().reload_current_scene()
	if _dead_t >= 0.0:
		_dead_t += delta
		if _dead_t > 8.0:
			_dead_t = -1.0
			boot = "continue" if FileAccess.file_exists(SAVE_PATH) else ""
			get_tree().reload_current_scene()


## Air pressure where the keeper is (kPa): the cabin's, the airlock's, a docked derelict's,
## or none outside.
func pressure_here() -> float:
	if derelict_view.aboard(player.global_position):
		return sim.port_p if derelict_view.is_docked() else 0.0
	var m := station.module_at(player.global_position)
	if m == "Airlock":
		return sim.lock_p
	if m == "":
		return 0.0
	return sim.pressure()


## The reel's button: clip the umbilical on, or off again.
func toggle_clip() -> void:
	if not suit.clipped:
		suit.worn = true
		suit.clipped = true
		Sfx.play("latch", -4.0, 1.2, "Suit")
		hud.toast("Clipped on: %d m of hose" % roundi(Suit.HOSE_LEN))
		return
	suit.clipped = false
	suit.worn = false
	Sfx.play("latch", -4.0, 0.9, "Suit")
	hud.toast("Unclipped: the hose winds back on its reel")


## The umbilical: clipped on at its reel in the airlock, it pays out and stops the keeper short
## at its full length; held R hauls them back in along it.
func _umbilical(delta: float) -> void:
	var where := station.module_at(player.global_position)
	if not suit.worn:
		suit.clipped = false
	# Back aboard past the airlock: the hose stays on its reel.
	if suit.clipped and where != "" and where != "Airlock":
		suit.clipped = false
		Sfx.play("latch", -8.0, 1.1, "Suit")
	suit.worn = suit.clipped
	# Clipped at the belt, inside the body: it goes through every hatch the body goes through.
	var waist := player.global_position + Vector3(0, -0.12, 0)
	var off := waist - airlock.reel_pos
	var d := off.length()
	hose.visible = suit.clipped
	if not suit.clipped:
		return
	var on_hose := player.anchored and player.anchor_body == hose.body
	hose.draw(airlock.reel_pos, Vector3(1, 0, 0), waist, clampf(d / Suit.HOSE_LEN, 0.0, 1.0), delta, player.anchor if on_hose else Vector3.INF)
	# How far out along the hose itself (round the hull, not through it), and the way it pulls.
	d = maxf(d, hose.path_len)
	var n := -hose.pull_dir if hose.pull_dir != Vector3.ZERO else off / maxf(off.length(), 1e-4)
	_hose_note_t -= delta
	if d > Suit.HOSE_LEN:
		# The hose snaps taut: no further out, and a little spring back.
		var out_v := player.velocity.dot(n)
		if out_v > 0.0:
			if out_v > 1.5:
				Sfx.play("thud", -6.0, 0.6, "Suit")
				hud.shake(0.4)
			player.velocity -= n * out_v * 1.2
		player.velocity -= n * (d - Suit.HOSE_LEN) * 2.0 * delta
		# A hand on something past the hose's reach cannot hold against it: the hose wins.
		if player.anchored and player.anchor.distance_to(airlock.reel_pos) > Suit.HOSE_LEN - Player.HANG:
			player.let_go()
			if _hose_note_t <= 0.0:
				_hose_note_t = 4.0
				hud.toast("The umbilical is at its full length")
		# And never a centimetre past it, whatever else pushes.
		if d > Suit.HOSE_LEN + 0.25:
			player.global_position += -n * minf(d - Suit.HOSE_LEN - 0.25, 0.5)
	if Input.is_action_pressed("reel") and player.accept_input and d > 1.2:
		player.let_go()
		var want := -n * Suit.REEL_SPEED
		player.velocity = player.velocity.move_toward(want, 3.0 * delta)


## The outer hatch opened with air in the airlock: it all goes out at once, and anything
## loose in there goes with it.
func blowout(k: float) -> void:
	var where := station.module_at(player.global_position)
	var node_z: float = (Station.SPINE["Node"][0] + Station.SPINE["Node"][1]) * 0.5
	var exit := Vector3(Station.A + Station.HULL + float(Station.SIDE_LEN["Airlock"]) + 1.0, 0, node_z)
	Sfx.play("impact", 0.0, 0.7, "Station")
	Sfx.play("hiss", 0.0, 0.8, "Suit")
	hud.shake(2.0)
	hud.toast("The air tore out through the open hatch")
	if sim.lock_inner_open:
		_gale = 25.0
	if where == "Airlock" or (where == "Node" and sim.lock_inner_open):
		# A hand on something solid can just hold against a gentle puff, not against this.
		if player.anchored and k < 0.25:
			return
		player.let_go()
		var dir := (exit - player.global_position).normalized()
		dir = (dir + Vector3(randf_range(-0.15, 0.15), randf_range(-0.15, 0.15), randf_range(-0.15, 0.15))).normalized()
		player.velocity = dir * (3.0 + 9.0 * k)
		player.surge_t = 4.0
	for prop in get_tree().get_nodes_in_group("props"):
		if prop is RigidBody3D and station.module_at((prop as RigidBody3D).global_position) == "Airlock":
			var rb := prop as RigidBody3D
			rb.apply_central_impulse((exit - rb.global_position).normalized() * rb.mass * (3.0 + 9.0 * k))


## The air stops going: say so, and how to get it back (the tanks do not refill the cabin
## on their own unless the REPRESS valves are on AUTO).
func _leak_watch() -> void:
	var leaking := sim.leak_area + sim.leak_area_extra + sim.leak_port > 0.0
	if _was_leaking and not leaking and sim.pressure() < 95.0:
		hud.toast("The leak has stopped: life support brings the pressure back up")
	_was_leaking = leaking


## Both airlock hatches open: the cabin empties through them, a gale toward space.
func _wind(delta: float) -> void:
	if not (sim.lock_inner_open and sim.lock_outer_open) or sim.pressure() < 3.0:
		_gale = 0.0
		return
	var where := station.module_at(player.global_position)
	if where not in ["Airlock", "Node"]:
		return
	var node_z: float = (Station.SPINE["Node"][0] + Station.SPINE["Node"][1]) * 0.5
	var exit := Vector3(Station.A + Station.HULL + float(Station.SIDE_LEN["Airlock"]) + 1.0, 0, node_z)
	var pull := 8.0 * sim.pressure() / 101.0
	if player.anchored and pull < 2.0:
		return
	player.let_go()
	player.velocity += (exit - player.global_position).normalized() * pull * delta
	player.surge_t = maxf(player.surge_t, 0.5)


## A whole module has come in to the port: it is part of the station for good.
func _module_home(b: int) -> void:
	var kind := String(flight.u.bodies[b].get("class", "GREENHOUSE"))
	var m := port_modules.attach(kind)
	salvage.take_module(flight.u, b)
	science.bonus = 1.0 + 0.5 * sim.modules.count("OBSERVATORY")
	hud.shake(0.6)
	hud.toast(Loc.t("%s docked for good: part of the station now. Its hatch is the port from here on.") % Loc.t(m))
	var what := {"GREENHOUSE": "Food every two hours: pick the ripe trays", "POWER MODULE": "Battery +200 kWh, solar +5 kW", "OBSERVATORY": "Every scan is worth half as much again"}
	hud.toast(String(what.get(kind, "")))
	save_game()


## The greenhouse's ripe trays, picked by hand into the galley's stores.
func pick_crop() -> void:
	var n := sim.pick_crop()
	if n <= 0:
		hud.toast("Nothing ripe yet")
		return
	Sfx.play("pickup", -6.0, 1.0, "Station")
	hud.toast("Picked: %d ration trays' worth (%d aboard)" % [n, sim.food])


func eat() -> void:
	if sim.food <= 0:
		hud.toast("No rations left")
		Sfx.play("error", -8.0, 1.0, "Station")
		return
	if body.hunger < 0.15:
		hud.toast("Not hungry")
		return
	sim.food -= 1
	body.eat()
	Sfx.play("pickup", -6.0, 0.8, "Station")
	hud.toast("Ration eaten  (%d left)" % sim.food)


func drink() -> void:
	if sim.water < 1.0:
		hud.toast("The water tank is dry")
		Sfx.play("error", -8.0, 1.0, "Station")
		return
	if body.thirst < 0.1:
		hud.toast("Not thirsty")
		return
	sim.water -= 0.5
	body.drink()
	Sfx.play("hiss", -14.0, 1.6, "Station")
	hud.toast("Water")


func take_pill() -> void:
	if sim.pills <= 0:
		hud.toast("No pills left")
		Sfx.play("error", -8.0, 1.0, "Station")
		return
	sim.pills -= 1
	body.pill()
	Sfx.play("click", -6.0, 1.4, "Station")
	hud.toast("Anti-radiation pill  (%d left)" % sim.pills)


## Asleep: run the station on in one-minute steps, a few hours a second, until the sleep is
## done or something wakes the keeper.
func _sleep_hours() -> void:
	var steps := maxi(3, ceili(_sleep_plan / 150.0))
	for i in steps:
		if _sleep_left <= 0.0:
			break
		var h := minf(1.0, _sleep_left)
		_advance(h)
		_sleep_left -= h
		_slept += h
		# Rest instead of tiring: what the waking clock added, and the sleep's share back.
		body.fatigue = maxf(body.fatigue - h / Body.AWAKE_TIME - _sleep_fat0 * h / _sleep_plan, 0.0)
		if _wake == "":
			if sim.any_warning():
				_wake = "The alarm woke you"
			elif _was_transit and flight.transit.is_empty():
				_wake = "Woken on arrival"
			elif body.hunger > 0.95 or body.thirst > 0.95:
				_wake = "Hunger woke you" if body.hunger > body.thirst else "Thirst woke you"
			elif not body.alive:
				_wake = "-"
		if _wake != "":
			_sleep_left = 0.0
	if _sleep_left <= 0.0:
		body.health = minf(body.health + 0.1 * _slept / 540.0, 1.0)
		if _wake != "-":
			hud.toast("%s  (slept %s)" % [_wake if _wake != "" else "You wake up rested", Flight.game_duration(_slept)])
		_sleep_t = 3.0


## Sleep in the bag (or pass out where you are when `forced`).
func sleep(forced := false) -> void:
	if _sleep_t >= 0.0:
		return
	if not forced:
		if not body.can_sleep():
			hud.toast("Not tired enough to sleep")
			return
		if body.hunger > 0.85 or body.thirst > 0.85:
			hud.toast("Too hungry and thirsty to sleep")
			return
		if sim.any_warning():
			hud.toast("Not with the alarms going")
			return
	# Two to nine hours, by how tired: the station lives through them at a gallop.
	_sleep_plan = clampf(body.fatigue * 540.0, 120.0, 540.0)
	_sleep_left = _sleep_plan
	_sleep_fat0 = body.fatigue
	_wake = ""
	_slept = 0.0
	_was_transit = not flight.transit.is_empty()
	_sleep_t = 0.0
	player.accept_input = false
	player.release_grip()
	hud.fade_to(1.0, 1.2)
	Sfx.play("breath", -10.0, 0.7, "Suit")


# --- Events, the Office, the endings ---------------------------------------------------------------

func _on_event(kind: String, data: Dictionary) -> void:
	if _sleep_t >= 0.0 and _wake == "":
		match kind:
			"micrometeoroid":
				_wake = "A bang on the hull woke you"
			"flare_warning":
				_wake = "The flare warning woke you"
			"coolant_leak", "pump_trip", "scram", "shield_crack":
				_wake = "The reactor alarm woke you"
	match kind:
		"micrometeoroid":
			var spot := damage_view.random_spot(events.rng)
			# Often the hit shorts the gear beside the hole too.
			var hit_brk := ""
			var can: Array = Damage.HIT_BREAKERS.get(String(spot[0]), [])
			if not can.is_empty() and events.rng.randf() < 0.6:
				hit_brk = String(can[events.rng.randi() % can.size()])
			damage.add_breach(spot[0], spot[1], spot[2], events.rng.randf_range(1.5e-3, 3.0e-3), hit_brk)
			damage.apply(sim)
			Sfx.play("impact", 0.0, 1.0, "Station")
			hud.shake(1.2)
			hud.toast("Impact! Hull breach in %s: the station is losing its warmth" % spot[0])
			if hit_brk != "":
				Sfx.play("powerdown", -6.0, 1.1, "Station")
				hud.toast("The hit shorted %s: its breaker will not stay in until the hole is patched" % ShipSim.BREAKERS[hit_brk][0])
			if bool(data.get("outside", false)):
				damage.break_part(data.part)
				hud.toast("The %s is damaged outside" % Damage.PART_NAMES[data.part])
		"flare_warning":
			Sfx.play("alarm", -10.0, 1.3, "Station")
			hud.toast("Solar flare in one minute: shelter in %s" % Events.SHELTER)
		"flare_start":
			hud.toast("The flare is here: stay in %s" % Events.SHELTER)
			hud.shake(0.6)
		"flare_end":
			hud.toast("The flare has passed")
		"failure":
			Sfx.play("powerdown", -6.0, 1.0, "Station")
			hud.toast("Fault: breaker %s tripped" % ShipSim.BREAKERS[data.breaker][0])
		"coolant_leak":
			Sfx.play("hiss", -8.0, 1.2, "Station")
			hud.toast("Reactor: primary coolant leak. Seal it (patch kit), then FILL from the reserve")
		"pump_trip":
			Sfx.play("powerdown", -6.0, 0.8, "Station")
			hud.toast("Reactor: coolant pumps tripped. No flow: reset the RX PUMP breaker")
		"scram":
			Sfx.play("clunk", -2.0, 0.6, "Station")
			hud.toast("Reactor SCRAM: the rods dropped on a false signal. Restart it")
		"shield_crack":
			Sfx.play("creak_a", -2.0, 0.8, "Station")
			hud.toast("Reactor: the biological shield has cracked. The reactor room is hot: patch it quickly")


func _on_message(text: String) -> void:
	if hud:
		hud.toast("Message from the Office (comms panel, LOG)")
	Sfx.play("chime", -8.0, 0.8, "Station")


func _on_ending(kind: String) -> void:
	playing = false
	player.accept_input = false
	_end_kind = kind
	_end_lines = Story.epilogue(kind)
	_end_t = 0.001
	hud.fade_to(1.0, 0.25)
	hud.card(_end_lines[0], "", 5.0)
	# The journey is over: the next game starts fresh.
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


func _end_stats() -> String:
	return "%d star systems   %.1f light years from the Sun   %d credits earned   %s aboard" % [
		galaxy.visited.size() - 1, galaxy.here_pos.length(), roundi(science.credit), Flight.duration(flight.t)]


func _on_died(cause: String) -> void:
	playing = false
	_dead_t = 0.0
	player.accept_input = false
	hud.fade_to(1.0, 0.4)
	hud.card("YOU " + cause.to_upper(), "Back to the last log entry...", 8.0)
	Sfx.play("heartbeat", -4.0, 0.6, "Suit")


func _debug_lines() -> PackedStringArray:
	var l := PackedStringArray()
	l.append("fps %d  module %s" % [Engine.get_frames_per_second(), station.module_at(player.global_position)])
	l.append("pos %s  vel %.2f" % [str(player.global_position.snapped(Vector3.ONE * 0.01)), player.velocity.length()])
	l.append("soi %s  alt %.0f km  v %.1f" % [flight.body_name(), flight.altitude() / 1000.0, flight.speed()])
	l.append("rx T %.0f P %.2f  bat %.1f  gen %.1f" % [sim.rx_t, sim.rx_power, sim.bat_kwh, sim.gen_kw])
	return l


# --- Save ---------------------------------------------------------------------------------------

func save_game() -> void:
	# The checks play a game of their own: never over the keeper's real one.
	if "--selftest" in _args:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("game", "version", 1)
	reactor.save_loose()
	cfg.set_value("sim", "state", sim.to_dict())
	cfg.set_value("flight", "state", flight.to_dict())
	cfg.set_value("galaxy", "state", galaxy.to_dict())
	cfg.set_value("body", "state", body.to_dict())
	cfg.set_value("science", "state", science.to_dict())
	cfg.set_value("suit", "state", suit.to_dict())
	cfg.set_value("damage", "state", damage.to_dict())
	cfg.set_value("events", "state", events.to_dict())
	cfg.set_value("story", "state", story.to_dict())
	cfg.set_value("photos", "state", photos.to_dict())
	cfg.set_value("salvage", "state", salvage.to_dict())
	cfg.save(SAVE_PATH)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	galaxy.from_dict(cfg.get_value("galaxy", "state", {}))
	universe = galaxy.current()
	flight.u = universe
	sim.from_dict(cfg.get_value("sim", "state", {}))
	body = Body.new()
	body.from_dict(cfg.get_value("body", "state", {}))
	science = Science.new()
	science.from_dict(cfg.get_value("science", "state", {}))
	suit = Suit.new()
	suit.from_dict(cfg.get_value("suit", "state", {}))
	damage = Damage.new()
	damage.from_dict(cfg.get_value("damage", "state", {}))
	events = Events.new()
	events.from_dict(cfg.get_value("events", "state", {}))
	story = Story.new()
	story.from_dict(cfg.get_value("story", "state", {}))
	_photos_state = cfg.get_value("photos", "state", {})
	salvage.from_dict(cfg.get_value("salvage", "state", {}))
	flight.from_dict(cfg.get_value("flight", "state", {}))


# --- Screenshots --------------------------------------------------------------------------------

func _shots() -> void:
	playing = false
	hud.cinematic = true
	hud.fade_to(0.0, 100.0)
	player.accept_input = false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://screenshots/rebuild"))
	var views := [
		["bow", Vector3(0, 0.1, -12.6), Vector3(0, 0.0, -15.0)],
		["desk", Vector3(0, 0.15, -11.75), Vector3(0, -1.05, -12.6)],
		["engine_panel", Vector3(-0.2, -0.1, -12.6), Vector3(1.0, -0.9, -12.6)],
		["gnc_panel", Vector3(0.2, -0.1, -12.6), Vector3(-1.0, -0.9, -12.6)],
		["eng_reactor", Vector3(-0.5, 0.0, -8.5), Vector3(Station.A, 0.0, -8.5)],
		["eng_electrical", Vector3(0.5, 0.0, -8.5), Vector3(-Station.A, 0.0, -8.5)],
		["eng_breakers", Vector3(-0.3, -0.4, -8.5), Vector3(0.7, 0.7, -8.5)],
		["eng_thermal", Vector3(0.3, 0.3, -8.5), Vector3(-0.7, -0.7, -8.5)],
		["eng_corridor", Vector3(0, 0, -6.4), Vector3(0, 0, -11.5)],
		["sign_node", Vector3(0, 0.2, -1.2), Vector3(0, 0.6, -3.0)],
		["node", Vector3(0, 0, -2.5), Vector3(0, 0, -5.0)],
		["hab", Vector3(0, 0, 2.6), Vector3(0, 0, -2.5)],
		["hab_window", Vector3(-0.4, 0, 0), Vector3(1.4, 0, 0)],
		["life", Vector3(-0.5, 0, 5.0), Vector3(Station.A, 0, 5.0)],
		["lab", Vector3(-2.0, 0, -4.5), Vector3(-5.5, -0.5, -4.5)],
		["outside", Vector3(25, 12, -30), Vector3(0, 0, 5)],
		["outside_aft", Vector3(-18, 9, 55), Vector3(0, 0, 20)],
	]
	for v: Array in views:
		player.global_position = v[1]
		player.look_at_point(v[2], Vector3.UP)
		for i in 12:
			await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		img.save_png("res://screenshots/rebuild/%s.png" % v[0])
		print("shot ", v[0])
	await _shot("lab_science", Vector3(-3.9, 0, -5.0), Vector3(-3.9, 0, -3.15))
	await _shot("lab_comms", Vector3(-3.9, 0, -4.0), Vector3(-3.9, 0, -5.85))
	await _shot("hab_galley", Vector3(0.6, 0, -1.75), Vector3(-Station.A, 0, -1.75))
	await _shot("hab_medical", Vector3(-0.6, 0, -1.75), Vector3(Station.A, 0, -1.75))
	await _shot("hab_bike_bunk", Vector3(-0.6, 0.5, -0.2), Vector3(0.6, -0.6, 1.7))
	# The star map, and the view from the nearest star.
	panels.map.mode = "galaxy"
	panels.map.lpp = 0.07
	panels.map.star_target = galaxy.pulsar_id()
	await _shot("desk_galaxy", Vector3(0, 0.15, -11.75), Vector3(0, -1.05, -12.6))
	universe = galaxy.arrive(galaxy.pulsar_id())
	flight.arrive_at(universe, universe.hub)
	flight.c_att_mode = Flight.ATT_MODES.find("TARGET")
	flight.c_target = 0
	var tb: Variant = flight.target_basis()
	if tb != null:
		flight.att = tb
	await _shot("bow_pulsar", Vector3(0, 0.1, -12.6), Vector3(0, 0.0, -15.0))
	flight.c_target = universe.hub
	tb = flight.target_basis()
	if tb != null:
		flight.att = tb
	await _shot("bow_pulsar_hub", Vector3(0, 0.1, -12.6), Vector3(0, 0.0, -15.0))
	await _shot("outside_pulsar", Vector3(25, 12, -30), Vector3(0, 0, 5))
	get_tree().quit()


func _menu_shots() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://screenshots/menu"))
	var snap := func(label: String, frames: int) -> void:
		for i in frames:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://screenshots/menu/%s.png" % label)
		print("shot ", label)
	_title()
	menu.show_title(3)
	await snap.call("title", 60)
	for page: String in ["game", "controls", "display", "audio"]:
		menu._open_settings(page)
		await snap.call("settings_" + page, 8)
	menu._close_settings()
	menu._ask("Start a new journey?
The one you are on will be lost.", "START OVER", "new")
	await snap.call("confirm", 8)
	menu._close_confirm()
	_start()
	menu.show_pause()
	await snap.call("pause", 30)
	get_tree().quit()


func _shot(label: String, at: Vector3, look: Vector3) -> void:
	player.global_position = at
	player.look_at_point(look, Vector3.UP)
	for i in 16:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://screenshots/rebuild/%s.png" % label)
	print("shot ", label)


## Average frame rate from a few places aboard (`-- --fps`).
func _fps_probe() -> void:
	# Raw speed: no vsync, no cap, unless asked to measure the capped game (--capped).
	if not "--capped" in _args:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
		Settings.fps_cap = 0
	playing = true
	hud.cinematic = true
	hud.fade_to(0.0, 100.0)
	player.accept_input = false
	for spot: Array in [["bow", Vector3(0, 0.1, -12.6), Vector3(0, 0, -15)], ["engineering", Vector3(0, 0, -6.5), Vector3(0, 0, -11)], ["habitation", Vector3(0, 0, 2.6), Vector3(0, 0, -3)]]:
		player.global_position = spot[1]
		player.look_at_point(spot[2])
		for i in 60:
			await get_tree().process_frame
		var t0 := Time.get_ticks_usec()
		for i in 120:
			await get_tree().process_frame
		var fps := 120.0 / ((Time.get_ticks_usec() - t0) / 1e6)
		print("fps %s: %.0f (quality %d)  process %.1f ms  physics %.1f ms  draws %d  objects %d  cap %d" % [spot[0], fps, Settings.quality,
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), Engine.max_fps])
	get_tree().quit()
