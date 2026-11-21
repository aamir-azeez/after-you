extends "res://presentation/lighthouse_world.gd"
## Physical chapter scenery reuses Lighthouse terrain, bridges, bells and spirits.
## All movement, ownership and gate decisions come from the simulation snapshot.
const CooperativeCatalog = preload("res://core/cooperative/stage_catalog.gd")
const BallRotationBlur = preload("res://presentation/ball_rotation_blur.gd")
const Cutaway = preload("res://presentation/kit/cutaway.gd")
const GoalBeacon = preload("res://presentation/kit/goal_beacon.gd")
const OpenTurns = preload("res://core/physical/open_turns.gd")
## Pads, levers and selectors in their styles (content/dressing/piece_styles.gd).
const PadPiece = preload("res://presentation/kit/pieces/pad.gd")
const LeverPiece = preload("res://presentation/kit/pieces/lever.gd")
const SelectorPiece = preload("res://presentation/kit/pieces/selector.gd")
## The pulley post by a missing crossing, in its style (_hang_pulleys).
const PulleyPiece = preload("res://presentation/kit/pieces/pulley.gd")
## The new pieces' looks (rules 16): decks, platforms, ladders and fog.
const NewPieces = preload("res://presentation/kit/new_pieces.gd")
## The opening glance at the goal (glance_at_goal): this long easing there and
## looking, then this long easing back to the spirit.
const GLANCE_TO := 1.6
const GLANCE_BACK := 0.6
var chapter_definition: Dictionary = {}
var _physical_pads: Dictionary = {}
## Cables and ropes laid on the floors this stage (_floor_cable).
var _floor_cables: Array = []
var _physical_levers: Dictionary = {}
## Lever and selector id -> its piece (kit/pieces/lever.gd, selector.gd);
## _physical_levers holds its anchor.
var _lever_pieces: Dictionary = {}
var _physical_balls: Dictionary = {}
var _ball_trails: Dictionary = {}
var _ball_materials: Dictionary = {}
var _weights: Dictionary = {}
## Crossing id -> its pulley post (kit/pieces/pulley.gd); its weight is in _weights.
var _pulleys: Dictionary = {}
## Crossings a gate link's cable or rope runs to this stage: the cable shows
## why they open, so they hang no pulley (_hangs_pulley).
var _cabled: Dictionary = {}
var _hatches: Dictionary = {}
var _upper_islands: Array[Node3D] = []
## Where the live spirit's turn ends (descriptor "goal_beacon"), or null.
var _goal_beacon: GoalBeacon
var _glance_left := 0.0
var _glance_target := Vector3.ZERO
## Tests may stand in a descriptor; otherwise the chapter's own.
var descriptor_override: Dictionary = {}
## Ball id -> radius (m), for the barriers' lock rings (_build_barrier_extras).
var _ball_radii: Dictionary = {}
## This stage's new pieces' looks (kit/new_pieces.gd), or null before a stage.
var new_pieces: RefCounted
## Where the stage's pips have been (kit/turn_paths.gd), for a fog cover that
## stays open where they walked; it outlives a stage's rebuilt pieces.
const TurnPaths = preload("res://presentation/kit/turn_paths.gd")
var turn_paths := TurnPaths.new()
## Spirit slot -> the floor the snapshot has it on, and [the deck that carried
## it, where that deck stood] as of the last frame it rode (kit/new_pieces.gd ride).
var _floors: Dictionary = {}
var _rode: Dictionary = {}
## How far inside a deck's edge (m) a pip that stepped off it waits (_carry).
const DECK_EDGE := 0.2

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
	pad_pieces.clear()
	_floor_cables.clear()
	_physical_levers.clear()
	_lever_pieces.clear()
	_physical_balls.clear()
	_ball_trails.clear()
	_ball_materials.clear()
	_weights.clear()
	_pulleys.clear()
	_cabled.clear()
	_hatches.clear()
	_upper_islands.clear()
	_ball_radii.clear()
	_clear_stage_marks()
	# These are presentation defaults for the shared Lighthouse builder.
	_configure_shared_view(view)
	new_pieces = NewPieces.new(self, view)
	var physical_props: Array = view.get("props", []).duplicate(true)
	view["props"] = []
	var goal: Dictionary = view.goal.duplicate(true)
	if view.goal_policy.kind == "ball_home": view.erase("goal")
	await super.load_level(view)
	terrain.name = "CooperativeIslands"
	if is_instance_valid(_bell):
		_goal_piece.root.position.y = _surface_height(str(goal.surface_id))
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
	var lanterns: Dictionary = {}
	for lever: Dictionary in view.get("levers", []):
		if _piece_style("lever", str(lever.id)) == "lantern": lanterns[str(lever.id)] = _at(lever)
	new_pieces.build(lanterns)
	new_pieces.set_quality(graphics_quality())
	new_pieces.show_paths(turn_paths)
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
	await _hang_pulleys(view)
	_build_goal_beacon(view)
	# Gates, chains, zone edges and locks, before the marks, which keep clear
	# of them (_pair_keep_clear). A chapter whose world draws every closed
	# stair itself says so in its descriptor ("stair_gates": false).
	if not bool(_descriptor().get("stair_gates", true)):
		for stair: Dictionary in view.get("stairs", []): route_barriers.skip(str(stair.id), "the descriptor's stair_gates is false")
	for prop: Dictionary in physical_props: _ball_radii[str(prop.id)] = float(prop.radius_cm) / 100.0
	# The tags lay themselves out when first shown, after every world's own
	# building is done, clear of all of it (the ball's cradle included).
	var tag_view := view.duplicate()
	tag_view["goal"] = goal
	_build_stage_marks(view, tag_view)
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

