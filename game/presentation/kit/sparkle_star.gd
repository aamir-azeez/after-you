extends RefCounted
## World kit: the game's four-pointed sparkle, always facing the camera. A
## pip's reunion draws the plain star (spirit_visual.gd); a keepsake ride's
## trail draws the glint: the star in warm gold over a darker gold rim, with a
## soft white core, so it reads on pale grass and on wood
## (presentation/keepsakes/keepsake_anim.gd spawn_sparkle).
##
## The star spans -1 to 1, so a node's scale is its half width. Meshes and looks
## are made once a session and let go through SessionRelease.
const SessionRelease = preload("res://presentation/kit/session_release.gd")
const RIM := Color("b9771c")
const GOLD := Color("ffc94a")
const CORE := Color("fffaf0")

static var _star: ArrayMesh
static var _glint: ArrayMesh
static var _looks: Dictionary = {}

## The plain star: one surface, its look given by the node.
static func star() -> ArrayMesh:
	if _star == null:
		_star = ArrayMesh.new()
		_star.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _arrays(1.0, 0.0))
		_register()
	return _star

## The glint: the rim, the gold star and the white core, each its own surface
## with its own look, the nearer to the camera the smaller.
static func glint() -> ArrayMesh:
	if _glint == null:
		_glint = ArrayMesh.new()
		var layers := [[1.3, 0.0, RIM], [1.0, 0.05, GOLD], [0.42, 0.1, CORE]]
		for index in range(layers.size()):
			_glint.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _arrays(layers[index][0], layers[index][1]))
			_glint.surface_set_material(index, look(layers[index][2]))
		_register()
	return _glint

## The sparkle's look in `color`: unshaded, facing the camera, scaling with its node.
static func look(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not _looks.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		material.billboard_keep_scale = true
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_looks[key] = material
		_register()
	return _looks[key]

## Every look the glint draws, for the GL warm-up's coverage.
static func glint_looks() -> Array[Material]:
	var result: Array[Material] = []
	for index in range(glint().get_surface_count()): result.append(glint().surface_get_material(index))
	return result

## The star's eight points round its middle, `size` times larger, `lift`
## nearer the camera.
static func _arrays(size: float, lift: float) -> Array:
	var points := PackedVector3Array([
		Vector3(0, 1, 0), Vector3(0.22, 0.22, 0), Vector3(1, 0, 0), Vector3(0.22, -0.22, 0),
		Vector3(0, -1, 0), Vector3(-0.22, -0.22, 0), Vector3(-1, 0, 0), Vector3(-0.22, 0.22, 0)])
	var middle := Vector3(0, 0, lift)
	var vertices := PackedVector3Array()
	for index in range(points.size()):
		vertices.append_array(PackedVector3Array([middle, points[index] * size + middle, points[(index + 1) % points.size()] * size + middle]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	return arrays

static func _register() -> void:
	SessionRelease.on_exit(Callable(load("res://presentation/kit/sparkle_star.gd"), "release_cached"))

## Lets go of the meshes and looks (SessionRelease calls this).
static func release_cached() -> void:
	_star = null
	_glint = null
	_looks.clear()
