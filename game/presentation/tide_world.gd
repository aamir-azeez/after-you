extends "res://presentation/journey_world.gd"
## Turn of the Tide at dusk: a harbour of beaches, terraces and quays between
## channels whose water follows the tide wheel, an outer sea past the mole that
## follows the basin wheel, and a sea chamber between them. Water, wheels, tide
## gauges and kept-crossing marks only read the snapshot; nothing here feeds
## back into the simulation, a recording or a checkpoint.

## The water: its bodies, the walls that hold it, its floods and its locks,
## from the chapter's water block (content/water/turn_of_the_tide.gd).
const WaterBodies = preload("res://presentation/kit/water_bodies.gd")
const WaterLocks = preload("res://presentation/kit/water_locks.gd")
## How far a raised ramp stands up (radians), and how fast it swings (radians a second).
const RAMP_RAISED := 0.95
const RAMP_RATE := 1.6
## Tide rules (journey simulation.gd): a closing crossing's edges flash this
## colour, and a drowned spirit sinks this far under the water it is in.
const CLOSING_COLOR := Color("f08a5d")
const DROWN_DEPTH := 0.55
## A drowned spirit's face (spirit_look.gd).
const KNOCKED_OUT := &"knocked_out"
const SpiritLook = preload("res://presentation/spirit_look.gd")
## Bubbles rising where a spirit went under: [x offset, z offset, start phase
## (0..1 of the rise), radius] in metres. Fixed, so live play and any replay
## of the same drowning show the same bubbles; Reduce motion holds them still.
const DROWN_BUBBLES := [[0.10, 0.04, 0.0, 0.045], [-0.09, -0.03, 0.35, 0.035], [0.02, -0.08, 0.7, 0.03], [-0.13, 0.06, 0.15, 0.025]]
const BUBBLE_RISE := 0.55
const BUBBLE_SPEED := 0.45
## The sea gates' leaves stand across both ends of the harbour mouth.
const MOUTH_X := [-704, -512]
const SEA_GATE_Z := 5.20
## The sea chamber (the water block's "chamber" body) stands in walls to here.
const CHAMBER_WALL_TOP := 0.74
const SPOUT := Color(0.80, 0.93, 0.95, 0.86)
const STONE := Parts.STONE
const STONE_DARK := Color("7d6d58")
const TIMBER := Parts.TIMBER
const PILE := Parts.TIMBER_DARK
const SAND := Color("e3cf9f")
const BRASS := Parts.BRASS
const COPING := Color("dccaa4")
const ROPE := Color("d1b98c")
## Walls under each tier, by deck height in cm: pale sand, terracotta, honey.
const WALLS := {0: Color("bca681"), 48: Color("a3705a"), 96: Color("8e6d48")}
## Ground when the dressing names none, by deck height in cm.
const DEFAULT_GROUND := {0: "sand", 48: "terracotta", 96: "honey_cobble"}
const CAMERA_X := Vector2(-9.6, 17.28)
const CAMERA_Z := Vector2(-5.44, 5.44)
## Dark sign plates: the water signs, the key sign and the gauge waves' outline.
const CHIP_DARK := Color("102133")
## A valve's water sign, scaled from the full-size sign (a 0.34 m plate).
const VALVE_SIGN_SCALE := 0.8
## A valve's mark for bubbles (_mark_scenery): half its dial's width (m).
const VALVE_MARK_REACH := 0.275
## Every selector's speech bubble points at its lever, like every chapter's.
## A wheel's bubble sits this far sideways on screen (metres; the kit clamps a
## shift to the farthest its tail still meets the body), clear of its valve's
## sign: the tide's and the chamber's to the left; the sea's centred, so once
## it has risen over the gate-bar and sea-bar levers it stays clear of jetty-1's
## gauge, with or without a spirit at its lever. Whatever a bubble would still
## cover, it rises over (_clear_scenery); its tail stays on its lever.
const BUBBLE_SHIFTS := {"tide": -4.0, "chamber": -4.0, "basin": 0.1}
## A bubble rises over a gauge's head, another control's valve, another
## lever's knob or a pad once it covers more than this share of it (the share the journey worlds
## allow over a spirit).
const SCENERY_COVER := 0.10
## Each water wheel's tint, for its rim, dial and water sign.
const WHEEL_WATER := {"tide": Color("6fb3c2"), "basin": Color("4f8fb5"), "chamber": Color("7cc4b0")}
## Which mouth crossing each sea value serves.
const MOUTHS := {"half": "boom-jetty", "low": "sea-gate-out", "high": "punt-ferry"}

## The water kit for the shown stage (kit/water_bodies.gd).
var waters := WaterBodies.new(self)
var _wheels: Dictionary = {}
var _gauges: Dictionary = {}
var _mouth_lamps: Dictionary = {}
var _lever_lamps: Dictionary = {}
var _catwalks: Array[String] = []
var _slack_marks: Array[MeshInstance3D] = []
## Catwalks that read the sea alone: id -> marks lit while that catwalk is dry.
var _dry_marks: Dictionary = {}
var _post_marks: Dictionary = {}
var _sea_gates: Array[Node3D] = []
var _chamber_lamps: Array[MeshInstance3D] = []
var _spout: Node3D
var _spout_streaks: Array[MeshInstance3D] = []
var _history_tide := ""
## Where the spirits stand (plan cm), refilled each snapshot for the locks
## and the wall fade.
var _spirits := PackedVector2Array()
## Shut crossings stay in view as faint outlines: id -> ghost node.
var _ghosts: Dictionary = {}
var _boats: Array[Node3D] = []
## Ramps built for the shown stage: crossing id -> its hinge (Node3D, meta
## "target"), and what lowers each: crossing id -> [selector id, value].
var _ramps: Dictionary = {}
var _ramp_on: Dictionary = {}
## Each control, lever and pad of the chapter by id -> its owner slot.
var _owners: Dictionary = {}
## Tide rules: the ring spreading where a spirit drowned and its bubbles,
## built once on the first drowning and reused; the slot drowned now ("" none);
## the water surface it went under; how long the bubbles have risen.
var _drown_ring: MeshInstance3D
var _drown_bubbles: Array[MeshInstance3D] = []
var _drowned_slot := ""
var _drown_surface := 0.0
var _bubble_age := 0.0
## Kept-crossing masts, raised with the water that covers their crossing.
const MAST_CLEARANCE := 0.25
var _kept_masts: Array[Dictionary] = []
var _clock := 0.0
## View-plane boxes of bubbles already placed this frame by _clear_scenery: the
## first _scenery_placed_count entries; and the scenery marks it clears, the
## first _scenery_mark_count entries, with the control each belongs to. The
## arrays only grow, so a frame allocates nothing.
var _scenery_placed: Array[Rect2] = []
var _scenery_placed_count := 0
var _scenery_marks: Array[Rect2] = []
var _scenery_owners: Array[String] = []
var _scenery_mark_count := 0
## The most _clear_scenery had to climb any bubble this frame (metres): the
## shared placement already clears the scenery, so normally 0.
var scenery_backstop := 0.0

## Builds only the stage shown first. Controllers call show_stage straight
## after load_level, so opening on the second stage no longer builds the first
## stage's harbour just to tear it down. A caller that shows no stage still gets
## the first one: before its first history, or at the end of the frame.
## A staged open (build_budget_usec) builds its opening stage here instead,
## over frames behind the chapter card, and returns once it is whole.
## Otherwise as cooperative_world.load_level.
func load_level(definition: Dictionary) -> void:
	chapter_definition = definition.duplicate(true)
	displayed_stage_id = ""
	if build_budget_usec > 0:
		var first := _opening_stage(chapter_definition.get("stages", []))
		if not first.is_empty(): await show_stage(first)
		return
	_show_first_stage.call_deferred()

func _show_first_stage() -> void:
	if displayed_stage_id.is_empty() and not chapter_definition.get("stages", []).is_empty(): show_stage(chapter_definition.stages[0])

func show_stage(stage: Dictionary) -> void:
	if str(stage.get("id", "")) == displayed_stage_id: return
	_wheels.clear()
	_gauges.clear()
	_mouth_lamps.clear()
	_lever_lamps.clear()
	_catwalks.clear()
	_slack_marks.clear()
	_dry_marks.clear()
	_post_marks.clear()
	_sea_gates.clear()
	_chamber_lamps.clear()
	_spout = null
	_spout_streaks.clear()
	_history_tide = ""
	_ghosts.clear()
	_boats.clear()
	_ramps.clear()
	_ramp_on.clear()
	_owners = _mechanism_owners()
	# Actors outlive a stage: a drowned face goes back before the new one.
	if not _drowned_slot.is_empty(): _clear_drowned()
	_drown_ring = null
	_drown_bubbles.clear()
	_kept_masts.clear()
	_bubbles_placed = false
	var decks: Dictionary = _decks_data()
	waters.start(stage, _water_block(), decks.keys().filter(func(id: String) -> bool: return decks[id] == "stones"))
	await super.show_stage(stage)
	terrain.name = "TurnOfTheTide"
	await waters.build_bodies()
	await waters.build_walls()
	await _build_step()
	_build_chamber()
	await _build_step()
	_build_sea_gates()
	await waters.build_locks(WaterLocks.bake_path(_chapter_key(), displayed_stage_id))
	await _build_step()
	_build_mouth_lamps()
	await _build_step()
	_build_spout()
	await _build_step()
	_build_foreshore()
	await _build_step()
	_build_boats()
	_build_ramps()
	await _build_step()
	_build_lamplight()

## The chapter's water block: the descriptor's "water" file, or {} for none.
func _water_block() -> Dictionary:
	var path := str(_descriptor().get("water", ""))
	return {} if path.is_empty() else load(path).DATA

