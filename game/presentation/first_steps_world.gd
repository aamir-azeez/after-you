extends "res://presentation/island_world.gd"
## The vertical First Steps world follows its authored surfaces and verified snapshots.
## Visual interpolation never decides boarding, arrival, seed ownership or activation.
## Floors, pads, scenery, the seed's throw, the follow camera and each stage's
## barriers, marks and tags come from island_world's shared build; this world
## adds the lift and the seed pedestal. Its goals, the loft bell and the
## garden planter, are goal pieces (island_world _build_goal), each with a pad
## per pip; the bell lights and rings as the loft opens, the planter as the
## seed is planted.
const Catalog = preload("res://core/first_steps/stage_catalog.gd")
const Typed = preload("res://services/typed_values.gd")
## The lift's look (content/dressing/piece_styles.gd "lift") and its kit.
const LiftKit = preload("res://presentation/kit/pieces/lift.gd")
var lift_piece: RefCounted
var actor_badges: Dictionary = {}
var lift_target_height := 0.0
var pedestal: Node3D
var active_stage: Dictionary = {}
var valid_definition := false

func load_level(definition: Dictionary) -> void:
	reset_camera_exploration()
	valid_definition = Typed.same(definition, Catalog.definition())
	if not valid_definition: return
	_reset_seed_pose()
	_clear_object_trails()
	current_level = definition.duplicate(true)
	displayed_stage_id = ""
	pad_pieces.clear()
	goal_pieces.clear()
	lift_piece = null
	if is_instance_valid(terrain):
		remove_child(terrain)
		terrain.queue_free()
	terrain = Node3D.new()
	terrain.name = "FirstStepsArchipelago"
	add_child(terrain)
	actors.clear()
	actor_targets.clear()
	actor_badges.clear()
	bridge_parts.clear()
	flowers.clear()
	garden_petals.clear()
	garden = null
	goal_ring = null
	garden_activation = null
	garden_state = "closed"
	bloomed = false
	home_view = false
	# Floors, the spots' pads (each in its pip's colour) and the scenery.
	await _build_island_ground(definition)
	_build_lift(definition.lift)
	await _build_step()
	for socket: Dictionary in definition.sockets:
		var at := _floor_point(socket.position_cm, socket.surface_id)
		if socket.kind == "garden":
			# The planting finds the planter by the socket's name.
			garden = _build_goal(str(socket.id), at, float(socket.radius_cm) / 100.0).root
			garden.name = str(socket.id)
			_create_garden(SocketKit.PLANTER + 0.02)
		else:
			var root := Node3D.new()
			root.name = str(socket.id)
			root.position = at
			terrain.add_child(root)
			pedestal = root
			cylinder(0.28, 0.35, Color("bbccb5"), Vector3(0, 0.175, 0), root)
			cylinder(0.37, 0.10, CREAM, Vector3(0, 0.39, 0), root)
			ring(0.31, GOLD, Vector3(0, 0.455, 0), root)
	await _build_step()
	for goal: Dictionary in definition.goals:
		_build_goal(str(goal.id), _floor_point(goal.position_cm, goal.surface_id), float(goal.radius_cm) / 100.0)
	await _build_step()
	for slot: String in ["p0", "p1"]:
		var spirit := _create_spirit(GOLD if slot == "p0" else TEAL, slot)
		terrain.add_child(spirit)
		actors[slot] = spirit
		actor_targets[slot] = Vector3.ZERO
		actor_badges[slot] = Badges.make(spirit)
		await _build_step()
	_build_seed_throw("SeedLanding")
	_follow_center = Vector3.ZERO
	_frame_camera()
	_present_garden(false, false, true)

## The lift in its style (content/dressing/piece_styles.gd "lift"); a
## rope_tower's winch stands beside the first stage's power spot.
func _build_lift(authored: Dictionary) -> void:
	var r := drawn_rect(authored)
	var area := Rect2(float(r[0]) / 100.0, float(r[1]) / 100.0, float(r[2] - r[0]) / 100.0, float(r[3] - r[1]) / 100.0)
	var drive := Vector3.ZERO
	for control: Dictionary in current_level.controls:
		if control.id == current_level.stages[0].power_control: drive = _floor_point(control.position_cm, control.surface_id)
	lift_piece = LiftKit.build(PieceStyles.style("lift", str(authored.id), _descriptor(), dressing), area, float(authored.bottom_height_cm) / 100.0, float(authored.top_height_cm) / 100.0, terrain, {"drive": drive})
	lift = lift_piece.root
	lift.name = str(authored.id)
	lift_target_height = float(authored.bottom_height_cm) / 100.0
	lift_piece.set_height(lift_target_height)

