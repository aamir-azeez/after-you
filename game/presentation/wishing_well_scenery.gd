extends RefCounted
## The Wishing Well's own scenery and moving rig, shared by every version's
## world: @1's on the cooperative world (wishing_well_world.gd) and @2's on the
## journey world (wishing_well_v2_world.gd). A garden below a stone cliff, an
## open-fronted well sunk into the cliff's east end, a rope-walk to a long
## winch wall, the bucket that lowers on its rope, the folding stairs and the
## rope ladder. Each world forwards its hooks here; everything is presentation,
## movement and gates come from the snapshot. Where things stand comes from the
## level (the cliff's west edge, the gardens, the tower's east end, the stairs),
## so a shorter version drops what lies off its floors and @1 draws as before.
const Props = preload("res://presentation/kit/props.gd")
const ContactShadows = preload("res://presentation/kit/contact_shadows.gd")
const Primitives = preload("res://presentation/kit/primitives.gd")
const OwnerMark = preload("res://presentation/kit/owner_mark.gd")
const GraphicsPolicy = preload("res://services/graphics_policy.gd")
const Look = preload("res://presentation/kit/look.gd")
const WalkReach = preload("res://presentation/kit/walk_reach.gd")
const STONE := Color("9a8d76")
const STONE_DARK := Color("6d6656")
const STONE_LIGHT := Color("bcae90")
const SAND_TRIM := Color("d2c4a2")
const MOSS := Color("6f8d5a")
const LAMP := Color("ffd894")
const GRASS := Color("6f8b66")
const SOIL := Color("6b5240")
const TIMBER := Color("7a5d45")
const ROPE := Color("d1b98c")
const WATER := Color("3f6a77")
const GOLD := OwnerMark.GOLD
## The open shaft in the cliff top is the drop mouth plus two centimetres, so no
## spirit ever stands over open air. The shaft below is the whole well floor.
const NOTCH := [1130, -38, 1190, -16]
const SHAFT := [1120, -48, 1200, -16]
const FOLD_RATE := 2.4
## The held rope reads as a big wooden bucket the friend stands in: about the
## walkable well floor across, a low lip, an open front and a tall bail.
const BUCKET_RADIUS := 0.40
const BUCKET_LIP := 0.20
const BAIL_TOP := 1.30
## The empty bucket hangs this far above the floor, just under its pulley, and
## lowers only while someone stands in it (the rope pad is held). The pad, the
## drop and every position stay the simulation's; only the drawing moves.
const BUCKET_RAISE := 0.90
## About three quarters of a second from the top to the floor.
const BUCKET_RATE := 1.35
## A route the rope opens finishes unfolding by this share of the descent.
const ROUTE_LEAD := 0.6
const DRUM_RADIUS := 0.09
## A stage's bell, around its centre: its base, its frame and the floor its
## frame and bell hide from the camera behind them.
const BELL_SHADE := Rect2(-0.53, -1.6, 1.06, 1.94)
## Cliff face blocks and ivy stand this far (m) clear of a swing's crane.
const CRANE_CLEAR := 0.4
## The world this draws into (an island world of the cooperative lineage).
var w: Node3D
var _bucket: Node3D
var _bucket_rest := Vector3.ZERO
var _bucket_pad := ""
var _bucket_surface := ""
## 0 hangs at the top, 1 rests on the floor.
var _bucket_shown := 0.0
var _bucket_down := false
var _bucket_fresh := true
var _bucket_rope: MeshInstance3D
var _bucket_rope_top := 0.0
var _windlass: Node3D
## Routes the held rope opens; their stairs settle with the bucket.
var _bucket_routes: Array[String] = []
## Simulated height (m) of each spirit standing in the bucket.
var _riders: Dictionary = {}
var _folds: Dictionary = {}
var _ladder: Node3D
var _ladder_rungs: Array[Node3D] = []
var _ladder_roll: Node3D
var _ladder_shown := 0.0
var _ladder_open := false
var _rope_rails: Dictionary = {}
## Where each folding stair's and the rope ladder's mark wants to sit, by stair id.
var _stair_marks: Dictionary = {}
## The shown stage's goal (its bell).
var _shown_goal: Dictionary = {}

func _init(world: Node3D) -> void:
	w = world

## The rig's nodes that move, hide or are looked up later: each world names
## them in a script variable, so its scenery fold (kit/static_batch.gd, which
## reads a world's variables) keeps them as they are.
func held() -> Array:
	return [_bucket, _bucket_rope, _windlass, _folds, _ladder, _ladder_rungs, _ladder_roll, _rope_rails]

## Marks keep clear of the notch rim and its hatch, which lie at their height.
func keep_clear() -> void:
	w.owner_marks.keep_clear(Rect2(Vector2(NOTCH[0], NOTCH[1]) / 100.0, Vector2(NOTCH[2] - NOTCH[0], NOTCH[3] - NOTCH[1]) / 100.0))

## A folding stair's mark sits before its foot; the rope ladder's past its roll.
func stair_mark(stair: Dictionary, fallback: Dictionary) -> Dictionary:
	return _stair_marks.get(stair.id, fallback)

## Low keeps the lanterns glowing but leaves out the light they cast.
func apply_graphics_quality(quality: String) -> void:
	for light: OmniLight3D in w.find_children("*", "OmniLight3D", true, false):
		if light.has_meta("lantern"): light.visible = GraphicsPolicy.lantern_lights(quality)

## Before the world builds a new stage: forget the last stage's rig.
func reset(stage: Dictionary) -> void:
	_shown_goal = stage.get("goal", {})
	_folds.clear()
	_stair_marks.clear()
	_rope_rails.clear()
	_ladder = null
	_ladder_rungs.clear()
	_ladder_roll = null
	_ladder_shown = 0.0
	_ladder_open = false
	_bucket = null
	_bucket_rope = null
	_windlass = null
	_bucket_pad = ""
	_bucket_surface = ""
	_bucket_routes.clear()
	_riders.clear()
	_bucket_shown = 0.0
	_bucket_down = false
	_bucket_fresh = true

