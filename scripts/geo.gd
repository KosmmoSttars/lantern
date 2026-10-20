class_name Geo
extends RefCounted
## Batched geometry: shapes are appended into a Builder per material and committed
## as one mesh, so a module full of greebles costs a handful of draw calls. The
## builder also keeps the raw triangles, which become trimesh colliders directly
## (meshes have no readable data in a headless run).


class Builder:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	## Applied to everything added; lets callers build in a local frame.
	var xform := Transform3D.IDENTITY

	func is_empty() -> bool:
		return verts.is_empty()

	## Triangle facing `n` (winding is fixed up to match). Flat-shaded unless
	## per-vertex normals are given.
	func tri(a: Vector3, b: Vector3, c: Vector3, n: Vector3, na := Vector3.ZERO, nb := Vector3.ZERO, nc := Vector3.ZERO, ua := Vector2.ZERO, ub := Vector2.ZERO, uc := Vector2.ZERO) -> void:
		a = xform * a
		b = xform * b
		c = xform * c
		n = (xform.basis * n).normalized()
		var smooth := na != Vector3.ZERO
		if smooth:
			na = (xform.basis * na).normalized()
			nb = (xform.basis * nb).normalized()
			nc = (xform.basis * nc).normalized()
		else:
			na = n
			nb = n
			nc = n
		# Godot front faces wind clockwise seen from the front: the cross product
		# then points away from the viewer.
		if (b - a).cross(c - a).dot(n) > 0.0:
			verts.append_array([a, c, b])
			normals.append_array([na, nc, nb])
			uvs.append_array([ua, uc, ub])
		else:
			verts.append_array([a, b, c])
			normals.append_array([na, nb, nc])
			uvs.append_array([ua, ub, uc])

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, uv_scale := 1.0) -> void:
		var ua := Vector2.ZERO
		var ub := Vector2((b - a).length(), 0.0) * uv_scale
		var uc := Vector2((b - a).length(), (c - b).length()) * uv_scale
		var ud := Vector2(0.0, (d - a).length()) * uv_scale
		tri(a, b, c, n, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, ua, ub, uc)
		tri(a, c, d, n, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, ua, uc, ud)

	## Edge bevel applied to every box (0 = sharp). Bevelled edges catch the light.
	var bevel := 0.0

	## Axis-aligned (in `basis`) box; bevelled when `bevel` > 0.
	func box(center: Vector3, size: Vector3, basis := Basis()) -> void:
		var bv := minf(bevel, minf(size.x, minf(size.y, size.z)) * 0.3)
		if bv > 0.0015:
			bevel_box(center, size, basis, bv)
			return
		var h := size * 0.5
		var ax := [basis.x, basis.y, basis.z]
		var ext := [h.x, h.y, h.z]
		for i in 3:
			for s in [-1.0, 1.0]:
				var n: Vector3 = ax[i] * s
				var u: Vector3 = ax[(i + 1) % 3] * ext[(i + 1) % 3]
				var v: Vector3 = ax[(i + 2) % 3] * ext[(i + 2) % 3]
				var c: Vector3 = center + n * ext[i]
				quad(c - u - v, c + u - v, c + u + v, c - u + v, n)

	## Box with chamfered edges and corners: 6 faces, 12 edge strips, 8 corners.
	func bevel_box(center: Vector3, size: Vector3, basis: Basis, bv: float) -> void:
		var h := size * 0.5
		var c := func(sx: float, sy: float, sz: float, ix: float, iy: float, iz: float) -> Vector3:
			return center + basis * Vector3(sx * (h.x - bv * ix), sy * (h.y - bv * iy), sz * (h.z - bv * iz))
		var nb := func(v: Vector3) -> Vector3: return (basis * v).normalized()
		# Faces.
		for s in [-1.0, 1.0]:
			quad(c.call(s, -1, -1, 0, 1, 1), c.call(s, 1, -1, 0, 1, 1), c.call(s, 1, 1, 0, 1, 1), c.call(s, -1, 1, 0, 1, 1), nb.call(Vector3(s, 0, 0)))
			quad(c.call(-1, s, -1, 1, 0, 1), c.call(1, s, -1, 1, 0, 1), c.call(1, s, 1, 1, 0, 1), c.call(-1, s, 1, 1, 0, 1), nb.call(Vector3(0, s, 0)))
			quad(c.call(-1, -1, s, 1, 1, 0), c.call(1, -1, s, 1, 1, 0), c.call(1, 1, s, 1, 1, 0), c.call(-1, 1, s, 1, 1, 0), nb.call(Vector3(0, 0, s)))
		# Edge chamfers.
		for a in [-1.0, 1.0]:
			for b in [-1.0, 1.0]:
				# Edges along X (between Y and Z faces).
				quad(c.call(-1, a, b, 1, 0, 1), c.call(1, a, b, 1, 0, 1), c.call(1, a, b, 1, 1, 0), c.call(-1, a, b, 1, 1, 0), nb.call(Vector3(0, a, b)))
				# Along Y (between X and Z faces).
				quad(c.call(a, -1, b, 0, 1, 1), c.call(a, 1, b, 0, 1, 1), c.call(a, 1, b, 1, 1, 0), c.call(a, -1, b, 1, 1, 0), nb.call(Vector3(a, 0, b)))
				# Along Z (between X and Y faces).
				quad(c.call(a, b, -1, 0, 1, 1), c.call(a, b, 1, 0, 1, 1), c.call(a, b, 1, 1, 0, 1), c.call(a, b, -1, 1, 0, 1), nb.call(Vector3(a, b, 0)))
		# Corners.
		for x in [-1.0, 1.0]:
			for y in [-1.0, 1.0]:
				for z in [-1.0, 1.0]:
					tri(c.call(x, y, z, 0, 1, 1), c.call(x, y, z, 1, 0, 1), c.call(x, y, z, 1, 1, 0), nb.call(Vector3(x, y, z)))

	## Tube along a polyline with a per-point radius; parallel-transport frames,
	## smooth normals, open ends unless `caps`.
	func sweep(path: PackedVector3Array, radius: float, sides := 8, radii := PackedFloat32Array(), caps := false) -> void:
		var n := path.size()
		if n < 2:
			return
		var tangents: Array[Vector3] = []
		for k in n:
			var prev := path[maxi(k - 1, 0)]
			var next := path[mini(k + 1, n - 1)]
			tangents.append((next - prev).normalized())
		var t0 := tangents[0]
		var normal := t0.cross(Vector3.UP if absf(t0.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT).normalized()
		var rings: Array[PackedVector3Array] = []
		var dirs: Array[PackedVector3Array] = []
		for k in n:
			if k > 0:
				var axis := tangents[k - 1].cross(tangents[k])
				if axis.length() > 1e-6:
					normal = normal.rotated(axis.normalized(), tangents[k - 1].angle_to(tangents[k]))
				normal = (normal - tangents[k] * normal.dot(tangents[k])).normalized()
			var bi := tangents[k].cross(normal)
			var r := radii[k] if radii.size() == n else radius
			var ring := PackedVector3Array()
			var dd := PackedVector3Array()
			for i in sides + 1:
				var a := TAU * i / sides
				var d := normal * cos(a) + bi * sin(a)
				ring.append(path[k] + d * r)
				dd.append(d)
			rings.append(ring)
			dirs.append(dd)
		for k in n - 1:
			for i in sides:
				var a := rings[k][i]
				var b := rings[k + 1][i]
				var c := rings[k + 1][i + 1]
				var d := rings[k][i + 1]
				var nf := (dirs[k][i] + dirs[k][i + 1] + dirs[k + 1][i] + dirs[k + 1][i + 1]).normalized()
				tri(a, b, c, nf, dirs[k][i], dirs[k + 1][i], dirs[k + 1][i + 1])
				tri(a, c, d, nf, dirs[k][i], dirs[k + 1][i + 1], dirs[k][i + 1])
		if caps:
			for end in [0, n - 1]:
				var out := -tangents[0] if end == 0 else tangents[n - 1]
				for i in sides:
					tri(path[end], rings[end][i], rings[end][i + 1], out)

	## Flexible ribbed duct along a path (the ISS's corrugated air hoses).
	func duct(path: PackedVector3Array, radius: float, pitch := 0.05, sides := 12) -> void:
		var dense := PackedVector3Array()
		var radii := PackedFloat32Array()
		var acc := 0.0
		for k in path.size() - 1:
			var seg := path[k].distance_to(path[k + 1])
			var steps := maxi(int(seg / (pitch * 0.25)), 1)
			for j in steps:
				var t := float(j) / steps
				dense.append(path[k].lerp(path[k + 1], t))
				radii.append(radius * (1.0 + 0.09 * cos(TAU * (acc + seg * t) / pitch)))
			acc += seg
		dense.append(path[path.size() - 1])
		radii.append(radius)
		sweep(dense, radius, sides, radii)

	## Cylinder along `axis` (unit) between two points, smooth sides, flat caps.
	func cylinder(from: Vector3, to: Vector3, radius: float, sides := 12, caps := true) -> void:
		var axis := (to - from).normalized()
		var helper := Vector3.UP if absf(axis.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
		var u := axis.cross(helper).normalized()
		var v := axis.cross(u)
		for i in sides:
			var a0 := TAU * i / sides
			var a1 := TAU * (i + 1) / sides
			var d0 := u * cos(a0) + v * sin(a0)
			var d1 := u * cos(a1) + v * sin(a1)
			var n := (d0 + d1).normalized()
			tri(from + d0 * radius, to + d0 * radius, to + d1 * radius, n, d0, d0, d1)
			tri(from + d0 * radius, to + d1 * radius, from + d1 * radius, n, d0, d1, d1)
			if caps:
				tri(from, from + d0 * radius, from + d1 * radius, -axis)
				tri(to, to + d1 * radius, to + d0 * radius, axis)

	## Open tube along X from x0 to x1. `inward` flips it to be seen from inside.
	func tube_x(radius: float, x0: float, x1: float, sides := 32, inward := false, uv_scale := 1.0) -> void:
		for i in sides:
			var a0 := TAU * i / sides
			var a1 := TAU * (i + 1) / sides
			var d0 := Vector3(0.0, cos(a0), sin(a0))
			var d1 := Vector3(0.0, cos(a1), sin(a1))
			var s := -1.0 if inward else 1.0
			var n := (d0 + d1).normalized() * s
			var u0 := a0 * radius * uv_scale
			var u1 := a1 * radius * uv_scale
			tri(Vector3(x0, 0, 0) + d0 * radius, Vector3(x1, 0, 0) + d0 * radius, Vector3(x1, 0, 0) + d1 * radius, n, d0 * s, d0 * s, d1 * s,
				Vector2(u0, x0 * uv_scale), Vector2(u0, x1 * uv_scale), Vector2(u1, x1 * uv_scale))
			tri(Vector3(x0, 0, 0) + d0 * radius, Vector3(x1, 0, 0) + d1 * radius, Vector3(x0, 0, 0) + d1 * radius, n, d0 * s, d1 * s, d1 * s,
				Vector2(u0, x0 * uv_scale), Vector2(u1, x1 * uv_scale), Vector2(u1, x0 * uv_scale))

	## tube_x cut into `rows` bands along X; a cell whose middle (in the builder's output space)
	## fails `keep` is left out. For a hull other hulls pass through.
	func tube_x_cut(radius: float, x0: float, x1: float, sides: int, rows: int, keep: Callable, uv_scale := 1.0) -> void:
		for r in rows:
			var xa := lerpf(x0, x1, float(r) / rows)
			var xb := lerpf(x0, x1, float(r + 1) / rows)
			for i in sides:
				var a0 := TAU * i / sides
				var a1 := TAU * (i + 1) / sides
				var d0 := Vector3(0.0, cos(a0), sin(a0))
				var d1 := Vector3(0.0, cos(a1), sin(a1))
				var n := (d0 + d1).normalized()
				if not keep.call(xform * (Vector3((xa + xb) * 0.5, 0, 0) + n * radius)):
					continue
				var u0 := a0 * radius * uv_scale
				var u1 := a1 * radius * uv_scale
				tri(Vector3(xa, 0, 0) + d0 * radius, Vector3(xb, 0, 0) + d0 * radius, Vector3(xb, 0, 0) + d1 * radius, n, d0, d0, d1,
					Vector2(u0, xa * uv_scale), Vector2(u0, xb * uv_scale), Vector2(u1, xb * uv_scale))
				tri(Vector3(xa, 0, 0) + d0 * radius, Vector3(xb, 0, 0) + d1 * radius, Vector3(xa, 0, 0) + d1 * radius, n, d0, d1, d1,
					Vector2(u0, xa * uv_scale), Vector2(u1, xb * uv_scale), Vector2(u1, xa * uv_scale))

	## Flat ring in the YZ plane at `x`, between two star-shaped outlines given as
	## functions of angle (returning (y, z)). Faces `facing` (+1 = +X).
	func ring_x(x: float, outer: Callable, inner: Callable, facing: float, segments := 48) -> void:
		var n := Vector3(facing, 0, 0)
		for i in segments:
			var a0 := TAU * i / segments
			var a1 := TAU * (i + 1) / segments
			var o0: Vector2 = outer.call(a0)
			var o1: Vector2 = outer.call(a1)
			var i0: Vector2 = inner.call(a0)
			var i1: Vector2 = inner.call(a1)
			quad(Vector3(x, o0.x, o0.y), Vector3(x, o1.x, o1.y), Vector3(x, i1.x, i1.y), Vector3(x, i0.x, i0.y), n)

	## Side band of an extruded outline between x0 and x1 (a hatch tunnel, a frame
	## lip). Normals point away from the axis unless `inward`.
	func band_x(x0: float, x1: float, outline: Callable, inward := false, segments := 48) -> void:
		for i in segments:
			var a0 := TAU * i / segments
			var a1 := TAU * (i + 1) / segments
			var p0: Vector2 = outline.call(a0)
			var p1: Vector2 = outline.call(a1)
			var e := p1 - p0
			var n2 := Vector2(e.y, -e.x).normalized()
			if n2.dot(p0 + p1) < 0.0:
				n2 = -n2
			if inward:
				n2 = -n2
			var n := Vector3(0, n2.x, n2.y)
			quad(Vector3(x0, p0.x, p0.y), Vector3(x1, p0.x, p0.y), Vector3(x1, p1.x, p1.y), Vector3(x0, p1.x, p1.y), n)

	## Surface of revolution around X: profile points are (x, radius).
	func lathe_x(profile: PackedVector2Array, sides := 32, outward := true) -> void:
		for j in profile.size() - 1:
			var p0 := profile[j]
			var p1 := profile[j + 1]
			var step := p1 - p0
			for i in sides:
				var a0 := TAU * i / sides
				var a1 := TAU * (i + 1) / sides
				var d0 := Vector3(0.0, cos(a0), sin(a0))
				var d1 := Vector3(0.0, cos(a1), sin(a1))
				# Outward normal of the profile segment, rotated around.
				var nr0 := (d0 * step.x - Vector3(step.y, 0, 0)).normalized()
				var nr1 := (d1 * step.x - Vector3(step.y, 0, 0)).normalized()
				if not outward:
					nr0 = -nr0
					nr1 = -nr1
				var a := Vector3(p0.x, 0, 0) + d0 * p0.y
				var b := Vector3(p1.x, 0, 0) + d0 * p1.y
				var c := Vector3(p1.x, 0, 0) + d1 * p1.y
				var d := Vector3(p0.x, 0, 0) + d1 * p0.y
				var n := (nr0 + nr1).normalized()
				if (b - a).length() > 1e-5:
					tri(a, b, c, n, nr0, nr0, nr1)
				if (d - c).length() > 1e-5:
					tri(a, c, d, n, nr0, nr1, nr1)

	func commit(mat: Material) -> ArrayMesh:
		var m := ArrayMesh.new()
		if verts.is_empty():
			return m
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		m.surface_set_material(0, mat)
		return m

	## The triangles as a one-sided trimesh shape.
	func shape() -> ConcavePolygonShape3D:
		var s := ConcavePolygonShape3D.new()
		s.backface_collision = true
		s.set_faces(verts)
		return s


## Outline helpers for ring_x.
static func circle(r: float) -> Callable:
	return func(a: float) -> Vector2: return Vector2(cos(a), sin(a)) * r


static func square(h: float) -> Callable:
	return func(a: float) -> Vector2:
		var d := Vector2(cos(a), sin(a))
		return d * (h / maxf(absf(d.x), absf(d.y)))


static func ellipse(ry: float, rz: float) -> Callable:
	return func(a: float) -> Vector2: return Vector2(cos(a) * ry, sin(a) * rz)


## Rounded square (superellipse): ISS-style hatch openings.
static func rounded_square(h: float, power := 5.0) -> Callable:
	return func(a: float) -> Vector2:
		var c := cos(a)
		var s := sin(a)
		var r := pow(pow(absf(c), power) + pow(absf(s), power), -1.0 / power)
		return Vector2(c, s) * r * h


## Square with its corners cut at 45 degrees (the module cross-section).
static func octagon(h: float, chamfer: float) -> Callable:
	return func(a: float) -> Vector2:
		var d := Vector2(cos(a), sin(a))
		var t := h / maxf(absf(d.x), absf(d.y))
		var t2 := (2.0 * h - chamfer) / (absf(d.x) + absf(d.y))
		return d * minf(t, t2)
