extends RefCounted
## Player progress: {"v": 3, "levels": {id: {"stars": n, "best": n, "crown": bool}}, "seen": [item ids]}.
## v1 (before stage 2) — by level number {"0": {...}}: migrated using the old order.
## v2 -> v3 (stage 3): stars are recomputed by the new thresholds from the record (upward only), a crown for the ideal,
## "seen" — items the player has already met (for introducing novelties).

const Levels := preload("res://scripts/levels.gd")
const Stars := preload("res://scripts/stars.gd")

const VERSION := 3
const OLD_ORDER := ["first_bed", "shady_corner", "fir_grove", "quiet_pond", "kitchen_garden",
	"evening_alley", "hills", "tight_island", "two_ponds", "big_garden"]


static func empty() -> Dictionary:
	return {"v": VERSION, "levels": {}, "seen": []}


static func migrate(data) -> Dictionary:
	if not data is Dictionary:
		return empty()
	var v := int(data.get("v", 1))
	var levels := {}
	if v < 2:
		for key in data:
			var i := int(key) if String(key).is_valid_int() else -1
			if i < 0 or i >= OLD_ORDER.size() or not data[key] is Dictionary:
				continue
			levels[OLD_ORDER[i]] = {"stars": int(data[key].get("stars", 0)), "best": int(data[key].get("best", 0))}
	else:
		for id in data.get("levels", {}):
			var e: Dictionary = data["levels"][id]
			levels[String(id)] = {"stars": int(e.get("stars", 0)), "best": int(e.get("best", 0)), "crown": bool(e.get("crown", false))}
	var seen := {}
	for s in data.get("seen", []):
		seen[String(s)] = true
	# recompute by the current thresholds: stars only grow, a crown never disappears
	for id in levels:
		var e: Dictionary = levels[id]
		var li := Levels.index_of(id)
		if li < 0:
			continue
		var L: Dictionary = Levels.LEVELS[li]
		e["stars"] = maxi(int(e["stars"]), Stars.count(int(e["best"]), L["perfect"]))
		e["crown"] = bool(e.get("crown", false)) or int(e["best"]) >= int(L["perfect"])
		# everything in the hand of a completed level the player has already seen
		for item in L["hand"]:
			seen[item] = true
	return {"v": VERSION, "levels": levels, "seen": seen.keys()}


static func entry(progress: Dictionary, id: String) -> Dictionary:
	return progress.get("levels", {}).get(id, {})


## Unlocking (stage 13): a chapter (five slots) opens by the SUM of stars in the previous chapter — 8 of 15 for five
## levels ("every level ★ and three better", or ★★ on four and one level skipped). A chapter with fewer levels needs
## proportionally fewer (ceil(8/5 per level)). A chapter with any progress stays open entirely (nothing that was open
## gets locked); the first chapter is always open. A season is open when any of its chapters is open.
const NEED_PER_FIVE := 8


## Chapter index → the ids of its levels (slot order).
static func chapters() -> Dictionary:
	var by_ch := {}
	for L in Levels.LEVELS:
		var c := chapter_of(L)
		if not by_ch.has(c):
			by_ch[c] = []
		by_ch[c].append(L["id"])
	return by_ch


static func chapter_of(L: Dictionary) -> int:
	return (int(L["slot"]) - 1) / 5


static func chapter_stars(progress: Dictionary, ids: Array) -> int:
	var n := 0
	for id in ids:
		n += int(entry(progress, id).get("stars", 0))
	return n


## Stars the chapter with these levels must collect to open the next one.
static func chapter_need(ids: Array) -> int:
	return ceili(ids.size() * NEED_PER_FIVE / 5.0)


## The set of open chapters {index: true} — computed once per menu fill / result.
static func open_chapters(progress: Dictionary) -> Dictionary:
	var by_ch := chapters()
	var keys := by_ch.keys()
	keys.sort()
	var open := {}
	var prev := -1
	for c in keys:
		var ids: Array = by_ch[c]
		var ok := prev < 0
		if not ok:
			ok = chapter_stars(progress, by_ch[prev]) >= chapter_need(by_ch[prev])
		if not ok:
			for id in ids:
				if not entry(progress, id).is_empty():
					ok = true
					break
		if ok:
			open[c] = true
		prev = c
	return open


## Whether the level with index i (in Levels.LEVELS, in slot order) is unlocked.
static func is_unlocked(i: int, progress: Dictionary, open := {}) -> bool:
	if i < 0 or i >= Levels.LEVELS.size():
		return false
	if open.is_empty():
		open = open_chapters(progress)
	return open.has(chapter_of(Levels.LEVELS[i]))


## A season is open when any of its chapters is open.
static func season_open(season: String, progress: Dictionary, open := {}) -> bool:
	if open.is_empty():
		open = open_chapters(progress)
	for L in Levels.LEVELS:
		if L["season"] == season and open.has(chapter_of(L)):
			return true
	return false


## The next unlocked level after i (or -1). It doesn't jump over a closed chapter: an old save can have a later
## chapter open (by its progress) while the one in between is still closed — "Next" stops before the gap.
static func next_unlocked(i: int, progress: Dictionary) -> int:
	var j := i + 1
	if j >= Levels.LEVELS.size() or not open_chapters(progress).has(chapter_of(Levels.LEVELS[j])):
		return -1
	return j


## The farthest campaign slot where the player has already completed a garden (free garden seasons and rules, stage 7).
static func reached(progress: Dictionary) -> int:
	var best := 0
	for id in progress.get("levels", {}):
		var li := Levels.index_of(String(id))
		if li >= 0:
			best = maxi(best, int(Levels.LEVELS[li]["slot"]))
	return best


static func seen(progress: Dictionary, item: String) -> bool:
	return item in progress.get("seen", [])


static func mark_seen(progress: Dictionary, item: String) -> void:
	if not progress.has("seen"):
		progress["seen"] = []
	if not item in progress["seen"]:
		progress["seen"].append(item)
