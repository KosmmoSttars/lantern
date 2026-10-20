extends Node
## Player preferences (autoload "Settings"): look, gameplay, graphics, audio and
## key bindings. Saved to user://settings.cfg and applied live. Every rebindable
## action has a keyboard/mouse binding and a fixed gamepad binding.

signal changed

const PATH := "user://settings.cfg"

## Rebindable actions in menu order: [action, label, default key or mouse button].
## Mouse buttons are stored as negative numbers (-1 = LMB, -2 = RMB, -3 = MMB).
const ACTIONS := [
	["grab", "Grab / use", -1],
	["throw", "Throw", -2],
	["flashlight", "Flashlight in hand, or the helmet lamp", KEY_F],
	["use_item", "Use what you hold (camera: take a photo)", KEY_E],
	["reel", "Haul in the umbilical", KEY_R],
	["offhand", "Other hand / pocket: Q stows, Q again puts away, Q takes out", KEY_Q],
]

## Gamepad: buttons and axes per action (Xbox layout).
const PAD_BUTTONS := {
	"flashlight": JOY_BUTTON_X,
	"use_item": JOY_BUTTON_Y,
	"pause": JOY_BUTTON_START,
}
const PAD_AXES := {
	"look_left": [JOY_AXIS_RIGHT_X, -1.0],
	"look_right": [JOY_AXIS_RIGHT_X, 1.0],
	"look_up": [JOY_AXIS_RIGHT_Y, -1.0],
	"look_down": [JOY_AXIS_RIGHT_Y, 1.0],
	"grab": [JOY_AXIS_TRIGGER_RIGHT, 1.0],
	"throw": [JOY_AXIS_TRIGGER_LEFT, 1.0],
}

const QUALITY := ["Low", "Medium", "High", "Ultra"]

var sensitivity := 1.0
var pad_sensitivity := 1.0
var invert_y := false
var fov := 78.0
var auto_level := true
## Hold the button to hold on (default); or click to grab and click again to let go.
var grab_toggle := false
## Holding on, the mouse pulls and pushes the body around the grip (default; RMB looks
## around), instead of free look with RMB or letting go to push off.
var hold_drag := true
## Holding on pulls you in to the grip (default); letting go flies you on at that speed.
var pull_grab := true
## Flicking the mouse toward you while holding on also pushes off (off by default: a quick
## glance down would set it off).
var flick_push := false
var quality := 2
var render_scale := 1.0
## Retro look: 0 off (smooth), 1 PSX-sharp pixels, 2 chunky pixels.
var retro_pixel := 3
var vsync := true
var fullscreen := false
var master_db := 0.0
var sfx_db := 0.0
var voice_db := 0.0
var music_db := 0.0
var subtitles := true
## The picture: brightness (x), film grain and lens streaks on or off.
var brightness := 1.0
var grain := true
## How hard knocks and blowouts shake the view (0 = never).
var shake := 1.0
## First-minute hints in a new game.
var hints := true
## "en" or "ru".
var language := "en"
## Frame rate limit: index into FPS_CAPS (0 = none). Uncapped, the GPU runs flat out.
const FPS_CAPS := [0, 30, 60, 90, 120, 144]
var fps_cap := 2
## While the window is in the background the game crawls along at this many frames.
const BACKGROUND_FPS := 10
## action -> key code (>0) or -mouse button (<0).
var bindings := {}

## What "Reset to defaults" puts back, per settings page.
const SECTIONS := {
	"game": ["sensitivity", "pad_sensitivity", "invert_y", "fov", "grab_toggle", "hold_drag", "pull_grab", "flick_push", "shake", "hints"],
	"display": ["quality", "retro_pixel", "render_scale", "brightness", "grain", "vsync", "fullscreen", "fps_cap"],
	"audio": ["master_db", "sfx_db", "music_db"],
}
var _defaults := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in ACTIONS:
		bindings[a[0]] = a[2]
	for sec: String in SECTIONS:
		for k: String in SECTIONS[sec]:
			_defaults[k] = get(k)
	load_settings()
	Loc.set_lang(language)
	apply_input()
	apply_audio()
	apply_display()


