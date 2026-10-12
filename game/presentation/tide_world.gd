extends "res://presentation/journey_world.gd"
## Turn of the Tide at dusk: a harbour of beaches, terraces and quays between
## channels whose water follows the tide wheel, an outer sea past the mole that
## follows the basin wheel, and a sea chamber between them. Water, wheels, tide
## gauges and kept-crossing marks only read the snapshot; nothing here feeds
## back into the simulation, a recording or a checkpoint.

## Display heights (metres) for each water value. Low sits below the beaches,
## half between beach and terrace, high between terrace and quay.
const HARBOUR_LEVELS := {"low": -0.22, "half": 0.24, "high": 0.70}
## The outer sea rests a little below the beaches while the sea gate is shut.
const SEA_LEVELS := {"shut": -0.06, "low": -0.22, "half": 0.24, "high": 0.70}
const SEABED := -0.70
## Water moves at this many metres a second; one tide step takes about half a second.
const WATER_RATE := 1.1
const HARBOUR_REGION := [-512, -480, 1728, 480]
## The outer sea: west of the mole and through the harbour mouth, with a short
## reach past each end of the mouth where the sea gates stand.
const SEA_REGIONS := [[-1152, -480, -512, 480], [-704, -560, -512, -480], [-704, 480, -512, 560]]
const MOUTH_X := [-704, -512]
const SEA_GATE_Z := 5.20
const CHAMBER_PIT := [-640, -128, -576, 128]
const CHAMBER_WALL_TOP := 0.74
const AQUEDUCT := ["aq-feeder", "aq-span"]
const WATER := Color(0.25, 0.42, 0.47, 0.84)
const SEA := Color(0.21, 0.37, 0.44, 0.88)
const CHAMBER_WATER := Color(0.28, 0.46, 0.50, 0.84)
const SPOUT := Color(0.80, 0.93, 0.95, 0.86)
const STONE := Color("a8947a")
const STONE_DARK := Color("7d6d58")
const TIMBER := Color("7a5d45")
const PILE := Color("5f4a38")
## Walls under each tier, by deck height in cm.
const WALLS := {0: Color("9c8d74"), 48: Color("a8947a"), 96: Color("8c7b63")}
## Ground when the dressing names none, by deck height in cm.
const DEFAULT_GROUND := {0: "sand", 48: "sandstone", 96: "harbour"}
const TIDE_VALUES := ["low", "half", "high"]
const CAMERA_X := Vector2(-9.6, 17.28)
const CAMERA_Z := Vector2(-5.44, 5.44)
const LABEL_SPACING := 0.80
## Label rows sit this far above their floor: clear of high water on a terrace.
const LABEL_LIFT := 0.32
const WHEEL_SWEEP := 0.95
## The first spirit's machines; everything else belongs to the second.
const P0_MECHANISMS := ["tide", "chamber", "winch", "sluice", "line", "punt-line", "boom-pin", "sea-key", "wheel-step-pad", "quay-step-pad", "bollard-pad"]
## Crest shape per mechanism: [bars, turned]. Colour, bar count and direction
## together tell every mechanism apart without relying on colour alone.
const CRESTS := {
	"winch": [1, false], "sluice": [2, false], "line": [3, false],
	"chamber": [1, true], "punt-line": [2, true], "bollard-pad": [3, true],
	"lock": [1, false], "gangway": [2, false], "basin": [3, false],
	"boom-chain": [1, true], "gate-bar": [2, true], "punt-chain": [3, true],
	# Second stage only, so they reuse first-stage shapes without meeting them.
	"boom-pin": [1, false], "sea-key": [2, false], "sea-bar": [2, false],
}
## Which mouth crossing each sea value serves.
const MOUTHS := {"half": "boom-jetty", "low": "sea-gate-out", "high": "punt-ferry"}

var _water: Dictionary = {}
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
var _history_tide := ""

