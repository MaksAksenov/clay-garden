extends RefCounted
## The garden's item catalog. Each item is modeled from primitives; the seed adds variety,
## so the preview ghost and the placed item match exactly.

const C := preload("res://scripts/clay.gd")

const CATALOG := [
	{"id": "tree", "abbr": "T", "sway": 0.035, "scale": 1.3},
	{"id": "pine", "abbr": "P", "sway": 0.025, "scale": 1.3},
	{"id": "bush", "abbr": "B", "sway": 0.03, "scale": 1.35},
	{"id": "flowers", "abbr": "F", "sway": 0.09, "scale": 1.45},
	{"id": "mushroom", "abbr": "M", "sway": 0.0, "scale": 1.55},
	{"id": "rock", "abbr": "R", "sway": 0.0, "scale": 1.35},
	{"id": "pumpkin", "abbr": "U", "sway": 0.0, "scale": 1.55},
	{"id": "fence", "abbr": "=", "sway": 0.0, "rotatable": true},
	{"id": "bench", "abbr": "S", "sway": 0.0, "rotatable": true, "scale": 1.1},
	{"id": "lantern", "abbr": "L", "sway": 0.0, "scale": 1.2},
	{"id": "lily", "abbr": "o", "sway": 0.0, "water": true, "scale": 1.25},
	{"id": "snowdrop", "abbr": "d", "sway": 0.07, "scale": 1.95},
	{"id": "birdhouse", "abbr": "h", "sway": 0.0, "scale": 1.45},
	{"id": "hive", "abbr": "H", "sway": 0.0, "scale": 1.35},
	{"id": "hammock", "abbr": "A", "sway": 0.0, "rotatable": true, "scale": 1.1},
	{"id": "scarecrow", "abbr": "C", "sway": 0.02, "scale": 1.25},
	{"id": "haystack", "abbr": "Y", "sway": 0.0, "scale": 1.3},
	{"id": "snowman", "abbr": "N", "sway": 0.0, "scale": 1.3},
	{"id": "campfire", "abbr": "K", "sway": 0.0, "scale": 1.3},
	{"id": "feeder", "abbr": "E", "sway": 0.0, "scale": 1.3},
]

const TRUNK := Color("8d5b3e")
const LEAVES := [Color("74c25c"), Color("62b356"), Color("8fd062")]
const AUTUMN := [Color("f2a444"), Color("e8803c"), Color("f4c752")]
const PINE := [Color("3f9160"), Color("327f58"), Color("4b9e66")]
const PETALS := [Color("f78fb3"), Color("c39bff"), Color("ffd166"), Color("ff8a65"), Color("fff8f0"), Color("7ec8ff")]
const STEM := Color("5aa84f")


## The item's letter for ASCII solution diagrams (generator, solver).
static func abbr(id: String) -> String:
	return info(id).get("abbr", "?")


static func info(id: String) -> Dictionary:
	for d in CATALOG:
		if d["id"] == id:
			return d
	return {}


static func build(id: String, seed_value: int, season: String = "", leaf_fall := false) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var root := Node3D.new()
	var sway := Node3D.new()
	sway.name = "Sway"
	root.add_child(sway)
	match id:
		"tree": _tree(sway, rng, season, leaf_fall)
		"pine": _pine(sway, rng, season)
		"bush": _bush(sway, rng)
		"flowers": _flowers_asleep(sway, rng) if season == "winter" else _flowers(sway, rng)
		"mushroom": _mushroom(sway, rng, season == "winter")
		"rock": _rock(sway, rng)
		"pumpkin": _pumpkin(sway, rng, season == "winter")
		"fence": _fence(sway)
		"bench": _bench(sway)
		"lantern": _lantern(sway)
		"lily": _lily(sway, rng, season == "winter")
		"snowdrop": _snowdrop(sway, rng)
		"birdhouse": _birdhouse(sway, rng)
		"hive": _hive(sway, rng, season == "winter")
		"hammock": _hammock_folded(sway, rng) if season == "winter" else _hammock(sway, rng)
		"scarecrow": _scarecrow(sway, rng)
		"haystack": _haystack(sway, rng)
		"snowman": _snowman_melted(sway, rng) if season in ["spring", "summer", "autumn"] else _snowman(sway, rng)
		"campfire": _campfire(sway, rng)
		"feeder": _feeder(sway, rng)
		"shovel": _shovel(sway)
	if not info(id).get("rotatable", false) and id != "shovel":
		sway.rotation.y = rng.randf() * TAU
	sway.scale = Vector3.ONE * float(info(id).get("scale", 1.0))
	root.set_meta("id", id)
	return root


static func _pick(rng: RandomNumberGenerator, arr: Array) -> Color:
	return arr[rng.randi() % arr.size()]