var _focused := true


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_focused = false
		Engine.max_fps = BACKGROUND_FPS
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_focused = true
		Engine.max_fps = FPS_CAPS[fps_cap]


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	sensitivity = cfg.get_value("look", "sensitivity", sensitivity)
	pad_sensitivity = cfg.get_value("look", "pad_sensitivity", pad_sensitivity)
	invert_y = cfg.get_value("look", "invert_y", invert_y)
	fov = cfg.get_value("look", "fov", fov)
	auto_level = cfg.get_value("game", "auto_level", auto_level)
	grab_toggle = cfg.get_value("game", "grab_click_v2", grab_toggle)
	hold_drag = cfg.get_value("game", "hand_move", hold_drag)
	pull_grab = cfg.get_value("game", "pull_grab", pull_grab)
	flick_push = cfg.get_value("game", "flick_push", flick_push)
	subtitles = cfg.get_value("game", "subtitles", subtitles)
	quality = cfg.get_value("video", "quality", quality)
	render_scale = cfg.get_value("video", "render_scale", render_scale)
	retro_pixel = clampi(int(cfg.get_value("video", "retro_pixel_v4", retro_pixel)), 0, 3)
	vsync = cfg.get_value("video", "vsync", vsync)
	fullscreen = cfg.get_value("video", "fullscreen", fullscreen)
	master_db = cfg.get_value("audio", "master", master_db)
	sfx_db = cfg.get_value("audio", "sfx", sfx_db)
	voice_db = cfg.get_value("audio", "voice", voice_db)
	music_db = cfg.get_value("audio", "music", music_db)
	brightness = cfg.get_value("video", "brightness", brightness)
	grain = cfg.get_value("video", "grain", grain)
	shake = cfg.get_value("game", "shake", shake)
	hints = cfg.get_value("game", "hints", hints)
	language = String(cfg.get_value("game", "language", language))
	fps_cap = clampi(int(cfg.get_value("video", "fps_cap", fps_cap)), 0, FPS_CAPS.size() - 1)
	for a in ACTIONS:
		bindings[a[0]] = cfg.get_value("keys", a[0], bindings[a[0]])


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("look", "sensitivity", sensitivity)
	cfg.set_value("look", "pad_sensitivity", pad_sensitivity)
	cfg.set_value("look", "invert_y", invert_y)
	cfg.set_value("look", "fov", fov)
	cfg.set_value("game", "auto_level", auto_level)
	cfg.set_value("game", "grab_click_v2", grab_toggle)
	cfg.set_value("game", "hand_move", hold_drag)
	cfg.set_value("game", "pull_grab", pull_grab)
	cfg.set_value("game", "flick_push", flick_push)
	cfg.set_value("game", "subtitles", subtitles)
	cfg.set_value("game", "language", language)
	cfg.set_value("video", "quality", quality)
	cfg.set_value("video", "render_scale", render_scale)
	cfg.set_value("video", "retro_pixel_v4", retro_pixel)
	cfg.set_value("video", "vsync", vsync)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("audio", "master", master_db)
	cfg.set_value("audio", "sfx", sfx_db)
	cfg.set_value("audio", "voice", voice_db)
	cfg.set_value("audio", "music", music_db)
	cfg.set_value("video", "brightness", brightness)
	cfg.set_value("video", "grain", grain)
	cfg.set_value("game", "shake", shake)
	cfg.set_value("game", "hints", hints)
	cfg.set_value("video", "fps_cap", fps_cap)
	for a: String in bindings:
		cfg.set_value("keys", a, bindings[a])
	cfg.save(PATH)


## Holding on, the mouse moves the body round the grip (the older scheme).
func drag_mode() -> bool:
	return hold_drag and not pull_grab


## Call after changing any field.
func commit() -> void:
	save_settings()
	apply_input()
	apply_audio()
	apply_display()
	changed.emit()


## Put one settings page back as it ships ("game", "display", "audio"; "controls" = keys).
func reset_section(sec: String) -> void:
	if sec == "controls":
		reset_bindings()
		return
	for k: String in SECTIONS.get(sec, []):
		set(k, _defaults[k])
	commit()


func reset_bindings() -> void:
	for a in ACTIONS:
		bindings[a[0]] = a[2]
	commit()


func apply_input() -> void:
	var all := {}
	for a in ACTIONS:
		all[a[0]] = true
	for a: String in PAD_AXES:
		all[a] = true
	all["pause"] = true
	for action: String in all:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.25)
		InputMap.action_erase_events(action)
		if bindings.has(action):
			InputMap.action_add_event(action, event_for(bindings[action]))
		if PAD_BUTTONS.has(action):
			var jb := InputEventJoypadButton.new()
			jb.button_index = PAD_BUTTONS[action]
			InputMap.action_add_event(action, jb)
		if PAD_AXES.has(action):
			var jm := InputEventJoypadMotion.new()
			jm.axis = PAD_AXES[action][0]
			jm.axis_value = PAD_AXES[action][1]
			InputMap.action_add_event(action, jm)
	for fixed: String in ["fullscreen", "debug"]:
		if not InputMap.has_action(fixed):
			InputMap.add_action(fixed)
			var k := InputEventKey.new()
			k.physical_keycode = KEY_F11 if fixed == "fullscreen" else KEY_F3
			InputMap.action_add_event(fixed, k)


static func event_for(code: int) -> InputEvent:
	if code < 0:
		var mb := InputEventMouseButton.new()
		mb.button_index = -code as MouseButton
		return mb
	var k := InputEventKey.new()
	k.physical_keycode = code as Key
	return k


static func describe(code: int) -> String:
	if code < 0:
		return ["", "Left mouse", "Right mouse", "Middle mouse", "Wheel up", "Wheel down", "", "", "Mouse 4", "Mouse 5"][clampi(-code, 0, 9)]
	return OS.get_keycode_string(code as Key)


func label_for(action: String) -> String:
	return describe(bindings.get(action, 0))


func apply_audio() -> void:
	AudioServer.set_bus_volume_db(0, master_db)
	var v := AudioServer.get_bus_index("Voice")
	if v >= 0:
		AudioServer.set_bus_volume_db(v, 2.0 + voice_db)
	for bus in ["Station", "Suit"]:
		var i := AudioServer.get_bus_index(bus)
		if i >= 0:
			AudioServer.set_bus_mute(i, sfx_db <= -39.0)
	# The Station bus volume is also driven by vacuum; Sfx adds this offset.


func apply_display() -> void:
	Engine.max_fps = FPS_CAPS[fps_cap] if _focused else BACKGROUND_FPS
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	if fullscreen != full:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	if retro_pixel > 0:
		# Big pixels are picked straight out of a full-resolution, un-antialiased frame, so
		# every one of them has a hard edge.
		get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		get_viewport().scaling_3d_scale = 1.0
		get_viewport().msaa_3d = Viewport.MSAA_DISABLED
	else:
		get_viewport().msaa_3d = Viewport.MSAA_2X
		get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2 if render_scale < 0.99 else Viewport.SCALING_3D_MODE_BILINEAR
		get_viewport().scaling_3d_scale = render_scale
