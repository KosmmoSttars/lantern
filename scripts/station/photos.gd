class_name Photos
extends Node
## The instant camera, its prints and the photo board in Habitation. Catch the camera, aim,
## press E: the flash goes, the view is taken (without the hand or the readouts), and a print
## slides out, dark at first and coming up over a few seconds. Carry a print to the board and
## press it on with LMB: it stays there, a little crooked, under a pin. Pinned prints are kept
## on disk (user://photos) and in the save. The film is the station's (ShipSim.film): ten to a
## pack, more from the supply catalogue.

const DIR := "user://photos"
## The print: card size, and the picture on it (m); the picture's pixels.
const CARD := Vector2(0.088, 0.107)
const PICTURE := 0.078
const PICTURE_PX := 160
## How long a print takes to come up (s).
const DEVELOP := 7.0
## The board's size (m) along the module and across the face.
const BOARD := Vector2(1.0, 0.46)

var main: Node
var station: Station
var sim: ShipSim
var board: Node3D
var camera: Prop
## Pinned prints: [{file, x, y, r}] in board space.
var pinned: Array = []
## The camera is up at the eye, looking through its finder.
var aiming := false
var _busy := false


func build(p_main: Node, p_station: Station, p_sim: ShipSim) -> void:
	main = p_main
	station = p_station
	sim = p_sim
	name = "Photos"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	_board()
	camera = _camera_prop()
	station.add_child(camera)
	camera.position = Vector3(-0.2, 0.25, -4.6)
	camera.angular_velocity = Vector3(0.05, 0.12, 0.03)
	var manual := Manual.make_prop()
	station.add_child(manual)
	manual.position = Vector3(0.2, 0.3, -12.2)
	manual.rotation = Vector3(0.4, 0.8, 0.2)
	manual.angular_velocity = Vector3(0.04, 0.09, -0.03)


# --- The board -------------------------------------------------------------------------------

func _board() -> void:
	board = Node3D.new()
	board.name = "PhotoBoard"
	board.transform = station.face_xform(6, -4.3)
	station.add_child(board)
	var cork := StandardMaterial3D.new()
	var noise := FastNoiseLite.new()
	noise.frequency = 0.35
	var tex := NoiseTexture2D.new()
	tex.noise = noise
	tex.width = 128
	tex.height = 96
	var g := Gradient.new()
	g.set_color(0, Color(0.42, 0.27, 0.15))
	g.set_color(1, Color(0.66, 0.47, 0.28))
	tex.color_ramp = g
	cork.albedo_texture = tex
	cork.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	cork.roughness = 0.95
	Kit.mesh(board, Kit.box(Vector3(BOARD.x, BOARD.y, 0.02)), cork, Vector3(0, 0, 0.01))
	var frame := Geo.Builder.new()
	frame.bevel = 0.004
	var w := 0.03
	frame.box(Vector3(0, BOARD.y * 0.5 + w * 0.5, 0.015), Vector3(BOARD.x + w * 2.0, w, 0.03))
	frame.box(Vector3(0, -BOARD.y * 0.5 - w * 0.5, 0.015), Vector3(BOARD.x + w * 2.0, w, 0.03))
	frame.box(Vector3(BOARD.x * 0.5 + w * 0.5, 0, 0.015), Vector3(w, BOARD.y, 0.03))
	frame.box(Vector3(-BOARD.x * 0.5 - w * 0.5, 0, 0.015), Vector3(w, BOARD.y, 0.03))
	Kit.mesh(board, frame.commit(Looks.panel(Color(0.36, 0.25, 0.15), 0.6)), null)
	Ctl.fit(Ctl.text(board, "PHOTOS", Vector3(-BOARD.x * 0.5 + 0.08, BOARD.y * 0.5 - 0.04, 0.022), 0.02, Color(0.15, 0.09, 0.04)), 0.14, 0.03)
	var shape := BoxShape3D.new()
	shape.size = Vector3(BOARD.x, BOARD.y, 0.03)
	var it := Interactable.make(board, "Photo board", "Pin the photo up", shape, Vector3(0, 0, 0.02))
	it.tool = "photo"
	it.tool_name = "a photo (catch the camera in Habitation: E raises it, LMB shoots)"
	it.value_fn = func() -> String: return "%d photo%s" % [pinned.size(), "" if pinned.size() == 1 else "s"]
	it.on_use = func() -> void: _pin_held(it.hit_point)


