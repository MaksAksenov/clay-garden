extends "res://scripts/ui.gd"
## Stage 10, R10: the phone layout (touch mode). A separate subclass — the desktop layout (ui.gd) is unchanged.
## Rationale — docs/defense/step10-touch.md (the designer agent's mockups and the defense result).
## The world in the center; thin elements at the edges: "≡" (rare things) at the top left, the level / garden season bar at the top center,
## "?" (gesture cheat sheet) at the top right, the rules card on the left (level); at the bottom — the dock (items | land) and the action
## cluster under the right thumb. Margins: 48 on the sides (the camera hole in landscape), 20 at the top, 24 at the bottom.

const SIDE := 48.0
const TOP := 20.0
const BOTTOM := 24.0
const TILE := 76
const ACT := 64
const CLUSTER_W := 216.0   # room for the cluster: rotate item + rotate island + undo ("Place" is above it)
const CARD_W := 300.0

var menu_toggle: Button        # «≡»
var memo_btn: Button           # «?»
var memo: PanelContainer       # gesture cheat sheet
var memo_body: Label
var catcher: Control           # a tap outside an open "≡" / "?" closes them (and doesn't reach the world)
var drawer_title: Label
var chip: Button               # garden: "Summer · Morning 08:41 [· coziness 42]" — a tap changes the season
var chip_season := "summer"
var chip_can := false
var chip_clock := ""
var chip_cozy := -1
var name_chip: Label           # garden: the selected item's name above the dock
var items_panel: PanelContainer
var land_panel: PanelContainer
var act_rot_island: Button
var act_main: Button           # "Place" / "Back to hand" / "Remove" while trying — instead of a bubble above the cell
var card_head: Button          # the rules card header: the item's name; a tap collapses / expands
var card_more: VBoxContainer
var card_scroll: ScrollContainer   # long rules (winter, All Year Round) — scroll with a finger, the card doesn't overlap the dock
const HUD_SHIFT := 122.0           # level: the bar centered in the space between the rules card and "?", not on the screen
var badges := {}               # id -> the "×N" badge on a tile
var restart_armed := 0.0


func setup(m) -> void:
	super.setup(m)
	# the "≡" and "?" pop-ups and the touch catcher under them — above the game panels; the toast — above everything
	for n in [catcher, corner, memo, toast_label]:
		root.move_child(n, -1)


# ================================================================ building

func _dock_box() -> StyleBoxFlat:
	var sb := _box(Color(1.0, 0.975, 0.93, 0.92), Color("ead9bb"))
	sb.set_corner_radius_all(20)
	sb.set_content_margin_all(8)
	return sb