## A piece's style, its descriptor's pin first (content/dressing/piece_styles.gd).
func _piece_style(slot: String, id: String) -> String:
	return PieceStyles.style(slot, id, _descriptor(), dressing)

## The descriptor's "goal_beacon" marks where each turn of the stage ends
## (kit/goal_beacon.gd), built hidden: the screen shows it in live play. Every
## open turns chapter gets it as a late guide (GoalBeacon.guide).
func _build_goal_beacon(view: Dictionary) -> void:
	var guide := OpenTurns.pinned(chapter_definition)
	if not guide and not bool(_descriptor().get("goal_beacon", false)): return
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
	_goal_beacon.guide = guide
	terrain.add_child(_goal_beacon)
	_goal_beacon.build(spots, {"p0": GOLD, "p1": TEAL})
	_goal_beacon.set_reduced_motion(reduced_motion)

## The screen shows the beacon only while a live turn plays; the open turns
## guide never shows in a hard run.
func set_goal_beacon_live(on: bool, hard: bool = false) -> void:
	if is_instance_valid(_goal_beacon): _goal_beacon.set_live(on and not (hard and _goal_beacon.guide))

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

## The goal while the opening glance looks at it, else the live spirit.
func _focus_point() -> Vector3:
	if _glance_left > GLANCE_BACK: return _glance_target
	return super._focus_point()

## The beacon shows and hides with play and changes nothing, so it never folds.
func _static_keep() -> Array:
	var keep := super._static_keep()
	if is_instance_valid(_goal_beacon): keep.append(_goal_beacon)
	# The parts of a piece that move, light or change stay whole; the rest folds.
	for piece: RefCounted in _lever_pieces.values(): keep.append_array(piece.moving_parts())
	for piece: RefCounted in _pulleys.values(): keep.append_array(piece.moving_parts())
	if new_pieces != null: keep.append_array(new_pieces.moving_nodes())
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

## Every physical chapter scrolls with the follow camera (island_world's; in
## the Lighthouse's fit-all frame the spirits were tiny).
func _uses_scrolling_camera() -> bool:
	return true

## The physical chapters scroll their camera's centre between x -3.2 and 12,
## on the z axis; a level whose follow data follows across and in depth
## ("axes": "xz") keeps inside its own floors.
func _follow_limits() -> Array[Vector2]:
	if str(_follow_data().get("axes", "x")) == "xz": return _floors_follow_limits()
	return [Vector2(-3.2, 0.0), Vector2(12.0, 0.0)]

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
	if Cutaway.hides(node, faded): return
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
	if str(dressing.get("obstacles", "")) == "post":
		_post(r, at)
		return
	box(Vector3(float(r[2] - r[0]) / 100.0, 0.35, float(r[3] - r[1]) / 100.0), Color("718b79"), at + Vector3(0, 0.175, 0), terrain)
	for x in range(int(r[0]) + 18, int(r[2]), 35):
		var tuft := sphere(0.21, Color("8dad95"), Vector3(float(x) / 100.0, at.y + 0.4, at.z), terrain)
		tuft.scale = Vector3(0.7, 0.6, 1)

