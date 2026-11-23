extends RefCounted
## Helpers: clay materials and soft rounded meshes.
## Everything is procedural, everything is cached.

const CLAY_SHADER := preload("res://shaders/clay.gdshader")
const WATER_SHADER := preload("res://shaders/water.gdshader")
const GHOST_SHADER := preload("res://shaders/ghost.gdshader")

static var _mats: Dictionary = {}
static var _meshes: Dictionary = {}


static func mat(color: Color, rough: float = 0.75, world_noise: bool = false) -> ShaderMaterial:
	var key := "c%s|%.2f|%s" % [color.to_html(), rough, world_noise]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = CLAY_SHADER
	m.set_shader_parameter("albedo", color)
	m.set_shader_parameter("roughness", rough)
	m.set_shader_parameter("world_offset", 1.0 if world_noise else 0.0)
	_mats[key] = m
	return m


## The shared glowing lantern material: the day-night cycle changes its brightness.
static func lamp_mat() -> ShaderMaterial:
	if _mats.has("lamp"):
		return _mats["lamp"]
	var m := ShaderMaterial.new()
	m.shader = CLAY_SHADER
	m.set_shader_parameter("albedo", Color("ffe6a8"))
	m.set_shader_parameter("roughness", 0.4)
	m.set_shader_parameter("emission_color", Color("ffb24d"))
	m.set_shader_parameter("emission_energy", 0.0)
	_mats["lamp"] = m
	return m


static func water_mat() -> ShaderMaterial:
	if _mats.has("water"):
		return _mats["water"]
	var m := ShaderMaterial.new()
	m.shader = WATER_SHADER
	_mats["water"] = m
	return m


static func ghost_mat(color: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = GHOST_SHADER
	m.set_shader_parameter("color", color)
	return m


static func sphere(r: float) -> SphereMesh:
	var key := "s%.3f" % r
	if _meshes.has(key):
		return _meshes[key]
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 28
	m.rings = 14
	_meshes[key] = m
	return m


static func cyl(top: float, bottom: float, height: float, seg: int = 18) -> CylinderMesh:
	var key := "y%.3f|%.3f|%.3f|%d" % [top, bottom, height, seg]
	if _meshes.has(key):
		return _meshes[key]
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = height
	m.radial_segments = seg
	m.rings = 2
	_meshes[key] = m
	return m


static func cone(radius: float, height: float) -> CylinderMesh:
	return cyl(0.03, radius, height, 22)


## A soft "lip" for a cone's base so the edge isn't sharp.
static func rim(radius: float, tube: float = 0.045) -> TorusMesh:
	var key := "t%.3f|%.3f" % [radius, tube]
	if _meshes.has(key):
		return _meshes[key]
	var m := TorusMesh.new()
	m.inner_radius = maxf(radius - tube * 2.0, 0.001)
	m.outer_radius = radius
	m.rings = 28
	m.ring_segments = 10
	_meshes[key] = m
	return m


## A rounded box: flat faces, edges are quarter circles.
## wobble slightly "squishes" the surface with noise so the blocks look hand-made.
static func rounded_box(size: Vector3, radius: float, seg: int = 3, wobble: float = 0.0, variant: int = 0) -> ArrayMesh:
	size = size.snapped(Vector3(0.01, 0.01, 0.01))
	var key := "b%s|%.3f|%d|%.3f|%d" % [size, radius, seg, wobble, variant]
	if _meshes.has(key):
		return _meshes[key]
	var half := size * 0.5
	var r := clampf(radius, 0.002, minf(half.x, minf(half.y, half.z)) - 0.001)
	var inner := half - Vector3(r, r, r)
	var noise: FastNoiseLite = null
	if wobble > 0.0:
		noise = FastNoiseLite.new()
		noise.seed = 101 + variant * 977
		noise.frequency = 2.2
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	for face in 6:
		var axis := face >> 1
		var s := 1.0 if face % 2 == 0 else -1.0
		var a1 := (axis + 1) % 3
		var a2 := (axis + 2) % 3
		var c1 := _axis_coords(half[a1], r, seg)
		var c2 := _axis_coords(half[a2], r, seg)
		var base := verts.size()
		for j in c2.size():
			for i in c1.size():
				var p := Vector3()
				p[axis] = s * half[axis]
				p[a1] = c1[i]
				p[a2] = c2[j]
				var q := p.clamp(-inner, inner)
				var n := (p - q).normalized()
				var pos := q + n * r
				if noise:
					pos += n * noise.get_noise_3dv(pos) * wobble
				verts.append(pos)
				norms.append(n)
		var w := c1.size()
		for j in c2.size() - 1:
			for i in w - 1:
				var v0 := base + j * w + i
				var v1 := v0 + 1
				var v2 := v0 + w
				var v3 := v2 + 1
				_tri(idx, verts, norms, v0, v1, v2)
				_tri(idx, verts, norms, v1, v3, v2)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_meshes[key] = mesh
	return mesh


## Godot treats clockwise-wound triangles as front faces.
static func _tri(idx: PackedInt32Array, v: PackedVector3Array, n: PackedVector3Array, a: int, b: int, c: int) -> void:
	var cr := (v[b] - v[a]).cross(v[c] - v[a])
	var nn := n[a] + n[b] + n[c]
	if cr.dot(nn) > 0.0:
		idx.append_array([a, c, b])
	else:
		idx.append_array([a, b, c])


## Coordinates along an axis: denser at the edges so the rounding is uniform by angle.
static func _axis_coords(half_len: float, r: float, seg: int) -> PackedFloat32Array:
	var inner := half_len - r
	var out := PackedFloat32Array()
	for k in range(seg, -1, -1):
		out.append(-inner - r * tan(PI * 0.25 * k / seg))
	var mid := maxi(1, ceili(inner * 2.0 / 0.22))
	for k in range(1, mid):
		out.append(-inner + inner * 2.0 * k / mid)
	for k in range(0, seg + 1):
		out.append(inner + r * tan(PI * 0.25 * k / seg))
	return out


static func part(parent: Node3D, mesh: Mesh, material: Material, pos: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi
