class_name Player
extends CharacterBody3D
## Zero-G body that owns the camera, the hand and the helmet lamp.
##
## The view turns like any first-person game: yaw round the station's up (+Y) and pitch
## clamped short of straight up or down, never any roll, so it never tumbles.
## The only way to move is the hand. Hold LMB on any surface within reach and the arm pulls
## you in to it; let go on the way and you fly on at that speed (RMB pushes off where you
## look, the wheel sets how close you hang). Older scheme in Settings: hold LMB on any surface and the mouse moves your body
## instead of the view, the way an arm would: mouse toward you pulls you forward (in to the
## wall you face, or off the one behind you), away pushes you back, sideways slides you. The
## body moves with the mouse at once, as the view does, so let go while moving and you fly on
## at that speed; shove on past arm's reach and the hand leaves the wall by itself. Hold RMB to look
## around without letting go. Hold LMB while drifting and the hand catches the first surface
## that comes within reach. Inside, air drag slowly settles you; outside nothing does, so a
## careless push can be your last. (Settings can switch to free look while holding on, with
## letting go or RMB pushing off where you look.)

signal bumped(speed: float)

const MAX_SPEED := 4.5
## Metres the body moves per pixel of mouse travel while holding on.
const DRAG := 0.0035
## The hand's speed is read over this much recent mouse travel: let go and you fly on at it.
const HAND_WINDOW := 0.07
## The hand can push or pull the body this fast at most.
const MAX_PUSH := 2.6
## Arm's reach from the grip, and how close the body can be pulled in.
const ARM := 1.1
const ARM_MIN := 0.25
const SENS := 0.0022
## The body's size: small enough that the hand pulls the eye right up to what it holds.
const RADIUS := 0.21
## A flick: at least this much mouse travel toward you, this fast, within FLICK_WINDOW.
const FLICK_PX := 45.0
const FLICK_RATE := 450.0
const FLICK_WINDOW := 0.14
## The arm as a spring-damper between the shoulder and the grip: stiffness and damping along
## the arm, and how fast it soaks up swinging round the grip.
const ARM_K := 45.0
const ARM_C := 9.0
const ARM_SWING_DAMP := 1.6
## How far one notch of the wheel pulls you in or lets you out while holding on.
const ARM_STEP := 0.08
## Push speed per (pixel per second) of flick, and its range.
const FLICK_GAIN := 0.0013
const PUSH_MIN := 0.9
const PUSH_MAX := 3.2
## RMB while holding on: a click pushes off at PUSH_TAP, holding it builds up to PUSH_MAX.
const PUSH_TAP := 1.5
const CHARGE_TIME := 0.8
## Click-to-grab: the second click shoves off at this speed.
const CLICK_PUSH := 2.4
## Pull to the grip: how hard and how fast the arm hauls the body in, and how far from the
## grip it comes to hang.
const PULL_ACCEL := 3.4
const PULL_SPEED := 2.4
const HANG := 0.25
## Weight: the body is ~90 kg with its kit. Coming in to the grip it overshoots a little and
## the arm takes it back (a spring, under-damped); sideways it swings on round the grip.
const HANG_K := 16.0
const HANG_C := 5.2
const SWING_DAMP := 1.1
## The head lags the body: shoved one way, the view sways the other and settles.
const HEAD_LAG := 0.011
const HEAD_MAX := 0.07

var cam: Camera3D
var _head := Vector3.ZERO
var _head_v := Vector3.ZERO
var _last_v := Vector3.ZERO
var hand: Hand
var lamp: SpotLight3D
var accept_input := true
## True when the air around the player is breathable (inside a pressurized module).
var in_air := true
var anchored := false
var anchor := Vector3.ZERO
## What the hand holds on to (a wall, the umbilical's grip body...), null if nothing.
var anchor_body: Object = null
## Outward normal of the surface held.
var anchor_normal := Vector3.UP
## How hard the arms can push (Expedition: wasted bones push weaker).
var push_scale := 1.0
## Seconds left of being carried by a rush of air: no speed limit, no grabbing on.
var surge_t := 0.0
## Where the view points: yaw round station up, pitch clamped.
var yaw := 0.0
var pitch := 0.0
const PITCH_LIMIT := 1.53

