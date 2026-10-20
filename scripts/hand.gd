class_name Hand
extends Node
## The player's one free hand. There is no hand model, only the cursor: aim at
## something and an open hand appears (with a white outline on objects), hold
## and it closes into a fist pinned to the grip point.
##
## LMB on a control uses it (or starts a held job), on a loose prop picks it up
## (LMB again lets it go, RMB throws), on any surface grabs hold of the station.
## While carrying a tool, LMB on a job that needs that tool does the job.

## A real arm's length: the hand reaches what is about a metre off, no further.
const REACH := 1.35
const GRIP_REACH := 1.2
const HOLD_MIN := 0.35
const HOLD_MAX := 0.9
const HOLD_DEFAULT := 0.55
const STRENGTH := 60.0

var player: Player
var cam: Camera3D

var held: Prop
## What the other hand carries (the Geiger counter, the camera, a manual), out of the way at
## the bottom of the view while this hand climbs; Q swaps.
var offhand: Prop
## A control being dragged with LMB held (the map), and how far the mouse has gone on it.
var dragging: Interactable
var _drag_px := 0.0
## Things put away (Q with this hand empty), out of sight; Q brings the last one back.
var pocket: Array[Prop] = []
const OFFHAND_SCALE := 1.35
## Small things in this hand come close to the eye, big enough to see.
const HOLD_SMALL := 0.27
const SMALL_KINDS := ["flashlight", "geiger", "camera"]
const OFFHAND_KINDS := ["flashlight", "geiger", "camera", "manual", "photo"]
## "", "use", "prop", "surface", "held", "anchor", "working".
var hover_kind := ""
var hover_name := ""
var hover_hint := ""
var working: Interactable
## The control under the cursor, if any.
var hover_it: Interactable

var _prop_local := Vector3.ZERO
var _hold_dist := HOLD_DEFAULT
var _hover_point := Vector3.ZERO
var _outlined: Node3D
var _lmb := false
## LMB is held without having grabbed or used anything: catch the first surface in reach.
var _catching := false
var _work_sound: AudioStreamPlayer3D


func setup(p: Player, c: Camera3D) -> void:
	player = p
	cam = c


## Is the hand pointed at a control it could use right now?
func aiming_at_control() -> bool:
	var hit := _ray()
	return not hit.is_empty() and hit.collider is Interactable and not (hit.collider as Interactable).grip and (hit.collider as Interactable).usable_with(carried_kind())


## Live reading of the control under the cursor ("" if none).
func hover_value() -> String:
	if hover_it and is_instance_valid(hover_it) and hover_it.value_fn.is_valid():
		return String(hover_it.value_fn.call())
	return ""


## The wheel on a control that turns: returns true if it took the wheel.
func wheel(dir: int) -> bool:
	var hit := _ray()
	if hit.is_empty() or not (hit.collider is Interactable):
		return false
	var it := hit.collider as Interactable
	if not it.on_wheel.is_valid() or not it.enabled:
		return false
	it.on_wheel.call(dir)
	return true


## Ready to catch the next surface that comes within reach (click-to-grab, after a click at nothing).
func catching() -> bool:
	return _catching


func carried_kind() -> String:
	return held.kind if held else ""


func cursor_world() -> Vector3:
	if player.anchored:
		return player.anchor
	if held:
		return held.global_transform * _prop_local
	return _hover_point


# --- Input -----------------------------------------------------------------

## The instant camera is up at the eye: LMB is its shutter, not the hand.
var aiming := false
signal shoot(p: Prop)
signal aim_cancel


func press() -> void:
	_lmb = true
	_catching = false
	if aiming and held:
		shoot.emit(held)
		return
	var hit := _ray()
	var col: Object = null if hit.is_empty() else hit.collider
	if col is Interactable and (col as Interactable).grip:
		# A screen: something to take hold of, like the wall it is set in.
		if held:
			if Settings.grab_toggle:
				_release_held()
		elif hit.position.distance_to(cam.global_position) <= GRIP_REACH:
			player.grab_surface(hit.position, hit.normal, col)
		else:
			_catching = true
		return
	if col is Interactable:
		var it := col as Interactable
		it.hit_point = hit.position
		if it.usable_with(carried_kind()):
			if it.on_drag.is_valid():
				# Held: a drag if the mouse moves, a plain touch if it does not (on release).
				dragging = it
				_drag_px = 0.0
				return
			if it.hold_time <= 0.0:
				it.complete()
				Sfx.play_at("click", hit.position, -6.0)
			else:
				_start_work(it, hit.position)
			return
		if not it.enabled or held == null:
			Sfx.play_at("error", hit.position, -12.0)
			return
	if held:
		# Click-to-grab: the second click lets go. (Otherwise letting go of LMB does.)
		if Settings.grab_toggle:
			_release_held()
		return
	if col is Prop and not (col as Prop).freeze:
		_pick(col as Prop, hit.position)
	elif col != null and hit.position.distance_to(cam.global_position) <= GRIP_REACH:
		player.grab_surface(hit.position, hit.normal, col)
	else:
		_catching = true


