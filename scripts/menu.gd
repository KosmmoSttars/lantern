class_name Menu
extends CanvasLayer
## Title screen, pause menu and settings, built from real Controls so they work with the
## mouse, keyboard and gamepad. Laid out for 1600 x 900 and scaled to the window. The look
## is the station's own: a pixel-art name in amber, menu entries like lines on a terminal,
## live telemetry from the running sim in CRT green, and a settings console with a tab rail,
## arrow selectors, ON/OFF switches and a line explaining whatever is under the cursor.
## Settings live in the Settings autoload; every change is applied and saved at once.

signal choice(what: String)

const ACCENT := Color(1.0, 0.72, 0.32)
const DIM := Color(0.62, 0.65, 0.68)
const TEXT := Color(0.9, 0.9, 0.88)
const GREEN := Color(0.45, 1.0, 0.62)
const BASE := Vector2(1600, 900)

var mode := ""   # "", "title", "pause"
var continue_day := 0
## Lines of live telemetry for the corner readout (set by main).
var status_fn: Callable

var _root: Control
var _shade: ColorRect
var _fade_left: TextureRect
var _left: VBoxContainer
var _logo: TextureRect
var _tagline: Label
var _paused: Label
var _main_box: VBoxContainer
var _footer: Label
var _telemetry: PanelContainer
var _telemetry_text: Label
var _settings: PanelContainer
var _rail: VBoxContainer
var _rows: VBoxContainer
var _page_title: Label
var _describe: Label
var _confirm: PanelContainer
var _confirm_text: Label
var _confirm_yes: Button
var _confirm_what := ""
var _page := "game"
var _waiting := ""
var _theme: Theme
var _mono: Font
var _status_t := 0.0
var _quiet := true

const PAGES := [["game", "GAME"], ["controls", "CONTROLS"], ["display", "DISPLAY"], ["audio", "AUDIO"]]


func _ready() -> void:
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS
	_mono = Ctl.mono()
	_theme = _make_theme()
	_root = Control.new()
	_root.theme = _theme
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_shade = ColorRect.new()
	_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_shade)
	# A dark wash from the left edge, so the name and the entries read over any view.
	var g := Gradient.new()
	g.set_color(0, Color(0.0, 0.005, 0.01, 0.92))
	g.set_color(1, Color(0.0, 0.005, 0.01, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0.0, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	_fade_left = TextureRect.new()
	_fade_left.texture = gt
	_fade_left.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_fade_left.offset_right = 900
	_fade_left.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_fade_left.stretch_mode = TextureRect.STRETCH_SCALE
	_fade_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_fade_left)

	_left = VBoxContainer.new()
	_left.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_left.offset_left = 110
	_left.offset_right = 640
	_left.alignment = BoxContainer.ALIGNMENT_CENTER
	_left.add_theme_constant_override("separation", 8)
	_root.add_child(_left)
	_logo = TextureRect.new()
	_logo.texture = _logo_texture()
	_logo.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	_logo.custom_minimum_size = Vector2(_logo.texture.get_width(), _logo.texture.get_height()) * 2.5
	_logo.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_left.add_child(_logo)
	var rule := ColorRect.new()
	rule.color = Color(ACCENT, 0.55)
	rule.custom_minimum_size = Vector2(470, 2)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_left.add_child(rule)
	_tagline = _mono_label("ONE KEEPER  ·  ONE STATION  ·  SATURN AND BEYOND", 15, DIM)
	_left.add_child(_tagline)
	_paused = _mono_label("// PAUSED", 18, ACCENT)
	_left.add_child(_paused)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 34)
	_left.add_child(gap)
	_main_box = VBoxContainer.new()
	_main_box.add_theme_constant_override("separation", 4)
	_left.add_child(_main_box)

	_footer = _mono_label("", 13, Color(DIM, 0.8))
	_footer.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_footer.offset_left = 110
	_footer.offset_top = -56
	_footer.offset_bottom = -30
	_root.add_child(_footer)

	_telemetry = PanelContainer.new()
	_telemetry.add_theme_stylebox_override("panel", _box(Color(0.0, 0.03, 0.015, 0.78), Color(GREEN, 0.35), 1, 14))
	_telemetry.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_telemetry.offset_left = -470
	_telemetry.offset_right = -60
	_telemetry.offset_top = -186
	_telemetry.offset_bottom = -50
	_telemetry.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_telemetry)
	_telemetry_text = _mono_label("", 15, GREEN)
	_telemetry.add_child(_telemetry_text)

	_build_settings()
	_build_confirm()
	get_viewport().size_changed.connect(_fit)
	_fit()
	hide_all()


