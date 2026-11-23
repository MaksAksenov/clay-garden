extends SceneTree
## Stage 10: touch. Run: Godot --headless --path . --script res://tests/test_touch.gd
## Synthetic InputEventScreenTouch/Drag straight into the world: try and confirm (a second tap, the ✓ button, protection against
## a double tap), moving and clearing the tried cell, long press (ring, back to hand), a camera drag places nothing, finger
## tremor is still a tap, pinch and releasing a finger mid-pinch, a tap on the interface doesn't place in the world,
## emulated mouse doesn't place, undo of every kind of action, garden — a tap places right away, "Back", pause.
## Layout at the phone's logical size of 1333×600: everything on screen, panels don't overlap, buttons ≥ 56 px.
## The player's files are compared by md5 before and after.

const Levels := preload("res://scripts/levels.gd")
const I18n := preload("res://scripts/i18n.gd")
const Campaign := preload("res://scripts/campaign.gd")

const PLAYER_FILES := ["user://progress.json", "user://garden.json", "user://settings.json", "user://playlog.json"]
const NO_CELL := Vector2i(-1, -1)

var checks := 0
var failed := 0
var m


func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		print("FAIL: " + what)


func _initialize() -> void:
	_run()


func _run() -> void:
	var before := _hashes()
	# phone: the logical size exactly 1333×600 (without a window the headless window is 64×64, "keep" gives exactly the base size)
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	m = load("res://main.tscn").instantiate()
	m.touch_mode = true
	m.fresh = true
	m.new_player = true
	m.seed_arg = 7
	m.save_enabled = false
	m.music_on = false
	m.lang_arg = "ru"
	m.save_path = "user://test_garden_touch.json"
	m.progress_path = "user://test_progress_touch.json"
	m.settings_path = "user://test_settings_touch.json"
	m.playlog_path = "user://test_playlog_touch.json"
	root.add_child(m)
	await _frames(3)
	check(root.get_visible_rect().size == Vector2(1333, 600), "the logical size is not the phone's: %s" % root.get_visible_rect().size)
	await _test_level()
	await _test_sandbox()
	await _test_back()
	await _test_layout()
	m.queue_free()
	await _frames(2)
	check(_hashes() == before, "player files changed")
	I18n.set_lang("ru")
	print("TESTS %s: %d checks, %d failed" % ["OK" if failed == 0 else "FAILED", checks, failed])
	quit(0 if failed == 0 else 1)


func _hashes() -> Dictionary:
	var out := {}
	for f in PLAYER_FILES:
		out[f] = FileAccess.get_md5(f) if FileAccess.file_exists(f) else "-"
	return out


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _physics() -> void:
	for i in 3:
		await physics_frame


## The screen point of a cell's top (the camera has settled).
func _screen(c: Vector2i) -> Vector2:
	return m.cam.unproject_position(m.terrain.cell_center(c) + Vector3(0, m.terrain.surface_y(c), 0))


