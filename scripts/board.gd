extends RefCounted
## Board state for scoring coziness: what stands where and what the terrain is. Data only, no logic.
## Build a level board ONLY through the make()/for_level() factories: they account for level properties
## (season, drought). A manual Board.new() is for the free garden and tests. This way no place
## (game, solver, metric, generator) scores coziness "for a different game" (stage 4 defense).

const Terrain := preload("res://scripts/terrain.gd")
const Campaign := preload("res://scripts/campaign.gd")
const DRY_REACH := 2   # drought: a dry cell has no water within 2 steps (diamond)

var items: Dictionary    # cell -> item id
var land: Dictionary     # cell -> height (water cells are here too)
var water: Dictionary    # cell -> true
var season: String       # "" — no seasonal modifiers
var drought := false     # a level with a drought
var dry: Dictionary = {} # dry cells (only during a drought). Depends only on terrain — delta's reach doesn't change
var flags: Array = []    # campaign flags for conditional rules (line, leaf_fall) — from the level's slot
var rs: Dictionary = {}  # rule set for the flags (Scoring puts it here on the first count; immutable)
var snow: Dictionary = {} # the level's snowdrifts (winter): an item on a snowdrift without warmth within 2 steps gives 0
var winter := false      # winter: water is ice
var sleep: Dictionary = {} # items "asleep" this season: 0 own points, neighbors still see them (All Year Round)
var subs: Array = []     # All Year Round: four seasonal boards over ONE shared items dictionary; coziness is the sum

## Where an item can go — the ONLY placement rule for the game, solver, bot and generator (stage 6 defense).
const ON_WATER := ["lily"]          # water only (in winter — nowhere: the water is frozen)
const ON_LAND_OR_ICE := ["snowman"] # on land, and in winter on ice too (a skating rink)


func _init(p_items := {}, p_land := {}, p_water := {}, p_season := "") -> void:
	items = p_items
	land = p_land
	water = p_water
	season = p_season


## A level board from already parsed terrain (as the game and the solver have it).
static func make(p_items: Dictionary, p_land: Dictionary, p_water: Dictionary, level: Dictionary):
	var b = load("res://scripts/board.gd").new(p_items, p_land, p_water, String(level.get("season", "")))
	b.drought = bool(level.get("drought", false))
	b.flags = Campaign.flags_for(level)
	b.winter = "winter" in b.flags
	if Campaign.is_year(level):
		# one arrangement, four seasons; placement follows the summer terrain (ice affects only the points)
		for season in Campaign.YEAR_SEASONS:
			var sb = load("res://scripts/board.gd").new(p_items, p_land, p_water, season)
			sb.flags = Campaign.YEAR_SEASONS[season]["flags"]
			for id in Campaign.YEAR_SEASONS[season]["sleep"]:
				sb.sleep[id] = true
			b.subs.append(sb)
	for s in level.get("snow", []):
		var m := Terrain.parse_map(level["map"])
		b.snow[m["off"] + Vector2i(int(s[0]), int(s[1]))] = true
	if b.drought:
		b.dry = dry_cells(p_land, p_water)
	return b


## A level board straight from its map (fixed items already stand if items is empty).
static func for_level(level: Dictionary, p_items = null):
	var m := Terrain.parse_map(level["map"])
	var its := {}
	if p_items == null:
		var off: Vector2i = m["off"]
		for f in level.get("fixed", []):
			its[off + Vector2i(f[0], f[1])] = f[2]
	else:
		its = p_items
	return make(its, m["land"], m["water"], level)


## The free garden board (stage 7): the season is the garden's look, the flags follow the player's progress; placement
## uses the summer terrain (winter = false: no snowman on ice), so changing the season removes no item.
static func for_sandbox(p_items: Dictionary, p_land: Dictionary, p_water: Dictionary, p_season: String, reached: int):
	var b = load("res://scripts/board.gd").new(p_items, p_land, p_water, p_season)
	b.flags = Campaign.sandbox_flags(p_season, reached)
	return b


## Whether id can be placed on cell c (regardless of whether it is occupied).
static func placeable(id: String, c: Vector2i, p_land: Dictionary, p_water: Dictionary, p_winter: bool) -> bool:
	if not p_land.has(c):
		return false
	if id in ON_WATER:
		return p_water.has(c) and not p_winter
	if id in ON_LAND_OR_ICE:
		return not p_water.has(c) or p_winter
	return not p_water.has(c)


func can_place(id: String, c: Vector2i) -> bool:
	return placeable(id, c, land, water, winter)


static func dry_cells(p_land: Dictionary, p_water: Dictionary) -> Dictionary:
	var out := {}
	for c in p_land:
		if p_water.has(c):
			continue
		var wet := false
		for w in p_water:
			if absi(w.x - c.x) + absi(w.y - c.y) <= DRY_REACH:
				wet = true
				break
		if not wet:
			out[c] = true
	return out