## Everything is laid out at 1600 x 900 and scaled to fill the window.
func _fit() -> void:
	var vs := get_viewport().get_visible_rect().size
	var k := minf(vs.x / BASE.x, vs.y / BASE.y)
	_root.scale = Vector2(k, k)
	_root.size = vs / k


func _process(delta: float) -> void:
	if mode == "":
		return
	_status_t -= delta
	if _status_t <= 0.0:
		_status_t = 0.25
		if status_fn.is_valid():
			var lines: PackedStringArray = status_fn.call()
			_telemetry_text.text = Loc.lines("\n".join(lines))
	# The selected entry's marker blinks like a terminal caret.
	var on := int(Time.get_ticks_msec() / 450) % 2 == 0
	for b in _main_box.get_children():
		if b is Button:
			var base: String = String(b.get_meta("num")) + Loc.t(String(b.get_meta("base")))
			var sel: bool = b.has_focus() or b.is_hovered()
			b.text = ("▸ " if sel and on else "  ") + base


# --- Look ------------------------------------------------------------------------------------

func _box(bg: Color, border := Color(0, 0, 0, 0), width := 0, margin := 10, left_bar := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.border_width_left = maxi(width, left_bar)
	s.border_width_right = width
	s.border_width_top = width
	s.border_width_bottom = width
	s.content_margin_left = margin
	s.content_margin_right = margin
	s.content_margin_top = margin * 0.5
	s.content_margin_bottom = margin * 0.5
	return s


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = Ctl.font()
	t.default_font_size = 18
	var clear := _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 12)
	var hover := _box(Color(ACCENT, 0.1), ACCENT, 0, 12, 3)
	var pressed := _box(Color(ACCENT, 0.22), ACCENT, 0, 12, 3)
	for kind in ["Button", "CheckBox"]:
		t.set_stylebox("normal", kind, clear)
		t.set_stylebox("hover", kind, hover)
		t.set_stylebox("pressed", kind, pressed)
		t.set_stylebox("focus", kind, hover)
		t.set_stylebox("hover_pressed", kind, pressed)
		t.set_color("font_color", kind, TEXT)
		t.set_color("font_hover_color", kind, ACCENT)
		t.set_color("font_focus_color", kind, ACCENT)
		t.set_color("font_pressed_color", kind, ACCENT)
		t.set_color("font_hover_pressed_color", kind, ACCENT)
	t.set_stylebox("panel", "PanelContainer", _box(Color(0.015, 0.02, 0.025, 0.96), Color(1, 1, 1, 0.1), 1, 0))
	var track := _box(Color(1, 1, 1, 0.1), Color(1, 1, 1, 0.14), 1, 0)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	t.set_stylebox("slider", "HSlider", track)
	var fill := _box(Color(ACCENT, 0.85), Color(0, 0, 0, 0), 0, 0)
	fill.content_margin_top = 4
	fill.content_margin_bottom = 4
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	var grab := _grabber_texture()
	t.set_icon("grabber", "HSlider", grab)
	t.set_icon("grabber_highlight", "HSlider", grab)
	t.set_stylebox("focus", "HSlider", _box(Color(0, 0, 0, 0), Color(ACCENT, 0.5), 1, 0))
	var vbar := _box(Color(1, 1, 1, 0.05), Color(0, 0, 0, 0), 0, 0)
	t.set_stylebox("scroll", "VScrollBar", vbar)
	t.set_stylebox("grabber", "VScrollBar", _box(Color(ACCENT, 0.4), Color(0, 0, 0, 0), 0, 0))
	t.set_stylebox("grabber_highlight", "VScrollBar", _box(Color(ACCENT, 0.7), Color(0, 0, 0, 0), 0, 0))
	return t


func _mono_label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _mono)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _grabber_texture() -> Texture2D:
	var img := Image.create(10, 22, false, Image.FORMAT_RGBA8)
	for y in 22:
		for x in 10:
			var edge := x == 0 or y == 0 or x == 9 or y == 21
			img.set_pixel(x, y, Color(0.08, 0.05, 0.02) if edge else (ACCENT.lightened(0.3) if y < 4 else ACCENT))
	return ImageTexture.create_from_image(img)