func show_stage(stage: Dictionary) -> void:
	if str(stage.get("id", "")) == displayed_stage_id: return
	_water.clear()
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
	_history_tide = ""
	super.show_stage(stage)
	terrain.name = "TurnOfTheTide"
	var islands: Array = chapter_definition.get("islands", [])
	_water["harbour"] = _water_body("HarbourWater", [HARBOUR_REGION], islands, [CHAMBER_PIT], WATER, HARBOUR_LEVELS.low)
	_water["sea"] = _water_body("OuterSea", SEA_REGIONS, islands, [CHAMBER_PIT], SEA, SEA_LEVELS.shut)
	_water["chamber"] = _water_body("ChamberWater", [CHAMBER_PIT], islands, [], CHAMBER_WATER, HARBOUR_LEVELS.half)
	_build_chamber()
	_build_sea_gates()
	_build_mouth_lamps()
	_build_spout()

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
	if str(island.id) in AQUEDUCT:
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
	var bottom := SEABED - height
	var color: Color = WALLS.get(int(island.get("height_cm", 0)), STONE)
	var size := Vector3(float(r[2] - r[0]) / 100.0 - 0.02, -0.20 - bottom, float(r[3] - r[1]) / 100.0 - 0.02)
	var wall := box(size, color, Vector3(float(r[0] + r[2]) / 200.0, (bottom - 0.20) * 0.5, float(r[1] + r[3]) / 200.0), raised)
	wall.name = str(island.id) + "Wall"
	# One weathered course on the face toward the camera, just under the deck.
	box(Vector3(size.x, 0.03, 0.02), color.darkened(0.18), Vector3(wall.position.x, -0.34, float(r[3]) / 100.0 - 0.005), raised)

func _aqueduct_piers(island: Dictionary, raised: Node3D) -> void:
	var r: Array = island.rect_cm
	var bottom := SEABED - raised.position.y
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

# --- Crossings: decks at their own height ---

func _build_bridge(definition: Dictionary) -> void:
	var before := terrain.get_child_count()
	super._build_bridge(definition)
	var id := str(definition.id)
	var built: Array[Node] = []
	for index in range(before, terrain.get_child_count()): built.append(terrain.get_child(index))
	# The shared deck builder places every deck at the ground; lift all it made.
	for node: Node in built: (node as Node3D).position.y += float(definition.get("height_cm", 0)) / 100.0
	# Built in order: the deck, an ownership mark at each end for an owned
	# route, then the pulley post, pulley, rope and weight.
	var unused: Array[Node] = []
	if not str(definition.get("owner_slot", "")).is_empty() and built.size() >= 3 and (_is_stub(definition) or _gate_for(id).is_empty()):
		# A stub shows its owner on its own pads and levers; a route this stage
		# never gates needs no ownership mark at all.
		unused.append_array(built.slice(1, 3))
	if _weights.has(id) and built.size() >= 4 and built[-1] == _weights[id]:
		if _quiet_route(definition):
			# Tide crossings carry a gauge and stubs their own marks instead.
			unused.append_array(built.slice(built.size() - 4))
			_weights.erase(id)
		else:
			_weights[id].set_meta("rest_y", _weights[id].position.y)
	for node: Node in unused:
		terrain.remove_child(node)
		node.free()
	_kept_pennant(definition)
	if id.begins_with("jetty") or id == "boom-jetty": _piles(definition)
	if _is_stub(definition): _stub_frame(definition)

## A route that never needs the pulley: a stub, a tide crossing, or one this
## stage leaves closed or always open.
func _quiet_route(route: Dictionary) -> bool:
	if _is_stub(route): return true
	var gate := _gate_for(str(route.id))
	return gate.is_empty() or gate.get("when", {}).is_empty() or not _tide_marks(gate.when).is_empty()

func _is_stub(route: Dictionary) -> bool:
	return str(route.get("to_surface", "")) == str(route.id)

func _gate_for(route_id: String) -> Dictionary:
	for gate: Dictionary in current_level.get("gates", []):
		if gate.route_id == route_id: return gate
	return {}

