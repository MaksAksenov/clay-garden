extends SceneTree
## Coziness engine tests. Run: Godot --headless --path . --script res://tests/test_rules.gd
## 1) Rule data without errors, every rule has a phrase.
## 2) References from the old code (tests/golden_scores.json, captured by tests/make_golden.gd.txt before "Rules 2.0"):
##    totals and each item's points, hints (gain and marks), card texts, the solver with seed 99.
## 3) Unit tests of the new rule types on synthetic boards.

const Scoring := preload("res://scripts/scoring.gd")
const Board := preload("res://scripts/board.gd")
const Levels := preload("res://scripts/levels.gd")
const Terrain := preload("res://scripts/terrain.gd")
const Progress := preload("res://scripts/progress.gd")
const I18n := preload("res://scripts/i18n.gd")

var fails := 0
var checks := 0


func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		if fails <= 25:
			print("FAIL: ", what)


func _init() -> void:
	I18n.set_lang("ru")   # the reference cards are Russian (golden_cards_ru.json); I18n defaults to English
	_test_data()
	_test_golden()
	_test_near()
	_test_between()
	_test_bad_rules()
	_test_delta_random()
	_test_drought()
	_test_autumn()
	_test_winter()
	_test_year()
	print("TESTS %s: %d checks, %d failed" % ["OK" if fails == 0 else "FAILED", checks, fails])
	quit(1 if fails > 0 else 0)


func _test_data() -> void:
	Scoring.compile()
	check(Scoring.errors.is_empty(), "errors in RULES: %s" % [Scoring.errors])
	for id in Scoring.RULES:
		for r in Scoring.RULES[id]:
			check(Scoring.phrase(r) != "", "no phrase for rule %s %s" % [id, r])
		check(Scoring.noun(id) != "noun." + id, "no item name for %s" % id)


func _cells(arr: Array) -> Dictionary:
	var d := {}
	for e in arr:
		d[Vector2i(int(e[0]), int(e[1]))] = e[2]
	return d


func _test_golden() -> void:
	var g: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/golden_scores.json"))
	# the references were captured in the old level order; levels are now found by permanent id
	var old_levels := []
	var maps := []
	for id in Progress.OLD_ORDER:
		var L: Dictionary = Levels.LEVELS[Levels.index_of(id)]
		old_levels.append(L)
		maps.append(Terrain.parse_map(L["map"]))
	for t in g["totals"]:
		var m: Dictionary = maps[int(t["level"])]
		var b := Board.new(_cells(t["items"]), m["land"], m["water"])
		check(Scoring.total(b) == int(t["total"]), "level %d total: %d instead of %d" % [t["level"], Scoring.total(b), t["total"]])
		for e in t["items"]:
			var c := Vector2i(int(e[0]), int(e[1]))
			var v := Scoring.item_points(e[2], c, b)
			check(v == int(e[3]), "points of %s at %s: %d instead of %d" % [e[2], c, v, e[3]])
	for p in g["previews"]:
		var m: Dictionary = maps[int(p["level"])]
		var b := Board.new(_cells(p["items"]), m["land"], m["water"])
		var at := Vector2i(int(p["at"][0]), int(p["at"][1]))
		var before := b.items.size()
		var r := Scoring.preview(p["id"], at, b)
		check(b.items.size() == before and not b.items.has(at) or p["items"].any(func(e): return Vector2i(int(e[0]), int(e[1])) == at), "the hint changed the board")
		check(r["delta"] == int(p["delta"]), "gain of %s at %s: %d instead of %d" % [p["id"], at, r["delta"], p["delta"]])
		var marks := []
		for n in r["marks"]:
			marks.append([n.x, n.y, r["marks"][n]])
		marks.sort()
		var want := []
		for e in p["marks"]:
			want.append([int(e[0]), int(e[1]), int(e[2])])
		check(marks == want, "marks of %s at %s: %s instead of %s" % [p["id"], at, marks, want])
	# the reference was captured when there were 11 items: compare the card within the same items
	# (new links — e.g. "bench: beehive −2" from stage 4 — the reference doesn't and shouldn't know)
	var old_items: Array = g["describe"].keys()
	for id in g["describe"]:
		check(Scoring.describe(id, old_items) == g["describe"][id], "card %s:\n%s\n---instead of---\n%s" % [id, Scoring.describe(id), g["describe"][id]])
	var ms := 0
	for s in g["solves"]:
		var li := int(s["level"])
		# the reference is the old engine: no campaign flags (the row and falling leaves depend on the level's slot)
		var L: Dictionary = old_levels[li].duplicate()
		L.erase("slot")
		var m: Dictionary = maps[li]
		var off: Vector2i = m["off"]
		var fixed := {}
		for f in L.get("fixed", []):
			fixed[off + Vector2i(f[0], f[1])] = f[2]
		var rng := RandomNumberGenerator.new()
		rng.seed = 99
		var t0 := Time.get_ticks_msec()
		var res := Scoring.solve(L, m["land"], m["water"], fixed, 5000, 1, rng)
		ms += Time.get_ticks_msec() - t0
		var cells := []
		for c in res["items"]:
			cells.append([c.x, c.y, res["items"][c]])
		cells.sort()
		var want := []
		for e in s["items"]:
			want.append([int(e[0]), int(e[1]), e[2]])
		check(res["best"] == int(s["best"]) and cells == want, "solver of level %d: %d instead of %d" % [li + 1, res["best"], s["best"]])
	print("SOLVER_MS %d (old code reference 497, budget 745)" % ms)
	check(ms <= 745, "the solver is slower than the budget: %d ms" % ms)


