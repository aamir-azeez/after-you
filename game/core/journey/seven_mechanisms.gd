extends RefCounted
## Pure selectors and terminal-route predicates for authored simulation7.
## No shared mutable state: all dictionaries belong to a single simulation.
## `open`: open controls (runtime.gd OPEN_RULES_VERSION), where a pad holds for
## either pip; otherwise only for its owner_slot.

static func predicate(value: Dictionary, stage: Dictionary, players: Dictionary, mechanisms: Dictionary, signals: Dictionary = {}, open: bool = false) -> bool:
	if value.has("all"):
		for child: Dictionary in value.all:
			if not predicate(child, stage, players, mechanisms, signals, open): return false
		return true
	if value.has("any"):
		for child: Dictionary in value.any:
			if predicate(child, stage, players, mechanisms, signals, open): return true
		return false
	if value.has("control_id"): return str(mechanisms.controls.get(value.control_id, "")) == str(value.value)
	if value.has("lever_id"): return bool(mechanisms.levers.get(value.lever_id, false))
	if value.has("signal_id"): return bool(signals.get(value.signal_id, false))
	if value.has("pad_id"):
		for pad: Dictionary in stage.get("pressure_pads", []):
			if pad.id == value.pad_id: return held(players, pad, open)
		return false
	return value.is_empty()

static func near(player: Dictionary, target: Dictionary) -> bool:
	return player.surface_id == target.surface_id and int(player.height) == int(target.get("height_cm", 0)) and Vector2i(player.x,player.z).distance_squared_to(Vector2i(target.position_cm[0],target.position_cm[1])) <= int(target.radius_cm) ** 2

## Whether a pip holds `pad`: its owner, or under open controls either pip.
static func held(players: Dictionary, pad: Dictionary, open: bool = false) -> bool:
	if not open: return near(players[pad.owner_slot], pad)
	for slot: String in ["p0", "p1"]:
		if players.has(slot) and near(players[slot], pad): return true
	return false

## The first branch, in the policy's order, whose pad is held.
static func choice(stage: Dictionary, players: Dictionary, open: bool = false) -> Dictionary:
	for branch: Dictionary in stage.source_policy.get("branches", []):
		for pad: Dictionary in stage.get("pressure_pads", []):
			if pad.id == branch.pad_id and held(players, pad, open): return branch
	return {}
