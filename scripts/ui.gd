extends CanvasLayer
## Interface: the palette with live 3D thumbnails, the level menu, the coziness bar, the result.

const C := preload("res://scripts/clay.gd")
const Items := preload("res://scripts/items.gd")
const Scoring := preload("res://scripts/scoring.gd")
const Levels := preload("res://scripts/levels.gd")
const Progress := preload("res://scripts/progress.gd")
const Campaign := preload("res://scripts/campaign.gd")
const I18n := preload("res://scripts/i18n.gd")
const BASE_ITEMS := ["tree", "pine", "bush", "flowers", "mushroom", "rock", "pumpkin", "fence", "bench", "lantern", "lily"]

const TOOL_INFO := [{"id": "raise"}, {"id": "lower"}, {"id": "water"}, {"id": "remove"}]   # captions — tool.<id>
const INK := Color("5b4636")

var main
var buttons: Dictionary = {}
var names: Dictionary = {}
var group := ButtonGroup.new()
var root: Control
var bar: PanelContainer
var tools_sep: VSeparator
var corner: PanelContainer
var help: PanelContainer
var help_title: Label
var help_body: Label
var clock: Label
var toast_label: Label
var toast_t := 0.0
var fast_btn: Button
var sound_btn: Button
var new_btn: Button
var menu_btn: Button
var restart_btn: Button
var new_armed := 0.0
var thumbs: Array[SubViewport] = []
var thumb_frames := 0

var hud: PanelContainer
var hud_title: Label
var hud_hint: Label
var season_btn: Button              # free garden: "Season: Summer" (cycles, key Y)
var cozy_btn: Button                # free garden: coziness counter on/off
var cozy_label: Label
var hud_year: HBoxContainer          # All Year Round: coziness per season; a press shows the island in that season
var year_btns := {}
const YEAR_ORDER := ["spring", "summer", "autumn", "winter"]
var hud_score: Label
var hud_stars: StarRow

var menu: Control
var menu_grid: VBoxContainer   # chapter rows of the selected season
var menu_tabs: HBoxContainer
var menu_total: Label
var menu_season := ""          # the selected season tab
var menu_progress: Dictionary = {}
var picker: Control            # first start: language choice

# stage 9: settings
const BUSES := ["master", "music", "effects"]
const HOLD_TIME := 3.0         # hold the reset button, seconds
const HOLD_DRAIN := 0.4        # released early — the bar drains in this time
const TERRACOTTA := Color("d9825b")
var gear_btn: Button           # the gear in the menu
var settings_btn: Button       # "Settings" in the corner panel (garden, level)
var settings: Control
var sliders := {}              # bus -> HSlider
var slider_pct := {}           # bus -> the "80%" caption
var confirm: Control           # the reset confirmation window
var lang_prev: Button
var lang_next: Button
var flag_btns := {}            # code -> the flag under the carousel
var hold_btn: Button
var hold_fill: Panel
var hold_t := 0.0

# stage 12: About — a child node of the settings (closing the settings closes it too)
## Android template libraries missing from Engine.get_copyright_info (class definitions and native libraries of a
## Godot 4.7.2 APK). tools/check_notices.py checks this list against a built APK — rerun it after any template change.
const ANDROID_LIBS := [
	["AndroidX (Jetpack) libraries", "The Android Open Source Project", "Apache-2.0"],
	["Kotlin Standard Library, kotlinx.coroutines", "JetBrains s.r.o. and Kotlin Programming Language contributors", "Apache-2.0"],
	["Guava: ListenableFuture", "The Guava Authors", "Apache-2.0"],
	["JSpecify annotations", "The JSpecify Authors", "Apache-2.0"],
	["JetBrains Java Annotations", "JetBrains s.r.o.", "Apache-2.0"],
	["LLVM libc++ (Android NDK C++ runtime)", "The LLVM Project contributors", "Apache-2.0 with LLVM Exceptions"],
]
## libc++'s own LICENSE.TXT (LLVM exceptions and its legacy UIUC / MIT notices), unchanged, from the NDK toolchain
## revision the APK's libc++_shared.so was built from (android.googlesource.com/toolchain/llvm-project 5e96669f).
const LIBCXX_LICENSE := "res://legal/libcxx-LICENSE.txt"
## Where to get the source form of MPL-2.0 components (MPL 3.2): "%s" — the Godot release tag.
const SOURCE_LINKS := {
	"CA certificates": "https://github.com/godotengine/godot/blob/%s/thirdparty/certs/ca-bundle.crt",
}
var about: Control
var about_panel: PanelContainer
var about_scroll: ScrollContainer
var about_box: VBoxContainer
var about_more: Button
var about_btn: Button          # the entry in the settings
var about_built := false
var about_full := false        # third-party components and license texts are built
var hold_mouse := false
var hold_key := false
var hold_fired := false
var tick_cd := 0.0
var hold_frozen := -1.0        # debugging (--resetbar): the bar is shown at this fraction and doesn't move, no reset
static var _icons := {}        # icons from SVG (gear, arrows), once per process

# stage 10: touch
var touch := false             # touch mode (main.touch_mode): big buttons, gestures instead of the mouse
const BTN_H := 56              # minimum button height on touch (≈ 6.5 mm on a phone)
var bar_scroll: ScrollContainer
var bar_row: HBoxContainer
var help_btn: Button
var actions: HBoxContainer     # ↶ ⟲ ⟳ ↻ — in the bottom-right corner, under the thumb
var act_undo: Button
var act_rot_item: Button
var bubble: Button             # above the tried cell: ✓ place / ↩ back to hand
var bubble_kind := ""
var ring: PressRing            # the long-press ring
var vibrate_btn: Button

var result: Control
var res_title: Label
var res_stars: StarRow
var res_text: Label
var res_next: Button

var mode := "menu"


func setup(m) -> void:
	main = m
	touch = bool(main.touch_mode)
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _make_theme()
	add_child(root)
	_build_bar()
	_build_help()
	_build_corner()
	_build_hud()
	_build_toast()
	_build_menu()
	_build_result()
	_build_picker()
	_build_touch()
	_build_settings()
	_build_about()
	_build_confirm()
	root.move_child(toast_label, -1)   # the "Progress reset" toast — above the menu's dim
	if touch and OS.has_feature("mobile"):
		_apply_safe_area()   # on PC the "safe area" is the work area without the taskbar — not what we want


# ================================================================ building

func _build_bar() -> void:
	bar = PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.offset_top = -16
	bar.offset_bottom = -16
	root.add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	bar_row = row
	if touch:
		# the palette is wider than the screen — scroll with a finger; a dead zone so scrolling doesn't press the button under the finger
		bar_scroll = ScrollContainer.new()
		bar_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
		bar_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		bar_scroll.scroll_deadzone = 20
		bar.add_child(bar_scroll)
		bar_scroll.add_child(row)
	else:
		bar.add_child(row)
	var n := 0
	for d in Items.CATALOG:
		n += 1
		row.add_child(_tool_button(d["id"], I18n.t("item." + d["id"]), _item_thumb(d["id"]), n))
	tools_sep = VSeparator.new()
	tools_sep.add_theme_constant_override("separation", 10)
	row.add_child(tools_sep)
	for d in TOOL_INFO:
		n += 1
		row.add_child(_tool_button(d["id"], I18n.t("tool." + d["id"]), _tool_thumb(d["id"]), n))


func _build_help() -> void:
	help = PanelContainer.new()
	help.position = Vector2(16, 16)
	root.add_child(help)
	var hv := VBoxContainer.new()
	help.add_child(hv)
	help_title = Label.new()
	help_title.add_theme_font_size_override("font_size", 24)
	hv.add_child(help_title)
	help_body = Label.new()
	help_body.add_theme_font_size_override("font_size", 14)
	help_body.modulate = Color(1, 1, 1, 0.85)
	help_body.custom_minimum_size.x = 280 if touch else 330
	help_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hv.add_child(help_body)


