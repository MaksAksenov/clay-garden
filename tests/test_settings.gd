extends SceneTree
## Stage 9: settings. Run: Godot --headless --path . --script res://tests/test_settings.gd
## Audio buses and sliders, settings storage (the old format is read, junk is dropped), the gear in the menu and in the corner
## panel, Esc, the language carousel (one interface, the settings screen open again), flags and the badge, progress reset
## by holding (released early, Esc, focus loss, a frame stall — no reset; 3 s — resets once,
## a copy in .bak), the garden after a reset. All files are our own; the player's files are compared by hash before and after.

const Main := preload("res://scripts/main.gd")
const I18n := preload("res://scripts/i18n.gd")
const Progress := preload("res://scripts/progress.gd")
const Levels := preload("res://scripts/levels.gd")

const PLAYER_FILES := ["user://progress.json", "user://progress.bak.json", "user://garden.json", "user://settings.json", "user://playlog.json"]
const T_SETTINGS := "user://test_settings.json"
const T_PROGRESS := "user://test_progress.json"
const T_BAK := "user://test_progress.bak.json"
const T_GARDEN := "user://test_garden_settings.json"
const T_PLAYLOG := "user://test_playlog_settings.json"

var checks := 0
var failed := 0


func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		print("FAIL: " + what)


func _initialize() -> void:
	_run()


func _run() -> void:
	var before := _hashes()
	_cleanup()
	_test_parse()
	_test_flags()
	await _test_scene()
	_cleanup()
	check(_hashes() == before, "player files changed: %s -> %s" % [before, _hashes()])
	I18n.set_lang("ru")
	print("TESTS %s: %d checks, %d failed" % ["OK" if failed == 0 else "FAILED", checks, failed])
	quit(0 if failed == 0 else 1)


func _hashes() -> Dictionary:
	var out := {}
	for f in PLAYER_FILES:
		out[f] = FileAccess.get_md5(f) if FileAccess.file_exists(f) else "-"
	return out


func _cleanup() -> void:
	for f in [T_SETTINGS, T_SETTINGS + ".tmp", T_PROGRESS, T_BAK, T_GARDEN, T_PLAYLOG]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))


func _write(path: String, data) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()


func _read(path: String):
	return JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null


func _frames(n: int) -> void:
	for i in n:
		await process_frame


## Reading volumes: numbers only, 0…1, anything missing or junk — the default.
func _test_parse() -> void:
	check(Main.parse_volumes(null) == Main.VOL_DEFAULT, "volumes from null are not the defaults")
	var v := Main.parse_volumes({"master": 2, "music": "loud", "effects": -1})
	check(is_equal_approx(v["master"], 1.0) and is_equal_approx(v["music"], Main.VOL_DEFAULT["music"]) and is_equal_approx(v["effects"], 0.0), "volumes not clamped: %s" % v)
	check(is_equal_approx(Main.parse_volumes({"music": 0.25})["music"], 0.25), "music volume not read")


## Flags: ru and en render; without a flag, with a broken or too long SVG — null (the interface shows a badge).
func _test_flags() -> void:
	I18n.load_all()
	for code in ["ru", "en"]:
		var tex := I18n.flag(code)
		check(tex != null and tex.get_width() > tex.get_height(), "flag %s not rendered" % code)
	check(I18n.flag("no_such") == null, "a flag for a nonexistent language")
	I18n.flag_svg["broken"] = "<svg not really"
	I18n.flag_svg["huge"] = "<svg xmlns='http://www.w3.org/2000/svg'>" + "x".repeat(5000) + "</svg>"
	check(I18n.flag("broken") == null, "a broken SVG produced a flag")
	check(I18n.flag("huge") == null, "an SVG longer than the limit was rasterized")
	I18n.load_all()


