extends RefCounted
## World kit: a drowning on any water world (presentation/water_world.gd
## hosts one; every water level uses it, never a copy). The snapshot's
## "drowned": {slot, route} (the journey rules: a crossing shut under a pip,
## or a sinking stone pushed under) sends that spirit under the water of the
## body its crossing stands in, with the knocked-out face; a ring spreads and
## bubbles rise where it went down, and the camera eases over to it (snapping
## under Reduce motion), so a drowning off screen is seen before the card. A
## fall (the same "drowned" with "fell": a spirit walked off a stepping stone
## its water left standing tall) shows the same way through the same path: the
## spirit wobbles at the stone's edge, drops in front of it to bob half in the
## water below with a small splash and a bump, dizzy. A snapshot without
## either (a retry, a replay seeking back) puts it all away again. Live play,
## the memory and a replay show the same, because it reads only the snapshot.
## Presentation only.
const SpiritLook = preload("res://presentation/spirit_look.gd")
const Parts = preload("res://presentation/kit/pieces/parts.gd")
## How far under the water a drowned spirit sinks (metres).
const DEPTH := 0.55
## Bubbles rising where a spirit went under: [x offset, z offset, start phase
## (0..1 of the rise), radius] in metres. Fixed, so live play and any replay
## of the same drowning show the same bubbles; Reduce motion holds them still.
const BUBBLES := [[0.10, 0.04, 0.0, 0.045], [-0.09, -0.03, 0.35, 0.035], [0.02, -0.08, 0.7, 0.03], [-0.13, 0.06, 0.15, 0.025]]
const BUBBLE_RISE := 0.55
const BUBBLE_SPEED := 0.45
## How fast the ring spreads (scale a second) and how far.
const RING_GROW := 1.6
const RING_MOST := 3.0
## A fall: how long the spirit wobbles at the edge first (s), how far it rolls
## and how fast; then where it lands, this far in front of where it stood
## (toward the camera) and this far under the water's face (m).
const WOBBLE := 0.4
const WOBBLE_TILT := 0.32
const WOBBLE_RATE := 26.0
const FALL_OUT := 0.34
const FALL_SINK := 0.14

var _world: Node3D
## Built once on the first drowning of a stage and reused.
var ring: MeshInstance3D
var bubbles: Array[MeshInstance3D] = []
## The slot drowned now ("" none), the water surface it went under, and how
## long the bubbles have risen.
var slot := ""
var _surface := 0.0
var _age := 0.0
## A fall: whether the spirit shown fell rather than drowned, where it stood
## (over its snapshot place by the stone's lift), where it lands, and whether
## it has.
var _fell := false
var _top := Vector3.ZERO
var _landing := Vector3.ZERO
var _landed := false

func _init(world: Node3D) -> void:
	_world = world

## A new stage: the face goes back (actors outlive a stage) and the ring and
## bubbles, built under the old terrain, are forgotten.
func forget() -> void:
	if not slot.is_empty(): clear()
	ring = null
	bubbles.clear()

## Each snapshot: its "drowned" ({} for none).
func show(drowned: Dictionary) -> void:
	var actors: Dictionary = _world.actors
	if drowned.is_empty() or not actors.has(str(drowned.get("slot", ""))):
		if not slot.is_empty(): clear()
		return
	var drowning := str(drowned.slot)
	_world.camera_focus = drowning
	var surface := _surface_of(str(drowned.get("route", "")), drowning)
	if drowned.has("fell"):
		_show_fall(drowning, surface)
		return
	var target: Vector3 = _world.actor_targets[drowning]
	target.y = minf(target.y, surface) - DEPTH
	_world.actor_targets[drowning] = target
	if slot == drowning: return
	slot = drowning
	_surface = surface
	_age = 0.0
	# A held face, so a replay seek keeps it; a doze would outrank it, so none.
	var spirit: Node3D = actors[drowning]
	if spirit.pose() == &"doze": spirit.set_pose(&"rest", {}, true)
	spirit.set_expression(SpiritLook.KNOCKED_OUT, _world.reduced_motion)
	_build()
	_splash(target)
	for index in range(bubbles.size()):
		var spec: Array = BUBBLES[index]
		bubbles[index].position = Vector3(target.x + float(spec[0]), 0.0, target.z + float(spec[1]))
		bubbles[index].visible = true
	_rise()