## A timber post exactly on the obstacle's collision rectangle, standing up to
## the underside of the raised floor over it (its 20 cm deep planks), else
## 1.2 m: the solid leg of a balcony.
func _post(r: Array, at: Vector3) -> void:
	var top := INF
	for island: Dictionary in current_level.get("islands", []):
		var o: Array = island.rect_cm
		var height := float(island.get("height_cm", 0)) / 100.0
		if height > at.y + 0.5 and o[0] <= r[0] and o[2] >= r[2] and o[1] <= r[1] and o[3] >= r[3]: top = minf(top, height - 0.20)
	if top == INF: top = at.y + 1.2
	var size := float(mini(int(r[2] - r[0]), int(r[3] - r[1]))) / 11.0
	var post := Props.build({"kind": "post", "size": size, "height": int(round((top - at.y) * 100.0))}, terrain, at.y, bool(dressing.get("lit", true)))
	post.position = Vector3(at.x, at.y, at.z)
	# An obstacle, not dressing: the dressing lint counts props by this mark.
	post.remove_meta("dressing_kind")

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

## A pulley post by each crossing that needs one (_hangs_pulley), in its style
## (kit/pieces/pulley.gd), at its west end on the camera's side and at its
## deck's height. Its weight hangs while the crossing is gone and drops while
## it is laid, so the post shows where a missing crossing goes. Built after
## the gate links, which say which crossings a cable already explains. The
## post is told the floors at its foot, so what lies there stays on them.
func _hang_pulleys(view: Dictionary) -> void:
	var floors: Array = RouteBarriers.floors_of(view).filter(func(f: Dictionary) -> bool: return not f.crossing)
	for definition: Dictionary in view.get("bridges", []):
		if not _hangs_pulley(definition): continue
		var id := str(definition.id)
		var rect: Array = definition.rect_cm
		var deck: Node3D = _decks.get(definition.id)
		var post := point([rect[0], rect[3]]) + Vector3(0.05, deck.position.y if deck != null else 0.0, 0.15)
		var ground: Array[Rect2] = []
		for f: Dictionary in floors:
			if absf(float(f.y) - post.y) < 0.02: ground.append(Rect2((f.rect as Rect2).position - Vector2(post.x, post.z), (f.rect as Rect2).size))
		var piece: RefCounted = PulleyPiece.build(_piece_style("pulley", id), post, terrain, ground)
		_pulleys[id] = piece
		_weights[id] = piece.weight
		piece.weight.set_meta("rest_y", piece.weight.position.y)
		await _build_step()

## A world that builds walls in front of its pulley posts after them gives
## them here (terrain space, kit/water_bodies.gd standing_walls): a post's coil the
## camera cannot see past them is left out (kit/pieces/pulley.gd).
func drop_unseen_coils(blockers: Array[AABB]) -> void:
	for piece: RefCounted in _pulleys.values(): piece.drop_unseen(blockers)

## Whether a crossing gets a pulley post: only where nothing else shows why
## it comes and goes. One rule for every world; a world that shows it some
## other way (Tide's gauges) says no as well.
func _hangs_pulley(definition: Dictionary) -> bool:
	# A new piece's deck (a rope, stones, the path behind the falls, a platform) is its own cause.
	if new_pieces != null and new_pieces.lays(definition): return false
	# A cable or rope runs to it from the pad or lever that opens it.
	if _cabled.has(str(definition.get("id", ""))): return false
	# A crossing only one pip may use has a little gate in its colour at its ends.
	var owner := str(definition.get("owner_slot", ""))
	if owner in ["p0", "p1"] and not RouteBarriers.mouths_of(definition, RouteBarriers.floors_of(current_level)).is_empty(): return false
	return true