## The game's name in chunky pixels: 5x7 letters, each pixel a 4x4 block with the amber
## shaded top to bottom by ordered dithering, over a dark drop shadow.
func _logo_texture() -> Texture2D:
	var glyphs := {
		"L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
		"A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
		"N": ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
		"T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
		"E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
		"R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
	}
	var word := "LANTERN"
	var sub := 4
	var cols := word.length() * 5 + (word.length() - 1) * 2 + 1
	var rows := 8
	var img := Image.create(cols * sub, rows * sub, false, Image.FORMAT_RGBA8)
	var bayer := [0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0]
	var palette := [Color(1.0, 0.9, 0.62), Color(1.0, 0.78, 0.4), Color(0.95, 0.6, 0.24), Color(0.78, 0.4, 0.14)]
	var on := {}
	for i in word.length():
		var gl: Array = glyphs[word[i]]
		for y in 7:
			for x in 5:
				if (gl[y] as String)[x] == "1":
					on[Vector2i(i * 7 + x, y)] = true
	for pass_i in 2:
		for cell: Vector2i in on:
			var c := cell + (Vector2i(1, 1) if pass_i == 0 else Vector2i.ZERO)
			for sy in sub:
				for sx in sub:
					var px := c.x * sub + sx
					var py := c.y * sub + sy
					var col := Color(0.16, 0.07, 0.02)
					if pass_i == 1:
						var t := float(py) / float(7 * sub - 1) * (palette.size() - 1)
						var b: float = (bayer[(py % 4) * 4 + px % 4] + 0.5) / 16.0
						var k := clampi(int(t) + (1 if t - floorf(t) > b else 0), 0, palette.size() - 1)
						col = palette[k]
						if sy == 0 and not on.has(cell + Vector2i(0, -1)):
							col = col.lightened(0.25)
					img.set_pixel(px, py, col)
	return ImageTexture.create_from_image(img)


# --- Screens ---------------------------------------------------------------------------------

func hide_all() -> void:
	mode = ""
	_root.visible = false
	_settings.visible = false
	_confirm.visible = false
	_waiting = ""


func show_title(day: int) -> void:
	mode = "title"
	continue_day = day
	_root.visible = true
	_shade.color = Color(0.0, 0.01, 0.02, 0.0)
	_tagline.visible = true
	_paused.visible = false
	_footer.text = "PROTOTYPE BUILD      ↑↓ / MOUSE  CHOOSE      ENTER  SELECT      ESC  BACK"
	var items := []
	if day > 0:
		items.append(["continue", "CONTINUE"])
	items.append(["new", "NEW JOURNEY"])
	items.append(["settings", "SETTINGS"])
	items.append(["quit", "QUIT"])
	_fill(items)


func show_pause() -> void:
	mode = "pause"
	_root.visible = true
	_shade.color = Color(0.0, 0.01, 0.02, 0.6)
	_tagline.visible = false
	_paused.visible = true
	_footer.text = "ESC  RESUME"
	_fill([["resume", "RESUME"], ["settings", "SETTINGS"], ["controls", "CONTROLS"], ["title", "SAVE AND QUIT TO TITLE"], ["quit", "SAVE AND QUIT TO DESKTOP"]])


func _fill(items: Array) -> void:
	for c in _main_box.get_children():
		_main_box.remove_child(c)
		c.queue_free()
	var first: Button = null
	var n := 1
	for it in items:
		var b := Button.new()
		var base := "%02d   %s" % [n, it[1]]
		b.set_meta("num", "%02d   " % n)
		b.set_meta("base", String(it[1]))
		b.text = "  " + base
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_override("font", _mono)
		b.add_theme_font_size_override("font_size", 25)
		b.custom_minimum_size = Vector2(470, 48)
		var what: String = it[0]
		b.pressed.connect(func() -> void: _on_item(what))
		b.focus_entered.connect(_tick)
		b.mouse_entered.connect(func() -> void: b.grab_focus())
		_main_box.add_child(b)
		n += 1
		if first == null:
			first = b
	_settings.visible = false
	_confirm.visible = false
	_left.visible = true
	_left.modulate = Color.WHITE
	_telemetry.visible = true
	_footer.visible = true
	_quiet = true
	if first:
		first.grab_focus.call_deferred()
	(func() -> void: _quiet = false).call_deferred()