## A small pennant on the deck shows a crossing kept for good. It belongs to
## the deck's remembered-footsteps marker, so it shows only while kept.
func _kept_pennant(route: Dictionary) -> void:
	var memories: Node3D = _memory_markers.get(route.id)
	if memories == null: return
	var r: Array = route.rect_cm
	var at := Vector3(-float(r[2] - r[0]) / 200.0 + 0.10, 0, float(r[3] - r[1]) / 200.0 - 0.10)
	box(Vector3(0.03, 0.34, 0.03), CREAM, at + Vector3(0, 0.17, 0), memories).name = "KeptPost"
	var flag := box(Vector3(0.16, 0.10, 0.012), GOLD, at + Vector3(0.09, 0.28, 0), memories)
	flag.name = "KeptPennant"

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
		box(Vector3(0.05, 0.08, z1 - z0), PILE, Vector3(x, y, (z0 + z1) * 0.5), frame)
	var tip := z0 + 0.03 if _route_anchor(route).z > z1 else z1 - 0.03
	box(Vector3(x1 - x0, 0.08, 0.05), PILE, Vector3((x0 + x1) * 0.5, y, tip), frame)
	for x: float in [x0 + 0.03, x1 - 0.03]:
		cylinder(0.035, y - SEABED, PILE, Vector3(x, (y + SEABED) * 0.5, tip), frame)

func _piles(route: Dictionary) -> void:
	var r: Array = route.rect_cm
	var top := float(route.height_cm) / 100.0 - 0.10
	for x: int in [r[0] + 10, r[2] - 10]:
		for z: int in [r[1] + 8, r[3] - 8]:
			cylinder(0.05, top - SEABED, PILE, Vector3(float(x) / 100.0, (top + SEABED) * 0.5, float(z) / 100.0), terrain).name = "JettyPile"

# --- Wheels and levers ---

func _build_selector(control: Dictionary) -> void:
	super._build_selector(control)
	# Every label row rides above the highest water and the chamber walls.
	# Three- and four-way wheels also get a closer row and a spoked hand wheel
	# whose pointer shows the value.
	var many: bool = control.values.size() >= 3
	var at := _at(control)
	var labels: Array = _journey_switches[control.id].labels
	for index in range(labels.size()):
		var label: Label3D = labels[index]
		var spot := at + Vector3((float(index) - float(labels.size() - 1) * 0.5) * (LABEL_SPACING if many else 1.28), LABEL_LIFT, 0.70)
		label.position = spot
		var backing: MeshInstance3D = label.get_meta("backing")
		backing.position = spot
		if many:
			label.pixel_size = 0.0068
			(backing.mesh as QuadMesh).size = Vector2(0.66, 0.26)
	if many: _build_wheel(control)

func _build_wheel(control: Dictionary) -> void:
	var color := GOLD if control.owner_slot == "p0" else TEAL
	var values: Array = control.values
	# Behind and above the standing point, so a spirit at the wheel never hides it.
	var center := _at(control) + Vector3(0, 1.0, -0.42)
	box(Vector3(0.07, 0.80, 0.07), TIMBER, center + Vector3(0, -0.44, -0.06), terrain)
	# The dial plate: one notch per value, with 1, 2 or 3 bands for low, half and
	# high (the tide gauges use the same bands) and a bar for a shut sea.
	var dial := Node3D.new()
	dial.name = "WheelDial_" + str(control.id)
	dial.position = center + Vector3(0, 0, -0.05)
	terrain.add_child(dial)
	for index in range(values.size()):
		var angle := _wheel_angle(index, values.size())
		var mark := Vector3(-sin(angle), cos(angle), 0) * 0.36
		var bands := TIDE_VALUES.find(str(values[index])) + 1
		if bands == 0:
			box(Vector3(0.10, 0.025, 0.02), CREAM, mark, dial).rotation.z = angle
		for band in range(bands):
			var tick := box(Vector3(0.022, 0.08, 0.02), CREAM, mark + Vector3(-sin(angle + PI / 2.0), cos(angle + PI / 2.0), 0) * (float(band) - float(bands - 1) * 0.5) * 0.04, dial)
			tick.rotation.z = angle
	var wheel := Node3D.new()
	wheel.name = "HandWheel_" + str(control.id)
	wheel.position = center
	terrain.add_child(wheel)
	var rim := ring(0.24, color, Vector3.ZERO, wheel)
	rim.rotation.x = PI / 2.0
	for spoke in range(4):
		var bar := box(Vector3(0.025, 0.46, 0.025), TIMBER.lightened(0.15), Vector3.ZERO, wheel)
		bar.rotation.z = float(spoke) * PI / 4.0
	sphere(0.05, color.darkened(0.2), Vector3.ZERO, wheel)
	var pointer := sphere(0.06, CREAM, Vector3(0, 0.24, 0.02), wheel)
	pointer.name = "WheelPointer"
	_wheels[control.id] = {"wheel": wheel, "values": values.duplicate()}

