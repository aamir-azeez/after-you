extends "res://presentation/cooperative_world.gd"
## The Wishing Well at dusk: a garden below a stone cliff, an open-fronted well
## sunk into the cliff's east end, and a rope-walk to a long winch wall.
## Everything here is presentation; movement and gates come from the snapshot.
const STONE := Color("9a8d76")
const STONE_DARK := Color("6d6656")
const STONE_LIGHT := Color("bcae90")
const SAND_TRIM := Color("d2c4a2")
const MOSS := Color("6f8d5a")
const LEAF := Color("7fa36a")
const LAMP := Color("ffd894")
const GRASS := Color("6f8b66")
const SOIL := Color("6b5240")
const TIMBER := Color("7a5d45")
const ROPE := Color("d1b98c")
const WATER := Color("3f6a77")
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

func _ready() -> void:
	super._ready()
	# Dusk instead of the Lighthouse night: warmer sky, ambient and sun.
	for child: Node in get_children():
		if child is WorldEnvironment:
			child.environment.background_color = Color("2b2945")
			child.environment.ambient_light_color = Color("aeb3cf")
			child.environment.ambient_light_energy = 0.42
		elif child is DirectionalLight3D:
			child.light_color = Color("f4d9bf") if child == sun else Color("8e95c6")
			child.light_energy = 0.72 if child == sun else 0.3
	for mote: MeshInstance3D in motes:
		(mote.material_override as StandardMaterial3D).albedo_color = Color("e7c48e")

func show_stage(stage: Dictionary) -> void:
	if str(stage.get("id", "")) == displayed_stage_id: return
	_folds.clear()
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
	await super.show_stage(stage)
	for gate: Dictionary in stage.get("gates", []):
		if not _bucket_pad.is_empty() and str(gate.get("pad_id", "")) == _bucket_pad: _bucket_routes.append(str(gate.route_id))
	terrain.name = "WishingWell"
	_build_well()
	_build_winch_house()
	_dress()

func _has_completion_garden(stage_id: String) -> bool:
	return stage_id == "back-for-you"

func _completion_garden_position(goal: Dictionary) -> Vector3:
	return _at(goal) + Vector3(1.44, 0, -0.46)

func _completion_garden_scale() -> float:
	return 0.5

## The well is an open notch in the cliff, so nothing ever covers the pit and the
## waiting friend stays in view. The garden is never beneath the cliff either.
func _uses_lower_cutaway() -> bool: return false
func _uses_scrolling_camera() -> bool: return true

func _camera_center() -> Vector3:
	var target := super._camera_center()
	if not _completion_view:
		var low := INF
		var high := -INF
		for island: Dictionary in chapter_definition.get("islands", []):
			low = minf(low, float(island.rect_cm[0]) / 100.0)
			high = maxf(high, float(island.rect_cm[2]) / 100.0)
		if is_finite(low) and is_finite(high):
			target.x = clampf(actors[_active_player].position.x, low + 6.0, high - 6.0)
	# Lift and pull the frame a little so the cliff top and the pit read together.
	target.y = 0.45
	target.z = 0.25
	return target

func _shore(island: Dictionary, color: Color) -> void:
	match str(island.id):
		"cliff": _build_rock(island, NOTCH, SHAFT)
		"tower", "rope-rock": _build_rock(island, [], [])
		"garden": super._shore(island, GRASS)
		"well-floor": _build_rock(island, [], [], STONE_DARK, STONE_DARK.darkened(0.1))
		_: super._shore(island, color)

## A raised tier drawn as a solid stone block down past the garden, with the top
## slab and the body cut separately so the well can be an open-fronted shaft.
func _build_rock(island: Dictionary, top_hole: Array, body_hole: Array, top_color: Color = STONE_LIGHT, body_color: Color = STONE) -> void:
	var raised := Node3D.new()
	raised.name = "Rock_" + str(island.id)
	raised.position.y = float(island.get("height_cm", 0)) / 100.0
	terrain.add_child(raised)
	raised.set_meta("bounds", island.rect_cm.duplicate())
	if raised.position.y > 0.5: _upper_islands.append(raised)
	var height := raised.position.y
	for piece: Array in _pieces(island.rect_cm, top_hole):
		_slab(piece, -0.20, 0.0, top_color, raised)
		# The lighter cap starts at the walking surface, so its sides never lie
		# on the slab's (coplanar faces flicker as the camera moves).
		_slab(piece, 0.0, 0.012, top_color.lightened(0.12), raised)
	for piece: Array in _pieces(island.rect_cm, body_hole):
		_slab(piece, -height - 1.45, -0.20, body_color, raised)
	var r: Array = island.rect_cm
	var front := float(r[3]) / 100.0
	# Weathered courses across the visible face; none cross the shaft.
	for course: float in [-0.45, -0.85, -1.25]:
		for piece: Array in _pieces(island.rect_cm, body_hole):
			if int(piece[3]) != int(r[3]): continue
			var width := float(piece[2] - piece[0]) / 100.0
			box(Vector3(width, 0.025, 0.012), STONE_DARK, Vector3(float(piece[0] + piece[2]) / 200.0, course, front + 0.004), raised)
	_surface_built(island, raised)