## A soft tick as the selection moves.
func _tick() -> void:
	if not _quiet:
		Sfx.play("click", -20.0, 1.7, "Suit")


func _on_item(what: String) -> void:
	Sfx.play("switch", -10.0, 1.0, "Suit")
	match what:
		"settings":
			_open_settings("game")
		"controls":
			_open_settings("controls")
		"new":
			if continue_day > 0:
				_ask("Start a new journey?\nThe one you are on will be lost.", "START OVER", "new")
			else:
				choice.emit("new")
		_:
			choice.emit(what)


func _unhandled_input(event: InputEvent) -> void:
	if _waiting != "" or mode == "":
		return
	var back: bool = (event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE) or event.is_action_pressed("pause")
	if not back:
		return
	get_viewport().set_input_as_handled()
	if _confirm.visible:
		_close_confirm()
	elif _settings.visible:
		_close_settings()
	elif mode == "pause":
		choice.emit("resume")


func _input(event: InputEvent) -> void:
	if _waiting == "":
		return
	var code := 0
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			_waiting = ""
			_show_page(_page)
			get_viewport().set_input_as_handled()
			return
		code = event.physical_keycode
	elif event is InputEventMouseButton and event.pressed:
		code = -event.button_index
	if code == 0:
		return
	get_viewport().set_input_as_handled()
	# One key, one job: whoever had it gets this action's old key.
	var old: int = Settings.bindings[_waiting]
	for a: String in Settings.bindings:
		if a != _waiting and Settings.bindings[a] == code:
			Settings.bindings[a] = old
	Settings.bindings[_waiting] = code
	_waiting = ""
	Settings.commit()
	Sfx.play("switch", -10.0, 1.2, "Suit")
	_show_page(_page)


# --- Confirmation ----------------------------------------------------------------------------

func _build_confirm() -> void:
	_confirm = PanelContainer.new()
	_confirm.add_theme_stylebox_override("panel", _box(Color(0.02, 0.02, 0.025, 0.98), Color(ACCENT, 0.6), 1, 28))
	_confirm.set_anchors_preset(Control.PRESET_CENTER)
	_confirm.offset_left = -300
	_confirm.offset_right = 300
	_confirm.offset_top = -110
	_confirm.offset_bottom = 110
	_root.add_child(_confirm)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 22)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	_confirm.add_child(v)
	_confirm_text = Label.new()
	_confirm_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirm_text.add_theme_font_size_override("font_size", 21)
	v.add_child(_confirm_text)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 18)
	v.add_child(h)
	_confirm_yes = _pill_button("")
	_confirm_yes.pressed.connect(func() -> void:
		var what := _confirm_what
		_close_confirm()
		choice.emit(what))
	h.add_child(_confirm_yes)
	var no := _pill_button("CANCEL")
	no.pressed.connect(_close_confirm)
	h.add_child(no)


func _ask(text: String, yes: String, what: String) -> void:
	_confirm_text.text = text
	_confirm_yes.text = yes
	_confirm_what = what
	_confirm.visible = true
	_left.modulate = Color(1, 1, 1, 0.3)
	_confirm_yes.grab_focus.call_deferred()


func _close_confirm() -> void:
	_confirm.visible = false
	_left.modulate = Color.WHITE
	if _main_box.get_child_count() > 0:
		(_main_box.get_child(0) as Control).grab_focus()


func _pill_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", _mono)
	b.add_theme_font_size_override("font_size", 17)
	b.custom_minimum_size = Vector2(170, 42)
	b.add_theme_stylebox_override("normal", _box(Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.25), 1, 14))
	b.add_theme_stylebox_override("hover", _box(Color(ACCENT, 0.18), ACCENT, 1, 14))
	b.add_theme_stylebox_override("focus", _box(Color(ACCENT, 0.18), ACCENT, 1, 14))
	b.add_theme_stylebox_override("pressed", _box(Color(ACCENT, 0.3), ACCENT, 1, 14))
	b.focus_entered.connect(_tick)
	b.mouse_entered.connect(func() -> void: b.grab_focus())
	return b


# --- Settings console ------------------------------------------------------------------------

