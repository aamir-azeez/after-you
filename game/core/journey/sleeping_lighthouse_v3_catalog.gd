extends RefCounted
## sleeping-lighthouse@3: the Sleeping Lighthouse on the shared journey rules,
## pinned to open turns with the new pieces (core/physical/pieces_rules.gd: 20, carry-over turns)
## and lit by the light pieces (core/physical/light_pieces.gd, the "light"
## block), so a stage passes back and forth until both pips end a turn at its
## goal with its light holding, up to its cap. Every control works for either
## pip. @1 and @2 keep the Lighthouse's own engine (core/lighthouse/) and
## replay unchanged. The same rooms in cm: the harbour, the court, the north
## and south isles, Rest Rock and the tower, all at the water's level, joined
## by bridges that stand only while light reaches their receivers (the tide
## rules: a bridge whose light goes closes slowly and drowns whoever is on it).
## A light pad lights its lamp only while a pip stands on it, far from the
## bridge it lights, so the pip holding it never crosses that way itself.
##   1 borrowed-light (orange first, the host's pip): the harbour lamp shines
##     while someone stands on the light pad; the harbour mirror turned sends
##     it to the bridge's receiver. Over in the court, the court mirror turned
##     sends the court lamp to a second receiver on the same bridge, so the
##     one who crossed keeps the way lit for the one who held the light.
##   2 missing-piece: the lens rests on the north isle. The court lamp shines
##     while someone stands on the court's light pad, and the north mirror
##     turned lights the north bridge. Fitted in its cradle, the lens lights
##     the court's glow, the goal.
##   3 two-promises: the lens in its cradle shines west and south. West, the
##     upper mirror sends it north to the north promise, which holds the north
##     bridge. The south bridge stands while someone holds the north isle's
##     light pad, or once the south mirror sends the lens's light to the south
##     promise. Both promises lit light the goal.
##   4 after-the-first-bell: the path lamp on the south isle shines while
##     someone holds its pad; the path selector a few steps off it steers it
##     to the first path (to Rest Rock) or the second (to the tower), or puts
##     it out, so the one holding the lamp steps off to turn it. On Rest Rock
##     and the tower, mirrors turned keep each path lit for the one who held
##     the lamp.
##   5 what-carried-you: the lens in its cradle lights the way to Rest Rock;
##     taken up, that way goes dark, so it is thrown from the court's edge to
##     Rest Rock's perch, where it lights the way again. The tower bridge
##     stands while someone holds the tower's light pad, or once the lens is in
##     the tower's projector, the goal.
##   6 a-welcome-left-on: the projector shines west and north. West, the
##     welcome mirror on Rest Rock turned sends it to the welcome below; north,
##     the beacon mirror sends it to the beacon. The tower bridge stands only
##     while someone holds the tower's light pad, both ways. Both lights lit
##     light the goal: the welcome left on.
## Neither pip can do any stage alone (claude-20261011\lighthouse-open\
## solver_lighthouse.py; tests/test_level_checker.gd).
## No player words here: the title and hints are the descriptor's copy and
## stage_copy, so changing them never changes the definition hash.

const StageBlocks = preload("res://core/blocks/stage_blocks.gd")
const PiecesRules = preload("res://core/physical/pieces_rules.gd")
## Turns a stage may take: ten on the first four, twenty on the last two.
const CAPS := {"borrowed-light": 10, "missing-piece": 10, "two-promises": 10, "after-the-first-bell": 10, "what-carried-you": 20, "a-welcome-left-on": 20}
## The light's plane, over every isle.
const BOUNDS := [-900, -560, 900, 560]
const LENS := "lens"

static func definition() -> Dictionary:
	return PiecesRules.pin(StageBlocks.expand(source()), CAPS)

static func source() -> Dictionary:
	return {"schema_version": 7, "simulation_version": 9, "id": "sleeping-lighthouse", "version": 3, "premium": true, "closing_ticks": 30,
		"turn_limits": {"a_ticks":2550,"b_ticks":2550},
		"starts": {"p0": {"position_cm": [-760, 0], "height_cm": 0, "surface_id": "harbour"}, "p1": {"position_cm": [-520, 80], "height_cm": 0, "surface_id": "harbour"}},
		"props": [], "drops": [], "stairs": [],
		# Away until the lens appears on the north isle.
		"items": [{"id": LENS, "at": "away"}],
		"item_spots": [
			{"id": "court-cradle", "surface_id": "court", "position_cm": [-150, 60], "height_cm": 0, "radius_cm": 32},
			{"id": "north-shelf", "surface_id": "north", "position_cm": [40, -400], "height_cm": 0, "radius_cm": 32},
			{"id": "rest-perch", "surface_id": "rest-rock", "position_cm": [290, 50], "height_cm": 0, "radius_cm": 28},
			{"id": "tower-projector", "surface_id": "tower", "position_cm": [650, 0], "height_cm": 0, "radius_cm": 32}],
		"islands": [_island("harbour", [-850, -180, -450, 180]), _island("court", [-250, -130, 150, 130]), _island("north", [-250, -500, 150, -240]),
			_island("south", [-250, 240, 150, 500]), _island("rest-rock", [240, -100, 340, 100]), _island("tower", [450, -180, 850, 180])],
		"bridges": [_bridge("harbour-court", [-450, -50, -250, 50], "harbour", "court"), _bridge("court-north", [-100, -240, 0, -130], "court", "north"),
			_bridge("court-south", [-100, 130, 0, 240], "court", "south"), _bridge("court-rest", [150, -50, 240, 50], "court", "rest-rock"),
			_bridge("rest-tower", [340, -50, 450, 50], "rest-rock", "tower")],
		"stages": [_borrowed_light(), _missing_piece(), _two_promises(), _after_the_first_bell(), _what_carried_you(), _a_welcome_left_on()]}

