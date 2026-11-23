extends SceneTree
## Campaign data tests: levels from JSON with correct types, permanent ids, progress migration.
## Run: Godot --headless --path . --script res://tests/test_campaign.gd

const Levels := preload("res://scripts/levels.gd")
const Progress := preload("res://scripts/progress.gd")
const Terrain := preload("res://scripts/terrain.gd")
const Scoring := preload("res://scripts/scoring.gd")
const Items := preload("res://scripts/items.gd")
const Stars := preload("res://scripts/stars.gd")
const Campaign := preload("res://scripts/campaign.gd")

var fails := 0
var checks := 0


func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		print("FAIL: ", what)


func _init() -> void:
	_test_levels()
	_test_migration()
	_test_items_complete()
	_test_stars()
	_test_unlock()
	_test_no_dead_rules()
	print("TESTS %s: %d checks, %d failed" % ["OK" if fails == 0 else "FAILED", checks, fails])
	quit(1 if fails > 0 else 0)


func _test_levels() -> void:
	check(Levels.LEVELS.size() >= 10, "fewer than 10 levels")
	var ids := {}
	var last_slot := 0
	for L in Levels.LEVELS:
		check(not ids.has(L["id"]), "duplicate id %s" % L["id"])
		ids[L["id"]] = true
		check(typeof(L["slot"]) == TYPE_INT and L["slot"] > last_slot, "%s: slot is not an int or not ascending" % L["id"])
		last_slot = L["slot"]
		check(L["season"] in ["spring", "summer", "autumn", "winter"], "%s: season \"%s\"" % [L["id"], L["season"]])
		check(typeof(L["perfect"]) == TYPE_INT, "%s: perfect is not an int" % L["id"])
		check(L["stars"].size() == 3, "%s: not three thresholds" % L["id"])
		for s in L["stars"]:
			check(typeof(s) == TYPE_INT, "%s: a threshold is not an int" % L["id"])
		check(L["stars"][2] <= L["perfect"], "%s: ★★★ above the ideal" % L["id"])
		for id in L["hand"]:
			check(typeof(L["hand"][id]) == TYPE_INT, "%s: hand %s is not an int" % [L["id"], id])
		var m := Terrain.parse_map(L["map"])
		for f in L.get("fixed", []):
			check(typeof(f[0]) == TYPE_INT and m["land"].has(m["off"] + Vector2i(f[0], f[1])), "%s: a fixed item outside the island" % L["id"])
	for id in Progress.OLD_ORDER:
		check(Levels.index_of(id) >= 0, "no level with the old id %s" % id)


func _test_migration() -> void:
	# old format v1: by level number in the old order
	var old := {"0": {"stars": 3, "best": 19}, "1": {"stars": 2, "best": 27}, "6": {"stars": 1, "best": 40}, "x": 5}
	var p := Progress.migrate(old)
	check(int(p["v"]) == Progress.VERSION, "version after migration")
	check(Progress.entry(p, "first_bed").get("stars", 0) == 3, "level 1 stars went to the wrong place")
	check(Progress.entry(p, "first_bed").get("crown", false), "record = ideal, but no crown")
	check(Progress.entry(p, "shady_corner").get("best", 0) == 27, "level 2 record")
	check(Progress.entry(p, "shady_corner").get("stars", 0) == Stars.count(27, 30), "stars not recomputed by the new thresholds")
	check(Progress.entry(p, "hills").get("stars", 0) >= 1, "old level 7 is \"Hills\", its stars dropped")
	check(Progress.entry(p, "fir_grove").is_empty(), "an extra level in progress")
	check(p["levels"].size() == 3, "a junk key was migrated")
	check(Progress.seen(p, "flowers") and Progress.seen(p, "tree"), "items of completed levels not marked as seen")
	# v2 -> v3: stars only grow, a crown never disappears
	var v2 := {"v": 2, "levels": {"first_bed": {"stars": 3, "best": 12}, "two_ponds": {"stars": 1, "best": 66, "crown": true}}}
	var p3 := Progress.migrate(v2)
	check(Progress.entry(p3, "first_bed").get("stars", 0) == 3, "stars dropped on recomputation")
	check(Progress.entry(p3, "two_ponds").get("crown", false), "the crown disappeared")
	check(Progress.entry(p3, "two_ponds").get("stars", 0) == Stars.count(66, 69), "stars of \"Two Ponds\" not recomputed")
	# a repeated migration changes nothing
	var again := Progress.migrate(p3)
	check(JSON.stringify(again) == JSON.stringify(p3), "a repeated migration changes the data")
	check(Progress.migrate(null)["levels"].is_empty(), "empty progress")
	var round = Progress.migrate(JSON.parse_string(JSON.stringify(p)))
	check(Progress.entry(round, "first_bed").get("stars", 0) == 3, "stars lost after JSON")


