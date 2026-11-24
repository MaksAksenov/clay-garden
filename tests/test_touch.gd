extends SceneTree
## Stages 10 and 14: touch. Run: Godot --headless --path . --script res://tests/test_touch.gd
## Synthetic InputEventScreenTouch/Drag straight into the world: try and place (the same cell again; a duplicate event
## doesn't place), moving and clearing the tried cell, long press (ring, back to hand), the trash, a drag turns the island
## (no lag, the pivot never moves), inertia and a touch that stops it, Q / E positions, the soft snap, finger tremor is
## still a tap, pinch and releasing a finger mid-pinch, a tap on the interface doesn't reach the world, emulated mouse
## doesn't place, undo of every kind of action, the pending result, garden — a tap places right away and a tap on an item
## selects it, "Back" (inside a level it opens "≡"), pause.
## Stage 14 bug 1: "≡" / "?" open and close through the real GUI path (root.push_input) with the touch and its emulated
## mouse twin in both orders. Bug 2: the island's screen position doesn't move when the rules card collapses or a sheet
## opens, at any zoom.
## Layout at 1333×600, 1200×600 and 1333×750: everything on screen, no overlaps, buttons ≥ 56 px, one gap (16) to the
## edges and between neighbors. The player's files are compared by md5 before and after.

const Levels := preload("res://scripts/levels.gd")
const I18n := preload("res://scripts/i18n.gd")
const Campaign := preload("res://scripts/campaign.gd")

