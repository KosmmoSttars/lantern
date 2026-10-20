class_name MapScreen
extends RefCounted
## The map on the flight desk, drawn on a CRT you can touch. Two scales:
##   system  the system seen from its north: click a body to pick it as the destination
##           (the map then centres on it), the wheel zooms
##   galaxy  zoom out past the system's edge: the star map. Only the systems the station has
##           been to are charted (the Solar System to begin with); the rest is fog. Touch a
##           charted star, or anywhere in the dark, and the computer plots a crossing to the
##           star nearest that point, whatever it turns out to be. One thing shows through
##           the fog: the radio pulses of the nearest pulsar. Wheel right in: the system.
## The readout gives the distance, how long the flight would take and what it would burn, or
## what stands in the way.

const PICK_PX := 18.0

var flight: Flight
var sim: ShipSim
var screen: Terminal
var touch: Interactable
## The body the map is centred on, and metres per screen pixel.
var center := 0
var mpp := 1.0e6
var galaxy: Galaxy
## Derelicts' state, to mark the empty ones (set by main).
var salvage: Salvage
## "system" or "galaxy".
var mode := "system"
## Galaxy scale: light years per screen pixel, and the star picked (-1: none).
var lpp := 0.06
var star_target := -1
## Where in the dark the keeper touched (light years, galaxy frame), INF when the target is
## a charted star.
var aim_pos := Vector3.INF
## How far round a charted system the fog is lifted (light years).
const CHARTED_LY := 1.4
## How far from a touch in the dark the computer will look for a star (light years).
const SEARCH_LY := 6.0

var _system := -1


func setup(p_flight: Flight, p_sim: ShipSim, p_screen: Terminal) -> void:
	flight = p_flight
	sim = p_sim
	screen = p_screen
	screen.draw_fn = _draw
	# Held on to like any screen; E opens it full size, where a click picks, a drag turns it
	# and the wheel zooms (the wheel zooms it in place too).
	touch = screen.it
	touch.display_name = "Map"
	touch.on_wheel = func(dir: int) -> void: zoom(dir)
	screen.click_fn = click_px
	screen.drag_fn = drag
	screen.wheel_fn = zoom
	# Beside the map seen full size: the derelicts and modules in this system, nearest first.
	screen.list_title = "CONTACTS"
	screen.list_fn = contacts
	screen.pick_fn = pick_contact
	touch.value_fn = func() -> String:
		if mode == "galaxy":
			if star_target < 0:
				return "no star picked"
			if not galaxy.visited.has(star_target):
				return "uncharted" if aim_pos != Vector3.INF else "radio source"
			return String(galaxy.star(star_target).get("name", "?"))
		return String(flight.u.bodies[flight.c_target].name)
	focus(flight.soi)


func _res() -> Vector2:
	return Vector2(maxi(int(screen.size.x * screen.px_per_m), 32), maxi(int(screen.size.y * screen.px_per_m), 24))


## Centre on body b, zoomed to show what goes round it.
func focus(b: int) -> void:
	var u := flight.u
	center = b
	var extent := 0.0
	for i in u.bodies.size():
		if int(u.bodies[i].parent) == b:
			extent = maxf(extent, float(u.bodies[i].a))
	if extent <= 0.0:
		extent = maxf(float(u.bodies[b].radius) * 40.0, flight.transit_radius(b) * 3.0)
	# Round the body the station falls round: its own orbit fills the view, the globe big in it.
	if b == flight.soi and float(u.bodies[b].mu) > 0.0:
		var el := Orbit.elements(flight.st, float(u.bodies[b].mu))
		var far := float(el.get("ap", INF))
		if far == INF or is_nan(far):
			far = Orbit.length(Orbit.pos(flight.st))
		extent = maxf(far, float(u.bodies[b].radius) * 2.5)
	var r := _res()
	mpp = extent * 1.15 / (minf(r.x, r.y) * 0.45)
	screen.refresh()


## Centre the map on body b and keep the scale: the view glides over to it, and the wheel then
## zooms in on it.
func center_on(b: int) -> void:
	if b == center:
		return
	var u := flight.u
	# The picture does not jump: it starts where it was and eases over to b.
	_pan_from = Orbit.to_vec(Orbit.sub(u.position(b, flight.t), u.position(center, flight.t))) + _pan_now()
	_pan_t0 = Time.get_ticks_msec() / 1000.0
	center = b
	mpp = maxf(mpp, _min_mpp())
	screen.refresh()


