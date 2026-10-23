extends "res://presentation/lighthouse_world.gd"
## Physical chapter scenery reuses Lighthouse terrain, bridges, bells and spirits.
## All movement, ownership and gate decisions come from the simulation snapshot.
const CooperativeCatalog = preload("res://core/cooperative/stage_catalog.gd")
const BallRotationBlur = preload("res://presentation/ball_rotation_blur.gd")
const Cutaway = preload("res://presentation/kit/cutaway.gd")
const GoalBeacon = preload("res://presentation/kit/goal_beacon.gd")
const StandSpot = preload("res://presentation/kit/stand_spot.gd")
## A lever's look (a winch, a bolt) where the descriptor's "lever_looks" names one.
const LeverLooks = preload("res://presentation/kit/lever_looks.gd")
## The opening glance at the goal (glance_at_goal): this long easing there and
## looking, then this long easing back to the spirit.
const GLANCE_TO := 1.6
const GLANCE_BACK := 0.6
var chapter_definition: Dictionary = {}
var displayed_stage_id := ""
var _physical_pads: Dictionary = {}
## Pressure pad id -> its StandSpot, in a chapter whose descriptor has
## "stand_spots"; _physical_pads holds the spot's rim.
var _stand_spots: Dictionary = {}
var _physical_levers: Dictionary = {}
## Levers and selectors built with a look: id -> its LeverLooks. Their
## _physical_levers entry is the look's anchor, which never tilts.
var _lever_looks: Dictionary = {}
var _physical_balls: Dictionary = {}
var _ball_trails: Dictionary = {}
var _ball_materials: Dictionary = {}
var _stair_gates: Dictionary = {}
var _weights: Dictionary = {}
var _hatches: Dictionary = {}
var _upper_islands: Array[Node3D] = []
var _active_player := "p0"
var _follow_center := Vector3.ZERO
var _follow_size := 9.2
var _completion_view := false
## Where the live spirit's turn ends (descriptor "goal_beacon"), or null.
var _goal_beacon: GoalBeacon
var _glance_left := 0.0
var _glance_target := Vector3.ZERO
## Tests may stand in a descriptor; otherwise the chapter's own.
var descriptor_override: Dictionary = {}

func load_level(definition: Dictionary) -> void:
	chapter_definition = definition.duplicate(true)
	displayed_stage_id = ""
	var first := _opening_stage(chapter_definition.get("stages", []))
	if not first.is_empty(): await show_stage(first)

