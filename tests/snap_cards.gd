extends SceneTree
## Reference for the Russian rules cards (stage 8): captured before the switch to keys; the test then compares byte for byte.
## Run: Godot --headless --path . --script res://tests/snap_cards.gd -- --out=res://tests/golden_cards_ru.json

const Scoring := preload("res://scripts/scoring.gd")
const Items := preload("res://scripts/items.gd")
const I18n := preload("res://scripts/i18n.gd")

const COMBOS := [
	{"flags": [], "drought": false, "snow": false},
	{"flags": [], "drought": true, "snow": false},
	{"flags": ["line"], "drought": false, "snow": false},
	{"flags": ["line", "leaf_fall"], "drought": false, "snow": false},
	{"flags": ["line", "winter"], "drought": false, "snow": false},
	{"flags": ["line", "winter"], "drought": false, "snow": true},
]
const KNOWN_SETS := [[], ["tree", "bush", "flowers", "pine", "bench", "lantern"]]


static func snapshot() -> Dictionary:
	var out := {}
	for info in Items.CATALOG:
		var id: String = info["id"]
		for ci in COMBOS.size():
			var cb: Dictionary = COMBOS[ci]
			for ki in KNOWN_SETS.size():
				out["%s|%d|%d" % [id, ci, ki]] = Scoring.describe(id, KNOWN_SETS[ki], cb["drought"], cb["flags"], cb["snow"])
	return out


func _init() -> void:
	I18n.set_lang("ru")   # the reference is the Russian cards (I18n defaults to English)
	var path := "res://tests/golden_cards_ru.json"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			path = a.substr(6)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(snapshot(), "\t", true))
	f.close()
	print("cards: %d -> %s" % [snapshot().size(), path])
	quit()
