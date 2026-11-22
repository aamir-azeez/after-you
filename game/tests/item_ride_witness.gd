extends RefCounted
## A small witness level for rules 20's items riding platforms
## (core/physical/carried_items.gd lay, core/journey/simulation.gd
## _move_platforms). Never registered: tests/test_carried_items.gd plays it
## through the journey engine and its proof with this script as its catalog,
## and keeps the server's copy (tests/fixtures/item_rides/, read by
## backend/test/carried-items.test.ts).
##
##   isle (0 cm) --raft-- landing (0 cm) --lift--> stilts (96 cm), and a pull-up rope ladder
##
## One stage, "home": p0 starts on the landing holding the pipsport, p1 on the
## stilts. The lift stands high while its pan on the landing holds a pip or the
## pipsport; the rope ladder needs both hands. The raft lies at the landing
## until its rope wheel on the isle pulls it over. Both pips must reach the lamp
## on the stilts.
const StageBlocks = preload("res://core/blocks/stage_blocks.gd")
const PiecesRules = preload("res://core/physical/pieces_rules.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const JourneyCatalog = preload("res://core/journey/stage_catalog.gd")
const LAMP := [700, 200]
const PAN := [60, 60]
const ROPE := [300, 900]

static func definition() -> Dictionary:
	return PiecesRules.pin(StageBlocks.expand(source()), {"home": 4})

static func source() -> Dictionary:
	return {"schema_version": 7, "simulation_version": 9, "id": "item-ride-witness", "version": 1, "premium": false, "closing_ticks": 30,
		"turn_limits": {"a_ticks": 1200, "b_ticks": 1200},
		"starts": {"p0": {"position_cm": [200, 200], "height_cm": 0, "surface_id": "landing"}, "p1": {"position_cm": [700, 100], "height_cm": 96, "surface_id": "stilts"}},
		"props": [],
		"items": [{"id": "pipsport", "at": "p0"}],
		"item_spots": [{"id": "pan", "surface_id": "landing", "position_cm": PAN, "height_cm": 0}],
		"islands": [{"id": "landing", "rect_cm": [0, 0, 400, 400], "height_cm": 0}, {"id": "stilts", "rect_cm": [500, 0, 900, 400], "height_cm": 96},
			{"id": "isle", "rect_cm": [0, 700, 400, 1000], "height_cm": 0}],
		"bridges": [{"id": "lift-low", "rect_cm": [400, 150, 500, 250], "from_surface": "landing", "to_surface": "stilts", "height_cm": 0},
			{"id": "lift-high", "rect_cm": [400, 150, 500, 250], "from_surface": "landing", "to_surface": "stilts", "height_cm": 96},
			{"id": "raft-north", "rect_cm": [150, 400, 250, 480], "from_surface": "landing", "to_surface": "isle", "height_cm": 0},
			{"id": "raft-south", "rect_cm": [150, 620, 250, 700], "from_surface": "landing", "to_surface": "isle", "height_cm": 0}],
		"stairs": [{"id": "ladder", "rect_cm": [400, 300, 500, 400], "axis": "x", "from_surface": "landing", "to_surface": "stilts", "from_height_cm": 0, "to_height_cm": 96}],
		"stages": [{"id": "home", "version": 1, "first_player_slot": "p0", "kind": "route_endpoint", "controls": [], "levers": [], "pressure_pads": [], "ball_pads": [],
			"gates": [], "entry_latch_routes": [], "source_policy": {"kind": "route_endpoint", "when": {}}, "receiver_route_cm": [LAMP], "receiver_action_ticks": 2,
			"blocks": [
				{"block": "weight_lift", "id": "lift", "low": "lift-low", "high": "lift-high",
					"pads": [{"id": "pan", "at": PAN, "surface": "landing", "owner": "p0", "height": 0}], "items": ["pipsport"]},
				{"block": "rope_ladder", "stairs": ["ladder"]},
				{"block": "rope_raft", "id": "raft", "selector": {"id": "rope", "at": ROPE, "surface": "isle", "owner": "p0", "height": 0, "values": ["NORTH", "SOUTH"], "initial": "NORTH"},
					"stops": {"NORTH": "raft-north", "SOUTH": "raft-south"}},
				{"block": "ring_bell", "id": "lamp", "at": LAMP, "surface": "stilts", "owner": "p1", "height": 96, "radius": 40}]}]}

# The catalog half Proof (core/physical/two_pair_proof.gd) asks of a catalog.

static func known(value: Dictionary) -> bool:
	return Canonical.same(value, definition())

static func initial_checkpoint(level: Dictionary) -> Dictionary:
	return JourneyCatalog.initial_checkpoint(level)

static func checkpoint_hash(checkpoint: Dictionary) -> String:
	return JourneyCatalog.checkpoint_hash(checkpoint)