func _new_main() -> Node:
	var m = load("res://main.tscn").instantiate()
	m.fresh = true
	m.seed_arg = 7
	m.save_path = T_GARDEN
	m.progress_path = T_PROGRESS
	m.settings_path = T_SETTINGS
	m.playlog_path = T_PLAYLOG
	m.music_on = false
	root.add_child(m)
	return m


func _key(m, code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = pressed
	m._unhandled_input(ev)


## A real mouse press on a button: through Input (updates the mouse button state) and into the window (GUI).
func _mouse(btn: Control, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = btn.get_global_rect().get_center()
	ev.global_position = ev.position
	Input.parse_input_event(ev)   # mouse button state (Input.is_mouse_button_pressed)
	Input.flush_buffered_events()
	root.push_input(ev, true)     # interface coordinates; without a window (headless) Input doesn't deliver the event to the GUI — we send it to the window ourselves


func _about_text(ui) -> String:
	var parts := []
	for l in ui.about_box.get_children():
		if l is Label:
			parts.append(l.text)
	return "\n".join(parts)


## Stage 12: About — opened from the settings; Esc, "Back", a click outside the panel — back to the settings; a second Esc — everything
## closed; version = config/version; third-party components — only via the button; all Godot components, the Android block and
## the texts of all licenses are on screen.
func _test_about(m) -> void:
	var ui = m.ui
	ui.gear_btn.pressed.emit()
	check(ui.about_btn != null and ui.about_btn.is_visible_in_tree(), "no About button in the settings")
	ui.about_btn.pressed.emit()
	check(ui.about.visible and ui.settings.visible, "About didn't open on top of the settings")
	var ver := String(ProjectSettings.get_setting("application/config/version", ""))
	check(ver != "" and _about_text(ui).contains(I18n.t("ui.about.version", {"v": ver})), "the version is not on screen: \"%s\"" % ver)
	check(_about_text(ui).contains("Permission is hereby granted"), "no Godot license text")
	check(not ui.about_full and not _about_text(ui).contains("FreeType"), "third-party components built before the button")
	_key(m, KEY_ESCAPE, true)
	check(not ui.about.visible and ui.settings.visible, "Esc from About didn't return to the settings")
	ui.about_btn.pressed.emit()
	m.go_back()
	check(not ui.about.visible and ui.settings.visible, "\"Back\" from About didn't return to the settings")
	ui.about_btn.pressed.emit()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	ui.about.gui_input.emit(click)
	check(ui.about.visible, "a press outside About closed it before the release (stage 14: a sheet closes on the release)")
	var up := click.duplicate() as InputEventMouseButton
	up.pressed = false
	ui.about.gui_input.emit(up)
	check(not ui.about.visible and ui.settings.visible, "a click outside About didn't return to the settings")
	ui.about_btn.pressed.emit()
	_key(m, KEY_ESCAPE, true)
	_key(m, KEY_ESCAPE, true)
	check(not ui.about.visible and not ui.settings.visible and m.mode == "menu", "two Esc didn't close About and the settings")
	ui.gear_btn.pressed.emit()
	check(ui.settings.visible and not ui.about.visible, "the settings opened with About already open")
	ui.about_btn.pressed.emit()
	ui.fill_about_full(true)   # the Android block, as in the APK
	check(not ui.about_more.visible, "the third-party components button stayed after building")
	var txt := _about_text(ui)
	var missing := []
	for c in Engine.get_copyright_info():
		if not txt.contains(String(c["name"])):
			missing.append(c["name"])
	check(missing.is_empty(), "Godot components not on screen: %s" % [missing])
	for lib in ui.ANDROID_LIBS:
		check(txt.contains(lib[0]), "an Android library not on screen: " + lib[0])
	var info := Engine.get_license_info()
	for key in info:
		check(txt.contains(String(info[key]).substr(0, 200)), "no license text for " + String(key))
	check(info.has("Apache-2.0") and info.has("Expat"), "no Apache-2.0 / MIT texts for the Android libraries")
	check(txt.contains("LLVM Exceptions to the Apache 2.0 License") and txt.contains("by the contributors listed in CREDITS.TXT"),
		"no libc++ LICENSE.TXT (LLVM exceptions and legacy notices) in the Android block")
	for name in ui.SOURCE_LINKS:
		var url: String = ui.SOURCE_LINKS[name] % ui.godot_tag()
		check(txt.contains(url), "no source link for the MPL component " + name)
	check(ui.godot_tag() == "4.7.2-stable", "unexpected Godot tag: " + ui.godot_tag())
	ui.close_settings()
	await _frames(1)


## n tenths of a second in frames of 0.05 s (the game's frame step is limited to 1/15 s).
func _steps(ui, n: int) -> void:
	for i in n * 2:
		ui.hold_step(0.05)


func _test_scene() -> void:
	# stage 8 settings (language only) are read, volumes — the defaults
	_write(T_SETTINGS, {"lang": "en"})
	_write(T_PROGRESS, Progress.empty())
	var m = _new_main()
	await _frames(3)
	check(I18n.current() == "en", "the language from the old settings.json was not read")
	check(m.vol == Main.VOL_DEFAULT, "volumes are not the defaults: %s" % m.vol)
	var buses := AudioServer.bus_count
	for b in ["Master", "Music", "Effects"]:
		check(AudioServer.get_bus_index(b) >= 0, "no bus " + b)
	check(AudioServer.get_bus_send(AudioServer.get_bus_index("Music")) == "Master", "Music doesn't go to Master")
	check(m.sfx.players.all(func(p): return p.bus == "Effects"), "effects are not on the Effects bus")
	check(is_equal_approx(AudioServer.get_bus_volume_db(0), linear_to_db(0.8)), "Master volume not applied")

	# the gear in the menu opens the settings; sliders move the buses right away
	check(m.ui.gear_btn != null and m.ui.gear_btn.visible, "no gear in the menu")
	m.ui.gear_btn.pressed.emit()
	check(m.ui.settings.visible, "the gear didn't open the settings")
	check(m.ui.is_over_ui(Vector2(5, 5)), "clicks under the settings go into the game")
	var mi := AudioServer.get_bus_index("Music")
	m.ui.sliders["music"].value = 0.0
	check(AudioServer.is_bus_mute(mi) and is_equal_approx(m.vol["music"], 0.0), "0% music is not mute")
	m.ui.sliders["music"].value = 0.5
	check(not AudioServer.is_bus_mute(mi) and is_equal_approx(AudioServer.get_bus_volume_db(mi), linear_to_db(0.5)), "50% music not applied")
	check(m.ui.slider_pct["music"].text == "50%", "slider caption: %s" % m.ui.slider_pct["music"].text)
	m.ui.sliders["effects"].value = 0.35
	check(m.settings_timer > 0.0, "writing the settings is not scheduled")
	# the quick "quiet" mutes Master, doesn't touch the volumes
	m.toggle_sound()
	check(AudioServer.is_bus_mute(0) and is_equal_approx(m.vol["master"], 0.8), "\"quiet\" didn't mute Master or touched the volume")
	m.toggle_sound()
	check(not AudioServer.is_bus_mute(0), "\"quiet\" didn't turn off")
	# Esc closes the settings and writes them
	_key(m, KEY_ESCAPE, true)
	check(not m.ui.settings.visible and m.mode == "menu", "Esc didn't close the settings")
	var saved = _read(T_SETTINGS)
	check(saved is Dictionary and saved.get("lang") == "en" and is_equal_approx(float(saved["vol"]["music"]), 0.5) and is_equal_approx(float(saved["vol"]["effects"]), 0.35), "settings not written: %s" % saved)
	check(not FileAccess.file_exists(T_SETTINGS + ".tmp"), "a temporary settings file was left")
	await _test_about(m)

	# the carousel: a full circle of languages; after each change one interface, the settings open again, the text in the new language
	m.ui.show_settings()
	var langs := I18n.languages()
	check(m.ui.flag_btns.size() == langs.size(), "the number of flags under the carousel differs from the number of languages")
	for i in langs.size():
		var want: String = langs[(langs.find(I18n.current()) + 1) % langs.size()]
		m.ui.lang_next.pressed.emit()
		await _frames(3)
		var uis := 0
		for ch in m.get_children():
			if ch is CanvasLayer and ch.has_method("show_menu"):
				uis += 1
		check(I18n.current() == want, "carousel: expected %s, got %s" % [want, I18n.current()])
		check(uis == 1, "interfaces after the carousel: %d" % uis)
		check(m.ui.settings.visible, "the settings closed after the language change")
		check(m.ui.gear_btn.tooltip_text == I18n.t("ui.settings"), "the gear's caption is not in the new language")
		check(m.ui.flag_btns[I18n.current()].button_pressed, "the current language's flag is not pressed")
		check(is_equal_approx(m.ui.sliders["music"].value, 0.5), "the slider reset after the language change")
	check(_read(T_SETTINGS).get("lang") == I18n.current(), "the carousel language was not saved")
	m.ui.lang_prev.pressed.emit()
	await _frames(3)
	check(I18n.current() == langs[(langs.find("en") - 1 + langs.size()) % langs.size()], "the back arrow didn't change the language")
	m.ui.flag_btns["en"].pressed.emit()
	await _frames(3)
	check(I18n.current() == "en", "the flag didn't choose the language")
	check(m.ui._flag_view("zz", Vector2(54, 36)) is PanelContainer, "no badge without a flag")
	m.ui.close_settings()

	# reset: progress up to slot 80 (winter unlocked), the garden in winter
	var prog := Progress.empty()
	for L in Levels.LEVELS:
		if int(L["slot"]) <= 80:
			prog["levels"][L["id"]] = {"stars": 2, "best": 1, "crown": int(L["slot"]) % 10 == 0}
	prog["seen"] = ["tree", "snowman"]
	m.progress = prog
	m._save_progress()
	m.enter_sandbox()
	check("winter" in m.garden_seasons(), "winter in the garden didn't unlock from progress")
	m.set_garden_season("winter")
	m._finish_wave()
	var garden_items: int = m.items.size()
	check(garden_items > 0, "no items in the garden")
	# the gear in the corner panel — one click from the garden
	check(m.ui.settings_btn.visible, "no \"Settings\" in the garden's corner panel")
	m.ui.settings_btn.pressed.emit()
	check(m.ui.settings.visible, "\"Settings\" from the garden didn't open")
	m.ui.set_process(false)   # the hold step — manually
	m.ui.show_reset_confirm()
	await _frames(2)
	check(m.ui.confirm.visible and m.ui.hold_btn != null, "the reset window didn't open")
	var hb: Button = m.ui.hold_btn
	# released early — nothing, the bar drained
	_mouse(hb, true)
	await _frames(1)
	check(m.ui.hold_mouse, "the mouse press didn't start the hold")
	_steps(m.ui, 10)
	check(is_equal_approx(m.ui.hold_t, 1.0) and m.ui.hold_fill.size.x > 0.0, "the bar didn't fill a third in 1 s: %s" % m.ui.hold_t)
	_mouse(hb, false)
	await _frames(1)
	check(not m.ui.holding(), "the release didn't stop the hold")
	_steps(m.ui, 5)
	check(m.ui.hold_t == 0.0 and m.progress["levels"].size() > 0, "after an early release the bar didn't drain or progress was reset")
	# Esc during the hold — only cancels (the window stays)
	_mouse(hb, true)
	await _frames(1)
	_steps(m.ui, 5)
	_key(m, KEY_ESCAPE, true)
	check(not m.ui.holding() and m.ui.confirm.visible, "Esc during the hold didn't cancel it or closed the window")
	_mouse(hb, false)
	_steps(m.ui, 5)
	# window focus loss — cancel
	_mouse(hb, true)
	await _frames(1)
	_steps(m.ui, 5)
	m._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not m.ui.holding(), "focus loss didn't cancel the hold")
	_mouse(hb, false)
	_steps(m.ui, 5)
	# a release that didn't reach the button: the mouse button is no longer held — the hold ends by itself
	m.ui.hold_mouse = true
	_steps(m.ui, 1)
	check(not m.ui.hold_mouse, "the hold without a held mouse button didn't end")
	_steps(m.ui, 5)
	# a frame stall (5 s in one step) doesn't reset
	_mouse(hb, true)
	await _frames(1)
	m.ui.hold_step(5.0)
	check(m.ui.hold_t < 0.1 and m.progress["levels"].size() > 0, "a long frame reset the progress")
	_mouse(hb, false)
	_steps(m.ui, 5)
	check(m.progress["levels"].size() > 0 and _read(T_PROGRESS)["levels"].size() > 0, "progress suffered from cancelled holds")
	# Space, a 3 s hold — reset, once
	_key(m, KEY_SPACE, true)
	check(m.ui.hold_key, "Space didn't start the hold")
	_steps(m.ui, 29)
	check(m.progress["levels"].size() > 0, "reset before 3 s")
	_steps(m.ui, 2)
	check(m.progress["levels"].is_empty() and m.progress["seen"].is_empty(), "3 s of holding didn't reset the progress")
	check(_read(T_PROGRESS) is Dictionary and _read(T_PROGRESS)["levels"].is_empty(), "empty progress not written")
	check(_read(T_BAK) is Dictionary and _read(T_BAK)["levels"].size() > 0, "no progress copy in .bak")
	check(not m.ui.confirm.visible and not m.ui.settings.visible and m.mode == "menu", "didn't return to the menu after the reset")
	check(m.ui.toast_label.text == I18n.t("toast.reset"), "no reset toast")
	check(m.ui.menu_season == "spring", "after the reset the menu is not on spring: %s" % m.ui.menu_season)
	check(m.ui.hold_fired, "firing not recorded")
	_key(m, KEY_SPACE, false)
	# no progress — nothing to reset
	m.ui.show_settings()
	m.ui.show_reset_confirm()
	check(m.ui.hold_btn == null, "a reset button without progress")
	_key(m, KEY_ESCAPE, true)
	check(not m.ui.confirm.visible and m.ui.settings.visible, "Esc closed more than the top window")
	_key(m, KEY_ESCAPE, true)
	check(not m.ui.settings.visible, "the second Esc didn't close the settings")
	m.ui.set_process(true)
	# the garden after a reset: data intact, season — summer, a toast explains
	m.enter_sandbox()
	m._finish_wave()
	check(m.garden_season == "summer", "the garden after the reset is not summer: %s" % m.garden_season)
	check(m.items.size() == garden_items, "the reset touched the garden: %d -> %d" % [garden_items, m.items.size()])
	check(m.ui.toast_label.text == I18n.t("toast.garden_locked"), "no explanation about the garden's seasons")
	# from a level — also one click
	m.start_level(0)
	await _frames(1)
	check(m.ui.settings_btn.visible, "no \"Settings\" in the level's corner panel")
	m.ui.settings_btn.pressed.emit()
	check(m.ui.settings.visible, "\"Settings\" from a level didn't open")
	_key(m, KEY_ESCAPE, true)
	check(m.mode == "level" and not m.ui.settings.visible, "Esc in a level's settings went to the menu")
	m.save_enabled = false
	m.queue_free()
	await _frames(2)
	# a second Main: buses didn't multiply, volumes were read
	var m2 = _new_main()
	await _frames(2)
	check(AudioServer.bus_count == buses, "buses multiplied: %d -> %d" % [buses, AudioServer.bus_count])
	check(is_equal_approx(m2.vol["effects"], 0.35), "effects volume not read at startup")
	m2.save_enabled = false
	m2.queue_free()
	await _frames(2)