func show_stage(stage: Dictionary) -> void:
	var stage_id := str(stage.get("id", ""))
	if stage_id.is_empty() or stage_id == displayed_stage_id: return
	var view := CooperativeCatalog.stage_definition(chapter_definition, stage_id)
	if view.is_empty(): return
	displayed_stage_id = stage_id
	_completion_view = false
	_goal_beacon = null
	_glance_left = 0.0
	_physical_pads.clear()
	_stand_spots.clear()
	_physical_levers.clear()
	_lever_looks.clear()
	_physical_balls.clear()
	_ball_trails.clear()
	_ball_materials.clear()
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
	await super.load_level(view)
	terrain.name = "CooperativeIslands"
	if is_instance_valid(_bell):
		_bell.get_parent().position.y = _surface_height(str(goal.surface_id))
		_court_light.position.y += _surface_height(str(goal.surface_id))
	await _build_step()
	for stair: Dictionary in view.get("stairs", []):
		_build_stair(stair)
		await _build_step()
	for pad: Dictionary in view.get("pressure_pads", []):
		_build_physical_pad(pad, false)
		await _build_step()
	for pad: Dictionary in view.get("ball_pads", []):
		_build_physical_pad(pad, true)
		await _build_step()
	for lever: Dictionary in view.get("levers", []):
		_build_lever(lever)
		await _build_step()
	for zone: Dictionary in view.get("access_zones", []):
		var r: Array = zone.rect_cm
		var zone_height := _surface_height(str(zone.surface_id))
		var color := GOLD if zone.owner_slot == "p0" else TEAL
		# The marks' tops (2 cm) stay under a spirit's ground shadow
		# (SpiritVisual.SHADOW_TOP), so the shadow never stripes on them.
		for x in range(int(r[0]) + 24, int(r[2]), 64):
			_ownership_mark(str(zone.owner_slot), Vector3(float(x) / 100.0, zone_height + 0.011, float(r[1] + r[3]) / 200.0), terrain)
		# A centimetre short of the zone's ends, so it never shares a face with
		# a flower bed or wall drawn exactly on a neighbouring rectangle.
		box(Vector3(float(r[2] - r[0]) / 100.0 - 0.01, 0.018, 0.035), color, Vector3(float(r[0] + r[2]) / 200.0, zone_height + 0.012, float(r[1]) / 100.0), terrain)
	for obstacle: Dictionary in view.get("obstacles", []):
		_build_obstacle(obstacle)
	await _build_step()
	for prop: Dictionary in physical_props:
		var ball := sphere(float(prop.radius_cm) / 100.0, Color("d08b56"), _at(prop), terrain)
		ball.name = str(prop.id)
		var band := ring(float(prop.radius_cm) / 100.0, Color("344b5c"), Vector3.ZERO, ball)
		band.scale.y = 2.4
		band.rotation.z = PI / 2.0
		_physical_balls[prop.id] = ball
		# The ball takes its holder's colour in place.
		_ball_materials[prop.id] = Primitives.own_material(ball)
		var blur := BallRotationBlur.new()
		blur.configure(self, ball, float(prop.radius_cm) / 100.0)
		terrain.add_child(blur)
		blur.set_quality(_motion_quality)
		_motion_trails.append(blur)
		_ball_trails[prop.id] = blur
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
	_build_goal_beacon(view)
	await _build_step()
	if _has_completion_garden(stage_id):
		garden = Node3D.new()
		garden.name = "HomeGarden"
		garden.position = _completion_garden_position(goal)
		garden.scale = _completion_garden_scale_vector()
		garden.set_meta("celebration_clear_point", Vector2(_at(goal).x, _at(goal).z))
		terrain.add_child(garden)
		# A warm planted bed in dressed chapters; the plain look keeps its slate disc.
		cylinder(1.45, 0.10, Color("a5845f") if not dressing.is_empty() else Color("617769"), Vector3(0, 0.01, 0), garden)
		cylinder(1.30, 0.02, Color("6b5240") if not dressing.is_empty() else Color("435b50"), Vector3(0, 0.06, 0), garden)
		goal_ring = null
		_create_garden()
	if is_instance_valid(camera_exploration): camera_exploration.maximum_pan = Vector2(1.2, 0.4)

## This chapter's descriptor (content/chapters/index.gd), or the test's.
func _descriptor() -> Dictionary:
	return descriptor_override if not descriptor_override.is_empty() else ChapterIndex.data(_chapter_key())

## The descriptor's "goal_beacon" marks where each turn of the stage ends
## (kit/goal_beacon.gd), built hidden: the screen shows it in live play.
func _build_goal_beacon(view: Dictionary) -> void:
	if not bool(_descriptor().get("goal_beacon", false)): return
	var spots: Dictionary = {}
	for role: String in ["a", "b"]:
		var slot := str(view.first_player_slot) if role == "a" else ("p0" if str(view.first_player_slot) == "p1" else "p1")
		spots[role] = GoalBeacon.spots_of(view, role).map(func(entity: Dictionary) -> Dictionary:
			var spot := {"at": _at(entity), "surface": str(entity.get("surface_id", "")), "slot": str(entity.get("owner_slot", slot))}
			# On a stand spot the beacon's ring breathes inside the spot; a seat
			# on the spot leaves it no room, and the spot and seat mark it.
			if _wears_stand_spot(view, entity):
				spot["inside"] = float(entity.radius_cm) / 100.0
				if _seated(str(entity.id)): spot["ring"] = false
			return spot)
	_goal_beacon = GoalBeacon.new()
	terrain.add_child(_goal_beacon)
	_goal_beacon.build(spots, {"p0": GOLD, "p1": TEAL})
	_goal_beacon.set_reduced_motion(reduced_motion)