## After the world built the stage's floors and pieces: the well, the winch
## house and the cliff garden.
func build(stage: Dictionary) -> void:
	for gate: Dictionary in stage.get("gates", []):
		if not _bucket_pad.is_empty() and _bucket_pad in _gate_pads(gate): _bucket_routes.append(str(gate.route_id))
	w.terrain.name = "WishingWell"
	_build_well()
	_build_winch_house()
	await w._build_step()
	await _dress()

## The pads a gate waits on: a cooperative gate's pad_id, or every pad in a
## journey gate's when.
static func _gate_pads(gate: Dictionary) -> Array:
	var found: Array = []
	if not str(gate.get("pad_id", "")).is_empty(): found.append(str(gate.pad_id))
	_when_pads(gate.get("when", {}), found)
	return found

static func _when_pads(when: Variant, found: Array) -> void:
	if not when is Dictionary: return
	if when.has("pad_id"): found.append(str(when.pad_id))
	for key: String in ["all", "any"]:
		for child: Variant in when.get(key, []): _when_pads(child, found)
	if when.has("not"): _when_pads(when["not"], found)

func has_completion_garden(stage_id: String) -> bool:
	return stage_id == "back-for-you"

func completion_garden_position(goal: Dictionary) -> Vector3:
	return w._at(goal) + Vector3(1.44, 0, -0.46)

## The camera frame from the world's: follows the active spirit across the
## level and lifts and pulls a little so the cliff top and the pit read together.
func camera_center(target: Vector3) -> Vector3:
	if not w._completion_view:
		var low := INF
		var high := -INF
		for island: Dictionary in w.chapter_definition.get("islands", []):
			low = minf(low, float(island.rect_cm[0]) / 100.0)
			high = maxf(high, float(island.rect_cm[2]) / 100.0)
		if is_finite(low) and is_finite(high):
			target.x = clampf(w.actors[w._active_player].position.x, low + 6.0, high - 6.0)
	# Lift and pull the frame a little so the cliff top and the pit read together.
	target.y = 0.45
	target.z = 0.25
	return target

## Builds the well's own floors; false for one the world's shore draws.
func shore(island: Dictionary) -> bool:
	match str(island.id):
		"cliff": _build_rock(island, NOTCH, SHAFT)
		"tower", "rope-rock": _build_rock(island, [], [])
		"well-floor": _build_rock(island, [], [], STONE_DARK, STONE_DARK.darkened(0.1))
		_: return false
	return true

## The colour the world's own shore draws `island` in: a garden is grass.
func shore_color(island: Dictionary, color: Color) -> Color:
	return GRASS if _garden(island) else color

static func _garden(island: Dictionary) -> bool:
	return str(island.get("id", "")).begins_with("garden")

## A raised tier drawn as a solid stone block down past the garden, with the top
## slab and the body cut separately so the well can be an open-fronted shaft.
func _build_rock(island: Dictionary, top_hole: Array, body_hole: Array, top_color: Color = STONE_LIGHT, body_color: Color = STONE) -> void:
	var raised := Node3D.new()
	raised.name = "Rock_" + str(island.id)
	raised.position.y = float(island.get("height_cm", 0)) / 100.0
	w.terrain.add_child(raised)
	raised.set_meta("bounds", island.rect_cm.duplicate())
	if raised.position.y > 0.5: w._upper_islands.append(raised)
	var height := raised.position.y
	var drawn: Array = w.drawn_rect(island)
	var shape: Array = w.drawn_pieces(island)
	for piece: Array in _cut(shape, top_hole):
		_slab(piece, -0.20, -0.012, top_color, raised)
		# The lighter cap ends at the walking surface, so the pair tags and floor
		# lines lying just over it show; its sides never lie on the slab's
		# (coplanar faces flicker as the camera moves).
		_slab(piece, -0.012, 0.0, top_color.lightened(0.12), raised)
	ContactShadows.ground_cm(raised, _cut(shape, top_hole), 0.0, false)
	for piece: Array in _cut(shape, body_hole):
		_slab(piece, -height - 1.45, -0.20, body_color, raised)
	var r := drawn
	var front := float(r[3]) / 100.0
	# Weathered courses across the visible face; none cross the shaft.
	for course: float in [-0.45, -0.85, -1.25]:
		for piece: Array in _cut(shape, body_hole):
			if int(piece[3]) != int(r[3]): continue
			var width := float(piece[2] - piece[0]) / 100.0
			w.box(Vector3(width, 0.025, 0.012), STONE_DARK, Vector3(float(piece[0] + piece[2]) / 200.0, course, front + 0.004), raised)
	w._surface_built(island, raised)

## Every piece of `shape` less `hole`.
static func _cut(shape: Array, hole: Array) -> Array:
	var found: Array = []
	for piece: Array in shape: found.append_array(WalkReach.minus(piece, hole) if not hole.is_empty() else [piece])
	return found

func _slab(rect: Array, bottom: float, top: float, color: Color, parent: Node3D) -> MeshInstance3D:
	var size := Vector3(float(rect[2] - rect[0]) / 100.0, top - bottom, float(rect[3] - rect[1]) / 100.0)
	return w.box(size, color, Vector3(float(rect[0] + rect[2]) / 200.0, (top + bottom) * 0.5, float(rect[1] + rect[3]) / 200.0), parent)