func _pin_held(hit: Vector3) -> void:
	var hand: Hand = main.player.hand
	var p := hand.held
	if p == null or not is_instance_valid(p) or p.kind != "photo":
		return
	hand.drop()
	var local := board.global_transform.affine_inverse() * hit
	var x := clampf(local.x, -BOARD.x * 0.5 + CARD.x * 0.5, BOARD.x * 0.5 - CARD.x * 0.5)
	var y := clampf(local.y, -BOARD.y * 0.5 + CARD.y * 0.5, BOARD.y * 0.5 - CARD.y * 0.5)
	var entry := {"file": String(p.get_meta("file")), "x": x, "y": y, "r": randf_range(-0.14, 0.14)}
	pinned.append(entry)
	_attach(entry)
	p.queue_free()
	Sfx.play_at("click", hit, -6.0, 0.8)
	main.hud.toast("Pinned up  (%d on the board)" % pinned.size())


## A print on the board, under a red pin.
func _attach(e: Dictionary) -> void:
	var tex := _load(String(e.file))
	if tex == null:
		return
	var card := _print_mesh(tex, 1.0)
	card.position = Vector3(float(e.x), float(e.y), 0.022 + pinned.find(e) * 0.0004)
	card.rotation.z = float(e.r)
	board.add_child(card)
	Kit.mesh(card, Kit.sphere(0.006, 8), Kit.matte(Color(0.8, 0.12, 0.08), 0.4), Vector3(0, CARD.y * 0.5 - 0.008, 0.006))


func _load(file: String) -> Texture2D:
	var img := Image.load_from_file(ProjectSettings.globalize_path(file))
	if img == null or img.is_empty():
		return null
	return ImageTexture.create_from_image(img)


## The white card with the picture on its upper part. `developed` 0..1 (dark to clear).
func _print_mesh(tex: Texture2D, developed: float) -> Node3D:
	var root := Node3D.new()
	Kit.mesh(root, Kit.box(Vector3(CARD.x, CARD.y, 0.0015)), Kit.matte(Color(0.93, 0.92, 0.88), 0.85), Vector3.ZERO)
	var pic := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(PICTURE, PICTURE)
	pic.mesh = q
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.albedo_color = Color(0.12, 0.12, 0.14).lerp(Color.WHITE, developed)
	m.roughness = 0.35
	pic.material_override = m
	pic.position = Vector3(0, (CARD.y - PICTURE) * 0.5 - 0.005, 0.0009)
	root.add_child(pic)
	root.set_meta("picture", m)
	return root


# --- The camera ------------------------------------------------------------------------------

