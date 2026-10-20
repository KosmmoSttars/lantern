class_name Prop
extends RigidBody3D
## Loose object floating in zero G. `kind` decides which sockets accept it and
## which jobs it can do as a tool; datapads carry `text` to read while held.

var kind := ""
var display_name := ""
var text := ""
## Socket the prop is seated in, if any.
var seated_in: Node = null

var _last_hit := 0.0


static func make(p_kind: String, p_name: String, mesh_root: Node3D, shape: Shape3D, p_mass := 1.0) -> Prop:
	var p := Prop.new()
	p.kind = p_kind
	p.display_name = p_name
	p.name = p_kind.capitalize().replace(" ", "")
	p.mass = p_mass
	p.add_child(mesh_root)
	Kit.collider(p, shape)
	# Small things cast no shadow: floating by a lamp (or in the hand), a book threw one across
	# half the module, black in the dim cabin.
	if p_kind in NO_SHADOW:
		_no_shadow(mesh_root)
	return p


const NO_SHADOW := ["manual", "flashlight", "geiger", "camera", "photo"]


static func _no_shadow(n: Node) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		_no_shadow(c)


func _ready() -> void:
	add_to_group("props")
	# (Again here: some get more meshes after make(), the reactor book its trefoil.)
	if kind in NO_SHADOW:
		_no_shadow(self)
	collision_layer = Layers.PROPS
	collision_mask = Layers.WORLD | Layers.FURNITURE | Layers.PROPS | Layers.PLAYER | Layers.USE
	gravity_scale = 0.0
	linear_damp = 0.12
	angular_damp = 0.15
	contact_monitor = true
	max_contacts_reported = 2
	continuous_cd = true
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.25
	pm.friction = 0.6
	physics_material_override = pm
	body_entered.connect(_on_hit)


func _on_hit(_other: Node) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var speed := linear_velocity.length()
	if speed > 0.6 and now - _last_hit > 0.25:
		_last_hit = now
		Sfx.play_at("thud", global_position, linear_to_db(clampf(speed / 3.0, 0.1, 1.0)) - 6.0, clampf(2.0 / sqrt(mass), 0.8, 1.6))
