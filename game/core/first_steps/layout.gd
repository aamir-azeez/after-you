extends RefCounted
## First Steps' plan (services/level_layout.gd). Two floors joined by the lift.
## On the stage that powers it, the lift is a ride from its bottom to its top
## (laid out as a stair) that only the pip playing second boards, running
## while the first pip holds the power pad (simulation.gd _update_lift); on a
## later stage it waits at the top, part of the upper floor. Each pad is
## worked by the first pip of the stage that names it; the pip who plays
## second rings the stage's bell or plants at its garden, its goal.
const Layout = preload("res://services/level_layout.gd")

static func plan(level: Dictionary, stage_id: String) -> Dictionary:
	var stage: Dictionary = {}
	for item: Dictionary in level.stages:
		if str(item.id) == stage_id: stage = item
	var islands: Array = level.islands.duplicate(true)
	var lift: Dictionary = level.lift
	var users: Dictionary = {}
	for item: Dictionary in level.stages:
		for field: String in ["power_control", "throw_control", "garden_control"]:
			if item.has(field): users[str(item[field])] = str(item.first_player_slot)
	var result := {
		"id": level.id, "stage_id": stage_id, "first_player_slot": str(stage.first_player_slot),
		"islands": islands, "bridges": [], "stairs": [],
		"pressure_pads": level.controls.map(func(item: Dictionary) -> Dictionary: return Layout.placed(item, islands, str(users.get(str(item.id), "")))),
		"sockets": level.sockets.duplicate(true), "goals": level.goals.duplicate(true),
		"goal_policy": {"kind": "ring"},
	}
	var route := {"id": str(lift.id), "rect_cm": lift.rect_cm.duplicate(), "from_surface": str(lift.from_surface), "to_surface": str(lift.to_surface)}
	if stage.has("power_control"):
		route.merge({"axis": "x", "from_height_cm": int(lift.bottom_height_cm), "to_height_cm": int(lift.top_height_cm), "owner_slot": Layout.second_slot(stage)})
		result.stairs.append(route)
		result["gates"] = [{"route_id": str(lift.id), "pad_id": str(stage.power_control)}]
	else:
		route["height_cm"] = int(lift.top_height_cm)
		result.bridges.append(route)
		result["gates"] = [{"route_id": str(lift.id)}]
	var goal_id := str(stage.get("goal_id", stage.get("destination", "")))
	for goal: Dictionary in level.goals + level.sockets:
		if str(goal.id) == goal_id: result["goal"] = goal.duplicate(true)
	if stage.has("landing_cm"):
		result["landing"] = {"id": "seed-landing", "position_cm": stage.landing_cm.duplicate(), "radius_cm": 66, "surface_id": str(stage.landing_surface)}
	if level.stages.find(stage) == 0: result["starts"] = Layout.starts_on(level.starts, islands)
	return result
