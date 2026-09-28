extends "res://presentation/lighthouse_world.gd"
## Physical chapter scenery reuses Lighthouse terrain, bridges, bells and spirits.
## All movement, ownership and gate decisions come from the simulation snapshot.
const CooperativeCatalog = preload("res://core/cooperative/stage_catalog.gd")
var chapter_definition: Dictionary = {}
var displayed_stage_id := ""
var _physical_pads: Dictionary = {}
var _physical_levers: Dictionary = {}
var _physical_balls: Dictionary = {}
var _stair_gates: Dictionary = {}
var _weights: Dictionary = {}
var _hatches: Dictionary = {}
var _upper_islands: Array[Node3D] = []
var _active_player := "p0"
var _follow_center := Vector3.ZERO
var _follow_size := 9.2
var _completion_view := false

func load_level(definition: Dictionary) -> void:
	chapter_definition = definition.duplicate(true)
	displayed_stage_id = ""
	if not definition.get("stages", []).is_empty(): show_stage(definition.stages[0])

func show_stage(stage: Dictionary) -> void:
	var stage_id := str(stage.get("id", ""))
	if stage_id.is_empty() or stage_id == displayed_stage_id: return
	var view := CooperativeCatalog.stage_definition(chapter_definition, stage_id)
	if view.is_empty(): return
	displayed_stage_id = stage_id
	_completion_view = false
	_physical_pads.clear()
	_physical_levers.clear()
	_physical_balls.clear()
	_stair_gates.clear()
	_weights.clear()
	_hatches.clear()
	_upper_islands.clear()
	# These are presentation defaults for the shared Lighthouse builder.
	_configure_shared_view(view)
	var physical_props: Array = view.get("props", []).duplicate(true)
	view["props"] = []
	var goal: Dictionary = view.goal.duplicate(true)
	if view.goal_policy.kind == "ball_home": view.erase("goal")
	super.load_level(view)
	terrain.name = "CooperativeIslands"
	if is_instance_valid(_bell):
		_bell.get_parent().position.y = _surface_height(str(goal.surface_id))
		_court_light.position.y += _surface_height(str(goal.surface_id))
	for stair: Dictionary in view.get("stairs", []): _build_stair(stair)
	for pad: Dictionary in view.get("pressure_pads", []): _build_physical_pad(pad, false)
	for pad: Dictionary in view.get("ball_pads", []): _build_physical_pad(pad, true)
	for lever: Dictionary in view.get("levers", []): _build_lever(lever)
	for zone: Dictionary in view.get("access_zones", []):
		var r: Array = zone.rect_cm
		var zone_height := _surface_height(str(zone.surface_id))
		var color := GOLD if zone.owner_slot == "p0" else TEAL
		for x in range(int(r[0]) + 24, int(r[2]), 64):
			_ownership_mark(str(zone.owner_slot), Vector3(float(x) / 100.0, zone_height + 0.015, float(r[1] + r[3]) / 200.0), terrain)
		box(Vector3(float(r[2] - r[0]) / 100.0, 0.018, 0.035), color, Vector3(float(r[0] + r[2]) / 200.0, zone_height + 0.012, float(r[1]) / 100.0), terrain)
	for obstacle: Dictionary in view.get("obstacles", []):
		_build_obstacle(obstacle)
	for prop: Dictionary in physical_props:
		var ball := sphere(float(prop.radius_cm) / 100.0, Color("d08b56"), _at(prop), terrain)
		ball.name = str(prop.id)
		var band := ring(float(prop.radius_cm) / 100.0, Color("344b5c"), Vector3.ZERO, ball)
		band.scale.y = 2.4
		band.rotation.z = PI / 2.0
		_physical_balls[prop.id] = ball
	if view.has("handoff"):
		var mark: Dictionary = view.handoff
		ring(0.42, CREAM, _at(mark) + Vector3(0, 0.03, 0), terrain)
		for side in [-1, 1]: _ownership_mark("p0" if side == -1 else "p1", _at(mark) + Vector3(side * 0.6, 0.03, 0), terrain)
	if view.goal_policy.kind == "ball_home":
		var at := _at(goal)
		cylinder(0.4, 0.07, Color("6b8984"), at + Vector3(0, 0.035, 0), terrain)
		ring(0.32, GOLD, at + Vector3(0, 0.085, 0), terrain)
		for side in [-1, 1]: sphere(0.08, CREAM, at + Vector3(side * 0.34, 0.13, 0), terrain)
	for drop: Dictionary in view.get("drops", []):
		var rect: Array = drop.rect_cm
		var center := point([(rect[0] + rect[2]) * 0.5, (rect[1] + rect[3]) * 0.5])
		var height := _surface_height(str(drop.surface_id))
		for side in [-1, 1]:
			box(Vector3(0.045, 0.04, float(rect[3] - rect[1]) / 100.0), TEAL, center + Vector3(side * float(rect[2] - rect[0]) / 200.0, height + 0.02, 0), terrain)
		var hatch := Node3D.new()
		terrain.add_child(hatch)
		for index in range(4):
			box(Vector3(float(rect[2] - rect[0]) / 100.0, 0.035, 0.035), CREAM, center + Vector3(0, height, (float(index) - 1.5) * float(rect[3] - rect[1]) / 400.0), hatch)
		if str(drop.get("requires_lever", "")).is_empty(): hatch.visible = false
		else:
			_hatches[drop.requires_lever] = hatch
			for lever: Dictionary in view.get("levers", []):
				if lever.id == drop.requires_lever:
					_bar_between(_at(lever) + Vector3(0, 0.04, 0), center + Vector3(0, height + 0.04, 0), 0.025, Color("b6a480"), terrain)
		ring(0.32, TEAL, center + Vector3(0, 0.025, 0), terrain)
		# Dashes inside the open shaft make its landing legible from above.
		for index in range(3): sphere(0.035, CREAM, center + Vector3(0, height * float(index + 1) / 4.0, 0), terrain)
	_build_gate_links(view)
	if _has_completion_garden(stage_id):
		garden = Node3D.new()
		garden.name = "HomeGarden"
		garden.position = _completion_garden_position(goal)
		garden.scale = _completion_garden_scale_vector()
		garden.set_meta("celebration_clear_point", Vector2(_at(goal).x, _at(goal).z))
		terrain.add_child(garden)
		cylinder(1.45, 0.10, Color("617769"), Vector3(0, 0.01, 0), garden)
		cylinder(1.30, 0.02, Color("435b50"), Vector3(0, 0.065, 0), garden)
		goal_ring = null
		_create_garden()
	if is_instance_valid(camera_exploration): camera_exploration.maximum_pan = Vector2(1.2, 0.4)