func _build_corner() -> void:
	corner = PanelContainer.new()
	corner.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	corner.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	corner.offset_left = -16
	corner.offset_right = -16
	corner.offset_top = 16
	root.add_child(corner)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 6)
	corner.add_child(cv)
	clock = Label.new()
	clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	clock.add_theme_font_size_override("font_size", 20)
	cv.add_child(clock)
	fast_btn = _small_button(I18n.t("ui.corner.time", {"k": 1}), func(): main.toggle_fast())
	cv.add_child(fast_btn)
	sound_btn = _small_button(I18n.t("ui.corner.sound_on"), func(): main.toggle_sound())
	sound_btn.visible = not touch   # on touch the sound is in the settings, the panel is shorter
	cv.add_child(sound_btn)
	restart_btn = _small_button(I18n.t("ui.corner.restart"), func(): main.restart_level())
	cv.add_child(restart_btn)
	new_btn = _small_button(I18n.t("ui.corner.new_island"), _on_new)
	cv.add_child(new_btn)
	season_btn = _small_button(I18n.t("ui.corner.season", {"season": I18n.t("season.summer")}), func(): main.cycle_garden_season())
	cv.add_child(season_btn)
	cozy_btn = _small_button(I18n.t("ui.corner.cozy_off"), func(): main.toggle_cozy())
	cv.add_child(cozy_btn)
	cozy_label = Label.new()
	cozy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cozy_label.add_theme_font_size_override("font_size", 18)
	cozy_label.visible = false
	cv.add_child(cozy_label)
	help_btn = _small_button(I18n.t("ui.corner.help"), func(): toggle_help())
	help_btn.visible = touch
	cv.add_child(help_btn)
	settings_btn = _small_button(I18n.t("ui.settings"), func(): show_settings())
	settings_btn.icon = icon("gear")
	settings_btn.add_theme_constant_override("icon_max_width", 20)
	cv.add_child(settings_btn)
	menu_btn = _small_button(I18n.t("ui.corner.menu"), func(): main.open_menu())
	cv.add_child(menu_btn)
	if touch:
		# on a phone a column of 7 buttons of 56 px doesn't fit above the action buttons — two columns
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 6)
		grid.add_theme_constant_override("v_separation", 6)
		for ch in cv.get_children():
			if ch is Button:
				cv.remove_child(ch)
				(ch as Button).custom_minimum_size.x = 150
				grid.add_child(ch)
		cv.add_child(grid)
		cv.move_child(grid, 1)


func _build_hud() -> void:
	hud = PanelContainer.new()
	hud.set_anchors_preset(Control.PRESET_CENTER_TOP)
	hud.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hud.offset_top = 16
	root.add_child(hud)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	hud.add_child(v)
	hud_title = Label.new()
	hud_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_title.add_theme_font_size_override("font_size", 22)
	v.add_child(hud_title)
	hud_hint = Label.new()
	hud_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hud_hint.custom_minimum_size.x = 560
	hud_hint.add_theme_font_size_override("font_size", 14)
	hud_hint.modulate = Color(1, 1, 1, 0.8)
	v.add_child(hud_hint)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	v.add_child(row)
	hud_score = Label.new()
	hud_score.add_theme_font_size_override("font_size", 26)
	row.add_child(hud_score)
	hud_stars = StarRow.new()
	hud_stars.star_size = 26.0
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
		b.add_theme_font_size_override("font_size", 14)
		if touch:
			b.custom_minimum_size.y = BTN_H
		b.tooltip_text = I18n.t("ui.year.tip")
		b.pressed.connect(func(): main.set_year_view(s))
		hud_year.add_child(b)
		year_btns[s] = b


func _build_toast() -> void:
	toast_label = Label.new()
	toast_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toast_label.offset_top = 24
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# long banners ("Winter is here!") wrap and don't go under the side panels
	toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var tw := 560 if touch else 720   # on a phone don't go under the corner panel
	toast_label.custom_minimum_size.x = tw
	toast_label.offset_left = -tw * 0.5
	toast_label.offset_right = tw * 0.5
	toast_label.add_theme_font_size_override("font_size", 18)
	toast_label.add_theme_color_override("font_outline_color", Color("fff7ea"))
	toast_label.add_theme_constant_override("outline_size", 8)
	toast_label.modulate.a = 0.0
	toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(toast_label)


func _dim() -> Control:
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.25, 0.2, 0.15, 0.28)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	return dim


func _center_panel(parent: Control) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	return v


func _build_menu() -> void:
	menu = _dim()
	root.add_child(menu)
	var v := _center_panel(menu)
	# title in the center, the gear on the right (on the left — the same empty square so the title doesn't shift)
	var top := HBoxContainer.new()
	v.add_child(top)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(48, 48)
	top.add_child(pad)
	var title := Label.new()
	title.text = I18n.t("ui.title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 40)
	top.add_child(title)
	gear_btn = _icon_button(icon("gear"), I18n.t("ui.settings"), func(): show_settings())
	gear_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(gear_btn)
	var sub := Label.new()
	sub.text = I18n.t("ui.subtitle")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 16)
	sub.modulate = Color(1, 1, 1, 0.8)
	sub.visible = not touch   # doesn't fit on a phone's height — the first level explains the rules
	v.add_child(sub)
	if touch:
		v.add_theme_constant_override("separation", 6)
	menu_tabs = HBoxContainer.new()
	menu_tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	menu_tabs.add_theme_constant_override("separation", 8)
	v.add_child(menu_tabs)
	menu_grid = VBoxContainer.new()
	menu_grid.add_theme_constant_override("separation", 6)
	v.add_child(menu_grid)
	menu_total = Label.new()
	menu_total.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_total.add_theme_font_size_override("font_size", 18)
	v.add_child(menu_total)
	var free := _small_button(I18n.t("ui.sandbox"), func(): main.enter_sandbox())
	free.custom_minimum_size = Vector2(260, BTN_H if touch else 48)
	free.add_theme_font_size_override("font_size", 18)
	free.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(free)


## A new player's first start: big language buttons, the title in all languages at once.
func _build_picker() -> void:
	picker = _dim()
	picker.visible = false
	root.add_child(picker)


func show_language_picker(suggested: String) -> void:
	for ch in picker.get_children():
		ch.queue_free()
	var v := _center_panel(picker)
	v.custom_minimum_size.x = 420
	var titles := []
	for code in I18n.languages():
		var tb: Dictionary = I18n.tables.get(code, {})
		titles.append(String(tb.get("ui.lang.pick", code)))
	var title := Label.new()
	title.text = "\n".join(titles)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	v.add_child(title)
	var order: Array = I18n.languages()
	order.erase(suggested)
	order.push_front(suggested)
	for code in order:
		var b := _small_button(I18n.lang_name(code), func(): main.set_language(code))
		b.icon = I18n.flag(code)
		b.add_theme_constant_override("icon_max_width", 42)
		b.custom_minimum_size = Vector2(300, 56)
		b.add_theme_font_size_override("font_size", 22)
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(b)
	picker.visible = true


# ---------------------------------------------------------------- touch (stage 10)

func _build_touch() -> void:
	actions = HBoxContainer.new()
	actions.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	actions.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	actions.grow_vertical = Control.GROW_DIRECTION_BEGIN
	actions.offset_right = -16
	actions.offset_bottom = -16 - 148   # above the palette
	actions.add_theme_constant_override("separation", 8)
	actions.visible = false
	root.add_child(actions)
	act_rot_item = _icon_button(icon("rot_item"), I18n.t("ui.act.rot_item"), func(): main.rotate_item())
	actions.add_child(act_rot_item)
	actions.add_child(_icon_button(icon("rot_left"), I18n.t("ui.act.rot_left"), func(): main.rotate_island(-1)))
	actions.add_child(_icon_button(icon("rot_right"), I18n.t("ui.act.rot_right"), func(): main.rotate_island(1)))
	act_undo = _icon_button(icon("undo"), I18n.t("ui.act.undo"), func(): main.undo())
	actions.add_child(act_undo)
	bubble = _icon_button(icon("check"), "", func():
		if bubble_kind == "ok":
			main.confirm_aim()
		elif bubble_kind == "back":
			main.take_back_aim())
	bubble.visible = false
	root.add_child(bubble)
	ring = PressRing.new()
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.visible = false
	root.add_child(ring)


## Action buttons are visible only on touch and outside the menu; "rotate the item" — if the item rotates.
func _sync_actions() -> void:
	if actions == null:
		return
	actions.visible = touch and mode != "menu"
	act_rot_item.visible = Items.info(String(main.tool)).get("rotatable", false)


