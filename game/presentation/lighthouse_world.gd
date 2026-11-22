extends "res://presentation/island_world.gd"
## The Lighthouse's view only. Every beam endpoint and gate state comes from
## the simulation; no collider, interaction or chapter progression lives here.

const BEAM_HEIGHT := 1.12
const LIGHT_COLOR := Parts.LIGHT
const SLEEP_COLOR := Color("536979")
const StageCatalog = preload("res://core/lighthouse/stage_catalog.gd")
## The kit bell, for an earlier stage's rung bell left resting (present_history).
const Bell = preload("res://presentation/kit/pieces/bell.gd")
## Two lights, two receivers or two mirrors this close (cm) overlap: their
## widest tops reach 22 cm from their centres at the same heights, so they
## would z-fight. A later one of the kind stands in for a remembered one.
const FIXTURE_CLEARANCE_CM := 45.0
var _tower_lamp: MeshInstance3D
var _deck: Node3D
var _mirror_pivot: Node3D
var _source_lens: MeshInstance3D
var _receiver_lens: MeshInstance3D
var _pad_ring: MeshInstance3D
## The stage's goal (kit/pieces/goal.gd) and the handles a world moves.
var _goal_piece: GoalPiece
var _bell: MeshInstance3D
var _bell_ring: MeshInstance3D
var _court_light: OmniLight3D
var _beam_roots: Array[Node3D] = []
var _cable: Array[MeshInstance3D] = []
var _badges: Dictionary = {}
var _mirror_target := -PI / 4.0
var _wake := false
var _view_center := Vector3(-3.8, 0.1, 0)
var _view_size := 7.5
## From the third stage the archipelago is too wide to fit with readable
## spirits: the follow camera (island_world's) takes the active spirit until
## the stage is solved, when it shows the whole archipelago again.
const FOLLOW_FROM_STAGE := 2
## The follow camera's centre stays this far (metres, x then z) inside the
## floors.
const FOLLOW_MARGIN := Vector2(3.0, 0.6)
var _stage_follow := false
var _decks: Dictionary = {}
var _mirror_nodes: Dictionary = {}
var _source_nodes: Dictionary = {}
var _receiver_nodes: Dictionary = {}
var _receiver_cables: Dictionary = {}
var _prop_nodes: Dictionary = {}
var _socket_nodes: Dictionary = {}
var _history_root: Node3D
var _memory_markers: Dictionary = {}
var _selector_nodes: Dictionary = {}
var _frame_points: Array[Vector3] = []
var _hold_pad_nodes: Dictionary = {}
var _beacon: Dictionary = {}
## Every hand control of the stage (levers, switches, selectors, mirrors), by
## the id its value goes by in the state, and the value it last showed, so the
## pip that works one turns to face it (_face_hands).
var _hand_controls: Dictionary = {}
var _hand_values: Dictionary = {}

func _beam_height() -> float:
	return BEAM_HEIGHT

func _control_base_height(_entity: Dictionary) -> float:
	return 0.0

func _ready() -> void:
	super._ready()
	relight("night")
	_frame_camera()

func load_level(definition: Dictionary) -> void:
	reset_camera_exploration()
	_reset_seed_pose()
	_clear_object_trails()
	current_level = definition.duplicate(true)
	displayed_stage_id = str(definition.get("stage_id", ""))
	_load_dressing()
	_tower_lamp = null
	if is_instance_valid(terrain):
		remove_child(terrain)
		terrain.queue_free()
	terrain = Node3D.new()
	terrain.name = "BorrowedLightShore"
	add_child(terrain)
	actors.clear()
	_hand_controls.clear()
	_hand_values.clear()
	actor_targets.clear()
	bridge_parts.clear()
	flowers.clear()
	_beam_roots.clear()
	_cable.clear()
	_badges.clear()
	_decks.clear()
	_mirror_nodes.clear()
	_source_nodes.clear()
	_receiver_nodes.clear()
	_receiver_cables.clear()
	_prop_nodes.clear()
	_socket_nodes.clear()
	_history_root = null
	_latched_bridge_ids.clear()
	_memory_markers.clear()
	_selector_nodes.clear()
	_frame_points.clear()
	_hold_pad_nodes.clear()
	_beacon.clear()
	plate = null
	_pad_ring = null
	_goal_piece = null
	goal_pieces.clear()
	_bell = null
	_bell_ring = null
	_court_light = null
	seed = null
	garden = null
	landing_marker = null
	lift = null
	home_view = false
	bloomed = false
	_wake = false
	for island: Dictionary in definition.islands:
		_shore(island, Color("526f79") if island.id == "harbour" else Color("59687d"))
		await _build_step()
	for bridge_definition: Dictionary in definition.bridges:
		_build_bridge(bridge_definition)
		await _build_step()
	for emitter: Dictionary in definition.optics.emitters:
		_build_source(definition.get("plate", {}), emitter)
	await _build_step()
	var controls: Array = definition.get("controls", [definition.mirror_control] if definition.has("mirror_control") else [])
	for control: Dictionary in controls:
		if control.get("kind", "mirror") == "mirror":
			_build_mirror(control)
		elif control.get("kind", "") == "selector":
			_build_selector(control)
		await _build_step()
	for receiver: Dictionary in definition.optics.receivers:
		_build_receiver(receiver)
	for pad: Dictionary in definition.get("hold_pads", []):
		_build_hold_pad(pad)
	if definition.get("goal_policy", {}).get("kind", "") == "activate_receivers":
		_build_beacon(definition.goal, definition.optics.receivers)
	elif definition.has("goal"):
		_build_bell(definition.goal)
		_goal_piece.add_needs(definition, func(id: String) -> String: return _piece_style("carried_item", id))
	for socket: Dictionary in definition.get("sockets", []):
		_build_socket(socket)
	for prop: Dictionary in definition.get("props", []):
		_build_prop(prop)
	await _build_step()
	# A fixed surface cable, distinct from an optical ray, shows why this
	# receiver controls this bridge. It never extends across the closed gap.
	for receiver: Dictionary in definition.optics.receivers:
		_build_receiver_cable(receiver, definition.bridges)
	for slot: String in ["p0", "p1"]:
		var spirit := _create_spirit(GOLD if slot == "p0" else TEAL, slot)
		# Later-stage positions are supplied by the verified checkpoint in
		# present(), rather than invented starting coordinates in the view.
		spirit.position = point(definition.starts[slot]) if definition.has("starts") else Vector3.ZERO
		spirit.visible = definition.has("starts")
		terrain.add_child(spirit)
		actors[slot] = spirit
		actor_targets[slot] = spirit.position
		_badges[slot] = Badges.make(spirit)
		await _build_step()
	if definition.stage_id == "borrowed-light":
		_view_center = Vector3(-3.8, 0.1, 0)
		_view_size = 7.5
	else:
		var bounds: Array = definition.islands[0].rect_cm.duplicate()
		for island: Dictionary in definition.islands:
			bounds[0] = mini(bounds[0], island.rect_cm[0])
			bounds[1] = mini(bounds[1], island.rect_cm[1])
			bounds[2] = maxi(bounds[2], island.rect_cm[2])
			bounds[3] = maxi(bounds[3], island.rect_cm[3])
		_view_center = point([(bounds[0] + bounds[2]) / 2.0, (bounds[1] + bounds[3]) / 2.0])
		_view_size = maxf(7.5, float(bounds[3] - bounds[1]) / 100.0 * 0.85 + 3.0)
	_stage_follow = _follows_stage(str(definition.get("stage_id", "")))
	for island: Dictionary in definition.islands:
		var bounds: Array = island.rect_cm
		for x in [bounds[0], bounds[2]]:
			for z in [bounds[1], bounds[3]]:
				for height in [-1.65, 1.65]:
					_frame_points.append(Vector3(float(x) / 100.0, height, float(z) / 100.0))
	await _build_step()
	await _build_dressing()
	await _build_step()
	show_keepsake_landmark(str(definition.get("stage_id", "")))
	_frame_camera()

