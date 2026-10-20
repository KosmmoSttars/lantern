class_name Outline
extends RefCounted
## White silhouette outline for whatever the hand is aimed at.
## Inverted hull pushed outward in screen space, so the line stays a few pixels
## wide at any distance. Vertices move away from the mesh center rather than along
## normals, which keeps hard-edged boxes from splitting at the corners.

const SHADER := """
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float width = 2.5;

void vertex() {
	vec3 dir = length(VERTEX) > 1e-5 ? normalize(VERTEX) : NORMAL;
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec4 clip_dir = PROJECTION_MATRIX * vec4(mat3(MODELVIEW_MATRIX) * dir, 0.0);
	vec2 d = clip_dir.xy;
	if (length(d) > 1e-6) {
		clip.xy += normalize(d) / VIEWPORT_SIZE * width * 2.0 * clip.w;
	}
	POSITION = clip;
}

void fragment() {
	ALBEDO = color.rgb;
}
"""

static var _material: ShaderMaterial


static func material() -> ShaderMaterial:
	if _material == null:
		var sh := Shader.new()
		sh.code = SHADER
		_material = ShaderMaterial.new()
		_material.shader = sh
	return _material


static func apply(root: Node, on: bool) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).material_overlay = material() if on else null
