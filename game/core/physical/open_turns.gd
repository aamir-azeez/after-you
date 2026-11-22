extends RefCounted
## Open turns (open_controls.gd OPEN_TURNS_RULES: 18 is the comfort rules with
## open controls and open turns, 19 the tide rules with both). A stage no
## longer has exactly two turns: it ends the moment both pips stand at its goal
## (the live pip and the friend's replay, whoever got there first) and the
## goal's light holds, otherwise play passes back to the other pip once the
## friend's replay is over, up to the stage's own cap ("turn_cap", set in the level). There
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
## 19, anything else as 18.
static func rules_for(earlier: int) -> int:
	if earlier in RULES: return earlier
	return OpenControls.OPEN_TURNS_TIDE_RULES_VERSION if earlier in OpenControls.TIDE_RULES else OpenControls.OPEN_TURNS_RULES_VERSION

## `level` on open controls and open turns, each stage's cap from `caps`
## ({stage id: turns}; a stage left out keeps DEFAULT_CAP). A level with a
## ball (its "props") takes the shared ball rules (21, runtime.gd
## _shared_ball). Changes and returns `level`.
static func pin(level: Dictionary, caps: Dictionary) -> Dictionary:
	var earlier := int(level.get("simulation_version", 0))
	OpenControls.pin(level)
	level.simulation_version = rules_for(earlier)
	if not level.get("props", []).is_empty() and level.simulation_version == OpenControls.OPEN_TURNS_RULES_VERSION: level.simulation_version = OpenControls.SHARED_BALL_RULES_VERSION
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

## Whether turn `turn` of `stage` must finish it: its cap's turn offers no
## pass. A room may also end a stage early when its bytes run out (the
## server's must_finish).
static func must_finish(stage: Dictionary, turn: int) -> bool:
	return turn >= cap(stage)

## Whether `stage`'s cap is one a level may set: a whole number of turns
## from MIN_CAP to MAX_CAP. Either pip's turn may finish, so any count will do.
static func cap_valid(stage: Dictionary) -> bool:
	var declared: Variant = stage.get("turn_cap", DEFAULT_CAP)
	return (declared is int or (declared is float and declared == floor(declared))) and int(declared) >= MIN_CAP and int(declared) <= MAX_CAP

## How a stage's turns play (the server's mirror is backend/src/v2/open-turns.ts).
## Turn 1 is a first turn (role "a") from the stage's checkpoint, the other pip
## standing. Every later turn (role "b") starts from the world the turn before
## it handed off (the shared timeline below) with the rest of that turn
## replaying beside it, and names it by source_recording_hash; nothing nests.
## Odd turns are the stage's first pip's (first_slot), even turns the other's.
## A later turn closes the stage the moment both pips are at the goal; the pip
## may instead pass once the friend's replay is over. Every turn has the second
## turn's time limit. Turn ids keep a letter for the turn's number:
## t<branch>-<stage>-a, -b, -c ...
const LETTERS := "abcdefghijklmnopqrst"
## Checkpoints of open turns hold every turn of their stage, in place of a and
## b, and the pip that starts the next stage (schema 9).
const CHECKPOINT_SCHEMA := 9
const CHECKPOINT_KEYS := ["schema_version", "level_id", "level_version", "definition_hash", "stage_index", "completed_stage_id", "next_stage_id", "players", "mechanisms", "previous_checkpoint_hash", "turn_hashes", "next_first_slot", "checkpoint_hash", "proof"]

## A completed stage's turns in play order, from its checkpoint's `proof`:
## every turn under open turns (proof.turns), a and b before. [] when the
## proof holds neither.
static func proof_turns(proof: Variant) -> Array:
	if not proof is Dictionary: return []
	if proof.get("turns") is Array:
		var turns: Array = proof.turns
		return turns if turns.size() >= 2 and turns.all(func(turn: Variant) -> bool: return turn is Dictionary) else []
	return [proof.a, proof.b] if proof.get("a") is Dictionary and proof.get("b") is Dictionary else []

## Whether a finished turn may be saved, from its check ({valid, snapshot,
## ready}) and its recording: it can commit, or under open turns it is a pass
## that may be the friend's memory (a later turn that did not finish the stage).
## The one rule for the review card and for Hard mode (hard_mode.gd failure).
static func keepable(verified: Dictionary, recording: Dictionary) -> bool:
	var snapshot: Variant = verified.get("snapshot", {})
	var passing: bool = recording.get("role") == "b" and recording.get("completed") == false and bool(verified.get("ready", false))
	return bool(verified.get("valid", false)) and snapshot is Dictionary and (bool(snapshot.get("can_commit", false)) or passing)

