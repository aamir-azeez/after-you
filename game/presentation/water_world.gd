extends "res://presentation/journey_world.gd"
## A journey world on the water: the chapter's water block (the descriptor's
## "water" file, kit/water_bodies.gd) fills every gap between the floors,
## each floor is a solid deck walled down to the water's bed, and every
## crossing stands at its own height. Turn of the Tide, The Falls and Fog Marsh
## are built on it; what one of them adds (Tide's chamber and sea gates) goes
## in the hooks below. Presentation only: the water reads the snapshot and
## nothing here feeds the simulation, a recording or a checkpoint.
##
## Hooks a world may extend, each called once per stage or snapshot:
##   _forget_stage()          before a new stage's build (clear its own lists)
##   _terrain_name()          the terrain's node name ("" keeps the base's)
##   _build_water_walls()     walls of its own that hold water (register each
##                            with waters.holds_water), before the locks
##   _build_water_scenery()   whatever stands on or by the water, after the locks
##   _present_water(state, immediate)  the water and what reads it
##   _advance_water(delta)    the water each frame
##   _default_ground(height_cm), _wall_color(height_cm), _piers(island, raised)
##
## What every water world shows with no code of its own: boats riding the water
## by the float rule (kit/floats.gd: the dressing's "moored_boats", and any
## dressing "boat" prop standing over water), a drowning (kit/drowning.gd), and
## stepping stones that sink just under the water while they are down (shut,
## or pushed under) and rise again, never hidden. A world never builds its own
## (test_shared_paths guards it).

const WaterBodies = preload("res://presentation/kit/water_bodies.gd")
const WaterLocks = preload("res://presentation/kit/water_locks.gd")
const Gorge = preload("res://presentation/kit/gorge.gd")
const PropRules = preload("res://presentation/kit/prop_rules.gd")
## How strongly a prop standing in the water rings it (a float rings at 1).
const WATERLINE_RINGS := 0.6
const Drowning = preload("res://presentation/kit/drowning.gd")
const Floats = preload("res://presentation/kit/floats.gd")
const Models = preload("res://presentation/kit/models.gd")
## Every boat that floats is the rowboat model at this size, so one set of
## float numbers (Floats "rowboat") holds for all of them.
const ROWBOAT_SIZE := 0.83
## A boat's mooring pile: from its water's bed to this far over its highest level.
const PILE_OVER := 0.19
## Where a stone that is down rests: its top this far under the water (m), and
## how fast it sinks and rises (m a second).
const STONE_UNDER := 0.10
const STONE_RATE := 0.45

## The water kit for the shown stage.
var waters := WaterBodies.new(self)
## Where the spirits stand (plan cm), refilled each snapshot for the locks and
## the wall fade.
var _water_spirits := PackedVector2Array()
## Dressing parts that turn on their own (a kit prop's "Spin" node, whose
## meta "spin" is radians a second, as a mill wheel's): held here, so the
## static fold batches each under itself and it still turns.
var _spinning: Array[Node3D] = []
## Running water in the falls' look (kit/props.gd _falls_material: a falls,
## a pour, a curtain): this world's own copy of the look, gathered once a
## stage, whose clock is the world's, so it runs with the world, holds still
## with Reduce motion and never moves another world's water.
var _flow_look: ShaderMaterial
var _flows_gathered := false
## The water world's own clock (seconds), for every bob.
var _clock := 0.0
## A drowning, shown from the snapshot (kit/drowning.gd).
var drowning := Drowning.new(self)
## Boats riding the water (each a node, its keel at its origin).
var _boats: Array[Node3D] = []
## Dressing "boat" props standing over water, built as floating boats once
## the water stands: [{"at": [x, z] cm, "heading": radians, "water": body id}].
var _floating: Array = []
## Stepping stones (crossings standing in the water): id -> {"deck", "rest"
## (its open height), "water" (body id), "down", "y" (shown height)}.
var _stones: Dictionary = {}