## Mouse travel while LMB holds a draggable control: it goes to the control, not the view.
func drag(rel: Vector2) -> void:
	if dragging == null or not is_instance_valid(dragging):
		dragging = null
		return
	_drag_px += rel.length()
	dragging.on_drag.call(rel)


func unpress() -> void:
	if dragging and is_instance_valid(dragging):
		# Hardly moved: it was a touch.
		if _drag_px < 6.0:
			dragging.complete()
			Sfx.play_at("click", dragging.hit_point, -6.0)
	dragging = null
	_lmb = false
	_catching = false
	_stop_work()
	if player.anchored:
		player.release_grip()
	# Things are carried with LMB held: let go of it and the hand lets go of them.
	if held and not aiming and not Settings.grab_toggle:
		_release_held()


## Let go of what the hand carries; over something that takes it (the photo board), it goes
## there instead of drifting off.
func _release_held() -> void:
	var hit := _ray()
	var col: Object = null if hit.is_empty() else hit.collider
	if col is Interactable:
		var it := col as Interactable
		if it.tool != "" and it.usable_with(carried_kind()):
			it.hit_point = hit.position
			it.complete()
			if held == null:
				return
	drop()


func release_surface() -> void:
	player.let_go()


func throw() -> void:
	if aiming:
		aim_cancel.emit()
		return
	if held == null:
		return
	var p := held
	drop()
	var dir := -cam.global_basis.z
	p.linear_velocity = player.velocity + dir * 3.2
	# Newton's third law, felt.
	player.velocity -= dir * 3.2 * p.mass / 90.0


func adjust_hold(step: float) -> void:
	# The manual in the hand: the wheel turns its pages instead.
	if held and held.kind == "manual":
		var page := clampi(int(held.get_meta("page", 0)) + (1 if step < 0.0 else -1), 0, Manual.count(String(held.get_meta("book", "station"))) - 1)
		if page != int(held.get_meta("page", 0)):
			held.set_meta("page", page)
			Sfx.play("click", -16.0, 0.7, "Suit")
		return
	_hold_dist = clampf(_hold_dist + step, HOLD_MIN, HOLD_MAX)


## E: use what the hand holds (the camera takes a photo).
signal use_held(p: Prop)


## The screen the hand is pointed at (in reach, held on to or not), or null.
func screen_in_view() -> Interactable:
	var hit := _ray()
	if hit.is_empty() or not (hit.collider is Interactable):
		return null
	var it := hit.collider as Interactable
	return it if it.on_open.is_valid() else null


## E on a screen: it opens full size. Returns false when there is no screen in view.
func open_screen() -> bool:
	if aiming:
		return false
	var it := screen_in_view()
	if it == null:
		return false
	it.on_open.call()
	return true


func use() -> void:
	# E with this hand empty: the torch in the other hand is switched there; anything else
	# there comes into this hand (the camera on up to the eye).
	if held == null and offhand and is_instance_valid(offhand):
		if offhand.kind == "flashlight":
			use_held.emit(offhand)
			return
		var cam_kind := offhand.kind == "camera"
		take_offhand()
		if not cam_kind:
			return
	if held and is_instance_valid(held):
		use_held.emit(held)


## Q: what this hand holds goes to the other hand (what was there goes in the pocket); Q with
## this hand empty puts the other hand's thing away in the pocket; Q with both empty takes the
## last thing pocketed back into the other hand.
func swap_offhand() -> void:
	if aiming:
		return
	pocket = pocket.filter(func(p: Prop) -> bool: return is_instance_valid(p))
	var back := offhand if offhand and is_instance_valid(offhand) else null
	var going := held if held and is_instance_valid(held) and held.kind in OFFHAND_KINDS else null
	if going:
		if back:
			_pocket(back)
		drop()
		_stow(going)
	elif back:
		_pocket(back)
	elif not pocket.is_empty():
		_stow(pocket.pop_back())
	else:
		return
	Sfx.play("pickup", -10.0, 0.9, "Suit")


## What the other hand holds, into this one.
func take_offhand() -> void:
	var back := offhand if offhand and is_instance_valid(offhand) else null
	if back == null:
		return
	offhand = null
	_unstow(back)
	_pick(back, back.global_position)


