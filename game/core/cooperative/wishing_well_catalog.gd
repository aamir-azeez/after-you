extends RefCounted
## The Wishing Well: a free composition of the unchanged physical comfort rules,
## pinned to rules 9 (the comfort rules under a number 0.5.x never advertised).
## Garden 0 cm, cliff 160 cm, and a sunken well floor at 0 cm under the cliff's
## east lip. The friend who drops in holds the rope that opens both later routes.

static func definition() -> Dictionary:
	return {
		"schema_version": 6, "simulation_version": 9, "id": "the-wishing-well", "version": 1,
		"title": "The Wishing Well", "premium": false,
		"starts": {"p0": [-1216,200], "p1": [-1168,232]},
		"islands": [
			_island("garden", [-1280,144,1040,288], 0),
			_island("cliff", [-1280,-208,1232,-16], 160),
			_island("well-floor", [1120,-48,1200,48], 0),
			_island("rope-rock", [1376,-192,1424,-96], 160),
			_island("tower", [1568,-208,2816,48], 160)],
		"bridges": [
			_rope("rope-walk-west", [1232,-176,1376,-112], "cliff", "rope-rock"),
			_rope("rope-walk-east", [1424,-176,1568,-112], "rope-rock", "tower")],
		"stairs": [
			_stair("cliff-steps", [-1248,-16,-1184,144], "z", "cliff", "garden", 160, 0, "p0"),
			_stair("long-stair", [944,-16,1008,144], "z", "cliff", "garden", 160, 0, "p1"),
			_stair("well-ladder", [1200,-8,1568,40], "x", "well-floor", "tower", 0, 160, "p0")],
		# Every centre inside the mouth lands fully on the well floor below.
		"drops": [{"id": "well-mouth", "rect_cm": [1132,-36,1188,-28], "surface_id": "cliff",
			"destination_surface": "well-floor", "height_cm": 0, "requires_lever": ""}],
		"props": [],
		"obstacles": [
			_stone("standing-stone-1", [-448,-136,-384,-16]),
			_stone("standing-stone-2", [-64,-208,0,-88]),
			_stone("standing-stone-3", [320,-136,384,-16]),
			_stone("standing-stone-4", [704,-208,768,-88]),
			_bed("garden-bed-1", [-576,144,-512,224]),
			_bed("garden-bed-2", [-192,208,-128,288]),
			_bed("garden-bed-3", [192,144,256,224]),
			_bed("garden-bed-4", [576,208,640,288]),
			_drum("rope-drum-1", [1920,-208,1984,-64]),
			_drum("rope-drum-2", [2240,-112,2304,48])],
		# Only the friend who goes ahead may step onto the well's lip.
		"access_zones": [{"id": "well-lip", "rect_cm": [1104,-64,1216,-16], "surface_id": "cliff", "owner_slot": "p0"}],
		"stages": [_go_on_ahead(), _back_for_you()]}

static func _go_on_ahead() -> Dictionary:
	return {
		"id": "go-on-ahead", "version": 1, "title": "Go On Ahead", "first_player_slot": "p0", "kind": "hold_switch",
		"ball_pads": [],
		"levers": [_goal("garden-gate", [-1104,192], "garden", "p0")],
		# The whole well floor lies inside the rope's reach, wherever the friend stands.
		"pressure_pads": [_rope_pad("bucket-rope", [1160,0], "well-floor", "p0")],
		"gates": [
			{"route_id": "cliff-steps", "pad_id": "", "lever_id": "garden-gate", "ball_pad_id": ""},
			{"route_id": "long-stair", "pad_id": "bucket-rope", "lever_id": "", "ball_pad_id": ""}],
		"source_policy": {"kind": "hold_switch", "pad_id": "bucket-rope", "lever_id": "garden-gate", "minimum_hold_ticks": 15},
		"goal_policy": {"kind": "ring"}, "goal": _goal("lookout-bell", [1160,-96], "cliff", "p1"),
		"receiver_route_cm": [[-1168,180],[-608,180],[-608,256],[-224,256],[-224,180],[160,180],[160,256],[544,256],[544,180],[976,180],[976,-96],[1160,-96]],
		"receiver_action_ticks": 1,
		"hint_a": "Hop down and hold the rope.",
		"hint_b": "Go on ahead."}

static func _back_for_you() -> Dictionary:
	return {
		"id": "back-for-you", "version": 1, "title": "Back for You", "first_player_slot": "p1", "kind": "hold_switch",
		"ball_pads": [],
		"levers": [_goal("winch-lever", [2752,-144], "tower", "p1")],
		"pressure_pads": [
			# Same place and reach as yesterday's rope: the friend still holding it opens the rope-walk.
			_rope_pad("still-holding", [1160,0], "well-floor", "p0"),
			{"id": "tower-step", "position_cm": [1648,-48], "surface_id": "tower", "radius_cm": 32, "owner_slot": "p1"}],
		"gates": [
			{"route_id": "rope-walk-west", "pad_id": "still-holding", "lever_id": "", "ball_pad_id": ""},
			{"route_id": "rope-walk-west", "pad_id": "", "lever_id": "winch-lever", "ball_pad_id": ""},
			{"route_id": "rope-walk-east", "pad_id": "still-holding", "lever_id": "", "ball_pad_id": ""},
			{"route_id": "rope-walk-east", "pad_id": "", "lever_id": "winch-lever", "ball_pad_id": ""},
			{"route_id": "well-ladder", "pad_id": "", "lever_id": "winch-lever", "ball_pad_id": ""}],
		"source_policy": {"kind": "hold_switch", "pad_id": "tower-step", "lever_id": "winch-lever", "minimum_hold_ticks": 15},
		"goal_policy": {"kind": "ring"}, "goal": _goal("reunion-bell", [1616,16], "tower", "p0"),
		"receiver_route_cm": [[1180,16],[1592,16]],
		"receiver_action_ticks": 1,
		"hint_a": "They're still holding on. Bring the ladder down.",
		"hint_b": "Get out of the well and sound the bell."}

static func _island(id: String, rect: Array, height: int) -> Dictionary:
	return {"id": id, "rect_cm": rect, "height_cm": height}

static func _rope(id: String, rect: Array, from: String, to: String) -> Dictionary:
	return {"id": id, "rect_cm": rect, "from_surface": from, "to_surface": to, "height_cm": 160, "owner_slot": "p1"}

static func _stair(id: String, rect: Array, axis: String, from: String, to: String, from_height: int, to_height: int, owner: String) -> Dictionary:
	return {"id": id, "rect_cm": rect, "axis": axis, "from_surface": from, "to_surface": to, "from_height_cm": from_height, "to_height_cm": to_height, "owner_slot": owner}

static func _stone(id: String, rect: Array) -> Dictionary:
	return {"id": id, "rect_cm": rect, "surface_id": "cliff"}

static func _drum(id: String, rect: Array) -> Dictionary:
	return {"id": id, "rect_cm": rect, "surface_id": "tower"}

static func _bed(id: String, rect: Array) -> Dictionary:
	return {"id": id, "rect_cm": rect, "surface_id": "garden"}

static func _rope_pad(id: String, at: Array, surface: String, owner: String) -> Dictionary:
	return {"id": id, "position_cm": at, "surface_id": surface, "radius_cm": 48, "owner_slot": owner}

static func _goal(id: String, at: Array, surface: String, owner: String) -> Dictionary:
	return {"id": id, "position_cm": at, "surface_id": surface, "radius_cm": 28, "owner_slot": owner}
