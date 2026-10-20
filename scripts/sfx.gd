extends Node
## Synthesized sound bank. Every effect is generated from formulas; the only audio
## files in the project are IRIS's voice lines (see tools/gen_voice.py). Short
## sounds render at startup, long ones on a worker thread, and both are cached in
## user:// so later launches load instantly.
##
## Buses: "Station" carries everything heard through the air (reverb inside, and
## muffled to almost nothing in vacuum), "Suit" is what reaches you through the
## helmet (breath, heartbeat, thrusters), "Voice" is IRIS over the suit radio.

signal sound_ready(sound: String)

const RATE := 32000
const CACHE_VERSION := 5
const CACHE_DIR := "user://sfx_cache_v%d" % CACHE_VERSION

const QUICK := ["tick", "grip", "release", "click", "switch", "beep", "beep_low", "chime", "thud", "clunk", "error", "rcs", "pickup", "latch"]
const SLOW := ["reactor_hum", "hum", "vent", "alarm", "hiss", "spray", "breath", "heartbeat", "static", "deep", "servo", "airflow", "impact", "creak_a", "creak_b", "glitch", "powerdown", "powerup", "burn"]
const LOOPS := ["reactor_hum", "hum", "vent", "alarm", "hiss", "spray", "breath", "heartbeat", "static", "deep", "burn"]

var _bank: Dictionary = {}
var _rng := RandomNumberGenerator.new()
## Separate generator for synthesis, which runs on a worker thread.
var _srng := RandomNumberGenerator.new()
var _task := -1
var _voice_player: AudioStreamPlayer
var _vacuum := 0.0
## Each module sounds like itself: [room size, damping, predelay ms, wet]. The Node is a small
## hard box, the long modules ring, Storage is soaked up by bags, the Airlock is bare metal.
const ROOMS := {
	"Command deck": [0.4, 0.4, 14.0, 0.22],
	"Engineering": [0.45, 0.7, 16.0, 0.2],
	"Node": [0.32, 0.45, 10.0, 0.2],
	"Habitation": [0.55, 0.62, 22.0, 0.24],
	"Life support": [0.4, 0.75, 14.0, 0.18],
	"Laboratory": [0.6, 0.5, 26.0, 0.27],
	"Airlock": [0.5, 0.22, 16.0, 0.32],
	"Dock": [0.3, 0.3, 9.0, 0.26],
}
var _room: Array = ROOMS["Node"].duplicate()
var _room_target: Array = ROOMS["Node"]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 7
	_srng.seed = 11
	_setup_buses()
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	for s in QUICK:
		_store(s, _load_or_render(s))
	_task = WorkerThreadPool.add_task(_render_slow, false, "sfx")
	_voice_player = AudioStreamPlayer.new()
	_voice_player.bus = "Voice"
	add_child(_voice_player)


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)


func _setup_buses() -> void:
	if AudioServer.get_bus_index("Station") >= 0:
		return
	# Easy on the ears: a gentle compressor evens the loud and the quiet out, a limiter
	# catches the peaks.
	var comp := AudioEffectCompressor.new()
	comp.threshold = -16.0
	comp.ratio = 2.5
	comp.attack_us = 8000.0
	comp.release_ms = 220.0
	AudioServer.add_bus_effect(0, comp)
	var limiter := AudioEffectHardLimiter.new()
	limiter.ceiling_db = -1.0
	AudioServer.add_bus_effect(0, limiter)

	var station := _add_bus("Station")
	var rev := AudioEffectReverb.new()
	rev.room_size = 0.45
	rev.damping = 0.6
	rev.spread = 0.8
	rev.wet = 0.22
	rev.dry = 0.95
	rev.predelay_msec = 18.0
	AudioServer.add_bus_effect(station, rev)
	var lp := AudioEffectLowPassFilter.new()
	lp.cutoff_hz = 20000.0
	AudioServer.add_bus_effect(station, lp)
	# No hiss or glare up top: a soft shelf takes the edge off everything.
	var shelf := AudioEffectHighShelfFilter.new()
	shelf.cutoff_hz = 6500.0
	shelf.gain = 0.55
	AudioServer.add_bus_effect(station, shelf)

	var suit_bus := _add_bus("Suit")
	var suit_shelf := AudioEffectHighShelfFilter.new()
	suit_shelf.cutoff_hz = 5000.0
	suit_shelf.gain = 0.5
	AudioServer.add_bus_effect(suit_bus, suit_shelf)

	var voice := _add_bus("Voice")
	var bp := AudioEffectBandPassFilter.new()
	bp.cutoff_hz = 1700.0
	bp.resonance = 0.35
	AudioServer.add_bus_effect(voice, bp)
	var chorus := AudioEffectChorus.new()
	chorus.voice_count = 2
	chorus.dry = 0.85
	chorus.wet = 0.35
	AudioServer.add_bus_effect(voice, chorus)
	var dist := AudioEffectDistortion.new()
	dist.mode = AudioEffectDistortion.MODE_CLIP
	dist.drive = 0.12
	dist.post_gain = -2.0
	AudioServer.add_bus_effect(voice, dist)
	AudioServer.set_bus_volume_db(voice, 2.0)