## A classic instant camera: a wedge, deep at the base and leaning back toward the top, a
## white face sloping up round a big black lens, the viewfinder window and the flash panel
## along the top, the red shutter button at the front, and a black jaw below with the slot
## the prints come out of.
func _camera_prop() -> Prop:
	var root := Node3D.new()
	var white := Kit.matte(Color(0.93, 0.92, 0.88), 0.55)
	var black := Kit.matte(Color(0.08, 0.08, 0.09), 0.5)
	var lean := Basis(Vector3.RIGHT, -0.28)
	var shell := Geo.Builder.new()
	shell.bevel = 0.006
	# The upper body, set back, and its sloping face.
	shell.box(Vector3(0, 0.03, -0.012), Vector3(0.15, 0.08, 0.1))
	shell.box(Vector3(0, 0.03, 0.04), Vector3(0.15, 0.085, 0.02), lean)
	Kit.mesh(root, shell.commit(white), null)
	var jaw := Geo.Builder.new()
	jaw.bevel = 0.006
	# The black base, deeper than the top, with the eyepiece on the back.
	jaw.box(Vector3(0, -0.03, 0.005), Vector3(0.152, 0.046, 0.13))
	jaw.box(Vector3(-0.045, 0.06, -0.066), Vector3(0.03, 0.022, 0.012))
	Kit.mesh(root, jaw.commit(black), null)
	# The print slot along the front of the jaw.
	Kit.mesh(root, Kit.box(Vector3(0.118, 0.005, 0.004)), Kit.matte(Color(0.01, 0.01, 0.01), 0.9), Vector3(0, -0.03, 0.071))
	# The lens on the face: a black barrel, its ring, the glass.
	var face_n := lean * Vector3(0, 0, 1)
	var lens_at := Vector3(0.0, 0.026, 0.05)
	var barrel := Kit.mesh(root, Kit.cylinder(0.032, 0.022, 24), black, lens_at + face_n * 0.01, Basis(Vector3.RIGHT, PI / 2.0 - 0.28))
	barrel.name = "Lens"
	Kit.mesh(root, Kit.cylinder(0.024, 0.024, 24), Kit.metal(Color(0.35, 0.36, 0.38), 0.3, 0.8), lens_at + face_n * 0.013, Basis(Vector3.RIGHT, PI / 2.0 - 0.28))
	Kit.mesh(root, Kit.cylinder(0.017, 0.026, 24), Kit.glass(Color(0.15, 0.2, 0.3, 0.92), 0.04), lens_at + face_n * 0.014, Basis(Vector3.RIGHT, PI / 2.0 - 0.28))
	# Viewfinder window top left, flash panel top right, a little light sensor.
	Kit.mesh(root, Kit.box(Vector3(0.026, 0.017, 0.004)), Kit.glass(Color(0.1, 0.12, 0.15, 0.95), 0.1), Vector3(-0.048, 0.06, 0.036) + face_n * 0.004, lean)
	Kit.mesh(root, Kit.box(Vector3(0.044, 0.02, 0.004)), Kit.glow(Color(0.85, 0.88, 0.9), 0.15), Vector3(0.044, 0.06, 0.036) + face_n * 0.004, lean)
	Kit.mesh(root, Kit.cylinder(0.005, 0.004, 10), Kit.matte(Color(0.12, 0.12, 0.14), 0.3), Vector3(0.05, 0.03, 0.047) + face_n * 0.004, Basis(Vector3.RIGHT, PI / 2.0 - 0.28))
	# The shutter button, red, on the face low right.
	Kit.mesh(root, Kit.cylinder(0.009, 0.01, 14), Kit.matte(Color(0.85, 0.12, 0.08), 0.35), Vector3(0.055, 0.0, 0.055) + face_n * 0.006, Basis(Vector3.RIGHT, PI / 2.0 - 0.28))
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.152, 0.12, 0.13)
	var p := Prop.make("camera", "Instant camera", root, shape, 0.7)
	return p


## E with something in the hand: the camera goes up to the eye, or comes down again.
func use(p: Prop) -> void:
	if p.kind == "camera":
		set_aim(not aiming)


func connect_hand(hand: Hand) -> void:
	hand.use_held.connect(use)
	hand.shoot.connect(func(p: Prop) -> void:
		if p.kind == "camera":
			take_photo(p))
	hand.aim_cancel.connect(func() -> void: set_aim(false))


## Up to the eye: the finder fills the view, a little narrower; LMB is the shutter and the
## hand keeps hold without the button. Down again: back to holding it with LMB.
func set_aim(on: bool) -> void:
	if aiming == on:
		return
	aiming = on
	var hand: Hand = main.player.hand
	hand.aiming = on
	camera.visible = not on
	var cam3d: Camera3D = main.player.cam
	var tw := create_tween()
	tw.tween_property(cam3d, "fov", Settings.fov * 0.72 if on else Settings.fov, 0.18)
	Sfx.play("click", -14.0, 0.6 if on else 0.5, "Suit")
	if not on and hand.held == camera and not Input.is_action_pressed("grab") and not Settings.grab_toggle:
		hand.drop()


func _process(_delta: float) -> void:
	# Dropped or thrown while up at the eye: the finder goes too.
	if aiming and main.player.hand.held != camera:
		set_aim(false)


## What the finder shows round the frame (empty when the camera is not up).
func viewfinder() -> String:
	if not aiming:
		return ""
	return "FILM %d      LMB  TAKE THE PHOTO      E  LOWER" % sim.film


