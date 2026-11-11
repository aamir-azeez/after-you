extends RefCounted
## A chapter's stages as the level tools see them (tests/level_tools/, the
## level checker suites): each stage's merged view (the level with the stage's
## fields over it, as the worlds and the dressing lint read it) and the
## checkpoint it opens from. Stage one opens from the chapter's initial
## checkpoint; a later stage from the checkpoint its fixtures leave after the
## stage before (tests/fixtures, written by the chapter suite), or {} when a
## chapter has none yet. Read only: nothing here writes a file.
const Registry = preload("res://services/chapter_registry.gd")
const Golden = preload("res://tests/golden_support.gd")
const CooperativeCatalog = preload("res://core/cooperative/stage_catalog.gd")

## Chapters laid out as floors and crossings (the cooperative and journey
## families): every level tool reads these. The others are listed in
## NOT_FLOOR_FAMILIES with why.
static func floor_chapter(key: String) -> bool:
	return Registry.is_cooperative(key)

## Families with no floors-and-crossings layout, and what they have instead.
const NOT_FLOOR_FAMILIES := {
	"relay": "two fixed islands and a seed throw, no floors or gates to check",
	"first-steps": "one tutorial plate and landing, no floors or gates to check",
	"lighthouse-room": "beam puzzles in one room, checked by its own proof suites",
}

## [{index, stage (as authored), view (merged), checkpoint}] for every stage.
static func stages(key: String, level: Dictionary = {}) -> Array:
	if level.is_empty(): level = Registry.definition(key)
	var result: Array = []
	for index in range(level.get("stages", []).size()):
		var stage: Dictionary = level.stages[index]
		result.append({"index": index, "stage": stage, "view": CooperativeCatalog.stage_definition(level, str(stage.id)), "checkpoint": checkpoint_before(key, level, index)})
	return result

## The checkpoint stage `index` opens from: the registered chapter's initial
## one for the first stage (else one from the starts), the fixtures' for a
## later one, else {}.
static func checkpoint_before(key: String, level: Dictionary, index: int) -> Dictionary:
	if index == 0:
		var initial := Registry.initial_checkpoint(key) if key in Registry.keys() else {}
		return initial if not initial.is_empty() else starts_checkpoint(level)
	var prefixes := Golden.fixture_prefixes(key)
	if prefixes.is_empty(): return {}
	return Golden.fixture("%s%s-checkpoint.json" % [prefixes.stages, level.stages[index - 1].id])

## A stand-in first checkpoint from the definition's own starts, for a layout
## no chapter has registered yet (players on their start floors, nothing kept).
static func starts_checkpoint(level: Dictionary) -> Dictionary:
	var players: Dictionary = {}
	var starts: Dictionary = level.get("starts", {})
	for slot: String in starts:
		var start: Variant = starts[slot]
		if start is Dictionary:
			players[slot] = {"x": int(start.position_cm[0]), "z": int(start.position_cm[1]), "height": int(start.get("height_cm", 0)), "surface_id": str(start.get("surface_id", ""))}
		elif start is Array and not level.get("islands", []).is_empty():
			players[slot] = {"x": int(start[0]), "z": int(start[1]), "height": 0, "surface_id": str(level.islands[0].id)}
	return {"players": players, "mechanisms": {"latched_bridges": [], "levers": {}, "controls": {}}}