## The button above the tried cell: kind "ok" — ✓ place, "back" — back to hand / remove, "" — hide. pos — the screen point
## above the cell; the button doesn't go off screen or under the panels.
func set_bubble(pos: Vector2, kind: String, below: Vector2 = Vector2(-1, -1)) -> void:
	if bubble == null:
		return
	if kind == "" or not touch:
		bubble.visible = false
		bubble_kind = ""
		return
	if kind != bubble_kind:
		bubble.icon = icon("check") if kind == "ok" else icon("back")
		bubble.tooltip_text = I18n.t("ui.act.ok") if kind == "ok" else (I18n.t("ui.act.back_level") if mode == "level" else I18n.t("ui.act.back_garden"))
	bubble_kind = kind
	var sz := bubble.get_combined_minimum_size()
	var vr := root.get_global_rect()
	# above the cell; if a panel is there — below the cell (the button must not cover the score or the palette)
	var spots := [Vector2(pos.x - sz.x * 0.5, pos.y - sz.y)]
	if below.x >= 0.0:
		spots.append(Vector2(below.x - sz.x * 0.5, below.y + 6.0))
	var at: Vector2 = spots[0]
	for sp in spots:
		var p := Vector2(clampf(sp.x, vr.position.x + 8, vr.end.x - sz.x - 8), clampf(sp.y, vr.position.y + 8, vr.end.y - sz.y - 8))
		var r := Rect2(p, sz)
		var free := true
		for c in [bar, corner, help, hud, actions]:
			if c and c.is_visible_in_tree() and c.get_global_rect().intersects(r):
				free = false
		at = p
		if free:
			break
	bubble.position = at
	bubble.visible = true


func press_ring(pos: Vector2, frac: float) -> void:
	if ring == null:
		return
	ring.visible = frac >= 0.0
	if ring.visible:
		ring.frac = clampf(frac, 0.0, 1.0)
		ring.position = pos - ring.size * 0.5
		ring.queue_redraw()


## Palette width: by content, but no wider than the screen (beyond that — scroll with a finger).
func _fit_bar() -> void:
	if bar_scroll == null:
		return
	var w := 0.0
	var n := 0
	for ch in bar_row.get_children():
		if (ch as Control).visible:
			w += maxf((ch as Control).custom_minimum_size.x, (ch as Control).get_minimum_size().x)
			n += 1
	w += maxf(0, n - 1) * 6.0
	var avail := root.get_global_rect().size.x - 32.0 - 28.0
	bar_scroll.custom_minimum_size = Vector2(minf(w, avail), 112)


## Camera cutout and rounded corners: the interface inside the safe area (it is in physical px — convert to logical).
func _apply_safe_area() -> void:
	var sa := DisplayServer.get_display_safe_area()
	var scr := DisplayServer.screen_get_size()
	if sa.size.x <= 0 or scr.x <= 0:
		return
	var k := root.get_viewport_rect().size.x / float(get_window().size.x)
	root.offset_left = sa.position.x * k
	root.offset_top = sa.position.y * k
	root.offset_right = -(scr.x - sa.end.x) * k
	root.offset_bottom = -(scr.y - sa.end.y) * k


# ---------------------------------------------------------------- settings (stage 9)

## The settings screen: sound (three sliders), language (carousel + flags of all languages), progress reset.
## Closed by "Done", Esc and a click on the dim around the panel.
func _build_settings() -> void:
	settings = _dim()
	settings.visible = false
	settings.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			close_settings())
	root.add_child(settings)
	var v := _center_panel(settings)
	v.get_parent().get_parent().mouse_filter = Control.MOUSE_FILTER_IGNORE   # a click outside the panel reaches the dim
	_solid(settings, v)
	v.custom_minimum_size.x = 500
	if touch:
		v.add_theme_constant_override("separation", 6)
	var title := Label.new()
	title.text = I18n.t("ui.settings")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24 if touch else 30)
	v.add_child(title)
	v.add_child(_section(I18n.t("ui.settings.sound")))
	for bus in BUSES:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		v.add_child(row)
		var lbl := Label.new()
		lbl.text = I18n.t("ui.settings." + bus)
		lbl.custom_minimum_size.x = 170
		lbl.add_theme_font_size_override("font_size", 16)
		row.add_child(lbl)
		var sl := HSlider.new()
		sl.min_value = 0.0
		sl.max_value = 1.0
		sl.step = 0.05
		sl.custom_minimum_size = Vector2(240, BTN_H if touch else 28)   # on touch the whole height is a finger target
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sl.focus_mode = Control.FOCUS_NONE
		sl.value = float(main.vol.get(bus, 0.8))
		row.add_child(sl)
		var pct := Label.new()
		pct.custom_minimum_size.x = 56
		pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		pct.add_theme_font_size_override("font_size", 16)
		pct.text = _pct(sl.value)
		row.add_child(pct)
		sliders[bus] = sl
		slider_pct[bus] = pct
		sl.value_changed.connect(func(x: float):
			main.set_volume(bus, x)
			pct.text = _pct(x)
			if bus != "music":
				_tick_sound())
	if touch:
		vibrate_btn = _small_button("", func(): main.set_vibrate(not main.vibrate_on); _sync_vibrate())
		vibrate_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		v.add_child(vibrate_btn)
		_sync_vibrate()
	v.add_child(_section(I18n.t("ui.settings.language")))
	v.add_child(_carousel())
	v.add_child(_flag_row())
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 14)
	v.add_child(sep)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	v.add_child(bottom)
	var reset := _small_button(I18n.t("ui.settings.reset"), func(): show_reset_confirm())
	reset.modulate = Color(1, 1, 1, 0.8)
	reset.custom_minimum_size.x = 200
	bottom.add_child(reset)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(gap)
	about_btn = _small_button(I18n.t("ui.settings.about"), func(): show_about())   # separated from "Reset" by a gap
	about_btn.modulate = Color(1, 1, 1, 0.8)
	about_btn.custom_minimum_size.x = 130
	bottom.add_child(about_btn)
	var done := _small_button(I18n.t("ui.settings.done"), func(): close_settings())
	done.custom_minimum_size = Vector2(150, 44)
	done.add_theme_font_size_override("font_size", 17)
	bottom.add_child(done)


## A window over the menu: the panel is opaque (the menu doesn't show through the text), the dim is denser.
func _solid(dim: Control, v: VBoxContainer) -> void:
	(dim as ColorRect).color = Color(0.25, 0.2, 0.15, 0.45)
	var sb := _box(Color("fffaf2"), Color("ead9bb"))
	sb.set_corner_radius_all(22)
	sb.set_content_margin_all(20)
	(v.get_parent() as PanelContainer).add_theme_stylebox_override("panel", sb)


func _sync_vibrate() -> void:
	if vibrate_btn:
		vibrate_btn.text = I18n.t("ui.settings.vibrate_on") if main.vibrate_on else I18n.t("ui.settings.vibrate_off")


func _section(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 19)
	l.modulate = Color(1, 1, 1, 0.7)
	return l


func _pct(x: float) -> String:
	return I18n.t("ui.settings.percent", {"n": int(round(x * 100.0))})


## A "plop" while dragging a slider — you hear the level, but no more often than every 0.2 s (no crackle).
func _tick_sound() -> void:
	if tick_cd <= 0.0 and settings.visible:
		main.sfx.play("plop", 1.0, -6.0)
		tick_cd = 0.2


## Carousel: ◀ [flag] Own name ▶. The change is deferred: the interface is not rebuilt in the middle of a press.
func _carousel() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	var langs := I18n.languages()
	var cur := langs.find(I18n.current())
	var prev := _icon_button(icon("left"), "", func(): main.call_deferred("set_language", langs[(cur - 1 + langs.size()) % langs.size()]))
	row.add_child(prev)
	lang_prev = prev
	var mid := HBoxContainer.new()
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.custom_minimum_size.x = 250   # constant width — the arrows don't jump with the name's length
	mid.add_theme_constant_override("separation", 12)
	row.add_child(mid)
	mid.add_child(_flag_view(I18n.current(), Vector2(54, 36)))
	var lbl := Label.new()
	lbl.text = I18n.lang_name(I18n.current())
	lbl.add_theme_font_size_override("font_size", 22)
	mid.add_child(lbl)
	var next := _icon_button(icon("right"), "", func(): main.call_deferred("set_language", langs[(cur + 1) % langs.size()]))
	row.add_child(next)
	lang_next = next
	return row


## Flags of all languages under the carousel: the current one is pressed, a click switches to that language at once.
func _flag_row() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	for code in I18n.languages():
		var b := Button.new()
		b.toggle_mode = true
		b.button_pressed = code == I18n.current()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(72, BTN_H) if touch else Vector2(52, 38)
		b.tooltip_text = I18n.lang_name(code)
		var tex := I18n.flag(code)
		if tex:
			b.icon = tex
			b.expand_icon = true
			b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		else:
			b.text = code.to_upper()
		b.pressed.connect(func(): main.call_deferred("set_language", code))
		row.add_child(b)
		flag_btns[code] = b
	return row


## The language's flag or, if there is none (or the SVG failed to render), a badge with the code.
func _flag_view(code: String, sz: Vector2) -> Control:
	var tex := I18n.flag(code)
	if tex:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.custom_minimum_size = sz
		return tr
	var badge := PanelContainer.new()
	badge.custom_minimum_size = sz
	var l := Label.new()
	l.text = code.to_upper()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 16)
	badge.add_child(l)
	return badge