static func _pieces(rect: Array, hole: Array) -> Array:
	if hole.is_empty(): return [rect]
	var result: Array = []
	for cut: Array in [[rect[0], rect[1], hole[0], rect[3]], [hole[2], rect[1], rect[2], rect[3]], [hole[0], rect[1], hole[2], hole[1]], [hole[0], hole[3], hole[2], rect[3]]]:
		if cut[2] > cut[0] and cut[3] > cut[1]: result.append(cut)
	return result

func _slab(rect: Array, bottom: float, top: float, color: Color, parent: Node3D) -> MeshInstance3D:
	var size := Vector3(float(rect[2] - rect[0]) / 100.0, top - bottom, float(rect[3] - rect[1]) / 100.0)
	return box(size, color, Vector3(float(rect[0] + rect[2]) / 200.0, (top + bottom) * 0.5, float(rect[1] + rect[3]) / 200.0), parent)

func _build_well() -> void:
	var well := Node3D.new()
	well.name = "OpenWell"
	terrain.add_child(well)
	var left := float(SHAFT[0]) / 100.0
	var right := float(SHAFT[2]) / 100.0
	var front := 0.48
	# Low front rim and side kerbs; the east kerb leaves the ladder's gap open.
	box(Vector3(right - left + 0.12, 0.22, 0.10), STONE_LIGHT, Vector3((left + right) * 0.5, 0.11, front + 0.05), well)
	box(Vector3(0.10, 0.30, 0.64), STONE_LIGHT, Vector3(left - 0.05, 0.15, 0.16), well)
	box(Vector3(0.10, 0.30, 0.08), STONE_LIGHT, Vector3(right + 0.05, 0.15, -0.12), well)
	box(Vector3(0.10, 0.30, 0.08), STONE_LIGHT, Vector3(right + 0.05, 0.15, 0.44), well)
	# A dark pool edge at the back makes the pit read as a well, not a ledge.
	box(Vector3(right - left - 0.04, 0.012, 0.10), WATER, Vector3((left + right) * 0.5, 0.013, -0.42), well)
	# The windlass straddles the open mouth; its rope drops straight to the bucket.
	var top := _surface_height("cliff")
	var beam_z := -0.27
	for x: float in [left + 0.05, right - 0.05]:
		box(Vector3(0.08, 0.78, 0.08), TIMBER, Vector3(x, top + 0.39, beam_z), well)
	_bar_between(Vector3(left - 0.04, top + 0.78, beam_z), Vector3(right + 0.04, top + 0.78, beam_z), 0.07, TIMBER, well)
	# The drum turns as rope pays out: dark bands and a crank show it.
	_windlass = Node3D.new()
	_windlass.name = "WindlassDrum"
	_windlass.position = Vector3((left + right) * 0.5, top + 0.66, beam_z)
	well.add_child(_windlass)
	var drum := cylinder(DRUM_RADIUS, right - left - 0.18, ROPE.darkened(0.15), Vector3.ZERO, _windlass)
	drum.rotation.z = PI / 2.0
	for turn: float in [0.0, PI]:
		box(Vector3(right - left - 0.22, 0.03, 0.03), TIMBER.darkened(0.1), Vector3(0, cos(turn) * DRUM_RADIUS, sin(turn) * DRUM_RADIUS), _windlass)
	var axle := cylinder(0.025, right - left + 0.22, TIMBER.darkened(0.2), Vector3.ZERO, _windlass)
	axle.rotation.z = PI / 2.0
	var crank_x := (right - left) * 0.5 + 0.10
	box(Vector3(0.04, 0.20, 0.04), TIMBER.darkened(0.2), Vector3(crank_x, 0.10, 0), _windlass)
	_bar_between(Vector3(crank_x, 0.19, 0), Vector3(crank_x + 0.14, 0.19, 0), 0.03, TIMBER.lightened(0.1), _windlass)
	# A short jib carries a pulley out over the bucket, so its rope hangs plumb.
	var pad: Vector3 = _pit_pad()
	_bar_between(Vector3(pad.x, top + 0.78, beam_z), Vector3(pad.x, top + 0.78, pad.z + 0.03), 0.06, TIMBER, well)
	var pulley := ring(0.06, STONE_DARK.lightened(0.2), Vector3(pad.x, top + 0.70, pad.z - 0.06), well)
	pulley.rotation.z = PI / 2.0
	_bar_between(Vector3(pad.x, top + 0.66 + DRUM_RADIUS, beam_z), Vector3(pad.x, top + 0.76, pad.z - 0.06), 0.024, ROPE, well)
	_bucket_rope_top = top + 0.70
	_bucket_rope = mesh_node(Primitives.box_mesh(Vector3(0.024, 1.0, 0.024)), ROPE, Vector3(pad.x, _bucket_rope_top, pad.z), well)
	_bucket_rope.name = "BucketRope"
	_place_bucket()