func _build_well() -> void:
	var well := Node3D.new()
	well.name = "OpenWell"
	w.terrain.add_child(well)
	var left := float(SHAFT[0]) / 100.0
	var right := float(SHAFT[2]) / 100.0
	var front := 0.48
	# Low front rim and side kerbs; the east kerb leaves the ladder's gap open.
	w.box(Vector3(right - left + 0.12, 0.22, 0.10), STONE_LIGHT, Vector3((left + right) * 0.5, 0.11, front + 0.05), well)
	# The west kerb stops a centimetre short of the shaft, off the cliff's side there.
	w.box(Vector3(0.09, 0.30, 0.64), STONE_LIGHT, Vector3(left - 0.055, 0.15, 0.16), well)
	w.box(Vector3(0.10, 0.30, 0.08), STONE_LIGHT, Vector3(right + 0.05, 0.15, -0.12), well)
	w.box(Vector3(0.10, 0.30, 0.08), STONE_LIGHT, Vector3(right + 0.05, 0.15, 0.44), well)
	# A dark pool edge at the back makes the pit read as a well, not a ledge.
	w.box(Vector3(right - left - 0.04, 0.012, 0.10), WATER, Vector3((left + right) * 0.5, 0.013, -0.42), well)
	# The windlass straddles the open mouth; its rope drops straight to the bucket.
	var top: float = w._surface_height("cliff")
	var beam_z := -0.27
	for x: float in [left + 0.05, right - 0.05]:
		w.box(Vector3(0.08, 0.78, 0.08), TIMBER, Vector3(x, top + 0.39, beam_z), well)
	w._bar_between(Vector3(left - 0.04, top + 0.78, beam_z), Vector3(right + 0.04, top + 0.78, beam_z), 0.07, TIMBER, well)
	# The drum turns as rope pays out: dark bands and a crank show it.
	_windlass = Node3D.new()
	_windlass.name = "WindlassDrum"
	_windlass.position = Vector3((left + right) * 0.5, top + 0.66, beam_z)
	well.add_child(_windlass)
	var drum: MeshInstance3D = w.cylinder(DRUM_RADIUS, right - left - 0.18, ROPE.darkened(0.15), Vector3.ZERO, _windlass)
	drum.rotation.z = PI / 2.0
	for turn: float in [0.0, PI]:
		w.box(Vector3(right - left - 0.22, 0.03, 0.03), TIMBER.darkened(0.1), Vector3(0, cos(turn) * DRUM_RADIUS, sin(turn) * DRUM_RADIUS), _windlass)
	var axle: MeshInstance3D = w.cylinder(0.025, right - left + 0.22, TIMBER.darkened(0.2), Vector3.ZERO, _windlass)
	axle.rotation.z = PI / 2.0
	var crank_x := (right - left) * 0.5 + 0.10
	w.box(Vector3(0.04, 0.20, 0.04), TIMBER.darkened(0.2), Vector3(crank_x, 0.10, 0), _windlass)
	w._bar_between(Vector3(crank_x, 0.19, 0), Vector3(crank_x + 0.14, 0.19, 0), 0.03, TIMBER.lightened(0.1), _windlass)
	# A short jib carries a pulley out over the bucket, so its rope hangs plumb.
	var pad: Vector3 = _pit_pad()
	w._bar_between(Vector3(pad.x, top + 0.78, beam_z), Vector3(pad.x, top + 0.78, pad.z + 0.03), 0.06, TIMBER, well)
	var pulley: MeshInstance3D = w.ring(0.06, STONE_DARK.lightened(0.2), Vector3(pad.x, top + 0.70, pad.z - 0.06), well)
	pulley.rotation.z = PI / 2.0
	w._bar_between(Vector3(pad.x, top + 0.66 + DRUM_RADIUS, beam_z), Vector3(pad.x, top + 0.76, pad.z - 0.06), 0.024, ROPE, well)
	_bucket_rope_top = top + 0.70
	_bucket_rope = w.mesh_node(Primitives.box_mesh(Vector3(0.024, 1.0, 0.024)), ROPE, Vector3(pad.x, _bucket_rope_top, pad.z), well)
	_bucket_rope.name = "BucketRope"
	_place_bucket()

## Whether `pad` is the rope at the bottom of the well, which this draws as the bucket.
static func is_bucket_pad(pad: Dictionary) -> bool:
	return str(pad.get("surface_id", "")) == "well-floor"

## The rope pad as the bucket the friend stands in.
func build_bucket(pad: Dictionary) -> void:
	# Visual only: the native pad keeps its 48 cm reach over the whole floor.
	var at: Vector3 = w._at(pad)
	var bucket := Node3D.new()
	bucket.name = "RopeBucket_" + str(pad.id)
	bucket.position = at
	w.terrain.add_child(bucket)
	_bucket = bucket
	_bucket_rest = at
	_bucket_pad = str(pad.id)
	_bucket_surface = str(pad.surface_id)
	w.cylinder(BUCKET_RADIUS, 0.05, TIMBER.darkened(0.15), Vector3(0, 0.025, 0), bucket)
	var outline: MeshInstance3D = w.ring(BUCKET_RADIUS - 0.07, GOLD, Vector3(0, 0.06, 0), bucket)
	w._physical_pads[pad.id] = outline
	# Open controls: a bucket either pip may hold carries no owner's mark.
	if pad.has("owner_slot"): w.owner_marks.mark(str(pad.owner_slot), &"bucket", str(pad.id), Vector3.ZERO, bucket)
	# Staves round the back and sides; the front stays open toward the camera.
	var count := 18
	for index in range(count):
		var angle := TAU * float(index) / float(count)
		var facing := Vector2(sin(angle), cos(angle))
		if facing.y > 0.55: continue
		var stave: MeshInstance3D = w.box(Vector3(0.11, BUCKET_LIP, 0.035), TIMBER if index % 2 == 0 else TIMBER.lightened(0.08), Vector3(facing.x * BUCKET_RADIUS, BUCKET_LIP * 0.5, facing.y * BUCKET_RADIUS), bucket)
		stave.rotation.y = atan2(facing.x, facing.y)
	var hoop: MeshInstance3D = w.ring(BUCKET_RADIUS + 0.01, STONE_DARK, Vector3(0, BUCKET_LIP * 0.6, 0), bucket)
	hoop.scale = Vector3(1, 1.4, 1)
	# A tall bail arcs over whoever stands inside, up to the rope.
	var previous := Vector3(-BUCKET_RADIUS, BUCKET_LIP, 0)
	for step in range(1, 9):
		var t := float(step) / 8.0
		var point := Vector3(-cos(PI * t) * BUCKET_RADIUS, BUCKET_LIP + sin(PI * t) * (BAIL_TOP - BUCKET_LIP), 0)
		w._bar_between(previous, point, 0.022, STONE_DARK.lightened(0.2), bucket)
		previous = point

