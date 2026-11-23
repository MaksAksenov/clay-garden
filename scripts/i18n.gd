extends RefCounted
## Languages (stage 8). Dictionaries are flat JSON "key → string" in res://lang/<code>.json and user://lang/<code>.json
## (the second adds to and overrides the first: a player can drop in a translation without rebuilding).
## A new language = copy lang/en.json to lang/<code>.json, translate the values and `_meta.name`; no code changes.
## Substitutions are named: t("ui.hud.score", {"n": 5}) for "Coziness {n}". Fallback chain: chosen language → English →
## the key itself (Russian is nobody's fallback — other languages must not contain Cyrillic). No plural forms:
## phrases are built so the number doesn't change the word form; the format reserves room for them ({n|…} — later).
## Pseudo-language "xx" (debugging, --lang=xx): English in brackets [!…!] — a screenshot shows strings that bypassed t().

const DIRS := ["res://lang", "user://lang"]
const FALLBACK := "en"
const PSEUDO := "xx"

static var lang := "en"   # English until a language is chosen (like FALLBACK); the game always sets the language at startup
static var pseudo := false
static var tables := {}   # code -> {key: string}
static var _loaded := false
static var flag_svg := {}   # code -> the flag SVG from `_meta.flag` (stage 9; drawn in code, no image files)
static var _flag_cache := {}
const FLAG_MAX := 4096      # dictionaries from user://lang are external: a long SVG is not rasterized


static func load_all() -> void:
	tables = {}
	flag_svg = {}
	_flag_cache = {}
	for d in DIRS:
		var da := DirAccess.open(d)
		if da == null:
			continue
		for f in da.get_files():
			if not f.ends_with(".json"):
				continue
			var data = JSON.parse_string(FileAccess.get_file_as_string(d + "/" + f))
			if not data is Dictionary:
				push_warning("Language %s/%s could not be read" % [d, f])
				continue
			var code := f.get_basename()
			if not tables.has(code):
				tables[code] = {}
			var tb: Dictionary = tables[code]
			for k in data:
				if data[k] is String:
					tb[k] = data[k]
				elif k == "_meta" and data[k] is Dictionary:
					tb["_meta.name"] = String(data[k].get("name", code))
					if data[k].get("flag", null) is String:
						flag_svg[code] = data[k]["flag"]
	_loaded = true


static func _ensure() -> void:
	if not _loaded:
		load_all()


## Language codes: Russian and English first, the rest alphabetically.
static func languages() -> Array:
	_ensure()
	var out := []
	for c in ["ru", "en"]:
		if tables.has(c):
			out.append(c)
	var rest := tables.keys().filter(func(c): return not c in out)
	rest.sort()
	out.append_array(rest)
	return out


static func set_lang(code: String) -> void:
	_ensure()
	pseudo = code == PSEUDO
	if pseudo:
		lang = FALLBACK
	else:
		lang = code if tables.has(code) else FALLBACK


static func current() -> String:
	return PSEUDO if pseudo else lang


## The language's own name ("English", "Deutsch").
static func lang_name(code: String) -> String:
	_ensure()
	if code == PSEUDO:
		return "[!Pseudo!]"
	return String(tables.get(code, {}).get("_meta.name", code))


## The language's flag — a texture from the dictionary's SVG, rasterized once with a size margin. null — no flag or it
## failed to render (then the interface shows a badge with the language code).
static func flag(code: String) -> Texture2D:
	_ensure()
	if _flag_cache.has(code):
		return _flag_cache[code]
	var tex: Texture2D = null
	var svg := String(flag_svg.get(code, ""))
	if svg != "" and svg.length() <= FLAG_MAX:
		var img := Image.new()
		if img.load_svg_from_string(svg, 4.0) == OK and img.get_width() > 0 and img.get_height() > 0:
			tex = ImageTexture.create_from_image(img)
	_flag_cache[code] = tex
	return tex


static func has(key: String) -> bool:
	_ensure()
	return tables.get(lang, {}).has(key) or tables.get(FALLBACK, {}).has(key)


static func t(key: String, args: Dictionary = {}) -> String:
	_ensure()
	var s: String
	if tables.get(lang, {}).has(key):
		s = tables[lang][key]
	elif tables.get(FALLBACK, {}).has(key):
		s = tables[FALLBACK][key]
	else:
		s = key   # a missing key shows right away (and the test catches it)
	if not args.is_empty():
		s = s.format(args)
	if pseudo:
		s = "[!" + s + "!]"
	return s


## A signed number for card phrases: +2, -1.
static func signed(v: int) -> String:
	return "%+d" % v


## The first letter uppercase, the rest as is (String.capitalize() raises every word: "Tree Or Pine").
static func cap_first(s: String) -> String:
	if s.is_empty():
		return s
	return s.substr(0, 1).to_upper() + s.substr(1)


## A level's name and hint — by its permanent id.
static func level_name(id: String) -> String:
	return t("level.%s.name" % id)


## touch: if the hint has a finger variant (`.hint_touch` — no keys or mouse), use it.
static func level_hint(id: String, touch := false) -> String:
	var key := "level.%s.hint" % id
	if touch and has(key + "_touch"):
		return t(key + "_touch")
	return t(key)