## The screen shows the beacon only while a live turn plays.
func set_goal_beacon_live(on: bool) -> void:
	if is_instance_valid(_goal_beacon): _goal_beacon.set_live(on)

## Starts the turn's opening glance when the goal is off screen: the follow
## camera eases to the nearest end spot, looks, and eases back, on this
## world's clock (glancing()). Returns its length in seconds, or 0 when there
## is nothing to glance at, the camera does not follow, or motion is reduced.
func glance_at_goal() -> float:
	if reduced_motion or not _uses_scrolling_camera() or not is_instance_valid(_goal_beacon) or not _goal_beacon.shown() or not is_instance_valid(camera) or not actors.has(_active_player): return 0.0
	if _goal_beacon.on_screen(camera): return 0.0
	_glance_target = to_local(_goal_beacon.glance_point(actors[_active_player].global_position))
	_glance_left = GLANCE_TO + GLANCE_BACK
	return _glance_left

func glancing() -> bool:
	return _glance_left > 0.0

func end_glance() -> void:
	_glance_left = 0.0

## What the follow camera centres on: the live spirit, or the goal while the
## opening glance looks at it.
func _focus_point() -> Vector3:
	if _glance_left > GLANCE_BACK: return _glance_target
	return actors[_camera_slot(_active_player)].position

## The beacon shows and hides with play and changes nothing, so it never folds.
func _static_keep() -> Array:
	var keep := super._static_keep()
	if is_instance_valid(_goal_beacon): keep.append(_goal_beacon)
	# The parts of a look a pull moves stay whole; its frame folds.
	for look: RefCounted in _lever_looks.values(): keep.append_array(look.moving_parts())
	return keep

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

## Every physical chapter scrolls with a follow camera (in the Lighthouse's
## fit-all frame the spirits were tiny). The camera angle, and so the stick, is
## the Lighthouse's.
func _uses_scrolling_camera() -> bool:
	return true

func _shore(island: Dictionary, color: Color) -> void:
	var original := terrain
	var raised := Node3D.new()
	raised.position.y = float(island.get("height_cm", 0)) / 100.0
	original.add_child(raised)
	_surface_nodes[str(island.id)] = raised
	if raised.position.y > 0.5: _upper_islands.append(raised)
	terrain = raised
	var hole: Dictionary = {}
	for drop: Dictionary in current_level.get("drops", []):
		if drop.surface_id == island.id: hole = drop
	if hole.is_empty():
		super._shore(island, color)
	else:
		# Four authored floor pieces leave an actual opening; no dark decal.
		for cut: Array in Primitives.rect_minus_hole(island.rect_cm, hole.rect_cm):
			super._shore({"id": island.id, "rect_cm": cut}, color)
	terrain = original
	raised.set_meta("bounds", island.rect_cm.duplicate())
	_surface_built(island, raised)

func _surface_built(_island: Dictionary, _surface: Node3D) -> void:
	pass

## Floors are held to build their markers and pieces on (_surface_nodes) and
## never move; only a raised floor fades (_upper_islands, the cutaway). Every
## other floor's plain pieces fold with the scenery around them.
func _still_held() -> Array:
	return super._still_held() + _surface_nodes.values().filter(func(surface: Variant) -> bool: return is_instance_valid(surface) and surface not in _upper_islands)

## Physical chapters celebrate a completed stage in present(), not the
## Lighthouse objective.
func _present_celebration(_immediate: bool) -> void:
	pass

## Physical chapters frame with their own fit or scrolling camera.
func _follows_stage(_stage_id: String) -> bool:
	return false

func _chapter_key() -> String:
	return "%s@%d" % [str(chapter_definition.get("id", "")), int(chapter_definition.get("version", 1))]