## Where the world draws a spirit standing that the chapter does not list:
## a rider stands in the bucket, on its floor plate. The dressing lint sweeps
## the spirit's ground shadow over it.
func spirit_supports() -> Array:
	if not is_instance_valid(_bucket): return []
	var at := _bucket.position
	return [{"rect": Rect2(at.x - BUCKET_RADIUS, at.z - BUCKET_RADIUS, BUCKET_RADIUS * 2.0, BUCKET_RADIUS * 2.0), "y": at.y, "name": "the bucket"}]

func _pit_pad() -> Vector3:
	for stage: Dictionary in w.chapter_definition.get("stages", []):
		for pad: Dictionary in stage.get("pressure_pads", []):
			if pad.surface_id == "well-floor": return w._at(pad)
	return Vector3(11.6, 0, 0)

## The level's floors this scenery fits, in cm: the cliff, the tower and every garden.
func _floor(id: String) -> Array:
	for island: Dictionary in w.chapter_definition.get("islands", []):
		if str(island.id) == id: return island.rect_cm
	return []

func _gardens() -> Array:
	return w.chapter_definition.get("islands", []).filter(func(island: Dictionary) -> bool: return _garden(island))

## Whether x (m) lies over a garden, at least `inset` (m) in from its ends.
func _over_garden(x: float, inset: float = 0.0) -> bool:
	for island: Dictionary in _gardens():
		if x >= float(island.rect_cm[0]) / 100.0 + inset and x <= float(island.rect_cm[2]) / 100.0 - inset: return true
	return false

## Each stair's middle along x (m), by id, from the level.
func _stair_x(id: String) -> float:
	for stair: Dictionary in w.chapter_definition.get("stairs", []):
		if str(stair.id) == id: return float(int(stair.rect_cm[0]) + int(stair.rect_cm[2])) / 200.0
	return INF

## Whether x (m) is clear of every swing's crane (core/physical/swings.gd).
func _clear_of_cranes(x: float) -> bool:
	for stage: Dictionary in w.chapter_definition.get("stages", []):
		for swing: Dictionary in stage.get("swings", []):
			if absf(x - float(swing.pivot_cm[0]) / 100.0) < CRANE_CLEAR: return false
	return true

func _build_winch_house() -> void:
	var tower: float = w._surface_height("tower")
	var house := Node3D.new()
	house.name = "WinchHouse"
	w.terrain.add_child(house)
	var at := Vector3(float(int(_floor("tower")[2]) - 30) / 100.0, tower, -1.62)
	w.box(Vector3(0.44, 0.9, 0.80), STONE_LIGHT, at + Vector3(0, 0.45, 0), house)
	var roof := PrismMesh.new()
	roof.size = Vector3(0.60, 0.34, 0.92)
	w.mesh_node(roof, TIMBER, at + Vector3(0, 1.07, 0), house)
	var wheel: MeshInstance3D = w.ring(0.36, TIMBER, at + Vector3(-0.26, 0.62, 0.30), house)
	wheel.rotation.z = PI / 2.0

## Draws a cliff stone, a garden bed or a tower rope drum; false for any other.
func build_obstacle(obstacle: Dictionary) -> bool:
	var r: Array = obstacle.rect_cm
	var at: Vector3 = w.point([(r[0] + r[2]) * 0.5, (r[1] + r[3]) * 0.5])
	at.y = w._surface_height(str(obstacle.surface_id))
	var width := float(r[2] - r[0]) / 100.0
	var depth := float(r[3] - r[1]) / 100.0
	var surface := str(obstacle.surface_id)
	if surface == "cliff":
		# Standing stones: the visible footprint is the collision rectangle.
		w.box(Vector3(width, 0.08, depth - 0.01), STONE_DARK, at + Vector3(0, 0.04, 0), w.terrain)
		for index in range(int(depth / 0.4) + 1):
			var z := at.z - depth * 0.5 + 0.2 + float(index) * (depth - 0.4) / maxf(1.0, floor(depth / 0.4))
			var stone: MeshInstance3D = w.box(Vector3(width * 0.9, 0.72 + 0.12 * float(index % 2), 0.32), STONE_LIGHT, Vector3(at.x, at.y + 0.38, z), w.terrain)
			stone.rotation.y = 0.08 * (1 if index % 2 == 0 else -1)
	elif surface.begins_with("garden"):
		w.box(Vector3(width - 0.01, 0.18, depth - 0.01), SOIL, at + Vector3(0, 0.09, 0), w.terrain)
		for x in range(int(r[0]) + 16, int(r[2]), 32):
			for z in range(int(r[1]) + 16, int(r[3]), 32):
				var tuft: MeshInstance3D = w.sphere(0.14, GRASS.lightened(0.12), Vector3(float(x) / 100.0, at.y + 0.24, float(z) / 100.0), w.terrain)
				tuft.scale = Vector3(0.9, 0.7, 0.9)
		w.sphere(0.06, Color("f1c27d"), at + Vector3(0.08, 0.36, 0.05), w.terrain)
		w.sphere(0.05, Color("e9a3a0"), at + Vector3(-0.1, 0.34, -0.1), w.terrain)
	elif surface == "tower":
		# A rope drum lying across the wall-walk, its ends a centimetre
		# inside the tier's face.
		var drum: MeshInstance3D = w.cylinder(minf(width, 0.6) * 0.5, depth - 0.02, TIMBER, at + Vector3(0, minf(width, 0.6) * 0.5, 0), w.terrain)
		drum.rotation.x = PI / 2.0
		for offset: float in [-0.3, 0.0, 0.3]:
			var band: MeshInstance3D = w.cylinder(minf(width, 0.6) * 0.5 + 0.015, 0.05, ROPE, at + Vector3(0, minf(width, 0.6) * 0.5, offset * depth), w.terrain)
			band.rotation.x = PI / 2.0
	else: return false
	return true

