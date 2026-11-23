extends SceneTree
## Stage 7: free garden seasons. Run: Godot --headless --path . --script res://tests/test_sandbox.gd
## The player's garden (garden.json) and progress are untouched: our own save path, a new player.

const Items := preload("res://scripts/items.gd")
const Scoring := preload("res://scripts/scoring.gd")
const Board := preload("res://scripts/board.gd")
const Campaign := preload("res://scripts/campaign.gd")
const Progress := preload("res://scripts/progress.gd")
const TEST_PATH := "user://test_garden_stage7.json"

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
	_test_items()
	_test_rules()
	await _test_scene()
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	print("TESTS %s: %d checks, %d failed" % ["OK" if failed == 0 else "FAILED", checks, failed])
	quit(0 if failed == 0 else 1)


## Every item is built in every season (and "out of season"); the nodes needed for animation are in place.
func _test_items() -> void:
	for info in Items.CATALOG:
		var id: String = info["id"]
		for season in ["", "spring", "summer", "autumn", "winter"]:
			for lf in [false, true]:
				var n := Items.build(id, 11, season, lf)
				var sway: Node3D = n.get_node_or_null("Sway")
				check(sway != null and sway.get_child_count() > 0, "%s/%s: the model is empty" % [id, season])
				if id == "hive":
					check(sway.get_node_or_null("Bees") != null, "beehive/%s: no bees (_update_life spins them)" % season)
				if id in ["lantern", "campfire"]:
					check(sway.get_node_or_null("Light") != null, "%s/%s: no light" % [id, season])
				n.free()
	# out-of-season shapes really are different
	var a := Items.build("snowman", 3, "summer").get_node("Sway").get_child_count()
	var b := Items.build("snowman", 3, "winter").get_node("Sway").get_child_count()
	check(a != b, "the summer snowman looks like the winter one")


## Free garden seasons and flags follow progress; placement uses the summer terrain.
func _test_rules() -> void:
	check(Campaign.sandbox_seasons(0) == ["spring", "summer"], "a newcomer has more than spring and summer unlocked")
	check(Campaign.sandbox_seasons(51) == ["spring", "summer", "autumn"], "autumn didn't unlock after 51")
	check(Campaign.sandbox_seasons(76).size() == 4, "winter didn't unlock after 76")
	check(Campaign.sandbox_flags("winter", 0).is_empty(), "an invisible rule for a newcomer")
	check(Campaign.sandbox_flags("summer", 54) == ["line"], "the fence row after 54")
	check(Campaign.sandbox_flags("autumn", 60) == ["line"], "falling leaves before 61")
	check(Campaign.sandbox_flags("autumn", 61) == ["line", "leaf_fall"], "falling leaves after 61")
	check(Campaign.sandbox_flags("winter", 80) == ["line", "winter"], "winter after 76")
	var land := {Vector2i(0, 0): 1, Vector2i(1, 0): 1, Vector2i(2, 0): 1}
	var water := {Vector2i(1, 0): true}
	land[Vector2i(1, 0)] = 1
	var bw = Board.for_sandbox({}, land, water, "winter", 99)
	check(not bw.can_place("snowman", Vector2i(1, 0)), "in the garden the snowman stood on ice (in spring it would be on water)")
	check(bw.can_place("lily", Vector2i(1, 0)), "a water lily can't be placed in the winter garden")
	# in winter water doesn't count, in summer it does
	var its := {Vector2i(0, 0): "flowers"}
	var s_sum := Scoring.total(Board.for_sandbox(its.duplicate(), land, water, "summer", 99))
	var s_win := Scoring.total(Board.for_sandbox(its.duplicate(), land, water, "winter", 99))
	check(s_sum > s_win, "in winter flowers still get water nearby")
	var s_new := Scoring.total(Board.for_sandbox(its.duplicate(), land, water, "winter", 0))
	check(s_new == s_sum, "for a newcomer winter changed the rules")


func _node_count() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _wait_wave(m) -> void:
	var guard := 0
	while m.wave_t >= 0.0 and guard < 5000:
		await process_frame
		guard += 1