## Where the view is still gliding from after a re-centre (metres from the centred body).
var _pan_from := Vector3.ZERO
var _pan_t0 := -10.0
const PAN_TIME := 0.45


func _pan_now() -> Vector3:
	var k := clampf((Time.get_ticks_msec() / 1000.0 - _pan_t0) / PAN_TIME, 0.0, 1.0)
	return _pan_from * (1.0 - smoothstep(0.0, 1.0, k))


func _panning() -> bool:
	return Time.get_ticks_msec() / 1000.0 - _pan_t0 < PAN_TIME


## Zoomed in no closer than keeps the camera well outside the centred globe.
func _min_mpp() -> float:
	return maxf(float(flight.u.bodies[center].radius) * 2.6, 20.0) / _focal()


## A derelict or a module drawn on top of the world it goes round (too far out to tell them
## apart): not shown, not picked, until the map is close enough (or it is the one picked).
func _tucked(i: int) -> bool:
	var b := flight.u.bodies[i]
	if not b.kind in ["derelict", "module"] or i == flight.c_target or i == center:
		return false
	var par: int = b.parent
	return par >= 0 and _to_px(i).distance_to(_to_px(par)) < 12.0


func zoom(dir: int) -> void:
	Sfx.play_at("click", screen.global_position, -18.0, 1.6)
	if mode == "system":
		mpp = maxf(mpp * pow(2.0, -dir), _min_mpp())
		# Out past the edge of the system: the stars.
		if dir < 0 and mpp * minf(_res().x, _res().y) * 0.5 > _system_extent() * 1.5:
			mode = "galaxy"
			lpp = 0.04
	else:
		lpp *= pow(1.6, -dir)
		if dir > 0 and lpp < 0.015:
			mode = "system"
			focus(0)
		lpp = clampf(lpp, 0.01, 1.5)
	screen.refresh()


## Radius of the outermost orbit round the system's primary.
func _system_extent() -> float:
	var e := 0.0
	for b in flight.u.bodies:
		if int(b.parent) == 0:
			e = maxf(e, float(b.a))
	return maxf(e, 1.0e9)


## A touch at world point p: pick the nearest marker to it.
func click(p: Vector3) -> void:
	var local := screen.global_transform.affine_inverse() * p
	var uv := Vector2(local.x / screen.size.x + 0.5, 0.5 - local.y / screen.size.y)
	# The tube bulges the picture; undo it so the touch lands where the eye sees.
	var c := uv * 2.0 - Vector2.ONE
	c *= 1.0 + 0.045 * c.dot(c)
	uv = c * 0.5 + Vector2(0.5, 0.5)
	click_px(uv * _res())


## Derelicts and modules in this system, nearest first: [[body index, line], ...].
func contacts() -> Array:
	var u := flight.u
	var me := flight.world_pos()
	var found := []
	for i in u.bodies.size():
		var b := u.bodies[i]
		if not b.kind in ["derelict", "module"] or b.get("gone", false):
			continue
		var d := Orbit.length(Orbit.sub(u.position(i, flight.t), me))
		var what := Loc.t(String(b.get("class", "")))
		if b.kind == "derelict" and salvage != null and salvage.empty(u, i):
			what += " " + Loc.t("EMPTY")
		var par: int = b.parent
		var line := "%s%s  %s  %s  %s" % ["> " if i == flight.c_target else "", String(b.name), what, StationPanels.km(d).strip_edges(), Loc.t(String(u.bodies[par].name)) if par >= 0 else ""]
		found.append([d, i, line])
	found.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	return found.map(func(e: Array) -> Array: return [e[1], e[2]])


## A contact picked from the list: the destination, the map centred on it and zoomed out just
## far enough to show the world it goes round.
func pick_contact(i: int) -> void:
	mode = "system"
	flight.c_target = i
	center_on(i)
	var r := _res()
	mpp = maxf(float(flight.u.bodies[i].a) * 2.4 / minf(r.x, r.y), _min_mpp())
	screen.refresh()