## Every item with rules has a name, a model, a letter for diagrams; letters don't repeat.
func _test_items_complete() -> void:
	var letters := {}
	for id in Scoring.RULES:
		check(Scoring.noun(id) != "noun." + id, "no name for %s" % id)
		check(not Items.info(id).is_empty(), "no item %s in the catalog" % id)
		var a := Items.abbr(id)
		check(a != "?" and not letters.has(a), "the letter %s of %s is empty or repeats" % [a, id])
		letters[a] = true
		var node := Items.build(id, 7)
		var sway := node.get_node_or_null("Sway")
		check(sway != null and sway.get_child_count() > 0, "model %s is empty" % id)
		node.free()
		check(Scoring.describe(id) != "", "empty card for %s" % id)


func _test_stars() -> void:
	for perfect in [3, 5, 10, 19, 30, 48, 69, 130]:
		var t := Stars.thresholds(perfect)
		check(t[0] <= t[1] and t[1] <= t[2] and t[2] < perfect, "thresholds %d: %s" % [perfect, t])
		check(Stars.metric_target(perfect) <= perfect, "bot goal %d" % perfect)
	check(Stars.thresholds(19)[2] == 17 and Stars.thresholds(69)[2] == 63, "92%% of the ideal rounds down")


func _test_unlock() -> void:
	var empty := Progress.empty()
	check(Progress.is_unlocked(0, empty), "the first level is locked")
	# a migrated player with progress on "First Bed" has its chapter fully unlocked
	var p := Progress.migrate({"0": {"stars": 2, "best": 17}})
	var i := Levels.index_of("first_bed")
	check(Progress.is_unlocked(i, p), "a level with progress is locked")
	var ch := (int(Levels.LEVELS[i]["slot"]) - 1) / 5
	for j in Levels.LEVELS.size():
		if (int(Levels.LEVELS[j]["slot"]) - 1) / 5 == ch:
			check(Progress.is_unlocked(j, p), "a chapter with progress is not fully unlocked (%s)" % Levels.LEVELS[j]["id"])
	# empty progress: only the first chapter with levels is unlocked, only spring is open
	var first_ch := (int(Levels.LEVELS[0]["slot"]) - 1) / 5
	for j in Levels.LEVELS.size():
		var c := (int(Levels.LEVELS[j]["slot"]) - 1) / 5
		check(Progress.is_unlocked(j, empty) == (c == first_ch), "unlocking of %s is wrong without progress" % Levels.LEVELS[j]["id"])
	for s in ["spring", "summer", "autumn", "winter"]:
		check(Progress.season_open(s, empty) == (s == "spring"), "season %s open state is wrong without progress" % s)
	# next_unlocked doesn't lead to a locked level
	for j in Levels.LEVELS.size():
		var nx := Progress.next_unlocked(j, p)
		check(nx == -1 or Progress.is_unlocked(nx, p), "\"Next\" leads to a locked level")
	_test_star_gate()


