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

const WaterBodies = preload("res://presentation/kit/water_bodies.gd")
const WaterLocks = preload("res://presentation/kit/water_locks.gd")

## The water kit for the shown stage.
var waters := WaterBodies.new(self)
## Where the spirits stand (plan cm), refilled each snapshot for the locks and
## the wall fade.
var _water_spirits := PackedVector2Array()
## Dressing parts that turn on their own (a kit prop's "Spin" node, whose
## meta "spin" is radians a second, as a mill wheel's): held here, so the
## static fold batches each under itself and it still turns.
var _spinning: Array[Node3D] = []

func show_stage(stage: Dictionary) -> void:
	if str(stage.get("id", "")) == displayed_stage_id: return
	_spinning.clear()
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
	await _build_water_scenery()

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
	for piece: Array in Primitives.rect_minus_hole(island.rect_cm, hole.get("rect_cm", [])):
		Surfaces.build({"id": island.id, "rect_cm": piece}, style, raised, false)
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

func _deck_walls(island: Dictionary, raised: Node3D) -> void:
	var r: Array = island.rect_cm
	var height := raised.position.y
	var bottom := waters.seabed() - height
	var color: Color = _wall_color(int(island.get("height_cm", 0)))
	var size := Vector3(float(r[2] - r[0]) / 100.0 - 0.02, -0.20 - bottom, float(r[3] - r[1]) / 100.0 - 0.02)
	var wall := box(size, color, Vector3(float(r[0] + r[2]) / 200.0, (bottom - 0.20) * 0.5, float(r[1] + r[3]) / 200.0), raised)
	wall.name = str(island.id) + "Wall"
	# One weathered course on the face toward the camera, just under the deck.
	box(Vector3(size.x - 0.012, 0.03, 0.02), color.darkened(0.18), Vector3(wall.position.x, -0.34, float(r[3]) / 100.0 - 0.005), raised)
	# Block courses down the face, and the water marks round every face.
	var y := -0.62
	while y > bottom + 0.08:
		var clear := true
		for level: float in waters.mark_levels().values(): clear = clear and absf(height + y - level) > 0.06
		if clear: box(Vector3(size.x + 0.016, 0.012, size.z + 0.016), color.darkened(0.10), Vector3(wall.position.x, y, wall.position.z), raised).name = "WallCourse"
		y -= 0.28
	waters.mark_bands(Vector3(wall.position.x, 0, wall.position.z) + Vector3(0, height, 0), Vector2(size.x, size.z), waters.seabed(), height - 0.20, raised, height)

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
	if _weights.has(str(definition.id)): _weights[str(definition.id)].set_meta("rest_y", _weights[str(definition.id)].position.y)

# --- Each snapshot and frame ---

func present(state: Dictionary, immediate: bool = false) -> void:
	super.present(state, immediate)
	if state.has("players"): _present_water(state, immediate)

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
	waters.advance(delta)
	waters.advance_fade(delta)
	if not reduced_motion:
		waters.bob()
		# From the world's clock, so a frame shows the same turn however it is reached.
		for part: Node3D in _spinning:
			if is_instance_valid(part): part.rotation.z = time * float(part.get_meta("spin"))

func _dressed_prop(prop: Node3D) -> void:
	super._dressed_prop(prop)
	var part := prop.get_node_or_null("Spin") as Node3D
	if part != null and part.has_meta("spin"): _spinning.append(part)

## The water and the floods move with the snapshot, so they stay whole.
func _static_keep() -> Array:
	var keep := super._static_keep()
	keep.append_array(waters.moving_nodes())
	return keep