## The registry-style key this world's dressing is filed under.
func _chapter_key() -> String:
	return "sleeping-lighthouse@1"

## The lighthouse lamp sleeps until the beacon is lit.
func _dressed_prop(prop: Node3D) -> void:
	var lamp := prop.find_child("TowerLamp", true, false) as MeshInstance3D
	if lamp == null: return
	_tower_lamp = lamp
	Primitives.own_material(lamp)
	_glow(lamp, LIGHT_COLOR, 0.0)

## Supply the checkpoint already verified by the chapter coordinator. Archived
## mechanisms are landmarks only: they add no controls, beams or collision.
func present_history(checkpoint: Dictionary) -> void:
	_latched_bridge_ids.clear()
	if is_instance_valid(_history_root):
		terrain.remove_child(_history_root)
		_history_root.queue_free()
	_history_root = Node3D.new()
	_history_root.name = "RememberedMechanisms"
	terrain.add_child(_history_root)
	if checkpoint.get("level_id", "") != current_level.get("id", ""):
		return
	var stage_index := StageCatalog.STAGE_IDS.find(str(current_level.get("stage_id", "")))
	if stage_index <= 0 or int(checkpoint.get("stage_index", -1)) != stage_index:
		return
	var mechanisms: Dictionary = checkpoint.get("mechanisms", {})
	_latched_bridge_ids = mechanisms.get("latched_bridges", []).duplicate()
	var remembered_mirrors: Dictionary = mechanisms.get("mirrors", {})
	var drawn: Dictionary = {}
	# A remembered fixture never overlaps a later one of its kind (_superseded).
	var later := _fixture_spots(stage_index)
	for index in range(stage_index):
		var earlier: Dictionary = StageCatalog.definition(StageCatalog.STAGE_IDS[index])
		for control: Dictionary in StageCatalog.controls(StageCatalog.STAGE_IDS[index]):
			var id := str(control.get("optical_id", control.id))
			if _mirror_nodes.has(id) or drawn.has(id) or _superseded(later.mirror, index, control.position_cm) or not remembered_mirrors.has(id):
				continue
			drawn[id] = true
			var pivot := _mirror_body(point(control.position_cm), 0.0, _history_root, true)
			pivot.rotation.y = PI / 4.0 if remembered_mirrors[id] == "slash" else -PI / 4.0
			pivot.set_meta("mirror_id", id)
			pivot.set_meta("orientation", remembered_mirrors[id])
		for emitter: Dictionary in earlier.optics.emitters:
			if _source_nodes.has(emitter.id) or drawn.has(emitter.id) or _superseded(later.light, index, emitter.position_cm):
				continue
			drawn[emitter.id] = true
			_source_body(point(emitter.position_cm), 0.0, _history_root, true)
		for receiver: Dictionary in earlier.optics.receivers:
			if _receiver_nodes.has(receiver.id) or drawn.has(receiver.id) or _superseded(later.receiver, index, receiver.position_cm):
				continue
			drawn[receiver.id] = true
			_receiver_body(point(receiver.position_cm), 0.0, _history_root, true)
		if earlier.has("plate"):
			var pad: Dictionary = earlier.plate
			if not drawn.has(pad.id):
				drawn[pad.id] = true
				cylinder(float(pad.radius_cm) / 100.0, 0.035, Color("7e8b83"), point(pad.position_cm) + Vector3(0, 0.018, 0), _history_root)
		if earlier.has("goal") and not current_level.has("goal"):
			var goal: Dictionary = earlier.goal
			if not drawn.has(goal.id):
				drawn[goal.id] = true
				# A rung bell rests below the new Court beam; the familiar location
				# remains marked without adding an apparent obstacle to its ray.
				var at := point(goal.position_cm)
				cylinder(0.34, 0.065, Color("697b8e"), at + Vector3(0, 0.033, 0), _history_root)
				var bell: MeshInstance3D = Bell.build(_history_root, at + Vector3(0, 0.065, 0), Vector2(0.6, 0.46), "none").body
				_glow(bell, LIGHT_COLOR, 0.25)
	_history_root.set_meta("checkpoint_hash", checkpoint.get("checkpoint_hash", ""))

## Where each stage up to this one (stage_index) puts its lights, receivers
## and mirrors: {light, receiver, mirror: [[stage index, cm]]}.
func _fixture_spots(stage_index: int) -> Dictionary:
	var spots := {"light": [], "receiver": [], "mirror": []}
	for index in range(stage_index + 1):
		var level: Dictionary = current_level if index == stage_index else StageCatalog.definition(StageCatalog.STAGE_IDS[index])
		for kind: String in spots:
			var fixtures: Array = level.optics.emitters if kind == "light" else level.optics.receivers if kind == "receiver" else StageCatalog.controls(StageCatalog.STAGE_IDS[index])
			for fixture: Dictionary in fixtures:
				spots[kind].append([index, Vector2(float(fixture.position_cm[0]), float(fixture.position_cm[1]))])
	return spots