func _build_settings() -> void:
	_settings = PanelContainer.new()
	_settings.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings.offset_left = 230
	_settings.offset_right = -230
	_settings.offset_top = 90
	_settings.offset_bottom = -90
	_settings.add_theme_stylebox_override("panel", _box(Color(0.012, 0.016, 0.02, 0.97), Color(1, 1, 1, 0.12), 1, 0))
	_root.add_child(_settings)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 0)
	_settings.add_child(outer)
	# Header strip.
	var head := PanelContainer.new()
	head.add_theme_stylebox_override("panel", _box(Color(ACCENT, 0.08), Color(0, 0, 0, 0), 0, 22))
	outer.add_child(head)
	var hh := HBoxContainer.new()
	head.add_child(hh)
	var title := _mono_label("SETTINGS", 26, ACCENT)
	hh.add_child(title)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hh.add_child(sp)
	var back := _pill_button("ESC  BACK")
	back.custom_minimum_size = Vector2(140, 36)
	back.pressed.connect(_close_settings)
	hh.add_child(back)
	var line := ColorRect.new()
	line.color = Color(ACCENT, 0.5)
	line.custom_minimum_size = Vector2(0, 2)
	outer.add_child(line)
	# Body: the tab rail and the page.
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	outer.add_child(body)
	var rail_bg := PanelContainer.new()
	rail_bg.add_theme_stylebox_override("panel", _box(Color(0, 0, 0, 0.35), Color(0, 0, 0, 0), 0, 0))
	rail_bg.custom_minimum_size = Vector2(230, 0)
	body.add_child(rail_bg)
	_rail = VBoxContainer.new()
	_rail.add_theme_constant_override("separation", 2)
	var rail_pad := MarginContainer.new()
	rail_pad.add_theme_constant_override("margin_top", 18)
	rail_pad.add_child(_rail)
	rail_bg.add_child(rail_pad)
	for p: Array in PAGES:
		var b := Button.new()
		b.text = String(p[1])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.add_theme_font_override("font", _mono)
		b.add_theme_font_size_override("font_size", 19)
		b.custom_minimum_size = Vector2(0, 46)
		var key: String = p[0]
		b.set_meta("page", key)
		b.pressed.connect(func() -> void:
			Sfx.play("click", -12.0, 1.2, "Suit")
			_show_page(key))
		b.focus_entered.connect(_tick)
		_rail.add_child(b)
	var page_box := VBoxContainer.new()
	page_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_box.add_theme_constant_override("separation", 0)
	body.add_child(page_box)
	var page_pad := MarginContainer.new()
	page_pad.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["margin_left", "margin_right"]:
		page_pad.add_theme_constant_override(side, 34)
	page_pad.add_theme_constant_override("margin_top", 20)
	page_box.add_child(page_pad)
	var page_v := VBoxContainer.new()
	page_v.add_theme_constant_override("separation", 12)
	page_pad.add_child(page_v)
	_page_title = _mono_label("", 15, DIM)
	page_v.add_child(_page_title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page_v.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 2)
	scroll.add_child(_rows)
	# Footer: what the row under the cursor does, and reset.
	var foot := PanelContainer.new()
	foot.add_theme_stylebox_override("panel", _box(Color(1, 1, 1, 0.03), Color(0, 0, 0, 0), 0, 22))
	foot.custom_minimum_size = Vector2(0, 74)
	outer.add_child(foot)
	var fh := HBoxContainer.new()
	fh.add_theme_constant_override("separation", 20)
	foot.add_child(fh)
	_describe = Label.new()
	_describe.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_describe.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_describe.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_describe.add_theme_color_override("font_color", DIM)
	_describe.add_theme_font_size_override("font_size", 16)
	fh.add_child(_describe)
	var reset := _pill_button("RESET PAGE")
	reset.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	reset.pressed.connect(func() -> void:
		Settings.reset_section(_page)
		Sfx.play("switch", -10.0, 0.9, "Suit")
		_show_page(_page))
	fh.add_child(reset)


func _open_settings(page: String) -> void:
	_settings.visible = true
	_left.visible = false
	_telemetry.visible = false
	_footer.visible = false
	_show_page(page)
	for b in _rail.get_children():
		if b.get_meta("page") == page:
			(b as Control).grab_focus.call_deferred()


func _close_settings() -> void:
	_settings.visible = false
	_left.visible = true
	_telemetry.visible = true
	_footer.visible = true
	_waiting = ""
	if _main_box.get_child_count() > 0:
		(_main_box.get_child(0) as Control).grab_focus()