## Beehive: +1 for flowers within 2 steps (a diamond), excluding the cell itself.
func _test_near() -> void:
	Scoring.use_rules({"hive": [{"t": "near", "of": "flowers", "r": 2, "v": 1}], "flowers": []})
	Scoring.compile()
	check(Scoring.errors.is_empty(), "near: errors %s" % [Scoring.errors])
	var items := {Vector2i(5, 5): "hive", Vector2i(6, 5): "flowers", Vector2i(7, 5): "flowers",
		Vector2i(6, 6): "flowers", Vector2i(8, 5): "flowers", Vector2i(7, 6): "flowers"}
	var b := Board.new(items, {}, {})
	# in the r=2 diamond: (6,5) d1, (7,5) d2, (6,6) d2; (8,5) d3 and (7,6) d3 — no
	check(Scoring.item_points("hive", Vector2i(5, 5), b) == 1 + 3, "near: the beehive should get 4")
	# the hint: marks on three flowers in the radius, gain 3 + base
	items.erase(Vector2i(5, 5))
	var p := Scoring.preview("hive", Vector2i(5, 5), b)
	check(p["delta"] == 4, "near: hint gain %d instead of 4" % p["delta"])
	check(p["marks"].size() == 3 and p["marks"].get(Vector2i(7, 5), 0) == 1, "near: marks %s" % [p["marks"]])
	check(Scoring.describe("hive") == "Цветы не дальше 2 шагов (и по диагонали): +1 за каждые", "near: card \"%s\"" % Scoring.describe("hive"))
	Scoring.use_rules({})


## Hammock: +5 if a tree or fir stands on two opposite sides; both axes are counted separately.
func _test_between() -> void:
	Scoring.use_rules({"hammock": [{"t": "between", "of": ["tree", "pine"], "v": 5}], "tree": [], "pine": []})
	Scoring.compile()
	check(Scoring.errors.is_empty(), "between: errors %s" % [Scoring.errors])
	var c := Vector2i(5, 5)
	var b := Board.new({c: "hammock", Vector2i(4, 5): "tree", Vector2i(6, 5): "pine"}, {}, {})
	check(Scoring.item_points("hammock", c, b) == 6, "between: one axis — 1 + 5")
	b.items[Vector2i(5, 4)] = "tree"
	check(Scoring.item_points("hammock", c, b) == 6, "between: a tree on only one side of the second axis doesn't count")
	b.items[Vector2i(5, 6)] = "tree"
	check(Scoring.item_points("hammock", c, b) == 6, "between: the pattern counts once, even on two axes (stage 4)")
	b.items.erase(c)
	var p := Scoring.preview("hammock", c, b)
	var sum := 0
	for n in p["marks"]:
		sum += p["marks"][n]
	check(p["delta"] == 6 and sum == 5, "between: hint %s" % [p])
	Scoring.use_rules({})


