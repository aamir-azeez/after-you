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
## The outer sea: wide past the mole, through the harbour mouth, and a short
## reach past each end of the mouth where the sea gates stand. Breakwaters hold
## it where it ends in view.
const SEA_REGIONS := [[-2400, -640, -960, 640], [-960, -480, -704, 480], [-704, -560, -512, 560]]
const MOUTH_X := [-704, -512]
const SEA_GATE_Z := 5.20
const CHAMBER_PIT := [-640, -128, -576, 128]
const CHAMBER_WALL_TOP := 0.74
## Water stops this many cm short of what holds it on the sides the camera sees.
const WATER_INSET := 3
const AQUEDUCT := ["aq-feeder", "aq-span"]
const WATER := Color(0.25, 0.42, 0.47, 0.84)
const SEA := Color(0.21, 0.37, 0.44, 0.88)
const CHAMBER_WATER := Color(0.28, 0.46, 0.50, 0.84)
const SPOUT := Color(0.80, 0.93, 0.95, 0.86)
const STONE := Color("a8947a")
const STONE_DARK := Color("7d6d58")
const TIMBER := Color("7a5d45")
const PILE := Color("5f4a38")
const SAND := Color("e3cf9f")
const BRASS := Color("b8914f")
const COPING := Color("dccaa4")
## One masonry for every wall that holds water back, so walls that meet at a
## corner read as one wall.
const PARAPET_STONE := Color("b8a283")
const FENDER := Color("6b4f37")
const ROPE := Color("d1b98c")
## Walls under each tier, by deck height in cm: pale sand, terracotta, honey.
const WALLS := {0: Color("bca681"), 48: Color("a3705a"), 96: Color("8e6d48")}
## Ground when the dressing names none, by deck height in cm.
const DEFAULT_GROUND := {0: "sand", 48: "terracotta", 96: "honey_cobble"}
## Water never stands higher than high; walls that hold it back stand to here.
const PARAPET_TOP := 0.77
## Weed and wet bands on every wall at the three water marks.
const MARK_BANDS := {"low": Color("4d5b40"), "half": Color("655e4c"), "high": Color("7a6f5d")}
const TIDE_VALUES := ["low", "half", "high"]
const CAMERA_X := Vector2(-9.6, 17.28)
const CAMERA_Z := Vector2(-5.44, 5.44)
## Dark sign plates: the water signs, the key sign and the gauge waves' outline.
const CHIP_DARK := Color("102133")
const WHEEL_SWEEP := 0.95
## The hand wheel stands beside the standing point, clear of the spirit and its badge.
const WHEEL_OFFSET := Vector3(0.62, 1.0, -0.42)
## Every selector's speech bubble points at its lever, like every chapter's.
## A wheel's bubble sits this far sideways on screen (metres; the kit clamps a
## shift to the farthest its tail still meets the body), clear of its hand
## wheel: the tide's and the chamber's to the left; the sea's centred, so once
## it has risen over the gate-bar and sea-bar levers it stays clear of jetty-1's
## gauge, with or without a spirit at its lever. Whatever a bubble would still
## cover, it rises over (_clear_scenery); its tail stays on its lever.
const BUBBLE_SHIFTS := {"tide": -4.0, "chamber": -4.0, "basin": 0.1}
## A bubble rises over a gauge's head, a hand wheel, another lever's knob or a
## pad once it covers more than this share of it (the share the journey worlds
## allow over a spirit).
const SCENERY_COVER := 0.10
## Each water wheel's tint, for its rim, dial and water sign.
const WHEEL_WATER := {"tide": Color("6fb3c2"), "basin": Color("4f8fb5"), "chamber": Color("7cc4b0")}
## The first spirit's machines; everything else belongs to the second.
const P0_MECHANISMS := ["tide", "chamber", "winch", "sluice", "line", "punt-line", "boom-pin", "sea-key", "wheel-step-pad", "quay-step-pad", "bollard-pad"]
## Crest glyph per mechanism: [shape, count]. Within each stage every machine
## that opens a route has its own glyph (shape and count), so a crossing's
## crests say which machines it waits on without relying on colour. The lock
## keeps its glyph in both stages; the tide is read from gauges instead.
const CRESTS := {
	"winch": ["bar", 1], "sluice": ["bar", 2], "line": ["bar", 3],
	"lock": ["dot", 1], "gangway": ["dot", 2], "bollard-pad": ["cross", 3],
	"chamber": ["cross", 1], "gate-bar": ["cross", 2], "basin": ["dot", 3],
	"boom-chain": ["chevron", 1], "sea-bar": ["chevron", 2], "punt-chain": ["chevron", 3],
	"punt-line": ["ring", 1], "boom-pin": ["pin", 1], "sea-key": ["key", 1],
}
## Which mouth crossing each sea value serves.
const MOUTHS := {"half": "boom-jetty", "low": "sea-gate-out", "high": "punt-ferry"}
## How each crossing is built.
const DECK_KINDS := {"sand-1": "sand", "slipway": "sand", "stones-1": "stones", "stones-2": "stones", "stones-3": "stones",
	"jetty-1": "jetty", "jetty-2": "jetty", "boom-jetty": "jetty", "jetty-3": "gangway", "towpath": "towpath", "punt-ferry": "punt"}
## Moored rowboats in the harbour channels, clear of every crossing: [x, z, heading].
const BOATS := [[-64, 176, 0.12], [480, 168, -0.18], [1248, -176, 0.10]]
## Lamps on the banks behind the quays, each with a light pool and bunting
## strung to a point further along its bank: [lamp x, z, bunting end x, z].
const LAMPS := [[-370, -530, -232, -640], [965, -530, 1140, -655], [1540, -530, 1700, -640]]

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
var _spout_streaks: Array[MeshInstance3D] = []
var _history_tide := ""
## Crossings that may be open while their water stands above the deck: walled
## and kept out of the water body.
var _walled: Array[String] = []
## Gated walled crossings: id -> the water that fills them while shut.
var _floods: Dictionary = {}
## Shut crossings stay in view as faint outlines: id -> ghost node.
var _ghosts: Dictionary = {}
var _boats: Array[Node3D] = []
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
## Parapet and sea-wall runs depend only on the chapter's floors and crossings,
## which both stages share: worked out once per definition, then reused.
static var _wall_layouts: Dictionary = {}

## Builds only the stage shown first. Controllers call show_stage straight
## after load_level, so opening on the second stage no longer builds the first
## stage's harbour just to tear it down. A caller that shows no stage still gets
## the first one: before its first history, or at the end of the frame.
## Otherwise as cooperative_world.load_level.
func load_level(definition: Dictionary) -> void:
	chapter_definition = definition.duplicate(true)
	displayed_stage_id = ""
	_show_first_stage.call_deferred()