## Where the hand is pulling the body to, while holding on.
var _target := Vector3.ZERO
## How fast the hand has been moving the body lately (smoothed mouse speed, m/s).
var _drag_vel := Vector3.ZERO
var _drag_t := 0
## Recent moves the hand made the body: [time usec, displacement].
var _strokes: Array = []
## Recent mouse motion while holding on: [time usec, relative, body basis before it turned].
var _motion: Array = []
## Mouse motion is ignored until then (usec): the rest of a flick must not spin the view.
var _swallow_until := 0
var _pad_prev_y := 0.0
var _charging := false
## RMB held while the hand moves the body: the mouse looks around instead.
var _looking := false
## Length of the arm right now, grip to body (the wheel changes it while holding on).
var _arm_len := 0.8
## When the current grip was taken (usec): the longer you have held on, the harder letting
## go shoves you off.
var _grab_t := 0
var _charge_start := 0


func _ready() -> void:
	add_to_group("player")
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	collision_layer = Layers.PLAYER
	collision_mask = Layers.WORLD | Layers.FURNITURE | Layers.PROPS | Layers.USE
	wall_min_slide_angle = 0.0
	var sphere := SphereShape3D.new()
	sphere.radius = RADIUS
	Kit.collider(self, sphere)
	cam = Camera3D.new()
	cam.name = "Camera"
	cam.fov = 78.0
	cam.near = 0.03
	cam.far = 20000.0
	add_child(cam)
	lamp = SpotLight3D.new()
	lamp.name = "Lamp"
	lamp.light_color = Color(1.0, 0.93, 0.82)
	lamp.light_energy = 1.8
	lamp.spot_range = 16.0
	lamp.spot_angle = 30.0
	lamp.spot_angle_attenuation = 1.4
	lamp.spot_attenuation = 1.2
	lamp.shadow_enabled = true
	lamp.light_volumetric_fog_energy = 0.5
	lamp.light_size = 0.03
	lamp.shadow_bias = 0.04
	lamp.position = Vector3(0.18, -0.12, 0.0)
	lamp.visible = false
	cam.add_child(lamp)
	hand = Hand.new()
	hand.name = "Hand"
	hand.setup(self, cam)
	add_child(hand)
	cam.fov = Settings.fov
	Settings.changed.connect(func() -> void: cam.fov = Settings.fov)
	_apply_look()
	capture_mouse(true)


func capture_mouse(on: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if not accept_input:
		return
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseMotion and captured:
		mouse_motion(event.relative)
	elif event.is_action_pressed("grab"):
		if not captured and event is InputEventMouseButton:
			capture_mouse(true)
			return
		if Settings.grab_toggle and anchored and not hand.aiming_at_control():
			release_grip()
			return
		hand.press()
	elif event.is_action_released("grab"):
		if Settings.grab_toggle:
			hand.stop_working()
		else:
			hand.unpress()
	elif event.is_action_pressed("throw"):
		if anchored and hand.held == null and Settings.drag_mode():
			_looking = true
		elif anchored and hand.held == null:
			_charging = true
			_charge_start = Time.get_ticks_usec()
		else:
			hand.throw()
	elif event.is_action_released("throw"):
		_looking = false
		release_push()
	elif event.is_action_pressed("flashlight"):
		toggle_lamp()
	elif event.is_action_pressed("use_item"):
		# A screen in view opens full size; otherwise E is for what the hands carry (the camera
		# in the hand always goes up to the eye: a screen is something to photograph too).
		var camera_up := hand.held != null and is_instance_valid(hand.held) and hand.held.kind == "camera"
		if camera_up or not hand.open_screen():
			hand.use()
	elif event.is_action_pressed("offhand"):
		hand.swap_offhand()
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and hand.wheel(1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1):
		pass
	elif event is InputEventMouseButton and event.pressed:
		if anchored and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			reel(-ARM_STEP if event.button_index == MOUSE_BUTTON_WHEEL_UP else ARM_STEP)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			hand.adjust_hold(0.06)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			hand.adjust_hold(-0.06)
	elif event.is_action_pressed("fullscreen"):
		var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)


## One mouse movement: look around, or (holding on) watch for a flick, or drag the body.
func mouse_motion(rel: Vector2) -> void:
	if Time.get_ticks_usec() < _swallow_until:
		return
	# LMB on the map: the hand turns the map, the head stays still.
	if hand.dragging:
		hand.drag(rel)
		return
	if anchored and Settings.drag_mode() and not _looking:
		drag(rel)
	elif anchored:
		look(rel)
		if Settings.flick_push:
			_motion.append([Time.get_ticks_usec(), rel, global_basis])
			_check_flick()
	else:
		look(rel)


## F: set by main (the torch in either hand, else the suit's helmet lamp); a bare toggle
## of the helmet lamp without it.
var lamp_fn: Callable


func toggle_lamp() -> void:
	if lamp_fn.is_valid():
		lamp_fn.call()
		return
	lamp.visible = not lamp.visible
	Sfx.play("click", -8.0, 0.8, "Suit")


