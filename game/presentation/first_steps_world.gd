extends "res://presentation/island_world.gd"
## The vertical First Steps world follows its authored surfaces and verified snapshots.
## Visual interpolation never decides boarding, arrival, seed ownership or activation.
const Catalog = preload("res://core/first_steps/stage_catalog.gd")
const Canonical = preload("res://core/v2/canonical.gd")
var actor_badges: Dictionary = {}
var control_visuals: Dictionary = {}
var island_visuals: Dictionary = {}
var lift_target_height := 0.0
var loft_bell: Node3D
var bell_ring: MeshInstance3D
var pedestal: Node3D
var active_stage: Dictionary = {}
var valid_definition := false

func load_level(definition: Dictionary) -> void:
	reset_camera_exploration()
	valid_definition = Canonical.same(definition, Catalog.definition())
	if not valid_definition: return
	_reset_seed_pose()
	current_level = definition.duplicate(true)
	if is_instance_valid(terrain):
		remove_child(terrain)
		terrain.queue_free()
	terrain = Node3D.new()
	terrain.name = "FirstStepsArchipelago"
	add_child(terrain)
	actors.clear()
	actor_targets.clear()
	actor_badges.clear()
	control_visuals.clear()
	island_visuals.clear()
	bridge_parts.clear()
	lift_guides.clear()
	flowers.clear()
	garden_petals.clear()
	garden = null
	goal_ring = null
	garden_activation = null
	garden_state = "closed"
	bloomed = false
	home_view = false
	for island: Dictionary in definition.islands:
		var start := terrain.get_child_count()
		var rect: Array = island.rect_cm
		_make_island(float(rect[0] + rect[2]) / 200.0, float(rect[1] + rect[3]) / 200.0,
			float(rect[2] - rect[0]) / 100.0, float(rect[3] - rect[1]) / 100.0, Color("a4c9aa"))
		var root := Node3D.new()
		root.name = str(island.id)
		terrain.add_child(root)
		# The shared scenery builder uses y=0. Group exactly these new nodes,
		# then raise the whole floor/scenery to its authored walking height.
		var additions := terrain.get_children().slice(start, terrain.get_child_count() - 1)
		for node: Node3D in additions:
			node.reparent(root, false)
		root.position.y = float(island.height_cm) / 100.0
		island_visuals[island.id] = root
	_build_lift(definition.lift)
	for control: Dictionary in definition.controls:
		var at := _surface_point(control.position_cm, control.surface_id)
		var radius := float(control.radius_cm) / 100.0
		var disk := cylinder(radius, 0.10, Color("9c9672"), at + Vector3(0, 0.055, 0), terrain)
		ring(radius + 0.05, CREAM, at + Vector3(0, 0.12, 0), terrain)
		var glyph := box(Vector3(0.18, 0.025, 0.18), GOLD, at + Vector3(0, 0.13, 0), terrain)
		glyph.rotation.y = PI / 4
		control_visuals[control.id] = disk
	for socket: Dictionary in definition.sockets:
		var root := Node3D.new()
		root.name = str(socket.id)
		root.position = _surface_point(socket.position_cm, socket.surface_id)
		terrain.add_child(root)
		if socket.kind == "garden":
			garden = root
			cylinder(0.48, 0.14, Color("6b847c"), Vector3(0, 0.07, 0), root)
			cylinder(0.35, 0.035, Color("244b46"), Vector3(0, 0.155, 0), root)
			goal_ring = ring(0.49, GOLD, Vector3(0, 0.17, 0), root)
			_create_garden()
		else:
			pedestal = root
			cylinder(0.28, 0.35, Color("bbccb5"), Vector3(0, 0.175, 0), root)
			cylinder(0.37, 0.10, CREAM, Vector3(0, 0.39, 0), root)
			ring(0.31, GOLD, Vector3(0, 0.455, 0), root)
	for goal: Dictionary in definition.goals:
		loft_bell = Node3D.new()
		loft_bell.name = str(goal.id)
		loft_bell.position = _surface_point(goal.position_cm, goal.surface_id)
		terrain.add_child(loft_bell)
		for side in [-1, 1]:
			cylinder(0.055, 1.80, Color("8d8f77"), Vector3(side * 0.44, 0.90, 0), loft_bell)
		# Keep the exact floor goal beneath an overhead chime. A waist-high
		# frame obscures the spirit's face at the adjacent seed pedestal.
		box(Vector3(1.04, 0.10, 0.13), CREAM, Vector3(0, 1.82, 0), loft_bell)
		var bell := sphere(0.22, GOLD, Vector3(0, 1.55, 0), loft_bell)
		bell.scale = Vector3(1.0, 1.25, 1.0)
		bell_ring = ring(float(goal.radius_cm) / 100.0, CREAM, Vector3(0, 0.04, 0), loft_bell)
	for slot: String in ["p0", "p1"]:
		var spirit := _create_spirit(GOLD if slot == "p0" else TEAL)
		terrain.add_child(spirit)
		actors[slot] = spirit
		actor_targets[slot] = Vector3.ZERO
		var badge := Label3D.new()
		badge.set_meta("replay_role_badge", true)
		badge.font = preload("res://assets/fonts/nunito.ttf")
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
	landing_marker.name = "SeedLanding"
	terrain.add_child(landing_marker)
	ring(0.66, TEAL, Vector3(0, 0.035, 0), landing_marker)
	for index in range(8):
		var angle := float(index) * TAU / 8.0
		box(Vector3(0.06, 0.025, 0.13), CREAM, Vector3(cos(angle) * 0.82, 0.03, sin(angle) * 0.82), landing_marker).rotation.y = -angle
	camera.position = Vector3(8, 12, 18)
	camera.look_at(Vector3(0, 0.9, 0))
	camera.size = 11.8
	camera.h_offset = 0.0
	_present_garden(false, false, true)