func _dressing_stage_id() -> String:
	return displayed_stage_id

func _surface_base(surface_id: String) -> float:
	return _surface_height(surface_id)

func _set_cutaway(node: Node, faded: bool) -> void:
	# Recurses through this method so leaves can extend each mesh (glass).
	if node is MeshInstance3D and node.material_override is StandardMaterial3D:
		if not Cutaway.fade_mesh(node, faded): return
	for child: Node in node.get_children(): _set_cutaway(child, faded)

func _build_obstacle(obstacle: Dictionary) -> void:
	var r: Array = obstacle.rect_cm
	var at := point([(r[0] + r[2]) * 0.5, (r[1] + r[3]) * 0.5])
	at.y = _surface_height(str(obstacle.surface_id))
	if str(dressing.get("obstacles", "")) == "flowerbed":
		_flowerbed(r, at)
		return
	box(Vector3(float(r[2] - r[0]) / 100.0, 0.35, float(r[3] - r[1]) / 100.0), Color("718b79"), at + Vector3(0, 0.175, 0), terrain)
	for x in range(int(r[0]) + 18, int(r[2]), 35):
		var tuft := sphere(0.21, Color("8dad95"), Vector3(float(x) / 100.0, at.y + 0.4, at.z), terrain)
		tuft.scale = Vector3(0.7, 0.6, 1)

## A raised timber flower bed exactly on the obstacle's collision rectangle.
func _flowerbed(r: Array, at: Vector3) -> void:
	var width := float(r[2] - r[0]) / 100.0
	var depth := float(r[3] - r[1]) / 100.0
	box(Vector3(width, 0.30, depth), Props.TIMBER, at + Vector3(0, 0.15, 0), terrain)
	box(Vector3(width - 0.08, 0.03, depth - 0.08), Color("6b5240"), at + Vector3(0, 0.30, 0), terrain)
	var index := 0
	for x in range(int(r[0]) + 20, int(r[2]), 30):
		for z in range(int(r[1]) + 20, int(r[3]), 30):
			var leaf := sphere(0.13, Props.LEAF if index % 2 == 0 else Props.LEAF_LIGHT, Vector3(float(x) / 100.0, at.y + 0.38, float(z) / 100.0), terrain)
			leaf.scale = Vector3(1.0, 0.75, 1.0)
			if index % 3 == 1: sphere(0.05, Props.BLOSSOMS[index % Props.BLOSSOMS.size()], Vector3(float(x) / 100.0 + 0.04, at.y + 0.48, float(z) / 100.0 + 0.03), terrain)
			index += 1

func _build_bridge(definition: Dictionary) -> void:
	super._build_bridge(definition)
	var rect: Array = definition.rect_cm
	var owner := str(definition.get("owner_slot", ""))
	var at := point([rect[0], (rect[1] + rect[3]) * 0.5])
	if not owner.is_empty() and _marks_route_owner(definition):
		_ownership_mark(owner, at + Vector3(-0.18, ROUTE_MARK_LIFT, 0), terrain)
		_ownership_mark(owner, point([rect[2] + 18, (rect[1] + rect[3]) * 0.5]) + Vector3(0, ROUTE_MARK_LIFT, 0), terrain)
	if not _hangs_pulley(definition): return
	# A fixed pulley and suspended weight show where a missing crossing goes.
	var post := at + Vector3(0.05, 0, float(rect[3] - rect[1]) / 200.0 + 0.15)
	box(Vector3(0.10, 1.1, 0.1), Color("9e9180"), post + Vector3(0, 0.55, 0), terrain)
	var pulley := ring(0.13, GOLD, post + Vector3(0, 1.1, 0), terrain)
	pulley.rotation.x = PI / 2.0
	box(Vector3(0.025, 1.2, 0.025), CREAM, post + Vector3(0.14, 0.45, 0), terrain)
	var warm := not dressing.is_empty()
	var weight := box(Vector3(0.22, 0.32, 0.22), Props.STONE_DARK if warm else Color("748998"), post + Vector3(0.14, 0.45, 0), terrain)
	_weights[definition.id] = weight
	weight.set_meta("rest_y", weight.position.y)

