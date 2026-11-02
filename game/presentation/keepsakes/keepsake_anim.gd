extends RefCounted
## One tap's timeline for a keepsake (presentation/home_keepsake_layer.gd runs
## it). A builder's play() adds its beat through these calls, at times measured
## from the beat's start; the layer owns the Tween, so leaving Home ends it.
## Every node a call moves, lights or shows must be one of the parts its
## build() returned, or a part made for the tap with spawn(), which goes when
## the tap ends; the layer puts every part back to its rest pose after, except
## what a beat keep()s or spin()s, which it holds until the next press.
##
## With reduced motion on nothing slides or spins: each node and property jumps
## once to the first value a beat gives it (the lit pose: a path's `peak`) when
## the layer calls apply_jumps(), and the layer holds that for a moment before
## putting everything back.
const Parts = preload("res://presentation/keepsakes/keepsake_parts.gd")
const SparkleStar = preload("res://presentation/kit/sparkle_star.gd")

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
## (cue: String, variant: int) -> void.
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
## The joy a ride can add (slide_down): (pip: Node3D) -> void pops a heart over
## the pip, () -> void gives a light tap of the phone. Either may be empty.
var pop_heart: Callable
var haptic: Callable
## What the tap leaves as it ends, by node (keep()), and what keeps turning
## after it (spin()): the layer holds both until the keepsake is pressed again.
var kept: Dictionary = {}
var spins: Array[Dictionary] = []
var _landing_at := -INF
var _first: Dictionary = {}
var _jumps: Array = []

## Leaves `node` (a moving part or a part made for the tap) as the tap ends it
## instead of putting it back: the keepsake's builder says what pressing it
## again does (keepsake_builder.gd press_again()).
func keep(node: Node) -> void:
	kept[node] = true

## Keeps `node` turning about its up axis at `rate` radians a second once the
## tap ends, for as long as the keepsake holds its end state (never under
## Reduce motion, and only while Home is drawn). `beams` evenly spaced arms
## turn on it; each of `answers`, [part, bearing, lit look, dark look], is lit
## while an arm points within ANSWER_WIDTH of its bearing.
func spin(node: Node3D, rate: float, beams: int = 1, answers: Array = []) -> void:
	keep(node)
	for answer: Array in answers:
		keep(answer[0])
		looks.append_array([answer[2], answer[3]])
	spins.append({"node": node, "rate": rate, "beams": maxi(1, beams), "answers": answers})

## How near an arm points to an answer's bearing to light it (radians).
const ANSWER_WIDTH := 0.22

## Turns every spin on by `step` seconds and lights its answers. Writes
## nothing else; a light changes only as an arm comes or goes.
static func advance_spins(list: Array[Dictionary], step: float) -> void:
	for turning: Dictionary in list:
		var node: Node3D = turning.node
		if not is_instance_valid(node): continue
		var angle := fposmod(node.rotation.y + float(turning.rate) * step, TAU)
		node.rotation.y = angle
		var gap := TAU / int(turning.beams)
		for answer: Array in turning.answers:
			var part: MeshInstance3D = answer[0]
			if not is_instance_valid(part): continue
			var off := fposmod(angle - float(answer[1]), gap)
			var look: Material = answer[2] if minf(off, gap - off) <= ANSWER_WIDTH else answer[3]
			if part.material_override != look: part.material_override = look

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

## Calls the pip's own ride hook `method` (presentation/spirit_visual.gd:
## play_hop, play_carry_release) at `at`. Nothing without a rider that has it,
## and nothing under Reduce motion, where the pip simply lands.
func rider_call(method: StringName, args: Array, at: float) -> void:
	if reduced or tween == null or rider == null or not rider.has_method(method): return
	var node := rider
	tween.tween_callback(func() -> void:
		if is_instance_valid(node): node.callv(method, args)).set_delay(start + at)

## When the last carry lands the pip, in seconds from the tap.
func landing_time() -> float:
	return maxf(_landing_at, 0.0)

# --- the pip's ride moves: data in, motion out ------------------------------------------
# Any keepsake that carries the pip (or, from a tap, a stand-in `mover` raised
# by `lift`) describes only its points; these turn them into hops and slides,
# with the pip's own ride hooks timed to them (spirit_visual.gd play_hop,
# set_ride_pose, play_carry_release). Everything is the tap's Tween: nothing
# runs at rest, and the layer puts the pip down out of its ride pose however
# the tap ends.

## The share of a hop's time at which the feet touch down. The path is there
## by then and holds; the pip's landing squash and footstep fall on it.
const HOP_CONTACT := 0.8
## How far back the pip leans while sitting on a slide (radians).
const SIT_LEAN := -0.3