func _add_bus(bus_name: String) -> int:
	AudioServer.add_bus()
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")
	return idx


## 0 = full air, 1 = hard vacuum: the station's sounds fade into a dull thump
## that only reaches you through the suit.
func set_vacuum(amount: float) -> void:
	_vacuum = clampf(amount, 0.0, 1.0)
	var idx := AudioServer.get_bus_index("Station")
	if idx < 0:
		return
	var lp := AudioServer.get_bus_effect(idx, 1) as AudioEffectLowPassFilter
	lp.cutoff_hz = lerpf(20000.0, 260.0, pow(_vacuum, 0.5))
	AudioServer.set_bus_volume_db(idx, lerpf(0.0, -14.0, _vacuum) + Settings.sfx_db)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Suit"), Settings.sfx_db)
	_apply_room()


## Which module the keeper is in (Station.module_at), for the reverb.
func set_room(module: String) -> void:
	_room_target = ROOMS.get(module, _room_target)


func _process(delta: float) -> void:
	var changed := false
	for i in 4:
		var v := move_toward(_room[i], _room_target[i], delta * (8.0 if i == 2 else 0.6))
		changed = changed or v != _room[i]
		_room[i] = v
	if changed:
		_apply_room()


func _apply_room() -> void:
	var idx := AudioServer.get_bus_index("Station")
	if idx < 0:
		return
	var rev := AudioServer.get_bus_effect(idx, 0) as AudioEffectReverb
	rev.room_size = _room[0]
	rev.damping = _room[1]
	rev.predelay_msec = _room[2]
	rev.wet = lerpf(_room[3], 0.02, _vacuum)


func _render_slow() -> void:
	for s in SLOW:
		var w := _load_or_render(s)
		call_deferred("_store", s, w)


func _store(sound: String, w: AudioStreamWAV) -> void:
	_bank[sound] = w
	sound_ready.emit(sound)


func has(sound: String) -> bool:
	return _bank.has(sound)


func stream(sound: String) -> AudioStream:
	return _bank.get(sound)


## Fire-and-forget positional sound.
func play_at(sound: String, pos: Vector3, volume_db := 0.0, pitch := 1.0) -> void:
	if not _bank.has(sound) or not is_inside_tree():
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = _once(sound)
	p.volume_db = volume_db
	p.pitch_scale = pitch * _rng.randf_range(0.96, 1.04)
	p.unit_size = 3.0
	p.bus = "Station"
	add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()


## Non-positional one-shot.
func play(sound: String, volume_db := 0.0, pitch := 1.0, bus := "Station") -> AudioStreamPlayer:
	if not _bank.has(sound) or not is_inside_tree():
		return null
	var p := AudioStreamPlayer.new()
	p.stream = _once(sound)
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.bus = bus
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
	return p