static func _wheel_angle(index: int, count: int) -> float:
	return lerpf(WHEEL_SWEEP, -WHEEL_SWEEP, float(index) / float(maxi(count - 1, 1)))

func _build_lever(lever: Dictionary) -> void:
	super._build_lever(lever)
	if lever.get("kind", "") == "selector": return
	# Levers toggle, so a lamp beside the handle says plainly whether it is on.
	var lamp := sphere(0.07, Color("4a4038"), _at(lever) + Vector3(0.24, 0.22, 0.0), terrain)
	lamp.name = "LeverLamp_" + str(lever.id)
	box(Vector3(0.03, 0.18, 0.03), TIMBER, _at(lever) + Vector3(0.24, 0.09, 0.0), terrain)
	_lever_lamps[lever.id] = {"lamp": lamp, "color": GOLD if lever.owner_slot == "p0" else TEAL}

# --- Goal: the bell, or the harbour lantern on the mole ---

func _build_bell(goal: Dictionary) -> void:
	if str(goal.get("id", "")) != "harbour-lantern":
		super._build_bell(goal)
		return
	var cradle := Node3D.new()
	cradle.name = "HarbourLanternGoal"
	cradle.position = point(goal.position_cm)
	terrain.add_child(cradle)
	cylinder(float(goal.radius_cm) / 100.0, 0.05, Color("6b8984"), Vector3(0, 0.025, 0), cradle)
	_bell_ring = ring(float(goal.radius_cm) / 100.0, CREAM, Vector3(0, 0.06, 0), cradle)
	# The lantern stands on a mole stone behind the exact standing point.
	var base := Vector3(0, 0, -0.50)
	box(Vector3(0.46, 0.20, 0.32), STONE, base + Vector3(0, 0.10, 0), cradle)
	cylinder(0.045, 1.0, TIMBER.darkened(0.2), base + Vector3(0, 0.70, 0), cradle)
	box(Vector3(0.30, 0.04, 0.30), TIMBER.darkened(0.2), base + Vector3(0, 1.20, 0), cradle)
	_bell = box(Vector3(0.22, 0.26, 0.22), Color("b8a87c"), base + Vector3(0, 1.35, 0), cradle)
	_bell.name = "HarbourLantern"
	_glow(_bell, LIGHT_COLOR, 0.0)
	box(Vector3(0.32, 0.05, 0.32), TIMBER.darkened(0.2), base + Vector3(0, 1.50, 0), cradle)
	_court_light = OmniLight3D.new()
	_court_light.light_color = LIGHT_COLOR
	_court_light.light_energy = 0.0
	_court_light.omni_range = 4.5
	_court_light.position = cradle.position + base + Vector3(0, 1.35, 0.2)
	terrain.add_child(_court_light)
	_ownership_mark(str(goal.owner_slot), cradle.position + Vector3(0, 0.025, 0.42), terrain)

# --- Gate links: tide gauges, crests and the catwalks' slack marks ---