static func _tree(s: Node3D, rng: RandomNumberGenerator, season: String = "", leaf_fall := false) -> void:
	if season == "winter":
		_bare_tree(s, rng)
		return
	var spring := season == "spring"
	var autumn := season == "autumn" or (not spring and rng.randf() < 0.18)
	if leaf_fall:
		# falling leaves sign: fallen leaves around the trunk (only on levels where the rules changed)
		for i in rng.randi_range(5, 8):
			var la := rng.randf() * TAU
			var ld := rng.randf_range(0.18, 0.42)
			C.part(s, C.sphere(0.06), C.mat(_pick(rng, AUTUMN), 0.7), Vector3(cos(la) * ld, 0.015, sin(la) * ld),
				Vector3(1.3, 0.18, 0.8), Vector3(0, rng.randf() * TAU, 0))
	var pal: Array = AUTUMN if autumn else LEAVES
	var trunk_h := rng.randf_range(0.5, 0.7)
	C.part(s, C.cyl(0.07, 0.12, trunk_h), C.mat(TRUNK), Vector3(0, trunk_h * 0.5, 0))
	var top := trunk_h + 0.24
	C.part(s, C.sphere(0.36), C.mat(pal[0]), Vector3(0, top, 0), Vector3(1, 0.92, 1))
	for i in 3:
		var a := TAU * i / 3.0 + rng.randf() * 0.8
		var r := rng.randf_range(0.2, 0.26)
		C.part(s, C.sphere(r), C.mat(_pick(rng, pal)), Vector3(cos(a) * 0.25, top - 0.1 + rng.randf() * 0.16, sin(a) * 0.25))
	if spring:
		# in spring the crown has pink blossom instead of apples
		for i in rng.randi_range(6, 9):
			var a := rng.randf() * TAU
			var y := rng.randf_range(-0.2, 0.7)
			var d := Vector3(cos(a), y, sin(a)).normalized()
			C.part(s, C.sphere(0.05), C.mat(_pick(rng, [Color("ffc1d9"), Color("ffd6e6"), Color("fff3f6")]), 0.5), Vector3(0, top, 0) + d * 0.36, Vector3(1, 0.6, 1))
	elif not autumn and rng.randf() < 0.55:
		for i in rng.randi_range(2, 4):
			var a := rng.randf() * TAU
			var y := rng.randf_range(-0.1, 0.5)
			var d := Vector3(cos(a), y, sin(a)).normalized()
			C.part(s, C.sphere(0.045), C.mat(Color("e8504a"), 0.45), Vector3(0, top, 0) + d * 0.37)


static func _pine(s: Node3D, rng: RandomNumberGenerator, season: String = "") -> void:
	C.part(s, C.cyl(0.06, 0.08, 0.3), C.mat(TRUNK), Vector3(0, 0.15, 0))
	var col := _pick(rng, PINE)
	var k := rng.randf_range(0.9, 1.15)
	var y := 0.2
	for i in 3:
		var rad := (0.42 - i * 0.1) * k
		var h := (0.5 - i * 0.06) * k
		C.part(s, C.cone(rad, h), C.mat(col), Vector3(0, y + h * 0.5, 0))
		C.part(s, C.rim(rad), C.mat(col), Vector3(0, y + 0.03, 0))
		y += h * 0.55
	C.part(s, C.sphere(0.045), C.mat(col), Vector3(0, y + 0.2 * k, 0))
	if season == "winter":
		# snow on the fir: white caps on the tiers
		var yy := 0.2
		for i in 3:
			var rad := (0.42 - i * 0.1) * k
			var h := (0.5 - i * 0.06) * k
			C.part(s, C.sphere(rad * 0.55), C.mat(Color("f7fbff"), 0.7), Vector3(0, yy + h * 0.62, 0), Vector3(1, 0.35, 1))
			yy += h * 0.55


static func _bush(s: Node3D, rng: RandomNumberGenerator) -> void:
	var col := _pick(rng, LEAVES).darkened(0.08)
	for i in rng.randi_range(3, 4):
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.05, 0.2)
		var r := rng.randf_range(0.17, 0.25)
		C.part(s, C.sphere(r), C.mat(col.darkened(0.06 * (i % 3))), Vector3(cos(a) * d, r * 0.8, sin(a) * d), Vector3(1, 0.85, 1))
	if rng.randf() < 0.5:
		var berry: Color = [Color("ff6f91"), Color("6c7bff"), Color("ffffff")][rng.randi() % 3]
		for i in rng.randi_range(3, 6):
			var a := rng.randf() * TAU
			var d := Vector3(cos(a), rng.randf_range(0.3, 1.0), sin(a)).normalized()
			C.part(s, C.sphere(0.035), C.mat(berry, 0.4), Vector3(0, 0.18, 0) + d * Vector3(0.28, 0.2, 0.28))