func show_stage(stage: Dictionary) -> void:
	if str(stage.get("id", "")) == displayed_stage_id: return
	_spinning.clear()
	_flows_gathered = false
	_boats.clear()
	_floating.clear()
	_stones.clear()
	drowning.forget()
	_forget_stage()
	waters.start(stage, _water_block(), _standing_routes(stage))
	await super.show_stage(stage)
	var name_given := _terrain_name()
	if not name_given.is_empty(): terrain.name = name_given
	await waters.build_bodies()
	await waters.build_walls()
	await _build_step()
	await _build_water_walls()
	await waters.build_locks(WaterLocks.bake_path(_chapter_key(), displayed_stage_id))
	# Every wall now stands: a coil behind one goes.
	drop_unseen_coils(waters.standing_walls())
	await _build_water_scenery()
	_build_boats()
	_find_stones(stage)
	# The dressing's gorge: rock behind the floors and rainbows in the spray.
	Gorge.build(self, dressing.get("gorge", {}))

func _forget_stage() -> void:
	pass

func _terrain_name() -> String:
	return ""

func _build_water_walls() -> void:
	pass

func _build_water_scenery() -> void:
	pass

## The chapter's water block: the descriptor's "water" file, or {} for none.
func _water_block() -> Dictionary:
	var path := str(_descriptor().get("water", ""))
	return {} if path.is_empty() else load(path).DATA

## Crossings that stand in the water as they are, never walled: the
## dressing's "stones" decks and the stage's sinking stones.
func _standing_routes(stage: Dictionary) -> Array:
	var decks: Dictionary = DressingCatalog.for_key(_chapter_key()).get("decks", {})
	var standing: Array = decks.keys().filter(func(id: String) -> bool: return decks[id] == "stones")
	for id: Variant in stage.get("sinking", []):
		if str(id) not in standing: standing.append(str(id))
	return standing

# --- Boats: every one by the float rule ---

## The dressing's "moored_boats", and every "boat" prop that stands over
## water, ride their water's level (and bob unless motion is reduced). Each
## sits by the float rule (kit/floats.gd "rowboat"): its keel at its origin,
## solid up to its floorboards, which stay over the water all through its bob,
## and open above them inside its gunwale. A pile it is tied to stands beside it.
func _build_boats() -> void:
	for spec: Dictionary in dressing.get("moored_boats", []) + _floating:
		var at := point(spec.at)
		var boat := Node3D.new()
		boat.name = "MooredBoat"
		boat.position = at
		boat.rotation.y = float(spec.heading)
		boat.set_meta("phase", float(spec.at[0]) * 0.013)
		# A dressing boat prop, floated: still the dressing's (test_dressing_lint counts it).
		if spec.has("dressing"): boat.set_meta("dressing_kind", "boat")
		terrain.add_child(boat)
		# The rowboat model along z, its keel at the node's origin (the float rule).
		var hull := Models.moving(Props.ROWBOAT, "rowboat", Props.rowboat_colors(), boat)
		hull.transform = Transform3D(Basis(Vector3.UP, -PI / 2.0).scaled(Vector3.ONE * ROWBOAT_SIZE), Vector3.ZERO)
		var water := str(spec.water)
		var bottom := waters.bed(water)
		var top: float = float(Array(waters.levels_of(water).values()).max()) + PILE_OVER
		cylinder(0.035, top - bottom, Parts.TIMBER_DARK, Vector3(at.x + 0.32, (top + bottom) * 0.5, at.z - 0.36), terrain).name = "MooringPile"
		_boats.append(boat)
		waters.ride(water, _float_boat.bind(boat), true, boat)

func _float_boat(level: float, boat: Node3D) -> void:
	if not is_instance_valid(boat): return
	boat.position.y = Floats.keel("rowboat", level, _clock, float(boat.get_meta("phase")), reduced_motion)

## A dressing "boat" standing over water (off every floor, inside a body) is
## not a prop: it floats, built with the moored boats once the water stands.
func _takes_prop(spec: Dictionary) -> bool:
	if str(spec.get("kind", "")) != "boat" or waters.water.is_empty(): return false
	var at: Array = spec.get("at", [])
	if at.size() != 2: return false
	for island: Dictionary in current_level.get("islands", []):
		if WaterBodies._inside(at, island.rect_cm): return false
	var water := waters.body_of([at[0], at[1], at[0], at[1]])
	if water.is_empty(): return false
	_floating.append({"at": at, "heading": deg_to_rad(float(spec.get("rot", 0))) + PI / 2.0, "water": water, "dressing": true})
	return true

# --- Currents: marks on the water ---