## A one-shot play of a sound that is stored as a loop (hiss, breath, deep...) plays it once
## through: a looping stream never finishes, so the player would hiss on for ever.
var _oneshots := {}


func _once(sound: String) -> AudioStream:
	var w: AudioStreamWAV = _bank[sound]
	if w.loop_mode == AudioStreamWAV.LOOP_DISABLED:
		return w
	if not _oneshots.has(sound):
		var o := w.duplicate() as AudioStreamWAV
		o.loop_mode = AudioStreamWAV.LOOP_DISABLED
		_oneshots[sound] = o
	return _oneshots[sound]


## A looping positional source attached to `parent`; starts as soon as the sound
## has been synthesized. Returns the player so callers can adjust or stop it.
func attach(sound: String, parent: Node3D, volume_db := 0.0, unit_size := 3.0) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.volume_db = volume_db
	p.unit_size = unit_size
	p.bus = "Station"
	parent.add_child(p)
	_start_when_ready(p, sound)
	return p


## A looping non-positional source (ambience, suit sounds).
func ambient(sound: String, volume_db := 0.0, bus := "Station") -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.volume_db = volume_db
	p.bus = bus
	add_child(p)
	_start_when_ready(p, sound)
	return p


func _start_when_ready(p: Node, sound: String) -> void:
	if _bank.has(sound):
		p.set("stream", _bank[sound])
		p.call("play")
		return
	var cb := func(s: String) -> void:
		if s == sound and is_instance_valid(p) and p.get("stream") == null:
			p.set("stream", _bank[sound])
			p.call("play")
	sound_ready.connect(cb)


## IRIS speaks a line if its recording exists. Returns the line's length in seconds.
func speak(line_id: String) -> float:
	var path := "res://voice/%s.wav" % line_id
	if not ResourceLoader.exists(path):
		return 0.0
	var w := load(path) as AudioStream
	if w == null:
		return 0.0
	_voice_player.stream = w
	_voice_player.play()
	return w.get_length()


func voice_playing() -> bool:
	return _voice_player.playing


func stop_voice() -> void:
	_voice_player.stop()


# --- Rendering ---------------------------------------------------------------

func _load_or_render(sound: String) -> AudioStreamWAV:
	var path := "%s/%s.pcm" % [CACHE_DIR, sound]
	var loop_flag := LOOPS.has(sound)
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f:
			f.get_8()
			var n := f.get_32()
			var data := f.get_buffer(n)
			return _wav(data, loop_flag)
	var pcm: PackedFloat32Array = call("_s_" + sound)
	var bytes := _to_bytes(pcm)
	var out := FileAccess.open(path, FileAccess.WRITE)
	if out:
		out.store_8(1 if loop_flag else 0)
		out.store_32(bytes.size())
		out.store_buffer(bytes)
	return _wav(bytes, loop_flag)


func _wav(bytes: PackedByteArray, loop: bool) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_end = bytes.size() / 2
	return w


func _to_bytes(pcm: PackedFloat32Array) -> PackedByteArray:
	var peak := 0.0
	for i in pcm.size():
		if is_nan(pcm[i]) or is_inf(pcm[i]):
			pcm[i] = 0.0
		peak = maxf(peak, absf(pcm[i]))
	var g := 0.95 / maxf(peak, 1.0)
	var data := PackedByteArray()
	data.resize(pcm.size() * 2)
	for i in pcm.size():
		data.encode_s16(i * 2, int(clampf(pcm[i] * g, -1.0, 1.0) * 32000.0))
	return data


func _buf(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(seconds * RATE))
	return b


## Renders `seconds + fade` with `gen` and crossfades the tail into the head so the
## result loops without a seam.
func _loopify(raw: PackedFloat32Array, fade: float) -> PackedFloat32Array:
	var nf := int(fade * RATE)
	var b := PackedFloat32Array()
	b.resize(raw.size() - nf)
	for i in b.size():
		b[i] = raw[i]
		if i < nf:
			var k := float(i) / nf
			b[i] = raw[i] * k + raw[i + b.size()] * (1.0 - k)
	return b


