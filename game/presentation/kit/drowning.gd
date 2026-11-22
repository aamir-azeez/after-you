extends RefCounted
## World kit: a drowning or a fall on any chapter world (presentation/
## cooperative_world.gd hosts one for every world; never a copy). The snapshot's
## "drowned": {slot, route} (the journey rules: a crossing shut under a pip,
## or a sinking stone pushed under) sends that spirit under the water of the
## body its crossing stands in, with the knocked-out face; a ring spreads and
## bubbles rise where it went down, and the camera eases over to it (snapping
## under Reduce motion), so a drowning off screen is seen before the card. A
## fall (the same "drowned" with "fell": a spirit walked off a stepping stone
## its water left standing tall) shows the same way through the same path: the
## spirit wobbles at the stone's edge, drops in front of it to bob half in the
## water below with a small splash and a bump, dizzy. A snapshot without
## either (a retry, a replay seeking back) puts it all away again. A fall into
## the sky (the drowned record with "sky": a pip whose floor went from under it
## away from any water, core/physical/runtime.gd _keep_footing) is a fall away:
## the pip startles and wobbles where it stood, then tumbles down under the
## island with a little spin, shrinking and fading out of view, and a soft
## puff of the kit's cream blooms where it went. Reduce motion skips the
## wobble and the tumble: the pip fades out where it stood, the puff still.
## A pip knocked off (show()'s `shoved`, a point past its floor's edge, such
## as a swinging bucket's shove, kit/pieces/swing.gd) is first shoved over
## the edge, toppling that way (SHOVE), and falls away, drowns or lands from
## there, so it never drops through the floor it stood on.
## A dropped item (the drowned record with "dropped": a pip carrying something
## stepped onto a crossing needing both hands) keeps the pip where it stands,
## startled, with the camera on it; the item itself is let go and lands at
## the crossing's foot through the world's own set-down
## (journey_world _present_items, from the snapshot's items).
## Live play,
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
## A fall away into the sky (s, m, radians): the startled wobble and its hop,
## then the tumble: how long, how far it drops (easing in, as a fall does),
## how far it drifts toward the camera, how far it rolls end over end and
## turns round, and the share of the tumble, at its end, it fades over.
## Reduce motion fades it in place over AWAY_FADE.
const AWAY_WOBBLE := 0.45
const AWAY_HOP := 0.07
const AWAY_TUMBLE := 1.15
const AWAY_DROP := 3.2
const AWAY_OUT := 0.45
const AWAY_ROLL := 3.4
const AWAY_TURN := 1.6
const AWAY_FADE_SHARE := 0.35
const AWAY_FADE := 0.3
## A shove off the edge (s, m, radians): how long it takes (an ease out), the
## hop over the edge and how far the pip tips over toward where it goes.
const SHOVE := 0.3
const SHOVE_HOP := 0.12
const SHOVE_TIP := 0.9
## The puff where it went: [x offset, y offset, z offset, radius] in metres,
## fixed so every replay blooms alike; it grows this much over its life (s).
const PUFF := [[0.0, 0.0, 0.0, 0.11], [0.12, 0.04, 0.03, 0.08], [-0.11, 0.05, -0.02, 0.085], [0.04, 0.11, -0.06, 0.07], [-0.05, -0.06, 0.07, 0.075]]
const PUFF_GROW := 1.8
const PUFF_LIFE := 0.6

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
## A fall away into the sky: whether the spirit shown falls away, the puff's
## balls (built once a stage), and each faded part's own see-through amount
## before it, to give back.
var _away := false
## Where a knocked pip is shoved to before it falls (its place when not shoved).
var _shoved := Vector3.ZERO
## A dropped item: whether the spirit shown is startled by its drop.
var _dropped := false
var puff: Array[MeshInstance3D] = []
var _faded: Dictionary = {}

func _init(world: Node3D) -> void:
	_world = world

## A new stage: the face goes back (actors outlive a stage) and the ring and
## bubbles, built under the old terrain, are forgotten.
func forget() -> void:
	if not slot.is_empty(): clear()
	ring = null
	bubbles.clear()
	puff.clear()