## A remembered fixture from stage `index` at `position_cm` is left out where
## one of its kind from a later stage, this one's own included, stands within
## FIXTURE_CLEARANCE_CM: the later one stands for it. Other kinds never hide
## it, so a remembered mirror always shows its kept orientation.
static func _superseded(spots: Array, index: int, position_cm: Array) -> bool:
	var at := Vector2(float(position_cm[0]), float(position_cm[1]))
	for spot: Array in spots:
		if int(spot[0]) > index and (spot[1] as Vector2).distance_to(at) < FIXTURE_CLEARANCE_CM: return true
	return false

func _shore(island: Dictionary, color: Color) -> void:
	if _dressed_ground(island, terrain): return
	var bounds := drawn_rect(island)
	var width := float(bounds[2] - bounds[0]) / 100.0
	var depth := float(bounds[3] - bounds[1]) / 100.0
	var center := point([(bounds[0] + bounds[2]) / 2.0, (bounds[1] + bounds[3]) / 2.0])
	# The visible top is the floor's drawn shape (drawn_pieces), at height 0.
	# The tapered lower rock is decorative and remains below the floor.
	var shape := drawn_pieces(island)
	for index in range(shape.size()):
		var piece: Array = shape[index]
		var top := box(Vector3(float(piece[2] - piece[0]) / 100.0, 0.20, float(piece[3] - piece[1]) / 100.0), color, point([(piece[0] + piece[2]) / 2.0, (piece[1] + piece[3]) / 2.0]) + Vector3(0, -0.10, 0), terrain)
		if index == 0: top.name = str(island.id) + "Floor"
	ContactShadows.ground_cm(terrain, shape, center.y, false)
	var corners := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	var top: Array[Vector3] = []
	var bottom: Array[Vector3] = []
	for corner: Vector2 in corners:
		top.append(center + Vector3(corner.x * width * 0.48, -0.20, corner.y * depth * 0.48))
		bottom.append(center + Vector3(corner.x * width * 0.22, -1.45, corner.y * depth * 0.24))
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_smooth_group(-1)
	for index in range(4):
		var next := (index + 1) % 4
		var face_color := color.darkened(0.18 + 0.035 * index)
		_shell_triangle(surface, top[index], bottom[index], bottom[next], face_color)
		_shell_triangle(surface, top[index], bottom[next], top[next], face_color)
		_shell_triangle(surface, bottom[index], center + Vector3(0, -1.62, 0), bottom[next], color.darkened(0.35))
	surface.generate_normals()
	var rock_material := material(Color.WHITE)
	rock_material.vertex_color_use_as_albedo = true
	rock_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var rock := Primitives.mesh_node(surface.commit(), rock_material, Vector3.ZERO, terrain)
	rock.name = str(island.id) + "LowerRock"
	# Edge strips start at the walking surface, clear of the floor's sides,
	# along the shape's outer edges.
	for edge: Array in WalkReach.outline(shape):
		var length := (float(edge[0][1]) - float(edge[0][0])) / 100.0
		var middle := (float(edge[0][0]) + float(edge[0][1])) / 200.0
		var line := float(edge[1]) / 100.0 - float(edge[2]) * 0.0275
		box(Vector3(length, 0.0175, 0.035) if edge[3] else Vector3(0.035, 0.0175, length), color.lightened(0.12), Vector3(middle, 0.00875, line) if edge[3] else Vector3(line, 0.00875, middle), terrain)
	# Only a few small stones at the outer corners; no invented obstacles or
	# extra stepping-stones through the real gap.
	for x_side in [-1, 1]:
		var stone := sphere(0.13, Color("85949c"), center + Vector3(x_side * (width / 2.0 - 0.25), 0.045, depth / 2.0 - 0.22), terrain)
		stone.scale = Vector3(1.4, 0.5, 0.9)

func _build_bridge(definition: Dictionary) -> void:
	var rect := drawn_rect(definition)
	var width := float(rect[2] - rect[0]) / 100.0
	var depth := float(rect[3] - rect[1]) / 100.0
	_deck = Node3D.new()
	_deck.name = "ReceiverBridge"
	_deck.position = point([(rect[0] + rect[2]) / 2.0, (rect[1] + rect[3]) / 2.0])
	terrain.add_child(_deck)
	_decks[definition.id] = _deck
	mark_sound("bridge:%s" % definition.id, _deck)
	var across_x := WalkReach.run_axis(definition, WalkReach.walkable(current_level)) == 0
	# The deck spans only the open gap: where a route crosses a floor at its
	# own height, that floor is already drawn there, and two tops at one
	# height z-fight. `low`/`high` bound the gap along the crossing.
	var span := _open_span(definition, across_x)
	var low: float = span[0]
	var high: float = span[1]
	var length := high - low
	var middle := (low + high) * 0.5
	_lay_deck(definition, _deck, width, depth, across_x, low, high)
	var memories := Node3D.new()
	memories.name = "RememberedFootsteps"
	_deck.add_child(memories)
	# Clear of the span's ends, and of any floor drawn under the crossing,
	# where a floor's trim runs.
	for index in range(3):
		var along := middle + ((float(index) + 0.5) / 3.0 - 0.5) * maxf(length - 0.20, 0.0)
		for side in [-1, 1]:
			var at := Vector3(along + side * 0.05, 0.011, side * 0.11) if across_x else Vector3(side * 0.11, 0.011, along + side * 0.05)
			if _over_floor(Vector2(_deck.position.x + at.x, _deck.position.z + at.z) * 100.0, 6.0): continue
			var footprint := cylinder(0.038, 0.005, Color("a68c60"), at, memories)
			footprint.scale = Vector3(1.6, 1, 1) if across_x else Vector3(1, 1, 1.6)
	memories.visible = false
	_memory_markers[definition.id] = memories
	_deck.visible = false

## Whether a floor of the shown plan is drawn within `margin` cm of `at` (cm).
func _over_floor(at: Vector2, margin: float) -> bool:
	for island: Dictionary in current_level.get("islands", []):
		for piece: Array in drawn_pieces(island):
			if Rect2(float(piece[0]), float(piece[1]), float(piece[2] - piece[0]), float(piece[3] - piece[1])).grow(margin).has_point(at): return true
	return false