## A new piece lays its own deck (kit/new_pieces.gd); every other crossing
## keeps the Lighthouse planks.
func _lay_deck(definition: Dictionary, deck: Node3D, width: float, depth: float, across_x: bool, low: float, high: float) -> void:
	if new_pieces != null and new_pieces.lays(definition): new_pieces.lay_deck(definition, deck, width, depth, across_x, low, high)
	else: super._lay_deck(definition, deck, width, depth, across_x, low, high)

func _build_stair(stair: Dictionary) -> void:
	# A one way stair is a pull-up rope ladder (rules 16).
	if stair.has("one_way") and new_pieces != null:
		new_pieces.build_ladder(stair)
		return
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
	# A closed stair's gate (posts, bar and chain at its foot and head) is the
	# route barriers' (kit/route_barriers.gd).

## Wooden stringers under both sides and a handrail along the far side, or,
## when the dressing asks for "stair_rail": "open", along the near side where
## a raised floor stands against the far one (its side is the wall there;
## the rail goes on the open drop); the walkable
## treads stay exactly the authored rectangle.
func _stair_frame(r: Array, from_height: float, rise: float, along_x: bool) -> void:
	for side: float in ([float(r[1]) / 100.0 - 0.03, float(r[3]) / 100.0 + 0.03] if along_x else [float(r[0]) / 100.0 - 0.03, float(r[2]) / 100.0 + 0.03]):
		var start := Vector3(float(r[0]) / 100.0, from_height - 0.10, side) if along_x else Vector3(side, from_height - 0.10, float(r[1]) / 100.0)
		var finish := Vector3(float(r[2]) / 100.0, from_height + rise - 0.10, side) if along_x else Vector3(side, from_height + rise - 0.10, float(r[3]) / 100.0)
		Primitives.bar_between(start, finish, 0.07, Primitives.shared_material(Props.TIMBER), terrain)
	var walled := str(dressing.get("stair_rail", "")) == "open" and _floor_against_far_side(r, maxf(from_height, from_height + rise), along_x)
	var rail := (float(r[3]) / 100.0 + 0.04 if walled else float(r[1]) / 100.0 - 0.04) if along_x else (float(r[2]) / 100.0 + 0.04 if walled else float(r[0]) / 100.0 - 0.04)
	var foot := Vector3(float(r[0]) / 100.0, from_height + 0.62, rail) if along_x else Vector3(rail, from_height + 0.62, float(r[1]) / 100.0)
	var head := Vector3(float(r[2]) / 100.0, from_height + rise + 0.62, rail) if along_x else Vector3(rail, from_height + rise + 0.62, float(r[3]) / 100.0)
	Primitives.bar_between(foot, head, 0.04, Primitives.shared_material(Props.TIMBER_DARK), terrain)
	for t: float in [0.0, 0.5, 1.0]:
		var top := foot.lerp(head, t)
		Primitives.mesh_node(Primitives.shared_mesh("box", 0.035, 0.62, 0.035), Primitives.shared_material(Props.TIMBER_DARK), top - Vector3(0, 0.31, 0), terrain)

## Whether a floor at the stair's top height runs along its far side (north
## of an x stair, west of a z one) within 40 cm, overlapping its length.
func _floor_against_far_side(r: Array, top: float, along_x: bool) -> bool:
	for island: Dictionary in current_level.get("islands", []):
		var o: Array = island.rect_cm
		if float(island.get("height_cm", 0)) / 100.0 < top - 0.1 or top < 0.5: continue
		if along_x and o[0] < r[2] and o[2] > r[0] and o[3] <= r[1] and o[3] >= r[1] - 40: return true
		if not along_x and o[1] < r[3] and o[3] > r[1] and o[2] <= r[0] and o[2] >= r[0] - 40: return true
	return false

## Whether `entity` is one of the stage's pressure pads drawn as a stand spot.
func _wears_stand_spot(view: Dictionary, entity: Dictionary) -> bool:
	for pad: Dictionary in view.get("pressure_pads", []):
		if pad.id == entity.get("id"): return _piece_style("pad", str(pad.id)) == "stand_spot"
	return false

## Whether a seat prop stands on pad `pad_id` (journey_world's "seats").
func _seated(_pad_id: String) -> bool:
	return false

