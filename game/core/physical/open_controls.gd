extends RefCounted
## Open controls (runtime.gd OPEN_RULES_VERSION): the rules a new level pins
## by default. A pad holds for either pip and either pip works any lever,
## switch or selector, so a definition on them carries no owner_slot on its
## controls; one-pip access comes from where a control stands. Zones keep
## their own owner_slot field; bridges and stairs open to both pips too
## (open_crossings), except those the puzzle truly needs owned, which keep
## their owner and the route barriers' visible gate (ADDING-A-CHAPTER,
## one-pip access).
## Shared by the engines (the numbers), the catalogs and the scaffold's
## templates. It preloads nothing, so a catalog may preload it.
##
## The numbers: 12 is the comfort rules (8, 9) with open controls, in either
## family; 13 the journey's tide rules (10) with open controls. 11 is the
## Lighthouse room's, which 0.8.1 already offers on join, so it is skipped.
## 18 and 19 are 12 and 13 with open turns on the shared timeline
## (core/physical/open_turns.gd): they keep open controls, and 19 keeps the
## tide. 20 is 19 with the new pieces of The Falls and Fog Marsh
## (core/physical/pieces_rules.gd): tide, open controls and open turns all hold
## for it. 21 is 18 with one shared ball (runtime.gd _shared_ball): both pips
## push it, and a ball home stage ends with it in its cradle; OpenTurns.pin
## gives it to a level with a ball. They took over 14 to 17, the open turns
## whose later turns replayed over nested memories, which are gone.
const OPEN_RULES_VERSION := 12
const OPEN_TIDE_RULES_VERSION := 13
const OPEN_TURNS_RULES_VERSION := 18
const OPEN_TURNS_TIDE_RULES_VERSION := 19
const PIECES_RULES_VERSION := 20
const SHARED_BALL_RULES_VERSION := 21
const TIDE_RULES := [10, OPEN_TIDE_RULES_VERSION, OPEN_TURNS_TIDE_RULES_VERSION, PIECES_RULES_VERSION]
const OPEN_RULES := [OPEN_RULES_VERSION, OPEN_TIDE_RULES_VERSION, OPEN_TURNS_RULES_VERSION, OPEN_TURNS_TIDE_RULES_VERSION, PIECES_RULES_VERSION, SHARED_BALL_RULES_VERSION]
const OPEN_TURNS_RULES := [OPEN_TURNS_RULES_VERSION, OPEN_TURNS_TIDE_RULES_VERSION, PIECES_RULES_VERSION, SHARED_BALL_RULES_VERSION]
const SHARED_BALL_RULES := [SHARED_BALL_RULES_VERSION]
const KINDS := ["controls", "levers", "pressure_pads"]

## The open rules that keep `earlier`'s other rules: the tide rules (10) as
## 13, anything else as the comfort rules with open controls (12).
static func rules_for(earlier: int) -> int:
	if earlier in OPEN_TURNS_RULES: return earlier
	return OPEN_TIDE_RULES_VERSION if earlier in TIDE_RULES else OPEN_RULES_VERSION

## `level` pinned to the open rules for its earlier rules, with no owner on
## any stage's controls, levers or pads. Changes and returns `level`.
static func pin(level: Dictionary) -> Dictionary:
	level.simulation_version = rules_for(int(level.get("simulation_version", 0)))
	for stage: Dictionary in level.get("stages", []):
		for kind: String in KINDS:
			for item: Dictionary in stage.get(kind, []): item.erase("owner_slot")
	return level

## `level` with every bridge and stair open to both pips, but those named in
## `keep`: the ones a stage needs owned, or one pip could finish it alone
## (tests/test_level_checker.gd, both pips). Changes and returns `level`.
static func open_crossings(level: Dictionary, keep: Array) -> Dictionary:
	for kind: String in ["bridges", "stairs"]:
		for route: Dictionary in level.get(kind, []):
			if str(route.id) not in keep: route.erase("owner_slot")
	return level

## Whether `definition` pins open controls.
static func pinned(definition: Dictionary) -> bool:
	var declared: Variant = definition.get("simulation_version")
	return (declared is int or declared is float) and int(declared) in OPEN_RULES
