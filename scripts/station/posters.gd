class_name Posters
extends RefCounted
## Safety posters taped to the walls, the kind every station has: a paper sheet with a coloured
## header (DANGER red, CAUTION yellow with hazard stripes, NOTICE blue, SAFETY green), a bold
## pictogram, a title and a line or two of advice. Built in the wall's frame: x across the
## sheet, y up it, z out of the wall.

const W := 0.3
const H := 0.42

## [style, title, text, pictogram, the modules it belongs in]
const SET := [
	["DANGER", "OUTER HATCH: NO INTERLOCK", "Pump the airlock down to VACUUM\nbefore you turn the wheel.", "warn", ["Airlock"]],
	["CAUTION", "CLIP ON FIRST", "The button on the hose reel.\nThen the hatch.", "o2", ["Airlock"]],
	["CAUTION", "HOLD ON", "A loose keeper is a hazard\nto every switch aboard.", "hand", ["Command deck", "Node"]],
	["DANGER", "HIGH VOLTAGE", "Buses A and B carry 120 V.\nBreaker out before you touch.", "volt", ["Engineering"]],
	["DANGER", "RADIATION", "Reactor aft of Life support.\nDo not linger by the shield.", "rad", ["Engineering", "Life support"]],
	["NOTICE", "FLARE SHELTER", "On a flare warning go aft to\nLIFE SUPPORT and stay there.", "arrow", ["Habitation", "Node"]],
	["CAUTION", "NO OPEN FLAMES", "Not even a birthday candle.", "noflame", ["Habitation"]],
	["NOTICE", "SECURE LOOSE ITEMS", "A floating pen is a projectile.", "warn", ["Node", "Engineering"]],
	["SAFETY", "WATER IS LIFE", "Keep the recycler running.", "drop", ["Life support"]],
	["SAFETY", "FIRE: MASK FIRST", "Breathing apparatus on\nbefore you look for the fire.", "o2", ["Life support", "Habitation"]],
]

const STYLE := {
	"DANGER": [Color(0.72, 0.09, 0.06), Color(0.98, 0.96, 0.92)],
	"CAUTION": [Color(0.96, 0.76, 0.1), Color(0.06, 0.05, 0.03)],
	"NOTICE": [Color(0.13, 0.28, 0.58), Color(0.98, 0.97, 0.94)],
	"SAFETY": [Color(0.1, 0.46, 0.24), Color(0.98, 0.97, 0.94)],
}


## One poster under `parent`, its back on the wall at `xf`. `faded`: an old one, sun-bleached.
static func make(parent: Node3D, xf: Transform3D, style: String, title: String, text: String, pict: String, faded := false, tilt := 0.0) -> Node3D:
	var root := Node3D.new()
	root.transform = xf * Transform3D(Basis(Vector3.BACK, tilt), Vector3.ZERO)
	parent.add_child(root)
	var fade := func(c: Color) -> Color: return c.lerp(Color(0.85, 0.82, 0.74), 0.45) if faded else c
	var colors: Array = STYLE.get(style, STYLE["NOTICE"])
	var band: Color = fade.call(colors[0])
	var on_band: Color = fade.call(colors[1])
	var ink: Color = fade.call(Color(0.08, 0.07, 0.06))
	var paper := Color(0.9, 0.88, 0.8) if not faded else Color(0.84, 0.8, 0.68)
	Kit.mesh(root, Kit.box(Vector3(W, H, 0.002)), Kit.matte(paper, 0.95), Vector3(0, 0, 0.001))
	# Header band and its word.
	Kit.mesh(root, Kit.box(Vector3(W - 0.02, 0.07, 0.001)), Kit.matte(band, 0.8), Vector3(0, H * 0.5 - 0.05, 0.0025))
	var head := Ctl.text(root, style, Vector3(0, H * 0.5 - 0.05, 0.0032), 0.032, on_band)
	head.shaded = true
	Ctl.fit(head, W - 0.05, 0.05)
	if style == "CAUTION":
		# Hazard stripes along the foot of the sheet.
		var stripes := Geo.Builder.new()
		for k in 9:
			stripes.box(Vector3(-W * 0.5 + 0.025 + k * 0.032, -H * 0.5 + 0.022, 0.0026), Vector3(0.012, 0.05, 0.001), Basis(Vector3.BACK, 0.6))
		Kit.mesh(root, Kit.box(Vector3(W - 0.02, 0.026, 0.001)), Kit.matte(band, 0.8), Vector3(0, -H * 0.5 + 0.022, 0.0024))
		Kit.mesh(root, stripes.commit(Kit.matte(Color(0.06, 0.05, 0.03), 0.8)), null)
	_pictogram(root, pict, Vector3(0, 0.055, 0.003), band, ink)
	var t := Ctl.text(root, title, Vector3(0, -0.06, 0.003), 0.026, ink)
	t.shaded = true
	Ctl.fit(t, W - 0.04, 0.05)
	var body := Ctl.text(root, text, Vector3(0, -0.125, 0.003), 0.013, ink)
	body.shaded = true
	Ctl.fit(body, W - 0.04, 0.06)
	# Tape on the corners.
	var tape := Kit.glass(Color(0.85, 0.85, 0.8, 0.55), 0.05)
	for c in [Vector2(-1, 1), Vector2(1, 1), Vector2(-1, -1), Vector2(1, -1)]:
		Kit.mesh(root, Kit.box(Vector3(0.045, 0.016, 0.001)), tape, Vector3(c.x * (W * 0.5 - 0.01), c.y * (H * 0.5 - 0.01), 0.0034), Basis(Vector3.BACK, c.x * c.y * 0.7))
	return root