## Lays a crossing's deck under `deck` (a crossing width by depth metres
## across x and z), before its remembered-footsteps marker: planks about a
## quarter metre wide (eight over two metres) with seams and a lit edge each
## side over the open span low..high (deck-local metres along the crossing).
## A short span gets few wide planks, so no plank's end lies just past a
## floor's lip under the deck's end. A world that lays its own decks overrides it, so no planks are
## made only to be freed.
func _lay_deck(_definition: Dictionary, deck: Node3D, width: float, depth: float, across_x: bool, low: float, high: float) -> void:
	var length := high - low
	var middle := (low + high) * 0.5
	# Warm chapters lay plank decks; the plain look keeps its pale glass deck.
	var timber := str(dressing.get("bridges", "")) == "timber"
	var plank := Props.TIMBER_LIGHT if timber else Color("bdc9c1")
	var seam := Props.TIMBER_DARK if timber else Color("637886")
	var count := maxi(1, roundi(length / 0.25))
	for index in range(count):
		var offset := low + (index + 0.5) * length / float(count)
		var board := Vector3(length / float(count), 0.10, depth) if across_x else Vector3(width, 0.10, length / float(count))
		var at := Vector3(offset, -0.05, 0) if across_x else Vector3(0, -0.05, offset)
		box(board, plank.darkened(0.05 * float(index % 2)) if timber else plank, at, deck)
		var seam_size := Vector3(0.016, 0.005, depth - 0.06) if across_x else Vector3(width - 0.06, 0.005, 0.016)
		var seam_at := Vector3(offset + length / float(2 * count) - 0.012, 0.003, 0) if across_x else Vector3(0, 0.003, offset + length / float(2 * count) - 0.012)
		box(seam_size, seam, seam_at, deck)
	for side in [-1, 1]:
		var trim_size := Vector3(length, 0.025, 0.035) if across_x else Vector3(0.035, 0.025, length)
		var trim_at := Vector3(middle, 0.015, side * (depth / 2.0 - 0.025)) if across_x else Vector3(side * (width / 2.0 - 0.025), 0.015, middle)
		var trim := box(trim_size, LIGHT_COLOR, trim_at, deck)
		_glow(trim, LIGHT_COLOR, 0.65)

## The part of a route's crossing axis (deck-local metres, from its drawn
## centre) not already covered by a floor at the route's height: where a floor
## reaches over its end (open_span), and where a floor spanning its whole
## width lies over it.
func _open_span(definition: Dictionary, across_x: bool) -> Array:
	var rect := drawn_rect(definition)
	var authored: Array = definition.rect_cm
	var axis := 0 if across_x else 1
	var centre := (float(rect[axis]) + float(rect[axis + 2])) * 0.5
	var span := open_span(definition)
	var low := float(span[0])
	var high := float(span[1])
	for island: Dictionary in current_level.get("islands", []):
		if int(island.get("height_cm", 0)) != int(definition.get("height_cm", 0)): continue
		# As drawn (drawn_rect). Only a floor spanning the route's whole width
		# covers the deck there.
		var r := drawn_rect(island)
		if float(r[1 - axis]) > float(authored[1 - axis]) or float(r[3 - axis]) < float(authored[3 - axis]): continue
		if float(r[axis]) <= low and float(r[axis + 2]) > low: low = minf(float(r[axis + 2]), high)
		if float(r[axis + 2]) >= high and float(r[axis]) < high: high = maxf(float(r[axis]), low)
	if high - low < 8.0: return [(float(rect[axis]) - centre) / 100.0, (float(rect[axis + 2]) - centre) / 100.0]
	return [(low - centre) / 100.0, (high - centre) / 100.0]

func _build_source(control: Dictionary, emitter: Dictionary) -> void:
	if not control.is_empty():
		var base := point(control.position_cm) + Vector3(0, _control_base_height(control), 0)
		var radius := float(control.radius_cm) / 100.0
		plate = cylinder(radius, 0.065, Color("927e5a"), base + Vector3(0, 0.033, 0), terrain)
		plate.name = "EmitterPad"
		_pad_ring = ring(radius + 0.02, Color("bba775"), base + Vector3(0, 0.08, 0), terrain)
		box(Vector3(0.18, 0.018, 0.18), Color("ded2a7"), base + Vector3(0, 0.075, 0), terrain).rotation.y = PI / 4.0
	_source_lens = _source_body(point(emitter.position_cm), _control_base_height(emitter), terrain, false)
	_source_nodes[emitter.id] = _source_lens
	_glow(_source_lens, LIGHT_COLOR, 0.0)

func _build_mirror(control: Dictionary) -> void:
	var at := point(control.position_cm)
	var base_height := _control_base_height(control)
	cylinder(0.18, 0.07, Color("98a8ad"), at + Vector3(0, base_height + 0.035, 0), terrain)
	ring(float(control.radius_cm) / 100.0, Color("8caab9"), at + Vector3(0, base_height + 0.04, 0), terrain)
	_mirror_pivot = _mirror_body(at, base_height, terrain, false)
	_mirror_nodes[control.get("optical_id", control.id)] = _mirror_pivot
	_hand_controls[control.get("optical_id", control.id)] = control
	mark_sound("mirror:%s" % control.get("optical_id", control.id), _mirror_pivot)
	_mirror_target = -PI / 4.0
	_mirror_pivot.rotation.y = _mirror_target
	# Discrete engraved arrows show two positions instead of implying free aim.
	for side in [-1, 1]:
		var arrow := box(Vector3(0.10, 0.02, 0.06), Color("d0dce2"), at + Vector3(side * 0.29, base_height + 0.06, 0.18), terrain)
		arrow.rotation.y = side * PI / 4.0

## A receiver's lamp post's radius (its pair tag's plaque clamps round it).
const RECEIVER_POST := 0.06

func _build_receiver(receiver: Dictionary) -> void:
	_receiver_lens = _receiver_body(point(receiver.position_cm), _control_base_height(receiver), terrain, false)
	_receiver_nodes[receiver.id] = _receiver_lens
	_glow(_receiver_lens, LIGHT_COLOR, 0.0)

# The fixtures themselves, live or remembered: a light, a mirror and a receiver
# at `at` on a floor `base_height` up, under `parent`. A remembered one (an
# earlier stage's, present_history) is the same fixture faded (_faded).

## The colour a remembered fixture fades toward, and how far.
const FADED := Color("7d8a90")
const FADE := 0.55

static func _faded(color: Color, faded: bool) -> Color:
	return color.lerp(FADED, FADE) if faded else color

## A light: its post, lantern, cap and the lens it shines from (returned).
func _source_body(at: Vector3, base_height: float, parent: Node3D, faded: bool) -> MeshInstance3D:
	var axis := _beam_height()
	cylinder(0.08, axis - base_height, _faded(Color("897c67"), faded), at + Vector3(0, (axis + base_height) / 2.0, 0), parent)
	var lantern := cylinder(0.16, 0.30, _faded(Color("6c777c"), faded), at + Vector3(0, axis, 0), parent)
	lantern.name = "HarbourEmitter"
	var lens := sphere(0.13, _faded(Color("706d5e"), faded), at + Vector3(0.04, axis, 0), parent)
	cylinder(0.20, 0.05, _faded(Color("ab966d"), faded), at + Vector3(0, axis + 0.18, 0), parent)
	return lens