func _show_first_stage() -> void:
	if displayed_stage_id.is_empty() and not chapter_definition.get("stages", []).is_empty(): show_stage(chapter_definition.stages[0])

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
	_spout_streaks.clear()
	_history_tide = ""
	_floods.clear()
	_ghosts.clear()
	_boats.clear()
	_kept_masts.clear()
	_bubbles_placed = false
	_walled = _walled_routes(stage)
	super.show_stage(stage)
	terrain.name = "TurnOfTheTide"
	var islands: Array = chapter_definition.get("islands", [])
	var cut: Array = [CHAMBER_PIT]
	for id: String in _walled: cut.append(_route(id).rect_cm)
	_water["harbour"] = _water_body("HarbourWater", [HARBOUR_REGION], islands, cut, WATER, HARBOUR_LEVELS.low)
	_water["sea"] = _water_body("OuterSea", SEA_REGIONS, islands, cut, SEA, SEA_LEVELS.shut)
	_water["chamber"] = _water_body("ChamberWater", [CHAMBER_PIT], islands, [], CHAMBER_WATER, HARBOUR_LEVELS.half)
	_build_parapets()
	_build_sea_walls()
	_build_route_walls(stage)
	_build_chamber()
	_build_sea_gates()
	_build_mouth_lamps()
	_build_spout()
	_build_foreshore()
	_build_boats()
	_build_lamplight()

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
	box(Vector3(size.x - 0.012, 0.03, 0.02), color.darkened(0.18), Vector3(wall.position.x, -0.34, float(r[3]) / 100.0 - 0.005), raised)
	# Block courses down the face, and the water marks round every face.
	var y := -0.62
	while y > bottom + 0.08:
		var clear := true
		for level: float in HARBOUR_LEVELS.values(): clear = clear and absf(height + y - level) > 0.06
		if clear: box(Vector3(size.x + 0.016, 0.012, size.z + 0.016), color.darkened(0.10), Vector3(wall.position.x, y, wall.position.z), raised).name = "WallCourse"
		y -= 0.28
	_mark_bands(Vector3(wall.position.x, 0, wall.position.z) + Vector3(0, height, 0), Vector2(size.x, size.z), SEABED, height - 0.20, raised, height)

## Bands at every water mark between `bottom` and `top` (world heights) around a
## wall block of `footprint` (metres) centred at `center` (world), under
## `parent` whose origin is `origin_y` above the ground. A wall run along x (or
## z) keeps its bands a little short of its own ends, clear of the walls it meets.
func _mark_bands(center: Vector3, footprint: Vector2, bottom: float, top: float, parent: Node3D, origin_y: float = 0.0, run_along: int = -1) -> void:
	var grow := Vector2(-0.008 if run_along == 0 else 0.05, -0.008 if run_along == 1 else 0.05)
	for value: String in TIDE_VALUES:
		var level: float = HARBOUR_LEVELS[value]
		if level <= bottom + 0.03 or level >= top - 0.03: continue
		var band := box(Vector3(footprint.x + grow.x, 0.036, footprint.y + grow.y), MARK_BANDS[value], Vector3(center.x, level - 0.012 - origin_y, center.z), parent)
		band.name = "WaterMark_" + value
		band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

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

# --- Parapets: water stands against stone, never against a dry deck ---

## The body of water a rectangle's centre lies in: "harbour", "sea" or "".
static func _body_of(rect: Array) -> String:
	var x := float(rect[0] + rect[2]) * 0.5
	var z := float(rect[1] + rect[3]) * 0.5
	if _inside([x, z], HARBOUR_REGION): return "harbour"
	for region: Array in SEA_REGIONS:
		if _inside([x, z], region): return "sea"
	return ""

static func _inside(at: Array, rect: Array) -> bool:
	return float(at[0]) > float(rect[0]) and float(at[0]) < float(rect[2]) and float(at[1]) > float(rect[1]) and float(at[1]) < float(rect[3])

func _route(id: String) -> Dictionary:
	for route: Dictionary in chapter_definition.get("bridges", []) + chapter_definition.get("stairs", []):
		if route.id == id: return route
	return {}

static func _low_cm(route: Dictionary) -> int:
	if route.has("axis"): return mini(int(route.from_height_cm), int(route.to_height_cm))
	return int(route.get("height_cm", 0))

