extends SceneTree
## The ideal in data = the engine: for each level the solver (with spare iterations) finds no more than the recorded perfect.
## If it does — the rules changed the level: a new id with replaces is needed (stage 5 defense).
## Run: Godot --headless --path . --script res://tests/test_perfect.gd

const Scoring := preload("res://scripts/scoring.gd")
const Levels := preload("res://scripts/levels.gd")
const Terrain := preload("res://scripts/terrain.gd")


func _init() -> void:
	var bad := 0
	for L in Levels.LEVELS:
		var m := Terrain.parse_map(L["map"])
		var off: Vector2i = m["off"]
		var fixed := {}
		for f in L.get("fixed", []):
			fixed[off + Vector2i(f[0], f[1])] = f[2]
		var n := 0
		for id in L["hand"]:
			n += int(L["hand"][id])
		var rng := RandomNumberGenerator.new()
		rng.seed = 777 + int(L["slot"])
		var res := Scoring.solve(L, m["land"], m["water"], fixed, 20000 + n * 4000, 2, rng)
		if res["best"] > int(L["perfect"]):
			bad += 1
			print("FAIL: %s (slot %d): the solver found %d, the data has %d" % [L["id"], L["slot"], res["best"], L["perfect"]])
	print("TESTS %s: %d levels, %d with an outdated ideal" % ["OK" if bad == 0 else "FAILED", Levels.LEVELS.size(), bad])
	quit(1 if bad > 0 else 0)