func _test_bad_rules() -> void:
	Scoring.use_rules({"x": [{"t": "ajd", "of": "x", "v": 1}, {"t": "adj", "of": "nobody", "v": 1}, {"t": "water"}]})
	Scoring.compile()
	check(Scoring.errors.size() == 3, "data validation should catch 3 errors, caught %d" % Scoring.errors.size())
	Scoring.use_rules({})
	Scoring.compile()


## delta == the difference of two totals on random boards, including near and between;
## swapping two neighboring items "step by step" (as in the solver) == the difference of totals.
func _test_delta_random() -> void:
	var rules := Scoring.RULES.duplicate()
	rules.erase("hive")
	rules.erase("hammock")
	rules["hive"] = [{"t": "near", "of": "flowers", "r": 2, "v": 1}, {"t": "adj", "of": "bench", "v": -2}]
	rules["hammock"] = [{"t": "between", "of": ["tree", "pine"], "v": 5}, {"t": "water", "v": 1}]
	rules["flowers"] = Scoring.RULES["flowers"] + [{"t": "near", "of": "hive", "r": 2, "v": 1}]
	Scoring.use_rules(rules)
	Scoring.compile()
	check(Scoring.errors.is_empty(), "delta: rule errors %s" % [Scoring.errors])
	var ids: Array = rules.keys()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var bad := 0
	for t in 10000:
		var land := {}
		var water := {}
		for z in 8:
			for x in 8:
				var c := Vector2i(x, z)
				land[c] = rng.randi_range(1, 4)
				if rng.randf() < 0.15:
					water[c] = true
		var items := {}
		for k in rng.randi_range(0, 30):
			items[Vector2i(rng.randi_range(0, 7), rng.randi_range(0, 7))] = ids[rng.randi() % ids.size()]
		var b := Board.new(items, land, water)
		if t % 3 == 0:   # a third of the boards have a drought: check that delta with the dry-cell mask is exact
			b.drought = true
			b.dry = Board.dry_cells(land, water)
		if t % 4 == 1:   # a quarter — with autumn flags: the fence row and falling leaves
			b.flags = ["line", "leaf_fall"]
			for x in range(1, 6):   # a row of fences across the board — check a swap in the middle of the row
				items[Vector2i(x, 3)] = "fence"
		var c := Vector2i(rng.randi_range(0, 7), rng.randi_range(0, 7))
		if t % 2 == 0:
			if items.has(c):
				continue
			var id: String = ids[rng.randi() % ids.size()]
			var before := Scoring.total(b)
			var d := Scoring.delta(id, c, b)
			check(not items.has(c), "delta left an item on the board")
			items[c] = id
			if Scoring.total(b) - before != d:
				bad += 1
		else:
			# swap c with a neighbor, like a solver move
			var nb: Vector2i = c + Scoring.DIRS[rng.randi() % 4]
			if not items.has(c) or not items.has(nb) or items[c] == items[nb]:
				continue
			var before := Scoring.total(b)
			var a: String = items[c]
			var z: String = items[nb]
			items.erase(c)
			var step := -Scoring.delta(a, c, b)
			items.erase(nb)
			step -= Scoring.delta(z, nb, b)
			step += Scoring.delta(z, c, b)
			items[c] = z
			step += Scoring.delta(a, nb, b)
			items[nb] = a
			if Scoring.total(b) - before != step:
				bad += 1
	check(bad == 0, "delta diverged from total in %d cases" % bad)
	Scoring.use_rules({})
	Scoring.compile()


