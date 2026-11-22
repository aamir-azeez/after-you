extends SceneTree
## Open turns (core/physical/open_turns.gd) on Turn of the Tide@3's Set the
## Tide, played from the native fixture inputs (re-recorded on today's rules):
## - the carry-over timeline (open_turns.gd): each turn's start, hand-off and
##   replay on the shared timeline, the pass rule and the field names;
## - every turn has the second turn's limit, and a level may declare equal
##   limits (refused on the rules before open turns); ids and pips follow turn order;
## - turn 2 hands off at tick 0 of turn 1 and may pass once turn 1's replay is
##   over, and the pass replays exactly and is ready to be a memory; the room's
##   must_finish takes the pass away;
## - turn 3 is the first pip's again, taking over where it stood when turn 1
##   ended, in turn 2's world there (its start hash is turn 2's hand-off hash);
##   there is no bell, and the first pip walks to the goal and passes, since
##   the second pip is not there;
## - turn 4 takes over at turn 3's start with all of turn 3 replaying, steps
##   to the goal and waits; the stage ends the moment the replay brings the
##   first pip there, and the checkpoint holds all four turns and the pip that
##   starts the next stage (schema 9), checked again from scratch;
## - every turn records packed (core/v2/recording_codec.gd), in rooms and solo,
##   whatever the room says, and plays as the next memory, from a kept start
##   world or from the stage's turns played again;
## - a solo journal's "Redo my previous turn" takes back its latest pass, and
##   reopening a stage brings its passes back; it keeps every turn packed, so a
##   run of every stage at its cap of the longest turns stays well under the
##   save's cap, and so does the worst any open level can make at 150 s turns,
##   which still backs up to the Saved Games slot;
## - a published two turn stage still proves the published way;
## - the turn dots (presentation/kit/turn_dots.gd) ring the last turn: the cap's
##   once it is next, this one when the room says it must finish; the cap's
##   turn offers no pass, and Solo counts turns as a room does and shows the
##   dots too (never in a replay);
## - Finish while the memory still plays (relay_preview.gd _end_turn_early):
##   the pip dozes and stands still, played out live, fast-forwarded or
##   skipped; the memory's later presses still land, the turn is byte for byte
##   the one a still pip records and passes as before, a turn that must finish
##   hands the controls back (the doze at the goal is presentation/
##   memory_wait.gd's, tested in test_memory_wait.gd);
## - a first turn may end at any time, its own part done or not (its outcome
##   says which), replays exactly and is the next turn's memory; the same turn
##   on the tide rules before open turns (13) may not be saved;
## - open turns show no bell: no Bell card and no bell hint on Tide@3.
## - the hand-off (test_open_turns_memories.gd): nothing acts twice, the world
##   only differs from the friend's turn by what the live pip does, and a
##   drowned friend fails the turn; and a save, load and step round trip
##   matches stepping straight through on every tick of each open level's
##   witness turns 1 and 2 and of the four turns above.
## SUITES splits these parts between this suite and its subclasses
## (test_open_turns_memories.gd, test_open_turns_long.gd), so each stays well
## inside CI's 120 s a suite. Nearly all the time is Tide@3's turns simulated.
const Registry = preload("res://services/chapter_registry.gd")
const Simulation = preload("res://core/journey/simulation.gd")
const OpenTurns = preload("res://core/physical/open_turns.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Witness = preload("res://tests/chapter_witness.gd")
const Journey = preload("res://services/relay_journey.gd")
const MemoryTrace = preload("res://core/physical/memory_trace.gd")
const CheckpointPairs = preload("res://services/checkpoint_pairs.gd")
const Collection = preload("res://services/shared_replay_collection.gd")
const TraceStore = preload("res://services/memory_trace_store.gd")
const TurnDots = preload("res://presentation/kit/turn_dots.gd")
const RecordingCodec = preload("res://core/v2/recording_codec.gd")
const MemoryWait = preload("res://presentation/memory_wait.gd")
const Joystick = preload("res://presentation/joystick.gd")
const ChapterControls = preload("res://presentation/chapter_controls.gd")
const SpiritLook = preload("res://presentation/spirit_look.gd")
const Frozen = preload("res://services/frozen_simulation.gd")
const OpenTurnStore = preload("res://services/open_turn_store.gd")
const TRACES := "user://open-turns-test-traces"
const TIDE := "turn-of-the-tide@3"
const STAGE := "set-the-tide"
var checks := 0
var failures := 0
## _chain's stage: turn 1, two passes, the closing turn, and its checkpoint.
var _stage: Array = []
var _stage_checkpoint: Dictionary = {}
## Turn 1 recorded from the fixture's inputs on today's rules (_first).
var _turn_one: Dictionary = {}
## The first pip's way from where turn 1 leaves it (on the bollard pad) to the
## goal, turning the tide to half and the sluice and lock on the way; and the
## second pip's last steps from the stone bar to the goal.
const P0_TO_GOAL := [["walk", [320, -400]], ["walk", [192, -400]], ["walk", [192, -340]], ["tap"], ["tap"], ["walk", [96, -340]], ["walk", [96, 0]], ["walk", [704, 0]], ["walk", [704, 72]], ["tap"], ["walk", [704, 52]], ["walk", [856, 52]], ["tap"], ["walk", [1428, 52]], ["walk", [1428, 0]]]
const P1_TO_GOAL := [["walk", [1452, 64]], ["walk", [1452, 0]]]

## The chapter screen with its saves, review and turn check left out: it
## notes how the turn ended.
class Screen extends "res://relay_preview.gd":
	var ended := ""
	func _persist_draft(_after_retry: String = "play", _periodic: bool = false) -> bool: return true
	func _take_review() -> void: review = sim.export_recording()
	func _start_turn_check() -> void: pass
	func _begin_completion(_from_replay: bool) -> void:
		ended = "complete"
		running = false
	func _after_visible_wait(_work: Callable) -> void: ended = "passed"

class ScreenWorld extends Node3D:
	var dozes := 0
	var wakes := 0
	func present(_state: Dictionary, _immediate: bool = false) -> void: pass
	func show_memory_wait(_live: String, _memory: String, _immediate: bool = false) -> void: dozes += 1
	func wake_from_memory_wait(_live: String, _reduced: bool) -> void: wakes += 1
	func end_memory_wait(_live: String) -> void: pass

class ScreenControls extends CanvasLayer:
	var held := false
	func update_state(_title: String, _remaining: float, _state: Dictionary, _live: bool) -> void: pass
	func show_memory_wait(_text: String, _ratio: float, _skipping: bool = false) -> void: pass
	func hide_memory_wait() -> void: pass
	func fast_forward_held() -> bool: return held
	func dim_stick(_dim: bool) -> void: pass
	func show_tries(_tries: int) -> void: pass

## The parts each open turns suite runs, every part in exactly one.
const SUITES := {
	"open_turns": ["rules", "chain", "packed", "sizes", "published", "dots", "end_early", "early_first"],
	"open_turns_memories": ["memories", "round_trip"],
	"open_turns_long": ["long_turns"],
}

func _initialize() -> void: _run.call_deferred()

## The suite this file runs as; each subclass names its own.
func _suite() -> String:
	return "open_turns"

func _run() -> void:
	var parts: Array = SUITES[_suite()]
	if "rules" in parts: _rules()
	if "chain" in parts:
		_chain()
		await _hard_runs()
	if "packed" in parts: _packed_chain()
	if "sizes" in parts:
		_solo_size()
		_solo_worst_case()
	if "memories" in parts: _memories()
	if "round_trip" in parts: _round_trips()
	if "long_turns" in parts: _long_turns()
	if "published" in parts: _published()
	if "dots" in parts: _dots()
	if "end_early" in parts: _end_early()
	if "early_first" in parts: _early_first_turn()
	print("OPEN TURNS (%s): %d checks, %d failures" % [_suite(), checks, failures])
	quit(1 if failures else 0)

func _rules() -> void:
	_check(OpenTurns.rules(18) and OpenTurns.rules(19) and OpenTurns.rules(20) and OpenTurns.rules(21) and not OpenTurns.rules(12) and not OpenTurns.rules(13), "Open turns are 18 to 21")
	_check([1, 2, 3, 4].map(func(n: int) -> String: return OpenTurns.slot("p1", n)) == ["p1", "p0", "p1", "p0"], "Odd turns are the first pip's")
	_check(OpenTurns.turn_id(3, 1, 1) == "t3-1-a" and OpenTurns.turn_id(3, 1, 3) == "t3-1-c" and OpenTurns.turn_id(0, 0, 20) == "t0-0-t", "Turn ids keep a and b and go on by letter")
	_timeline()
	var level := Registry.definition(TIDE)
	var first := Simulation.new()
	first.reset(level, STAGE, Registry.initial_checkpoint(TIDE), {}, "a")
	_check(first.duration_limit() == Simulation.turn_ticks(level, 19, "b"), "A first turn has the second turn's limit")
	# Every open turn has the same limit, so a level may declare one number for both.
	var equal: Dictionary = level.duplicate(true)
	equal.turn_limits = {"a_ticks": 2730, "b_ticks": 2730}
	_check(Simulation.rules_allowed(equal, 19) and Simulation.turn_ticks(equal, 19, "a") == 2730 and Simulation.turn_ticks(equal, 19, "b") == 2730, "Open turns take equal turn limits")
	var closed: Dictionary = equal.duplicate(true)
	closed.simulation_version = 13
	var longer: Dictionary = closed.duplicate(true)
	longer.turn_limits = {"a_ticks": 2700, "b_ticks": 3000}
	_check(not Simulation.rules_allowed(closed, 13) and Simulation.rules_allowed(longer, 13), "Rules before open turns still need the longer second turn")

## The shared timeline (open_turns.gd start_tick, handoff_tick, replay_ticks):
## The Falls' stage 1 from the design (8, 40, 70 and 45 s turns), the same
## with turn 4 ending just as Gold's replay does, and equal turns. Each row
## is [S, H, M] for turns 1 to 5; a turn's replay is the next one's hand-off.
func _timeline() -> void:
	var tables := [
		[[8, 40, 70, 45], [[0, 0, 0], [0, 0, 8], [8, 8, 32], [40, 32, 38], [78, 38, 7]]],
		[[8, 40, 70, 38], [[0, 0, 0], [0, 0, 8], [8, 8, 32], [40, 32, 38], [78, 38, 0]]],
		[[10, 10, 10, 10], [[0, 0, 0], [0, 0, 10], [10, 10, 0], [10, 0, 10], [20, 10, 0]]],
	]
	for table: Array in tables:
		var lengths: Array = table[0]
		var rows: Array = []
		for turn in range(1, 6): rows.append([OpenTurns.start_tick(lengths, turn), OpenTurns.handoff_tick(lengths, turn), OpenTurns.replay_ticks(lengths, turn)])
		_check(rows == table[1], "The timeline of %s turns is %s (got %s)" % [str(lengths), str(table[1]), str(rows)])
		var chained := true
		for turn in range(1, 5): chained = chained and OpenTurns.replay_ticks(lengths, turn) == OpenTurns.handoff_tick(lengths, turn + 1)
		_check(chained, "Each turn's replay ends where the next turn takes over (%s)" % str(lengths))
	# Run time: each turn adds what it lengthens the timeline by, so a stage counts S(last) + L(last) once.
	_check(OpenTurns.timeline_shares([8, 40, 70, 45]) == [8, 32, 38, 7] and OpenTurns.timeline_shares([8, 40, 70, 20]) == [8, 32, 38, -18], "A stage's run time is its timeline's length: 85 s, or 60 s when turn 4 finishes before the replay ends")
	var falls := [8, 40, 70]
	_check(OpenTurns.long_enough(falls, 4, 38, false) and not OpenTurns.long_enough(falls, 4, 37, false) and OpenTurns.long_enough(falls, 4, 5, true) and OpenTurns.long_enough([], 1, 1, false), "A pass waits out the replay; a finished turn and turn 1 need not")
	_check(OpenTurns.first_slot({"stage_index": 0}) == "p0" and OpenTurns.first_slot({OpenTurns.NEXT_FIRST_SLOT: "p1"}) == "p1", "The host starts a level; the checkpoint names who starts each later stage")
	_check(OpenTurns.next_first_slot("p0", 4) == "p0" and OpenTurns.next_first_slot("p0", 3) == "p1" and OpenTurns.next_first_slot("p1", 2) == "p1", "The next stage starts with whoever did not close this one")
	_check(OpenTurns.RECORD_FIELDS == ["handoff_tick", "start_hash", "handoff_hash"] and OpenTurns.NEXT_FIRST_SLOT == "next_first_slot", "The record and checkpoint field names")

## Turn 1 of Set the Tide, the first pip's part, recorded from the fixture's
## inputs on today's rules (the fixture itself is on rules that are gone).
func _first() -> Dictionary:
	if not _turn_one.is_empty(): return _turn_one
	var one := Simulation.new()
	one.reset(Registry.definition(TIDE), STAGE, Registry.initial_checkpoint(TIDE), {}, "a")
	for frame: Dictionary in Simulation.expand_recording_inputs(_fixture("turn-of-the-tide-v3-set-the-tide-a.json")): one.step(frame)
	_turn_one = _json(one.export_recording())
	return _turn_one

func _chain() -> void:
	var level := Registry.definition(TIDE)
	var start := Registry.initial_checkpoint(TIDE)
	var a := _first()
	var b_frames: Array = Simulation.expand_recording_inputs(_fixture("turn-of-the-tide-v3-set-the-tide-b.json"))
	var length := int(a.duration_ticks)
	_check(a.handoff_tick == 0 and a.start_hash == a.handoff_hash and a.start_hash.length() == 64, "Turn 1 hands off at its own start: its start and hand-off worlds are one")
	# Turn 2: the second pip's route, stopped where turn 1 ended (short of the goal), once turn 1's replay is over.
	var two := Simulation.new()
	_check(two.reset(level, STAGE, start, a, "b"), "Turn 2 starts over turn 1 (%s)" % two.error)
	_check(two.turn_number == 2 and two.active_slot == OpenTurns.slot(str(two.first_player_slot), 2) and two.memory_slot == two.first_player_slot and two.first_player_slot == "p0", "Turn 2 is the second pip's, over the host's")
	_check(two.handoff_tick == 0 and two.replay_ticks() == length and two.world_hash() == a.start_hash, "Turn 2 hands off at tick 0 of turn 1 and replays all of it")
	while int(two.tick) < length - 1: two.step(b_frames[two.tick])
	_check(not two.can_pass() and two.snapshot().can_end_early, "Turn 2 may not pass while turn 1's replay plays")
	two.step(b_frames[two.tick])
	_check(not two.complete and two.can_pass(), "Turn 2 may pass once turn 1's replay is over (%s)" % two.commit_reason())
	two.pass_allowed = false
	_check(not two.can_pass(), "A turn the room says must finish offers no pass")
	two.pass_allowed = true
	two.pass_turn()
	var pass_two: Dictionary = _json(two.export_recording())
	_check(two.passed and pass_two.completed == false and pass_two.role == "b" and pass_two.source_recording_hash == a.recording_hash and pass_two.handoff_tick == 0 and pass_two.handoff_hash == two.world_hash(), "Turn 2's pass is an unfinished later turn over turn 1, handing off at its end")
	var checked := Simulation.verify_recording(level, pass_two, start, a)
	_check(checked.valid and checked.get("ready", false), "The pass replays exactly and may be a memory (%s)" % str(checked.get("error", "")))
	# Turn 3: the first pip again, where it stood when turn 1 ended, in turn 2's world there.
	var three := Simulation.new()
	_check(three.reset(level, STAGE, start, pass_two, "b", 0, [a]), "Turn 3 starts over turn 2 (%s)" % three.error)
	_check(three.turn_number == 3 and three.active_slot == three.first_player_slot and three.memory_slot != three.first_player_slot, "Turn 3 is the first pip's, the replay the second's")
	_check(three.handoff_tick == length and three.replay_ticks() == 0 and three.world_hash() == pass_two.handoff_hash, "Turn 3 takes over where turn 1 ended, in the world turn 2 handed off")
	_check(three.snapshot().players[three.memory_slot].ghost and not three.snapshot().players[three.active_slot].ghost, "The replayed pip is the ghost")
	_check(Witness._play(three, P0_TO_GOAL).is_empty() and three._at_goal(three.active_slot) and three.snapshot().context_action.get("id", "") != "ring", "Turn 3 walks the first pip to the goal; there is no bell to ring")
	_check(not three.complete and not three.finished, "One pip at the goal does not finish the stage")
	for _tick in range(30): three.step({})
	_check(three.can_pass(), "Turn 3 may pass, with no replay left (%s)" % three.commit_reason())
	three.pass_turn()
	var pass_three: Dictionary = _json(three.export_recording())
	var checked_three := Simulation.verify_recording(level, pass_three, start, pass_two, [a])
	_check(checked_three.valid and checked_three.get("ready", false), "Turn 3's pass replays from its hand-off (%s)" % str(checked_three.get("error", "")))
	_check(not Simulation.verify_recording(level, pass_three, start, pass_two).valid, "A later turn without the turns before it is refused")
	# Turn 4: the second pip takes over at turn 3's start, with all of turn 3 replaying.
	var four := Simulation.new()
	_check(four.reset(level, STAGE, start, pass_three, "b", 0, [a, pass_two]), "Turn 4 starts over turn 3 (%s)" % four.error)
	_check(four.active_slot == two.active_slot and four.handoff_tick == 0 and four.replay_ticks() == int(pass_three.duration_ticks), "Turn 4 is the second pip's, taking over at turn 3's start")
	# The cap's turn must finish the stage, in Solo as in a room (OpenTurns.must_finish).
	_check(three.pass_allowed and four.pass_allowed, "Turns before the cap may pass")
	var capped: Dictionary = level.duplicate(true)
	for each: Dictionary in capped.stages:
		if each.id == STAGE: each.turn_cap = 4
	var at_cap := Simulation.new()
	at_cap._reset_trusted(capped, STAGE, start, pass_three, "b", [a, pass_two])
	_check(at_cap.turn_number == 4 and not at_cap.pass_allowed and not at_cap.can_pass(), "The cap's turn offers no pass")
	Witness._play(four, P1_TO_GOAL)
	_check(four._at_goal(four.active_slot) and not four.complete and four.snapshot().objective_done and not four.snapshot().complete, "The second pip reaches the goal first and waits for the replay: objective_done, not complete")
	while not four.finished: four.step({})
	_check(four.complete and int(four.tick) < four.replay_ticks(), "The stage ends the moment the replay brings the first pip to the goal, the rest of the replay dropped (%s, tick %d of %d)" % [four.commit_reason(), int(four.tick), four.replay_ticks()])
	if not four.complete: return
	var closing: Dictionary = _json(four.export_recording())
	_check(closing.handoff_hash == "", "A turn that ends before its replay does hands nothing off")
	var derived := Simulation.derive_checkpoint(level, start, a, closing, [pass_two, pass_three])
	_check(derived.valid, "The closing checkpoint derives (%s)" % str(derived.get("error", "")))
	if not derived.valid: return
	var checkpoint: Dictionary = derived.checkpoint
	_stage = [a, pass_two, pass_three, closing]
	_stage_checkpoint = checkpoint
	_check(int(checkpoint.schema_version) == 9 and checkpoint.turn_hashes == [a.recording_hash, pass_two.recording_hash, pass_three.recording_hash, closing.recording_hash] and checkpoint.proof.turns.size() == 4 and not checkpoint.has("a_recording_hash"), "It holds all four turns in order (schema 9)")
	_check(checkpoint.next_first_slot == "p0" and OpenTurns.first_slot(checkpoint) == "p0", "The second pip closed the stage, so the host's pip starts the next")
	MemoryTrace.clear()
	_check(Simulation.verify_checkpoint(level, checkpoint).valid, "The four turn checkpoint proves from scratch")
	# A solo journal keeps the passes and plays each turn over the latest (relay_journey.gd).
	var path := "user://open-turns-journal.json"
	var journal := Journey.new(path, null, TIDE)
	_solo_dots(journal, 1, two.first_player_slot)
	_check(journal.accept_recording(a) and journal.accept_recording(pass_two) and journal.accept_recording(pass_three), "A solo journal takes turn 1 and two passes (%s)" % journal.last_error)
	_check(journal.passes().size() == 2 and journal.prior_recording().get("recording_hash") == pass_three.recording_hash and journal.role() == "b", "Its next turn plays over the latest pass")
	_solo_dots(journal, 4, two.first_player_slot)
	# A Solo turn over a pass keeps its draft as it plays (the draft checks the pass it plays over).
	var live: RefCounted = journal.create_live_simulation()
	# The screen saves a draft once a turn has ticked (relay_preview _persist_draft).
	if live != null:
		for _tick in range(5): live.step({})
	_check(live != null and journal.save_live_draft(live) and journal.has_draft(), "A Solo turn over a pass saves its draft (%s)" % journal.last_error)
	_check(journal.save_draft({}) and not journal.has_draft(), "Its draft clears")
	_check(Journey.new(path, null, TIDE).passes().size() == 2, "The passes survive a reload")
	# Solo Play my turn again with passes held: the latest pass is taken back in memory, so turn 3 plays over turn 2 again.
	var plan := journal.redo_plan()
	_check(plan.get("kind") == "pass" and plan.get("turn") == pass_three.recording_hash, "Play my turn again offers the latest pass")
	_check(journal.begin_replace(plan) and journal.replacing() and journal.passes().size() == 1 and journal.prior_recording().get("recording_hash") == pass_two.recording_hash and journal.role() == "b", "It takes the pass back; the next turn plays over turn 2 (%s)" % journal.last_error)
	_check(not journal.begin_replace(journal.redo_plan()), "One turn is played again at a time")
	_check(Journey.new(path, null, TIDE).passes().size() == 2, "The saved pass stays until a new one is saved")
	journal.end_replace()
	_check(not journal.replacing() and journal.passes().size() == 2 and journal.prior_recording().get("recording_hash") == pass_three.recording_hash, "Keep it as it is brings the pass back")
	_check(journal.begin_replace(journal.redo_plan()) and journal.accept_recording(pass_three) and not journal.replacing() and journal.passes().size() == 2, "The turn saved next replaces it (%s)" % journal.last_error)
	_check(Journey.new(path, null, TIDE).passes().size() == 2 and Journey.new(path, null, TIDE).prior_recording().get("recording_hash") == pass_three.recording_hash, "The replaced pass survives a reload")
	_check(journal.accept_recording(closing) and journal.passes().is_empty() and journal.pairs()[0].get("passes", []).size() == 2 and Canonical.same(journal.checkpoint(), checkpoint), "The closing turn ends the stage with its passes in the pair (%s)" % journal.last_error)
	_check(OpenTurns.pair_turns(Journey.new(path, null, TIDE).pairs()[0]).all(func(turn: Dictionary) -> bool: return RecordingCodec.is_packed(turn)), "The saved journal keeps every turn packed")
	# Reopening the stage brings its passes back, so the closing turn plays over turn 3 again.
	var reopen := journal.redo_plan()
	_check(reopen.get("kind") == "stage" and journal.begin_replace(reopen) and journal.passes().size() == 2 and journal.prior_recording().get("recording_hash") == pass_three.recording_hash, "Playing the closing turn again reopens the stage with its passes (%s)" % journal.last_error)
	_check(journal.accept_recording(closing) and Canonical.same(journal.checkpoint(), checkpoint), "The closing turn ends it again (%s)" % journal.last_error)
	_check(Canonical.same(Journey.new(path, null, TIDE).checkpoint(), checkpoint), "A reloaded journal proves the stage with its passes")
	for suffix: String in ["", ".tmp", ".backup"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	# Replays, room history and local records read the stage's turns from its checkpoint (checkpoint_pairs.gd).
	var pair := CheckpointPairs.pair(TIDE, checkpoint, 0, 0)
	_check(pair.get("a", {}).get("recording_hash") == a.recording_hash and pair.get("b", {}).get("recording_hash") == closing.recording_hash and OpenTurns.pair_turns(pair).map(func(turn: Dictionary) -> String: return str(turn.recording_hash)) == checkpoint.turn_hashes, "A replay pair holds the first and closing turn, its passes from the checkpoint")
	_check(Canonical.same(CheckpointPairs.derive(Simulation, level, start, pair).get("checkpoint"), checkpoint) and Canonical.same(CheckpointPairs.derive(Simulation, level, start, {"a": a, "b": closing, "passes": [pass_two, pass_three]}).get("checkpoint"), checkpoint), "A pair or a local record with its passes derives the same checkpoint")
	_check(OpenTurns.number("t3-1-c") == 3 and OpenTurns.number("t0-0-a") == 1, "A turn id's letter is its number")
	var host := "A".repeat(22)
	var entry := {"schema_version": 1, "room": {"family": "chapter", "room_id": "C".repeat(22), "host_id": host, "guest_id": "B".repeat(22), "chapter_key": TIDE, "title": "Tide"}, "pair": pair}
	_check(Collection.verify_entry(entry, host), "Replays list a stage with passes")
	var shuffled: Dictionary = checkpoint.duplicate(true)
	shuffled.proof.turns = [a, pass_three, pass_two, closing]
	_check(not Simulation.verify_checkpoint(level, shuffled).valid, "Turns out of order are refused")

## Hard runs (services/hard_mode.gd) on open turns, with _chain's four turns:
## a slip on turn 4 is kept with turn 3 as its memory and turns 1 and 2 under
## it, and replays over them; a finished stage is kept with its passes and
## replays; turns that do not chain are refused when watched, and shapes a
## run never has are refused when kept. A two-turn slip keeps its three fields.
const HardRun = preload("res://services/hard_run.gd")
const TurnTries = preload("res://services/turn_tries.gd")
const Index = preload("res://content/chapters/index.gd")
const HARD_MARKS := "user://open-turns-hard-marks.json"
const HARD_TRIES := "user://open-turns-hard-tries.json"
func _hard_runs() -> void:
	if _stage.size() < 4: return
	var level := Registry.definition(TIDE)
	var start := Registry.initial_checkpoint(TIDE)
	var a: Dictionary = _stage[0]
	var turn_two: Dictionary = _stage[1]
	var turn_three: Dictionary = _stage[2]
	var closing: Dictionary = _stage[3]
	_clear_hard()
	var hashes := func(turns: Array) -> Array: return turns.map(func(turn: Dictionary) -> String: return str(turn.recording_hash))
	# Turn 4 slips a second in, over turn 3 and the turns under it.
	var four := Simulation.new()
	four.reset(level, STAGE, start, turn_three, "b", 0, [a, turn_two])
	var frames: Array = Simulation.expand_recording_inputs(closing)
	for tick in 30: four.step(frames[tick])
	var slip: Dictionary = _json(four.export_recording())
	var journal := Journey.new(HardMode.journal_path(TIDE), null, TIDE)
	journal.load_data()
	var run: RefCounted = HardRun.solo(TIDE, HARD_MARKS)
	var tries := TurnTries.new(HARD_TRIES)
	_check(journal.accept_recording(a), "A hard run keeps turn 1 (%s)" % journal.last_error)
	# Each pass is a turn the run keeps (the review's own check), and each next turn starts as a first try.
	var slots: Array = []
	for turn: Dictionary in [turn_two, turn_three]:
		var slot := TurnTries.slot_for(journal, run.tries_key(TIDE), false)
		_check(slot not in slots and tries.start(slot) == 1 and not run.slipped(tries.count(slot)), "Turn %d starts as its own first try" % (slots.size() + 2))
		slots.append(slot)
		_check(run.failure(journal.verify_turn(turn), turn).is_empty() and not run.failure(journal.verify_turn(turn), {}).is_empty(), "A pass is kept in a hard run, where a later turn that cannot pass would not be (turn %d)" % (slots.size() + 1))
		_check(journal.accept_recording(turn), "The journal keeps the pass (%s)" % journal.last_error)
	_check(hashes.call(journal.memory_chain()) == hashes.call([a, turn_two]) and journal.prior_recording().get("recording_hash") == turn_three.recording_hash, "Turn 4 plays over turn 3, which nests turns 1 and 2")
	_check(run.fail_solo(journal, tries, "failed_turn", slip, TIDE) and journal.pairs().is_empty() and journal.passes().is_empty(), "A slip on turn 4 ends the run and starts it again")
	HardMode.wait_writes()
	var kept: Array[Dictionary] = HardMode.runs(TIDE)
	var slipped: Dictionary = kept[0] if kept.size() == 1 else {}
	_check(not slipped.is_empty() and slipped.slip.prior.get("recording_hash") == turn_three.recording_hash and hashes.call(slipped.slip.get(HardMode.CHAIN, [])) == hashes.call([a, turn_two]) and slipped.role == "b", "The slip is kept with turn 3 as its memory and turns 1 and 2 under it")
	if slipped.is_empty(): return
	var part: Dictionary = HardMode.watch_pairs(slipped)[0]
	var turns := OpenTurns.pair_turns(part)
	_check(hashes.call(turns) == hashes.call([a, turn_two, turn_three, slip]) and Canonical.same(part.start, start), "Watching it plays the slip from its checkpoint over every turn before it")
	var sim := Simulation.new()
	_check(Registry.reset_simulation(sim, TIDE, level, STAGE, part.start, turns[-2], "b", turns[-1], turns.slice(0, turns.size() - 2)), "The slip starts over its kept memories (%s)" % sim.error)
	for input: Dictionary in Simulation.expand_recording_inputs(slip): sim.step(input)
	_check(Canonical.same(_json(sim.export_recording()), slip), "and plays back byte for byte")
	var viewer: Node = await _hard_viewer({"chapter_key": TIDE, "kind": "watch", "run": slipped})
	_check(viewer.mode == "replay" and viewer.replay_pair_index == 0 and viewer.sim.get("role") == "b", "The chapter screen opens the kept slip in its replay (%s)" % viewer.mode)
	# Carry-over turns: the screen plays the stage's shared timeline straight through, the slip last.
	var stretches: Array = viewer._replay_stretches
	var ticks := 0
	while viewer.mode == "replay" and ticks < 6000:
		if viewer.replay_cursor < viewer.replay_frames.size(): viewer.advance_input({})
		elif not viewer._next_stretch(): break
		ticks += 1
	_check(stretches == OpenTurnStore.timeline(turns) and not stretches.is_empty() and viewer._replay_stretch == stretches.size() - 1 and viewer.replay_cursor == viewer.replay_frames.size() and viewer.replay_frames.size() == int(slip.duration_ticks), "and plays the stage's timeline up to the slip (stretch %d of %d, %s)" % [viewer._replay_stretch + 1, stretches.size(), viewer.mode])
	await _close_hard_viewer(viewer)
	# A finished stage: kept with its passes, and its closing turn replays over them.
	_check(journal.accept_recording(a) and journal.accept_recording(turn_two) and journal.accept_recording(turn_three) and journal.accept_recording(closing), "The run plays the stage again in four turns (%s)" % journal.last_error)
	run.complete_solo(journal)
	HardMode.wait_writes()
	var done: Array = HardMode.runs(TIDE).filter(func(item: Dictionary) -> bool: return item.kind == HardMode.COMPLETE)
	var whole: Dictionary = done[0] if done.size() == 1 else {}
	_check(not whole.is_empty() and whole.pairs[0].get("passes", []).size() == 2 and HardMode.new(HARD_MARKS).completed(TIDE, HardMode.SOLO), "A finished run is kept with the stage's passes and marked")
	if whole.is_empty(): return
	_check(int(HardMode.summary(whole).parts) == 1 and HardMode.runs(TIDE).size() == 2, "It lists as one part beside the slip")
	_check(Canonical.same(CheckpointPairs.derive(Simulation, level, start, HardMode.watch_pairs(whole)[0]).get("checkpoint"), _stage_checkpoint), "Its stage derives the same checkpoint when watched")
	viewer = await _hard_viewer({"chapter_key": TIDE, "kind": "watch", "id": str(whole.id)})
	var timeline := OpenTurnStore.timeline([a, turn_two, turn_three, closing])
	_check(viewer.mode == "replay" and viewer._replay_stretches == timeline and not timeline.is_empty() and timeline[-1] == {"turn": 3, "ticks": -1} and viewer.sim.get("role") == "b", "The chapter screen replays the stage straight through its timeline, the closing turn last (%s)" % viewer.mode)
	await _close_hard_viewer(viewer)
	# Turns that do not chain are refused when watched.
	var shuffled: Dictionary = whole.duplicate(true)
	shuffled.pairs[0].passes = [turn_three, turn_two]
	_check(HardMode.valid_run(shuffled) and not CheckpointPairs.derive(Simulation, level, start, HardMode.watch_pairs(shuffled)[0]).get("valid", false), "Passes out of order are refused when watched")
	var gap: Dictionary = slipped.duplicate(true)
	gap.slip[HardMode.CHAIN] = [turn_two]
	var broken: Dictionary = HardMode.watch_pairs(gap)[0]
	var broken_turns := OpenTurns.pair_turns(broken)
	_check(not Registry.reset_simulation(Simulation.new(), TIDE, level, STAGE, broken.start, broken_turns[-2], "b", broken_turns[-1], broken_turns.slice(0, broken_turns.size() - 2)), "A slip missing a turn under its memory does not replay")
	# Shapes a run never has are refused.
	for bad: Variant in [[], [7], [turn_two, "x"]]:
		var odd: Dictionary = whole.duplicate(true)
		odd.pairs[0].passes = bad
		_check(not HardMode.valid_run(odd) and not HardMode.save_run(odd), "A stage with passes %s is refused" % str(bad).left(24))
	var extra: Dictionary = whole.duplicate(true)
	extra.pairs[0].more = [turn_two]
	_check(not HardMode.valid_run(extra), "A stage with another field is refused")
	for bad: Variant in [[], [3], "x"]:
		var odd: Dictionary = slipped.duplicate(true)
		odd.slip[HardMode.CHAIN] = bad
		_check(not HardMode.valid_run(odd), "A slip with chain %s is refused" % str(bad))
	var first_turn: Dictionary = slipped.duplicate(true)
	first_turn.slip.prior = {}
	_check(not HardMode.valid_run(first_turn), "A chain under no memory is refused")
	# A two-turn slip (and a first turn) keeps exactly its three fields.
	_check(HardMode.kept_slip(slip, start, a).keys() == ["recording", "checkpoint", "prior"] and HardMode.kept_slip(slip, start, {}, [a]).size() == 3 and HardMode.kept_slip(slip, start, turn_three, [a, turn_two]).size() == 4, "Only a slip over a pass keeps a chain")
	_clear_hard()

func _hard_viewer(request: Dictionary) -> Node:
	HardMode.hand_over(request)
	var viewer: Node = load(Index.data(TIDE).scene).instantiate()
	viewer.settings = {"sound": false, "haptics": false, "reduced_motion": true, "assistance": true, "left_handed": false}
	root.add_child(viewer)
	viewer.set_physics_process(false)
	viewer.set_process(false)
	await process_frame
	return viewer

func _close_hard_viewer(viewer: Node) -> void:
	viewer.set_block_signals(true)
	viewer._leaving = true
	viewer.queue_free()
	await process_frame

func _clear_hard() -> void:
	HardMode.wait_writes()
	for path: String in [HardMode.journal_path(TIDE), HardMode.runs_path(TIDE), HardMode.INDEX_PATH, HARD_MARKS, HARD_TRIES]:
		for suffix: String in ["", ".tmp", ".backup"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))

## The same four turns as the engine records them with nothing set: packed
## (open turns always are, runtime.gd), each replaying exactly; the closing turn
## is the same whether each turn starts from its kept start world or plays the
## stage's turns again; the checkpoint holds them packed and plays back in
## the replay view.
func _packed_chain() -> void:
	if _stage.size() < 4: return
	var level := Registry.definition(TIDE)
	var start := Registry.initial_checkpoint(TIDE)
	var a: Dictionary = _stage[0]
	var pass_two: Dictionary = _stage[1]
	var pass_three: Dictionary = _stage[2]
	_check(_stage.all(func(turn: Dictionary) -> bool: return RecordingCodec.is_packed(turn)), "Every turn records packed with nothing set")
	var closing := {}
	for kept: bool in [true, false]:
		# Kept start worlds, then none: the same closing turn.
		MemoryTrace.clear()
		MemoryTrace.enabled = kept
		var four := Simulation.new()
		_check(four.reset(level, STAGE, start, pass_three, "b", 0, [a, pass_two]), "Turn 4 starts over the packed passes (%s)" % four.error)
		var frames: Array = Simulation.expand_recording_inputs(_stage[3])
		for frame: Dictionary in frames: four.step(frame)
		var record: Dictionary = _json(four.export_recording())
		_check(four.complete and Canonical.same(record, _stage[3]), "The packed closing turn finishes the same whether its start world is kept or not (kept %s)" % kept)
		closing = record
	MemoryTrace.enabled = true
	var derived := Simulation.derive_checkpoint(level, start, a, closing, [pass_two, pass_three])
	_check(derived.valid and derived.checkpoint.proof.turns.all(func(turn: Dictionary) -> bool: return RecordingCodec.is_packed(turn)), "The closing checkpoint holds every turn packed (%s)" % str(derived.get("error", "")))
	if not derived.valid: return
	MemoryTrace.clear()
	_check(Simulation.verify_checkpoint(level, derived.checkpoint).valid, "The packed checkpoint proves from scratch")
	# The replay view plays each later turn from the one before it (shared_replay_view.gd).
	var turns := OpenTurns.pair_turns(CheckpointPairs.pair(TIDE, derived.checkpoint, 0, 0))
	var sim := Simulation.new()
	_check(Registry.reset_simulation(sim, TIDE, level, STAGE, start, turns[2], "b", turns[3], turns.slice(0, 2)), "The replay starts the closing turn from its hand-off (%s)" % sim.error)
	for input: Dictionary in Simulation.expand_recording_inputs(turns[3]): sim.step(input)
	_check(Canonical.same(_json(sim.export_recording()), closing), "and plays it back byte for byte, packed")

## A solo run of every open turns chapter with each stage at its cap and every
## turn its widest at the chapter's limit (a new stick every tick): saved as
## the journal saves it (attempt_archive.gd), it stays under half the save's cap,
## where the same run in JSON would not fit at all.
func _solo_size() -> void:
	var keys: Array = Registry.keys().filter(func(key: String) -> bool: return OpenTurns.pinned(Registry.definition(key)))
	_check(TIDE in keys, "Every open turns chapter is sized, Tide@3 among them")
	for key: String in keys:
		var level := Registry.definition(key)
		var rules := Registry.preferred_rules(key)
		var ticks := Simulation.turn_ticks(level, rules, "b")
		var actions: Array = []
		for tick in ticks: actions.append({"ticks": 1, "x": 100 if tick % 2 else -100, "z": -100, "action": tick % 3 == 0})
		var checks: Array = []
		for tick in range(RecordingCodec.CHECK_EVERY, ticks, RecordingCodec.CHECK_EVERY): checks.append({"tick": tick, "state_hash": "f".repeat(64)})
		checks.append({"tick": ticks, "state_hash": "f".repeat(64)})
		var pairs: Array = []
		var json_pairs: Array = []
		var turns := 0
		for stage: Dictionary in level.stages:
			var list: Array = []
			for n in range(1, OpenTurns.cap(stage) + 1):
				var record := {"schema_version": 7, "simulation_version": rules, "level_id": level.id, "level_version": level.version, "definition_hash": "f".repeat(64), "stage_id": stage.id,
					"stage_version": 1, "checkpoint_hash": "f".repeat(64), "role": "a" if n == 1 else "b", "player_slot": OpenTurns.slot(str(stage.first_player_slot), n), "tick_rate": 30,
					"duration_ticks": ticks, "catch_assistance": false, "actions": actions, "replay_checks": checks, "final_state_hash": "f".repeat(64), "completed": n == OpenTurns.cap(stage),
					"outcome": {"source_ready": true, "objective_complete": n == OpenTurns.cap(stage)}, "source_recording_hash": "" if n == 1 else "f".repeat(64), "recording_hash": "f".repeat(64),
					"handoff_tick": ticks, "start_hash": "f".repeat(64), "handoff_hash": "f".repeat(64)}
				list.append(record)
			turns += list.size()
			var packed: Array = []
			for record: Dictionary in list:
				var form := RecordingCodec.packed_form(record)
				form["recording_hash"] = "f".repeat(64)
				packed.append(form)
			pairs.append({"a": packed[0], "b": packed[-1], "passes": packed.slice(1, packed.size() - 1)})
			json_pairs.append({"a": list[0], "b": list[-1], "passes": list.slice(1, list.size() - 1)})
		var bytes := JSON.stringify(Canonical.normalized({"archive_version": 1, "relay": {"pairs": pairs, "a": {}, "draft": {}}})).to_utf8_buffer().size()
		var json_bytes := JSON.stringify(Canonical.normalized({"archive_version": 1, "relay": {"pairs": json_pairs, "a": {}, "draft": {}}})).to_utf8_buffer().size()
		print("OPEN TURNS: a solo %s run of %d turns of %d ticks at their widest saves %d bytes packed, %d as JSON (cap %d)" % [key, turns, ticks, bytes, json_bytes, Journey.MAX_SAVE_BYTES])
		_check(bytes * 2 < Journey.MAX_SAVE_BYTES, "A solo %s run of every stage at its cap of the widest turns stays under half the save's cap packed" % key)

## The largest solo journal any open turns level can make at WORST_TURN_TICKS:
## four stages of OpenTurns.MAX_CAP turns plus a draft, every turn its widest
## with random sticks, presses and hashes (the least a recording compresses).
## Raw it stays under half the save's cap; a journal at the cap, compressed as
## this one does, still fits the Saved Games progress slot alone; and a proof
## or a Hard run as big as two such journals keeps its file.
const WORST_STAGES := 4
## 150 s. At 4 x 20 turns about 160 s is the longest that keeps the half-cap
## margin; 600 s turns (6.7 MB raw, 4.6 MB zstd) fit no Saved Games slot.
const WORST_TURN_TICKS := 4500
const Bundle = preload("res://services/platform_games/cloud_save_bundle.gd")
const Proofs = preload("res://services/journey_proofs.gd")
const HardMode = preload("res://services/hard_mode.gd")
func _solo_worst_case() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261116
	var hex := func() -> String:
		var raw := PackedByteArray()
		for i in 32: raw.append(rng.randi() % 256)
		return raw.hex_encode()
	var level := Registry.definition(TIDE)
	var rules := Registry.preferred_rules(TIDE)
	var turn := func(stage: int, n: int, last: bool) -> Dictionary:
		var actions: Array = []
		var x := 0
		for tick in WORST_TURN_TICKS:
			var next := rng.randi_range(-100, 100)
			x = next if next != x else -next if next != 0 else 1
			actions.append({"ticks": 1, "x": x, "z": rng.randi_range(-100, 100), "action": rng.randi() % 2 == 0})
		var checks: Array = []
		for tick in range(RecordingCodec.CHECK_EVERY, WORST_TURN_TICKS, RecordingCodec.CHECK_EVERY): checks.append({"tick": tick, "state_hash": hex.call()})
		var final_hash: String = hex.call()
		checks.append({"tick": WORST_TURN_TICKS, "state_hash": final_hash})
		var form := RecordingCodec.packed_form({"schema_version": 7, "simulation_version": rules, "level_id": level.id, "level_version": level.version, "definition_hash": hex.call(),
			"stage_id": "stage-%d" % stage, "stage_version": 1, "checkpoint_hash": hex.call(), "role": "a" if n == 1 else "b", "player_slot": OpenTurns.slot("p0", n), "tick_rate": 30,
			"duration_ticks": WORST_TURN_TICKS, "catch_assistance": false, "actions": actions, "replay_checks": checks, "final_state_hash": final_hash, "completed": last,
			"outcome": {"source_ready": true, "objective_complete": last}, "source_recording_hash": "" if n == 1 else hex.call(), "recording_hash": "",
			"handoff_tick": WORST_TURN_TICKS, "start_hash": hex.call(), "handoff_hash": hex.call()})
		form["recording_hash"] = hex.call()
		return form
	var pairs: Array = []
	for stage in WORST_STAGES:
		var list: Array = []
		for n in range(1, OpenTurns.MAX_CAP + 1): list.append(turn.call(stage, n, n == OpenTurns.MAX_CAP))
		pairs.append({"a": list[0], "b": list[-1], "passes": list.slice(1, list.size() - 1)})
	var relay := {"schema_version": 2, "simulation_version": rules, "level_id": level.id, "level_version": level.version, "definition_hash": hex.call(), "pairs": pairs, "a": {}, "draft": turn.call(WORST_STAGES, 1, false)}
	var envelope := {"version": 1, "generation": 1, "settings": {}, "attempts": {}, "completed": {}, "replays": {}, "room": {}, "relay": relay}
	var raw := JSON.stringify(envelope).to_utf8_buffer()
	var packed := raw.compress(FileAccess.COMPRESSION_ZSTD).size()
	var encoded := Bundle.encode(Bundle.collect({}, 0, {}, {"the-falls-journey-v2.json": envelope}))
	var at_cap := ceili(float(encoded.size()) * Journey.MAX_SAVE_BYTES / raw.size())
	print("OPEN TURNS: the worst solo journal, %d stages of %d turns of %d ticks, saves %d bytes (%d a turn), %d zstd (%.3f); at the cap of %d it fills the slot to %d of %d" % [WORST_STAGES, OpenTurns.MAX_CAP, WORST_TURN_TICKS, raw.size(), raw.size() / (WORST_STAGES * OpenTurns.MAX_CAP + 1), packed, float(packed) / raw.size(), Journey.MAX_SAVE_BYTES, at_cap, Bundle.MAX_BYTES])
	_check(raw.size() * 2 < Journey.MAX_SAVE_BYTES, "The worst solo journal stays under half the save's cap")
	_check(Bundle.journal_stages(Bundle.decode(encoded).get("journals", {}).get("the-falls-journey-v2.json", {}).get("envelope")) == WORST_STAGES, "It backs up whole to the Saved Games progress slot")
	_check(at_cap <= Bundle.MAX_BYTES, "A journal at the save's cap, as random, still fits the progress slot")
	_check(Proofs.MAX_FILE_BYTES >= 2 * Journey.MAX_SAVE_BYTES and HardMode.MAX_RUNS_BYTES >= 2 * Journey.MAX_SAVE_BYTES, "A proof file and a Hard runs file hold two journals at the cap")

## The hand-off on Set the Tide, with a later turn 2 so turn 3 takes over
## mid-replay (H = turn 1's length, M = the rest of turn 2):
## - nothing acts twice: turn 1's tide presses land once, in turn 2's world,
##   and turn 3 starts after them with the tide as turn 1 left it; standing
##   still, the first pip never moves again in turn 3;
## - divergence only comes from the live pip: a live pip that plays what its
##   old self did (standing still once its turn was over) keeps the world
##   exactly the friend's turn's, tick for tick, in turns 2, 3 and 4;
## - a drowned friend fails the turn: in turn 2 the live pip unhooks the line
##   while turn 1's replay stands on the bollard step, the step shuts under it
##   and the turn ends with DROWNED_FRIEND, unsaved and with no draft.
## Then ten turns of passes, each checked once: one check of the latest covers
## the stage, and the same turns record the same whether start worlds are
## kept or the stage's turns are played again. Prints the check's time.
func _memories() -> void:
	var level := Registry.definition(TIDE)
	var start := Registry.initial_checkpoint(TIDE)
	var a := _first()
	var b_frames: Array = Simulation.expand_recording_inputs(_fixture("turn-of-the-tide-v3-set-the-tide-b.json"))
	var length := int(a.duration_ticks)
	var extra := 123
	var still := {}
	# Turn 2: the second pip's route to where turn 1 ended, then standing until extra ticks later.
	var two := Simulation.new()
	two.reset(level, STAGE, start, a, "b")
	var presses := 0
	while int(two.tick) < length + extra:
		two.step(b_frames[two.tick] if int(two.tick) < length else still)
		presses += two._events.filter(func(event: String) -> bool: return event == "selector:tide").size()
	two.pass_turn()
	var pass_two: Dictionary = _json(two.export_recording())
	_check(two.passed and presses == 2, "Turn 1's two tide presses land once each, in turn 2's world (%d)" % presses)
	var three := Simulation.new()
	_check(three.reset(level, STAGE, start, pass_two, "b", 0, [a]) and three.handoff_tick == length and three.replay_ticks() == extra, "Turn 3 takes over at turn 1's end with turn 2's last %d ticks to replay (%s)" % [extra, three.error])
	_check(str(three._mechanisms.controls.tide) == str(two._mechanisms.controls.tide) and three.world_hash() == pass_two.handoff_hash, "Turn 3 starts with the tide turn 1 left, nothing played again")
	var stood: Dictionary = three._players[three.active_slot].duplicate()
	var moved := false
	presses = 0
	while int(three.tick) < extra + 60:
		three.step(still)
		moved = moved or not Canonical.same(three._players[three.active_slot], stood)
		presses += three._events.filter(func(event: String) -> bool: return event.begins_with("selector:") or event == "lever").size()
	_check(not moved and presses == 0, "Standing still, the first pip's old self never acts again in turn 3")
	three.pass_turn()
	var pass_three: Dictionary = _json(three.export_recording())
	# The live pip doing what its old self did keeps the friend's world, tick for tick.
	_check(_follows(level, start, a, {}, [], []), "Turn 2 with the live pip still is turn 1's world, tick for tick")
	_check(_follows(level, start, pass_two, a, [], []), "Turn 3 with the live pip still is turn 2's world from the hand-off on, tick for tick")
	_check(_follows(level, start, pass_three, pass_two, [a], []), "Turn 4 with the live pip still is turn 3's world from the hand-off on, tick for tick")
	# A drowned friend fails the turn.
	var drown := Simulation.new()
	drown.reset(level, STAGE, start, a, "b")
	while int(drown.tick) < length - 150 and not drown.finished: drown.step(still)
	_check(str(drown._players.p0.surface_id) == "bollard-step", "Turn 1's replay stands on the bollard step (%s)" % str(drown._players.p0.surface_id))
	var line := Simulation._entity(drown.stage.levers, "line")
	drown._players[drown.active_slot] = {"x": int(line.position_cm[0]), "z": int(line.position_cm[1]), "height": int(line.height_cm), "surface_id": str(line.surface_id)}
	_check(drown.context_action().id == "lever" and drown.context_action().target_id == "line", "The live pip may unhook the line (%s)" % str(drown.context_action()))
	drown.step({"interact": true})
	while not drown.finished: drown.step(still)
	var drowned: Dictionary = drown.snapshot().drowned
	_check(drowned.get("slot") == "p0" and drowned.get("route") == "bollard-step", "The step shuts under the friend's replay and it drowns (%s)" % str(drowned))
	_check(drown.commit_reason() == Simulation.DROWNED_FRIEND and not drown.can_commit() and not drown.can_pass() and not drown.keeps_draft(), "The turn fails with DROWNED_FRIEND, cannot be saved or passed and keeps no draft")
	# Ten turns of passes.
	var short := _passes(level, start, a, 10, length)
	if short.size() < 10: return
	MemoryTrace.clear()
	var started := Time.get_ticks_msec()
	var checked := Simulation.verify_recording(level, short[-1], start, short[-2], short.slice(0, short.size() - 2))
	print("OPEN TURNS: turn 10's check, playing the nine turns before it once each, took %d ms (%d ticks a turn)" % [Time.get_ticks_msec() - started, length])
	# Turn 10 is the stage's cap: it checks, but can be no pass (only finishing the stage keeps it).
	_check(checked.valid and not checked.get("ready", false) and MemoryTrace.simulated == 10, "Turn 10 checks, each turn simulated once, and on the cap is no pass (%s, %d)" % [str(checked.get("error", "")), MemoryTrace.simulated])
	MemoryTrace.clear()
	MemoryTrace.enabled = false
	var again := _passes(level, start, a, 6, length)
	MemoryTrace.enabled = true
	_check(again.size() == 6 and Canonical.same(again, short.slice(0, 6)), "With no kept start worlds, turns record the same")
	MemoryTrace.clear()
	var cold := Simulation.verify_recording(level, short[5], start, short[4], short.slice(0, 4))
	_check(cold.valid and Canonical.same(cold, Simulation.verify_recording(level, short[5], start, short[4], short.slice(0, 4))), "A kept check is the check")

## Whether turn `record`'s world, its live pip standing still (or playing
## `live`, its inputs), is the friend's turn `prior`'s from the hand-off on,
## tick for tick, for as long as the replay plays (all of turn 1 for turn 2).
## `before`: the turn before prior, `chain` the turns before that. With an
## empty `prior`, `record` is turn 2 over turn 1 (`before` empty too).
func _follows(level: Dictionary, start: Dictionary, prior: Dictionary, before: Dictionary, chain: Array, live: Array) -> bool:
	# The friend's turn played again, its world hash each tick.
	var friend := Simulation.new()
	var first: bool = before.is_empty() and chain.is_empty() and prior.role == "a"
	friend.reset(level, STAGE, start, before if not first else {}, "a" if first else "b", 0, chain)
	var worlds: Array = [friend.world_hash()]
	for frame: Dictionary in Simulation.expand_recording_inputs(prior):
		friend._tick(frame)
		worlds.append(friend.world_hash())
	var next := Simulation.new()
	if not next.reset(level, STAGE, start, prior, "b", 0, chain + ([] if first else [before])): return false
	if next.world_hash() != worlds[next.handoff_tick]: return false
	for tick in range(next.replay_ticks()):
		next._tick(live[tick] if tick < live.size() else {})
		if next.world_hash() != worlds[next.handoff_tick + tick + 1]: return false
	return true

## Ten 100 s turns (the tide's longest), every checked turn persisted as the
## phone keeps them: turn 10 starts and checks from turn 9's kept start world,
## and again from the files after a restart. Prints how long each takes.
func _long_turns() -> void:
	var level := Registry.definition(TIDE)
	var start := Registry.initial_checkpoint(TIDE)
	var a := _first()
	TraceStore.attach(TRACES)
	var long_ticks := Simulation.turn_ticks(level, 19, "b") - 10
	var long := _passes(level, start, a, 10, long_ticks)
	if long.size() < 10: return
	var memory: Dictionary = long[-2]
	var before: Array = long.slice(0, long.size() - 2)
	var started := Time.get_ticks_msec()
	var ten := Simulation.new()
	var ten_started := ten.reset(level, STAGE, start, memory, "b", 0, before)
	var reset_ms := Time.get_ticks_msec() - started
	started = Time.get_ticks_msec()
	var ten_checked := Simulation.verify_recording(level, long[-1], start, memory, before)
	print("OPEN TURNS: 100 s turns (%d ticks), turn 10 starts in %d ms and checks in %d ms with its start world kept" % [long_ticks, reset_ms, Time.get_ticks_msec() - started])
	_check(ten_started and ten_checked.valid and not ten_checked.get("ready", false), "Turn 10 of 100 s turns starts and checks, the cap's turn no pass (%s)" % ten.error)
	# After a restart: nothing in memory, the kept turns read back from their files.
	MemoryTrace.clear()
	started = Time.get_ticks_msec()
	var again := Simulation.new()
	var again_started := again.reset(level, STAGE, start, memory, "b", 0, before)
	reset_ms = Time.get_ticks_msec() - started
	started = Time.get_ticks_msec()
	var again_checked := Simulation.verify_recording(level, long[-1], start, memory, before)
	print("OPEN TURNS: after a restart turn 10 starts in %d ms and checks in %d ms from the kept files" % [reset_ms, Time.get_ticks_msec() - started])
	_check(again_started and again_checked.valid and not again_checked.get("ready", false) and MemoryTrace.simulated == 0, "After a restart turn 10 starts and checks from its kept files, simulating nothing")
	var frames: Array = Simulation.expand_recording_inputs(long[-1])
	for frame: Dictionary in frames: again._tick(frame)
	again.pass_turn()
	_check(Canonical.same(_json(again.export_recording()), long[-1]), "A memory read back from its file plays the same turn")
	TraceStore.detach()
	for name: String in DirAccess.get_files_at(TRACES): DirAccess.remove_absolute(TRACES.path_join(name))

## `count` turns of one stage, every one `ticks` long: turn 1's route and
## then the second pip's up to turn 1's length, each then standing still, and
## every later turn standing still; each passes. [] when one cannot.
func _passes(level: Dictionary, start: Dictionary, a: Dictionary, count: int, ticks: int) -> Array:
	var routes := [Simulation.expand_recording_inputs(a), Simulation.expand_recording_inputs(_fixture("turn-of-the-tide-v3-set-the-tide-b.json"))]
	var first := a
	if ticks > int(a.duration_ticks):
		var one := Simulation.new()
		one.reset(level, STAGE, start, {}, "a")
		while int(one.tick) < ticks: one._tick(routes[0][one.tick] if int(one.tick) < routes[0].size() else {})
		first = _json(one.export_recording())
	var turns: Array = [first]
	for n in range(2, count + 1):
		var sim := Simulation.new()
		if not sim.reset(level, STAGE, start, turns[-1], "b", 0, turns.slice(0, turns.size() - 1)):
			_check(false, "Turn %d starts (%s)" % [n, sim.error])
			return []
		var frames: Array = routes[1] if n == 2 else []
		while int(sim.tick) < ticks and not sim.finished: sim._tick(frames[sim.tick] if int(sim.tick) < mini(frames.size(), int(a.duration_ticks)) else {})
		# These turns measure checks, not the cap: the cap's turn passes here too.
		sim.pass_allowed = true
		if not sim.can_pass():
			_check(false, "Turn %d may pass (%s)" % [n, sim.commit_reason()])
			return []
		sim.pass_turn()
		turns.append(_json(sim.export_recording()))
	return turns

## The save, load and step round trip, on every open level's first stage
## (its witness route's turns 1 and 2) and the four turns of _chain's stage.
func _round_trips() -> void:
	var keys: Array = Registry.keys().filter(func(key: String) -> bool: return OpenTurns.pinned(Registry.definition(key)))
	_check(keys.size() >= 10, "Every open level takes the round trip (%d)" % keys.size())
	var ticks := 0
	var started := Time.get_ticks_msec()
	for key: String in keys:
		var level := Registry.definition(key)
		var start := Registry.initial_checkpoint(key)
		var stage_id := str(level.stages[0].id)
		var steps: Array = Witness._turn_steps(Witness.routes(key).get(stage_id))
		if steps.size() < 2:
			_check(false, "%s has a witness route for its first stage" % key)
			continue
		var script: Script = Registry.simulation_script(key)
		var one: RefCounted = script.new()
		one.reset(level, stage_id, start, {}, "a")
		Witness._play(one, steps[0])
		var first: Dictionary = _json(one.export_recording())
		var two: RefCounted = script.new()
		two.reset(level, stage_id, start, first, "b")
		Witness._play(two, steps[1])
		while not two.finished and not two.can_pass() and int(two.tick) < int(two.duration_limit()): two.step({})
		var second: Dictionary = _json(two.export_recording())
		ticks += int(first.duration_ticks) + int(second.duration_ticks)
		_check(_round_trip(script, level, stage_id, start, first, {}, []), "%s: turn 1 steps the same from its world saved and loaded on every tick" % key)
		_check(_round_trip(script, level, stage_id, start, second, first, []), "%s: turn 2 steps the same from its world saved and loaded on every tick" % key)
	if _stage.size() < 4: _chain()
	if _stage.size() == 4:
		var level := Registry.definition(TIDE)
		var start := Registry.initial_checkpoint(TIDE)
		for index in range(4):
			var prior: Dictionary = _stage[index - 1] if index > 0 else {}
			ticks += int(_stage[index].duration_ticks)
			_check(_round_trip(Simulation, level, STAGE, start, _stage[index], prior, _stage.slice(0, maxi(0, index - 1))), "Set the Tide turn %d steps the same from its world saved and loaded on every tick" % (index + 1))
	print("OPEN TURNS: the round trip took %d ms over %d ticks" % [Time.get_ticks_msec() - started, ticks])

## Plays `record` (over `prior` after `chain`) straight through; before each
## tick a fresh engine, a copy of the turn as it started, takes the straight
## run's world there (save_world, load_world with the friend's replay H + tick
## on) and plays the same input. Its world must be the straight run's after
## every tick, so the world holds everything a tick reads.
func _round_trip(script: Script, level: Dictionary, stage_id: String, start: Dictionary, record: Dictionary, prior: Dictionary, chain: Array) -> bool:
	var straight: RefCounted = script.new()
	straight.catch_assistance = bool(record.catch_assistance)
	if not straight.reset(level, stage_id, start, prior, str(record.role), 0, chain): return false
	var pristine: RefCounted = Frozen.of(straight)
	var frames: Array = script.expand_recording_inputs(record)
	for tick in range(frames.size()):
		if straight.finished: break
		var fresh: RefCounted = Frozen.of(pristine)
		fresh.load_world(straight.save_world(), int(straight.handoff_tick) + tick)
		straight._tick(frames[tick])
		fresh._tick(frames[tick])
		if fresh.save_world() != straight.save_world() or fresh.complete != straight.complete:
			push_error("Round trip differs at tick %d of %s/%s" % [tick, str(level.id), stage_id])
			return false
	return true

## A published tide stage (rules 10) still nests a and b.
func _published() -> void:
	var key := "turn-of-the-tide@2"
	var level := Registry.definition(key)
	var a := _fixture("turn-of-the-tide-v2-set-the-tide-a.json")
	var b := _fixture("turn-of-the-tide-v2-set-the-tide-b.json")
	var derived := Simulation.derive_checkpoint(level, Registry.initial_checkpoint(key), a, b)
	_check(derived.valid and derived.checkpoint.has("a_recording_hash") and not derived.checkpoint.has("turn_hashes") and derived.checkpoint.proof.has("a"), "A published stage keeps its two turn checkpoint")
	var ending: Dictionary = _fixture("turn-of-the-tide-v2-set-the-tide-checkpoint.json")
	_check(derived.valid and Canonical.same(derived.checkpoint, ending), "byte for byte as its fixture")

func _fixture(name: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/journey/" + name))

static func _json(value: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(value))

func _dots() -> void:
	_check(TurnDots.view({"turn": 4, "cap": 10, "must_finish": false}, "p1") == {"turn": 4, "cap": 10, "first_slot": "p1", "last": 0, "edge": false}, "Mid stage, no turn wears the last turn's ring")
	_check(TurnDots.view({"turn": 9, "cap": 10, "must_finish": false}, "p0").last == 10, "With the cap's turn next, its dot wears the ring")
	var last := TurnDots.view({"turn": 10, "cap": 10, "must_finish": true}, "p0")
	_check(last.last == 10 and last.edge, "The cap's turn must finish: ring and coral edge")
	var early := TurnDots.view({"turn": 6, "cap": 20, "must_finish": true}, "p0")
	_check(early.last == 6 and early.edge, "A turn that must finish early (the stage's bytes ran out) wears the ring itself")
	_check(TurnDots.view({"turn": 3, "cap": 10}, "").is_empty() and TurnDots.view({}, "p0").is_empty(), "No stage or no count draws no dots")

## Solo: the journal counts a stage's turns as a room does, its player_slot
## the pip this turn steers, and the chapter screen shows its dots with no
## room (relay_preview.gd _open_turns_view), never in a replay.
func _solo_dots(journal: RefCounted, turn: int, first: String) -> void:
	var level := Registry.definition(TIDE)
	var index: int = level.stages.map(func(stage: Dictionary) -> String: return str(stage.id)).find(STAGE)
	var open: Dictionary = journal.open_turns()
	var steered := OpenTurns.slot(first, turn)
	_check(open == {"turn": turn, "cap": OpenTurns.cap(level.stages[index]), "must_finish": false, "player_slot": steered, "stage_index": index}, "Solo turn %d: the journal counts it as a room does (%s)" % [turn, open])
	var screen := Screen.new()
	screen.journey = journal
	screen.definition = level
	screen.mode = "play"
	_check(screen.online_session == null and not open.is_empty() and screen._open_turns_view() == TurnDots.view(open, first), "Solo turn %d shows the turn dots" % turn)
	_check(screen._own_room_color() == (SpiritLook.PEACH if steered == "p0" else SpiritLook.MINT), "Solo turn %d: the Last turn pill wears the steered pip's colour" % turn)
	screen.mode = "replay"
	_check(screen._open_turns_view().is_empty(), "A Solo replay shows no turn dots")
	screen.free()
	_check(Journey.new("", null, Registry.RELAY).open_turns().is_empty(), "A chapter without open turns counts none in Solo")

func _check(okay: bool, label: String) -> void:
	checks += 1
	if not okay:
		failures += 1
		push_error("FAIL " + label)

## Finish while the memory still plays, through the chapter screen.
func _end_early() -> void:
	var level := Registry.definition(TIDE)
	var start := Registry.initial_checkpoint(TIDE)
	var a := _first()
	var still := MemoryWait.STILL_INPUT
	var first := Simulation.new()
	first.reset(level, STAGE, start, {}, "a")
	_check(not first.can_end_early() and not first.snapshot().can_end_early, "A first turn has no memory to play out")
	for frame: Dictionary in Simulation.expand_recording_inputs(a): first.step(frame)
	var memory_end: Dictionary = first.snapshot().controls
	# The pip stands still from the start and ends its turn early; it records what a pip standing there would.
	var reference := Simulation.new()
	reference.reset(level, STAGE, start, a, "b")
	while int(reference.tick) < int(a.duration_ticks): reference.step(still)
	reference.pass_turn()
	var expected: Dictionary = _json(reference.export_recording())
	var press := 10
	for way: String in ["play", "fast_forward", "skip"]:
		var sim := Simulation.new()
		sim.reset(level, STAGE, start, a, "b")
		var run := _screen(sim, a)
		var screen: Screen = run.screen
		for _tick in range(press): screen.advance_input(still)
		var at_press: Dictionary = sim.snapshot().controls.duplicate()
		_check(sim.snapshot().can_end_early and not sim.can_pass(), "Finish is there while the memory plays: " + way)
		screen._finish()
		_check(screen.running and screen.memory_wait.waiting() and run.world.dozes > 0 and int(sim.tick) == press, "The pip dozes where it stands while the memory plays on: " + way)
		# A stick pushed and the action pressed meanwhile move nothing.
		screen.stick.value = Vector2(1, 0)
		screen.action_pressed = true
		if way == "fast_forward": run.controls.held = true
		if way == "skip": screen._skip_memory_wait()
		var guard := 0
		while screen.running and guard < 4000:
			screen._physics_process(1.0 / 30.0)
			guard += 1
		var recording: Dictionary = _json(sim.export_recording())
		_check(screen.ended == "passed" and sim.passed and int(sim.tick) == int(a.duration_ticks) and run.world.wakes == 1, "The pip wakes as the memory ends and the turn passes: %s (%s, tick %d)" % [way, screen.ended, int(sim.tick)])
		_check(Canonical.same(recording, expected), "The turn is the one a pip standing still until the memory ended records: " + way)
		_check(sim.snapshot().controls == memory_end and memory_end != at_press, "The memory's later presses still land: " + way)
		var checked := Simulation.verify_recording(level, recording, start, a)
		_check(checked.valid and checked.get("ready", false), "It replays exactly and may be the next memory: %s (%s)" % [way, str(checked.get("error", ""))])
		_free_screen(run)
	# A turn the room says must finish: once the memory is over the pip has its controls back.
	var last := Simulation.new()
	last.reset(level, STAGE, start, a, "b")
	last.pass_allowed = false
	var held := _screen(last, a)
	held.screen._finish()
	var steps := 0
	while held.screen.memory_wait.waiting() and steps < 4000:
		held.screen._physics_process(1.0 / 30.0)
		steps += 1
	_check(held.screen.running and not last.passed and not last.finished and not held.screen._standing_still(), "A turn that must finish gets its controls back once the memory is over")
	_free_screen(held)
	var controls := ChapterControls.new()
	root.add_child(controls)
	controls.update_state("", 30.0, {"can_end_early": true, "duration_ticks": 900}, true)
	_check(not controls.finish_button.disabled and controls.finish_button.visible, "Finish is offered while the memory plays")
	controls.update_state("", 30.0, {"duration_ticks": 900}, true)
	_check(controls.finish_button.disabled, "Without a way to end, Finish waits as before")
	controls.free()

func _screen(sim: RefCounted, prior: Dictionary) -> Dictionary:
	var screen := Screen.new()
	screen.memory_wait.skip_budget_usec = 1 << 40
	var controls := ScreenControls.new()
	var world := ScreenWorld.new()
	screen.chapter_key = TIDE
	screen.chapter = Registry.descriptor(TIDE)
	screen.definition = Registry.definition(TIDE)
	screen.checkpoint = Registry.initial_checkpoint(TIDE).duplicate()
	screen.settings = {"sound": false, "haptics": false, "reduced_motion": false, "skip_waits": false}
	screen.controls = controls
	screen.world = world
	screen.stick = Joystick.new()
	screen.sim = sim
	screen.role = "b"
	screen.mode = "play"
	screen.running = true
	screen._begin_memory_wait("b", prior)
	return {"screen": screen, "controls": controls, "world": world}

func _free_screen(run: Dictionary) -> void:
	run.screen.stick.free()
	for part: String in ["controls", "world", "screen"]: run[part].free()

## A first turn ended before its part is done, on open turns only.
func _early_first_turn() -> void:
	var level := Registry.definition(TIDE)
	var start := Registry.initial_checkpoint(TIDE)
	var frames: Array = Simulation.expand_recording_inputs(_first())
	var one := Simulation.new()
	one.reset(level, STAGE, start, {}, "a")
	for tick in range(20): one.step(frames[tick])
	var state: Dictionary = one.snapshot()
	_check(one.can_commit() and state.can_commit and not state.outcome.source_ready and state.objective_display.is_empty(), "A first turn may end at any time; its part is not done yet, and no card counts it")
	var older := Simulation.new()
	older.reset(level, STAGE, start, {}, "a")
	for tick in range(20): older.step(frames[tick])
	older.simulation_version = 13
	_check(not older.can_commit(), "On the tide rules before open turns (13) the same turn may not be saved")
	var early: Dictionary = _json(one.export_recording())
	var checked := Simulation.verify_recording(level, early, start)
	_check(checked.valid and checked.get("ready", false) and early.outcome.source_ready == false and early.completed == false, "It replays exactly and may be a memory (%s)" % str(checked.get("error", "")))
	var two := Simulation.new()
	_check(two.reset(level, STAGE, start, early, "b"), "The next turn plays over it (%s)" % two.error)
	_check(two.snapshot().objective_display.is_empty() and Registry.stage_presentation(TIDE, level.stages[0]).get("hint_b") == "", "Open turns show no Bell card and no bell hint")
	while int(two.tick) < int(early.duration_ticks): two.step({})
	two.pass_turn()
	var pass_two: Dictionary = _json(two.export_recording())
	var checked_two := Simulation.verify_recording(level, pass_two, start, early)
	_check(two.passed and checked_two.valid and checked_two.get("ready", false), "Its pass over the early first turn verifies (%s)" % str(checked_two.get("error", "")))
