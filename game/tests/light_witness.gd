extends RefCounted
## The light pieces' witness level (core/physical/light_pieces.gd), written
## with the light block (core/blocks/stage_blocks.gd) on rules 16. A quay and
## an isle joined by the span, all at height 0:
##   "pad": the harbour lamp shines while someone stands on the light pad, far
##     from the span; the quay mirror turned to slash sends its light north to
##     the span's receiver, which holds the span. The goal is on the isle.
##   "cradle": the lens rests in its cradle on the quay and lights the lens
##     lamp; the path selector steers the fixed mirror over the water north
##     (the north receiver lights the goal) or south (the south receiver holds
##     the span), or puts the lamp out. The lens may be carried to the isle's
##     shelf, where it lights nothing.
## It is no chapter: tests play it through _reset_trusted with the memory
## trace off and read it with the level graph (tests/test_light_pieces.gd).
const StageBlocks = preload("res://core/blocks/stage_blocks.gd")
const PiecesRules = preload("res://core/physical/pieces_rules.gd")
const CAPS := {"pad": 10, "cradle": 10}

static func definition() -> Dictionary:
	return PiecesRules.pin(StageBlocks.expand(source()), CAPS)

static func source() -> Dictionary:
	return {"schema_version": 7, "simulation_version": 9, "id": "light-witness", "version": 1, "premium": false, "closing_ticks": 30,
		"turn_limits": {"a_ticks": 1800, "b_ticks": 1800},
		"starts": {"p0": {"position_cm": [130, 340], "height_cm": 0, "surface_id": "quay"}, "p1": {"position_cm": [200, 340], "height_cm": 0, "surface_id": "quay"}},
		"props": [], "drops": [], "stairs": [],
		"items": [{"id": "lens", "at": "away"}],
		"item_spots": [{"id": "cradle", "surface_id": "quay", "position_cm": [200, 300], "height_cm": 0, "radius_cm": 32},
			{"id": "shelf", "surface_id": "isle", "position_cm": [900, 340], "height_cm": 0, "radius_cm": 32}],
		"islands": [{"id": "quay", "rect_cm": [0, 0, 400, 400], "height_cm": 0}, {"id": "isle", "rect_cm": [600, 0, 1000, 400], "height_cm": 0}],
		"bridges": [{"id": "span", "rect_cm": [400, 150, 600, 250], "from_surface": "quay", "to_surface": "isle", "height_cm": 0}],
		"stages": [_pad(), _cradle()]}

static func _pad() -> Dictionary:
	var stage := _stage("pad", "p0", [800, 200])
	stage.blocks = [
		{"block": "pad", "id": "light-pad", "at": [60, 340], "surface": "quay", "owner": "p0"},
		{"block": "light", "bounds": [-50, -50, 1050, 450],
			"lamps": [{"id": "harbour-lamp", "at": [60, 50], "facing": "east", "when": {"pad_id": "light-pad"}}],
			"mirrors": [{"id": "quay-mirror", "at": [300, 50], "surface": "quay", "owner": "p1", "initial": "backslash"}],
			"receivers": [{"id": "span-eye", "at": [300, 10]}],
			"routes": {"span": "span-eye"}},
		{"block": "ring_bell", "id": "isle-bell", "at": [800, 200], "surface": "isle", "owner": "p1"}]
	return stage

static func _cradle() -> Dictionary:
	var stage := _stage("cradle", "p1", [300, 340])
	stage.item_starts = {"lens": "cradle"}
	stage.blocks = [
		{"block": "light", "bounds": [-50, -50, 1050, 450],
			"lamps": [{"id": "lens-lamp", "at": [200, 100], "facing": "east", "when": {"item_id": "lens", "spot_id": "cradle"}}],
			"fixed_mirrors": [{"id": "steer", "at": [500, 100], "orientation": "backslash"}],
			"selectors": [{"id": "path", "at": [100, 200], "surface": "quay", "owner": "p0", "values": ["north", "south", "off"], "initial": "off",
				"optics": {"north": {"steer": {"orientation": "slash"}}, "south": {"steer": {"orientation": "backslash"}}, "off": {"lens-lamp": {"enabled": false}}}}],
			"receivers": [{"id": "north-eye", "at": [500, 20]}, {"id": "south-eye", "at": [500, 140]}],
			"routes": {"span": "south-eye"}},
		{"block": "ring_bell", "id": "quay-bell", "at": [300, 340], "surface": "quay", "owner": "p1", "when": {"signal_id": "north-eye"}}]
	return stage

static func _stage(id: String, first: String, goal: Array) -> Dictionary:
	return {"id": id, "version": 1, "first_player_slot": first, "kind": "route_endpoint", "controls": [], "levers": [], "pressure_pads": [], "ball_pads": [],
		"gates": [], "entry_latch_routes": [], "source_policy": {"kind": "route_endpoint", "when": {}}, "receiver_route_cm": [goal.duplicate()], "receiver_action_ticks": 2}
