extends SceneTree
## The level checker's view half: every stage of every chapter laid out as
## floors and crossings, built as its world on an 800x360 view (a phone held
## sideways), with a pip standing at each control, lever, pad and goal in turn
## (tests/level_tools/stage_shots.gd), the camera framed by the world's own
## follow rule and the bubbles placed by its own placement. A failure names
## the chapter, the stage, the spot and what went wrong:
##  - the spot itself lies outside the view (or within EDGE_PX of its edge);
##  - a selector's own bubble is cut off by the view's edge while its pip
##    stands at it;
##  - two bubbles on the view overlap;
##  - a refusal with no cause shown: an end of an owned crossing with no owner
##    gate, a stair that can be closed with neither its chain nor the world's
##    own drawing of it (a folding stair, water: the world's skip(), with why),
##    or a stretch of an owned zone's edge with no rope
##    (presentation/kit/route_barriers.gd). A gap, a folded piece and water
##    are the world's own; everything else is a barrier;
##  - a pip inside a wall: every spot a pip can stand (the engine's own
##    Navigation.at, its walk radius, every crossing open), near each floor's
##    edge, keeps the drawn pip (its half-width, kit/walk_reach.gd) out of
##    every wall that stands up beside it (the water kit's walls, each floor's
##    walls down to the water);
##  - a pip over the edge: at every such spot (every world), drawn ground
##    carries the drawn pip all round, its half-width out from its centre:
##    the drawn tops (meshes, read as triangles) stand at the floor's height
##    there, or the pip leans over another floor (a ledge);
##  - a wall that holds nothing: a wall standing up over a floor's edge faces
##    water that can rise over that floor (else it is a fender);
##  - water short of its stone: at every level each body stands at, every
##    edge of its surface lies within EDGE_MEET (CORNER_MEET by a corner) of
##    the inside of what holds it
##    there (a water wall, a lock's stones, a floor's slab or its wall down to
##    the water), meets another body or leaves the block's window, so no strip
##    of bare bed shows between the water and the stone;
##  - a boat that leaks: every boat on a water world floats by the float rule
##    (kit/floats.gd), its keel in the water and its inside floor over it at
##    every level its water stands at and all through its bob, and no boat
##    prop stands over water unfloated;
##  - a stone that vanishes or changes size: a stepping stone that is down
##    (shut, or pushed under by a drowning) stays in view just under its water,
##    or stands tall over its open height while its water has fallen away
##    (journey stage_catalog.gd left_high), a pip on it riding up; a drowning
##    on it shows the shared drown and a fall off it the shared fall
##    (kit/drowning.gd);
##  - a piece that stretches with the water: with every body at its lowest,
##    middle and highest level, every mesh but the water's own (WATER_SIZES)
##    keeps its scale and its mesh's size, so whatever must reach the water or
##    stand over it is built once at a size that holds for every level and only
##    moves or shows (water: fixed-size pieces, never stretched);
##  - a stone whose foot shows: every stepping stone is built once from its
##    top down to STONE_FOOT under its water's bed, even at the highest it
##    stands (STONE_TALL over its open height), so the bed always hides its
##    foot and the water only covers more or less of it.
## KNOWN lists what fails on purpose, by the start of its message, with why;
## an entry that stops failing fails the suite. The definitions-only half is
## tests/test_level_checker.gd.
const Registry = preload("res://services/chapter_registry.gd")
const Stages = preload("res://tests/level_tools/level_stages.gd")
const Shots = preload("res://tests/level_tools/stage_shots.gd")
const LabelBubble = preload("res://presentation/kit/label_bubble.gd")
const RouteBarriers = preload("res://presentation/kit/route_barriers.gd")
const LevelGraph = preload("res://tests/level_graph.gd")
const FoldPresent = preload("res://tests/test_fold_present.gd")
const Navigation = preload("res://core/cooperative/navigation.gd")
const WaterBodies = preload("res://presentation/kit/water_bodies.gd")
const WaterLook = preload("res://presentation/kit/water_look.gd")
const WaterWorld = preload("res://presentation/water_world.gd")
const JourneyCatalog = preload("res://core/journey/stage_catalog.gd")
const Runtime = preload("res://core/physical/runtime.gd")
const WalkReach = preload("res://presentation/kit/walk_reach.gd")
## The engine's walk radius and the drawn pip's half-width (cm).
const WALK_RADIUS := Runtime.PLAYER_RADIUS
const PIP_HALF := WalkReach.PIP_HALF_CM
## Drawn ground is looked for this many ways round a spot, this far (cm) short
## of the drawn pip's half-width, within this much (m) of the floor's height
## there (a stair's steps stand round its slope).
const COVER_WAYS := 12
## What may change size with the water, by node name (or name start): only
## the water and its effects. Everything else is built once and only moves.
const WATER_SIZES := {
	"Water": "a body's surface (kit/water_bodies.gd), stretched from its bed to its level",
	"FloodedStub_": "a walled stub's flood (kit/water_bodies.gd), filled to its water's level",
	"SpillSheet": "the water falling over a spillway (kit/water_locks.gd), as long as the drop",
	"FallsSpray": "the mist where a pour lands (kit/water_locks.gd), spread by the drop",
	"DrownRing": "the ring a drowning spreads on the water (kit/drowning.gd)",
	"DrownBubble": "the bubbles a drowning raises (kit/drowning.gd)",
}
const COVER_SHORT := 3.0
const COVER_SLACK := 0.08
## Drawn ground this near (cm) carries the pip too: the seam between two boards.
const COVER_SEAM := 2.0
## Spots for the ground check lie this far in from an edge at most, this far
## apart (cm), and the drawn tops are sorted into cells this wide (m).
const COVER_BAND := 16
const COVER_STEP := 12
const COVER_CELL := 0.25
## A wall may touch a walk circle by this much (cm: a coping's 2.5 cm lip
## over the edge), and counts only while it stands this far (m) over the
## pip's floor and starts under its head.
const WALL_TOUCH := 3.0
const WALL_OVER := 0.06
const PIP_TALL := 0.85
## A wall standing this far (m) over a floor beside it is a wall, not a fender.
const WALL_UP := 0.30
## A water edge meets what holds it within this much (m) any way round: a
## wall stops 0.6 cm short of each end of its run, so two runs meeting in line
## leave a 1.2 cm joint. By a corner of the water, where two walls' trimmed
## ends and the inset meet, within CORNER_MEET along the edge's normal. Its
## edges are read WATER_EDGE_STEP apart (m).
const EDGE_MEET := 0.0065
const CORNER_MEET := 0.016
const WATER_EDGE_STEP := 0.04
## How far in from a floor's edge (cm) spots are tried, and how far apart.
const EDGE_BAND := 24
const EDGE_STEP := 4
const Floats = preload("res://presentation/kit/floats.gd")
const Props = preload("res://presentation/kit/props.gd")
const Models = preload("res://presentation/kit/models.gd")
## Bob phases tried round a boat's full heave.
const BOB_STEPS := 16
const VIEW := Vector2i(800, 360)
## A spot this close to the view's edge (px) counts as outside it.
const EDGE_PX := 16.0
## Bubbles overlapping by less than this (px squared) only touch.
const OVERLAP_PX2 := 16.0
## Known failures, matched by the start of the failure id: {prefix: why}.
## The pip reach checks (kit/walk_reach.gd) name a chapter (every version)
## and a surface: where a neighbour or a piece leaves a side short.
const KNOWN := {
	"conservatory mirror-room": "a neighbour 32 cm off (the gallery): the gap between them stays readable (WalkReach KEEP_GAP_CM), so this side reaches only part of the way",
	"conservatory recovery-stair": "a neighbour 16 cm off (the room return): the gap between them stays readable (WalkReach KEEP_GAP_CM), so this side reaches only part of the way",
	"conservatory room-return": "a neighbour 16 cm off (the recovery stair): the gap between them stays readable (WalkReach KEEP_GAP_CM), so this side reaches only part of the way",
	"fog-marsh bank": "its corner by stepping stones: the open water round the stones' mouth stays open a reach either side of them (WalkReach open), walled at the floor's edge",
	"fog-marsh jetty": "its edge by the raft's stop: a floor never reaches under a platform's stop (WalkReach), the raft moves off it",
	"fog-marsh lift-low": "the lift runs up the stilts' face, so a pip on the car stands against that wall",
	"fog-marsh middle": "its corner by stepping stones: the open water round the stones' mouth stays open a reach either side of them (WalkReach open), walled at the floor's edge",
	"fog-marsh path": "its corner by stepping stones: the open water round the stones' mouth stays open a reach either side of them (WalkReach open), walled at the floor's edge",
	"fog-marsh reed-stones": "an open deck by design: stones, rungs or a ride with water or air between them, drawn wider (kit/walk_reach.gd) but never a solid floor",
	"fog-marsh reeds": "its corner by stepping stones: the open water round the stones' mouth stays open a reach either side of them (WalkReach open), walled at the floor's edge",
	"fog-marsh rope-ladder": "an open deck by design: stones, rungs or a ride with water or air between them, drawn wider (kit/walk_reach.gd) but never a solid floor",
	"fog-marsh stilts": "its corner by the rope ladder: the ladder's rungs are an open deck",
	"fog-marsh swirl-stones": "an open deck by design: stones, rungs or a ride with water or air between them, drawn wider (kit/walk_reach.gd) but never a solid floor",
	"high-and-low lower-causeway": "a neighbour 48 cm off (the blue stair): the gap between them stays readable (WalkReach KEEP_GAP_CM), so this side reaches only part of the way",
	"long-way-home near-crossing": "a neighbour 48 cm off its corner (the garden arch): the gap between them stays readable (WalkReach KEEP_GAP_CM), so this side reaches only 14 cm",
	"long-way-home porch-door": "a neighbour 48 cm off its corner (the garden door): the gap between them stays readable (WalkReach KEEP_GAP_CM), so this side reaches only 14 cm",
	"long-way-home recovery-stair": "the garden meets the stair along its run, so that side keeps its walkable edge",
	"relay-isles relay-east": "its @3 rope bridge sags between its ends: an open deck by design: stones, rungs or a ride with water or air between them, drawn wider (kit/walk_reach.gd) but never a solid floor",
	"the-falls beach": "its corner by stepping stones: the open water round the stones' mouth stays open a reach either side of them (WalkReach open), walled at the floor's edge",
	"the-falls down-to-lookout": "the lock wall stands where the pools meet, placed by the water block",
	"the-falls isle": "its corner by stepping stones: the open water round the stones' mouth stays open a reach either side of them (WalkReach open), walled at the floor's edge",
	"the-falls loft": "its edge by the mill wheel ride, an open deck",
	"the-falls look": "its corner by stepping stones: the open water round the stones' mouth stays open a reach either side of them (WalkReach open), walled at the floor's edge",
	"the-falls rock": "its corner by stepping stones: the open water round the stones' mouth stays open a reach either side of them (WalkReach open), walled at the floor's edge",
	"the-falls rope-bridge": "a rope bridge sags between its ends: an open deck by design: stones, rungs or a ride with water or air between them, drawn wider (kit/walk_reach.gd) but never a solid floor",
	"the-falls rope-span": "a rope bridge sags between its ends: an open deck by design: stones, rungs or a ride with water or air between them, drawn wider (kit/walk_reach.gd) but never a solid floor",
	"the-falls s1": "an open deck by design: stones, rungs or a ride with water or air between them, drawn wider (kit/walk_reach.gd) but never a solid floor",
	"the-falls s2": "an open deck by design: stones, rungs or a ride with water or air between them, drawn wider (kit/walk_reach.gd) but never a solid floor",
	"the-falls s3": "an open deck by design: stones, rungs or a ride with water or air between them, drawn wider (kit/walk_reach.gd) but never a solid floor",
	"the-falls s4": "an open deck by design: stones, rungs or a ride with water or air between them, drawn wider (kit/walk_reach.gd) but never a solid floor",
	"the-falls stones": "an open deck by design: stones, rungs or a ride with water or air between them, drawn wider (kit/walk_reach.gd) but never a solid floor",
	"the-falls west-ladder": "the ladder climbs the top tier's face, so a pip near its top stands against that wall",
	"the-falls wheel": "an open deck by design: stones, rungs or a ride with water or air between them, drawn wider (kit/walk_reach.gd) but never a solid floor",
	"the-wishing-well cliff": "its corner by the well ladder, 8 cm off: the gap stays readable",
	"the-wishing-well tower": "its corner by the well ladder's top: the rungs are an open deck",
	"the-wishing-well well-ladder": "an open deck by design: stones, rungs or a ride with water or air between them, drawn wider (kit/walk_reach.gd) but never a solid floor",
	"turn-of-the-tide aq-feeder": "a neighbour 48 cm off (the towpath) and the lock wall under the aqueduct: the gap between them stays readable (WalkReach KEEP_GAP_CM), so this side reaches only part of the way",
	"turn-of-the-tide aq-span": "a neighbour 32 cm off (the boathouse steps) and the lock wall under the aqueduct: the gap between them stays readable (WalkReach KEEP_GAP_CM), so this side reaches only part of the way",
	"turn-of-the-tide bar-catwalk": "a neighbour 16 cm off (the next catwalk post): the gap between them stays readable (WalkReach KEEP_GAP_CM), so this side reaches only part of the way",
	"turn-of-the-tide boom-post": "a neighbour 16 cm off (the west steps): the gap between them stays readable (WalkReach KEEP_GAP_CM), so this side reaches only part of the way",
	"turn-of-the-tide e-terrace-east": "its corner by stepping stones: the open water round the stones' mouth stays open a reach either side of them (WalkReach open), walled at the floor's edge",
	"turn-of-the-tide e-terrace-west": "its corner by stepping stones: the open water round the stones' mouth stays open a reach either side of them (WalkReach open), walled at the floor's edge",
	"turn-of-the-tide gate-catwalk": "a neighbour 16 cm off (the next catwalk post): the gap between them stays readable (WalkReach KEEP_GAP_CM), so this side reaches only part of the way",
	"turn-of-the-tide gate-post": "a neighbour 16 cm off (the next catwalk post or the west steps): the gap between them stays readable (WalkReach KEEP_GAP_CM), so this side reaches only part of the way",
	"turn-of-the-tide m-terrace": "its corner by stepping stones: the open water round the stones' mouth stays open a reach either side of them (WalkReach open), walled at the floor's edge",
	"turn-of-the-tide mill-ladder": "a neighbour 48 cm off (the race stage): the gap between them stays readable (WalkReach KEEP_GAP_CM), so this side reaches only part of the way",
	"turn-of-the-tide punt-post": "a neighbour 16 cm off (the next catwalk post): the gap between them stays readable (WalkReach KEEP_GAP_CM), so this side reaches only part of the way",
	"turn-of-the-tide r-terrace": "its corner by stepping stones: the open water round the stones' mouth stays open a reach either side of them (WalkReach open), walled at the floor's edge",
	"turn-of-the-tide race-stage": "a neighbour 32 cm off (the mill quay) and 48 cm (the mill ladder): the gap between them stays readable (WalkReach KEEP_GAP_CM), so this side reaches only part of the way",
	"turn-of-the-tide e-beach water edge": "at low water, a few cm where its parapet's foot ends by the harbour's south sea wall, under the parapet's coping",
	"turn-of-the-tide m-beach water edge": "at low water, a few cm where its parapet's foot ends by the harbour's south sea wall, under the parapet's coping",
	"turn-of-the-tide sea-chamber": "the chamber's walls stand where the water block puts them, 15 cm past its floor",
	"turn-of-the-tide stones-1": "an open deck by design: stones, rungs or a ride with water or air between them, drawn wider (kit/walk_reach.gd) but never a solid floor",
	"turn-of-the-tide stones-2": "an open deck by design: stones, rungs or a ride with water or air between them, drawn wider (kit/walk_reach.gd) but never a solid floor",
	"turn-of-the-tide stones-3": "an open deck by design: stones, rungs or a ride with water or air between them, drawn wider (kit/walk_reach.gd) but never a solid floor",
	"turn-of-the-tide towpath": "a neighbour 48 cm off (the aqueduct feeder): the gap between them stays readable (WalkReach KEEP_GAP_CM), so this side reaches only part of the way",
	"turn-of-the-tide w-beach": "its corner by the west steps, whose side keeps its edge (a catwalk post 16 cm off)",
	"turn-of-the-tide w-steps-high": "a neighbour 16 cm off (the gate post): the gap between them stays readable (WalkReach KEEP_GAP_CM), so this side reaches only part of the way",
	"turn-of-the-tide w-steps-low": "a neighbour 16 cm off (the boom post): the gap between them stays readable (WalkReach KEEP_GAP_CM), so this side reaches only part of the way",
	"turn-of-the-tide w-terrace": "its corner by the west steps, whose side keeps its edge (a catwalk post 16 cm off)",
}
var checks := 0
var failures := 0
var _found: Dictionary = {}
var _spots := 0
var _bubbles_seen := 0
## Spots off the view while the pip stands at its start: proof the framing
## check can fail at all.
var _off_view := 0
## Selector bubbles cut by the view's edge while the pips stand at their
## starts: proof the bubble check can fail at all.
var _cut_from_start := 0
## Refusals a world with no barriers would leave unexplained: proof the
## barrier check can fail at all.
var _unshown := 0
var _refusals_seen := 0
## Wall checks made (walk spots against walls) and walls beside floors seen:
## proof the wall checks ran on the water worlds.
var _wall_spots := 0
var _walls_by_floors := 0
## Spots the ground check stood a pip at, and ones it found over the edge.
var _cover_spots := 0
var _cover_short := 0
## Boats and stepping stones checked on the water worlds.
var _boats_seen := 0
var _stones_seen := 0
## Rolled decks checked (kit/pieces/bridge_roll.gd), shut and open.
var _rolls_seen := 0
## Meshes on the water worlds held to one size across the water's levels.
var _sized_seen := 0
var _stones_feet_seen := 0
## Water edge spots read against what holds them.
var _water_edges := 0
## The rowboat model's floorboards (its "inside" slot), read once.
var _rowboat_floor := NAN

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = VIEW
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(viewport)
	for key: String in _keys():
		var started := Time.get_ticks_msec()
		await _chapter(viewport, key)
		print("LEVEL VIEW: %s in %d ms" % [key, Time.get_ticks_msec() - started])
	var least: Dictionary = _least()
	_check(_spots > least.spots and _bubbles_seen > least.bubbles, "The view checks stand a pip at every spot (%d), with bubbles in view (%d)" % [_spots, _bubbles_seen])
	_check(_off_view > 0, "From the starts, some spots lie off the view, so the framing check can fail (%d)" % _off_view)
	if least.cut > 0: _check(_cut_from_start >= least.cut, "From the starts, some selector bubbles are cut by the view's edge, so the bubble check can fail (%d)" % _cut_from_start)
	if _runs_shared():
		_check(_meets(Rect2(0, 0, 60, 30), Rect2(50, 10, 60, 30)) and not _meets(Rect2(0, 0, 60, 30), Rect2(61, 0, 60, 30)), "Bubbles that share a corner overlap; bubbles side by side do not")
		_check(_refusals_seen > 50 and _unshown > 50, "Every refusal is checked for a shown cause (%d), and a world with no barriers leaves many unexplained, so the check can fail (%d)" % [_refusals_seen, _unshown])
	_check(_rolls_seen >= int(least.get("rolls", 0)), "Every held crossing's rolled deck is checked shut and open (%d)" % _rolls_seen)
	_check(_boats_seen >= least.boats and _stones_seen >= least.stones, "Every water world's boats float by the float rule (%d boats on stages) and its stepping stones go under, never away (%d)" % [_boats_seen, _stones_seen])
	_check(_sized_seen >= int(least.get("sized", 0)), "Every water world's pieces keep one size at every water level (%d meshes)" % _sized_seen)
	print("LEVEL VIEW: %d meshes held to one size across the water's levels" % _sized_seen)
	_check(_stones_feet_seen >= int(least.get("feet", 0)), "Every stepping stone stands built once, its foot under the bed (%d stones)" % _stones_feet_seen)
	_check(_cover_spots > least.cover, "The ground check stands pips at the edges of every world's floors (%d spots, %d over an edge)" % [_cover_spots, _cover_short])
	_check(_wall_spots >= least.wall_spots and _walls_by_floors >= least.walls, "The wall checks stand pips by the water worlds' walls (%d spots) and read the walls beside floors (%d)" % [_wall_spots, _walls_by_floors])
	_check(_water_edges >= int(least.get("water_edges", 0)), "The water edge check reads the water worlds' edges at every level (%d spots)" % _water_edges)
	for prefix: String in KNOWN:
		# Each suite answers for its own chapters' entries.
		if not _answers(prefix): continue
		_check(_found.has(prefix), "Known failure still fails, or comes off the list: %s (%s)" % [prefix, KNOWN[prefix]])
	print("LEVEL VIEW: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## The chapters this suite walks: every registered chapter (each family lays
## its stages out; the level checker fails one that does not); a split suite
## narrows it.
func _keys() -> Array[String]:
	return Registry.keys().filter(_runs)

## Whether this suite walks chapter `key`: every one not on the water here
## (test_level_view_tide walks the Tide's, test_level_view_falls The Falls',
## test_level_view_water the rest).
func _runs(key: String) -> bool:
	return not FoldPresent._on_water(key)

## Whether this suite answers for KNOWN entry `prefix`: by default, when it
## walks a version of the chapter the entry names.
func _answers(prefix: String) -> bool:
	return _keys().any(func(key: String) -> bool: return key.get_slice("@", 0) == prefix.get_slice(" ", 0))

## Whether this suite runs the checks no chapter owns (bubbles, refusals).
func _runs_shared() -> bool:
	return true

## The least this suite's chapters give each proof that its checks ran.
func _least() -> Dictionary:
	return {"spots": 100, "bubbles": 60, "cut": 0, "boats": 0, "stones": 0, "cover": 3000, "wall_spots": 0, "walls": 0, "rolls": 4}

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
		print("FAIL: " + message)

func _expect(ok: bool, id: String, message: String) -> void:
	if not ok:
		for prefix: String in KNOWN:
			if id.begins_with(prefix):
				_found[prefix] = true
				print("KNOWN: %s (%s)" % [message, KNOWN[prefix]])
				ok = true
				break
	_check(ok, message)

func _chapter(viewport: SubViewport, key: String) -> void:
	var level := Registry.definition(key)
	var world: Node3D = Registry.world_script(key).new()
	viewport.add_child(world)
	world.set_process(false)
	world.configure_camera_exploration(func() -> bool: return false, func(_point: Vector2) -> bool: return false)
	await world.load_level(level)
	for item: Dictionary in Stages.stages(key, level):
		var view: Dictionary = item.view
		var where := "%s %s" % [key, view.stage_id]
		_check(not item.checkpoint.is_empty(), "%s: the stage opens from a saved checkpoint" % where)
		if item.checkpoint.is_empty(): continue
		var ends := _route_ends(view)
		await world.show_stage(item.stage)
		world.present_history(item.opening)
		_walls(world, where, view)
		_meets_stone(world, where)
		_barriers(world, where, view, item.checkpoint, ends)
		var shots := Shots.new(key, level, str(view.stage_id), item.opening)
		var base := shots.snapshot()
		_check(not base.is_empty(), "%s: the engine opens the stage" % where)
		if base.is_empty(): continue
		_cover(world, where, view, base)
		_present(world, base)
		_floats(world, where)
		_current_marks(world, where, view)
		_stones(world, where, base)
		_rolls(world, where, view, base)
		_fixed_sizes(world, where, base)
		for spot: Dictionary in shots.spots():
			if not _inside(world, spot.entity): _off_view += 1
			if spot.kind == "selector" and "_journey_switches" in world and world._journey_switches.has(spot.id):
				var own: Rect2 = (world._journey_switches[spot.id].bubble as LabelBubble).screen_rect(world.camera)
				if not Rect2(Vector2.ZERO, Vector2(VIEW)).encloses(own): _cut_from_start += 1
		for spot: Dictionary in shots.spots():
			_present(world, shots.snapshot(shots.beside({}, spot.entity, spot.slot)))
			_look(world, where, spot)
			_spots += 1
	world.queue_free()
	await process_frame

## Shows `state` as the game's next frame would: an immediate present, then
## the placement pass it leaves due (what the world sets after it, its own
## levers and wheels, is read by the next pass).
static func _present(world: Node3D, state: Dictionary) -> void:
	world.present(state, true)
	world._frame_camera()

## Where the entity's floor point lands on the view (px).
static func _shown(world: Node3D, entity: Dictionary) -> Vector2:
	return world.camera.unproject_position(world.terrain.to_global(world._at(entity)))

static func _inside(world: Node3D, entity: Dictionary) -> bool:
	return Rect2(Vector2.ZERO, Vector2(VIEW)).grow(-EDGE_PX).has_point(_shown(world, entity))

func _look(world: Node3D, where: String, spot: Dictionary) -> void:
	var camera: Camera3D = world.camera
	var screen := Rect2(Vector2.ZERO, Vector2(VIEW))
	var label := "%s %s" % [spot.kind, spot.id]
	_expect(_inside(world, spot.entity), "%s %s framing" % [where, label], "%s: with its pip at the %s, it lies outside the view at %s px" % [where, label, _shown(world, spot.entity).round()])
	if not "_bubbles" in world: return
	var boxes: Array = []
	for bubble: Node in world._bubbles:
		if not is_instance_valid(bubble) or not (bubble as Node3D).is_visible_in_tree(): continue
		var box: Rect2 = (bubble as LabelBubble).screen_rect(camera)
		if box.has_area() and box.intersects(screen): boxes.append([bubble, box])
	_bubbles_seen += boxes.size()
	if spot.kind == "selector" and world._journey_switches.has(spot.id):
		var own: LabelBubble = world._journey_switches[spot.id].bubble
		var box := own.screen_rect(camera)
		_expect(box.has_area() and screen.encloses(box), "%s %s bubble cut" % [where, label], "%s: with its pip at the %s, its bubble is cut off by the view's edge at %s" % [where, label, _px(box)])
	for a in range(boxes.size()):
		for b in range(a + 1, boxes.size()):
			var meet: Rect2 = (boxes[a][1] as Rect2).intersection(boxes[b][1])
			_expect(not _meets(boxes[a][1], boxes[b][1]), "%s %s bubbles overlap" % [where, label], "%s: with a pip at the %s, the bubbles of %s and %s overlap (%s)" % [where, label, _name(world, boxes[a][0]), _name(world, boxes[b][0]), _px(meet)])

## Every refusal of the stage shows its cause in the built world (its route
## barriers' layout and the stairs it draws itself), and the same check finds
## them unexplained in a world that builds no barriers.
func _barriers(world: Node3D, where: String, view: Dictionary, checkpoint: Dictionary, ends: Dictionary) -> void:
	var kit: Variant = world.get("route_barriers")
	_check(kit != null, "%s: the world keeps route barriers" % where)
	if kit == null: return
	var kept: Array = checkpoint.get("mechanisms", {}).get("latched_bridges", [])
	_refusals_seen += _unexplained(where, view, kit.placed(), kit.skips(), kept, ends, true)
	for mouth: Dictionary in kit.placed().get("mouths", []):
		var clash: Array = mouth.get("clash", [])
		_expect(clash.is_empty(), "%s crossing %s posts" % [where, mouth.route], "%s: a post of the gate at the %s end of %s stands in %s" % [where, "%s" % mouth.get("floor", ""), mouth.route, ", ".join(clash)])
	_unshown += _unexplained(where, view, {"mouths": [], "spans": []}, {}, kept, ends, false)

## How many refusals of `view` show no cause with `placed` barriers and the
## world's `skips`; with `report`, each is a failure naming the chapter, the
## stage, the crossing or zone, and the pip refused.
func _unexplained(where: String, view: Dictionary, placed: Dictionary, skips: Dictionary, kept: Array, ends: Dictionary, report: bool) -> int:
	var floors := RouteBarriers.floors_of(view)
	var count := 0
	var seen := 0
	for kind: String in ["bridges", "stairs"]:
		for route: Dictionary in view.get(kind, []):
			var id := str(route.id)
			var owner := str(route.get("owner_slot", ""))
			var closes: bool = kind == "stairs" and id not in kept
			# The floors the engine lets a pip step to from this crossing, were
			# owners no rule (tests/level_graph.gd): each needs its cause shown.
			for end: String in ends.get(id, {}):
				var built: Array = placed.get("mouths", []).filter(func(found: Dictionary) -> bool: return found.route == id and str(found.get("floor", "")) == end)
				if not owner.is_empty():
					seen += 1
					var other := "p1" if owner == "p0" else "p0"
					var shown := built.any(func(found: Dictionary) -> bool: return found.owner == owner)
					if not shown: count += 1
					if report: _expect(shown, "%s crossing %s %s gate" % [where, id, end], "%s: the %s %s refuses %s at its end on %s and nothing there shows why (no owner gate)" % [where, kind.trim_suffix("s"), id, other, end])
				if closes:
					seen += 1
					var shown := skips.has(id) or built.any(func(found: Dictionary) -> bool: return bool(found.stair_gate))
					if not shown: count += 1
					if report: _expect(shown, "%s crossing %s %s chain" % [where, id, end], "%s: the stair %s, closed, refuses both pips at its end on %s and nothing there shows why (no chain, and the world draws nothing of its own)" % [where, id, end])
	for zone: Dictionary in view.get("access_zones", []):
		var owner := str(zone.get("owner_slot", ""))
		if owner.is_empty(): continue
		var other := "p1" if owner == "p0" else "p0"
		var wanted := RouteBarriers.zone_edges(zone, view, floors).size()
		var built: int = placed.get("spans", []).filter(func(found: Dictionary) -> bool: return found.zone == str(zone.get("id", ""))).size()
		seen += wanted
		if built < wanted: count += wanted - built
		if report: _expect(built >= wanted, "%s zone %s rope" % [where, zone.get("id", "")], "%s: the zone %s refuses %s along %d stretches of its edge and only %d show a rope" % [where, zone.get("id", ""), other, wanted, built])
	return seen if report else count

## Drawn ground carries the drawn pip all round at every spot a pip can stand
## near a floor's edge, every crossing open: round each spot, at the drawn
## pip's half-width (less COVER_SHORT), a drawn top stands at the floor's
## height there (within COVER_SLACK), or the pip leans over another walkable
## surface (a ledge, a crossing's end). Read from the world's own meshes.
func _cover(world: Node3D, where: String, view: Dictionary, base: Dictionary) -> void:
	var open := base.duplicate(true)
	for id: Variant in open.get("bridges", {}): open.bridges[id] = true
	world.present(open, true)
	var tops := _tops(world)
	var cells := Navigation.index_for(view, "level-view " + where)
	var routes: Dictionary = {}
	for route: Dictionary in view.get("bridges", []) + view.get("stairs", []): routes[str(route.id)] = true
	var surfaces: Array = view.get("islands", []) + view.get("bridges", []) + view.get("stairs", [])
	# A lift's or a raft's stops: its car or raft is drawn where the snapshot has it.
	var moving: Dictionary = {str(world.current_level.get("lift", {}).get("id", "")): true}
	for platform: Dictionary in view.get("platforms", []):
		for id: Variant in platform.get("stops", []): moving[str(id)] = true
	var short: Dictionary = {}
	for surface: Dictionary in surfaces:
		if moving.has(str(surface.id)): continue
		var r: Array = surface.rect_cm
		for x in range(int(r[0]), int(r[2]) + 1, COVER_STEP):
			for z in range(int(r[1]), int(r[3]) + 1, COVER_STEP):
				if mini(mini(x - int(r[0]), int(r[2]) - x), mini(z - int(r[1]), int(r[3]) - z)) > COVER_BAND: continue
				var start := Navigation.stair_height(surface, Vector2i(x, z)) if surface.has("axis") else int(surface.get("height_cm", 0))
				var at := Navigation.at(view, routes, {}, {"height": start}, x, z, "p0", WALK_RADIUS, false, cells)
				if at.is_empty() or str(at.surface_id) != str(surface.id): continue
				_cover_spots += 1
				for way in range(COVER_WAYS):
					var angle := TAU * float(way) / float(COVER_WAYS)
					var sample := Vector2(x, z) + Vector2(cos(angle), sin(angle)) * (float(PIP_HALF) - COVER_SHORT)
					if _carried(tops, surface, surfaces, sample): continue
					# By chapter (every version) and surface, whatever the stage: KNOWN names a surface once.
					var id := "%s %s cover" % [where.get_slice(" ", 0).get_slice("@", 0), surface.id]
					if not short.has(id): short[id] = [0, x, z, sample]
					short[id][0] += 1
					_cover_short += 1
					break
	for id: String in short:
		var found: Array = short[id]
		_expect(false, id, "%s %s: a pip standing at (%d, %d) hangs over the edge: no drawn ground under its side at (%.0f, %.0f) (%d spots)" % [where, id.get_slice(" ", 1), found[1], found[2], found[3].x, found[3].y, found[0]])
	world.present(base, true)

## Whether drawn ground carries a pip on `surface` at `sample` (cm): another
## walkable surface under it (a ledge, a crossing's end), or a drawn top there
## at the height of the surface, or of a neighbour reaching over to it, there.
func _carried(tops: Dictionary, surface: Dictionary, surfaces: Array, sample: Vector2) -> bool:
	var heights: Array = [[_height_near(surface, sample), _slack(surface)]]
	for other: Dictionary in surfaces:
		if other == surface: continue
		var o: Array = other.rect_cm
		if sample.x > float(o[0]) and sample.x < float(o[2]) and sample.y > float(o[1]) and sample.y < float(o[3]): return true
		var near := Rect2(float(o[0]), float(o[1]), float(o[2] - o[0]), float(o[3] - o[1])).grow(float(WalkReach.REACH_CM))
		if near.has_point(sample): heights.append([_height_near(other, sample), _slack(other)])
	# A plank's seam (a centimetre or so between boards) is not a gap.
	for nudge: Vector2 in [Vector2.ZERO, Vector2(COVER_SEAM, 0), Vector2(-COVER_SEAM, 0), Vector2(0, COVER_SEAM), Vector2(0, -COVER_SEAM)]:
		var at := (sample + nudge) / 100.0
		for triangle: PackedVector3Array in tops.get(Vector2i(floori(at.x / COVER_CELL), floori(at.y / COVER_CELL)), []):
			var y := _height_on(triangle, at)
			if is_nan(y): continue
			for height: Array in heights:
				if absf(y - float(height[0])) <= float(height[1]): return true
	return false

## How far (m) a drawn top may stand off a surface's height and still carry a
## pip: a stair's treads step a tenth of its rise round its slope.
static func _slack(surface: Dictionary) -> float:
	if not surface.has("axis"): return COVER_SLACK
	return COVER_SLACK + absf(float(surface.to_height_cm) - float(surface.from_height_cm)) / 1000.0

## `surface`'s height (m) at the point of it nearest `at` (cm).
static func _height_near(surface: Dictionary, at: Vector2) -> float:
	var r: Array = surface.rect_cm
	return WalkReach.height_at(surface, Vector2(clampf(at.x, float(r[0]), float(r[2])), clampf(at.y, float(r[1]), float(r[3])))) / 100.0

## The drawn tops of `world`: every upward face of its visible solid meshes
## under the terrain (terrain space, m), by the COVER_CELL cells they cross.
## Water, see-through and shader-drawn meshes (water, barriers, shadows) and
## the pips are left out.
func _tops(world: Node3D) -> Dictionary:
	var cells: Dictionary = {}
	var to_terrain: Transform3D = world.terrain.global_transform.affine_inverse()
	var skip: Array = []
	for actor: Variant in world.actors.values():
		if actor is Node3D: skip.append(actor)
	for node: Node in world.terrain.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null or not mesh.is_visible_in_tree() or str(mesh.name).begins_with("Water"): continue
		var material := mesh.material_override if mesh.material_override != null else mesh.mesh.surface_get_material(0)
		# A raised floor faded for a pip under it (kit/cutaway.gd) is still drawn ground.
		var see_through := material is BaseMaterial3D and ((material as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or (material as BaseMaterial3D).albedo_color.a < 1.0)
		if material is ShaderMaterial or (see_through and not mesh.get_meta("cutaway", false)): continue
		if skip.any(func(actor: Node3D) -> bool: return actor.is_ancestor_of(mesh)): continue
		var place := to_terrain * mesh.global_transform
		var faces := mesh.mesh.get_faces()
		for index in range(0, faces.size(), 3):
			var a := place * faces[index]
			var b := place * faces[index + 1]
			var c := place * faces[index + 2]
			if absf((b - a).cross(c - a).normalized().y) < 0.3: continue
			var low := Vector2(minf(a.x, minf(b.x, c.x)), minf(a.z, minf(b.z, c.z)))
			var high := Vector2(maxf(a.x, maxf(b.x, c.x)), maxf(a.z, maxf(b.z, c.z)))
			for cx in range(floori(low.x / COVER_CELL), floori(high.x / COVER_CELL) + 1):
				for cz in range(floori(low.y / COVER_CELL), floori(high.y / COVER_CELL) + 1):
					var key := Vector2i(cx, cz)
					if not cells.has(key): cells[key] = []
					cells[key].append(PackedVector3Array([a, b, c]))
	return cells

## The height of `triangle` over `at` (x, z), or NAN when it is not over it.
static func _height_on(triangle: PackedVector3Array, at: Vector2) -> float:
	var a := Vector2(triangle[0].x, triangle[0].z)
	var b := Vector2(triangle[1].x, triangle[1].z)
	var c := Vector2(triangle[2].x, triangle[2].z)
	var area := (b - a).cross(c - a)
	if absf(area) < 0.000001: return NAN
	var u := (c - b).cross(at - b) / area
	var v := (a - c).cross(at - c) / area
	var w := 1.0 - u - v
	if u < -0.0001 or v < -0.0001 or w < -0.0001: return NAN
	return u * triangle[0].y + v * triangle[1].y + w * triangle[2].y

## No pip stands inside a wall, and no wall stands over a floor's edge with
## nothing to hold: the water kit's walls (parapets, sea walls, crossing and
## lock walls) and each floor's walls down to the water, against every spot the
## engine lets a pip stand near a floor's edge.
func _walls(world: Node3D, where: String, view: Dictionary) -> void:
	var kit: Variant = world.get("waters")
	if kit == null or kit.water.is_empty(): return
	var walls: Array = []
	var to_terrain: Transform3D = world.terrain.global_transform.affine_inverse()
	for box: AABB in kit.walls: walls.append([box, "water wall", ""])
	# The locks' capped walls and spillway stones.
	for stones: Node in world.terrain.find_children("WaterLockStone", "", true, false):
		for piece: Node in stones.find_children("*", "MeshInstance3D", true, false):
			walls.append([to_terrain * (piece as MeshInstance3D).global_transform * (piece as MeshInstance3D).get_aabb(), "a lock wall", ""])
	for island: Dictionary in view.get("islands", []):
		# A floor drawn in pieces (kit/walk_reach.gd) has a wall under each.
		for wall: Node in world.terrain.find_children(str(island.id) + "Wall*", "MeshInstance3D", true, false):
			walls.append([to_terrain * (wall as MeshInstance3D).global_transform * (wall as MeshInstance3D).get_aabb(), "the wall of " + str(island.id), str(island.id)])
	var cells := Navigation.index_for(view, "level-view " + where)
	var routes: Dictionary = {}
	for route: Dictionary in view.get("bridges", []) + view.get("stairs", []): routes[str(route.id)] = true
	var worst: Dictionary = {}
	for surface: Dictionary in view.get("islands", []) + view.get("bridges", []) + view.get("stairs", []):
		var r: Array = surface.rect_cm
		var reach := Rect2(float(r[0]), float(r[1]), float(r[2] - r[0]), float(r[3] - r[1])).grow(float(PIP_HALF) + 1.0)
		var beside: Array = walls.filter(func(entry: Array) -> bool: return entry[2] != str(surface.id) and reach.intersects(Rect2((entry[0] as AABB).position.x * 100.0, (entry[0] as AABB).position.z * 100.0, (entry[0] as AABB).size.x * 100.0, (entry[0] as AABB).size.z * 100.0)))
		if beside.is_empty(): continue
		for x in range(int(r[0]), int(r[2]) + 1, EDGE_STEP):
			for z in range(int(r[1]), int(r[3]) + 1, EDGE_STEP):
				if mini(mini(x - int(r[0]), int(r[2]) - x), mini(z - int(r[1]), int(r[3]) - z)) > EDGE_BAND: continue
				var start := Navigation.stair_height(surface, Vector2i(x, z)) if surface.has("axis") else int(surface.get("height_cm", 0))
				var at := Navigation.at(view, routes, {}, {"height": start}, x, z, "p0", WALK_RADIUS, false, cells)
				if at.is_empty() or str(at.surface_id) != str(surface.id): continue
				_wall_spots += 1
				var feet := float(at.height) / 100.0
				for entry: Array in beside:
					var box: AABB = entry[0]
					if box.end.y <= feet + WALL_OVER or box.position.y >= feet + PIP_TALL: continue
					var near := Vector2(clampf(x, box.position.x * 100.0, box.end.x * 100.0), clampf(z, box.position.z * 100.0, box.end.z * 100.0))
					var into := float(PIP_HALF) - Vector2(x, z).distance_to(near)
					# By chapter (every version), surface and wall, whatever the stage (as KNOWN names it).
					var id := "%s %s in %s" % [where.get_slice(" ", 0).get_slice("@", 0), surface.id, entry[1]]
					if into > WALL_TOUCH and into > float(worst.get(id, [0.0])[0]): worst[id] = [into, x, z, box]
	for id: String in worst:
		_expect(false, id, "%s %s: a pip standing at (%d, %d) runs %.0f cm into a wall at %s (%s)" % [where, id.get_slice(" ", 1), worst[id][1], worst[id][2], worst[id][0], worst[id][3], id])
	# Each parapet that stands up over a floor's edge holds water that can rise over that floor.
	for parapet: Node in world.terrain.find_children("Parapet*", "MeshInstance3D", true, false):
		var box: AABB = to_terrain * (parapet as MeshInstance3D).global_transform * (parapet as MeshInstance3D).get_aabb()
		var centre := [box.get_center().x * 100.0, box.get_center().z * 100.0]
		var top := -INF
		for body: Dictionary in kit.open_bodies():
			if WaterBodies.covered(centre[0], centre[1], body.rects):
				for level: float in body.levels.values(): top = maxf(top, level)
		for island: Dictionary in view.get("islands", []):
			var r: Array = island.rect_cm
			var floor_top := float(island.get("height_cm", 0)) / 100.0
			if box.end.y < floor_top + WALL_UP: continue
			var flat := Rect2(box.position.x * 100.0, box.position.z * 100.0, box.size.x * 100.0, box.size.z * 100.0)
			if not flat.grow(3.0).intersects(Rect2(float(r[0]), float(r[1]), float(r[2] - r[0]), float(r[3] - r[1]))): continue
			_walls_by_floors += 1
			_expect(top > floor_top, "%s wall by %s" % [where, island.id], "%s: a wall stands %.2f m up beside %s, over water that never rises over that floor (its highest %.2f m): a fender, not a wall" % [where, box.end.y - floor_top, island.id, top])

## Every edge of each body's surface, at every level the body stands at,
## lies within EDGE_MEET (CORNER_MEET by a corner) of the inside of something
## solid at that height (the water kit's walls, the locks' stones, the meshes
## of each floor's deck: its slab, lips and wall down to the water), over
## another body's water, under a crossing's deck where it lands, or out of the
## block's window. Read on either side of the edge: water running under a wall
## to its far face meets it as surely as water stopping inside it. Water over
## a floor's height at its edge is the locks' doors' to hold.
func _meets_stone(world: Node3D, where: String) -> void:
	var kit: Variant = world.get("waters")
	if kit == null or kit.water.is_empty(): return
	var to_terrain: Transform3D = world.terrain.global_transform.affine_inverse()
	var solids: Array[AABB] = []
	solids.append_array(kit.walls)
	for holder: Node in world.terrain.find_children("WaterLockStone", "", true, false) + world.terrain.find_children("Deck_*", "Node3D", false, false):
		for piece: Node in holder.find_children("*", "MeshInstance3D", true, false):
			solids.append(to_terrain * (piece as MeshInstance3D).global_transform * (piece as MeshInstance3D).get_aabb())
	# Floors' tops: water standing over a floor at its edge is held there by
	# the locks' doors at the crossing's mouth (kit/water_locks.gd), not here.
	var decks: Array = []
	for holder: Node in world.terrain.find_children("Deck_*", "Node3D", false, false):
		# The floor's walking height, under every piece of it.
		var top := (holder as Node3D).position.y
		for piece: Node in holder.find_children("*", "MeshInstance3D", true, false):
			var box: AABB = to_terrain * (piece as MeshInstance3D).global_transform * (piece as MeshInstance3D).get_aabb()
			decks.append([Rect2(box.position.x, box.position.z, box.size.x, box.size.z).grow(0.0005), top, str(holder.name).trim_prefix("Deck_")])
	# Where a crossing lands on a floor its deck covers the water's edge.
	var landings: Array[Rect2] = []
	for route: Dictionary in world.chapter_definition.get("bridges", []) + world.chapter_definition.get("stairs", []):
		var r: Array = world.drawn_rect(route)
		landings.append(Rect2(float(r[0]) / 100.0, float(r[1]) / 100.0, float(r[2] - r[0]) / 100.0, float(r[3] - r[1]) / 100.0).grow(0.001))
	var wet: Dictionary = {}
	for id: String in kit.bodies:
		var sheet := (kit.bodies[id] as Node3D).get_node_or_null("Water") as MeshInstance3D
		wet[id] = WaterLook._wet_rects(sheet.mesh) if sheet != null and sheet.mesh != null else []
	var bounds: Array = kit.water.bounds
	var window := Rect2(float(bounds[0]) / 100.0, float(bounds[1]) / 100.0, float(bounds[2] - bounds[0]) / 100.0, float(bounds[3] - bounds[1]) / 100.0)
	var short: Dictionary = {}
	for id: String in wet:
		var others: Array[Rect2] = []
		for other: String in wet:
			if other != id: others.append_array(wet[other])
		for rect: Rect2 in wet[id]:
			for side in range(4):
				var along_x := side < 2
				var normal := Vector2(0, -1) if side == 0 else Vector2(0, 1) if side == 1 else Vector2(-1, 0) if side == 2 else Vector2(1, 0)
				var from := rect.position + (Vector2(0, rect.size.y) if side == 1 else Vector2(rect.size.x, 0) if side == 3 else Vector2.ZERO)
				var length := rect.size.x if along_x else rect.size.y
				# Only what lies near this side can hold it or skip a spot on it.
				var near := Rect2(from, Vector2(length, 0) if along_x else Vector2(0, length)).grow(CORNER_MEET + EDGE_MEET + 0.07)
				var near_solids := solids.filter(func(box: AABB) -> bool: return Rect2(box.position.x, box.position.z, box.size.x, box.size.z).intersects(near, true))
				var near_decks := decks.filter(func(deck: Array) -> bool: return (deck[0] as Rect2).intersects(near, true))
				var near_others := others.filter(func(other: Rect2) -> bool: return other.grow(0.001).intersects(near, true))
				var near_wet := (wet[id] as Array).filter(func(other: Rect2) -> bool: return other.intersects(near, true))
				var near_landings := landings.filter(func(landing: Rect2) -> bool: return landing.intersects(near, true))
				var t := WATER_EDGE_STEP * 0.5
				while t < length:
					var at := from + (Vector2(t, 0) if along_x else Vector2(0, t))
					var reach := CORNER_MEET if t < WATER_EDGE_STEP or t > length - WATER_EDGE_STEP else 0.0
					t += WATER_EDGE_STEP
					var past := at + normal * EDGE_MEET
					# Inside its own water: not an edge.
					if near_wet.any(func(other: Rect2) -> bool: return other.has_point(past)): continue
					if not window.grow(-0.001).has_point(past): continue
					if near_others.any(func(other: Rect2) -> bool: return other.grow(0.001).has_point(past)): continue
					if near_landings.any(func(landing: Rect2) -> bool: return landing.has_point(at)): continue
					for level: float in kit.levels_of(id).values():
						if near_decks.any(func(deck: Array) -> bool: return deck[1] < level and (deck[0] as Rect2).has_point(past)): continue
						_water_edges += 1
						var held := false
						# Along the line through the edge, from `reach` inside the water to
						# `reach` past it, half a reach at a time.
						for step in range(-2, 3):
							var spot := Vector3(at.x + normal.x * reach * step * 0.5, level, at.y + normal.y * reach * step * 0.5)
							if near_solids.any(func(box: AABB) -> bool: return box.grow(EDGE_MEET).has_point(spot)): held = true
						if held: continue
						var key := "%s %s %s" % [where, id, ["north", "south", "west", "east"][side]]
						if not short.has(key):
							# Named by the floor it stops short of, when it is a floor's edge, as KNOWN names it.
							var beside: Array = near_decks.filter(func(deck: Array) -> bool: return (deck[0] as Rect2).grow(0.06).has_point(past))
							short[key] = [0, at, level, "%s %s water edge" % [where.get_slice(" ", 0).get_slice("@", 0), beside[0][2] if not beside.is_empty() else id]]
						short[key][0] += 1
	for key: String in short:
		_expect(false, short[key][3], "%s: the water's edge stops short of what holds it at %d spots, e.g. (%.2f, %.2f) at level %.2f: bare bed shows between the water and the stone (%s)" % [key, short[key][0], short[key][1].x, short[key][1].y, short[key][2], short[key][3]])

## Every boat rides its water by the float rule at every level its water
## stands at and all through its bob: its keel in the water, its floorboards
## over it. No still boat prop stands over water.
func _floats(world: Node3D, where: String) -> void:
	var kit: Variant = world.get("waters")
	if kit == null or kit.water.is_empty(): return
	if is_nan(_rowboat_floor):
		var probe := Node3D.new()
		var model := Models.still(Props.ROWBOAT, "rowboat", Props.rowboat_colors(), probe, false)
		_rowboat_floor = (model.find_child("inside", false, false) as MeshInstance3D).get_aabb().end.y
		probe.free()
	for prop: Node in world.terrain.find_children("Prop_boat", "", true, false):
		var at: Vector3 = world.terrain.to_local((prop as Node3D).global_position) * 100.0
		var over: String = kit.body_of([at.x, at.z, at.x, at.z])
		var dry: bool = world.current_level.get("islands", []).any(func(island: Dictionary) -> bool: return WaterBodies._inside([at.x, at.z], island.rect_cm))
		_check(dry or over.is_empty(), "%s: a boat prop stands over the %s water at (%d, %d) without floating: the water world floats every boat" % [where, over, at.x, at.z])
	var spec: Dictionary = Floats.kind("rowboat")
	var reduced: bool = world.reduced_motion
	world.reduced_motion = false
	for boat: Node3D in world._boats:
		_boats_seen += 1
		var water := ""
		for rider: Array in kit._riders:
			if (rider[1] as Callable).get_bound_arguments().has(boat): water = str(rider[0])
		_check(not water.is_empty(), "%s: a boat at %s rides no water" % [where, boat.position])
		var hull := boat.find_child("rowboat", true, false) as Node3D
		var floor_at: float = (hull.transform * AABB(Vector3(0, _rowboat_floor, 0), Vector3.ZERO)).position.y if hull != null else 0.0
		var low := INF
		var high := -INF
		for level: float in kit.levels_of(water).values():
			for step in range(BOB_STEPS):
				world._clock = float(step) / float(BOB_STEPS) * TAU / float(spec.rate)
				world._float_boat(level, boat)
				low = minf(low, boat.position.y + floor_at - level)
				high = maxf(high, boat.position.y - level)
		_check(low >= Floats.MARGIN - 0.0001 and high < 0.0, "%s: a boat on the %s water keeps its floorboards %.3f m over the water and its keel %.3f m under it at every level and bob (floor at least %.2f over, keel under)" % [where, water, low, -high, Floats.MARGIN])
	world.reduced_motion = reduced

## A current's marks lie on the water, never on a floor or a crossing: no
## mark's corner stands more than a mark's half length inside one.
func _current_marks(world: Node3D, where: String, view: Dictionary) -> void:
	var piece: Variant = world.get("_current_piece")
	if piece == null: return
	for marks: Node in (piece.root as Node3D).find_children("Marks", "MeshInstance3D", true, false):
		var mesh := marks as MeshInstance3D
		var to_terrain: Transform3D = world.terrain.global_transform.affine_inverse() * mesh.global_transform
		var points: PackedVector3Array = mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var inside := ""
		for vertex: Vector3 in points:
			var at := to_terrain * vertex * 100.0
			for surface: Dictionary in view.get("islands", []) + view.get("bridges", []) + view.get("stairs", []):
				var r: Array = surface.rect_cm
				if at.x > float(r[0]) + 9.0 and at.x < float(r[2]) - 9.0 and at.z > float(r[1]) + 9.0 and at.z < float(r[3]) - 9.0: inside = str(surface.id)
		_check(inside.is_empty(), "%s: a current's mark lies on %s, not on the water" % [where, inside])

## A stepping stone that is down stays in view just under its water, at once
## for a snap and by sinking otherwise; a drowning on it shows the shared drown.
## Every crossing the world rolls up (kit/pieces/bridge_roll.gd: each held or
## toggled plank or rope crossing): shut, its deck is gone and its roll lies
## on the crossing at one end, the log across the crossing and the loose end
## facing across the gap to the far bank, whichever way the crossing runs;
## open, the deck is laid whole and the roll gone.
func _rolls(world: Node3D, where: String, view: Dictionary, base: Dictionary) -> void:
	var to_terrain: Transform3D = world.terrain.global_transform.affine_inverse()
	for id: String in world.crossing_pieces:
		var piece: RefCounted = world.crossing_pieces[id]
		if not "roll" in piece: continue
		_rolls_seen += 1
		var route: Dictionary = {}
		for candidate: Dictionary in view.get("bridges", []):
			if str(candidate.id) == id: route = candidate
		var run := Vector3.RIGHT if WalkReach.run_axis(route, WalkReach.walkable(view)) == 0 else Vector3.BACK
		var rect := Rect2(float(route.rect_cm[0]), float(route.rect_cm[1]), float(route.rect_cm[2] - route.rect_cm[0]), float(route.rect_cm[3] - route.rect_cm[1]))
		var shut := base.duplicate(true)
		shut.bridges[id] = false
		world.present(shut, true)
		var roll: Transform3D = to_terrain * (piece.roll as Node3D).global_transform
		var at := Vector2(roll.origin.x, roll.origin.z) * 100.0
		# The gap's ends as the world laid them, flat on the floor.
		var ends: Array = piece.gap_ends().map(func(end: Vector3) -> Vector3: return Vector3(end.x, 0.0, end.z))
		var flat := Vector3(roll.origin.x, 0.0, roll.origin.z)
		var across: Vector3 = (ends[1] - ends[0]).normalized()
		var loose := roll.basis.z.normalized()
		var lined_up := absf(across.dot(run)) > 0.99 and absf(roll.basis.x.normalized().dot(run)) < 0.01 and loose.dot(across) > 0.99 and flat.distance_to(ends[0]) <= flat.distance_to(ends[1]) + 0.001
		_check(not (piece.deck as Node3D).visible and (piece.roll as Node3D).is_visible_in_tree() and rect.grow(1.0).has_point(at) and lined_up, "%s: the shut crossing %s rolls up on itself at its near end (roll at %s cm), the log across it and the loose end facing the far bank" % [where, id, Vector2i(at)])
		var open := base.duplicate(true)
		open.bridges[id] = true
		world.present(open, true)
		_check((piece.deck as Node3D).is_visible_in_tree() and not (piece.roll as Node3D).visible and (piece.deck as Node3D).scale == Vector3.ONE, "%s: the open crossing %s is laid whole, its roll gone" % [where, id])
	world.present(base, true)

func _stones(world: Node3D, where: String, base: Dictionary) -> void:
	var stones: Variant = world.get("_stones")
	if stones == null: return
	for id: String in stones:
		_stones_seen += 1
		var stone: Dictionary = stones[id]
		var deck: Node3D = stone.deck
		var down := base.duplicate(true)
		down.bridges[id] = false
		world.present(down, true)
		var body: Node3D = world.waters.bodies.get(str(stone.water))
		var level: float = float(body.get_meta("shown")) if body != null else float(stone.rest)
		if JourneyCatalog.left_high(world.chapter_definition, id, down.get("controls", {})):
			_tall_stone(world, where, id, down, level)
		else:
			_check(deck.is_visible_in_tree() and deck.position.y <= minf(float(stone.rest), level - world.STONE_UNDER) + 0.001 and deck.position.y > level - 0.3, "%s: the stone %s, down, stays in view just under its water (top %.2f, water %.2f)" % [where, id, deck.position.y, level])
		var up := base.duplicate(true)
		up.bridges[id] = true
		world.present(up, true)
		var rest_y := deck.position.y
		var sunk := up.duplicate(true)
		sunk["drowned"] = {"slot": "p0", "route": id, "tick": 1}
		world.present(sunk, false)
		var start_y := deck.position.y
		world._advance_water(0.1)
		_check(deck.is_visible_in_tree() and deck.position.y < start_y and deck.position.y > float(stone.y) - 0.001 and is_equal_approx(start_y, rest_y), "%s: the stone %s sinks under a pip pushing it under, in view" % [where, id])
		_check(world.drowning.slot == "p0" and world.drowning.ring.visible and world.actor_targets.p0.y < level, "%s: a drowning on the stone %s shows the shared drown: the pip under the water, a ring spreading" % [where, id])
		world.present(up, true)
		_check(world.drowning.slot.is_empty() and is_equal_approx(deck.position.y, rest_y), "%s: without the drowning the stone %s stands again" % [where, id])
		world.present(base, true)

## A stone its water has fallen away from, shut: it stands STONE_TALL over its
## open height, the same column (never resized); a pip on it rides up with it;
## a fall off it leaves it standing and shows the shared fall: a wobble on top,
## then the pip dizzy in the water in front of it with a ring spreading.
func _tall_stone(world: Node3D, where: String, id: String, down: Dictionary, level: float) -> void:
	var stone: Dictionary = world._stones[id]
	var deck: Node3D = stone.deck
	var size := _stone_extent(deck)
	_check(deck.is_visible_in_tree() and is_equal_approx(deck.position.y, float(stone.rest) + world.STONE_TALL) and deck.position.y > level, "%s: the stone %s, left high by its water, stands tall over its open height (top %.2f, water %.2f)" % [where, id, deck.position.y, level])
	var on := down.duplicate(true)
	var route: Array = world._route_rect(id)
	on.players.p0.merge({"x": (int(route[0]) + int(route[2])) / 2, "z": (int(route[1]) + int(route[3])) / 2, "surface_id": id}, true)
	world.present(on, true)
	world._process(1.0)
	_check(absf(world.actors.p0.position.y - world.actor_targets.p0.y - world.STONE_TALL) < 0.01, "%s: a pip on the stone %s left high rides up on it" % [where, id])
	var fell := on.duplicate(true)
	fell["drowned"] = {"slot": "p0", "route": id, "tick": 1, "fell": true}
	world.present(fell, true)
	_check(world.drowning.slot == "p0" and is_equal_approx(deck.position.y, float(stone.rest) + world.STONE_TALL) and world.actor_targets.p0.y > level, "%s: a pip falling off the stone %s wobbles on top of it, the stone still standing tall" % [where, id])
	world.drowning.advance(world.drowning.WOBBLE + 0.01)
	_check(world.actor_targets.p0.y < level and world.drowning.ring.visible and _stone_extent(deck).is_equal_approx(size), "%s: then it lands in the water in front of the stone %s, a ring spreading, the stone the same size" % [where, id])
	world.present(down, true)
	_check(world.drowning.slot.is_empty() and is_zero_approx(world.actors.p0.rotation.z), "%s: without the fall the pip stands upright again" % where)

## No piece changes size with the water: every body at its lowest, middle and
## highest level in turn (the locks and riders following), every mesh but the
## water's own (WATER_SIZES) keeps its scale in the world and its mesh's size.
func _fixed_sizes(world: Node3D, where: String, base: Dictionary) -> void:
	var kit: Variant = world.get("waters")
	if kit == null or kit.water.is_empty(): return
	var first: Dictionary = {}
	var reported := 0
	for step: float in [0.0, 0.5, 1.0]:
		for id: String in kit.bodies:
			var levels: Array = kit.levels_of(id).values()
			kit.set_level(id, lerpf(float(levels.min()), float(levels.max()), step), true)
		if is_instance_valid(kit.locks): kit.locks.present(kit.lock_levels("target"), true)
		world._advance_water(0.0)
		for node: Node in world.find_children("*", "MeshInstance3D", true, false):
			if _water_sized(node, world): continue
			var mesh := node as MeshInstance3D
			var size := [(world.global_transform.affine_inverse() * mesh.global_transform).basis.get_scale(), mesh.get_aabb().size]
			var key := mesh.get_instance_id()
			if not first.has(key):
				if step == 0.0: first[key] = size
				continue
			if step == 0.0: continue
			_sized_seen += 1
			var ok: bool = (size[0] as Vector3).is_equal_approx(first[key][0]) and (size[1] as Vector3).is_equal_approx(first[key][1])
			if not ok and reported < 5:
				reported += 1
				_check(false, "%s: %s changes size with the water (scale %s to %s, mesh %s to %s): build it once tall enough for every level, and only move or show it" % [where, world.get_path_to(mesh), first[key][0], size[0], first[key][1], size[1]])
	world.present(base, true)
	_stone_feet(world, where)

## Every stepping stone reaches STONE_FOOT under its water's bed from the
## highest it stands, so its foot never shows over the bed.
func _stone_feet(world: Node3D, where: String) -> void:
	var stones: Variant = world.get("_stones")
	if not stones is Dictionary: return
	for id: String in stones:
		var stone: Dictionary = stones[id]
		var deck := stone.deck as Node3D
		if not is_instance_valid(deck): continue
		var foot := INF
		for node: Node in deck.find_children("*", "MeshInstance3D", true, false):
			var mesh := node as MeshInstance3D
			foot = minf(foot, (deck.global_transform.affine_inverse() * mesh.global_transform * mesh.get_aabb()).position.y)
		var bed: float = world.waters.bed(str(stone.water))
		var lowest := float(stone.rest) + WaterWorld.STONE_TALL + foot
		_stones_feet_seen += 1
		_check(lowest <= bed - WaterWorld.STONE_FOOT + 0.001, "%s: stone %s's foot reaches %.2f m over its highest, the bed is at %.2f: build it once down to %.2f m under the bed, so no foot shows and the water only covers more or less of it" % [where, id, lowest, bed, WaterWorld.STONE_FOOT])

## Whether `node` is the water's own, or under it (WATER_SIZES).
static func _water_sized(node: Node, world: Node) -> bool:
	while node != null and node != world:
		# A sibling of the same name is told apart by a number on its end.
		var own := str(node.name).rstrip("0123456789")
		for name: String in WATER_SIZES:
			if own == name or (name.ends_with("_") and own.begins_with(name)): return true
		node = node.get_parent()
	return false

## A deck's drawn size: the bounds of its meshes in its own frame.
static func _stone_extent(deck: Node3D) -> Vector3:
	var box := AABB()
	for node: Node in deck.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		box = box.merge(deck.global_transform.affine_inverse() * mesh.global_transform * mesh.get_aabb())
	return box.size

## Crossing ends found so far, by the stage floors they were read from.
var _ends_by_floors: Dictionary = {}

## Each crossing's ends as the engine walks them: route id -> {floor id: true},
## the floors a pip can step to from it once no crossing has an owner. Read
## from the stage's plan (its floors, as the level checker reads them), so
## every family is walked alike.
func _route_ends(view: Dictionary) -> Dictionary:
	var bare: Dictionary = {}
	for field: String in ["islands", "bridges", "stairs", "drops", "obstacles", "access_zones"]: bare[field] = view.get(field, []).duplicate(true)
	for kind: String in ["bridges", "stairs"]:
		for route: Dictionary in bare.get(kind, []): route.erase("owner_slot")
	var id := JSON.stringify(bare)
	if _ends_by_floors.has(id): return _ends_by_floors[id]
	var graph: RefCounted = LevelGraph.new(bare)
	var ends: Dictionary = {}
	for pair: String in graph.build("p0"):
		var sides := pair.split(">")
		for index in range(2):
			if graph.route_bit.has(sides[index]): (ends.get_or_add(sides[index], {}) as Dictionary)[sides[1 - index]] = true
	_ends_by_floors[id] = ends
	return ends

## Whether two bubble boxes overlap by more than a touch.
static func _meets(a: Rect2, b: Rect2) -> bool:
	return a.intersection(b).get_area() >= OVERLAP_PX2

## A bubble's name for a message: its selector, else what it says.
static func _name(world: Node3D, bubble: LabelBubble) -> String:
	for id: String in world._journey_switches:
		if world._journey_switches[id].bubble == bubble: return "the %s selector" % id
	return "\"%s\"" % bubble.labels[0].text if not bubble.labels.is_empty() else "a bubble"

static func _px(box: Rect2) -> String:
	return "(%d, %d) to (%d, %d) px" % [roundi(box.position.x), roundi(box.position.y), roundi(box.end.x), roundi(box.end.y)]