## Whether `turns` is a stage's later turns as a record keeps them: one at
## least, at most a cap's worth, each a turn.
static func turns_valid(turns: Variant) -> bool:
	return turns is Array and not turns.is_empty() and turns.size() <= MAX_CAP and turns.all(func(turn: Variant) -> bool: return turn is Dictionary)

## Whether `pair` is a completed stage as a journal or a kept hard run holds
## it: {a, b}, or under open turns {a, b, passes}. The one shape check for
## both (relay_journey.gd, hard_mode.gd).
static func record_valid(pair: Variant) -> bool:
	if not pair is Dictionary or not pair.get("a") is Dictionary or not pair.get("b") is Dictionary: return false
	return pair.size() == 2 or (pair.size() == 3 and turns_valid(pair.get("passes")))

## A completed pair's turns in play order: its first turn, its passes (from its
## checkpoint's proof, or a local record's own "passes"), its closing turn.
static func pair_turns(pair: Dictionary) -> Array:
	var passes: Variant = pair.get("passes")
	if not passes is Array:
		var nested := proof_turns(pair.get("checkpoint", {}).get("proof") if pair.get("checkpoint") is Dictionary else null)
		passes = nested.slice(1, nested.size() - 1) if nested.size() > 2 else []
	return [pair.get("a")] + passes + [pair.get("b")]

## Carry-over turns: a stage is
## one shared timeline that only moves forward. Turn k starts from turn k-1's
## world at its hand-off tick H(k), with the rest of turn k-1 (its pip's
## recorded inputs) replaying beside the live pip for M(k) ticks. Every turn's
## record adds three header fields, covered by its recording_hash: H
## (handoff_tick), the world hash at its start (start_hash) and at its tick M,
## which is the next turn's start (handoff_hash). A checkpoint adds the pip
## that starts the next stage (next_first_slot, checkpoint schema 9). The rules
## numbers are 18 to 21 (open_controls.gd).
const HANDOFF_TICK := "handoff_tick"
const START_HASH := "start_hash"
const HANDOFF_HASH := "handoff_hash"
const RECORD_FIELDS := [HANDOFF_TICK, START_HASH, HANDOFF_HASH]
const NEXT_FIRST_SLOT := "next_first_slot"
## The pip that starts a level's first stage: the host's.
const FIRST_SLOT := "p0"

## S(turn): where turn `turn` starts on its stage's shared timeline, from
## `lengths`, the durations of the stage's turns before it in order (turn 1
## first; at least turn - 1 of them). Each pip's turns join end to end on its
## own track: S(1) = S(2) = 0, S(k) = S(k-2) + L(k-2).
static func start_tick(lengths: Array, turn: int) -> int:
	var start := 0
	for k in range(turn - 2, 0, -2): start += int(lengths[k - 1])
	return start

## H(turn): how many ticks into turn - 1 turn `turn` takes over, S(k) - S(k-1).
## 0 for turns 1 and 2 (turn 2 hands off at tick 0 of turn 1).
static func handoff_tick(lengths: Array, turn: int) -> int:
	return 0 if turn <= 2 else start_tick(lengths, turn) - start_tick(lengths, turn - 1)

## M(turn): how long the friend's replay plays beside turn `turn`, the rest of
## turn - 1 after the hand-off: L(k-1) - H(k). 0 for turn 1. It is also the
## next turn's hand-off: H(k+1) = M(k).
static func replay_ticks(lengths: Array, turn: int) -> int:
	return 0 if turn <= 1 else int(lengths[turn - 2]) - handoff_tick(lengths, turn)

## Whether turn `turn` may end after `length` ticks: a pass once the friend's
## replay is over (length >= M), and a turn that finished the stage at any
## tick (both pips at the lit goal; the rest of the replay is dropped).
static func long_enough(lengths: Array, turn: int, length: int, completed: bool) -> bool:
	return completed or length >= replay_ticks(lengths, turn)

## The pip that starts the stage after `checkpoint`: its next_first_slot, or
## the host's for a level's first stage (a checkpoint without one).
static func first_slot(checkpoint: Dictionary) -> String:
	var declared: Variant = checkpoint.get(NEXT_FIRST_SLOT)
	return str(declared) if declared in ["p0", "p1"] else FIRST_SLOT

## The pip that starts the next stage once a stage whose first pip is `first`
## closed on turn `turns`: whoever did not play the closing turn.
static func next_first_slot(first: String, turns: int) -> String:
	return "p1" if slot(first, turns) == "p0" else "p0"

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
