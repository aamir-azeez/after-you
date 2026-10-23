extends Node3D
## World kit: where the live spirit's turn ends. A chapter turns it on with its
## descriptor's "goal_beacon" (content/chapters/index.gd); cooperative_world
## builds it for each stage and feeds it the snapshot and the camera.
##
## Each end spot gets a beacon: a ring on the floor, a mast with a lamp and a
## pennant in the spirit's colour. On a pad drawn as a stand spot
## (kit/stand_spot.gd) the ring breathes inside the spot, never past where the
## pad counts. A spot whose floor is open now (its
## crossing's gate holds, or it stands on an island) has its lamp lit warm and
## its ring breathing; one still shut stands grey and still with its lamp out,
## so the beacon also says which spot is ready. Within NEAR_CM of a beacon the
## live spirit sees only its ring, so the mast never tangles with the spirit.
## While every spot is off screen, a pin at the screen's edge points the way
## to the nearest. The world can glance the camera at the nearest spot when a
## turn starts (glance_point).
##
## Presentation only: it reads the hashed stage and the snapshot, and nothing
## here feeds back into the simulation, a recording or a checkpoint.
##
## Cost: the pieces move in their shader from TIME alone (goal_beacon.gdshader),
## so a beacon at rest does no CPU work. present() touches materials only when
## the shown role, the open or near spots or the turn's readiness change, and follow()
## places the pointer only when the camera, the viewport or the shown spots
## changed since the last call. Hidden, it does nothing.
const SHADER := preload("res://presentation/kit/goal_beacon.gdshader")
const Primitives = preload("res://presentation/kit/primitives.gd")
const CREAM := Color("f6f1dc")
const MAST := Color("e9e1c6")
## A shut spot's pieces, mixed this far toward DIM: greyed, never dark, so a
## shut beacon still reads as a beacon and not as a hole.
const DIM := Color("8f9894")
const DIM_MIX := 0.6
const MAST_HEIGHT := 1.45
## An open spot's lamp, warm like the harbour's lanterns, and a shut one's.
const LAMP_LIT := Color("ffc96b")
const LAMP_OUT := Color("6a645a")
## Within this many cm of a spot, the live spirit's beacon shows only its ring.
const NEAR_CM := 100
## The floor ring's radius (its tube's centre line), and how far it breathes
## outward (goal_beacon.gdshader, part 1: the mesh grows to 1 + BREATH).
const RING_RADIUS := 0.30
const BREATH := 0.12
## Inside a stand spot the ring keeps this clear of the spot's edge at its
## widest, inside the spot's rim (StandSpot.RIM_WIDTH).
const INSIDE_CLEAR := 0.05
## A beacon's pieces, in build order.
enum {RING, MAST_PIECE, LAMP, PENNANT}
## The pointer keeps inside this share of the screen: clear of the title (top
## left), the stick (bottom left), the goal card, Pause and Finish (right).
const SAFE := Rect2(0.06, 0.22, 0.74, 0.46)
const POINTER_RADIUS := 30.0
## A spot counts as on screen when its lamp is this far inside the view (px).
const ON_SCREEN_MARGIN := 24.0

## The spots by role: {"a": [{"at": Vector3, "surface": String, "slot": String}], "b": [...]};
## a spot on a stand spot also has "inside", the spot's radius in metres, and
## "ring": false when a seat fills the spot and leaves its ring no room.
var _spots: Dictionary = {}
## {slot: Color}, the spirits' colours.
var _colors: Dictionary = {}
## Per role, per spot: {"root", "nodes", "materials", "tints"}, each by piece.
var _beacons: Dictionary = {}
var _live := false
var _shown_role := ""
var _shown_key := ""
var _pointer: Pointer
var _pointer_layer: CanvasLayer
var _camera_key: Array = []
## How many times follow() worked the pointer out (the tests read it).
var placements := 0
## The last snapshot shown, read again when play starts or stops.
var _last_state: Dictionary = {}
var _reduced := false

## Where a stage's turn ends for `role` ("a" the first turn, "b" the second),
## as the stage's own hashed entities: the bell or goal for the second turn;
## for the first, every branch's pad (choice_pad),
## the held pad or ball pad (hold_switch, weight_switch), the endpoint
## (route_endpoint, signal_route; a route that ends on a condition has none)
## or the hand-off mark (offer_ball).
static func spots_of(stage: Dictionary, role: String) -> Array:
	if role == "b": return [stage.goal] if stage.get("goal") is Dictionary else []
	var policy: Dictionary = stage.get("source_policy", {})
	var ids: Array = []
	match str(policy.get("kind", "")):
		"choice_pad": ids = policy.get("branches", []).map(func(branch: Dictionary) -> String: return str(branch.pad_id))
		"hold_switch", "weight_switch": ids = [str(policy.get("pad_id", policy.get("ball_pad_id", "")))]
		"route_endpoint", "signal_route": return [policy.endpoint] if policy.get("endpoint") is Dictionary else []
		"offer_ball": return [stage.handoff] if stage.get("handoff") is Dictionary else []
	var found: Array = []
	for pad: Dictionary in stage.get("pressure_pads", []) + stage.get("ball_pads", []):
		if str(pad.id) in ids: found.append(pad)
	return found

