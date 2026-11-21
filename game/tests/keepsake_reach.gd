extends RefCounted
## Where a Home keepsake really reaches: the shapes of the meshes its builder
## draws (Blender models included), in its own frame, at rest and through its
## whole tap, the Tween stepped STEP at a time like frames. A shape is a mesh's
## ground outline (the hull of its vertices seen from above) and the heights it
## spans, so two shapes meet only where both their outlines and their heights
## do. The tap's own effects (drops, bursts, halos under anim.fx) are left out:
## they are not things that stand. test_keepsake_props keeps a keepsake's own
## pieces apart with it, test_home_keepsake_layer keeps the keepsakes and
## Home's props apart.
const Anim = preload("res://presentation/keepsakes/keepsake_anim.gd")
const STEP := 1.0 / 20.0

## {"still": [shape], "parts": {name: {"pivot": Vector3 (where it rests),
## "shapes": [shape], "points": PackedVector3Array (its meshes' vertices)}}}:
## the still meshes once, and each moving part's meshes at every step. A shape
## is {"hull": PackedVector2Array (x, z), "low": float, "high": float}.
static func sweep(holder: Node, builder: RefCounted, state: Dictionary) -> Dictionary:
	var prop := Node3D.new()
	holder.add_child(prop)
	var parts: Dictionary = builder.build(prop, state)
	var moving := {}
	for name: Variant in parts:
		if parts[name] is Node3D: moving[name] = parts[name]
	var anim := Anim.new()
	anim.fx = Node3D.new()
	prop.add_child(anim.fx)
	var result := {"still": [], "parts": {}}
	for mesh: MeshInstance3D in _meshes(prop):
		if anim.fx.is_ancestor_of(mesh) or moving.values().any(func(part: Node3D) -> bool: return part.is_ancestor_of(mesh)): continue
		result.still.append(_shape(_points(prop, mesh)))
	for name: Variant in moving:
		var at: Vector3 = prop.global_transform.affine_inverse() * (moving[name] as Node3D).global_position
		result.parts[name] = {"pivot": at, "shapes": [], "points": PackedVector3Array()}
	var tween := prop.create_tween().set_parallel(true)
	tween.pause()
	anim.tween = tween
	var time := 0.0
	for beat: Dictionary in builder.beats(state):
		anim.start = time
		builder.play(str(beat.beat), anim, parts, state)
		time += float(beat.time)
	tween.tween_interval(time)
	var clock := 0.0
	var seen := {}
	while true:
		for name: Variant in moving:
			for mesh: MeshInstance3D in _meshes(moving[name]):
				# A part at rest through most of a tap gives the same shape again and again.
				var placed := prop.global_transform.affine_inverse() * mesh.global_transform
				var key := [mesh.get_instance_id(), placed]
				if seen.has(key): continue
				seen[key] = true
				var points := placed * _corners(mesh.mesh)
				result.parts[name].shapes.append(_shape(points))
				result.parts[name].points.append_array(points)
		if clock >= time: break
		tween.custom_step(STEP)
		clock += STEP
	tween.kill()
	prop.free()
	return result

## Every shape in `reach`, still and moving.
static func every_shape(reach: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	result.assign(reach.still)
	for part: Dictionary in reach.parts.values(): result.append_array(part.shapes)
	return result

## A shape's outline placed on the ground through `placed`.
static func ground(placed: Transform3D, shape: Dictionary) -> PackedVector2Array:
	var result := PackedVector2Array()
	for corner: Vector2 in shape.hull:
		var at := placed * Vector3(corner.x, 0, corner.y)
		result.append(Vector2(at.x, at.z))
	return result

static func _meshes(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	var found: Array[Node] = node.find_children("*", "MeshInstance3D", true, false)
	if node is MeshInstance3D: found.push_front(node)
	for each: Node in found:
		var mesh := each as MeshInstance3D
		if mesh.mesh != null and mesh.is_visible_in_tree(): result.append(mesh)
	return result

## A mesh's vertices in the keepsake's frame.
static func _points(prop: Node3D, mesh: MeshInstance3D) -> PackedVector3Array:
	return (prop.global_transform.affine_inverse() * mesh.global_transform) * _corners(mesh.mesh)

static func _shape(points: PackedVector3Array) -> Dictionary:
	var flat := PackedVector2Array()
	var low := INF
	var high := -INF
	for point: Vector3 in points:
		flat.append(Vector2(point.x, point.z))
		low = minf(low, point.y)
		high = maxf(high, point.y)
	var hull := Geometry2D.convex_hull(flat)
	if hull.size() > 1: hull.remove_at(hull.size() - 1)
	return {"hull": hull, "low": low, "high": high}

## A mesh's vertices, once each, kept per mesh.
static var _corner_cache := {}

static func _corners(mesh: Mesh) -> PackedVector3Array:
	if _corner_cache.has(mesh): return _corner_cache[mesh]
	var seen := {}
	for corner: Vector3 in mesh.get_faces(): seen[corner] = true
	var result := PackedVector3Array(seen.keys())
	_corner_cache[mesh] = result
	return result