func _build_physical_pad(pad: Dictionary, heavy: bool) -> void:
	if str(pad.get("surface_id", "")) != "well-floor":
		super._build_physical_pad(pad, heavy)
		return
	# Visual only: the native pad keeps its 48 cm reach over the whole floor.
	var at := _at(pad)
	var bucket := Node3D.new()
	bucket.name = "RopeBucket_" + str(pad.id)
	bucket.position = at
	terrain.add_child(bucket)
	_bucket = bucket
	_bucket_rest = at
	_bucket_pad = str(pad.id)
	_bucket_surface = str(pad.surface_id)
	cylinder(BUCKET_RADIUS, 0.05, TIMBER.darkened(0.15), Vector3(0, 0.025, 0), bucket)
	var outline := ring(BUCKET_RADIUS - 0.07, GOLD, Vector3(0, 0.06, 0), bucket)
	_physical_pads[pad.id] = outline
	_ownership_mark(str(pad.owner_slot), Vector3(0, 0.058, 0), bucket)
	# Staves round the back and sides; the front stays open toward the camera.
	var count := 18
	for index in range(count):
		var angle := TAU * float(index) / float(count)
		var facing := Vector2(sin(angle), cos(angle))
		if facing.y > 0.55: continue
		var stave := box(Vector3(0.11, BUCKET_LIP, 0.035), TIMBER if index % 2 == 0 else TIMBER.lightened(0.08), Vector3(facing.x * BUCKET_RADIUS, BUCKET_LIP * 0.5, facing.y * BUCKET_RADIUS), bucket)
		stave.rotation.y = atan2(facing.x, facing.y)
	var hoop := ring(BUCKET_RADIUS + 0.01, STONE_DARK, Vector3(0, BUCKET_LIP * 0.6, 0), bucket)
	hoop.scale = Vector3(1, 1.4, 1)
	# A tall bail arcs over whoever stands inside, up to the rope.
	var previous := Vector3(-BUCKET_RADIUS, BUCKET_LIP, 0)
	for step in range(1, 9):
		var t := float(step) / 8.0
		var point := Vector3(-cos(PI * t) * BUCKET_RADIUS, BUCKET_LIP + sin(PI * t) * (BAIL_TOP - BUCKET_LIP), 0)
		_bar_between(previous, point, 0.022, STONE_DARK.lightened(0.2), bucket)
		previous = point

## Where this world draws a spirit standing that the chapter does not list:
## a rider stands in the bucket, on its floor plate. The dressing lint sweeps
## the spirit's ground shadow over it.
func spirit_supports() -> Array:
	if not is_instance_valid(_bucket): return []
	var at := _bucket.position
	return [{"rect": Rect2(at.x - BUCKET_RADIUS, at.z - BUCKET_RADIUS, BUCKET_RADIUS * 2.0, BUCKET_RADIUS * 2.0), "y": at.y, "name": "the bucket"}]

func _pit_pad() -> Vector3:
	for stage: Dictionary in chapter_definition.get("stages", []):
		for pad: Dictionary in stage.get("pressure_pads", []):
			if pad.surface_id == "well-floor": return _at(pad)
	return Vector3(11.6, 0, 0)

func _build_winch_house() -> void:
	var tower := _surface_height("tower")
	var house := Node3D.new()
	house.name = "WinchHouse"
	terrain.add_child(house)
	var at := Vector3(27.86, tower, -1.62)
	box(Vector3(0.44, 0.9, 0.80), STONE_LIGHT, at + Vector3(0, 0.45, 0), house)
	var roof := PrismMesh.new()
	roof.size = Vector3(0.60, 0.34, 0.92)
	mesh_node(roof, TIMBER, at + Vector3(0, 1.07, 0), house)
	var wheel := ring(0.36, TIMBER, at + Vector3(-0.26, 0.62, 0.30), house)
	wheel.rotation.z = PI / 2.0