static func _flowers(s: Node3D, rng: RandomNumberGenerator) -> void:
	var col := _pick(rng, PETALS)
	var col2 := _pick(rng, PETALS)
	for i in rng.randi_range(4, 6):
		var a := rng.randf() * TAU
		var d := 0.0 if i == 0 else rng.randf_range(0.12, 0.32)
		var h := rng.randf_range(0.22, 0.42)
		var f := Node3D.new()
		f.position = Vector3(cos(a) * d, 0, sin(a) * d)
		s.add_child(f)
		C.part(f, C.cyl(0.018, 0.022, h, 8), C.mat(STEM), Vector3(0, h * 0.5, 0))
		C.part(f, C.sphere(0.06), C.mat(Color("6cbf5a")), Vector3(0.04, h * 0.3, 0), Vector3(1.4, 0.35, 0.7), Vector3(0, 0, 0.5))
		var head := Node3D.new()
		head.position = Vector3(0, h, 0)
		head.rotation = Vector3(rng.randf_range(-0.35, 0.35), rng.randf() * TAU, rng.randf_range(-0.35, 0.35))
		f.add_child(head)
		var c := col if rng.randf() < 0.65 else col2
		for p in 5:
			var pa := TAU * p / 5.0
			C.part(head, C.sphere(0.05), C.mat(c), Vector3(cos(pa) * 0.055, 0, sin(pa) * 0.055), Vector3(1, 0.45, 1))
		C.part(head, C.sphere(0.035), C.mat(Color("ffcf4a")), Vector3(0, 0.02, 0))


## A snow cap: a flattened white lump (winter item shapes — one function).
static func _snow_cap(s: Node3D, pos: Vector3, r: float) -> void:
	C.part(s, C.sphere(r), C.mat(Color("f7fbff"), 0.7), pos, Vector3(1, 0.42, 1))


## In winter flowers sleep under the snow: a small drift and colored closed buds in snow caps (not dry stems).
static func _flowers_asleep(s: Node3D, rng: RandomNumberGenerator) -> void:
	var col := _pick(rng, PETALS)
	var col2 := _pick(rng, PETALS)
	C.part(s, C.sphere(0.3), C.mat(Color("f7fbff"), 0.75), Vector3(0, 0.03, 0), Vector3(1.2, 0.38, 1.2))
	for i in rng.randi_range(3, 4):
		var a := rng.randf() * TAU
		var d := 0.0 if i == 0 else rng.randf_range(0.1, 0.2)
		var h := rng.randf_range(0.13, 0.2)
		var p := Vector3(cos(a) * d, 0, sin(a) * d)
		C.part(s, C.cyl(0.014, 0.018, h, 8), C.mat(STEM), p + Vector3(0, h * 0.5, 0))
		C.part(s, C.sphere(0.04), C.mat(col if rng.randf() < 0.65 else col2), p + Vector3(0, h + 0.02, 0), Vector3(0.8, 1.3, 0.8))
		_snow_cap(s, p + Vector3(0, h + 0.065, 0), 0.03)


static func _mushroom(s: Node3D, rng: RandomNumberGenerator, winter := false) -> void:
	var red := rng.randf() < 0.6
	var cap_col := Color("e5533d") if red else Color("bd8552")
	for i in rng.randi_range(1, 3):
		var k := 1.0 if i == 0 else rng.randf_range(0.5, 0.7)
		var a := rng.randf() * TAU
		var pos := Vector3.ZERO if i == 0 else Vector3(cos(a) * 0.26, 0, sin(a) * 0.26)
		var stem_h := 0.24 * k
		C.part(s, C.cyl(0.065 * k, 0.085 * k, stem_h, 14), C.mat(Color("f3e6cf")), pos + Vector3(0, stem_h * 0.5, 0))
		var cap_r := 0.2 * k
		var cap_c := pos + Vector3(0, stem_h + cap_r * 0.12, 0)
		C.part(s, C.sphere(cap_r), C.mat(cap_col, 0.6), cap_c, Vector3(1, 0.58, 1))
		if red:
			for j in 6:
				var da := rng.randf() * TAU
				var dv := Vector3(cos(da), rng.randf_range(0.35, 1.2), sin(da)).normalized()
				C.part(s, C.sphere(0.026 * k), C.mat(Color("fff8ee")), cap_c + Vector3(dv.x * cap_r * 0.96, dv.y * cap_r * 0.58 * 0.96, dv.z * cap_r * 0.96), Vector3(1, 0.5, 1))
		if winter:
			_snow_cap(s, cap_c + Vector3(0, cap_r * 0.42, 0), cap_r * 0.85)


static func _rock(s: Node3D, rng: RandomNumberGenerator) -> void:
	var grays := [Color("aaa69e"), Color("918e88"), Color("bbb4a8")]
	for i in rng.randi_range(1, 3):
		var k := 1.0 if i == 0 else 0.6
		var sz := Vector3(rng.randf_range(0.26, 0.42), rng.randf_range(0.18, 0.3), rng.randf_range(0.26, 0.4)) * k
		var a := rng.randf() * TAU
		var off := Vector3.ZERO if i == 0 else Vector3(cos(a) * 0.27, 0, sin(a) * 0.27)
		var mesh := C.rounded_box(sz, 0.09 * k, 3, 0.03, rng.randi() % 5)
		C.part(s, mesh, C.mat(_pick(rng, grays), 0.85), off + Vector3(0, sz.y * 0.42, 0), Vector3.ONE,
			Vector3(rng.randf_range(-0.2, 0.2), rng.randf() * TAU, rng.randf_range(-0.2, 0.2)))
	if rng.randf() < 0.4:
		C.part(s, C.sphere(0.07), C.mat(Color("7cbf62")), Vector3(0.1, 0.02, 0.18), Vector3(1.3, 0.4, 1.0))


