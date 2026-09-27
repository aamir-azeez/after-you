extends RefCounted
## A new composition of the unchanged simulation-6 physical rules.
## Existing chapters retain their definitions and deterministic rules.

static func definition() -> Dictionary:
	return {
		"schema_version": 6, "simulation_version": 6, "id": "a-house-for-two", "version": 1,
		"title": "A House for Two", "premium": true,
		"starts": {"p0": [-528,112], "p1": [-528,-112]},
		"islands": [
			_island("foyer", [-640,-256,-192,256], 0),
			_island("workshop", [-128,-256,192,256], 0),
			_island("loft", [384,-256,704,256], 160),
			_island("lower-hall", [384,-256,704,256], 0),
			_island("sunroom", [768,-256,1152,256], 0)],
		"bridges": [
			_bridge("workshop-entry", [-192,64,-128,160], "foyer", "workshop", "p0"),
			_bridge("workshop-return", [-192,-160,-128,-64], "foyer", "workshop"),
			_bridge("lower-hall-passage", [192,-48,384,48], "workshop", "lower-hall"),
			_bridge("sunroom-entry", [704,-48,768,48], "lower-hall", "sunroom")],
		"stairs": [{"id": "loft-stairs", "rect_cm": [192,-160,384,-64], "axis": "x",
			"from_surface": "workshop", "to_surface": "loft", "from_height_cm": 0, "to_height_cm": 160, "owner_slot": "p1"}],
		"drops": [{"id": "loft-hatch", "rect_cm": [464,64,528,128], "surface_id": "loft",
			"destination_surface": "lower-hall", "height_cm": 0, "requires_lever": "loft-lever"}],
		"props": [{"id": "house-ball", "kind": "ball", "position_cm": [-448,112], "surface_id": "foyer", "radius_cm": 20}],
		"obstacles": [{"id": "workshop-bench", "rect_cm": [-16,-16,80,80], "surface_id": "workshop"}],
		"stages": [_open_house(), _room_below()]}

static func _open_house() -> Dictionary:
	return {
		"id": "open-the-house", "version": 1, "title": "Open the House", "first_player_slot": "p0", "kind": "weight_switch",
		"pressure_pads": [],
		"ball_pads": [_ball_pad("entry-weight", [-288,112], "foyer"), _ball_pad("stair-weight", [-352,-112], "foyer")],
		"levers": [_goal("workshop-lever", [32,144], "workshop", "p0")],
		"gates": [
			_gate("workshop-entry", "entry-weight"),
			_gate("workshop-entry", "", "workshop-lever"),
			_gate("workshop-return", "", "workshop-lever"),
			_gate("loft-stairs", "stair-weight", "workshop-lever")],
		"source_policy": {"kind": "weight_switch", "ball_pad_id": "stair-weight", "prop_id": "house-ball",
			"lever_id": "workshop-lever", "minimum_hold_ticks": 15},
		"goal_policy": {"kind": "ring"}, "goal": _goal("loft-bell", [576,-128], "loft", "p1"),
		"receiver_route_cm": [[-528,-112],[-528,-192],[-240,-192],[-240,-112],[128,-112],[576,-112],[576,-128]],
		"receiver_action_ticks": 1,
		"hint_a": "There's more than one way through the workshop.",
		"hint_b": "Go to the bell in the loft."}

static func _room_below() -> Dictionary:
	return {
		"id": "the-room-below", "version": 1, "title": "The Room Below", "first_player_slot": "p1", "kind": "offer_ball",
		"pressure_pads": [], "ball_pads": [_ball_pad("sunroom-weight", [592,0], "lower-hall")],
		"levers": [_goal("loft-lever", [560,80], "loft", "p1")],
		"gates": [_gate("lower-hall-passage", "", "loft-lever"), _gate("sunroom-entry", "sunroom-weight")],
		"source_policy": {"kind": "offer_ball", "prop_id": "house-ball", "lever_id": "loft-lever", "release_socket_id": "lower-hall-handoff"},
		"handoff": {"id": "lower-hall-handoff", "position_cm": [464,0], "surface_id": "lower-hall", "radius_cm": 36, "owner_slot": "p1"},
		"goal_policy": {"kind": "ring"}, "goal": _goal("sunroom-bell", [960,112], "sunroom", "p0"),
		"receiver_route_cm": [[416,0],[560,0],[560,96],[656,96],[656,0],[960,0],[960,112]],
		"receiver_action_ticks": 2,
		"hint_a": "Look for a way down and retrieve the ball.",
		"hint_b": "Open the sunroom."}

static func _island(id: String, rect: Array, height: int) -> Dictionary:
	return {"id": id, "rect_cm": rect, "height_cm": height}

static func _bridge(id: String, rect: Array, from: String, to: String, owner: String = "") -> Dictionary:
	return {"id": id, "rect_cm": rect, "from_surface": from, "to_surface": to, "height_cm": 0, "owner_slot": owner}

static func _ball_pad(id: String, at: Array, surface: String) -> Dictionary:
	return {"id": id, "position_cm": at, "surface_id": surface, "radius_cm": 36, "prop_id": "house-ball"}

static func _goal(id: String, at: Array, surface: String, owner: String) -> Dictionary:
	return {"id": id, "position_cm": at, "surface_id": surface, "radius_cm": 28, "owner_slot": owner}

static func _gate(route: String, pad: String = "", lever: String = "") -> Dictionary:
	return {"route_id": route, "pad_id": "", "ball_pad_id": pad, "lever_id": lever}
