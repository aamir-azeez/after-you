extends RefCounted
## What each puzzle block (core/blocks/stage_blocks.gd) brings with it besides
## its definition data: the cues the shared sound map already plays for it,
## its default hint words, and the look, water and hint fields it gives a
## chapter descriptor that leaves them out. Nothing here is hashed.
##
## A descriptor opts in with "block_source": [catalog script, static method],
## the chapter's definition written with blocks before StageBlocks.expand().
## content/chapters/index.gd then fills, only where the descriptor gives none:
##   stage_copy    for a family whose stage HUD reads it (journey): each stage's
##                 title from its definition, the first turn's hint from the
##                 first block that has one and the second turn's from the last
##   lever_looks   a lever or selector block's "look" (kit/lever_looks.gd), whose
##                 sounds follow (services/sound_cues.gd LOOK_CUES)
##   water_levels  a selector block with "water": true, its values in order
## A cooperative chapter's hints are its hashed definition's, so it gets none.

const PlayerCopy = preload("res://presentation/player_copy.gd")
const Families = preload("res://services/chapter_families.gd")

## Block -> {"cues": what services/chapter_sound_map.gd plays for it with no
## chapter override, "hint_a"/"hint_b": PlayerCopy defaults}.
const BLOCKS := {
	"open_route": {"cues": []},
	"hold_door": {"cues": ["bridge_opened", "bridge_closed"], "hint_a": PlayerCopy.BLOCK_HOLD_DOOR_HINT_A, "hint_b": PlayerCopy.WISHING_WELL_AHEAD_HINT_B},
	"relay_lever": {"cues": ["lever_pulled", "bridge_opened"], "hint_a": PlayerCopy.BLOCK_RELAY_LEVER_HINT_A, "hint_b": PlayerCopy.WISHING_WELL_AHEAD_HINT_B},
	"selector_gate": {"cues": ["switch_set", "bridge_opened"], "hint_a": PlayerCopy.BLOCK_SELECTOR_GATE_HINT_A, "hint_b": PlayerCopy.WISHING_WELL_AHEAD_HINT_B},
	"match_selectors": {"cues": ["switch_set", "bridge_opened"], "hint_b": PlayerCopy.BLOCK_MATCH_SELECTORS_HINT_B},
	"weight_pad": {"cues": ["bridge_opened"], "hint_a": PlayerCopy.BLOCK_WEIGHT_PAD_HINT_A, "hint_b": PlayerCopy.WISHING_WELL_AHEAD_HINT_B},
	"one_way_drop": {"cues": ["seed_landed"], "hint_b": PlayerCopy.BLOCK_ONE_WAY_DROP_HINT_B},
	"ring_bell": {"cues": ["bell_rung"], "hint_b": PlayerCopy.BLOCK_RING_BELL_HINT_B},
	"pad": {"cues": []},
	"lever": {"cues": ["lever_pulled"]},
	"selector": {"cues": ["switch_set"]},
	"raw": {"cues": []},
}
## Fields a block may give a lever or selector, read here only.
const LOOK_FIELDS := ["look", "water"]

## Fills the descriptor `data` in place from its block source; does nothing
## without one. Only fields still at their empty default are filled.
static func fill(data: Dictionary) -> void:
	var source := source_of(data)
	if source.is_empty(): return
	var copy := stage_copy(source)
	if Families.row(str(data.get("family", ""))).get("stage_hud", "") == "stage_copy":
		data.stage_copy = _over(copy, data.stage_copy)
	data.lever_looks = _over(looks(source), data.lever_looks)
	data.water_levels = _over(water_levels(source), data.water_levels)

## The block source a descriptor names, or {}.
static func source_of(data: Dictionary) -> Dictionary:
	var named: Array = data.get("block_source", [])
	if named.size() < 2: return {}
	var made: Variant = load(str(named[0])).callv(str(named[1]), named.slice(2))
	return made if made is Dictionary else {}

## {stage id: {title, hint_a, hint_b}} from each stage's blocks.
static func stage_copy(source: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for stage: Dictionary in source.get("stages", []):
		var hint_a := ""
		var hint_b := ""
		for block: Dictionary in stage.get("blocks", []):
			var row: Dictionary = BLOCKS.get(str(block.get("block", "")), {})
			if hint_a.is_empty(): hint_a = str(row.get("hint_a", ""))
			if row.has("hint_b"): hint_b = str(row.hint_b)
		if stage.has("title") and not hint_a.is_empty() and not hint_b.is_empty():
			result[str(stage.id)] = {"title": str(stage.title), "hint_a": hint_a, "hint_b": hint_b}
	return result

## {control id: look} from lever and selector blocks that name one.
static func looks(source: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for spec: Dictionary in _controls(source):
		if spec.has("look"): result[str(spec.id)] = str(spec.look)
	return result

## {selector id: its values in order} for selector blocks marked as water.
static func water_levels(source: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for spec: Dictionary in _controls(source):
		if bool(spec.get("water", false)) and spec.has("values"): result[str(spec.id)] = spec.values.duplicate()
	return result

## Every lever and selector placed by a block, standalone or inline.
static func _controls(source: Dictionary) -> Array:
	var found: Array = []
	for stage: Dictionary in source.get("stages", []):
		for block: Dictionary in stage.get("blocks", []):
			if str(block.get("block", "")) in ["lever", "selector"]: found.append(block)
			for field: String in ["lever", "second_lever", "selector", "matches"]:
				if block.get(field) is Dictionary: found.append(block[field])
	return found

## `defaults` with `given` over it, key by key.
static func _over(defaults: Dictionary, given: Dictionary) -> Dictionary:
	var result: Dictionary = defaults.duplicate(true)
	result.merge(given, true)
	return result