## Each snapshot: its "drowned" ({} for none), and where the pip is shoved to
## first when it was knocked off (terrain space, null for none).
func show(drowned: Dictionary, shoved: Variant = null) -> void:
	var actors: Dictionary = _world.actors
	if drowned.is_empty() or not actors.has(str(drowned.get("slot", ""))):
		if not slot.is_empty(): clear()
		return
	var drowning := str(drowned.slot)
	_world.camera_focus = drowning
	if drowned.has("dropped"):
		_show_dropped(drowning)
		return
	# A world with no water to go into shows any loss as a fall away.
	if drowned.has("sky") or not "waters" in _world:
		_show_fall_away(drowning, shoved)
		return
	var surface := _surface_of(str(drowned.get("route", "")), drowning)
	if drowned.has("fell"):
		_show_fall(drowning, surface)
		return
	var target: Vector3 = _world.actor_targets[drowning]
	if shoved is Vector3: target = Vector3(shoved.x, target.y, shoved.z)
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

## A dropped item: the pip stays put, startled (a held face, so a replay
## seek keeps it).
func _show_dropped(dropping: String) -> void:
	if slot == dropping and _dropped: return
	if not slot.is_empty(): clear()
	slot = dropping
	_dropped = true
	var spirit: Node3D = _world.actors[dropping]
	if spirit.pose() == &"doze": spirit.set_pose(&"rest", {}, true)
	spirit.set_expression(SpiritLook.SURPRISED, _world.reduced_motion)

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

## A fall away: it starts where its snapshot has it, startled (shoved over
## the edge to `shoved` first when knocked off); advance plays the rest (a
## fade in place under Reduce motion).
func _show_fall_away(falling: String, shoved: Variant = null) -> void:
	if slot == falling and _away:
		_place_away()
		return
	if not slot.is_empty(): clear()
	slot = falling
	_away = true
	_age = 0.0
	_top = _world.actor_targets[falling]
	_shoved = Vector3(shoved.x, _top.y, shoved.z) if shoved is Vector3 else _top
	var spirit: Node3D = _world.actors[falling]
	if spirit.pose() == &"doze": spirit.set_pose(&"rest", {}, true)
	spirit.set_expression(SpiritLook.SURPRISED, _world.reduced_motion)
	_faded.clear()
	for part: Node in spirit.find_children("*", "GeometryInstance3D", true, false):
		_faded[part] = (part as GeometryInstance3D).transparency
	if puff.is_empty() or not is_instance_valid(puff[0]):
		puff.clear()
		for spec: Array in PUFF:
			var ball: MeshInstance3D = _world.sphere(float(spec[3]), Color(Parts.CREAM, 0.8), Vector3.ZERO, _world.terrain)
			ball.name = "FallPuff"
			ball.visible = false
			puff.append(ball)
	_place_away()

