extends Node3D
## Clay Garden: the island, arranging items, day and night, wildlife, saving.

const C := preload("res://scripts/clay.gd")
const Items := preload("res://scripts/items.gd")
const Terrain := preload("res://scripts/terrain.gd")
const UI := preload("res://scripts/ui.gd")
const UIPhone := preload("res://scripts/ui_phone.gd")   # stage 10, R10: the phone layout (touch mode)
const Sfx := preload("res://scripts/sfx.gd")
const Music := preload("res://scripts/music.gd")
const Scoring := preload("res://scripts/scoring.gd")
const Levels := preload("res://scripts/levels.gd")
const Progress := preload("res://scripts/progress.gd")
const Campaign := preload("res://scripts/campaign.gd")
const I18n := preload("res://scripts/i18n.gd")

const SAVE_PATH := "user://garden.json"
const PROGRESS_PATH := "user://progress.json"
const SETTINGS_PATH := "user://settings.json"   # player settings (language, volume); garden and progress are separate
const VOL_DEFAULT := {"master": 0.8, "music": 0.4, "effects": 0.8}
const PLAYLOG_PATH := "user://playlog.json"   # play log for calibrating the D metric (local only)
const DAY_LENGTH := 360.0          # seconds per day at ×1 speed
const FAST := 30.0
const TERRAIN_TOOLS := ["raise", "lower", "water", "remove"]
const NO_CELL := Vector2i(-1, -1)

var terrain: Terrain
var ui: UI
var sfx: Sfx
var music: Music
var items_root: Node3D
var pivot: Node3D
var cam: Camera3D
var sun: DirectionalLight3D
var env: Environment
var fireflies: GPUParticles3D
var shadow_clouds: Array[Node3D] = []
var cloud_ring: Node3D

var items: Dictionary = {}        # Vector2i -> {id, seed, rot, node, sway, amp, phase}
var tool := "tree"
var ghost: Node3D
var ghost_seed := 1
var ghost_rot := 0
var ghost_material: ShaderMaterial
var highlight: MeshInstance3D
var highlight_material: ShaderMaterial
var hover_cell := NO_CELL
var painting := 0                 # 0 — none, 1 — left button, 2 — right button
var rotating := false             # PC: a middle drag, or a left drag that began off the island, turns the island

var island_seed := 0
var day_time := 0.36
var time_fast := false
var daylight := 1.0
var yaw_target := PI * 0.25
var zoom_target := 13.0
## Stage 14 (D4): the camera orbits the island's fixed center; a drag turns it by any angle, Q / E go to the fixed
## positions 45° + k·90°. The zoom range comes from the map: at the closest zoom every land cell stays in the free area.
const YAW_BASE := PI * 0.25
const YAW_STEP := PI * 0.5
const SNAP_DEG := 10.0            # Q / E skip a position closer than this; after a spin the island eases into one this close
const SPIN_DECAY := 0.1           # release inertia: the speed falls e times every 0.1 s (≈ 0.3 s to a stop)
const SPIN_MIN := 0.05            # rad/s: slower than this the spin stops (and the soft snap applies)
const SPIN_STOP := 0.3            # rad/s: a touch during a faster spin stops it and is not a tap
const PITCH := 35.0
var yaw_vel := 0.0                # rad/s of the release inertia
var drag_us := 0                  # the last rotation drag event's time (µs) — for the release speed
var zoom_min := 7.0
var zoom_max := 24.0
var fit_key := []                 # what the zoom range was computed for: mode, level, the free area
const RESULT_DELAY := 1.0         # D6: the finished island and its "+N" are seen before the result sheet
var result_delay := RESULT_DELAY  # tests set 0
var result_wait := -1.0           # > 0 — the result is pending; the world and undo don't take input
var result_args := []
var pond_note := false           # the loaded garden's ponds found their level: say so once on entering
var aim_placed := 0               # placements by "tap again" this session: the hint repeats until the 3rd
var t := 0.0
var save_enabled := true
var save_timer := -1.0
var ambient_timer := 2.0
var butterfly_timer := 0.0
var butterflies: Array = []

# modes: "menu" — level menu, "sandbox" — free garden, "level" — a level
var mode := "menu"
var sandbox_ready := false        # the island currently holds the free garden (not a level)
var level_idx := -1
var hand: Dictionary = {}         # id -> how many are left in the hand
var level_score := 0
var year_view := "winter"   # All Year Round: the season the island is shown in
var garden_season := "summer"   # free garden: the season is the garden's look, chosen by the player (garden.json v2)
var garden_cozy := false        # free garden: the coziness counter, off by default (the garden is not an exam)
var save_path := SAVE_PATH      # tests set their own path and never touch the player's garden
var progress_path := PROGRESS_PATH   # stage 9: also fields — tests set their own paths before add_child (before _ready)
var settings_path := SETTINGS_PATH
var playlog_path := PLAYLOG_PATH
var music_on := true              # tests turn the music off (don't synthesize notes for every Main)
var vol: Dictionary = VOL_DEFAULT.duplicate()   # bus volumes 0…1
var quiet := false                # the quick "quiet" (M, the corner button): mutes Master, not saved
var saved_lang := ""              # the language from settings or chosen by the player (--lang is not saved)
var settings_timer := -1.0        # settings are written 0.5 s after the last change

# stage 10: touch. Finger state machine: tap (released quickly and almost in place) / long press / camera
# drag / two fingers (pinch). A finger that started over the interface is ignored by the world until released.
const TAP_SLOP := 26.0            # logical px: beyond this it's a camera drag, not a tap
const LONG_TIME := 0.45           # long press — remove / back to hand
const RING_FROM := 0.2            # from this moment a ring grows around the finger
const CONFIRM_GUARD := 0.06       # a second try-tap sooner than this is the same tap's duplicate event (a quick double tap places)
const UNDO_MAX := 10
const TOUCH_SIZE := Vector2i(1333, 600)   # logical interface size on a phone: everything is bigger
var touch_mode := false           # Android/iOS or --touch
var touch_arg := false
var fingers := {}                 # finger index -> {start, pos, t0, ui, moved, long}
var multi := false                # there were two fingers: until all are released — no taps and no drags
var pinch_d := 0.0
var aim_cell := NO_CELL           # the tried cell (a tap on a cell) — replaces the mouse hover
var aim_t := 0.0
var undo_stack: Array = []        # [{c, s: the cell's state before the action}]
var vibrate_on := true
var back_armed := 0.0             # "Back" in the menu: a second press within 2 s exits
var coach := {}                   # one-time gesture tips (stored in the settings)
var card_collapsed := false       # phone: the rules card is collapsed (here, not in ui — survives a language change)
## Season change as a wave from the center: one controlling wave, changes only the LOOK (nodes), not the garden data.
const WAVE_TIME := 1.6
var wave_t := -1.0              # < 0 — no wave
var wave_done := {}             # cells already re-dressed by this wave
var wave_center := Vector2.ZERO
var wave_reach := 1.0
var progress: Dictionary = Progress.empty()   # see progress.gd
var run_log := {}   # the current level attempt: start time, placements, returns to hand
var delta_label: Label3D
var hint_labels: Array[Label3D] = []          # word hints: "drought: 0", "+5 if a tree is here"
var radius_tiles: Array[MeshInstance3D] = []  # highlighted cells within a rule's radius (beehive)
var mark_labels: Array[Label3D] = []
var level_arg := -1               # --level=N
var sandbox_arg := false          # --sandbox
var tool_arg := ""               # --tool=id
var autosolve := false            # --autosolve: the solver places the hand like a player
var season_arg := ""              # --season=winter: open the free garden in this season (no progress check)
var cozy_arg := false             # --cozy: turn on the coziness counter in the free garden
var lang_arg := ""                # --lang=en (or xx — the pseudo-language for finding untranslated strings)
var lang_pick := false
var force_pick := false           # --langpick: show the language choice (first-start screenshot)
var settings_arg := false         # --settings: open the settings screen (screenshot)
# stage 12 — store listing shots (tools/store_shots.py)
var about_arg := false            # --about: open About on top of the settings
var no_toasts := false            # --nocoach: no one-time captions (tips, "New item", toasts) in the frame
var no_ui := false                # --noui: a frame without the interface (feature graphic)
var zoom_arg := 0.0               # --zoom=11: camera scale for the frame (smaller — closer)
var nocard_arg := false           # --nocard: collapse the rules card in the frame
var midplay := false              # --midplay: after --autosolve take one item back to the hand and try it
var resetbar_arg := -1.0          # --resetbar=0.5: the reset window, the bar frozen at this fraction (screenshot; no reset)
var year_arg := ""                # --yearview=autumn: All Year Round — show this season after --autosolve
var explain := false              # --explain: after --autosolve label each item's points

# command-line options (for checks): --shot=path.png --time=0.85 --fresh --seed=7 --nosave
var shot_path := ""
var shot_frames := 0
var forced_time := -1.0
var fresh := false
var new_player := false   # --newplayer: progress as for a new player (the file is not read)
var debug_mouse := Vector2(-1, -1)       # --hover=x,y
var debug_clicks: Array[Vector2] = []    # --click=x,y;x,y
var debug_drawer := false         # --drawer: open "≡" (phone layout screenshot)
var sheet_arg := ""               # --sheet=drawer|help: open that sheet for a screenshot
var yaw_arg := INF                # --yaw=20: the camera's yaw in degrees for a screenshot
var debug_aim := Vector2(-1, -1)          # --aim=x,y: try a cell (touch) on frame 30 — for a screenshot
var debug_rclicks: Array[Vector2] = []   # --rclick=x,y;x,y (right button, on frame 60 — after --autosolve)
var seed_arg := -1


func _ready() -> void:
	randomize()
	_parse_args()
	if shot_path != "":
		seed(20261122)   # the screenshot is reproducible: clouds, butterflies, leaves are the same every run
	touch_mode = touch_mode or touch_arg or OS.has_feature("mobile")
	if touch_mode:
		get_tree().root.content_scale_size = TOUCH_SIZE
		if touch_arg and not OS.has_feature("mobile"):
			Input.emulate_touch_from_mouse = true   # checking on PC: the mouse produces touches
	_setup_env()
	terrain = Terrain.new()
	add_child(terrain)
	items_root = Node3D.new()
	add_child(items_root)
	_setup_camera()
	sfx = Sfx.new()
	add_child(sfx)
	if music_on:
		music = Music.new()
		add_child(music)
	ghost_material = C.ghost_mat(Color(1, 1, 1, 0.5))
	highlight_material = C.ghost_mat(Color(1, 1, 1, 0.35))
	highlight = C.part(self, C.rounded_box(Vector3(0.98, 0.06, 0.98), 0.03, 2), highlight_material)
	highlight.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	highlight.visible = false
	_setup_clouds()
	_setup_fireflies()

	delta_label = _make_label(80)
	for i in 16:
		mark_labels.append(_make_label(56))
	for i in 4:
		var hl := _make_label(40)
		hl.modulate = Color("8a5a2a")
		hint_labels.append(hl)
	var tile_mat := StandardMaterial3D.new()
	tile_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tile_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tile_mat.albedo_color = Color(1.0, 0.78, 0.2, 0.55)
	for i in 16:
		var t := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(0.86, 0.86)
		t.mesh = pm
		t.material_override = tile_mat
		t.visible = false
		add_child(t)
		radius_tiles.append(t)
	_load_progress()
	_load_settings()

	ui = _make_ui()
	add_child(ui)
	ui.setup(self)
	# the free garden serves as the menu background
	_load_sandbox()
	if forced_time >= 0.0:
		day_time = forced_time
	if level_arg >= 0:
		start_level(level_arg)
	elif sandbox_arg:
		enter_sandbox()
	else:
		open_menu()
		if lang_pick or force_pick:
			ui.show_language_picker(_suggested_language())
	if settings_arg or resetbar_arg >= 0.0:
		ui.show_settings()
	if about_arg:
		ui.show_about()
	if resetbar_arg >= 0.0:
		ui.show_reset_confirm()
		ui.hold_frozen = resetbar_arg
	if tool_arg != "" and mode != "menu":
		set_tool(tool_arg)
	if forced_time >= 0.0:
		day_time = forced_time
	_update_day(0.0)