## One hop from `from` to `to`, `height` above the line at its middle,
## touching down at HOP_CONTACT of its time.
static func hop_leg(from: Vector3, to: Vector3, height: float) -> Callable:
	var flight := arc(from, to, height)
	return func(t: float) -> Vector3: return flight.call(minf(t / HOP_CONTACT, 1.0))

## Down `points` by distance (their own straight pieces), gathering speed.
static func slide_leg(points: Array[Vector3]) -> Callable:
	var lengths: Array[float] = [0.0]
	for index in range(1, points.size()): lengths.append(lengths[index - 1] + points[index - 1].distance_to(points[index]))
	var total: float = lengths[lengths.size() - 1]
	return func(t: float) -> Vector3:
		var eased := clampf(t, 0.0, 1.0)
		var at := (0.35 * eased + 0.65 * eased * eased) * total
		var index := 1
		while index < lengths.size() - 1 and lengths[index] < at: index += 1
		var span := maxf(0.0001, lengths[index] - lengths[index - 1])
		return points[index - 1].lerp(points[index], (at - lengths[index - 1]) / span)

## Hops through `points`, one hop each of `time` seconds and `height` high,
## starting `at`, the pip crouching, stretching and landing with a footstep on
## each (a `mover` given rides instead, and the pip is left alone). Returns
## when the last hop ends.
func hop_steps(points: Array, at: float, time: float, height: float, mover: Node3D = null, lift: Vector3 = Vector3.ZERO) -> float:
	var t := at
	for index in range(points.size() - 1):
		_follow(hop_leg(points[index], points[index + 1], height), t, time, mover, lift)
		if mover == null: rider_call(&"play_hop", [time, HOP_CONTACT], t)
		t += time
	return t

## From `from`, sits onto the top of `points` over `sit_time`, slides down them
## over `time` leaning into the curve by `lean` radians at its middle, and hops
## off their end onto `landing` over `lip_time`, settling with a bounce.
## `joy`, all optional: "face" (an expression the pip wears from the sit until
## it lets go), "sparkles" (how many sparkles trail it down, popping just behind
## it, twinkling up and shrinking away), "heart_at" (the share of the slide
## where a heart pops over it) and "haptic" (a light tap of the phone as it
## lands). Reduce motion keeps the face and the tap, and drops
## the glints and the heart.
## Returns when it lands.
func slide_down(from: Vector3, points: Array[Vector3], landing: Vector3, at: float, sit_time: float, time: float, lip_time: float, lean: float, mover: Node3D = null, lift: Vector3 = Vector3.ZERO, joy: Dictionary = {}) -> float:
	var top := points[0]
	_follow(func(u: float) -> Vector3: return from.lerp(top, u), at, sit_time, mover, lift)
	_follow(slide_leg(points), at + sit_time, time, mover, lift)
	var off := at + sit_time + time
	_follow(hop_leg(points[points.size() - 1], landing, 0.12), off, lip_time, mover, lift)
	# The pip's own hooks only when the pip is what rides (a `mover` rides in its place).
	if mover != null: return off + lip_time
	_slide_joy(points, at, sit_time, time, off + lip_time * HOP_CONTACT, lift, joy)
	rider_call(&"play_hop", [lip_time, HOP_CONTACT], off)
	rider_call(&"play_carry_release", [], off + lip_time * HOP_CONTACT)
	if not reduced and tween != null and rider != null and rider.has_method(&"set_ride_pose"):
		var node := rider
		var sit := func(u: float) -> void:
			if is_instance_valid(node): node.set_ride_pose(u, Vector3(SIT_LEAN * u, 0, 0))
		var ride := func(u: float) -> void:
			if is_instance_valid(node): node.set_ride_pose(1.0, Vector3(SIT_LEAN, 0, lean * sin(u * PI)))
		var rise := func(u: float) -> void:
			if is_instance_valid(node): node.set_ride_pose(1.0 - u, Vector3(SIT_LEAN * (1.0 - u), 0, 0))
		tween.tween_method(sit, 0.0, 1.0, maxf(sit_time, 0.01)).set_delay(start + at)
		tween.tween_method(ride, 0.0, 1.0, maxf(time, 0.01)).set_delay(start + at + sit_time)
		tween.tween_method(rise, 0.0, 1.0, maxf(lip_time * HOP_CONTACT, 0.01)).set_delay(start + off)
	return off + lip_time

## A trail sparkle's size (half width, metres: a third of a pip's head across)
## and life, from popping in to gone.
const SPARKLE_SIZE := 0.1
const SPARKLE_LIFE := 0.65
## How long before the sit a ride's face goes on (spirit_face.gd swaps a face
## with a quick blink).
const FACE_LEAD := 0.2
## How far out to the side a sparkle pops: past a pip's head (0.345 half wide).
const SPARKLE_SIDE := 0.42
## How far behind the pip along the slide a sparkle pops (a share of it).
const SPARKLE_LAG := 0.06