## A mirror: its post and the framed two-sided glass on its turning pivot (returned).
func _mirror_body(at: Vector3, base_height: float, parent: Node3D, faded: bool) -> Node3D:
	var axis := _beam_height()
	cylinder(0.055, axis - base_height, _faded(Color("819199"), faded), at + Vector3(0, (axis + base_height) / 2.0, 0), parent)
	var pivot := Node3D.new()
	pivot.name = "MirrorOrientation"
	pivot.position = at + Vector3(0, axis, 0)
	parent.add_child(pivot)
	box(Vector3(0.70, 0.54, 0.06), _faded(Color("c3ae78"), faded), Vector3.ZERO, pivot)
	for side in [-1, 1]:
		var glass := box(Vector3(0.62, 0.46, 0.012), _faded(Color("acd6e7"), faded), Vector3(0, 0, side * 0.037), pivot)
		if not faded: _glow(glass, Color("7eadc3"), 0.25)
	return pivot

## A receiver: its post, its disc and the lens that lights (returned).
func _receiver_body(at: Vector3, base_height: float, parent: Node3D, faded: bool) -> MeshInstance3D:
	var axis := _beam_height()
	cylinder(RECEIVER_POST, axis - base_height, _faded(Color("697a88"), faded), at + Vector3(0, (axis + base_height) / 2.0, 0), parent)
	var disk := cylinder(0.22, 0.07, _faded(Color("8da2ac"), faded), at + Vector3(0, axis, 0), parent)
	disk.rotation.x = PI / 2.0
	var lens := box(Vector3(0.20, 0.20, 0.035), _faded(Color("536579"), faded), at + Vector3(0, axis, 0.052), parent)
	lens.rotation.z = PI / 4.0
	lens.name = "BridgeReceiver"
	return lens

func _build_selector(control: Dictionary) -> void:
	# The mirror still follows the exact optical orientation. Three engraved
	# positions distinguish this switch from an ordinary two-way mirror.
	_build_mirror(control)
	# A selector's value is its state, by its own id.
	_hand_controls.erase(control.get("optical_id", control.id))
	_hand_controls[control.id] = control
	var at := point(control.position_cm) + Vector3(0, _control_base_height(control), 0)
	var dial := Node3D.new()
	dial.name = "PathSelector"
	dial.position = at
	terrain.add_child(dial)
	var dots: Array[MeshInstance3D] = []
	for index in range(control.states.size()):
		var x := (float(index) - float(control.states.size() - 1) / 2.0) * 0.30
		var marker := cylinder(0.10, 0.035, Color("738392"), Vector3(x, 0.055, 0.46), dial)
		dots.append(marker)
		# One and two raised bars remain readable without colour or sound.
		for bar in range(index):
			box(Vector3(0.025, 0.02, 0.105), Color("e7dfc7"), Vector3(x + (float(bar) - float(index - 1) / 2.0) * 0.055, 0.084, 0.46), dial)
	var pointer := box(Vector3(0.085, 0.03, 0.085), LIGHT_COLOR, Vector3(-0.30, 0.095, 0.64), dial)
	pointer.rotation.y = PI / 4.0
	_selector_nodes[control.id] = {"root": dial, "dots": dots, "pointer": pointer, "states": control.states.duplicate()}
	mark_sound("control:%s" % control.id, dial)

## The goal in its style (kit/pieces/goal.gd), at its exact centre and radius.
func _build_bell(goal: Dictionary) -> void:
	_goal_piece = _build_goal(str(goal.get("id", "")), point(goal.position_cm), float(goal.radius_cm) / 100.0)
	_bell = _goal_piece.bell
	_bell_ring = _goal_piece.ring
	_court_light = _goal_piece.light

## Whether an owned goal's cradle carries its owner's mark (kit/owner_mark.gd):
## its style says (kit/pieces/goal.gd MARKED).
func _marks_goal(goal: Dictionary) -> bool:
	return _piece_style("goal", str(goal.get("id", ""))) in GoalPiece.MARKED

## A light receiver's lamp post, for its pair tag's plaque (kit/pair_tags.gd):
## {top (the height its lamp head sits at), radius}.
func _pair_receiver_post(_receiver: Dictionary) -> Dictionary:
	return {"top": _beam_height(), "radius": RECEIVER_POST}

## A piece's style (content/dressing/piece_styles.gd): the dressing's pick here;
## a chapter world pins pieces from its descriptor too.
func _piece_style(slot: String, id: String) -> String:
	return PieceStyles.style(slot, id, {}, dressing)

func _build_receiver_cable(receiver: Dictionary, bridges: Array) -> void:
	var route: Array[Vector3] = []
	if current_level.stage_id == "borrowed-light":
		route = [Vector3(-5.6, 0.045, -1.6), Vector3(-4.75, 0.045, -1.6), Vector3(-4.75, 0.045, -0.47)]
	else:
		for bridge_definition: Dictionary in bridges:
			if bridge_definition.get("receiver_id", "") != receiver.id:
				continue
			var adjacent := false
			for island: Dictionary in current_level.islands:
				if island.id not in [bridge_definition.from_surface, bridge_definition.to_surface]: continue
				var floor: Array = island.rect_cm
				var receiver_at: Array = receiver.position_cm
				if receiver_at[0] >= floor[0] and receiver_at[0] <= floor[2] and receiver_at[1] >= floor[1] and receiver_at[1] <= floor[3]: adjacent = true
			# A distant selector can control another island, but its decorative
			# surface wire must not invent an unsupported rectangle over the void.
			if not adjacent: break
			var rect: Array = bridge_definition.rect_cm
			var at := point(receiver.position_cm) + Vector3(0, 0.045, 0)
			var edge := point([clampf(receiver.position_cm[0], rect[0], rect[2]), clampf(receiver.position_cm[1], rect[1], rect[3])]) + Vector3(0, 0.045, 0)
			route = [at, Vector3(edge.x, at.y, at.z), edge]
			break
	var cables: Array[MeshInstance3D] = []
	for index in range(1, route.size()):
		if route[index - 1].distance_to(route[index]) < 0.005:
			continue
		var cable := _bar_between(route[index - 1], route[index], 0.025, Color("718592"), terrain)
		cable.name = "ReceiverCable%d" % index
		cables.append(cable)
	if not route.is_empty():
		var relay := cylinder(0.12, 0.045, Color("bca778"), route[-1], terrain)
		relay.name = "BridgeSignal"
		cables.append(relay)
	_receiver_cables[receiver.id] = cables
	_cable.append_array(cables)