## The wave: quick changes don't multiply nodes or touch data; a save in the middle of a wave writes the whole garden;
## a saved winter opens in winter without a wave; v1 — summer.
func _test_scene() -> void:
	var m = load("res://main.tscn").instantiate()
	m.fresh = true
	m.new_player = true
	m.seed_arg = 7
	m.save_path = TEST_PATH
	m.progress_path = "user://test_progress_other.json"
	m.settings_path = "user://test_settings_other.json"
	m.playlog_path = "user://test_playlog_other.json"
	m.music_on = false
	root.add_child(m)
	await _frames(3)
	m.enter_sandbox()
	await _frames(3)
	# the garden: several items on land (no flowers — butterflies change the node count)
	var ids := ["tree", "pine", "hive", "hammock", "snowman", "pumpkin", "mushroom", "bench", "lantern", "campfire"]
	var k := 0
	for c in m.terrain.heights:
		if k >= ids.size():
			break
		if m.terrain.is_water(c) or m.items.has(c):
			continue
		m._place_item(c, ids[k], 100 + k, 0, false)
		k += 1
	check(k == ids.size(), "not enough land for the items")
	var before_items := {}
	for c in m.items:
		before_items[c] = m.items[c]["id"]
	m.set_garden_season("summer")
	await _wait_wave(m)
	await _frames(5)
	var nodes0 := _node_count()
	# ten quick changes, a frame between them
	var seq := ["winter", "autumn", "spring", "winter", "summer", "autumn", "winter", "spring", "autumn", "winter"]
	for s in seq:
		m.set_garden_season(s)
		await process_frame
	# a save in the middle of a wave: the whole garden and the target season
	check(m.wave_t >= 0.0, "the wave already ended — saving mid-wave wasn't checked")
	m._save()
	var saved = JSON.parse_string(FileAccess.get_file_as_string(TEST_PATH))
	check(saved is Dictionary and saved["items"].size() == before_items.size(), "only part of the garden was saved mid-wave")
	check(saved is Dictionary and saved["season"] == "winter" and int(saved["version"]) == 2, "the file doesn't have the target season")
	await _wait_wave(m)
	check(m.terrain.season == "winter", "after the wave the island is not wintry")
	# the data didn't change, every record has a live node
	var same: bool = before_items.size() == m.items.size()
	for c in before_items:
		same = same and m.items.has(c) and m.items[c]["id"] == before_items[c]
	check(same, "the wave changed the garden data")
	var alive := true
	for c in m.items:
		var nd: Node3D = m.items[c]["node"]
		alive = alive and is_instance_valid(nd) and nd.is_inside_tree() and m.items[c]["sway"] == nd.get_node("Sway")
	check(alive, "after the wave a record points to a freed node")
	m.set_garden_season("summer")
	await _wait_wave(m)
	await _frames(5)
	check(m.items_root.get_child_count() == m.items.size(), "extra item nodes: %d for %d items" % [m.items_root.get_child_count(), m.items.size()])
	check(_node_count() == nodes0, "node leak after season changes: was %d, now %d" % [nodes0, _node_count()])
	# loading v2 "winter" — winter right away, no wave
	m.set_garden_season("winter")
	await _wait_wave(m)
	m._save()
	m.garden_season = "summer"
	m.terrain.season = "summer"
	m.fresh = false
	m._load_sandbox()
	check(m.garden_season == "winter" and m.terrain.season == "winter", "the saved winter didn't open in winter")
	check(m.wave_t < 0.0, "loading started a wave")
	check(m.items.size() == before_items.size(), "loading lost items")
	# v1 (no season) — summer
	var v1 = JSON.parse_string(FileAccess.get_file_as_string(TEST_PATH))
	v1.erase("season")
	v1.erase("cozy")
	v1["version"] = 1
	var f := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(v1))
	f.close()
	m._load_sandbox()
	check(m.garden_season == "summer" and m.terrain.season == "summer", "a v1 save didn't open in summer")
	# the sandbox score — a for_sandbox board with flags by progress; the counter is off by default
	check(not m.garden_cozy, "the coziness counter is on by default")
	var bd = m._board()
	check(bd.flags == Campaign.sandbox_flags(m.garden_season, Progress.reached(m.progress)), "the garden board is not for_sandbox")
	m.save_enabled = false
	m.queue_free()
	await _frames(2)