func _touch(idx: int, pos: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = idx
	ev.position = pos
	ev.pressed = pressed
	m._unhandled_input(ev)


func _drag(idx: int, pos: Vector2, rel: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = idx
	ev.position = pos
	ev.relative = rel
	m._unhandled_input(ev)


func _tap(pos: Vector2) -> void:
	_touch(0, pos, true)
	_touch(0, pos, false)


## Cells that: a tap hits themselves, are not under the interface, are free and suit the current tool.
func _good_cells(n: int) -> Array:
	var out := []
	var keys: Array = m.terrain.heights.keys()
	keys.sort()
	for c in keys:
		var p := _screen(c)
		if m.items.has(c) or not m._is_valid(c) or m.ui.is_over_ui(p) or m._pick(p) != c:
			continue
		out.append(c)
		if out.size() >= n:
			break
	return out


## A screen point off the island and off the interface.
func _empty_point() -> Vector2:
	for y in range(80, 560, 20):
		for x in range(400, 1000, 20):
			var p := Vector2(x, y)
			if not m.ui.is_over_ui(p) and m._pick(p) == NO_CELL:
				return p
	return Vector2(-1, -1)


func _settle() -> void:
	m.zoom_target = m.cam.size
	m.pivot.rotation.y = m.yaw_target
	await _frames(2)
	await _physics()


func _test_level() -> void:
	m.start_level(0)
	await _frames(3)
	await _settle()
	var cells := _good_cells(4)
	check(cells.size() == 4, "too few cells for the check: %d" % cells.size())
	if cells.size() < 4:
		return
	var tool: String = m.tool
	var n0: int = m.hand[tool]
	var c0: Vector2i = cells[0]
	# try
	_tap(_screen(c0))
	await _frames(2)
	check(m.aim_cell == c0 and not m.items.has(c0), "the tap didn't try or placed right away")
	check(m.ghost != null and m.ghost.visible, "no ghost while trying")
	check(m.ui.bubble.visible and m.ui.bubble_kind == "ok", "no ✓ button above the tried cell")
	check(m.ui.toast_label.text == I18n.t("coach.aim"), "no tip about trying")
	# a double tap faster than 0.25 s doesn't place
	_tap(_screen(c0))
	check(not m.items.has(c0), "a double tap placed the item")
	# a later second tap places
	m.t += 0.3
	_tap(_screen(c0))
	check(m.items.has(c0) and m.items[c0]["id"] == tool, "the second tap didn't place")
	check(int(m.hand.get(tool, 0)) == n0 - 1, "the hand didn't shrink")
	check(m.aim_cell == NO_CELL, "the tried cell wasn't cleared after placing")
	await _frames(2)
	# the ✓ button
	tool = m.tool
	var c1: Vector2i = cells[1]
	if not m._is_valid(c1):
		c1 = _good_cells(1)[0]
	_tap(_screen(c1))
	await _frames(2)
	m.ui.bubble.pressed.emit()
	check(m.items.has(c1), "the ✓ button didn't place")
	# undoing a placement — the item goes back to the hand
	var before_undo: int = int(m.hand.get(m.items[c1]["id"], 0))
	var id1: String = m.items[c1]["id"]
	m.ui.act_undo.pressed.emit()
	check(not m.items.has(c1) and int(m.hand.get(id1, 0)) == before_undo + 1, "undoing a placement didn't return the item to the hand")
	# moving and clearing the tried cell
	await _settle()
	var free := _good_cells(2)
	_tap(_screen(free[0]))
	_tap(_screen(free[1]))
	check(m.aim_cell == free[1], "the tried cell didn't move")
	var empty := _empty_point()
	check(empty.x >= 0, "no point off the island found")
	_tap(empty)
	check(m.aim_cell == NO_CELL, "a tap off the island didn't clear the tried cell")
	# finger tremor below the threshold — still a tap
	_touch(0, _screen(free[0]), true)
	_drag(0, _screen(free[0]) + Vector2(10, 6), Vector2(10, 6))
	_touch(0, _screen(free[0]) + Vector2(10, 6), false)
	check(m.aim_cell == m._pick(_screen(free[0]) + Vector2(10, 6)) and m.aim_cell != NO_CELL, "finger tremor broke the tap")
	_tap(empty)
	# a camera drag places nothing
	var placed: int = m.items.size()
	var p0: Vector3 = m.pivot.position
	var sp := _screen(free[0])
	_touch(0, sp, true)
	for i in 6:
		_drag(0, sp + Vector2(15 * (i + 1), 0), Vector2(15, 0))
	_touch(0, sp + Vector2(90, 0), false)
	check(m.pivot.position.distance_to(p0) > 0.1, "a finger drag didn't move the camera")
	check(m.items.size() == placed and m.aim_cell == NO_CELL, "a camera drag placed or tried")
	await _settle()
	# long press: the ring, then back to hand; releasing afterwards — nothing
	var cp := _screen(c0)
	var idp: String = m.items[c0]["id"]
	var hp: int = int(m.hand.get(idp, 0))
	_touch(0, cp, true)
	m.t += 0.3
	m._touch_hold()
	check(m.ui.ring.visible and m.items.has(c0), "no long-press ring or the item was removed early")
	m.t += 0.2
	m._touch_hold()
	check(not m.items.has(c0) and int(m.hand.get(idp, 0)) == hp + 1, "the long press didn't return the item to the hand")
	check(not m.ui.ring.visible, "the ring didn't hide")
	_touch(0, cp, false)
	check(m.aim_cell == NO_CELL, "the release after a long press acted as a tap")
	# undoing the return to hand — the item is back in place
	m.ui.act_undo.pressed.emit()
	check(m.items.has(c0) and int(m.hand.get(idp, 0)) == hp, "undoing the return didn't put the item back")
	# the button above a placed item — back to hand
	_tap(cp)
	await _frames(2)
	check(m.ui.bubble.visible and m.ui.bubble_kind == "back", "no \"back to hand\" button above a placed item")
	m.ui.bubble.pressed.emit()
	check(not m.items.has(c0), "the \"back to hand\" button didn't remove")
	_tap(empty)
	# pinch: zoom; one finger released — the other neither moves nor taps
	await _settle()
	var z0: float = m.zoom_target
	var a := Vector2(600, 300)
	var b := Vector2(700, 300)
	_touch(0, a, true)
	_touch(1, b, true)
	_drag(1, Vector2(800, 300), Vector2(100, 0))
	check(m.zoom_target < z0, "the pinch didn't zoom in: %s -> %s" % [z0, m.zoom_target])
	_touch(1, Vector2(800, 300), false)
	var p1: Vector3 = m.pivot.position
	_drag(0, a + Vector2(80, 0), Vector2(80, 0))
	_touch(0, a + Vector2(80, 0), false)
	check(m.pivot.position == p1 and m.aim_cell == NO_CELL, "the finger after the pinch moved the camera or tried")
	check(not m.multi and m.fingers.is_empty(), "the finger state wasn't cleared")
	# a tap on an interface button doesn't place or try
	await _settle()
	var bp: Vector2 = m.ui.buttons[m.tool].get_global_rect().get_center()
	var cnt: int = m.items.size()
	_tap(bp)
	check(m.items.size() == cnt and m.aim_cell == NO_CELL, "a tap on the palette went into the world")
	_tap(m.ui.act_undo.get_global_rect().get_center())
	check(m.aim_cell == NO_CELL, "a tap on the undo button went into the world")
	# the mouse (including emulated from touches) doesn't touch the world in touch mode
	var free2 := _good_cells(1)
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	mb.position = _screen(free2[0])
	m._unhandled_input(mb)
	mb.pressed = false
	m._unhandled_input(mb)
	check(m.items.size() == cnt and m.painting == 0, "the mouse placed an item in touch mode")
	# action buttons
	check(m.ui.actions.visible, "no action buttons on a level")
	var y0: float = m.yaw_target
	m.ui.act_rot_island.pressed.emit()
	check(is_equal_approx(m.yaw_target, y0 + PI * 0.5), "the rotate-island button didn't rotate")
	# the rules card: the header collapses it; the state survives a language change
	check(m.ui.help.visible and m.ui.card_scroll.visible, "the rules card is not expanded on a level")
	m.ui.card_head.pressed.emit()
	check(not m.ui.card_scroll.visible and m.card_collapsed, "the card header didn't collapse it")
	m.set_language("en")
	await _frames(2)
	check(not m.ui.card_scroll.visible, "the card expanded after the language change")
	m.ui.card_head.pressed.emit()
	m.set_language("ru")
	await _frames(2)
	check(m.ui.card_scroll.visible, "the card didn't expand back")
	# "≡": opens, a tap outside closes it and doesn't reach the world
	m.ui.menu_toggle.pressed.emit()
	check(m.ui.corner.visible and m.ui.is_over_ui(Vector2(700, 300)), "\"≡\" didn't open or a tap outside goes into the world")
	m.go_back()
	check(not m.ui.corner.visible and m.mode == "level", "\"Back\" didn't close \"≡\"")
	var r0: int = m.ghost_rot
	m.rotate_item()
	check(m.ghost_rot == (r0 + 1) % 4, "rotating the item didn't work")


func _test_sandbox() -> void:
	m.enter_sandbox()
	await _frames(3)
	await _settle()
	check(m.ui.toast_label.text == I18n.t("coach.sandbox"), "no tip in the garden")
	check(not m.ui.help.visible and m.ui.memo_btn.visible, "in the garden the rules card is visible or there is no \"?\"")
	m.ui.memo_btn.pressed.emit()
	check(m.ui.memo.visible and m.ui.memo_body.text == I18n.t("ui.help.sandbox_touch"), "\"?\" didn't show the gesture cheat sheet")
	m.ui.memo_btn.pressed.emit()
	check(not m.ui.memo.visible, "\"?\" didn't close the cheat sheet")
	# the season bar: a tap changes the season (if more than one is unlocked)
	var opts: Array = m.garden_seasons()
	var s0: String = m.garden_season
	m.ui.chip.pressed.emit()
	if opts.size() > 1:
		check(m.garden_season != s0, "a tap on the bar didn't change the season")
		m.set_garden_season(s0)
		m._finish_wave()
	else:
		check(m.ui.toast_label.text == I18n.t("ui.corner.season_locked"), "a locked season: no explanation")
	m.set_tool("flowers")
	var cells := _good_cells(2)
	var c: Vector2i = cells[0]
	_tap(_screen(c))
	check(m.items.has(c) and m.items[c]["id"] == "flowers", "a tap in the garden didn't place right away")
	# undo: remove what was placed
	m.undo()
	check(not m.items.has(c), "undo in the garden didn't remove the item")
	# land: raise and undo
	m.set_tool("raise")
	await _settle()
	var c2: Vector2i = _good_cells(1)[0]
	var h0: int = m.terrain.heights.get(c2, 0)
	_tap(_screen(c2))
	check(int(m.terrain.heights.get(c2, 0)) == h0 + 1, "a \"Raise\" tap didn't raise")
	m.undo()
	check(int(m.terrain.heights.get(c2, 0)) == h0, "undo didn't restore the height")
	# a long press removes, undo returns
	m.set_tool("flowers")
	await _settle()
	var c3: Vector2i = _good_cells(1)[0]
	_tap(_screen(c3))
	await _settle()
	_touch(0, _screen(c3), true)
	m.t += 0.5
	m._touch_hold()
	_touch(0, _screen(c3), false)
	check(not m.items.has(c3), "a long press in the garden didn't remove")
	m.undo()
	check(m.items.has(c3), "undo didn't return the removed item")
	# no more than 10 steps
	for i in 14:
		m.undo_stack.append({"c": c3, "s": m._cell_state(c3)})
	m._push_undo(c3, {"h": 0, "w": false, "b": 0.0, "it": null})
	check(m.undo_stack.size() <= 15, "undo stack")
	m.undo_stack.clear()


func _test_back() -> void:
	m.start_level(0)
	await _frames(2)
	m.ui.show_settings()
	m.go_back()
	check(not m.ui.settings.visible and m.mode == "level", "\"Back\" didn't close the settings")
	m.go_back()
	check(m.mode == "menu", "\"Back\" from a level didn't go to the menu")
	m.go_back()
	check(m.back_armed > 0.0 and m.ui.toast_label.text == I18n.t("toast.back_exit"), "\"Back\" in the menu didn't warn about exiting")
	m.back_armed = 0.0
	m.save_timer = 0.4
	m.fingers[3] = {"start": Vector2.ZERO, "pos": Vector2.ZERO, "t0": 0.0, "ui": false, "moved": false, "long": false}
	m._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	check(m.save_timer < 0.0 and m.fingers.is_empty(), "the app pause didn't save or didn't reset the fingers")


## Phone layout: panels on screen, no overlaps; buttons at least 56 px; the 48 px side margins are free.
func _check_layout(where: String, panels: Array) -> void:
	await _frames(3)
	var vr: Rect2 = root.get_visible_rect()
	var rects := []
	for c in panels:
		if c == null or not c.is_visible_in_tree():
			continue
		var r: Rect2 = c.get_global_rect()
		check(vr.encloses(r), "%s: %s off screen: %s" % [where, c.name, r])
		for o in rects:
			check(not r.intersects(o[1]), "%s: %s overlaps %s" % [where, c.name, o[0]])
		rects.append([c.name, r])
	_small_buttons(m.ui.root, where)


func _small_buttons(n: Node, where: String) -> void:
	if n is Control and not (n as Control).is_visible_in_tree():
		return
	if n is Button:
		var r := (n as Button).get_global_rect()
		check(r.size.y >= 55.5, "%s: button \"%s\" lower than 56 px: %s" % [where, (n as Button).text, r.size])
	for ch in n.get_children():
		_small_buttons(ch, where)


## Game panels don't enter the 48 px side margins (the Pixel's camera hole in landscape) or the bottom 24 px.
func _margins(where: String, panels: Array) -> void:
	var w: float = root.get_visible_rect().size.x
	var h: float = root.get_visible_rect().size.y
	for c in panels:
		if c == null or not c.is_visible_in_tree():
			continue
		var r: Rect2 = c.get_global_rect()
		check(r.position.x >= 47.5 and r.end.x <= w - 47.5 and r.end.y <= h - 23.5, "%s: %s in a side margin or at the edge: %s" % [where, c.name, r])


func _name_panels(u) -> void:
	for pair in [["items_panel", "dock"], ["land_panel", "land"], ["actions", "cluster"], ["act_main", "action"], ["hud", "bar"],
			["help", "card"], ["menu_toggle", "≡"], ["memo_btn", "?"], ["chip", "season"], ["name_chip", "name"], ["corner", "≡ list"], ["memo", "cheat sheet"]]:
		(u.get(pair[0]) as Control).name = pair[1]


func _game_panels(u) -> Array:
	return [u.items_panel, u.land_panel, u.actions, u.act_main, u.hud, u.help, u.menu_toggle, u.memo_btn, u.chip, u.name_chip]


func _test_layout() -> void:
	# 1333×750 — a 16:9 phone and the store screenshot frame (stage 12)
	for size in [Vector2i(1333, 600), Vector2i(1200, 600), Vector2i(1333, 750)]:
		root.content_scale_size = size
		for lang in ["ru", "en"]:
			m.set_language(lang)
			await _frames(2)
			var u = m.ui
			_name_panels(u)
			var tag := "%s %d" % [lang, size.x]
			m.open_menu()
			for s in Campaign.SEASONS:
				u.menu_season = s["id"]
				u._fill_menu()
				await _check_layout("%s menu/%s" % [tag, s["id"]], [u.menu.get_child(0).get_child(0)])
			u.show_settings()
			await _check_layout(tag + " settings", [u.settings.get_child(0).get_child(0)])
			u.show_reset_confirm()
			await _check_layout(tag + " reset", [u.confirm.get_child(0).get_child(0)])
			u.confirm.visible = false
			u.show_about()
			u.fill_about_full(true)
			await _check_layout(tag + " about", [u.about_panel])
			check(u.about_scroll.size.y > 300.0, "%s about: the scroll collapsed: %s" % [tag, u.about_scroll.size])
			var narrow := 0
			for l in u.about_box.get_children():
				if l is Label and l.size.x < u.about_scroll.size.x - 30.0:
					narrow += 1
			check(narrow == 0, "%s about: %d labels narrower than the scroll (letter-by-letter wrapping)" % [tag, narrow])
			u.close_about()
			u.close_settings()
			m.enter_sandbox()
			await _settle()
			var gc := _good_cells(1)
			if gc.size() > 0:
				m._set_aim(gc[0])
			await _check_layout(tag + " garden", _game_panels(u))
			_margins(tag + " garden", _game_panels(u))
			m.toggle_cozy()
			await _check_layout(tag + " garden, coziness", _game_panels(u))
			m.toggle_cozy()
			u.toggle_drawer()
			await _check_layout(tag + " garden, \"≡\"", [u.corner, u.hud, u.memo_btn, u.chip, u.items_panel, u.land_panel, u.actions])
			u.toggle_help()
			await _check_layout(tag + " garden, \"?\"", [u.memo, u.corner, u.menu_toggle, u.chip, u.items_panel, u.land_panel, u.actions])
			u.close_popups()
			for slot in [1, 38, 66, 79, 97]:
				m.start_level(slot - 1)
				await _settle()
				var free := _good_cells(1)
				if free.size() > 0:
					m._set_aim(free[0])
				await _check_layout("%s level %d" % [tag, slot], _game_panels(u))
				_margins("%s level %d" % [tag, slot], _game_panels(u))
				u.toggle_help()
				await _check_layout("%s level %d, \"?\"" % [tag, slot], [u.memo, u.hud, u.help, u.menu_toggle, u.items_panel, u.actions])
				u.close_popups()
			u.show_result(3, 99, Levels.LEVELS[0], true, true)
			await _check_layout(tag + " result", [u.result.get_child(0).get_child(0)])
			u.hide_result()
	root.content_scale_size = Vector2i(1333, 600)
	# the rules card doesn't overlap the dock on any level, for any hand item
	m.set_language("ru")
	await _frames(2)
	var u2 = m.ui
	var worst := 0.0
	for i in Levels.LEVELS.size():
		m.start_level(i)
		for id in m.hand:
			m.set_tool(id)
			await _frames(2)
			var gap: float = u2.items_panel.get_global_rect().position.y - u2.help.get_global_rect().end.y
			worst = minf(worst, gap) if worst != 0.0 else gap
			if gap < 8.0:
				check(false, "level %d, %s: the rules card overlaps the dock (gap %.0f)" % [i + 1, id, gap])
	print("smallest card–dock gap: %.0f px" % worst)
	# the card header: sits exactly on the panel's padding, the roundings are concentric (header radius = panel radius − padding),
	# the left and right text padding is no less than the vertical one
	var hp: Rect2 = u2.help.get_global_rect()
	var hh: Rect2 = u2.card_head.get_global_rect()
	var psb: StyleBoxFlat = u2.help.get_theme_stylebox("panel")
	var inset: float = psb.content_margin_left
	check(is_equal_approx(hh.position.x - hp.position.x, inset) and is_equal_approx(hh.position.y - hp.position.y, psb.content_margin_top), "the card header is not on the panel's padding: %s in %s" % [hh, hp])
	for st in ["normal", "hover", "pressed", "hover_pressed"]:
		var hsb: StyleBoxFlat = u2.card_head.get_theme_stylebox(st)
		check(hsb.corner_radius_top_left == psb.corner_radius_top_left - int(inset), "the header (%s) and card roundings are not concentric: %d with %d − %d" % [st, hsb.corner_radius_top_left, psb.corner_radius_top_left, int(inset)])
		var font_h: float = u2.card_head.get_theme_font("font").get_height(u2.card_head.get_theme_font_size("font_size"))
		check(hsb.content_margin_left >= (hh.size.y - font_h) / 2.0 - 1.0, "the header's left text padding (%s) is less than the vertical one: %.0f < %.0f" % [st, hsb.content_margin_left, (hh.size.y - font_h) / 2.0])
	# on a phone no level hint and no result talk about keys or the mouse
	var keys := RegEx.create_from_string("\\b(Tab|Esc|Shift|Ctrl|WASD|F\\d+)\\b|ЛКМ|ПКМ|СКМ|[Rr]ight.click|[Ll]eft.click|колес|wheel")
	check(keys.search(I18n.t("level.four_times.hint")) != null and keys.search("ПКМ возвращает") != null, "the key check catches nothing")
	for lang in ["ru", "en"]:
		m.set_language(lang)
		await _frames(1)
		for i in Levels.LEVELS.size():
			m.start_level(i)
			var hint: String = m.ui.hud_hint.text
			check(keys.search(hint) == null, "%s level %d: a phone hint about keys: %s" % [lang, i + 1, hint])
		m.ui.show_result(0, 10, Levels.LEVELS[0], false, true)
		check(keys.search(m.ui.res_text.text) == null, "%s result without a star mentions the mouse: %s" % [lang, m.ui.res_text.text])
		m.ui.hide_result()
	m.set_language("ru")
