extends RefCounted
## A tiny journey level written with puzzle blocks, for tests/test_block_defaults.gd:
## a step that holds the crossing open, a water switch that opens the ford,
## a lever that opens the back gate, and a bell across the water.
const Blocks = preload("res://core/blocks/stage_blocks.gd")

static func source() -> Dictionary:
	return {"schema_version": 7, "simulation_version": 7, "id": "block-yard", "version": 1, "title": "Block Yard", "premium": false,
		"starts": {"p0": {"position_cm": [100, 0], "height_cm": 0, "surface_id": "near"}, "p1": {"position_cm": [100, 120], "height_cm": 0, "surface_id": "near"}},
		"props": [],
		"islands": [{"id": "near", "rect_cm": [0, -200, 400, 200], "height_cm": 0}, {"id": "far", "rect_cm": [600, -200, 1000, 200], "height_cm": 0}],
		"stairs": [],
		"bridges": [
			{"id": "crossing", "rect_cm": [400, -48, 600, 48], "from_surface": "near", "to_surface": "far", "height_cm": 0, "owner_slot": ""},
			{"id": "ford", "rect_cm": [400, 112, 600, 176], "from_surface": "near", "to_surface": "far", "height_cm": 0, "owner_slot": ""},
			{"id": "back-gate", "rect_cm": [400, -176, 600, -112], "from_surface": "near", "to_surface": "far", "height_cm": 0, "owner_slot": ""}],
		"stages": [{"id": "the-yard", "version": 1, "title": "The Yard", "first_player_slot": "p0", "kind": "route_endpoint", "ball_pads": [],
			"blocks": [
				{"block": "hold_door", "pad": {"id": "step", "at": [200, 0], "surface": "near", "owner": "p0", "style": "stand_spot"}, "routes": ["crossing"]},
				{"block": "selector_gate", "selector": {"id": "sluice", "at": [300, 150], "surface": "near", "owner": "p0", "values": ["low", "high"], "initial": "low", "style": "valve", "water": true}, "routes": {"ford": "high"}},
				{"block": "relay_lever", "lever": {"id": "gate-chain", "at": [300, -150], "surface": "near", "owner": "p0", "style": "winch"}, "routes": ["back-gate"]},
				{"block": "ring_bell", "id": "bell", "at": [800, 0], "surface": "far", "owner": "p1", "style": "crest"}],
			"entry_latch_routes": [], "source_policy": {"kind": "route_endpoint", "when": {"pad_id": "step"}},
			"receiver_route_cm": [[100, 120], [800, 0]], "receiver_action_ticks": 1}]}

static func definition() -> Dictionary:
	return Blocks.expand(source())
