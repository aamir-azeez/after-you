extends RefCounted
## One tap's timeline for a keepsake (presentation/home_keepsake_layer.gd runs
## it). A builder's play() adds its beat through these calls, at times measured
## from the beat's start; the layer owns the Tween, so leaving Home ends it.
## Every node a call moves, lights or shows must be one of the parts its
## build() returned, or a part made for the tap with spawn(), which goes when
## the tap ends; the layer puts every part back to its rest pose after.
##
## With reduced motion on nothing slides or spins: each node and property jumps
## once to the first value a beat gives it (the lit pose: a path's `peak`) when
## the layer calls apply_jumps(), and the layer holds that for a moment before
## putting everything back.

## The Tween every call adds to (parallel), or null while only collecting.
var tween: Tween
## Where the current beat starts, in seconds from the tap.
var start := 0.0
var reduced := false
## The nodes this tap changed, and the parts it made (freed when it ends).
var touched: Dictionary = {}
var spawned: Array[Node] = []
## Every look a part is given, for the warm-up's coverage.
var looks: Array[Material] = []
## Where parts made for the tap go: a node in the keepsake's own frame (its
## footing's floor, not its raised body). The layer makes and frees it.
var fx: Node3D
## Parts a builder made in one beat and reuses in a later one, by name.
var made: Dictionary = {}
## (cue: String) -> void.
var cue: Callable
var _first: Dictionary = {}
var _jumps: Array = []

## Tweens `node`'s `property` (a subpath such as "rotation:y" is fine) to `to`
## over `time` seconds, starting `at`.
func move(node: Node, property: String, to: Variant, at: float, time: float, trans: Tween.TransitionType = Tween.TRANS_SINE, ease: Tween.EaseType = Tween.EASE_IN_OUT) -> void:
	touched[node] = true
	if reduced:
		_jump(node, property, to)
		return
	if tween != null: tween.tween_property(node, property, to, maxf(time, 0.01)).set_delay(start + at).set_trans(trans).set_ease(ease)

## Moves `node` to `where.call(t)` for t from 0 to 1, starting `at` for `time`
## seconds. Reduced motion puts it at `where.call(peak)` instead.
func path(node: Node3D, where: Callable, at: float, time: float, peak: float = 1.0) -> void:
	touched[node] = true
	if reduced:
		_jump(node, "position", where.call(peak))
		return
	if tween == null: return
	var step := func(t: float) -> void:
		if is_instance_valid(node): node.position = where.call(t)
	tween.tween_method(step, 0.0, 1.0, maxf(time, 0.01)).set_delay(start + at)

## An arc from `from` to `to`, `height` above the line at its middle.
static func arc(from: Vector3, to: Vector3, height: float) -> Callable:
	return func(t: float) -> Vector3: return from.lerp(to, t) + Vector3(0, sin(t * PI) * height, 0)

## Sets `node`'s `property` to `value` at `at` (a lamp's look, a part shown).
func set_at(node: Node, property: String, value: Variant, at: float) -> void:
	touched[node] = true
	if value is Material: looks.append(value)
	if reduced:
		_jump(node, property, value)
		return
	if tween == null: return
	var apply := func() -> void:
		if is_instance_valid(node): node.set_indexed(property, value)
	tween.tween_callback(apply).set_delay(start + at)

## A part made for this tap under `parent`, hidden until shown with set_at.
func spawn(parent: Node3D, mesh: Mesh, look: Material, at: Vector3, rot: Vector3 = Vector3.ZERO, size: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = look
	part.position = at
	part.rotation = rot
	part.scale = size
	part.visible = false
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(part)
	looks.append(look)
	spawned.append(part)
	touched[part] = true
	return part

## An empty node made for this tap, to turn spawned parts about a point.
func spawn_pivot(parent: Node3D, at: Vector3) -> Node3D:
	var part := Node3D.new()
	part.position = at
	part.visible = false
	parent.add_child(part)
	spawned.append(part)
	touched[part] = true
	return part

## Plays a cue at `at`. Reduced motion plays the tap's first cue only.
func sound(name: String, at: float = 0.0) -> void:
	if name.is_empty() or not cue.is_valid(): return
	if reduced:
		if not _first.has("sound"): cue.call(name)
		_first["sound"] = true
		return
	if tween != null: tween.tween_callback(func() -> void: cue.call(name)).set_delay(start + at)

## Reduced motion: puts every part in its lit pose (after the layer has kept
## the rest pose).
func apply_jumps() -> void:
	for jump: Array in _jumps:
		if is_instance_valid(jump[0]): (jump[0] as Node).set_indexed(jump[1], jump[2])

func _jump(node: Node, property: String, value: Variant) -> void:
	var key := [node.get_instance_id(), property]
	if _first.has(key): return
	_first[key] = true
	_jumps.append([node, property, value])