## After the world built crossing `definition` (its nodes from child `before`
## on): a rope-walk hangs at the cliff height with posts and hand ropes. With
## `raised_only`, a crossing on the ground (a garden plank) keeps the world's look.
func dress_bridge(definition: Dictionary, before: int, raised_only: bool = false) -> void:
	var lift := float(definition.get("height_cm", 0)) / 100.0
	if raised_only and lift <= 0.0: return
	# Rope-walks hang at the cliff height; lift everything this builder made.
	for index in range(before, w.terrain.get_child_count()):
		w.terrain.get_child(index).position.y += lift
	var r: Array = w.drawn_rect(definition)
	var deck: Node3D = w._decks.get(definition.id)
	for side: int in [-1, 1]:
		var z := float(r[1] if side < 0 else r[3]) / 100.0
		for x: float in [float(r[0]) / 100.0, float(r[2]) / 100.0]:
			w.box(Vector3(0.07, 0.62, 0.07), TIMBER, Vector3(x, lift + 0.31, z), w.terrain)
		if deck != null:
			# Hand ropes belong to the deck: they are taut only while it is open.
			var rail: MeshInstance3D = w._bar_between(Vector3(-float(r[2] - r[0]) / 200.0, 0.55, z - deck.position.z), Vector3(float(r[2] - r[0]) / 200.0, 0.55, z - deck.position.z), 0.022, ROPE, deck)
			rail.name = "HandRope"

func build_stair(stair: Dictionary) -> void:
	if stair.axis == "x":
		_build_ladder(stair)
		return
	var r: Array = w.drawn_rect(stair)
	var width := float(r[2] - r[0]) / 100.0
	var top_z := float(r[1]) / 100.0
	var foot_z := float(r[3]) / 100.0
	var top_y := float(stair.from_height_cm) / 100.0
	# A folding stair hinged at the cliff edge: it hangs against the face while
	# closed and swings down onto the grass when its route opens.
	var pivot := Node3D.new()
	pivot.name = "FoldingStair_" + str(stair.id)
	pivot.position = Vector3(float(r[0] + r[2]) / 200.0, top_y, top_z)
	w.terrain.add_child(pivot)
	var run := foot_z - top_z
	for index in range(10):
		var along := (float(index) + 0.5) / 10.0
		var step: MeshInstance3D = w.box(Vector3(width, 0.08, run / 10.0 + 0.02), STONE_LIGHT if stair.get("owner_slot", "") == "p0" else Color("b9c7c0"), Vector3(0, -top_y * along - 0.04, run * along), pivot)
		step.name = "Step"
	for side: int in [-1, 1]:
		w._bar_between(Vector3(side * (width * 0.5 + 0.02), 0.02, 0), Vector3(side * (width * 0.5 + 0.02), -top_y + 0.02, run), 0.04, TIMBER, pivot)
	# Folded, it leans just off the face rather than through it.
	_folds[stair.id] = {"pivot": pivot, "open": 0.0, "target": 0.0, "fold": atan2(run, top_y) - 0.07}
	pivot.rotation.x = _folds[stair.id].fold
	_stair_marks[stair.id] = {"anchor": Vector3(pivot.position.x, 0.0, foot_z), "away": Vector3.BACK, "kind": &"stair"}

## The well ladder is a rope ladder that unrolls from the winch drum down into
## the pit. Its rungs follow the exact ramp the simulation walks.
func _build_ladder(stair: Dictionary) -> void:
	var r: Array = w.drawn_rect(stair)
	var low := Vector3(float(r[0]) / 100.0, float(stair.from_height_cm) / 100.0, float(r[1] + r[3]) / 200.0)
	var high := Vector3(float(r[2]) / 100.0, float(stair.to_height_cm) / 100.0, low.z)
	var width := float(r[3] - r[1]) / 100.0
	_ladder = Node3D.new()
	_ladder.name = "WellLadder"
	w.terrain.add_child(_ladder)
	var count := 16
	for index in range(count):
		var along := 1.0 - (float(index) + 0.5) / float(count)
		var rung := Node3D.new()
		rung.position = low.lerp(high, along)
		_ladder.add_child(rung)
		w.box(Vector3(0.05, 0.035, width), TIMBER, Vector3(0, 0.02, 0), rung)
		for side: int in [-1, 1]:
			var span := (high - low) / float(count)
			w._bar_between(Vector3(-span.x * 0.5, 0.06 - span.y * 0.5, side * width * 0.5), Vector3(span.x * 0.5, 0.06 + span.y * 0.5, side * width * 0.5), 0.02, ROPE, rung)
		rung.visible = false
		_ladder_rungs.append(rung)
	_ladder_roll = Node3D.new()
	_ladder_roll.name = "RolledLadder"
	_ladder_roll.position = high + Vector3(-0.02, 0.12, 0)
	w.terrain.add_child(_ladder_roll)
	var roll: MeshInstance3D = w.cylinder(0.1, width + 0.04, TIMBER.lightened(0.1), Vector3.ZERO, _ladder_roll)
	roll.rotation.x = PI / 2.0
	# Its top: beside the roll, or just east of the bell frame when the
	# stage's bell stands over the ladder's top and hides the floor there.
	var head := high + Vector3(0.18, 0, -0.36)
	if _shown_goal.has("position_cm"):
		var shade := Rect2(BELL_SHADE.position + Vector2(float(_shown_goal.position_cm[0]), float(_shown_goal.position_cm[1])) / 100.0, BELL_SHADE.size)
		if shade.grow(OwnerMark.REACH).has_point(Vector2(head.x, head.z)): head.x = shade.end.x + OwnerMark.REACH + OwnerMark.CLEAR
	_stair_marks[stair.id] = {"anchor": low, "away": Vector3.LEFT, "kind": &"ladder", "head": head}