## A touch at screen pixel px (as the tube shows it, the bulge already undone).
func click_px(px: Vector2) -> void:
	if mode == "galaxy":
		_click_star(px)
		return
	var best := -1
	var best_d := PICK_PX
	var u := flight.u
	for i in u.bodies.size():
		if u.bodies[i].get("gone", false) or _tucked(i):
			continue
		var q := _to_px(i)
		var d := q.distance_to(px)
		if d < best_d:
			best_d = d
			best = i
	if best < 0:
		Sfx.play_at("beep_low", screen.global_position, -14.0)
		return
	flight.c_target = best
	center_on(best)
	Sfx.play_at("beep", screen.global_position, -10.0)
	screen.refresh()


func _star_px(pos: Vector3) -> Vector2:
	var d := pos - galaxy.here_pos
	return _res() * 0.5 + Vector2(d.x, d.z) / lpp


## A star whose place the keeper knows: one visited, or the pulsar heard through the fog.
func charted(id: int) -> bool:
	return galaxy.visited.has(id) or id == galaxy.pulsar_id()


## The stars the map can show: the visited ones and the pulsar. (Generating every star out
## to the edge of a zoomed-out map, hundreds of light years, was what made it crawl.)
func _known_stars() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: int in galaxy.visited:
		var e := galaxy.star(id)
		if not e.is_empty():
			out.append(e)
	var pid := galaxy.pulsar_id()
	if not galaxy.visited.has(pid):
		out.append(galaxy.star(pid))
	return out


func _click_star(px: Vector2) -> void:
	# A charted star under the finger.
	var best := -1
	var best_d := PICK_PX
	for e in _known_stars():
		var d := _star_px(e.pos).distance_to(px)
		if d < best_d:
			best_d = d
			best = e.id
	if best >= 0 and best != galaxy.here:
		star_target = best
		aim_pos = Vector3.INF
		Sfx.play_at("beep", screen.global_position, -10.0)
		screen.refresh()
		return
	# Anywhere in the dark: course for whatever star lies nearest that point.
	var off := (px - _res() * 0.5) * lpp
	var g := galaxy.here_pos + Vector3(off.x, 0.0, off.y)
	var found := -1
	var found_d := INF
	for e in galaxy.stars_near(g, SEARCH_LY):
		if int(e.id) == galaxy.here:
			continue
		var p: Vector3 = e.pos
		var d := Vector2(p.x - g.x, p.z - g.z).length()
		if d < found_d:
			found_d = d
			found = e.id
	if found < 0:
		Sfx.play_at("beep_low", screen.global_position, -14.0)
		return
	star_target = found
	aim_pos = g if not charted(found) else Vector3.INF
	Sfx.play_at("beep", screen.global_position, -10.0)
	screen.refresh()


func _rel(i: int) -> PackedFloat64Array:
	var u := flight.u
	return Orbit.sub(u.position(i, flight.t), u.position(center, flight.t))


func _relv(i: int) -> Vector3:
	return Orbit.to_vec(_rel(i))


# --- The 3D view --------------------------------------------------------------------------------
# The system seen in perspective from a camera that circles the centred body: wireframe globes,
# a grid on the system's plane, the orbits. Drag the screen to turn it; the wheel zooms.

## The camera's bearing round the centre and its height above the plane (radians).
var yaw := 0.7
var pitch := 0.5
const VIEW_HALF := 0.55


## The hand dragging across the screen turns the view.
func drag(rel: Vector2) -> void:
	if mode != "system":
		return
	yaw -= rel.x * 0.008
	pitch = clampf(pitch + rel.y * 0.006, -1.45, 1.45)
	screen.refresh()


func _focal() -> float:
	return _res().y * 0.5 / tan(VIEW_HALF)


## Where the camera stands: as far from the centre as makes `mpp` metres a pixel there.
func _cam_dist() -> float:
	return mpp * _focal()


func _view() -> Basis:
	return Basis(Vector3.RIGHT, pitch) * Basis(Vector3.UP, yaw)


## A point (metres from the centred body) on the screen: x, y in pixels and its depth (<= 0:
## behind the camera).
func _proj(rel: Vector3) -> Vector3:
	var c := _view() * ((rel + _pan_now()) / _cam_dist())
	var depth := 1.0 - c.z
	if depth < 0.03:
		return Vector3(0, 0, -1)
	var f := _focal()
	var r := _res()
	return Vector3(r.x * 0.5 + f * c.x / depth, r.y * 0.5 - f * c.y / depth, depth)


