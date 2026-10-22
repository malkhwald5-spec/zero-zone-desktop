class_name EnTranslation
extends Translation
## English for the game's Arabic text. The Arabic strings in the code are
## the keys (i18n/en.json). Text built with % (a number or a name put into
## a sentence) is matched against the keys that have placeholders, and the
## same values are put into the English sentence.

var _exact := {}
var _patterns: Array = []          # [RegEx, english template]

func _init() -> void:
	locale = "en"
	var f := FileAccess.open("res://i18n/en.json", FileAccess.READ)
	if f == null: return
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY: return
	_exact = data
	var ph := RegEx.create_from_string("%[-+0-9.]*[dsfx]")
	for k in data:
		var key := String(k)
		if not ph.search(key): continue
		# "قتلت %d بـ %s" -> ^قتلت (.+?) بـ (.+?)$ ; the English side gets %s for each value.
		var rx := "^"
		var at := 0
		for m in ph.search_all(key):
			rx += _escape(key.substr(at, m.get_start() - at).replace("%%", "%")) + "(.+?)"
			at = m.get_end()
		rx += _escape(key.substr(at).replace("%%", "%")) + "$"
		var re := RegEx.create_from_string(rx)
		if re.is_valid():
			_patterns.append([re, ph.sub(String(data[k]).replace("%%", "\u0001"), "%s", true).replace("\u0001", "%%"), ph.sub(key, "", true).length()])
	# Most specific first: "باتل رويال • %s • %s" before a bare "%s • %s".
	_patterns.sort_custom(func(a, b): return a[2] > b[2])

static func _escape(s: String) -> String:
	var out := ""
	for ch in s:
		out += ("\\" + ch) if ch in ".^$*+?()[]{}|\\/" else ch
	return out

## A value put into a sentence: whole if it is a key, else word by word ("فضة V").
func _words(v: String) -> String:
	if _exact.has(v): return String(_exact[v])
	var parts := v.split(" ")
	for i in parts.size():
		parts[i] = String(_exact.get(parts[i], parts[i]))
	return " ".join(parts)

func _get_message(src_message: StringName, _context: StringName) -> StringName:
	var s := String(src_message)
	if _exact.has(s): return StringName(String(_exact[s]))
	if s.is_empty() or s.length() > 400: return src_message
	for p in _patterns:
		var m: RegExMatch = (p[0] as RegEx).search(s)
		if m:
			var vals := []
			# The values put in may be words themselves (a map name, a rank).
			for i in range(1, m.get_group_count() + 1):
				vals.append(_words(m.get_string(i)))
			return StringName(String(p[1]) % vals)
	return src_message
