extends RefCounted
## The Falls: four stages on the new pieces (rules 16, core/physical/pieces_rules.gd:
## the tide rules with open controls and open turns, plus carried items,
## currents, platforms, sinking stones, one way stairs and "not" gates),
## written with the stage blocks (core/blocks/stage_blocks.gd). The designs are
## claude-20261011\pipsport-concepts\solver\levels.py (falls_1 to falls_4):
## Teal is p1, Gold is p0, and Gold (the host's pip) plays first in stage 1.
## A journey is one map: each stage starts with both pips where the stage
## before ended (its goal), so each stage opens one stair from that goal down
## into its own start (stage 2 starts both on the bank, 3 on the west ledge, 4
## on the lookout). Heights in cm; stage 4 is all at 96 cm.
##   1 foot-of-the-falls: the mill wheel sets the pool (LOW shows the stepping
##     stones, HIGH winds the bucket up to the ledge); the footbridge from the
##     mill is down while its pan on the island is weighed (a pip or the
##     pipsport); the island ladder needs both hands.
##   2 the-old-mill: the water gate board turns the big wheel (ride it up to
##     the loft, both hands), floods the mill steps and dries the old
##     riverbed; the sack lift carries the hook up while the gate board or the
##     loft's winding board is held; the attic ladder is bolted from the loft.
##   3 behind-the-falls: the rope bridge is tight while a crank board at either
##     end is held, and the west one winds the basket line across; the water
##     gate lever on the east top dries the path behind the falls.
##   4 the-last-stones: the stream wheel shows the floating log (HIGH), the
##     middle steps (MID) or the sinking stones (LOW); the lookout crank board
##     keeps the rope bridge tight; the leap needs both hands; the far gate is
##     held by its board outside or by the bar pulled inside.
## No player words here: the title and hints are the descriptor's copy and
## stage_copy, so changing them never changes the definition hash.
## The turn limits are development ones (120 s every turn, what the 1 MiB
## solo save fits today) until play sets them (scripts/chapter_turn_limits.py).

const StageBlocks = preload("res://core/blocks/stage_blocks.gd")
const PiecesRules = preload("res://core/physical/pieces_rules.gd")
## Turns a stage may take: 10, or 20 on a hard stage (the owner's call).
const CAPS := {"foot-of-the-falls": 10, "the-old-mill": 10, "behind-the-falls": 10, "the-last-stones": 10}
const CARRIED := {"item_id": "pipsport", "carried": true}

static func definition() -> Dictionary:
	return PiecesRules.pin(StageBlocks.expand(source()), CAPS)

static func source() -> Dictionary:
	return _proto(_plain())