## A current's mark lies on open water only: off every floor and crossing and
## inside a body of this world's water.
func _current_water(at: Vector3, view: Dictionary) -> bool:
	if waters.water.is_empty(): return super._current_water(at, view)
	var cm := [at.x * 100.0, at.z * 100.0, at.x * 100.0, at.z * 100.0]
	return super._current_water(at, view) and not waters.body_of(cm).is_empty() and not WaterBodies.covered(cm[0], cm[1], waters.basin_rects())

## Each leg rides the body under its middle, so its marks sit on the water at
## every level.
func _ride_current(legs: Array) -> void:
	if waters.water.is_empty(): return
	for index in range(legs.size()):
		var middle: Vector3 = (legs[index].from + legs[index].to) * 50.0
		var water := waters.body_of([middle.x, middle.z, middle.x, middle.z])
		if not water.is_empty(): waters.ride(water, _current_piece.set_level.bind(index))

# --- Stepping stones: down under the water, never hidden ---

## The stage's stepping stones that have a deck: the crossings that stand in
## the water (the dressing's "stones" decks, the stage's sinking stones) and
## every crossing laid in the "stones" deck style.
func _find_stones(stage: Dictionary) -> void:
	var standing := _standing_routes(stage)
	for id: String in _decks:
		var deck: Node3D = _decks[id]
		if id not in standing and (new_pieces == null or new_pieces.deck_style(id) != "stones"): continue
		_stones[id] = {"deck": deck, "rest": deck.position.y, "water": waters.body_of(_route_rect(id)), "down": false, "y": deck.position.y}

func _route_rect(id: String) -> Array:
	for route: Dictionary in current_level.get("bridges", []):
		if str(route.id) == id: return route.rect_cm
	return [0, 0, 0, 0]

## A stone is down while its crossing is shut, or once it is pushed under (a
## drowning on it): it stays in view, sinking to just under its water.
func _present_stones(state: Dictionary, immediate: bool) -> void:
	var routes: Dictionary = state.get("bridges", {})
	var sunk := str(state.get("drowned", {}).get("route", ""))
	for id: String in _stones:
		var stone: Dictionary = _stones[id]
		if not is_instance_valid(stone.deck): continue
		stone.down = not bool(routes.get(id, false)) or id == sunk
		stone.deck.visible = true
		if immediate or reduced_motion:
			stone.y = _stone_target(stone)
			stone.deck.position.y = stone.y

## Where a stone heads: its open height, or just under its water while down.
func _stone_target(stone: Dictionary) -> float:
	if not stone.down: return float(stone.rest)
	var body: Node3D = waters.bodies.get(str(stone.water))
	var level: float = float(body.get_meta("shown")) if is_instance_valid(body) and body.has_meta("shown") else float(stone.rest)
	return minf(float(stone.rest), level - STONE_UNDER)

func _sink_stones(delta: float) -> void:
	for stone: Dictionary in _stones.values():
		if not is_instance_valid(stone.deck): continue
		var target := _stone_target(stone)
		if is_equal_approx(float(stone.y), target): continue
		stone.y = target if reduced_motion else move_toward(float(stone.y), target, STONE_RATE * maxf(delta, 0.0))
		stone.deck.position.y = stone.y

# --- Floors: solid decks with walls down to the water ---

func _shore(island: Dictionary, _color: Color) -> void:
	var height := float(island.get("height_cm", 0)) / 100.0
	var raised := Node3D.new()
	raised.name = "Deck_" + str(island.id)
	raised.position.y = height
	terrain.add_child(raised)
	_surface_nodes[str(island.id)] = raised
	raised.set_meta("bounds", island.rect_cm.duplicate())
	var style := _ground_style(str(island.id))
	if style.is_empty(): style = _default_ground(int(island.get("height_cm", 0)))
	var hole: Dictionary = {}
	for drop: Dictionary in current_level.get("drops", []):
		if drop.surface_id == island.id: hole = drop
	# A drop keeps a real opening in its floor; no decal covers it.
	Surfaces.build(island, style, raised, false, _floor_shape(island, hole.get("rect_cm", [])))
	if str(island.id) in waters.water.get("piers", []):
		# A floor on piers: water runs under it, so it gets no walls.
		raised.set_meta("tide_occluder", true)
		_upper_islands.append(raised)
		_piers(island, raised)
	else:
		_deck_walls(island, raised)
	_surface_built(island, raised)