## A bold pictogram round `c`, about eight centimetres across.
static func _pictogram(root: Node3D, kind: String, c: Vector3, band: Color, ink: Color) -> void:
	var b := Geo.Builder.new()
	var accent := Geo.Builder.new()
	var line := func(builder: Geo.Builder, a: Vector2, e: Vector2, w: float) -> void:
		var mid := (a + e) * 0.5
		var d := e - a
		builder.box(c + Vector3(mid.x, mid.y, 0), Vector3(d.length() + w, w, 0.001), Basis(Vector3.BACK, d.angle()))
	var ring := func(builder: Geo.Builder, r: float, w: float) -> void:
		for k in 24:
			var a0 := TAU * k / 24.0
			var a1 := TAU * (k + 1) / 24.0
			line.call(builder, Vector2(cos(a0), sin(a0)) * r, Vector2(cos(a1), sin(a1)) * r, w)
	match kind:
		"warn":
			var p := [Vector2(0, 0.05), Vector2(0.048, -0.035), Vector2(-0.048, -0.035)]
			for k in 3:
				line.call(b, p[k], p[(k + 1) % 3], 0.008)
			b.box(c + Vector3(0, 0.008, 0), Vector3(0.008, 0.032, 0.001))
			b.box(c + Vector3(0, -0.02, 0), Vector3(0.008, 0.008, 0.001))
		"o2":
			ring.call(b, 0.042, 0.007)
			Ctl.text(root, "O2", c + Vector3(0, -0.002, 0.0004), 0.03, ink).shaded = true
		"hand":
			line.call(b, Vector2(-0.05, 0.02), Vector2(0.05, 0.02), 0.01)
			for k in 4:
				var x := -0.015 + k * 0.012
				line.call(accent, Vector2(x, 0.03), Vector2(x, -0.015), 0.009)
			line.call(accent, Vector2(-0.03, 0.005), Vector2(-0.02, -0.025), 0.009)
			accent.box(c + Vector3(0.003, -0.03, 0), Vector3(0.05, 0.03, 0.001))
		"volt":
			line.call(accent, Vector2(0.015, 0.05), Vector2(-0.015, 0.0), 0.012)
			line.call(accent, Vector2(-0.015, 0.0), Vector2(0.015, 0.0), 0.012)
			line.call(accent, Vector2(0.015, 0.0), Vector2(-0.015, -0.05), 0.012)
			var tri := [Vector2(0, 0.06), Vector2(0.055, -0.04), Vector2(-0.055, -0.04)]
			for k in 3:
				line.call(b, tri[k], tri[(k + 1) % 3], 0.006)
		"rad":
			b.box(c, Vector3(0.012, 0.012, 0.001))
			for k in 3:
				var a := TAU * k / 3.0 + PI / 2.0
				for r in [0.016, 0.024, 0.032, 0.04]:
					line.call(b, Vector2(cos(a - 0.45), sin(a - 0.45)) * r, Vector2(cos(a + 0.45), sin(a + 0.45)) * r, 0.009)
		"noflame":
			accent.box(c + Vector3(0, -0.008, 0), Vector3(0.022, 0.03, 0.001))
			accent.box(c + Vector3(0, 0.012, 0), Vector3(0.012, 0.022, 0.001), Basis(Vector3.BACK, 0.3))
			ring.call(b, 0.045, 0.008)
			line.call(b, Vector2(-0.032, 0.032), Vector2(0.032, -0.032), 0.008)
		"arrow":
			line.call(b, Vector2(-0.045, 0), Vector2(0.03, 0), 0.014)
			line.call(b, Vector2(0.05, 0), Vector2(0.022, 0.026), 0.012)
			line.call(b, Vector2(0.05, 0), Vector2(0.022, -0.026), 0.012)
		"drop":
			accent.box(c + Vector3(0, -0.01, 0), Vector3(0.05, 0.05, 0.001), Basis(Vector3.BACK, PI / 4.0))
			accent.box(c + Vector3(0, -0.012, 0), Vector3(0.056, 0.03, 0.001))
	if not b.is_empty():
		Kit.mesh(root, b.commit(Kit.matte(ink, 0.8)), null)
	if not accent.is_empty():
		var acc := Color(0.15, 0.4, 0.8) if kind == "drop" else (Color(0.95, 0.45, 0.08) if kind == "noflame" else band)
		Kit.mesh(root, accent.commit(Kit.matte(acc, 0.8)), null)