const PLAYER_FILES := ["user://progress.json", "user://garden.json", "user://settings.json", "user://playlog.json"]
const NO_CELL := Vector2i(-1, -1)
const GAP := 16.0

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
	m.result_delay = 0.0
	root.add_child(m)
	await _frames(3)
	check(root.get_visible_rect().size == Vector2(1333, 600), "the logical size is not the phone's: %s" % root.get_visible_rect().size)
	_test_yaw_math()
	await _test_level()
	await _test_sheets_input()
	await _test_framing()
	await _test_result_wait()
	await _test_sandbox()
	await _test_back()
	await _test_layout()
	m.queue_free()
	await _frames(2)
	for f in ["user://test_progress_touch.json", "user://test_playlog_touch.json"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
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


## A tap through the real GUI path: the touch and its emulated mouse twin, in the given order, press then release.
func _gui_tap(pos: Vector2, touch_first: bool) -> void:
	for pressed in [true, false]:
		var t := InputEventScreenTouch.new()
		t.index = 0
		t.position = pos
		t.pressed = pressed
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.position = pos
		mb.global_position = pos
		mb.pressed = pressed
		mb.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		var order: Array = [t, mb] if touch_first else [mb, t]
		for ev in order:
			root.push_input(ev, true)


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
	m.yaw_vel = 0.0
	m.zoom_target = m.cam.size
	m.pivot.rotation.y = m.yaw_target
	await _frames(2)
	await _physics()


## Q / E positions and the soft snap — pure math (stage 14, D4).
func _test_yaw_math() -> void:
	var cases := [[45.0, 1, 135.0], [44.99, 1, 135.0], [75.0, 1, 135.0], [130.0, 1, 225.0], [-30.0, -1, -45.0], [-40.0, -1, -135.0],
		[3645.0, 1, 3735.0], [3645.0, -1, 3555.0], [45.0, -1, -45.0], [52.0, -1, -45.0]]
	for cs in cases:
		var got: float = rad_to_deg(m.next_yaw(deg_to_rad(cs[0]), cs[1]))
		check(absf(got - cs[2]) < 0.01, "Q/E from %.2f° (%d): %.2f°, expected %.2f°" % [cs[0], cs[1], got, cs[2]])
	m.yaw_target = deg_to_rad(52.0)
	m._soft_snap()
	check(absf(rad_to_deg(m.yaw_target) - 45.0) < 0.01, "the soft snap didn't ease 52° into 45°")
	m.yaw_target = deg_to_rad(70.0)
	m._soft_snap()
	check(absf(rad_to_deg(m.yaw_target) - 70.0) < 0.01, "the soft snap moved a free angle (70°)")
	m.yaw_target = deg_to_rad(45.0)


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
	check(m.ui.bubble_kind == "ok" and m.ui.act_trash.modulate.a < 0.9, "trying an empty cell: the trash should be dim")
	check(m.ui.toast_label.text == I18n.t("coach.aim"), "no tip about trying")
	# the same tap's duplicate event (no time between) doesn't place
	_tap(_screen(c0))
	check(not m.items.has(c0), "a duplicate event placed the item")
	# a quick second tap (0.1 s — a double tap) places
	m.t += 0.1
	_tap(_screen(c0))
	check(m.items.has(c0) and m.items[c0]["id"] == tool, "the second tap didn't place")
	check(int(m.hand.get(tool, 0)) == n0 - 1, "the hand didn't shrink")
	check(m.aim_cell == NO_CELL, "the tried cell wasn't cleared after placing")
	await _frames(2)
	# a second item by a double tap
	var c1: Vector2i = cells[1]
	if not m._is_valid(c1):
		c1 = _good_cells(1)[0]
	_tap(_screen(c1))
	m.t += 0.1
	_tap(_screen(c1))
	check(m.items.has(c1), "the double tap didn't place the second item")
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
	# a drag turns the island: the yaw follows the finger at once, the pivot stays, nothing is placed or tried
	var placed: int = m.items.size()
	var p0: Vector3 = m.pivot.position
	var y0: float = m.yaw_target
	var sp := _screen(free[0])
	_touch(0, sp, true)
	var lag := 0.0
	for i in 6:
		_drag(0, sp + Vector2(15 * (i + 1), 0), Vector2(15, 0))
		lag = maxf(lag, absf(m.pivot.rotation.y - m.yaw_target))
	_touch(0, sp + Vector2(90, 0), false)
	check(m.pivot.position == p0, "a drag moved the island's center")
	check(m.yaw_target < y0 - 0.05, "a drag to the right didn't turn the island (yaw %.3f -> %.3f)" % [y0, m.yaw_target])
	check(lag < 0.0001, "the island lags behind the finger: %.4f rad" % lag)
	check(m.items.size() == placed and m.aim_cell == NO_CELL, "a drag placed or tried")
	# a touch during the spin stops it and isn't a tap
	m.yaw_vel = 3.0
	_tap(_screen(free[0]))
	check(m.yaw_vel == 0.0 and m.aim_cell == NO_CELL, "a touch during the spin didn't stop it or acted as a tap")
	m.yaw_target = m.next_yaw(m.yaw_target, 1)
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
	# the trash: nothing selected — a hint; a tap on the item selects it, the trash returns it to the hand
	m.ui.act_trash.pressed.emit()
	check(m.items.has(c0) and m.ui.toast_label.text == I18n.t("toast.trash_pick"), "the trash without a selection: no hint")
	_tap(cp)
	await _frames(2)
	check(m.ui.bubble_kind == "back" and m.ui.act_trash.modulate.a > 0.9, "a selected item doesn't light the trash")
	m.ui.act_trash.pressed.emit()
	check(not m.items.has(c0) and int(m.hand.get(idp, 0)) == hp + 1, "the trash didn't return the item to the hand")
	_tap(empty)
	# pinch: zoom; one finger released — the other neither turns nor taps
	await _settle()
	m.zoom_target = m.zoom_max
	var z0: float = m.zoom_target
	var a := Vector2(600, 300)
	var b := Vector2(700, 300)
	_touch(0, a, true)
	_touch(1, b, true)
	_drag(1, Vector2(800, 300), Vector2(100, 0))
	check(m.zoom_target < z0, "the pinch didn't zoom in: %s -> %s" % [z0, m.zoom_target])
	_touch(1, Vector2(800, 300), false)
	var y1: float = m.yaw_target
	_drag(0, a + Vector2(80, 0), Vector2(80, 0))
	_touch(0, a + Vector2(80, 0), false)
	check(m.yaw_target == y1 and m.aim_cell == NO_CELL, "the finger after the pinch turned the island or tried")
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
	# the action column: "rotate item" keeps its slot — trash and undo don't move when it appears
	check(m.ui.actions.visible, "no action buttons on a level")
	var tr0: Rect2 = m.ui.act_trash.get_global_rect()
	m.ui.act_rot_item.modulate.a = 1.0 - m.ui.act_rot_item.modulate.a
	await _frames(1)
	check(m.ui.act_trash.get_global_rect() == tr0, "the trash moved when \"rotate item\" changed")
	m.ui._sync_actions()
	# Q / E from a free angle land on the next position
	m.yaw_target = deg_to_rad(75.0)
	m.rotate_island(1)
	check(absf(rad_to_deg(m.yaw_target) - 135.0) < 0.01, "E from 75° didn't land on 135°")
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
	# "≡" opens a full-screen sheet; "Back" closes it; "Back" with nothing open opens it (an edge swipe is Back)
	m.ui.menu_toggle.pressed.emit()
	check(m.ui.drawer.visible and m.ui.is_over_ui(Vector2(700, 300)), "\"≡\" didn't open or a tap outside goes into the world")
	m.go_back()
	check(not m.ui.drawer.visible and m.mode == "level", "\"Back\" didn't close \"≡\"")
	m.go_back()
	check(m.ui.drawer.visible and m.mode == "level", "\"Back\" in a level left it instead of opening \"≡\"")
	m.go_back()
	var r0: int = m.ghost_rot
	m.rotate_item()
	check(m.ghost_rot == (r0 + 1) % 4, "rotating the item didn't work")


## Bug 1: "≡" and "?" through the real GUI path, the touch and its mouse twin in both orders: a tap opens, a second tap on
## the same button (now under the scrim) closes, and nothing reaches the world.
func _test_sheets_input() -> void:
	m.start_level(0)
	await _settle()
	var u = m.ui
	for touch_first in [true, false]:
		var tag := "touch first" if touch_first else "mouse first"
		for pair in [[u.menu_toggle, u.drawer, "≡"], [u.memo_btn, u.memo, "?"]]:
			var p: Vector2 = (pair[0] as Control).get_global_rect().get_center()
			_gui_tap(p, touch_first)
			await _frames(2)
			check((pair[1] as Control).visible, "%s: a tap on \"%s\" didn't open it" % [tag, pair[2]])
			_gui_tap(p, touch_first)
			await _frames(2)
			check(not (pair[1] as Control).visible, "%s: a second tap on \"%s\" didn't close it (bug 1)" % [tag, pair[2]])
			check(m.aim_cell == NO_CELL and m.fingers.is_empty(), "%s: the tap on \"%s\" reached the world" % [tag, pair[2]])
		# a tap on the dim over the island closes the sheet and doesn't act on a cell (the garden: its island is wider
		# than the panel; a tap there would place right away)
		m.enter_sandbox()
		await _frames(3)
		m.zoom_arg = 9.0   # closer than the garden allows (like --zoom=): the island reaches past the panel
		m.zoom_target = 9.0
		m.cam.size = 9.0
		await _settle()
		u.close_popups()
		var n_items: int = m.items.size()
		u.open_sheet("drawer")
		await _frames(2)
		var panel: Rect2 = _sheet_panel(u.drawer).get_global_rect().grow(4.0)
		var cp := Vector2(-1, -1)
		var keys: Array = m.terrain.heights.keys()
		keys.sort()
		for c in keys:
			if not panel.has_point(_screen(c)):
				cp = _screen(c)   # a cell visible beside the panel: the tap is on the dim, over the island
				break
		check(cp.x >= 0.0, "%s: no cell beside the \"≡\" panel to tap" % tag)
		_gui_tap(cp, touch_first)
		await _frames(2)
		check(not u.drawer.visible and m.items.size() == n_items, "%s: a tap on the dim didn't close \"≡\" or acted on a cell" % tag)
		m.zoom_arg = 0.0
		m.fit_key = []
		m.start_level(0)
		await _settle()
	# a grep: only sheets.gd writes a sheet's visibility
	var re := RegEx.create_from_string("\\b(settings|about|confirm|picker|result|drawer|memo)\\.visible\\s*=[^=]")
	for f in ["res://scripts/ui.gd", "res://scripts/ui_phone.gd", "res://scripts/main.gd"]:
		var hits := re.search_all(FileAccess.get_file_as_string(f))
		check(hits.is_empty(), "%s writes a sheet's visibility outside sheets.gd: %s" % [f, hits[0].get_string() if hits.size() > 0 else ""])


## Bug 2: the island's center is drawn at the free area's center — with the card open or collapsed, with a sheet open,
## at the closest and the farthest zoom, at several yaws.
func _test_framing() -> void:
	for slot in [1, 38, 97]:
		m.start_level(slot - 1)
		await _frames(3)
		for z in [m.zoom_min, m.zoom_max]:
			for yaw in [0.0, 37.0, 45.0]:
				m.yaw_target = deg_to_rad(yaw)
				m.zoom_target = z
				m.cam.size = z
				await _settle()
				var want: Vector2 = m.ui.free_rect().get_center()
				var at: Vector2 = m.cam.unproject_position(m.pivot.global_position)
				check(at.distance_to(want) < 1.0, "level %d zoom %.1f yaw %.0f: the island at %s, the free center %s" % [slot, z, yaw, at, want])
				m.toggle_card()
				await _frames(2)
				var at2: Vector2 = m.cam.unproject_position(m.pivot.global_position)
				check(at2.distance_to(at) < 1.0, "level %d: collapsing the card moved the island %s -> %s (bug 2)" % [slot, at, at2])
				m.toggle_card()
				m.ui.open_sheet("help")
				await _frames(2)
				check(m.cam.unproject_position(m.pivot.global_position).distance_to(at) < 1.0, "level %d: a sheet moved the island" % slot)
				m.ui.close_popups()
		# the closest zoom keeps every cell inside the free area at any yaw
		m.zoom_target = m.zoom_min
		m.cam.size = m.zoom_min
		var fr: Rect2 = m.ui.free_rect().grow(1.0)
		var out := 0
		for yaw in range(0, 360, 15):
			m.yaw_target = deg_to_rad(yaw)
			await _settle()
			for c in m.terrain.heights:
				if not fr.has_point(_screen(c)):
					out += 1
		check(out == 0, "level %d: %d cell positions outside the free area at the closest zoom" % [slot, out])


## D6: the result comes a moment after the last placement; meanwhile the world and undo take no input.
func _test_result_wait() -> void:
	m.start_level(0)
	await _settle()
	m.result_delay = 0.5
	m.undo_stack.append({"c": Vector2i(0, 0), "s": m._cell_state(Vector2i(0, 0))})
	m._level_complete()
	check(not m.ui.result.visible and m.result_wait > 0.0, "the result opened at once, without the pause")
	var cell := _good_cells(1)
	if cell.size() > 0:
		_tap(_screen(cell[0]))
		check(m.aim_cell == NO_CELL, "a tap during the pause tried a cell")
	var n_undo: int = m.undo_stack.size()
	m.undo()
	check(m.undo_stack.size() == n_undo, "undo worked during the pause")
	await create_timer(0.7).timeout
	await _frames(2)
	check(m.ui.result.visible and m.result_wait < 0.0, "the result didn't open after the pause")
	m.ui.hide_result()
	m.result_delay = 0.0
	m.undo_stack.clear()


func _test_sandbox() -> void:
	m.enter_sandbox()
	await _frames(3)
	await _settle()
	check(m.coach.has("sandbox"), "no tip in the garden (shown once, on the first entry)")
	check(not m.ui.help.visible and m.ui.memo_btn.visible, "in the garden the rules card is visible or there is no \"?\"")
	m.ui.memo_btn.pressed.emit()
	check(m.ui.memo.visible and m.ui.memo_body.text == I18n.t("ui.help.sandbox_touch"), "\"?\" didn't show the gesture cheat sheet")
	m.go_back()
	check(not m.ui.memo.visible, "\"Back\" didn't close the cheat sheet")
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
	# a tap on the item with an item tool selects it silently; the trash removes it; undo returns it
	m.t += 0.5
	var n_undo: int = m.undo_stack.size()
	_tap(_screen(c))
	check(m.items.has(c) and m.aim_cell == c and m.undo_stack.size() == n_undo, "a tap on an item in the garden didn't just select it")
	m.ui.act_trash.pressed.emit()
	check(not m.items.has(c), "the trash in the garden didn't remove the item")
	m.undo()
	check(m.items.has(c), "undo didn't return the item removed by the trash")
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
	# the garden's closest zoom keeps the whole island in the free area
	m.zoom_target = m.zoom_min
	m.cam.size = m.zoom_min
	var fr: Rect2 = m.ui.free_rect().grow(1.0)
	var out := 0
	for yaw in range(0, 360, 30):
		m.yaw_target = deg_to_rad(yaw)
		await _settle()
		for cc in m.terrain.heights:
			if not fr.has_point(_screen(cc)):
				out += 1
	check(out == 0, "garden: %d cell positions outside the free area at the closest zoom" % out)
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
	check(m.ui.drawer.visible and m.mode == "level", "\"Back\" from a level didn't open \"≡\"")
	m.ui.menu_btn.pressed.emit()
	check(m.mode == "menu" and not m.ui.drawer.visible, "\"Menu\" in \"≡\" didn't go to the menu")
	m.go_back()
	check(m.back_armed > 0.0 and m.ui.toast_label.text == I18n.t("toast.back_exit"), "\"Back\" in the menu didn't warn about exiting")
	m.back_armed = 0.0
	m.save_timer = 0.4
	m.fingers[3] = {"start": Vector2.ZERO, "pos": Vector2.ZERO, "t0": 0.0, "ui": false, "moved": false, "long": false}
	m._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	check(m.save_timer < 0.0 and m.fingers.is_empty(), "the app pause didn't save or didn't reset the fingers")


## Phone layout: panels on screen, no overlaps; buttons at least 56 px.
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


func _near(a: float, b: float) -> bool:
	return absf(a - b) <= 1.0


## D5: one gap. Every game element keeps at least GAP from the screen edges; the corner elements sit exactly GAP from their
## edges; neighbors are exactly GAP apart (explicit pairs).
func _gaps(where: String) -> void:
	var u = m.ui
	var w: float = root.get_visible_rect().size.x
	var h: float = root.get_visible_rect().size.y
	for c in _game_panels(u):
		if c == null or not c.is_visible_in_tree():
			continue
		var r: Rect2 = c.get_global_rect()
		check(r.position.x >= GAP - 0.5 and r.end.x <= w - GAP + 0.5 and r.position.y >= GAP - 0.5 and r.end.y <= h - GAP + 0.5,
			"%s: %s closer than %d to an edge: %s" % [where, c.name, GAP, r])
	var tg: Rect2 = u.menu_toggle.get_global_rect()
	var mq: Rect2 = u.memo_btn.get_global_rect()
	var col: Rect2 = u.actions.get_global_rect()
	var dock: Rect2 = u.items_panel.get_global_rect()
	check(_near(tg.position.x, GAP) and _near(tg.position.y, GAP), "%s: \"≡\" not at the corner gap: %s" % [where, tg])
	check(_near(mq.end.x, w - GAP) and _near(mq.position.y, GAP), "%s: \"?\" not at the corner gap: %s" % [where, mq])
	check(_near(col.end.x, w - GAP) and _near(col.end.y, h - GAP), "%s: the action column not at the corner gap: %s" % [where, col])
	check(_near(dock.position.x, GAP) and _near(dock.end.y, h - GAP), "%s: the dock not at the corner gap: %s" % [where, dock])
	var right_of_dock: float = u.land_panel.get_global_rect().end.x if u.land_panel.is_visible_in_tree() else dock.end.x
	check(right_of_dock <= col.position.x - GAP + 0.5, "%s: the dock comes closer than the gap to the action column" % where)
	if u.land_panel.is_visible_in_tree():
		check(_near(u.land_panel.get_global_rect().position.x - dock.end.x, GAP), "%s: dock ↔ land group not one gap" % where)
	var kids: Array = u.actions.get_children()
	for i in kids.size() - 1:
		check(_near((kids[i + 1] as Control).get_global_rect().position.y - (kids[i] as Control).get_global_rect().end.y, GAP),
			"%s: the action buttons %d and %d are not one gap apart" % [where, i, i + 1])
	if u.help.is_visible_in_tree():
		check(_near(u.help.get_global_rect().position.y - tg.end.y, GAP) and _near(u.help.get_global_rect().position.x, GAP),
			"%s: the rules card is not one gap under \"≡\"" % where)
		check(u.help.get_global_rect().end.y <= dock.position.y - GAP + 0.5, "%s: the rules card comes closer than the gap to the dock" % where)
	if u.hud.is_visible_in_tree():
		check(_near(u.hud.get_global_rect().position.y, GAP), "%s: the top bar is not one gap from the top" % where)
	if u.name_chip.is_visible_in_tree():
		check(_near(dock.position.y - u.name_chip.get_global_rect().end.y, GAP), "%s: the name chip is not one gap above the dock" % where)


func _name_panels(u) -> void:
	for pair in [["items_panel", "dock"], ["land_panel", "land"], ["actions", "column"], ["hud", "bar"],
			["help", "card"], ["menu_toggle", "≡"], ["memo_btn", "?"], ["chip", "season"], ["name_chip", "name"]]:
		(u.get(pair[0]) as Control).name = pair[1]


func _game_panels(u) -> Array:
	return [u.items_panel, u.land_panel, u.actions, u.hud, u.help, u.menu_toggle, u.memo_btn, u.chip, u.name_chip]


func _sheet_panel(sheet: Control) -> Control:
	return sheet.get_child(0).get_child(0)


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
			await _check_layout(tag + " settings", [_sheet_panel(u.settings)])
			u.show_reset_confirm()
			await _check_layout(tag + " reset", [_sheet_panel(u.confirm)])
			u.sheets.close("confirm")
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
			_gaps(tag + " garden")
			m.toggle_cozy()
			await _check_layout(tag + " garden, coziness", _game_panels(u))
			m.toggle_cozy()
			u.toggle_drawer()
			await _check_layout(tag + " garden, \"≡\"", [_sheet_panel(u.drawer)])
			check(u.drawer.get_global_rect() == root.get_visible_rect() or u.drawer.size == root.get_visible_rect().size or u.drawer.get_global_rect().encloses(u.root.get_global_rect()),
				"%s garden: \"≡\" doesn't cover the screen" % tag)
			u.close_popups()
			u.toggle_help()
			await _check_layout(tag + " garden, \"?\"", [_sheet_panel(u.memo)])
			u.close_popups()
			for slot in [1, 38, 66, 79, 97]:
				m.start_level(slot - 1)
				await _settle()
				var free := _good_cells(1)
				if free.size() > 0:
					m._set_aim(free[0])
				await _check_layout("%s level %d" % [tag, slot], _game_panels(u))
				_gaps("%s level %d" % [tag, slot])
				u.toggle_help()
				await _check_layout("%s level %d, \"?\"" % [tag, slot], [_sheet_panel(u.memo)])
				u.close_popups()
				u.toggle_drawer()
				await _check_layout("%s level %d, \"≡\"" % [tag, slot], [_sheet_panel(u.drawer)])
				u.close_popups()
			u.show_result(3, 99, Levels.LEVELS[0], true, true)
			await _check_layout(tag + " result", [_sheet_panel(u.result)])
			u.hide_result()
	root.content_scale_size = Vector2i(1333, 600)
	# the rules card doesn't come closer than the gap to the dock on any level, for any hand item
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
			if gap < GAP - 0.5:
				check(false, "level %d, %s: the rules card comes closer than the gap to the dock (%.0f)" % [i + 1, id, gap])
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
	# on a phone no level hint, cheat sheet, tip or result talks about keys or the mouse
	var keys := RegEx.create_from_string("\\b(Tab|Esc|Shift|Ctrl|WASD|F\\d+)\\b|ЛКМ|ПКМ|СКМ|[Rr]ight.click|[Ll]eft.click|колес|wheel")
	check(keys.search(I18n.t("level.four_times.hint")) != null and keys.search("ПКМ возвращает") != null, "the key check catches nothing")
	for lang in ["ru", "en"]:
		m.set_language(lang)
		await _frames(1)
		for k in ["ui.help.level_touch", "ui.help.sandbox_touch", "coach.aim", "coach.place", "coach.sandbox", "toast.trash_pick"]:
			check(keys.search(I18n.t(k)) == null, "%s %s talks about keys: %s" % [lang, k, I18n.t(k)])
		for i in Levels.LEVELS.size():
			m.start_level(i)
			var hint: String = m.ui.hud_hint.text
			check(keys.search(hint) == null, "%s level %d: a phone hint about keys: %s" % [lang, i + 1, hint])
		m.ui.show_result(0, 10, Levels.LEVELS[0], false, true)
		check(keys.search(m.ui.res_text.text) == null, "%s result without a star mentions the mouse: %s" % [lang, m.ui.res_text.text])
		m.ui.hide_result()
	m.set_language("ru")
