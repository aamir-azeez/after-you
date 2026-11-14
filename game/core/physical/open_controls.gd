extends RefCounted
## Open controls (runtime.gd OPEN_RULES_VERSION): the rules a new level pins
## by default. A pad holds for either pip and either pip works any lever,
## switch or selector, so a definition on them carries no owner_slot on its
## controls; one-pip access comes from where a control stands. Crossings and
## zones keep their own owner_slot field (ADDING-A-CHAPTER, one-pip access).
## Shared by the engines (the numbers), the catalogs and the scaffold's
## templates. It preloads nothing, so a catalog may preload it.
##
## The numbers: 12 is the comfort rules (8, 9) with open controls, in either
## family; 13 the journey's tide rules (10) with open controls. 11 is the
## Lighthouse room's, which 0.8.1 already offers on join, so it is skipped.
const OPEN_RULES_VERSION := 12
const OPEN_TIDE_RULES_VERSION := 13
const TIDE_RULES := [10, OPEN_TIDE_RULES_VERSION]
const OPEN_RULES := [OPEN_RULES_VERSION, OPEN_TIDE_RULES_VERSION]
const KINDS := ["controls", "levers", "pressure_pads"]

## The open rules that keep `earlier`'s other rules: the tide rules (10) as
## 13, anything else as the comfort rules with open controls (12).
static func rules_for(earlier: int) -> int:
	return OPEN_TIDE_RULES_VERSION if earlier in TIDE_RULES else OPEN_RULES_VERSION

## `level` pinned to the open rules for its earlier rules, with no owner on
## any stage's controls, levers or pads. Changes and returns `level`.
static func pin(level: Dictionary) -> Dictionary:
	level.simulation_version = rules_for(int(level.get("simulation_version", 0)))
	for stage: Dictionary in level.get("stages", []):
		for kind: String in KINDS:
			for item: Dictionary in stage.get(kind, []): item.erase("owner_slot")
	return level

## Whether `definition` pins open controls.
static func pinned(definition: Dictionary) -> bool:
	var declared: Variant = definition.get("simulation_version")
	return (declared is int or declared is float) and int(declared) in OPEN_RULES
