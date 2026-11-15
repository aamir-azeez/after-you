extends RefCounted
## The Lighthouse room's plan (services/level_layout.gd), from each stage's
## native definition (room_catalog.gd embeds them). Flat islands joined by
## bridges: a bridge with a receiver opens while light reaches it, one with a
## prop gate once the prop is fitted (a gate with no key: something the pips
## can always bring about), and one with neither only stays open as an earlier
## stage left it. Mirrors and selectors are its controls, the light pad and
## hold pads its pads, each worked by its own owner_slot.
const Layout = preload("res://services/level_layout.gd")

static func plan(level: Dictionary, stage_id: String) -> Dictionary:
	var native: Dictionary = {}
	for item: Dictionary in level.stages:
		if str(item.id) == stage_id: native = item.native
	var islands: Array = native.islands.duplicate(true)
	var result := native.duplicate(true)
	result.merge({"id": level.id, "stage_id": stage_id, "first_player_slot": str(native.first_player_slot), "islands": islands}, true)
	result["bridges"] = native.bridges.map(func(bridge: Dictionary) -> Dictionary:
		var flat := bridge.duplicate(true)
		flat["height_cm"] = int(bridge.get("height_cm", 0))
		return flat)
	result["gates"] = native.bridges.filter(func(bridge: Dictionary) -> bool: return not str(bridge.get("receiver_id", "")).is_empty() or bridge.has("prop_gate")).map(func(bridge: Dictionary) -> Dictionary: return {"route_id": str(bridge.id)})
	var controls: Array = native.get("controls", [])
	if native.has("mirror_control"): controls = [_with(native.mirror_control, {"kind": "mirror"})]
	result.erase("mirror_control")
	result["controls"] = controls.map(func(item: Dictionary) -> Dictionary: return Layout.placed(item, islands))
	var pads: Array = native.get("hold_pads", []).duplicate(true)
	if native.has("plate"): pads.push_front(native.plate)
	result.erase("plate")
	result.erase("hold_pads")
	result["pressure_pads"] = pads.map(func(item: Dictionary) -> Dictionary: return Layout.placed(item, islands))
	if native.has("goal"): result["goal"] = Layout.placed(native.goal, islands)
	if not native.has("goal_policy"): result["goal_policy"] = {"kind": "ring"}
	if native.has("starts"): result["starts"] = Layout.starts_on(native.starts, islands)
	return result

static func _with(entity: Dictionary, extra: Dictionary) -> Dictionary:
	var result := entity.duplicate(true)
	result.merge(extra)
	return result
