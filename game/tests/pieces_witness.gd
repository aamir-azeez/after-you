extends RefCounted
## The new pieces' witness level (rules 20, core/physical/pieces_rules.gd),
## written with their blocks (core/blocks/stage_blocks.gd). Two small stages,
## all heights 0 or 96 cm:
##   "marsh": a landing and the stilts above it, joined by a weight lift (a pan
##     on the landing raises it, one on the stilts brings it down) and a
##     pull-up rope ladder; a rope raft from the landing over the water to the
##     isle, its rope wheel on the isle; the fog lantern on the stilts, whose
##     pump floods the low boards and drains the reed stones from the isle to
##     the jetty while it burns, and fills the lift's pan. A pan holds a pip
##     or the pipsport (carried items, train/new-pieces-carry). The goal is on
##     the stilts and wants the lantern lit.
##   "falls": the bank and the far bank joined by two sinking stones (dry at
##     pool LOW) and the path behind the falls (dry while the water gate lever
##     on the far bank is on); the rope bridge from the far bank to the cliff
##     is tight while someone stands on a crank board at either end. The wheel
##     ride carries a pip up from the bank to the loft while someone stands on
##     the water gate board. A footbridge from the cliff to the islet is down
##     while its pan is weighed, and a punt (a plain platform) crosses beside
##     it while someone stands on its call board.
## It is no chapter: tests play it through _reset_trusted with the memory trace
## off, and read it with the level graph (tests/test_pieces.gd).
const StageBlocks = preload("res://core/blocks/stage_blocks.gd")
const PiecesRules = preload("res://core/physical/pieces_rules.gd")
const CAPS := {"marsh": 10, "falls": 10}

static func definition() -> Dictionary:
	return PiecesRules.pin(StageBlocks.expand(source()), CAPS)

static func source() -> Dictionary:
	return {"schema_version": 7, "simulation_version": 9, "id": "pieces-witness", "version": 1, "premium": false, "closing_ticks": 30,
		"turn_limits": {"a_ticks": 3000, "b_ticks": 3000},
		"starts": {"p0": {"position_cm": [200, 200], "height_cm": 0, "surface_id": "landing"}, "p1": {"position_cm": [100, 850], "height_cm": 0, "surface_id": "isle"}},
		"props": [],
		"islands": [_island("landing", [0, 0, 400, 400], 0), _island("stilts", [500, 0, 900, 400], 96), _island("isle", [0, 700, 400, 1000], 0),
			_island("jetty", [500, 700, 900, 1000], 0), _island("bank", [0, 1200, 300, 1600], 0), _island("far", [460, 1200, 800, 1600], 0),
			_island("cliff", [900, 1200, 1200, 1600], 0), _island("loft", [0, 1700, 300, 2000], 96), _island("islet", [1400, 1300, 1600, 1500], 0)],
		"bridges": [_bridge("lift-low", [400, 150, 500, 250], 0, "landing", "stilts"), _bridge("lift-high", [400, 150, 500, 250], 96, "landing", "stilts"),
			_bridge("raft-north", [150, 400, 250, 480], 0, "landing", "isle"), _bridge("raft-south", [150, 620, 250, 700], 0, "landing", "isle"),
			_bridge("boards", [400, 800, 500, 900], 0, "isle", "jetty"), _bridge("reeds", [400, 920, 500, 980], 0, "isle", "jetty"),
			_bridge("s1", [300, 1300, 380, 1380], 0, "bank", "far"), _bridge("s2", [380, 1300, 460, 1380], 0, "bank", "far"),
			_bridge("behind", [300, 1460, 460, 1540], 0, "bank", "far"), _bridge("span", [800, 1350, 900, 1450], 0, "far", "cliff"),
			_bridge("foot", [1200, 1460, 1400, 1500], 0, "cliff", "islet"),
			_bridge("punt-a", [1200, 1350, 1260, 1420], 0, "cliff", "islet"), _bridge("punt-b", [1340, 1350, 1400, 1420], 0, "cliff", "islet")],
		"stairs": [{"id": "ladder", "rect_cm": [400, 300, 500, 400], "axis": "x", "from_surface": "landing", "to_surface": "stilts", "from_height_cm": 0, "to_height_cm": 96},
			{"id": "wheel", "rect_cm": [100, 1600, 200, 1700], "axis": "z", "from_surface": "bank", "to_surface": "loft", "from_height_cm": 0, "to_height_cm": 96}],
		"stages": [_marsh(), _falls()]}