## Drought: on a dry cell flowers give 0, neighbors see them; one arrangement gives one total
## through the factory for the game (Board.make with the level map) and the solver.
func _test_drought() -> void:
	var L := {"id": "t", "slot": 36, "season": "summer", "drought": true,
		"map": ["~2222", "22222", "22222"], "hand": {"flowers": 3, "hive": 1, "bush": 1}}
	var m := Terrain.parse_map(L["map"])
	var off: Vector2i = m["off"]
	var b = Board.for_level(L, {})
	check(b.drought and not b.dry.is_empty(), "the factory didn't compute dry cells")
	var far: Vector2i = off + Vector2i(4, 2)
	var near: Vector2i = off + Vector2i(1, 0)
	check(b.dry.has(far) and not b.dry.has(near), "the dry-cell mask is wrong")
	b.items[far] = "flowers"
	check(Scoring.item_points("flowers", far, b) == 0, "a flower on a dry cell should give 0")
	b.items[off + Vector2i(3, 2)] = "hive"
	check(Scoring.item_points("hive", off + Vector2i(3, 2), b) == 2, "the beehive should see the dry flower (1 + 1)")
	b.items[near] = "flowers"
	check(Scoring.item_points("flowers", near, b) == 1 + 2, "a flower by the water is alive")
	# without a drought the same flower gives points
	var L2 := L.duplicate()
	L2["drought"] = false
	var b2 = Board.for_level(L2, b.items.duplicate())
	check(Scoring.item_points("flowers", far, b2) >= 1, "without a drought a flower should not give 0")
	# consistency: game/factory = solver
	var items: Dictionary = b.items.duplicate()
	var total_factory := Scoring.total(Board.make(items.duplicate(), m["land"], m["water"], L))
	var total_level := Scoring.total(Board.for_level(L, items.duplicate()))
	check(total_factory == total_level, "the factories diverge")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var res := Scoring.solve(L, m["land"], m["water"], {}, 3000, 1, rng)
	check(Scoring.total(Board.make(res["items"].duplicate(), m["land"], m["water"], L)) == res["best"], "the solver counts a different total than the game")
	# card: the drought phrase only on drought levels
	check(not "Засуха" in Scoring.describe("flowers"), "the drought phrase outside a drought")
	check("Засуха" in Scoring.describe("flowers", [], true), "no drought phrase on a drought level")


## Autumn: the fence row and falling leaves by the level's slot; one total through the factory for every consumer.
func _test_autumn() -> void:
	var m := Terrain.parse_map(["22222", "22222", "22222"])
	var off: Vector2i = m["off"]
	var summer := {"id": "s", "slot": 44, "map": ["22222", "22222", "22222"], "hand": {"fence": 3}}
	var autumn := summer.duplicate()
	autumn["slot"] = 62
	var row := {off + Vector2i(1, 1): "fence", off + Vector2i(2, 1): "fence", off + Vector2i(3, 1): "fence"}
	var bs = Board.make(row.duplicate(), m["land"], m["water"], summer)
	var ba = Board.make(row.duplicate(), m["land"], m["water"], autumn)
	check(Scoring.total(ba) == Scoring.total(bs) + 3, "a row of 3 fences: +3 only from slot 54 (summer %d, autumn %d)" % [Scoring.total(bs), Scoring.total(ba)])
	check(not "Ряд" in Scoring.describe("fence", [], false, []) and "Ряд" in Scoring.describe("fence", [], false, ["line"]), "the row phrase only where the rule applies")
	# falling leaves: the pumpkin gets tree +1 instead of −1
	var pt := {off + Vector2i(1, 1): "pumpkin", off + Vector2i(2, 1): "tree"}
	var p_summer := Scoring.item_points("pumpkin", off + Vector2i(1, 1), Board.make(pt.duplicate(), m["land"], m["water"], summer))
	var p_fall := Scoring.item_points("pumpkin", off + Vector2i(1, 1), Board.make(pt.duplicate(), m["land"], m["water"], autumn))
	check(p_summer == 0 and p_fall == 2, "falling leaves: a pumpkin by a tree %d in summer and %d in falling leaves" % [p_summer, p_fall])
	# the scarecrow gives pumpkins +1 within radius 2, the birdhouse −2
	var sc := {off + Vector2i(0, 0): "scarecrow", off + Vector2i(2, 0): "pumpkin", off + Vector2i(1, 1): "birdhouse"}
	var bsc = Board.make(sc.duplicate(), m["land"], m["water"], autumn)
	check(Scoring.item_points("pumpkin", off + Vector2i(2, 0), bsc) == 2, "a pumpkin 2 steps from the scarecrow gets +1")
	check(Scoring.item_points("birdhouse", off + Vector2i(1, 1), bsc) == -1, "the birdhouse gets −2 from a scarecrow nearby")
	# haystack: no more than two neighbors
	var hs := {off + Vector2i(2, 1): "haystack", off + Vector2i(1, 1): "pumpkin", off + Vector2i(3, 1): "pumpkin", off + Vector2i(2, 0): "fence"}
	check(Scoring.item_points("haystack", off + Vector2i(2, 1), Board.make(hs.duplicate(), m["land"], m["water"], autumn)) == 1 + 4, "the haystack counts no more than two neighbors")
	# an unknown flag is a data error
	Scoring.use_rules({"x": [{"t": "adj", "of": "x", "v": 1, "when": "leaf_fal"}]})
	Scoring.compile()
	check(Scoring.errors.size() == 1, "a typo in a flag was not caught")
	Scoring.use_rules({})
	Scoring.compile()
	# consistency: the solver counts the same total as the game's factory
	var L := {"id": "a", "slot": 62, "season": "autumn", "map": ["22222", "22222", "2222 "], "hand": {"fence": 4, "pumpkin": 3, "tree": 1, "scarecrow": 1}}
	var mm := Terrain.parse_map(L["map"])
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var res := Scoring.solve(L, mm["land"], mm["water"], {}, 4000, 1, rng)
	check(Scoring.total(Board.make(res["items"].duplicate(), mm["land"], mm["water"], L)) == res["best"], "the autumn solver counts a different total")