## The falling spirit and its puff at `_age` into the fall: the wobble (or
## the shove over the edge), then the tumble (or the fade in place under
## Reduce motion). The spirit is drawn where its target is, so the world's
## easing adds nothing.
func _place_away() -> void:
	var spirit: Node3D = _world.actors[slot]
	var at := _top
	var fade := 0.0
	var size := 1.0
	var reduced: bool = _world.reduced_motion
	var push := _shoved - _top
	var shoved := push.length() > 0.01
	if reduced:
		fade = clampf(_age / AWAY_FADE, 0.0, 1.0)
		spirit.rotation = Vector3.ZERO
	elif shoved and _age < SHOVE:
		# Shoved over the edge, toppling that way as it goes.
		var share := _age / SHOVE
		var eased := 1.0 - (1.0 - share) * (1.0 - share)
		at = _top + push * eased + Vector3(0.0, SHOVE_HOP * sin(PI * share), 0.0)
		spirit.rotation = _tip(push, SHOVE_TIP * eased)
	elif shoved:
		at = _shoved
		var share := clampf((_age - SHOVE) / AWAY_TUMBLE, 0.0, 1.0)
		at += push.normalized() * AWAY_OUT * share + Vector3(0.0, -AWAY_DROP * share * share, 0.0)
		spirit.rotation = _tip(push, SHOVE_TIP + AWAY_ROLL * share * share) + Vector3(0.0, AWAY_TURN * share, 0.0)
		size = 1.0 - 0.85 * share * share
		fade = clampf((share - (1.0 - AWAY_FADE_SHARE)) / AWAY_FADE_SHARE, 0.0, 1.0)
	elif _age < AWAY_WOBBLE:
		var share := _age / AWAY_WOBBLE
		at.y += AWAY_HOP * sin(PI * share)
		spirit.rotation = Vector3(0.0, 0.0, sin(_age * WOBBLE_RATE) * WOBBLE_TILT * (1.0 - share))
	else:
		var share := clampf((_age - AWAY_WOBBLE) / AWAY_TUMBLE, 0.0, 1.0)
		at += Vector3(0.0, -AWAY_DROP * share * share, AWAY_OUT * share)
		spirit.rotation = Vector3(AWAY_ROLL * share * share, AWAY_TURN * share, 0.0)
		size = 1.0 - 0.85 * share * share
		fade = clampf((share - (1.0 - AWAY_FADE_SHARE)) / AWAY_FADE_SHARE, 0.0, 1.0)
	spirit.scale = Vector3.ONE * maxf(size, 0.01)
	spirit.position = at
	_world.actor_targets[slot] = at
	for part: Variant in _faded:
		if is_instance_valid(part): (part as GeometryInstance3D).transparency = maxf(float(_faded[part]), fade)
	# The puff blooms as the pip fades out, where it is then.
	var since := _age - (AWAY_FADE if reduced else (SHOVE if shoved else AWAY_WOBBLE) + AWAY_TUMBLE * (1.0 - AWAY_FADE_SHARE * 0.5))
	for index in range(puff.size()):
		var ball := puff[index]
		var spec: Array = PUFF[index]
		ball.visible = since >= 0.0 and (reduced or since < PUFF_LIFE)
		if not ball.visible: continue
		var bloom := 1.0 if reduced else clampf(since / PUFF_LIFE, 0.0, 1.0)
		ball.position = at + Vector3(float(spec[0]), float(spec[1]) + 0.15, float(spec[2])) * (1.0 + bloom)
		ball.scale = Vector3.ONE * (1.0 + PUFF_GROW * bloom)
		ball.transparency = 0.4 if reduced else bloom

## A spirit tipped over by `angle` (radians) toward `push` (its rotation).
static func _tip(push: Vector3, angle: float) -> Vector3:
	var way := Vector2(push.x, push.z).normalized()
	return Vector3(way.y * angle, 0.0, -way.x * angle)

## Whether spirit `role` is falling away now: the kit draws it, nothing carries it.
func falling_away(role: String) -> bool:
	return _away and slot == role

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

## Each frame: the ring spreads and the bubbles climb; a falling spirit
## wobbles, then lands; a spirit falling away wobbles, tumbles and is gone in a
## puff. Under Reduce motion only a fall away moves on (its fade).
func advance(delta: float) -> void:
	if slot.is_empty() or _dropped: return
	if _away:
		_age += maxf(delta, 0.0)
		_place_away()
		return
	if _world.reduced_motion or not is_instance_valid(ring): return
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
		if _away:
			(actors[slot] as Node3D).rotation = Vector3.ZERO
			(actors[slot] as Node3D).scale = Vector3.ONE
	for part: Variant in _faded:
		if is_instance_valid(part): (part as GeometryInstance3D).transparency = float(_faded[part])
	_faded.clear()
	for ball: MeshInstance3D in puff:
		if is_instance_valid(ball): ball.visible = false
	if _world.camera_focus == slot: _world.camera_focus = ""
	slot = ""
	_away = false
	_dropped = false
	_fell = false
	_landed = false
	if is_instance_valid(ring): ring.visible = false
	for bubble: MeshInstance3D in bubbles: bubble.visible = false

## The ring and bubbles move and hide, so the static fold keeps them whole.
func moving_nodes() -> Array:
	var nodes: Array = []
	if is_instance_valid(ring): nodes.append(ring)
	nodes.append_array(bubbles)
	nodes.append_array(puff)
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
