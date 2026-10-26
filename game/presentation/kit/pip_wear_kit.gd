extends RefCounted
## Shared pieces for pip cosmetics (presentation/pip_wear/): an item's small
## parts baked into one mesh with vertex colours (Parts), so a many-coloured
## item is one draw call with one material, and the glow pieces: a soft round
## sprite (halo) and a faint beam, added on top, so a glow shows without bloom
## or a light node.
##
## Meshes are built once per item and shared by every pip wearing it
## (cached_mesh); the halo texture, the quads and the shared materials are
## kept too. They hold GPU resources, so their release is registered with
## kit/session_release.gd. Materials an item animates (a lamp that brightens
## and dims) are made per pip and go with it.
const SessionRelease = preload("res://presentation/kit/session_release.gd")
const SCRIPT_PATH := "res://presentation/kit/pip_wear_kit.gd"

## How many sides the small round parts get: enough at a pip's size, and an
## item stays within about 600 triangles.
const SEGMENTS := 8
const RINGS := 4

static var _meshes: Dictionary = {}
static var _vertex_material: StandardMaterial3D
static var _star_materials: Dictionary = {}
static var _halo_texture: GradientTexture2D

## Lets go of every kept mesh, material and texture (at shutdown).
static func release_cached() -> void:
	_meshes.clear()
	_vertex_material = null
	_star_materials.clear()
	_halo_texture = null

static func _keep() -> void:
	SessionRelease.on_exit(Callable(load(SCRIPT_PATH), "release_cached"))

## The mesh made by `build` (a Callable returning a Mesh) for `key`, built the
## first time and shared after.
static func cached_mesh(key: String, build: Callable) -> Mesh:
	var found: Mesh = _meshes.get(key)
	if found != null: return found
	found = build.call()
	_meshes[key] = found
	_keep()
	return found

## How many meshes are kept (tests).
static func cached_count() -> int:
	return _meshes.size()

## The one matte material every baked item uses: its colours are the mesh's.
static func vertex_material() -> StandardMaterial3D:
	if _vertex_material == null:
		_vertex_material = StandardMaterial3D.new()
		_vertex_material.vertex_color_use_as_albedo = true
		_vertex_material.roughness = 0.9
		_keep()
	return _vertex_material

## A glowing part's own material (emissive, no light node); made per pip, so
## an item may animate it.
static func glow_material(color: Color, glow: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	material.emission_enabled = true
	material.emission = glow
	material.emission_energy_multiplier = energy
	return material

## A soft round glow: one quad facing the camera, added on top and still hidden
## by whatever stands in front of it. Its material is its own (alpha may be
## animated through albedo_color.a).
static func halo(size: float, color: Color, strength: float) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.albedo_texture = _halo()
	material.albedo_color = Color(color, strength)
	var node := MeshInstance3D.new()
	node.name = "Halo"
	node.mesh = cached_mesh("quad:%s" % size, func() -> Mesh:
		var quad := QuadMesh.new()
		quad.size = Vector2(size, size)
		return quad)
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node

static func _halo() -> GradientTexture2D:
	if _halo_texture == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(1, 1, 1, 1))
		gradient.set_color(1, Color(1, 1, 1, 0))
		gradient.add_point(0.35, Color(1, 1, 1, 0.45))
		_halo_texture = GradientTexture2D.new()
		_halo_texture.fill = GradientTexture2D.FILL_RADIAL
		_halo_texture.fill_from = Vector2(0.5, 0.5)
		_halo_texture.fill_to = Vector2(1.0, 0.5)
		_halo_texture.width = 64
		_halo_texture.height = 64
		_halo_texture.gradient = gradient
		_keep()
	return _halo_texture

## A faint beam: two crossed flat wedges from `origin` along `direction`,
## fading out along their length, added on top. Its material is its own
## (alpha through albedo_color.a).
static func beam(key: String, origin: Vector3, direction: Vector3, length: float, width: float, strength: float) -> MeshInstance3D:
	var mesh := cached_mesh("beam:" + key, func() -> Mesh:
		var along := direction.normalized()
		var side := along.cross(Vector3.UP).normalized()
		var up := side.cross(along).normalized()
		var vertices := PackedVector3Array()
		var colors := PackedColorArray()
		for axis: Vector3 in [side, up]:
			vertices.append_array(PackedVector3Array([origin, origin + along * length + axis * width * 0.5, origin + along * length - axis * width * 0.5]))
			colors.append_array(PackedColorArray([Color.WHITE, Color(1, 1, 1, 0), Color(1, 1, 1, 0)]))
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_COLOR] = colors
		var made := ArrayMesh.new()
		made.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return made)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(1, 0.93, 0.72, strength)
	var node := MeshInstance3D.new()
	node.name = "Beam"
	node.mesh = mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node

## Little four-point stars facing the camera, one mesh: each [x, y, size] in
## the node's plane around its origin.
static func stars(key: String, points: Array, color: Color) -> MeshInstance3D:
	var mesh := cached_mesh("stars:" + key, func() -> Mesh:
		var outline := [Vector2(0, 1), Vector2(0.22, 0.22), Vector2(1, 0), Vector2(0.22, -0.22), Vector2(0, -1), Vector2(-0.22, -0.22), Vector2(-1, 0), Vector2(-0.22, 0.22)]
		var vertices := PackedVector3Array()
		for point: Array in points:
			var at := Vector3(float(point[0]), float(point[1]), 0.0)
			var size := float(point[2])
			for index in range(outline.size()):
				var a: Vector2 = outline[index] * size
				var b: Vector2 = outline[(index + 1) % outline.size()] * size
				vertices.append_array(PackedVector3Array([at, at + Vector3(a.x, a.y, 0), at + Vector3(b.x, b.y, 0)]))
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		var made := ArrayMesh.new()
		made.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return made)
	var node := MeshInstance3D.new()
	node.name = "Stars"
	node.mesh = mesh
	node.material_override = _star_material(color)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node