## A pressure pad or a ball pad (heavy, always plain) in its style
## (kit/pieces/pad.gd), in pad_pieces (island_world's), whose stand spots
## record their owner's marks with the stage's (_build_stage_marks).
func _build_physical_pad(pad: Dictionary, heavy: bool) -> void:
	var style := "plain" if heavy else _piece_style("pad", str(pad.id))
	var piece: RefCounted = PadPiece.build(style, _at(pad), float(pad.radius_cm) / 100.0, terrain, {"owner": str(pad.get("owner_slot", "")), "heavy": heavy, "id": str(pad.id)})
	pad_pieces[pad.id] = piece
	_physical_pads[pad.id] = piece.rim

## A valve's dial marks for a selector (kit/pieces/selector.gd): per value,
## how many bands; one each by default.
func _look_marks(control: Dictionary) -> Array:
	return Array(control.get("values", [])).map(func(_value: Variant) -> int: return 1)

## A lever or a selector in its style (kit/pieces/lever.gd, selector.gd).
func _build_lever(lever: Dictionary) -> void:
	var slot := PieceStyles.control_slot(lever)
	var options := {"owner": str(lever.get("owner_slot", "")), "id": str(lever.id), "values": Array(lever.get("values", [])), "marks": _look_marks(lever)}
	var kit: Script = SelectorPiece if slot == "selector" else LeverPiece
	var piece: RefCounted = kit.build(_piece_style(slot, str(lever.id)), _at(lever), terrain, options)
	_lever_pieces[lever.id] = piece
	_physical_levers[lever.id] = piece.anchor
	mark_sound("control:%s" % lever.id, piece.anchor)

## Gate links: cables this wide, their centres this high.
const LINK_WIDTH := 0.025
const LINK_LIFT := 0.03

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
			if str(mechanism.id) not in PairTags.references(gate): continue
			var link_color := _gate_link_color(mechanism)
			var start := _at(mechanism) + Vector3(0, 0.03, 0)
			var elbow := Vector3(end.x - 0.18, start.y, start.z)
			if start.distance_to(elbow) > 0.01: _floor_cable(start, elbow, 0.025, link_color)
			if elbow.distance_to(end) > 0.01: _floor_cable(elbow, end, 0.025, link_color)
			_cabled[str(route.id)] = true

## Gate links that never cross the void: a cable runs along a floor the
## mechanism and its route share; otherwise matching tags mark both ends.
func _build_floor_links(view: Dictionary) -> void:
	for gate: Dictionary in view.get("gates", []):
		var route: Dictionary = {}
		for candidate: Dictionary in view.bridges + view.get("stairs", []):
			if candidate.id == gate.route_id: route = candidate
		if route.is_empty(): continue
		var rect: Array = route.rect_cm
		# The cable ends on the crossing's near end mark.
		var end := OwnerMark.route_ends_of(route, chapter_definition.get("islands", []))[0] + Vector3(0, float(route.get("height_cm", route.get("from_height_cm", 0))) / 100.0 + LINK_LIFT, 0)
		for mechanism: Dictionary in view.get("pressure_pads", []) + view.get("ball_pads", []) + view.get("levers", []):
			if str(mechanism.id) not in PairTags.references(gate): continue
			var link_color := _gate_link_color(mechanism)
			var start := _at(mechanism) + Vector3(0, LINK_LIFT, 0)
			var elbow := Vector3(end.x, start.y, start.z)
			# Across a gap the pair tags (pair_tags) tie the two ends instead.
			if _shares_floor(start, elbow) and _shares_floor(elbow, end):
				if start.distance_to(elbow) > 0.01: _floor_cable(start, elbow, LINK_WIDTH, link_color)
				if elbow.distance_to(end) > 0.01: _floor_cable(elbow, end, LINK_WIDTH, link_color)
				_cabled[str(route.id)] = true

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

## The chapter's floors, whichever stage is shown.
func _route_islands() -> Array:
	return chapter_definition.get("islands", [])

## The lock ring round each rolling ball, beside the stage's barriers.
func _build_barrier_extras() -> void:
	route_barriers.build_rings(_physical_balls, _ball_radii, terrain)

func _at(value: Dictionary) -> Vector3:
	return point(value.position_cm) + Vector3(0, _surface_height(str(value.get("surface_id", ""))), 0)