# ================================================================ language (stage 8)

## Settings (stages 8–9): language and volume from settings.json. Language: if there are no settings but there is a garden or
## progress — this is a player of the earlier Russian-only version: Russian; a brand-new player gets the choice screen. --lang= overrides everything.
## A stage 8 file (language only) is read: volumes take their defaults.
func _load_settings() -> void:
	var data = null
	if FileAccess.file_exists(settings_path):
		data = JSON.parse_string(FileAccess.get_file_as_string(settings_path))
	if data is Dictionary:
		var l = data.get("lang", "")
		saved_lang = l if l is String else ""
		vol = parse_volumes(data.get("vol", {}))
		vibrate_on = bool(data.get("vibrate", true)) if data.get("vibrate", true) is bool else true
		var cc = data.get("coach", [])
		if cc is Array:
			for id in cc:
				coach[String(id)] = true
	# The earlier Russian version existed only on PC; on a phone a garden without a language choice is no reason to speak Russian
	var old_player := not OS.has_feature("mobile") and (FileAccess.file_exists(save_path) or FileAccess.file_exists(progress_path))
	var choice := choose_language(saved_lang, old_player, lang_arg, _suggested_language())
	I18n.set_lang(choice[0])
	lang_pick = choice[1] and level_arg < 0 and not sandbox_arg and shot_path == ""
	_apply_volumes()


## Volumes from the file: numbers only, within 0…1, anything missing takes the default.
static func parse_volumes(raw) -> Dictionary:
	var out: Dictionary = VOL_DEFAULT.duplicate()
	if raw is Dictionary:
		for k in out:
			var v = raw.get(k, null)
			if v is float or v is int:
				out[k] = clampf(float(v), 0.0, 1.0)
	return out


func _apply_volumes() -> void:
	for k in vol:
		Sfx.set_volume(k, vol[k], quiet and k == "master")


## Settings slider: audible right away, written 0.5 s after the last change (catches the keyboard too).
func set_volume(bus: String, v: float) -> void:
	vol[bus] = clampf(v, 0.0, 1.0)
	_apply_volumes()
	settings_timer = 0.5


func flush_settings() -> void:
	if settings_timer > 0.0:
		_save_settings()


## The language choice rule at startup (a pure function — tested): [code, whether to show the choice].
## Explicit --lang > saved choice > player of the earlier Russian version (has a garden or progress) > new player: choice.
static func choose_language(saved: String, old_player: bool, arg: String, suggested: String) -> Array:
	if arg != "":
		return [arg, false]
	if saved != "":
		return [saved, false]
	if old_player:
		return ["ru", false]
	return [suggested, true]


## The system language if there is such a dictionary; otherwise English.
func _suggested_language() -> String:
	var sys := OS.get_locale_language()
	return sys if sys in I18n.languages() else I18n.FALLBACK


## Write the whole file to a temporary one and rename: an interrupted write won't corrupt the settings.
func _save_settings() -> void:
	settings_timer = -1.0
	if not save_enabled:
		return
	var data := {"vol": vol, "vibrate": vibrate_on}
	if not coach.is_empty():
		data["coach"] = coach.keys()
	if saved_lang != "":
		data["lang"] = saved_lang
	var tmp := settings_path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(data))
	f.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(settings_path))


## Change the language: the interface is rebuilt entirely and returns to the current mode (no manual list of captions).
## The settings screen and the menu's season tab survive the rebuild (the language carousel changes the language right in the settings).
func set_language(code: String) -> void:
	I18n.set_lang(code)
	lang_pick = false
	saved_lang = code
	_save_settings()
	var old = ui
	var reopen_settings: bool = old.settings.visible
	var season_tab: String = old.menu_season
	ui = _make_ui()
	add_child(ui)
	ui.setup(self)
	old.queue_free()
	ui.menu_season = season_tab
	ui.set_fast(time_fast)
	ui.set_sound(not quiet)
	match mode:
		"menu":
			ui.show_menu(progress)
		"sandbox":
			ui.enter_sandbox_ui()
			ui.set_garden_season(garden_season, garden_seasons().size() > 1)
			_refresh_garden_score()
			ui.select_tool(tool)
		"level":
			ui.enter_level_ui(level_idx, Levels.LEVELS[level_idx], hand)
			_refresh_score()
			ui.select_tool(tool)
	if reopen_settings:
		ui.show_settings()


## Reset campaign progress (stage 9): a copy in progress.bak.json, empty progress (stars, crowns, "seen" —
## novelties are introduced again). The garden, settings and calibration log are untouched. Back to the menu, spring.
func reset_progress() -> void:
	if save_enabled and FileAccess.file_exists(progress_path):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(progress_path),
			ProjectSettings.globalize_path(progress_path.get_basename() + ".bak.json"))
	progress = Progress.empty()
	_save_progress()
	ui.menu_season = ""
	open_menu()
	ui.toast(I18n.t("toast.reset"), 3.5)


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			shot_path = a.substr(7)
		elif a.begins_with("--time="):
			forced_time = float(a.substr(7))
		elif a.begins_with("--seed="):
			seed_arg = int(a.substr(7))
		elif a == "--fresh":
			fresh = true
		elif a == "--newplayer":
			new_player = true
		elif a == "--nosave":
			save_enabled = false
		elif a.begins_with("--hover="):
			var xy := a.substr(8).split(",")
			debug_mouse = Vector2(float(xy[0]), float(xy[1]))
		elif a.begins_with("--click="):
			for pt in a.substr(8).split(";"):
				var xy := pt.split(",")
				debug_clicks.append(Vector2(float(xy[0]), float(xy[1])))
		elif a.begins_with("--rclick="):
			for pt in a.substr(9).split(";"):
				var xy := pt.split(",")
				debug_rclicks.append(Vector2(float(xy[0]), float(xy[1])))
		elif a.begins_with("--tool="):
			tool_arg = a.substr(7)
		elif a.begins_with("--level="):
			level_arg = int(a.substr(8)) - 1
		elif a == "--sandbox":
			sandbox_arg = true
		elif a.begins_with("--lang="):
			lang_arg = a.substr(7)
		elif a.begins_with("--aim="):
			var axy := a.substr(6).split(",")
			debug_aim = Vector2(float(axy[0]), float(axy[1]))
		elif a == "--drawer":
			debug_drawer = true
		elif a.begins_with("--sheet="):
			sheet_arg = a.substr(8)
		elif a.begins_with("--yaw="):
			yaw_arg = float(a.substr(6))
		elif a == "--touch":
			touch_arg = true
		elif a == "--settings":
			settings_arg = true
		elif a == "--about":
			settings_arg = true
			about_arg = true
		elif a == "--nocoach":
			no_toasts = true
		elif a == "--noui":
			no_ui = true
			no_toasts = true
		elif a.begins_with("--zoom="):
			zoom_arg = float(a.substr(7))
		elif a == "--midplay":
			midplay = true
		elif a == "--nocard":
			nocard_arg = true
		elif a.begins_with("--resetbar="):
			resetbar_arg = float(a.substr(11))
		elif a == "--langpick":
			force_pick = true
		elif a.begins_with("--season="):
			season_arg = a.substr(9)
		elif a == "--cozy":
			cozy_arg = true
		elif a.begins_with("--yearview="):
			year_arg = a.substr(11)
		elif a == "--autosolve":
			autosolve = true
		elif a == "--explain":
			explain = true


# ================================================================ scene

func _setup_env() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	env.ssao_enabled = true
	env.ssao_radius = 0.7
	env.ssao_intensity = 1.8
	env.ssil_enabled = true
	env.ssil_intensity = 0.6
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 0.95
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.shadow_blur = 1.4
	sun.light_angular_distance = 1.2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 70.0
	add_child(sun)


func _setup_camera() -> void:
	pivot = Node3D.new()
	pivot.position = Vector3(0, 1.0, 0)
	pivot.rotation.y = yaw_target
	add_child(pivot)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = zoom_target
	cam.near = 0.5
	cam.far = 120.0
	cam.rotation.x = deg_to_rad(-35.0)
	pivot.add_child(cam)
	cam.position = cam.transform.basis.z * 35.0
	cam.current = true


func _cloud(parent: Node3D, rng: RandomNumberGenerator, k: float) -> Node3D:
	var cl := Node3D.new()
	parent.add_child(cl)
	var white := C.mat(Color("f8f8fc"), 0.9)
	for i in rng.randi_range(4, 6):
		var r := rng.randf_range(0.45, 0.9) * k
		C.part(cl, C.sphere(r), white, Vector3((i - 2.5) * 0.55 * k, rng.randf_range(0.0, 0.3) * k, rng.randf_range(-0.35, 0.35) * k), Vector3(1, 0.8, 1))
	return cl