## State-variable filter in the trapezoidal (zero-delay feedback) form, which stays
## stable at any cutoff and Q.
class Svf:
	var ic1 := 0.0
	var ic2 := 0.0
	var low := 0.0
	var high := 0.0

	func process(x: float, cutoff: float, q: float) -> float:
		var g := tan(PI * clampf(cutoff, 20.0, 15000.0) / 32000.0)
		var k := 1.0 / maxf(q, 0.05)
		var a1 := 1.0 / (1.0 + g * (g + k))
		var a2 := g * a1
		var a3 := g * a2
		var v3 := x - ic2
		var v1 := a1 * ic1 + a2 * v3
		var v2 := ic2 + a2 * ic1 + a3 * v3
		ic1 = 2.0 * v1 - ic1
		ic2 = 2.0 * v2 - ic2
		low = v2
		high = x - k * v1 - v2
		return v1

	func lowpass(x: float, cutoff: float, q := 0.707) -> float:
		process(x, cutoff, q)
		return low

	func highpass(x: float, cutoff: float, q := 0.707) -> float:
		process(x, cutoff, q)
		return high


func _n() -> float:
	return _srng.randf_range(-1.0, 1.0)


# --- Short sounds -------------------------------------------------------------

## A Geiger counter's tick: a dry snap of noise a few milliseconds long.
func _s_tick() -> PackedFloat32Array:
	var b := _buf(0.012)
	for i in b.size():
		var t := float(i) / RATE
		b[i] = _n() * exp(-t * 900.0) * 0.9
	return b


## A gloved hand closing on a rail or a panel edge: a soft, padded knock.
func _s_grip() -> PackedFloat32Array:
	var b := _buf(0.12)
	var f := Svf.new()
	for i in b.size():
		var t := float(i) / RATE
		b[i] = (f.lowpass(_n(), 900.0) * 1.4 + sin(TAU * 140.0 * t) * 0.5) * exp(-t * 45.0) * 0.5
	return b


## Letting go: the glove's fabric brushing off, barely there.
func _s_release() -> PackedFloat32Array:
	var b := _buf(0.18)
	var f := Svf.new()
	for i in b.size():
		var t := float(i) / RATE
		b[i] = f.process(_n(), 1800.0, 0.6) * minf(t * 60.0, 1.0) * exp(-t * 22.0) * 0.25
	return b


## The reactor room: the deep thrum of the coolant pumps, a slow beat, a little bearing whirr.
func _s_reactor_hum() -> PackedFloat32Array:
	var raw := _buf(7.0)
	var f := Svf.new()
	var f2 := Svf.new()
	for i in raw.size():
		var t := float(i) / RATE
		var beat := 0.8 + 0.2 * sin(TAU * 0.9 * t)
		var v := sin(TAU * 49.0 * t) * 0.3 + sin(TAU * 98.3 * t) * 0.12 + sin(TAU * 146.8 * t) * 0.05
		v += f.lowpass(_n(), 220.0) * 0.5
		v += f2.process(_n(), 640.0, 3.0) * 0.08
		raw[i] = v * beat
	return _loopify(raw, 1.0)


func _s_click() -> PackedFloat32Array:
	var b := _buf(0.05)
	for i in b.size():
		var t := float(i) / RATE
		b[i] = _n() * exp(-t * 300.0) * 0.6 + sin(TAU * 2400.0 * t) * exp(-t * 120.0) * 0.4
	return b


## A heavy toggle: the lever's snap and the contact closing a moment later.
func _s_switch() -> PackedFloat32Array:
	var b := _buf(0.18)
	var f := Svf.new()
	for i in b.size():
		var t := float(i) / RATE
		var snap := f.process(_n(), 2200.0, 3.0) * exp(-t * 180.0) * 1.2
		var t2 := t - 0.035
		var contact := 0.0
		if t2 > 0.0:
			contact = (sin(TAU * 140.0 * t2) * 0.7 + _n() * 0.3) * exp(-t2 * 60.0)
		b[i] = snap + contact
	return b