## Winter: the single placement rule, cold and warmth, ice instead of water; delta is exact with cold at distance 2.
func _test_winter() -> void:
	var L := {"id": "w", "slot": 82, "season": "winter", "map": ["22~22", "22222", "22222"],
		"snow": [[0, 2], [1, 2], [4, 0]], "hand": {"snowman": 1, "campfire": 1, "bench": 2, "pine": 2, "rock": 1}}
	var b = Board.for_level(L, {})
	var m := Terrain.parse_map(L["map"])
	var off: Vector2i = m["off"]
	var ice: Vector2i = off + Vector2i(2, 0)
	check(b.winter and b.snow.size() == 3, "the factory didn't build winter and snowdrifts")
	# the single placement rule
	check(b.can_place("snowman", ice) and not b.can_place("bench", ice) and not b.can_place("lily", ice), "ice: snowman yes, bench and water lily no")
	var summer := L.duplicate()
	summer["slot"] = 40
	var bs = Board.for_level(summer, {})
	check(not bs.can_place("snowman", ice) and bs.can_place("lily", ice), "summer water: water lily yes, snowman no")
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var res := Scoring.solve(L, m["land"], m["water"], {}, 3000, 1, rng)
	for c in res["items"]:
		check(b.can_place(res["items"][c], c), "the solver placed %s where it can't go" % res["items"][c])
	# cold: a bench on a snowdrift without warmth gives 0, with a campfire 2 steps away it comes alive; neighbors see it
	var cold: Vector2i = off + Vector2i(0, 2)
	b.items[cold] = "bench"
	check(Scoring.item_points("bench", cold, b) == 0, "a bench on a cold snowdrift should give 0")
	b.items[off + Vector2i(2, 2)] = "campfire"
	check(Scoring.item_points("bench", cold, b) >= 1, "a campfire 2 steps away should warm the snowdrift")
	b.items.erase(off + Vector2i(2, 2))
	# snowman: +2 on ice, melts near warmth
	b.items[ice] = "snowman"
	check(Scoring.item_points("snowman", ice, b) == 3, "snowman on ice: 1 + 2")
	# ice instead of water: in winter water doesn't count for a stone, ice +1
	var rk: Vector2i = off + Vector2i(1, 0)
	b.items[rk] = "rock"
	check(Scoring.item_points("rock", rk, b) == 1 + 1, "a stone by ice in winter: 1 + ice 1 (water off)")
	check(Scoring.item_points("rock", rk, Board.for_level(summer, {rk: "rock"})) == 1 + 2, "in summer a stone gets water +2")
	# delta == the difference of totals: swapping a heat source and a frozen item at distance 2
	var bad := 0
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 21
	var ids := ["bench", "pine", "campfire", "lantern", "snowman", "rock", "tree", "feeder"]
	for t in 3000:
		var items := {}
		for k in rng2.randi_range(2, 12):
			var c := off + Vector2i(rng2.randi_range(0, 4), rng2.randi_range(0, 2))
			var id: String = ids[rng2.randi() % ids.size()]
			if Board.placeable(id, c, m["land"], m["water"], true):
				items[c] = id
		var bb = Board.for_level(L, items)
		var c := off + Vector2i(rng2.randi_range(0, 4), rng2.randi_range(0, 2))
		var nid: String = ids[rng2.randi() % ids.size()]
		if items.has(c) or not bb.can_place(nid, c):
			continue
		var before := Scoring.total(bb)
		var d := Scoring.delta(nid, c, bb)
		items[c] = nid
		if Scoring.total(bb) - before != d:
			bad += 1
	check(bad == 0, "delta with cold diverged from total in %d cases" % bad)
	# card
	check("замёрзла" in Scoring.describe("rock", [], false, ["winter"]) and "лёд +1" in Scoring.describe("rock", [], false, ["winter"]), "the stone card in winter")
	check("мёрзнет" in Scoring.describe("bench", [], false, ["winter"], true), "card: about the snowdrift")