func _build_gate_links(view: Dictionary) -> void:
	var entities: Array = view.get("controls", []) + view.get("levers", []) + view.get("pressure_pads", [])
	var crested: Array[String] = []
	for gate: Dictionary in view.get("gates", []):
		var route: Dictionary = {}
		for candidate: Dictionary in view.bridges + view.get("stairs", []):
			if candidate.id == gate.route_id: route = candidate
		if route.is_empty(): continue
		var when: Dictionary = gate.get("when", {})
		var references := _predicate_references(when)
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
			# One crest beside each machine, however many routes it opens.
			if id not in crested: _route_crest(id, _crest_beside(entity, start), color, terrain)
			crested.append(id)
			_route_crest(id, spot, color, terrain)
			if _shares_floor(start, spot):
				var elbow := Vector3(spot.x, start.y, start.z)
				if start.distance_to(elbow) > 0.01: _bar_between(start, elbow, 0.016, color.darkened(0.25), terrain)
				if elbow.distance_to(spot) > 0.01: _bar_between(elbow, spot, 0.016, color.darkened(0.25), terrain)

## Beside a machine: to its east on an island, or toward the far end of the
## narrow stub it stands on, so the crest never lands in a gap or on a neighbour.
func _crest_beside(entity: Dictionary, start: Vector3) -> Vector3:
	for route: Dictionary in chapter_definition.get("bridges", []):
		if route.id != entity.get("surface_id", "") or not _is_stub(route): continue
		return start + Vector3(0, 0.01, -0.22 if _route_anchor(route).z > float(route.rect_cm[3]) / 100.0 else 0.22)
	return start + Vector3(0.33, 0.01, 0)

## Tide values a gate needs outright (through "all" only), low to high.
func _tide_marks(predicate: Dictionary) -> Array:
	var found: Array = []
	if str(predicate.get("control_id", "")) == "tide": found.append(str(predicate.get("value", "")))
	for child: Dictionary in predicate.get("all", []):
		for value: String in _tide_marks(child):
			if value not in found: found.append(value)
	return found

## Where a route's crests sit: a stub's mouth on its own floor, or just before a
## crossing's west end, at the route's own height.
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

func _route_color(id: String) -> Color:
	return GOLD if id in P0_MECHANISMS else TEAL

func _route_crest(id: String, at: Vector3, color: Color, parent: Node3D) -> void:
	var shape: Array = CRESTS.get(id, [1, false])
	var crest := Node3D.new()
	crest.name = "Crest_" + id
	crest.set_meta("crest", id)
	crest.position = at
	crest.rotation.y = PI / 2.0 if shape[1] else 0.0
	parent.add_child(crest)
	var count := int(shape[0])
	for index in range(count):
		box(Vector3(0.07, 0.014, 0.18), color, Vector3((float(index) - float(count - 1) * 0.5) * 0.12, 0, 0), crest)

func _carries_pad(view: Dictionary, surface_id: String) -> bool:
	for pad: Dictionary in view.get("pressure_pads", []):
		if pad.get("surface_id", "") == surface_id: return true
	return false

## The sea value a gate needs outright, or "" when it needs none.
func _sea_value(predicate: Dictionary) -> String:
	if str(predicate.get("control_id", "")) == "basin": return str(predicate.get("value", ""))
	for child: Dictionary in predicate.get("all", []):
		var value := _sea_value(child)
		if not value.is_empty(): return value
	return ""

## A post's mouth shows the sea value it rises at: 1, 2 or 3 teal bands.
func _build_post_mark(route: Dictionary, value: String) -> void:
	var at := _route_anchor(route)
	var bands: Array[MeshInstance3D] = []
	var count := TIDE_VALUES.find(value) + 1
	for index in range(count):
		var band := box(Vector3(0.035, 0.012, 0.16), TEAL.darkened(0.2), at + Vector3((float(index) - float(count - 1) * 0.5) * 0.08, 0.002, 0), terrain)
		band.name = "PostMark_" + str(route.id)
		bands.append(band)
	_post_marks[route.id] = {"value": value, "bands": bands}