func look(rel: Vector2) -> void:
	var k := SENS * Settings.sensitivity
	yaw = wrapf(yaw - rel.x * k, -PI, PI)
	pitch = clampf(pitch - rel.y * k * (-1.0 if Settings.invert_y else 1.0), -PITCH_LIMIT, PITCH_LIMIT)
	_apply_look()


func _apply_look() -> void:
	global_basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)


## Take yaw and pitch from wherever the body is pointing now (drops any roll).
func sync_look() -> void:
	var f := -global_basis.z
	yaw = atan2(-f.x, -f.z)
	pitch = clampf(asin(clampf(f.y, -1.0, 1.0)), -PITCH_LIMIT, PITCH_LIMIT)
	_apply_look()


func _process(delta: float) -> void:
	Ctl.eye = cam.global_position
	if not accept_input:
		return
	# Right stick: radians per second, with a gentle response curve.
	var stick := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	# Snapping the stick down while holding on is the gamepad's flick.
	if anchored and not Settings.drag_mode() and Settings.flick_push and stick.y > 0.85 and _pad_prev_y < 0.35:
		_pad_prev_y = stick.y
		push_off(-cam.global_basis.z, 2.4)
		return
	_pad_prev_y = stick.y
	if stick.length() > 0.0:
		stick = stick * stick.length()
		if anchored and Settings.drag_mode() and not _looking:
			drag(stick * 900.0 * Settings.pad_sensitivity * delta)
		else:
			look(stick * 2.6 * Settings.pad_sensitivity * delta / (SENS * Settings.sensitivity))


## Point the view at a world position, keeping `up` as close to up as possible.
func look_at_point(p: Vector3, _up := Vector3.UP) -> void:
	var d := p - global_position
	if d.length() < 1e-4:
		return
	d = d.normalized()
	yaw = atan2(-d.x, -d.z)
	pitch = clampf(asin(clampf(d.y, -1.0, 1.0)), -PITCH_LIMIT, PITCH_LIMIT)
	_apply_look()


func grab_surface(point: Vector3, normal := Vector3.ZERO, on: Object = null) -> void:
	if not anchored:
		Sfx.play_at("grip", point, -12.0, randf_range(0.9, 1.1))
	anchored = true
	anchor = point
	anchor_body = on
	anchor_normal = normal if normal != Vector3.ZERO else (global_position - point).normalized()
	_motion.clear()
	_target = global_position
	_drag_vel = Vector3.ZERO
	_drag_t = Time.get_ticks_usec()
	_arm_len = HANG if Settings.pull_grab else clampf(global_position.distance_to(point), ARM_MIN, ARM)
	_grab_t = Time.get_ticks_usec()
	if Settings.drag_mode():
		# The arm takes the speed you came in with.
		velocity = Vector3.ZERO
		_strokes.clear()
	Sfx.play("pickup", -10.0, 0.7, "Suit")


## Wheel while holding on: pull yourself in to the grip, or let yourself out to arm's length.
func reel(step: float) -> void:
	_arm_len = clampf(_arm_len + step, ARM_MIN, ARM)
	if Settings.drag_mode():
		var off := global_position - anchor
		var d := maxf(off.length(), 1e-4)
		_move_by(_clamp_target(anchor + off / d * clampf(d + step, ARM_MIN, ARM)) - global_position)


## Mouse travel while holding on moves the body around the grip, within arm's reach, as a
## hand on a rail would: mouse toward you moves you forward, where you look (pulling yourself
## in to the wall you face, or shoving off the one behind you); away moves you back; to the
## side slides you the other way. Reaching full stretch while still moving away from the grip
## lets go: that is how you push off, as fast as the mouse was moving.
func drag(rel: Vector2) -> void:
	var k := DRAG * Settings.sensitivity
	var step := (-global_basis.z * rel.y - global_basis.x * rel.x) * k
	var off := global_position + step - anchor
	var dist := off.length()
	if dist > ARM and step.dot(off) > 0.0:
		# Arm straight and still pushing: the hand leaves the wall.
		_strokes.append([Time.get_ticks_usec(), step])
		var hv := hand_velocity()
		var away := off / dist
		var push := maxf(hv.dot(away), 0.6)
		_strokes.clear()
		velocity = (away * push + (hv - away * hv.dot(away)) * 0.5).limit_length(MAX_PUSH)
		hand.release_surface()
		# The rest of this mouse stroke must not turn into a sudden spin of the view.
		_swallow_until = Time.get_ticks_usec() + 150000
		Sfx.play("thud", -16.0, 1.3, "Suit")
		return
	_move_by(_clamp_target(global_position + step) - global_position)