## Bottom: one row — the item dock (scrolls), the permanent land group (garden), the action cluster on the right.
func _build_bar() -> void:
	bar = PanelContainer.new()
	bar.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_left = SIDE
	bar.offset_right = -SIDE
	bar.offset_bottom = -BOTTOM
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bar)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(line)
	items_panel = PanelContainer.new()
	items_panel.add_theme_stylebox_override("panel", _dock_box())
	line.add_child(items_panel)
	bar_scroll = ScrollContainer.new()
	bar_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	bar_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	bar_scroll.scroll_deadzone = 20
	items_panel.add_child(bar_scroll)
	bar_row = HBoxContainer.new()
	bar_row.add_theme_constant_override("separation", 8)
	bar_scroll.add_child(bar_row)
	land_panel = PanelContainer.new()
	land_panel.add_theme_stylebox_override("panel", _dock_box())
	line.add_child(land_panel)
	var land_row := HBoxContainer.new()
	land_row.add_theme_constant_override("separation", 8)
	land_panel.add_child(land_row)
	var n := 0
	for d in Items.CATALOG:
		n += 1
		bar_row.add_child(_tool_button(d["id"], I18n.t("item." + d["id"]), _item_thumb(d["id"]), n))
	tools_sep = VSeparator.new()
	tools_sep.visible = false
	land_row.add_child(tools_sep)
	for d in TOOL_INFO:
		n += 1
		land_row.add_child(_tool_button(d["id"], I18n.t("tool." + d["id"]), _tool_thumb(d["id"]), n))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(gap)
	actions = HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 8)
	actions.size_flags_vertical = Control.SIZE_SHRINK_END
	line.add_child(actions)
	act_main = _small_button("", func():
		if bubble_kind == "ok":
			main.confirm_aim()
		elif bubble_kind == "back":
			main.take_back_aim())
	act_main.custom_minimum_size = Vector2(200, ACT)
	act_main.add_theme_font_size_override("font_size", 18)
	act_main.add_theme_constant_override("icon_max_width", 24)
	act_main.visible = false
	# above the cluster, at the right edge — under the thumb, doesn't narrow the dock
	act_main.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	act_main.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	act_main.grow_vertical = Control.GROW_DIRECTION_BEGIN
	act_main.offset_right = -SIDE
	act_main.offset_bottom = -(BOTTOM + ACT + 10)
	root.add_child(act_main)
	bubble = act_main
	act_rot_item = _round(icon("rot_item"), I18n.t("ui.act.rot_item"), func(): main.rotate_item())
	actions.add_child(act_rot_item)
	act_rot_island = _round(icon("rot_right"), I18n.t("ui.act.rot_right"), func(): main.rotate_island(1))
	actions.add_child(act_rot_island)
	act_undo = _round(icon("undo"), I18n.t("ui.act.undo"), func(): main.undo())
	actions.add_child(act_undo)
	# the selected item's name (garden) — a chip above the dock
	name_chip = Label.new()
	var cs := _box(Color("fff7ea"), Color("ead9bb"))
	cs.set_corner_radius_all(16)
	cs.content_margin_left = 16
	cs.content_margin_right = 16
	name_chip.add_theme_stylebox_override("normal", cs)
	name_chip.add_theme_font_size_override("font_size", 17)
	name_chip.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	name_chip.grow_vertical = Control.GROW_DIRECTION_BEGIN
	name_chip.offset_left = SIDE
	name_chip.offset_bottom = -(BOTTOM + TILE + 16 + 10)
	name_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(name_chip)


func _round(tex: Texture2D, tip: String, cb: Callable) -> Button:
	var b := _icon_button(tex, tip, cb)
	b.custom_minimum_size = Vector2(ACT, ACT)
	b.add_theme_constant_override("icon_max_width", 32)
	return b


## A dock tile: only the 3D thumbnail (the name is in the chip or the card header), on a level — the "×N" badge.
func _tool_button(id: String, label: String, tex: Texture2D, n: int) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.button_group = group
	b.icon = tex
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.custom_minimum_size = Vector2(TILE, TILE)
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_PASS   # dragging over a tile reaches the dock's scroll
	b.pressed.connect(func(): main.set_tool(id))
	var badge := Label.new()
	var bs := StyleBoxFlat.new()
	bs.bg_color = INK
	bs.set_corner_radius_all(8)
	bs.content_margin_left = 6
	bs.content_margin_right = 6
	badge.add_theme_stylebox_override("normal", bs)
	badge.add_theme_color_override("font_color", Color("fff7ea"))
	badge.add_theme_font_size_override("font_size", 16)
	badge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	badge.grow_vertical = Control.GROW_DIRECTION_BEGIN
	badge.offset_right = -3
	badge.offset_bottom = -3
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.visible = false
	b.add_child(badge)
	badges[id] = badge
	buttons[id] = b
	names[id] = label
	return b