## A floor's ground when the dressing names none, by its height in cm.
func _default_ground(_height_cm: int) -> String:
	return "harbour"

## The wall under a floor, by its height in cm: the water block's masonry.
func _wall_color(_height_cm: int) -> Color:
	return waters.water.get("stone", Parts.STONE)

## What holds up a floor on piers.
func _piers(_island: Dictionary, _raised: Node3D) -> void:
	pass

## The rectangles a floor is drawn as (drawn_pieces), less a drop's `hole`.
func _floor_shape(island: Dictionary, hole: Array) -> Array:
	var shape: Array = []
	for piece: Array in drawn_pieces(island):
		shape.append_array(WalkReach.minus(piece, hole) if not hole.is_empty() else [piece])
	return shape

func _deck_walls(island: Dictionary, raised: Node3D) -> void:
	var shape := drawn_pieces(island)
	for r: Array in shape: _deck_wall(island, raised, r, shape)

## The wall under one piece `r` (cm) of a floor's drawn `shape`: a centimetre
## in from each side the shape's edge runs along, flush where the next piece meets it.
func _deck_wall(island: Dictionary, raised: Node3D, r: Array, shape: Array) -> void:
	var height := raised.position.y
	# Down to the bed of the pool it stands in (WaterBodies.bed_at).
	var bed := waters.bed_at(Vector2(float(r[0] + r[2]), float(r[1] + r[3])) * 0.5)
	var bottom := bed - height
	var color: Color = _wall_color(int(island.get("height_cm", 0)))
	var inset: Array = Surfaces.outer_sides(r, shape).map(func(outer: bool) -> float: return 0.01 if outer else 0.0)
	var low := Vector2(float(r[0]) / 100.0 + inset[0], float(r[1]) / 100.0 + inset[1])
	var high := Vector2(float(r[2]) / 100.0 - inset[2], float(r[3]) / 100.0 - inset[3])
	var size := Vector3(high.x - low.x, -0.20 - bottom, high.y - low.y)
	var wall := box(size, color, Vector3((low.x + high.x) * 0.5, (bottom - 0.20) * 0.5, (low.y + high.y) * 0.5), raised)
	wall.name = str(island.id) + "Wall"
	# One weathered course on the face toward the camera, just under the deck.
	box(Vector3(size.x - 0.012, 0.03, 0.02), color.darkened(0.18), Vector3(wall.position.x, -0.34, float(r[3]) / 100.0 - 0.005), raised)
	# Block courses down the face (the water block's "courses" apart, 0.28 m by
	# default; 0 for plain rock faces), and the water marks round every face.
	var course := float(waters.water.get("courses", 0.28))
	var y := -0.62
	while course > 0.0 and y > bottom + 0.08:
		var clear := true
		for level: float in waters.mark_levels().values(): clear = clear and absf(height + y - level) > 0.06
		if clear: box(Vector3(size.x + 0.016, 0.012, size.z + 0.016), color.darkened(0.10), Vector3(wall.position.x, y, wall.position.z), raised).name = "WallCourse"
		y -= course
	waters.mark_bands(Vector3(wall.position.x, 0, wall.position.z) + Vector3(0, height, 0), Vector2(size.x, size.z), bed, height - 0.20, raised, height)

func _framed_stairs() -> bool:
	return false

func _surface_height(id: String) -> float:
	# Markers on a raised crossing (the waiting steps, posts and catwalks) stand
	# at that crossing's own height, not the shared island-only lookup's zero.
	for island: Dictionary in chapter_definition.get("islands", []):
		if island.id == id: return float(island.get("height_cm", 0)) / 100.0
	for route: Dictionary in chapter_definition.get("bridges", []):
		if route.id == id: return float(route.get("height_cm", 0)) / 100.0
	return 0.0

# --- Crossings: decks at their own height ---

func _build_bridge(definition: Dictionary) -> void:
	var before := terrain.get_child_count()
	super._build_bridge(definition)
	var built: Array[Node] = []
	for index in range(before, terrain.get_child_count()): built.append(terrain.get_child(index))
	# The shared deck builder places every deck at the ground; lift all it made.
	for node: Node in built: (node as Node3D).position.y += float(definition.get("height_cm", 0)) / 100.0

# --- Each snapshot and frame ---