## A gauge post beside a tide crossing: 1, 2 or 3 bands for low, half or high.
## A crossing over water stands its post in the channel; a stub on its floor.
func _build_gauge(route: Dictionary, values: Array) -> void:
	var r: Array = route.rect_cm
	var base := SEABED
	var at := point([r[0] + 16, r[3] + 12])
	var top := float(route.get("height_cm", 0)) / 100.0 + 0.60
	if route.has("axis"):
		at = point([r[2] + 12, (r[1] + r[3]) * 0.5])
		top = maxf(float(route.from_height_cm), float(route.to_height_cm)) / 100.0 + 0.60
	elif _is_stub(route):
		at = point([r[2] + 10, r[3] + 10]) if _route_anchor(route).z > float(r[3]) / 100.0 else point([r[2] + 10, r[1] - 10])
		base = float(route.height_cm) / 100.0
		top = base + 0.55
	var post := Node3D.new()
	post.name = "TideGauge_" + str(route.id)
	post.position = at
	terrain.add_child(post)
	cylinder(0.03, top - base, CREAM.darkened(0.15), Vector3(0, (top + base) * 0.5, 0), post)
	var bands: Array[MeshInstance3D] = []
	var count := 0
	for value: String in values: count = maxi(count, TIDE_VALUES.find(value) + 1)
	for index in range(count):
		var band := cylinder(0.055, 0.035, GOLD, Vector3(0, top - 0.06 - float(index) * 0.075, 0), post)
		band.name = "GaugeBand"
		bands.append(band)
	_gauges[route.id] = {"bands": bands, "values": values.duplicate(), "post": post}

## A catwalk that reads the sea alone: a plank across its mouth glows while
## the sea leaves it dry (the same for both spirits, as the sea is copied).
func _build_dry_mark(route: Dictionary) -> void:
	var plank := box(Vector3(0.22, 0.012, 0.05), TEAL.darkened(0.2), _route_anchor(route) + Vector3(0, 0.002, 0), terrain)
	plank.name = "DryMark_" + str(route.id)
	_dry_marks[route.id] = [plank]

## The catwalk mouth's slack mark glows while the catwalk is dry.
func _build_slack_mark(route: Dictionary) -> void:
	var at := _route_anchor(route)
	for side: int in [-1, 1]:
		var wave := box(Vector3(0.20, 0.012, 0.035), TEAL.darkened(0.2), at + Vector3(0.0, 0.002, float(side) * 0.05), terrain)
		wave.name = "SlackMark_" + str(route.id)
		_slack_marks.append(wave)

# --- Water, chamber, sea gates, mouth lamps and spout ---

## One body of water: the region minus every island and excluded rectangle,
## merged into strips. Its root moves and stretches with the level, so the
## water always reaches down to the harbour floor.
func _water_body(name: String, regions: Array, islands: Array, excluded: Array, color: Color, level: float) -> Node3D:
	var holes: Array = excluded.duplicate()
	for island: Dictionary in islands: holes.append(island.rect_cm)
	var xs: Array = []
	var zs: Array = []
	for rect: Array in regions + holes:
		for x: int in [rect[0], rect[2]]:
			if x not in xs: xs.append(x)
		for z: int in [rect[1], rect[3]]:
			if z not in zs: zs.append(z)
	xs.sort()
	zs.sort()
	var root := Node3D.new()
	root.name = name
	terrain.add_child(root)
	var surface := Primitives.fresh_material(color, 0.35)
	# Labels, faded floors and the spout draw over the water, never under it.
	surface.render_priority = -2
	for zi in range(zs.size() - 1):
		var start := -1
		for xi in range(xs.size()):
			var wet := xi < xs.size() - 1 and _wet((xs[xi] + xs[xi + 1]) * 0.5, (zs[zi] + zs[zi + 1]) * 0.5, regions, holes)
			if wet and start < 0: start = xi
			if not wet and start >= 0:
				var strip := Primitives.mesh_node(Primitives.box_mesh(Vector3(float(xs[xi] - xs[start]) / 100.0, 1.0, float(zs[zi + 1] - zs[zi]) / 100.0)), surface,
					Vector3(float(xs[start] + xs[xi]) / 200.0, -0.5, float(zs[zi] + zs[zi + 1]) / 200.0), root)
				strip.name = "WaterStrip"
				strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				start = -1
	_water_entry(root, level)
	return root