## How each crossing is built: the dressing's "decks" (route id -> kind).
## Read from the catalog, as a stage's own dressing loads after its floors.
func _decks_data() -> Dictionary:
	return DressingCatalog.for_key(_chapter_key()).get("decks", {})

## Every control, lever and pad of every stage: id -> its owner slot.
func _mechanism_owners() -> Dictionary:
	var found := {}
	for stage: Dictionary in chapter_definition.get("stages", []):
		for entity: Dictionary in stage.get("controls", []) + stage.get("levers", []) + stage.get("pressure_pads", []):
			found[str(entity.id)] = str(entity.get("owner_slot", ""))
	return found

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
	if style.is_empty(): style = str(DEFAULT_GROUND.get(int(island.get("height_cm", 0)), "harbour"))
	var hole: Dictionary = {}
	for drop: Dictionary in current_level.get("drops", []):
		if drop.surface_id == island.id: hole = drop
	# The spout keeps a real opening in the aqueduct floor; no decal covers it.
	for piece: Array in Primitives.rect_minus_hole(island.rect_cm, hole.get("rect_cm", [])):
		Surfaces.build({"id": island.id, "rect_cm": piece}, style, raised, false)
	if str(island.id) in waters.water.get("piers", []):
		# The aqueduct stands on piers, so the spout lands on open beach below it.
		raised.set_meta("tide_occluder", true)
		_upper_islands.append(raised)
		_aqueduct_piers(island, raised)
	else:
		_deck_walls(island, raised)
	_surface_built(island, raised)

func _deck_walls(island: Dictionary, raised: Node3D) -> void:
	var r: Array = island.rect_cm
	var height := raised.position.y
	var bottom := waters.seabed() - height
	var color: Color = WALLS.get(int(island.get("height_cm", 0)), STONE)
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

func _aqueduct_piers(island: Dictionary, raised: Node3D) -> void:
	var r: Array = island.rect_cm
	var bottom := waters.seabed() - raised.position.y
	var piers: Array = []
	if island.id == "aq-span": piers = [[300, 288], [470, 288], [560, 288]]
	else: piers = [[320, 200]]
	for at: Array in piers:
		var size := Vector3(0.18 if island.id == "aq-span" else float(r[2] - r[0]) / 100.0 - 0.04, -0.20 - bottom, 0.50 if island.id == "aq-span" else 0.18)
		box(size, STONE, Vector3(float(at[0]) / 100.0, (bottom - 0.20) * 0.5, float(at[1]) / 100.0), raised).name = "AqueductPier"

func _surface_height(id: String) -> float:
	# Markers on a raised crossing (the waiting steps, posts and catwalks) stand
	# at that crossing's own height, not the shared island-only lookup's zero.
	for island: Dictionary in chapter_definition.get("islands", []):
		if island.id == id: return float(island.get("height_cm", 0)) / 100.0
	for route: Dictionary in chapter_definition.get("bridges", []):
		if route.id == id: return float(route.get("height_cm", 0)) / 100.0
	return 0.0

func _route(id: String) -> Dictionary:
	for route: Dictionary in chapter_definition.get("bridges", []) + chapter_definition.get("stairs", []):
		if route.id == id: return route
	return {}

# --- Crossings: decks at their own height ---

func _build_bridge(definition: Dictionary) -> void:
	var before := terrain.get_child_count()
	super._build_bridge(definition)
	var id := str(definition.id)
	var built: Array[Node] = []
	for index in range(before, terrain.get_child_count()): built.append(terrain.get_child(index))
	# The shared deck builder places every deck at the ground; lift all it made.
	for node: Node in built: (node as Node3D).position.y += float(definition.get("height_cm", 0)) / 100.0
	if _weights.has(id): _weights[id].set_meta("rest_y", _weights[id].position.y)
	_kept_pennant(definition)
	if id.begins_with("jetty") or id == "boom-jetty": _piles(definition)
	if _is_stub(definition): _stub_frame(definition)
	else: _ghost(definition)

## A stub shows its owner on its own pads and levers; a route this stage never
## gates needs no ownership mark at all.
func _marks_route_owner(route: Dictionary) -> bool:
	return not (_is_stub(route) or _gate_for(str(route.id)).is_empty())

## Tide crossings carry a gauge and stubs their own marks instead of a pulley.
func _hangs_pulley(route: Dictionary) -> bool:
	return not _quiet_route(route)

## A route that never needs the pulley: a stub, a tide crossing, or one this
## stage leaves closed or always open.
func _quiet_route(route: Dictionary) -> bool:
	if _is_stub(route): return true
	var gate := _gate_for(str(route.id))
	return gate.is_empty() or gate.get("when", {}).is_empty() or not _tide_marks(gate.when).is_empty()

func _is_stub(route: Dictionary) -> bool:
	return WaterBodies.is_stub(route)

func _gate_for(route_id: String) -> Dictionary:
	for gate: Dictionary in current_level.get("gates", []):
		if gate.route_id == route_id: return gate
	return {}

## Each crossing in its own build, by the dressing's "decks": a rippled sand
## hump, round stepping stones, piled timber, a rope-railed gangway, flagged
## towpath stones or a punt, over the whole crossing. The long edges glow while
## the crossing is open, in gold where the tide opens it.
func _lay_deck(route: Dictionary, deck: Node3D, width: float, depth: float, across_x: bool, _low: float, _high: float) -> void:
	var id := str(route.id)
	var length := width if across_x else depth
	var lane := depth if across_x else width
	var kind := str(_decks_data().get(id, "timber"))
	match kind:
		"sand":
			box(Vector3(width, 0.10, depth), SAND, Vector3(0, -0.05, 0), deck)
			box(Vector3(width * (0.86 if across_x else 0.7), 0.02, depth * (0.7 if across_x else 0.86)), SAND.lightened(0.06), Vector3(0, -0.006, 0), deck)
			for index in range(6):
				var along := (float(index) + 0.5) / 6.0 * length - length * 0.5
				box(Vector3(0.016, 0.006, lane - 0.12) if across_x else Vector3(lane - 0.12, 0.006, 0.016), SAND.darkened(0.12), Vector3(along, 0.005, 0) if across_x else Vector3(0, 0.005, along), deck)
		"stones":
			var count := clampi(int(round(length / 0.42)), 3, 5)
			# Neighbouring stones, and the end ones and the terraces, never
			# overlap: their tops share one height.
			var radius := minf(0.26, minf(lane * 0.5 - 0.02, length / float(count) * 0.5 - 0.01))
			# Each stone is a column standing on the seabed (a centimetre above it),
			# so it stands in the channel's water at any level.
			var column := float(WaterBodies.low_cm(route)) / 100.0 - waters.seabed() - 0.01
			for index in range(count):
				var along := (float(index) + 0.5) / float(count) * length - length * 0.5
				var at := Vector3(along, -column * 0.5, 0) if across_x else Vector3(0, -column * 0.5, along)
				cylinder(radius, column, STONE.darkened(0.04 * float(index % 2)), at, deck).name = "SteppingStone"
				cylinder(radius * 0.8, 0.012, STONE.lightened(0.10), Vector3(at.x, 0.002, at.z), deck)
		"towpath":
			box(Vector3(width, 0.10, depth), COPING.darkened(0.08), Vector3(0, -0.05, 0), deck)
			var flags := int(length / 0.48)
			for index in range(1, flags):
				var along := float(index) / float(flags) * length - length * 0.5
				box(Vector3(0.014, 0.006, lane - 0.04) if across_x else Vector3(lane - 0.04, 0.006, 0.014), COPING.darkened(0.25), Vector3(along, 0.003, 0) if across_x else Vector3(0, 0.003, along), deck)
		"punt":
			box(Vector3(width, 0.10, depth), TIMBER.lightened(0.15), Vector3(0, -0.05, 0), deck)
			for side in [-1, 1]:
				# Rail tops stay clear of the kept-crossing marker between them.
				box(Vector3(width - 0.012, 0.09, 0.06) if across_x else Vector3(0.06, 0.09, depth - 0.012), TIMBER.darkened(0.1), Vector3(0, 0.005, side * (depth * 0.5 - 0.045)) if across_x else Vector3(side * (width * 0.5 - 0.045), 0.005, 0), deck)
		_:
			for index in range(8):
				var offset := -length / 2.0 + (index + 0.5) * length / 8.0
				var size := Vector3(width / 8.0, 0.10, depth) if across_x else Vector3(width, 0.10, depth / 8.0)
				box(size, Props.TIMBER_LIGHT.darkened(0.05 * float(index % 2)), Vector3(offset, -0.05, 0) if across_x else Vector3(0, -0.05, offset), deck)
			if kind == "gangway":
				for side in [-1, 1]:
					var posts: Array[Vector3] = []
					for t: float in [-0.5, 0.0, 0.5]:
						var at := Vector3(t * (length - 0.08), 0, side * (lane * 0.5 - 0.04)) if across_x else Vector3(side * (lane * 0.5 - 0.04), 0, t * (length - 0.08))
						cylinder(0.025, 0.50, TIMBER.darkened(0.2), at + Vector3(0, 0.25, 0), deck)
						posts.append(at + Vector3(0, 0.46, 0))
					_bar_between(posts[0], posts[2], 0.022, ROPE, deck)
	var tide := not _tide_marks(_gate_for(id).get("when", {})).is_empty()
	for side in [-1, 1]:
		var trim := box(Vector3(width, 0.025, 0.035) if across_x else Vector3(0.035, 0.025, depth), GOLD if tide else LIGHT_COLOR, Vector3(0, 0.015, side * (depth / 2.0 - 0.025)) if across_x else Vector3(side * (width / 2.0 - 0.025), 0.015, 0), deck)
		trim.name = "OpenEdge"
		_glow(trim, GOLD if tide else LIGHT_COLOR, 0.9 if tide else 0.65)
		trim.set_meta("edge", [GOLD if tide else LIGHT_COLOR, 0.9 if tide else 0.65])