## Out of the hands and out of sight, in a suit pocket.
func _pocket(p: Prop) -> void:
	offhand = null
	p.visible = false
	pocket.append(p)


func _stow(p: Prop) -> void:
	offhand = p
	p.visible = true
	if p.get_parent() != cam:
		p.set_meta("layers", Vector2i(p.collision_layer, p.collision_mask))
	p.freeze = true
	p.collision_layer = 0
	p.collision_mask = 0
	p.linear_velocity = Vector3.ZERO
	p.angular_velocity = Vector3.ZERO
	p.reparent(cam, false)
	# Shown larger than life down there, so it reads at a glance.
	(p.get_child(0) as Node3D).scale = Vector3.ONE * OFFHAND_SCALE
	# Close in at the bottom left of the view, big enough to read; the torch points ahead.
	if p.kind == "flashlight":
		p.position = Vector3(-0.13, -0.11, -0.26)
		p.rotation = Vector3(0.05, 0.12, 0.0)
	else:
		p.position = Vector3(-0.15, -0.12, -0.27)
		p.rotation = Vector3(0.3, 0.4, 0.08)


func _unstow(p: Prop) -> void:
	(p.get_child(0) as Node3D).scale = Vector3.ONE
	p.visible = true
	var at := p.global_transform
	p.reparent(player.get_parent().get_node("Station"), false)
	p.global_transform = at
	var l: Vector2i = p.get_meta("layers", Vector2i(Layers.PROPS, Layers.WORLD | Layers.FURNITURE | Layers.PROPS | Layers.PLAYER | Layers.USE))
	p.collision_layer = l.x
	p.collision_mask = l.y
	p.freeze = false


func _pick(p: Prop, at: Vector3) -> void:
	held = p
	_prop_local = p.global_transform.affine_inverse() * at
	_hold_dist = HOLD_SMALL if p.kind in SMALL_KINDS else clampf(cam.global_position.distance_to(at), HOLD_MIN, HOLD_DEFAULT)
	p.sleeping = false
	p.angular_damp = 4.0
	player.add_collision_exception_with(p)
	Sfx.play_at("pickup", at, -4.0)
	_set_outline(null)


func drop() -> void:
	if held == null:
		return
	if is_instance_valid(held):
		held.angular_damp = 0.15
		player.remove_collision_exception_with(held)
	held = null


func _start_work(it: Interactable, at: Vector3) -> void:
	working = it
	if not it.keep_progress:
		it.progress = 0.0
	if it.has_meta("work_sound"):
		_work_sound = AudioStreamPlayer3D.new()
		_work_sound.bus = "Station"
		_work_sound.stream = Sfx.stream(str(it.get_meta("work_sound")))
		_work_sound.unit_size = 2.0
		player.get_parent().add_child(_work_sound)
		_work_sound.global_position = at
		_work_sound.play()


## Let go of the button without letting go of a surface (toggle grabbing).
func stop_working() -> void:
	_lmb = false
	_stop_work()


func _stop_work() -> void:
	if working and not working.keep_progress:
		working.progress = 0.0
	working = null
	if _work_sound:
		_work_sound.queue_free()
		_work_sound = null


# --- Per-frame -------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if held and (not is_instance_valid(held) or held.seated_in != null):
		held = null
	if held:
		_carry(delta)
	if _catching and (_lmb or Settings.grab_toggle) and not player.anchored and held == null:
		var hit := _ray()
		var col: Object = null if hit.is_empty() else hit.collider
		if col != null and not (col is Prop) and (not (col is Interactable) or (col as Interactable).grip) and hit.position.distance_to(cam.global_position) <= GRIP_REACH:
			_catching = false
			player.grab_surface(hit.position, hit.normal, col)
	# Button still held and the aim back on a job that keeps its progress: carry on with it.
	if _lmb and working == null and not player.anchored:
		var again := _ray(Layers.WORLD | Layers.USE)
		var it: Object = null if again.is_empty() else again.collider
		if it is Interactable and (it as Interactable).hold_time > 0.0 and (it as Interactable).keep_progress and (it as Interactable).usable_with(carried_kind()):
			_start_work(it as Interactable, again.position)
	if working:
		# The sealant spray (or the hand) gets past loose debris drawn into the job.
		var hit := _ray(Layers.WORLD | Layers.USE)
		if hit.is_empty() or hit.collider != working or not working.usable_with(carried_kind()):
			_stop_work()
		else:
			working.progress += delta / working.hold_time
			if working.progress >= 1.0:
				var it := working
				_stop_work()
				it.complete()
	_update_hover()