func _build_obstacle(obstacle: Dictionary) -> void:
	var r: Array = obstacle.rect_cm
	var at := point([(r[0] + r[2]) * 0.5, (r[1] + r[3]) * 0.5])
	at.y = _surface_height(str(obstacle.surface_id))
	var width := float(r[2] - r[0]) / 100.0
	var depth := float(r[3] - r[1]) / 100.0
	match str(obstacle.surface_id):
		"cliff":
			# Standing stones: the visible footprint is the collision rectangle.
			box(Vector3(width, 0.08, depth - 0.01), STONE_DARK, at + Vector3(0, 0.04, 0), terrain)
			for index in range(int(depth / 0.4) + 1):
				var z := at.z - depth * 0.5 + 0.2 + float(index) * (depth - 0.4) / maxf(1.0, floor(depth / 0.4))
				var stone := box(Vector3(width * 0.9, 0.72 + 0.12 * float(index % 2), 0.32), STONE_LIGHT, Vector3(at.x, at.y + 0.38, z), terrain)
				stone.rotation.y = 0.08 * (1 if index % 2 == 0 else -1)
		"garden":
			box(Vector3(width - 0.01, 0.18, depth - 0.01), SOIL, at + Vector3(0, 0.09, 0), terrain)
			for x in range(int(r[0]) + 16, int(r[2]), 32):
				for z in range(int(r[1]) + 16, int(r[3]), 32):
					var tuft := sphere(0.14, GRASS.lightened(0.12), Vector3(float(x) / 100.0, at.y + 0.24, float(z) / 100.0), terrain)
					tuft.scale = Vector3(0.9, 0.7, 0.9)
			sphere(0.06, Color("f1c27d"), at + Vector3(0.08, 0.36, 0.05), terrain)
			sphere(0.05, Color("e9a3a0"), at + Vector3(-0.1, 0.34, -0.1), terrain)
		"tower":
			# A rope drum lying across the wall-walk, its ends a centimetre
			# inside the tier's face.
			var drum := cylinder(minf(width, 0.6) * 0.5, depth - 0.02, TIMBER, at + Vector3(0, minf(width, 0.6) * 0.5, 0), terrain)
			drum.rotation.x = PI / 2.0
			for offset: float in [-0.3, 0.0, 0.3]:
				var band := cylinder(minf(width, 0.6) * 0.5 + 0.015, 0.05, ROPE, at + Vector3(0, minf(width, 0.6) * 0.5, offset * depth), terrain)
				band.rotation.x = PI / 2.0
		_: super._build_obstacle(obstacle)

func _build_bridge(definition: Dictionary) -> void:
	var before := terrain.get_child_count()
	super._build_bridge(definition)
	# Rope-walks hang at the cliff height; lift everything this builder made.
	var lift := float(definition.get("height_cm", 0)) / 100.0
	for index in range(before, terrain.get_child_count()):
		terrain.get_child(index).position.y += lift
	if _weights.has(definition.id): _weights[definition.id].set_meta("rest_y", _weights[definition.id].position.y)
	var r: Array = definition.rect_cm
	var deck: Node3D = _decks.get(definition.id)
	for side: int in [-1, 1]:
		var z := float(r[1] if side < 0 else r[3]) / 100.0
		for x: float in [float(r[0]) / 100.0, float(r[2]) / 100.0]:
			box(Vector3(0.07, 0.62, 0.07), TIMBER, Vector3(x, lift + 0.31, z), terrain)
		if deck != null:
			# Hand ropes belong to the deck: they are taut only while it is open.
			var rail := _bar_between(Vector3(-float(r[2] - r[0]) / 200.0, 0.55, z - deck.position.z), Vector3(float(r[2] - r[0]) / 200.0, 0.55, z - deck.position.z), 0.022, ROPE, deck)
			rail.name = "HandRope"

func _build_stair(stair: Dictionary) -> void:
	if stair.axis == "x":
		_build_ladder(stair)
		return
	var r: Array = stair.rect_cm
	var width := float(r[2] - r[0]) / 100.0
	var top_z := float(r[1]) / 100.0
	var foot_z := float(r[3]) / 100.0
	var top_y := float(stair.from_height_cm) / 100.0
	# A folding stair hinged at the cliff edge: it hangs against the face while
	# closed and swings down onto the grass when its route opens.
	var pivot := Node3D.new()
	pivot.name = "FoldingStair_" + str(stair.id)
	pivot.position = Vector3(float(r[0] + r[2]) / 200.0, top_y, top_z)
	terrain.add_child(pivot)
	var run := foot_z - top_z
	for index in range(10):
		var along := (float(index) + 0.5) / 10.0
		var step := box(Vector3(width, 0.08, run / 10.0 + 0.02), STONE_LIGHT if stair.owner_slot == "p0" else Color("b9c7c0"), Vector3(0, -top_y * along - 0.04, run * along), pivot)
		step.name = "Step"
	for side: int in [-1, 1]:
		_bar_between(Vector3(side * (width * 0.5 + 0.02), 0.02, 0), Vector3(side * (width * 0.5 + 0.02), -top_y + 0.02, run), 0.04, TIMBER, pivot)
	# Folded, it leans just off the face rather than through it.
	_folds[stair.id] = {"pivot": pivot, "open": 0.0, "target": 0.0, "fold": atan2(run, top_y) - 0.07}
	pivot.rotation.x = _folds[stair.id].fold
	var foot := Vector3(pivot.position.x, 0.0, foot_z + 0.24)
	_ownership_mark(str(stair.owner_slot), foot + Vector3(0, 0.03, 0), terrain)

