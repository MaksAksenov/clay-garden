extends Node3D
## A floating island of clay columns: a grass cap, soil, roots below.

const C := preload("res://scripts/clay.gd")

const N := 18
const STEP := 0.5
const MAX_H := 7

const GRASS := [Color("8acb6c"), Color("7cbf62"), Color("94d277")]
## The island's seasonal palette: a table, no "machinery". Summer (as it was) and spring (stage 3) are filled in.
const PALETTE := {
	"summer": {"grass": GRASS},
	"spring": {"grass": [Color("a9db7c"), Color("9fd270"), Color("b6e38a")]},
	"autumn": {"grass": [Color("b9b765"), Color("aaa95a"), Color("c4bf72")]},
	"winter": {"grass": [Color("eef3f8"), Color("e4ebf2"), Color("f4f7fb")]},
}
var season := "summer"   # which palette to paint with; set before load_map/generate
var dry := {}            # dry cells of a drought level (yellower and cracked); set before load_map
var snow_cells := {}     # snowdrifts (winter): a mound of snow on the cell — a shape, not just a color
const DRY_GRASS := [Color("cfc27a"), Color("c4b56c"), Color("d8cc86")]
const CRACK := Color("8a6a3e")
const DIRT := [Color("ad7752"), Color("9f6a48")]
const ROOT := Color("74503a")
const SAND := Color("ecd59d")

var heights: Dictionary = {}   # Vector2i -> int (1..MAX_H)
var water: Dictionary = {}     # Vector2i -> true
var bottoms: Dictionary = {}   # Vector2i -> float, depth of the island's "roots"
var cols: Dictionary = {}      # Vector2i -> StaticBody3D


func cell_center(c: Vector2i) -> Vector3:
	return Vector3(c.x - N * 0.5 + 0.5, 0.0, c.y - N * 0.5 + 0.5)


func world_to_cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x + N * 0.5), floori(p.z + N * 0.5))


