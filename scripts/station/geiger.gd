class_name Geiger
extends RefCounted
## A pocket Geiger counter (a dosimeter of the Terra-P kind): a slim body, an LCD with the
## reading, a speaker. It hears the radiation where it is and clicks for it, slowly in the cabin's
## background, in a frantic crackle by an open core. Carry it to know what you are floating in.

## Where it waits at the start: in Life support, by the reactor hatch.
const HOME := Vector3(-0.25, -0.2, -0.75)
## Clicks per second at a dose rate (mSv/h): a trickle at the background, a roar near the core.
const CPS_BASE := 0.4
const CPS_K := 14.0
const CPS_MAX := 55.0

var prop: Prop
## The dose rate (mSv/h) at a point, from main: the sky, a flare, the reactor.
var rate_fn: Callable
var rate := 0.0
var _click: AudioStreamPlayer3D
var _readout: Label3D
var _next := 0.0
var _read_t := 0.0


func build(station: Station) -> void:
	prop = make_prop()
	station.add_child(prop)
	prop.position = HOME
	prop.rotation = Vector3(0.3, 1.1, 0.2)
	prop.angular_velocity = Vector3(0.03, 0.07, -0.02)
	_readout = prop.get_meta("readout")
	_click = AudioStreamPlayer3D.new()
	_click.max_polyphony = 6
	_click.unit_size = 2.0
	_click.volume_db = -8.0
	_click.bus = "Station"
	prop.add_child(_click)


## A pocket dosimeter of the Terra-P kind: a slim graphite body with a yellow band, a big grey
## LCD with the reading, two buttons under it and the speaker slots at the foot, a lanyard
## eyelet at the top corner. 12 x 5.5 x 2.4 cm.
static func make_prop() -> Prop:
	var r := Node3D.new()
	var body := Geo.Builder.new()
	body.bevel = 0.006
	body.box(Vector3(0, 0, 0), Vector3(0.055, 0.12, 0.024))
	Kit.mesh(r, body.commit(Kit.matte(Color(0.17, 0.18, 0.19), 0.55)), null)
	var band := Geo.Builder.new()
	band.bevel = 0.002
	band.box(Vector3(0, -0.012, 0), Vector3(0.057, 0.012, 0.025))
	Kit.mesh(r, band.commit(Kit.matte(Color(0.95, 0.75, 0.12), 0.5)), null)
	# The LCD in its bezel.
	Kit.mesh(r, Kit.box(Vector3(0.045, 0.042, 0.002)), Kit.matte(Color(0.08, 0.08, 0.09), 0.4), Vector3(0, 0.026, 0.0121))
	Kit.mesh(r, Kit.box(Vector3(0.039, 0.034, 0.001)), Kit.matte(Color(0.62, 0.68, 0.58), 0.35), Vector3(0, 0.026, 0.0132))
	var lcd := Ctl.text(r, "0.02", Vector3(0, 0.03, 0.0139), 0.013, Color(0.08, 0.1, 0.06), HORIZONTAL_ALIGNMENT_CENTER, true)
	lcd.shaded = true
	Ctl.text(r, "mSv/h", Vector3(0.008, 0.016, 0.0139), 0.0045, Color(0.12, 0.13, 0.1))
	# Two buttons, the speaker slots.
	var keys := Geo.Builder.new()
	for sx in [-0.011, 0.011]:
		keys.cylinder(Vector3(sx, -0.028, 0.012), Vector3(sx, -0.028, 0.0145), 0.0055, 12)
	for k in 4:
		keys.box(Vector3(0, -0.043 - k * 0.0035, 0.0122), Vector3(0.022, 0.0012, 0.001))
	Kit.mesh(r, keys.commit(Kit.matte(Color(0.06, 0.06, 0.07), 0.6)), null)
	# The eyelet.
	var eye := Geo.Builder.new()
	for f in 10:
		var a0 := TAU * f / 10.0
		var a1 := TAU * (f + 1) / 10.0
		eye.cylinder(Vector3(0.021 + cos(a0) * 0.005, 0.064 + sin(a0) * 0.005, 0), Vector3(0.021 + cos(a1) * 0.005, 0.064 + sin(a1) * 0.005, 0), 0.0012, 4)
	Kit.mesh(r, eye.commit(Kit.metal(Color(0.6, 0.62, 0.65), 0.35, 0.8)), null)
	Ctl.text(r, "TERRA", Vector3(0, 0.053, 0.0122), 0.0045, Color(0.85, 0.85, 0.8))
	var p := Prop.make("geiger", "Geiger counter", r, Kit.box_shape(Vector3(0.056, 0.125, 0.026)), 0.2)
	p.set_meta("readout", lcd)
	return p


func update(delta: float) -> void:
	if prop == null or not is_instance_valid(prop) or not rate_fn.is_valid():
		return
	rate = float(rate_fn.call(prop.global_position))
	_read_t -= delta
	if _read_t <= 0.0:
		_read_t = 0.4
		_readout.text = "OVER" if rate >= 9999.0 else ("%.2f" % rate if rate < 10.0 else "%d" % roundi(rate))
	if _click.stream == null:
		_click.stream = Sfx.stream("tick")
		return
	# The clicks come at random, as the particles do: one at most a frame, the rest a roar.
	_next -= delta
	if _next <= 0.0:
		_click.pitch_scale = randf_range(0.85, 1.2)
		_click.play()
		_next = -log(maxf(randf(), 1e-4)) / cps(rate)


static func cps(r: float) -> float:
	return minf(CPS_BASE + CPS_K * sqrt(maxf(r, 0.0)), CPS_MAX)