static func _marsh() -> Dictionary:
	return {"id": "marsh", "version": 1, "first_player_slot": "p0", "kind": "route_endpoint", "controls": [], "levers": [], "pressure_pads": [], "ball_pads": [],
		"gates": [], "entry_latch_routes": [], "source_policy": {"kind": "route_endpoint", "when": {}}, "receiver_route_cm": [[700, 200]], "receiver_action_ticks": 2,
		"blocks": [
			{"block": "weight_lift", "id": "lift", "low": "lift-low", "high": "lift-high",
				"pads": [_spot("pan", [100, 100], "landing", 0)], "top_pads": [_spot("top-pan", [850, 50], "stilts", 96)],
				"items": ["pipsport"], "also": {"lever_id": "lantern"}},
			{"block": "rope_ladder", "stairs": ["ladder"]},
			{"block": "rope_raft", "id": "raft", "selector": _rope("rope", [300, 900], "isle"), "stops": {"NORTH": "raft-north", "SOUTH": "raft-south"}},
			{"block": "fog_lantern", "lever": _spot("lantern", [800, 300], "stilts", 96), "floods": {"boards": {}}, "drains": {"reeds": {}}},
			{"block": "ring_bell", "id": "lamp", "at": [700, 200], "surface": "stilts", "owner": "p1", "height": 96, "when": {"lever_id": "lantern"}}]}

static func _falls() -> Dictionary:
	return {"id": "falls", "version": 1, "first_player_slot": "p0", "kind": "route_endpoint", "controls": [], "levers": [], "pressure_pads": [], "ball_pads": [],
		"gates": [], "entry_latch_routes": [], "source_policy": {"kind": "route_endpoint", "when": {}}, "receiver_route_cm": [[1100, 1400]], "receiver_action_ticks": 2,
		"blocks": [
			{"block": "selector", "id": "pool", "at": [100, 1550], "surface": "bank", "owner": "p0", "values": ["HIGH", "LOW"], "initial": "HIGH", "water": true},
			{"block": "sinking_stones", "stones": ["s1", "s2"], "when": {"control_id": "pool", "value": "LOW"}},
			{"block": "falls_path", "lever": _spot("water-gate", [700, 1250], "far", 0), "routes": ["behind"]},
			{"block": "crank_bridge", "pads": [_spot("crank", [750, 1520], "far", 0), _spot("east-crank", [950, 1250], "cliff", 0)], "routes": ["span"]},
			{"block": "wheel_ride", "stairs": ["wheel"], "when": {"pad_id": "gate-board"}},
			{"block": "pad", "id": "gate-board", "at": [250, 1520], "surface": "bank", "owner": "p0", "style": "board"},
			{"block": "weight_pan", "pad": _spot("foot-pan", [1150, 1550], "cliff", 0), "items": ["pipsport"], "routes": ["foot"]},
			{"block": "pad", "id": "call", "at": [1150, 1250], "surface": "cliff", "owner": "p0"},
			{"block": "platform", "id": "punt", "stops": {"punt-a": {"not": {"pad_id": "call"}}, "punt-b": {"pad_id": "call"}}},
			{"block": "ring_bell", "id": "lamp", "at": [1100, 1400], "surface": "cliff", "owner": "p1"}]}

static func _island(id: String, rect: Array, height: int) -> Dictionary:
	return {"id": id, "rect_cm": rect, "height_cm": height}

static func _bridge(id: String, rect: Array, height: int, from: String, to: String) -> Dictionary:
	return {"id": id, "rect_cm": rect, "from_surface": from, "to_surface": to, "height_cm": height}

static func _spot(id: String, at: Array, surface: String, height: int) -> Dictionary:
	return {"id": id, "at": at, "surface": surface, "owner": "p0", "height": height}

static func _rope(id: String, at: Array, surface: String) -> Dictionary:
	return {"id": id, "at": at, "surface": surface, "owner": "p0", "height": 0, "values": ["NORTH", "SOUTH"], "initial": "NORTH"}