## The well ladder is a rope ladder that unrolls from the winch drum down into
## the pit. Its rungs follow the exact ramp the simulation walks.
func _build_ladder(stair: Dictionary) -> void:
	var r: Array = stair.rect_cm
	var low := Vector3(float(r[0]) / 100.0, float(stair.from_height_cm) / 100.0, float(r[1] + r[3]) / 200.0)
	var high := Vector3(float(r[2]) / 100.0, float(stair.to_height_cm) / 100.0, low.z)
	var width := float(r[3] - r[1]) / 100.0
	_ladder = Node3D.new()
	_ladder.name = "WellLadder"
	terrain.add_child(_ladder)
	var count := 16
	for index in range(count):
		var along := 1.0 - (float(index) + 0.5) / float(count)
		var rung := Node3D.new()
		rung.position = low.lerp(high, along)
		_ladder.add_child(rung)
		box(Vector3(0.05, 0.035, width), TIMBER, Vector3(0, 0.02, 0), rung)
		for side: int in [-1, 1]:
			var span := (high - low) / float(count)
			_bar_between(Vector3(-span.x * 0.5, 0.06 - span.y * 0.5, side * width * 0.5), Vector3(span.x * 0.5, 0.06 + span.y * 0.5, side * width * 0.5), 0.02, ROPE, rung)
		rung.visible = false
		_ladder_rungs.append(rung)
	_ladder_roll = Node3D.new()
	_ladder_roll.name = "RolledLadder"
	_ladder_roll.position = high + Vector3(-0.02, 0.12, 0)
	terrain.add_child(_ladder_roll)
	var roll := cylinder(0.1, width + 0.04, TIMBER.lightened(0.1), Vector3.ZERO, _ladder_roll)
	roll.rotation.x = PI / 2.0
	_ownership_mark(str(stair.owner_slot), low + Vector3(-0.36, 0.03, 0), terrain)

## The lip zone's marks step off the notch rim and its hatch, which lie at
## their height (they would z-fight), to the nearer side of the notch.
func _ownership_mark(slot: String, at: Vector3, parent: Node3D) -> void:
	var rim := Rect2(Vector2(NOTCH[0], NOTCH[1]) / 100.0, Vector2(NOTCH[2] - NOTCH[0], NOTCH[3] - NOTCH[1]) / 100.0).grow(0.02 + MARK_REACH + 0.01)
	if parent == terrain and rim.has_point(Vector2(at.x, at.z)):
		at.x = rim.position.x if at.x < rim.get_center().x else rim.end.x
	super._ownership_mark(slot, at, parent)

func _build_gate_links(view: Dictionary) -> void:
	var cliff := _surface_height("cliff")
	var tower := _surface_height("tower")
	for gate: Dictionary in view.get("gates", []):
		match [str(gate.route_id), str(gate.get("lever_id", "")), str(gate.get("pad_id", ""))]:
			["cliff-steps", "garden-gate", ""]:
				# Gate cable along the grass to the folded steps.
				_rope_path([Vector3(-11.04, 0.04, 1.92), Vector3(-11.04, 0.04, 1.62), Vector3(-12.16, 0.04, 1.62)])
			["long-stair", "", "bucket-rope"]:
				# The bucket rope runs over the windlass and west to the long stair's hinge.
				_rope_path([Vector3(11.25, cliff + 0.66, -0.27), Vector3(11.10, cliff + 0.03, -0.27), Vector3(9.76, cliff + 0.03, -0.27), Vector3(9.76, cliff + 0.03, -0.18)])
			["rope-walk-west", "", "still-holding"]:
				_rope_path([Vector3(11.95, cliff + 0.66, -0.27), Vector3(12.10, cliff + 0.03, -0.27), Vector3(12.10, cliff + 0.03, -1.12), Vector3(12.32, cliff + 0.03, -1.12)])
			["rope-walk-east", "", "still-holding"]:
				_rope_path([Vector3(13.76, cliff + 0.03, -1.10), Vector3(14.24, cliff + 0.03, -1.10)])
			["well-ladder", "winch-lever", ""]:
				# The winch rope weaves past both drums to the rolled ladder.
				# It runs under the tower step's disc, never level with its top.
				_rope_path([Vector3(27.52, tower + 0.03, -1.44), Vector3(27.52, tower + 0.03, -1.24), Vector3(21.00, tower + 0.03, -1.24), Vector3(21.00, tower + 0.03, -0.56), Vector3(16.10, tower + 0.03, -0.56), Vector3(16.10, tower + 0.03, 0.16), Vector3(15.74, tower + 0.10, 0.16)])

