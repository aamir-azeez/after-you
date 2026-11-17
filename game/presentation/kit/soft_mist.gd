extends RefCounted
## World kit: soft haze for spray, fog banks and lamp light. A blot is a flat
## card whose round middle fades to nothing at its rim, so it reads as a haze
## rather than a ball. Every blot of one tint shares one look and one small
## radial texture, kept for the session (SessionRelease), and a cluster of
## blots is one mesh: one draw for a waterfall's whole spray.
##
## Haze is see-through, so it writes no depth and never z-fights; it is only
## drawing and never hides a pip (each user keeps it clear of what matters).

const SessionRelease = preload("res://presentation/kit/session_release.gd")

static var _looks: Dictionary = {}
static var _texture: GradientTexture2D

## The haze look in `color` (its alpha is the middle's). `instanced`: a
## MultiMesh's per-blot colours tint it. `glow`: added on top, as light is.
static func look(color: Color, instanced: bool = false, glow: bool = false) -> StandardMaterial3D:
	var key := "%s|%s|%s" % [color.to_html(), instanced, glow]
	if _looks.has(key): return _looks[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.albedo_texture = _blot()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = instanced
	# Drawn after the other see-through things (water, a falls' sheet), so a
	# haze in front of them is never painted over by them.
	mat.render_priority = 1
	if glow: mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_looks[key] = mat
	SessionRelease.on_exit(Callable(load("res://presentation/kit/soft_mist.gd"), "release"))
	return mat

## Lets go of the kept looks and texture (SessionRelease, at shutdown).
static func release() -> void:
	_looks.clear()
	_texture = null

## The round blot: white, opaque in the middle, gone at the rim.
static func _blot() -> GradientTexture2D:
	if _texture != null: return _texture
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.45, 0.78, 1.0])
	gradient.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.85), Color(1, 1, 1, 0.38), Color(1, 1, 1, 0)])
	_texture = GradientTexture2D.new()
	_texture.gradient = gradient
	_texture.fill = GradientTexture2D.FILL_RADIAL
	_texture.fill_from = Vector2(0.5, 0.5)
	_texture.fill_to = Vector2(1.0, 0.5)
	_texture.width = 64
	_texture.height = 64
	return _texture

## One mesh of blots, each [centre (m), size (m, across and up or deep),
## facing ("up" lies flat, "front" stands facing +z)].
static func cluster(blots: Array) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for blot: Array in blots:
		var centre: Vector3 = blot[0]
		var half: Vector2 = (blot[1] as Vector2) * 0.5
		var flat := str(blot[2]) == "up"
		var across := Vector3(half.x, 0, 0)
		var other := Vector3(0, 0, half.y) if flat else Vector3(0, half.y, 0)
		var normal := Vector3.UP if flat else Vector3.BACK
		var corners := [centre - across - other, centre + across - other, centre + across + other, centre - across + other]
		var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
		for index: int in [0, 1, 2, 0, 2, 3]:
			surface.set_normal(normal)
			surface.set_uv(uvs[index])
			surface.add_vertex(corners[index])
	return surface.commit()

## A cluster of blots in `color` under `parent`, casting no shadow.
static func build(blots: Array, color: Color, parent: Node3D, glow: bool = false) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = "SoftMist"
	node.mesh = cluster(blots)
	node.material_override = look(color, false, glow)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node