func _carry(delta: float) -> void:
	var p := held.global_transform * _prop_local
	var target := cam.global_position - cam.global_basis.z * _hold_dist
	if p.distance_to(target) > 1.6:
		drop()
		return
	var r := p - held.global_position
	var v_point := held.linear_velocity + held.angular_velocity.cross(r)
	var v_des := player.velocity + ((target - p) * 10.0).limit_length(5.0)
	var dv := v_des - v_point
	var m := held.mass
	var imp := Vector3.ZERO
	if dv.length() > 1e-5:
		# Effective mass at the grip along dv, so off-center grips don't overshoot.
		var n := dv.normalized()
		var inv_i := held.get_inverse_inertia_tensor()
		var k := 1.0 / m + n.dot((inv_i * r.cross(n)).cross(r))
		imp = dv * (0.5 / k)
	imp = imp.limit_length(STRENGTH * delta)
	held.apply_impulse(imp, r)
	# What the arm does to the thing, the thing does back to the body: a fuel assembly drags
	# you about, a camera does not. (Not while you hold on to the station.)
	if not player.anchored:
		player.velocity -= imp / 90.0


func _ray(mask := Layers.HAND_RAY) -> Dictionary:
	var from := cam.global_position
	var to := from - cam.global_basis.z * REACH
	var q := PhysicsRayQueryParameters3D.create(from, to, mask)
	var ex: Array[RID] = [player.get_rid()]
	if held and is_instance_valid(held):
		ex.append(held.get_rid())
	q.exclude = ex
	return player.get_world_3d().direct_space_state.intersect_ray(q)


func _update_hover() -> void:
	hover_name = ""
	hover_hint = ""
	hover_kind = ""
	hover_it = null
	var hit := _ray()
	var target: Node3D = null
	var col: Object = null if hit.is_empty() else hit.collider
	if working:
		hover_kind = "working"
		hover_name = working.display_name
		_hover_point = hit.position if not hit.is_empty() else _hover_point
	elif player.anchored:
		hover_kind = "anchor"
		if Settings.pull_grab:
			hover_hint = "Hold LMB: pulled in to the grip    Let go to fly on    RMB: push off where you look    Wheel: hang closer / farther"
		elif Settings.drag_mode():
			hover_hint = "Mouse toward you: pull forward    Away: push back    Let go while moving to fly    RMB: look    Wheel: in / out"
		elif Settings.grab_toggle:
			hover_hint = "Look where to go, click LMB to push off (look at the wall to let go)    Wheel: pull in / let out"
		elif not Settings.drag_mode():
			hover_hint = "Look where to go and let go of LMB to push off (hold on longer = harder)    Wheel: pull in / let out"
		# Held on at a screen: E opens it.
		if col is Interactable and (col as Interactable).on_open.is_valid():
			hover_hint = "E  open the screen    RMB: push off where you look"
	elif col is Interactable and (col as Interactable).grip:
		var g := col as Interactable
		hover_kind = "surface" if hit.position.distance_to(cam.global_position) <= GRIP_REACH else "use"
		hover_it = g
		hover_name = g.display_name
		hover_hint = g.hint_for(carried_kind())
	elif col is Interactable:
		var it := col as Interactable
		hover_kind = "use"
		hover_it = it
		hover_name = it.display_name
		hover_hint = it.hint_for(carried_kind())
		target = it
	elif held:
		hover_kind = "held"
		hover_name = held.display_name
		var let_go := "Click  let go" if Settings.grab_toggle else "Release LMB  let go"
		match held.kind:
			"manual":
				hover_hint = "Wheel  turn the page      %s      RMB  throw" % let_go
			"camera":
				hover_hint = "E  raise it to your eye      %s      RMB  throw" % let_go
			"photo":
				hover_hint = "Let go over the photo board to pin it up      RMB  throw"
			_:
				hover_hint = "%s      RMB  throw" % let_go
	elif col is Prop and not (col as Prop).freeze:
		hover_kind = "prop"
		hover_name = (col as Prop).display_name
		target = col as Node3D
	elif col != null and hit.position.distance_to(cam.global_position) <= GRIP_REACH:
		hover_kind = "surface"
		if (col as Node).is_in_group("hose"):
			hover_name = "Umbilical"
			hover_hint = "Hold LMB: pull yourself along it"
	if not hit.is_empty() and hover_kind != "working":
		_hover_point = hit.position
	_set_outline(target)


func _set_outline(node: Node3D) -> void:
	if node == _outlined:
		return
	if is_instance_valid(_outlined):
		Outline.apply(_outlined, false)
	_outlined = node
	if node:
		Outline.apply(node, true)
