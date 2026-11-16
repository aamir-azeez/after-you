extends RefCounted
## A small witness level for rules 16's carried items and currents
## (core/physical/carried_items.gd). Never registered: tests/test_carried_items.gd
## plays it through the journey engine with this script as its catalog, and
## tests/test_carried_items_checker.gd runs the level graph over it.
##
##   dock (0 cm)  --ladder (both hands)-->  loft (48 cm)
##     |  ferry: open while the raft lies at its berth
##   quay (0 cm)
##
## Stage 1, "hand-up": the pipsport waits in the post box on the dock. Nobody
## climbs the ladder with it, so whoever fetches it hands it up to the other at
## the top; the loft's goal wants it carried there.
## Stage 2, "drift": the pipsport bobs in the eddy and the raft at its mooring.
## The wheel on the dock turned north carries both one leg: the raft to its
## berth, which opens the ferry, and the pipsport to the quay's landing, unless
## someone stands on the sluice board. The goal wants it back in the post box.
const Canonical = preload("res://core/v2/canonical.gd")
const JourneyCatalog = preload("res://core/journey/stage_catalog.gd")
const OpenControls = preload("res://core/physical/open_controls.gd")
const KEY := "carry-witness@1"

static func definition() -> Dictionary:
	return {
		"id": "carry-witness", "version": 1, "schema_version": 7, "premium": false,
		"simulation_version": OpenControls.PIECES_RULES_VERSION,
		"islands": [
			{"id": "dock", "rect_cm": [-400, -120, -100, 120], "height_cm": 0},
			{"id": "loft", "rect_cm": [0, -120, 400, 120], "height_cm": 48},
			{"id": "quay", "rect_cm": [-400, 200, -100, 360], "height_cm": 0},
		],
		"bridges": [
			{"id": "ferry", "rect_cm": [-290, 120, -210, 200], "height_cm": 0, "from_surface": "dock", "to_surface": "quay"},
		],
		"stairs": [
			{"id": "ladder", "axis": "x", "rect_cm": [-100, -32, 0, 32], "from_height_cm": 0, "to_height_cm": 48, "from_surface": "dock", "to_surface": "loft", "hands": true},
		],
		"drops": [], "props": [],
		"starts": {
			"p0": {"position_cm": [-300, 0], "surface_id": "dock", "height_cm": 0},
			"p1": {"position_cm": [250, 0], "surface_id": "loft", "height_cm": 48},
		},
		"items": [{"id": "pipsport", "at": "post"}, {"id": "raft", "at": "mooring", "carry": false}],
		"item_spots": [
			{"id": "post", "surface_id": "dock", "position_cm": [-350, 80], "height_cm": 0},
			{"id": "desk", "surface_id": "loft", "position_cm": [320, 80], "height_cm": 48},
			{"id": "landing", "surface_id": "quay", "position_cm": [-160, 300], "height_cm": 0},
			{"id": "eddy", "surface_id": "", "position_cm": [-40, 300], "height_cm": 0},
			{"id": "mooring", "surface_id": "", "position_cm": [-160, 160], "height_cm": 0},
			{"id": "berth", "surface_id": "", "position_cm": [-250, 160], "height_cm": 0},
		],
		"stages": [_hand_up(), _drift()],
	}

static func _stage(id: String) -> Dictionary:
	return {"id": id, "version": 1, "kind": "journey", "first_player_slot": "p0", "turn_cap": 10,
		"controls": [], "levers": [], "pressure_pads": [], "ball_pads": [], "entry_latch_routes": [],
		"gates": [{"route_id": "ladder"}],
		"source_policy": {"kind": "route_endpoint", "when": {}}, "receiver_action_ticks": 0}

static func _hand_up() -> Dictionary:
	var stage := _stage("hand-up")
	stage.goal = {"id": "loft-goal", "surface_id": "loft", "position_cm": [250, 0], "height_cm": 48, "radius_cm": 48}
	stage.goal_policy = {"kind": "ring", "when": {"item_id": "pipsport", "carried": true}}
	stage.receiver_route_cm = [[250, 0]]
	return stage

static func _drift() -> Dictionary:
	var stage := _stage("drift")
	stage.item_starts = {"pipsport": "eddy"}
	stage.controls = [{"id": "current", "kind": "selector", "surface_id": "dock", "position_cm": [-350, -80], "height_cm": 0, "radius_cm": 28, "values": ["south", "north"], "initial": "south"}]
	stage.pressure_pads = [{"id": "sluice-board", "surface_id": "quay", "position_cm": [-350, 300], "height_cm": 0, "radius_cm": 28}]
	stage.gates = [{"route_id": "ladder"}, {"route_id": "ferry", "when": {"item_id": "raft", "spot_id": "berth"}}]
	stage.current_legs = [
		{"from": "mooring", "to": "berth", "control_id": "current", "value": "north"},
		{"from": "eddy", "to": "landing", "control_id": "current", "value": "north", "stop": {"pad_id": "sluice-board"}},
	]
	stage.goal = {"id": "dock-goal", "surface_id": "dock", "position_cm": [-250, 0], "height_cm": 0, "radius_cm": 48}
	stage.goal_policy = {"kind": "ring", "when": {"item_id": "pipsport", "spot_id": "post"}}
	stage.receiver_route_cm = [[-250, 0]]
	return stage

# The catalog half Proof (core/physical/two_pair_proof.gd) asks of a catalog.

static func known(value: Dictionary) -> bool:
	return Canonical.same(value, definition())

static func initial_checkpoint(level: Dictionary) -> Dictionary:
	return JourneyCatalog.initial_checkpoint(level)

static func checkpoint_hash(checkpoint: Dictionary) -> String:
	return JourneyCatalog.checkpoint_hash(checkpoint)