## The rules card (level): a header button with the item's name, the level hint, the rules. On the left, not over the island.
func _build_help() -> void:
	help = PanelContainer.new()
	help.position = Vector2(SIDE, TOP + 72)
	help.custom_minimum_size.x = CARD_W
	root.add_child(help)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	help.add_child(v)
	card_head = _small_button("", func(): main.toggle_card())
	card_head.alignment = HORIZONTAL_ALIGNMENT_LEFT
	card_head.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	card_head.add_theme_font_size_override("font_size", 22)
	card_head.add_theme_constant_override("icon_max_width", 22)
	card_head.custom_minimum_size = Vector2(CARD_W - 28, 56)
	# Left and right padding equal to top and bottom (≈ 14 px at a height of 56 and font 22), not 6 from the generic button.
	# The rounding is concentric with the card: the header is inset by the panel's padding, radius = panel radius − padding (22 − 14 = 8),
	# the arc centers coincide. Styles come from the game theme (the button isn't in the tree yet: get_theme_stylebox would give Godot's style).
	var panel_sb: StyleBoxFlat = root.theme.get_stylebox("panel", "PanelContainer")
	var inset := int(panel_sb.content_margin_left)
	var r := maxi(panel_sb.corner_radius_top_left - inset, 0)
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var sb: StyleBoxFlat = root.theme.get_stylebox(st, "Button").duplicate()
		sb.content_margin_left = 14
		sb.content_margin_right = 14
		sb.set_corner_radius_all(r)
		card_head.add_theme_stylebox_override(st, sb)
	v.add_child(card_head)
	help_title = Label.new()   # the base layout writes the title here; on a phone the title is in the header
	help_title.visible = false
	v.add_child(help_title)
	card_scroll = ScrollContainer.new()
	card_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	card_scroll.scroll_deadzone = 12
	v.add_child(card_scroll)
	card_more = VBoxContainer.new()
	card_more.add_theme_constant_override("separation", 6)
	card_more.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_scroll.add_child(card_more)
	hud_hint = Label.new()   # the level hint lives in the card, not in the top bar
	hud_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hud_hint.custom_minimum_size.x = CARD_W - 28
	hud_hint.add_theme_font_size_override("font_size", 15)
	hud_hint.modulate = Color(1, 1, 1, 0.72)
	card_more.add_child(hud_hint)
	card_more.add_child(HSeparator.new())
	help_body = Label.new()
	help_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help_body.custom_minimum_size.x = CARD_W - 28
	help_body.add_theme_font_size_override("font_size", 16)
	card_more.add_child(help_body)


## "≡" and the drawer of rare things; "?" and the cheat sheet; the garden season bar. No corner panel on a phone.
func _build_corner() -> void:
	catcher = Control.new()
	catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	catcher.visible = false
	catcher.gui_input.connect(func(e):
		if (e is InputEventMouseButton and e.pressed) or (e is InputEventScreenTouch and e.pressed):
			close_popups())
	root.add_child(catcher)
	menu_toggle = _icon_button(icon("menu"), I18n.t("ui.corner.menu"), func(): toggle_drawer())
	menu_toggle.custom_minimum_size = Vector2(56, 56)
	menu_toggle.position = Vector2(SIDE, TOP)
	root.add_child(menu_toggle)
	memo_btn = _small_button("?", func(): toggle_help())
	memo_btn.custom_minimum_size = Vector2(56, 56)
	memo_btn.add_theme_font_size_override("font_size", 26)
	memo_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	memo_btn.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	memo_btn.offset_right = -SIDE
	memo_btn.offset_left = -SIDE - 56
	memo_btn.offset_top = TOP
	root.add_child(memo_btn)
	help_btn = memo_btn
	chip = _small_button("", func():
		if chip_can:
			main.cycle_garden_season()
		else:
			toast(I18n.t("ui.corner.season_locked"), 3.0))
	chip.custom_minimum_size = Vector2(300, 56)
	chip.add_theme_font_size_override("font_size", 18)
	chip.set_anchors_preset(Control.PRESET_CENTER_TOP)
	chip.grow_horizontal = Control.GROW_DIRECTION_BOTH
	chip.offset_top = TOP
	root.add_child(chip)
	season_btn = chip
	# the "≡" drawer
	corner = PanelContainer.new()
	corner.position = Vector2(SIDE, TOP + 56 + 10)
	corner.visible = false
	root.add_child(corner)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 8)
	corner.add_child(cv)
	var head := HBoxContainer.new()
	cv.add_child(head)
	drawer_title = Label.new()
	drawer_title.add_theme_font_size_override("font_size", 20)
	drawer_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(drawer_title)
	clock = Label.new()
	clock.add_theme_font_size_override("font_size", 15)
	clock.modulate = Color(1, 1, 1, 0.7)
	head.add_child(clock)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	cv.add_child(grid)
	fast_btn = _drawer_button(I18n.t("ui.corner.time", {"k": 1}), func(): main.toggle_fast())
	grid.add_child(fast_btn)
	new_btn = _drawer_button(I18n.t("ui.corner.new_island"), _on_new)
	grid.add_child(new_btn)
	restart_btn = _drawer_button(I18n.t("ui.corner.restart"), _on_restart)
	grid.add_child(restart_btn)
	cozy_btn = _drawer_button(I18n.t("ui.corner.cozy_off"), func(): main.toggle_cozy())
	grid.add_child(cozy_btn)
	settings_btn = _drawer_button(I18n.t("ui.settings"), func():
		close_popups()
		show_settings())
	settings_btn.icon = icon("gear")
	settings_btn.add_theme_constant_override("icon_max_width", 20)
	grid.add_child(settings_btn)
	menu_btn = _drawer_button(I18n.t("ui.corner.menu"), func():
		close_popups()
		main.open_menu())
	grid.add_child(menu_btn)
	sound_btn = _drawer_button(I18n.t("ui.corner.sound_on"), func(): main.toggle_sound())
	sound_btn.visible = false   # on a phone the sound is in the settings
	grid.add_child(sound_btn)
	cozy_label = Label.new()    # on a phone the garden's coziness is in the season bar
	cozy_label.visible = false
	cv.add_child(cozy_label)
	# the "?" cheat sheet
	memo = PanelContainer.new()
	memo.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	memo.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	memo.offset_right = -SIDE
	memo.offset_top = TOP + 56 + 10
	memo.visible = false
	root.add_child(memo)
	memo_body = Label.new()
	memo_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	memo_body.custom_minimum_size.x = 280   # narrower: don't overlap the All Year Round bar
	memo_body.add_theme_font_size_override("font_size", 16)
	memo.add_child(memo_body)