## Whether an owned crossing gets an ownership mark at each end. A world that
## shows its owner some other way says no, so no mark is made only to be freed.
func _marks_route_owner(_definition: Dictionary) -> bool:
	return true

## Whether a crossing gets the fixed pulley and suspended weight that show
## where a missing crossing goes (they are _weights). A world that shows it
## some other way says no.
func _hangs_pulley(_definition: Dictionary) -> bool:
	return true

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
		var timber := str(dressing.get("stairs", "")) == "timber"
		var tread := (Props.TIMBER_LIGHT if index % 2 == 0 else Props.TIMBER_LIGHT.darkened(0.06)) if timber else Color("b4c5bd")
		box(Vector3(width / 10.0 if along_x else width, 0.12, depth if along_x else depth / 10.0), tread, at, terrain)
		box(Vector3(0.025 if along_x else width, 0.014, depth if along_x else 0.025), Props.TIMBER_DARK if timber else TEAL, at + Vector3(0, 0.065, 0), terrain)
	if str(dressing.get("stairs", "")) == "timber": _stair_frame(r, from_height, rise, along_x)
	var entrance := point([r[0], (r[1] + r[3]) * 0.5] if along_x else [(r[0] + r[2]) * 0.5, r[1]]) + Vector3(0, from_height, 0)
	_ownership_mark(str(stair.owner_slot), entrance + (Vector3(-0.24, 0.03, 0) if along_x else Vector3(0, 0.03, -0.24)), terrain)
	# The gate is a centimetre wider than the stair, so its faces stand proud
	# of the treads' instead of sharing them.
	_stair_gates[stair.id] = box(Vector3(0.08, 0.4, depth + 0.01) if along_x else Vector3(width + 0.01, 0.4, 0.08), TEAL, entrance + Vector3(0, 0.2, 0), terrain)

## Wooden stringers under both sides and a handrail along the far side; the
## walkable treads stay exactly the authored rectangle.
func _stair_frame(r: Array, from_height: float, rise: float, along_x: bool) -> void:
	for side: float in ([float(r[1]) / 100.0 - 0.03, float(r[3]) / 100.0 + 0.03] if along_x else [float(r[0]) / 100.0 - 0.03, float(r[2]) / 100.0 + 0.03]):
		var start := Vector3(float(r[0]) / 100.0, from_height - 0.10, side) if along_x else Vector3(side, from_height - 0.10, float(r[1]) / 100.0)
		var finish := Vector3(float(r[2]) / 100.0, from_height + rise - 0.10, side) if along_x else Vector3(side, from_height + rise - 0.10, float(r[3]) / 100.0)
		Primitives.bar_between(start, finish, 0.07, Primitives.shared_material(Props.TIMBER), terrain)
	var rail := float(r[1]) / 100.0 - 0.04 if along_x else float(r[0]) / 100.0 - 0.04
	var foot := Vector3(float(r[0]) / 100.0, from_height + 0.62, rail) if along_x else Vector3(rail, from_height + 0.62, float(r[1]) / 100.0)
	var head := Vector3(float(r[2]) / 100.0, from_height + rise + 0.62, rail) if along_x else Vector3(rail, from_height + rise + 0.62, float(r[3]) / 100.0)
	Primitives.bar_between(foot, head, 0.04, Primitives.shared_material(Props.TIMBER_DARK), terrain)
	for t: float in [0.0, 0.5, 1.0]:
		var top := foot.lerp(head, t)
		Primitives.mesh_node(Primitives.shared_mesh("box", 0.035, 0.62, 0.035), Primitives.shared_material(Props.TIMBER_DARK), top - Vector3(0, 0.31, 0), terrain)

