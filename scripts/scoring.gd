extends RefCounted
## Coziness rules. Every item gives 1 point on its own plus points (or minuses) by its rules.
## Rules are data: RULES[id] = a list of rules of different types. On first access they are validated
## and converted into a fast form (_compiled) so the solver doesn't compare strings in the hot loop.
##
## Rule types:
##   {"t": "adj",     "of": id, "v": n}             — for each neighbor id on the 4 sides
##   {"t": "water",   "v": n}                        — for each water cell on the 4 sides
##   {"t": "view",    "v": n}                        — if the cell is higher than all neighboring island cells
##   {"t": "near",    "of": id, "r": 2, "v": n}      — for each id within r steps by the sides (a diamond)
##   {"t": "between", "of": [id, ...], "v": n}       — if items from the list stand on two opposite sides
##                                                    (counted once, even if the pattern is on both axes)
##   {"t": "thirst"}                                  — drought: on a dry cell (Board.dry) the item gives 0 — of its own points;
##                                                    neighbors still see it. Applies only on drought levels

const Board := preload("res://scripts/board.gd")

const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const BASE := 1
const VIEW_BONUS := 2        # a bench higher than all neighboring cells
const ON_WATER := ["lily"]   # placed only on water
const INCREMENTAL_FROM := 16   # from how many items the solver evaluates a move through delta (stage 2 measurement)

const RULES := {
	"tree": [{"t": "adj", "of": "bush", "v": 2}, {"t": "adj", "of": "flowers", "v": 1},
		{"t": "adj", "of": "tree", "v": -1, "unless": "winter"}, {"t": "adj", "of": "pine", "v": -1}],
	"pine": [{"t": "adj", "of": "pine", "v": 2}, {"t": "adj", "of": "mushroom", "v": 1}],
	"bush": [{"t": "adj", "of": "tree", "v": 1}, {"t": "adj", "of": "fence", "v": 1}, {"t": "adj", "of": "flowers", "v": 1}],
	"flowers": [{"t": "adj", "of": "flowers", "v": 1}, {"t": "water", "v": 2}, {"t": "adj", "of": "bench", "v": 1},
		{"t": "thirst"}],
	"mushroom": [{"t": "adj", "of": "pine", "v": 2}, {"t": "adj", "of": "tree", "v": 2}, {"t": "adj", "of": "lantern", "v": -2}],
	"rock": [{"t": "water", "v": 2}, {"t": "adj", "of": "rock", "v": 1}, {"t": "ice", "v": 1}],
	"pumpkin": [{"t": "adj", "of": "fence", "v": 2}, {"t": "adj", "of": "pumpkin", "v": 1},
		{"t": "adj", "of": "tree", "v": -1, "unless": "leaf_fall"}, {"t": "adj", "of": "tree", "v": 1, "when": "leaf_fall"},
		{"t": "near", "of": "scarecrow", "r": 2, "v": 1}],
	"fence": [{"t": "adj", "of": "fence", "v": 1}, {"t": "adj", "of": "pumpkin", "v": 1}, {"t": "adj", "of": "bush", "v": 1},
		{"t": "line", "min": 3, "v": 1, "when": "line"}],
	"bench": [{"t": "water", "v": 2}, {"t": "adj", "of": "flowers", "v": 1}, {"t": "adj", "of": "lantern", "v": 2},
		{"t": "adj", "of": "tree", "v": 1}, {"t": "view", "v": VIEW_BONUS}, {"t": "adj", "of": "hive", "v": -2},
		{"t": "ice", "v": 1}, {"t": "adj", "of": "campfire", "v": 2}],
	"lantern": [{"t": "adj", "of": "bench", "v": 2}, {"t": "adj", "of": "fence", "v": 1}, {"t": "adj", "of": "lantern", "v": -2}],
	"lily": [{"t": "adj", "of": "lily", "v": 1}, {"t": "adj", "of": "flowers", "v": 2}, {"t": "adj", "of": "rock", "v": 1}],
	# spring (stage 3): the snowdrop grows under bushes and likes water; birdhouses are crowded next to each other
	"snowdrop": [{"t": "adj", "of": "bush", "v": 2}, {"t": "water", "v": 1}, {"t": "adj", "of": "rock", "v": 1},
		{"t": "adj", "of": "tree", "v": -1}],
	"birdhouse": [{"t": "adj", "of": "tree", "v": 2}, {"t": "adj", "of": "bush", "v": 1}, {"t": "adj", "of": "birdhouse", "v": -2},
		{"t": "near", "of": "scarecrow", "r": 2, "v": -2}],
	# summer (stage 4): flowers around feed the beehive (diagonals too); the hammock is strung between two trees
	"hive": [{"t": "near", "of": "flowers", "r": 2, "v": 1}],
	"hammock": [{"t": "between", "of": ["tree", "pine"], "v": 5}, {"t": "water", "v": 1}],
	# autumn (stage 5): the scarecrow GIVES — pumpkins next to it get +1 (their rule), birds −2; the haystack counts no more than two neighbors
	"scarecrow": [],
	"haystack": [{"t": "cap", "of": ["pumpkin", "fence"], "max": 2, "v": 2}],
	# winter (stage 6): the snowman likes snow and ice under it, melts near warmth; the campfire gathers benches; the feeder likes firs
	"snowman": [{"t": "on", "what": ["snow", "ice"], "v": 2}, {"t": "adj", "of": "pine", "v": 1},
		{"t": "near", "of": "lantern", "r": 2, "v": -3}, {"t": "near", "of": "campfire", "r": 2, "v": -3}],
	"campfire": [{"t": "adj", "of": "bench", "v": 2}],
	"feeder": [{"t": "adj", "of": "pine", "v": 2}, {"t": "adj", "of": "tree", "v": 1}, {"t": "adj", "of": "birdhouse", "v": 1},
		{"t": "adj", "of": "campfire", "v": -2}],
}