## Builds both roles' beacons, hidden. The beacon stands at its parent's
## origin. `spots`: {role: [{"at": the floor point in the parent's space,
## "surface": the floor's id, "slot": the spirit's slot, and on a stand spot
## "inside": its radius in metres, and "ring": false for no floor ring}]};
## `colors`: {slot: Color}.
func build(spots: Dictionary, colors: Dictionary) -> void:
	name = "GoalBeacon"
	_spots = spots
	_colors = colors
	for role: String in spots:
		var list: Array = []
		for spot: Dictionary in spots[role]:
			list.append(_beacon(spot, colors.get(spot.slot, CREAM)))
		_beacons[role] = list
	_pointer_layer = CanvasLayer.new()
	_pointer_layer.name = "GoalPointer"
	# Under the screen's controls and cards (layer 1 and up).
	_pointer_layer.layer = 0
	add_child(_pointer_layer)
	_pointer = Pointer.new()
	_pointer.visible = false
	_pointer_layer.add_child(_pointer)
	visible = false

func _beacon(spot: Dictionary, color: Color) -> Dictionary:
	var root := Node3D.new()
	root.name = "Beacon"
	root.position = spot.at
	root.visible = false
	add_child(root)
	var nodes: Array[MeshInstance3D] = []
	var materials: Array[ShaderMaterial] = []
	var tints: Array[Color] = []
	# RING, MAST_PIECE, LAMP, PENNANT: [shader part, mesh, position, tint].
	for piece: Array in [[1, ring_mesh(float(spot.get("inside", 0.0))), Vector3(0, ring_lift(float(spot.get("inside", 0.0))), 0), color],
			[0, Primitives.cylinder_mesh(0.022, MAST_HEIGHT), Vector3(0, MAST_HEIGHT * 0.5, 0), MAST],
			[3, Primitives.sphere_mesh(0.085), Vector3(0, MAST_HEIGHT + 0.06, 0), LAMP_LIT],
			[2, Primitives.box_mesh(Vector3(0.34, 0.20, 0.012)), Vector3(0.19, MAST_HEIGHT - 0.16, 0), color]]:
		var node := MeshInstance3D.new()
		node.mesh = Primitives.cached_shape(piece[1])
		node.position = piece[2]
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var look := ShaderMaterial.new()
		look.shader = SHADER
		look.set_shader_parameter("part", piece[0])
		node.material_override = look
		root.add_child(node)
		nodes.append(node)
		materials.append(look)
		tints.append(piece[3])
	if not bool(spot.get("ring", true)): nodes[RING].visible = false
	return {"root": root, "nodes": nodes, "materials": materials, "tints": tints, "ring": bool(spot.get("ring", true))}

## The floor ring: RING_RADIUS, or on a stand spot of radius `inside` one
## whose outer edge stays INSIDE_CLEAR inside it at its widest breath.
static func ring_mesh(inside: float) -> TorusMesh:
	if inside <= 0.0: return Primitives.ring_mesh(RING_RADIUS)
	var shape := TorusMesh.new()
	shape.outer_radius = (inside - INSIDE_CLEAR) / (1.0 + BREATH)
	shape.inner_radius = shape.outer_radius - 0.03
	shape.rings = 24
	shape.ring_segments = 8
	return shape

## The floor ring's height: over a stand spot's disc and mark, under its rim's top.
static func ring_lift(inside: float) -> float:
	return 0.035 if inside <= 0.0 else 0.045

## Shows the beacons only while the screen plays a live turn.
func set_live(on: bool) -> void:
	if on == _live: return
	_live = on
	if not _last_state.is_empty(): present(_last_state)

## Reduce motion holds every piece still.
func set_reduced_motion(on: bool) -> void:
	_reduced = on
	for role: String in _beacons:
		for beacon: Dictionary in _beacons[role]:
			for look: ShaderMaterial in beacon.materials: look.set_shader_parameter("motion", 0.0 if on else 1.0)
	_shown_key = ""
	if not _last_state.is_empty(): present(_last_state)