## Both start on the harbour; the bell is in the court.
static func _borrowed_light() -> Dictionary:
	var stage := _stage("borrowed-light", "p0", [40, -40])
	stage.blocks = [
		_pad("harbour-pad", [-800, 120], "harbour"),
		{"block": "light", "bounds": BOUNDS,
			"lamps": [_lamp("harbour-lamp", [-690, -100], "east", {"pad_id": "harbour-pad"}), _lamp("court-lamp", [100, 60], "west")],
			"mirrors": [_mirror("harbour-mirror", [-560, -100], "harbour", "backslash"), _mirror("court-mirror", [-60, 60], "court", "slash")],
			"receivers": [_receiver("harbour-eye", [-560, -160]), _receiver("court-eye", [-60, -100])],
			"routes": {"harbour-court": ["harbour-eye", "court-eye"]}},
		_goal("court-bell", [40, -40], "court")]
	return stage

## Both start at the court bell; the lens waits on the north isle.
static func _missing_piece() -> Dictionary:
	var stage := _stage("missing-piece", "p1", [-150, -50])
	stage.item_starts = {LENS: "north-shelf"}
	stage.blocks = [
		_pad("court-pad", [110, 90], "court"),
		{"block": "light", "bounds": BOUNDS,
			"lamps": [_lamp("court-lamp", [100, 0], "west", {"pad_id": "court-pad"}), _lamp("cradle-lamp", [-150, 116], "west", _in("court-cradle"))],
			"mirrors": [_mirror("north-mirror", [-50, 0], "court", "slash")],
			"receivers": [_receiver("north-eye", [-50, -90]), _receiver("court-glow", [-240, 116])],
			"routes": {"court-north": "north-eye"}},
		{"block": "open_route", "routes": ["harbour-court"]},
		_goal("lens-crest", [-150, -50], "court", {"signal_id": "court-glow"})]
	return stage

## Both start by the lens's cradle; the promises are on the north and south isles.
static func _two_promises() -> Dictionary:
	var stage := _stage("two-promises", "p0", [60, -60])
	stage.blocks = [
		_pad("north-pad", [100, -450], "north"),
		{"block": "light", "bounds": BOUNDS,
			"lamps": [_lamp("lens-west", [-150, 116], "west", _in("court-cradle")), _lamp("lens-south", [-94, 60], "south", _in("court-cradle")),
				_lamp("north-lamp", [-200, -300], "south", {"pad_id": "north-pad"})],
			"mirrors": [_mirror("upper-mirror", [-220, 116], "court", "slash"), _mirror("south-mirror", [-94, 350], "south", "slash")],
			"receivers": [_receiver("north-promise", [-220, -420]), _receiver("south-promise", [0, 350]), _receiver("south-way", [-200, 270])],
			"routes": {"court-north": "north-promise", "court-south": ["south-way", "south-promise"]}},
		{"block": "open_route", "routes": ["harbour-court"]},
		_goal("promise-crest", [60, -60], "court", {"all": [{"signal_id": "north-promise"}, {"signal_id": "south-promise"}]})]
	return stage

## Both start in the court; the bell is on the tower.
static func _after_the_first_bell() -> Dictionary:
	var stage := _stage("after-the-first-bell", "p1", [700, 80])
	stage.blocks = [
		_pad("path-pad", [-200, 450], "south"),
		{"block": "light", "bounds": BOUNDS,
			"lamps": [_lamp("path-lamp", [-200, 350], "east", {"pad_id": "path-pad"}), _lamp("rest-lamp", [320, -80], "west"), _lamp("beacon-lamp", [800, -120], "west")],
			"fixed_mirrors": [{"id": "path-mirror", "at": [56, 350], "orientation": "backslash"}],
			"selectors": [{"id": "path-selector", "at": [-120, 420], "surface": "south", "owner": "p0", "values": ["off", "first", "second"], "initial": "off",
				"optics": {"off": {"path-lamp": {"enabled": false}}, "first": {"path-mirror": {"orientation": "slash"}}, "second": {"path-mirror": {"orientation": "backslash"}}}}],
			"mirrors": [_mirror("rest-mirror", [260, -80], "rest-rock", "backslash"), _mirror("tower-mirror", [520, -120], "tower", "backslash")],
			"receivers": [_receiver("first-path", [56, 270]), _receiver("second-path", [56, 460]), _receiver("rest-eye", [260, 70]), _receiver("tower-path", [520, -70])],
			"routes": {"court-rest": ["first-path", "rest-eye"], "rest-tower": ["second-path", "tower-path"]}},
		{"block": "open_route", "routes": ["harbour-court", "court-north", "court-south"]},
		_goal("tower-bell", [700, 80], "tower")]
	return stage