## @1's gate links: ropes over the well's rig to each crossing.
func gate_links(view: Dictionary) -> void:
	var cliff: float = w._surface_height("cliff")
	var tower: float = w._surface_height("tower")
	for gate: Dictionary in view.get("gates", []):
		match [str(gate.route_id), str(gate.get("lever_id", "")), str(gate.get("pad_id", ""))]:
			["cliff-steps", "garden-gate", ""]:
				# Gate cable from the winch's back edge along the grass to the folded steps.
				_rope_path(str(gate.route_id), [Vector3(-11.04, 0.04, 1.80), Vector3(-11.04, 0.04, 1.62), Vector3(-12.16, 0.04, 1.62)])
			["long-stair", "", "bucket-rope"]:
				# The bucket rope runs over the windlass and west to the long stair's hinge.
				_rope_path(str(gate.route_id), [Vector3(11.25, cliff + 0.66, -0.27), Vector3(11.10, cliff + 0.03, -0.27), Vector3(9.76, cliff + 0.03, -0.27), Vector3(9.76, cliff + 0.03, -0.18)])
			["rope-walk-west", "", "still-holding"]:
				_rope_path(str(gate.route_id), [Vector3(11.95, cliff + 0.66, -0.27), Vector3(12.10, cliff + 0.03, -0.27), Vector3(12.10, cliff + 0.03, -1.12), Vector3(12.32, cliff + 0.03, -1.12)])
			["rope-walk-east", "", "still-holding"]:
				_rope_path(str(gate.route_id), [Vector3(13.76, cliff + 0.03, -1.10), Vector3(14.24, cliff + 0.03, -1.10)])
			["well-ladder", "winch-lever", ""]:
				# The winch rope weaves past both drums to the rolled ladder.
				# It runs under the tower step's disc, never level with its top.
				_rope_path(str(gate.route_id), [Vector3(27.52, tower + 0.03, -1.44), Vector3(27.52, tower + 0.03, -1.24), Vector3(21.00, tower + 0.03, -1.24), Vector3(21.00, tower + 0.03, -0.56), Vector3(16.10, tower + 0.03, -0.56), Vector3(16.10, tower + 0.03, 0.16), Vector3(15.74, tower + 0.10, 0.16)])

## A gate link's rope along `points` to crossing `route_id`, which then needs
## no pulley (cooperative_world _hangs_pulley).
func _rope_path(route_id: String, points: Array) -> void:
	w._cabled[route_id] = true
	for index in range(points.size() - 1):
		w._floor_cable(points[index], points[index + 1], 0.022, ROPE)

## After the world presented `state`: the bucket, its riders, the folding
## stairs and the rope ladder.
func present(state: Dictionary, immediate: bool) -> void:
	if not state.has("players"): return
	# The held rope pad is the bucket's weight: it lowers only while held.
	_bucket_down = bool(state.get("hold_pads", {}).get(_bucket_pad, false))
	_riders.clear()
	for slot: String in w.actors:
		var player: Dictionary = state.players.get(slot, {})
		if not _bucket_surface.is_empty() and str(player.get("surface_id", "")) == _bucket_surface: _riders[slot] = float(player.get("height", 0)) / 100.0
	# A new stage, a retry or a jump shows the end state with no movement.
	if immediate or w.reduced_motion or _bucket_fresh: _bucket_shown = 1.0 if _bucket_down else 0.0
	_bucket_fresh = false
	_place_bucket()
	if immediate:
		for slot: String in _riders: w.actors[slot].position.y = w.actor_targets[slot].y
	var routes: Dictionary = state.get("bridges", {})
	for id: String in _folds:
		_folds[id].target = 1.0 if bool(routes.get(id, false)) else 0.0
		if immediate or w.reduced_motion: _set_fold(id, _folds[id].target)
	_ladder_open = bool(routes.get("well-ladder", false))
	if immediate or w.reduced_motion: _set_ladder(1.0 if _ladder_open else 0.0)

## One frame of the rig: the bucket lowering or rising, stairs folding, the ladder rolling.
func advance(delta: float) -> void:
	var goal_shown := 1.0 if _bucket_down else 0.0
	var lowering := not is_equal_approx(_bucket_shown, goal_shown)
	# The windlass pays the rope out as the bucket goes down, and winds it in.
	w.note_motion("bucket", "bucket", (-1 if _bucket_down else 1) if lowering else 0)
	if lowering:
		_bucket_shown = goal_shown if w.reduced_motion else move_toward(_bucket_shown, goal_shown, BUCKET_RATE * delta)
		_place_bucket()
	for id: String in _folds:
		var fold: Dictionary = _folds[id]
		var unfolding := not is_equal_approx(float(fold.open), float(fold.target))
		w.note_motion("fold", id, (1 if float(fold.target) > float(fold.open) else -1) if unfolding else 0)
		if unfolding or (lowering and id in _bucket_routes): _set_fold(id, move_toward(float(fold.open), float(fold.target), FOLD_RATE * delta))
	if _ladder != null:
		var goal := 1.0 if _ladder_open else 0.0
		var rolling := not is_equal_approx(_ladder_shown, goal)
		# Unrolling lets the ladder down; rolling it up winds it in.
		w.note_motion("ladder", "ladder", (-1 if _ladder_open else 1) if rolling else 0)
		if rolling: _set_ladder(move_toward(_ladder_shown, goal, FOLD_RATE * 0.75 * delta))