## The cables and ropes this stage lays on its floors: {rect, y, what} each
## (_floor_cable). Ownership marks keep off them.
func floor_cables() -> Array:
	return _floor_cables

## A cable or rope lying along a floor from `from` to `to` (terrain space),
## kept in floor_cables() when it runs level.
func _floor_cable(from: Vector3, to: Vector3, width: float, color: Color) -> MeshInstance3D:
	if absf(from.y - to.y) < 0.05:
		var low := Vector2(minf(from.x, to.x), minf(from.z, to.z))
		var high := Vector2(maxf(from.x, to.x), maxf(from.z, to.z))
		_floor_cables.append({"rect": Rect2(low, high - low).grow(width * 0.5), "y": minf(from.y, to.y), "what": "a cable"})
	return _bar_between(from, to, width, color, terrain)

## Only the kept crossings (island_world's), never the Lighthouse's
## remembered mechanisms.
func present_history(checkpoint: Dictionary) -> void:
	_latched_bridge_ids = kept_crossings(checkpoint)

## Whether this world keeps where the stage's pips have been (its look has a
## fog cover): the screen then hands it each turn's history.
func wants_turn_paths() -> bool:
	return not Look.preset(str(DressingCatalog.for_key(_chapter_key()).get("look", ""))).get("cover", {}).is_empty()

## A turn's history (TurnPaths.of, at its reset): the cover opens where the
## stage has been, all of it at once.
func present_turn_paths(history: Dictionary) -> void:
	turn_paths.set_history(history)
	if new_pieces != null: new_pieces.show_paths(turn_paths)

## One tick of the turn shown, presented or stepped silently (memory_wait.gd).
func note_tick(state: Dictionary) -> void:
	if not state.has("players") or new_pieces == null or new_pieces.cover == null: return
	var change := turn_paths.note(state)
	if new_pieces != null and (change.rewound or change.from_points < turn_paths.live_points.size() or change.from_levers < turn_paths.live_levers.size()):
		new_pieces.paths_changed(change)

func apply_graphics_quality(quality: String) -> void:
	super.apply_graphics_quality(quality)
	if new_pieces != null: new_pieces.set_quality(graphics_quality())

func present(state: Dictionary, immediate: bool = false) -> void:
	if state.get("stage_id", "") != displayed_stage_id:
		for authored: Dictionary in chapter_definition.get("stages", []):
			if authored.id == state.get("stage_id", ""): show_stage(authored)
	if not state.has("players"): return
	note_tick(state)
	_active_player = str(state.active_slot)
	for slot: String in state.players: _floors[slot] = str(state.players[slot].get("surface_id", ""))
	# Placed at once, a spirit is where its deck is: nothing to take along.
	if immediate: _rode.clear()
	_completion_view = bool(state.get("complete", false))
	for raised: Node3D in _upper_islands:
		_set_cutaway(raised, _should_cutaway(raised,state))
	# This adapter adds missing top-level fields; nested simulation values are
	# read-only throughout the shared renderer.
	var visual := state.duplicate()
	visual.merge({"mirror_orientation": "slash", "emitter_powered": false, "objective_done": bool(state.get("complete", false)), "optics": {"segments": [], "signals": {}}, "bridges": {}, "mirrors": {}, "selectors": {}, "props": {}}, false)
	super.present(visual, immediate)
	pair_tags.present(state)
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
		var target := Vector3(float(prop.x) / 100.0, float(prop.get("height", 0)) / 100.0 + RouteBarriers.BALL_LIFT, float(prop.z) / 100.0)
		if not immediate:
			var displacement: Vector3 = target - _physical_balls[id].position
			_physical_balls[id].rotate_x(displacement.z / 0.2)
			_physical_balls[id].rotate_z(-displacement.x / 0.2)
		_physical_balls[id].position = target
		var trail: Node3D = _ball_trails[id]
		trail.tint = material.albedo_color
		trail.set_motion_allowed(str(prop.get("status", "")) == "free" and str(prop.get("socket_id", "")).is_empty(), immediate)
	for id: String in _lever_pieces: _lever_pieces[id].set_pulled(bool(state.get("levers", {}).get(id, false)), immediate or reduced_motion)
	for id: String in _hatches: _hatches[id].visible = not state.get("levers", {}).get(id, false)
	for id: String in _physical_pads:
		var pressed: bool = state.get("hold_pads", {}).get(id, false)
		_glow(_physical_pads[id], LIGHT_COLOR, 1.0 if pressed else 0.0)
		if pad_pieces.has(id): pad_pieces[id].set_held(pressed, immediate or reduced_motion)
	_present_barriers(state)
	for id: String in _weights:
		_weights[id].position.y = float(_weights[id].get_meta("rest_y")) - (0.7 if state.get("bridges", {}).get(id, false) else 0.0)
	for id: String in _pulleys: _pulleys[id].set_laid(bool(state.get("bridges", {}).get(id, false)))
	if is_instance_valid(_goal_beacon): _goal_beacon.present(state)
	if new_pieces != null: new_pieces.present(state, immediate or reduced_motion)
	if immediate: _snap_follow()