static func _pumpkin(s: Node3D, rng: RandomNumberGenerator, winter := false) -> void:
	var orange := C.mat(Color("f2913d"), 0.6)
	for i in rng.randi_range(1, 2):
		var k := 1.0 if i == 0 else 0.7
		var a := rng.randf() * TAU
		var c := Vector3.ZERO if i == 0 else Vector3(cos(a) * 0.27, 0, sin(a) * 0.27)
		var R := 0.18 * k
		for l in 6:
			var la := TAU * l / 6.0
			C.part(s, C.sphere(R * 0.62), orange, c + Vector3(cos(la) * R * 0.42, R * 0.7, sin(la) * R * 0.42), Vector3(1.0, 0.95, 0.72), Vector3(0, -la, 0))
		C.part(s, C.sphere(R * 0.7), orange, c + Vector3(0, R * 0.7, 0))
		C.part(s, C.cyl(0.018, 0.028, 0.1 * k, 8), C.mat(Color("6f7d3a")), c + Vector3(0.01, R * 1.35, 0), Vector3.ONE, Vector3(0, 0, 0.3))
		if winter:
			_snow_cap(s, c + Vector3(0, R * 1.22, 0), R * 0.8)
	C.part(s, C.sphere(0.09), C.mat(Color("5fae4e")), Vector3(-0.18, 0.02, 0.12), Vector3(1.4, 0.3, 1.0), Vector3(0, 0.6, 0))


static func _fence(s: Node3D) -> void:
	var wood := C.mat(Color("c98f5e"))
	C.part(s, C.rounded_box(Vector3(0.13, 0.56, 0.13), 0.045, 2), wood, Vector3(0, 0.28, 0))
	C.part(s, C.rounded_box(Vector3(1.0, 0.085, 0.06), 0.03, 2), wood, Vector3(0, 0.19, 0))
	C.part(s, C.rounded_box(Vector3(1.0, 0.085, 0.06), 0.03, 2), wood, Vector3(0, 0.4, 0))


static func _bench(s: Node3D) -> void:
	var wood := C.mat(Color("bd7d4d"))
	var dark := C.mat(Color("6b5a4e"), 0.6)
	C.part(s, C.rounded_box(Vector3(0.8, 0.07, 0.3), 0.03, 2), wood, Vector3(0, 0.28, 0.02))
	C.part(s, C.rounded_box(Vector3(0.8, 0.22, 0.06), 0.03, 2), wood, Vector3(0, 0.46, -0.13), Vector3.ONE, Vector3(-0.18, 0, 0))
	for x in [-0.32, 0.32]:
		for z in [-0.1, 0.12]:
			C.part(s, C.rounded_box(Vector3(0.07, 0.28, 0.07), 0.025, 2), dark, Vector3(x, 0.14, z))


static func _lantern(s: Node3D) -> void:
	var metal := C.mat(Color("4f5662"), 0.5)
	C.part(s, C.cyl(0.035, 0.05, 0.76, 12), metal, Vector3(0, 0.38, 0))
	C.part(s, C.rounded_box(Vector3(0.22, 0.06, 0.22), 0.025, 2), metal, Vector3(0, 0.77, 0))
	C.part(s, C.rounded_box(Vector3(0.17, 0.2, 0.17), 0.055, 3), C.lamp_mat(), Vector3(0, 0.9, 0))
	C.part(s, C.cone(0.18, 0.13), metal, Vector3(0, 1.06, 0))
	C.part(s, C.sphere(0.035), metal, Vector3(0, 1.14, 0))
	var light := OmniLight3D.new()
	light.name = "Light"
	light.position = Vector3(0, 0.9, 0)
	light.omni_range = 3.4
	light.light_color = Color("ffbf6b")
	light.light_energy = 0.0
	light.shadow_enabled = false
	s.add_child(light)


static func _lily(s: Node3D, rng: RandomNumberGenerator, winter := false) -> void:
	var pad := C.mat(Color("9cc3b0") if winter else Color("5db35a"))   # in winter the water lily is frozen into the ice: frosty
	C.part(s, C.cyl(0.25, 0.25, 0.035, 26), pad, Vector3(0, 0.02, 0))
	var a := rng.randf() * TAU
	C.part(s, C.cyl(0.15, 0.15, 0.03, 20), pad, Vector3(cos(a) * 0.3, 0.015, sin(a) * 0.3))
	var head := Node3D.new()
	head.position = Vector3(0.04, 0.05, 0.02)
	s.add_child(head)
	var petal := C.mat(_pick(rng, [Color("f7a8c8"), Color("fff6f6"), Color("ffc6dc")]))
	for i in 7:
		var pa := TAU * i / 7.0
		C.part(head, C.sphere(0.05), petal, Vector3(cos(pa) * 0.06, 0.03, sin(pa) * 0.06), Vector3(0.55, 0.4, 1.2), Vector3(0.5, -pa + PI * 0.5, 0))
	C.part(head, C.sphere(0.035), C.mat(Color("ffd34d")), Vector3(0, 0.05, 0))
	if winter:
		head.scale = Vector3(0.7, 1.0, 0.7)   # the bud has closed
		for i in 5:
			var fa := rng.randf() * TAU
			C.part(s, C.sphere(0.03), C.mat(Color("f7fbff"), 0.6), Vector3(cos(fa) * 0.18, 0.04, sin(fa) * 0.18), Vector3(1.4, 0.3, 1.4))


