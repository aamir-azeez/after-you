extends RefCounted
## A chapter's stages as the level tools see them (tests/level_tools/, the
## level checker suites): each stage's plan (services/level_layout.gd, the one
## layout function of its family, as the worlds and the dressing lint read it)
## and the checkpoint it opens from. Stage one opens from the chapter's initial
## checkpoint; a later stage from the checkpoint its fixtures leave after the
## stage before (tests/fixtures, written by the chapter suite), or {} when a
## chapter has none yet. Read only: nothing here writes a file.
const Registry = preload("res://services/chapter_registry.gd")
const Families = preload("res://services/chapter_families.gd")
const Layout = preload("res://services/level_layout.gd")
const Golden = preload("res://tests/golden_support.gd")
const OpenTurns = preload("res://core/physical/open_turns.gd")

## Whether the level tools can read the chapter: its family lays its stages
## out (services/chapter_families.gd "layout"). The checker fails a
## registered chapter that cannot.
static func laid_out(key: String) -> bool:
	return Layout.has_layout(Layout.family_of(key))

## [{index, stage (as authored), view (its plan), checkpoint (in the plan's
## terms: floor_checkpoint), opening (the engine's own, for a snapshot or a
## world's history)}] for every stage. `family` reads a layout no chapter
## registers yet (the key's own family when left out).
static func stages(key: String, level: Dictionary = {}, family: String = "") -> Array:
	if level.is_empty(): level = Registry.definition(key)
	if family.is_empty(): family = Layout.family_of(key)
	var result: Array = []
	for index in range(level.get("stages", []).size()):
		var stage: Dictionary = level.stages[index]
		var opening := checkpoint_before(key, level, index)
		result.append({"index": index, "stage": stage, "view": Layout.plan(family, level, str(stage.id)), "checkpoint": floor_checkpoint(opening), "opening": opening})
	return result

## The checkpoint stage `index` opens from, as its engine reads it: the
## registered chapter's initial one for the first stage (else one from the
## starts), the fixtures' for a later one, else {}.
static func checkpoint_before(key: String, level: Dictionary, index: int) -> Dictionary:
	if index == 0:
		var initial := Registry.initial_checkpoint(key) if key in Registry.keys() else {}
		return initial if not initial.is_empty() else starts_checkpoint(level)
	var prefixes := Golden.fixture_prefixes(key)
	if prefixes.is_empty(): return {}
	var named := Golden.fixture("%s%s-checkpoint.json" % [prefixes.stages, level.stages[index - 1].id])
	return named if not named.is_empty() else _fixture_opening(key, str(level.stages[index].id))

## A family whose fixtures name their checkpoints their own way: the first
## checkpoint in the family's fixture folder (by file name, a chain file's
## "checkpoints" too) that opens `stage_id` of this exact definition.
static func _fixture_opening(key: String, stage_id: String) -> Dictionary:
	var initial := Registry.initial_checkpoint(key)
	var folder := str(Families.row(Layout.family_of(key)).get("fixture_dir", ""))
	if initial.is_empty() or folder.is_empty(): return {}
	var files := Array(DirAccess.get_files_at("res://tests/fixtures/" + folder)).filter(func(file: String) -> bool: return file.ends_with(".json"))
	files.sort()
	for file: String in files:
		var value := Golden.fixture(folder.path_join(file))
		for candidate: Variant in [value] + value.get("checkpoints", []):
			if candidate is Dictionary and str(candidate.get("next_stage_id", "")) == stage_id and candidate.get("definition_hash") == initial.definition_hash: return candidate
	return {}

## `checkpoint` in the plan's terms, as the level graph and the map read it:
## {players: {slot: {x, z, height, surface_id}}, mechanisms (with the kept
## crossings in latched_bridges)}; {} for {}.
static func floor_checkpoint(checkpoint: Dictionary) -> Dictionary:
	if checkpoint.is_empty(): return {}
	var players: Dictionary = {}
	for slot: String in checkpoint.get("players", {}):
		var player: Dictionary = checkpoint.players[slot]
		players[slot] = {"x": int(player.x), "z": int(player.z), "height": int(player.get("height", 0)), "surface_id": str(player.get("surface_id", ""))}
	var mechanisms: Dictionary = checkpoint.get("mechanisms", {}).duplicate(true)
	if not mechanisms.has("latched_bridges"): mechanisms["latched_bridges"] = checkpoint.get("latched_bridges", []).duplicate()
	return {"players": players, "mechanisms": mechanisms}

## How many turns `stage` (as authored) may take on open turns, in words
## ("up to 10 turns"), or "" on the two-turn rules. The map, the preview and
## the playtest report all say it this way.
static func turns_label(level: Dictionary, stage: Dictionary) -> String:
	return "up to %d turns" % OpenTurns.cap(stage) if OpenTurns.pinned(level) else ""

## `text` with `stage`'s turns after it, when it has open turns.
static func with_turns(text: String, level: Dictionary, stage: Dictionary) -> String:
	var turns := turns_label(level, stage)
	return text if turns.is_empty() else "%s, %s" % [text, turns]

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