func _should_cutaway(raised: Node3D, state: Dictionary) -> bool:
	return _uses_lower_cutaway() and _below_raised(raised,state.players[_active_player])

func _below_raised(raised: Node3D, player: Dictionary) -> bool:
	return Cutaway.below_raised(raised, player)

## The platforms move before the spirits, so a rider is drawn on its deck as
## it is this frame.
func _advance_carriers(delta: float) -> void:
	if new_pieces != null and new_pieces.moving(): new_pieces.advance(delta)

## The one rider rule (kit/new_pieces.gd ride): a spirit on a platform's stop,
## the live pip or a memory, goes along with its deck's movement since the last
## frame and is drawn as far from its snapshot place as the deck stands from
## that stop; one that stepped off before its deck got there waits on it until
## it is (ride_off).
func _carry(role: String, actor: Node3D) -> Vector3:
	var deck: Array = new_pieces.ride(str(_floors.get(role, ""))) if new_pieces != null else []
	var was: Array = _rode.get(role, [])
	var riding := not was.is_empty() and is_instance_valid(was[0])
	# Stepped off a deck still on its way: it waits on the deck until the deck
	# is there, then walks on to catch up (never through the floor's edge).
	var off := deck.is_empty() and riding
	if off: deck = new_pieces.ride_off(was[0])
	if deck.is_empty():
		_rode.erase(role)
		return Vector3.ZERO
	var root: Node3D = deck[0]
	if riding and was[0] == root: actor.position += root.position - (was[1] as Vector3)
	_rode[role] = [root, root.position]
	if not off: return deck[1]
	# Off: its walk goes on only as far as the deck's edge (DECK_EDGE in), at
	# the deck's height, until the deck is there.
	var target: Vector3 = (actor_targets[role] as Vector3) + (deck[1] as Vector3)
	var room: Vector2 = ((deck[2] as Vector2) - Vector2.ONE * DECK_EDGE).max(Vector2.ZERO)
	target.x = clampf(target.x, root.position.x - room.x, root.position.x + room.x)
	target.z = clampf(target.z, root.position.z - room.y, root.position.z + room.y)
	return target - (actor_targets[role] as Vector3)

func _advance_camera(delta: float) -> void:
	if new_pieces != null and not reduced_motion: new_pieces.drift(time)
	if new_pieces != null and actors.has(_active_player): new_pieces.follow((actors[_active_player] as Node3D).global_position + Vector3(0, 0.25, 0))
	if new_pieces != null: new_pieces.advance_cover(delta, time)
	for id: String in _lever_pieces:
		if _lever_pieces[id].moving(): _lever_pieces[id].advance(delta)
	if _uses_scrolling_camera():
		# Authored framing advances once per rendered frame. Snapshot delivery
		# and pinch zoom must never feed back into the follow state.
		var rate := FOLLOW_RATE
		if _glance_left > 0.0:
			_glance_left = maxf(_glance_left - delta, 0.0)
			rate = 3.5 if _glance_left > GLANCE_BACK else 6.0
		_ease_follow(delta, rate)
	_frame_camera()
	if is_instance_valid(_goal_beacon): _goal_beacon.follow(camera)

func _frame_camera() -> void:
	if not _uses_scrolling_camera():
		super._frame_camera()
		return
	_frame_follow()