func _descriptor() -> Dictionary:
	return ChapterIndex.data(_chapter_key())


func show_stage(value: Dictionary) -> void:
	reset_camera_exploration()
	displayed_stage_id = str(value.get("id", ""))
	show_keepsake_landmark(displayed_stage_id)
	active_stage = value.duplicate(true)
	landing_marker.visible = value.has("landing_cm")
	if landing_marker.visible:
		landing_marker.position = _floor_point(value.landing_cm, value.landing_surface)
	_clear_stage_marks()
	# The lift car shows itself whether it can run (waiting at the bottom).
	route_barriers.skip(str(current_level.lift.id), "the lift car shows whether it runs")
	_build_stage_marks(LevelLayout.for_key(_chapter_key(), displayed_stage_id, current_level))

func present(state: Dictionary, immediate: bool = false) -> void:
	if immediate: reset_camera_exploration()
	if not valid_definition or state.is_empty() or not is_instance_valid(seed): return
	for slot: String in actors:
		var actor: Dictionary = state.players[slot]
		actor_targets[slot] = Vector3(float(actor.x) / 100.0, float(actor.height) / 100.0, float(actor.z) / 100.0)
		if immediate:
			actors[slot].position = actor_targets[slot]
			actors[slot].reset_motion()
		actors[slot].visible = true
		actor_badges[slot].text = _role_badge_text(state, slot)
	lift_target_height = float(state.mechanisms.lift.height_cm) / 100.0
	if immediate: lift.position.y = lift_target_height
	if lift_piece != null: lift_piece.set_height(lift.position.y)
	for id: String in pad_pieces:
		pad_pieces[id].set_held(bool(state.controls.get(id, false)), immediate or reduced_motion)
	# A bell rung while the friend's memory still plays rings when it ends.
	var rung := bool(state.mechanisms.loft_open) and not bool(state.get("ring_held", false))
	var planted: bool = bool(state.complete) and state.seed.status == "planted"
	for piece: RefCounted in goal_pieces.values(): piece.set_lit(planted if piece.root == garden else rung, immediate or reduced_motion)
	_present_goal_pips(state.players, immediate or reduced_motion)
	_present_seed(state.seed, immediate)
	_present_garden(bool(state.mechanisms.garden_open), planted, immediate)
	_present_stage_marks(state)
	_present_follow(state, immediate)

## The pads are held as the snapshot's controls say; the lift is the
## crossing its owner's gates stand at.
func _marks_state(state: Dictionary) -> Dictionary:
	var shared := state.duplicate()
	shared["hold_pads"] = state.get("controls", {})
	shared["bridges"] = {str(current_level.lift.id): true}
	return shared

func _uses_scrolling_camera() -> bool:
	return true

func _chapter_key() -> String:
	return "first-steps@1"

func _fold_key() -> String:
	return _chapter_key()

func _doze_anchors() -> Array[Node3D]:
	var anchors := super._doze_anchors()
	for piece: RefCounted in goal_pieces.values():
		if piece.root != garden and is_instance_valid(piece.root): anchors.append(piece.root)
	return anchors

## A planted seed finds its socket by name and reads its cylinders.
func _static_keep() -> Array:
	var keep := super._static_keep() + [pedestal]
	if lift_piece != null: keep += lift_piece.moving_parts()
	return keep

## The lift is still once it is this close (metres) to its height.
const LIFT_SETTLED := 0.005

func _process(delta: float) -> void:
	super._process(delta)
	if is_instance_valid(lift):
		# The lift trails its rising target by a few centimetres while it moves.
		var travel := lift_target_height - lift.position.y
		note_motion("lift", "lift", (1 if travel > 0.0 else -1) if absf(travel) > LIFT_SETTLED else 0)
		lift.position.y = lerpf(lift.position.y, lift_target_height, minf(delta * 14.0, 1.0))
		if lift_piece != null: lift_piece.set_height(lift.position.y)