func _drawer_button(text: String, cb: Callable) -> Button:
	var b := _small_button(text, cb)
	b.custom_minimum_size = Vector2(170, 56)
	return b


## The level's top bar: "Level 38 · Beehive", below it coziness and stars with thresholds; All Year Round — the season row.
func _build_hud() -> void:
	hud = PanelContainer.new()
	hud.set_anchors_preset(Control.PRESET_CENTER_TOP)
	hud.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hud.offset_top = TOP
	hud.offset_left = HUD_SHIFT
	hud.offset_right = HUD_SHIFT
	hud.custom_minimum_size.x = 520
	root.add_child(hud)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	hud.add_child(v)
	hud_title = Label.new()
	hud_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_title.add_theme_font_size_override("font_size", 20)
	hud_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(hud_title)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	v.add_child(row)
	hud_score = Label.new()
	hud_score.add_theme_font_size_override("font_size", 20)
	row.add_child(hud_score)
	hud_stars = StarRow.new()
	hud_stars.star_size = 20.0
	hud_stars.pitch = 36.0   # All Year Round thresholds have three digits (133 178 204)
	row.add_child(hud_stars)
	hud_year = HBoxContainer.new()
	hud_year.alignment = BoxContainer.ALIGNMENT_CENTER
	hud_year.add_theme_constant_override("separation", 6)
	hud_year.visible = false
	v.add_child(hud_year)
	for s in YEAR_ORDER:
		var b := Button.new()
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(124, 56)
		b.add_theme_font_size_override("font_size", 16)
		b.pressed.connect(func(): main.set_year_view(s))
		hud_year.add_child(b)
		year_btns[s] = b


## Touch: only the long-press ring (the action cluster is in the dock, no bubble above the cell).
func _build_touch() -> void:
	ring = PressRing.new()
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.visible = false
	root.add_child(ring)


## The level result is on the left (over the rules card: it's no longer needed), the dim is light: the island on a level is shifted
## to the right, and the garden just built stays visible.
func _build_result() -> void:
	super._build_result()
	(result as ColorRect).color = Color(0.25, 0.2, 0.15, 0.12)
	var center: Control = result.get_child(0)
	center.anchor_right = 0.5
	center.offset_left = SIDE
	var sb := _box(Color("fffaf2"), Color("ead9bb"))
	sb.set_corner_radius_all(22)
	sb.set_content_margin_all(20)
	(center.get_child(0) as PanelContainer).add_theme_stylebox_override("panel", sb)


