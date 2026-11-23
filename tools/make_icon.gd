extends SceneTree
## App icon (stage 11): a render of the game's real clay models (terrain.gd, items.gd) — not a single hand-drawn
## image. Run only with a window (headless renders nothing):
##   Godot --path . --script res://tools/make_icon.gd                 — final files into icon/
##   Godot --path . --script res://tools/make_icon.gd -- --candidates — all variants into icon/candidates/ for comparison
## Everything uses fixed seeds, the "summer" season, time of day plays no part — the result repeats. The PNGs are committed.

const Terrain := preload("res://scripts/terrain.gd")
const Items := preload("res://scripts/items.gd")

const CHOSEN := "B_duo"                  # chosen at the defense (both critics)
const SKY_TOP := Color("6fc3d8")         # saturated turquoise: the icon doesn't fade on light wallpapers
const SKY_BOTTOM := Color("f7d3a6")      # warm peach at the horizon — coziness
const SHADOW := Color(0.18, 0.22, 0.30, 0.28)
const SAFE_D := 264.0                    # adaptive icon: the mask circle is 66 dp of 108 → 264 px of 432

const VARIANTS := {
	"A_island": {
		"heights": {Vector2i(0, 0): 2, Vector2i(1, 0): 2, Vector2i(0, 1): 2, Vector2i(1, 1): 1, Vector2i(2, 0): 1, Vector2i(2, 1): 1, Vector2i(0, 2): 1, Vector2i(1, 2): 1, Vector2i(2, 2): 1},
		"water": [Vector2i(2, 2)],
		"items": {Vector2i(0, 0): "tree", Vector2i(1, 0): "pine", Vector2i(0, 1): "flowers", Vector2i(2, 1): "bench", Vector2i(1, 2): "flowers", Vector2i(2, 2): "lily"},
	},
	"B_duo": {
		"heights": {Vector2i(0, 0): 2, Vector2i(1, 0): 1, Vector2i(0, 1): 1, Vector2i(1, 1): 1},
		"water": [Vector2i(1, 1)],
		"items": {Vector2i(0, 0): "tree", Vector2i(1, 0): "flowers", Vector2i(0, 1): "mushroom", Vector2i(1, 1): "lily"},
	},
	"C_tree": {
		"heights": {Vector2i(0, 0): 1},
		"water": [],
		"items": {Vector2i(0, 0): "tree"},
	},
	"D_pond": {
		"heights": {Vector2i(0, 0): 2, Vector2i(1, 0): 2, Vector2i(2, 0): 2, Vector2i(0, 1): 2, Vector2i(1, 1): 2, Vector2i(2, 1): 2, Vector2i(0, 2): 2, Vector2i(1, 2): 2, Vector2i(2, 2): 2},
		"water": [Vector2i(1, 1)],
		"items": {Vector2i(0, 0): "pine", Vector2i(2, 0): "tree", Vector2i(1, 1): "lily", Vector2i(0, 2): "flowers", Vector2i(2, 2): "lantern", Vector2i(1, 0): "bush"},
	},
}


func _initialize() -> void:
	_run()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("make_icon: needs a windowed run (without --headless) — headless renders nothing")
		quit(1)
		return
	if "--candidates" in OS.get_cmdline_user_args():
		DirAccess.make_dir_recursive_absolute("res://icon/candidates")
		for key in VARIANTS:
			_full(await _island(VARIANTS[key]), 1024).save_png("res://icon/candidates/%s.png" % key)
		quit()
		return
	var island := await _island(VARIANTS[CHOSEN])
	DirAccess.make_dir_recursive_absolute("res://icon")
	_full(island, 1024).save_png("res://icon/icon.png")            # config/icon: the PC window, fallback for Android
	_full(island, 192).save_png("res://icon/android_192.png")       # launcher_icons/main_192x192
	var fg := _foreground(island, 432)
	fg.save_png("res://icon/android_foreground.png")                # adaptive: foreground
	_sky(432, false).save_png("res://icon/android_background.png")  # adaptive: background (no clouds — the mask would cut them)
	# monochrome (Android 13+ themed icons, a common setting on Pixel): without it Godot substitutes ITS OWN logo.
	# Not a white blob: a toned silhouette — dark parts denser, light parts more transparent; crown, cap and block edges show.
	_monochrome(fg).save_png("res://icon/android_monochrome.png")
	_check_safe(fg)
	_preview(island, fg)
	quit()