## Both start at the tower bell; the lens rests in its cradle in the court.
static func _what_carried_you() -> Dictionary:
	var stage := _stage("what-carried-you", "p0", [720, -90])
	# From the court's edge to Rest Rock's perch: caught there, or it lands in it.
	stage.throws = [{"id": "lens-throw", "mark": {"position_cm": [110, -90], "surface_id": "court", "height_cm": 0, "radius_cm": 30}, "to": "rest-perch", "flight_ticks": 60, "catch_cm": 60}]
	stage.blocks = [
		_pad("tower-pad", [800, 150], "tower"),
		{"block": "light", "bounds": BOUNDS,
			"lamps": [_lamp("cradle-lamp", [-94, 60], "east", _in("court-cradle")), _lamp("perch-lamp", [320, -60], "west", _in("rest-perch")),
				_lamp("tower-lamp", [790, -60], "west", {"pad_id": "tower-pad"}), _lamp("projector-lamp", [610, 30], "west", _in("tower-projector"))],
			"receivers": [_receiver("cradle-eye", [130, 60]), _receiver("perch-eye", [130, -60]), _receiver("tower-eye", [480, -60]), _receiver("projector-eye", [480, 30])],
			"routes": {"court-rest": ["cradle-eye", "perch-eye"], "rest-tower": ["tower-eye", "projector-eye"]}},
		{"block": "open_route", "routes": ["harbour-court", "court-north", "court-south"]},
		_goal("projector-crest", [720, -90], "tower", _in("tower-projector"))]
	return stage

## Both start by the projector; the welcome is lit from Rest Rock and the beacon.
static func _a_welcome_left_on() -> Dictionary:
	var stage := _stage("a-welcome-left-on", "p1", [700, 80])
	stage.blocks = [
		_pad("tower-pad", [800, 150], "tower"),
		{"block": "light", "bounds": BOUNDS,
			"lamps": [_lamp("tower-lamp", [790, -60], "west", {"pad_id": "tower-pad"}), _lamp("projector-west", [610, -20], "west", _in("tower-projector")),
				_lamp("projector-north", [650, -40], "north", _in("tower-projector"))],
			"mirrors": [_mirror("welcome-mirror", [290, -20], "rest-rock", "backslash"), _mirror("beacon-mirror", [650, -130], "tower", "backslash")],
			"receivers": [_receiver("tower-eye", [480, -60]), _receiver("welcome-below", [290, 90]), _receiver("beacon", [800, -130])],
			"routes": {"rest-tower": "tower-eye"}},
		_goal("beacon-crest", [700, 80], "tower", {"all": [{"signal_id": "beacon"}, {"signal_id": "welcome-below"}]})]
	return stage

static func _pad(id: String, at: Array, surface: String) -> Dictionary:
	return {"block": "pad", "id": id, "at": at, "surface": surface, "owner": "p0", "radius": 32}

static func _lamp(id: String, at: Array, facing: String, when: Dictionary = {}) -> Dictionary:
	var lamp := {"id": id, "at": at, "facing": facing}
	if not when.is_empty(): lamp["when"] = when
	return lamp

static func _mirror(id: String, at: Array, surface: String, initial: String) -> Dictionary:
	return {"id": id, "at": at, "surface": surface, "owner": "p0", "initial": initial}

static func _receiver(id: String, at: Array) -> Dictionary:
	return {"id": id, "at": at}

## The lens resting at `spot`.
static func _in(spot: String) -> Dictionary:
	return {"item_id": LENS, "spot_id": spot}

static func _goal(id: String, at: Array, surface: String, when: Dictionary = {}) -> Dictionary:
	var goal := {"block": "ring_bell", "id": id, "at": at, "surface": surface, "owner": "p1", "radius": 36}
	if not when.is_empty(): goal["when"] = when
	return goal

static func _stage(id: String, first: String, goal: Array) -> Dictionary:
	return {"id": id, "version": 1, "first_player_slot": first, "kind": "route_endpoint", "controls": [], "levers": [], "pressure_pads": [], "ball_pads": [],
		"gates": [], "entry_latch_routes": [], "source_policy": {"kind": "route_endpoint", "when": {}}, "receiver_route_cm": [goal.duplicate()], "receiver_action_ticks": 2}

static func _island(id: String, rect: Array) -> Dictionary:
	return {"id": id, "rect_cm": rect, "height_cm": 0}

static func _bridge(id: String, rect: Array, from: String, to: String) -> Dictionary:
	return {"id": id, "rect_cm": rect, "from_surface": from, "to_surface": to, "height_cm": 0}