## The camera's place, in the same frame as the points.
func _cam_pos() -> Vector3:
	return _view().inverse() * Vector3(0, 0, _cam_dist())


func _px(rel: PackedFloat64Array) -> Vector2:
	var q := _proj(Orbit.to_vec(rel))
	return Vector2(q.x, q.y) if q.z > 0.0 else Vector2(-1e5, -1e5)


func _to_px(i: int) -> Vector2:
	return _px(_rel(i))


func _poly(c: Control, pts: PackedVector3Array, col: Color, closed := false) -> void:
	var prev := Vector3(0, 0, -1)
	var first := Vector3(0, 0, -1)
	for k in pts.size():
		var q := _proj(pts[k])
		if k == 0:
			first = q
		if q.z > 0.0 and prev.z > 0.0:
			c.draw_line(Vector2(prev.x, prev.y), Vector2(q.x, q.y), col, 1.0)
		prev = q
	if closed and first.z > 0.0 and prev.z > 0.0:
		c.draw_line(Vector2(prev.x, prev.y), Vector2(first.x, first.y), col, 1.0)


## A globe in wire: its disc blacked out (what is behind it is hidden), then the lines of
## latitude and longitude on the side that faces the camera.
func _globe(c: Control, at: Vector3, radius: float, col: Color, rings := Vector2.ZERO) -> float:
	var q := _proj(at)
	if q.z <= 0.0:
		return 0.0
	var r_px := _focal() * (radius / _cam_dist()) / q.z
	var centre := Vector2(q.x, q.y)
	if r_px < 3.0:
		c.draw_circle(centre, 2.0, col)
		return 2.0
	c.draw_circle(centre, r_px, Color(0, 0, 0, 1))
	var cam := _cam_pos()
	var seg := 24
	var lines: Array[PackedVector3Array] = []
	for lat in [-60.0, -30.0, 0.0, 30.0, 60.0]:
		var la := deg_to_rad(lat)
		var ring := PackedVector3Array()
		for k in seg + 1:
			var a := TAU * k / seg
			ring.append(Vector3(cos(la) * cos(a), sin(la), cos(la) * sin(a)))
		lines.append(ring)
	for m in 12:
		var lo := TAU * m / 12.0
		var mer := PackedVector3Array()
		for k in seg / 2 + 1:
			var b := -PI * 0.5 + PI * k / (seg / 2)
			mer.append(Vector3(cos(b) * cos(lo), sin(b), cos(b) * sin(lo)))
		lines.append(mer)
	for line in lines:
		for k in line.size() - 1:
			var a := at + line[k] * radius
			var b := at + line[k + 1] * radius
			var mid := (a + b) * 0.5
			# Only the near side shows.
			if (mid - at).dot(cam - mid) <= 0.0:
				continue
			var pa := _proj(a)
			var pb := _proj(b)
			if pa.z > 0.0 and pb.z > 0.0:
				c.draw_line(Vector2(pa.x, pa.y), Vector2(pb.x, pb.y), col, 1.0)
	c.draw_arc(centre, r_px, 0.0, TAU, 48, col, 1.0)
	if rings != Vector2.ZERO:
		for rr in [rings.x, rings.y]:
			var pts := PackedVector3Array()
			for k in 64:
				var a := TAU * k / 64.0
				pts.append(at + Vector3(cos(a), 0.0, sin(a)) * rr)
			_poly(c, pts, Color(col, 0.6), true)
	return r_px


## The grid on the system's plane round the centre, spaced in round numbers of kilometres.
func _grid(c: Control) -> void:
	var span := mpp * _res().y * 1.6
	var raw := span / 10.0
	var p10 := pow(10.0, floor(log(raw) / log(10.0)))
	var step := p10
	for k in [1.0, 2.0, 5.0, 10.0]:
		if p10 * k >= raw:
			step = p10 * k
			break
	var n := 8
	for i in range(-n, n + 1):
		var fade := 0.16 * (1.0 - absf(float(i)) / (n + 1))
		var col := Color(1, 1, 1, fade)
		var a := PackedVector3Array()
		var b := PackedVector3Array()
		for k in 17:
			var t := (-n + 2.0 * n * k / 16.0) * step
			a.append(Vector3(i * step, 0.0, t))
			b.append(Vector3(t, 0.0, i * step))
		_poly(c, a, col)
		_poly(c, b, col)