## A fall: on top of its stone while it wobbles, then landed in the water in
## front of it (at once under Reduce motion, which never wobbles).
func _show_fall(falling: String, surface: float) -> void:
	var at: Vector3 = _world.actor_targets[falling]
	if slot != falling:
		slot = falling
		_fell = true
		_landed = false
		_surface = surface
		_age = 0.0
		_top = at + Vector3(0.0, _world.stone_lift(falling), 0.0)
		_landing = Vector3(at.x, surface - FALL_SINK, at.z + FALL_OUT)
		var spirit: Node3D = _world.actors[falling]
		if spirit.pose() == &"doze": spirit.set_pose(&"rest", {}, true)
		spirit.set_expression(SpiritLook.DIZZY, _world.reduced_motion)
		_build()
		ring.visible = false
		for bubble: MeshInstance3D in bubbles: bubble.visible = false
	if _world.reduced_motion and not _landed: _land()
	_world.actor_targets[falling] = _landing if _landed else _top

func _land() -> void:
	_landed = true
	var spirit: Node3D = _world.actors[slot]
	spirit.rotation.z = 0.0
	spirit.play_bump(_world.reduced_motion)
	_world.actor_targets[slot] = _landing
	_splash(_landing)

## The ring and bubbles, built once on the first drowning or fall of a stage.
func _build() -> void:
	if is_instance_valid(ring): return
	ring = _world.cylinder(0.32, 0.01, Color(Parts.CREAM, 0.7), Vector3.ZERO, _world.terrain)
	ring.name = "DrownRing"
	for spec: Array in BUBBLES:
		var bubble: MeshInstance3D = _world.sphere(float(spec[3]), Color(Parts.CREAM, 0.85), Vector3.ZERO, _world.terrain)
		bubble.name = "DrownBubble"
		bubbles.append(bubble)

## The ring starts to spread on the water's face over `at`.
func _splash(at: Vector3) -> void:
	ring.position = Vector3(at.x, _surface + 0.02, at.z)
	ring.scale = Vector3.ONE
	ring.visible = true

## Each frame the world animates (never under Reduce motion): the ring
## spreads and the bubbles climb; a falling spirit wobbles, then lands.
func advance(delta: float) -> void:
	if slot.is_empty() or not is_instance_valid(ring): return
	_age += maxf(delta, 0.0)
	if _fell and not _landed:
		var spirit: Node3D = _world.actors[slot]
		if _age < WOBBLE: spirit.rotation.z = sin(_age * WOBBLE_RATE) * WOBBLE_TILT * (1.0 - _age / WOBBLE)
		else: _land()
		return
	var grown := minf(ring.scale.x + delta * RING_GROW, RING_MOST)
	ring.scale = Vector3(grown, 1.0, grown)
	if not _fell: _rise()

func clear() -> void:
	var actors: Dictionary = _world.actors
	if actors.has(slot):
		actors[slot].set_expression(SpiritLook.NORMAL, true)
		(actors[slot] as Node3D).rotation.z = 0.0
	if _world.camera_focus == slot: _world.camera_focus = ""
	slot = ""
	_fell = false
	_landed = false
	if is_instance_valid(ring): ring.visible = false
	for bubble: MeshInstance3D in bubbles: bubble.visible = false

## The ring and bubbles move and hide, so the static fold keeps them whole.
func moving_nodes() -> Array:
	var nodes: Array = []
	if is_instance_valid(ring): nodes.append(ring)
	nodes.append_array(bubbles)
	return nodes

## Each bubble climbs BUBBLE_RISE above the water and starts again, from its
## own phase; still at that phase under Reduce motion.
func _rise() -> void:
	for index in range(bubbles.size()):
		var phase := fmod(float(BUBBLES[index][2]) + _age * BUBBLE_SPEED / BUBBLE_RISE, 1.0)
		bubbles[index].position.y = _surface + 0.03 + phase * BUBBLE_RISE

## The shown level of the water over the crossing it drowned on (the body its
## rectangle stands in, else the first body), else the spirit's own height.
func _surface_of(route_id: String, drowning: String) -> float:
	var waters: RefCounted = _world.waters
	var rect: Array = [0, 0, 0, 0]
	for route: Dictionary in _world.chapter_definition.get("bridges", []) + _world.chapter_definition.get("stairs", []):
		if str(route.id) == route_id: rect = route.rect_cm
	var body: Node3D = waters.bodies.get(waters.body_of(rect))
	if not is_instance_valid(body): body = waters.bodies.get(waters.first_body())
	return float(body.get_meta("shown")) if is_instance_valid(body) and body.has_meta("shown") else float(_world.actor_targets[drowning].y)