## One shared unshaded, camera-facing material per star colour.
static func _star_material(color: Color) -> StandardMaterial3D:
	var found: StandardMaterial3D = _star_materials.get(color)
	if found != null: return found
	found = StandardMaterial3D.new()
	found.albedo_color = color
	found.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	found.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	found.billboard_keep_scale = true
	found.cull_mode = BaseMaterial3D.CULL_DISABLED
	_star_materials[color] = found
	_keep()
	return found

## A part's mesh scaled about its own origin, as a new mesh (a bigger leaf).
static func scaled(mesh: Mesh, scale: float) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.append_from(mesh, 0, Transform3D(Basis().scaled(Vector3.ONE * scale), Vector3.ZERO))
	return tool.commit()

## A pivot that, parented to a part resting at `rest`, puts its children back
## in the part's parent space at rest; they then follow the part's motion (a
## lantern that sways with the leaf).
static func follow(rest: Transform3D) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = "Follow"
	pivot.transform = rest.affine_inverse()
	return pivot

## An item's small parts baked into one mesh, each with its own colour.
## Positions, sizes and turns are in the frame on top of the stack (push).
class Parts:
	var _tool := SurfaceTool.new()
	var _frames: Array[Transform3D] = [Transform3D.IDENTITY]
	var _empty := true

	func _init() -> void:
		_tool.begin(Mesh.PRIMITIVE_TRIANGLES)

	## Parts after this sit in `frame`, within the current one, until pop().
	func push(frame: Transform3D) -> void:
		_frames.append(_frames.back() * frame)

	func pop() -> void:
		if _frames.size() > 1: _frames.pop_back()

	static func place(at: Vector3, rotation: Vector3 = Vector3.ZERO, size: Vector3 = Vector3.ONE) -> Transform3D:
		return Transform3D(Basis.from_euler(rotation).scaled_local(size), at)

	## An ellipsoid with these half sizes.
	func blob(color: Color, at: Vector3, size: Vector3, rotation: Vector3 = Vector3.ZERO, segments: int = SEGMENTS, rings: int = RINGS) -> void:
		var sphere := SphereMesh.new()
		sphere.radius = 1.0
		sphere.height = 2.0
		sphere.radial_segments = segments
		sphere.rings = rings
		add(sphere, color, place(at, rotation, size))

	## A blob placed by a full transform (an ellipsoid set on a curved surface).
	func blob_at(color: Color, frame: Transform3D, segments: int = SEGMENTS, rings: int = RINGS) -> void:
		var sphere := SphereMesh.new()
		sphere.radius = 1.0
		sphere.height = 2.0
		sphere.radial_segments = segments
		sphere.rings = rings
		add(sphere, color, frame)

	## A cylinder (a cone with `top` 0), centred on `at`.
	func cylinder(color: Color, at: Vector3, radius: float, height: float, top: float = -1.0, rotation: Vector3 = Vector3.ZERO, segments: int = 12) -> void:
		var shape := CylinderMesh.new()
		shape.bottom_radius = radius
		shape.top_radius = radius if top < 0.0 else top
		shape.height = height
		shape.radial_segments = segments
		shape.rings = 0
		add(shape, color, place(at, rotation))

	## A thin ring lying flat (a torus), squashed by `size`.
	func ring(color: Color, at: Vector3, inner: float, outer: float, size: Vector3 = Vector3.ONE, rotation: Vector3 = Vector3.ZERO, rings: int = 16, sides: int = 4) -> void:
		var torus := TorusMesh.new()
		torus.inner_radius = inner
		torus.outer_radius = outer
		torus.rings = rings
		torus.ring_segments = sides
		add(torus, color, place(at, rotation, size))

	## A rod from `from` to `to`.
	func rod(color: Color, from: Vector3, to: Vector3, radius: float, segments: int = 6) -> void:
		var along := to - from
		var up := along.normalized()
		var side := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
		var basis := Basis(side, up, side.cross(up))
		var shape := CylinderMesh.new()
		shape.top_radius = radius
		shape.bottom_radius = radius
		shape.height = along.length()
		shape.radial_segments = segments
		shape.rings = 0
		shape.cap_top = false
		shape.cap_bottom = false
		add(shape, color, Transform3D(basis, (from + to) * 0.5))

	## Any primitive's triangles, placed by `frame` in the current frame.
	func add(shape: Mesh, color: Color, frame: Transform3D) -> void:
		var arrays: Array = shape.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var placed: Transform3D = _frames.back() * frame
		var turn := placed.basis.inverse().transposed()
		var flip := placed.basis.determinant() < 0.0
		var count := indices.size() if not indices.is_empty() else vertices.size()
		var triangle := [0, 0, 0]
		for index in range(count):
			var vertex := indices[index] if not indices.is_empty() else index
			triangle[index % 3] = vertex
			if index % 3 != 2: continue
			var order := [triangle[0], triangle[2], triangle[1]] if flip else triangle
			for corner: int in order:
				_tool.set_color(color)
				_tool.set_normal((turn * normals[corner]).normalized())
				_tool.add_vertex(placed * vertices[corner])
		_empty = false

	## The baked mesh (one surface).
	func commit() -> ArrayMesh:
		return _tool.commit() if not _empty else ArrayMesh.new()
