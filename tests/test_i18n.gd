extends SceneTree
## Stage 8: languages. Run: Godot --headless --path . --script res://tests/test_i18n.gd
## Checks the dictionaries (the same keys and substitutions, all required keys present), the Russian cards — byte for byte
## as the reference, English — no Cyrillic and no leftover {…}, Cyrillic in player-facing code, a walk through the whole interface in English
## (menu, garden, levels, cards, result, language choice), switching the language on the fly, the first-start language rule.
## The player's garden and progress are untouched: our own save path, a new player, settings are not written.

const I18n := preload("res://scripts/i18n.gd")
const Scoring := preload("res://scripts/scoring.gd")
const Items := preload("res://scripts/items.gd")
const Levels := preload("res://scripts/levels.gd")
const Campaign := preload("res://scripts/campaign.gd")
const Snap := preload("res://tests/snap_cards.gd")
const Main := preload("res://scripts/main.gd")

## Code files the player sees; Cyrillic in them — only in developer messages.
const PLAYER_CODE := ["main.gd", "ui.gd", "scoring.gd", "items.gd", "terrain.gd", "board.gd", "levels.gd", "progress.gd", "stars.gd"]
const DEV_LINE := ["push_error", "push_warning", "_bad(", "print("]

var checks := 0
var failed := 0
var cyr := RegEx.create_from_string("[А-Яа-яЁё]")
var placeholder := RegEx.create_from_string("\\{[a-z_]+\\}")
var raw_key := RegEx.create_from_string("\\b(ui|item|noun|card|level|chapter|season|mech|toast|hint|tool|terrain|list)\\.[a-z_0-9.]+")


func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		if failed <= 40:
			print("FAIL: " + what)


func _initialize() -> void:
	_run()


func _run() -> void:
	I18n.load_all()
	_test_tables()
	_test_needed_keys()
	_test_cards()
	_test_code_scan()
	_test_rule()
	_test_user_dir()
	await _test_scene()
	I18n.set_lang("ru")
	print("TESTS %s: %d checks, %d failed" % ["OK" if failed == 0 else "FAILED", checks, failed])
	quit(0 if failed == 0 else 1)


func _placeholders(s: String) -> Array:
	var out := []
	for m in placeholder.search_all(s):
		out.append(m.get_string())
	out.sort()
	return out


## Languages: the same set of keys, the same substitutions, English has no Cyrillic.
func _test_tables() -> void:
	check("ru" in I18n.languages() and "en" in I18n.languages(), "no ru or en")
	var ru: Dictionary = I18n.tables["ru"]
	for code in I18n.languages():
		var tb: Dictionary = I18n.tables[code]
		check(tb.has("_meta.name"), "%s: no _meta.name" % code)
		for key in ru:
			check(tb.has(key), "%s: no key %s" % [code, key])
			if tb.has(key) and key != "_meta.name":
				check(_placeholders(tb[key]) == _placeholders(ru[key]), "%s: substitutions in %s: %s vs %s" % [code, key, _placeholders(tb[key]), _placeholders(ru[key])])
		for key in tb:
			check(ru.has(key), "%s: extra key %s (not in ru)" % [code, key])
	for key in I18n.tables["en"]:
		check(cyr.search(I18n.tables["en"][key]) == null, "en: Cyrillic in %s" % key)


## Keys the code builds on the fly (names, seasons, chapters, levels…), and all literal keys from the code.
func _test_needed_keys() -> void:
	var need := []
	for info in Items.CATALOG:
		need.append("item." + info["id"])
		need.append("noun." + info["id"])
	for id in Scoring.RULES:
		need.append("noun." + id)
	need.append_array(["noun.water", "noun.ice", "terrain.on.snow", "terrain.on.ice"])
	for id in ["raise", "lower", "water", "remove"]:
		need.append("tool." + id)
	for s in Campaign.SEASONS:
		need.append("season." + s["id"])
	for i in Campaign.CHAPTERS.size():
		need.append("chapter.%d" % i)
	for m in Main.MECH_INTRO:
		need.append("mech." + m)
	for i in [1, 2, 3]:
		need.append("ui.result.star%d" % i)
	for L in Levels.LEVELS:
		need.append("level.%s.name" % L["id"])
		need.append("level.%s.hint" % L["id"])
	var lit := RegEx.create_from_string("I18n\\.t\\(\"([a-z_0-9.]+)\"[,)]")
	for f in DirAccess.get_files_at("res://scripts"):
		if f.ends_with(".gd"):
			for m in lit.search_all(FileAccess.get_file_as_string("res://scripts/" + f)):
				need.append(m.get_string(1))
	for code in I18n.languages():
		for key in need:
			check(I18n.tables[code].has(key), "%s: no required key %s" % [code, key])