## The bucket, its rope and the drum at the shown height. A spirit standing in
## the bucket is drawn on its floor; its simulated height never changes.
func _place_bucket() -> void:
	if not is_instance_valid(_bucket): return
	var eased := _bucket_shown * _bucket_shown * (3.0 - 2.0 * _bucket_shown)
	var lift := BUCKET_RAISE * (1.0 - eased)
	_bucket.position = _bucket_rest + Vector3(0, lift, 0)
	if is_instance_valid(_bucket_rope):
		var bail := _bucket.position.y + BAIL_TOP
		_bucket_rope.position.y = (_bucket_rope_top + bail) * 0.5
		_bucket_rope.scale.y = maxf(_bucket_rope_top - bail, 0.001)
	if is_instance_valid(_windlass): _windlass.rotation.x = -(BUCKET_RAISE - lift) / DRUM_RADIUS
	for slot: String in _riders:
		if w.actor_targets.has(slot): w.actor_targets[slot].y = float(_riders[slot]) + lift

func _set_fold(id: String, amount: float) -> void:
	var fold: Dictionary = _folds[id]
	fold.open = amount
	# A route the held rope opens unfolds as the bucket settles, not before it.
	var shown := amount
	if _bucket_down and id in _bucket_routes: shown = minf(amount, clampf(_bucket_shown / ROUTE_LEAD, 0.0, 1.0))
	var eased := shown * shown * (3.0 - 2.0 * shown)
	(fold.pivot as Node3D).rotation.x = lerpf(float(fold.fold), 0.0, eased)

func _set_ladder(amount: float) -> void:
	_ladder_shown = amount
	if _ladder == null: return
	var shown := int(round(amount * _ladder_rungs.size()))
	for index in range(_ladder_rungs.size()): _ladder_rungs[index].visible = index < shown
	if _ladder_roll != null: _ladder_roll.scale = Vector3.ONE * lerpf(1.0, 0.45, amount)

# --- Dressing: visual only, never on a route, never over a spirit or control ---