## The station's own path round the body it is falling round, with its high and low points.
func _ship_orbit(c: Control, font: Font, col: Color) -> void:
	var u := flight.u
	var mu: float = u.bodies[flight.soi].mu
	if mu <= 0.0:
		return
	var at := _relv(flight.soi)
	var r := Orbit.to_vec(Orbit.pos(flight.st))
	var v := Orbit.to_vec(Orbit.vel(flight.st))
	var h := r.cross(v)
	if h.length() < 1e-6:
		return
	var ev := v.cross(h) / mu - r.normalized()
	var e := ev.length()
	var p_axis := ev / e if e > 1e-6 else r.normalized()
	var q_axis := h.normalized().cross(p_axis)
	var semi := h.length_squared() / mu
	var nu_max := PI if e < 1.0 else acos(-1.0 / e) - 0.05
	var pts := PackedVector3Array()
	var steps := 128
	for k in steps + 1:
		var nu := -nu_max + 2.0 * nu_max * k / steps
		var rr := semi / (1.0 + e * cos(nu))
		if rr < 0.0 or rr > 1e13:
			continue
		pts.append(at + (p_axis * cos(nu) + q_axis * sin(nu)) * rr)
	_poly(c, pts, col)
	var el := Orbit.elements(flight.st, mu)
	var marks := [["PE", 0.0, float(el.get("t_pe", INF))]]
	if e < 1.0:
		marks.append(["AP", PI, float(el.get("t_ap", INF))])
	for m: Array in marks:
		var nu: float = m[1]
		var rr := semi / (1.0 + e * cos(nu))
		var q := _proj(at + (p_axis * cos(nu) + q_axis * sin(nu)) * rr)
		if q.z <= 0.0:
			continue
		var s := Vector2(q.x, q.y)
		c.draw_rect(Rect2(s - Vector2(2, 2), Vector2(4, 4)), col)
		c.draw_string(font, s + Vector2(5, -3), "T-%s: %s" % [m[0], _clock(m[2])], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)


## Seconds as h:mm:ss, or dashes.
static func _clock(secs: float) -> String:
	if secs == INF or is_nan(secs) or secs < 0.0:
		return "--:--:--"
	var s := int(secs)
	return "%02d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]