func _configure_shared_view(view: Dictionary) -> void:
	view["optics"] = {"emitters": [], "receivers": []}
	view["controls"] = []

func _completion_garden_position(goal: Dictionary) -> Vector3:
	return _at(goal) + Vector3(0, 0, -0.7)

func _completion_garden_scale() -> float:
	return 0.85

func _completion_garden_scale_vector() -> Vector3:
	return Vector3.ONE * _completion_garden_scale()

func _has_completion_garden(stage_id: String) -> bool:
	return stage_id in ["down-and-around", "bring-it-home"]

func _uses_lower_cutaway() -> bool:
	return displayed_stage_id == "down-and-around"

func _uses_scrolling_camera() -> bool:
	return chapter_definition.get("id", "") == "rolling-home"

func _shore(island: Dictionary, color: Color) -> void:
	var original := terrain
	var raised := Node3D.new()
	raised.position.y = float(island.get("height_cm", 0)) / 100.0
	original.add_child(raised)
	if raised.position.y > 0.5: _upper_islands.append(raised)
	terrain = raised
	var hole: Dictionary = {}
	for drop: Dictionary in current_level.get("drops", []):
		if drop.surface_id == island.id: hole = drop
	if hole.is_empty():
		super._shore(island, color)
	else:
		var r: Array = island.rect_cm
		var h: Array = hole.rect_cm
		# Four authored floor pieces leave an actual opening; no dark decal.
		for cut: Array in [[r[0], r[1], h[0], r[3]], [h[2], r[1], r[2], r[3]], [h[0], r[1], h[2], h[1]], [h[0], h[3], h[2], r[3]]]:
			if cut[2] > cut[0] and cut[3] > cut[1]: super._shore({"id": island.id, "rect_cm": cut}, color)
	terrain = original
	raised.set_meta("bounds", island.rect_cm.duplicate())
	_surface_built(island, raised)