## Whether `entity` is one of the stage's pressure pads and the chapter
## marks them with stand spots (descriptor "stand_spots").
func _wears_stand_spot(view: Dictionary, entity: Dictionary) -> bool:
	if not bool(_descriptor().get("stand_spots", false)): return false
	for pad: Dictionary in view.get("pressure_pads", []):
		if pad.id == entity.get("id"): return true
	return false

## Whether a seat prop stands on pad `pad_id` (journey_world's "seats").
func _seated(_pad_id: String) -> bool:
	return false

func _build_physical_pad(pad: Dictionary, heavy: bool) -> void:
	var at := _at(pad)
	var color := GOLD if heavy or pad.get("owner_slot", "") == "p0" else TEAL
	if not heavy and bool(_descriptor().get("stand_spots", false)):
		_build_stand_spot(pad, at, color)
		return
	cylinder(float(pad.radius_cm) / 100.0, 0.055, color.darkened(0.25), at + Vector3(0, 0.025, 0), terrain)
	var outline := ring(float(pad.radius_cm) / 100.0, color, at + Vector3(0, 0.065, 0), terrain)
	_physical_pads[pad.id] = outline
	if heavy:
		ring(0.16, CREAM, at + Vector3(0, 0.06, 0), terrain)
	else: _ownership_mark(str(pad.owner_slot), at + Vector3(0, 0.06, 0), terrain)

## A pressure pad drawn as a stand spot (kit/stand_spot.gd): exactly the pad's
## radius, with the owner's mark on its disc.
func _build_stand_spot(pad: Dictionary, at: Vector3, color: Color) -> void:
	var spot := StandSpot.new()
	terrain.add_child(spot)
	spot.build(at, float(pad.radius_cm) / 100.0, str(pad.owner_slot), color, LIGHT_COLOR)
	spot.name = "StandSpot_" + str(pad.id)
	_physical_pads[pad.id] = spot.rim
	_stand_spots[pad.id] = spot

## A valve look's dial marks for a selector (kit/lever_looks.gd): per value,
## how many bands; one each by default.
func _look_marks(control: Dictionary) -> Array:
	return Array(control.get("values", [])).map(func(_value: Variant) -> int: return 1)

func _build_lever(lever: Dictionary) -> void:
	var at := _at(lever)
	var look_kind := str(_descriptor().get("lever_looks", {}).get(str(lever.id), ""))
	if look_kind in (LeverLooks.SELECTOR_KINDS if str(lever.get("kind", "")) == "selector" else LeverLooks.LEVER_KINDS):
		var look := LeverLooks.build(look_kind, at, GOLD if lever.owner_slot == "p0" else TEAL, terrain, _look_marks(lever))
		_lever_looks[lever.id] = look
		_physical_levers[lever.id] = look.anchor
		_ownership_mark(str(lever.owner_slot), at + Vector3(0, 0.025, 0.33), terrain)
		return
	cylinder(0.18, 0.2, Color("728788"), at + Vector3(0, 0.1, 0), terrain)
	var pivot := Node3D.new()
	pivot.position = at + Vector3(0, 0.2, 0)
	terrain.add_child(pivot)
	box(Vector3(0.055, 0.40, 0.055), CREAM, Vector3(0, 0.2, 0), pivot)
	sphere(0.09, GOLD if lever.owner_slot == "p0" else TEAL, Vector3(0, 0.4, 0), pivot)
	_physical_levers[lever.id] = pivot
	_ownership_mark(str(lever.owner_slot), at + Vector3(0, 0.025, 0.33), terrain)

## An ownership diamond's side. Turned 45 degrees, it reaches MARK_REACH from
## its centre along x and z; anything meeting a mark at its height stops there.
const MARK_SIDE := 0.17
const MARK_REACH := MARK_SIDE * 0.7072
const MARK_THICKNESS := 0.018
## A route's end marks sit this high (centres) above the route.
const ROUTE_MARK_LIFT := 0.025
## Gate links: cables this wide, their centres and tags this high.
const LINK_WIDTH := 0.025
const LINK_LIFT := 0.03
## A route's end tag lies on the route's mark and under a cable that meets it
## there, so its top sits midway between their tops.
const LINK_TAG_THICKNESS := (ROUTE_MARK_LIFT + MARK_THICKNESS * 0.5) + (LINK_LIFT + LINK_WIDTH * 0.5) - 2.0 * LINK_LIFT