func show_result(stars: int, score: int, L: Dictionary, record: bool, has_next: bool, note := "") -> void:
	super.show_result(stars, score, L, record, has_next, note)
	help.visible = false   # the result takes the rules card's place
	act_main.visible = false


func hide_result() -> void:
	super.hide_result()
	help.visible = mode == "level"


## Settings in two columns: sound and vibration on the left, language on the right (they don't fit one column on a phone's height).
func _build_settings() -> void:
	settings = _dim()
	settings.visible = false
	settings.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			close_settings())
	root.add_child(settings)
	var v := _center_panel(settings)
	v.get_parent().get_parent().mouse_filter = Control.MOUSE_FILTER_IGNORE
	_solid(settings, v)
	v.add_theme_constant_override("separation", 10)
	var title := Label.new()
	title.text = I18n.t("ui.settings")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	v.add_child(title)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 24)
	v.add_child(cols)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	left.custom_minimum_size.x = 470
	cols.add_child(left)
	cols.add_child(VSeparator.new())
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	right.custom_minimum_size.x = 420
	cols.add_child(right)
	left.add_child(_section(I18n.t("ui.settings.sound")))
	for bus in BUSES:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		left.add_child(row)
		var lbl := Label.new()
		lbl.text = I18n.t("ui.settings." + bus)
		lbl.custom_minimum_size.x = 160
		lbl.add_theme_font_size_override("font_size", 17)
		row.add_child(lbl)
		var sl := HSlider.new()
		sl.min_value = 0.0
		sl.max_value = 1.0
		sl.step = 0.05
		sl.custom_minimum_size = Vector2(220, BTN_H)
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sl.focus_mode = Control.FOCUS_NONE
		sl.value = float(main.vol.get(bus, 0.8))
		row.add_child(sl)
		var pct := Label.new()
		pct.custom_minimum_size.x = 56
		pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		pct.add_theme_font_size_override("font_size", 17)
		pct.text = _pct(sl.value)
		row.add_child(pct)
		sliders[bus] = sl
		slider_pct[bus] = pct
		sl.value_changed.connect(func(x: float):
			main.set_volume(bus, x)
			pct.text = _pct(x)
			if bus != "music":
				_tick_sound())
	vibrate_btn = _small_button("", func(): main.set_vibrate(not main.vibrate_on); _sync_vibrate())
	vibrate_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	vibrate_btn.custom_minimum_size.x = 240
	left.add_child(vibrate_btn)
	_sync_vibrate()
	right.add_child(_section(I18n.t("ui.settings.language")))
	right.add_child(_carousel())
	right.add_child(_flag_row())
	# About — a quiet button under the flags, away from "Reset progress…" (stage 12 defense)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(spacer)
	about_btn = _small_button(I18n.t("ui.settings.about"), func(): show_about())
	about_btn.modulate = Color(1, 1, 1, 0.8)
	about_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	about_btn.custom_minimum_size.x = 180
	right.add_child(about_btn)
	v.add_child(HSeparator.new())
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	v.add_child(bottom)
	var reset := _small_button(I18n.t("ui.settings.reset"), func(): show_reset_confirm())
	reset.modulate = Color(1, 1, 1, 0.8)
	reset.custom_minimum_size.x = 240
	bottom.add_child(reset)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(gap)
	var done := _small_button(I18n.t("ui.settings.done"), func(): close_settings())
	done.custom_minimum_size.x = 180
	bottom.add_child(done)


## Camera cutout: the base 48 px on the sides are already there — add only what goes beyond them.
func _apply_safe_area() -> void:
	var sa := DisplayServer.get_display_safe_area()
	var scr := DisplayServer.screen_get_size()
	if sa.size.x <= 0 or scr.x <= 0:
		return
	var k := root.get_viewport_rect().size.x / float(get_window().size.x)
	root.offset_left = maxf(0.0, sa.position.x * k - SIDE)
	root.offset_right = -maxf(0.0, (scr.x - sa.end.x) * k - SIDE)
	root.offset_top = maxf(0.0, sa.position.y * k - TOP)
	root.offset_bottom = -maxf(0.0, (scr.y - sa.end.y) * k - BOTTOM)