func _draw(c: Control, size: Vector2) -> void:
	var u := flight.u
	if u.system_id != _system:
		_system = u.system_id
		mode = "system"
		star_target = -1
		focus(flight.soi)
	if mode == "galaxy":
		_draw_galaxy(c, size)
		return
	var col := Color.WHITE
	var dim := Color(1, 1, 1, 0.45)
	var faint := Color(1, 1, 1, 0.22)
	var font := Ctl.mono()
	_grid(c)
	# Orbits of what goes round what, in the plane each one really lies in.
	for i in u.bodies.size():
		var b := u.bodies[i]
		var par: int = b.parent
		if par < 0 or b.kind == "gate" or b.get("gone", false):
			continue
		var a: float = b.a
		if a / mpp < 4.0 or a / mpp > size.x * 40.0:
			continue
		var pc := _relv(par)
		var pts := PackedVector3Array()
		for k in 96:
			var th := TAU * k / 96.0
			pts.append(pc + u._tilt(b, Vector3(cos(th), 0.0, -sin(th))) * a)
		_poly(c, pts, faint, true)
	# Bodies, far ones first so the near ones cover them.
	var order: Array = []
	for i in u.bodies.size():
		var q := _proj(_relv(i))
		if q.z > 0.0 and not u.bodies[i].get("gone", false) and not _tucked(i):
			order.append([q.z, i])
	order.sort_custom(func(x: Array, y: Array) -> bool: return x[0] > y[0])
	for e: Array in order:
		var i: int = e[1]
		var b := u.bodies[i]
		var at := _relv(i)
		var q := _proj(at)
		var s := Vector2(q.x, q.y)
		if s.x < -40.0 or s.y < -40.0 or s.x > size.x + 40.0 or s.y > size.y + 40.0:
			continue
		var r_px := 2.0
		match String(b.kind):
			"star", "planet", "moon":
				var rings := Vector2.ZERO
				if b.has("rings"):
					rings = Vector2(float(b.rings[0]), float(b.rings[1]))
				r_px = _globe(c, at, float(b.radius), col if b.kind != "moon" else dim, rings)
			"derelict", "module":
				var d := 3.5
				var looted: bool = b.kind == "derelict" and salvage != null and salvage.empty(u, i)
				c.draw_rect(Rect2(s - Vector2(d, d), Vector2(d, d) * 2.0), col if not looted else dim, false, 1.0)
				if b.kind == "module":
					c.draw_line(s - Vector2(d, 0), s + Vector2(d, 0), col, 1.0)
				if looted:
					c.draw_line(s - Vector2(d, d), s + Vector2(d, d), dim, 1.0)
		# Names only for what is near enough to matter here, and spread out enough to read.
		var spacing: float = float(b.get("a", 1e30)) / mpp
		var near := q.z < 2.5
		if i == flight.c_target or i == center or (near and spacing > 30.0) or (b.kind == "star" and near):
			c.draw_string(font, s + Vector2(maxf(r_px, 3.0) + 4.0, -3.0), Loc.t(String(b.name)), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, dim if i != flight.c_target else col)
	# The station: its orbit, itself, and a line to where it is bound.
	_ship_orbit(c, font, col)
	var me := Orbit.to_vec(Orbit.sub(flight.world_pos(), u.position(center, flight.t)))
	var mq := _proj(me)
	var tq := _to_px(flight.c_target)
	if mq.z > 0.0:
		var ms := Vector2(mq.x, mq.y)
		var vrel := Orbit.to_vec(Orbit.sub(flight.world_vel(), u.velocity(center, flight.t)))
		var ahead := _proj(me + vrel.normalized() * mpp * 20.0 * mq.z) if vrel.length() > 0.01 else mq
		var fwd := Vector2.UP
		if ahead.z > 0.0 and Vector2(ahead.x, ahead.y).distance_to(ms) > 0.5:
			fwd = (Vector2(ahead.x, ahead.y) - ms).normalized()
		var side := Vector2(-fwd.y, fwd.x)
		c.draw_colored_polygon(PackedVector2Array([ms + fwd * 8.0, ms - fwd * 4.0 + side * 4.5, ms - fwd * 1.5, ms - fwd * 4.0 - side * 4.5]), col)
		c.draw_dashed_line(ms, tq, Color(1, 1, 1, 0.45), 1.0, 4.0)
	var bs := 9.0
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var k: Vector2 = tq + corner * bs
		c.draw_line(k, k - Vector2(corner.x * 4.0, 0), col, 1.0)
		c.draw_line(k, k - Vector2(0, corner.y * 4.0), col, 1.0)
	_readout(c, size, font)
	# Still gliding over to a new centre: draw again next frame.
	if _panning():
		screen.refresh()