static func _wet(x: float, z: float, regions: Array, holes: Array) -> bool:
	var inside := false
	for region: Array in regions:
		if x > region[0] and x < region[2] and z > region[1] and z < region[3]: inside = true
	if not inside: return false
	for hole: Array in holes:
		if x > hole[0] and x < hole[2] and z > hole[1] and z < hole[3]: return false
	return true

func _water_entry(root: Node3D, level: float) -> void:
	root.set_meta("target", level)
	root.set_meta("shown", level)
	_show_water(root, level)

func _show_water(root: Node3D, level: float) -> void:
	root.set_meta("shown", level)
	root.position.y = level
	root.scale.y = maxf(level - SEABED, 0.02)

func _set_water(name: String, level: float, immediate: bool) -> void:
	var root: Node3D = _water.get(name)
	if not is_instance_valid(root): return
	root.set_meta("target", level)
	if immediate or reduced_motion: _show_water(root, level)

func _advance_water(delta: float) -> void:
	for root: Node3D in _water.values():
		if not is_instance_valid(root): continue
		var target := float(root.get_meta("target"))
		var shown := float(root.get_meta("shown"))
		if not is_equal_approx(shown, target): _show_water(root, move_toward(shown, target, WATER_RATE * maxf(delta, 0.0)))

func _build_chamber() -> void:
	var pit := CHAMBER_PIT
	var west := float(pit[0]) / 100.0
	var east := float(pit[2]) / 100.0
	var height := CHAMBER_WALL_TOP - SEABED
	for z_side: Array in [[pit[1], -96], [96, pit[3]]]:
		var middle := float(z_side[0] + z_side[1]) / 200.0
		var depth := float(z_side[1] - z_side[0]) / 100.0
		for x: float in [west, east]:
			box(Vector3(0.06, height, depth), STONE_DARK, Vector3(x, SEABED + height * 0.5, middle), terrain).name = "ChamberWall"
	for z: float in [float(pit[1]) / 100.0, float(pit[3]) / 100.0]:
		box(Vector3(east - west + 0.06, height, 0.06), STONE_DARK, Vector3((west + east) * 0.5, SEABED + height * 0.5, z), terrain).name = "ChamberWall"
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
			box(Vector3(span - 0.02, 1.30, 0.08), TIMBER, Vector3(-side * (span * 0.5), SEABED + 0.65 + 0.10, 0), hinge)
			box(Vector3(span - 0.02, 0.05, 0.10), TIMBER.darkened(0.2), Vector3(-side * (span * 0.5), 0.70, 0), hinge)
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
		cylinder(0.035, top - SEABED, TIMBER.darkened(0.1), at + Vector3(0, (top + SEABED) * 0.5, 0), terrain)
		for band in range(TIDE_VALUES.find(value) + 1):
			cylinder(0.05, 0.03, TEAL, at + Vector3(0, top - 0.24 - float(band) * 0.07, 0), terrain)
		var lamp := sphere(0.08, Color("4a4038"), at + Vector3(0, top + 0.06, 0), terrain)
		lamp.name = "MouthLamp_" + value
		_mouth_lamps[value] = lamp

