extends RefCounted
## The Relay family's plan (services/level_layout.gd). Flat islands joined by
## bridges; a stage opens its own bridge while its first pip stands on the
## stage's plate (simulation_v2.gd _update_bridges), and keeps it once
## crossed. Each plate is worked by the first pip of the stage that names it;
## the pip who plays second catches the seed and brings it to the stage's
## socket, its goal.
const Layout = preload("res://services/level_layout.gd")

static func plan(level: Dictionary, stage_id: String) -> Dictionary:
	var stage: Dictionary = {}
	for item: Dictionary in level.stages:
		if str(item.id) == stage_id: stage = item
	var islands: Array = level.islands.map(func(island: Dictionary) -> Dictionary: return {"id": str(island.id), "rect_cm": island.rect_cm.duplicate(), "height_cm": int(island.get("height_cm", 0))})
	var users: Dictionary = {}
	for item: Dictionary in level.stages: users[str(item.plate_id)] = str(item.first_player_slot)
	var result := {
		"id": level.id, "stage_id": stage_id, "first_player_slot": str(stage.first_player_slot),
		"islands": islands,
		"bridges": level.bridges.map(func(bridge: Dictionary) -> Dictionary:
			var flat := bridge.duplicate(true)
			flat["height_cm"] = int(bridge.get("height_cm", 0))
			return flat),
		"gates": [{"route_id": str(stage.bridge_id), "pad_id": str(stage.plate_id)}],
		"pressure_pads": level.plates.map(func(item: Dictionary) -> Dictionary: return Layout.placed(item, islands, str(users.get(str(item.id), "")))),
		"sockets": level.sockets.duplicate(true),
		"landing": {"id": "seed-landing", "position_cm": stage.landing_cm.duplicate(), "radius_cm": 65, "surface_id": str(stage.landing_surface)},
		"goal_policy": {"kind": "ring"},
	}
	for socket: Dictionary in level.sockets:
		if str(socket.id) == str(stage.destination): result["goal"] = socket.duplicate(true)
	if level.stages.find(stage) == 0: result["starts"] = Layout.starts_on(level.starts, islands)
	return result