func in_grid(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < N and c.y < N


func has_land(c: Vector2i) -> bool:
	return heights.get(c, 0) > 0


func is_water(c: Vector2i) -> bool:
	return water.has(c)


func top_y(c: Vector2i) -> float:
	return heights.get(c, 0) * STEP


## Where items stand: on grass or on the water surface.
func surface_y(c: Vector2i) -> float:
	return top_y(c) - 0.1 if water.has(c) else top_y(c)


func clear_all() -> void:
	for c in cols:
		cols[c].queue_free()
	cols.clear()
	heights.clear()
	water.clear()
	bottoms.clear()


func generate(seed_value: int) -> void:
	clear_all()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var shape := FastNoiseLite.new()
	shape.seed = seed_value
	shape.frequency = 0.13
	var hills := FastNoiseLite.new()
	hills.seed = seed_value + 17
	hills.frequency = 0.085
	var radius := 6.3
	var pond := Vector2(rng.randf_range(-2.5, 2.5), rng.randf_range(-2.5, 2.5))
	var pond_r := rng.randf_range(1.4, 2.0)
	for x in N:
		for z in N:
			var c := Vector2i(x, z)
			var p := Vector2(x - N * 0.5 + 0.5, z - N * 0.5 + 0.5)
			var d := p.length() / radius + shape.get_noise_2d(x, z) * 0.35
			if d > 1.0:
				continue
			var h := 2 + int(round((hills.get_noise_2d(x, z) + 0.15) * 4.5))
			if d > 0.82:
				h -= 1
			h = clampi(h, 1, 5)
			if p.distance_to(pond) < pond_r and d < 0.85:
				water[c] = true
				h = 2
			heights[c] = h
			bottoms[c] = snappedf(-0.7 - (1.0 - clampf(d, 0.0, 1.0)) * 2.6 - rng.randf() * 0.7, 0.25)


## Parsing a level map: {"land": cell->height, "water": cell->true, "off": offset, "size": Vector2i}.
static func parse_map(rows: Array) -> Dictionary:
	var w := 0
	for r in rows:
		w = maxi(w, (r as String).length())
	var off := Vector2i((N - w) / 2, (N - rows.size()) / 2)
	var land := {}
	var wet := {}
	for z in rows.size():
		var row: String = rows[z]
		for x in row.length():
			var ch := row[x]
			if ch == " ":
				continue
			var c := off + Vector2i(x, z)
			if ch == "~":
				wet[c] = true
				land[c] = 2
			else:
				land[c] = int(ch)
	return {"land": land, "water": wet, "off": off, "size": Vector2i(w, rows.size())}


func load_map(rows: Array) -> Dictionary:
	clear_all()
	var m := parse_map(rows)
	var size: Vector2i = m["size"]
	var off: Vector2i = m["off"]
	var center := Vector2(off) + Vector2(size - Vector2i.ONE) * 0.5
	var maxd := Vector2(size).length() * 0.5 + 0.5
	var rng := RandomNumberGenerator.new()
	rng.seed = size.x * 31 + size.y * 7 + rows.size()
	for c in m["land"]:
		heights[c] = m["land"][c]
		var d := Vector2(c).distance_to(center) / maxd
		bottoms[c] = snappedf(-0.7 - (1.0 - d) * 2.2 - rng.randf() * 0.6, 0.25)
	for c in m["water"]:
		water[c] = true
	build_all()
	return m


func build_all() -> void:
	for c in heights:
		build_cell(c)


func build_cell(c: Vector2i, animate: bool = false) -> void:
	if cols.has(c):
		cols[c].queue_free()
		cols.erase(c)
	var h: int = heights.get(c, 0)
	if h <= 0:
		return
	var col := StaticBody3D.new()
	col.position = cell_center(c)
	col.set_meta("cell", c)
	add_child(col)
	cols[c] = col

	var top := h * STEP
	var bottom: float = bottoms.get(c, -1.2)
	var v := absi(c.x * 7 + c.y * 13) % 3
	var wet := water.has(c)
	var root_top := -0.3
	_seg(col, 0.86, bottom, root_top + 0.1, C.mat(ROOT, 0.85, true), v)
	var dirt_top := top - (0.3 if wet else 0.18)
	_seg(col, 0.96, root_top - 0.05, dirt_top, C.mat(DIRT[(c.x + c.y) % 2], 0.85, true), v)
	if wet:
		_seg(col, 0.98, dirt_top - 0.1, top - 0.26, C.mat(SAND, 0.85, true), v)
		var wm := C.rounded_box(Vector3(1.0, 0.26, 1.0), 0.08, 3)
		if season == "winter":
			C.part(col, wm, C.mat(Color("cfe7f4"), 0.08), Vector3(0, top - 0.23, 0))   # ice: glossy light blue
		else:
			C.part(col, wm, C.water_mat(), Vector3(0, top - 0.23, 0))
	else:
		var grass: Array = PALETTE.get(season, PALETTE["summer"])["grass"]
		if dry.has(c):
			grass = DRY_GRASS
		_seg(col, 1.0, top - 0.3, top, C.mat(grass[v], 0.8, true), v)
		if snow_cells.has(c):
			# snowdrift: a plump mound of snow over the cell
			C.part(col, C.sphere(0.38), C.mat(Color("ffffff"), 0.85), Vector3(0, top + 0.02, 0), Vector3(1.15, 0.32, 1.15))
		if dry.has(c):
			# drought cracks: three thin dark stripes on the top face — always visible, not only on hover
			var rng := RandomNumberGenerator.new()
			rng.seed = c.x * 73 + c.y * 19
			for i in 3:
				var a := rng.randf() * PI
				var p := Vector3(rng.randf_range(-0.25, 0.25), top + 0.005, rng.randf_range(-0.25, 0.25))
				C.part(col, C.rounded_box(Vector3(rng.randf_range(0.22, 0.38), 0.02, 0.035), 0.01, 1), C.mat(CRACK, 0.9), p,
					Vector3.ONE, Vector3(0, a, 0))

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, top - bottom, 1.0)
	shape.shape = box
	shape.position.y = (top + bottom) * 0.5
	col.add_child(shape)

	if animate:
		col.scale = Vector3(1.12, 0.92, 1.12)
		var tw := col.create_tween()
		tw.tween_property(col, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _seg(parent: Node3D, width: float, y0: float, y1: float, material: Material, variant: int) -> void:
	var height := y1 - y0
	if height < 0.06:
		return
	var mesh := C.rounded_box(Vector3(width, height, width), minf(0.13, height * 0.5), 3, 0.03, variant)
	C.part(parent, mesh, material, Vector3(0, (y0 + y1) * 0.5, 0))


func raise(c: Vector2i) -> bool:
	if not in_grid(c):
		return false
	var h: int = heights.get(c, 0)
	if h >= MAX_H:
		return false
	if h == 0:
		bottoms[c] = snappedf(-0.8 - randf() * 0.8, 0.25)
	heights[c] = h + 1
	build_cell(c, true)
	return true


func lower(c: Vector2i) -> bool:
	var h: int = heights.get(c, 0)
	if h <= 0:
		return false
	if h == 1:
		heights.erase(c)
		water.erase(c)
	else:
		heights[c] = h - 1
	build_cell(c, true)
	return true


func toggle_water(c: Vector2i) -> bool:
	if not has_land(c):
		return false
	if water.has(c):
		water.erase(c)
	else:
		water[c] = true
	build_cell(c, true)
	return true