func _build_spout() -> void:
	for drop: Dictionary in current_level.get("drops", []):
		var r: Array = drop.rect_cm
		var top := _surface_height(str(drop.surface_id))
		var bottom := float(drop.get("height_cm", 0)) / 100.0
		_spout = Node3D.new()
		_spout.name = "SpoutWater"
		_spout.position = point([(r[0] + r[2]) * 0.5, (r[1] + r[3]) * 0.5])
		terrain.add_child(_spout)
		var fall := Primitives.mesh_node(Primitives.box_mesh(Vector3(float(r[2] - r[0]) / 100.0 - 0.08, top - bottom, float(r[3] - r[1]) / 100.0 - 0.06)), Primitives.fresh_material(SPOUT, 0.2), Vector3(0, (top + bottom) * 0.5, 0), _spout)
		fall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_glow(fall, SPOUT, 0.35)
		# Pale streaks down the front of the falling water.
		for index in range(3):
			var streak := box(Vector3(0.025, top - bottom - 0.04, 0.01), CREAM, Vector3((float(index) - 1.0) * 0.10, (top + bottom) * 0.5, float(r[3] - r[1]) / 200.0 - 0.02), _spout)
			streak.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var splash := ring(0.26, Color("d7ecec"), Vector3(0, bottom + 0.02, 0), _spout)
		splash.scale.y = 0.5
		_spout.set_meta("lever", str(drop.get("requires_lever", "")))
		_spout.visible = false
		# The lip only the second spirit may cross, at the access zone's edge.
		for zone: Dictionary in current_level.get("access_zones", []):
			if zone.surface_id != drop.surface_id: continue
			var z: Array = zone.rect_cm
			box(Vector3(0.05, 0.04, float(z[3] - z[1]) / 100.0 - 0.04), TEAL, Vector3(float(z[0]) / 100.0 - 0.03, top + 0.02, float(z[1] + z[3]) / 200.0), terrain).name = "SpoutLip"
		return

# --- History, presentation and camera ---

func present_history(checkpoint: Dictionary) -> void:
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
		var t := float(chosen) / float(maxi(wheel.values.size() - 1, 1))
		wheel.wheel.rotation.z = _wheel_angle(chosen, wheel.values.size())
		wheel.wheel.set_meta("value", str(controls.get(id, "")))
		if _physical_levers.has(id): _physical_levers[id].rotation.z = lerpf(0.60, -0.60, t)
	_set_water("harbour", float(HARBOUR_LEVELS.get(tide, HARBOUR_LEVELS.low)), immediate)
	_set_water("sea", float(SEA_LEVELS.get(basin, SEA_LEVELS.shut)), immediate)
	_set_water("chamber", float(HARBOUR_LEVELS.get(str(controls.get("chamber", "half")), HARBOUR_LEVELS.half)), immediate)
	for id: String in _gauges:
		var gauge: Dictionary = _gauges[id]
		var lit: bool = tide in gauge.values
		for band: MeshInstance3D in gauge.bands: _glow(band, GOLD, 0.9 if lit else 0.0)
		gauge.post.set_meta("lit", lit)
	for value: String in _mouth_lamps: _lamp(_mouth_lamps[value], TEAL, basin == value)
	for id: String in _lever_lamps: _lamp(_lever_lamps[id].lamp, _lever_lamps[id].color, bool(levers.get(id, false)))
	var matched := controls.has("chamber") and str(controls.get("chamber")) == tide
	for lamp: MeshInstance3D in _chamber_lamps: _lamp(lamp, GOLD, matched)
	for hinge: Node3D in _sea_gates:
		# Open leaves swing in along the mouth, staying in the water.
		hinge.rotation.y = 0.0 if basin == "shut" else -float(hinge.get_meta("side")) * float(hinge.get_meta("outward")) * 1.35
		hinge.set_meta("open", basin != "shut")
	if is_instance_valid(_spout): _spout.visible = bool(levers.get(str(_spout.get_meta("lever")), false))
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

func _lamp(lamp: MeshInstance3D, color: Color, lit: bool) -> void:
	(lamp.material_override as StandardMaterial3D).albedo_color = color if lit else Color("4a4038")
	_glow(lamp, color, 1.2 if lit else 0.0)
	lamp.set_meta("lit", lit)

func _advance_camera(delta: float) -> void:
	_advance_water(delta)
	super._advance_camera(delta)

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
	if not _completion_view and actors.has(_active_player):
		var at: Vector3 = actors[_active_player].position
		target.x = clampf(at.x, CAMERA_X.x, CAMERA_X.y)
		target.z = clampf(at.z, CAMERA_Z.x, CAMERA_Z.y)
	return target