func _build_hold_pad(definition: Dictionary) -> void:
	var at := point(definition.position_cm)
	var radius := float(definition.radius_cm) / 100.0
	var base := cylinder(radius, 0.05, Color("70858d"), at + Vector3(0, 0.025, 0), terrain)
	base.name = "SourceHoldPad"
	var rim := ring(radius, Color("9fcbd0"), at + Vector3(0, 0.06, 0), terrain)
	# Two engraved footsteps show a standing action, distinct from a mirror.
	for side in [-1, 1]:
		var foot := cylinder(0.048, 0.008, Color("e0e7dd"), at + Vector3(side * 0.085, 0.056, 0), terrain)
		foot.scale = Vector3(0.8, 1.0, 1.7)
	_hold_pad_nodes[definition.id] = {"base": base, "rim": rim}

func _build_beacon(goal: Dictionary, receivers: Array) -> void:
	# The activation crest lies on its exact authored surface. The small open
	# lantern stays behind the receiver edge, clear of both mirror approaches.
	var at := point(goal.position_cm)
	var crest := Node3D.new()
	crest.name = "BeaconCrest"
	crest.position = at
	terrain.add_child(crest)
	cylinder(float(goal.radius_cm) / 100.0, 0.035, Color("778a94"), Vector3(0, 0.018, 0), crest)
	var rim := ring(float(goal.radius_cm) / 100.0, Color("d0c5a0"), Vector3(0, 0.05, 0), crest)
	var markers: Dictionary = {}
	var lantern_at := Vector3.ZERO
	for index in range(receivers.size()):
		var receiver: Dictionary = receivers[index]
		lantern_at += point(receiver.position_cm)
		var marker := box(Vector3(0.08, 0.02, 0.16), Color("94a7aa"), Vector3((float(index) - 0.5) * 0.18, 0.047, 0), crest)
		marker.rotation.y = PI / 4.0 if index == 0 else -PI / 4.0
		markers[receiver.id] = marker
	lantern_at = lantern_at / float(maxi(receivers.size(), 1)) + Vector3(0.42, 0, 0)
	var lantern := Node3D.new()
	lantern.name = "WelcomeLantern"
	lantern.position = lantern_at
	terrain.add_child(lantern)
	cylinder(0.26, 0.12, Color("859595"), Vector3(0, 0.06, 0), lantern)
	cylinder(0.13, 0.48, Color("9a9986"), Vector3(0, 0.35, 0), lantern)
	cylinder(0.29, 0.07, Color("c4b785"), Vector3(0, 0.63, 0), lantern)
	for side in [-1, 1]:
		box(Vector3(0.035, 0.61, 0.035), Color("b1ab8b"), Vector3(side * 0.20, 0.96, 0), lantern)
	var glass := sphere(0.19, Color("8ba7ad"), Vector3(0, 0.97, 0), lantern)
	glass.scale = Vector3(0.8, 1.35, 0.8)
	var roof := CylinderMesh.new()
	roof.top_radius = 0.03
	roof.bottom_radius = 0.34
	roof.height = 0.22
	roof.radial_segments = 8
	mesh_node(roof, Color("b2a581"), Vector3(0, 1.40, 0), lantern)
	var halo := ring(0.50, LIGHT_COLOR, Vector3(0, 0.98, 0), lantern)
	halo.visible = false
	var glow := OmniLight3D.new()
	glow.light_color = LIGHT_COLOR
	glow.light_energy = 0.0
	glow.omni_range = 5.0
	glow.position = Vector3(0, 1.10, 0)
	lantern.add_child(glow)
	_beacon = {"crest": crest, "rim": rim, "signals": markers, "lantern": lantern, "glass": glass, "halo": halo, "light": glow}

func _present_beacon(state: Dictionary) -> void:
	for id: String in _hold_pad_nodes:
		var held: bool = state.get("hold_pads", {}).get(id, false)
		var pad: Dictionary = _hold_pad_nodes[id]
		Primitives.own_material(pad.base).albedo_color = Color("d2bf8a") if held else Color("70858d")
		_glow(pad.rim, LIGHT_COLOR, 0.9 if held else 0.0)
		pad.base.set_meta("occupied", held)
	if _beacon.is_empty(): return
	var state_beacon: Dictionary = state.get("beacon", {})
	var lit: bool = state_beacon.get("lit", false)
	for id: String in _beacon.signals:
		_glow(_beacon.signals[id], LIGHT_COLOR, 0.9 if state_beacon.get("signals", {}).get(id, false) else 0.0)
	_glow(_beacon.rim, LIGHT_COLOR, 1.0 if state_beacon.get("ready", false) else 0.0)
	_glow(_beacon.glass, LIGHT_COLOR, 1.8 if lit else 0.0)
	_beacon.halo.visible = lit
	_glow(_beacon.halo, LIGHT_COLOR, 0.65 if lit else 0.0)
	_beacon.light.light_energy = Look.lamp_energy(1.6) if lit else 0.0
	_beacon.lantern.set_meta("lit", lit)
	if is_instance_valid(_tower_lamp): _glow(_tower_lamp, LIGHT_COLOR, 2.2 if lit else 0.0)

func _build_prop(definition: Dictionary) -> void:
	var at := point(definition.position_cm)
	# A step-on stand where the lens is taken; its lowest notch rests in the cup.
	var rest := Node3D.new()
	rest.name = "LensPedestal"
	rest.position = at
	terrain.add_child(rest)
	SocketKit.stand(rest, 0.23, 0.20, Color("8995a5"), Color("8995a5"), Color("8995a5"))
	var lens := Node3D.new()
	lens.name = "PortableLens"
	lens.position = at + Vector3(0, 0.44, 0)
	terrain.add_child(lens)
	var frame := ring(0.20, Color("d5b876"), Vector3.ZERO, lens)
	frame.rotation.x = PI / 2.0
	var glass := cylinder(0.18, 0.035, Color("99dfd9"), Vector3.ZERO, lens)
	glass.rotation.x = PI / 2.0
	_glow(glass, Color("99dfd9"), 0.55)
	# A matching three-notch frame distinguishes the lens and cradle without
	# relying on colour alone. It is never a second collectible on the ground.
	for index in range(3):
		var angle := float(index) * TAU / 3.0
		box(Vector3(0.05, 0.07, 0.05), LIGHT_COLOR, Vector3(sin(angle) * 0.21, cos(angle) * 0.21, 0), lens)
	_prop_nodes[definition.id] = lens