## The island on a transparent background, cropped to its opaque pixels.
func _island(spec: Dictionary) -> Image:
	var px := 1024
	var vp := SubViewport.new()
	vp.size = Vector2i(px, px)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_8X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("e6eef6")
	env.ambient_light_energy = 0.62
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.15
	we.environment = env
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.shadow_blur = 1.2
	sun.light_energy = 1.25
	sun.light_color = Color("fff1dc")
	sun.rotation = Vector3(deg_to_rad(-52.0), deg_to_rad(-60.0), 0.0)
	vp.add_child(sun)
	var t := Terrain.new()
	t.season = "summer"
	vp.add_child(t)
	var hs: Dictionary = spec["heights"]
	for c in hs:
		t.heights[c] = int(hs[c])
		t.bottoms[c] = -0.5 - 0.1 * ((c.x + c.y) % 2)   # roots shorter and more even than in the game
	for c in spec["water"]:
		t.water[c] = true
	t.build_all()
	var center := Vector3.ZERO
	for c in hs:
		center += t.cell_center(c)
	center /= float(hs.size())
	var its: Dictionary = spec["items"]
	var k := 0
	for c in its:
		k += 1
		var n := Items.build(its[c], 4242 + k * 17, "summer")
		n.position = t.cell_center(c) + Vector3(0, t.surface_y(c), 0)
		if its[c] == "mushroom":
			n.scale = Vector3.ONE * 1.2   # the red cap is the main color accent at 48 px
		vp.add_child(n)
	var piv := Node3D.new()
	piv.position = center + Vector3(0, 0.9, 0)
	piv.rotation.y = PI * 0.25
	vp.add_child(piv)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 6.0   # with a margin: we crop to the opaque pixels afterwards
	cam.near = 0.5
	cam.far = 120.0
	cam.rotation.x = deg_to_rad(-32.0)
	piv.add_child(cam)
	cam.position = cam.transform.basis.z * 30.0
	cam.current = true
	for i in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	vp.queue_free()
	return img.get_region(img.get_used_rect())


## Sky: turquoise → peach; clouds — small crisp clouds in the visible zone.
func _sky(px: int, clouds: bool) -> Image:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	for y in px:
		var k := float(y) / (px - 1)
		var col := SKY_TOP.lerp(SKY_BOTTOM, k * k * 0.9 + k * 0.1)
		for x in px:
			img.set_pixel(x, y, col)
	if clouds:
		for b in [[0.22, 0.26, 0.055], [0.29, 0.25, 0.07], [0.35, 0.27, 0.05], [0.74, 0.36, 0.05], [0.80, 0.35, 0.065]]:
			_disc(img, b[0] * px, b[1] * px, b[2] * px, Color("ffffff"), 0.92)
	return img


func _disc(img: Image, cx: float, cy: float, r: float, col: Color, alpha: float) -> void:
	var w := img.get_width()
	var hgt := img.get_height()
	for y in range(maxi(0, int(cy - r - 2)), mini(hgt, int(cy + r + 2))):
		for x in range(maxi(0, int(cx - r - 2)), mini(w, int(cx + r + 2))):
			var d := Vector2(x - cx, y - cy).length()
			var a: float = clampf(r + 0.5 - d, 0.0, 1.0) * alpha   # smooth edge
			if a > 0.0:
				img.set_pixel(x, y, img.get_pixel(x, y).lerp(col, a))


## A soft elliptical shadow under the island: separates the silhouette from the background.
func _shadow(img: Image, cx: float, cy: float, rx: float, ry: float) -> void:
	var px := img.get_width()
	for y in range(maxi(0, int(cy - ry * 1.6)), mini(px, int(cy + ry * 1.6))):
		for x in range(maxi(0, int(cx - rx * 1.6)), mini(px, int(cx + rx * 1.6))):
			var d := Vector2((x - cx) / rx, (y - cy) / ry).length()
			if d < 1.5:
				var a: float = SHADOW.a * clampf(1.0 - d / 1.5, 0.0, 1.0)
				img.set_pixel(x, y, img.get_pixel(x, y).lerp(Color(SHADOW, 1.0), a))


## The full icon: sky, small clouds, shadow, the island at 74% of the width, centered.
func _full(island: Image, px: int) -> Image:
	var out := _sky(px, true)
	var isl := island.duplicate()
	var w: float = px * 0.74
	var h: float = w * isl.get_height() / isl.get_width()
	if h > px * 0.8:
		h = px * 0.8
		w = h * isl.get_width() / isl.get_height()
	isl.resize(int(w), int(h), Image.INTERPOLATE_LANCZOS)
	var pos := Vector2i(int((px - w) * 0.5), int((px - h) * 0.56))
	_shadow(out, px * 0.5, pos.y + h * 0.97, w * 0.36, px * 0.035)
	out.blend_rect(isl, Rect2i(Vector2i.ZERO, isl.get_size()), pos)
	return out