func _beep(f0: float, f1: float, length := 0.16) -> PackedFloat32Array:
	var b := _buf(length)
	for i in b.size():
		var t := float(i) / RATE
		var f := f0 if t < length * 0.45 else f1
		var env := minf(t * 160.0, 1.0) * clampf((length - t) * 30.0, 0.0, 1.0)
		b[i] = (sin(TAU * f * t) + 0.08 * sin(TAU * f * 2.0 * t)) * env * 0.28
	return b


func _s_beep() -> PackedFloat32Array:
	return _beep(880.0, 1174.7)


func _s_beep_low() -> PackedFloat32Array:
	return _beep(660.0, 440.0, 0.3)


## IRIS clears her throat: two soft bell tones before every line.
func _s_chime() -> PackedFloat32Array:
	var b := _buf(1.1)
	var notes := [[880.0, 0.0], [1318.5, 0.16]]
	for i in b.size():
		var t := float(i) / RATE
		var v := 0.0
		for nt in notes:
			var tk: float = t - nt[1]
			if tk > 0.0:
				var f: float = nt[0]
				v += (sin(TAU * f * tk) + 0.3 * sin(TAU * f * 2.01 * tk)) * minf(tk * 80.0, 1.0) * exp(-tk * 4.5) * 0.3
		b[i] = v
	return b


func _s_thud() -> PackedFloat32Array:
	var b := _buf(0.3)
	var f := Svf.new()
	for i in b.size():
		var t := float(i) / RATE
		b[i] = sin(TAU * 62.0 * t + 1.5 * exp(-t * 40.0)) * exp(-t * 18.0) * 0.8 + f.lowpass(_n(), 700.0) * exp(-t * 45.0) * 0.6
	return b


func _s_clunk() -> PackedFloat32Array:
	var b := _buf(0.4)
	for i in b.size():
		var t := float(i) / RATE
		var body := sin(TAU * 95.0 * t + 2.0 * exp(-t * 30.0)) * exp(-t * 14.0)
		var ring := sin(TAU * 610.0 * t) * exp(-t * 30.0) * 0.3 + sin(TAU * 1460.0 * t) * exp(-t * 45.0) * 0.15
		b[i] = body * 0.8 + ring + _n() * exp(-t * 120.0) * 0.4
	return b


## Cartridge seating in its slot: slide, then a double latch.
func _s_latch() -> PackedFloat32Array:
	var b := _buf(0.5)
	var f := Svf.new()
	for i in b.size():
		var t := float(i) / RATE
		var slide := f.process(_n(), 1400.0 + 1200.0 * t, 1.5) * clampf(t * 20.0, 0.0, 1.0) * clampf((0.25 - t) * 20.0, 0.0, 1.0) * 0.5
		var v := slide
		for at in [0.26, 0.34]:
			var tk: float = t - at
			if tk > 0.0:
				v += (sin(TAU * 1900.0 * tk) * 0.5 + _n() * 0.6) * exp(-tk * 220.0)
				v += sin(TAU * 120.0 * tk) * exp(-tk * 40.0) * 0.5
		b[i] = v
	return b


func _s_error() -> PackedFloat32Array:
	var b := _buf(0.42)
	for i in b.size():
		var t := float(i) / RATE
		var f := 392.0 if t < 0.17 else 311.1
		var tk := t if t < 0.17 else t - 0.17
		var env := minf(tk * 120.0, 1.0) * exp(-tk * 9.0)
		b[i] = (sin(TAU * f * t) + 0.15 * sin(TAU * f * 2.0 * t)) * env * 0.32
	return b


## Suit thruster puff, heard through the backpack.
func _s_rcs() -> PackedFloat32Array:
	var b := _buf(0.22)
	var f := Svf.new()
	for i in b.size():
		var t := float(i) / RATE
		var env := minf(t * 300.0, 1.0) * exp(-t * 14.0)
		b[i] = f.process(_n(), 1100.0, 0.9) * env * 1.4 + sin(TAU * 85.0 * t) * env * 0.3
	return b


