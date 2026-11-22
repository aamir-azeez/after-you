extends "res://presentation/island_world.gd"
## A view of the v2 surface graph. Walkability and checkpoint state stay in core.
## Floors, the plates (pads in the style they resolve to), the crossings (the
## bridge kit), the scenery and the seed's throw all come from island_world's
## shared build; this world adds the relay nest, and the garden planter as its
## goal piece (island_world _build_goal), a pad per pip, lit once planted. Its
## camera follows the live spirit, and its barriers, marks and tags stand, as
## every scrolling chapter's do.

var socket_visuals: Dictionary = {}
var actor_badges: Dictionary = {}


func load_level(definition: Dictionary) -> void:
	reset_camera_exploration()
	_reset_seed_pose()
	_clear_object_trails()
	current_level = definition
	displayed_stage_id = ""
	pad_pieces.clear()
	goal_pieces.clear()
	if is_instance_valid(terrain):
		remove_child(terrain)
		terrain.queue_free()
	terrain = Node3D.new()
	terrain.name = "RelayArchipelago"
	add_child(terrain)
	actors.clear()
	actor_targets.clear()
	bridge_parts.clear()
	socket_visuals.clear()
	actor_badges.clear()
	flowers.clear()
	garden = null
	goal_ring = null
	garden_activation = null
	garden_petals.clear()
	garden_state = "closed"
	bloomed = false
	home_view = false
	# Floors, the plates, the scenery and the crossings.
	await _build_island_ground(definition)
	for item: Dictionary in definition.sockets:
		var at := point(item.position_cm)
		var socket: Node3D
		if item.get("kind", "") == "garden":
			# The planting finds the planter by the socket's name.
			socket = _build_goal(str(item.id), at, float(item.radius_cm) / 100.0).root
			socket.name = str(item.id)
			garden = socket
			_create_garden(GoalPiece.PLANTER_DRUM + 0.02)
			# Relay's garden socket has no gate or lift condition in simulation.
			_present_garden(true, false, true)
		else:
			socket = Node3D.new()
			socket.name = str(item.id)
			socket.position = at
			terrain.add_child(socket)
			SocketKit.relay(socket)
		socket_visuals[item.id] = socket
		await _build_step()
	for slot: String in ["p0", "p1"]:
		var spirit := _create_spirit(GOLD if slot == "p0" else TEAL, slot)
		terrain.add_child(spirit)
		actors[slot] = spirit
		actor_targets[slot] = Vector3.ZERO
		actor_badges[slot] = Badges.make(spirit)
		await _build_step()
	_build_seed_throw("ActiveLanding")
	_follow_center = Vector3.ZERO
	_frame_camera()


func show_stage(stage: Dictionary) -> void:
	reset_camera_exploration()
	displayed_stage_id = str(stage.get("id", ""))
	show_keepsake_landmark(displayed_stage_id)
	landing_marker.position = point(stage.get("landing_cm", [0, 0]))
	_clear_stage_marks()
	_build_stage_marks(LevelLayout.for_key(_chapter_key(), displayed_stage_id, current_level))


func present(state: Dictionary, immediate: bool = false) -> void:
	if immediate: reset_camera_exploration()
	if state.is_empty() or not is_instance_valid(seed):
		return
	for slot: String in actors:
		var player: Dictionary = state.players[slot]
		actor_targets[slot] = Vector3(float(player.x) / 100.0, float(player.get("height", 0)) / 100.0, float(player.z) / 100.0)
		if immediate:
			actors[slot].position = actor_targets[slot]
			actors[slot].reset_motion()
		# A sees where the waiting partner is. B sees the earlier spirit moving.
		actors[slot].visible = true
		actor_badges[slot].text = _role_badge_text(state, slot)
	_present_crossings(state.bridges, immediate)
	# A plate stays lit while its crossing is open.
	for bridge: Dictionary in current_level.bridges:
		pad_pieces[bridge.plate_id].set_held(bool(state.bridges.get(bridge.id, false)), immediate or reduced_motion)
	_present_seed(state.seed, immediate)
	var garden_complete := bool(state.get("complete", false)) and str(state.get("stage_id", "")) == str(current_level.stages[-1].id)
	for piece: RefCounted in goal_pieces.values(): piece.set_lit(garden_complete, immediate or reduced_motion)
	_present_goal_pips(state.players, immediate or reduced_motion)
	_present_garden(true, garden_complete, immediate)
	_present_stage_marks(state)
	_present_follow(state, immediate)


func _chapter_key() -> String:
	return "relay-isles@2"

func _fold_key() -> String:
	return _chapter_key()

## Relay's plain floors (no ground style) keep their grass.
func _plain_floor_colour() -> Color:
	return Color("9fc8b8")

## A planted seed finds its socket by name and reads its cylinders.
func _static_keep() -> Array:
	return super._static_keep() + socket_visuals.values()

func _uses_scrolling_camera() -> bool:
	return true

## A plate is held while its crossing stands open.
func _marks_state(state: Dictionary) -> Dictionary:
	var held: Dictionary = {}
	for bridge: Dictionary in current_level.bridges: held[str(bridge.plate_id)] = bool(state.get("bridges", {}).get(bridge.id, false))
	var shared := state.duplicate()
	shared["hold_pads"] = held
	return shared