func _show_page(page: String) -> void:
	_page = page
	for b in _rail.get_children():
		(b as Button).set_pressed_no_signal(b.get_meta("page") == page)
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	_describe.text = ""
	match page:
		"game":
			_page_title.text = "HOW THE KEEPER MOVES AND FEELS"
			_game_rows()
		"controls":
			_page_title.text = "KEYS  ·  CLICK ONE, THEN PRESS THE NEW KEY"
			_control_rows()
		"display":
			_page_title.text = "THE PICTURE"
			_display_rows()
		"audio":
			_page_title.text = "SOUND"
			_audio_rows()


## One settings row: a name on the left, its control on the right; hovering or focusing it
## explains it in the footer.
func _row(text: String, desc: String, control: Control) -> void:
	var p := PanelContainer.new()
	var normal := _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 12)
	var lit := _box(Color(1, 1, 1, 0.045), Color(ACCENT, 0.7), 0, 12, 2)
	p.add_theme_stylebox_override("panel", normal)
	p.custom_minimum_size = Vector2(0, 50)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	p.add_child(h)
	var l := Label.new()
	l.text = text
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", TEXT)
	h.add_child(l)
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(control)
	var light := func(on: bool) -> void:
		p.add_theme_stylebox_override("panel", lit if on else normal)
		if on:
			_describe.text = desc
	p.mouse_entered.connect(light.bind(true))
	p.mouse_exited.connect(light.bind(false))
	for c in _focusables(control):
		c.focus_entered.connect(light.bind(true))
		c.focus_exited.connect(light.bind(false))
		c.mouse_entered.connect(light.bind(true))
	_rows.add_child(p)


func _focusables(n: Node) -> Array[Control]:
	var out: Array[Control] = []
	if n is Control and (n as Control).focus_mode != Control.FOCUS_NONE:
		out.append(n as Control)
	for c in n.get_children():
		out.append_array(_focusables(c))
	return out


func _section(text: String) -> void:
	var l := _mono_label(text, 13, Color(ACCENT, 0.75))
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_top", 14)
	m.add_theme_constant_override("margin_left", 12)
	m.add_child(l)
	_rows.add_child(m)


## ◂ value ▸ : click either arrow (or the value) to step through the choices.
func _choice(text: String, desc: String, items: Array, value: int, setter: Callable) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	h.custom_minimum_size = Vector2(380, 0)
	var at := [value]
	var shown := Button.new()
	shown.text = String(items[value])
	shown.custom_minimum_size = Vector2(300, 38)
	shown.clip_text = true
	shown.add_theme_color_override("font_color", ACCENT)
	shown.add_theme_stylebox_override("normal", _box(Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.14), 1, 10))
	var step := func(d: int) -> void:
		at[0] = posmod(at[0] + d, items.size())
		shown.text = String(items[at[0]])
		setter.call(at[0])
		Settings.commit()
		Sfx.play("click", -12.0, 1.4, "Suit")
	var left := _arrow("◂")
	left.pressed.connect(step.bind(-1))
	var right := _arrow("▸")
	right.pressed.connect(step.bind(1))
	shown.pressed.connect(step.bind(1))
	h.add_child(left)
	h.add_child(shown)
	h.add_child(right)
	_row(text, desc, h)


func _arrow(t: String) -> Button:
	var b := Button.new()
	b.text = t
	b.custom_minimum_size = Vector2(38, 38)
	b.add_theme_font_size_override("font_size", 20)
	b.add_theme_stylebox_override("normal", _box(Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.14), 1, 6))
	return b


## An ON / OFF switch.
func _toggle(text: String, desc: String, value: bool, setter: Callable) -> void:
	var b := Button.new()
	b.toggle_mode = true
	b.button_pressed = value
	b.custom_minimum_size = Vector2(120, 38)
	b.add_theme_font_override("font", _mono)
	var paint := func(on: bool) -> void:
		b.text = "■ ON " if on else "□ OFF"
		b.add_theme_stylebox_override("normal", _box(Color(ACCENT, 0.85) if on else Color(1, 1, 1, 0.04), ACCENT if on else Color(1, 1, 1, 0.2), 1, 10))
		b.add_theme_stylebox_override("pressed", _box(Color(ACCENT, 0.85), ACCENT, 1, 10))
		b.add_theme_color_override("font_color", Color(0.06, 0.04, 0.02) if on else DIM)
		b.add_theme_color_override("font_pressed_color", Color(0.06, 0.04, 0.02))
		b.add_theme_color_override("font_hover_pressed_color", Color(0.06, 0.04, 0.02))
	paint.call(value)
	b.toggled.connect(func(on: bool) -> void:
		paint.call(on)
		setter.call(on)
		Settings.commit()
		Sfx.play("switch", -12.0, 1.3, "Suit"))
	var wrap := HBoxContainer.new()
	wrap.custom_minimum_size = Vector2(380, 0)
	wrap.alignment = BoxContainer.ALIGNMENT_END
	wrap.add_child(b)
	_row(text, desc, wrap)