## The hand moves the body straight away, on this very mouse event (no waiting for a physics
## step, so it is as quick as looking), stopping at anything solid on the way.
func _move_by(d: Vector3) -> void:
	var from := global_position
	move_and_collide(d)
	_strokes.append([Time.get_ticks_usec(), global_position - from])


## How fast the hand has been moving the body lately (m/s).
func hand_velocity() -> Vector3:
	var now := Time.get_ticks_usec()
	while not _strokes.is_empty() and now - int(_strokes[0][0]) > int(HAND_WINDOW * 1e6):
		_strokes.pop_front()
	var sum := Vector3.ZERO
	for s: Array in _strokes:
		sum += s[1]
	return sum / HAND_WINDOW


## Keep where the hand puts the body within arm's reach of the grip and out of the wall held.
func _clamp_target(p: Vector3) -> Vector3:
	var off := p - anchor
	var into := RADIUS + 0.05 - off.dot(anchor_normal)
	if into > 0.0:
		off += anchor_normal * into
	var dist := off.length()
	if dist > ARM:
		off = off / dist * ARM
	elif dist < ARM_MIN:
		off = (off / dist if dist > 1e-4 else anchor_normal) * ARM_MIN
	return anchor + off


func let_go() -> void:
	if anchored and Settings.drag_mode() and not _strokes.is_empty():
		# Let go mid-stroke: fly on as fast as the hand was moving you.
		velocity = hand_velocity().limit_length(MAX_PUSH)
	_strokes.clear()
	if anchored:
		Sfx.play("release", -20.0, randf_range(0.9, 1.15), "Suit")
	anchored = false
	anchor_body = null
	_motion.clear()
	_charging = false
	_looking = false


## How far the push has built up (0..1), or -1 when not holding on: from RMB held, or else
## from how long LMB has held the grip.
func charge() -> float:
	if _charging:
		return clampf((Time.get_ticks_usec() - _charge_start) / (CHARGE_TIME * 1e6), 0.0, 1.0)
	if anchored and not Settings.drag_mode() and not Settings.grab_toggle and not Settings.pull_grab:
		return clampf(((Time.get_ticks_usec() - _grab_t) / 1e6 - 0.1) / CHARGE_TIME, 0.0, 1.0)
	return -1.0


## LMB let go while holding on: push off where you look, harder the longer you held on.
## Looking into the thing you hold just lets go, gently.
func release_grip() -> void:
	if not anchored:
		return
	if Settings.pull_grab:
		# Let go: fly on at whatever speed the pull had built up.
		hand.release_surface()
		return
	if Settings.drag_mode():
		hand.release_surface()
		return
	var dir := -cam.global_basis.z
	if dir.dot(anchor_normal) < -0.35:
		hand.release_surface()
		return
	if Settings.grab_toggle:
		push_off(dir, CLICK_PUSH)
		return
	push_off(dir, lerpf(PUSH_TAP * 0.8, PUSH_MAX, charge()))


## RMB let go while holding on: push off where you look, harder the longer it was held.
func release_push() -> void:
	var k := charge()
	_charging = false
	if k < 0.0 or not anchored:
		return
	push_off(-cam.global_basis.z, lerpf(PUSH_TAP, PUSH_MAX, k))


## A flick toward you within the last moment: undo the dip it gave the view, then push off
## where the view was pointing.
func _check_flick() -> void:
	var now := Time.get_ticks_usec()
	while not _motion.is_empty() and now - int(_motion[0][0]) > int(FLICK_WINDOW * 1e6):
		_motion.pop_front()
	if _motion.is_empty():
		return
	var sum := Vector2.ZERO
	for m: Array in _motion:
		sum += m[1]
	var span := maxf((now - int(_motion[0][0])) / 1e6, 1.0 / 120.0)
	var rate := sum.y / span
	if sum.y < FLICK_PX or rate < FLICK_RATE or absf(sum.x) > sum.y * 0.75:
		return
	global_basis = _motion[0][2]
	sync_look()
	push_off(-cam.global_basis.z, clampf(rate * FLICK_GAIN, PUSH_MIN, PUSH_MAX))


## The arm shoves the body off the grip toward `dir` at `speed`. Into the surface is not a
## direction an arm can push: looking at what you hold pulls you in to it; looking past it
## sends you along it.
func push_off(dir: Vector3, speed: float) -> void:
	if not anchored:
		return
	var n := anchor_normal
	var into := -dir.dot(n)
	if into > 0.75:
		# Pull in, still holding on: the body comes to rest a short way off the grip.
		_target = anchor + n * 0.55
		_swallow_until = Time.get_ticks_usec() + 200000
		_motion.clear()
		Sfx.play("pickup", -14.0, 0.9, "Suit")
		return
	if into > 0.0:
		dir = (dir + n * into).normalized()
	velocity = dir * speed * push_scale
	_swallow_until = Time.get_ticks_usec() + 250000
	hand.release_surface()
	Sfx.play("thud", -16.0, 1.3, "Suit")