func _surface_built(_island: Dictionary, _surface: Node3D) -> void:
	pass

func _set_cutaway(node: Node, faded: bool) -> void:
	if node is MeshInstance3D and node.material_override is StandardMaterial3D:
		if node.get_meta("cutaway", false) == faded: return
		node.set_meta("cutaway", faded)
		var mat := node.material_override as StandardMaterial3D
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if faded else BaseMaterial3D.TRANSPARENCY_DISABLED
		mat.albedo_color.a = 0.10 if faded else 1.0
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if faded else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for child: Node in node.get_children(): _set_cutaway(child, faded)

func _build_obstacle(obstacle: Dictionary) -> void:
	var r: Array = obstacle.rect_cm
	var at := point([(r[0] + r[2]) * 0.5, (r[1] + r[3]) * 0.5])
	at.y = _surface_height(str(obstacle.surface_id))
	box(Vector3(float(r[2] - r[0]) / 100.0, 0.35, float(r[3] - r[1]) / 100.0), Color("718b79"), at + Vector3(0, 0.175, 0), terrain)
	for x in range(int(r[0]) + 18, int(r[2]), 35):
		var tuft := sphere(0.21, Color("8dad95"), Vector3(float(x) / 100.0, at.y + 0.4, at.z), terrain)
		tuft.scale = Vector3(0.7, 0.6, 1)

func _build_bridge(definition: Dictionary) -> void:
	super._build_bridge(definition)
	var rect: Array = definition.rect_cm
	var owner := str(definition.get("owner_slot", ""))
	var at := point([rect[0], (rect[1] + rect[3]) * 0.5])
	if not owner.is_empty():
		_ownership_mark(owner, at + Vector3(-0.18, 0.025, 0), terrain)
		_ownership_mark(owner, point([rect[2] + 18, (rect[1] + rect[3]) * 0.5]) + Vector3(0, 0.025, 0), terrain)
	# A fixed pulley and suspended weight show where a missing crossing goes.
	var post := at + Vector3(0.05, 0, float(rect[3] - rect[1]) / 200.0 + 0.15)
	box(Vector3(0.10, 1.1, 0.1), Color("9e9180"), post + Vector3(0, 0.55, 0), terrain)
	var pulley := ring(0.13, GOLD, post + Vector3(0, 1.1, 0), terrain)
	pulley.rotation.x = PI / 2.0
	box(Vector3(0.025, 1.2, 0.025), CREAM, post + Vector3(0.14, 0.45, 0), terrain)
	var weight := box(Vector3(0.22, 0.32, 0.22), Color("748998"), post + Vector3(0.14, 0.45, 0), terrain)
	_weights[definition.id] = weight
	weight.set_meta("rest_y", weight.position.y)

func _build_stair(stair: Dictionary) -> void:
	var r: Array = stair.rect_cm
	var from_height := float(stair.from_height_cm) / 100.0
	var rise := float(stair.to_height_cm - stair.from_height_cm) / 100.0
	var width := float(r[2] - r[0]) / 100.0
	var depth := float(r[3] - r[1]) / 100.0
	var center := point([(r[0] + r[2]) * 0.5, (r[1] + r[3]) * 0.5])
	var along_x: bool = stair.axis == "x"
	for index in range(10):
		var height := from_height + rise * float(index + 1) / 10.0
		var at := center + Vector3((float(index) - 4.5) * width / 10.0 if along_x else 0, height - 0.06, (float(index) - 4.5) * depth / 10.0 if not along_x else 0)
		box(Vector3(width / 10.0 if along_x else width, 0.12, depth if along_x else depth / 10.0), Color("b4c5bd"), at, terrain)
		box(Vector3(0.025 if along_x else width, 0.014, depth if along_x else 0.025), TEAL, at + Vector3(0, 0.065, 0), terrain)
	var entrance := point([r[0], (r[1] + r[3]) * 0.5] if along_x else [(r[0] + r[2]) * 0.5, r[1]]) + Vector3(0, from_height, 0)
	_ownership_mark(str(stair.owner_slot), entrance + (Vector3(-0.24, 0.03, 0) if along_x else Vector3(0, 0.03, -0.24)), terrain)
	_stair_gates[stair.id] = box(Vector3(0.08, 0.4, depth) if along_x else Vector3(width, 0.4, 0.08), TEAL, entrance + Vector3(0, 0.2, 0), terrain)