func show_settings() -> void:
	for bus in BUSES:
		sliders[bus].set_value_no_signal(float(main.vol.get(bus, 0.8)))
		slider_pct[bus].text = _pct(sliders[bus].value)
	confirm.visible = false
	about.visible = false
	settings.visible = true


func close_settings() -> void:
	cancel_hold()
	confirm.visible = false
	about.visible = false
	settings.visible = false
	main.flush_settings()


## About: a panel the full height of the screen (not CenterContainer — it would shrink the scroll to zero), width ≤ 900.
## On top — the human part (name, version, what it's made with), below — the Godot license; third-party components and full
## license texts are built only on a button press (77k characters — a pause on a phone). License texts are in the original.
func _build_about() -> void:
	about = _dim()
	(about as ColorRect).color = Color(0.25, 0.2, 0.15, 0.35)
	about.visible = false
	about.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			close_about())   # a click outside the panel — back to the settings
	settings.add_child(about)
	about_panel = PanelContainer.new()
	about_panel.anchor_left = 0.5
	about_panel.anchor_right = 0.5
	about_panel.anchor_top = 0.0
	about_panel.anchor_bottom = 1.0
	about_panel.offset_left = -450
	about_panel.offset_right = 450
	about_panel.offset_top = 20 if touch else 40
	about_panel.offset_bottom = -(20 if touch else 40)
	var sb := _box(Color("fffaf2"), Color("ead9bb"))
	sb.set_corner_radius_all(22)
	sb.set_content_margin_all(20)
	about_panel.add_theme_stylebox_override("panel", sb)
	about.add_child(about_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	about_panel.add_child(v)
	about_scroll = ScrollContainer.new()
	about_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED   # otherwise text wraps letter by letter
	about_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	about_scroll.scroll_deadzone = 12
	v.add_child(about_scroll)
	about_box = VBoxContainer.new()
	about_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	about_box.add_theme_constant_override("separation", 8)
	about_scroll.add_child(about_box)
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(bottom)
	var done := _small_button(I18n.t("ui.settings.done"), func(): close_about())
	done.custom_minimum_size = Vector2(180 if touch else 150, BTN_H if touch else 44)
	bottom.add_child(done)


func show_about() -> void:
	if not about_built:
		_fill_about()
	about.visible = true
	about_scroll.scroll_vertical = 0   # every opening starts at the top


func close_about() -> void:
	about.visible = false


func _about_label(text: String, size: int, alpha := 1.0, center := false) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", size)
	l.modulate = Color(1, 1, 1, alpha)
	if center:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	about_box.add_child(l)
	return l


func _fill_about() -> void:
	about_built = true
	_about_label(I18n.t("ui.title"), 28, 1.0, true)
	_about_label(I18n.t("ui.about.version", {"v": String(ProjectSettings.get_setting("application/config/version", ""))}), 17, 0.75, true)
	_about_label(I18n.t("ui.about.engine"), 18, 1.0, true)
	_about_label(I18n.t("ui.about.handmade"), 16, 0.85, true)
	about_box.add_child(HSeparator.new())
	about_box.add_child(_section(I18n.t("ui.about.license")))
	_about_label(Engine.get_license_text(), 14, 0.85)
	about_more = _small_button(I18n.t("ui.about.more"), func(): fill_about_full(OS.has_feature("android")))
	about_more.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	about_more.custom_minimum_size.x = 360
	about_box.add_child(about_more)


## Godot's third-party components, the Android template libraries and full license texts. android — show the Android block
## (the APK has it, a PC build doesn't; the test passes true).
func fill_about_full(android: bool) -> void:
	if about_full:
		return
	about_full = true
	about_more.visible = false
	_about_label(I18n.t("ui.about.legal_note"), 14, 0.7)
	about_box.add_child(_section(I18n.t("ui.about.components")))
	for c in Engine.get_copyright_info():
		var lines := [String(c["name"])]
		var lics := []
		for p in c["parts"]:
			for who in p["copyright"]:
				lines.append("© " + String(who))
			if not String(p["license"]) in lics:
				lics.append(String(p["license"]))
		lines.append(", ".join(lics))
		if SOURCE_LINKS.has(String(c["name"])):
			lines.append(I18n.t("ui.about.source", {"url": SOURCE_LINKS[String(c["name"])] % godot_tag()}))
		_about_label("\n".join(lines), 14, 0.85)
	if android:
		about_box.add_child(_section(I18n.t("ui.about.android")))
		for lib in ANDROID_LIBS:
			_about_label("%s\n© %s\n%s" % lib, 14, 0.85)
	about_box.add_child(_section(I18n.t("ui.about.texts")))
	var info := Engine.get_license_info()
	for key in info:
		_about_label(String(key), 16, 1.0)
		_about_label(String(info[key]), 13, 0.8)
	if android:
		_about_label("LLVM libc++ — LICENSE.TXT", 16, 1.0)
		_about_label(FileAccess.get_file_as_string(LIBCXX_LICENSE), 13, 0.8)


## The Godot release tag of the running engine, e.g. "4.7.2-stable" (a .0 patch has no third number: "4.7-stable").
static func godot_tag() -> String:
	var v := Engine.get_version_info()
	var num := "%d.%d" % [v["major"], v["minor"]]
	if int(v["patch"]) > 0:
		num += ".%d" % v["patch"]
	return "%s-%s" % [num, v["status"]]


## The reset window: what will be lost (in numbers), what stays; "Cancel" is bigger and on the left; hold the reset button for 3 s.
## No progress — nothing to reset, no reset button.
func _build_confirm() -> void:
	confirm = _dim()
	confirm.visible = false
	root.add_child(confirm)


func show_reset_confirm() -> void:
	for ch in confirm.get_children():
		ch.queue_free()
	hold_btn = null
	hold_fill = null
	hold_t = 0.0
	hold_mouse = false
	hold_key = false
	hold_fired = false
	var v := _center_panel(confirm)
	_solid(confirm, v)
	v.custom_minimum_size.x = 470
	var title := Label.new()
	title.text = I18n.t("ui.reset.title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	v.add_child(title)
	var levels: Dictionary = main.progress.get("levels", {})
	var stars := 0
	var crowns := 0
	for id in levels:
		stars += int(levels[id].get("stars", 0))
		if levels[id].get("crown", false):
			crowns += 1
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	if levels.is_empty():
		v.add_child(_para(I18n.t("ui.reset.none"), 1.0))
		v.add_child(row)
		var close := _small_button(I18n.t("ui.reset.close"), func(): confirm.visible = false)
		close.custom_minimum_size = Vector2(200, BTN_H if touch else 50)
		row.add_child(close)
		confirm.visible = true
		return
	v.add_child(_para(I18n.t("ui.reset.lose", {"stars": stars, "max": Levels.LEVELS.size() * 3, "crowns": crowns}), 1.0))
	v.add_child(_para(I18n.t("ui.reset.keep"), 0.75))
	v.add_child(row)
	var cancel := _small_button(I18n.t("ui.reset.cancel"), func(): confirm.visible = false)
	cancel.custom_minimum_size = Vector2(200, BTN_H if touch else 54)
	cancel.add_theme_font_size_override("font_size", 18)
	row.add_child(cancel)
	hold_btn = Button.new()
	hold_btn.focus_mode = Control.FOCUS_NONE
	hold_btn.custom_minimum_size = Vector2(230, BTN_H if touch else 54)
	hold_btn.add_theme_stylebox_override("normal", _box(Color("f8e6da"), TERRACOTTA))
	hold_btn.add_theme_stylebox_override("hover", _box(Color("fbeee5"), TERRACOTTA))
	hold_btn.add_theme_stylebox_override("pressed", _box(Color("f3dccd"), TERRACOTTA, 3))
	hold_btn.button_down.connect(func(): hold_mouse = true)
	hold_btn.button_up.connect(func(): hold_mouse = false)
	row.add_child(hold_btn)
	# the fill bar — under the caption, over the button's background (children are drawn after the parent)
	hold_fill = Panel.new()
	hold_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fs := StyleBoxFlat.new()
	fs.bg_color = Color(TERRACOTTA, 0.75)
	fs.set_corner_radius_all(14)
	hold_fill.add_theme_stylebox_override("panel", fs)
	hold_fill.position = Vector2(3, 3)
	hold_fill.size = Vector2(0, hold_btn.custom_minimum_size.y - 8)
	hold_btn.add_child(hold_fill)
	var hl := Label.new()
	hl.text = I18n.t("ui.reset.hold")
	hl.set_anchors_preset(Control.PRESET_FULL_RECT)
	hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hl.add_theme_font_size_override("font_size", 17)
	hold_btn.add_child(hl)
	confirm.visible = true


func _para(text: String, alpha: float) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 440
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 16)
	l.modulate = Color(1, 1, 1, alpha)
	return l


func holding() -> bool:
	return hold_mouse or hold_key


func cancel_hold() -> void:
	hold_mouse = false
	hold_key = false


## A hold step: accumulates while the button is held (mouse or Space/Enter), otherwise the bar drains. The frame step is limited
## to 1/15 s — a window stall won't reset progress in one frame. The mouse button is checked every frame: the release may
## not reach the button (the window lost focus). Fires once.
func hold_step(dt: float) -> void:
	if hold_btn == null or not confirm.visible:
		return
	if hold_frozen >= 0.0:
		hold_fill.size.x = (hold_btn.size.x - 6.0) * clampf(hold_frozen, 0.0, 1.0)
		return
	dt = minf(dt, 1.0 / 15.0)
	if hold_mouse and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		hold_mouse = false
	if holding() and not hold_fired:
		hold_t = minf(HOLD_TIME, hold_t + dt)
		if hold_t >= HOLD_TIME:
			hold_fired = true
			cancel_hold()
			confirm.visible = false
			settings.visible = false
			main.reset_progress()
			return
	else:
		hold_t = maxf(0.0, hold_t - dt * HOLD_TIME / HOLD_DRAIN)
	if hold_fill:
		hold_fill.size.x = (hold_btn.size.x - 6.0) * hold_t / HOLD_TIME


## Close the top window (Esc, "Back" on Android): the reset window (during a hold — only cancel it),
## then the settings. false — nothing to close.
func close_top() -> bool:
	if confirm.visible:
		if holding():
			cancel_hold()
		else:
			confirm.visible = false
		return true
	if about.visible:
		close_about()
		return true
	if settings.visible:
		close_settings()
		return true
	return false


## Keys while the settings screen, the reset window or the language choice is open: they don't reach the game.
## Esc closes only the top window; during a hold — only cancels the hold.
func handle_overlay_input(event: InputEvent) -> bool:
	if not (settings.visible or confirm.visible or picker.visible):
		return false
	if not event is InputEventKey:
		return false
	var k := event as InputEventKey
	if confirm.visible:
		if k.keycode == KEY_ESCAPE and k.pressed:
			close_top()
		elif (k.keycode == KEY_SPACE or k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER) and hold_btn != null:
			if k.pressed and not k.echo:
				hold_key = true
			elif not k.pressed:
				hold_key = false
	elif settings.visible and k.keycode == KEY_ESCAPE and k.pressed:
		close_top()   # About first, then the settings
	return true


func _build_result() -> void:
	result = _dim()
	result.visible = false
	root.add_child(result)
	var v := _center_panel(result)
	v.custom_minimum_size.x = 420
	res_title = Label.new()
	res_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	res_title.add_theme_font_size_override("font_size", 30)
	v.add_child(res_title)
	res_stars = StarRow.new()
	res_stars.star_size = 52.0
	res_stars.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(res_stars)
	res_text = Label.new()
	res_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	res_text.add_theme_font_size_override("font_size", 17)
	v.add_child(res_text)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	var again := _small_button(I18n.t("ui.result.again"), func(): hide_result())
	again.custom_minimum_size.x = 130
	row.add_child(again)
	var to_menu := _small_button(I18n.t("ui.result.menu"), func(): main.open_menu())
	to_menu.custom_minimum_size.x = 110
	row.add_child(to_menu)
	res_next = _small_button(I18n.t("ui.result.next"), func(): main.next_level())
	res_next.custom_minimum_size.x = 130
	row.add_child(res_next)


# ================================================================ modes

func show_menu(progress: Dictionary) -> void:
	mode = "menu"
	if actions:
		actions.visible = false
		set_bubble(Vector2.ZERO, "")
	result.visible = false
	menu.visible = true
	menu_progress = progress
	if menu_season == "":
		menu_season = _default_season(progress)
	_fill_menu()
	bar.visible = false
	hud.visible = false
	help.visible = false
	corner.visible = false


## The default tab: the season of the first unlocked level without stars; if every open level has stars (the next
## chapter waits for more), the season of the farthest open chapter.
func _default_season(progress: Dictionary) -> String:
	var open := Progress.open_chapters(progress)
	var last := "spring"
	for i in Levels.LEVELS.size():
		var L: Dictionary = Levels.LEVELS[i]
		if not open.has(Progress.chapter_of(L)):
			continue
		if int(Progress.entry(progress, L["id"]).get("stars", 0)) == 0:
			return L["season"]
		last = L["season"]
	return last


func _fill_menu() -> void:
	for ch in menu_tabs.get_children():
		ch.queue_free()
	for ch in menu_grid.get_children():
		ch.queue_free()
	var progress := menu_progress
	var by_slot := {}
	for i in Levels.LEVELS.size():
		by_slot[int(Levels.LEVELS[i]["slot"])] = i
	var total := 0
	var crowns := 0
	var season_stars := {}
	for L in Levels.LEVELS:
		var p := Progress.entry(progress, L["id"])
		total += int(p.get("stars", 0))
		if p.get("crown", false):
			crowns += 1
		season_stars[L["season"]] = int(season_stars.get(L["season"], 0)) + int(p.get("stars", 0))
	var open := Progress.open_chapters(progress)
	var by_ch := Progress.chapters()
	for s in Campaign.SEASONS:
		var sid: String = s["id"]
		var s_open := Progress.season_open(sid, progress, open)
		# a locked season: dimmed, a lock instead of the star count; it can still be opened to see what's ahead
		var label := I18n.t("ui.menu.tab", {"season": I18n.t("season." + sid), "n": int(season_stars.get(sid, 0))}) if s_open \
			else I18n.t("season." + sid)
		var tab := _small_button(label, func():
			menu_season = sid
			_fill_menu())
		tab.custom_minimum_size = Vector2(150, BTN_H) if touch else Vector2(150, 40)
		tab.toggle_mode = true
		tab.button_pressed = sid == menu_season
		if not s_open:
			# the lock sits right before the name, and the pair is centered like the other tabs' text: left alignment
			# with a left margin of half the free space
			var iw := 18 if touch else 15
			var fs := 17 if touch else 15
			var tw := root.get_theme_default_font().get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			tab.icon = icon("lock")
			tab.add_theme_constant_override("icon_max_width", iw)
			tab.add_theme_constant_override("h_separation", 6)
			tab.alignment = HORIZONTAL_ALIGNMENT_LEFT
			tab.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
			for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
				var sb: StyleBox = root.theme.get_stylebox(st, "Button").duplicate()
				sb.content_margin_left = maxf(8.0, floorf((tab.custom_minimum_size.x - iw - 6 - tw) / 2.0))
				sb.content_margin_right = 4
				tab.add_theme_stylebox_override(st, sb)
			tab.modulate = Color(1, 1, 1, 0.6)
		menu_tabs.add_child(tab)
	var season: Dictionary = Campaign.SEASONS[0]
	for s in Campaign.SEASONS:
		if s["id"] == menu_season:
			season = s
	for ch in 5:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		menu_grid.add_child(row)
		var first: int = int(season["from"]) + ch * 5
		var c := (first - 1) / 5
		row.add_child(_chapter_caption(c, open, by_ch, progress))
		for slot in range(first, first + 5):
			if by_slot.has(slot):
				var i: int = by_slot[slot]
				var L: Dictionary = Levels.LEVELS[i]
				var p := Progress.entry(progress, L["id"])
				row.add_child(_level_card(i, L, int(p.get("stars", 0)), int(p.get("best", 0)), open.has(c), bool(p.get("crown", false))))
			else:
				row.add_child(_soon_card(slot))
	menu_total.text = I18n.t("ui.menu.total", {"stars": total, "max": Levels.LEVELS.size() * 3, "crowns": crowns})
	if not Progress.season_open(menu_season, progress, open):
		# what opens this season: the stars of the chapter just before it
		var gate := int(season["from"] - 1) / 5 - 1
		if by_ch.has(gate):
			menu_total.text = I18n.t("ui.menu.season_locked", {"season": I18n.t("season." + menu_season),
				"need": Progress.chapter_need(by_ch[gate]), "chapter": I18n.t("chapter.%d" % gate)})


## The chapter caption, centered in its column: the name, and — on the open chapter whose next one is still closed — a
## small "★ 7 / 8" toward it. The name is fitted to one line so the counter doesn't push the row taller (phone rows).
func _chapter_caption(c: int, open: Dictionary, by_ch: Dictionary, progress: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(150, 0)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 0)
	var cap := Label.new()
	cap.text = I18n.t("chapter.%d" % c)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_theme_font_size_override("font_size", _fit_font(cap.text, 146.0, 15, 12))
	cap.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	cap.custom_minimum_size.x = 150
	cap.modulate = Color(1, 1, 1, 0.75 if open.has(c) else 0.45)
	box.add_child(cap)
	if open.has(c) and by_ch.has(c) and by_ch.has(c + 1) and not open.has(c + 1):
		var cnt := Label.new()
		cnt.name = "ChapterStars"
		cnt.text = I18n.t("ui.menu.chapter_stars", {"n": Progress.chapter_stars(progress, by_ch[c]), "need": Progress.chapter_need(by_ch[c])})
		cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cnt.add_theme_font_size_override("font_size", 13)
		cnt.add_theme_color_override("font_color", Color("b07a1e"))
		box.add_child(cnt)
	return box


func _level_card(i: int, L: Dictionary, stars: int, best: int, unlocked: bool, crown: bool) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(_card_w(), 58) if touch else Vector2(136, 74)
	b.focus_mode = Control.FOCUS_NONE
	b.disabled = not unlocked
	b.pressed.connect(func(): main.start_level(i))
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 2)
	b.add_child(v)
	var nm := Label.new()
	nm.text = I18n.t("ui.card.name", {"slot": int(L["slot"]), "name": I18n.level_name(L["id"])}) if unlocked else I18n.t("ui.card.locked", {"slot": int(L["slot"])})
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if touch:
		# phone: the name on one line (two lines pushed the stars off the card); if it doesn't fit — a smaller font
		nm.add_theme_font_size_override("font_size", _fit_font(nm.text, _card_w() - 14.0, 15, 12))
		nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		nm.custom_minimum_size.x = _card_w() - 14.0
	else:
		nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nm.custom_minimum_size.x = 128
		nm.add_theme_font_size_override("font_size", 13)
	v.add_child(nm)
	var line := HBoxContainer.new()
	line.alignment = BoxContainer.ALIGNMENT_CENTER
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(line)
	var sr := StarRow.new()
	sr.star_size = 15.0
	sr.filled = stars
	sr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(sr)
	if crown:
		var cr := Crown.new()
		cr.custom_minimum_size = Vector2(20, 16)
		cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(cr)
	if not unlocked:
		v.modulate = Color(1, 1, 1, 0.45)
	if best > 0:
		b.tooltip_text = I18n.t("ui.card.best", {"best": best, "perfect": int(L["perfect"])})
	return b


