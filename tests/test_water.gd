extends SceneTree
## Stage 15: water finds its level; waterfalls. Run: Godot --headless --path . --script res://tests/test_water.gd
## The rule (no water cell above an orthogonal land neighbor, no step between touching water cells) on every level as the
## game loads it, on 200 generated gardens, and after 2,000 random garden edits, each undone and redone exactly; items
## follow the cells that move; the garden edit cases (raise a pond, drain it by its rim, water digs its bed, a raised
## cell drains a pond); waterfalls exactly on the open sides, ending at their column's bottom, frozen in winter; a saved
## garden with a raised pond loads settled, its file untouched; levels 37 and 99 keep their ideal exactly.
## The player's files are compared by md5 before and after.

const Terrain := preload("res://scripts/terrain.gd")
const Levels := preload("res://scripts/levels.gd")
const Scoring := preload("res://scripts/scoring.gd")
const I18n := preload("res://scripts/i18n.gd")

const PLAYER_FILES := ["user://progress.json", "user://garden.json", "user://settings.json", "user://playlog.json"]
const SAVE := "user://test_garden_water.json"
const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

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
	_test_rule()
	_test_levels()
	_test_generated()
	_test_ideals()
	await _test_garden()
	await _test_saved()
	for f in [SAVE, "user://test_progress_water.json", "user://test_settings_water.json", "user://test_playlog_water.json"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	check(_hashes() == before, "player files changed")
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


## Every place where water stands above land or above the touching water: [water cell, neighbor, why].
static func violations(land: Dictionary, wet: Dictionary) -> Array:
	var out := []
	for w in wet:
		if not land.has(w):
			continue
		for d in DIRS:
			var n: Vector2i = w + d
			if not land.has(n):
				continue
			if wet.has(n):
				if int(land[n]) != int(land[w]):
					out.append([w, n, "water %d next to water %d" % [land[w], land[n]]])
			elif int(land[n]) < int(land[w]):
				out.append([w, n, "land %d below water %d" % [land[n], land[w]]])
	return out


## The rule itself: idempotent, never moves land, fixes the classic raised pond.
func _test_rule() -> void:
	var land := {Vector2i(0, 0): 1, Vector2i(1, 0): 2, Vector2i(2, 0): 2, Vector2i(3, 0): 3, Vector2i(1, 1): 4}
	var wet := {Vector2i(1, 0): true, Vector2i(2, 0): true}
	check(not violations(land, wet).is_empty(), "the oracle doesn't see a raised pond")
	var s := Terrain.settled(land, wet)
	check(violations(s, wet).is_empty(), "the rule left a raised pond: %s" % [violations(s, wet)])
	check(s[Vector2i(1, 0)] == 1 and s[Vector2i(2, 0)] == 1, "the pond didn't go down to its lowest bank (1)")
	check(Terrain.settled(s, wet) == s, "the rule is not idempotent")
	for c in land:
		if not wet.has(c):
			check(s[c] == land[c], "the rule moved a land cell %s" % c)
	# a pond on the edge (no land on one side) keeps its level: that side is a waterfall, not a bank
	var edge := {Vector2i(0, 0): 3, Vector2i(1, 0): 3}
	check(Terrain.settled(edge, {Vector2i(1, 0): true})[Vector2i(1, 0)] == 3, "an open side lowered the pond")


## Every level as the game loads it (parse_map and the terrain after start-like loading).
func _test_levels() -> void:
	var bad := 0
	var t := Terrain.new()
	for L in Levels.LEVELS:
		var mp := Terrain.parse_map(L["map"])
		var v := violations(mp["land"], mp["water"])
		if not v.is_empty():
			bad += 1
			print("  level %d %s: %s" % [L["slot"], L["id"], v.slice(0, 2)])
		t.load_map(L["map"])
		check(violations(t.heights, t.water).is_empty(), "level %d: the loaded island has raised water" % L["slot"])
	check(bad == 0, "%d levels with water above land" % bad)
	t.free()


func _test_generated() -> void:
	var t := Terrain.new()
	var bad := 0
	for s in 200:
		t.generate(s)
		if not violations(t.heights, t.water).is_empty():
			bad += 1
	check(bad == 0, "%d of 200 generated gardens have water above land" % bad)
	t.free()


## Levels 37 and 99 have a bench that may gain a view next to a lowered pond: the ideal must stay exactly the data's.
func _test_ideals() -> void:
	for slot in [37, 99]:
		var L: Dictionary = {}
		for x in Levels.LEVELS:
			if int(x["slot"]) == slot:
				L = x
		var mp := Terrain.parse_map(L["map"])
		var off: Vector2i = mp["off"]
		var fixed := {}
		for f in L.get("fixed", []):
			fixed[off + Vector2i(f[0], f[1])] = f[2]
		var n := 0
		for id in L["hand"]:
			n += int(L["hand"][id])
		var best := 0
		for r in 3:
			var rng := RandomNumberGenerator.new()
			rng.seed = 900 + r
			best = maxi(best, int(Scoring.solve(L, mp["land"], mp["water"], fixed, 20000 + n * 4000, 2, rng)["best"]))
		check(best == int(L["perfect"]), "level %d: the solver reaches %d with settled water, the data says %d" % [slot, best, L["perfect"]])


func _start(fresh: bool) -> void:
	m = load("res://main.tscn").instantiate()
	m.fresh = fresh
	m.new_player = true
	m.seed_arg = 7
	m.save_enabled = false
	m.music_on = false
	m.lang_arg = "en"
	m.save_path = SAVE
	m.progress_path = "user://test_progress_water.json"
	m.settings_path = "user://test_settings_water.json"
	m.playlog_path = "user://test_playlog_water.json"
	root.add_child(m)
	await _frames(3)
	m.enter_sandbox()
	await _frames(2)


func _stop() -> void:
	m.queue_free()
	await _frames(2)


func _state() -> Dictionary:
	var its := {}
	for c in m.items:
		its[c] = [m.items[c]["id"], m.items[c]["seed"], m.items[c]["rot"]]
	return {"h": m.terrain.heights.duplicate(), "w": m.terrain.water.duplicate(), "it": its}


func _edit(tool: String, c: Vector2i) -> void:
	m.tool = tool
	m.hover_cell = c
	m.painting = 0
	m._apply(1)


## Waterfalls: on each water cell exactly one per open side; on land none; each sheet ends at the column's bottom.
func _check_falls(where: String) -> void:
	var t = m.terrain
	var wrong := 0
	var ends := 0
	for c in t.heights:
		var col: Node3D = t.cols.get(c)
		if col == null:
			continue
		var want: int = t.open_sides(c).size()
		if int(col.get_meta("falls", 0)) != want:
			wrong += 1
		for ch in col.get_children():
			if ch.has_meta("fall"):
				# the real lowest point of the fall's pieces (the bottom drop): exactly the column's bottom, never lower
				var low := INF
				for piece in ch.get_children():
					var mi := piece as MeshInstance3D
					if mi:
						low = minf(low, mi.position.y + mi.get_aabb().position.y * mi.scale.y)
				if absf(low - float(t.bottoms.get(c, -1.2))) > 0.01:
					ends += 1
	check(wrong == 0, "%s: %d cells with the wrong number of waterfalls" % [where, wrong])
	check(ends == 0, "%s: %d waterfalls not ending at their column's bottom" % [where, ends])


func _items_follow(where: String) -> void:
	var off := 0
	for c in m.items:
		var node: Node3D = m.items[c]["node"]
		if absf(node.position.y - m.terrain.surface_y(c)) > 0.001:
			off += 1
	check(off == 0, "%s: %d items float or sink after the terrain moved" % [where, off])


func _test_garden() -> void:
	await _start(true)
	var t = m.terrain
	check(violations(t.heights, t.water).is_empty(), "the fresh garden has raised water")
	_check_falls("fresh garden")
	var opens := 0
	for c in t.water:
		opens += t.open_sides(c).size()
	print("waterfalls in the seed-7 garden: %d" % opens)
	# lilies on the water and a few land items, so moved cells carry items
	var placed := 0
	for c in t.water:
		if placed < 3 and not m.items.has(c):
			m._place_item(c, "lily", 5, 0, false)
			placed += 1
	# the D3 cases on a clean plateau: 5×5 at height 2, the center is water
	t.clear_all()
	m._clear_items()
	for x in range(5, 10):
		for y in range(5, 10):
			t.heights[Vector2i(x, y)] = 2
			t.bottoms[Vector2i(x, y)] = -2.0
	var p := Vector2i(7, 7)
	t.water[p] = true
	t.build_all()
	m._place_item(p, "lily", 5, 0, false)
	m.undo_stack.clear()
	_edit("raise", p)
	check(int(t.heights[p]) == 2, "the pond rose above its rim")
	check(m.ui.toast_label.text == I18n.t("toast.pond_low"), "a pond that can't rise: no explanation")
	for d in DIRS:
		t.heights[p + d] = 3
		t.build_cell(p + d)
	_edit("raise", p)
	check(int(t.heights[p]) == 3, "the pond didn't rise with its rim at 3")
	_items_follow("a raised pond")
	# lowering one rim cell to 1 drains the whole pond to 1; one undo puts everything back
	_edit("lower", p + Vector2i(1, 0))
	_edit("lower", p + Vector2i(1, 0))
	check(int(t.heights[p]) == 1 and violations(t.heights, t.water).is_empty(), "lowering the rim didn't drain the pond")
	check(m.ui.toast_label.text == I18n.t("toast.water_level") or m.coach.has("water_level"), "no explanation when water ran down")
	_items_follow("a drained pond")
	m.undo()
	check(int(t.heights[p]) == 2 and int(t.heights[p + Vector2i(1, 0)]) == 2, "undoing the second lowering didn't put the pond back to 2")
	m.undo()
	check(int(t.heights[p]) == 3 and int(t.heights[p + Vector2i(1, 0)]) == 3, "undoing the first lowering didn't put the pond and its rim back to 3")
	_items_follow("undo of a drain")
	# water on a high cell digs its bed down to the lowest bank
	var hi := Vector2i(5, 5)
	t.heights[hi] = 4
	t.build_cell(hi)
	_edit("water", hi)
	check(t.water.has(hi) and int(t.heights[hi]) == 2, "water on a high cell didn't sink to its bank (%d)" % t.heights[hi])
	m.undo()
	check(not t.water.has(hi) and int(t.heights[hi]) == 4, "undo didn't bring the high cell back")
	# a pond on the edge, then raising an empty cell next to it (new land at 1) drains it
	var e := Vector2i(9, 7)
	t.water[e] = true
	t.heights[e] = 2
	t.build_cell(e)
	check(int(t.cols[e].get_meta("falls", 0)) == 1, "an edge water cell has no waterfall")
	_edit("raise", Vector2i(10, 7))
	check(t.has_land(Vector2i(10, 7)) and int(t.heights[e]) == 1, "a new cell at 1 beside the pond didn't drain it")
	check(int(t.cols[e].get_meta("falls", 0)) == 0, "the waterfall stayed after land appeared on its side")
	m.undo()
	check(not t.has_land(Vector2i(10, 7)) and int(t.heights[e]) == 2 and int(t.cols[e].get_meta("falls", 0)) == 1,
		"undo didn't restore the edge pond and its waterfall")
	# 2,000 random edits on the seed-7 garden: the rule holds, items follow, each edit undoes exactly and redoes the same
	m.new_island(7)
	await _frames(1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 15
	var tools := ["raise", "lower", "water"]
	var broken := 0
	var undo_bad := 0
	var redo_bad := 0
	var cells: Array = []
	for x in range(2, 16):
		for y in range(2, 16):
			cells.append(Vector2i(x, y))
	for c in t.water.keys().slice(0, 4):
		m._place_item(c, "lily", 3, 0, false)
	for i in 2000:
		var c: Vector2i = cells[rng.randi() % cells.size()]
		var tool: String = tools[rng.randi() % tools.size()]
		m.tool = tool
		if not m._is_valid(c):
			continue
		var s0 := _state()
		m.undo_stack.clear()
		_edit(tool, c)
		if not violations(t.heights, t.water).is_empty():
			broken += 1
		var s1 := _state()
		if s1 == s0:
			continue
		m.undo()
		if _state() != s0:
			undo_bad += 1
		_edit(tool, c)
		if _state() != s1:
			redo_bad += 1
	check(broken == 0, "%d random edits left water above land" % broken)
	check(undo_bad == 0, "%d random edits didn't undo exactly" % undo_bad)
	check(redo_bad == 0, "%d random edits didn't redo the same way" % redo_bad)
	_items_follow("2,000 random edits")
	_check_falls("after random edits")
	# winter: the falls are frozen (no animated sheet), still one per open side
	t.season = "winter"
	t.build_all()
	var sheets := 0
	for c in t.cols:
		for ch in t.cols[c].get_children():
			if ch.has_meta("fall"):
				sheets += 1
	check(sheets == 0, "winter: %d flowing waterfalls instead of frozen ones" % sheets)
	_check_falls("winter")
	t.season = "summer"
	await _stop()


## A garden saved before this stage, with a raised pond: loads settled, says so once, the file is unchanged until a save.
func _test_saved() -> void:
	var land := []
	for x in range(5, 10):
		for y in range(5, 10):
			var c := Vector2i(x, y)
			land.append([x, y, 2 if c == Vector2i(7, 7) else 1, 1 if c == Vector2i(7, 7) else 0, -2.0])
	var data := {"version": 2, "seed": 3, "land": land, "items": [[7, 7, "lily", 5, 0]], "time": 0.4, "season": "summer", "cozy": false}
	var f := FileAccess.open(SAVE, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	var md5 := FileAccess.get_md5(SAVE)
	await _start(false)
	check(int(m.terrain.heights[Vector2i(7, 7)]) == 1, "the old garden's raised pond wasn't settled on load")
	check(m.ui.toast_label.text == I18n.t("toast.pond_settled"), "no note that the pond found its level")
	_items_follow("a loaded garden")
	check(FileAccess.get_md5(SAVE) == md5, "loading rewrote the saved garden")
	# saved settled: the next load says nothing
	m.save_enabled = true
	m._save()
	m.save_enabled = false
	await _stop()
	await _start(false)
	check(m.ui.toast_label.text != I18n.t("toast.pond_settled"), "the note repeated on a garden that was already settled")
	await _stop()