func _s_pickup() -> PackedFloat32Array:
	var b := _buf(0.16)
	var f := Svf.new()
	for i in b.size():
		var t := float(i) / RATE
		b[i] = f.process(_n(), 600.0, 1.2) * exp(-t * 35.0) * 0.9 + sin(TAU * 180.0 * t) * exp(-t * 50.0) * 0.3
	return b


# --- Long sounds (worker thread) -------------------------------------------

## The station breathing: mains hum, fans and a faint high whine.
func _s_hum() -> PackedFloat32Array:
	var seconds := 6.0
	var raw := _buf(seconds + 1.0)
	var f := Svf.new()
	var f2 := Svf.new()
	for i in raw.size():
		var t := float(i) / RATE
		var v := sin(TAU * 60.0 * t) * 0.22 + sin(TAU * 120.0 * t) * 0.14 + sin(TAU * 180.4 * t) * 0.05
		v += f.lowpass(_n(), 380.0) * 0.45
		v += f2.process(_n(), 1250.0, 2.0) * 0.05 * (0.8 + 0.2 * sin(TAU * 0.7 * t))
		raw[i] = v
	return _loopify(raw, 1.0)


func _s_vent() -> PackedFloat32Array:
	var raw := _buf(7.0)
	var f := Svf.new()
	var f2 := Svf.new()
	for i in raw.size():
		var t := float(i) / RATE
		var gust := 0.75 + 0.25 * sin(TAU * t / 2.3) * sin(TAU * t / 3.7 + 1.0)
		raw[i] = f.process(_n(), 700.0 + 250.0 * gust, 0.8) * gust * 0.7 + f2.lowpass(_n(), 150.0) * 0.4
	return _loopify(raw, 1.0)


## Master alarm: a rising two-stage whoop, then a gap.
func _s_alarm() -> PackedFloat32Array:
	var b := _buf(1.6)
	var ph := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var on := t < 1.0
		var x := clampf(t / 1.0, 0.0, 1.0)
		ph += (520.0 + 380.0 * x) / RATE
		var env := minf(t * 14.0, 1.0) * clampf((1.0 - t) * 10.0, 0.0, 1.0) if on else 0.0
		var tone := sin(TAU * ph) + 0.18 * sin(TAU * ph * 2.0)
		b[i] = tone * env * 0.26
	return b


## Air escaping through a puncture: hard, bright and fluttering.
func _s_hiss() -> PackedFloat32Array:
	var raw := _buf(4.0)
	var f := Svf.new()
	var f2 := Svf.new()
	for i in raw.size():
		var t := float(i) / RATE
		var flutter := 0.8 + 0.2 * sin(TAU * 13.0 * t + 2.0 * sin(TAU * 0.9 * t))
		raw[i] = (f.process(_n(), 5600.0, 0.7) * 1.1 + f2.process(_n(), 2400.0, 3.0) * 0.4) * flutter
	return _loopify(raw, 1.0)


func _s_spray() -> PackedFloat32Array:
	var raw := _buf(2.5)
	var f := Svf.new()
	for i in raw.size():
		var t := float(i) / RATE
		var sputter := 0.7 + 0.3 * sin(TAU * 31.0 * t) * sin(TAU * 4.3 * t)
		raw[i] = f.process(_n(), 2900.0, 1.1) * sputter
	return _loopify(raw, 0.5)


## Breathing inside a closed helmet.
func _s_breath() -> PackedFloat32Array:
	var b := _buf(4.4)
	var f := Svf.new()
	var f2 := Svf.new()
	for i in b.size():
		var t := float(i) / RATE
		var v := 0.0
		if t < 1.5:
			var x := t / 1.5
			v = f.process(_n(), 900.0 + 600.0 * x, 1.6) * pow(sin(PI * x), 1.5) * 0.6
		elif t > 1.8 and t < 3.8:
			var x := (t - 1.8) / 2.0
			v = f2.process(_n(), 750.0 - 250.0 * x, 1.2) * pow(sin(PI * x), 1.2) * 0.75
			v += f.lowpass(_n(), 260.0) * pow(sin(PI * x), 2.0) * 0.4
		b[i] = v
	return b