## Crossings in this stage that can stand open while their water rises above
## the deck: every always-open low crossing (stairs, the towpath, the mole
## slip), and every gated one whose gate does not tie it to a water value that
## leaves its deck dry (the posts, catwalks, lock gates, punt and chamber gate).
func _walled_routes(stage: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for route: Dictionary in chapter_definition.get("bridges", []) + chapter_definition.get("stairs", []):
		var low := _low_cm(route)
		var body := _body_of(route.rect_cm)
		if low >= 70 or body.is_empty(): continue
		var gate: Variant = null
		for item: Dictionary in stage.get("gates", []):
			if item.route_id == route.id: gate = item
		if gate == null: continue
		var levels: Dictionary = HARBOUR_LEVELS if body == "harbour" else SEA_LEVELS
		var marks := _control_marks(gate.get("when", {}), "tide" if body == "harbour" else "basin")
		var dry := not marks.is_empty()
		for value: String in marks:
			if float(levels[value]) >= float(low) / 100.0: dry = false
		if not dry: result.append(str(route.id))
	return result

## Values a predicate needs outright (through "all" only) of one control.
static func _control_marks(predicate: Dictionary, control: String) -> Array:
	var found: Array = []
	if str(predicate.get("control_id", "")) == control: found.append(str(predicate.get("value", "")))
	for child: Dictionary in predicate.get("all", []):
		for value: String in _control_marks(child, control):
			if value not in found: found.append(value)
	return found

## Every beach and terrace edge that faces water gets a parapet to just above
## high water, with a coping stone; crossing mouths stay open, so a flooded
## crossing shows as water in the gap. Quays stand above every tide and get a
## timber fender instead.
func _build_parapets() -> void:
	var root := Node3D.new()
	root.name = "Parapets"
	terrain.add_child(root)
	for wall: Array in _wall_layout().parapets:
		var run: Array = wall[0]
		var edge: float = wall[1]
		var outward: float = wall[2]
		var along_x: bool = wall[3]
		var height: float = wall[4]
		if height >= 0.70: _fender(run, edge, outward, along_x, height, root)
		else: _parapet(run, edge, outward, along_x, height, root)

## Every parapet and sea-wall run, in build order: {"parapets": [[run, edge,
## outward, along_x, height]], "sea_walls": [[run, edge, outward, along_x]]}.
func _wall_layout() -> Dictionary:
	var islands: Array = chapter_definition.get("islands", [])
	var routes: Array = chapter_definition.get("bridges", []) + chapter_definition.get("stairs", [])
	var key := [islands, routes].hash()
	if not _wall_layouts.has(key): _wall_layouts[key] = {"parapets": _parapet_runs(islands, routes), "sea_walls": _sea_wall_runs(islands)}
	return _wall_layouts[key]

func _parapet_runs(islands: Array, routes: Array) -> Array:
	var holes: Array = [CHAMBER_PIT]
	for island: Dictionary in islands: holes.append(island.rect_cm)
	var walls: Array = []
	for island: Dictionary in islands:
		var id := str(island.id)
		if id in AQUEDUCT or id == "sea-chamber": continue
		var height := float(island.get("height_cm", 0)) / 100.0
		var r: Array = island.rect_cm
		for side in range(4):
			var along_x := side < 2
			var edge := float(r[1] if side == 0 else r[3] if side == 1 else r[0] if side == 2 else r[2])
			var outward := -1.0 if side == 0 or side == 2 else 1.0
			var start := float(r[0] if along_x else r[1]) - 8.0
			var finish := float(r[2] if along_x else r[3]) + 8.0
			var runs: Array = []
			var t := start + 2.0
			while t <= finish - 2.0:
				var at: Array = [t, edge + outward * 6.0] if along_x else [edge + outward * 6.0, t]
				var kind := "dry"
				for route: Dictionary in routes:
					if _inside(at, route.rect_cm): kind = "mouth"
				if kind == "dry" and _wet_at(at, holes): kind = "wall"
				if runs.is_empty() or runs[-1][2] != kind: runs.append([t - 2.0, t + 2.0, kind])
				else: runs[-1][1] = t + 2.0
				t += 4.0
			for run: Array in runs:
				if run[2] == "wall": walls.append([run, edge, outward, along_x, height])
	return walls

func _wet_at(at: Array, holes: Array) -> bool:
	var regions: Array = [HARBOUR_REGION] + SEA_REGIONS
	var wet := false
	for region: Array in regions:
		if _inside(at, region): wet = true
	if not wet: return false
	for hole: Array in holes:
		if _inside(at, hole): return false
	return true

## Where a body of water ends in view against open air or the other water (the
## harbour's channel ends, the sea gates' reaches, the mouth beside the west
## islands), a sea wall to above high water holds it: no water ever shows a
## bare face.
func _build_sea_walls() -> void:
	var root := Node3D.new()
	root.name = "SeaWalls"
	terrain.add_child(root)
	for wall: Array in _wall_layout().sea_walls:
		var run: Array = wall[0]
		var edge: float = wall[1]
		var outward: float = wall[2]
		var along_x: bool = wall[3]
		var out := Vector3(0, 0, outward * 0.015) if along_x else Vector3(outward * 0.015, 0, 0)
		var piece := _edge_box(run, edge, outward, along_x, 0.12, SEABED, PARAPET_TOP, PARAPET_STONE, root, 0.6)
		piece.position += out
		piece.name = "SeaWall"
		var coping := _edge_box(run, edge, outward, along_x, 0.17, PARAPET_TOP, PARAPET_TOP + 0.05, COPING, root, 0.6)
		coping.position += out + (Vector3(0, 0, -outward * 0.025) if along_x else Vector3(-outward * 0.025, 0, 0))
		var size := (piece.mesh as BoxMesh).size
		_mark_bands(piece.position, Vector2(size.x, size.z), SEABED, PARAPET_TOP, root, 0.0, 0 if along_x else 1)

func _sea_wall_runs(islands: Array) -> Array:
	var holes: Array = [CHAMBER_PIT]
	for island: Dictionary in islands: holes.append(island.rect_cm)
	var walls: Array = []
	for body: Array in [[HARBOUR_REGION], SEA_REGIONS]:
		for region: Array in body:
			for side in range(4):
				var along_x := side < 2
				var edge := float(region[1] if side == 0 else region[3] if side == 1 else region[0] if side == 2 else region[2])
				var outward := -1.0 if side == 0 or side == 2 else 1.0
				var start := float(region[0] if along_x else region[1])
				var finish := float(region[2] if along_x else region[3])
				var runs: Array = []
				var t := start + 2.0
				while t <= finish - 2.0:
					var inside: Array = [t, edge - outward * 2.0] if along_x else [edge - outward * 2.0, t]
					var outside: Array = [t, edge + outward * 2.0] if along_x else [edge + outward * 2.0, t]
					var wall := _wet(float(inside[0]), float(inside[1]), body, holes)
					for other: Array in body:
						if _inside(outside, other): wall = false
					# The harbour side builds the wall between the two waters.
					if body != [HARBOUR_REGION] and _inside(outside, HARBOUR_REGION): wall = false
					for hole: Array in holes:
						if _inside(outside, hole): wall = false
					var view: Array = [t, edge] if along_x else [edge, t]
					if absf(float(view[0]) - 384.0) > 1500.0 or absf(float(view[1])) > 700.0: wall = false
					if wall and not runs.is_empty() and float(runs[-1][1]) >= t - 2.0: runs[-1][1] = t + 2.0
					elif wall: runs.append([t - 2.0, t + 2.0])
					t += 4.0
				for run: Array in runs: walls.append([run, edge, outward, along_x])
	return walls

## A wall piece along one edge: [from, to] in cm along the edge, short of
## each end by `trim` cm so it never shares a face with what it meets.
func _edge_box(run: Array, edge: float, outward: float, along_x: bool, thickness: float, bottom: float, top: float, color: Color, parent: Node3D, trim: float = 0.0) -> MeshInstance3D:
	var length := float(run[1] - run[0] - 2.0 * trim) / 100.0
	var middle := float(run[0] + run[1]) / 200.0
	var off := edge / 100.0 + outward * thickness * 0.5
	var size := Vector3(length, top - bottom, thickness) if along_x else Vector3(thickness, top - bottom, length)
	var at := Vector3(middle, (top + bottom) * 0.5, off) if along_x else Vector3(off, (top + bottom) * 0.5, middle)
	return box(size, color, at, parent)

func _parapet(run: Array, edge: float, outward: float, along_x: bool, height: float, parent: Node3D) -> void:
	var wall := _edge_box(run, edge, outward, along_x, 0.09, height - 0.20, PARAPET_TOP, PARAPET_STONE, parent, 0.6)
	wall.name = "Parapet"
	var coping := _edge_box(run, edge, outward, along_x, 0.14, PARAPET_TOP, PARAPET_TOP + 0.05, COPING, parent, 0.6)
	coping.position += (Vector3(0, 0, -outward * 0.025) if along_x else Vector3(-outward * 0.025, 0, 0))
	coping.name = "ParapetCoping"
	var size := (wall.mesh as BoxMesh).size
	_mark_bands(wall.position, Vector2(size.x, size.z), height - 0.20, PARAPET_TOP, parent, 0.0, 0 if along_x else 1)

func _fender(run: Array, edge: float, outward: float, along_x: bool, height: float, parent: Node3D) -> void:
	_edge_box(run, edge, outward, along_x, 0.10, height - 0.16, height - 0.03, FENDER, parent, 0.6).name = "QuayFender"

## Walled crossings: masonry along the sides that do not meet their floors, a floor in the dry pit, a plinth under
## each stair, and for a gated one the water that fills it while it is shut.
func _build_route_walls(stage: Dictionary) -> void:
	var root := Node3D.new()
	root.name = "WalledCrossings"
	terrain.add_child(root)
	for id: String in _walled:
		var route := _route(id)
		var r: Array = route.rect_cm
		var floors: Array = []
		for surface: Variant in [route.get("from_surface", ""), route.get("to_surface", "")]:
			if str(surface) == id: continue
			for item: Dictionary in chapter_definition.get("islands", []) + chapter_definition.get("bridges", []):
				if item.id == surface: floors.append(item.rect_cm)
		var color := PARAPET_STONE
		for side in range(4):
			var along_x := side < 2
			var edge := float(r[1] if side == 0 else r[3] if side == 1 else r[0] if side == 2 else r[2])
			var outward := -1.0 if side == 0 or side == 2 else 1.0
			var mouth := false
			for floor: Array in floors:
				var touches := absf(float(floor[3] if outward < 0 else floor[1]) - edge) <= 2.0 if along_x else absf(float(floor[2] if outward < 0 else floor[0]) - edge) <= 2.0
				var overlaps := float(floor[0]) < float(r[2]) and float(floor[2]) > float(r[0]) if along_x else float(floor[1]) < float(r[3]) and float(floor[3]) > float(r[1])
				if touches and overlaps: mouth = true
			if mouth: continue
			var run: Array = [float(r[0]) - 9.0, float(r[2]) + 9.0] if along_x else [float(r[1]) - 9.0, float(r[3]) + 9.0]
			var wall := _edge_box(run, edge, outward, along_x, 0.09, SEABED, PARAPET_TOP, color, root)
			wall.name = "CrossingWall_" + id
			var coping := _edge_box(run, edge, outward, along_x, 0.14, PARAPET_TOP, PARAPET_TOP + 0.05, COPING, root)
			coping.position += (Vector3(0, 0, -outward * 0.025) if along_x else Vector3(-outward * 0.025, 0, 0))
			coping.name = "CrossingCoping"
			var size := (wall.mesh as BoxMesh).size
			_mark_bands(wall.position, Vector2(size.x, size.z), SEABED, PARAPET_TOP, root, 0.0, 0 if along_x else 1)
		var center := point([(r[0] + r[2]) * 0.5, (r[1] + r[3]) * 0.5])
		var width := float(r[2] - r[0]) / 100.0
		var depth := float(r[3] - r[1]) / 100.0
		box(Vector3(width, 0.04, depth), STONE_DARK.darkened(0.2), center + Vector3(0, SEABED + 0.02, 0), root).name = "PitFloor"
		if route.has("axis"):
			var top := float(_low_cm(route)) / 100.0 - 0.12
			box(Vector3(width - 0.04, top - SEABED, depth - 0.04), WALLS.get(48, STONE).darkened(0.08), center + Vector3(0, (top + SEABED) * 0.5, 0), root).name = "StairPlinth"
		var gate: Dictionary = {}
		for item: Dictionary in stage.get("gates", []):
			if item.route_id == id: gate = item
		if gate.get("when", {}).is_empty(): continue
		var body: Node3D = _water.get(_body_of(r))
		if not is_instance_valid(body): continue
		var water: MeshInstance3D = body.get_child(0) if body.get_child_count() > 0 else null
		# Its sides toward the camera stand 3 cm inside the crossing, clear of the
		# faces of its deck, frame and pit floor.
		var flood := Primitives.mesh_node(Primitives.box_mesh(Vector3(width - 0.03, 1.0, depth - 0.03)), water.material_override if water != null else material(WATER), Vector3(center.x - 0.015, -0.5, center.z - 0.015), body)
		flood.name = "FloodedCrossing_" + id
		flood.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		flood.visible = false
		_floods[id] = flood

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
	_restyle_deck(definition)
	_kept_pennant(definition)
	if id.begins_with("jetty") or id == "boom-jetty": _piles(definition)
	if _is_stub(definition): _stub_frame(definition)
	else: _ghost(definition)

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

## Each crossing in its own build: a rippled sand hump, round stepping stones,
## piled timber, a rope-railed gangway, flagged towpath stones or a punt. The
## long edges glow while the crossing is open, in gold where the tide opens it.
func _restyle_deck(route: Dictionary) -> void:
	var id := str(route.id)
	var deck: Node3D = _decks.get(id)
	if deck == null: return
	var memories: Node3D = _memory_markers.get(id)
	for child: Node in deck.get_children():
		if child == memories: continue
		deck.remove_child(child)
		child.free()
	var r: Array = route.rect_cm
	var width := float(r[2] - r[0]) / 100.0
	var depth := float(r[3] - r[1]) / 100.0
	var across_x := width >= depth
	var length := width if across_x else depth
	var lane := depth if across_x else width
	var kind: String = DECK_KINDS.get(id, "timber")
	match kind:
		"sand":
			box(Vector3(width, 0.10, depth), SAND, Vector3(0, -0.05, 0), deck)
			box(Vector3(width * (0.86 if across_x else 0.7), 0.02, depth * (0.7 if across_x else 0.86)), SAND.lightened(0.06), Vector3(0, -0.006, 0), deck)
			for index in range(6):
				var along := (float(index) + 0.5) / 6.0 * length - length * 0.5
				box(Vector3(0.016, 0.006, lane - 0.12) if across_x else Vector3(lane - 0.12, 0.006, 0.016), SAND.darkened(0.12), Vector3(along, 0.005, 0) if across_x else Vector3(0, 0.005, along), deck)
		"stones":
			var count := clampi(int(round(length / 0.42)), 3, 5)
			var radius := minf(0.26, lane * 0.5 - 0.02)
			for index in range(count):
				var along := (float(index) + 0.5) / float(count) * length - length * 0.5
				var at := Vector3(along, -0.06, 0) if across_x else Vector3(0, -0.06, along)
				cylinder(radius, 0.12, STONE.darkened(0.04 * float(index % 2)), at, deck).name = "SteppingStone"
				cylinder(radius * 0.8, 0.012, STONE.lightened(0.10), at + Vector3(0, 0.062, 0), deck)
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

## A shut crossing stays in view as a faint outline at its own height (sunk
## under the water when the tide covers it), so the other ways can be read.
func _ghost(route: Dictionary) -> void:
	var id := str(route.id)
	var deck: Node3D = _decks.get(id)
	if deck == null: return
	var ghost := deck.duplicate() as Node3D
	ghost.name = "ShutCrossing_" + id
	var memories := ghost.find_child("RememberedFootsteps", false, false)
	if memories != null:
		ghost.remove_child(memories)
		memories.free()
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
	var middle := Vector2(float(r[0] + r[2]), float(r[1] + r[3])) / 2.0
	var body := "chamber" if _covered(middle.x, middle.y, [CHAMBER_PIT]) else "sea" if _covered(middle.x, middle.y, SEA_REGIONS) else "harbour"
	_kept_masts.append({"deck": float(route.get("height_cm", 0)) / 100.0, "body": body, "post": post, "knob": knob, "flag": flag})
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
		cylinder(0.035, y - SEABED, PILE, Vector3(x, (y + SEABED) * 0.5, tip), frame)

func _piles(route: Dictionary) -> void:
	var r: Array = route.rect_cm
	var top := float(route.height_cm) / 100.0 - 0.10
	for x: int in [r[0] + 10, r[2] - 10]:
		for z: int in [r[1] + 8, r[3] - 8]:
			cylinder(0.05, top - SEABED, PILE, Vector3(float(x) / 100.0, (top + SEABED) * 0.5, float(z) / 100.0), terrain).name = "JettyPile"

# --- Wheels and levers ---

## Every selector names its values in the shared speech bubble over its lever
## (journey_world). Three- and four-way wheels also get a spoked hand wheel
## whose needle shows the value, tinted with the water the wheel moves.
func _build_selector(control: Dictionary) -> void:
	super._build_selector(control)
	if control.values.size() >= 3: _build_wheel(control)

func _selector_bubble_shift(control: Dictionary) -> float:
	return float(BUBBLE_SHIFTS.get(control.id, 0.0))

## A small upright sign on a hand wheel's post: a wave for the harbour tide, a
## pair of gate leaves for the sea, a walled basin for the chamber.
func _water_icon(id: String, at: Vector3, tint: Color) -> void:
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

func _build_wheel(control: Dictionary) -> void:
	var color := GOLD if control.owner_slot == "p0" else TEAL
	var tint: Color = WHEEL_WATER.get(control.id, color)
	var values: Array = control.values
	# Beside and above the standing point, so neither a spirit at the wheel nor
	# its badge hides it.
	var center := _at(control) + WHEEL_OFFSET
	box(Vector3(0.07, 0.80, 0.07), TIMBER, center + Vector3(0, -0.44, -0.06), terrain)
	if WHEEL_WATER.has(control.id): _water_icon(str(control.id), center + Vector3(0, -0.56, -0.01), tint)
	# The dial plate: one notch per value, with 1, 2 or 3 bands for low, half and
	# high (the tide gauges use the same bands) and a bar for a shut sea, on a
	# disc in the colour of the water the wheel moves.
	var dial := Node3D.new()
	dial.name = "WheelDial_" + str(control.id)
	dial.position = center + Vector3(0, 0, -0.05)
	terrain.add_child(dial)
	var disc := cylinder(0.30, 0.02, tint.darkened(0.35), Vector3(0, 0, -0.02), dial)
	disc.rotation.x = PI / 2.0
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
	var inner := ring(0.19, tint, Vector3.ZERO, wheel)
	inner.rotation.x = PI / 2.0
	inner.scale = Vector3(1, 0.6, 1)
	for spoke in range(4):
		var bar := box(Vector3(0.025, 0.46, 0.025), TIMBER.lightened(0.15), Vector3.ZERO, wheel)
		bar.rotation.z = float(spoke) * PI / 4.0
	sphere(0.05, color.darkened(0.2), Vector3.ZERO, wheel)
	# A long cream needle from the hub to past the rim points at the value.
	var pointer := box(Vector3(0.04, 0.30, 0.03), CREAM, Vector3(0, 0.15, 0.03), wheel)
	pointer.name = "WheelPointer"
	_glow(pointer, CREAM, 0.3)
	_wheels[control.id] = {"wheel": wheel, "values": values.duplicate()}

static func _wheel_angle(index: int, count: int) -> float:
	return lerpf(WHEEL_SWEEP, -WHEEL_SWEEP, float(index) / float(maxi(count - 1, 1)))

func _build_lever(lever: Dictionary) -> void:
	var before := terrain.get_child_count()
	super._build_lever(lever)
	# The housing is warm brass under a timber collar, not grey stone.
	if terrain.get_child_count() > before:
		var housing := terrain.get_child(before) as MeshInstance3D
		if housing != null: (housing.material_override as StandardMaterial3D).albedo_color = BRASS
		cylinder(0.19, 0.04, TIMBER, _at(lever) + Vector3(0, 0.19, 0), terrain)
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
	# A tall harbour lantern on a mole stone well north of the standing point,
	# so a spirit lighting it never covers its head from the follow camera.
	var base := Vector3(0, 0, -0.85)
	box(Vector3(0.50, 0.22, 0.40), STONE, base + Vector3(0, 0.11, 0), cradle)
	cylinder(0.05, 1.40, TIMBER.darkened(0.2), base + Vector3(0, 0.92, 0), cradle)
	var head := base + Vector3(0, 1.78, 0)
	box(Vector3(0.40, 0.05, 0.40), TIMBER.darkened(0.25), head + Vector3(0, -0.24, 0), cradle)
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		box(Vector3(0.035, 0.46, 0.035), TIMBER.darkened(0.25), head + Vector3(corner.x * 0.16, 0, corner.y * 0.16), cradle)
	for side: Vector3 in [Vector3(0, 0, 0.16), Vector3(0, 0, -0.16), Vector3(0.16, 0, 0), Vector3(-0.16, 0, 0)]:
		var pane := box(Vector3(0.012 if side.x != 0.0 else 0.30, 0.40, 0.012 if side.z != 0.0 else 0.30), Color(1.0, 0.92, 0.72, 0.42), head + side, cradle)
		pane.name = "LanternPane"
		pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bell = sphere(0.10, Color("e6c98a"), head, cradle)
	_bell.name = "HarbourLantern"
	_glow(_bell, LIGHT_COLOR, 0.0)
	box(Vector3(0.46, 0.06, 0.46), TIMBER.darkened(0.25), head + Vector3(0, 0.25, 0), cradle)
	box(Vector3(0.28, 0.08, 0.28), TIMBER.darkened(0.25), head + Vector3(0, 0.31, 0), cradle)
	sphere(0.05, BRASS, head + Vector3(0, 0.38, 0), cradle)
	_court_light = OmniLight3D.new()
	_court_light.light_color = LIGHT_COLOR
	_court_light.light_energy = 0.0
	_court_light.omni_range = 4.5
	_court_light.position = cradle.position + head + Vector3(0, 0, 0.2)
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
	glyph.rotation.x = -PI / 2.0
	glyph.scale = Vector3.ONE * 2.2
	sign.add_child(glyph)
	_crest_glyph(CRESTS["sea-key"], GOLD, glyph)
	sign.set_meta("crest", "sea-key")

## Beside a machine: to its east on an island, or toward the far end of the
## narrow stub it stands on, so the crest never lands in a gap or on a neighbour.
func _crest_beside(entity: Dictionary, start: Vector3) -> Vector3:
	for route: Dictionary in chapter_definition.get("bridges", []):
		if route.id != entity.get("surface_id", "") or not _is_stub(route): continue
		return start + Vector3(0, 0.01, -0.22 if _route_anchor(route).z > float(route.rect_cm[3]) / 100.0 else 0.22)
	return start + Vector3(0.33, 0.01, 0)

## Tide values a gate needs outright (through "all" only), low to high.
func _tide_marks(predicate: Dictionary) -> Array:
	return _control_marks(predicate, "tide")

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
	var crest := Node3D.new()
	crest.name = "Crest_" + id
	crest.set_meta("crest", id)
	crest.position = at + Vector3(0, 0.02, 0)
	parent.add_child(crest)
	_crest_glyph(CRESTS.get(id, ["bar", 1]), color, crest)

## One glyph lying flat: `count` bars across the view, bars along it, dots,
## chevrons or rings, or a pin or a key.
func _crest_glyph(shape: Array, color: Color, parent: Node3D) -> void:
	var count := int(shape[1])
	for index in range(count):
		var x := (float(index) - float(count - 1) * 0.5) * 0.13
		match str(shape[0]):
			"bar": box(Vector3(0.07, 0.014, 0.18), color, Vector3(x, 0, 0), parent)
			"cross": box(Vector3(0.18, 0.014, 0.07), color, Vector3(0, 0, x), parent)
			"dot": cylinder(0.05, 0.016, color, Vector3(x, 0, 0), parent)
			"chevron":
				for side in [-1, 1]:
					box(Vector3(0.04, 0.014, 0.13), color, Vector3(x + float(side) * 0.03, 0, 0), parent).rotation.y = float(side) * 0.55
			"ring": ring(0.055, color, Vector3(x, 0, 0), parent)
			"pin":
				box(Vector3(0.035, 0.014, 0.16), color, Vector3(x, 0, 0.02), parent)
				ring(0.04, color, Vector3(x, 0, -0.08), parent)
			"key":
				ring(0.045, color, Vector3(x, 0, -0.07), parent)
				box(Vector3(0.03, 0.014, 0.14), color, Vector3(x, 0, 0.03), parent)
				box(Vector3(0.05, 0.014, 0.025), color, Vector3(x + 0.03, 0, 0.08), parent)
				box(Vector3(0.04, 0.014, 0.025), color, Vector3(x + 0.025, 0, 0.04), parent)

func _carries_pad(view: Dictionary, surface_id: String) -> bool:
	for pad: Dictionary in view.get("pressure_pads", []):
		if pad.get("surface_id", "") == surface_id: return true
	return false

## The sea value a gate needs outright, or "" when it needs none.
func _sea_value(predicate: Dictionary) -> String:
	var marks := _control_marks(predicate, "basin")
	return "" if marks.is_empty() else str(marks[0])

## A post's mouth shows the sea value it rises at: 1, 2 or 3 teal bands.
func _build_post_mark(route: Dictionary, value: String) -> void:
	var at := _route_anchor(route)
	var bands: Array[MeshInstance3D] = []
	var count := TIDE_VALUES.find(value) + 1
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
	var base := SEABED
	var at := point([r[0] + 16, r[3] + 12])
	var top := float(route.get("height_cm", 0)) / 100.0 + 0.92
	if route.has("axis"):
		at = point([r[2] + 12, (r[1] + r[3]) * 0.5])
		top = maxf(float(route.from_height_cm), float(route.to_height_cm)) / 100.0 + 0.90
	elif _is_stub(route):
		at = point([r[2] + 10, r[3] + 10]) if _route_anchor(route).z > float(r[3]) / 100.0 else point([r[2] + 10, r[1] - 10])
		base = float(route.height_cm) / 100.0
		top = base + 0.85
	var post := Node3D.new()
	post.name = "TideGauge_" + str(route.id)
	post.position = at
	terrain.add_child(post)
	cylinder(0.045, top - base, CREAM.darkened(0.15), Vector3(0, (top + base) * 0.5, 0), post)
	var bands: Array[MeshInstance3D] = []
	var count := 0
	for value: String in values: count = maxi(count, TIDE_VALUES.find(value) + 1)
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

## One body of water: the region minus every island and excluded rectangle, as
## one mesh of its surface and the outer faces of its sides. No face stands
## inside the water, where it would show through the surface as a band. Its
## root moves and stretches with the level, so the water always reaches down
## to the harbour floor.
## The sides that face the camera (east and south) stop WATER_INSET short of
## each island and walled crossing, and of the end of the body: inside the
## wall that holds the water back, or behind the sea wall past it, and never
## on a wall's inner face, where the two would fight over the same pixels.
func _water_body(name: String, regions: Array, islands: Array, excluded: Array, color: Color, level: float) -> Node3D:
	var holes: Array = []
	for rect: Array in excluded + islands.map(func(island: Dictionary) -> Array: return island.rect_cm):
		holes.append([int(rect[0]) - WATER_INSET, int(rect[1]) - WATER_INSET, rect[2], rect[3]])
	var xs: Array = []
	var zs: Array = []
	for rect: Array in regions + holes:
		for x: int in [rect[0], rect[2]]:
			if x not in xs: xs.append(x)
		for z: int in [rect[1], rect[3]]:
			if z not in zs: zs.append(z)
	for region: Array in regions:
		if int(region[2]) - WATER_INSET not in xs: xs.append(int(region[2]) - WATER_INSET)
		if int(region[3]) - WATER_INSET not in zs: zs.append(int(region[3]) - WATER_INSET)
	xs.sort()
	zs.sort()
	# wet[zi][xi]: whether the cell between those grid lines holds water. A cell
	# within WATER_INSET of where the body ends to its east or south stays dry.
	var wet: Array = []
	for zi in range(zs.size() - 1):
		var row: Array[bool] = []
		for xi in range(xs.size() - 1):
			var east := float(xs[xi + 1] + WATER_INSET)
			var south := float(zs[zi + 1] + WATER_INSET)
			var x := float(xs[xi] + xs[xi + 1]) * 0.5
			var z := float(zs[zi] + zs[zi + 1]) * 0.5
			row.append(_wet(x, z, regions, holes) and _covered(east, z, regions) and _covered(x, south, regions) and _covered(east, south, regions))
		wet.append(row)
	var shape := SurfaceTool.new()
	shape.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := 0
	# The surface, one quad per run of wet cells along each row.
	for zi in range(wet.size()):
		var start := -1
		for xi in range(xs.size()):
			var here: bool = xi < xs.size() - 1 and wet[zi][xi]
			if here and start < 0: start = xi
			if not here and start >= 0:
				var x0 := float(xs[start]) / 100.0
				var x1 := float(xs[xi]) / 100.0
				var z0 := float(zs[zi]) / 100.0
				var z1 := float(zs[zi + 1]) / 100.0
				_water_quad(shape, [Vector3(x0, 0, z0), Vector3(x1, 0, z0), Vector3(x1, 0, z1), Vector3(x0, 0, z1)], Vector3.UP)
				faces += 1
				start = -1
	# Sides only where water meets something else, merged along each grid line.
	for along_x: bool in [true, false]:
		var lines: Array = zs if along_x else xs
		var cells: Array = xs if along_x else zs
		for line in range(lines.size()):
			var start := 0
			var facing := 0
			for cell in range(cells.size()):
				var side := 0
				if cell < cells.size() - 1:
					var before: bool = line > 0 and (wet[line - 1][cell] if along_x else wet[cell][line - 1])
					var after: bool = line < lines.size() - 1 and (wet[line][cell] if along_x else wet[cell][line])
					side = 1 if before and not after else -1 if after and not before else 0
				if side == facing: continue
				if facing != 0:
					var at := float(lines[line]) / 100.0
					var a := float(cells[start]) / 100.0
					var b := float(cells[cell]) / 100.0
					if along_x: _water_quad(shape, [Vector3(a, -1, at), Vector3(b, -1, at), Vector3(b, 0, at), Vector3(a, 0, at)], Vector3(0, 0, facing))
					else: _water_quad(shape, [Vector3(at, -1, a), Vector3(at, -1, b), Vector3(at, 0, b), Vector3(at, 0, a)], Vector3(facing, 0, 0))
					faces += 1
				start = cell
				facing = side
	var root := Node3D.new()
	root.name = name
	terrain.add_child(root)
	if faces > 0:
		var surface := Primitives.fresh_material(color, 0.35)
		# Labels, faded floors and the spout draw over the water, never under it.
		surface.render_priority = -2
		var water := Primitives.mesh_node(shape.commit(), surface, Vector3.ZERO, root)
		water.name = "Water"
		water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_water_entry(root, level)
	return root

## One flat quad of water, its corners in order round it, wound to face along
## `normal` (Godot draws a triangle a, b, c whose (a - c) x (a - b) faces the eye).
static func _water_quad(shape: SurfaceTool, corners: Array, normal: Vector3) -> void:
	var a: Vector3 = corners[0]
	var b: Vector3 = corners[1]
	var c: Vector3 = corners[2]
	if (a - c).cross(a - b).dot(normal) < 0.0: corners.reverse()
	for index: int in [0, 1, 2, 0, 2, 3]:
		shape.set_normal(normal)
		shape.add_vertex(corners[index])

## Whether a point lies in one of `regions`, edges included.
static func _covered(x: float, z: float, regions: Array) -> bool:
	for region: Array in regions:
		if x >= region[0] and x <= region[2] and z >= region[1] and z <= region[3]: return true
	return false

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
	if root == _water.get("harbour"): _float_boats(level)
	for mast: Dictionary in _kept_masts:
		if root == _water.get(mast.body): _raise_mast(mast, level)

## Keeps a kept crossing's pennant MAST_CLEARANCE above the water at `level`.
func _raise_mast(mast: Dictionary, level: float) -> void:
	if not is_instance_valid(mast.post): return
	var lift := maxf(0.0, level + MAST_CLEARANCE - (float(mast.deck) + 0.50))
	var post: MeshInstance3D = mast.post
	post.scale.y = (0.50 + lift) / 0.50
	post.position.y = (0.50 + lift) * 0.5
	(mast.knob as Node3D).position.y = 0.52 + lift
	(mast.flag as Node3D).position.y = 0.38 + lift

## Every height each body of water can stand at in the shown stage: each value
## of the wheel that moves it, or where it rests while no wheel does. The
## scenery lint sweeps them all.
func water_levels() -> Dictionary:
	var levels := {"harbour": {"low": HARBOUR_LEVELS.low}, "sea": {"shut": SEA_LEVELS.shut}, "chamber": {"half": HARBOUR_LEVELS.half}}
	for control: Dictionary in current_level.get("controls", []):
		match str(control.get("id", "")):
			"tide": levels.harbour = HARBOUR_LEVELS
			"basin": levels.sea = SEA_LEVELS
			"chamber": levels.chamber = HARBOUR_LEVELS
	return levels

func _set_water(name: String, level: float, immediate: bool) -> void:
	var root: Node3D = _water.get(name)
	if not is_instance_valid(root): return
	root.set_meta("target", level)
	if immediate or reduced_motion: _show_water(root, level)

func _advance_water(delta: float) -> void:
	_clock += maxf(delta, 0.0)
	for root: Node3D in _water.values():
		if not is_instance_valid(root): continue
		var target := float(root.get_meta("target"))
		var shown := float(root.get_meta("shown"))
		if not is_equal_approx(shown, target): _show_water(root, move_toward(shown, target, WATER_RATE * maxf(delta, 0.0)))
	if not reduced_motion:
		var harbour: Node3D = _water.get("harbour")
		if is_instance_valid(harbour): _float_boats(float(harbour.get_meta("shown")))
		# Pale streaks run down the falling water.
		if is_instance_valid(_spout) and _spout.visible:
			for streak: MeshInstance3D in _spout_streaks:
				var span := float(streak.get_meta("span"))
				var phase := fmod(_clock * 0.9 + float(streak.get_meta("phase")), 1.0)
				streak.position.y = float(streak.get_meta("top")) - phase * span

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
			# The leaf stops 2 cm under high water, inside its cap.
			box(Vector3(span - 0.02, 1.28, 0.08), TIMBER, Vector3(-side * (span * 0.5), SEABED + 0.74, 0), hinge)
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
		cylinder(0.035, top - SEABED, TIMBER.darkened(0.1), at + Vector3(0, (top + SEABED) * 0.5, 0), terrain)
		for band in range(TIDE_VALUES.find(value) + 1):
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
			if str(island.id) not in AQUEDUCT: continue
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

## Rowboats moored in the channels ride the harbour level (and bob unless
## motion is reduced): a second cue for the tide.
func _build_boats() -> void:
	for spec: Array in BOATS:
		var boat := Node3D.new()
		boat.name = "MooredBoat"
		boat.position = point([spec[0], spec[1]])
		boat.rotation.y = float(spec[2])
		boat.set_meta("phase", float(spec[0]) * 0.013)
		terrain.add_child(boat)
		box(Vector3(0.40, 0.14, 0.92), TIMBER.lightened(0.10), Vector3(0, 0.05, 0), boat)
		box(Vector3(0.32, 0.06, 0.82), TIMBER.darkened(0.25), Vector3(0, 0.10, 0), boat)
		box(Vector3(0.24, 0.10, 0.20), TIMBER.lightened(0.10), Vector3(0, 0.06, 0.48), boat)
		for z: float in [-0.18, 0.18]: box(Vector3(0.38, 0.03, 0.08), TIMBER.lightened(0.20), Vector3(0, 0.13, z), boat)
		cylinder(0.035, PARAPET_TOP + 0.12 - SEABED, PILE, Vector3(float(spec[0]) / 100.0 + 0.32, (PARAPET_TOP + 0.12 + SEABED) * 0.5, float(spec[1]) / 100.0 - 0.36), terrain).name = "MooringPile"
		_boats.append(boat)

func _float_boats(level: float) -> void:
	for boat: Node3D in _boats:
		if not is_instance_valid(boat): continue
		var bob := 0.0 if reduced_motion else sin(_clock * 1.4 + float(boat.get_meta("phase"))) * 0.018
		boat.position.y = level - 0.02 + bob

## Warm pools of light under the bank lamps, and bunting strung along the banks.
func _build_lamplight() -> void:
	var bunting := [Color("e9a3a0"), Color("f1c27d"), Color("91d6c6"), Color("f4ecd0")]
	for spec: Array in LAMPS:
		var foot := point([spec[0], spec[1]]) + Vector3(0, 1.09, 0)
		var pool := cylinder(0.62, 0.006, Color(1.0, 0.82, 0.5, 0.30), foot + Vector3(0, 0.005, 0), terrain)
		pool.name = "LampPool"
		(pool.material_override as StandardMaterial3D).shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var from := foot + Vector3(0, 1.30, 0)
		var to := point([spec[2], spec[3]]) + Vector3(0, 1.09 + 0.95, 0)
		cylinder(0.025, 0.95, TIMBER.darkened(0.2), point([spec[2], spec[3]]) + Vector3(0, 1.09 + 0.475, 0), terrain)
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
		var t := float(chosen) / float(maxi(wheel.values.size() - 1, 1))
		wheel.wheel.rotation.z = _wheel_angle(chosen, wheel.values.size())
		wheel.wheel.set_meta("value", str(controls.get(id, "")))
		if _physical_levers.has(id): _physical_levers[id].rotation.z = lerpf(0.60, -0.60, t)
	_follow_knobs()
	_set_water("harbour", float(HARBOUR_LEVELS.get(tide, HARBOUR_LEVELS.low)), immediate)
	_set_water("sea", float(SEA_LEVELS.get(basin, SEA_LEVELS.shut)), immediate)
	_set_water("chamber", float(HARBOUR_LEVELS.get(str(controls.get("chamber", "half")), HARBOUR_LEVELS.half)), immediate)
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
	for id: String in _ghosts:
		if is_instance_valid(_ghosts[id]) and _decks.has(id): _ghosts[id].visible = not _decks[id].visible
	for id: String in _floods:
		var shown: bool = _decks[id].visible if _decks.has(id) else bool(routes.get(id, false))
		_floods[id].visible = not shown
	if is_instance_valid(_bell) and bool(state.get("complete", false)): _glow(_bell, LIGHT_COLOR, 1.6)

func _lamp(lamp: MeshInstance3D, color: Color, lit: bool) -> void:
	(lamp.material_override as StandardMaterial3D).albedo_color = color if lit else Color("4a4038")
	_glow(lamp, color, 1.2 if lit else 0.0)
	lamp.set_meta("lit", lit)

func _advance_camera(delta: float) -> void:
	_advance_water(delta)
	super._advance_camera(delta)

func _frame_camera() -> void:
	super._frame_camera()
	_clear_scenery()

## The shared placement (journey_world) sees this frame's scenery marks.
func _lift_bubbles() -> void:
	_mark_scenery()
	super._lift_bubbles()
	_bubbles_placed = true

# --- Static fold (kit/static_batch.gd, island_world._fold_static_scenery) ---

## Set once the stage's bubbles have been placed: the fold waits for it.
var _bubbles_placed := false

## Only stone, sand and timber that never change fold: nothing a variable
## here names, and nothing anywhere under one. Decks are rebuilt and copied
## for their ghosts at build; water, floods, ghosts, kept marks and masts,
## boats, sea gates, the spout, wheels, gauges, levers and lamps move, show,
## hide or glow with the tide; the remembered routes are found by index.
func _fold_inside_held() -> bool:
	return false

func _folds_static_scenery() -> bool:
	return _bubbles_placed and super._folds_static_scenery()

func _static_keep() -> Array:
	var keep := super._static_keep()
	for group: Dictionary in [_decks, _memory_markers, _ghosts, _floods, _water]: keep.append_array(group.values())
	for mast: Dictionary in _kept_masts: keep.append_array([mast.post, mast.knob, mast.flag])
	for wheel: Dictionary in _wheels.values(): keep.append(wheel.wheel)
	for gauge: Dictionary in _gauges.values(): keep.append_array([gauge.post, gauge.icon] + gauge.bands)
	for lamp: Dictionary in _lever_lamps.values(): keep.append(lamp.lamp)
	keep.append_array(_mouth_lamps.values())
	keep.append_array(_chamber_lamps)
	keep.append_array(_sea_gates)
	keep.append_array(_boats)
	keep.append_array(_spout_streaks)
	keep.append_array(_slack_marks)
	for marks: Array in _dry_marks.values(): keep.append_array(marks)
	for mark: Dictionary in _post_marks.values(): keep.append_array(mark.get("bands", []))
	keep.append_array(_physical_levers.values())
	keep.append_array([_spout, _remembered])
	return keep.filter(func(node: Variant) -> bool: return node is Node and is_instance_valid(node))

## The shared placement's scenery rule (journey_world._scenery_need), counted
## in every place it tries for a bubble, straight up or leaning aside: how much
## further a bubble at `rect` climbs to leave every gauge's head, hand wheel,
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
## waves and bands, any hand wheel, another lever's knob or a pad) and the
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
		if not is_instance_valid(bubble): continue
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
## with the control each belongs to: every gauge's head, every hand wheel, every
## lever's knob and every pad.
func _mark_scenery() -> void:
	_scenery_mark_count = 0
	for id: String in _gauges: _add_mark(_gauge_head(_gauges[id]), "")
	for id: String in _wheels:
		var hub := LabelBubble.plane_point((_wheels[id].wheel as Node3D).global_position)
		var reach := Vector2(0.36, 0.36 * LabelBubble.screen_up().y)
		_add_mark(Rect2(hub - reach, reach * 2.0), "")
	for id: String in _physical_levers:
		var knob := LabelBubble.plane_point((_physical_levers[id] as Node3D).global_transform * Vector3(0, 0.4, 0))
		_add_mark(Rect2(knob - Vector2.ONE * 0.09, Vector2.ONE * 0.18), id)
	for id: String in _physical_pads:
		var pad := _physical_pads[id] as MeshInstance3D
		var radius: float = (pad.mesh as TorusMesh).outer_radius if pad.mesh is TorusMesh else 0.2
		var at := LabelBubble.plane_point(pad.global_position)
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
	if not _completion_view and actors.has(_active_player):
		var at: Vector3 = actors[_active_player].position
		target.x = clampf(at.x, CAMERA_X.x, CAMERA_X.y)
		target.z = clampf(at.z, CAMERA_Z.x, CAMERA_Z.y)
	return target