func _rope_path(points: Array) -> void:
	for index in range(points.size() - 1):
		_bar_between(points[index], points[index + 1], 0.022, ROPE, terrain)

func present(state: Dictionary, immediate: bool = false) -> void:
	super.present(state, immediate)
	if not state.has("players"): return
	# The held rope pad is the bucket's weight: it lowers only while held.
	_bucket_down = bool(state.get("hold_pads", {}).get(_bucket_pad, false))
	_riders.clear()
	for slot: String in actors:
		var player: Dictionary = state.players.get(slot, {})
		if not _bucket_surface.is_empty() and str(player.get("surface_id", "")) == _bucket_surface: _riders[slot] = float(player.get("height", 0)) / 100.0
	# A new stage, a retry or a jump shows the end state with no movement.
	if immediate or reduced_motion or _bucket_fresh: _bucket_shown = 1.0 if _bucket_down else 0.0
	_bucket_fresh = false
	_place_bucket()
	if immediate:
		for slot: String in _riders: actors[slot].position.y = actor_targets[slot].y
	var routes: Dictionary = state.get("bridges", {})
	for id: String in _folds:
		_folds[id].target = 1.0 if bool(routes.get(id, false)) else 0.0
		if immediate or reduced_motion: _set_fold(id, _folds[id].target)
	_ladder_open = bool(routes.get("well-ladder", false))
	if immediate or reduced_motion: _set_ladder(1.0 if _ladder_open else 0.0)

func _advance_camera(delta: float) -> void:
	var goal_shown := 1.0 if _bucket_down else 0.0
	var lowering := not is_equal_approx(_bucket_shown, goal_shown)
	# The windlass pays the rope out as the bucket goes down, and winds it in.
	note_motion("bucket", "bucket", (-1 if _bucket_down else 1) if lowering else 0)
	if lowering:
		_bucket_shown = goal_shown if reduced_motion else move_toward(_bucket_shown, goal_shown, BUCKET_RATE * delta)
		_place_bucket()
	for id: String in _folds:
		var fold: Dictionary = _folds[id]
		var unfolding := not is_equal_approx(float(fold.open), float(fold.target))
		note_motion("fold", id, (1 if float(fold.target) > float(fold.open) else -1) if unfolding else 0)
		if unfolding or (lowering and id in _bucket_routes): _set_fold(id, move_toward(float(fold.open), float(fold.target), FOLD_RATE * delta))
	if _ladder != null:
		var goal := 1.0 if _ladder_open else 0.0
		var rolling := not is_equal_approx(_ladder_shown, goal)
		# Unrolling lets the ladder down; rolling it up winds it in.
		note_motion("ladder", "ladder", (-1 if _ladder_open else 1) if rolling else 0)
		if rolling: _set_ladder(move_toward(_ladder_shown, goal, FOLD_RATE * 0.75 * delta))
	super._advance_camera(delta)

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
		if actor_targets.has(slot): actor_targets[slot].y = float(_riders[slot]) + lift

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