## Adaptive foreground: the island fits the safe circle by its opaque-pixel bounds.
func _foreground(island: Image, px: int) -> Image:
	var out := Image.create(px, px, false, Image.FORMAT_RGBA8)
	var isl := island.duplicate()
	var diag := Vector2(isl.get_width(), isl.get_height()).length()
	var k: float = (SAFE_D - 6.0) / diag * 1.24   # by the bounds' diagonal, with a margin; the farthest pixel after scaling ≈ 128 of 132
	isl.resize(int(isl.get_width() * k), int(isl.get_height() * k), Image.INTERPOLATE_LANCZOS)
	var pos := Vector2i((px - isl.get_width()) / 2, (px - isl.get_height()) / 2)
	out.blend_rect(isl, Rect2i(Vector2i.ZERO, isl.get_size()), pos)
	return out


func _monochrome(fg: Image) -> Image:
	var out := Image.create(fg.get_width(), fg.get_height(), false, Image.FORMAT_RGBA8)
	for y in fg.get_height():
		for x in fg.get_width():
			var c := fg.get_pixel(x, y)
			if c.a <= 0.0:
				continue
			var lum := c.r * 0.3 + c.g * 0.59 + c.b * 0.11
			var a: float = c.a * clampf(1.15 - lum * 0.95, 0.35, 1.0)
			out.set_pixel(x, y, Color(1, 1, 1, a))
	return out


## Check: every opaque foreground pixel is inside the mask circle.
func _check_safe(fg: Image) -> void:
	var c := Vector2(fg.get_width(), fg.get_height()) * 0.5
	var worst := 0.0
	for y in fg.get_height():
		for x in fg.get_width():
			if fg.get_pixel(x, y).a > 0.05:
				worst = maxf(worst, Vector2(x + 0.5, y + 0.5).distance_to(c))
	print("adaptive icon: farthest pixel %.0f px from the center (mask circle — %.0f)" % [worst, SAFE_D * 0.5])
	if worst > SAFE_D * 0.5:
		push_error("the island goes beyond the adaptive icon's safe circle")


## Review sheet: light, dark and busy wallpapers; the icon among "other" tiles at 96 and 48 px; adaptive in a circle.
func _preview(island: Image, fg: Image) -> void:
	var sheet := Image.create(3 * 420, 260, false, Image.FORMAT_RGBA8)
	var walls := [Color("f2efe9"), Color("23262e"), Color("8c6a9e")]
	var others := [Color("e84b3c"), Color("3b7dd8"), Color("f4b400"), Color("2e9e5b"), Color("9b59b6")]
	var full := _full(island, 1024)
	var ad := _sky(432, false)
	ad.blend_rect(fg, Rect2i(0, 0, 432, 432), Vector2i.ZERO)
	ad = ad.get_region(Rect2i(54, 54, 324, 324))   # the visible part: 72 dp of 108
	ad.resize(96, 96, Image.INTERPOLATE_LANCZOS)
	_mask(ad, 48, true)
	for i in 3:
		var x0 := i * 420
		sheet.fill_rect(Rect2i(x0, 0, 420, 260), walls[i])
		if i == 2:
			for s in 12:
				_disc(sheet, x0 + 30 + s * 33, 40 + (s % 3) * 80, 44, Color("d9a3b8") if s % 2 else Color("6f9ccc"), 0.6)
		for j in 4:
			var tile: Image
			if j == 1:
				tile = full.duplicate()
				tile.resize(96, 96, Image.INTERPOLATE_LANCZOS)
			else:
				tile = Image.create(96, 96, false, Image.FORMAT_RGBA8)
				tile.fill(others[(j + i) % others.size()])
			_mask(tile, 96 * 0.22, false)
			sheet.blend_rect(tile, Rect2i(0, 0, 96, 96), Vector2i(x0 + 12 + j * 102, 14))
		var small := full.duplicate()
		small.resize(48, 48, Image.INTERPOLATE_LANCZOS)
		_mask(small, 48 * 0.22, false)
		for j in 4:
			var t2: Image = small if j == 2 else Image.create(48, 48, false, Image.FORMAT_RGBA8)
			if j != 2:
				t2.fill(others[(j + i + 2) % others.size()])
				_mask(t2, 48 * 0.22, false)
			sheet.blend_rect(t2, Rect2i(0, 0, 48, 48), Vector2i(x0 + 20 + j * 60, 140))
		sheet.blend_rect(ad, Rect2i(0, 0, 96, 96), Vector2i(x0 + 290, 128))
	sheet.save_png("res://icon/preview.png")


func _mask(img: Image, r: float, circle: bool) -> void:
	var w := img.get_width()
	for y in w:
		for x in w:
			var out := false
			if circle:
				out = Vector2(x + 0.5 - w * 0.5, y + 0.5 - w * 0.5).length() > w * 0.5
			else:
				var dx := maxf(maxf(r - x, x - (w - 1 - r)), 0.0)
				var dy := maxf(maxf(r - y, y - (w - 1 - r)), 0.0)
				out = dx * dx + dy * dy > r * r
			if out:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
