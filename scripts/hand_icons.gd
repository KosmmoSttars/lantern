class_name HandIcons
extends RefCounted
## Hand cursors (open palm and closed fist) in the game's chunky pixels: the same signed
## distance fields as before, sampled on a coarse grid into a filled pale silhouette with a
## one-pixel dark outline and dark creases, then blown up without smoothing.

const SIZE := 128
const HALF_WIDTH := 2.7
## The coarse grid, and how many screen pixels each of its cells becomes.
const GRID := 24
const CELL := 2

static var _open: Texture2D
static var _fist: Texture2D


static func open_hand() -> Texture2D:
	if _open == null:
		# Dark lines between the fingers, so they read apart at this size.
		_open = _render(false, [[Vector2(53, 24), Vector2(53, 66)], [Vector2(69, 24), Vector2(69, 66)], [Vector2(85, 34), Vector2(84, 70)]])
	return _open


static func fist() -> Texture2D:
	if _fist == null:
		# Creases between the curled fingers and the line of the thumb.
		var strokes := [
			[Vector2(48, 56), Vector2(48, 68)],
			[Vector2(64, 54), Vector2(64, 68)],
			[Vector2(80, 56), Vector2(80, 70)],
			[Vector2(34, 82), Vector2(62, 90)],
		]
		_fist = _render(true, strokes)
	return _fist


static func _open_sdf(p: Vector2) -> float:
	var d := _round_box(p, Vector2(66, 86), Vector2(22, 20), 12)
	d = minf(d, _capsule(p, Vector2(45, 70), Vector2(43, 26), 7.4))
	d = minf(d, _capsule(p, Vector2(61, 68), Vector2(61, 17), 7.4))
	d = minf(d, _capsule(p, Vector2(77, 70), Vector2(79, 23), 7.4))
	d = minf(d, _capsule(p, Vector2(89, 76), Vector2(95, 41), 6.8))
	d = minf(d, _capsule(p, Vector2(48, 94), Vector2(26, 68), 8.4))
	return d


static func _fist_sdf(p: Vector2) -> float:
	var d := _round_box(p, Vector2(64, 80), Vector2(30, 22), 16)
	d = minf(d, _circle(p, Vector2(40, 60), 11))
	d = minf(d, _circle(p, Vector2(56, 56), 11))
	d = minf(d, _circle(p, Vector2(72, 56), 11))
	d = minf(d, _circle(p, Vector2(88, 61), 10.5))
	return d


static func _sdf(closed: bool, p: Vector2) -> float:
	return _fist_sdf(p) if closed else _open_sdf(p)


static func _render(closed: bool, strokes: Array) -> Texture2D:
	var k := float(SIZE) / GRID
	var inside := []
	inside.resize(GRID * GRID)
	var crease := []
	crease.resize(GRID * GRID)
	for y in GRID:
		for x in GRID:
			var p := Vector2((x + 0.5) * k, (y + 0.5) * k)
			var sd := _sdf(closed, p)
			inside[y * GRID + x] = sd < -1.5 or (sd < 0.5 and _near(p, strokes, k * 0.55))
			var c := false
			if sd < 0.5:
				for st in strokes:
					if _segment(p, st[0], st[1]) < k * 0.55:
						c = true
			crease[y * GRID + x] = c
	var img := Image.create(GRID, GRID, false, Image.FORMAT_RGBA8)
	var fill := Color(0.93, 0.92, 0.86, 0.92)
	var dark := Color(0.04, 0.04, 0.04, 0.95)
	for y in GRID:
		for x in GRID:
			var i := y * GRID + x
			if inside[i]:
				img.set_pixel(x, y, dark if crease[i] else fill)
				continue
			# Outline: an outside cell touching the hand.
			var edge := false
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + d.x
				var ny: int = y + d.y
				if nx >= 0 and ny >= 0 and nx < GRID and ny < GRID and inside[ny * GRID + nx]:
					edge = true
			img.set_pixel(x, y, dark if edge else Color(0, 0, 0, 0))
	img.resize(GRID * CELL, GRID * CELL, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(img)


static func _near(p: Vector2, strokes: Array, r: float) -> bool:
	for st in strokes:
		if _segment(p, st[0], st[1]) < r:
			return true
	return false


static func _capsule(p: Vector2, a: Vector2, b: Vector2, r: float) -> float:
	return _segment(p, a, b) - r


static func _segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)


static func _circle(p: Vector2, c: Vector2, r: float) -> float:
	return p.distance_to(c) - r


static func _round_box(p: Vector2, c: Vector2, half: Vector2, r: float) -> float:
	var q := (p - c).abs() - (half - Vector2(r, r))
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - r