func _readout(c: Control, size: Vector2, font: Font) -> void:
	var u := flight.u
	var b := flight.c_target
	var lines := PackedStringArray()
	# The station's own state round what it orbits.
	var mu: float = u.bodies[flight.soi].mu
	var rn := Orbit.length(Orbit.pos(flight.st))
	# Where the station is (what the map is centred on may be somewhere else entirely).
	lines.append(Loc.t("ORBIT %s") % Loc.t(String(u.bodies[flight.soi].name)).to_upper())
	lines.append(Loc.t("VELOCITY:"))
	lines.append("  %.1f M/S" % Orbit.length(Orbit.vel(flight.st)))
	lines.append(Loc.t("ALTITUDE:"))
	lines.append("  %s" % StationPanels.km(rn - float(u.bodies[flight.soi].radius)).strip_edges())
	lines.append(Loc.t("T-ORBIT:"))
	var period := float(Orbit.elements(flight.st, mu).get("period", INF)) if mu > 0.0 else INF
	lines.append("  " + _clock(period))
	lines.append("")
	lines.append(Loc.t("DEST %s") % Loc.t(String(u.bodies[b].name)).to_upper())
	if u.bodies[b].kind == "derelict":
		lines.append(Loc.t("DERELICT %s%s") % [String(u.bodies[b].get("class", "")), Loc.t("  EMPTY") if salvage != null and salvage.empty(u, b) else ""])
	elif u.bodies[b].kind == "module":
		lines.append(Loc.t("MODULE %s") % Loc.t(String(u.bodies[b].get("class", ""))))
	if not flight.transit.is_empty():
		lines.append(Loc.t("IN TRANSIT"))
		lines.append(Loc.t("ARRIVE IN %s") % Flight.game_duration(flight.transit_left()))
	else:
		lines.append(Loc.t("DIST %s") % StationPanels.km(flight.transit_distance(b)).strip_edges())
		lines.append(Loc.t("FLIGHT %s") % Flight.game_duration(flight.transit_duration(b)))
		lines.append(Loc.t("FUEL %d kg D-HE3") % roundi(flight.transit_fuel(b)))
		var why := flight.transit_blocker(b, sim)
		lines.append(Loc.t("ENGAGE READY") if why == "" else Loc.t(why))
	# The tube bulges its picture and pushes the corners out of sight: the text keeps well in.
	var y := TEXT_TOP
	var wide := 0.0
	for l in lines:
		wide = maxf(wide, font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x)
	# On a dark plate, so the bodies' names behind it never run into it.
	c.draw_rect(Rect2(TEXT_LEFT - 5.0, TEXT_TOP - 13.0, minf(wide, size.x - TEXT_LEFT * 2.0) + 10.0, lines.size() * 13.0 + 6.0), Color(0, 0, 0, 0.85))
	for l in lines:
		c.draw_string(font, Vector2(TEXT_LEFT, y), l, HORIZONTAL_ALIGNMENT_LEFT, size.x - TEXT_LEFT * 2.0, 12, Color.WHITE)
		y += 13.0
	c.draw_string(font, Vector2(TEXT_LEFT, size.y - TEXT_BOTTOM), Loc.t("DRAG  TURN    WHEEL  ZOOM"), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.45))


## Text margins on the tube (pixels): clear of its curved, darkened edge.
const TEXT_LEFT := 24.0
const TEXT_TOP := 30.0
const TEXT_BOTTOM := 30.0