## The slide's joy (slide_down's `joy`), for a pip that rides it: the face
## from the sit, the sparkles, the heart and the tap.
func _slide_joy(points: Array[Vector3], seat: float, sit_time: float, time: float, landed: float, lift: Vector3, joy: Dictionary) -> void:
	if rider == null or joy.is_empty(): return
	var at := seat + sit_time
	ride_face(joy.get("face", &""), seat)
	# Reduce motion shows the beat all at once: the face, and the tap (its own
	# Settings switch) once, with no glints or heart.
	if reduced:
		if joy.get("haptic", false) and haptic.is_valid(): haptic.call()
		return
	if tween == null: return
	var slide := slide_leg(points)
	var trail: int = joy.get("sparkles", 0)
	for index in range(trail):
		var share := (index + 0.5) / trail
		var when := at + time * share
		# Popped just behind the pip, out past its head on either side (so the
		# head never hides one at its biggest), then twinkling up and away.
		var side := SPARKLE_SIDE if index % 2 == 0 else -SPARKLE_SIDE
		var from: Vector3 = (slide.call(maxf(0.0, share - SPARKLE_LAG)) as Vector3) + lift + Vector3(side, 0.35 + 0.08 * (index % 3), 0)
		var spark := spawn_sparkle(fx, from)
		var size := SPARKLE_SIZE * (1.0 if index % 3 != 1 else 0.8)
		set_at(spark, "visible", true, when)
		move(spark, "scale", Vector3.ONE * size, when, 0.12, Tween.TRANS_BACK, Tween.EASE_OUT)
		move(spark, "scale", Vector3.ONE * size * 0.65, when + 0.12, 0.12)
		move(spark, "scale", Vector3.ONE * size * 0.9, when + 0.24, 0.12)
		move(spark, "scale", Vector3.ZERO, when + 0.36, SPARKLE_LIFE - 0.36, Tween.TRANS_QUAD, Tween.EASE_IN)
		move(spark, "position", from + Vector3(0, 0.22, 0), when, SPARKLE_LIFE, Tween.TRANS_SINE, Tween.EASE_OUT)
		set_at(spark, "visible", false, when + SPARKLE_LIFE)
	var node := rider
	if joy.has("heart_at") and pop_heart.is_valid():
		var heart := pop_heart
		tween.tween_callback(func() -> void:
			if is_instance_valid(node): heart.call(node)).set_delay(start + at + time * float(joy.heart_at))
	if joy.get("haptic", false) and haptic.is_valid(): tween.tween_callback(haptic).set_delay(start + landed)

## Puts `face` (spirit_look.gd) on a carried pip from `at`, a beat's time: the
## face swaps in just before, so the swap is done by then, and the layer takes
## it off as the ride lands (kept through the bounce) or is cut short.
## Reduce motion puts it on at once. Nothing without a rider.
func ride_face(face: StringName, at: float) -> void:
	if rider == null or face == &"": return
	if reduced:
		if rider.has_method(&"set_ride_face"): rider.set_ride_face(face)
	else: rider_call(&"set_ride_face", [face], maxf(0.0, at - FACE_LEAD))

func _follow(leg: Callable, at: float, time: float, mover: Node3D, lift: Vector3) -> void:
	if mover != null: path(mover, func(u: float) -> Vector3: return leg.call(u) + lift, at, time, 1.0)
	else: carry(leg, at, time)

## Hops the pip through `points` (the keepsake's own frame), each hop `time`
## seconds and `height` high, starting `at`. Returns when the last hop lands.
func hops(points: Array, at: float, time: float, height: float) -> float:
	return hop_steps(points, at, time, height)

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

## One of the game's sparkles (kit/sparkle_star.gd glint: gold on a darker rim
## with a white core) made for this tap at `at`, hidden and at no size until a
## beat shows it.
func spawn_sparkle(parent: Node3D, at: Vector3) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = SparkleStar.glint()
	part.position = at
	part.scale = Vector3.ZERO
	part.visible = false
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(part)
	looks.append_array(SparkleStar.glint_looks())
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

## Plays a cue at `at`; `variant` picks a run's next pitch (drops across
## stones). Reduced motion plays the tap's first cue only.
func sound(name: String, at: float = 0.0, variant: int = 0) -> void:
	if name.is_empty() or not cue.is_valid(): return
	if reduced:
		if not _first.has("sound"): cue.call(name, variant)
		_first["sound"] = true
		return
	if tween != null: tween.tween_callback(func() -> void: cue.call(name, variant)).set_delay(start + at)

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
