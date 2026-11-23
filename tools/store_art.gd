extends SceneTree
## Stage 12: the 512 icon for Play from icon/icon.png and the listing thumbnail sheet shots/store_contact.png.
## Run by tools/store_shots.py (headless): Godot --headless --path . --script res://tools/store_art.gd -- --langs=ru,en

const THUMB := Vector2i(320, 180)   # roughly the size of screenshot cards on the Play page
const GAP := 16


func _initialize() -> void:
	var langs := ["ru", "en"]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--langs="):
			langs = a.substr(8).split(",")
	var store := ProjectSettings.globalize_path("res://store")
	# 512 icon: PNG with alpha, from the same 1024 px icon the app uses
	var icon := Image.load_from_file(ProjectSettings.globalize_path("res://icon/icon.png"))
	icon.convert(Image.FORMAT_RGBA8)
	icon.resize(512, 512, Image.INTERPOLATE_LANCZOS)
	icon.save_png(store.path_join("icon-512.png"))
	# the sheet: one row per language (5 shots), below — the 1024×500 graphic and the icon at thumbnail size
	var rows := []
	for lang in langs:
		var row := []
		var dir := store.path_join(lang).path_join("screenshots")
		var files := Array(DirAccess.get_files_at(dir)).filter(func(f): return f.ends_with(".png"))
		files.sort()
		for f in files:
			row.append(Image.load_from_file(dir.path_join(f)))
		rows.append(row)
	var cols := 1
	for r in rows:
		cols = maxi(cols, r.size())
	var w := GAP + cols * (THUMB.x + GAP)
	var feat_h := int(THUMB.y * 1.25)
	var h := GAP + rows.size() * (THUMB.y + GAP) + feat_h + GAP
	var sheet := Image.create(w, h, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("ffffff"))   # white background — like the Play page
	for ri in rows.size():
		for ci in rows[ri].size():
			var im: Image = rows[ri][ci]
			im.convert(Image.FORMAT_RGBA8)
			im.resize(THUMB.x, THUMB.y, Image.INTERPOLATE_LANCZOS)
			sheet.blit_rect(im, Rect2i(Vector2i.ZERO, THUMB), Vector2i(GAP + ci * (THUMB.x + GAP), GAP + ri * (THUMB.y + GAP)))
	var y := GAP + rows.size() * (THUMB.y + GAP)
	var fpath := store.path_join("feature-graphic.png")
	if FileAccess.file_exists(fpath):
		var f := Image.load_from_file(fpath)
		f.convert(Image.FORMAT_RGBA8)
		f.resize(int(feat_h * 1024.0 / 500.0), feat_h, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(f, Rect2i(Vector2i.ZERO, f.get_size()), Vector2i(GAP, y))
	var small := icon.duplicate()
	small.resize(96, 96, Image.INTERPOLATE_LANCZOS)
	sheet.blend_rect(small, Rect2i(0, 0, 96, 96), Vector2i(w - GAP - 96, y))
	var out := ProjectSettings.globalize_path("res://shots/store_contact.png")
	sheet.save_png(out)
	print("store_art: icon-512, sheet %s — done" % out)
	quit()