func present(state: Dictionary, immediate: bool = false) -> void:
	super.present(state, immediate)
	if not state.has("players"): return
	_present_stones(state, immediate)
	_present_water(state, immediate)
	drowning.show(state.get("drowned", {}))

## The water at the snapshot's levels, the walled stubs' floods, and the
## doors and wall fade round where the spirits stand.
func _present_water(state: Dictionary, immediate: bool) -> void:
	waters.present_controls(state.get("controls", {}), immediate)
	waters.show_floods(_decks)
	_occupy_water(state, immediate)

## Where the spirits stand, from the snapshot's positions, so live play, the
## memory, a retry and a replay all agree: a door dips while one stands in its
## mouth, and the walls in front of one on a walled stub fade.
func _occupy_water(state: Dictionary, immediate: bool) -> void:
	var players: Dictionary = state.get("players", {})
	_water_spirits.resize(players.size())
	var index := 0
	for slot: String in players:
		_water_spirits[index] = Vector2(float(players[slot].x), float(players[slot].z))
		index += 1
	waters.occupy(_water_spirits, state.get("bridges", {}), immediate or reduced_motion)

func _advance_camera(delta: float) -> void:
	_advance_water(delta)
	super._advance_camera(delta)

func _advance_water(delta: float) -> void:
	_clock += maxf(delta, 0.0)
	waters.advance(delta)
	if not _stones.is_empty(): _sink_stones(delta)
	waters.advance_fade(delta)
	if not reduced_motion:
		drowning.advance(delta)
		waters.bob()
		# From the world's clock, so a frame shows the same turn however it is reached.
		for part: Node3D in _spinning:
			if is_instance_valid(part): part.rotation.z = time * float(part.get_meta("spin"))
		if not _flows_gathered: _gather_flows()
		if _flow_look != null: _flow_look.set_shader_parameter(&"clock", time)

## Moves this stage's running water onto the world's own copy of the falls' look.
func _gather_flows() -> void:
	_flows_gathered = true
	var shared: ShaderMaterial = Props._falls_material()
	for node: Node in terrain.find_children("*", "MeshInstance3D", true, false):
		if (node as MeshInstance3D).material_override != shared: continue
		if _flow_look == null: _flow_look = shared.duplicate()
		(node as MeshInstance3D).material_override = _flow_look

func _dressed_prop(prop: Node3D) -> void:
	super._dressed_prop(prop)
	var part := prop.get_node_or_null("Spin") as Node3D
	if part != null and part.has_meta("spin"): _spinning.append(part)
	_waterline(prop)

## A dressing prop standing in the water (Props.stands_in_water(), over a
## body, off every floor: a pole down to the bed, a boat, a wreck) makes the water's rings where it
## meets the surface, at whatever level the water stands, from its foot to its
## top (WaterLook.ripple_from; the foam band round it comes with the edge
## maps). Its "Waterline" marker sits halfway up that reach.
func _waterline(prop: Node3D) -> void:
	var spec: Dictionary = prop.get_meta("dressing_spec", {})
	var at := Vector2(prop.position.x, prop.position.z)
	if not Props.stands_in_water(str(spec.get("kind", ""))) or waters.body_under(at * 100.0).is_empty(): return
	for island: Dictionary in current_level.get("islands", []):
		if PropRules.rect(island.rect_cm).grow(PropRules.LIP).has_point(at): return
	var base := prop.position.y + (prop.get_parent() as Node3D).position.y if prop.get_parent() != terrain else prop.position.y
	# Its foot: the base less what its model reaches under it (Props.BELOW).
	var extent := Props.extent(spec)
	var foot := base + float(extent.base) - float(spec.get("y", 0)) / 100.0
	var low := foot - float(spec.get("wade", 0)) / 100.0
	var high := foot + float(extent.height)
	var marker := Node3D.new()
	marker.name = "Waterline"
	prop.add_child(marker)
	marker.global_position = terrain.to_global(Vector3(at.x, (low + high) * 0.5, at.y))
	waters.look.ripple_from(marker, WATERLINE_RINGS, (high - low) * 0.5, true)

## The water and the floods move with the snapshot, so they stay whole.
func _static_keep() -> Array:
	var keep := super._static_keep()
	keep.append_array(waters.moving_nodes())
	keep.append_array(drowning.moving_nodes())
	keep.append_array(_boats)
	for stone: Dictionary in _stones.values(): keep.append(stone.deck)
	return keep