## All Year Round: coziness = the sum of four seasons over one arrangement; a sleeping item — 0 of its own, neighbors see it.
func _test_year() -> void:
	const Campaign := preload("res://scripts/campaign.gd")
	var L := {"id": "y", "slot": 97, "season": "winter", "map": ["2~222", "22222", "22222"], "hand": {"tree": 2, "pumpkin": 2, "rock": 1, "hive": 1, "flowers": 2}}
	var m := Terrain.parse_map(L["map"])
	var off: Vector2i = m["off"]
	var items := {off + Vector2i(0, 0): "rock", off + Vector2i(1, 1): "pumpkin", off + Vector2i(2, 1): "tree", off + Vector2i(3, 1): "hive", off + Vector2i(3, 0): "flowers"}
	var b = Board.for_level(L, items)
	check(b.subs.size() == 4, "All Year Round: 4 seasonal boards are needed")
	var sum := 0
	for season in Campaign.YEAR_SEASONS:
		var one := Board.new(items, m["land"], m["water"], season)
		one.flags = Campaign.YEAR_SEASONS[season]["flags"]
		for id in Campaign.YEAR_SEASONS[season]["sleep"]:
			one.sleep[id] = true
		sum += Scoring.total(one)
	check(Scoring.total(b) == sum, "All Year Round coziness is not the sum of the seasons")
	# the beehive sleeps everywhere except summer; flowers — in winter
	var hv: Vector2i = off + Vector2i(3, 1)
	var winter_b = b.subs[3]
	check(Scoring.item_points("hive", hv, winter_b) == 0, "the beehive should sleep in winter")
	check(Scoring.item_points("hive", hv, b.subs[1]) >= 1, "the beehive doesn't sleep in summer")
	# delta == the difference of totals
	var bad := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var ids := ["tree", "pumpkin", "rock", "hive", "flowers", "fence", "snowman", "bench"]
	for t in 1500:
		var its := {}
		for k in rng.randi_range(1, 9):
			var c := off + Vector2i(rng.randi_range(0, 4), rng.randi_range(0, 2))
			if not m["water"].has(c):
				its[c] = ids[rng.randi() % ids.size()]
		var bb = Board.for_level(L, its)
		var c := off + Vector2i(rng.randi_range(0, 4), rng.randi_range(0, 2))
		var nid: String = ids[rng.randi() % ids.size()]
		if its.has(c) or not bb.can_place(nid, c):
			continue
		var before := Scoring.total(bb)
		var d := Scoring.delta(nid, c, bb)
		its[c] = nid
		if Scoring.total(bb) - before != d:
			bad += 1
	check(bad == 0, "All Year Round delta diverged from total in %d cases" % bad)
	check(not b.can_place("snowman", off + Vector2i(1, 0)), "All Year Round: placement uses the summer terrain — no snowman on water")