func _s_heartbeat() -> PackedFloat32Array:
	var b := _buf(0.95)
	for i in b.size():
		var t := float(i) / RATE
		var v := 0.0
		for beat in [[0.0, 1.0], [0.26, 0.7]]:
			var tk: float = t - beat[0]
			if tk > 0.0:
				v += sin(TAU * 52.0 * tk + 3.0 * exp(-tk * 30.0)) * exp(-tk * 22.0) * beat[1]
		b[i] = v * 0.9
	return b


## Radio static with occasional crackles.
func _s_static() -> PackedFloat32Array:
	var raw := _buf(4.0)
	var f := Svf.new()
	var hold := 0.0
	for i in raw.size():
		var t := float(i) / RATE
		if _srng.randf() < 0.0006:
			hold = _srng.randf_range(0.6, 1.4)
		hold *= 0.995
		var hiss := f.process(_n(), 2200.0, 0.6)
		raw[i] = hiss * (0.45 + 0.1 * sin(TAU * 0.6 * t)) + _n() * hold * 0.6
	return _loopify(raw, 0.6)


## The Well: a sub-bass pressure you feel more than hear, and a slow inhuman choir.
func _s_deep() -> PackedFloat32Array:
	var seconds := 14.0
	var raw := _buf(seconds + 2.0)
	var f := Svf.new()
	var choir := [110.0, 110.7, 164.9, 220.4, 247.1, 329.0]
	for i in raw.size():
		var t := float(i) / RATE
		var v := sin(TAU * 31.0 * t + 0.4 * sin(TAU * 0.11 * t)) * 0.5 + sin(TAU * 46.5 * t) * 0.22
		v += f.lowpass(_n(), 70.0) * 0.9
		var swell := 0.5 + 0.5 * sin(TAU * t / 9.0)
		for k in choir.size():
			var fr: float = choir[k]
			v += sin(TAU * fr * t + k * 1.3 + 0.8 * sin(TAU * 0.07 * (k + 1) * t)) * 0.035 * swell
		raw[i] = v
	return _loopify(raw, 2.0)


## Hatch gear, no motor: the handwheel's ratchet clicking round, the latch dogs grinding in
## their guides, and the seal seating with a clunk. (It used to be a rising motor whine,
## which sounded like the master alarm.)
func _s_servo() -> PackedFloat32Array:
	var b := _buf(1.6)
	var f := Svf.new()
	var f2 := Svf.new()
	for i in b.size():
		var t := float(i) / RATE
		var v := 0.0
		if t < 1.2:
			var tk := fmod(t * 13.0, 1.0) / 13.0
			v += f.process(_n(), 2600.0, 2.0) * exp(-tk * 420.0) * 0.55
			v += sin(TAU * 760.0 * tk) * exp(-tk * 260.0) * 0.18
			v += f2.lowpass(_n(), 260.0) * 0.3 * clampf(t * 8.0, 0.0, 1.0) * clampf((1.2 - t) * 8.0, 0.0, 1.0)
		var tc := t - 1.2
		if tc > 0.0:
			v += sin(TAU * 85.0 * tc + 2.0 * exp(-tc * 30.0)) * exp(-tc * 14.0) * 0.9 + _n() * exp(-tc * 60.0) * 0.4
		b[i] = v
	return b


## Air rushing in or out of the airlock.
func _s_airflow() -> PackedFloat32Array:
	var b := _buf(6.0)
	var f := Svf.new()
	var f2 := Svf.new()
	for i in b.size():
		var t := float(i) / RATE
		var x := t / 6.0
		var env := minf(t * 2.0, 1.0) * pow(1.0 - x, 1.4)
		b[i] = (f.process(_n(), 600.0 + 2200.0 * (1.0 - x), 0.9) * 0.9 + f2.lowpass(_n(), 200.0) * 0.5) * env
	return b


