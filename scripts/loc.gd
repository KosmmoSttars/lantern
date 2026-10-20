class_name Loc
extends RefCounted
## The game's languages: English as written in the scripts, and Russian from LocRu.WORDS.
##
## Every player-facing string goes through Loc.t() where it is shown: the 3D labels made by
## Ctl.text, the CRT screens, the HUD's toasts, hints and manual pages. A string is looked up
## whole; a formatted one ("Recycled: %s") is matched back to its template and its arguments
## translated in turn; a block of lines is translated line by line. The menu's controls are
## translated by Godot itself from the same words (a Translation registered for "ru").

static var lang := "en"
static var _cache := {}
## [RegEx, Russian template] for the templates in WORDS, the most specific first.
static var _templates: Array = []
static var _upper := {}
static var _registered := false

const PLACEHOLDER := "%[-+ 0#]*\\d*(?:\\.\\d+)?[sdfx]"


## Switch the language ("en" or "ru").
static func set_lang(l: String) -> void:
	lang = l if l in ["en", "ru"] else "en"
	_cache.clear()
	if lang == "ru":
		_prepare()
	TranslationServer.set_locale(lang)


static func t(s: String) -> String:
	if lang == "en" or s == "":
		return s
	if _cache.has(s):
		return _cache[s]
	var out := _translate(s)
	if _cache.size() > 6000:
		_cache.clear()
	_cache[s] = out
	return out


## A block of text, line by line (the CRT screens).
static func lines(s: String) -> String:
	if lang == "en" or s == "":
		return s
	var out := PackedStringArray()
	for l in s.split("\n"):
		out.append(t(l))
	return "\n".join(out)


static func _translate(s: String) -> String:
	var words: Dictionary = LocRu.WORDS
	if words.has(s):
		return words[s]
	if s.contains("\n"):
		return lines(s)
	# Keep the padding round a word (columns on the screens, legends with spaces).
	var core := s.strip_edges()
	if core != s and core != "":
		var lead := s.substr(0, s.find(core))
		var trail := s.substr(s.find(core) + core.length())
		var tc := t(core)
		if tc != core:
			return lead + tc + trail
	if _upper.has(s):
		return _upper[s]
	for tp: Array in _templates:
		var m: RegExMatch = (tp[0] as RegEx).search(s)
		if m == null:
			continue
		var args := PackedStringArray()
		for k in range(1, m.get_group_count() + 1):
			args.append(t(m.get_string(k)))
		return _fill(String(tp[1]), args)
	return s


## Put the arguments into a Russian template in order, whatever their placeholders.
static func _fill(tpl: String, args: PackedStringArray) -> String:
	var re := RegEx.create_from_string(PLACEHOLDER)
	var out := ""
	var at := 0
	var k := 0
	for m in re.search_all(tpl):
		out += tpl.substr(at, m.get_start() - at)
		out += args[k] if k < args.size() else ""
		k += 1
		at = m.get_end()
	return (out + tpl.substr(at)).replace("%%", "%")


static func _prepare() -> void:
	if not _templates.is_empty():
		return
	var words: Dictionary = LocRu.WORDS
	var ph := RegEx.create_from_string(PLACEHOLDER)
	var tps: Array = []
	var tr := Translation.new()
	tr.locale = "ru"
	for en: String in words:
		var ru: String = words[en]
		if ph.search(en) == null:
			tr.add_message(en, ru)
			# Legends are often shown in capitals: match those too.
			if en.to_upper() != en:
				_upper[en.to_upper()] = ru.to_upper()
			continue
		# A template: escape what is literal, catch what is filled in.
		var literal := ph.sub(en, "", true)
		if literal.strip_edges().length() < 3:
			continue
		var pat := "^"
		var at := 0
		for m in ph.search_all(en):
			pat += _escape(en.substr(at, m.get_start() - at))
			pat += "(.+?)"
			at = m.get_end()
		pat += _escape(en.substr(at)) + "$"
		var re := RegEx.create_from_string(pat.replace("%%", "%"))
		if re.is_valid():
			tps.append([re, ru, literal.length()])
	tps.sort_custom(func(a: Array, b: Array) -> bool: return int(a[2]) > int(b[2]))
	_templates = tps
	if not _registered:
		TranslationServer.add_translation(tr)
		_registered = true


static func _escape(s: String) -> String:
	var out := ""
	for c in s:
		if c in "\\^$.|?*+()[]{}":
			out += "\\"
		out += c
	return out


## After a language change: every label made by Ctl.text and every CRT screen again.
static func retranslate(root: Node) -> void:
	for n in root.find_children("*", "Label3D", true, false):
		var l := n as Label3D
		if l.has_meta("en"):
			l.text = t(String(l.get_meta("en")))
			if l.has_meta("fit"):
				var f: Vector2 = l.get_meta("fit")
				Ctl.fit(l, f.x, f.y)
	for n in root.find_children("*", "Node3D", true, false):
		if n is Terminal:
			(n as Terminal).retranslate()