## The snapshot's role and open floors light the right beacons. A turn that is
## ready (or done) hides them.
func present(state: Dictionary) -> void:
	_last_state = state
	var role := str(state.get("role", ""))
	var done := bool(state.get("can_commit", false)) or bool(state.get("complete", false))
	var shown: bool = _live and not done and _beacons.has(role) and not _beacons[role].is_empty()
	var open: Array[bool] = []
	var near: Array[bool] = []
	if shown:
		var player: Dictionary = state.get("players", {}).get(str(state.get("active_slot", "")), {})
		for spot: Dictionary in _spots[role]:
			open.append(bool(state.get("bridges", {}).get(spot.surface, true)))
			var at: Vector3 = spot.at
			near.append(not player.is_empty() and Vector2(float(player.x) - at.x * 100.0, float(player.z) - at.z * 100.0).length() < NEAR_CM)
	var key := "%s|%s|%s|%s" % [shown, role, open, near]
	if key == _shown_key: return
	_shown_key = key
	if shown and role != _shown_role:
		_pointer.tint = _colors.get(_spots[role][0].slot, CREAM)
		_pointer.queue_redraw()
	_shown_role = role if shown else ""
	visible = shown
	_camera_key = []
	for each: String in _beacons:
		for index in range(_beacons[each].size()):
			var beacon: Dictionary = _beacons[each][index]
			beacon.root.visible = shown and each == role
			if not beacon.root.visible: continue
			for piece in range(beacon.materials.size()):
				var tint: Color = beacon.tints[piece]
				if not open[index]: tint = LAMP_OUT if piece == LAMP else tint.lerp(DIM, DIM_MIX)
				var look: ShaderMaterial = beacon.materials[piece]
				look.set_shader_parameter("tint", tint)
				look.set_shader_parameter("motion", 1.0 if open[index] and not _reduced else 0.0)
				(beacon.nodes[piece] as Node3D).visible = bool(beacon.ring) if piece == RING else not near[index]
	if not shown: _pointer.visible = false

## Places the pointer for `camera`; returns at once when nothing it reads has
## changed since the last call.
func follow(camera: Camera3D) -> void:
	if _shown_role.is_empty() or not is_instance_valid(camera): return
	var view := camera.get_viewport().get_visible_rect()
	var key := [camera.global_transform, camera.size, view]
	if key == _camera_key: return
	_camera_key = key
	placements += 1
	var safe := Rect2(view.position + view.size * SAFE.position, view.size * SAFE.size)
	var centre := safe.get_center()
	var nearest := Vector2.INF
	for point: Vector3 in _lamps():
		var at := camera.unproject_position(point)
		if view.grow(-ON_SCREEN_MARGIN).has_point(at):
			_pointer.visible = false
			return
		if at.distance_squared_to(centre) < nearest.distance_squared_to(centre): nearest = at
	if nearest == Vector2.INF:
		_pointer.visible = false
		return
	var direction := (nearest - centre).normalized()
	_pointer.position = _edge(safe, centre, direction) - _pointer.size * 0.5
	_pointer.pivot_offset = _pointer.size * 0.5
	_pointer.rotation = direction.angle()
	_pointer.visible = true

## Whether any shown spot is on screen for `camera`.
func on_screen(camera: Camera3D) -> bool:
	var view := camera.get_viewport().get_visible_rect().grow(-ON_SCREEN_MARGIN)
	for point: Vector3 in _lamps():
		if view.has_point(camera.unproject_position(point)): return true
	return false

## The shown spot nearest `from` (a global point), or `from` when none is shown.
func glance_point(from: Vector3) -> Vector3:
	var best := from
	var best_distance := INF
	for beacon: Dictionary in _beacons.get(_shown_role, []):
		var at: Vector3 = beacon.root.global_position
		var distance := Vector2(at.x - from.x, at.z - from.z).length()
		if distance < best_distance:
			best_distance = distance
			best = at
	return best

func shown() -> bool:
	return not _shown_role.is_empty()

func _lamps() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for beacon: Dictionary in _beacons.get(_shown_role, []):
		points.append((beacon.root as Node3D).global_position + Vector3(0, MAST_HEIGHT, 0))
	return points

## Where the ray from `centre` along `direction` leaves `rect`.
static func _edge(rect: Rect2, centre: Vector2, direction: Vector2) -> Vector2:
	var reach := INF
	if absf(direction.x) > 0.0001: reach = minf(reach, (rect.size.x * 0.5) / absf(direction.x))
	if absf(direction.y) > 0.0001: reach = minf(reach, (rect.size.y * 0.5) / absf(direction.y))
	return centre + direction * reach

## The edge pointer: a pin in the spirit's colour with a lit lamp at its
## heart and its tip toward the goal, drawn once per role; following the
## camera only moves and turns it.
class Pointer extends Control:
	var tint := CREAM

	func _init() -> void:
		name = "Pointer"
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size = Vector2.ONE * POINTER_RADIUS * 3.4
		custom_minimum_size = size

	func _draw() -> void:
		var middle := size * 0.5
		var r := POINTER_RADIUS
		var tip := PackedVector2Array([middle + Vector2(r * 1.6, 0), middle + Vector2.from_angle(0.75) * r, middle + Vector2.from_angle(-0.75) * r])
		draw_circle(middle + Vector2(0, 2), r, Color(0, 0, 0, 0.22))
		draw_colored_polygon(tip, tint)
		draw_circle(middle, r, tint)
		draw_arc(middle, r - 1.5, 0.0, TAU, 40, CREAM, 3.0, true)
		draw_circle(middle, r * 0.46, Color("1d3b3a"))
		draw_circle(middle, r * 0.34, LAMP_LIT)
