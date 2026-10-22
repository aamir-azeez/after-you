extends RefCounted
## World kit: walls that fade while a spirit stands behind them. A world adds a
## spot for each place a spirit can stand hidden (a plan rectangle in cm) with
## the meshes that hide it from the camera; with each snapshot it says where
## the spirits stand (occupy), and each frame advance() eases every spot's
## meshes toward FADED_ALPHA while a spirit stands in it, and back to solid
## once none does. The targets come from the snapshot's positions alone, so
## live play, the memory and a replay fade the same walls; an immediate call
## (a seek, a retry, reduced motion) snaps. Visual only.
##
##   var fade := WallFade.new()
##   fade.add([x0, z0, x1, z1], [front_wall, coping])
##   fade.occupy(spirit_positions_cm, immediate)   # each snapshot
##   if fade.moving(): fade.advance(delta)          # each frame
##
## Each faded mesh gets its own material copy when it is added (a kit look is
## shared and never changed in place); it stays opaque, with its own shadow
## setting, while solid, and turns alpha-blended only while it fades. A mesh
## serving several spots shows the faintest of them. Nothing here is static,
## so nothing needs SessionRelease, and no frame allocates.
const Primitives = preload("res://presentation/kit/primitives.gd")
## How much of a wall still shows while a spirit stands behind it.
const FADED_ALPHA := 0.08
## How fast a wall fades or comes back (alpha a second): about a fifth of a second.
const RATE := 4.5

## Per spot: {"rect": Rect2 (cm), "indices": PackedInt32Array into the mesh
## arrays, "alpha": shown, "target": wanted}.
var _spots: Array[Dictionary] = []
var _meshes: Array[MeshInstance3D] = []
var _materials: Array[StandardMaterial3D] = []
var _shadows: PackedInt32Array = PackedInt32Array()
## Each mesh's alpha this frame, refilled in place.
var _alphas: PackedFloat32Array = PackedFloat32Array()
var _moving := false

## A spot at `rect_cm` ([x0, z0, x1, z1]) hidden by `meshes`.
func add(rect_cm: Array, meshes: Array) -> void:
	var indices := PackedInt32Array()
	for node: Variant in meshes:
		var mesh := node as MeshInstance3D
		if mesh == null or not (mesh.material_override is StandardMaterial3D): continue
		var index := _meshes.find(mesh)
		if index < 0:
			index = _meshes.size()
			_meshes.append(mesh)
			_materials.append(Primitives.own_material(mesh))
			_shadows.append(mesh.cast_shadow)
			_alphas.append(1.0)
		if not indices.has(index): indices.append(index)
	var rect := Rect2(float(rect_cm[0]), float(rect_cm[1]), float(rect_cm[2]) - float(rect_cm[0]), float(rect_cm[3]) - float(rect_cm[1]))
	_spots.append({"rect": rect, "indices": indices, "alpha": 1.0, "target": 1.0})

## Every mesh the spots fade, for a world's list of nodes its static fold keeps whole.
func meshes() -> Array[MeshInstance3D]:
	return _meshes

## How many spots fade now (target below solid), for tests.
func faded_spots() -> int:
	var count := 0
	for spot: Dictionary in _spots:
		if float(spot.target) < 1.0: count += 1
	return count

## Where the spirits stand (plan cm): a spot with one inside fades, the others
## come back. Immediate snaps every spot to its target.
func occupy(spirits: PackedVector2Array, immediate: bool = false) -> void:
	for spot: Dictionary in _spots:
		var inside := false
		for at: Vector2 in spirits:
			if (spot.rect as Rect2).has_point(at): inside = true
		spot.target = FADED_ALPHA if inside else 1.0
		if immediate: spot.alpha = spot.target
		if not is_equal_approx(float(spot.alpha), float(spot.target)): _moving = true
	if immediate: _apply()

func moving() -> bool:
	return _moving

## Eases every spot toward its target; does nothing once all rest.
func advance(delta: float) -> void:
	if not _moving: return
	for spot: Dictionary in _spots:
		spot.alpha = move_toward(float(spot.alpha), float(spot.target), RATE * maxf(delta, 0.0))
	_apply()

func _apply() -> void:
	_moving = false
	_alphas.fill(1.0)
	for spot: Dictionary in _spots:
		if not is_equal_approx(float(spot.alpha), float(spot.target)): _moving = true
		for index: int in spot.indices: _alphas[index] = minf(_alphas[index], float(spot.alpha))
	for index in range(_meshes.size()):
		var alpha := _alphas[index]
		var solid := alpha >= 0.999
		var material := _materials[index]
		if solid == (material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED) and is_equal_approx(material.albedo_color.a, 1.0 if solid else alpha): continue
		material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED if solid else BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color.a = 1.0 if solid else alpha
		_meshes[index].cast_shadow = _shadows[index] if solid else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