func _dress() -> void:
	var props := Node3D.new()
	props.name = "CliffGardenProps"
	terrain.add_child(props)
	var cliff := _surface_height("cliff")
	var tower := _surface_height("tower")
	# Sandstone coping and weathered blocks along the cliff face.
	# The coping sits just under the cliff top and short of its ends.
	for span: Array in [[-12.80, 11.29], [11.90, 12.31]]:
		box(Vector3(span[1] - span[0], 0.07, 0.10), SAND_TRIM, Vector3((span[0] + span[1]) * 0.5, cliff - 0.041, -0.13), props)
	for index in range(26):
		var x := -12.4 + float(index) * 0.93 + 0.2 * sin(index * 2.3)
		if x > 11.0 and x < 12.2: continue
		var y := cliff - 0.55 - 0.32 * float(index % 4)
		box(Vector3(0.34 + 0.08 * float(index % 3), 0.18, 0.03), STONE.lightened(0.06 + 0.04 * float(index % 2)), Vector3(x, y, -0.148), props)
	# Ivy hangs down the face between the stair hinges, and inside the shaft.
	for index in range(15):
		var x := -11.3 + float(index) * 1.55
		if absf(x + 12.16) < 0.7 or absf(x - 9.76) < 0.7 or (x > 10.9 and x < 12.3): continue
		_ivy(Vector3(x, cliff - 0.02, -0.15), 0.55 + 0.25 * float(index % 3), props)
	_ivy(Vector3(11.42, cliff - 0.22, -0.47), 0.9, props)
	_ivy(Vector3(11.80, cliff - 0.22, -0.47), 0.6, props)
	# The notch rim keeps a lighter worn edge so the open mouth reads clearly.
	# Its top stays between the hatch bars and a spirit's ground shadow
	# (SpiritVisual.SHADOW_TOP).
	box(Vector3(0.04, 0.03, 0.21), SAND_TRIM, Vector3(11.30, cliff + 0.006, -0.275), props)
	box(Vector3(0.04, 0.03, 0.21), SAND_TRIM, Vector3(11.90, cliff + 0.006, -0.275), props)
	box(Vector3(0.64, 0.03, 0.04), SAND_TRIM, Vector3(11.60, cliff + 0.006, -0.38), props)
	# A planted bank behind the cliff: trees, bushes, a bench and lanterns.
	box(Vector3(25.12, 0.30, 0.42), STONE, Vector3(-0.24, cliff + 0.15, -2.29), props)
	box(Vector3(25.10, 0.05, 0.40), MOSS, Vector3(-0.24, cliff + 0.32, -2.29), props)
	for x: float in [-10.6, -6.4, -2.2, 2.0, 5.6, 9.2]:
		_tree(Vector3(x, cliff + 0.32, -2.36), 0.9 + 0.12 * absf(sin(x)), props)
	for index in range(24):
		var x := -12.4 + float(index) * 1.05
		var bush := sphere(0.17, LEAF.darkened(0.08 * float(index % 3)), Vector3(x, cliff + 0.42, -2.18), props)
		bush.scale = Vector3(1.3, 0.8, 0.9)
		if index % 4 == 1: _flower_dot(Vector3(x + 0.12, cliff + 0.55, -2.12), props)
	_bench(Vector3(-4.2, cliff + 0.32, -2.30), props)
	for at: Vector3 in [Vector3(-8.2, cliff + 0.32, -2.20), Vector3(0.2, cliff + 0.32, -2.20), Vector3(11.0, cliff + 0.32, -2.20)]:
		_lantern(at, 0.85, true, props)
	# Low cover on the cliff top: flat, so nothing looks like a new obstacle.
	for index in range(22):
		var x := -12.2 + float(index) * 1.1
		if x > 10.9 and x < 12.4: continue
		_tuft(Vector3(x, cliff, -1.98 + 0.06 * float(index % 2)), props)
	# Garden: a low picket fence just past the front edge, with lanterns.
	var front := 2.95
	# Rails run just behind the pickets' faces, not level with them.
	box(Vector3(23.2, 0.035, 0.03), Color("e8dcc0"), Vector3(-1.2, 0.13, front - 0.01), props)
	box(Vector3(23.2, 0.035, 0.03), Color("e8dcc0"), Vector3(-1.2, 0.27, front - 0.01), props)
	for index in range(49):
		box(Vector3(0.05, 0.34, 0.035), Color("efe4c8"), Vector3(-12.76 + float(index) * 0.48, 0.17, front), props)
	for x: float in [-10.9, -4.9, 1.1, 7.1]:
		_lantern(Vector3(x, 0.0, front + 0.02), 0.72, absf(x) < 6.0, props)
	for index in range(40):
		var x := -12.6 + float(index) * 0.58
		_tuft(Vector3(x, 0.0, 2.84), props)
		if index % 3 == 0: _flower_dot(Vector3(x + 0.2, 0.08, 2.82), props)
		# A grass fringe softens the back edge above the gap.
		if index % 2 == 0 and absf(x + 12.16) > 0.5 and absf(x - 9.76) > 0.5: _tuft(Vector3(x + 0.1, 0.0, 1.47), props)
	# Wall-walk: a crenellated back parapet and a low front kerb.
	box(Vector3(12.48, 0.34, 0.14), STONE, Vector3(21.92, tower + 0.17, -2.15), props)
	for index in range(26):
		box(Vector3(0.22, 0.15, 0.15), SAND_TRIM, Vector3(15.9 + float(index) * 0.48, tower + 0.40, -2.15), props)
	box(Vector3(12.48, 0.12, 0.10), SAND_TRIM, Vector3(21.92, tower + 0.06, 0.54), props)
	for x: float in [16.5, 20.6, 24.8]:
		_lantern(Vector3(x, tower + 0.34, -2.15), 0.6, x < 17.0, props)
	for x: float in [17.2, 18.1, 25.9]:
		_pot(Vector3(x, tower + 0.34, -2.12), props)
	# By the winch: a crate stack and a rope coil, clear of the lever.
	box(Vector3(0.30, 0.28, 0.30), TIMBER.lightened(0.15), Vector3(27.10, tower + 0.14, -1.96), props)
	box(Vector3(0.22, 0.20, 0.22), TIMBER.lightened(0.25), Vector3(27.12, tower + 0.38, -1.94), props)
	for loop in range(3):
		var coil := ring(0.20 - loop * 0.03, ROPE, Vector3(28.0, tower + 0.03 + loop * 0.035, 0.24), props)
		coil.scale.y = 1.6
	for x: float in [13.86, 14.12]:
		_tuft(Vector3(x, cliff, -1.86), props)

