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
##   piece_styles  the "style" a pad, lever, selector or bell names, pinned to
##                 that piece (content/dressing/piece_styles.gd); a piece that
##                 names none takes the dressing's or theme's pick. A lever's or
##                 selector's sounds follow its style (services/sound_cues.gd LOOK_CUES)
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
	# Cooperative only, and cooperative hints are the hashed definition's: no words.
	"weight_pad": {"cues": ["bridge_opened"]},
	"one_way_drop": {"cues": ["seed_landed"], "hint_b": PlayerCopy.BLOCK_ONE_WAY_DROP_HINT_B},
	"ring_bell": {"cues": ["bell_rung"], "hint_b": PlayerCopy.BLOCK_RING_BELL_HINT_B},
	"pad": {"cues": []},
	"lever": {"cues": ["lever_pulled"]},
	"selector": {"cues": ["switch_set"]},
	"raw": {"cues": []},
}
## Fields a block may give a piece, read here only: never part of the
## expanded definition, so a style never changes a hash.
const LOOK_FIELDS := ["style", "water"]

## Fills the descriptor `data` in place from its block source; does nothing
## without one. Only fields still at their empty default are filled.
static func fill(data: Dictionary) -> void:
	var source := source_of(data)
	if source.is_empty(): return
	var copy := stage_copy(source)
	if Families.row(str(data.get("family", ""))).get("stage_hud", "") == "stage_copy":
		data.stage_copy = _over(copy, data.stage_copy)
	data.piece_styles = _over(styles(source), data.piece_styles)
	data.water_levels = _over(water_levels(source), data.water_levels)

## The block source a descriptor names, or {}. It must be a method of the
## chapter's own definition catalog, so the index only ever loads a script
## the registry loads anyway.
static func source_of(data: Dictionary) -> Dictionary:
	var named: Array = data.get("block_source", [])
	var catalog: Array = data.get("definition", [])
	if named.size() < 2 or catalog.is_empty() or str(named[0]) != str(catalog[0]): return {}
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

## Stage ids the defaults give no stage copy, because their blocks offer no
## first or no second turn hint: the descriptor must write those itself.
static func missing_copy(source: Dictionary) -> Array:
	var copied := stage_copy(source)
	var missing: Array = []
	for stage: Dictionary in source.get("stages", []):
		if not copied.has(str(stage.id)): missing.append(str(stage.id))
	return missing

## {piece id: style} from every pad, lever, selector and bell a block places
## that names a "style".
static func styles(source: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for spec: Dictionary in _pieces(source):
		if spec.has("style"): result[str(spec.id)] = str(spec.style)
	return result

## {selector id: its values in order} for selector blocks marked as water.
static func water_levels(source: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for spec: Dictionary in _controls(source):
		if bool(spec.get("water", false)) and spec.has("values"): result[str(spec.id)] = spec.values.duplicate()
	return result

## Every lever and selector placed by a block, standalone or inline.
static func _controls(source: Dictionary) -> Array:
	return _placed(source, ["lever", "selector"], ["lever", "second_lever", "selector", "matches"])

## Every pad, lever, selector and bell placed by a block, standalone or inline.
static func _pieces(source: Dictionary) -> Array:
	return _placed(source, ["pad", "lever", "selector", "ring_bell"], ["pad", "lever", "second_lever", "selector", "matches"])

## Blocks named `blocks` themselves, and the inline pieces in `fields` of any block.
static func _placed(source: Dictionary, blocks: Array, fields: Array) -> Array:
	var found: Array = []
	for stage: Dictionary in source.get("stages", []):
		for block: Dictionary in stage.get("blocks", []):
			if str(block.get("block", "")) in blocks: found.append(block)
			for field: String in fields:
				if block.get(field) is Dictionary: found.append(block[field])
	return found

## `defaults` with `given` over it, key by key.
static func _over(defaults: Dictionary, given: Dictionary) -> Dictionary:
	var result: Dictionary = defaults.duplicate(true)
	result.merge(given, true)
	return result