# ================================================================ modes

func show_menu(progress: Dictionary) -> void:
	super.show_menu(progress)
	close_popups()
	for c in [menu_toggle, memo_btn, chip, name_chip, act_main]:
		c.visible = false


func enter_sandbox_ui() -> void:
	mode = "sandbox"
	close_popups()
	menu.visible = false
	result.visible = false
	hud.visible = false
	help.visible = false
	bar.visible = true
	land_panel.visible = true
	for c in [menu_toggle, memo_btn, chip, name_chip]:
		c.visible = true
	drawer_title.text = I18n.t("ui.drawer.garden")
	new_btn.visible = true
	cozy_btn.visible = true
	restart_btn.visible = false
	memo_body.text = I18n.t("ui.help.sandbox_touch")
	toast_label.offset_top = TOP + 56 + 12
	for id in buttons:
		buttons[id].visible = id in BASE_ITEMS or Items.info(id).is_empty() or Progress.seen(main.progress, id)
		buttons[id].disabled = false
		badges[id].visible = false
	_fit_bar()
	_sync_actions()


func enter_level_ui(idx: int, L: Dictionary, hand: Dictionary) -> void:
	mode = "level"
	close_popups()
	menu.visible = false
	result.visible = false
	hud.visible = true
	help.visible = true
	bar.visible = true
	land_panel.visible = false
	menu_toggle.visible = true
	memo_btn.visible = true
	chip.visible = false
	name_chip.visible = false
	drawer_title.text = I18n.t("ui.drawer.level")
	new_btn.visible = false
	cozy_btn.visible = false
	restart_btn.visible = true
	restart_btn.text = I18n.t("ui.corner.restart")
	restart_armed = 0.0
	memo_body.text = I18n.t("ui.help.level_touch")
	hud_year.visible = Campaign.is_year(L)
	toast_label.offset_top = 184 if hud_year.visible else 120
	hud_title.text = I18n.t("ui.hud.title", {"slot": int(L["slot"]), "name": I18n.level_name(L["id"])})
	hud_hint.text = I18n.level_hint(L["id"], true)
	hud_stars.thresholds = L["stars"]
	for id in buttons:
		buttons[id].visible = hand.has(id)
		badges[id].visible = false
	update_hand(hand)
	_sync_card()
	_fit_bar()
	_sync_actions()


func update_hand(hand: Dictionary) -> void:
	for id in hand:
		var n: int = hand[id]
		badges[id].text = "×%d" % n
		badges[id].visible = true
		buttons[id].disabled = n <= 0


func show_rules(id: String) -> void:
	if mode != "level":
		return
	card_head.text = names.get(id, id)
	help_body.text = I18n.t("ui.help.card_rules", {"base": Scoring.BASE, "rules": Scoring.describe(id, main.known_items(), main.level_drought(), main.level_flags(), main.level_snow())})
	_sync_card()


## The rules card is collapsed / expanded (the state is in main — survives a language change).
func _sync_card() -> void:
	var open: bool = not main.card_collapsed
	card_scroll.visible = open
	card_head.icon = icon("up") if open else icon("down")
	card_scroll.custom_minimum_size.y = 0
	_fit_card.call_deferred()


## The card's height: by the text, but no lower than the top of the dock (then — scrolling). Line wrapping is known after layout.
func _fit_card() -> void:
	if not is_instance_valid(card_scroll) or not card_scroll.visible:
		return
	var need := card_more.get_combined_minimum_size().y
	var dock_top := root.get_global_rect().end.y - BOTTOM - TILE - 16
	var room := dock_top - 12.0 - card_scroll.get_global_rect().position.y - 14.0
	card_scroll.custom_minimum_size.y = clampf(need, 0.0, maxf(room, 60.0))


func _sync_actions() -> void:
	if actions == null:
		return
	actions.visible = mode != "menu"
	act_rot_item.visible = Items.info(String(main.tool)).get("rotatable", false)
	if name_chip:
		name_chip.text = names.get(String(main.tool), "")