static func _plain() -> Dictionary:
	return {"schema_version": 7, "simulation_version": 9, "id": "the-falls", "version": 1, "premium": false, "closing_ticks": 30,
		"turn_limits": {"a_ticks": 3600, "b_ticks": 3600},
		"starts": {"p0": {"position_cm": [150, -200], "height_cm": 48, "surface_id": "mill"}, "p1": {"position_cm": [150, 200], "height_cm": 0, "surface_id": "beach"}},
		"props": [], "drops": [],
		"items": [{"id": "pipsport", "at": "post"}],
		"item_spots": [
			_spot("post", "isle", [440, 310], 0), _spot("pan", "isle", [760, 310], 0), _spot("bucket", "isle", [760, 90], 0), _spot("bucket-top", "ledge", [740, -290], 48),
			_spot("hook", "yard", [1340, 110], 48), _spot("sack-top", "loft", [1340, -410], 96),
			_spot("basket", "wtop", [2760, -410], 144), _spot("basket-end", "etop", [3240, -410], 144)],
		"islands": [
			_island("mill", [0, -350, 300, -50], 48), _island("ledge", [400, -350, 800, -50], 48), _island("isle", [400, 50, 800, 350], 0), _island("beach", [0, 50, 300, 350], 0),
			_island("bank", [900, -250, 1200, 450], 0), _island("yard", [1300, -150, 1600, 150], 48), _island("deck", [1700, -150, 2000, 450], 48), _island("loft", [1300, -450, 2000, -250], 96),
			_island("wledge", [2100, -450, 2400, 450], 48), _island("wtop", [2500, -450, 2800, -150], 144), _island("etop", [3200, -450, 3500, -150], 144), _island("eledge", [3200, 150, 3500, 450], 48),
			_island("look", [3600, -450, 3900, -50], 96), _island("ledge-4", [3600, 150, 3900, 450], 96), _island("rock", [4060, -450, 4160, -170], 96), _island("big", [4260, -450, 4600, 450], 96),
			_island("far", [4700, -450, 5000, 0], 96)],
		"bridges": [
			_bridge("footbridge", [300, -250, 400, -154], 48, "mill", "ledge"), _bridge("stones", [300, 150, 400, 246], 0, "beach", "isle"),
			_bridge("walkway", [1600, -50, 1700, 46], 48, "yard", "deck"),
			_bridge("rope-bridge", [2800, -350, 3200, -254], 144, "wtop", "etop", true), _bridge("behind", [2400, 250, 3200, 346], 48, "wledge", "eledge"),
			_bridge("log", [3700, -50, 3796, 150], 96, "look", "ledge-4"), _bridge("s1", [3900, -350, 3980, -270], 96, "look", "rock"), _bridge("s2", [3980, -350, 4060, -270], 96, "look", "rock"),
			_bridge("leap", [4160, -350, 4260, -270], 96, "rock", "big", true), _bridge("rope-span", [3900, 200, 4260, 296], 96, "ledge-4", "big", true),
			_bridge("middle-steps", [3900, 350, 4260, 446], 96, "ledge-4", "big"), _bridge("far-gate", [4600, -300, 4700, -204], 96, "big", "far")],
		"stairs": [
			_stair("ladder", [560, -50, 656, 50], "z", "ledge", "isle", 48, 0, true), _stair("down-to-bank", [800, -250, 900, -154], "x", "ledge", "bank", 48, 0),
			_stair("mill-steps", [1200, -100, 1300, -4], "x", "bank", "yard", 0, 48), _stair("riverbed", [1200, 300, 1700, 396], "x", "bank", "deck", 0, 48),
			_stair("wheel", [1850, -250, 1946, -150], "z", "loft", "deck", 96, 48, true), _stair("attic-ladder", [1450, -250, 1546, -150], "z", "loft", "yard", 96, 48, true),
			_stair("down-to-ledge", [2000, -400, 2100, -304], "x", "loft", "wledge", 96, 48),
			_stair("west-ladder", [2400, -350, 2500, -254], "x", "wledge", "wtop", 48, 144, true), _stair("spray-steps", [3300, -150, 3396, 150], "z", "etop", "eledge", 144, 48),
			_stair("down-to-lookout", [3500, -350, 3600, -254], "x", "etop", "look", 144, 96)],
		"stages": [_foot(), _mill(), _behind(), _stones()]}

## Stage 1: Gold on the mill with the pool wheel, Teal on the beach; the
## pipsport in the post box on the island.
static func _foot() -> Dictionary:
	var stage := _stage("foot-of-the-falls", "p0", [480, -290])
	stage.item_starts = {"pipsport": "post"}
	stage.current_legs = [{"from": "bucket", "to": "bucket-top", "control_id": "pool", "value": "HIGH"}]
	stage.blocks = [
		{"block": "selector", "id": "pool", "at": [80, -290], "surface": "mill", "owner": "p0", "height": 48, "values": ["HIGH", "LOW"], "initial": "HIGH"},
		{"block": "selector_gate", "selector": "pool", "routes": {"stones": "LOW"}},
		{"block": "weight_pan", "pad": _pad("pan", [760, 310], "isle", 0), "items": ["pipsport"], "routes": ["footbridge"]},
		{"block": "open_route", "routes": ["ladder"]},
		_goal("foot-goal", [480, -290], "ledge", 48, CARRIED)]
	return stage

## Stage 2: both come down the stair to the bank; Teal holds the pipsport.
static func _mill() -> Dictionary:
	var stage := _stage("the-old-mill", "p1", [1700, -350])
	stage.item_starts = {"pipsport": "p1"}
	var gate := {"pad_id": "gate-board"}
	stage.current_legs = [{"from": "hook", "to": "sack-top", "when": {"any": [gate, {"pad_id": "winding-board"}]}}]
	stage.blocks = [
		{"block": "open_route", "routes": ["down-to-bank", "walkway"]},
		{"block": "pad", "id": "gate-board", "at": [1940, 400], "surface": "deck", "owner": "p0", "height": 48, "style": "board"},
		{"block": "pad", "id": "winding-board", "at": [1920, -410], "surface": "loft", "owner": "p0", "height": 96, "style": "board"},
		{"block": "raw", "gates": [{"route_id": "mill-steps", "when": {"not": gate}}, {"route_id": "riverbed", "when": gate}]},
		{"block": "wheel_ride", "stairs": ["wheel"], "when": gate},
		{"block": "relay_lever", "lever": {"id": "hatch", "at": [1580, -410], "surface": "loft", "owner": "p0", "height": 96}, "routes": ["attic-ladder"]},
		_goal("mill-goal", [1700, -350], "loft", 96, CARRIED)]
	return stage