func _build_socket(definition: Dictionary) -> void:
	var at := point(definition.position_cm)
	var cradle := Node3D.new()
	cradle.name = "LensCradle"
	cradle.position = at
	terrain.add_child(cradle)
	cylinder(0.31, 0.12, Color("728994"), Vector3(0, 0.06, 0), cradle)
	var marker := ring(float(definition.radius_cm) / 100.0, Color("b5c3b9"), Vector3(0, 0.075, 0), cradle)
	for index in range(3):
		var angle := float(index) * TAU / 3.0
		# Wider and deeper than the lens's own notches, so a fitted lens never
		# shares a face with its cradle.
		box(Vector3(0.075, 0.12, 0.065), Color("d5b876"), Vector3(sin(angle) * 0.22, 0.45 + cos(angle) * 0.22, 0), cradle)
	_socket_nodes[definition.id] = marker

func _present_props(state: Dictionary, immediate: bool=false) -> void:
	var props: Dictionary = state.get("props", {})
	for actor: Node3D in actors.values():
		actor.carrying_seed=false
		actor.carried_radius=0.25
	for id: String in _prop_nodes:
		var lens: Node3D = _prop_nodes[id]
		if not props.has(id):
			lens.visible = false
			lens.set_meta("holder_slot", "")
			lens.set_meta("prop_status", "")
			continue
		var value: Dictionary = props[id]
		var previous_holder := str(lens.get_meta("holder_slot", ""))
		if not immediate and lens.get_meta("prop_status", "")=="carried" and value.status in ["offered","fitted"] and actors.has(previous_holder):
			actors[previous_holder].play_carry_release()
		if value.status=="carried" and actors.has(value.holder_slot):
			actors[value.holder_slot].carrying_seed=true
		lens.visible = value.status in ["pedestal", "carried", "offered", "fitted"]
		lens.set_meta("holder_slot", str(value.holder_slot) if value.status == "carried" else "")
		lens.set_meta("prop_status", str(value.status))
		lens.position = actors[value.holder_slot].carry_point() if value.status == "carried" and actors.has(value.holder_slot) else point([value.x, value.z]) + Vector3(0, 0.44, 0)
	for id: String in _socket_nodes:
		var fitted := false
		for value: Dictionary in props.values():
			if value.status == "fitted" and value.socket_id == id:
				fitted = true
		_glow(_socket_nodes[id], LIGHT_COLOR, 1.0 if fitted else 0.0)

func present(state: Dictionary, immediate: bool = false) -> void:
	if immediate: reset_camera_exploration()
	if not is_instance_valid(terrain) or not state.has("players"):
		return
	for slot: String in actors:
		var player: Dictionary = state.players[slot]
		actors[slot].visible = true
		actor_targets[slot] = Vector3(float(player.x) / 100.0, float(player.get("height", 0)) / 100.0, float(player.z) / 100.0)
		if immediate:
			actors[slot].position = actor_targets[slot]
			actors[slot].reset_motion()
		_badges[slot].text = _role_badge_text(state, slot)
	# Discrete orientation and beam redirect change together. Interpolating the
	# mirror would temporarily depict a reflection the simulation never made.
	for id: String in _decks:
		_decks[id].visible = bool(state.bridges.get(id, false))
		var kept_now: Array = state.get("route_progress", {}).get("kept_bridges", [])
		_memory_markers[id].visible = _decks[id].visible and (id in _latched_bridge_ids or id in kept_now)
	for id: String in _mirror_nodes:
		var orientation: String = state.get("mirrors", {}).get(id, state.mirror_orientation)
		_mirror_target = PI / 4.0 if orientation == "slash" else -PI / 4.0
		_mirror_nodes[id].rotation.y = _mirror_target
	for id: String in _selector_nodes:
		var selector: Dictionary = _selector_nodes[id]
		var index := int(state.get("selectors", {}).get(id, 0))
		selector.root.set_meta("selected_state", index)
		selector.pointer.position.x = (float(index) - float(selector.states.size() - 1) / 2.0) * 0.30
		for marker_index in range(selector.dots.size()):
			_glow(selector.dots[marker_index], LIGHT_COLOR, 0.8 if marker_index == index else 0.0)
	var powered: bool = state.emitter_powered
	if is_instance_valid(plate):
		Primitives.own_material(plate).albedo_color = Color("d4b876") if powered else Color("927e5a")
		_glow(_pad_ring, LIGHT_COLOR, 0.8 if powered else 0.0)
	for id: String in _source_nodes:
		var emitting := false
		for segment: Dictionary in state.optics.segments:
			if segment.get("emitter_id", "") == id:
				emitting = true
		_glow(_source_nodes[id], LIGHT_COLOR, 1.4 if emitting else 0.0)
	for id: String in _receiver_nodes:
		var received: bool = state.optics.signals.get(id, false)
		_glow(_receiver_nodes[id], LIGHT_COLOR, 1.2 if received else 0.0)
		for cable: MeshInstance3D in _receiver_cables.get(id, []):
			_glow(cable, LIGHT_COLOR if received else Color("718592"), 0.7 if received else 0.0)
	_present_props(state, immediate)
	_present_beacon(state)
	_wake = bool(state.objective_done)
	_present_follow(state, immediate)
	_present_celebration(immediate)
	if _goal_piece != null and is_instance_valid(_bell):
		_goal_piece.set_lit(GoalPiece.lit(state), immediate or reduced_motion)
		_goal_piece.present_pips(state.get("players", {}), immediate or reduced_motion)
		_goal_piece.needs.present(state)
	_present_beams(state.optics.segments)
	_face_hands(state, immediate)

## The pip that works a hand control turns to face it, so it stands beside
## it watching the pull (the engines have it work one from beside its solid
## footprint, core/solid_footprint.gd). Read from the snapshot alone: a
## control whose shown value changed (a lever, control, mirror or selector
## value), and the pip within its reach (the live one first; a memory works
## controls too). Presentation only.
func _face_hands(state: Dictionary, immediate: bool) -> void:
	var values: Dictionary = {}
	for key: String in ["levers", "controls", "mirrors", "selectors"]: values.merge(state.get(key, {}))
	var players: Dictionary = state.get("players", {})
	var active := str(state.get("active_slot", "p0"))
	for id: Variant in _hand_controls:
		var now: Variant = values.get(id)
		var was: Variant = _hand_values.get(id)
		_hand_values[id] = now
		if immediate or was == null or now == null or was == now: continue
		var control: Dictionary = _hand_controls[id]
		for slot: String in [active, "p1" if active == "p0" else "p0"]:
			var player: Variant = players.get(slot)
			if not actors.has(slot) or not RouteBarriers.at_control(control, player): continue
			var toward := Vector2(float(control.position_cm[0]) - float(player.x), float(control.position_cm[1]) - float(player.z))
			if not toward.is_zero_approx(): actors[slot].facing_target = atan2(toward.x, toward.y)
			break