## Snowdrop: white bells drooping on thin arched stems, and a couple of narrow leaves.
static func _snowdrop(s: Node3D, rng: RandomNumberGenerator) -> void:
	var white := C.mat(Color("fbfbf4"), 0.55)
	var tip := C.mat(Color("8fd16a"))
	var leaf := C.mat(Color("5fae5a"))
	for i in rng.randi_range(3, 5):
		var a := rng.randf() * TAU
		var d := 0.0 if i == 0 else rng.randf_range(0.1, 0.26)
		var h := rng.randf_range(0.26, 0.4)
		var f := Node3D.new()
		f.position = Vector3(cos(a) * d, 0, sin(a) * d)
		f.rotation.y = rng.randf() * TAU
		s.add_child(f)
		C.part(f, C.cyl(0.014, 0.018, h, 8), C.mat(STEM), Vector3(0, h * 0.5, 0))
		# the arc of the stem and the drooping bell
		C.part(f, C.cyl(0.013, 0.013, 0.09, 8), C.mat(STEM), Vector3(0.035, h + 0.02, 0), Vector3.ONE, Vector3(0, 0, -1.0))
		var bell := Node3D.new()
		bell.position = Vector3(0.08, h - 0.03, 0)
		f.add_child(bell)
		for p in 3:
			var pa := TAU * p / 3.0
			C.part(bell, C.sphere(0.045), white, Vector3(cos(pa) * 0.022, -0.02, sin(pa) * 0.022), Vector3(0.7, 1.35, 0.7), Vector3(cos(pa) * 0.25, 0, sin(pa) * 0.25))
		C.part(bell, C.sphere(0.022), tip, Vector3(0, 0.035, 0))
	for i in 2:
		var la := rng.randf() * TAU
		C.part(s, C.sphere(0.05), leaf, Vector3(cos(la) * 0.06, 0.12, sin(la) * 0.06), Vector3(0.45, 2.6, 0.25), Vector3(cos(la) * 0.25, la, sin(la) * 0.25))


## Birdhouse: a little house on a post, a gable roof, a round entrance and a perch.
static func _birdhouse(s: Node3D, rng: RandomNumberGenerator) -> void:
	var wood := C.mat(_pick(rng, [Color("d39a62"), Color("c88d5a"), Color("dcab72")]))
	var roof := C.mat(_pick(rng, [Color("b8573f"), Color("4f8f7a"), Color("6f6aa8")]), 0.6)
	var dark := C.mat(Color("3a2a22"), 0.9)
	C.part(s, C.cyl(0.04, 0.05, 0.6, 12), C.mat(TRUNK), Vector3(0, 0.3, 0))
	C.part(s, C.rounded_box(Vector3(0.3, 0.32, 0.28), 0.05, 3, 0.02, rng.randi() % 5), wood, Vector3(0, 0.74, 0))
	for side in [-1.0, 1.0]:
		C.part(s, C.rounded_box(Vector3(0.24, 0.045, 0.38), 0.02, 2), roof, Vector3(side * 0.09, 0.95, 0), Vector3.ONE, Vector3(0, 0, -side * 0.62))
	C.part(s, C.cyl(0.055, 0.055, 0.03, 18), dark, Vector3(0, 0.78, 0.142), Vector3.ONE, Vector3(PI * 0.5, 0, 0))
	C.part(s, C.cyl(0.012, 0.012, 0.09, 8), C.mat(TRUNK), Vector3(0, 0.68, 0.18), Vector3.ONE, Vector3(PI * 0.5, 0, 0))


