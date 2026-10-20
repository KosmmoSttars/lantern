class_name Music
extends Node
## The score: three looping layers from tools/gen_score.py (music/*.ogg), crossfaded by what
## is going on. Inside with everything well: calm. An alarm, or a breach still open: tense.
## Outside: the void. Plays on its own "Music" bus, under everything else.

const LAYERS := ["calm", "tense", "void"]
const FADE := 0.35          # volume change per second, 0..1
const QUIET_DB := -60.0
const LEVEL_DB := -16.0

var state := "calm"

var _players := {}
var _mix := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var bus := AudioServer.get_bus_index("Music")
	if bus < 0:
		AudioServer.add_bus()
		bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus, "Music")
		AudioServer.set_bus_send(bus, "Master")
	for layer: String in LAYERS:
		var stream := load("res://music/%s.ogg" % layer) as AudioStreamOggVorbis
		if stream == null:
			continue
		stream.loop = true
		var p := AudioStreamPlayer.new()
		p.stream = stream
		p.bus = "Music"
		p.volume_db = QUIET_DB
		add_child(p)
		p.play()
		_players[layer] = p
		_mix[layer] = 0.0
	apply_volume()
	Settings.changed.connect(apply_volume)


func apply_volume() -> void:
	var bus := AudioServer.get_bus_index("Music")
	AudioServer.set_bus_volume_db(bus, Settings.music_db)
	AudioServer.set_bus_mute(bus, Settings.music_db <= -39.0)


func _process(delta: float) -> void:
	for layer: String in _players:
		var target := 1.0 if layer == state else 0.0
		_mix[layer] = move_toward(_mix[layer], target, FADE * delta)
		var p: AudioStreamPlayer = _players[layer]
		# Equal-power-ish: the layers cross at -3 dB rather than dipping.
		var amp: float = sin(_mix[layer] * PI * 0.5)
		p.volume_db = LEVEL_DB + linear_to_db(maxf(amp, 0.001)) if amp > 0.001 else QUIET_DB
