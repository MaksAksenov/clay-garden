extends RefCounted
## Campaign levels. Data is in data/levels.json (before stage 2 it was a constant here).
## Level fields:
##   id      — a permanent key (the player's progress is stored by it, not by number);
##   slot    — the campaign slot 1…100 (sorted by it); season — spring|summer|autumn|winter;
##   texts (name, hint) are in lang/<lang>.json by id: level.<id>.name / .hint (stage 8); map — the map (' ' empty, '1'…'4' height, '~' water);
##   hand    — what is given in the hand (key order matters: the palette and the solver use it);
##   fixed   — [[x, z, id], …] fixed items; perfect — the solver's ideal;
##   stars   — thresholds [★, ★★, ★★★]: not stored, computed from the ideal (scripts/stars.gd);
##   time    — an optional time of day.

const Stars := preload("res://scripts/stars.gd")

const PATH := "res://data/levels.json"

static var LEVELS: Array = _load()


static func _load() -> Array:
	var txt := FileAccess.get_file_as_string(PATH)
	var data = JSON.parse_string(txt)
	if not data is Array:
		push_error("Could not read " + PATH)
		return []
	var out := []
	for raw in data:
		out.append(_typed(raw))
	out.sort_custom(func(a, b): return a["slot"] < b["slot"])
	return out


## JSON gives numbers as float — convert everything to the right types.
static func _typed(raw: Dictionary) -> Dictionary:
	var L := {
		"id": String(raw["id"]),
		"slot": int(raw["slot"]),
		"season": String(raw.get("season", "")),
		"map": [],
		"hand": {},
		"stars": [],
		"perfect": int(raw["perfect"]),
	}
	for row in raw["map"]:
		L["map"].append(String(row))
	for id in raw["hand"]:
		L["hand"][String(id)] = int(raw["hand"][id])
	L["stars"] = Stars.thresholds(L["perfect"])
	if raw.has("fixed"):
		var fx := []
		for f in raw["fixed"]:
			fx.append([int(f[0]), int(f[1]), String(f[2])])
		L["fixed"] = fx
	if raw.has("time"):
		L["time"] = float(raw["time"])
	L["drought"] = bool(raw.get("drought", false))
	if raw.has("snow"):
		var sn := []
		for c in raw["snow"]:
			sn.append([int(c[0]), int(c[1])])
		L["snow"] = sn
	for key in ["D", "gen_seed", "legacy", "shape", "finale"]:
		if raw.has(key):
			L[key] = raw[key]
	return L


static func index_of(id: String) -> int:
	for i in LEVELS.size():
		if LEVELS[i]["id"] == id:
			return i
	return -1
