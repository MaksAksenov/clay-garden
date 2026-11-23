extends RefCounted
## The campaign plan: seasons, chapters, item and mechanic unlocks, rule flags by slot, All Year Round and the free
## garden's seasons.

const SEASONS := [
	{"id": "spring", "name": "Spring", "from": 1, "to": 25},
	{"id": "summer", "name": "Summer", "from": 26, "to": 50},
	{"id": "autumn", "name": "Autumn", "from": 51, "to": 75},
	{"id": "winter", "name": "Winter", "from": 76, "to": 100},
]

const CHAPTERS := ["Sprouts", "Shade", "Stones and Pond", "Fir Grove", "Spring Garden",
	"Hilltop View", "Evening", "Drought and Bees", "Hammock", "Summer Garden",
	"Vegetable Patch", "Scarecrow", "Falling Leaves", "Haystack", "Harvest",
	"Ice and Snow", "Campfire", "Bird Feeder", "Winter Garden", "All Year Round"]

## Unlocks: level -> novelty. kind: item — an item, mech — a mechanic (a rule or terrain type).
const UNLOCKS := [
	{"lvl": 1, "kind": "item", "id": "flowers"}, {"lvl": 1, "kind": "mech", "id": "water"},
	{"lvl": 3, "kind": "item", "id": "bush"},
	{"lvl": 7, "kind": "item", "id": "tree"},   # the conflict of two trees teaches the "twist" at slot 8 — not a new rule type
	{"lvl": 9, "kind": "item", "id": "snowdrop"},
	{"lvl": 12, "kind": "item", "id": "rock"},
	{"lvl": 15, "kind": "item", "id": "lily"}, {"lvl": 15, "kind": "mech", "id": "on_water"},
	{"lvl": 18, "kind": "item", "id": "pine"},
	{"lvl": 20, "kind": "mech", "id": "fixed"},
	{"lvl": 21, "kind": "item", "id": "mushroom"},
	{"lvl": 23, "kind": "item", "id": "birdhouse"},
	{"lvl": 26, "kind": "item", "id": "bench"}, {"lvl": 26, "kind": "mech", "id": "view"},
	{"lvl": 31, "kind": "item", "id": "lantern"},
	{"lvl": 36, "kind": "mech", "id": "drought"},
	{"lvl": 38, "kind": "item", "id": "hive"}, {"lvl": 38, "kind": "mech", "id": "near"},
	{"lvl": 41, "kind": "item", "id": "hammock"}, {"lvl": 41, "kind": "mech", "id": "between"},
	{"lvl": 51, "kind": "item", "id": "pumpkin"},
	{"lvl": 34, "kind": "item", "id": "fence"},   # the fence unlocks in summer: the lantern and the bush like it (stage 4)
	{"lvl": 54, "kind": "mech", "id": "line"},
	{"lvl": 56, "kind": "item", "id": "scarecrow"},
	{"lvl": 61, "kind": "mech", "id": "leaf_fall"},
	{"lvl": 66, "kind": "item", "id": "haystack"},   # the "cap" is the haystack's own rule, not counted as a separate mechanic
	{"lvl": 76, "kind": "item", "id": "snowman"}, {"lvl": 76, "kind": "mech", "id": "winter"},
	{"lvl": 79, "kind": "mech", "id": "snow"},
	{"lvl": 81, "kind": "item", "id": "campfire"},
	{"lvl": 86, "kind": "item", "id": "feeder"},
	{"lvl": 96, "kind": "mech", "id": "year"},
]

## Campaign flags for conditional rules (stage 5): the fence row — from slot 54 on,
## falling leaves — from 61 to the end of autumn. A level without a slot (free garden, tests) has no flags.
static func flags_for(level: Dictionary) -> Array:
	var out := []
	if not level.has("slot"):
		return out
	var L := int(level["slot"])
	if L >= 54:
		out.append("line")
	if L >= 61 and L <= 75:
		out.append("leaf_fall")
	if L >= 76 and L <= 95:
		out.append("winter")   # water is ice, trees are bare (stage 6); All Year Round 96–100 is scored by seasons
	return out


## All Year Round (96–100, stage 6): one arrangement is scored by the four seasons, coziness is the sum.
## Only explicit seasonal differences count: water and ice, falling leaves, bare trees (no drought or cold).
## A seasonal item out of its season "sleeps" (0 own points, neighbors see it); in winter flowers, water lilies, mushrooms and pumpkins sleep too.
const YEAR_SEASONS := {
	"spring": {"flags": ["line"], "sleep": ["hive", "hammock", "scarecrow", "haystack", "snowman", "campfire", "feeder"]},
	"summer": {"flags": ["line"], "sleep": ["snowdrop", "birdhouse", "scarecrow", "haystack", "snowman", "campfire", "feeder"]},
	"autumn": {"flags": ["line", "leaf_fall"], "sleep": ["snowdrop", "birdhouse", "hive", "hammock", "snowman", "campfire", "feeder"]},
	"winter": {"flags": ["line", "winter"], "sleep": ["snowdrop", "birdhouse", "hive", "hammock", "scarecrow", "haystack",
		"flowers", "lily", "mushroom", "pumpkin"]},
}


## Free garden (stage 7): seasons unlock with progress — autumn after slot 51, winter after 76 (we don't spoil
## ice and bare trees before the "Winter is here" banner).
const SEASON_ORDER := ["spring", "summer", "autumn", "winter"]


static func sandbox_seasons(reached: int) -> Array:
	var out := ["spring", "summer"]
	if reached >= 51:
		out.append("autumn")
	if reached >= 76:
		out.append("winter")
	return out


## Free garden rule flags: only mechanics the player has already met (the honesty rule),
## and only seasonal differences (no drought or snowdrifts — those are level properties; no "sleep" — that's All Year Round).
static func sandbox_flags(season: String, reached: int) -> Array:
	var out := []
	if reached >= 54:
		out.append("line")
	if season == "autumn" and reached >= 61:
		out.append("leaf_fall")
	if season == "winter" and reached >= 76:
		out.append("winter")
	return out


static func is_year(level: Dictionary) -> bool:
	return level.has("slot") and int(level["slot"]) >= 96


## In winter (before All Year Round) these items are absent: flowers, water lilies, mushrooms, pumpkins — and the summer beehive and hammock
## (the bees sleep, the hammock is put away; they "sleep" in winter in All Year Round too — one rule, not two).
const WINTER_GONE := ["flowers", "lily", "mushroom", "pumpkin", "hive", "hammock"]


static func season_of(L: int) -> Dictionary:
	for s in SEASONS:
		if L >= s["from"] and L <= s["to"]:
			return s
	return SEASONS[-1]


static func novelties(L: int) -> Array:
	var out := []
	for u in UNLOCKS:
		if u["lvl"] == L:
			out.append(u)
	return out


## Items available at slot L.
static func items_at(L: int) -> Array[String]:
	var out: Array[String] = []
	var winter: bool = season_of(L)["id"] == "winter" and L < 96
	for u in UNLOCKS:
		if u["kind"] == "item" and u["lvl"] <= L:
			if winter and u["id"] in WINTER_GONE:
				continue
			out.append(u["id"])
	return out