## Russian cards — byte for byte as the reference; English ones — no Cyrillic, no {…} and no raw keys.
func _test_cards() -> void:
	I18n.set_lang("ru")
	var gold = JSON.parse_string(FileAccess.get_file_as_string("res://tests/golden_cards_ru.json"))
	var now := Snap.snapshot()
	for k in gold:
		check(now.get(k, "") == gold[k], "ru card %s:\n%s\n---reference---\n%s" % [k, now.get(k, ""), gold[k]])
	I18n.set_lang("en")
	var en := Snap.snapshot()
	for k in en:
		var txt: String = en[k]
		check(cyr.search(txt) == null, "en card %s with Cyrillic: %s" % [k, txt])
		check(not "{" in txt and raw_key.search(txt) == null, "en card %s: a leftover substitution or key: %s" % [k, txt])
	I18n.set_lang("xx")
	check(I18n.t("ui.title").begins_with("[!") and I18n.t("ui.title").ends_with("!]"), "the pseudo-language doesn't wrap")
	I18n.set_lang("ru")


## Cyrillic in player-facing code — only in developer messages and comments.
func _test_code_scan() -> void:
	var lit := RegEx.create_from_string("\"((?:[^\"\\\\]|\\\\.)*)\"")
	for f in PLAYER_CODE:
		var n := 0
		for line in FileAccess.get_file_as_string("res://scripts/" + f).split("\n"):
			var code_part: String = line
			var hash := line.find("#")
			if hash >= 0 and line.substr(0, hash).count("\"") % 2 == 0:
				code_part = line.substr(0, hash)
			if code_part.strip_edges().begins_with("##"):
				continue
			var dev := false
			for d in DEV_LINE:
				if d in code_part:
					dev = true
			if dev:
				continue
			for m in lit.search_all(code_part):
				if cyr.search(m.get_string(1)) != null:
					n += 1
					check(false, "%s: a Russian string bypassing the dictionary: %s" % [f, m.get_string(1)])
		check(n == 0, "%s: %d strings bypassing the dictionary" % [f, n])


## The first-start language.
func _test_rule() -> void:
	check(Main.choose_language("", true, "", "en") == ["ru", false], "a player of the earlier version without settings didn't get Russian")
	check(Main.choose_language("", false, "", "en") == ["en", true], "a new player wasn't shown the choice")
	check(Main.choose_language("en", true, "", "ru") == ["en", false], "the saved choice wasn't respected")
	check(Main.choose_language("ru", false, "xx", "en") == ["xx", false], "--lang didn't override")


## A player's own translation: user://lang/<code>.json is found without rebuilding.
func _test_user_dir() -> void:
	DirAccess.make_dir_recursive_absolute("user://lang")
	var path := "user://lang/zz_test.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"_meta": {"name": "Zz"}, "ui.title": "Zz Garden"}))
	f.close()
	I18n.load_all()
	check("zz_test" in I18n.languages(), "the language from user://lang was not found")
	I18n.set_lang("zz_test")
	check(I18n.t("ui.title") == "Zz Garden", "the translation from user://lang was not applied")
	check(I18n.t("ui.sandbox") == I18n.tables["en"]["ui.sandbox"], "the fallback language is not English")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	I18n.load_all()
	I18n.set_lang("ru")


func _frames(n: int) -> void:
	for i in n:
		await process_frame