func _setup_clouds() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	# high clouds are visible only as shadows crawling over the garden
	for i in 4:
		var cl := _cloud(self, rng, 1.6)
		cl.position = Vector3(-16.0 + i * 9.0, 9.0, rng.randf_range(-6.0, 6.0))
		for ch in cl.get_children():
			(ch as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		shadow_clouds.append(cl)
	# a ring of clouds under the floating island
	cloud_ring = Node3D.new()
	add_child(cloud_ring)
	for i in 9:
		var a := TAU * i / 9.0 + rng.randf() * 0.4
		var cl := _cloud(cloud_ring, rng, rng.randf_range(0.8, 1.3))
		var r := rng.randf_range(8.5, 11.5)
		cl.position = Vector3(cos(a) * r, rng.randf_range(-4.5, -2.0), sin(a) * r)
		cl.rotation.y = -a
		for ch in cl.get_children():
			(ch as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _setup_fireflies() -> void:
	fireflies = GPUParticles3D.new()
	fireflies.amount = 70
	fireflies.lifetime = 7.0
	fireflies.preprocess = 7.0
	fireflies.position = Vector3(0, 2.4, 0)
	fireflies.visibility_aabb = AABB(Vector3(-10, -4, -10), Vector3(20, 8, 20))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(5.5, 0.9, 5.5)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.2
	pm.gravity = Vector3(0, 0.02, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.2
	pm.turbulence_noise_scale = 3.0
	pm.turbulence_influence_min = 0.04
	pm.turbulence_influence_max = 0.12
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.0))
	curve.add_point(Vector2(0.2, 1.0))
	curve.add_point(Vector2(0.8, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	fireflies.process_material = pm
	var m := SphereMesh.new()
	m.radius = 0.035
	m.height = 0.07
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.albedo_color = Color(1.0, 0.95, 0.55)
	fm.emission_enabled = true
	fm.emission = Color(0.85, 1.0, 0.4)
	fm.emission_energy_multiplier = 5.0
	m.material = fm
	fireflies.draw_pass_1 = m
	fireflies.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fireflies)


# ================================================================ island

func new_island(seed_value: int = -1) -> void:
	if seed_value < 0:
		seed_value = randi() % 100000
	for c in items:
		items[c]["node"].queue_free()
	items.clear()
	island_seed = seed_value
	undo_stack.clear()
	_stop_wave()
	terrain.season = garden_season
	terrain.dry = {}
	terrain.snow_cells = {}
	terrain.generate(seed_value)
	terrain.build_all()
	_decorate(seed_value)
	_mark_dirty()


func _clear_items() -> void:
	for c in items:
		items[c]["node"].queue_free()
	items.clear()


func _flush_save() -> void:
	if save_timer > 0.0:
		_save()
	save_timer = -1.0


func _load_sandbox() -> void:
	undo_stack.clear()
	_stop_wave()
	_clear_items()
	var loaded := false
	if not fresh:
		loaded = _load()
	if not loaded:
		if season_arg != "":
			garden_season = season_arg
		new_island(seed_arg if seed_arg >= 0 else randi() % 100000)
	if cozy_arg:
		garden_cozy = true
	sandbox_ready = true
	pivot.position = Vector3(0, 1.0, 0)
	zoom_target = 15.0 if touch_mode else 13.0


# ================================================================ modes

func open_menu() -> void:
	_flush_save()
	result_wait = -1.0
	result_args = []
	yaw_vel = 0.0
	mode = "menu"
	_set_aim(NO_CELL)
	painting = 0
	_hide_preview()
	if ghost:
		ghost.visible = false
	highlight.visible = false
	if season_arg != "" and ui.menu_season == "":
		ui.menu_season = season_arg   # --season=summer in the menu: open that tab (a screenshot of a locked season)
	ui.show_menu(progress)
	if music:
		music.set_duck(false)


func enter_sandbox() -> void:
	if not sandbox_ready:
		_load_sandbox()
	mode = "sandbox"
	if music:
		music.set_duck(false)
	ui.enter_sandbox_ui()
	ui.set_garden_season(garden_season, garden_seasons().size() > 1)
	_refresh_garden_score()
	tool = ""
	set_tool("tree")
	_set_aim(NO_CELL)
	# after a progress reset the garden's season may be locked: the garden data is intact, the look goes to summer in a wave
	if season_arg == "" and not garden_season in garden_seasons():
		set_garden_season("summer")
		ui.toast(I18n.t("toast.garden_locked"), 4.5)
	elif pond_note:
		pond_note = false
		ui.toast(I18n.t("toast.pond_settled"), 4.0)
	elif touch_mode and not coach.has("sandbox"):
		_coach("sandbox")
	else:
		ui.toast(I18n.t("toast.sandbox"), 2.5)


func start_level(i: int) -> void:
	i = clampi(i, 0, Levels.LEVELS.size() - 1)
	_flush_save()
	mode = "level"
	_set_aim(NO_CELL)
	undo_stack.clear()
	result_wait = -1.0
	result_args = []
	yaw_vel = 0.0
	if music:
		music.set_duck(true)
	level_idx = i
	sandbox_ready = false
	painting = 0
	var L: Dictionary = Levels.LEVELS[i]
	_stop_wave()
	_clear_items()
	year_view = "winter"   # All Year Round opens in winter — the chapter's season; Tab and the buttons show other seasons
	terrain.season = _season()
	var lb = Scoring.Board.for_level(L)
	terrain.dry = lb.dry
	terrain.snow_cells = lb.snow
	var m := terrain.load_map(L["map"])
	var off: Vector2i = m["off"]
	var size: Vector2i = m["size"]
	var fixed_rng := RandomNumberGenerator.new()
	fixed_rng.seed = int(L["slot"]) * 101   # the look of fixed items doesn't depend on level order
	for f in L.get("fixed", []):
		_place_item(off + Vector2i(f[0], f[1]), f[2], fixed_rng.randi(), 0, false, true)
	hand = (L["hand"] as Dictionary).duplicate()
	day_time = float(L.get("time", 0.42))
	time_fast = false
	ui.set_fast(false)
	# camera — on the island's center
	var mid := terrain.cell_center(off) + Vector3(size.x - 1, 0, size.y - 1) * 0.5
	pivot.position = Vector3(mid.x, 1.0, mid.z)
	zoom_target = clampf(maxf(size.x, size.y) * 1.25 + 3.5, 8.0, 15.0)
	if touch_mode:
		zoom_target *= 1.05   # on a phone the dock at the bottom is taller — the island a bit farther
	yaw_target = YAW_BASE + roundf((yaw_target - YAW_BASE) / YAW_STEP) * YAW_STEP
	ui.enter_level_ui(i, L, hand)
	run_log = {"start": Time.get_ticks_msec(), "placed": 0, "returned": 0}
	tool = ""
	set_tool(_first_in_hand())
	_refresh_score()
	_introduce_new_items()


## Items unlocked up to the current campaign slot (in the free garden — all).
func known_items() -> Array:
	if mode == "level" and level_idx >= 0:
		return Campaign.items_at(int(Levels.LEVELS[level_idx]["slot"]))
	return []


## Mechanics with their own intro banner (text — mech.<id> in the language dictionary).
const MECH_INTRO := ["winter", "snow", "drought", "line", "leaf_fall"]


## Mechanics in effect on this level (for the intro).
func _level_mechs() -> Array:
	var out := []
	if mode != "level" or level_idx < 0:
		return out
	var L: Dictionary = Levels.LEVELS[level_idx]
	if L.get("drought", false):
		out.append("drought")
	var fl := Campaign.flags_for(L)
	if "winter" in fl:
		out.append("winter")
	if not L.get("snow", []).is_empty():
		out.append("snow")
	if "line" in fl and hand.has("fence"):
		out.append("line")
	if "leaf_fall" in fl and (hand.has("pumpkin") or hand.has("tree")):
		out.append("leaf_fall")
	# introduce the mechanic the slot was made for first (falling leaves at 61 — before the row)
	var here := []
	for u in Campaign.novelties(int(L["slot"])):
		here.append(u["id"])
	out.sort_custom(func(a, b): return (a in here) and not (b in here))
	return out


## Introducing a novelty: on the player's first meeting with an item or mechanic — a banner and the rules card.
func _introduce_new_items() -> void:
	for m in _level_mechs():
		if Progress.seen(progress, "mech:" + m):
			continue
		Progress.mark_seen(progress, "mech:" + m)
		_save_progress()
		ui.toast(I18n.t("mech." + m), 8.0)
		return
	for id in hand:
		if Progress.seen(progress, id):
			continue
		Progress.mark_seen(progress, id)
		_save_progress()
		set_tool(id)
		var fans := []
		var known := known_items()
		for other in Scoring.RULES:
			if not other in known:
				continue
			for r in Scoring.RULES[other]:
				if r.get("of", "") is String and r.get("of", "") == id and int(r.get("v", 0)) > 0 and other != id:
					fans.append(Scoring.noun(other))
		var line := I18n.t("toast.new_item", {"item": I18n.t("item." + id)})
		if not fans.is_empty():
			line += I18n.t("toast.new_item_fans", {"list": I18n.t("list.sep").join(fans)})
		ui.toast(line, 7.0)
		ui.highlight_tool(id)
		return


func restart_level() -> void:
	if mode == "level":
		start_level(level_idx)


func next_level() -> void:
	var j := Progress.next_unlocked(level_idx, progress)
	if j >= 0:
		start_level(j)
	else:
		open_menu()


func _first_in_hand() -> String:
	for id in all_tools():
		if int(hand.get(id, 0)) > 0:
			return id
	return ""


## The season for the palette and scoring: the level's season, in the free garden — summer (the season switch is stage 7).
## On All Year Round — the season the player is looking at (the score doesn't depend on the view: always the sum of seasons).
func _season() -> String:
	if _is_year():
		return year_view
	if mode == "level" and level_idx >= 0:
		return Levels.LEVELS[level_idx].get("season", "summer")
	return garden_season


## The board for scoring coziness: what stands now and the island's terrain.
func _board(ids: Dictionary = {}) -> Scoring.Board:
	var its := ids if not ids.is_empty() else _ids()
	if mode == "level" and level_idx >= 0:
		return Scoring.Board.make(its, terrain.heights, terrain.water, Levels.LEVELS[level_idx])
	return Scoring.Board.for_sandbox(its, terrain.heights, terrain.water, garden_season, Progress.reached(progress))


# ================================================================ free garden seasons (stage 7)

## Seasons unlocked for the player's free garden (by campaign progress).
func garden_seasons() -> Array:
	return Campaign.sandbox_seasons(Progress.reached(progress))


func cycle_garden_season() -> void:
	if mode != "sandbox":
		return
	var opts := garden_seasons()
	if opts.size() < 2:
		return
	set_garden_season(opts[(opts.find(garden_season) + 1) % opts.size()])


func set_garden_season(s: String) -> void:
	if s == garden_season and wave_t < 0.0:
		return
	garden_season = s
	_start_wave()
	ui.set_garden_season(s, garden_seasons().size() > 1)
	_mark_dirty()
	if hover_cell != NO_CELL:
		_update_preview(hover_cell)


func toggle_cozy() -> void:
	garden_cozy = not garden_cozy
	_mark_dirty()
	if hover_cell != NO_CELL:
		_update_preview(hover_cell)
	else:
		_hide_preview()


func _refresh_garden_score() -> void:
	if ui:
		ui.set_garden_score(garden_cozy, Scoring.total(_board()) if garden_cozy else 0, garden_season)


## The wave: cells and items are re-dressed into the _season() season from the island's center to its edges.
## Changing again during a wave instantly finishes the current one and starts a new one — nodes don't pile up.
func _start_wave() -> void:
	if wave_t >= 0.0:
		_finish_wave()
	terrain.season = _season()
	wave_done = {}
	var sum := Vector2.ZERO
	for c in terrain.heights:
		sum += Vector2(c)
	wave_center = sum / maxf(1.0, terrain.heights.size())
	wave_reach = 0.5
	for c in terrain.heights:
		wave_reach = maxf(wave_reach, Vector2(c).distance_to(wave_center) + 0.5)
	wave_t = 0.0


func _step_wave(dt: float) -> void:
	if wave_t < 0.0:
		return
	wave_t += dt
	var r := wave_t / WAVE_TIME * wave_reach
	for c in terrain.heights.keys():
		if not wave_done.has(c) and Vector2(c).distance_to(wave_center) <= r:
			_redress(c, true)
	if wave_t >= WAVE_TIME:
		_finish_wave()


func _finish_wave() -> void:
	for c in terrain.heights.keys():
		if not wave_done.has(c):
			_redress(c, false)
	_stop_wave()


func _stop_wave() -> void:
	wave_t = -1.0
	wave_done = {}


## Re-dress a cell: rebuild its look and the look of the item on it (the items[c] record stays — node and sway change).
func _redress(c: Vector2i, animate: bool) -> void:
	wave_done[c] = true
	terrain.build_cell(c, animate)
	if not items.has(c):
		return
	var it: Dictionary = items[c]
	var old: Node3D = it["node"]
	var node := Items.build(it["id"], it["seed"], _season(), _leaf_fall())
	items_root.add_child(node)
	node.position = old.position
	node.rotation.y = int(it["rot"]) * PI * 0.5
	it["node"] = node
	it["sway"] = node.get_node("Sway")
	old.queue_free()
	if animate:
		node.scale = Vector3(1.25, 0.4, 1.25)
		var tw := node.create_tween()
		tw.tween_property(node, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _ids() -> Dictionary:
	var out := {}
	for c in items:
		out[c] = items[c]["id"]
	return out


func _stars_for(score: int) -> int:
	var n := 0
	for th in Levels.LEVELS[level_idx]["stars"]:
		if score >= int(th):
			n += 1
	return n


func _refresh_score() -> void:
	var b := _board()
	level_score = Scoring.total(b)
	ui.set_score(level_score, _stars_for(level_score))
	if not b.subs.is_empty():
		var parts := {}
		for sb in b.subs:
			parts[sb.season] = Scoring.total(sb)
		ui.set_year(parts, year_view)


func _hand_empty() -> bool:
	for id in hand:
		if int(hand[id]) > 0:
			return false
	return true


func _level_complete() -> void:
	var L: Dictionary = Levels.LEVELS[level_idx]
	var stars := _stars_for(level_score)
	if autosolve:
		print("LEVEL_DONE %d score=%d stars=%d id=%s slot=%d" % [level_idx + 1, level_score, stars, L["id"], L["slot"]])
	var key: String = L["id"]
	var old: Dictionary = Progress.entry(progress, key)
	var record: bool = level_score > int(old.get("best", 0)) and old.has("best") and int(old.get("best", 0)) > 0
	var crown: bool = bool(old.get("crown", false)) or level_score >= int(L["perfect"])
	var open_before := Progress.open_chapters(progress)
	progress["levels"][key] = {"stars": maxi(stars, int(old.get("stars", 0))), "best": maxi(level_score, int(old.get("best", 0))), "crown": crown}
	_save_progress()
	if not autosolve:
		_log_run(L, stars)
	if stars > 0:
		sfx.play("chirp", 1.0, -4.0)
	else:
		sfx.play("nope", 1.0, -6.0)
	result_args = [stars, level_score, L, record, Progress.next_unlocked(level_idx, progress) >= 0, _unlock_note(L, open_before)]
	result_wait = 0.0 if autosolve else result_delay
	if result_wait <= 0.0:
		_show_pending_result()


func _show_pending_result() -> void:
	result_wait = -1.0
	if mode != "level" or result_args.is_empty():
		return
	var a := result_args
	result_args = []
	ui.show_result(a[0], a[1], a[2], a[3], a[4], a[5])


## A result line about unlocking (stage 13): a new season or chapter has just opened; otherwise, while the next chapter
## is closed, how many stars this chapter has toward it.
func _unlock_note(L: Dictionary, open_before: Dictionary) -> String:
	var open := Progress.open_chapters(progress)
	var by_ch := Progress.chapters()
	var keys := by_ch.keys()
	keys.sort()
	for c in keys:
		if open.has(c) and not open_before.has(c):
			var season: String = Levels.LEVELS[Levels.index_of(by_ch[c][0])]["season"]
			if not Progress.season_open(season, progress, open_before):
				return I18n.t("ui.result.season_open", {"season": I18n.t("season." + season)})
			return I18n.t("ui.result.chapter_open", {"chapter": I18n.t("chapter.%d" % c)})
	var ch := Progress.chapter_of(L)
	var i := keys.find(ch)
	if i < 0 or i + 1 >= keys.size() or open.has(keys[i + 1]):
		return ""
	return I18n.t("ui.result.chapter_stars", {"chapter": I18n.t("chapter.%d" % ch),
		"n": Progress.chapter_stars(progress, by_ch[ch]), "need": Progress.chapter_need(by_ch[ch])})


## Play log: every level completion (empty hand) is a line with the time since the attempt started,
## the number of placements and returns to hand. Needed to calibrate the difficulty metric with real play.
func _log_run(L: Dictionary, stars: int) -> void:
	if not save_enabled:
		return
	var entries := []
	if FileAccess.file_exists(playlog_path):
		var old = JSON.parse_string(FileAccess.get_file_as_string(playlog_path))
		if old is Array:
			entries = old
	entries.append({"id": L["id"], "slot": L["slot"], "sec": snappedf((Time.get_ticks_msec() - int(run_log.get("start", 0))) / 1000.0, 0.1),
		"placed": run_log.get("placed", 0), "returned": run_log.get("returned", 0), "score": level_score,
		"stars": stars, "perfect": L["perfect"], "when": Time.get_datetime_string_from_system()})
	var f := FileAccess.open(playlog_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(entries))
		f.close()


func _load_progress() -> void:
	if new_player:
		progress = Progress.empty()
		return
	if not FileAccess.file_exists(progress_path):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(progress_path))
	var was_old: bool = data is Dictionary and int(data.get("v", 1)) < Progress.VERSION
	progress = Progress.migrate(data)
	if was_old:
		_save_progress()   # the old format (by level number) is migrated once


func _save_progress() -> void:
	if not save_enabled:
		return
	var f := FileAccess.open(progress_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(progress))
		f.close()


func _make_label(font_px: int) -> Label3D:
	var l := Label3D.new()
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.pixel_size = 0.005
	l.font_size = font_px
	l.outline_size = 18
	l.outline_modulate = Color("fff7ea")
	l.render_priority = 10
	l.outline_render_priority = 9
	l.visible = false
	add_child(l)
	return l


func _set_label(l: Label3D, v: int, pos: Vector3) -> void:
	l.text = "%+d" % v if v != 0 else "0"
	l.modulate = Color("3f8f3a") if v > 0 else (Color("d0503f") if v < 0 else Color("8a7a6a"))
	l.position = pos
	l.visible = true


func _hide_preview() -> void:
	delta_label.visible = false
	for l in mark_labels:
		l.visible = false
	for l in hint_labels:
		l.visible = false
	for t in radius_tiles:
		t.visible = false


func _hint(i: int, text: String, pos: Vector3) -> void:
	if i >= hint_labels.size():
		return
	hint_labels[i].text = text
	hint_labels[i].position = pos
	hint_labels[i].visible = true


## The hammock goes along the axis with supports on both sides (if there is one); otherwise as the player rotated it.
func _hammock_axis(c: Vector2i, rot: int) -> int:
	var ids := _ids()
	var ok := func(n): return ids.get(n, "") in ["tree", "pine"]
	if ok.call(c + Vector2i(1, 0)) and ok.call(c - Vector2i(1, 0)):
		return 0
	if ok.call(c + Vector2i(0, 1)) and ok.call(c - Vector2i(0, 1)):
		return 1
	return rot


func _leaf_fall() -> bool:
	if _is_year():
		return year_view == "autumn"
	if mode == "level" and level_idx >= 0:
		return "leaf_fall" in Campaign.flags_for(Levels.LEVELS[level_idx])
	return garden_season == "autumn"   # free garden: leaves lie on the ground in autumn (the look; the rule follows progress)


func _is_year() -> bool:
	return mode == "level" and level_idx >= 0 and Campaign.is_year(Levels.LEVELS[level_idx])


## All Year Round: show the island in another season — redraw the terrain and items (the arrangement is the same).
func set_year_view(s: String) -> void:
	if not _is_year():
		return
	year_view = s
	_start_wave()
	_refresh_score()
	if hover_cell != NO_CELL:
		_update_preview(hover_cell)


func level_snow() -> bool:
	return mode == "level" and level_idx >= 0 and not Levels.LEVELS[level_idx].get("snow", []).is_empty()


## Campaign flags of the current level (for the rules card).
func level_flags() -> Array:
	if mode == "level" and level_idx >= 0:
		return Campaign.flags_for(Levels.LEVELS[level_idx])
	return []


## A level with a drought (for the rules card).
func level_drought() -> bool:
	return mode == "level" and level_idx >= 0 and bool(Levels.LEVELS[level_idx].get("drought", false))


## Score hint: how much the item gives here and what its neighbors get.
func _update_preview(c: Vector2i) -> void:
	_hide_preview()
	var cozy_on := mode == "sandbox" and garden_cozy and not tool in TERRAIN_TOOLS
	if not (mode == "level" or cozy_on) or not ghost or not ghost.visible:
		return
	var p := Scoring.preview(tool, c, _board())
	_set_label(delta_label, p["delta"], terrain.cell_center(c) + Vector3(0, terrain.surface_y(c) + 1.7, 0))
	var k := 0
	var marks: Dictionary = p["marks"]
	for n in marks:
		if k >= mark_labels.size():
			break
		var y := terrain.surface_y(n) + 0.45 if terrain.has_land(n) else 0.5
		_set_label(mark_labels[k], marks[n], terrain.cell_center(n) + Vector3(0, y, 0))
		mark_labels[k].font_size = 56
		k += 1
	# the honesty rule: invisible reasons for points are shown in words and with highlighting
	var b := _board()
	var r := Scoring.compiled(tool, b)
	var hi := 0
	var ti := 0
	if r["thirst"] and b.dry.has(c):
		_hint(hi, I18n.t("hint.drought"), terrain.cell_center(c) + Vector3(0, terrain.surface_y(c) + 1.25, 0))
		hi += 1
	if b.snow.has(c) and not tool in Scoring.NO_FREEZE and not Scoring.warm_at(c, b.items):
		_hint(hi, I18n.t("hint.cold"), terrain.cell_center(c) + Vector3(0, terrain.surface_y(c) + 1.25, 0))
		hi += 1
	if not b.snow.is_empty() and tool in Scoring.WARMTH:
		# warmth diamond: which snowdrifts the source warms
		for o in Scoring._warm_offs:
			var n: Vector2i = c + o
			if ti < radius_tiles.size() and terrain.heights.has(n):
				radius_tiles[ti].position = terrain.cell_center(n) + Vector3(0, terrain.surface_y(n) + 0.07, 0)
				radius_tiles[ti].visible = true
				ti += 1
	for nr in r["near"]:
		for o in nr[1]:
			var n: Vector2i = c + o
			if ti < radius_tiles.size() and terrain.heights.has(n):
				radius_tiles[ti].position = terrain.cell_center(n) + Vector3(0, terrain.surface_y(n) + 0.07, 0)
				radius_tiles[ti].visible = true
				ti += 1
	for bt in r["between"]:
		var set: Dictionary = bt[0]
		for d in [Vector2i(1, 0), Vector2i(0, 1)]:
			var a: Vector2i = c + d
			var z: Vector2i = c - d
			var ha: bool = set.has(b.items.get(a, ""))
			var hz: bool = set.has(b.items.get(z, ""))
			if ha != hz:
				var miss: Vector2i = z if ha else a
				if terrain.heights.has(miss) and not b.items.has(miss) and not terrain.is_water(miss):
					_hint(hi, I18n.t("hint.between", {"v": I18n.signed(int(bt[1]))}), terrain.cell_center(miss) + Vector3(0, terrain.surface_y(miss) + 0.9, 0))
					hi += 1
	var ln: Array = r["line"]
	if not ln.is_empty():
		# a row of fences: how many in a row together with this one
		for d in [Vector2i(1, 0), Vector2i(0, 1)]:
			var run := 1
			for side in [d, -d]:
				var n: Vector2i = c + side
				while b.items.get(n, "") == tool:
					run += 1
					n += side
			if run >= int(ln[0]):
				_hint(hi, I18n.t("hint.line", {"n": run, "v": I18n.signed(int(ln[1]))}), terrain.cell_center(c) + Vector3(0, terrain.surface_y(c) + 1.25, 0))
				hi += 1
				break
	for cp in r["cap"]:
		var cset: Dictionary = cp[0]
		var cnt := 0
		for d in Scoring.DIRS:
			if cset.has(b.items.get(c + d, "")):
				cnt += 1
		if cnt > int(cp[1]):
			_hint(hi, I18n.t("hint.cap", {"max": int(cp[1]), "n": cnt}), terrain.cell_center(c) + Vector3(0, terrain.surface_y(c) + 1.25, 0))
			hi += 1


func _float_points(v: int, pos: Vector3) -> void:
	var l := _make_label(90)
	_set_label(l, v, pos)
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", pos.y + 1.0, 1.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 1.1).set_delay(0.3)
	tw.tween_property(l, "outline_modulate:a", 0.0, 1.1).set_delay(0.3)
	tw.chain().tween_callback(l.queue_free)


## Starting decoration, so the island isn't empty.
func _decorate(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 31 + 5
	var land: Array[Vector2i] = []
	var wet: Array[Vector2i] = []
	for c in terrain.heights:
		if terrain.is_water(c):
			wet.append(c)
		else:
			land.append(c)
	for i in range(land.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := land[i]
		land[i] = land[j]
		land[j] = tmp
	var plan := {"tree": 5, "pine": 4, "bush": 4, "flowers": 6, "rock": 3, "mushroom": 2, "pumpkin": 1, "lantern": 2}
	var k := 0
	for id in plan:
		for n in plan[id]:
			if k >= land.size():
				break
			_place_item(land[k], id, rng.randi(), 0, false)
			k += 1
	for i in mini(2, wet.size()):
		_place_item(wet[rng.randi() % wet.size()], "lily", rng.randi(), 0, false)


func _place_item(c: Vector2i, id: String, seed_value: int, rot: int, animate: bool, fixed: bool = false) -> void:
	if items.has(c):
		return
	var node := Items.build(id, seed_value, _season(), _leaf_fall())
	items_root.add_child(node)
	node.position = terrain.cell_center(c) + Vector3(0, terrain.surface_y(c), 0)
	node.rotation.y = rot * PI * 0.5
	items[c] = {
		"id": id, "seed": seed_value, "rot": rot, "node": node,
		"sway": node.get_node("Sway"), "amp": Items.info(id).get("sway", 0.0),
		"phase": randf() * TAU, "fixed": fixed,
	}
	if animate:
		node.scale = Vector3(1.35, 0.2, 1.35)
		var tw := node.create_tween()
		tw.tween_property(node, "scale", Vector3(0.85, 1.2, 0.85), 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(node, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		sfx.play("splash" if id == "lily" else "plop", 1.0, -4.0)
		_crumbs(node.position + Vector3(0, 0.05, 0), Color("8acb6c") if id != "lily" else Color("9fd8ef"), 7)


func _remove_item(c: Vector2i) -> void:
	if not items.has(c):
		return
	var node: Node3D = items[c]["node"]
	items.erase(c)
	var tw := node.create_tween()
	tw.tween_property(node, "scale", Vector3(1.3, 0.3, 1.3), 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(node, "scale", Vector3(0.01, 0.01, 0.01), 0.08)
	tw.tween_callback(node.queue_free)
	sfx.play("pop", 1.0, -6.0)
	_crumbs(node.position + Vector3(0, 0.1, 0), Color("ad7752"), 6)


## After terrain edits: the item moves with the height or disappears if it doesn't belong there.
## Stage 15 (D3): after a terrain edit water finds its level; every moved cell is rebuilt and its item follows it.
## The first time an edit moves water, a one-time toast says why.
func _settle_terrain() -> void:
	var moved: Array = terrain.settle()
	for m in moved:
		terrain.build_cell(m, true)
		_after_terrain(m)
	if not moved.is_empty() and not coach.has("water_level"):
		coach["water_level"] = true
		settings_timer = 0.5
		ui.toast(I18n.t("toast.water_level"), 4.0)


func _after_terrain(c: Vector2i) -> void:
	if not items.has(c):
		return
	var it: Dictionary = items[c]
	if not _board().can_place(it["id"], c):   # the single placement rule (Board)
		_remove_item(c)
	else:
		var node: Node3D = it["node"]
		node.position.y = terrain.surface_y(c)


# ================================================================ tools

func set_tool(id: String) -> void:
	if id == tool or id == "":
		return
	if mode == "level" and not hand.has(id):
		return
	tool = id
	ui.select_tool(id)
	sfx.play("tick", 1.0, -10.0)
	ghost_seed = randi()
	_rebuild_ghost()


## Tools in the order of keys 1…0: on a level — only what is in the hand.
func all_tools() -> Array:
	var out := []
	for d in Items.CATALOG:
		if mode != "level" or hand.has(d["id"]):
			out.append(d["id"])
	if mode != "level":
		out.append_array(TERRAIN_TOOLS)
	return out


func toggle_fast() -> void:
	time_fast = not time_fast
	ui.set_fast(time_fast)
	sfx.play("tick", 1.2, -10.0)


## The quick "quiet" right in the game: mutes the master bus, doesn't touch the settings volumes.
func toggle_sound() -> void:
	quiet = not quiet
	_apply_volumes()
	ui.set_sound(not quiet)


func _rebuild_ghost() -> void:
	if ghost:
		ghost.queue_free()
		ghost = null
	if tool in TERRAIN_TOOLS or tool == "":
		return
	ghost = Items.build(tool, ghost_seed, _season(), _leaf_fall())
	_ghostify(ghost)
	add_child(ghost)
	ghost.rotation.y = ghost_rot * PI * 0.5 if Items.info(tool).get("rotatable", false) else 0.0
	ghost.visible = false


func _ghostify(n: Node) -> void:
	for ch in n.get_children():
		if ch is Light3D:
			ch.visible = false
		elif ch is GeometryInstance3D:
			ch.material_override = ghost_material
			ch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_ghostify(ch)


func _is_valid(c: Vector2i) -> bool:
	if c == NO_CELL or tool == "":
		return false
	if mode == "level" and (tool in TERRAIN_TOOLS or int(hand.get(tool, 0)) <= 0):
		return false
	match tool:
		"raise":
			return terrain.in_grid(c) and terrain.heights.get(c, 0) < Terrain.MAX_H
		"lower", "water":
			return terrain.has_land(c)
		"remove":
			return items.has(c)
	if not terrain.has_land(c) or items.has(c):
		return false
	return _board().can_place(tool, c)   # the single placement rule (Board)


## The action on the cell under the cursor (or the tried cell) + a record for undo: the cell's state before and after.
func _apply(button: int) -> void:
	var c := hover_cell
	var before := _cell_state(c) if c != NO_CELL else {}
	# stage 15 (D4): a terrain edit may move a whole pond — snapshot the terrain, keep the other changed cells in the entry
	var land0: Dictionary = terrain.heights.duplicate() if mode == "sandbox" else {}
	var wet0: Dictionary = terrain.water.duplicate() if mode == "sandbox" else {}
	_apply_inner(button)
	if c != NO_CELL:
		_push_undo(c, before, _terrain_diff(land0, wet0, c) if mode == "sandbox" else {})


## The cells (other than the edited one) whose terrain an edit changed, with their state before it.
func _terrain_diff(land0: Dictionary, wet0: Dictionary, c: Vector2i) -> Dictionary:
	var out := {}
	for x in land0.keys() + terrain.heights.keys():
		if x == c or out.has(x):
			continue
		if int(land0.get(x, 0)) != int(terrain.heights.get(x, 0)) or wet0.has(x) != terrain.water.has(x):
			out[x] = {"h": int(land0.get(x, 0)), "w": wet0.has(x), "b": float(terrain.bottoms.get(x, -1.0))}
	return out


func _apply_inner(button: int) -> void:
	var c := hover_cell
	if mode == "menu":
		return
	if mode == "level":
		_apply_level(button, c)
		return
	if button == 2:
		if items.has(c):
			_remove_item(c)
			_mark_dirty()
		return
	if not _is_valid(c):
		if c != NO_CELL and painting == 0:
			sfx.play("nope", 1.0, -10.0)
		return
	match tool:
		"raise":
			if terrain.is_water(c):
				# stage 15 (D3): the whole pond rises — only when all the land around it is at least that high
				if not terrain.raise_pond(c).is_empty():
					sfx.play("nope", 1.0, -10.0)
					ui.toast(I18n.t("toast.pond_low"), 3.0)
					return
				for w in Terrain.pond_cells(c, terrain.heights, terrain.water):
					_after_terrain(w)
				sfx.play("splash", 1.1, -6.0)
			else:
				terrain.raise(c)
				_after_terrain(c)
				sfx.play("dig", 1.15, -6.0)
			_crumbs(terrain.cell_center(c) + Vector3(0, terrain.top_y(c), 0), Color("ad7752"), 6)
			_settle_terrain()
		"lower":
			terrain.lower(c)
			_after_terrain(c)
			sfx.play("dig", 0.85, -6.0)
			_crumbs(terrain.cell_center(c) + Vector3(0, terrain.top_y(c), 0), Color("ad7752"), 6)
			_settle_terrain()
		"water":
			terrain.toggle_water(c)
			_after_terrain(c)
			sfx.play("splash" if terrain.is_water(c) else "dig", 1.0, -6.0)
			_settle_terrain()
		"remove":
			_remove_item(c)
		_:
			_place_item(c, tool, ghost_seed, ghost_rot if Items.info(tool).get("rotatable", false) else 0, true)
			ghost_seed = randi()
			_rebuild_ghost()
	_mark_dirty()


func _apply_level(button: int, c: Vector2i) -> void:
	if button == 2:
		if not items.has(c):
			return
		if items[c]["fixed"]:
			if painting == 0:
				sfx.play("nope", 1.0, -10.0)
				ui.toast(I18n.t("toast.fixed"), 2.0)
			return
		var id: String = items[c]["id"]
		_remove_item(c)
		run_log["returned"] = int(run_log.get("returned", 0)) + 1
		hand[id] = int(hand.get(id, 0)) + 1
		ui.update_hand(hand)
		if int(hand.get(tool, 0)) <= 0:
			set_tool(id)
		_refresh_score()
		return
	if not _is_valid(c):
		if c != NO_CELL and painting == 0:
			sfx.play("nope", 1.0, -10.0)
		return
	var gain: int = Scoring.preview(tool, c, _board())["delta"]
	var rot := ghost_rot if Items.info(tool).get("rotatable", false) else 0
	if tool == "hammock":
		rot = _hammock_axis(c, rot)
	_place_item(c, tool, ghost_seed, rot, true)
	run_log["placed"] = int(run_log.get("placed", 0)) + 1
	_float_points(gain, terrain.cell_center(c) + Vector3(0, terrain.surface_y(c) + 1.4, 0))
	hand[tool] = int(hand[tool]) - 1
	ui.update_hand(hand)
	_refresh_score()
	if int(hand[tool]) <= 0:
		var nxt := _first_in_hand()
		if nxt != "":
			set_tool(nxt)
	ghost_seed = randi()
	_rebuild_ghost()
	if _hand_empty():
		painting = 0
		_hide_preview()
		_level_complete()


## Debugging: the solver finds an arrangement, and it is placed with ordinary "clicks".
func _autosolve() -> void:
	var fixed := {}
	for c in items:
		if items[c]["fixed"]:
			fixed[c] = items[c]["id"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var res := Scoring.solve(Levels.LEVELS[level_idx], terrain.heights, terrain.water, fixed, 40000, 2, rng)
	var placed: Dictionary = res["items"]
	for c in placed:
		if fixed.has(c):
			continue
		set_tool(placed[c])
		hover_cell = c
		_apply_level(1, c)
	if year_arg != "":
		ui.hide_result()
		set_year_view(year_arg)
		_finish_wave()   # screenshot — the final look, not the middle of the wave
	if explain:
		_explain_layout()


## Store shot "level in progress": the result is hidden, the most valuable placed item returns to the hand and
## is tried on its own cell — the "+N", the neighbors and an almost full row of stars are visible.
func _midplay() -> void:
	ui.hide_result()
	var best := Vector2i(-1, -1)
	var best_gain := -999
	var low := Vector2i(-1, -1)
	var low_gain := 9999
	var two: int = int(Levels.LEVELS[level_idx]["stars"][1])
	for c in items.keys():
		if items[c]["fixed"]:
			continue
		var kept = items[c]   # the gain — on the board without this item, without rebuilding anything
		items.erase(c)
		var gain: int = Scoring.preview(String(kept["id"]), c, _board())["delta"]
		items[c] = kept
		if gain > best_gain and level_score - gain >= two:   # two stars stay lit without it
			best_gain = gain
			best = c
		if gain < low_gain:
			low_gain = gain
			low = c
	if best.x < 0:
		best = low
	if best.x < 0:
		return
	var id: String = items[best]["id"]
	_apply_level(2, best)
	ui.hide_result()
	set_tool(id)
	_set_aim(best)


## Remove the floating "+N" from placement (screenshots: --autosolve, --explain).
func _clear_floats() -> void:
	for ch in get_children():
		if ch is Label3D and ch != delta_label and not mark_labels.has(ch) and not hint_labels.has(ch):
			ch.queue_free()


## Debugging: label each item with how much coziness it brings.
func _explain_layout() -> void:
	ui.hide_result()
	_hide_preview()
	if ghost:
		ghost.visible = false
	_clear_floats()   # only the final labels remain
	zoom_target -= 1.5
	var ids := _ids()
	var tall := {"tree": 1.75, "pine": 1.75, "lantern": 1.5, "bench": 0.95}
	var rows := []
	for c in ids:
		var v := Scoring.item_points(ids[c], c, _board(ids))
		rows.append("%s %s = %d" % [ids[c], str(c), v])
		var l := _make_label(84)
		_set_label(l, v, terrain.cell_center(c) + Vector3(0, terrain.surface_y(c) + tall.get(ids[c], 0.85), 0))
		l.text = str(v)
	rows.sort()
	print("EXPLAIN total=%d
  %s" % [Scoring.total(_board(ids)), "
  ".join(rows)])


func _pick(mp: Vector2) -> Vector2i:
	var from := cam.project_ray_origin(mp)
	var dir := cam.project_ray_normal(mp)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 300.0)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		var col: Object = hit["collider"]
		if col and col.has_meta("cell"):
			var c: Vector2i = col.get_meta("cell")
			var n: Vector3 = hit["normal"]
			# "Raise" on a side face — grow the neighbor, like in cube sandboxes
			if tool == "raise" and absf(n.y) < 0.5:
				var side := c + Vector2i(roundi(n.x), roundi(n.z))
				if terrain.in_grid(side):
					return side
			return c
	if tool == "raise" and absf(dir.y) > 0.001:
		var p := from + dir * ((0.0 - from.y) / dir.y)
		var c := terrain.world_to_cell(p)
		if terrain.in_grid(c):
			return c
	return NO_CELL


# ================================================================ input

func _unhandled_input(event: InputEvent) -> void:
	if ui.handle_overlay_input(event):
		return
	if touch_mode:
		# the world listens only to touches; the mouse (including mouse emulated from touches) is for interface buttons
		if event is InputEventScreenTouch or event is InputEventScreenDrag:
			_touch(event)
			return
		if event is InputEventMouse:
			return
	if result_wait >= 0.0 and not event is InputEventKey:
		return   # the finished island is on show; the result comes in a moment
	if event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		if ui.result.visible:
			ui.hide_result()
		elif mode != "menu":
			open_menu()
		return
	if mode == "menu":
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			match mb.button_index:
				MOUSE_BUTTON_LEFT:
					if hover_cell == NO_CELL and _pick(mb.position) == NO_CELL:
						rotating = true   # a left drag that begins off the island turns it; over cells it paints
						yaw_vel = 0.0
					else:
						painting = 1
						_apply(1)
				MOUSE_BUTTON_RIGHT:
					painting = 2
					_apply(2)
				MOUSE_BUTTON_MIDDLE:
					rotating = true
					yaw_vel = 0.0
				MOUSE_BUTTON_WHEEL_UP:
					zoom_target = clampf(zoom_target - 1.0, zoom_min, zoom_max)
				MOUSE_BUTTON_WHEEL_DOWN:
					zoom_target = clampf(zoom_target + 1.0, zoom_min, zoom_max)
		else:
			if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
				painting = 0
			if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_MIDDLE:
				if rotating:
					_release_spin()
				rotating = false
	elif event is InputEventMouseMotion and rotating:
		_rotate_px((event as InputEventMouseMotion).relative.x)
	elif event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).keycode
		match key:
			KEY_Q:
				rotate_island(-1)
			KEY_E:
				rotate_island(1)
			KEY_R:
				rotate_item()
			KEY_Z:
				if (event as InputEventKey).ctrl_pressed:
					undo()
			KEY_T:
				toggle_fast()
			KEY_M:
				toggle_sound()
			KEY_H:
				ui.toggle_help()
			KEY_F12:
				_screenshot()
			KEY_Y:
				cycle_garden_season()
			KEY_TAB:
				if _is_year():
					var order: Array = ui.YEAR_ORDER
					set_year_view(order[(order.find(year_view) + 1) % order.size()])
			_:
				var tools := all_tools()
				if key >= KEY_1 and key <= KEY_9 and key - KEY_1 < tools.size():
					set_tool(tools[key - KEY_1])
				elif key == KEY_0 and tools.size() >= 10:
					set_tool(tools[9])


# ================================================================ frame

func _process(dt: float) -> void:
	t += dt
	if settings_timer > 0.0:
		settings_timer -= dt
		if settings_timer <= 0.0:
			_save_settings()
	_step_wave(dt)
	if result_wait > 0.0:
		result_wait -= dt
		if result_wait <= 0.0:
			_show_pending_result()
	_update_camera(dt)
	_touch_hold()
	if back_armed > 0.0:
		back_armed -= dt
	_update_hover()
	_update_day(dt)
	_update_life(dt)
	_update_ambient(dt)
	if save_timer > 0.0:
		save_timer -= dt
		if save_timer <= 0.0:
			_save()
	if shot_path != "":
		shot_frames += 1
		if shot_frames == 30:
			for p in debug_clicks:
				hover_cell = _pick(p)
				_apply(1)
			if autosolve and mode == "level":
				_autosolve()
				if midplay:
					_midplay()
				_clear_floats()
			if nocard_arg and card_collapsed == false and mode == "level":
				toggle_card()
			if debug_aim.x >= 0.0:
				_set_aim(_pick(debug_aim))
			if zoom_arg > 0.0:
				zoom_target = zoom_arg
				cam.size = zoom_arg
			if no_ui:
				ui.visible = false
			if debug_drawer and ui.has_method("toggle_drawer"):
				ui.toggle_drawer()
			if sheet_arg != "" and ui.sheets.has(sheet_arg):
				ui.open_sheet(sheet_arg)
			if yaw_arg != INF:
				yaw_target = deg_to_rad(yaw_arg)
				yaw_vel = 0.0
				pivot.rotation.y = yaw_target
		if shot_frames == 60:
			for p in debug_rclicks:
				hover_cell = _pick(p)
				_apply(2)
		if shot_frames == 120:
			_shot_and_quit(shot_path)
			shot_path = ""


func _update_camera(dt: float) -> void:
	var k := 1.0 - exp(-dt * 9.0)
	if _turning():
		pivot.rotation.y = yaw_target   # under the finger: no smoothing, no lag
	else:
		if yaw_vel != 0.0:
			yaw_target += yaw_vel * dt
			yaw_vel *= exp(-dt / SPIN_DECAY)
			if absf(yaw_vel) < SPIN_MIN:
				yaw_vel = 0.0
				_soft_snap()
		pivot.rotation.y = lerp_angle(pivot.rotation.y, yaw_target, k)
	_fit_zoom()
	cam.size = lerpf(cam.size, zoom_target, k)
	_frame_island()


## D2: the island's center (the pivot) is drawn at the center of the free area — the screen minus the interface's reserved
## parts, which don't change when the rules card collapses or a sheet opens. The shift is fixed in pixels and converted
## with the current zoom, so a pinch doesn't move the island either.
func _frame_island() -> void:
	cam.h_offset = 0.0
	cam.v_offset = 0.0
	var vs: Vector2 = ui.view_size()
	var fr: Rect2 = ui.free_rect()
	if fr.size.x <= 1.0 or vs.y <= 1.0:
		return
	var s := fr.get_center() - vs * 0.5
	var px := cam.size / vs.y   # world units per logical pixel (an orthographic camera keeps the height)
	cam.h_offset = -s.x * px
	cam.v_offset = s.y * px


## The zoom range of this map: the closest zoom keeps every land cell inside the free area at any yaw (no pan any more).
## Recomputed when the mode, the level or the free area changes; --zoom= (screenshots) is left alone.
func _fit_zoom() -> void:
	if mode == "menu" or zoom_arg > 0.0:
		return
	var fr: Rect2 = ui.free_rect()
	var vs: Vector2 = ui.view_size()
	var key := [mode, level_idx, fr, vs, terrain.heights.size() + terrain.water.size()]
	if key == fit_key or fr.size.x <= 1.0 or fr.size.y <= 1.0:
		return
	fit_key = key
	zoom_min = fit_size(fr, vs)
	zoom_max = maxf(24.0, zoom_min * 1.4)
	zoom_target = clampf(zoom_target, zoom_min, zoom_max)


## The orthographic size at which the whole map fits the free area at any yaw: its horizontal radius R around the pivot
## must fit half the free width, and its height range (cell tops) plus R·sin(pitch) half the free height.
func fit_size(fr: Rect2, vs: Vector2) -> float:
	var cells: Array = terrain.heights.keys() + terrain.water.keys()   # the land (the garden recomputes when it grows)
	var r := 0.0
	var top := 0.0
	var low := 0.0
	for c in cells:
		var p: Vector3 = terrain.cell_center(c) - pivot.position
		r = maxf(r, Vector2(p.x, p.z).length() + 0.71)
		var y: float = terrain.top_y(c) - pivot.position.y
		top = maxf(top, y + 0.3)   # the cell's top face must be reachable, not the item standing on it
		low = minf(low, y)
	var a := deg_to_rad(PITCH)
	var up := r * sin(a) + top * cos(a)
	var down := r * sin(a) - low * cos(a)
	var need_w := 2.0 * r * vs.y / fr.size.x
	var need_h := 2.0 * maxf(up, down) * vs.y / fr.size.y
	return maxf(need_w, need_h)


func _turning() -> bool:
	if rotating:
		return true
	for i in fingers:
		var f: Dictionary = fingers[i]
		if not f["ui"] and f["moved"] and not multi:
			return true
	return false


## A horizontal drag by dx logical pixels: the island follows the finger, a full screen width is half a turn.
func _rotate_px(dx: float) -> void:
	var w: float = maxf(ui.view_size().x, 1.0)
	var d := -dx * PI / w
	yaw_target += d
	pivot.rotation.y = yaw_target
	var now := Time.get_ticks_usec()
	var gap := maxf(float(now - drag_us) / 1000000.0, 1.0 / 240.0)
	drag_us = now
	yaw_vel = lerpf(yaw_vel, clampf(d / gap, -12.0, 12.0), 0.5)


## The finger lifted: keep the speed only if it was still moving (a pause before the release stops the island).
func _release_spin() -> void:
	if float(Time.get_ticks_usec() - drag_us) / 1000000.0 > 0.06:
		yaw_vel = 0.0
	if absf(yaw_vel) < SPIN_MIN:
		yaw_vel = 0.0
		_soft_snap()


## After a spin: within SNAP_DEG of a fixed position the island eases into it; any other angle stays.
func _soft_snap() -> void:
	var k := (yaw_target - YAW_BASE) / YAW_STEP
	var n := roundf(k)
	if absf(k - n) * 90.0 < SNAP_DEG:
		yaw_target = YAW_BASE + n * YAW_STEP


## Q / E: to the next fixed position (45° + k·90°) in that direction, counted from where the island is going; if less than
## SNAP_DEG remain to it, to the one after (this also absorbs float noise right at a position).
static func next_yaw(yaw: float, dir: int) -> float:
	var k := (yaw - YAW_BASE) / YAW_STEP
	var n: float
	if dir > 0:
		n = floorf(k) + 1.0
		if (n - k) * 90.0 < SNAP_DEG:
			n += 1.0
	else:
		n = ceilf(k) - 1.0
		if (k - n) * 90.0 < SNAP_DEG:
			n -= 1.0
	return YAW_BASE + n * YAW_STEP


func _update_hover() -> void:
	var c := NO_CELL
	if touch_mode:
		c = aim_cell if mode != "menu" else NO_CELL
		hover_cell = c
		_update_bubble(c)
	else:
		var mp := debug_mouse if debug_mouse.x >= 0.0 else get_viewport().get_mouse_position()
		var over_ui: bool = mode == "menu" or ui.is_over_ui(mp)
		c = NO_CELL if over_ui else _pick(mp)
		if c != hover_cell:
			hover_cell = c
			if painting != 0 and c != NO_CELL:
				_apply(painting)
	var valid := _is_valid(c)
	var show := c != NO_CELL
	highlight.visible = show
	if show:
		var y := terrain.surface_y(c) if terrain.has_land(c) else 0.0
		highlight.position = terrain.cell_center(c) + Vector3(0, y + 0.03, 0)
		var col := Color(1, 1, 1, 0.4) if valid else Color(1.0, 0.45, 0.4, 0.45)
		if tool == "remove" and valid:
			col = Color(1.0, 0.55, 0.35, 0.55)
		highlight_material.set_shader_parameter("color", col)
	if ghost:
		ghost.visible = show and valid
		if ghost.visible:
			ghost.position = terrain.cell_center(c) + Vector3(0, terrain.surface_y(c), 0)
	_update_preview(c)


func _update_day(dt: float) -> void:
	# on a level time stands still (the level sets the lighting) until "speed up" is pressed
	var speed := FAST if time_fast else (0.0 if mode == "level" else 1.0)
	day_time = fposmod(day_time + dt * speed / DAY_LENGTH, 1.0)
	var ang := (day_time - 0.25) * TAU
	var elev := sin(ang)
	daylight = clampf(elev * 3.0 + 0.4, 0.0, 1.0)
	var dusk := clampf(1.0 - absf(elev) * 3.5, 0.0, 1.0)
	var night := 1.0 - daylight

	sun.rotation = Vector3(-deg_to_rad(20.0 + 50.0 * absf(elev)), deg_to_rad(-60.0) - ang * 0.5, 0.0)
	var light_col := Color(0.55, 0.65, 1.0).lerp(Color(1.0, 0.96, 0.88), daylight).lerp(Color(1.0, 0.62, 0.42), dusk * 0.65)
	sun.light_color = light_col
	sun.light_energy = lerpf(0.45, 1.25, daylight) * (1.0 - dusk * 0.25)

	env.background_color = Color("1d2645").lerp(Color("bfe6f2"), daylight).lerp(Color("f5b89c"), dusk * 0.5)
	env.ambient_light_color = Color("4d5d94").lerp(Color("e6eef6"), daylight).lerp(Color("f6c7a8"), dusk * 0.4)
	env.ambient_light_energy = lerpf(0.85, 0.6, daylight)

	C.lamp_mat().set_shader_parameter("emission_energy", night * 4.0)
	fireflies.amount_ratio = clampf(night * 1.2 - 0.15, 0.0, 1.0)
	fireflies.emitting = fireflies.amount_ratio > 0.0 and _season() != "winter"
	if ui:
		ui.set_clock(day_time)


func _update_life(dt: float) -> void:
	var gust := 0.75 + 0.35 * sin(t * 0.37) + 0.15 * sin(t * 1.3)
	var night := 1.0 - daylight
	for c in items:
		var it: Dictionary = items[c]
		var sway: Node3D = it["sway"]
		var amp: float = it["amp"]
		var ph: float = it["phase"]
		if amp > 0.0:
			sway.rotation.x = sin(t * 1.7 + ph) * amp * gust
			sway.rotation.z = cos(t * 1.3 + ph * 1.3) * amp * gust * 0.8
		match it["id"]:
			"lily":
				sway.position.y = sin(t * 1.2 + ph) * 0.012
			"campfire":
				var fl: OmniLight3D = sway.get_node("Light")
				fl.light_energy = (0.6 + night * 1.4) * (0.85 + 0.15 * sin(t * 13.0 + ph) * sin(t * 7.3))
			"hive":
				var bees: Node3D = sway.get_node("Bees")
				bees.rotation.y = t * 1.6 + ph
				bees.position.y = 0.3 + sin(t * 3.1 + ph) * 0.03
			"lantern":
				var light: OmniLight3D = sway.get_node("Light")
				light.light_energy = night * 1.7 * (0.95 + 0.05 * sin(t * 9.0 + ph))
	# clouds
	for cl in shadow_clouds:
		cl.position.x += dt * 0.45
		if cl.position.x > 18.0:
			cl.position.x = -18.0
	cloud_ring.rotation.y += dt * 0.012
	# butterflies over flowers (daytime)
	butterfly_timer -= dt
	if butterfly_timer <= 0.0:
		butterfly_timer = 1.0
		_sync_butterflies()
	var spots := _flower_spots()
	for b in butterflies:
		b.step(dt, spots, daylight)


func _flower_spots() -> Array:
	var out := []
	if _season() == "winter":
		return out   # butterflies don't fly in winter
	for c in items:
		if items[c]["id"] == "flowers":
			out.append((items[c]["node"] as Node3D).position)
	return out


func _sync_butterflies() -> void:
	var spots := _flower_spots()
	var want := mini(6, (spots.size() + 1) / 2)
	while butterflies.size() < want:
		var col: Color = [Color("ffd166"), Color("f78fb3"), Color("7ec8ff"), Color("ffffff"), Color("ff9f5a")][randi() % 5]
		var b := Butterfly.new(col)
		var s: Vector3 = spots[randi() % spots.size()]
		b.position = s + Vector3(randf_range(-1, 1), 1.0, randf_range(-1, 1))
		add_child(b)
		butterflies.append(b)
	while butterflies.size() > want:
		butterflies.pop_back().queue_free()


func _update_ambient(dt: float) -> void:
	ambient_timer -= dt
	if ambient_timer > 0.0:
		return
	if daylight > 0.7:
		sfx.play("chirp", randf_range(0.85, 1.2), -16.0)
		ambient_timer = randf_range(2.5, 7.0)
	elif daylight < 0.3:
		sfx.play("cricket", randf_range(0.95, 1.05), -20.0)
		ambient_timer = randf_range(0.7, 2.2)
	else:
		ambient_timer = 1.5


func _crumbs(pos: Vector3, col: Color, n: int) -> void:
	for i in n:
		var cr := Crumb.new()
		cr.mesh = C.sphere(0.04)
		cr.material_override = C.mat(col)
		cr.position = pos
		var a := randf() * TAU
		cr.vel = Vector3(cos(a) * randf_range(0.6, 1.4), randf_range(1.8, 2.8), sin(a) * randf_range(0.6, 1.4))
		add_child(cr)


# ================================================================ saving

func _mark_dirty() -> void:
	save_timer = 0.8
	if mode == "sandbox":
		_refresh_garden_score()


func _save() -> void:
	if not save_enabled or not sandbox_ready:
		return
	var land := []
	for c in terrain.heights:
		land.append([c.x, c.y, terrain.heights[c], 1 if terrain.is_water(c) else 0, terrain.bottoms.get(c, -1.0)])
	var its := []
	for c in items:
		var it: Dictionary = items[c]
		its.append([c.x, c.y, it["id"], it["seed"], it["rot"]])
	var data := {"version": 2, "seed": island_seed, "land": land, "items": its, "time": day_time,
		"season": garden_season, "cozy": garden_cozy}   # v2 (stage 7): the garden season and the counter; during a wave — the target season
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
		f.close()


func _load() -> bool:
	if not FileAccess.file_exists(save_path):
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if typeof(data) != TYPE_DICTIONARY or not data.has("land"):
		return false
	# the season — before building the island: a saved winter opens straight in winter, without a wave (v1 — summer)
	garden_season = String(data.get("season", "summer"))
	if not garden_season in Campaign.SEASON_ORDER:
		garden_season = "summer"
	if season_arg != "":
		garden_season = season_arg
	garden_cozy = bool(data.get("cozy", false))
	terrain.season = garden_season
	terrain.dry = {}
	terrain.snow_cells = {}
	terrain.clear_all()
	for row in data["land"]:
		var c := Vector2i(int(row[0]), int(row[1]))
		terrain.heights[c] = int(row[2])
		if int(row[3]) == 1:
			terrain.water[c] = true
		terrain.bottoms[c] = float(row[4])
	pond_note = not terrain.settle().is_empty()   # stage 15 (D5): a garden from before may have raised ponds
	terrain.build_all()
	for row in data["items"]:
		_place_item(Vector2i(int(row[0]), int(row[1])), str(row[2]), int(row[3]), int(row[4]), false)
	day_time = float(data.get("time", 0.36))
	island_seed = int(data.get("seed", 0))
	return true


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if save_timer > 0.0:
			_save()
		flush_settings()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT and ui:
		ui.cancel_hold()   # the window lost focus — the button release may not arrive, cancel the reset hold
		fingers.clear()
	elif what == NOTIFICATION_APPLICATION_PAUSED:
		# Android kills the process in the background without warning — save everything right away
		if save_timer > 0.0:
			_save()
			save_timer = -1.0
		flush_settings()
		fingers.clear()
		if ui:
			ui.cancel_hold()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		go_back()


## The system "Back" button (Android): close the top window; from a level or the garden — to the menu; in the menu a second press within
## 2 s exits (Godot can't minimize the app), everything is saved before exiting.
func go_back() -> void:
	if ui.close_top():
		return
	if result_wait >= 0.0:
		return
	if mode != "menu":
		if touch_mode and ui.has_method("open_sheet"):
			ui.open_sheet("drawer")   # D2 finding: an edge swipe is Back — it mustn't throw the player out of a level
		else:
			open_menu()
		return
	if back_armed > 0.0:
		_flush_save()
		flush_settings()
		get_tree().quit()
	else:
		back_armed = 2.0
		ui.toast(I18n.t("toast.back_exit"), 2.0)


# ================================================================ touch (stage 10)

func _world_fingers() -> Array:
	var out := []
	for i in fingers:
		if not fingers[i]["ui"]:
			out.append(fingers[i])
	return out


func _touch(ev: InputEvent) -> void:
	if ev is InputEventScreenTouch:
		var st := ev as InputEventScreenTouch
		if st.pressed:
			fingers[st.index] = {"start": st.position, "pos": st.position, "t0": t,
				"ui": mode == "menu" or result_wait >= 0.0 or ui.is_over_ui(st.position), "moved": false, "long": false}
			if absf(yaw_vel) > SPIN_STOP and not fingers[st.index]["ui"]:
				fingers[st.index]["moved"] = true   # this touch stops the spin: not a tap, may go on as a drag
				drag_us = Time.get_ticks_usec()
			yaw_vel = 0.0
			var world := _world_fingers()
			if world.size() >= 2:
				multi = true
				ui.press_ring(Vector2.ZERO, -1.0)
				pinch_d = (world[0]["pos"] as Vector2).distance_to(world[1]["pos"])
			return
		var f = fingers.get(st.index)
		fingers.erase(st.index)
		ui.press_ring(Vector2.ZERO, -1.0)
		if f != null and not f["ui"] and f["moved"] and not multi:
			_release_spin()
		if f != null and not f["ui"] and not multi and not f["moved"] and not f["long"] and t - float(f["t0"]) < LONG_TIME:
			_tap(st.position)
		if _world_fingers().size() < 2:
			pinch_d = 0.0
		if fingers.is_empty():
			multi = false
		return
	var sd := ev as InputEventScreenDrag
	var fd = fingers.get(sd.index)
	if fd == null or fd["ui"]:
		return
	fd["pos"] = sd.position
	if multi:
		var world := _world_fingers()
		if world.size() >= 2:
			var d := (world[0]["pos"] as Vector2).distance_to(world[1]["pos"])
			if pinch_d > 1.0 and d > 1.0:
				zoom_target = clampf(zoom_target * pinch_d / d, zoom_min, zoom_max)
			pinch_d = d
		return   # one finger left after a pinch — no drag and no tap until all are released
	if not fd["moved"] and sd.position.distance_to(fd["start"]) > TAP_SLOP:
		fd["moved"] = true
		ui.press_ring(Vector2.ZERO, -1.0)
		drag_us = Time.get_ticks_usec()
		_rotate_px(sd.position.x - (fd["start"] as Vector2).x)   # the slop isn't lost: the island catches up with the finger
		yaw_vel = 0.0
		return
	if fd["moved"]:
		_rotate_px(sd.relative.x)


## Long press: the ring grows from 0.2 s, at 0.45 s the item is removed (on a level — back to hand). Only over an item.
func _touch_hold() -> void:
	if not touch_mode or multi or fingers.size() != 1:
		return
	var f: Dictionary = fingers.values()[0]
	if f["ui"] or f["moved"] or f["long"]:
		return
	var held := t - float(f["t0"])
	if held < RING_FROM:
		return
	var c := _pick(f["pos"])
	if not items.has(c):
		ui.press_ring(Vector2.ZERO, -1.0)
		return
	if held >= LONG_TIME:
		f["long"] = true
		ui.press_ring(Vector2.ZERO, -1.0)
		_take_back(c)
	else:
		ui.press_ring(f["pos"], (held - RING_FROM) / (LONG_TIME - RING_FROM))


## Tap: on a level — try the cell (a second tap on the same cell places); in the garden — the tool acts right away.
func _tap(pos: Vector2) -> void:
	var c := _pick(pos)
	if mode == "level":
		if c == NO_CELL:
			_set_aim(NO_CELL)
		elif c == aim_cell:
			if t - aim_t >= CONFIRM_GUARD:
				confirm_aim()
		else:
			_set_aim(c)
			if not items.has(c) and aim_placed < 3:
				_aim_hint()
	elif mode == "sandbox":
		if c == NO_CELL:
			_set_aim(NO_CELL)
			return
		if items.has(c) and not Items.info(tool).is_empty():
			_set_aim(c)   # an item tool on an occupied cell selects it (for the trash), silently
			hover_cell = c
			return
		hover_cell = c
		_apply(1)
		_set_aim(c)


func _set_aim(c: Vector2i) -> void:
	aim_cell = c
	aim_t = t
	if touch_mode:
		hover_cell = c


## Place the tried item (a second tap or the ✓ button above the cell).
func confirm_aim() -> void:
	var c := aim_cell
	if c == NO_CELL or items.has(c) or mode != "level":
		return
	hover_cell = c
	_apply(1)
	if items.has(c):
		_set_aim(NO_CELL)
		aim_placed += 1
		if aim_placed >= 3:
			coach["aim"] = true
			settings_timer = 0.5
		_coach("place")


## Remove the item from a cell: on a level — back to hand, in the garden — remove (long press or the button above the tried cell).
func _take_back(c: Vector2i) -> void:
	if not items.has(c):
		return
	hover_cell = c
	_apply(2)
	if not items.has(c):
		_buzz()
		if aim_cell == c:
			_set_aim(c)


func take_back_aim() -> void:
	_take_back(aim_cell)


## The trash button (D3): return the selected item to the hand (level) or remove it (garden). Nothing selected — say how.
func trash() -> void:
	if result_wait >= 0.0 or mode == "menu":
		return
	if aim_cell == NO_CELL or not items.has(aim_cell):
		sfx.play("nope", 1.0, -10.0)
		ui.toast(I18n.t("toast.trash_pick"), 2.5)
		return
	if items[aim_cell]["fixed"]:
		sfx.play("nope", 1.0, -10.0)
		ui.toast(I18n.t("toast.fixed"), 2.0)
		return
	_take_back(aim_cell)


## "Tap again to place" — shown on every try until the 3rd placement (not only once).
func _aim_hint() -> void:
	if not touch_mode or coach.has("aim"):
		return
	ui.toast(I18n.t("coach.aim"), 4.0)


## The button above the tried cell: ✓ — place (level), arrow into the tray — remove / back to hand (if the item isn't fixed).
func _update_bubble(c: Vector2i) -> void:
	var kind := ""
	if c != NO_CELL and mode != "menu" and not ui.result.visible:
		if items.has(c):
			if not items[c]["fixed"]:
				kind = "back"
		elif mode == "level" and _is_valid(c):
			kind = "ok"
	if kind == "":
		ui.set_bubble(Vector2.ZERO, "")
		return
	var top := terrain.cell_center(c) + Vector3(0, terrain.surface_y(c) + 1.9, 0)
	var low := terrain.cell_center(c) + Vector3(0, terrain.surface_y(c) - 0.5, 0)
	ui.set_bubble(cam.unproject_position(top), kind, cam.unproject_position(low))


func _buzz() -> void:
	if touch_mode and vibrate_on:
		Input.vibrate_handheld(25)


func set_vibrate(on: bool) -> void:
	vibrate_on = on
	settings_timer = 0.5
	_buzz()


## One-time gesture tips (touch only): first try, first placement, first entry into the garden.
func _coach(id: String) -> void:
	if not touch_mode or coach.has(id):
		return
	coach[id] = true
	settings_timer = 0.5
	var text := ""
	match id:
		"aim":
			text = I18n.t("coach.aim")
		"place":
			text = I18n.t("coach.place")
		"sandbox":
			text = I18n.t("coach.sandbox")
	ui.toast(text, 5.0)


## Interface: on touch — the phone layout (a separate subclass), otherwise — the desktop one.
func _make_ui() -> UI:
	return UIPhone.new() if touch_mode else UI.new()


func toggle_card() -> void:
	card_collapsed = not card_collapsed
	ui._sync_card()


func rotate_island(dir: int) -> void:
	yaw_vel = 0.0
	yaw_target = next_yaw(yaw_target, dir)


func rotate_item() -> void:
	ghost_rot = (ghost_rot + 1) % 4
	if ghost and Items.info(tool).get("rotatable", false):
		ghost.rotation.y = ghost_rot * PI * 0.5


# ================================================================ undo (stage 10)

## A cell's state: land (height, water, "roots") and the item. Undo returns the cell to it.
func _cell_state(c: Vector2i) -> Dictionary:
	var it = null
	if items.has(c):
		var d: Dictionary = items[c]
		it = {"id": d["id"], "seed": d["seed"], "rot": d["rot"], "fixed": d["fixed"]}
	return {"h": int(terrain.heights.get(c, 0)), "w": terrain.water.has(c), "b": float(terrain.bottoms.get(c, -1.0)), "it": it}


func _push_undo(c: Vector2i, before: Dictionary, extra: Dictionary = {}) -> void:
	if before == _cell_state(c) and extra.is_empty():
		return
	undo_stack.append({"c": c, "s": before, "extra": extra})
	if undo_stack.size() > UNDO_MAX:
		undo_stack.pop_front()


## Undo the last action (up to 10): a button on touch, Ctrl+Z on PC. On a level items go through the hand.
func undo() -> void:
	if mode == "menu" or ui.result.visible or result_wait >= 0.0 or undo_stack.is_empty():
		if mode != "menu":
			sfx.play("nope", 1.0, -10.0)
		return
	var e: Dictionary = undo_stack.pop_back()
	var c: Vector2i = e["c"]
	var s: Dictionary = e["s"]
	var now := _cell_state(c)
	if mode == "level" and s["it"] != null and now["it"] != s["it"] and int(hand.get(s["it"]["id"], 0)) <= 0:
		sfx.play("nope", 1.0, -10.0)   # this item is already placed elsewhere — nothing to return
		return
	if now["h"] != s["h"] or now["w"] != s["w"]:
		if int(s["h"]) <= 0:
			terrain.heights.erase(c)
			terrain.water.erase(c)
		else:
			terrain.heights[c] = int(s["h"])
			if s["w"]:
				terrain.water[c] = true
			else:
				terrain.water.erase(c)
			terrain.bottoms[c] = float(s["b"])
		terrain.build_cell(c, true)
		if (now["h"] <= 0) != (int(s["h"]) <= 0):
			terrain._rebuild_wet_neighbors(c)
	# the other cells the edit moved (a pond that settled): their terrain back as it was, without settling again
	var extra: Dictionary = e.get("extra", {})
	for x in extra:
		var xs: Dictionary = extra[x]
		if int(xs["h"]) <= 0:
			terrain.heights.erase(x)
			terrain.water.erase(x)
		else:
			terrain.heights[x] = int(xs["h"])
			if xs["w"]:
				terrain.water[x] = true
			else:
				terrain.water.erase(x)
		terrain.build_cell(x, true)
		if items.has(x):
			(items[x]["node"] as Node3D).position.y = terrain.surface_y(x)
	if now["it"] != s["it"]:
		if now["it"] != null:
			if mode == "level":
				hand[now["it"]["id"]] = int(hand.get(now["it"]["id"], 0)) + 1
			_remove_item(c)
		if s["it"] != null:
			if mode == "level":
				hand[s["it"]["id"]] = int(hand[s["it"]["id"]]) - 1
			_place_item(c, s["it"]["id"], int(s["it"]["seed"]), int(s["it"]["rot"]), true, bool(s["it"]["fixed"]))
	elif now["it"] != null:
		(items[c]["node"] as Node3D).position.y = terrain.surface_y(c)
	if mode == "level":
		ui.update_hand(hand)
		_refresh_score()
		if int(hand.get(tool, 0)) <= 0:
			var nxt := _first_in_hand()
			if nxt != "":
				set_tool(nxt)
	else:
		_mark_dirty()
	sfx.play("tick", 0.9, -8.0)


func _screenshot() -> void:
	DirAccess.make_dir_recursive_absolute("user://screenshots")
	var path := "user://screenshots/garden_%s.png" % Time.get_datetime_string_from_system().replace(":", "-")
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	ui.toast(I18n.t("toast.shot", {"path": ProjectSettings.globalize_path(path)}), 4.0)


func _shot_and_quit(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()


# ================================================================ wildlife

class Butterfly extends Node3D:
	const CL := preload("res://scripts/clay.gd")
	var target := Vector3.ZERO
	var vel := Vector3.ZERO
	var wing_l := Node3D.new()
	var wing_r := Node3D.new()
	var phase := randf() * TAU
	var retarget := 0.0
	var vis := 0.0

	func _init(col: Color) -> void:
		CL.part(self, CL.sphere(0.025), CL.mat(Color("4a3b33")), Vector3.ZERO, Vector3(0.6, 0.6, 2.4))
		add_child(wing_l)
		add_child(wing_r)
		for w in [[wing_l, 1.0], [wing_r, -1.0]]:
			var node: Node3D = w[0]
			var sx: float = w[1]
			CL.part(node, CL.sphere(0.07), CL.mat(col), Vector3(0.07 * sx, 0, 0.025), Vector3(1.0, 0.12, 0.8))
			CL.part(node, CL.sphere(0.05), CL.mat(col.darkened(0.12)), Vector3(0.05 * sx, 0, -0.055), Vector3(1.0, 0.12, 0.8))
		scale = Vector3.ONE * 0.001

	func step(dt: float, spots: Array, day: float) -> void:
		phase += dt * 24.0
		var flap := sin(phase) * 1.0
		wing_l.rotation.z = flap
		wing_r.rotation.z = -flap
		retarget -= dt
		if spots.size() > 0 and (retarget <= 0.0 or position.distance_to(target) < 0.15):
			retarget = randf_range(2.0, 5.0)
			var s: Vector3 = spots[randi() % spots.size()]
			target = s + Vector3(randf_range(-0.35, 0.35), randf_range(0.4, 0.85), randf_range(-0.35, 0.35))
		var desired := (target - position).limit_length(0.9)
		desired += Vector3(sin(phase * 0.11) * 0.35, cos(phase * 0.15) * 0.3, cos(phase * 0.09) * 0.35)
		vel = vel.lerp(desired, clampf(dt * 2.0, 0.0, 1.0))
		position += vel * dt
		if vel.length() > 0.05:
			rotation.y = atan2(vel.x, vel.z)
		vis = lerpf(vis, 1.0 if day > 0.5 else 0.0, clampf(dt * 2.0, 0.0, 1.0))
		scale = Vector3.ONE * maxf(vis, 0.001)
		visible = vis > 0.01


class Crumb extends MeshInstance3D:
	var vel := Vector3.ZERO
	var life := 0.0

	func _process(dt: float) -> void:
		life += dt
		vel.y -= 9.0 * dt
		position += vel * dt
		var k := 1.0 - life / 0.55
		scale = Vector3.ONE * maxf(k, 0.01)
		if life > 0.55:
			queue_free()