func _ownership_mark(slot: String, at: Vector3, parent: Node3D) -> void:
	# Shape repeats on spirit-specific routes and controls, alongside color.
	if slot == "p0":
		var diamond := box(Vector3(MARK_SIDE, MARK_THICKNESS, MARK_SIDE), GOLD, at, parent)
		diamond.rotation.y = PI / 4.0
	else:
		ring(0.13, TEAL, at, parent)

func _build_gate_links(view: Dictionary) -> void:
	if str(dressing.get("cables", "")) == "floor":
		_build_floor_links(view)
		return
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

## Gate links that never cross the void: a cable runs along a floor the
## mechanism and its route share; otherwise matching tags mark both ends.
func _build_floor_links(view: Dictionary) -> void:
	for gate: Dictionary in view.get("gates", []):
		var route: Dictionary = {}
		for candidate: Dictionary in view.bridges + view.get("stairs", []):
			if candidate.id == gate.route_id: route = candidate
		if route.is_empty(): continue
		var rect: Array = route.rect_cm
		var end := point([rect[0], (rect[1] + rect[3]) * 0.5]) + Vector3(-0.18, float(route.get("height_cm", route.get("from_height_cm", 0))) / 100.0 + LINK_LIFT, 0)
		for mechanism: Dictionary in view.get("pressure_pads", []) + view.get("ball_pads", []) + view.get("levers", []):
			if mechanism.id not in [gate.get("pad_id", ""), gate.get("lever_id", ""), gate.get("second_lever_id", ""), gate.get("ball_pad_id", "")]: continue
			var link_color := _gate_link_color(mechanism)
			var start := _at(mechanism) + Vector3(0, LINK_LIFT, 0)
			var elbow := Vector3(end.x, start.y, start.z)
			if _shares_floor(start, elbow) and _shares_floor(elbow, end):
				if start.distance_to(elbow) > 0.01: _bar_between(start, elbow, LINK_WIDTH, link_color, terrain)
				if elbow.distance_to(end) > 0.01: _bar_between(elbow, end, LINK_WIDTH, link_color, terrain)
			else:
				_link_tag(start + Vector3(0.36, 0, 0), link_color)
				_link_tag(end, link_color)

## A pair of tags at a gate link's end (LINK_TAG_THICKNESS).
func _link_tag(at: Vector3, color: Color) -> void:
	for index in range(2):
		var tag := box(Vector3(0.07, LINK_TAG_THICKNESS, 0.18), color, at + Vector3((float(index) - 0.5) * 0.12, 0, 0), terrain)
		tag.name = "GateLinkTag"