## Beehive: a straw bell-shaped dome of rings, a dark entrance, bees circling (main.gd spins the "Bees" node).
static func _hive(s: Node3D, rng: RandomNumberGenerator, winter := false) -> void:
	var straw := [Color("e2b45c"), Color("d6a24c"), Color("ebc472")]
	C.part(s, C.rounded_box(Vector3(0.5, 0.06, 0.5), 0.03, 2), C.mat(Color("9b6b45")), Vector3(0, 0.03, 0))
	var y := 0.07
	for i in 5:
		var r := 0.24 - i * 0.035
		C.part(s, C.cyl(r, r + 0.012, 0.085, 22), C.mat(straw[i % 3], 0.85), Vector3(0, y + 0.04, 0))
		C.part(s, C.rim(r + 0.006), C.mat(straw[(i + 1) % 3], 0.85), Vector3(0, y + 0.005, 0))
		y += 0.075
	C.part(s, C.sphere(0.1), C.mat(straw[0], 0.85), Vector3(0, y, 0), Vector3(1, 0.7, 1))
	C.part(s, C.cyl(0.045, 0.045, 0.03, 16), C.mat(Color("3a2a22"), 0.9), Vector3(0, 0.13, 0.225), Vector3.ONE, Vector3(PI * 0.5, 0, 0))
	var bees := Node3D.new()
	bees.name = "Bees"
	bees.position = Vector3(0, 0.3, 0)
	s.add_child(bees)
	for i in 3:
		var a := TAU * i / 3.0 + rng.randf() * 0.5
		var b := Node3D.new()
		b.position = Vector3(cos(a) * 0.36, rng.randf_range(-0.05, 0.12), sin(a) * 0.36)
		bees.add_child(b)
		C.part(b, C.sphere(0.035), C.mat(Color("f6c445"), 0.5), Vector3.ZERO, Vector3(1.3, 1, 1))
		C.part(b, C.sphere(0.022), C.mat(Color("3a3030"), 0.6), Vector3(-0.025, 0, 0))
		C.part(b, C.sphere(0.022), C.mat(Color("ffffff"), 0.3), Vector3(0, 0.03, 0), Vector3(1.2, 0.4, 0.7))
	if winter:
		bees.visible = false   # the bees winter inside
		_snow_cap(s, Vector3(0, 0.47, 0), 0.17)


## Hammock: two posts and sagging striped fabric along the X axis.
static func _hammock(s: Node3D, rng: RandomNumberGenerator) -> void:
	var wood := C.mat(Color("a8734b"))
	var cloth := C.mat(_pick(rng, [Color("e8735a"), Color("6aa7d8"), Color("e9b949")]), 0.7)
	var stripe := C.mat(Color("fff4e4"), 0.7)
	for x in [-0.4, 0.4]:
		C.part(s, C.cyl(0.035, 0.045, 0.55, 10), wood, Vector3(x, 0.275, 0))
		C.part(s, C.sphere(0.045), wood, Vector3(x, 0.56, 0))
	for i in 7:
		var u := -0.33 + i * 0.11
		var sag := 0.46 - 0.16 * (1.0 - pow(u / 0.36, 2.0))
		C.part(s, C.sphere(0.075), cloth if i % 2 == 0 else stripe, Vector3(u, sag, 0), Vector3(0.95, 0.35, 2.2))
	C.part(s, C.cyl(0.008, 0.008, 0.09, 6), C.mat(Color("ead8b8")), Vector3(-0.37, 0.5, 0), Vector3.ONE, Vector3(0, 0, -0.9))
	C.part(s, C.cyl(0.008, 0.008, 0.09, 6), C.mat(Color("ead8b8")), Vector3(0.37, 0.5, 0), Vector3.ONE, Vector3(0, 0, 0.9))


## Hammock in winter: the fabric is rolled up between the posts, snow on the roll and the posts.
static func _hammock_folded(s: Node3D, rng: RandomNumberGenerator) -> void:
	var wood := C.mat(Color("a8734b"))
	var cloth := C.mat(_pick(rng, [Color("e8735a"), Color("6aa7d8"), Color("e9b949")]), 0.7)
	for x in [-0.4, 0.4]:
		C.part(s, C.cyl(0.035, 0.045, 0.55, 10), wood, Vector3(x, 0.275, 0))
		_snow_cap(s, Vector3(x, 0.57, 0), 0.05)
	C.part(s, C.cyl(0.055, 0.055, 0.62, 14), cloth, Vector3(0, 0.47, 0), Vector3.ONE, Vector3(0, 0, PI * 0.5))
	for x in [-0.2, 0.0, 0.2]:
		C.part(s, C.cyl(0.058, 0.058, 0.035, 14), C.mat(Color("fff4e4"), 0.7), Vector3(x, 0.47, 0), Vector3.ONE, Vector3(0, 0, PI * 0.5))
	C.part(s, C.sphere(0.06), C.mat(Color("f7fbff"), 0.7), Vector3(0, 0.525, 0), Vector3(4.6, 0.4, 0.9))