func _slider(text: String, desc: String, lo: float, hi: float, step: float, value: float, fmt: String, setter: Callable) -> void:
	var h := HBoxContainer.new()
	h.custom_minimum_size = Vector2(380, 0)
	h.add_theme_constant_override("separation", 14)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var v := _mono_label(fmt % value, 17, ACCENT)
	v.custom_minimum_size = Vector2(76, 0)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	s.value_changed.connect(func(x: float) -> void:
		v.text = fmt % x
		setter.call(x)
		Settings.commit())
	h.add_child(s)
	h.add_child(v)
	_row(text, desc, h)


func _game_rows() -> void:
	_section("LANGUAGE")
	_choice("Language", "The language of the panels, the screens, the manuals and the menus.", ["ENGLISH", "РУССКИЙ"], 1 if Settings.language == "ru" else 0, func(i: int) -> void:
		Settings.language = "ru" if i == 1 else "en"
		Loc.set_lang(Settings.language)
		Loc.retranslate(get_tree().root))
	_section("LOOKING")
	_slider("Mouse sensitivity", "How far the view turns for a move of the mouse.", 0.2, 3.0, 0.05, Settings.sensitivity, "%.2f", func(x: float) -> void: Settings.sensitivity = x)
	_slider("Gamepad look speed", "How fast the right stick turns the view.", 0.2, 3.0, 0.05, Settings.pad_sensitivity, "%.2f", func(x: float) -> void: Settings.pad_sensitivity = x)
	_toggle("Invert vertical look", "Mouse forward looks down instead of up.", Settings.invert_y, func(on: bool) -> void: Settings.invert_y = on)
	_slider("Field of view", "How wide you see, in degrees. Wider shows more of the cabin; narrower feels closer.", 60.0, 105.0, 1.0, Settings.fov, "%d°", func(x: float) -> void: Settings.fov = x)
	_section("HANDS")
	_choice("Holding on", "Pull: hold LMB on a surface and the arm pulls you to it; let go to fly on. Drag: the mouse pulls and pushes you round the grip. Push-off: free look, let go or RMB to push off.", ["PULL TO THE GRIP", "DRAG ROUND THE GRIP", "LOOK AND PUSH OFF"], 0 if Settings.pull_grab else (1 if Settings.hold_drag else 2), func(i: int) -> void:
		Settings.pull_grab = i == 0
		Settings.hold_drag = i == 1)
	_choice("Grab button", "Hold the button to hang on, or click once to grab and again to let go.", ["HOLD TO HOLD ON", "CLICK TO GRAB"], 1 if Settings.grab_toggle else 0, func(i: int) -> void: Settings.grab_toggle = i == 1)
	_toggle("Flick to push off", "A quick flick of the mouse toward you while holding on also pushes off. Off by default: a fast glance down can set it off.", Settings.flick_push, func(on: bool) -> void: Settings.flick_push = on)
	_section("COMFORT")
	_slider("Screen shake", "How hard knocks, impacts and blowouts shake the view. 0 turns it off.", 0.0, 1.0, 0.05, Settings.shake, "%.2f", func(x: float) -> void: Settings.shake = x)
	_toggle("First-minute hints", "Short tips in the first minutes of a new journey.", Settings.hints, func(on: bool) -> void: Settings.hints = on)