## Both points lie on one walkable island at the same height.
func _shares_floor(a: Vector3, b: Vector3) -> bool:
	if absf(a.y-b.y)>0.05: return false
	for island: Dictionary in chapter_definition.islands:
		var r: Array = island.rect_cm
		if absf(float(island.get("height_cm", 0)) / 100.0 - (a.y - 0.03)) > 0.06 and absf(float(island.get("height_cm", 0)) / 100.0 - (a.y - 0.025)) > 0.06: continue
		if a.x*100>=r[0] and a.x*100<=r[2] and a.z*100>=r[1] and a.z*100<=r[3] and b.x*100>=r[0] and b.x*100<=r[2] and b.z*100>=r[1] and b.z*100<=r[3]: return true
	return false

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
	# This adapter adds missing top-level fields; nested simulation values are
	# read-only throughout the shared renderer.
	var visual := state.duplicate()
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
		var material := _ball_materials[id] as StandardMaterial3D
		material.albedo_color = GOLD if holder == "p0" else TEAL if holder == "p1" else CREAM
		var target := Vector3(float(prop.x) / 100.0, float(prop.get("height", 0)) / 100.0 + 0.2, float(prop.z) / 100.0)
		if not immediate:
			var displacement: Vector3 = target - _physical_balls[id].position
			_physical_balls[id].rotate_x(displacement.z / 0.2)
			_physical_balls[id].rotate_z(-displacement.x / 0.2)
		_physical_balls[id].position = target
		var trail: Node3D = _ball_trails[id]
		trail.tint = material.albedo_color
		trail.set_motion_allowed(str(prop.get("status", "")) == "free" and str(prop.get("socket_id", "")).is_empty(), immediate)
	for id: String in _physical_levers:
		if _lever_looks.has(id): _lever_looks[id].set_pulled(bool(state.get("levers", {}).get(id, false)), immediate or reduced_motion)
		else: _physical_levers[id].rotation.z = -0.6 if state.get("levers", {}).get(id, false) else 0.6
	for id: String in _hatches: _hatches[id].visible = not state.get("levers", {}).get(id, false)
	for id: String in _physical_pads:
		var pressed: bool = state.get("hold_pads", {}).get(id, false)
		_glow(_physical_pads[id], LIGHT_COLOR, 1.0 if pressed else 0.0)
		if _stand_spots.has(id): _stand_spots[id].set_held(pressed)
	for id: String in _stair_gates: _stair_gates[id].visible = not state.get("bridges", {}).get(id, false)
	for id: String in _weights:
		_weights[id].position.y = float(_weights[id].get_meta("rest_y")) - (0.7 if state.get("bridges", {}).get(id, false) else 0.0)
	if is_instance_valid(_goal_beacon): _goal_beacon.present(state)
	if immediate:
		if actors.has(_active_player): _follow_center = _camera_center()
		_follow_size = 10.6 if _completion_view else 9.2
		_frame_camera()

func _should_cutaway(raised: Node3D, state: Dictionary) -> bool:
	return _uses_lower_cutaway() and _below_raised(raised,state.players[_active_player])

func _below_raised(raised: Node3D, player: Dictionary) -> bool:
	return Cutaway.below_raised(raised, player)

func _camera_center() -> Vector3:
	var target := _focus_point()
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
	for id: String in _lever_looks:
		if _lever_looks[id].moving(): _lever_looks[id].advance(delta)
	if _uses_scrolling_camera():
		# Authored framing advances once per rendered frame. Snapshot delivery
		# and pinch zoom must never feed back into the follow state.
		var rate := 8.0
		if _glance_left > 0.0:
			_glance_left = maxf(_glance_left - delta, 0.0)
			rate = 3.5 if _glance_left > GLANCE_BACK else 6.0
		var weight := 1.0 if reduced_motion else 1.0 - exp(-rate * maxf(delta, 0.0))
		if actors.has(_active_player): _follow_center = _follow_center.lerp(_camera_center(), weight)
		_follow_size = lerpf(_follow_size, 10.6 if _completion_view else 9.2, weight)
		_follow_motes()
	_frame_camera()
	if is_instance_valid(_goal_beacon): _goal_beacon.follow(camera)

## Motes are authored around the origin; a scrolling camera carries them along
## so the far end of a long chapter keeps its drifting specks. Each mote keeps
## its own spot on a repeating 23 m strip, so nothing slides with the view.
func _follow_motes() -> void:
	for mote: MeshInstance3D in motes:
		if not mote.has_meta("rest_x"): mote.set_meta("rest_x", mote.position.x)
		mote.position.x = _follow_center.x + wrapf(float(mote.get_meta("rest_x")) - _follow_center.x, -11.5, 11.5)

func _frame_camera() -> void:
	if not _uses_scrolling_camera():
		super._frame_camera()
		return
	if not is_instance_valid(camera): return
	camera.position = _follow_center + Vector3(3, 13, 10)
	camera.look_at(to_global(_follow_center))
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = ViewFit.viewport(_follow_size, self)
	camera.h_offset = 0
	camera.v_offset = 0.2
