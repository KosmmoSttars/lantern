class_name Flashlight
extends RefCounted
## A hand torch: an aluminium tube with a knurled grip, a wide head and a rubber tail switch.
## E (in the hand) or F (in either hand) switches it. Carried, it shines where you look; let
## go of it lit, it shines where it points, turning slowly in the air.

## Where it waits at the start: by the flight desk, within reach of the waking keeper.
const HOME := Vector3(0.28, -0.12, -12.15)
## The lens, in the prop's own frame: the torch points along its -Z.
const LENS := Vector3(0, 0, -0.085)

var prop: Prop
var on := false
var beam: SpotLight3D
var _lens: MeshInstance3D
var _lens_on: StandardMaterial3D
var _lens_off: StandardMaterial3D


func build(station: Station) -> void:
	prop = make_prop()
	station.add_child(prop)
	prop.position = HOME
	prop.rotation = Vector3(0.2, 2.2, 0.4)
	prop.angular_velocity = Vector3(0.02, -0.05, 0.03)
	_lens = prop.get_meta("lens")
	_lens_off = _lens.material_override
	_lens_on = Kit.glow(Color(1.0, 0.92, 0.78), 4.0)
	beam = SpotLight3D.new()
	beam.name = "TorchBeam"
	beam.light_color = Color(1.0, 0.92, 0.8)
	beam.light_energy = 2.4
	beam.spot_range = 9.0
	beam.spot_angle = 16.0
	beam.spot_angle_attenuation = 2.2
	beam.spot_attenuation = 1.1
	beam.shadow_enabled = true
	beam.shadow_bias = 0.04
	beam.light_size = 0.02
	beam.light_volumetric_fog_energy = 0.35
	beam.visible = false
	station.add_child(beam)


func toggle() -> void:
	on = not on
	Sfx.play_at("click", prop.global_position, -6.0, 1.3 if on else 1.0)


## Each frame: the beam from the lens, along the view while a hand holds it.
func update(hand: Hand) -> void:
	if prop == null or not is_instance_valid(prop):
		beam.visible = false
		return
	_lens.material_override = _lens_on if on else _lens_off
	# In a pocket: no light gets out.
	beam.visible = on and prop.is_visible_in_tree()
	if not beam.visible:
		return
	var lens := prop.global_transform * LENS
	var carried := hand.held == prop or hand.offhand == prop
	if carried:
		beam.global_transform = Transform3D(hand.cam.global_basis, lens)
	else:
		beam.global_transform = Transform3D(prop.global_basis, lens)


## The torch: tail cap at +Z, lens at -Z. 18 cm long, 4.4 cm across the head.
static func make_prop() -> Prop:
	var r := Node3D.new()
	var alu := Geo.Builder.new()
	# Body, head flare and bezel: one lathe along Z (lathe_x turns round X, so turn it).
	alu.xform = Transform3D(Basis(Vector3.UP, -PI / 2.0), Vector3.ZERO)
	alu.lathe_x(PackedVector2Array([
		Vector2(-0.09, 0.0), Vector2(-0.09, 0.02), Vector2(-0.087, 0.022), Vector2(-0.06, 0.022),
		Vector2(-0.035, 0.0145), Vector2(0.075, 0.0145), Vector2(0.078, 0.0155), Vector2(0.088, 0.0155),
		Vector2(0.09, 0.0)]), 24)
	alu.xform = Transform3D.IDENTITY
	Kit.mesh(r, alu.commit(Kit.metal(Color(0.16, 0.17, 0.19), 0.45, 0.85)), null)
	# Knurled grip rings and the rubber tail switch.
	var grip := Geo.Builder.new()
	for k in 7:
		var z := -0.005 + k * 0.011
		grip.cylinder(Vector3(0, 0, z), Vector3(0, 0, z + 0.006), 0.0158, 16)
	Kit.mesh(r, grip.commit(Kit.metal(Color(0.1, 0.1, 0.11), 0.6, 0.7)), null)
	var tail := Geo.Builder.new()
	tail.cylinder(Vector3(0, 0, 0.09), Vector3(0, 0, 0.098), 0.011, 16)
	Kit.mesh(r, tail.commit(Kit.matte(Color(0.06, 0.06, 0.06), 0.8)), null)
	# The pocket clip.
	var clip := Geo.Builder.new()
	clip.box(Vector3(0, 0.0165, 0.04), Vector3(0.007, 0.0015, 0.06))
	clip.box(Vector3(0, 0.0152, 0.071), Vector3(0.007, 0.004, 0.004))
	Kit.mesh(r, clip.commit(Kit.metal(Color(0.6, 0.62, 0.65), 0.3, 0.8)), null)
	# The lens: dark glass, lit when on.
	var lens := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.019
	disc.bottom_radius = 0.019
	disc.height = 0.002
	disc.radial_segments = 24
	lens.mesh = disc
	lens.rotation.x = PI / 2.0
	lens.position = Vector3(0, 0, -0.0885)
	lens.material_override = Kit.metal(Color(0.55, 0.56, 0.5), 0.1, 0.6)
	r.add_child(lens)
	var shape := CylinderShape3D.new()
	shape.radius = 0.02
	shape.height = 0.19
	var p := Prop.make("flashlight", "Flashlight", r, shape, 0.25)
	(p.get_child(p.get_child_count() - 1) as Node).set("rotation", Vector3(PI / 2.0, 0, 0))
	p.set_meta("lens", lens)
	return p