func _physics_process(delta: float) -> void:
	if anchored:
		_hold(delta)
	elif in_air:
		velocity *= exp(-0.18 * delta)
	surge_t = maxf(surge_t - delta, 0.0)
	# Pushing off and floating about are slow; a rush of air out of a hatch is not, and
	# outside nothing slows you down at all.
	if in_air and surge_t <= 0.0:
		velocity = velocity.limit_length(MAX_SPEED)

	var before := velocity
	move_and_slide()
	_head_sway(delta)
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var n := c.get_normal()
		var other := c.get_collider()
		if other is RigidBody3D:
			# Loose things get shoved out of the way: an inelastic push between
			# the keeper (~90 kg with the suit) and the prop.
			var rb := other as RigidBody3D
			var rel := (before - rb.linear_velocity).dot(-n)
			if rel > 0.0:
				var j := rel * (90.0 * rb.mass) / (90.0 + rb.mass) * 1.2
				rb.apply_impulse(-n * j, c.get_position() - rb.global_position)
				velocity = before - (-n) * (j / 90.0)
			continue
		var into := -before.dot(n)
		if into > 0.9:
			# Bounce off with a little energy kept, and feel it.
			velocity = before + n * into * 1.35
			velocity *= 0.8
			bumped.emit(into)
			Sfx.play("thud", linear_to_db(clampf(into / 3.0, 0.15, 1.0)) - 4.0, 0.8, "Suit")
			break


## The head on the neck: a change of speed leaves it behind for a moment (a shove, a catch, a
## bump), then it springs back. Nothing moves when nothing changes.
func _head_sway(delta: float) -> void:
	if delta <= 0.0 or cam == null:
		return
	var accel := (velocity - _last_v) / delta
	_last_v = velocity
	var want := (-accel * HEAD_LAG).limit_length(HEAD_MAX)
	_head_v += ((want - _head) * 90.0 - _head_v * 13.0) * delta
	_head += _head_v * delta
	_head = _head.limit_length(HEAD_MAX)
	cam.position = global_basis.inverse() * _head


## Hanging on with one hand: the arm carries the body to where the mouse put it on a spring,
## as fast as an arm can, so letting go while moving keeps that speed.
func _hold(delta: float) -> void:
	if Settings.pull_grab:
		_pull(delta)
		return
	if Settings.drag_mode():
		# The hand alone moves the body (see drag); between strokes it hangs still.
		velocity = Vector3.ZERO
		return
	# A real arm: the body swings round the grip on a damped spring the length of the arm.
	var off := global_position - anchor
	var dist := maxf(off.length(), 1e-4)
	var n := off / dist
	var radial := velocity.dot(n)
	velocity += n * (-(dist - _arm_len) * ARM_K - radial * ARM_C) * delta
	var tangential := velocity - n * velocity.dot(n)
	velocity -= tangential * (1.0 - exp(-ARM_SWING_DAMP * delta))


## Pull to the grip: the arm hauls the body toward the grip at up to PULL_SPEED and holds it
## hanging HANG metres off it; sideways drift dies away as the arm takes the strain.
func _pull(delta: float) -> void:
	var off := global_position - anchor
	var dist := maxf(off.length(), 1e-4)
	var n := off / dist
	var gap := dist - _arm_len
	# Speed the arm wants along the line to the grip: in while far, easing to rest at the hang
	# (briskly, all the way: the last few centimetres must not crawl).
	var radial := velocity.dot(n)
	var dv := 0.0
	if gap > 0.35:
		# Far off: the arm hauls, and a heavy body only gathers speed so fast.
		var want := -clampf(gap * 3.0, -PULL_SPEED, PULL_SPEED)
		dv = clampf(want - radial, -PULL_ACCEL * push_scale * delta, PULL_ACCEL * push_scale * delta)
	else:
		# Close in: the arm is a spring; the body sails a little past the hang and is drawn back.
		dv = (-gap * HANG_K - radial * HANG_C) * delta
		dv = clampf(dv, -PULL_ACCEL * 2.0 * delta, PULL_ACCEL * 2.0 * delta)
	velocity += n * dv
	var tangential := velocity - n * velocity.dot(n)
	velocity -= tangential * (1.0 - exp(-SWING_DAMP * delta))