## Phone: level cards share the menu panel's full width (chapter caption 150, five cards, gaps).
func _card_w() -> float:
	var w := root.get_global_rect().size.x
	return clampf((w - 96.0 - 28.0 - 150.0 - 30.0) / 5.0, 150.0, 205.0)


## The largest font size (from big to small) at which the line fits the width.
func _fit_font(text: String, width: float, big: int, small: int) -> int:
	var font := root.get_theme_default_font()
	for fs in range(big, small - 1, -1):
		if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= width:
			return fs
	return small


func _soon_card(slot: int) -> Control:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(_card_w(), 58) if touch else Vector2(136, 74)
	p.modulate = Color(1, 1, 1, 0.35)
	var l := Label.new()
	l.text = I18n.t("ui.card.soon", {"slot": slot})
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 13)
	p.add_child(l)
	return p


func enter_sandbox_ui() -> void:
	mode = "sandbox"
	menu.visible = false
	result.visible = false
	hud.visible = false
	help.visible = true
	corner.visible = true
	bar.visible = true
	help_title.text = I18n.t("ui.title")
	help_body.text = I18n.t("ui.help.sandbox_touch") if touch else I18n.t("ui.help.sandbox")
	new_btn.visible = true
	season_btn.visible = true
	cozy_btn.visible = true
	restart_btn.visible = false
	tools_sep.visible = true
	toast_label.offset_top = 24
	for id in buttons:
		# basic items and tools — always; seasonal ones — after meeting them in the campaign (the palette doesn't overflow)
		buttons[id].visible = id in BASE_ITEMS or Items.info(id).is_empty() or Progress.seen(main.progress, id)
		buttons[id].disabled = false
		buttons[id].text = names[id]
	help.visible = not touch   # on touch the cheat sheet is behind the "Help" button (and one-time tips)
	_fit_bar()
	_sync_actions()