## A shut crossing stays in view as a faint outline at its own height (sunk
## under the water when the tide covers it), so the other ways can be read.
func _ghost(route: Dictionary) -> void:
	var id := str(route.id)
	var deck: Node3D = _decks.get(id)
	if deck == null: return
	# The outline leaves out the remembered-footsteps marker (footprints and
	# pennant): it is set aside while the deck is copied, not copied and freed.
	var memories := deck.find_child("RememberedFootsteps", false, false)
	var memories_at := memories.get_index() if memories != null else -1
	if memories != null: deck.remove_child(memories)
	var ghost := deck.duplicate() as Node3D
	if memories != null:
		deck.add_child(memories)
		deck.move_child(memories, memories_at)
	ghost.name = "ShutCrossing_" + id
	var faint := Primitives.fresh_material(Color(CREAM, 0.30))
	faint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	faint.render_priority = -3
	for node: Node in ghost.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).material_override = faint
		(node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	terrain.add_child(ghost)
	ghost.visible = not deck.visible
	_ghosts[id] = ghost

## A mooring post with a pennant, and a gold edge along both sides of the deck,
## show a crossing kept for good. They belong to the deck's remembered-footsteps
## marker, so they show only while kept. The post and its knob cast no shadow,
## so nothing dims the pennant, and the post grows to keep the pennant above
## water that covers the deck.
func _kept_pennant(route: Dictionary) -> void:
	var memories: Node3D = _memory_markers.get(route.id)
	if memories == null: return
	var r: Array = route.rect_cm
	var width := float(r[2] - r[0]) / 100.0
	var depth := float(r[3] - r[1]) / 100.0
	var at := Vector3(-width / 2.0 + 0.10, 0, depth / 2.0 - 0.10)
	var post := box(Vector3(0.06, 0.50, 0.06), CREAM, at + Vector3(0, 0.25, 0), memories)
	post.name = "KeptPost"
	post.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var knob := sphere(0.05, GOLD, at + Vector3(0, 0.52, 0), memories)
	knob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var flag := box(Vector3(0.36, 0.22, 0.015), GOLD, at + Vector3(0.19, 0.38, 0), memories)
	flag.name = "KeptPennant"
	_glow(flag, GOLD, 1.0)
	# The mast rides the water over its crossing (the first body's off the water).
	var body := waters.body_of(r)
	if body.is_empty(): body = waters.first_body()
	var mast := {"deck": float(route.get("height_cm", 0)) / 100.0, "post": post, "knob": knob, "flag": flag}
	_kept_masts.append(mast)
	waters.ride(body, _raise_mast.bind(mast))
	var across_x := width >= depth
	for side in [-1, 1]:
		var edge := box(Vector3(width - 0.05, 0.02, 0.08) if across_x else Vector3(0.08, 0.02, depth - 0.05), GOLD, Vector3(0, 0.035, side * (depth / 2.0 - 0.075)) if across_x else Vector3(side * (width / 2.0 - 0.075), 0.035, 0), memories)
		edge.name = "KeptEdge"
		_glow(edge, GOLD, 1.4)

## A stub's timber frame stays in view while its boards are up, so its pads
## and levers never float; posts carry it down to the harbour floor.
func _stub_frame(route: Dictionary) -> void:
	var r: Array = route.rect_cm
	var y := float(route.height_cm) / 100.0 - 0.07
	var frame := Node3D.new()
	frame.name = "StubFrame_" + str(route.id)
	terrain.add_child(frame)
	var x0 := float(r[0]) / 100.0
	var x1 := float(r[2]) / 100.0
	var z0 := float(r[1]) / 100.0
	var z1 := float(r[3]) / 100.0
	for x: float in [x0 + 0.03, x1 - 0.03]:
		box(Vector3(0.05, 0.08, z1 - z0 - 0.014), PILE, Vector3(x, y, (z0 + z1) * 0.5), frame)
	var tip := z0 + 0.03 if _route_anchor(route).z > z1 else z1 - 0.03
	box(Vector3(x1 - x0 - 0.014, 0.08, 0.05), PILE, Vector3((x0 + x1) * 0.5, y, tip), frame)
	for x: float in [x0 + 0.03, x1 - 0.03]:
		cylinder(0.035, y - waters.seabed(), PILE, Vector3(x, (y + waters.seabed()) * 0.5, tip), frame)

func _piles(route: Dictionary) -> void:
	var r: Array = route.rect_cm
	var top := float(route.height_cm) / 100.0 - 0.10
	for x: int in [r[0] + 10, r[2] - 10]:
		for z: int in [r[1] + 8, r[3] - 8]:
			cylinder(0.05, top - waters.seabed(), PILE, Vector3(float(x) / 100.0, (top + waters.seabed()) * 0.5, float(z) / 100.0), terrain).name = "JettyPile"

# --- Wheels and levers ---

## Every selector names its values in the shared speech bubble over its lever
## (journey_world). The three- and four-way water wheels are valves (pinned
## in the descriptor's "piece_styles"), the control itself.
func _build_selector(control: Dictionary) -> void:
	super._build_selector(control)
	if control.values.size() >= 3 and _lever_pieces[control.id].style == "valve": _register_valve(control)

## A water wheel drawn as a valve: the valve is the control, on its own spot,
## and turns itself; it carries the water's sign on the post behind it, small
## enough to stay clear of a spirit at the wheel.
func _register_valve(control: Dictionary) -> void:
	var look: RefCounted = _lever_pieces[control.id]
	_wheels[control.id] = {"wheel": look.wheel(), "values": control.values.duplicate()}
	if WHEEL_WATER.has(control.id):
		var sign := _water_icon(str(control.id), look.sign_point(), WHEEL_WATER[control.id])
		sign.scale = Vector3.ONE * VALVE_SIGN_SCALE

## A valve's dial: one band for low, two for half, three for high, a bar for
## a shut sea (the tide gauges' bands).
func _look_marks(control: Dictionary) -> Array:
	return control.get("values", []).map(func(value: Variant) -> int: return _water_mark(str(value)))

func _selector_bubble_shift(control: Dictionary) -> float:
	return float(BUBBLE_SHIFTS.get(control.id, 0.0))

## A small upright sign on a valve's post: a wave for the harbour tide, a
## pair of gate leaves for the sea, a walled basin for the chamber.
func _water_icon(id: String, at: Vector3, tint: Color) -> Node3D:
	var icon := Node3D.new()
	icon.name = "WaterIcon_" + id
	icon.position = at
	terrain.add_child(icon)
	box(Vector3(0.34, 0.34, 0.02), CHIP_DARK, Vector3(0, 0, -0.01), icon)
	match id:
		"tide":
			for index in range(4):
				box(Vector3(0.09, 0.03, 0.02), tint, Vector3(-0.11 + float(index) * 0.075, 0.0, 0.0), icon).rotation.z = 0.55 if index % 2 == 0 else -0.55
		"basin":
			for side in [-1, 1]: box(Vector3(0.07, 0.20, 0.02), tint, Vector3(side * 0.06, -0.01, 0.0), icon)
			box(Vector3(0.24, 0.03, 0.02), tint, Vector3(0, 0.11, 0.0), icon)
		_:
			for side in [-1, 1]: box(Vector3(0.03, 0.20, 0.02), tint, Vector3(side * 0.10, 0.0, 0.0), icon)
			box(Vector3(0.23, 0.03, 0.02), tint, Vector3(0, -0.10, 0.0), icon)
			box(Vector3(0.17, 0.07, 0.02), tint.lightened(0.2), Vector3(0, -0.05, 0.005), icon)
	return icon

## Every lever and selector takes its style (the dressing's brass, or a pinned
## machine); a lever also carries a lamp that says whether it is on, whatever
## its style.
func _build_lever(lever: Dictionary) -> void:
	super._build_lever(lever)
	if lever.get("kind", "") == "selector": return
	# Levers toggle, so a lamp beside the handle says plainly whether it is on.
	var lamp := sphere(0.07, Color("4a4038"), _at(lever) + Vector3(0.24, 0.22, 0.0), terrain)
	lamp.name = "LeverLamp_" + str(lever.id)
	box(Vector3(0.03, 0.18, 0.03), TIMBER, _at(lever) + Vector3(0.24, 0.09, 0.0), terrain)
	_lever_lamps[lever.id] = {"lamp": lamp, "color": GOLD if lever.owner_slot == "p0" else TEAL}

# --- Gate links: tide gauges, crests and the catwalks' slack marks ---

func _build_gate_links(view: Dictionary) -> void:
	var entities: Array = view.get("controls", []) + view.get("levers", []) + view.get("pressure_pads", [])
	# The tide's own wheel shows on every crossing's gauge, never as a pair tag.
	pair_tags.skip("tide")
	for gate: Dictionary in view.get("gates", []):
		var route: Dictionary = {}
		for candidate: Dictionary in view.bridges + view.get("stairs", []):
			if candidate.id == gate.route_id: route = candidate
		if route.is_empty(): continue
		var when: Dictionary = gate.get("when", {})
		var references := PairTags.predicate_references(when)
		# Eleven routes read the tide in the first stage alone: each gets a gauge
		# post with its bands rather than a crest or cable back to the wheel.
		var marks := _tide_marks(when)
		if not marks.is_empty(): _build_gauge(route, marks)
		if when.has("any") and "basin" in references and "tide" in references:
			_catwalks.append(str(route.id))
			_build_slack_mark(route)
		if _is_stub(route) and route.get("owner_slot", "") == "p1":
			# The second spirit's stubs say all at their mouths: a post's sea bands,
			# the gate catwalk's slack mark, or the shut-sea mark of a catwalk that
			# reads the sea alone, with its chain or bar right beside it.
			if _carries_pad(view, str(route.id)):
				var sea := _sea_value(when)
				if not sea.is_empty(): _build_post_mark(route, sea)
			elif str(route.id) not in _catwalks and "basin" in references and "tide" not in references:
				_build_dry_mark(route)
			pair_tags.skip("", str(route.id))
			continue
		var others: Array = references.filter(func(id: String) -> bool: return id != "tide")
		var end := _route_anchor(route)
		for index in range(others.size()):
			var id: String = others[index]
			var entity: Dictionary = {}
			for item: Dictionary in entities:
				if item.id == id: entity = item
			if entity.is_empty(): continue
			var start := _at(entity) + Vector3(0, 0.025, 0)
			var spot := end + Vector3(0, 0, (float(index) - float(others.size() - 1) * 0.5) * 0.26)
			var color := _route_color(id)
			if _shares_floor(start, spot):
				var elbow := Vector3(spot.x, start.y, start.z)
				if start.distance_to(elbow) > 0.01: _floor_cable(start, elbow, 0.016, color.darkened(0.25))
				if elbow.distance_to(spot) > 0.01: _floor_cable(elbow, spot, 0.016, color.darkened(0.25))
		# The sea gate out waits on the key from the mill: a large key sign over
		# the gate, facing the chamber and the gate in.
		if str(route.id) == "sea-gate-out" and "sea-key" in references: _key_sign(route)

func _key_sign(route: Dictionary) -> void:
	var r: Array = route.rect_cm
	var sign := Node3D.new()
	sign.name = "KeySign_" + str(route.id)
	sign.position = point([r[2] - 6, r[1] - 10]) + Vector3(0, float(route.height_cm) / 100.0, 0)
	terrain.add_child(sign)
	cylinder(0.03, 1.10, TIMBER.darkened(0.2), Vector3(0, 0.55, 0), sign)
	box(Vector3(0.50, 0.42, 0.03), CHIP_DARK, Vector3(0, 1.20, 0), sign)
	box(Vector3(0.54, 0.46, 0.02), GOLD.darkened(0.2), Vector3(0, 1.20, -0.012), sign)
	var glyph := Node3D.new()
	glyph.position = Vector3(0, 1.20, 0.025)
	# Turned up to face the camera: the tile's face toward it, the letter upright.
	glyph.rotation.x = PI / 2.0
	glyph.scale = Vector3.ONE * 1.4
	sign.add_child(glyph)
	# The key's pair tag, standing on the sign.
	pair_tags.tag("sea-key", PairTags.SIGN, Vector3.ZERO, glyph)

## Tide values a gate needs outright (through "all" only), low to high.
func _tide_marks(predicate: Dictionary) -> Array:
	return WaterBodies.control_marks(predicate, "tide")

## How many bands mark a water value: 1 for low, 2 for half, 3 for high, none
## for any other (a shut sea).
func _water_mark(value: String) -> int:
	return waters.mark_levels().keys().find(value) + 1

## Where a route's marks and pair tags sit: a stub's mouth on its own floor,
## or just before a crossing's west end, at the route's own height.
func _route_anchor(route: Dictionary) -> Vector3:
	var r: Array = route.rect_cm
	var height := float(route.get("height_cm", route.get("from_height_cm", 0))) / 100.0 + 0.025
	if _is_stub(route):
		for island: Dictionary in chapter_definition.islands:
			if island.id != route.get("from_surface", ""): continue
			var floor: Array = island.rect_cm
			if int(r[3]) <= int(floor[1]): return point([(r[0] + r[2]) * 0.5, r[3] + 16]) + Vector3(0, height, 0)
			if int(r[1]) >= int(floor[3]): return point([(r[0] + r[2]) * 0.5, r[1] - 16]) + Vector3(0, height, 0)
	return point([r[0] - 18, (r[1] + r[3]) * 0.5]) + Vector3(0, height, 0)

## A gate's pair tags start at its route's anchor, on the floor (a stub's
## mouth, else before its west end), else by its far end.
func _pair_gate_anchors(route: Dictionary) -> Array:
	var ends := super._pair_gate_anchors(route)
	return [_route_anchor(route) - Vector3(0, 0.025, 0), ends[1]]

## Pair tags keep clear of the gauges and mouth marks built at the routes,
## and of the route barriers.
func _pair_keep_clear() -> Array:
	var found: Array = super._pair_keep_clear()
	for gauge: Dictionary in _gauges.values(): found.append({"centre": Vector2(gauge.post.position.x, gauge.post.position.z), "radius": 0.12, "what": "gauge " + str(gauge.post.name)})
	var marks: Array = _slack_marks.duplicate()
	for entry: Dictionary in _post_marks.values(): marks.append_array(entry.bands)
	for planks: Array in _dry_marks.values(): marks.append_array(planks)
	for mark: Node3D in marks: found.append({"centre": Vector2(mark.position.x, mark.position.z), "radius": 0.16, "y": mark.position.y, "what": str(mark.name)})
	return found

func _route_color(id: String) -> Color:
	return GOLD if _owners.get(id, "") == "p0" else TEAL

func _carries_pad(view: Dictionary, surface_id: String) -> bool:
	for pad: Dictionary in view.get("pressure_pads", []):
		if pad.get("surface_id", "") == surface_id: return true
	return false

## The sea value a gate needs outright, or "" when it needs none.
func _sea_value(predicate: Dictionary) -> String:
	var marks := WaterBodies.control_marks(predicate, "basin")
	return "" if marks.is_empty() else str(marks[0])

## A post's mouth shows the sea value it rises at: 1, 2 or 3 teal bands.
func _build_post_mark(route: Dictionary, value: String) -> void:
	var at := _route_anchor(route)
	var bands: Array[MeshInstance3D] = []
	var count := _water_mark(value)
	for index in range(count):
		var band := box(Vector3(0.05, 0.014, 0.20), TEAL.darkened(0.2), at + Vector3((float(index) - float(count - 1) * 0.5) * 0.10, 0.002, 0), terrain)
		band.name = "PostMark_" + str(route.id)
		bands.append(band)
	_post_marks[route.id] = {"value": value, "bands": bands}

## A gauge post beside a tide crossing: 1, 2 or 3 bands for low, half or high,
## capped with a wave sign that keeps its size on screen.
## A crossing over water stands its post in the channel; a stub on its floor.
func _build_gauge(route: Dictionary, values: Array) -> void:
	var r: Array = route.rect_cm
	var base := waters.seabed()
	var at := point([r[0] + 16, r[3] + 12])
	var top := float(route.get("height_cm", 0)) / 100.0 + 0.92
	if route.has("axis"):
		at = point([r[2] + 12, (r[1] + r[3]) * 0.5])
		top = maxf(float(route.from_height_cm), float(route.to_height_cm)) / 100.0 + 0.90
	elif _is_stub(route):
		# Past the coping's corner when the stub is walled, else beside its deck.
		var out := 17 if str(route.id) in waters.walled else 10
		at = point([r[2] + out, r[3] + 10]) if _route_anchor(route).z > float(r[3]) / 100.0 else point([r[2] + out, r[1] - 10])
		base = float(route.height_cm) / 100.0
		top = base + 0.85
	var post := Node3D.new()
	post.name = "TideGauge_" + str(route.id)
	post.position = at
	terrain.add_child(post)
	cylinder(0.045, top - base, CREAM.darkened(0.15), Vector3(0, (top + base) * 0.5, 0), post)
	var bands: Array[MeshInstance3D] = []
	var count := 0
	for value: String in values: count = maxi(count, _water_mark(value))
	for index in range(count):
		var band := cylinder(0.10, 0.09, GOLD, Vector3(0, top - 0.10 - float(index) * 0.15, 0), post)
		band.name = "GaugeBand"
		bands.append(band)
	var icon := Badges.glyph(post, "~".repeat(count), Vector3(0, top + 0.06, 0), GOLD, CHIP_DARK)
	icon.name = "GaugeWaves"
	_gauges[route.id] = {"bands": bands, "values": values.duplicate(), "post": post, "icon": icon}

## A catwalk that reads the sea alone: a plank across its mouth glows while
## the sea leaves it dry (the same for both spirits, as the sea is copied).
func _build_dry_mark(route: Dictionary) -> void:
	var plank := box(Vector3(0.26, 0.014, 0.06), TEAL.darkened(0.2), _route_anchor(route) + Vector3(0, 0.002, 0), terrain)
	plank.name = "DryMark_" + str(route.id)
	_dry_marks[route.id] = [plank]

## The catwalk mouth's slack mark glows while the catwalk is dry.
func _build_slack_mark(route: Dictionary) -> void:
	var at := _route_anchor(route)
	for side: int in [-1, 1]:
		var wave := box(Vector3(0.24, 0.014, 0.04), TEAL.darkened(0.2), at + Vector3(0.0, 0.002, float(side) * 0.06), terrain)
		wave.name = "SlackMark_" + str(route.id)
		_slack_marks.append(wave)

# --- Water, chamber, sea gates, mouth lamps and spout ---

## Keeps a kept crossing's pennant MAST_CLEARANCE above the water at `level`.
func _raise_mast(level: float, mast: Dictionary) -> void:
	if not is_instance_valid(mast.post): return
	var lift := maxf(0.0, level + MAST_CLEARANCE - (float(mast.deck) + 0.50))
	var post: MeshInstance3D = mast.post
	post.scale.y = (0.50 + lift) / 0.50
	post.position.y = (0.50 + lift) * 0.5
	(mast.knob as Node3D).position.y = 0.52 + lift
	(mast.flag as Node3D).position.y = 0.38 + lift

func _advance_water(delta: float) -> void:
	_clock += maxf(delta, 0.0)
	waters.advance(delta)
	_swing_ramps(delta)
	if not _drowned_slot.is_empty() and not reduced_motion:
		var grown := minf(_drown_ring.scale.x + delta * 1.6, 3.0)
		_drown_ring.scale = Vector3(grown, 1.0, grown)
		_bubble_age += maxf(delta, 0.0)
		_rise_bubbles()
	waters.advance_fade(delta)
	if not reduced_motion:
		waters.bob()
		# Pale streaks run down the falling water.
		if is_instance_valid(_spout) and _spout.visible:
			for streak: MeshInstance3D in _spout_streaks:
				var span := float(streak.get_meta("span"))
				var phase := fmod(_clock * 0.9 + float(streak.get_meta("phase")), 1.0)
				streak.position.y = float(streak.get_meta("top")) - phase * span

func _build_chamber() -> void:
	var pit: Array = waters.body_data("chamber").rects[0]
	var west := float(pit[0]) / 100.0
	var east := float(pit[2]) / 100.0
	var seabed := waters.seabed()
	var height := CHAMBER_WALL_TOP - seabed
	for z_side: Array in [[pit[1], -96], [96, pit[3]]]:
		var middle := float(z_side[0] + z_side[1]) / 200.0
		var depth := float(z_side[1] - z_side[0]) / 100.0
		for x: float in [west, east]:
			var side := box(Vector3(0.06, height, depth), STONE_DARK, Vector3(x, seabed + height * 0.5, middle), terrain)
			side.name = "ChamberWall"
			waters.holds_water(side)
	for z: float in [float(pit[1]) / 100.0, float(pit[3]) / 100.0]:
		var end := box(Vector3(east - west + 0.06, height, 0.06), STONE_DARK, Vector3((west + east) * 0.5, seabed + height * 0.5, z), terrain)
		end.name = "ChamberWall"
		waters.holds_water(end)
		# A lamp on each inner corner glows while the chamber matches the harbour.
		var lamp := sphere(0.07, Color("4a4038"), Vector3(east, CHAMBER_WALL_TOP + 0.10, z), terrain)
		lamp.name = "ChamberMatched"
		_chamber_lamps.append(lamp)

func _build_sea_gates() -> void:
	# Leaves across both ends of the harbour mouth: closed while the sea is shut.
	var west := float(MOUTH_X[0]) / 100.0
	var east := float(MOUTH_X[1]) / 100.0
	var span := (east - west) * 0.5
	for z: float in [-SEA_GATE_Z, SEA_GATE_Z]:
		for side: int in [-1, 1]:
			var hinge := Node3D.new()
			hinge.name = "SeaGateLeaf"
			hinge.position = Vector3(west if side < 0 else east, 0, z)
			terrain.add_child(hinge)
			# The leaf stops 2 cm under high water, inside its cap.
			box(Vector3(span - 0.02, 1.28, 0.08), TIMBER, Vector3(-side * (span * 0.5), waters.seabed() + 0.74, 0), hinge)
			box(Vector3(span - 0.034, 0.05, 0.10), TIMBER.darkened(0.2), Vector3(-side * (span * 0.5), 0.70, 0), hinge)
			hinge.set_meta("side", side)
			hinge.set_meta("outward", 1.0 if z > 0 else -1.0)
			_sea_gates.append(hinge)

func _build_mouth_lamps() -> void:
	# A teal lamp at each mouth crossing lights for the sea value it serves.
	for value: String in MOUTHS:
		var route: Dictionary = {}
		for candidate: Dictionary in chapter_definition.get("bridges", []):
			if candidate.id == MOUTHS[value]: route = candidate
		if route.is_empty(): continue
		var r: Array = route.rect_cm
		var at := point([r[0] + 40, r[3] + 12])
		var top := 1.20
		cylinder(0.035, top - waters.seabed(), TIMBER.darkened(0.1), at + Vector3(0, (top + waters.seabed()) * 0.5, 0), terrain)
		for band in range(_water_mark(value)):
			cylinder(0.05, 0.03, TEAL, at + Vector3(0, top - 0.24 - float(band) * 0.07, 0), terrain)
		var lamp := sphere(0.08, Color("4a4038"), at + Vector3(0, top + 0.06, 0), terrain)
		lamp.name = "MouthLamp_" + value
		_mouth_lamps[value] = lamp

## The spout: a pale ribbon of falling water from the aqueduct to the beach,
## with streaks running down it, foam and a splash ring where it lands, and a
## glowing teal lip round the opening while the sluice runs.
func _build_spout() -> void:
	for drop: Dictionary in current_level.get("drops", []):
		var r: Array = drop.rect_cm
		var top := _surface_height(str(drop.surface_id))
		var bottom := float(drop.get("height_cm", 0)) / 100.0
		_spout = Node3D.new()
		_spout.name = "SpoutWater"
		_spout.position = point([(r[0] + r[2]) * 0.5, (r[1] + r[3]) * 0.5])
		terrain.add_child(_spout)
		var width := float(r[2] - r[0]) / 100.0 - 0.08
		var fall := Primitives.mesh_node(Primitives.box_mesh(Vector3(width, top - bottom + 0.06, 0.10)), Primitives.fresh_material(Color(SPOUT, 0.80), 0.2), Vector3(0, (top + bottom) * 0.5 + 0.03, 0.04), _spout)
		fall.name = "SpoutRibbon"
		fall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_glow(fall, SPOUT, 0.6)
		var core := Primitives.mesh_node(Primitives.box_mesh(Vector3(width * 0.55, top - bottom, 0.14)), Primitives.fresh_material(Color(1, 1, 1, 0.55), 0.2), Vector3(0, (top + bottom) * 0.5, 0.04), _spout)
		core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_glow(core, Color("eaf8fa"), 0.5)
		# Streaks run down the front of the falling water.
		for index in range(4):
			var streak := box(Vector3(0.03, 0.14, 0.012), CREAM, Vector3((float(index) - 1.5) * 0.08, top - 0.10, 0.10), _spout)
			streak.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_glow(streak, CREAM, 0.6)
			streak.set_meta("top", top - 0.08)
			streak.set_meta("span", top - bottom - 0.16)
			streak.set_meta("phase", float(index) * 0.27)
			streak.position.y = top - 0.08 - fmod(float(index) * 0.27, 1.0) * (top - bottom - 0.16)
			_spout_streaks.append(streak)
		var foam := cylinder(0.46, 0.012, Color("eef7f4"), Vector3(0, bottom + 0.012, 0.10), _spout)
		foam.name = "SpoutFoam"
		_glow(foam, Color("eef7f4"), 0.3)
		var splash := ring(0.52, Color("d7ecec"), Vector3(0, bottom + 0.03, 0.10), _spout)
		splash.scale.y = 0.5
		for index in range(5):
			var spray := sphere(0.05, Color("f4fbfb"), Vector3((float(index) - 2.0) * 0.12, bottom + 0.10 + 0.05 * float(index % 2), 0.40), _spout)
			spray.name = "SpoutSpray"
			_glow(spray, Color("f4fbfb"), 0.4)
		# The sluice sends water along the aqueduct to the opening: a pale rill
		# down the feeder and the span, seen from above while it runs.
		var rill := Primitives.fresh_material(Color(SPOUT, 0.85), 0.2)
		rill.render_priority = 1
		for island: Dictionary in chapter_definition.get("islands", []):
			if str(island.id) not in waters.water.get("piers", []): continue
			var a: Array = island.rect_cm
			var along_x: bool = int(a[2] - a[0]) >= int(a[3] - a[1])
			var from := Vector3(float(a[0]) / 100.0 + 0.04, top + 0.008, float(a[1] + a[3]) / 200.0) if along_x else Vector3(float(a[0] + a[2]) / 200.0, top + 0.008, float(a[1]) / 100.0 + 0.04)
			var to := Vector3(float(r[0]) / 100.0, top + 0.008, from.z) if along_x else Vector3(from.x, top + 0.008, float(a[3]) / 100.0 - 0.04)
			var flow := Primitives.mesh_node(Primitives.box_mesh(Vector3(absf(to.x - from.x), 0.008, 0.20) if along_x else Vector3(0.20, 0.008, absf(to.z - from.z))), rill, (from + to) * 0.5 - _spout.position, _spout)
			flow.name = "AqueductRill"
			flow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for side in [-1, 1]:
			var lip := box(Vector3(float(r[2] - r[0]) / 100.0 - 0.014, 0.03, 0.03), TEAL, Vector3(0, top + 0.02, side * float(r[3] - r[1]) / 200.0), _spout)
			_glow(lip, TEAL, 0.8)
		_spout.set_meta("lever", str(drop.get("requires_lever", "")))
		_spout.visible = false
		# The lip only the second spirit may cross, at the access zone's edge.
		for zone: Dictionary in current_level.get("access_zones", []):
			if zone.surface_id != drop.surface_id: continue
			var z: Array = zone.rect_cm
			box(Vector3(0.05, 0.04, float(z[3] - z[1]) / 100.0 - 0.04), TEAL, Vector3(float(z[0]) / 100.0 - 0.03, top + 0.02, float(z[1] + z[3]) / 200.0), terrain).name = "SpoutLip"
		return

# --- The harbour's edges: foreshore, moored boats, lamplight ---

## South of the beaches a fixed foreshore of wet sand runs out to shallow
## water; it never follows the tide, and it carries the beach catwalk's piles.
func _build_foreshore() -> void:
	var root := Node3D.new()
	root.name = "Foreshore"
	terrain.add_child(root)
	box(Vector3(27.2, 0.40, 1.60), Color("b7a27a"), Vector3(3.84, -0.50, 5.60), root).name = "WetSand"
	var shallow := Primitives.mesh_node(Primitives.box_mesh(Vector3(27.2, 0.06, 0.80)), Primitives.fresh_material(Color(0.36, 0.55, 0.58, 0.55), 0.3), Vector3(3.84, -0.27, 6.00), root)
	shallow.name = "Shallows"
	shallow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	box(Vector3(27.2, 0.012, 0.05), Color("eef2e6"), Vector3(3.84, -0.235, 5.62), root).name = "SurfLine"
	# Shells and a darker wet edge along the sand.
	for index in range(18):
		var x := -9.2 + float(index) * 1.49
		cylinder(0.035, 0.01, Color("f1e4d0") if index % 3 else Color("e7c0b0"), Vector3(x, -0.295, 5.05 + 0.18 * float(index % 4)), root)

## Rowboats moored in the channels (the dressing's "moored_boats") ride their
## water's level (and bob unless motion is reduced): a second cue for the tide.
func _build_boats() -> void:
	for spec: Dictionary in dressing.get("moored_boats", []):
		var boat := Node3D.new()
		boat.name = "MooredBoat"
		boat.position = point(spec.at)
		boat.rotation.y = float(spec.heading)
		boat.set_meta("phase", float(spec.at[0]) * 0.013)
		terrain.add_child(boat)
		box(Vector3(0.40, 0.14, 0.92), TIMBER.lightened(0.10), Vector3(0, 0.05, 0), boat)
		box(Vector3(0.32, 0.06, 0.82), TIMBER.darkened(0.25), Vector3(0, 0.10, 0), boat)
		box(Vector3(0.24, 0.10, 0.20), TIMBER.lightened(0.10), Vector3(0, 0.06, 0.48), boat)
		for z: float in [-0.18, 0.18]: box(Vector3(0.38, 0.03, 0.08), TIMBER.lightened(0.20), Vector3(0, 0.13, z), boat)
		cylinder(0.035, waters.wall_top() + 0.12 - waters.seabed(), PILE, Vector3(float(spec.at[0]) / 100.0 + 0.32, (waters.wall_top() + 0.12 + waters.seabed()) * 0.5, float(spec.at[1]) / 100.0 - 0.36), terrain).name = "MooringPile"
		_boats.append(boat)
		waters.ride(str(spec.water), _float_boat.bind(boat), true)

## A winch's ramp: a crossing (never a stub or a stair) whose gate, in any
## stage, needs a water value and another selector's value lies flat in it as
## a ramp at that value, at any water; raised, it stands up out of the water.
## It follows the snapshot's selector value, so it moves the moment the winch
## is turned. Crossing id -> [selector id, value].
func _ramp_selectors() -> Dictionary:
	var water_selectors: Array = waters.water.get("bodies", []).map(func(body: Dictionary) -> String: return str(body.selector))
	var found := {}
	for stage: Dictionary in chapter_definition.get("stages", []):
		for gate: Dictionary in stage.get("gates", []):
			var route := _route(str(gate.route_id))
			if route.is_empty() or route.has("axis") or _is_stub(route) or found.has(str(route.id)): continue
			var when: Dictionary = gate.get("when", {})
			var wet := false
			var other: Array = []
			for term: Dictionary in [when] + when.get("all", []):
				var control := str(term.get("control_id", ""))
				if control.is_empty(): continue
				if control in water_selectors: wet = true
				elif other.is_empty(): other = [control, str(term.get("value", ""))]
			if wet and not other.is_empty(): found[str(route.id)] = other
	return found

## Each ramp crossing (_ramp_selectors) gets a timber ramp on a hinge at its
## west end, with a winch drum on two posts beside the hinge. It starts raised;
## present() sets where it heads.
func _build_ramps() -> void:
	_ramp_on = _ramp_selectors()
	for id: String in _ramp_on:
		var route := _route(id)
		var r: Array = route.rect_cm
		var length := float(r[2] - r[0]) / 100.0
		var lane := float(r[3] - r[1]) / 100.0
		var hinge := Node3D.new()
		hinge.name = "SlipRamp_" + id
		hinge.position = point([r[0], (r[1] + r[3]) / 2.0]) + Vector3(0, float(route.height_cm) / 100.0 - 0.035, 0)
		terrain.add_child(hinge)
		for index in range(6):
			var along := (float(index) + 0.5) / 6.0 * length
			box(Vector3(length / 6.0 - 0.012, 0.05, lane - 0.28), TIMBER.lightened(0.08 * float(index % 2)), Vector3(along, 0, 0), hinge)
		for side in [-1, 1]:
			box(Vector3(length, 0.06, 0.05), TIMBER.darkened(0.2), Vector3(length * 0.5, 0.02, side * (lane * 0.5 - 0.125)), hinge)
			cylinder(0.04, 0.42, PILE, Vector3(-0.06, 0.21, side * (lane * 0.5 - 0.06)) + hinge.position, terrain).name = "RampPost"
		var drum := cylinder(0.07, lane - 0.16, ROPE.darkened(0.15), hinge.position + Vector3(-0.06, 0.36, 0), terrain)
		drum.name = "RampDrum"
		drum.rotation.x = PI / 2.0
		hinge.rotation.z = RAMP_RAISED
		hinge.set_meta("target", RAMP_RAISED)
		_ramps[id] = hinge

## Where each ramp heads from the snapshot's controls.
func _aim_ramps(controls: Dictionary, immediate: bool) -> void:
	for id: String in _ramps:
		var hinge: Node3D = _ramps[id]
		var lowered := str(controls.get(str(_ramp_on[id][0]), "")) == str(_ramp_on[id][1])
		hinge.set_meta("target", 0.0 if lowered else RAMP_RAISED)
		if immediate or reduced_motion: hinge.rotation.z = float(hinge.get_meta("target"))

func _swing_ramps(delta: float) -> void:
	for hinge: Node3D in _ramps.values():
		if not is_instance_valid(hinge): continue
		var target := float(hinge.get_meta("target"))
		if not is_equal_approx(hinge.rotation.z, target): hinge.rotation.z = move_toward(hinge.rotation.z, target, RAMP_RATE * maxf(delta, 0.0))

## Tide rules: while a crossing closes (route id -> ticks left before it
## shuts, from the snapshot), its edges flash and the water still moving
## slows to reach its new level as the crossing shuts, so the warning is the
## water rising over it. Nothing here in rules without closing crossings.
func _show_closing(closing: Dictionary) -> void:
	for id: String in _decks:
		var deck: Node3D = _decks[id]
		if not is_instance_valid(deck): continue
		for child: Node in deck.get_children():
			var trim := child as MeshInstance3D
			if trim == null or not trim.has_meta("edge"): continue
			if closing.has(id):
				if not trim.has_meta("warned"):
					var warned_material := trim.material_override.duplicate()
					# A copy is never a kit look, whatever it was copied from.
					warned_material.remove_meta(Primitives.SHARED_META)
					trim.material_override = warned_material
					trim.set_meta("warned", true)
				# Reduce motion: a steady glow instead of a flash.
				_glow(trim, CLOSING_COLOR, 1.1 if reduced_motion else (1.6 if int(closing[id]) % 10 < 5 else 0.5))
			elif trim.has_meta("warned"):
				var edge: Array = trim.get_meta("edge")
				_glow(trim, edge[0], float(edge[1]))
	# Water rising past a closing crossing's deck reaches it as the crossing
	# shuts, then goes on at its usual rate.
	waters.pace_closing(closing)

## Tide rules: a drowned spirit (snapshot "drowned": {slot, route}) heads under
## the water over its crossing with its knocked-out face, a ring spreads and
## bubbles rise where it went down, and the camera eases over to it (snapping
## under Reduce motion), so a drowning off screen is seen before the card. A
## snapshot without a drowning (a retry, a replay seeking back) puts it all
## away again.
func _show_drowned(drowned: Dictionary) -> void:
	if drowned.is_empty() or not actors.has(str(drowned.get("slot", ""))):
		if not _drowned_slot.is_empty(): _clear_drowned()
		return
	var slot := str(drowned.slot)
	camera_focus = slot
	# The water over the crossing it drowned on: the harbour's or the outer sea's.
	var body: Node3D = waters.bodies.get(waters.body_of(_route(str(drowned.get("route", ""))).get("rect_cm", [0, 0, 0, 0])))
	if not is_instance_valid(body): body = waters.bodies.get(waters.first_body())
	var surface: float = float(body.get_meta("shown")) if is_instance_valid(body) else float(actor_targets[slot].y)
	var target: Vector3 = actor_targets[slot]
	target.y = minf(target.y, surface) - DROWN_DEPTH
	actor_targets[slot] = target
	if _drowned_slot == slot: return
	_drowned_slot = slot
	_drown_surface = surface
	_bubble_age = 0.0
	# A held face, so a replay seek keeps it; a doze would outrank it, so none.
	var spirit := actors[slot] as SpiritVisual
	if spirit.pose() == &"doze": spirit.set_pose(&"rest", {}, true)
	spirit.set_expression(KNOCKED_OUT, reduced_motion)
	if not is_instance_valid(_drown_ring):
		_drown_ring = cylinder(0.32, 0.01, Color(CREAM, 0.7), Vector3.ZERO, terrain)
		_drown_ring.name = "DrownRing"
		for spec: Array in DROWN_BUBBLES:
			var bubble := sphere(float(spec[3]), Color(CREAM, 0.85), Vector3.ZERO, terrain)
			bubble.name = "DrownBubble"
			_drown_bubbles.append(bubble)
	_drown_ring.position = Vector3(target.x, surface + 0.02, target.z)
	_drown_ring.scale = Vector3.ONE
	_drown_ring.visible = true
	for index in range(_drown_bubbles.size()):
		var spec: Array = DROWN_BUBBLES[index]
		_drown_bubbles[index].position = Vector3(target.x + float(spec[0]), 0.0, target.z + float(spec[1]))
		_drown_bubbles[index].visible = true
	_rise_bubbles()

## Each bubble climbs BUBBLE_RISE above the water and starts again, from its
## own phase; still at that phase under Reduce motion.
func _rise_bubbles() -> void:
	for index in range(_drown_bubbles.size()):
		var phase := fmod(float(DROWN_BUBBLES[index][2]) + _bubble_age * BUBBLE_SPEED / BUBBLE_RISE, 1.0)
		_drown_bubbles[index].position.y = _drown_surface + 0.03 + phase * BUBBLE_RISE

func _clear_drowned() -> void:
	if actors.has(_drowned_slot): (actors[_drowned_slot] as SpiritVisual).set_expression(SpiritLook.NORMAL, true)
	if camera_focus == _drowned_slot: camera_focus = ""
	_drowned_slot = ""
	if is_instance_valid(_drown_ring): _drown_ring.visible = false
	for bubble: MeshInstance3D in _drown_bubbles: bubble.visible = false

func _float_boat(level: float, boat: Node3D) -> void:
	if not is_instance_valid(boat): return
	var bob := 0.0 if reduced_motion else sin(_clock * 1.4 + float(boat.get_meta("phase"))) * 0.018
	boat.position.y = level - 0.02 + bob

## Warm pools of light under the bank lamps that name "bunting" in the
## dressing, and bunting strung from each to that point along its bank.
func _build_lamplight() -> void:
	var bunting := [Color("e9a3a0"), Color("f1c27d"), Color("91d6c6"), Color("f4ecd0")]
	for spec: Dictionary in DressingCatalog.stage_props(dressing, displayed_stage_id):
		if str(spec.get("kind", "")) != "lamp_post" or not spec.has("bunting"): continue
		var ground := _surface_height(str(spec.get("surface", ""))) + float(spec.get("y", 0)) / 100.0 + 0.01
		var foot := point(spec.at) + Vector3(0, ground, 0)
		var pool := cylinder(0.62, 0.006, Color(1.0, 0.82, 0.5, 0.30), foot + Vector3(0, 0.005, 0), terrain)
		pool.name = "LampPool"
		Primitives.own_material(pool).shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var from := foot + Vector3(0, 1.30, 0)
		var to := point(spec.bunting) + Vector3(0, ground + 0.95, 0)
		cylinder(0.025, 0.95, TIMBER.darkened(0.2), point(spec.bunting) + Vector3(0, ground + 0.475, 0), terrain)
		_bar_between(from, to, 0.012, ROPE, terrain)
		for index in range(1, 8):
			var t := float(index) / 8.0
			var at := from.lerp(to, t) + Vector3(0, -0.10 * sin(t * PI), 0)
			var flag := box(Vector3(0.10, 0.12, 0.01), bunting[index % bunting.size()], at + Vector3(0, -0.07, 0), terrain)
			flag.name = "Bunting"
			flag.rotation.z = PI / 4.0
			flag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

# --- History, presentation and camera ---

func present_history(checkpoint: Dictionary) -> void:
	_show_first_stage()
	super.present_history(checkpoint)
	# The kept-crossing marks are drawn at ground level by the shared adapter;
	# raise each pair to its crossing's height.
	if is_instance_valid(_remembered):
		var index := 0
		for route: Dictionary in chapter_definition.get("bridges", []):
			if route.id not in _latched_bridge_ids: continue
			for offset in range(2):
				if index + offset < _remembered.get_child_count():
					(_remembered.get_child(index + offset) as Node3D).position.y += float(route.get("height_cm", 0)) / 100.0
			index += 2
	_history_tide = str(checkpoint.get("mechanisms", {}).get("controls", {}).get("tide", ""))

func present(state: Dictionary, immediate: bool = false) -> void:
	super.present(state, immediate)
	if not state.has("players"): return
	var controls: Dictionary = state.get("controls", {})
	var levers: Dictionary = state.get("levers", {})
	var tide := str(controls.get("tide", "low"))
	var basin := str(controls.get("basin", "shut"))
	# Both worlds of a stage open from the same checkpoint, so its first tick
	# shows the remembered tide when no history was supplied.
	if _history_tide.is_empty() and int(state.get("tick", -1)) == 0: _history_tide = tide
	for id: String in _wheels:
		var wheel: Dictionary = _wheels[id]
		var chosen: int = wheel.values.find(controls.get(id, ""))
		if chosen < 0: continue
		# The valve turned itself with the journey switches.
		wheel.wheel.set_meta("value", str(controls.get(id, "")))
	_follow_knobs()
	_aim_ramps(controls, immediate)
	waters.present_controls(controls, immediate)
	for id: String in _gauges:
		var gauge: Dictionary = _gauges[id]
		var lit: bool = tide in gauge.values
		for band: MeshInstance3D in gauge.bands: _glow(band, GOLD, 0.9 if lit else 0.0)
		gauge.icon.modulate = GOLD if lit else Color(GOLD, 0.5)
		gauge.post.set_meta("lit", lit)
	for value: String in _mouth_lamps: _lamp(_mouth_lamps[value], TEAL, basin == value)
	for id: String in _lever_lamps: _lamp(_lever_lamps[id].lamp, _lever_lamps[id].color, bool(levers.get(id, false)))
	var matched := controls.has("chamber") and str(controls.get("chamber")) == tide
	for lamp: MeshInstance3D in _chamber_lamps: _lamp(lamp, GOLD, matched)
	for hinge: Node3D in _sea_gates:
		# Open leaves swing in along the mouth, staying in the water.
		hinge.rotation.y = 0.0 if basin == "shut" else -float(hinge.get_meta("side")) * float(hinge.get_meta("outward")) * 1.35
		hinge.set_meta("open", basin != "shut")
	var pouring := false
	if is_instance_valid(_spout):
		_spout.visible = bool(levers.get(str(_spout.get_meta("lever")), false))
		pouring = _spout.visible
	# Every stage reports it, so a stage without a spout silences the last one.
	note_motion("spout", "spout", 1 if pouring else 0, false)
	# Catwalks read "dry at slack" from the remembered tide: the second spirit
	# walks them under that tide even after the first has turned the wheel.
	var slack_tide := _history_tide if not _history_tide.is_empty() else tide
	var dry := basin == slack_tide
	var kept_now: Array = state.get("route_progress", {}).get("entered_routes", [])
	for id: String in _catwalks:
		if not _decks.has(id): continue
		_decks[id].visible = dry or id in _latched_bridge_ids
		_memory_markers[id].visible = _decks[id].visible and (id in _latched_bridge_ids or id in kept_now)
		_decks[id].set_meta("dry", dry)
	for mark: MeshInstance3D in _slack_marks: _glow(mark, TEAL, 0.9 if dry else 0.0)
	var routes: Dictionary = state.get("bridges", {})
	for id: String in _dry_marks:
		var open := bool(routes.get(id, false))
		for mark: MeshInstance3D in _dry_marks[id]:
			_glow(mark, TEAL, 0.9 if open else 0.0)
			mark.set_meta("lit", open)
	for id: String in _post_marks:
		var at_value: bool = basin == _post_marks[id].value
		for band: MeshInstance3D in _post_marks[id].bands: _glow(band, TEAL, 0.9 if at_value else 0.0)
	for id: String in _ghosts:
		if is_instance_valid(_ghosts[id]) and _decks.has(id): _ghosts[id].visible = not _decks[id].visible
	waters.show_floods(_decks)
	_show_closing(state.get("route_progress", {}).get("closing", {}))
	_show_drowned(state.get("drowned", {}))
	# Where the spirits stand, from the snapshot's positions, so live play, the
	# memory, a retry and a replay all agree: a door dips while one stands in
	# its mouth, and the walls in front of one on a walled stub fade.
	var players: Dictionary = state.get("players", {})
	_spirits.resize(players.size())
	var index := 0
	for slot: String in players:
		_spirits[index] = Vector2(float(players[slot].x), float(players[slot].z))
		index += 1
	waters.occupy(_spirits, routes, immediate or reduced_motion)
	if is_instance_valid(_bell) and bool(state.get("complete", false)): _glow(_bell, LIGHT_COLOR, 1.6)

func _lamp(lamp: MeshInstance3D, color: Color, lit: bool) -> void:
	Primitives.own_material(lamp).albedo_color = color if lit else Color("4a4038")
	_glow(lamp, color, 1.2 if lit else 0.0)
	lamp.set_meta("lit", lit)

func _advance_camera(delta: float) -> void:
	_advance_water(delta)
	super._advance_camera(delta)

func _place_bubbles() -> void:
	super._place_bubbles()
	_clear_scenery()

## The shared placement (journey_world) sees this frame's scenery marks.
func _lift_bubbles() -> void:
	_mark_scenery()
	super._lift_bubbles()
	_bubbles_placed = true

# --- Static fold (kit/static_batch.gd, island_world._fold_static_scenery) ---

## Set once the stage's bubbles have been placed: the fold waits for it.
var _bubbles_placed := false

## Everything that moves, shows, hides or glows with the tide stays whole
## (_static_keep): crossing decks (rebuilt and copied for their ghosts at
## build), water, walled stubs' floods, ghosts, kept marks and masts, boats, sea gates, the
## spout, wheels, gauges, levers and lamps, and the remembered routes (found by
## index). The island floors fold like every world's (cooperative_world).
func _folds_static_scenery() -> bool:
	return _bubbles_placed and super._folds_static_scenery()

func _static_keep() -> Array:
	var keep := super._static_keep()
	for group: Dictionary in [_decks, _memory_markers, _ghosts]: keep.append_array(group.values())
	keep.append_array(waters.moving_nodes())
	for mast: Dictionary in _kept_masts: keep.append_array([mast.post, mast.knob, mast.flag])
	for wheel: Dictionary in _wheels.values(): keep.append(wheel.wheel)
	for gauge: Dictionary in _gauges.values(): keep.append_array([gauge.post, gauge.icon] + gauge.bands)
	for lamp: Dictionary in _lever_lamps.values(): keep.append(lamp.lamp)
	keep.append_array(_mouth_lamps.values())
	keep.append_array(_chamber_lamps)
	keep.append_array(_sea_gates)
	keep.append_array(_boats)
	keep.append_array(_ramps.values())
	if is_instance_valid(_drown_ring): keep.append(_drown_ring)
	keep.append_array(_drown_bubbles)
	keep.append_array(_spout_streaks)
	keep.append_array(_slack_marks)
	for marks: Array in _dry_marks.values(): keep.append_array(marks)
	for mark: Dictionary in _post_marks.values(): keep.append_array(mark.get("bands", []))
	keep.append_array(_physical_levers.values())
	keep.append_array([_spout, _remembered])
	# Validity first: `is` on a freed node is an error (as in StaticBatch.start).
	return keep.filter(func(node: Variant) -> bool: return is_instance_valid(node) and node is Node)

## The shared placement's scenery rule (journey_world._scenery_need), counted
## in every place it tries for a bubble, straight up or leaning aside: how much
## further a bubble at `rect` climbs to leave every gauge's head, valve,
## other lever's knob and pad in view.
func _scenery_need(rect: Rect2, bubble: LabelBubble) -> float:
	var rise := LabelBubble.screen_up().y
	var own := _bubble_owner(bubble)
	var climb := 0.0
	for _pass in range(4):
		var after := _mark_climb(rect, climb, own, rise)
		if after <= climb: break
		climb = after
	return climb

## One pass over the scenery marks: from `climb`, how far a bubble at `rect`
## (plane_rect, raised by climb) climbs to clear each mark but its own lever's.
func _mark_climb(rect: Rect2, climb: float, own: String, rise: float) -> float:
	for index in range(_scenery_mark_count):
		if _scenery_owners[index] == own: continue
		var mark := _scenery_marks[index]
		# The body only: the tail is a thin point that may pass in front.
		var body := Rect2(rect.position - Vector2(0, climb * rise), rect.size - Vector2(0, LabelBubble.TAIL))
		if body.intersection(mark).get_area() > mark.get_area() * SCENERY_COVER:
			climb += (body.end.y - mark.position.y) / rise + BUBBLE_CLEARANCE
	return climb

## The backstop: every bubble, as the shared placement left it, keeps
## climbing by the same rule over what it would still cover (a tide gauge's
## waves and bands, another control's valve, another lever's knob or a pad) and the
## bubbles placed below it; scenery_backstop records the most it climbed. Its
## tail stays on its lever. Lowest on screen first, from the current state
## alone, so a frame never depends on the last; like the journey lift it is
## worked out on the fixed journey view plane in metres and rounded up to
## whole centimetres, so every platform places bubbles alike.
func _clear_scenery() -> void:
	scenery_backstop = 0.0
	if _bubbles.is_empty(): return
	_mark_scenery()
	var rise := LabelBubble.screen_up().y
	if _scenery_placed.size() < _bubbles.size(): _scenery_placed.resize(_bubbles.size())
	_scenery_placed_count = 0
	for bubble: LabelBubble in _bubbles:
		if not is_instance_valid(bubble) or not bubble.visible: continue
		var own := _bubble_owner(bubble)
		var rect := bubble.plane_rect()
		var climb := 0.0
		for _pass in range(4):
			var moved := false
			var after := _mark_climb(rect, climb, own, rise)
			if after > climb:
				climb = after
				moved = true
			for index in range(_scenery_placed_count):
				var raised := Rect2(rect.position - Vector2(0, climb * rise), rect.size)
				if raised.intersects(_scenery_placed[index]):
					climb += (raised.end.y - _scenery_placed[index].position.y) / rise + BUBBLE_CLEARANCE
					moved = true
			if not moved: break
		climb = ceilf(climb * 100.0) / 100.0
		_scenery_placed[_scenery_placed_count] = Rect2(rect.position - Vector2(0, climb * rise), rect.size)
		_scenery_placed_count += 1
		scenery_backstop = maxf(scenery_backstop, climb)
		if climb > 0.0: bubble.set_lift(bubble.lift + climb)

## The selector a bubble names, or "" for any other bubble.
func _bubble_owner(bubble: LabelBubble) -> String:
	for id: String in _journey_switches:
		if _journey_switches[id].bubble == bubble: return id
	return ""

## What a bubble must not cover, on the journey view plane (metres, y down),
## with the control each belongs to: every gauge's head, every valve (its
## own bubble may stand over it), every lever's knob and every pad.
func _mark_scenery() -> void:
	_scenery_mark_count = 0
	for id: String in _gauges: _add_mark(_gauge_head(_gauges[id]), "")
	for id: String in _wheels:
		var hub := LabelBubble.plane_point((_wheels[id].wheel as Node3D).global_position)
		var reach := Vector2(VALVE_MARK_REACH, VALVE_MARK_REACH * LabelBubble.screen_up().y)
		_add_mark(Rect2(hub - reach, reach * 2.0), id)
	for id: String in _physical_levers:
		var knob := LabelBubble.plane_point((_physical_levers[id] as Node3D).global_transform * Vector3(0, 0.4, 0))
		_add_mark(Rect2(knob - Vector2.ONE * 0.09, Vector2.ONE * 0.18), id)
	for id: String in _physical_pads:
		var pad := _physical_pads[id] as MeshInstance3D
		var radius: float = (pad.mesh as TorusMesh).outer_radius if pad.mesh is TorusMesh else 0.2
		# A stand spot sinks while held; its pad marks where it stands free.
		var at := LabelBubble.plane_point(_pad_pieces[id].spot.rest_rim() if _pad_pieces.has(id) and _pad_pieces[id].spot != null else pad.global_position)
		_add_mark(Rect2(at - Vector2(radius, radius * 0.8), Vector2(radius * 2.0, radius * 1.6)), "")

func _add_mark(mark: Rect2, owner: String) -> void:
	if _scenery_marks.size() <= _scenery_mark_count:
		_scenery_marks.resize(_scenery_mark_count + 8)
		_scenery_owners.resize(_scenery_mark_count + 8)
	_scenery_marks[_scenery_mark_count] = mark
	_scenery_owners[_scenery_mark_count] = owner
	_scenery_mark_count += 1

## A gauge's readable head on the journey view plane (metres, y down): its
## waves and the bands under them. The waves keep their size on screen, so
## their height in metres follows the follow camera's authored view height.
func _gauge_head(gauge: Dictionary) -> Rect2:
	var icon: Label3D = gauge.icon
	var foot := LabelBubble.plane_point(icon.global_position)
	var em := float(icon.font_size) * icon.pixel_size * 0.5 * (10.6 if _completion_view else 9.2)
	var bands: Array = gauge.bands
	var low := LabelBubble.plane_point((bands[-1] as Node3D).global_position).y + 0.05 if not bands.is_empty() else foot.y
	var half := maxf(em * 0.3 * float(icon.text.length()), 0.10)
	return Rect2(foot.x - half, foot.y - em, half * 2.0, low - foot.y + em)

## Only the aqueduct ever stands over another floor. Fade it while it hides a
## spirit from the camera; the stepped tiers rise away from the camera and
## never hide anyone, so they never fade.
func _should_cutaway(raised: Node3D, state: Dictionary) -> bool:
	if not raised.has_meta("tide_occluder"): return false
	var players: Array = state.players.values() if _completion_view else [state.players[_active_player]]
	for player: Dictionary in players:
		if _hidden_under(raised, player): return true
	return false

static func _hidden_under(raised: Node3D, player: Dictionary) -> bool:
	var r: Array = raised.get_meta("bounds")
	var floor := Rect2(Vector2(float(r[0]), float(r[1])) / 100.0, Vector2(float(r[2] - r[0]), float(r[3] - r[1])) / 100.0).grow(0.12)
	var top := raised.position.y
	for lift: float in [0.1, 0.5, 0.95]:
		var y := float(player.height) / 100.0 + lift
		if y >= top: continue
		# Follow the view ray from this point of the spirit up to the floor's height.
		var rise := top - y
		if floor.has_point(Vector2(float(player.x) / 100.0 + rise * 3.0 / 13.0, float(player.z) / 100.0 + rise * 10.0 / 13.0)): return true
	return false

func _camera_center() -> Vector3:
	var target := super._camera_center()
	if not _completion_view and actors.has(_camera_slot(_active_player)):
		var at := _focus_point()
		target.x = clampf(at.x, CAMERA_X.x, CAMERA_X.y)
		target.z = clampf(at.z, CAMERA_Z.x, CAMERA_Z.y)
	return target
