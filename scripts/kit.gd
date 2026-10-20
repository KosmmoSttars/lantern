class_name Kit
extends RefCounted
## Small helpers for building geometry and materials in code.


static func metal(color: Color, roughness := 0.35, metallic := 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	return m


static func matte(color: Color, roughness := 0.8) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	return m


static func glow(color: Color, energy := 2.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


static func glass(color: Color, energy := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = Color(color, 1.0)
	m.emission_energy_multiplier = energy
	m.roughness = 0.05
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func mesh(parent: Node3D, m: Mesh, mat: Material, pos := Vector3.ZERO, basis := Basis()) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.transform = Transform3D(basis, pos)
	parent.add_child(mi)
	return mi


static func box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func cylinder(radius: float, height: float, sides := 24, top := -1.0) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.bottom_radius = radius
	c.top_radius = radius if top < 0.0 else top
	c.height = height
	c.radial_segments = sides
	c.rings = 1
	return c


static func sphere(radius: float, segments := 16) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = segments
	s.rings = segments / 2
	return s


static func collider(body: CollisionObject3D, shape: Shape3D, pos := Vector3.ZERO, basis := Basis()) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = Transform3D(basis, pos)
	body.add_child(cs)
	return cs


## Basis whose Y axis points along `dir` (cylinders are built along Y).
static func basis_y_to(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var helper := Vector3.FORWARD if absf(y.dot(Vector3.UP)) > 0.9 else Vector3.UP
	var x := helper.cross(y).normalized()
	var z := x.cross(y)
	return Basis(x, y, z)


## Regular prism or frustum with flat-shaded faces, axis along Y.
## Side face i is centered at angle offset + (i + 0.5) * TAU / sides, measured from +X toward +Z.
static func frustum(r_bottom: float, r_top: float, y0: float, y1: float, sides: int, offset := 0.0, caps := true) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bottom: Array[Vector3] = []
	var top: Array[Vector3] = []
	for i in sides + 1:
		var a := offset + TAU * i / sides
		var d := Vector3(cos(a), 0.0, sin(a))
		bottom.append(d * r_bottom + Vector3.UP * y0)
		top.append(d * r_top + Vector3.UP * y1)
	for i in sides:
		_quad(st, bottom[i], bottom[i + 1], top[i + 1], top[i])
	if caps:
		var cb := Vector3.UP * y0
		var ct := Vector3.UP * y1
		for i in sides:
			_tri(st, cb, bottom[i + 1], bottom[i])
			_tri(st, ct, top[i], top[i + 1])
	st.generate_normals()
	return st.commit()


## Collision hull matching `frustum` (computed directly, so it also works headless).
static func frustum_shape(r_bottom: float, r_top: float, y0: float, y1: float, sides: int, offset := 0.0) -> ConvexPolygonShape3D:
	var pts := PackedVector3Array()
	for i in sides:
		var a := offset + TAU * i / sides
		var d := Vector3(cos(a), 0.0, sin(a))
		pts.append(d * r_bottom + Vector3.UP * y0)
		pts.append(d * r_top + Vector3.UP * y1)
	var shape := ConvexPolygonShape3D.new()
	shape.points = pts
	return shape


static func box_shape(size: Vector3) -> BoxShape3D:
	var b := BoxShape3D.new()
	b.size = size
	return b


## Outward face frame for frustum side i: origin at the face center, Y = face normal,
## Z = down the slope (toward someone standing at the face), X along the face edge.
static func frustum_face(r_bottom: float, r_top: float, y0: float, y1: float, sides: int, i: int, offset := 0.0) -> Transform3D:
	var a := offset + TAU * (i + 0.5) / sides
	var d := Vector3(cos(a), 0.0, sin(a))
	var k := cos(PI / sides)
	var apo_b := r_bottom * k
	var apo_t := r_top * k
	var center := d * (apo_b + apo_t) * 0.5 + Vector3.UP * (y0 + y1) * 0.5
	var n := (d * (y1 - y0) + Vector3.UP * (apo_b - apo_t)).normalized()
	var slope := (d * (apo_b - apo_t) + Vector3.UP * (y0 - y1)).normalized()
	var x := n.cross(slope).normalized()
	return Transform3D(Basis(x, n, slope), center)


## Surface of revolution around Y. `profile` holds (radius, height) points; the side
## to the right of the walking direction (radius to the right, height up) faces out.
## UV: u around (repeated `u_repeat` times), v along the profile in meters.
static func lathe(profile: PackedVector2Array, sides: int, u_repeat := 1.0, a0 := 0.0, a1 := TAU) -> ArrayMesh:
	var rings: Array[PackedVector3Array] = []
	var vs := PackedFloat32Array()
	var acc := 0.0
	for j in profile.size():
		if j > 0:
			acc += profile[j].distance_to(profile[j - 1])
		vs.append(acc)
		var ring := PackedVector3Array()
		for i in sides + 1:
			var a := lerpf(a0, a1, float(i) / sides)
			ring.append(Vector3(cos(a) * profile[j].x, profile[j].y, sin(a) * profile[j].x))
		rings.append(ring)
	var us := PackedFloat32Array()
	for i in sides + 1:
		us.append(float(i) / sides * u_repeat)
	# Outward hints for the winding test: the right-hand normal of each profile step.
	var hints := PackedVector3Array()
	for j in profile.size() - 1:
		var step := profile[j + 1] - profile[j]
		hints.append(Vector3(cos(a0) * step.y, -step.x, sin(a0) * step.y))
	return _grid(rings, us, vs, hints)


## Tube swept along `path` with per-point `radii`. The cross-section is an ellipse
## (`aspect` = minor/major) that twists `twist` turns along the length, which makes
## ribbon-like coral. UV: u around, v along the path in meters.
static func sweep(path: PackedVector3Array, radii: PackedFloat32Array, sides := 12, aspect := 1.0, twist := 0.0, closed := false) -> ArrayMesh:
	var n := path.size()
	var tangents := PackedVector3Array()
	for k in n:
		var prev := path[k - 1] if k > 0 else (path[n - 2] if closed else path[k])
		var next := path[k + 1] if k < n - 1 else (path[1] if closed else path[k])
		tangents.append((next - prev).normalized())
	# Parallel-transport frame keeps the tube from flipping.
	var normal := tangents[0].cross(Vector3.UP if absf(tangents[0].dot(Vector3.UP)) < 0.9 else Vector3.RIGHT).normalized()
	var length := 0.0
	var total := 0.0
	for k in range(1, n):
		total += path[k].distance_to(path[k - 1])
	var rings: Array[PackedVector3Array] = []
	var vs := PackedFloat32Array()
	var outs: Array[PackedVector3Array] = []
	for k in n:
		if k > 0:
			length += path[k].distance_to(path[k - 1])
			var axis := tangents[k - 1].cross(tangents[k])
			if axis.length() > 1e-6:
				normal = normal.rotated(axis.normalized(), tangents[k - 1].angle_to(tangents[k]))
			normal = (normal - tangents[k] * normal.dot(tangents[k])).normalized()
		var binormal := tangents[k].cross(normal)
		var turn := TAU * twist * (length / maxf(total, 1e-4))
		var ring := PackedVector3Array()
		var out := PackedVector3Array()
		for i in sides + 1:
			var a := TAU * float(i) / sides
			var c := cos(a)
			var s := sin(a) * aspect
			var dir := normal * cos(turn) + binormal * sin(turn)
			var dir2 := -normal * sin(turn) + binormal * cos(turn)
			var off := (dir * c + dir2 * s) * radii[k]
			ring.append(path[k] + off)
			out.append(off.normalized())
		rings.append(ring)
		outs.append(out)
		vs.append(length)
	var us := PackedFloat32Array()
	for i in sides + 1:
		us.append(float(i) / sides)
	var hints := PackedVector3Array()
	for j in n - 1:
		hints.append(outs[j][0])
	return _grid(rings, us, vs, hints)


## Builds an indexed, smooth-shaded grid from rings of vertices. `hints[j]` is the
## direction the surface should face at ring j, column 0; the first non-degenerate
## quad uses it to pick the triangle winding.
static func _grid(rings: Array[PackedVector3Array], us: PackedFloat32Array, vs: PackedFloat32Array, hints: PackedVector3Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cols := us.size()
	for j in rings.size():
		for i in cols:
			st.set_uv(Vector2(us[i], vs[j]))
			st.add_vertex(rings[j][i])
	# Godot front faces are clockwise: (b - a) x (c - a) must point inward.
	var flip := false
	for j in rings.size() - 1:
		var a := rings[j][0]
		var cr := (rings[j][1] - a).cross(rings[j + 1][1] - a)
		if cr.length() < 1e-8:
			cr = (rings[j + 1][1] - a).cross(rings[j + 1][0] - a)
		if cr.length() > 1e-8:
			flip = cr.dot(hints[j]) > 0.0
			break
	for j in rings.size() - 1:
		for i in cols - 1:
			var p0 := j * cols + i
			var p1 := p0 + 1
			var p2 := p0 + cols + 1
			var p3 := p0 + cols
			if flip:
				st.add_index(p0)
				st.add_index(p2)
				st.add_index(p1)
				st.add_index(p0)
				st.add_index(p3)
				st.add_index(p2)
			else:
				st.add_index(p0)
				st.add_index(p1)
				st.add_index(p2)
				st.add_index(p0)
				st.add_index(p2)
				st.add_index(p3)
	st.generate_normals()
	st.generate_tangents()
	return st.commit()


## Catenary-like sagging curve between two points, for hanging cables.
static func sag(from: Vector3, to: Vector3, droop: float, segments := 16) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for k in segments + 1:
		var t := float(k) / segments
		pts.append(from.lerp(to, t) + Vector3.DOWN * droop * 4.0 * t * (1.0 - t))
	return pts


## Cubic Bezier sampled into points.
static func bezier(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, segments := 24) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for k in segments + 1:
		var t := float(k) / segments
		var u := 1.0 - t
		pts.append(p0 * u * u * u + p1 * 3.0 * u * u * t + p2 * 3.0 * u * t * t + p3 * t * t * t)
	return pts


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	# Godot treats clockwise triangles as front faces.
	_tri(st, a, b, c)
	_tri(st, a, c, d)