## A solved stage makes both spirits jump, sparkle and smile, as in the other
## chapters. The physical worlds celebrate a committed stage themselves.
func _present_celebration(immediate: bool) -> void:
	for actor: SpiritVisual in actors.values(): actor.set_celebration(_wake, immediate, reduced_motion)

func _present_beams(segments: Array) -> void:
	while _beam_roots.size() < segments.size():
		var root := Node3D.new()
		root.name = "OpticalSegment%d" % _beam_roots.size()
		terrain.add_child(root)
		# Their own meshes: a beam's length is set on its mesh as it moves.
		var halo := mesh_node(Primitives.box_mesh(Vector3(0.07, 0.07, 1)), Color(1.0, 0.85, 0.57, 0.18), Vector3.ZERO, root)
		var core := mesh_node(Primitives.box_mesh(Vector3(0.022, 0.022, 1)), LIGHT_COLOR, Vector3.ZERO, root)
		_glow(halo, LIGHT_COLOR, 0.8)
		_glow(core, LIGHT_COLOR, 1.3)
		for side in [-1, 1]:
			var arrow := box(Vector3(0.026, 0.032, 0.15), LIGHT_COLOR, Vector3(side * 0.035, 0.015, 0.045), root)
			arrow.rotation.y = side * PI / 4.0
			_glow(arrow, LIGHT_COLOR, 1.0)
		_beam_roots.append(root)
	for index in range(_beam_roots.size()):
		var root: Node3D = _beam_roots[index]
		root.visible = index < segments.size()
		if not root.visible:
			continue
		var segment: Dictionary = segments[index]
		var height := _beam_height()
		# Endpoints are copied below, so an in-place simulation update cannot
		# make this comparison accidentally reuse stale geometry.
		if root.get_meta("from_cm",[]) == segment.from_cm and root.get_meta("to_cm",[]) == segment.to_cm and root.get_meta("beam_height",-INF) == height and root.get_meta("terrain_frame",Transform3D()) == terrain.global_transform:
			continue
		var from := point(segment.from_cm) + Vector3(0, height, 0)
		var to := point(segment.to_cm) + Vector3(0, height, 0)
		var length := from.distance_to(to)
		root.position = (from + to) / 2.0
		root.look_at(terrain.to_global(to), Vector3.UP)
		for child_index in [0, 1]:
			var child := root.get_child(child_index) as MeshInstance3D
			(child.mesh as BoxMesh).size.z = length
		for child_index in [2, 3]:
			root.get_child(child_index).visible = length >= 0.25
		root.set_meta("from_cm", segment.from_cm.duplicate())
		root.set_meta("to_cm", segment.to_cm.duplicate())
		root.set_meta("beam_height", height)
		root.set_meta("terrain_frame", terrain.global_transform)

func _bar_between(from: Vector3, to: Vector3, width: float, color: Color, parent: Node3D) -> MeshInstance3D:
	return Primitives.bar_between(from, to, width, Primitives.shared_material(color), parent)

func _glow(node: MeshInstance3D, color: Color, energy: float) -> void:
	Parts.glow(node, color, energy)

func _follows_stage(stage_id: String) -> bool:
	return StageCatalog.STAGE_IDS.find(stage_id) >= FOLLOW_FROM_STAGE

## The camera follows the active spirit now (not the whole-archipelago frame).
func _uses_scrolling_camera() -> bool:
	return _stage_follow and not _wake and actors.has(_active_player)

## Inside the floors by FOLLOW_MARGIN, across x and z.
func _follow_limits() -> Array[Vector2]:
	var floors := _floors_rect()
	var low := floors.position + FOLLOW_MARGIN
	return [low, (floors.end - FOLLOW_MARGIN).max(low)]

func _frame_camera() -> void:
	if not is_instance_valid(camera):
		return
	if _uses_scrolling_camera():
		_frame_follow()
		return
	# A higher, less oblique view keeps the short mirror-to-receiver segment
	# visible behind the mirror face without moving either optical endpoint.
	camera.position = _view_center + ViewFit.CAMERA_FROM
	camera.look_at(to_global(_view_center))
	camera.size = _view_size
	camera.h_offset = 0.0
	camera.v_offset = 0.0
	if _frame_points.is_empty(): return
	# Fit the whole authored world (including its height) inside the space
	# between title and touch controls. Depth alone cannot fit a wide chapter.
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for corner: Vector3 in _frame_points:
		var relative := corner - _view_center
		var projected := Vector2(relative.dot(camera.basis.x), relative.dot(camera.basis.y))
		minimum = minimum.min(projected)
		maximum = maximum.max(projected)
	var viewport := get_viewport().get_visible_rect().size
	var aspect := maxf(viewport.x / maxf(viewport.y, 1.0), 1.0)
	var extent := maximum - minimum
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = maxf(extent.y / 0.66, extent.x / (aspect * 0.88))
	camera.h_offset = (minimum.x + maximum.x) / 2.0
	camera.v_offset = (minimum.y + maximum.y) / 2.0 - camera.size * 0.015

## The whole-archipelago frame holds still; the follow camera eases.
func _advance_camera(delta: float) -> void:
	if _uses_scrolling_camera(): super._advance_camera(delta)
	else: _frame_camera()

## A waiting spirit leans on the bell (or the goal standing in for it).
func _doze_anchors() -> Array[Node3D]:
	var anchors := super._doze_anchors()
	if is_instance_valid(_bell): anchors.append(_bell)
	return anchors

## Every stage builds the terrain again, so its marks fold with it.
func _marks_fold() -> bool:
	return true

## The physical chapters on this world name their own key (_chapter_key).
func _fold_key() -> String:
	return _chapter_key()

## Beams resize their parts by child index (_present_beams).
func _static_keep() -> Array:
	var keep := super._static_keep()
	keep.append_array(_beam_roots)
	return keep

func _process(delta: float) -> void:
	super._process(delta)
	_follow_lenses()

func _idle_card_frame() -> void:
	super._idle_card_frame()
	_follow_lenses()

func _follow_lenses() -> void:
	for lens: Node3D in _prop_nodes.values():
		var holder := str(lens.get_meta("holder_slot", ""))
		if actors.has(holder):
			lens.position = actors[holder].carry_point()