func enter_level_ui(idx: int, L: Dictionary, hand: Dictionary) -> void:
	mode = "level"
	menu.visible = false
	result.visible = false
	hud.visible = true
	help.visible = true
	corner.visible = true
	bar.visible = true
	new_btn.visible = false
	season_btn.visible = false
	cozy_btn.visible = false
	cozy_label.visible = false
	restart_btn.visible = true
	tools_sep.visible = false
	hud_year.visible = Campaign.is_year(L)
	toast_label.offset_top = 236 if hud_year.visible else 196
	hud_title.text = I18n.t("ui.hud.title", {"slot": int(L["slot"]), "name": I18n.level_name(L["id"])})
	hud_hint.text = I18n.level_hint(L["id"], touch)
	hud_stars.thresholds = L["stars"]
	for id in buttons:
		buttons[id].visible = hand.has(id)
	update_hand(hand)
	_fit_bar()
	_sync_actions()


## Highlight an item's button in the palette (introducing a novelty): a soft pulse for a few seconds.
func highlight_tool(id: String) -> void:
	if not buttons.has(id):
		return
	var b: Button = buttons[id]
	var tw := b.create_tween()
	tw.set_loops(4)
	tw.tween_property(b, "modulate", Color(1.25, 1.15, 0.8), 0.45)
	tw.tween_property(b, "modulate", Color.WHITE, 0.45)


func update_hand(hand: Dictionary) -> void:
	for id in hand:
		var b: Button = buttons[id]
		var n: int = hand[id]
		b.text = "%s ×%d" % [names[id], n]
		b.disabled = n <= 0


## Free garden: the current season on the button (if only one is unlocked — the button is disabled).
func set_garden_season(s: String, can_change: bool) -> void:
	season_btn.text = I18n.t("ui.corner.season", {"season": I18n.t("season." + s)})
	season_btn.disabled = not can_change
	season_btn.tooltip_text = I18n.t("ui.corner.season_tip") if can_change else I18n.t("ui.corner.season_locked")


## Free garden: an optional counter — one number by the rules of the chosen season, no thresholds or records.
func set_garden_score(on: bool, v: int, s: String) -> void:
	cozy_btn.text = I18n.t("ui.corner.cozy_on") if on else I18n.t("ui.corner.cozy_off")
	cozy_label.visible = on and mode == "sandbox"
	cozy_label.text = I18n.t("ui.corner.cozy_value", {"season": I18n.t("season." + s), "n": v})


## All Year Round: how much coziness the garden gives in each season (the sum is the total); the selected season is pressed.
func set_year(parts: Dictionary, view: String) -> void:
	for s in YEAR_ORDER:
		var b: Button = year_btns[s]
		b.text = I18n.t("ui.year.btn", {"season": I18n.t("season." + s), "n": int(parts.get(s, 0))})
		b.set_pressed_no_signal(s == view)


func set_score(score: int, stars: int) -> void:
	hud_score.text = I18n.t("ui.hud.score", {"n": score})
	hud_stars.filled = stars
	hud_stars.queue_redraw()


func show_rules(id: String) -> void:
	if mode != "level":
		return
	help_title.text = names.get(id, id)
	var key := "ui.help.card_touch" if touch else "ui.help.card"
	help_body.text = I18n.t(key, {"base": Scoring.BASE, "rules": Scoring.describe(id, main.known_items(), main.level_drought(), main.level_flags(), main.level_snow())})


func show_result(stars: int, score: int, L: Dictionary, record: bool, has_next: bool, note := "") -> void:
	result.visible = true
	res_stars.filled = stars
	res_stars.queue_redraw()
	var th: Array = L["stars"]
	if stars == 0:
		res_title.text = I18n.t("ui.result.almost")
		res_text.text = I18n.t("ui.result.need_first_touch" if touch else "ui.result.need_first", {"score": score, "need": th[0]})
	else:
		res_title.text = I18n.t("ui.result.star%d" % stars)
		if score >= int(L.get("perfect", 9999)):
			res_title.text = I18n.t("ui.result.perfect_title")
		var lines := I18n.t("ui.result.score", {"score": score})
		if stars < 3:
			lines += I18n.t("ui.result.to_next", {"n": int(th[stars]) - score})
		if record:
			lines += "\n" + I18n.t("ui.result.record")
		if score > int(L.get("perfect", 9999)):
			lines += "\n" + I18n.t("ui.result.beyond")
		elif score == int(L.get("perfect", 9999)):
			lines += "\n" + I18n.t("ui.result.ideal")
		elif stars == 3:
			lines += "\n" + I18n.t("ui.result.ideal_is", {"n": int(L["perfect"])})
		res_text.text = lines
	if note != "":
		res_text.text += "\n" + note
	res_next.visible = has_next and stars > 0