func _build_physical_pad(pad: Dictionary, heavy: bool) -> void:
	var at := _at(pad)
	var color := GOLD if heavy or pad.get("owner_slot", "") == "p0" else TEAL
	cylinder(float(pad.radius_cm) / 100.0, 0.055, color.darkened(0.25), at + Vector3(0, 0.025, 0), terrain)
	var outline := ring(float(pad.radius_cm) / 100.0, color, at + Vector3(0, 0.065, 0), terrain)
	_physical_pads[pad.id] = outline
	if heavy:
		ring(0.16, CREAM, at + Vector3(0, 0.06, 0), terrain)
	else: _ownership_mark(str(pad.owner_slot), at + Vector3(0, 0.06, 0), terrain)

func _build_lever(lever: Dictionary) -> void:
	var at := _at(lever)
	cylinder(0.18, 0.2, Color("728788"), at + Vector3(0, 0.1, 0), terrain)
	var pivot := Node3D.new()
	pivot.position = at + Vector3(0, 0.2, 0)
	terrain.add_child(pivot)
	box(Vector3(0.055, 0.40, 0.055), CREAM, Vector3(0, 0.2, 0), pivot)
	sphere(0.09, GOLD if lever.owner_slot == "p0" else TEAL, Vector3(0, 0.4, 0), pivot)
	_physical_levers[lever.id] = pivot
	_ownership_mark(str(lever.owner_slot), at + Vector3(0, 0.025, 0.33), terrain)

func _ownership_mark(slot: String, at: Vector3, parent: Node3D) -> void:
	# Shape repeats on spirit-specific routes and controls, alongside color.
	if slot == "p0":
		var diamond := box(Vector3(0.17, 0.018, 0.17), GOLD, at, parent)
		diamond.rotation.y = PI / 4.0
	else:
		ring(0.13, TEAL, at, parent)

func _build_gate_links(view: Dictionary) -> void:
	for gate: Dictionary in view.get("gates", []):
		var route: Dictionary = {}
		for candidate: Dictionary in view.bridges + view.get("stairs", []):
			if candidate.id == gate.route_id: route = candidate
		if route.is_empty(): continue
		var rect: Array = route.rect_cm
		var end := point([rect[0], (rect[1] + rect[3]) * 0.5]) + Vector3(0, float(route.get("height_cm", route.get("from_height_cm", 0))) / 100.0 + 0.03, 0)
		for mechanism: Dictionary in view.get("pressure_pads", []) + view.get("ball_pads", []) + view.get("levers", []):
			if mechanism.id not in [gate.get("pad_id", ""), gate.get("lever_id", ""), gate.get("second_lever_id", ""), gate.get("ball_pad_id", "")]: continue
			var link_color := _gate_link_color(mechanism)
			var start := _at(mechanism) + Vector3(0, 0.03, 0)
			var elbow := Vector3(end.x - 0.18, start.y, start.z)
			if start.distance_to(elbow) > 0.01: _bar_between(start, elbow, 0.025, link_color, terrain)
			if elbow.distance_to(end) > 0.01: _bar_between(elbow, end, 0.025, link_color, terrain)

func _gate_link_color(_mechanism: Dictionary) -> Color:
	return Color("b6a480")

func _surface_height(id: String) -> float:
	for island: Dictionary in chapter_definition.get("islands", []):
		if island.id == id: return float(island.get("height_cm", 0)) / 100.0
	return 0.0

func _at(value: Dictionary) -> Vector3:
	return point(value.position_cm) + Vector3(0, _surface_height(str(value.get("surface_id", ""))), 0)

func present_history(checkpoint: Dictionary) -> void:
	_latched_bridge_ids = checkpoint.get("mechanisms", {}).get("latched_bridges", []).duplicate()