## A snowman out of winter: melted — a small puddle (smaller than a water cell) with a carrot, coals, a bucket and twigs in it.
static func _snowman_melted(s: Node3D, rng: RandomNumberGenerator) -> void:
	C.part(s, C.cyl(0.22, 0.24, 0.02, 24), C.mat(Color("bfdcea"), 0.12), Vector3(0, 0.01, 0), Vector3(1, 1, 0.8))
	for i in 2:
		var a := rng.randf() * TAU
		C.part(s, C.sphere(0.06), C.mat(Color("f6f9fc"), 0.75), Vector3(cos(a) * 0.15, 0.02, sin(a) * 0.12), Vector3(1.2, 0.35, 1))
	C.part(s, C.cone(0.025, 0.12), C.mat(Color("f08a3c")), Vector3(0.06, 0.03, 0.02), Vector3.ONE, Vector3(0, rng.randf() * TAU, PI * 0.5))
	for i in 3:
		C.part(s, C.sphere(0.017), C.mat(Color("2c2622"), 0.8), Vector3(-0.04 + i * 0.05, 0.025, -0.08))
	C.part(s, C.cyl(0.07, 0.09, 0.1, 14), C.mat(_pick(rng, [Color("c0573f"), Color("5b7fb5"), Color("8b6b3f")]), 0.7),
		Vector3(-0.13, 0.07, 0.07), Vector3.ONE, Vector3(PI * 0.5, 0.4, 0))
	for side in [-1.0, 1.0]:
		C.part(s, C.cyl(0.012, 0.012, 0.24, 6), C.mat(TRUNK), Vector3(side * 0.1, 0.02, 0.12), Vector3.ONE, Vector3(PI * 0.5, side * 0.7, 0))


## Scarecrow: a pole with a crossbar, a shirt, a sack head with a hat.
static func _scarecrow(s: Node3D, rng: RandomNumberGenerator) -> void:
	var wood := C.mat(Color("8d6a47"))
	var shirt := C.mat(_pick(rng, [Color("c0573f"), Color("5b7fb5"), Color("7a9a4a")]), 0.8)
	var sack := C.mat(Color("e2c690"), 0.85)
	var hat := C.mat(Color("8b6b3f"), 0.8)
	C.part(s, C.cyl(0.035, 0.04, 0.95, 10), wood, Vector3(0, 0.475, 0))
	C.part(s, C.cyl(0.028, 0.028, 0.62, 10), wood, Vector3(0, 0.66, 0), Vector3.ONE, Vector3(0, 0, PI * 0.5))
	C.part(s, C.rounded_box(Vector3(0.3, 0.32, 0.16), 0.06, 3, 0.02, rng.randi() % 5), shirt, Vector3(0, 0.6, 0))
	for x in [-0.26, 0.26]:
		C.part(s, C.sphere(0.06), C.mat(Color("e8c66a")), Vector3(x, 0.66, 0), Vector3(1.3, 0.6, 0.8))
	C.part(s, C.sphere(0.11), sack, Vector3(0, 0.88, 0))
	C.part(s, C.cyl(0.16, 0.16, 0.025, 20), hat, Vector3(0, 0.97, 0))
	C.part(s, C.cyl(0.08, 0.1, 0.1, 16), hat, Vector3(0, 1.03, 0))
	C.part(s, C.sphere(0.018), C.mat(Color("3a2a22")), Vector3(-0.04, 0.9, 0.1))
	C.part(s, C.sphere(0.018), C.mat(Color("3a2a22")), Vector3(0.04, 0.9, 0.1))


## Haystack: a plump straw dome with straws.
static func _haystack(s: Node3D, rng: RandomNumberGenerator) -> void:
	var hay := [Color("e7c25a"), Color("d9b04a"), Color("f0d074")]
	C.part(s, C.sphere(0.34), C.mat(hay[0], 0.9), Vector3(0, 0.22, 0), Vector3(1.0, 0.85, 1.0))
	C.part(s, C.sphere(0.22), C.mat(hay[2], 0.9), Vector3(0, 0.46, 0), Vector3(1.0, 0.9, 1.0))
	for i in 9:
		var a := rng.randf() * TAU
		var y := rng.randf_range(0.12, 0.5)
		var d := Vector3(cos(a), 0, sin(a)) * (0.3 if y < 0.35 else 0.2)
		C.part(s, C.cyl(0.008, 0.008, 0.12, 5), C.mat(_pick(rng, hay)), d + Vector3(0, y, 0), Vector3.ONE,
			Vector3(rng.randf_range(-0.8, 0.8), 0, rng.randf_range(-0.8, 0.8)))


## A winter tree: a bare trunk with branches and snow in the forks.
static func _bare_tree(s: Node3D, rng: RandomNumberGenerator) -> void:
	var bark := C.mat(TRUNK)
	var trunk_h := rng.randf_range(0.6, 0.8)
	C.part(s, C.cyl(0.06, 0.11, trunk_h), bark, Vector3(0, trunk_h * 0.5, 0))
	for i in 4:
		var a := TAU * i / 4.0 + rng.randf() * 0.6
		var br := Node3D.new()
		br.position = Vector3(0, trunk_h * rng.randf_range(0.65, 0.95), 0)
		br.rotation = Vector3(0, a, rng.randf_range(0.5, 0.9))
		s.add_child(br)
		C.part(br, C.cyl(0.02, 0.035, 0.38, 8), bark, Vector3(0, 0.19, 0))
		C.part(br, C.sphere(0.04), C.mat(Color("f7fbff"), 0.7), Vector3(0, 0.36, 0), Vector3(1.2, 0.6, 1.2))


