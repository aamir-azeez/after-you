extends RefCounted
## Open turns (open_controls.gd OPEN_TURNS_RULES: 14 is the comfort rules with
## open controls and open turns, 15 the tide rules with both). A stage no
## longer has exactly two turns: it ends when its goal holds at the end of a
## turn, otherwise play passes back to the other pip, up to the stage's own
## cap ("turn_cap", set in the level). Every turn has the level's time limit.
## The level checker (tests/test_level_checker.gd) asks that no stage can be
## finished by one pip alone, whichever pip, across any number of its own turns
## while the other does nothing.
## Shared by the engines, the catalogs and the level tools. It preloads only
## open_controls.gd, so a catalog may preload it.
const OpenControls = preload("res://core/physical/open_controls.gd")
const RULES := OpenControls.OPEN_TURNS_RULES
## A stage with no "turn_cap" gets this many turns.
const DEFAULT_CAP := 10
## The caps a level may set: two turns at least (the old shape), twenty at most.
const MIN_CAP := 2
const MAX_CAP := 20

## The open turns rules that keep `earlier`'s other rules: the tide rules as
## 15, anything else as 14.
static func rules_for(earlier: int) -> int:
	if earlier in RULES: return earlier
	return OpenControls.OPEN_TURNS_TIDE_RULES_VERSION if earlier in OpenControls.TIDE_RULES else OpenControls.OPEN_TURNS_RULES_VERSION

## `level` on open controls and open turns, each stage's cap from `caps`
## ({stage id: turns}; a stage left out keeps DEFAULT_CAP). Changes and
## returns `level`.
static func pin(level: Dictionary, caps: Dictionary) -> Dictionary:
	var earlier := int(level.get("simulation_version", 0))
	OpenControls.pin(level)
	level.simulation_version = rules_for(earlier)
	for stage: Dictionary in level.get("stages", []):
		if caps.has(stage.id): stage.turn_cap = int(caps[stage.id])
	return level

## Whether `definition` pins open turns.
static func pinned(definition: Dictionary) -> bool:
	var declared: Variant = definition.get("simulation_version")
	return (declared is int or declared is float) and int(declared) in RULES

## The most turns `stage` may take.
static func cap(stage: Dictionary) -> int:
	var declared: Variant = stage.get("turn_cap", DEFAULT_CAP)
	return int(declared) if declared is int or declared is float else DEFAULT_CAP

## The pips that may light `stage`'s goal on a turn after the first: the
## goal's own pip (its owner_slot), the one who plays second. The first pip
## plays turns 1, 3, 5 and so on, so with the goal open to it the first pip
## could finish a stage alone while the other passed.
static func ringers(stage: Dictionary) -> Array:
	var owner := str(stage.get("goal", {}).get("owner_slot", ""))
	return [owner] if owner in ["p0", "p1"] else ["p0", "p1"]

## Whether `stage`'s cap is one a level may set: even, so the last turn is
## the goal's own pip's and can still finish the stage.
static func cap_valid(stage: Dictionary) -> bool:
	var declared: Variant = stage.get("turn_cap", DEFAULT_CAP)
	return (declared is int or (declared is float and declared == floor(declared))) and int(declared) >= MIN_CAP and int(declared) <= MAX_CAP and int(declared) % 2 == 0