func _build_lift(authored: Dictionary) -> void:
	var rect: Array = authored.rect_cm
	var width := float(rect[2] - rect[0]) / 100.0
	var depth := float(rect[3] - rect[1]) / 100.0
	var center := Vector3(float(rect[0] + rect[2]) / 200.0, 0, float(rect[1] + rect[3]) / 200.0)
	lift = Node3D.new()
	lift.name = str(authored.id)
	lift.position = center
	terrain.add_child(lift)
	box(Vector3(width, 0.18, depth), Color("b8aa8c"), Vector3(0, -0.09, 0), lift)
	box(Vector3(width - 0.06, 0.025, depth - 0.06), Color("e0d4ac"), Vector3(0, 0.012, 0), lift)
	ring(0.40, GOLD, Vector3(0, 0.035, 0), lift)
	var height := float(authored.top_height_cm - authored.bottom_height_cm) / 100.0
	for side in [-1, 1]:
		# Side guides sit outside the walkable rectangle; entry/exit remain open.
		for edge in [-1, 1]:
			var at := center + Vector3(edge * (width / 2.0 - 0.16), height / 2.0, side * (depth / 2.0 + 0.10))
			cylinder(0.045, height + 0.40, Color("809d91"), at, terrain)
		box(Vector3(width, 0.05, 0.045), CREAM, Vector3(0, 0.33, side * (depth / 2.0 + 0.04)), lift)
	lift_target_height = float(authored.bottom_height_cm) / 100.0
	lift.position.y = lift_target_height

func _surface_point(position_cm: Array, surface: String) -> Vector3:
	for island: Dictionary in current_level.islands:
		if island.id == surface:
			return Vector3(float(position_cm[0]) / 100.0, float(island.height_cm) / 100.0, float(position_cm[1]) / 100.0)
	return Vector3.ZERO # Bundled definition is validated before any geometry.

func show_stage(value: Dictionary) -> void:
	reset_camera_exploration()
	active_stage = value.duplicate(true)
	landing_marker.visible = value.has("landing_cm")
	if landing_marker.visible:
		landing_marker.position = _surface_point(value.landing_cm, value.landing_surface)

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
		actor_badges[slot].text = "You" if slot == state.active_slot else "Memory" if actor.get("ghost", false) else "Waiting"
	lift_target_height = float(state.mechanisms.lift.height_cm) / 100.0
	if immediate: lift.position.y = lift_target_height
	for id: String in control_visuals:
		var mat := control_visuals[id].material_override as StandardMaterial3D
		var active: bool = bool(state.controls.get(id, false))
		mat.albedo_color = Color("f5d990") if active else Color("9c9672")
		mat.emission_enabled = active
		mat.emission = GOLD
		mat.emission_energy_multiplier = 0.28
	bell_ring.visible = not bool(state.mechanisms.loft_open)
	_present_seed(state.seed, immediate)
	_present_garden(bool(state.mechanisms.garden_open), bool(state.complete) and state.seed.status == "planted", immediate)

func _process(delta: float) -> void:
	super._process(delta)
	if is_instance_valid(lift):
		lift.position.y = lerpf(lift.position.y, lift_target_height, minf(delta * 14.0, 1.0))
	if is_instance_valid(camera):
		camera.size = 11.8
		camera.h_offset = 0.0