func hide_result() -> void:
	result.visible = false


# ================================================================ frame and odds and ends

func _process(dt: float) -> void:
	if toast_t > 0.0:
		toast_t -= dt
		toast_label.modulate.a = clampf(toast_t, 0.0, 1.0)
	tick_cd -= dt
	hold_step(dt)
	if new_armed > 0.0:
		new_armed -= dt
		if new_armed <= 0.0:
			new_btn.text = I18n.t("ui.corner.new_island")
	# thumbnails are drawn for a few frames, then frozen
	if thumb_frames < 6:
		thumb_frames += 1
		if thumb_frames == 6:
			for vp in thumbs:
				vp.render_target_update_mode = SubViewport.UPDATE_DISABLED


func is_over_ui(p: Vector2) -> bool:
	if menu.visible or result.visible or picker.visible or settings.visible or confirm.visible:
		return true
	for c in [bar, corner, help, hud, actions, bubble]:
		if c and c.is_visible_in_tree() and c.get_global_rect().has_point(p):
			return true
	return false


func select_tool(id: String) -> void:
	if buttons.has(id):
		buttons[id].button_pressed = true
	show_rules(id)
	_sync_actions()


func toast(text: String, seconds: float = 2.5) -> void:
	if main.no_toasts:   # --nocoach / --noui: a store frame without one-time captions
		return
	toast_label.text = text
	toast_t = seconds


func toggle_help() -> void:
	if mode != "menu":
		help.visible = not help.visible


func set_clock(day_time: float) -> void:
	var minutes := int(day_time * 24.0 * 60.0)
	var hh := minutes / 60
	var part := I18n.t("ui.clock.night")
	if hh >= 5 and hh < 11:
		part = I18n.t("ui.clock.morning")
	elif hh >= 11 and hh < 17:
		part = I18n.t("ui.clock.day")
	elif hh >= 17 and hh < 22:
		part = I18n.t("ui.clock.evening")
	clock.text = "%s  %02d:%02d" % [part, hh, minutes % 60]


func set_fast(on: bool) -> void:
	fast_btn.text = I18n.t("ui.corner.time", {"k": 30 if on else 1})


func set_sound(on: bool) -> void:
	sound_btn.text = I18n.t("ui.corner.sound_on") if on else I18n.t("ui.corner.sound_off")


func _on_new() -> void:
	if new_armed > 0.0:
		new_armed = 0.0
		new_btn.text = I18n.t("ui.corner.new_island")
		main.new_island()
	else:
		new_armed = 3.0
		new_btn.text = I18n.t("ui.corner.new_confirm")


# ---------------------------------------------------------------- buttons

func _tool_button(id: String, label: String, tex: Texture2D, n: int) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.button_group = group
	b.icon = tex
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	b.text = label
	b.custom_minimum_size = Vector2(96, 112) if touch else Vector2(84, 98)
	b.add_theme_font_size_override("font_size", 14 if touch else 13)
	if touch:
		b.mouse_filter = Control.MOUSE_FILTER_PASS   # dragging over a button reaches the palette's scroll
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = "%s  [%d]" % [label, n % 10] if n <= 10 else label
	b.pressed.connect(func(): main.set_tool(id))
	buttons[id] = b
	names[id] = label
	return b


## A square button with an icon (gear, carousel arrows): at least 48 px — easy to hit.
func _icon_button(tex: Texture2D, tip: String, cb: Callable) -> Button:
	var b := Button.new()
	b.icon = tex
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_constant_override("icon_max_width", 28)
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(60, 60) if touch else Vector2(48, 48)
	b.tooltip_text = tip
	b.pressed.connect(cb)
	return b


## Interface icons are SVG in code, rasterized once (like language flags; no image files).
static func icon(id: String) -> Texture2D:
	if _icons.has(id):
		return _icons[id]
	var ink := "#" + INK.to_html(false)
	var svg := ""
	match id:
		"gear":
			var teeth := ""
			for a in range(0, 360, 45):
				teeth += "<rect x='-2.3' y='-11' width='4.6' height='5.5' rx='1.2' transform='rotate(%d)'/>" % a
			svg = "<svg xmlns='http://www.w3.org/2000/svg' viewBox='-12 -12 24 24'><g fill='%s'>%s<circle r='7.6'/></g><circle r='3.1' fill='#fff7ea'/></svg>" % [ink, teeth]
		"check":
			svg = "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 10 10'><path d='M2.2,5.4 L4.2,7.4 L7.9,2.8' fill='none' stroke='#3f8a4a' stroke-width='1.5' stroke-linecap='round' stroke-linejoin='round'/></svg>"
		"back":
			svg = "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 10 10'><path d='M5,1.5 V6.3 M3,4.4 L5,6.4 L7,4.4 M2,8.5 H8' fill='none' stroke='%s' stroke-width='1.3' stroke-linecap='round' stroke-linejoin='round'/></svg>" % ink
		"undo":
			svg = "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 10 10'><path d='M3,3.8 H6 A2.3,2.3 0 0 1 6,8.4 H4 M4.6,2.1 L2.8,3.8 L4.6,5.5' fill='none' stroke='%s' stroke-width='1.2' stroke-linecap='round' stroke-linejoin='round'/></svg>" % ink
		"rot_right", "rot_left", "rot_item":
			var arc := "<path d='M5,2.2 A2.8,2.8 0 1 1 2.2,5 M3.9,1.1 L5,2.2 L3.9,3.3' fill='none' stroke='%s' stroke-width='1.1' stroke-linecap='round' stroke-linejoin='round'/>" % ink
			if id == "rot_left":
				arc = "<g transform='translate(10,0) scale(-1,1)'>%s</g>" % arc
			if id == "rot_item":
				arc += "<rect x='4.1' y='4.1' width='1.8' height='1.8' rx='0.3' fill='%s'/>" % ink
			svg = "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 10 10'>%s</svg>" % arc
		"lock":
			svg = "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 10 10'><path d='M3.3,4.6 V3.4 A1.7,1.7 0 0 1 6.7,3.4 V4.6' fill='none' stroke='%s' stroke-width='1.1' stroke-linecap='round'/><rect x='2.3' y='4.5' width='5.4' height='4.2' rx='0.9' fill='%s'/></svg>" % [ink, ink]
		"menu":
			svg ="<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 10 10'><path d='M2,3 H8 M2,5 H8 M2,7 H8' stroke='%s' stroke-width='1.1' stroke-linecap='round'/></svg>" % ink
		"up", "down":
			var d2 := "M2.5,6.2 L5,3.8 L7.5,6.2" if id == "up" else "M2.5,3.8 L5,6.2 L7.5,3.8"
			svg = "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 10 10'><path d='%s' fill='none' stroke='%s' stroke-width='1.2' stroke-linecap='round' stroke-linejoin='round'/></svg>" % [d2, ink]
		"left", "right":
			var d := "M6.5,1.8 L3.2,5 L6.5,8.2" if id == "left" else "M3.5,1.8 L6.8,5 L3.5,8.2"
			svg = "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 10 10'><path d='%s' fill='none' stroke='%s' stroke-width='1.6' stroke-linecap='round' stroke-linejoin='round'/></svg>" % [d, ink]
	var img := Image.new()
	var tex: Texture2D = null
	if svg != "" and img.load_svg_from_string(svg, 4.0) == OK:
		tex = ImageTexture.create_from_image(img)
	_icons[id] = tex
	return tex


func _small_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(170, BTN_H) if touch else Vector2(170, 36)
	b.add_theme_font_size_override("font_size", 17 if touch else 15)
	b.pressed.connect(cb)
	return b


# ---------------------------------------------------------------- thumbnails

func _item_thumb(id: String) -> Texture2D:
	var model := Node3D.new()
	if Items.info(id).get("water", false):
		C.part(model, C.rounded_box(Vector3(0.9, 0.24, 0.9), 0.08, 3), C.mat(Color("ecd59d")), Vector3(0, -0.2, 0))
		C.part(model, C.rounded_box(Vector3(0.94, 0.2, 0.94), 0.07, 3), C.water_mat(), Vector3(0, -0.1, 0))
	else:
		C.part(model, C.rounded_box(Vector3(0.9, 0.26, 0.9), 0.09, 3), C.mat(Color("8acb6c")), Vector3(0, -0.13, 0))
	var item := Items.build(id, 4242)
	if id == "lily":
		item.position.y = -0.02
	if id == "fence" or id == "bench":
		item.scale = Vector3.ONE * 0.8
	model.add_child(item)
	return _render(model)