func present(state: Dictionary, immediate: bool = false) -> void:
	if state.get("stage_id", "") != displayed_stage_id:
		for authored: Dictionary in chapter_definition.get("stages", []):
			if authored.id == state.get("stage_id", ""): show_stage(authored)
	if not state.has("players"): return
	_active_player = str(state.active_slot)
	_completion_view = bool(state.get("complete", false))
	for raised: Node3D in _upper_islands:
		_set_cutaway(raised, _should_cutaway(raised,state))
	var visual := state.duplicate(true)
	visual.merge({"mirror_orientation": "slash", "emitter_powered": false, "objective_done": bool(state.get("complete", false)), "optics": {"segments": [], "signals": {}}, "bridges": {}, "mirrors": {}, "selectors": {}, "props": {}}, false)
	super.present(visual, immediate)
	for actor: SpiritVisual in actors.values(): actor.set_celebration(_completion_view, immediate, reduced_motion)
	if is_instance_valid(garden): _present_garden(false, bool(state.get("complete", false)), immediate)
	for id: String in _physical_balls:
		var prop: Dictionary = state.get("props", {}).get(id, {})
		if prop.is_empty(): continue
		# A persistent claim authorizes a future push; only native contact means
		# this spirit is currently using the ball. Snapshots without a cue stay neutral.
		var holder := str(prop.get("controller_slot", ""))
		var material := _physical_balls[id].material_override as StandardMaterial3D
		material.albedo_color = GOLD if holder == "p0" else TEAL if holder == "p1" else CREAM
		var target := Vector3(float(prop.x) / 100.0, float(prop.get("height", 0)) / 100.0 + 0.2, float(prop.z) / 100.0)
		if not immediate:
			var displacement: Vector3 = target - _physical_balls[id].position
			_physical_balls[id].rotate_x(displacement.z / 0.2)
			_physical_balls[id].rotate_z(-displacement.x / 0.2)
		_physical_balls[id].position = target
	for id: String in _physical_levers:
		_physical_levers[id].rotation.z = -0.6 if state.get("levers", {}).get(id, false) else 0.6
	for id: String in _hatches: _hatches[id].visible = not state.get("levers", {}).get(id, false)
	for id: String in _physical_pads:
		var pressed: bool = state.get("hold_pads", {}).get(id, false)
		_glow(_physical_pads[id], LIGHT_COLOR, 1.0 if pressed else 0.0)
	for id: String in _stair_gates: _stair_gates[id].visible = not state.get("bridges", {}).get(id, false)
	for id: String in _weights:
		_weights[id].position.y = float(_weights[id].get_meta("rest_y")) - (0.7 if state.get("bridges", {}).get(id, false) else 0.0)
	if immediate:
		if actors.has(_active_player): _follow_center = _camera_center()
		_follow_size = 10.6 if _completion_view else 9.2
		_frame_camera()

func _should_cutaway(raised: Node3D, state: Dictionary) -> bool:
	return _uses_lower_cutaway() and _below_raised(raised,state.players[_active_player])

func _below_raised(raised: Node3D, player: Dictionary) -> bool:
	var bounds: Array = raised.get_meta("bounds")
	return float(player.height)/100.0 < raised.position.y-0.5 and int(player.x) >= int(bounds[0])-200 and int(player.x) <= int(bounds[2])+100

func _camera_center() -> Vector3:
	var target: Vector3 = actors[_active_player].position
	if _completion_view:
		var left := target.x
		var right := target.x
		for actor: Node3D in actors.values():
			left = minf(left, actor.position.x)
			right = maxf(right, actor.position.x)
		if is_instance_valid(garden): right = maxf(right, garden.position.x + 1.0)
		target.x = (left + right) * 0.5
	else:
		target.x = clampf(target.x, -3.2, 12.0)
	target.z = 0
	target.y = 0
	return target

func _advance_camera(delta: float) -> void:
	if _uses_scrolling_camera():
		# Authored framing advances once per rendered frame. Snapshot delivery
		# and pinch zoom must never feed back into the follow state.
		var weight := 1.0 if reduced_motion else 1.0 - exp(-8.0 * maxf(delta, 0.0))
		if actors.has(_active_player): _follow_center = _follow_center.lerp(_camera_center(), weight)
		_follow_size = lerpf(_follow_size, 10.6 if _completion_view else 9.2, weight)
	_frame_camera()

func _frame_camera() -> void:
	if not _uses_scrolling_camera():
		super._frame_camera()
		return
	if not is_instance_valid(camera): return
	camera.position = _follow_center + Vector3(3, 13, 10)
	camera.look_at(to_global(_follow_center))
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = _follow_size
	camera.h_offset = 0
	camera.v_offset = 0.2
