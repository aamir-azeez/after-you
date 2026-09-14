extends "res://presentation/island_world.gd"
## A view of the v2 surface graph. Walkability and checkpoint state stay in core.

var bridge_visuals: Dictionary = {}
var bridge_targets: Dictionary = {}
var socket_visuals: Dictionary = {}
var plate_visuals: Dictionary = {}
var actor_badges: Dictionary = {}
var active_landing: Vector3 = Vector3.ZERO
var view_center := Vector3.ZERO


func load_level(definition: Dictionary) -> void:
	_reset_seed_pose()
	current_level = definition
	if is_instance_valid(terrain):
		remove_child(terrain)
		terrain.queue_free()
	terrain = Node3D.new()
	terrain.name = "RelayArchipelago"
	add_child(terrain)
	actors.clear()
	actor_targets.clear()
	bridge_parts.clear()
	bridge_visuals.clear()
	bridge_targets.clear()
	socket_visuals.clear()
	plate_visuals.clear()
	actor_badges.clear()
	flowers.clear()
	garden = null
	goal_ring = null
	garden_activation = null
	garden_petals.clear()
	garden_state = "closed"
	bloomed = false
	home_view = false
	for island: Dictionary in definition.islands:
		var rect: Array = island.rect_cm
		_make_island(float(rect[0] + rect[2]) / 200.0, float(rect[1] + rect[3]) / 200.0,
			float(rect[2] - rect[0]) / 100.0, float(rect[3] - rect[1]) / 100.0, Color("9fc8b8"))
	for bridge: Dictionary in definition.bridges:
		var rect: Array = bridge.rect_cm
		var width := float(rect[2] - rect[0]) / 100.0
		var depth := float(rect[3] - rect[1]) / 100.0
		var root := Node3D.new()
		root.name = str(bridge.id)
		root.position = Vector3(float(rect[0] + rect[2]) / 200.0, -0.6, float(rect[1] + rect[3]) / 200.0)
		terrain.add_child(root)
		for index in range(7):
			var x := -width / 2.0 + (float(index) + 0.5) * width / 7.0
			var plank := box(Vector3(width / 7.0 - 0.012, 0.10, depth), Color("c4b090"), Vector3(x, -0.06, 0), root)
			for side in [-1, 1]:
				cylinder(0.035, 0.3, Color("8b7964"), Vector3(0, 0.19, side * (depth / 2.0 - 0.06)), plank)
		bridge_visuals[bridge.id] = root
		bridge_targets[bridge.id] = false
	for item: Dictionary in definition.plates:
		var p := point(item.position_cm)
		var radius := float(item.radius_cm) / 100.0
		var disk := cylinder(radius, 0.10, GOLD, p + Vector3(0, 0.055, 0), terrain)
		ring(radius + 0.025, CREAM, p + Vector3(0, 0.12, 0), terrain)
		box(Vector3(0.21, 0.022, 0.21), Color("977346"), p + Vector3(0, 0.12, 0), terrain).rotation.y = PI / 4
		plate_visuals[item.id] = disk
	for item: Dictionary in definition.sockets:
		var at := point(item.position_cm)
		var socket := Node3D.new()
		socket.name = str(item.id)
		socket.position = at
		terrain.add_child(socket)
		cylinder(0.42, 0.14, Color("6b847c"), Vector3(0, 0.07, 0), socket)
		cylinder(0.30, 0.035, Color("244b46"), Vector3(0, 0.155, 0), socket)
		var socket_ring := ring(0.43, TEAL, Vector3(0, 0.17, 0), socket)
		if item.get("kind", "") == "garden":
			garden = socket
			goal_ring = socket_ring
			_create_garden()
			# Relay's garden socket has no gate or lift condition in simulation.
			_present_garden(true, false, true)
		else:
			# A small cradle and two leaves distinguish a relay from a pressure plate.
			for side in [-1, 1]:
				var leaf := sphere(0.17, TEAL, Vector3(side * 0.36, 0.40, 0), socket)
				leaf.scale = Vector3(0.5, 1.6, 0.35)
				leaf.rotation.z = -side * 0.5
		socket_visuals[item.id] = socket
	for slot: String in ["p0", "p1"]:
		var spirit := _create_spirit(GOLD if slot == "p0" else TEAL)
		terrain.add_child(spirit)
		actors[slot] = spirit
		actor_targets[slot] = Vector3.ZERO
		var badge := Label3D.new()
		badge.set_meta("replay_role_badge", true)
		var badge_font := FontVariation.new()
		badge_font.base_font = preload("res://assets/fonts/nunito.ttf")
		badge_font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 700.0}
		badge.font = badge_font
		badge.font_size = 42
		badge.pixel_size = 0.006
		badge.position.y = 1.34
		badge.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		badge.modulate = CREAM
		badge.outline_modulate = Color("193d39")
		badge.outline_size = 8
		spirit.add_child(badge)
		actor_badges[slot] = badge
	seed = sphere(0.13, Color("ffda83"), Vector3.ZERO, terrain)
	var seed_material := seed.material_override as StandardMaterial3D
	seed_material.emission_enabled = true
	seed_material.emission = Color("e6b767")
	seed_material.emission_energy_multiplier = 1.2
	landing_marker = Node3D.new()
	landing_marker.name = "ActiveLanding"
	terrain.add_child(landing_marker)
	ring(0.65, TEAL, Vector3(0, 0.035, 0), landing_marker)
	for index in range(8):
		var angle := float(index) * TAU / 8.0
		box(Vector3(0.06, 0.025, 0.13), CREAM, Vector3(cos(angle) * 0.83, 0.03, sin(angle) * 0.83), landing_marker).rotation.y = -angle
	camera.position = Vector3(8, 14, 19)
	camera.look_at(Vector3.ZERO)
	camera.size = 12.0
	camera.h_offset = 0.0


func show_stage(stage: Dictionary) -> void:
	active_landing = point(stage.get("landing_cm", [0, 0]))
	landing_marker.position = active_landing
	# Both gaps remain visible. The checkpoint changes the goal, not the world.
	view_center = Vector3.ZERO


func present(state: Dictionary, immediate: bool = false) -> void:
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
		actor_badges[slot].text = "You" if slot == str(state.active_slot) else ("Memory" if player.get("ghost", false) else "Waiting")
	for id: String in bridge_visuals:
		bridge_targets[id] = bool(state.bridges.get(id, false))
		if immediate:
			bridge_visuals[id].position.y = 0.0 if bridge_targets[id] else -0.65
	for bridge: Dictionary in current_level.bridges:
		var disk: MeshInstance3D = plate_visuals[bridge.plate_id]
		(disk.material_override as StandardMaterial3D).albedo_color = Color("f5d990") if bridge_targets[bridge.id] else Color("a18f66")
	_present_seed(state.seed, immediate)
	var garden_complete := bool(state.get("complete", false)) and str(state.get("stage_id", "")) == str(current_level.stages[-1].id)
	_present_garden(true, garden_complete, immediate)


func _process(delta: float) -> void:
	# Reuse character gait, garden animation and motes; no legacy bridge is present.
	super._process(delta)
	var weight := minf(delta * 12.0, 1.0)
	for id: String in bridge_visuals:
		var target_y := 0.0 if bridge_targets[id] else -0.65
		bridge_visuals[id].position.y = lerpf(bridge_visuals[id].position.y, target_y, weight)
	if is_instance_valid(camera):
		camera.size = 12.0
		camera.h_offset = 0.0