## Stage 3: both come down to the west ledge; Teal holds the pipsport.
static func _behind() -> Dictionary:
	var stage := _stage("behind-the-falls", "p1", [3340, -300])
	stage.item_starts = {"pipsport": "p1"}
	stage.current_legs = [{"from": "basket", "to": "basket-end", "when": {"pad_id": "crank"}}]
	stage.blocks = [
		{"block": "open_route", "routes": ["down-to-ledge", "west-ladder", "spray-steps"]},
		{"block": "crank_bridge", "pads": [_pad("crank", [2540, -200], "wtop", 144), _pad("east-crank", [3460, -410], "etop", 144)], "routes": ["rope-bridge"]},
		{"block": "falls_path", "lever": {"id": "water-gate", "at": [3460, -200], "surface": "etop", "owner": "p0", "height": 144}, "routes": ["behind"]},
		_goal("behind-goal", [3340, -300], "etop", 144, CARRIED)]
	return stage

## Stage 4: both come down to the lookout; Gold holds the pipsport.
static func _stones() -> Dictionary:
	var stage := _stage("the-last-stones", "p1", [4850, -150])
	stage.item_starts = {"pipsport": "p0"}
	stage.blocks = [
		{"block": "open_route", "routes": ["down-to-lookout", "leap"]},
		{"block": "selector", "id": "stream", "at": [3660, -100], "surface": "look", "owner": "p0", "height": 96, "values": ["HIGH", "MID", "LOW"], "initial": "HIGH"},
		{"block": "selector_gate", "selector": "stream", "routes": {"log": "HIGH", "middle-steps": "MID"}},
		{"block": "sinking_stones", "stones": ["s1", "s2"], "when": {"control_id": "stream", "value": "LOW"}},
		{"block": "crank_bridge", "pads": [_pad("look-crank", [3860, -100], "look", 96)], "routes": ["rope-span"]},
		{"block": "pad", "id": "gate-step", "at": [4560, 400], "surface": "big", "owner": "p0", "height": 96, "style": "board"},
		{"block": "lever", "id": "bar", "at": [4940, -410], "surface": "far", "owner": "p0", "height": 96},
		{"block": "raw", "gates": [{"route_id": "far-gate", "when": {"any": [{"pad_id": "gate-step"}, {"lever_id": "bar"}]}}]},
		_goal("stones-goal", [4850, -150], "far", 96, CARRIED)]
	return stage

static func _stage(id: String, first: String, goal: Array) -> Dictionary:
	return {"id": id, "version": 1, "first_player_slot": first, "kind": "route_endpoint", "controls": [], "levers": [], "pressure_pads": [], "ball_pads": [],
		"gates": [], "entry_latch_routes": [], "source_policy": {"kind": "route_endpoint", "when": {}}, "receiver_route_cm": [goal.duplicate()], "receiver_action_ticks": 2}

static func _goal(id: String, at: Array, surface: String, height: int, when: Dictionary) -> Dictionary:
	return {"block": "ring_bell", "id": id, "at": at, "surface": surface, "owner": "p1", "height": height, "radius": 48, "when": when}

static func _pad(id: String, at: Array, surface: String, height: int) -> Dictionary:
	return {"id": id, "at": at, "surface": surface, "owner": "p0", "height": height}

static func _spot(id: String, surface: String, at: Array, height: int) -> Dictionary:
	return {"id": id, "surface_id": surface, "position_cm": at, "height_cm": height}

static func _island(id: String, rect: Array, height: int) -> Dictionary:
	return {"id": id, "rect_cm": rect, "height_cm": height}

static func _bridge(id: String, rect: Array, height: int, from: String, to: String, hands: bool = false) -> Dictionary:
	var bridge := {"id": id, "rect_cm": rect, "from_surface": from, "to_surface": to, "height_cm": height}
	if hands: bridge["hands"] = true
	return bridge

static func _stair(id: String, rect: Array, axis: String, from: String, to: String, low: int, high: int, hands: bool = false) -> Dictionary:
	var stair := {"id": id, "rect_cm": rect, "axis": axis, "from_surface": from, "to_surface": to, "from_height_cm": low, "to_height_cm": high}
	if hands: stair["hands"] = true
	return stair

## PROTOTYPE (train/falls-rethink-proto): floors spread 2.6 times apart along x
## and 1.5 across (growing only a little), each stage on its own tier up the gorge (the mill at the
## foot, the path behind the falls higher, the last stones at the lip), with
## heights inside a stage 2.5 times taller. core/journey/proto_spread.gd.
const ProtoSpread = preload("res://core/journey/proto_spread.gd")
const PROTO_TIERS := [[900, 200], [2100, 450], [3600, 700]]

static func _proto(plain: Dictionary) -> Dictionary:
	return ProtoSpread.apply(plain, Vector2(2.6, 1.5), Vector2(1.2, 1.15), 2.5, PROTO_TIERS)
