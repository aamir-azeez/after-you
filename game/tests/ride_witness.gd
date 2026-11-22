extends RefCounted
## A small witness level for rules 20's friend's replay riding a platform
## (core/journey/simulation.gd _move_platforms). Never
## registered: tests/test_pieces.gd plays it through the journey engine and
## its proof with this script as its catalog, and keeps the server's copy
## (tests/fixtures/memory_rides/, read by backend/test/pieces-rules.test.ts).
##
##   landing (0 cm) --lift--> stilts (96 cm), and a pull-up rope ladder
##
## One stage, "lift": the lift stands high while its pan holds a pip or either
## of its levers is on, the winch on the landing or the crank inside the lift
## (no way down once wound). Both pips must reach the lamp on the stilts.
const StageBlocks = preload("res://core/blocks/stage_blocks.gd")
const PiecesRules = preload("res://core/physical/pieces_rules.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const JourneyCatalog = preload("res://core/journey/stage_catalog.gd")
const LAMP := [600, 200]

static func definition() -> Dictionary:
	return PiecesRules.pin(StageBlocks.expand(source()), {"lift": 4})

static func source() -> Dictionary:
	return {"schema_version": 7, "simulation_version": 9, "id": "ride-witness", "version": 1, "premium": false, "closing_ticks": 30,
		"turn_limits": {"a_ticks": 1200, "b_ticks": 1200},
		"starts": {"p0": {"position_cm": [200, 200], "height_cm": 0, "surface_id": "landing"}, "p1": {"position_cm": [300, 120], "height_cm": 0, "surface_id": "landing"}},
		"props": [],
		"islands": [{"id": "landing", "rect_cm": [0, 0, 400, 400], "height_cm": 0}, {"id": "stilts", "rect_cm": [500, 0, 900, 400], "height_cm": 96}],
		"bridges": [{"id": "lift-low", "rect_cm": [400, 150, 500, 250], "from_surface": "landing", "to_surface": "stilts", "height_cm": 0},
			{"id": "lift-high", "rect_cm": [400, 150, 500, 250], "from_surface": "landing", "to_surface": "stilts", "height_cm": 96}],
		"stairs": [{"id": "ladder", "rect_cm": [400, 300, 500, 400], "axis": "x", "from_surface": "landing", "to_surface": "stilts", "from_height_cm": 0, "to_height_cm": 96}],
		"stages": [{"id": "lift", "version": 1, "first_player_slot": "p0", "kind": "route_endpoint", "controls": [], "levers": [], "pressure_pads": [], "ball_pads": [],
			"gates": [], "entry_latch_routes": [], "source_policy": {"kind": "route_endpoint", "when": {}}, "receiver_route_cm": [LAMP], "receiver_action_ticks": 2,
			"blocks": [
				{"block": "lever", "id": "winch", "at": [300, 60], "surface": "landing", "owner": "p0"},
				{"block": "lever", "id": "crank", "at": [450, 200], "surface": "lift-low", "owner": "p0"},
				{"block": "weight_lift", "id": "lift", "low": "lift-low", "high": "lift-high",
					"pads": [{"id": "pan", "at": [60, 60], "surface": "landing", "owner": "p0", "height": 0}],
					"also": {"any": [{"lever_id": "winch"}, {"lever_id": "crank"}]}},
				{"block": "rope_ladder", "stairs": ["ladder"]},
				{"block": "ring_bell", "id": "lamp", "at": LAMP, "surface": "stilts", "owner": "p1", "height": 96, "radius": 40}]}]}

# The catalog half Proof (core/physical/two_pair_proof.gd) asks of a catalog.

static func known(value: Dictionary) -> bool:
	return Canonical.same(value, definition())

static func initial_checkpoint(level: Dictionary) -> Dictionary:
	return JourneyCatalog.initial_checkpoint(level)

static func checkpoint_hash(checkpoint: Dictionary) -> String:
	return JourneyCatalog.checkpoint_hash(checkpoint)