func _tool_thumb(id: String) -> Texture2D:
	var model := Node3D.new()
	var grass := C.mat(Color("8acb6c"))
	var dirt := C.mat(Color("ad7752"))
	var arrow := C.mat(Color("ffd166"), 0.5)
	match id:
		"raise":
			C.part(model, C.rounded_box(Vector3(0.7, 0.5, 0.7), 0.1, 3), dirt, Vector3(0, -0.05, 0))
			C.part(model, C.rounded_box(Vector3(0.74, 0.18, 0.74), 0.08, 3), grass, Vector3(0, 0.22, 0))
			C.part(model, C.cone(0.2, 0.28), arrow, Vector3(0, 0.62, 0))
			C.part(model, C.cyl(0.07, 0.07, 0.2), arrow, Vector3(0, 0.42, 0))
		"lower":
			C.part(model, C.rounded_box(Vector3(0.7, 0.2, 0.7), 0.08, 3), dirt, Vector3(0, -0.2, 0))
			C.part(model, C.rounded_box(Vector3(0.74, 0.14, 0.74), 0.06, 3), grass, Vector3(0, -0.06, 0))
			C.part(model, C.cone(0.2, 0.28), arrow, Vector3(0, 0.26, 0), Vector3.ONE, Vector3(PI, 0, 0))
			C.part(model, C.cyl(0.07, 0.07, 0.2), arrow, Vector3(0, 0.5, 0))
		"water":
			C.part(model, C.rounded_box(Vector3(0.8, 0.3, 0.8), 0.09, 3), dirt, Vector3(0, -0.15, 0))
			C.part(model, C.rounded_box(Vector3(0.84, 0.18, 0.84), 0.07, 3), C.water_mat(), Vector3(0, 0.02, 0))
			C.part(model, C.sphere(0.14), C.mat(Color("5fb6d9"), 0.2), Vector3(0, 0.45, 0))
			C.part(model, C.cone(0.1, 0.18), C.mat(Color("5fb6d9"), 0.2), Vector3(0, 0.6, 0))
		"remove":
			model.add_child(Items.build("shovel", 1))
	return _render(model)


func _render(model: Node3D) -> Texture2D:
	var vp := SubViewport.new()
	vp.size = Vector2i(128, 128)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("e8eef4")
	e.ambient_light_energy = 0.7
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = e
	vp.add_child(we)
	var light := DirectionalLight3D.new()
	light.rotation = Vector3(deg_to_rad(-50), deg_to_rad(20), 0)
	light.light_energy = 1.15
	light.light_color = Color("fff3e0")
	vp.add_child(light)
	var piv := Node3D.new()
	piv.position = Vector3(0, 0.42, 0)
	piv.rotation.y = PI * 0.25
	vp.add_child(piv)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.55
	cam.rotation.x = deg_to_rad(-30)
	piv.add_child(cam)
	cam.position = cam.transform.basis.z * 10.0
	vp.add_child(model)
	thumbs.append(vp)
	return vp.get_texture()


# ---------------------------------------------------------------- theme

func _make_theme() -> Theme:
	var th := Theme.new()
	th.set_stylebox("normal", "Button", _box(Color("fff7ea"), Color("e6d5b8")))
	th.set_stylebox("hover", "Button", _box(Color("fffdf7"), Color("e8c98f")))
	th.set_stylebox("pressed", "Button", _box(Color("ffe2a3"), Color("e3a54a"), 3))
	th.set_stylebox("hover_pressed", "Button", _box(Color("ffe8b5"), Color("e3a54a"), 3))
	th.set_stylebox("disabled", "Button", _box(Color(0.96, 0.93, 0.88, 0.7), Color("e6d5b8")))
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		th.set_color(k, "Button", INK)
	th.set_color("font_disabled_color", "Button", Color(INK, 0.45))
	th.set_color("font_color", "Label", INK)
	var track := StyleBoxFlat.new()
	track.bg_color = Color("ead9bb")
	track.set_corner_radius_all(6)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	th.set_stylebox("slider", "HSlider", track)
	var filled := StyleBoxFlat.new()
	filled.bg_color = Color("e3a54a")
	filled.set_corner_radius_all(6)
	filled.content_margin_top = 4
	filled.content_margin_bottom = 4
	th.set_stylebox("grabber_area", "HSlider", filled)
	th.set_stylebox("grabber_area_highlight", "HSlider", filled)
	var panel := _box(Color(1.0, 0.975, 0.93, 0.9), Color("ead9bb"))
	panel.set_corner_radius_all(22)
	panel.set_content_margin_all(14)
	th.set_stylebox("panel", "PanelContainer", panel)
	var tip := _box(Color("fff7ea"), Color("e6d5b8"))
	tip.set_corner_radius_all(10)
	th.set_stylebox("panel", "TooltipPanel", tip)
	th.set_color("font_color", "TooltipLabel", INK)
	return th


func _box(bg: Color, border: Color, bw: int = 2) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.border_width_bottom = bw + 2
	s.set_corner_radius_all(16)
	s.set_content_margin_all(6)
	s.shadow_color = Color(0.35, 0.25, 0.15, 0.16)
	s.shadow_size = 4
	s.shadow_offset = Vector2(0, 3)
	return s


# ---------------------------------------------------------------- long-press ring

## A ring around the finger: fills over the long-press time (shows the gesture exists and is about to fire).
class PressRing extends Control:
	var frac := 0.0

	func _init() -> void:
		size = Vector2(96, 96)

	func _draw() -> void:
		var c := size * 0.5
		draw_arc(c, 40.0, 0.0, TAU, 48, Color(1, 1, 1, 0.45), 7.0, true)
		draw_arc(c, 40.0, -PI * 0.5, -PI * 0.5 + TAU * frac, 48, Color("d9825b"), 7.0, true)


# ---------------------------------------------------------------- stars

## A row of three stars, drawn by hand (independent of the font).
## If thresholds are given, each star has its threshold written under it.
class StarRow extends Control:
	var star_size := 24.0:
		set(v):
			star_size = v
			_resize()
	var filled := 0
	var pitch := 0.0   # step between stars; 0 — 1.25 of the size (three-digit thresholds need more)
	var thresholds: Array = []:
		set(v):
			thresholds = v
			_resize()

	func _init() -> void:
		_resize()

	func _resize() -> void:
		var h := star_size + (18.0 if thresholds.size() > 0 else 0.0)
		custom_minimum_size = Vector2(star_size + 2.0 * _pitch(), h)
		queue_redraw()

	func _pitch() -> float:
		return pitch if pitch > 0.0 else star_size * 1.25

	func _draw() -> void:
		var font := get_theme_default_font()
		for i in 3:
			var c := Vector2(star_size * 0.5 + i * _pitch(), star_size * 0.5)
			var pts := PackedVector2Array()
			for k in 10:
				var a := -PI * 0.5 + k * PI / 5.0
				var r := star_size * (0.5 if k % 2 == 0 else 0.22)
				pts.append(c + Vector2(cos(a), sin(a)) * r)
			var on := i < filled
			draw_colored_polygon(pts, Color("f6b93b") if on else Color(0.87, 0.8, 0.68, 0.55))
			pts.append(pts[0])
			draw_polyline(pts, Color("c98a1e") if on else Color(0.72, 0.62, 0.48, 0.7), maxf(1.5, star_size * 0.06), true)
			if thresholds.size() > i:
				var txt := str(thresholds[i])
				var tw := maxf(star_size * 1.2, _pitch() - 2.0)
				draw_string(font, Vector2(c.x - tw * 0.5, star_size + 15.0), txt, HORIZONTAL_ALIGNMENT_CENTER, tw, 14, Color(0.36, 0.27, 0.21, 0.85))


## The "Perfect" crown next to the stars.
class Crown extends Control:
	func _draw() -> void:
		var w := size.x
		var h := size.y
		var pts := PackedVector2Array([Vector2(w * 0.08, h * 0.9), Vector2(w * 0.08, h * 0.3), Vector2(w * 0.32, h * 0.58),
			Vector2(w * 0.5, h * 0.12), Vector2(w * 0.68, h * 0.58), Vector2(w * 0.92, h * 0.3), Vector2(w * 0.92, h * 0.9)])
		draw_colored_polygon(pts, Color("f2b632"))
		pts.append(pts[0])
		draw_polyline(pts, Color("b07a16"), 1.5, true)