## Snowman: three snowballs, a carrot, coals, twig arms, a bucket.
static func _snowman(s: Node3D, rng: RandomNumberGenerator) -> void:
	var snow := C.mat(Color("f6f9fc"), 0.75)
	C.part(s, C.sphere(0.2), snow, Vector3(0, 0.18, 0))
	C.part(s, C.sphere(0.15), snow, Vector3(0, 0.46, 0))
	C.part(s, C.sphere(0.11), snow, Vector3(0, 0.68, 0))
	C.part(s, C.cone(0.025, 0.12), C.mat(Color("f08a3c")), Vector3(0, 0.68, 0.14), Vector3.ONE, Vector3(PI * 0.5, 0, 0))
	for x in [-0.04, 0.04]:
		C.part(s, C.sphere(0.017), C.mat(Color("2c2622"), 0.8), Vector3(x, 0.72, 0.095))
	for i in 3:
		C.part(s, C.sphere(0.018), C.mat(Color("2c2622"), 0.8), Vector3(0, 0.52 - i * 0.07, 0.14))
	for side in [-1.0, 1.0]:
		C.part(s, C.cyl(0.012, 0.012, 0.26, 6), C.mat(TRUNK), Vector3(side * 0.22, 0.5, 0), Vector3.ONE, Vector3(0, 0, side * -1.1))
	C.part(s, C.cyl(0.07, 0.09, 0.1, 14), C.mat(_pick(rng, [Color("c0573f"), Color("5b7fb5"), Color("8b6b3f")]), 0.7), Vector3(0, 0.8, 0))


## Campfire: logs in a tepee, tongues of flame (glowing), warm light.
static func _campfire(s: Node3D, rng: RandomNumberGenerator) -> void:
	var wood := C.mat(Color("7a5236"))
	for i in 5:
		var a := TAU * i / 5.0
		C.part(s, C.cyl(0.03, 0.035, 0.36, 8), wood, Vector3(cos(a) * 0.09, 0.13, sin(a) * 0.09), Vector3.ONE, Vector3(sin(a) * 0.55, 0, -cos(a) * 0.55))
	for i in 6:
		var a := TAU * i / 6.0
		C.part(s, C.sphere(0.06), C.mat(Color("8f8a84"), 0.9), Vector3(cos(a) * 0.24, 0.03, sin(a) * 0.24), Vector3(1, 0.6, 1))
	var flame := C.lamp_mat()
	C.part(s, C.cone(0.09, 0.26), flame, Vector3(0, 0.2, 0))
	C.part(s, C.cone(0.05, 0.16), flame, Vector3(0.05, 0.17, 0.03))
	var light := OmniLight3D.new()
	light.name = "Light"
	light.position = Vector3(0, 0.35, 0)
	light.omni_range = 3.0
	light.light_color = Color("ff9a4a")
	light.light_energy = 0.8
	light.shadow_enabled = false
	s.add_child(light)


## Feeder: a post, a tray with seeds and a small roof.
static func _feeder(s: Node3D, rng: RandomNumberGenerator) -> void:
	var wood := C.mat(Color("c48e5c"))
	C.part(s, C.cyl(0.035, 0.045, 0.62, 10), C.mat(TRUNK), Vector3(0, 0.31, 0))
	C.part(s, C.rounded_box(Vector3(0.36, 0.05, 0.3), 0.02, 2), wood, Vector3(0, 0.64, 0))
	for x in [-0.16, 0.16]:
		C.part(s, C.cyl(0.015, 0.015, 0.2, 6), wood, Vector3(x, 0.75, 0))
	for side in [-1.0, 1.0]:
		C.part(s, C.rounded_box(Vector3(0.24, 0.035, 0.38), 0.015, 2), C.mat(Color("8b5a3c")), Vector3(side * 0.1, 0.88, 0), Vector3.ONE, Vector3(0, 0, -side * 0.5))
	for i in 7:
		C.part(s, C.sphere(0.018), C.mat(_pick(rng, [Color("e8c56a"), Color("c99b4a"), Color("4a3a2a")])), Vector3(rng.randf_range(-0.12, 0.12), 0.675, rng.randf_range(-0.1, 0.1)))


## Only for the "Remove" tool icon.
static func _shovel(s: Node3D) -> void:
	var sh := Node3D.new()
	sh.rotation = Vector3(0, 0, 0.35)
	sh.position = Vector3(0.05, 0.05, 0)
	s.add_child(sh)
	C.part(sh, C.cyl(0.03, 0.03, 0.62, 10), C.mat(Color("c98f5e")), Vector3(0, 0.5, 0))
	C.part(sh, C.rounded_box(Vector3(0.16, 0.06, 0.06), 0.025, 2), C.mat(Color("e5533d")), Vector3(0, 0.83, 0))
	C.part(sh, C.rounded_box(Vector3(0.2, 0.24, 0.04), 0.03, 3), C.mat(Color("9aa3ad"), 0.35), Vector3(0, 0.12, 0))
	C.part(s, C.sphere(0.22), C.mat(Color("ad7752")), Vector3(-0.08, 0.0, 0.0), Vector3(1.2, 0.45, 1.0))