func _tree(at: Vector3, size: float, parent: Node3D) -> void:
	cylinder(0.07 * size, 0.8 * size, Color("806f59"), at + Vector3(0, 0.4 * size, 0), parent)
	for lobe in range(3):
		var crown := sphere(0.38 * size, Color("659d86").lerp(Color("8daf83"), 0.3 * lobe), at + Vector3((lobe - 1) * 0.2 * size, (0.98 + 0.18 * (1 - absi(lobe - 1))) * size, 0), parent)
		crown.scale = Vector3(0.85, 1.2, 0.85)
	for j in range(3):
		sphere(0.06, Color("ebc28f"), at + Vector3(sin(j * 2.1) * 0.27 * size, (0.92 + 0.12 * j) * size, cos(j * 2.1) * 0.22 * size + 0.1), parent)

func _ivy(at: Vector3, length: float, parent: Node3D) -> void:
	box(Vector3(0.12, length, 0.015), MOSS, at - Vector3(0, length * 0.5, 0), parent)
	for index in range(int(length / 0.18)):
		var leaf := sphere(0.07, LEAF.darkened(0.06 * float(index % 2)), at + Vector3(0.05 * (1 if index % 2 == 0 else -1), -0.1 - float(index) * 0.18, 0.012), parent)
		leaf.scale = Vector3(1.2, 0.8, 0.35)

func _tuft(at: Vector3, parent: Node3D) -> void:
	for j in range(3):
		var blade := box(Vector3(0.022, 0.08 + j * 0.03, 0.03), Color("6f9a64"), at + Vector3(j * 0.035 - 0.035, 0.04 + j * 0.01, 0), parent)
		blade.rotation.z = (j - 1) * 0.3

func _flower_dot(at: Vector3, parent: Node3D) -> void:
	var tints := [Color("f1c27d"), Color("e9a3a0"), Color("f4ecd0")]
	sphere(0.045, tints[int(absf(at.x * 7.0)) % 3], at, parent)

func _lantern(at: Vector3, height: float, lit: bool, parent: Node3D) -> void:
	box(Vector3(0.05, height, 0.05), TIMBER.darkened(0.1), at + Vector3(0, height * 0.5, 0), parent)
	box(Vector3(0.16, 0.03, 0.03), TIMBER.darkened(0.1), at + Vector3(0.06, height - 0.02, 0), parent)
	var lamp := box(Vector3(0.12, 0.15, 0.12), LAMP, at + Vector3(0.12, height - 0.13, 0), parent)
	_glow(lamp, Color("f2a94e"), 0.7)
	box(Vector3(0.16, 0.035, 0.16), TIMBER.darkened(0.2), at + Vector3(0.12, height - 0.04, 0), parent)
	if not lit: return
	var light := OmniLight3D.new()
	light.light_color = LAMP
	light.light_energy = 0.55
	light.omni_range = 2.2
	light.position = at + Vector3(0.12, height - 0.05, 0.1)
	parent.add_child(light)

func _bench(at: Vector3, parent: Node3D) -> void:
	box(Vector3(0.80, 0.05, 0.22), TIMBER.lightened(0.1), at + Vector3(0, 0.24, 0), parent)
	box(Vector3(0.80, 0.18, 0.04), TIMBER.lightened(0.1), at + Vector3(0, 0.38, -0.10), parent)
	for x: float in [-0.34, 0.34]: box(Vector3(0.05, 0.24, 0.18), TIMBER, at + Vector3(x, 0.12, 0), parent)

func _pot(at: Vector3, parent: Node3D) -> void:
	cylinder(0.08, 0.13, Color("b97b5a"), at + Vector3(0, 0.065, 0), parent)
	var plant := sphere(0.10, LEAF, at + Vector3(0, 0.19, 0), parent)
	plant.scale = Vector3(1.1, 0.9, 1.1)
	_flower_dot(at + Vector3(0.04, 0.26, 0.03), parent)