## Stage 13: a chapter opens by the sum of stars in the previous one (8 of 15 for five levels).
func _test_star_gate() -> void:
	var by_ch := Progress.chapters()
	for c in by_ch:
		check(by_ch[c].size() == 5, "chapter %d has %d levels (the gate assumes five)" % [c, by_ch[c].size()])
	check(Progress.chapter_need(by_ch[0]) == 8, "five levels need 8 stars")
	check(Progress.chapter_need(["a", "b", "c"]) == 5, "three levels need ceil(4.8) = 5 stars")
	check(Progress.chapter_need(["a"]) == 2, "one level needs ceil(1.6) = 2 stars")
	var cases := [[[1, 1, 1, 1, 1], false], [[2, 2, 1, 1, 1], false], [[2, 2, 2, 1, 1], true],
		[[2, 2, 2, 2, 0], true], [[3, 3, 1, 1, 0], true], [[3, 3, 1, 0, 0], false], [[3, 3, 2, 0, 0], true],
		[[3, 3, 3, 3, 3], true]]
	for cs in cases:
		var pr := Progress.empty()
		for k in 5:
			if cs[0][k] > 0:
				pr["levels"][by_ch[0][k]] = {"stars": cs[0][k], "best": 1, "crown": false}
		var opened := Progress.is_unlocked(Levels.index_of(by_ch[1][0]), pr)
		check(opened == cs[1], "stars %s: chapter 2 open = %s, expected %s" % [cs[0], opened, cs[1]])
		# "Next" from the last level of chapter 1 goes on only when chapter 2 is open
		var last := Levels.index_of(by_ch[0][4])
		check((Progress.next_unlocked(last, pr) >= 0) == cs[1], "\"Next\" at the end of chapter 1 with %s" % [cs[0]])
	# a full spring opens summer; spring at 7 stars in its last chapter keeps summer closed
	var sp := Progress.empty()
	for c in range(0, 5):
		for k in 5:
			sp["levels"][by_ch[c][k]] = {"stars": 2, "best": 1, "crown": false}
	check(Progress.season_open("summer", sp), "a two-star spring doesn't open summer")
	sp["levels"][by_ch[4][0]]["stars"] = 0
	sp["levels"][by_ch[4][1]]["stars"] = 1
	check(not Progress.season_open("summer", sp), "7 stars in the last spring chapter opened summer")
	# an old save (fixture, not the player's file): progress in later slots keeps those chapters open, the gaps stay
	# closed, and "Next" never jumps over a closed chapter
	var old := Progress.empty()
	for id in ["first_sprouts", "small_pond", "first_bush", "narrow_bed", "windy_bushes"]:
		old["levels"][id] = {"stars": 3, "best": 1, "crown": false}
	for id in ["first_bed", "shady_corner", "fir_grove", "evening_alley", "quiet_pond", "two_ponds"]:
		old["levels"][id] = {"stars": 2, "best": 1, "crown": false}
	var open := Progress.open_chapters(old)
	for id in old["levels"]:
		var li := Levels.index_of(id)
		check(li >= 0 and Progress.is_unlocked(li, old, open), "a level with old progress is locked: %s" % id)
	check(open.has(1) and not open.has(2), "the old save: chapter 2 should be open by stars and chapter 3 closed")
	check(Progress.season_open("summer", old, open), "the old save has summer progress but summer is closed")
	for j in Levels.LEVELS.size():
		var nx := Progress.next_unlocked(j, old)
		check(nx == -1 or nx == j + 1, "\"Next\" from %d jumps to %d" % [j + 1, nx + 1])
		if nx >= 0:
			check(open.has(Progress.chapter_of(Levels.LEVELS[nx])), "\"Next\" from %d leads to a closed chapter" % (j + 1))


## "Dead rules": on every level the cards of the items in the hand don't promise links to items not yet
## unlocked (otherwise the player looks for what isn't there — like a snowdrop's "stones +2" before stones).
func _test_no_dead_rules() -> void:
	for L in Levels.LEVELS:
		var known := Campaign.items_at(int(L["slot"]))
		var ids: Array = L["hand"].keys()
		for f in L.get("fixed", []):
			ids.append(f[2])
		for id in ids:
			check(id in known or L["slot"] >= 96, "%s: item %s not unlocked by slot %d yet" % [L["id"], id, L["slot"]])
			var text := Scoring.describe(id, known, bool(L.get("drought", false)))
			for other in Scoring.RULES:
				if other in known or other == id:
					continue
				var nm: String = Scoring.noun(other)
				check(not (" " + nm + " ") in (" " + text.replace(",", " ").replace(":", " ") + " "),
					"%s: the card of \"%s\" mentions the locked \"%s\"" % [L["id"], id, nm])
