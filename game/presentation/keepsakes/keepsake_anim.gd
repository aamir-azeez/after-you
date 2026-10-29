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
const Parts = preload("res://presentation/keepsakes/keepsake_parts.gd")

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
## The pip, when it set the keepsake off in Explore (null for a tap): carry()
## moves it. rider_frame turns the keepsake's own frame into the pip's parent
## space; rider_from is where the pip stood, in the keepsake's frame.
var rider: Node3D
var rider_frame := Transform3D.IDENTITY
var rider_from := Vector3.ZERO
## Where the last carry leaves the pip, on the ground in its parent space
## (null when nothing carries it). The layer puts the pip there when the tap
## ends, however it ends.
var landing: Variant = null
var _landing_at := -INF
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

## Carries the pip along `where.call(t)` (the keepsake's own frame) for t from
## 0 to 1, starting `at` for `time` seconds. No rider, no carry. Reduced motion
## moves nothing now: the layer lands the pip where the last carry ends.
func carry(where: Callable, at: float, time: float) -> void:
	if rider == null: return
	var end: Vector3 = rider_frame * (where.call(1.0) as Vector3)
	if start + at + time >= _landing_at:
		_landing_at = start + at + time
		landing = Vector3(end.x, 0.0, end.z)
	if reduced or tween == null: return
	var node := rider
	var frame := rider_frame
	var step := func(t: float) -> void:
		if is_instance_valid(node): node.position = frame * (where.call(t) as Vector3)
	tween.tween_method(step, 0.0, 1.0, maxf(time, 0.01)).set_delay(start + at)

## Hops through `points` (the keepsake's own frame), each hop `time` seconds
## and `height` high, starting `at`. Returns when the last hop lands.
func hops(points: Array, at: float, time: float, height: float) -> float:
	var t := at
	for index in range(points.size() - 1):
		carry(arc(points[index], points[index + 1], height), t, time)
		t += time
	return t

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

## A soft glow round `at` (a lamp lit, a ring of light), shown from `from` for
## `time` seconds.
func halo(parent: Node3D, at: Vector3, radius: float, color: Color, from: float, time: float, alpha: float = 0.3) -> MeshInstance3D:
	var glow := spawn(parent, Parts.low_sphere(radius), Parts.clear(color, alpha, 1.4), at)
	set_at(glow, "visible", true, from)
	set_at(glow, "visible", false, from + time)
	return glow

## `count` sparkles in a ring round `at`, popping out from `from` for `time`.
func burst(parent: Node3D, at: Vector3, count: int, radius: float, from: float, time: float) -> void:
	for index in range(count):
		var angle := index * TAU / count
		var out := Vector3(cos(angle) * radius, sin(angle * 2.0) * radius * 0.4, sin(angle) * radius * 0.5)
		var spark := spawn(parent, Parts.low_sphere(0.035), Parts.glow(Parts.SNOW, 2.0), at)
		set_at(spark, "visible", true, from)
		move(spark, "position", at + out, from, time * 0.6, Tween.TRANS_QUAD, Tween.EASE_OUT)
		set_at(spark, "visible", false, from + time)

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