## In a staged build a few pieces a frame (island_world._build_step): this
## dressing alone took about 25 ms of one frame on a desktop.
func _dress() -> void:
	var props := Node3D.new()
	props.name = "CliffGardenProps"
	w.terrain.add_child(props)
	var cliff: float = w._surface_height("cliff")
	var tower: float = w._surface_height("tower")
	var cliff_rect: Array = _floor("cliff")
	var tower_rect: Array = _floor("tower")
	# The cliff's west edge and the tower's east end, in m (@1: -12.8 and 28.16).
	var west := float(cliff_rect[0]) / 100.0
	var tower_east := int(tower_rect[2])
	var steps_x := _stair_x("cliff-steps")
	var stair_x := _stair_x("long-stair")
	# Sandstone coping and weathered blocks along the cliff face.
	# The coping sits just under the cliff top and short of its ends.
	for span: Array in [[west, 11.29], [11.90, 12.31]]:
		w.box(Vector3(span[1] - span[0], 0.07, 0.10), SAND_TRIM, Vector3((span[0] + span[1]) * 0.5, cliff - 0.041, -0.13), props)
	for index in range(26):
		var x := -12.4 + float(index) * 0.93 + 0.2 * sin(index * 2.3)
		if x > 11.0 and x < 12.2: continue
		if x - 0.21 < west or not _clear_of_cranes(x): continue
		var y := cliff - 0.55 - 0.32 * float(index % 4)
		w.box(Vector3(0.34 + 0.08 * float(index % 3), 0.18, 0.03), STONE.lightened(0.06 + 0.04 * float(index % 2)), Vector3(x, y, -0.148), props)
	await w._build_step()
	# Ivy hangs down the face between the stair hinges, and inside the shaft.
	for index in range(15):
		var x := -11.3 + float(index) * 1.55
		if absf(x - steps_x) < 0.7 or absf(x - stair_x) < 0.7 or (x > 10.9 and x < 12.3): continue
		if x - 0.2 < west or not _clear_of_cranes(x): continue
		_kit_prop({"kind": "ivy", "length": 55 + 25 * (index % 3)}, Vector3(x, cliff - 0.02, -0.15), props)
	_kit_prop({"kind": "ivy", "length": 90}, Vector3(11.42, cliff - 0.22, -0.47), props)
	_kit_prop({"kind": "ivy", "length": 60}, Vector3(11.80, cliff - 0.22, -0.47), props)
	await w._build_step()
	# The notch rim keeps a lighter worn edge so the open mouth reads clearly.
	# Its top stays between the hatch bars and a spirit's ground shadow
	# (SpiritVisual.SHADOW_TOP).
	w.box(Vector3(0.04, 0.03, 0.21), SAND_TRIM, Vector3(11.30, cliff + 0.006, -0.275), props)
	w.box(Vector3(0.04, 0.03, 0.21), SAND_TRIM, Vector3(11.90, cliff + 0.006, -0.275), props)
	w.box(Vector3(0.64, 0.03, 0.04), SAND_TRIM, Vector3(11.60, cliff + 0.006, -0.38), props)
	await w._build_step()
	# A planted bank behind the cliff: trees, bushes, a bench and lanterns.
	var bank_cm := int(cliff_rect[2]) - int(cliff_rect[0])
	var bank_x := float(int(cliff_rect[0]) + int(cliff_rect[2])) / 200.0
	w.box(Vector3(float(bank_cm) / 100.0, 0.30, 0.42), STONE, Vector3(bank_x, cliff + 0.15, -2.29), props)
	w.box(Vector3(float(bank_cm - 2) / 100.0, 0.05, 0.40), MOSS, Vector3(bank_x, cliff + 0.32, -2.29), props)
	for x: float in [-10.6, -6.4, -2.2, 2.0, 5.6, 9.2]:
		if x - 0.5 < west: continue
		_kit_prop({"kind": "tree", "size": 0.9 + 0.12 * absf(sin(x))}, Vector3(x, cliff + 0.32, -2.36), props)
	await w._build_step()
	for index in range(24):
		var x := -12.4 + float(index) * 1.05
		if x - 0.3 < west: continue
		_kit_prop({"kind": "bush", "size": 0.6, "flowers": index % 4 == 1}, Vector3(x, cliff + 0.32, -2.18), props)
	if -4.2 - 0.5 >= west: _kit_prop({"kind": "bench"}, Vector3(-4.2, cliff + 0.32, -2.30), props)
	for at: Vector3 in [Vector3(-8.2, cliff + 0.32, -2.20), Vector3(0.2, cliff + 0.32, -2.20), Vector3(11.0, cliff + 0.32, -2.20)]:
		if at.x - 0.3 < west: continue
		_lantern(at, 0.85, true, props)
	await w._build_step()
	# Low cover on the cliff top: flat, so nothing looks like a new obstacle.
	for index in range(22):
		var x := -12.2 + float(index) * 1.1
		if x > 10.9 and x < 12.4: continue
		if x - 0.3 < west: continue
		_kit_prop({"kind": "tuft"}, Vector3(x, cliff, -1.98 + 0.06 * float(index % 2)), props)
	await w._build_step()
	# Garden: a low picket fence just past the front edge, with lanterns.
	var front := 2.95
	# Rails run just behind the pickets' faces, not level with them; one pair per garden.
	for garden: Dictionary in _gardens():
		var r: Array = garden.rect_cm
		var rail := Vector3(float(int(r[2]) - int(r[0])) / 100.0, 0.035, 0.03)
		var middle := float(int(r[0]) + int(r[2])) / 200.0
		w.box(rail, Color("e8dcc0"), Vector3(middle, 0.13, front - 0.01), props)
		w.box(rail, Color("e8dcc0"), Vector3(middle, 0.27, front - 0.01), props)
	for index in range(49):
		var x := -12.76 + float(index) * 0.48
		if not _over_garden(x, 0.025): continue
		w.box(Vector3(0.05, 0.34, 0.035), Color("efe4c8"), Vector3(x, 0.17, front), props)
	for x: float in [-10.9, -4.9, 1.1, 7.1]:
		if not _over_garden(x, 0.2): continue
		_lantern(Vector3(x, 0.0, front + 0.02), 0.72, absf(x) < 6.0, props)
	await w._build_step()
	for index in range(40):
		var x := -12.6 + float(index) * 0.58
		if not _over_garden(x, 0.15): continue
		_kit_prop({"kind": "tuft"}, Vector3(x, 0.0, 2.84), props)
		if index % 3 == 0 and _over_garden(x + 0.2, 0.05): _flower_dot(Vector3(x + 0.2, 0.08, 2.82), props)
		# A grass fringe softens the back edge above the gap.
		if index % 2 == 0 and absf(x - steps_x) > 0.5 and absf(x - stair_x) > 0.5 and _over_garden(x + 0.1, 0.15): _kit_prop({"kind": "tuft"}, Vector3(x + 0.1, 0.0, 1.47), props)
	await w._build_step()
	# Wall-walk: a crenellated back parapet and a low front kerb.
	var walk_cm := tower_east - int(tower_rect[0])
	var walk_x := float(int(tower_rect[0]) + tower_east) / 200.0
	var east := float(tower_east) / 100.0
	w.box(Vector3(float(walk_cm) / 100.0, 0.34, 0.14), STONE, Vector3(walk_x, tower + 0.17, -2.15), props)
	for index in range(26):
		var x := 15.9 + float(index) * 0.48
		if x + 0.11 > east: continue
		w.box(Vector3(0.22, 0.15, 0.15), SAND_TRIM, Vector3(x, tower + 0.40, -2.15), props)
	w.box(Vector3(float(walk_cm) / 100.0, 0.12, 0.10), SAND_TRIM, Vector3(walk_x, tower + 0.06, 0.54), props)
	for x: float in [16.5, 20.6, 24.8]:
		if x + 0.3 > east: continue
		_lantern(Vector3(x, tower + 0.34, -2.15), 0.6, x < 17.0, props)
	for x: float in [17.2, 18.1, 25.9]:
		if x + 0.3 > east: continue
		_kit_prop({"kind": "pot"}, Vector3(x, tower + 0.34, -2.12), props)
	await w._build_step()
	# By the winch: a crate stack and a rope coil, clear of the winch.
	w.box(Vector3(0.30, 0.28, 0.30), TIMBER.lightened(0.15), Vector3(float(tower_east - 106) / 100.0, tower + 0.14, -1.96), props)
	w.box(Vector3(0.22, 0.20, 0.22), TIMBER.lightened(0.25), Vector3(float(tower_east - 104) / 100.0, tower + 0.38, -1.94), props)
	for loop in range(3):
		var coil: MeshInstance3D = w.ring(0.20 - loop * 0.03, ROPE, Vector3(float(tower_east - 16) / 100.0, tower + 0.03 + loop * 0.035, 0.24), props)
		coil.scale.y = 1.6
	for x: float in [13.86, 14.12]:
		_kit_prop({"kind": "tuft"}, Vector3(x, cliff, -1.86), props)

## A kit prop (kit/props.gd) the well's own cliff garden places at `at`,
## apart from the chapter's dressing.
func _kit_prop(spec: Dictionary, at: Vector3, parent: Node3D) -> Node3D:
	var prop := Props.build(spec, parent, 0.0, true)
	prop.remove_meta("dressing_kind")
	prop.position = at
	return prop

func _flower_dot(at: Vector3, parent: Node3D) -> void:
	var tints := [Color("f1c27d"), Color("e9a3a0"), Color("f4ecd0")]
	w.sphere(0.045, tints[int(absf(at.x * 7.0)) % 3], at, parent)

## The kit lantern `height` tall at `at`; a lit one also casts its light.
func _lantern(at: Vector3, height: float, lit: bool, parent: Node3D) -> void:
	_kit_prop({"kind": "lantern", "size": height / 0.85}, at, parent)
	if not lit: return
	var light := OmniLight3D.new()
	light.light_color = LAMP
	light.light_energy = Look.lamp_energy(0.55)
	light.omni_range = 2.2
	light.position = at + Vector3(0.12, height - 0.05, 0.1)
	light.set_meta("lantern", true)
	light.visible = GraphicsPolicy.lantern_lights(w._motion_quality)
	parent.add_child(light)
