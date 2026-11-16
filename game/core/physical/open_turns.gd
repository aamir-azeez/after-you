extends RefCounted
## Open turns (open_controls.gd OPEN_TURNS_RULES: 14 is the comfort rules with
## open controls and open turns, 15 the tide rules with both). A stage no
## longer has exactly two turns: it ends when a turn ends with both pips at
## its goal (the live pip and the memory standing there once the memory has
## played out) and the goal's light holds, otherwise play passes back to the
## other pip, up to the stage's own cap ("turn_cap", set in the level). There
## is no bell to ring and no first pip's part that must still hold at the end:
## both pips at the goal is the whole finish (runtime.gd _at_goal). Every turn
## has the level's time limit. The level checker (tests/test_level_checker.gd)
## asks that no stage can be finished by one pip alone and that both pips can
## reach the goal; the chapter suite plays a witness within the cap.
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

## Whether `stage`'s cap is one a level may set: a whole number of turns
## from MIN_CAP to MAX_CAP. Either pip's turn may finish, so any count will do.
static func cap_valid(stage: Dictionary) -> bool:
	var declared: Variant = stage.get("turn_cap", DEFAULT_CAP)
	return (declared is int or (declared is float and declared == floor(declared))) and int(declared) >= MIN_CAP and int(declared) <= MAX_CAP

## How a stage's turns play and nest (the server's mirror is
## backend/src/v2/open-turns.ts). Turn 1 is a first turn as before (role "a");
## every later turn (role "b") plays from the stage's checkpoint with the other
## pip's latest turn as its memory, which nests the turns before it by
## source_recording_hash. Odd turns are the stage's first pip's, even turns the
## other's. A later turn that has both pips at the goal once its memory has
## played out closes the stage; the pip may instead pass once the memory is over. Every
## turn has the second turn's time limit. Turn ids keep a letter for the
## turn's number: t<branch>-<stage>-a, -b, -c ...
const LETTERS := "abcdefghijklmnopqrst"
## Checkpoints of open turns nest every turn of their stage, in place of a and b.
const CHECKPOINT_SCHEMA := 8
const CHECKPOINT_KEYS := ["schema_version", "level_id", "level_version", "definition_hash", "stage_index", "completed_stage_id", "next_stage_id", "players", "mechanisms", "previous_checkpoint_hash", "turn_hashes", "checkpoint_hash", "proof"]

## A completed stage's turns in play order, from its checkpoint's `proof`:
## every turn under open turns (proof.turns), a and b before. [] when the
## proof holds neither.
static func proof_turns(proof: Variant) -> Array:
	if not proof is Dictionary: return []
	if proof.get("turns") is Array:
		var turns: Array = proof.turns
		return turns if turns.size() >= 2 and turns.all(func(turn: Variant) -> bool: return turn is Dictionary) else []
	return [proof.a, proof.b] if proof.get("a") is Dictionary and proof.get("b") is Dictionary else []

## A completed pair's turns in play order: its first turn, its passes (from its
## checkpoint's proof, or a local record's own "passes"), its closing turn.
static func pair_turns(pair: Dictionary) -> Array:
	var passes: Variant = pair.get("passes")
	if not passes is Array:
		var nested := proof_turns(pair.get("checkpoint", {}).get("proof") if pair.get("checkpoint") is Dictionary else null)
		passes = nested.slice(1, nested.size() - 1) if nested.size() > 2 else []
	return [pair.get("a")] + passes + [pair.get("b")]

## Whether rules `version` play open turns.
static func rules(version: int) -> bool:
	return version in RULES

## The slot that plays turn `turn` (1 based) of a stage whose first pip is `first`.
static func slot(first: String, turn: int) -> String:
	return first if turn % 2 == 1 else ("p1" if first == "p0" else "p0")

## The turn number a turn id names by its letter (a = 1), or 0.
static func number(id: String) -> int:
	return LETTERS.find(id.right(1)) + 1 if not id.is_empty() else 0

## Turn `turn`'s id on `branch` and stage `stage_index`.
static func turn_id(branch: int, stage_index: int, turn: int) -> String:
	return "t%d-%d-%s" % [branch, stage_index, LETTERS[turn - 1]]

## The memory a turn on `room` (a room snapshot before open turns) replays:
## its first turn (recording_a), or nothing. An open turns room's view names
## its turns by hash and carries only the newest in full; the phone plays them
## from its own copies (services/relay_room_coordinator.gd _memory).
static func memory(room: Dictionary) -> Dictionary:
	var first: Variant = room.get("recording_a")
	return {"prior": first, "chain": []} if first is Dictionary else {"prior": {}, "chain": []}