## Cold (winter): an item on a snowdrift gives 0 of its own points if there is no heat source within WARM_R steps.
## Heat sources and the snowman don't freeze; neighbors of a frozen item still see it.
const I18n := preload("res://scripts/i18n.gd")
const WARMTH := ["lantern", "campfire"]
const NO_FREEZE := ["lantern", "campfire", "snowman"]
const WARM_R := 2

## Words for card phrases come from the language dictionary (scripts/i18n.gd, lang/*.json): noun.<id>.
static func noun(id: String) -> String:
	return I18n.t("noun." + id)

const TYPES := ["adj", "water", "view", "near", "between", "thirst", "line", "cap", "ice", "on"]
const FLAGS := ["line", "leaf_fall", "winter"]   # campaign flags (when / unless); drought — via Board.dry, snowdrifts — Board.snow
const EMPTY := {"adj": {}, "water": 0, "view": 0, "near": [], "between": [], "thirst": false, "line": [], "cap": [], "on": [], "simple": true}
static var _warm_offs: Array[Vector2i] = _diamond(WARM_R)


static func _diamond(rad: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dz in range(-rad, rad + 1):
		for dx in range(-rad, rad + 1):
			if (dx != 0 or dz != 0) and absi(dx) + absi(dz) <= rad:
				out.append(Vector2i(dx, dz))
	return out


## Whether there is warmth (a lantern or campfire) within WARM_R steps of cell c.
static func warm_at(c: Vector2i, items: Dictionary) -> bool:
	for o in _warm_offs:
		if items.get(c + o, "") in WARMTH:
			return true
	return false

static var _rules: Dictionary = RULES
static var _cache: Dictionary = {}       # flags key -> rule set (immutable; a board keeps a reference to its own)
static var errors: Array[String] = []   # errors in the rule data; the test requires there are none


## Substitute the rule set (for tests). An empty dictionary — back to RULES.
static func use_rules(rules: Dictionary) -> void:
	_rules = rules if not rules.is_empty() else RULES
	_cache = {}


## Validate the rules (all of them, regardless of flags) and reset the rule set cache.
static func compile() -> void:
	errors.clear()
	_cache = {}
	_build([], true)


## The rule set for a level's flags. A set doesn't change after it is built, so different boards
## (game, solver, generator, report) never share switchable global state.
static func ruleset(flags: Array) -> Dictionary:
	var f := flags.duplicate()
	f.sort()
	var key := ",".join(f)
	if not _cache.has(key):
		_cache[key] = _build(f, false)
	return _cache[key]


static func _rs(b: Board) -> Dictionary:
	if b.rs.is_empty():
		b.rs = ruleset(b.flags)
	return b.rs


static func _active(r: Dictionary, flags: Array) -> bool:
	if r.has("when") and not r["when"] in flags:
		return false
	if r.has("unless") and r["unless"] in flags:
		return false
	return true


static func _build(flags: Array, validate: bool) -> Dictionary:
	var comp := {}
	var own := {}
	var far := {}   # id -> {which item the far rule is about: radius} — whom the item "sees" beyond its neighbors
	var known := {"water": true}
	for id in _rules:
		known[id] = true
	for id in _rules:
		var c := {"adj": {}, "water": 0, "view": 0, "near": [], "between": [], "thirst": false, "line": [], "cap": [], "on": []}
		var reach := 1
		var fr := {}
		var winter: bool = "winter" in flags
		for r in _rules[id]:
			var t: String = r.get("t", "")
			if validate:
				for key in ["when", "unless"]:
					if r.has(key) and not r[key] in FLAGS:
						_bad("%s: unknown flag \"%s\" in %s" % [id, r[key], key])
			if not t in TYPES:
				if validate:
					_bad("%s: unknown rule type \"%s\"" % [id, t])
				continue
			if not _active(r, flags) and not validate:
				continue
			if t == "thirst":
				if validate and r.size() != 1:
					_bad("%s: the drought rule takes no parameters" % id)
				c["thirst"] = true
				continue
			if not r.has("v"):
				if validate:
					_bad("%s: rule %s has no points v" % [id, t])
				continue
			var v: int = r["v"]
			match t:
				"adj":
					if not known.has(r.get("of", "")):
						if validate:
							_bad("%s: unknown neighbor \"%s\"" % [id, r.get("of", "")])
						continue
					c["adj"][r["of"]] = c["adj"].get(r["of"], 0) + v
				"water":
					if not winter or validate:   # in winter the water is frozen: every "water nearby" rule is switched off here, in one place
						c["water"] += v
				"ice":
					if winter and not validate:  # ice nearby — only in winter (for stones and the bench: a rink)
						c["water"] += v
				"on":
					var on := {}
					for w in r.get("what", []):
						if validate and not w in ["snow", "ice"]:
							_bad("%s: unknown terrain \"%s\" in on" % [id, w])
						if w == "snow" or (w == "ice" and winter):
							on[w] = true
					if not on.is_empty():
						c["on"].append([on, v])
				"view":
					c["view"] += v
				"near":
					if not known.has(r.get("of", "")):
						if validate:
							_bad("%s: unknown item \"%s\" in near" % [id, r.get("of", "")])
						continue
					var rad: int = r.get("r", 2)
					var offs: Array[Vector2i] = []
					for dz in range(-rad, rad + 1):
						for dx in range(-rad, rad + 1):
							if (dx != 0 or dz != 0) and absi(dx) + absi(dz) <= rad:
								offs.append(Vector2i(dx, dz))
					c["near"].append([r["of"], offs, v])
					reach = maxi(reach, rad)
					fr[r["of"]] = maxi(int(fr.get(r["of"], 0)), rad)
				"between":
					var set := {}
					for o in r.get("of", []):
						if validate and not known.has(o):
							_bad("%s: unknown item \"%s\" in between" % [id, o])
						set[o] = true
					c["between"].append([set, v])
				"line":
					var mn: int = r.get("min", 3)
					c["line"] = [mn, v]
					reach = maxi(reach, mn - 1)   # a row of mn is seen mn−1 cells in each direction
					fr[id] = maxi(int(fr.get(id, 0)), mn - 1)
				"cap":
					var cset := {}
					for o in r.get("of", []):
						if validate and not known.has(o):
							_bad("%s: unknown item \"%s\" in cap" % [id, o])
						cset[o] = true
					c["cap"].append([cset, int(r.get("max", 2)), v])
		c["simple"] = c["near"].is_empty() and c["between"].is_empty() and c["line"].is_empty() and c["cap"].is_empty() and c["on"].is_empty()
		if winter and not id in NO_FREEZE:
			# a freezing item "sees" heat sources 2 steps away: delta recounts it when they are placed nearby
			fr["lantern"] = maxi(int(fr.get("lantern", 0)), WARM_R)
			fr["campfire"] = maxi(int(fr.get("campfire", 0)), WARM_R)
			reach = maxi(reach, WARM_R)
		comp[id] = c
		own[id] = reach
		far[id] = fr
	var maxr := 1
	for id in own:
		maxr = maxi(maxr, own[id])
	var reach_offs: Array[Vector2i] = []
	var reach_d: Array[int] = []
	for dz in range(-maxr, maxr + 1):
		for dx in range(-maxr, maxr + 1):
			if (dx != 0 or dz != 0) and absi(dx) + absi(dz) <= maxr:
				reach_offs.append(Vector2i(dx, dz))
				reach_d.append(absi(dx) + absi(dz))
	return {"comp": comp, "own": own, "far": far, "reach": reach_offs, "reach_d": reach_d, "flags": flags}


## The fast form of an item's rules (for hints on the field: radius, pattern, drought, row).
static func compiled(id: String, b: Board = null) -> Dictionary:
	var rs: Dictionary = _rs(b) if b != null else ruleset([])
	return rs["comp"].get(id, EMPTY)


static func _bad(msg: String) -> void:
	errors.append(msg)
	push_error("Coziness rules: " + msg)


## Points of item id on cell c. src (dictionary cell -> points) — where to record how much came from which cell.
static func item_points(id: String, c: Vector2i, b: Board, src = null) -> int:
	if not b.subs.is_empty():
		var sum := 0
		for sb in b.subs:
			sum += item_points(id, c, sb, src)
		return sum
	return _points(id, c, b.items, b.land, b.water, b.dry, src, _rs(b)["comp"], b.snow, b.sleep)


## The scoring core: dictionaries directly, no access to Board fields (the solver's hot path).
static func _points(id: String, c: Vector2i, items: Dictionary, land: Dictionary, water: Dictionary, dry: Dictionary, src, comp: Dictionary, snow: Dictionary = {}, sleep: Dictionary = {}) -> int:
	var r: Dictionary = comp.get(id, EMPTY)
	if not sleep.is_empty() and sleep.has(id):
		return 0   # All Year Round: a seasonal item out of its season sleeps
	if not dry.is_empty() and r["thirst"] and dry.has(c):
		return 0   # drought: the item itself gives nothing on a dry cell (neighbors see it — those are their rules)
	if not snow.is_empty() and snow.has(c) and not id in NO_FREEZE and not warm_at(c, items):
		return 0   # cold: on a snowdrift without warmth nearby the item freezes and gives nothing
	var adj: Dictionary = r["adj"]
	var wv: int = r["water"]
	var p := BASE
	for d in DIRS:
		var n: Vector2i = c + d
		var v := 0
		if wv != 0 and water.has(n):
			v += wv
		if items.has(n):
			v += adj.get(items[n], 0)
		if v != 0:
			p += v
			if src != null:
				src[n] = src.get(n, 0) + v
	var vv: int = r["view"]
	if vv != 0 and has_view(c, land):
		p += vv
	if r["simple"]:
		return p   # no radius, pattern, row, cap or "stands on" — the solver's hot path
	for on in r["on"]:
		var what: Dictionary = on[0]
		if (what.has("snow") and snow.has(c)) or (what.has("ice") and water.has(c)):
			p += int(on[1])
	for nr in r["near"]:
		var of: String = nr[0]
		var nv: int = nr[2]
		for o in nr[1]:
			var n: Vector2i = c + o
			if items.get(n, "") == of:
				p += nv
				if src != null:
					src[n] = src.get(n, 0) + nv
	for bt in r["between"]:
		var set: Dictionary = bt[0]
		var bv: int = bt[1]
		for k in 2:
			var a: Vector2i = c + DIRS[k * 2]
			var z: Vector2i = c + DIRS[k * 2 + 1]
			if set.has(items.get(a, "")) and set.has(items.get(z, "")):
				p += bv
				if src != null:
					src[a] = src.get(a, 0) + bv / 2
					src[z] = src.get(z, 0) + bv - bv / 2
				break   # the pattern counts once
	var ln: Array = r["line"]
	if not ln.is_empty():
		var lv: int = ln[1]
		for k in 2:
			var run := 1
			var first := Vector2i(-9999, -9999)
			for side in [DIRS[k * 2], DIRS[k * 2 + 1]]:
				for step in range(1, ln[0]):
					var n: Vector2i = c + side * step
					if items.get(n, "") != id:
						break
					run += 1
					if first.x == -9999:
						first = n
			if run >= ln[0]:
				p += lv
				if src != null:
					src[first] = src.get(first, 0) + lv
				break   # a row counts once, even at a crossing
	for cp in r["cap"]:
		var cset: Dictionary = cp[0]
		var mx: int = cp[1]
		var cv: int = cp[2]
		var k := 0
		for d in DIRS:
			var n: Vector2i = c + d
			if cset.has(items.get(n, "")):
				k += 1
				if k <= mx:
					p += cv
					if src != null:
						src[n] = src.get(n, 0) + cv
	return p


## A bench "with a view": higher than all neighboring island cells.
static func has_view(c: Vector2i, land: Dictionary) -> bool:
	var h: int = land.get(c, 0)
	var any := false
	for d in DIRS:
		var n: Vector2i = c + d
		if land.has(n):
			any = true
			if land[n] >= h:
				return false
	return any


static func total(b: Board) -> int:
	if not b.subs.is_empty():
		var sum := 0
		for sb in b.subs:
			sum += total(sb)
		return sum
	var comp: Dictionary = _rs(b)["comp"]
	var sleep := b.sleep
	var items := b.items
	var land := b.land
	var water := b.water
	var dry := b.dry
	var snow := b.snow
	var s := 0
	for c in items:
		s += _points(items[c], c, items, land, water, dry, null, comp, snow, sleep)
	return s


## The gain in total coziness if id is placed on the empty cell c. Recounts only the items
## reached by their own rules; the result equals the difference of two totals (the test checks this).
static func delta(id: String, c: Vector2i, b: Board) -> int:
	if not b.subs.is_empty():
		var sum := 0
		for sb in b.subs:
			sum += delta(id, c, sb)
		return sum
	var rs := _rs(b)
	var sleep := b.sleep
	var comp: Dictionary = rs["comp"]
	var reach: Array = rs["reach"]
	var reach_d: Array = rs["reach_d"]
	var far: Dictionary = rs["far"]
	var items := b.items
	var land := b.land
	var water := b.water
	var dry := b.dry
	var snow := b.snow
	var d := 0
	var touched: Array[Vector2i] = []
	for k in reach.size():
		var n: Vector2i = c + reach[k]
		# a side neighbor is always recounted; a far one — only if its far rule is about the item being placed
		if items.has(n) and (int(reach_d[k]) <= 1 or int(far[items[n]].get(id, 0)) >= int(reach_d[k]) if far.has(items[n]) else int(reach_d[k]) <= 1):
			touched.append(n)
			d -= _points(items[n], n, items, land, water, dry, null, comp, snow, sleep)
	items[c] = id
	d += _points(id, c, items, land, water, dry, null, comp, snow, sleep)
	for n in touched:
		d += _points(items[n], n, items, land, water, dry, null, comp, snow, sleep)
	items.erase(c)
	return d


## What changes if id is placed on the empty cell c.
## delta — the total coziness gain (honestly: the difference of two counts).
## marks — marks per source cell: how much the new item gets from that cell
## plus how much the points of the item standing there change.
static func preview(id: String, c: Vector2i, b: Board) -> Dictionary:
	var src := {}
	var delta := item_points(id, c, b, src)
	var before := {}
	for o in b.items:
		before[o] = item_points(b.items[o], o, b)
	b.items[c] = id
	for o in before:
		var dv: int = item_points(b.items[o], o, b) - before[o]
		if dv != 0:
			delta += dv
			src[o] = src.get(o, 0) + dv
	b.items.erase(c)
	var marks := {}
	for n in src:
		if src[n] != 0:
			marks[n] = src[n]
	return {"delta": delta, "marks": marks}


# ---------------------------------------------------------------- rules card

static func _name(id) -> String:
	if id is Array:
		var parts := []
		for x in id:
			parts.append(noun(x))
		return I18n.t("list.or").join(parts)
	return noun(id)


## A human phrase for a rule. adj and water — short, for the "for each neighbor" list.
static func phrase(r: Dictionary) -> String:
	var v: int = r.get("v", 0)
	var sv := I18n.signed(v)
	match r.get("t", ""):
		"adj":
			var leaf := I18n.t("card.leaf_suffix") if r.get("when", "") == "leaf_fall" else ""
			return I18n.t("card.adj", {"item": _name(r["of"]), "v": sv}) + leaf
		"water":
			return I18n.t("card.adj", {"item": noun("water"), "v": sv})
		"view":
			return I18n.t("card.view", {"v": sv})
		"near":
			return I18n.t("card.near", {"item": I18n.cap_first(_name(r["of"])), "r": int(r.get("r", 2)), "v": sv})
		"between":
			return I18n.t("card.between", {"v": sv, "items": _name(r["of"])})
		"thirst":
			return I18n.t("card.thirst")
		"line":
			return I18n.t("card.line", {"n": int(r.get("min", 3)), "v": sv})
		"cap":
			return I18n.t("card.cap", {"items": I18n.cap_first(_name(r["of"])), "v": sv, "max": int(r.get("max", 2))})
		"ice":
			return I18n.t("card.adj", {"item": noun("ice"), "v": sv})
		"on":
			var w := []
			for x in r.get("what", []):
				w.append(I18n.t("terrain.on." + String(x)))
			return I18n.t("card.on", {"where": I18n.t("list.or").join(w), "v": sv})
	return ""


## Rules text for the hint. known — which items the player has already unlocked (empty — all):
## rules about items not yet unlocked are not shown, so as not to confuse or reveal ahead.
static func describe(id: String, known: Array = [], drought := false, flags: Array = [], snow := false) -> String:
	var frozen := false
	var likes := []
	var dislikes := []
	var extra := []
	for r in _rules.get(id, []):
		var t: String = r.get("t", "")
		if not _active(r, flags):
			continue   # a conditional rule is shown only where it applies
		if t == "ice" and not "winter" in flags:
			continue   # ice happens only in winter
		if t == "water" and "winter" in flags:
			frozen = true   # in winter "water nearby" doesn't apply — we say so in a line below
			continue
		if t == "thirst" and not drought:
			continue   # the drought phrase — only on drought levels
		if not known.is_empty() and r.has("of"):
			var of = r["of"]
			if of is String and not of in known:
				continue
			if of is Array and of.filter(func(o): return o in known).is_empty():
				continue
		if t == "adj" or t == "water" or t == "ice":
			if int(r.get("v", 0)) > 0:
				likes.append(phrase(r))
			else:
				dislikes.append(phrase(r))
		else:
			extra.append(phrase(r))
	var lines := []
	var sep := I18n.t("list.sep")
	if likes.size() > 0:
		lines.append(I18n.t("card.likes", {"list": sep.join(likes)}))
	if dislikes.size() > 0:
		lines.append(I18n.t("card.dislikes", {"list": sep.join(dislikes)}))
	lines.append_array(extra)
	# what the item gives others at a distance (radius rules of neighbors): the scarecrow has no rules of its own — it gives
	for other in _rules:
		if other == id or (not known.is_empty() and not other in known):
			continue
		for r in _rules[other]:
			if r.get("t", "") == "near" and r.get("of", "") == id and _active(r, flags):
				lines.append(I18n.t("card.gives", {"item": I18n.cap_first(_name(other)), "r": int(r.get("r", 2)), "v": I18n.signed(int(r.get("v", 0)))}))
	if frozen:
		lines.append(I18n.t("card.frozen"))
	if snow and not id in NO_FREEZE:
		lines.append(I18n.t("card.freezes"))
	if snow and id in WARMTH:
		lines.append(I18n.t("card.warms"))
	if id in ON_WATER:
		lines.append(I18n.t("card.water_only"))
	if id == "snowman":
		lines.append(I18n.t("card.on_ice"))
	return "\n".join(lines)


# ---------------------------------------------------------------- solver
## Simulated annealing: finds the best arrangement of the hand on a level. Needed to set star thresholds honestly.

static func solve(level: Dictionary, terrain_land: Dictionary, terrain_water: Dictionary, fixed: Dictionary, iters: int, restarts: int, rng: RandomNumberGenerator) -> Dictionary:
	var hand: Array[String] = []
	for id in level["hand"]:
		for i in int(level["hand"][id]):
			hand.append(id)
	var land_cells: Array[Vector2i] = []
	var water_cells: Array[Vector2i] = []
	for c in terrain_land:
		if fixed.has(c):
			continue
		if terrain_water.has(c):
			water_cells.append(c)
		else:
			land_cells.append(c)
	var ice_cells: Array[Vector2i] = land_cells + water_cells   # snowman in winter: land and ice
	var cls: Array[int] = []
	var cells_of: Array = []
	var best := -999999
	var best_items := {}
	var incremental := hand.size() + fixed.size() > INCREMENTAL_FROM
	for r in restarts:
		var items := fixed.duplicate()
		var b = Board.make(items, terrain_land, terrain_water, level)
		var pos: Array[Vector2i] = []
		var free_land := land_cells.duplicate()
		var free_water := water_cells.duplicate()
		_shuffle(free_land, rng)
		_shuffle(free_water, rng)
		for id in hand:
			var pool := free_water if id in Board.ON_WATER else free_land
			var c: Vector2i = pool.pop_back()
			items[c] = id
			pos.append(c)
		var cur := total(b)
		# the placement class and cells — once per hand item (the hot loop doesn't check lists)
		if cells_of.is_empty():
			for hid in hand:
				var c_cls := 1 if hid in Board.ON_WATER else (2 if hid in Board.ON_LAND_OR_ICE and b.winter else 0)
				cls.append(c_cls)
				cells_of.append(water_cells if c_cls == 1 else (ice_cells if c_cls == 2 else land_cells))
		for i in iters:
			var temp := lerpf(2.5, 0.05, float(i) / iters)
			var k := rng.randi() % hand.size()
			var id := hand[k]
			var from := pos[k]
			var cells: Array[Vector2i] = cells_of[k]
			var to: Vector2i = cells[rng.randi() % cells.size()]
			if to == from:
				continue
			var j := pos.find(to)
			if j >= 0 and hand[j] == id:
				continue
			if j >= 0 and cls[j] != cls[k] and not b.can_place(hand[j], from):
				continue   # a swap after which an item would end up where it can't be placed
			# move: put k into to (if occupied — swap them).
			# On big boards the gain is computed step by step via delta, on small ones a full recount is cheaper.
			# The result is identical to the point, so the annealing trajectory is the same.
			var nxt := 0
			if incremental:
				items.erase(from)
				var step := -delta(id, from, b)
				if j >= 0:
					var jd: String = hand[j]
					items.erase(to)
					step -= delta(jd, to, b)
					step += delta(jd, from, b)
					items[from] = jd
					pos[j] = from
				step += delta(id, to, b)
				items[to] = id
				pos[k] = to
				nxt = cur + step
			else:
				items.erase(from)
				if j >= 0:
					items[from] = hand[j]
					pos[j] = from
				items[to] = id
				pos[k] = to
				nxt = total(b)
			if nxt >= cur or rng.randf() < exp((nxt - cur) / temp):
				cur = nxt
				if cur > best:
					best = cur
					best_items = items.duplicate()
			else:
				items.erase(to)
				if j >= 0:
					items[to] = hand[j]
					pos[j] = to
					items.erase(from)
				items[from] = id
				pos[k] = from
		if cur > best:
			best = cur
			best_items = items.duplicate()
	return {"best": best, "items": best_items}


static func _shuffle(a: Array, rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = a[i]
		a[i] = a[j]
		a[j] = tmp
