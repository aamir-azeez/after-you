extends "res://presentation/island_world.gd"
## A view of the v2 surface graph. Walkability and checkpoint state stay in core.
## Floors, the plates (pads in the style they resolve to), the crossings (the
## bridge kit), the scenery and the seed's throw all come from island_world's
## shared build; this world adds the relay nest and the garden planter. Its
## camera follows the live spirit as every scrolling chapter's does.

## The follow camera's centre stays this far (metres) inside the
## archipelago's west and east ends.
const FOLLOW_INSET := 4.0

var socket_visuals: Dictionary = {}
var actor_badges: Dictionary = {}


func load_level(definition: Dictionary) -> void:
	reset_camera_exploration()
	_reset_seed_pose()
	_clear_object_trails()
	current_level = definition
	displayed_stage_id = ""
	pad_pieces.clear()
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
		var socket := Node3D.new()
		socket.name = str(item.id)
		socket.position = at
		terrain.add_child(socket)
		if item.get("kind", "") == "garden":
			garden = socket
			goal_ring = SocketKit.garden(socket, 0.42, TEAL)
			_create_garden(SocketKit.PLANTER + 0.02)
			# Relay's garden socket has no gate or lift condition in simulation.
			_present_garden(true, false, true)
		else:
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
	route_barriers.clear()
	route_barriers.build(LevelLayout.for_key(_chapter_key(), displayed_stage_id, current_level))


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
		pad_pieces[bridge.plate_id].set_held(bool(state.bridges.get(bridge.id, false)))
	_present_seed(state.seed, immediate)
	var garden_complete := bool(state.get("complete", false)) and str(state.get("stage_id", "")) == str(current_level.stages[-1].id)
	_present_garden(true, garden_complete, immediate)
	route_barriers.present(state)
	_active_player = str(state.get("active_slot", _active_player))
	_completion_view = bool(state.get("complete", false))
	if immediate: _snap_follow()


func _chapter_key() -> String:
	return "relay-isles@2"

func _fold_key() -> String:
	return _chapter_key()

## Relay's plain floors (no ground style) keep their grass.
func _plain_floor_colour() -> Color:
	return Color("9fc8b8")

## A planted seed finds its socket by name and reads its cylinders.
func _static_keep() -> Array:
	var keep: Array = super._static_keep() + socket_visuals.values()
	for id: String in pad_pieces: keep += pad_pieces[id].moving_parts()
	return keep

func _uses_scrolling_camera() -> bool:
	return true

## Kept between the archipelago's ends while a stage plays.
func _camera_center() -> Vector3:
	var target := super._camera_center()
	if not _completion_view and actors.has(_camera_slot(_active_player)):
		var low := INF
		var high := -INF
		for island: Dictionary in current_level.get("islands", []):
			low = minf(low, float(island.rect_cm[0]) / 100.0)
			high = maxf(high, float(island.rect_cm[2]) / 100.0)
		target.x = clampf(_focus_point().x, low + FOLLOW_INSET, high - FOLLOW_INSET)
	return target

func _advance_camera(delta: float) -> void:
	if route_barriers.moving(): route_barriers.advance(delta)
	_ease_follow(delta)
	_frame_camera()