## The action button while trying — in the cluster under the thumb (not a bubble above the cell: it covered the neighbors).
func set_bubble(pos: Vector2, kind: String, below: Vector2 = Vector2(-1, -1)) -> void:
	if act_main == null:
		return
	if kind == "":
		act_main.visible = false
		bubble_kind = ""
		return
	if kind != bubble_kind:
		if kind == "ok":
			act_main.text = I18n.t("ui.act.place")
			act_main.icon = icon("check")
		else:
			act_main.text = I18n.t("ui.act.back_level") if mode == "level" else I18n.t("ui.act.back_garden")
			act_main.icon = icon("back")
	bubble_kind = kind
	act_main.visible = true


## The item dock's width: by content, but no wider than the space between the left edge, the land group and the cluster.
func _fit_bar() -> void:
	if bar_scroll == null:
		return
	var n := 0
	for ch in bar_row.get_children():
		if (ch as Control).visible:
			n += 1
	var w: float = n * TILE + maxf(0, n - 1) * 8.0
	var land_w: float = float(4 * TILE + 3 * 8 + 16 + 12) if land_panel.visible else 0.0
	var avail: float = root.get_global_rect().size.x - 2 * SIDE - CLUSTER_W - land_w - 12 - 16
	bar_scroll.custom_minimum_size = Vector2(minf(w, avail), TILE)


func is_over_ui(p: Vector2) -> bool:
	if menu.visible or result.visible or picker.visible or settings.visible or confirm.visible or catcher.visible:
		return true
	for c in [items_panel, land_panel, actions, act_main, hud, help, menu_toggle, memo_btn, chip, corner, memo]:
		if c and c.is_visible_in_tree() and c.get_global_rect().has_point(p):
			return true
	return false


# ================================================================ "≡", "?", the season bar

func toggle_drawer() -> void:
	var open := not corner.visible
	close_popups()
	corner.visible = open
	catcher.visible = open
	if open:
		toast_t = minf(toast_t, 0.3)   # a tip banner doesn't go over the drawer


func toggle_help() -> void:
	if mode == "menu":
		return
	var open := not memo.visible
	close_popups()
	# on a level the cheat sheet is under the bar (with the All Year Round row the bar is wider and lower)
	memo.offset_top = (hud.get_global_rect().end.y + 10.0) if hud.visible else TOP + 56 + 10
	memo.visible = open
	catcher.visible = open


func close_popups() -> void:
	if corner == null:
		return
	corner.visible = false
	memo.visible = false
	catcher.visible = false


## "Back" and Esc close "≡" / "?" too.
func close_top() -> bool:
	if super.close_top():
		return true
	if corner.visible or memo.visible:
		close_popups()
		return true
	return false


func set_clock(day_time: float) -> void:
	super.set_clock(day_time)
	if clock.text != chip_clock:
		chip_clock = clock.text
		_sync_chip()


func set_garden_season(s: String, can_change: bool) -> void:
	chip_season = s
	chip_can = can_change
	_sync_chip()


func set_garden_score(on: bool, v: int, s: String) -> void:
	cozy_btn.text = I18n.t("ui.corner.cozy_on") if on else I18n.t("ui.corner.cozy_off")
	chip_cozy = v if on else -1
	chip_season = s
	_sync_chip()


func _sync_chip() -> void:
	var args := {"season": I18n.t("season." + chip_season), "time": chip_clock.replace("  ", " "), "n": chip_cozy}
	chip.text = I18n.t("ui.chip_cozy", args) if chip_cozy >= 0 else I18n.t("ui.chip", args)


## "Restart" on a phone — by a double press, like "New island" (a finger might have touched it by accident).
func _on_restart() -> void:
	if restart_armed > 0.0:
		restart_armed = 0.0
		restart_btn.text = I18n.t("ui.corner.restart")
		close_popups()
		main.restart_level()
	else:
		restart_armed = 3.0
		restart_btn.text = I18n.t("ui.corner.new_confirm")


func _process(dt: float) -> void:
	super._process(dt)
	if mode == "level" and card_scroll.visible:
		_fit_card()   # line wrapping changes after layout (a change of item, language, width)
	if restart_armed > 0.0:
		restart_armed -= dt
		if restart_armed <= 0.0:
			restart_btn.text = I18n.t("ui.corner.restart")