func take_photo(cam: Prop) -> void:
	if _busy:
		return
	if sim.film <= 0:
		Sfx.play("error", -8.0, 1.0, "Suit")
		main.hud.toast("No film left. More from the supply catalogue: INSTANT FILM")
		return
	_busy = true
	sim.film -= 1
	Sfx.play_at("click", cam.global_position, -2.0, 0.7)
	var flash := OmniLight3D.new()
	flash.light_cull_mask = Station.INSIDE_LAYER
	flash.light_color = Color(0.95, 0.97, 1.0)
	flash.light_energy = 5.0
	flash.omni_range = 5.0
	station.add_child(flash)
	flash.global_position = cam.global_position + main.player.cam.global_basis.z * -0.2
	# The picture as the eye sees it, without the hand, the camera or the readouts.
	var hud: CanvasLayer = main.hud
	var hud_was := hud.visible
	hud.visible = false
	cam.visible = false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	hud.visible = hud_was
	cam.visible = not aiming
	flash.queue_free()
	var shot := _film_look(img)
	var n := 1
	while FileAccess.file_exists("%s/photo_%03d.png" % [DIR, n]):
		n += 1
	var file := "%s/photo_%03d.png" % [DIR, n]
	shot.save_png(ProjectSettings.globalize_path(file))
	Sfx.play_at("servo", cam.global_position, -10.0, 2.2)
	_eject(cam, file, ImageTexture.create_from_image(shot))
	main.hud.toast("Click. %d shot%s left" % [sim.film, "" if sim.film == 1 else "s"])
	_busy = false


## Square, small, and in the colours of instant film: soft blacks, warm, a little faded,
## darker at the corners.
func _film_look(src: Image) -> Image:
	var w := src.get_width()
	var h := src.get_height()
	var s := mini(w, h)
	var img := src.get_region(Rect2i((w - s) / 2, (h - s) / 2, s, s))
	img.convert(Image.FORMAT_RGB8)
	img.resize(PICTURE_PX, PICTURE_PX, Image.INTERPOLATE_BILINEAR)
	for y in PICTURE_PX:
		for x in PICTURE_PX:
			var c := img.get_pixel(x, y)
			var grey := c.r * 0.3 + c.g * 0.59 + c.b * 0.11
			c = c.lerp(Color(grey, grey, grey), 0.18)
			c = Color(c.r * 1.06 + 0.05, c.g * 0.99 + 0.045, c.b * 0.88 + 0.06)
			var d := Vector2(x, y) / PICTURE_PX - Vector2(0.5, 0.5)
			var v := 1.0 - 0.55 * d.length_squared() * 2.0
			img.set_pixel(x, y, Color(c.r * v, c.g * v, c.b * v))
	return img


## The print slides out of the slot and drifts off, developing as it goes.
func _eject(cam: Prop, file: String, tex: Texture2D) -> void:
	var look: Camera3D = main.player.cam
	var card := _print_mesh(tex, 0.0)
	var shape := BoxShape3D.new()
	shape.size = Vector3(CARD.x, CARD.y, 0.006)
	var p := Prop.make("photo", "Photo", card, shape, 0.02)
	p.set_meta("file", file)
	station.add_child(p)
	p.global_position = cam.global_position - look.global_basis.y * 0.07 - look.global_basis.z * 0.05
	p.global_basis = look.global_basis * Basis(Vector3.RIGHT, -PI / 2.0 + 0.3)
	p.linear_velocity = main.player.velocity - look.global_basis.y * 0.12 - look.global_basis.z * 0.25
	p.angular_velocity = Vector3(randf_range(-0.3, 0.3), randf_range(-0.3, 0.3), randf_range(-0.3, 0.3))
	var m: StandardMaterial3D = card.get_meta("picture")
	var tw := p.create_tween()
	tw.tween_property(m, "albedo_color", Color.WHITE, DEVELOP).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


# --- Save ------------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"pinned": pinned}


func from_dict(d: Dictionary) -> void:
	for e: Dictionary in d.get("pinned", []):
		if FileAccess.file_exists(String(e.file)):
			pinned.append(e)
			_attach(e)