func _draw_galaxy(c: Control, size: Vector2) -> void:
	var font := Ctl.mono()
	var col := Color.WHITE
	var dim := Color(1, 1, 1, 0.4)
	var me := _star_px(galaxy.here_pos)
	if star_target >= 0 and charted(star_target):
		aim_pos = Vector3.INF
	var stars := _known_stars()
	# The fog: a field of faint dots everywhere but round the charted systems.
	var clear: Array[Vector2] = [me]
	for e in stars:
		if galaxy.visited.has(int(e.id)):
			clear.append(_star_px(e.pos))
	var r_px := CHARTED_LY / lpp
	var step := 9.0
	var yy := fmod(me.y, step)
	while yy < size.y:
		var xx := fmod(me.x, step)
		while xx < size.x:
			var q := Vector2(xx, yy)
			var open := false
			for cq in clear:
				if q.distance_squared_to(cq) < r_px * r_px:
					open = true
					break
			if not open:
				c.draw_rect(Rect2(q, Vector2(1, 1)), Color(1, 1, 1, 0.16))
			xx += step
		yy += step
	for cq in clear:
		c.draw_arc(cq, r_px, 0.0, TAU, 48, Color(1, 1, 1, 0.12), 1.0)
	# How far the computer can plot without a pulsar fix.
	if not galaxy.pulsar_fix:
		c.draw_arc(me, Galaxy.FREE_RANGE / lpp, 0.0, TAU, 96, Color(1, 1, 1, 0.22), 1.0)
		c.draw_string(font, me + Vector2(4.0, -Galaxy.FREE_RANGE / lpp - 3.0), Loc.t("10 LY  NO PULSAR FIX"), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.35))
	for e in stars:
		var id := int(e.id)
		var q := _star_px(e.pos)
		if q.x < -10.0 or q.y < -10.0 or q.x > size.x + 10.0 or q.y > size.y + 10.0:
			continue
		if galaxy.visited.has(id):
			var kind: String = e.kind
			match kind:
				"pulsar":
					c.draw_circle(q, 2.0, col)
					c.draw_line(q + Vector2(-6, -6), q + Vector2(6, 6), dim, 1.0)
					c.draw_line(q + Vector2(-6, 6), q + Vector2(6, -6), dim, 1.0)
				"black hole":
					c.draw_arc(q, 4.0, 0.0, TAU, 16, col, 1.5)
				"rogue planet", "brown dwarf":
					c.draw_arc(q, 2.5, 0.0, TAU, 12, dim, 1.0)
				"blue giant":
					c.draw_circle(q, 3.5, col)
				_:
					c.draw_circle(q, 2.5 if kind != "red dwarf" else 1.8, col)
			c.draw_arc(q, 6.0, 0.0, TAU, 16, Color(1, 1, 1, 0.3), 1.0)
			c.draw_string(font, q + Vector2(6.0, -4.0), String(e.name).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, dim if id != star_target else col)
		elif id == galaxy.pulsar_id():
			# Heard, not seen: rings beating out from where the pulses come from.
			var beat := fmod(Time.get_ticks_msec() / 900.0, 1.0)
			c.draw_arc(q, 3.0 + beat * 9.0, 0.0, TAU, 20, Color(1, 1, 1, 0.6 * (1.0 - beat)), 1.0)
			c.draw_circle(q, 1.5, Color(1, 1, 1, 0.7))
			c.draw_string(font, q + Vector2(8.0, -4.0), Loc.t("RADIO PULSES"), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, dim)
	# Where the station is.
	c.draw_colored_polygon(PackedVector2Array([me + Vector2(0, -7), me + Vector2(5, 5), me + Vector2(-5, 5)]), col)
	if star_target >= 0:
		var e := galaxy.star(star_target)
		if not e.is_empty():
			var tq := _star_px(e.pos) if aim_pos == Vector3.INF else _star_px(aim_pos)
			c.draw_dashed_line(me, tq, Color(1, 1, 1, 0.5), 1.0, 4.0)
			for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var k: Vector2 = tq + corner * 9.0
				c.draw_line(k, k - Vector2(corner.x * 4.0, 0), col, 1.0)
				c.draw_line(k, k - Vector2(0, corner.y * 4.0), col, 1.0)
			if aim_pos != Vector3.INF:
				c.draw_string(font, tq + Vector2(-3.0, 4.0), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)
	var lines := PackedStringArray()
	lines.append("STAR MAP  FROM %s" % flight.u.system_name.to_upper())
	if star_target >= 0 and not galaxy.star(star_target).is_empty():
		var e2 := galaxy.star(star_target)
		var d := galaxy.distance(star_target)
		if aim_pos != Vector3.INF:
			lines.append("DEST UNCHARTED")
			lines.append("DIST ~%d LY" % roundi(d))
			lines.append("FLIGHT ~%s" % Flight.game_duration(Galaxy.travel_time(d)))
			lines.append("FUEL ~%d kg D-HE3" % (roundi(Galaxy.travel_fuel(d) / 10.0) * 10))
		elif galaxy.visited.has(star_target):
			lines.append("DEST %s  %s" % [String(e2.name).to_upper(), String(e2.kind).to_upper()])
			lines.append("DIST %.2f LY" % d)
			lines.append("FLIGHT %s" % Flight.game_duration(Galaxy.travel_time(d)))
			lines.append("FUEL %d kg D-HE3" % roundi(Galaxy.travel_fuel(d)))
		else:
			lines.append("DEST RADIO SOURCE")
			lines.append("DIST %.1f LY" % d)
			lines.append("FLIGHT %s" % Flight.game_duration(Galaxy.travel_time(d)))
			lines.append("FUEL %d kg D-HE3" % roundi(Galaxy.travel_fuel(d)))
		var why := galaxy.plot_blocker(star_target)
		if why == "" and not sim.torch_lit:
			why = "TORCH NOT LIT"
		lines.append("ENGAGE READY" if why == "" else why)
	else:
		lines.append("TOUCH A STAR, OR ANYWHERE IN THE DARK")
	if not flight.transit.is_empty() and flight.transit.has("interstellar"):
		lines.append("BETWEEN THE STARS: %s" % Flight.game_duration(flight.transit_left()))
	var y := TEXT_TOP
	for l in lines:
		c.draw_string(font, Vector2(TEXT_LEFT, y), Loc.t(l), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
		y += 13.0
	c.draw_string(font, Vector2(TEXT_LEFT, size.y - TEXT_BOTTOM), Loc.t("SCALE %.1f LY / 100 px   WHEEL IN: BACK TO THE SYSTEM" % (lpp * 100.0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.45))