func _control_rows() -> void:
	_section("KEYS")
	for a in Settings.ACTIONS:
		var action: String = a[0]
		var b := Button.new()
		b.text = "PRESS A KEY ·  ESC CANCELS" if _waiting == action else Settings.label_for(action).to_upper()
		b.custom_minimum_size = Vector2(300, 38)
		b.add_theme_font_override("font", _mono)
		b.add_theme_stylebox_override("normal", _box(Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.3), 1, 10))
		b.add_theme_color_override("font_color", ACCENT if _waiting == action else TEXT)
		b.pressed.connect(func() -> void:
			_waiting = action
			b.text = "PRESS A KEY ·  ESC CANCELS"
			b.add_theme_color_override("font_color", ACCENT))
		var wrap := HBoxContainer.new()
		wrap.custom_minimum_size = Vector2(380, 0)
		wrap.alignment = BoxContainer.ALIGNMENT_END
		wrap.add_child(b)
		_row(String(a[1]), "Click, then press the key or mouse button for this. A key already in use swaps over.", wrap)
	_section("FIXED")
	for pair: Array in [["Look", "MOUSE"], ["Hold on, pulled to the grip", "HOLD LMB"], ["Push off where you look", "RMB"], ["Hang closer / farther, turn knobs, turn the manual's pages", "WHEEL"], ["Menu", "ESC"], ["Fullscreen", "F11"], ["Readout", "F3"]]:
		var l := _mono_label(String(pair[1]), 16, DIM)
		l.custom_minimum_size = Vector2(380, 0)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_row(String(pair[0]), "Fixed: these cannot be rebound.", l)
	_section("GAMEPAD")
	for pair: Array in [["Look", "RIGHT STICK"], ["Grab / use", "RT"], ["Throw / push off", "LT"], ["Helmet lamp", "X"], ["Use what you hold", "Y"], ["Menu", "START"]]:
		var l := _mono_label(String(pair[1]), 16, DIM)
		l.custom_minimum_size = Vector2(380, 0)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_row(String(pair[0]), "Xbox layout.", l)


func _display_rows() -> void:
	_section("RENDERING")
	_choice("Quality", "Ultra: global illumination, volumetric light and reflections. High: shadows, haze and bounce light. Medium: shadows. Low: plain lighting, for weak machines.", Array(Settings.QUALITY).map(func(q: String) -> String: return q.to_upper()), Settings.quality, func(i: int) -> void: Settings.quality = i)
	_choice("Retro pixels", "Dithered: big pixels, eight shades a channel, a checkerboard dither between them. PSX: crisp big pixels that still keep distant lettering readable. Chunky: bigger pixels, more grit. Off: a smooth modern picture.", ["OFF  ·  SMOOTH", "PSX", "CHUNKY", "DITHERED"], Settings.retro_pixel, func(i: int) -> void: Settings.retro_pixel = i)
	_slider("Render scale", "Renders fewer pixels and upscales them with FSR 2. Only with retro pixels off.", 0.5, 1.0, 0.05, Settings.render_scale, "%.2f", func(x: float) -> void: Settings.render_scale = x)
	_section("PICTURE")
	_slider("Brightness", "Lifts or darkens the whole picture. The station is meant to be dim.", 0.6, 1.5, 0.05, Settings.brightness, "%.2f", func(x: float) -> void: Settings.brightness = x)
	_toggle("Film grain and lens streaks", "The fine grain over the picture and the streaks off bright lights.", Settings.grain, func(on: bool) -> void: Settings.grain = on)
	_section("PERFORMANCE")
	_choice("Frame rate limit", "Caps the frames drawn each second. Lower keeps the computer cool and quiet; uncapped makes the graphics card run flat out. In the background the game always slows to a crawl.", ["NONE", "30 FPS", "60 FPS", "90 FPS", "120 FPS", "144 FPS"], Settings.fps_cap, func(i: int) -> void: Settings.fps_cap = i)
	_section("WINDOW")
	_toggle("Fullscreen", "Fill the screen (F11 switches too).", Settings.fullscreen, func(on: bool) -> void: Settings.fullscreen = on)
	_toggle("VSync", "Wait for the screen's refresh: no tearing, a little more input lag.", Settings.vsync, func(on: bool) -> void: Settings.vsync = on)


func _audio_rows() -> void:
	_section("VOLUME")
	_slider("Master", "Everything.", -40.0, 6.0, 1.0, Settings.master_db, "%+d dB", func(x: float) -> void: Settings.master_db = x)
	_slider("Effects", "The station, the suit and everything you touch. All the way down mutes them.", -40.0, 6.0, 1.0, Settings.sfx_db, "%+d dB", func(x: float) -> void: Settings.sfx_db = x)
	_slider("Music", "The score.", -40.0, 6.0, 1.0, Settings.music_db, "%+d dB", func(x: float) -> void: Settings.music_db = x)