## All texts of a node and its descendants (including hidden panels).
func _texts(n: Node, out: Array, skip: Node = null) -> void:
	if n == skip:
		return   # the language choice screen deliberately writes each language in its own script
	if n is Label:
		out.append((n as Label).text)
	if n is Label3D:
		out.append((n as Label3D).text)
	if n is Button:
		out.append((n as Button).text)
	if n is Control and (n as Control).tooltip_text != "":
		out.append((n as Control).tooltip_text)
	for ch in n.get_children():
		_texts(ch, out, skip)


func _walk_en(m, where: String) -> void:
	var out := []
	_texts(m.ui, out, m.ui.picker)
	for l in m.hint_labels:
		out.append(l.text)
	var self_names := I18n.languages().map(func(c): return I18n.lang_name(c))
	for t in out:
		if t in self_names:
			continue   # the language flags in the settings are labeled with their own names ("Русский") — deliberately
		check(cyr.search(t) == null, "%s: Cyrillic in the interface: \"%s\"" % [where, t])
		check(raw_key.search(t) == null and not "{" in t, "%s: a raw key or substitution: \"%s\"" % [where, t])


func _test_scene() -> void:
	var m = load("res://main.tscn").instantiate()
	m.fresh = true
	m.new_player = true
	m.seed_arg = 7
	m.save_path = "user://test_garden_i18n.json"
	m.progress_path = "user://test_progress_other.json"
	m.settings_path = "user://test_settings_other.json"
	m.playlog_path = "user://test_playlog_other.json"
	m.music_on = false
	m.save_enabled = false
	m.lang_arg = "en"
	root.add_child(m)
	await _frames(3)
	check(I18n.current() == "en", "--lang=en didn't turn on English")
	# menu: all season tabs
	for s in Campaign.SEASONS:
		m.ui.menu_season = s["id"]
		m.ui._fill_menu()
		await _frames(1)
		_walk_en(m, "menu/" + s["id"])
		# stage 13: a new player has only spring open; a locked season says what opens it
		var locked: bool = s["id"] != "spring"
		check(("opens after" in m.ui.menu_total.text) == locked, "menu/%s: the locked-season line: \"%s\"" % [s["id"], m.ui.menu_total.text])
	m.ui.show_language_picker("en")
	await _frames(1)
	var pt := []
	_texts(m.ui.picker, pt)
	for code in I18n.languages():
		check(I18n.lang_name(code) in pt, "the language choice has no \"%s\"" % I18n.lang_name(code))
		check(pt.any(func(x): return I18n.tables[code]["ui.lang.pick"] in x), "the choice title has no phrase in %s" % code)
	m.ui.picker.visible = false
	# free garden: all seasons, the counter
	m.enter_sandbox()
	m.toggle_cozy()
	for s in Campaign.SEASON_ORDER:
		m.set_garden_season(s)
		await _frames(1)
		_walk_en(m, "garden/" + s)
	# levels: one per season and All Year Round; the card of every hand item, the result
	for slot in [1, 38, 66, 79, 97]:
		m.start_level(slot - 1)
		await _frames(2)
		for id in m.hand:
			m.set_tool(id)
			_walk_en(m, "level %d/%s" % [slot, id])
		var L: Dictionary = Levels.LEVELS[slot - 1]
		for st in [0, 1, 2, 3]:
			m.ui.show_result(st, int(L["perfect"]) if st == 3 else 1, L, true, true)
			_walk_en(m, "result %d/%d" % [slot, st])
		m.ui.hide_result()
	# switching the language on the fly: the interface is rebuilt, no extra interfaces, the text became Russian
	m.set_language("ru")
	await _frames(3)
	var uis := 0
	for ch in m.get_children():
		if ch is CanvasLayer and ch.has_method("show_menu"):
			uis += 1
	check(uis == 1, "interfaces after the language change: %d" % uis)
	check(m.ui.hud_title.text.begins_with("Уровень"), "after switching to Russian the title is: %s" % m.ui.hud_title.text)
	check(m.mode == "level" and m.ui.hud.visible, "the level didn't come back after the language change")
	m.set_language("en")
	await _frames(3)
	_walk_en(m, "level after two language changes")
	m.queue_free()
	await _frames(2)
