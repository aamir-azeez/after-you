extends RefCounted
## World kit: a drowning on any water world (presentation/water_world.gd
## hosts one; every water level uses it, never a copy), and on a journey world
## without water of its own a pip a swing knocked off (journey_world.gd hosts
## one for a stage with swings), sinking under the lane's floor. The snapshot's
## "drowned": {slot, route} (the journey rules: a crossing shut under a pip,
## or a sinking stone pushed under) sends that spirit under the water of the
## body its crossing stands in, with the knocked-out face; a ring spreads and
## bubbles rise where it went down, and the camera eases over to it (snapping
## under Reduce motion), so a drowning off screen is seen before the card. A
## snapshot without a drowning (a retry, a replay seeking back) puts it all
## away again. Live play, the memory and a replay show the same, because it
## reads only the snapshot. Presentation only.
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

var _world: Node3D
## Built once on the first drowning of a stage and reused.
var ring: MeshInstance3D
var bubbles: Array[MeshInstance3D] = []
## The slot drowned now ("" none), the water surface it went under, and how
## long the bubbles have risen.
var slot := ""
var _surface := 0.0
var _age := 0.0

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
	if not is_instance_valid(ring):
		ring = _world.cylinder(0.32, 0.01, Color(Parts.CREAM, 0.7), Vector3.ZERO, _world.terrain)
		ring.name = "DrownRing"
		for spec: Array in BUBBLES:
			var bubble: MeshInstance3D = _world.sphere(float(spec[3]), Color(Parts.CREAM, 0.85), Vector3.ZERO, _world.terrain)
			bubble.name = "DrownBubble"
			bubbles.append(bubble)
	ring.position = Vector3(target.x, surface + 0.02, target.z)
	ring.scale = Vector3.ONE
	ring.visible = true
	for index in range(bubbles.size()):
		var spec: Array = BUBBLES[index]
		bubbles[index].position = Vector3(target.x + float(spec[0]), 0.0, target.z + float(spec[1]))
		bubbles[index].visible = true
	_rise()

## Each frame the world animates (never under Reduce motion): the ring
## spreads and the bubbles climb.
func advance(delta: float) -> void:
	if slot.is_empty() or not is_instance_valid(ring): return
	var grown := minf(ring.scale.x + delta * RING_GROW, RING_MOST)
	ring.scale = Vector3(grown, 1.0, grown)
	_age += maxf(delta, 0.0)
	_rise()

func clear() -> void:
	var actors: Dictionary = _world.actors
	if actors.has(slot): actors[slot].set_expression(SpiritLook.NORMAL, true)
	if _world.camera_focus == slot: _world.camera_focus = ""
	slot = ""
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
## A world without water: the floor or crossing it went off.
func _surface_of(route_id: String, drowning: String) -> float:
	var waters: Variant = _world.get("waters")
	if waters == null:
		for surface: Dictionary in _world.chapter_definition.get("islands", []) + _world.chapter_definition.get("bridges", []):
			if str(surface.id) == route_id: return float(surface.get("height_cm", 0)) / 100.0
		return float(_world.actor_targets[drowning].y)
	var rect: Array = [0, 0, 0, 0]
	for route: Dictionary in _world.chapter_definition.get("bridges", []) + _world.chapter_definition.get("stairs", []):
		if str(route.id) == route_id: rect = route.rect_cm
	var body: Node3D = waters.bodies.get(waters.body_of(rect))
	if not is_instance_valid(body): body = waters.bodies.get(waters.first_body())
	return float(body.get_meta("shown")) if is_instance_valid(body) and body.has_meta("shown") else float(_world.actor_targets[drowning].y)