## Micrometeoroid strike: a bang through the frame, metal ringing, debris rattle.
func _s_impact() -> PackedFloat32Array:
	var b := _buf(2.4)
	var parts := [[173.0, 0.8, 2.5], [431.0, 0.5, 3.5], [997.0, 0.35, 5.0], [2141.0, 0.2, 8.0], [3570.0, 0.12, 11.0]]
	var f := Svf.new()
	for i in b.size():
		var t := float(i) / RATE
		var v := sin(TAU * 45.0 * t + 4.0 * exp(-t * 20.0)) * exp(-t * 6.0) * 1.2
		v += f.lowpass(_n(), 1500.0) * exp(-t * 25.0) * 1.2
		for p in parts:
			v += sin(TAU * p[0] * t) * p[1] * exp(-t * p[2])
		if t > 0.3 and _srng.randf() < 0.0015 * exp(-(t - 0.3) * 2.0):
			v += _srng.randf_range(0.5, 1.0)
		b[i] = v * 0.6
	return b


func _creak(seed_value: int, length: float, base: float) -> PackedFloat32Array:
	var b := _buf(length)
	var f := Svf.new()
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	var ph := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var x := t / length
		var rate := base * (1.0 + 0.6 * sin(TAU * x * 1.3 + 1.0)) + r.randf_range(-6.0, 6.0)
		ph += rate / RATE
		var pulse := 0.0
		if ph >= 1.0:
			ph -= 1.0
			pulse = r.randf_range(0.5, 1.0)
		var env := sin(PI * x) * (0.6 + 0.4 * sin(TAU * x * 3.0))
		b[i] = f.process(pulse * 6.0 + _n() * 0.03, 520.0 + 300.0 * x, 6.0) * env
	return b


func _s_creak_a() -> PackedFloat32Array:
	return _creak(3, 1.4, 34.0)


func _s_creak_b() -> PackedFloat32Array:
	return _creak(9, 2.1, 22.0)


func _s_glitch() -> PackedFloat32Array:
	var b := _buf(0.7)
	var level := 0.0
	var freq := 300.0
	for i in b.size():
		var t := float(i) / RATE
		if i % 700 == 0:
			level = _srng.randf_range(0.0, 1.0) if _srng.randf() < 0.7 else 0.0
			freq = _srng.randf_range(80.0, 2400.0)
		var sq := signf(sin(TAU * freq * t))
		b[i] = (sq * 0.5 + _n() * 0.5) * level * 0.4
	return b


func _sweep(seconds: float, up: bool) -> PackedFloat32Array:
	var b := _buf(seconds)
	var f := Svf.new()
	var ph := 0.0
	for i in b.size():
		var t := float(i) / RATE
		var x := t / seconds if up else 1.0 - t / seconds
		ph += (38.0 + 140.0 * x * x) / RATE
		var env := minf(t * 4.0, 1.0) * clampf((seconds - t) * 2.0, 0.0, 1.0)
		var tone := sin(TAU * ph) + 0.5 * sin(TAU * ph * 2.0) + 0.3 * sin(TAU * ph * 3.01)
		b[i] = (tone * 0.5 + f.process(_n(), 300.0 + 2500.0 * x, 3.0) * 0.4) * env
	return b


func _s_powerup() -> PackedFloat32Array:
	return _sweep(2.4, true)


func _s_powerdown() -> PackedFloat32Array:
	return _sweep(2.0, false)


## Main engine burn felt through the frame: rumble and roar.
func _s_burn() -> PackedFloat32Array:
	var raw := _buf(5.0)
	var f := Svf.new()
	var f2 := Svf.new()
	for i in raw.size():
		var t := float(i) / RATE
		var v := f.lowpass(_n(), 120.0) * 1.4 + f2.process(_n(), 480.0, 0.8) * 0.5
		v += sin(TAU * 38.0 * t) * 0.3 * (0.8 + 0.2 * sin(TAU * 3.0 * t))
		raw[i] = v
	return _loopify(raw, 1.0)
