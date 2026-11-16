extends SceneTree
## Open turns (core/physical/open_turns.gd) on Turn of the Tide@3's Set the
## Tide, played with the native fixture inputs:
## - every turn has the second turn's limit; ids and pips follow turn order;
## - turn 2 may pass once its memory is over, and the pass replays exactly and
##   is ready to be a memory; the room's must_finish takes the pass away;
## - turn 3 is the first pip's again, over turn 2 (which nests turn 1): the
##   memory pip is the second one, and the memory's own memory never acts;
##   there is no bell, and the first pip walks to the goal and passes, since
##   the second pip is not there (the witness route's third turn);
## - turn 4 plays the second pip's route over it and closes the stage with both
##   pips at the goal, and the checkpoint nests all four turns (schema 8),
##   checked again from scratch;
## - in a packed room every later turn records packed (core/v2/recording_codec.gd)
##   and plays as the next memory, kept or simulated, and the closing checkpoint
##   nests both forms;
## - a solo journal's "Redo my previous turn" takes back its latest pass, and
##   reopening a stage brings its passes back;
## - a published two turn stage still proves the published way;
## - the turn dots (presentation/kit/turn_dots.gd) ring the last turn: the cap's
##   once it is next, this one when the room says it must finish;
## - Finish while the memory still plays (relay_preview.gd _end_turn_early):
##   the pip dozes and stands still, played out live, fast-forwarded or
##   skipped; the memory's later presses still land, the turn is byte for byte
##   the one a still pip records and passes as before, a turn that must finish
##   hands the controls back, and with both pips at the goal at the memory's end
##   the stage completes. A first turn has no memory and keeps its own part.
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
const TRACES := "user://open-turns-test-traces"
const TIDE := "turn-of-the-tide@3"
const STAGE := "set-the-tide"
var checks := 0
var failures := 0

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

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	_rules()
	_chain()
	_packed_chain()
	_ten_turns()
	_published()
	_dots()
	_end_early()
	print("OPEN TURNS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _rules() -> void:
	_check(OpenTurns.rules(14) and OpenTurns.rules(15) and not OpenTurns.rules(12) and not OpenTurns.rules(13), "Open turns are 14 and 15")
	_check([1, 2, 3, 4].map(func(n: int) -> String: return OpenTurns.slot("p1", n)) == ["p1", "p0", "p1", "p0"], "Odd turns are the first pip's")
	_check(OpenTurns.turn_id(3, 1, 1) == "t3-1-a" and OpenTurns.turn_id(3, 1, 3) == "t3-1-c" and OpenTurns.turn_id(0, 0, 20) == "t0-0-t", "Turn ids keep a and b and go on by letter")
	var level := Registry.definition(TIDE)
	var first := Simulation.new()
	first.reset(level, STAGE, Registry.initial_checkpoint(TIDE), {}, "a")
	_check(first.duration_limit() == Simulation.turn_ticks(level, 15, "b"), "A first turn has the second turn's limit")

func _chain() -> void:
	var level := Registry.definition(TIDE)
	var start := Registry.initial_checkpoint(TIDE)
	var a := _fixture("turn-of-the-tide-v3-set-the-tide-a.json")
	var b := _fixture("turn-of-the-tide-v3-set-the-tide-b.json")
	var a_frames: Array = Simulation.expand_recording_inputs(a)
	var b_frames: Array = Simulation.expand_recording_inputs(b)
	# Turn 2: the second pip's route, stopped before it lights the goal, once the memory is over.
	var two := Simulation.new()
	_check(two.reset(level, STAGE, start, a, "b"), "Turn 2 starts over turn 1 (%s)" % two.error)
	_check(two.turn_number == 2 and two.active_slot == OpenTurns.slot(str(two.first_player_slot), 2) and two.memory_slot == two.first_player_slot, "Turn 2 is the second pip's, over the first")
	var cut := int(a.duration_ticks)
	while int(two.tick) < cut: two.step(b_frames[two.tick] if int(two.tick) < b_frames.size() else {})
	_check(not two.complete and two.can_pass(), "Turn 2 may pass once its memory is over (%s)" % two.commit_reason())
	two.pass_allowed = false
	_check(not two.can_pass(), "A turn the room says must finish offers no pass")
	two.pass_allowed = true
	two.pass_turn()
	var pass_two: Dictionary = _json(two.export_recording())
	_check(two.passed and pass_two.completed == false and pass_two.role == "b" and pass_two.source_recording_hash == a.recording_hash, "Turn 2's pass is an unfinished later turn over turn 1")
	var checked := Simulation.verify_recording(level, pass_two, start, a)
	_check(checked.valid and checked.get("ready", false), "The pass replays exactly and may be a memory (%s)" % str(checked.get("error", "")))
	# Turn 3: the first pip again, over turn 2, which nests turn 1.
	var three := Simulation.new()
	_check(three.reset(level, STAGE, start, pass_two, "b", 0, [a]), "Turn 3 starts over turn 2 (%s)" % three.error)
	_check(three.turn_number == 3 and three.active_slot == three.first_player_slot and three.memory_slot != three.first_player_slot, "Turn 3 is the first pip's, the memory the second's")
	_check(three.snapshot().players[three.memory_slot].ghost and not three.snapshot().players[three.active_slot].ghost, "The memory pip is the ghost")
	_check(Witness._play(three, Witness.routes(TIDE)[STAGE].turns[2]).is_empty() and three.snapshot().context_action.get("id", "") != "ring", "Turn 3 walks the first pip to the goal; there is no bell to ring")
	_check(not three.complete and not three.finished, "One pip at the goal does not finish the stage")
	while int(three.tick) < int(pass_two.duration_ticks): three.step({})
	_check(three.can_pass(), "Turn 3 may pass once turn 2 is over (%s)" % three.commit_reason())
	three.pass_turn()
	var pass_three: Dictionary = _json(three.export_recording())
	var checked_three := Simulation.verify_recording(level, pass_three, start, pass_two, [a])
	_check(checked_three.valid and checked_three.get("ready", false), "Turn 3's pass replays over its nested memory (%s)" % str(checked_three.get("error", "")))
	_check(not Simulation.verify_recording(level, pass_three, start, pass_two).valid, "A later memory without its own turns before it is refused")
	# Turn 4: the second pip's route again closes the stage over turns 3, 2 and 1.
	var four := Simulation.new()
	_check(four.reset(level, STAGE, start, pass_three, "b", 0, [a, pass_two]), "Turn 4 starts over turn 3 (%s)" % four.error)
	_check(four.active_slot == two.active_slot, "Turn 4 is the second pip's")
	while not four.finished: four.step(b_frames[four.tick] if int(four.tick) < b_frames.size() else {})
	_check(four.complete, "Turn 4 closes the stage with both pips at the goal (%s)" % four.commit_reason())
	if not four.complete: return
	var closing: Dictionary = _json(four.export_recording())
	var derived := Simulation.derive_checkpoint(level, start, a, closing, [pass_two, pass_three])
	_check(derived.valid, "The closing checkpoint derives (%s)" % str(derived.get("error", "")))
	if not derived.valid: return
	var checkpoint: Dictionary = derived.checkpoint
	_check(int(checkpoint.schema_version) == OpenTurns.CHECKPOINT_SCHEMA and checkpoint.turn_hashes == [a.recording_hash, pass_two.recording_hash, pass_three.recording_hash, closing.recording_hash] and checkpoint.proof.turns.size() == 4 and not checkpoint.has("a_recording_hash"), "It nests all four turns in order (schema 8)")
	MemoryTrace.clear()
	_check(Simulation.verify_checkpoint(level, checkpoint).valid, "The four turn checkpoint proves from scratch")
	# A solo journal keeps the passes and plays each turn over the latest (relay_journey.gd).
	var path := "user://open-turns-journal.json"
	var journal := Journey.new(path, null, TIDE)
	_check(journal.accept_recording(a) and journal.accept_recording(pass_two) and journal.accept_recording(pass_three), "A solo journal takes turn 1 and two passes (%s)" % journal.last_error)
	_check(journal.passes().size() == 2 and journal.prior_recording().get("recording_hash") == pass_three.recording_hash and journal.role() == "b", "Its next turn plays over the latest pass")
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

## The same four turns in a packed room: turn 1 went before the room knew it
## was packed, so it stays JSON; every later turn records packed, replays
## exactly, plays as the next memory from its kept trace or simulated, and the
## closing checkpoint nests both forms and plays back in the replay view.
func _packed_chain() -> void:
	var level := Registry.definition(TIDE)
	var start := Registry.initial_checkpoint(TIDE)
	var a := _fixture("turn-of-the-tide-v3-set-the-tide-a.json")
	var b_frames: Array = Simulation.expand_recording_inputs(_fixture("turn-of-the-tide-v3-set-the-tide-b.json"))
	MemoryTrace.clear()
	var two := Simulation.new()
	two.reset(level, STAGE, start, a, "b")
	two.packed_recordings = true
	while int(two.tick) < int(a.duration_ticks): two.step(b_frames[two.tick] if int(two.tick) < b_frames.size() else {})
	two.pass_turn()
	var pass_two: Dictionary = _json(two.export_recording())
	_check(RecordingCodec.is_packed(pass_two) and Simulation.verify_recording(level, pass_two, start, a).get("ready", false), "A pass in a packed room records packed and may be a memory")
	var three := Simulation.new()
	_check(three.reset(level, STAGE, start, pass_two, "b", 0, [a]), "Turn 3 starts over a packed pass (%s)" % three.error)
	three.packed_recordings = true
	Witness._play(three, Witness.routes(TIDE)[STAGE].turns[2])
	while int(three.tick) < int(pass_two.duration_ticks): three.step({})
	three.pass_turn()
	var pass_three: Dictionary = _json(three.export_recording())
	_check(RecordingCodec.is_packed(pass_three) and Simulation.verify_recording(level, pass_three, start, pass_two, [a]).get("ready", false), "A packed pass over a packed pass may be a memory")
	var closing := {}
	for traced: bool in [true, false]:
		# Kept traces, then every nested memory simulated: the same closing turn.
		MemoryTrace.clear()
		MemoryTrace.enabled = traced
		var four := Simulation.new()
		_check(four.reset(level, STAGE, start, pass_three, "b", 0, [a, pass_two]), "Turn 4 starts over the packed passes (%s)" % four.error)
		four.packed_recordings = true
		while not four.finished: four.step(b_frames[four.tick] if int(four.tick) < b_frames.size() else {})
		var record: Dictionary = _json(four.export_recording())
		_check(four.complete and (closing.is_empty() or Canonical.same(record, closing)), "The packed closing turn finishes the same whether its memories play from traces or not")
		closing = record
	MemoryTrace.enabled = true
	var derived := Simulation.derive_checkpoint(level, start, a, closing, [pass_two, pass_three])
	_check(derived.valid and derived.checkpoint.proof.turns.map(func(turn: Dictionary) -> bool: return RecordingCodec.is_packed(turn)) == [false, true, true, true], "The closing checkpoint nests turn 1 as JSON and the rest packed (%s)" % str(derived.get("error", "")))
	if not derived.valid: return
	MemoryTrace.clear()
	_check(Simulation.verify_checkpoint(level, derived.checkpoint).valid, "The mixed checkpoint proves from scratch")
	# The replay view plays each later turn over the one before it (shared_replay_view.gd).
	var turns := OpenTurns.pair_turns(CheckpointPairs.pair(TIDE, derived.checkpoint, 0, 0))
	var sim := Simulation.new()
	_check(Registry.reset_simulation(sim, TIDE, level, STAGE, start, turns[2], "b", turns[3], turns.slice(0, 2)), "The replay starts the closing turn over its packed memories (%s)" % sim.error)
	for input: Dictionary in Simulation.expand_recording_inputs(turns[3]): sim.step(input)
	_check(Canonical.same(_json(sim.export_recording()), closing), "and plays it back byte for byte, packed")

## Ten turns of passes, each pip's own route again: every one replays and
## may be a memory, and one check of the latest covers the chain. Memories
## play back from their kept traces (memory_trace.gd), so the same turns give
## the same recordings as simulating every nested memory. Prints how long the
## checks take: 15 s turns, then 100 s turns (the tide's longest) started and
## checked with the traces kept.
func _ten_turns() -> void:
	var level := Registry.definition(TIDE)
	var start := Registry.initial_checkpoint(TIDE)
	var a := _fixture("turn-of-the-tide-v3-set-the-tide-a.json")
	var short := _passes(level, start, a, 10, int(a.duration_ticks))
	if short.size() < 10: return
	var started := Time.get_ticks_msec()
	var checked := Simulation.verify_recording(level, short[-1], start, short[-2], short.slice(0, short.size() - 2))
	print("OPEN TURNS: turn 10's check over its nine memories took %d ms (%d ticks a turn)" % [Time.get_ticks_msec() - started, int(a.duration_ticks)])
	_check(checked.valid and checked.get("ready", false), "Turn 10's pass checks over nine nested memories (%s)" % str(checked.get("error", "")))
	# The same six turns simulating every nested memory: the same recordings.
	MemoryTrace.clear()
	MemoryTrace.enabled = false
	var nested := _passes(level, start, a, 6, int(a.duration_ticks))
	MemoryTrace.enabled = true
	_check(nested.size() == 6 and Canonical.same(nested, short.slice(0, 6)), "Played over kept traces, turns record the same as over nested memories")
	MemoryTrace.clear()
	var cold := Simulation.verify_recording(level, short[5], start, short[4], short.slice(0, 4))
	_check(cold.valid and Canonical.same(cold, Simulation.verify_recording(level, short[5], start, short[4], short.slice(0, 4))), "A kept check is the check")
	# 100 s turns, every checked turn persisted as the phone keeps them.
	TraceStore.attach(TRACES)
	var long_ticks := Simulation.turn_ticks(level, 15, "b") - 10
	var long := _passes(level, start, a, 10, long_ticks)
	if long.size() < 10: return
	var memory: Dictionary = long[-2]
	var before: Array = long.slice(0, long.size() - 2)
	started = Time.get_ticks_msec()
	var ten := Simulation.new()
	var ten_started := ten.reset(level, STAGE, start, memory, "b", 0, before)
	var reset_ms := Time.get_ticks_msec() - started
	started = Time.get_ticks_msec()
	var ten_checked := Simulation.verify_recording(level, long[-1], start, memory, before)
	print("OPEN TURNS: 100 s turns (%d ticks), turn 10 starts in %d ms and checks in %d ms with its memories' traces kept" % [long_ticks, reset_ms, Time.get_ticks_msec() - started])
	_check(ten_started and ten_checked.valid and ten_checked.get("ready", false), "Turn 10 of 100 s turns starts and checks (%s)" % ten.error)
	# After a restart: nothing in memory, the kept turns read back from their files.
	MemoryTrace.clear()
	started = Time.get_ticks_msec()
	var again := Simulation.new()
	var again_started := again.reset(level, STAGE, start, memory, "b", 0, before)
	reset_ms = Time.get_ticks_msec() - started
	started = Time.get_ticks_msec()
	var again_checked := Simulation.verify_recording(level, long[-1], start, memory, before)
	print("OPEN TURNS: after a restart turn 10 starts in %d ms and checks in %d ms from the kept files" % [reset_ms, Time.get_ticks_msec() - started])
	_check(again_started and again_checked.valid and again_checked.get("ready", false) and MemoryTrace.simulated == 0, "After a restart turn 10 starts and checks from its kept files, simulating nothing")
	var frames: Array = Simulation.expand_recording_inputs(long[-1])
	for frame: Dictionary in frames: again._tick(frame)
	again.pass_turn()
	_check(Canonical.same(_json(again.export_recording()), long[-1]), "A memory read back from its file plays the same turn")
	TraceStore.detach()
	for name: String in DirAccess.get_files_at(TRACES): DirAccess.remove_absolute(TRACES.path_join(name))

## `count` turns of one stage, each pip's own route up to turn 1's length then standing still,
## every pass `ticks` long; [] when one cannot pass.
func _passes(level: Dictionary, start: Dictionary, a: Dictionary, count: int, ticks: int) -> Array:
	var routes := [Simulation.expand_recording_inputs(a), Simulation.expand_recording_inputs(_fixture("turn-of-the-tide-v3-set-the-tide-b.json"))]
	var first := a
	if ticks > int(a.duration_ticks):
		var one := Simulation.new()
		one.reset(level, STAGE, start, {}, "a")
		while int(one.tick) < ticks: one._tick(routes[0][one.tick] if int(one.tick) < routes[0].size() else {})
		if not one.can_commit():
			_check(false, "A %d tick first turn may be saved (%s)" % [ticks, one.commit_reason()])
			return []
		first = _json(one.export_recording())
	var turns: Array = [first]
	for n in range(2, count + 1):
		var sim := Simulation.new()
		if not sim.reset(level, STAGE, start, turns[-1], "b", 0, turns.slice(0, turns.size() - 1)):
			_check(false, "Turn %d starts (%s)" % [n, sim.error])
			return []
		var frames: Array = routes[1 if n % 2 == 0 else 0]
		# Each route stops where turn 1 ended, short of the goal, then the pip stands still.
		while int(sim.tick) < ticks and not sim.finished: sim._tick(frames[sim.tick] if int(sim.tick) < mini(frames.size(), int(a.duration_ticks)) else {})
		if not sim.can_pass():
			_check(false, "Turn %d may pass (%s)" % [n, sim.commit_reason()])
			return []
		sim.pass_turn()
		turns.append(_json(sim.export_recording()))
	return turns

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

func _check(okay: bool, label: String) -> void:
	checks += 1
	if not okay:
		failures += 1
		push_error("FAIL " + label)

## Finish while the memory still plays, through the chapter screen.
func _end_early() -> void:
	var level := Registry.definition(TIDE)
	var start := Registry.initial_checkpoint(TIDE)
	var a := _fixture("turn-of-the-tide-v3-set-the-tide-a.json")
	var still := MemoryWait.STILL_INPUT
	var first := Simulation.new()
	first.reset(level, STAGE, start, {}, "a")
	_check(not first.can_end_early() and not first.snapshot().can_end_early, "A first turn has no memory to play out: it ends once its part is done")
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
	_end_early_at_goal(level, start, a)
	var controls := ChapterControls.new()
	root.add_child(controls)
	controls.update_state("", 30.0, {"can_end_early": true, "duration_ticks": 900}, true)
	_check(not controls.finish_button.disabled and controls.finish_button.visible, "Finish is offered while the memory plays")
	controls.update_state("", 30.0, {"duration_ticks": 900}, true)
	_check(controls.finish_button.disabled, "Without a way to end, Finish waits as before")
	controls.free()

## Turn 4 over the first pip standing at the goal: the second pip reaches the
## goal, ends its turn while the memory still plays, and the stage completes
## as the memory ends with both pips there.
func _end_early_at_goal(level: Dictionary, start: Dictionary, a: Dictionary) -> void:
	var b_frames: Array = Simulation.expand_recording_inputs(_fixture("turn-of-the-tide-v3-set-the-tide-b.json"))
	var two := Simulation.new()
	two.reset(level, STAGE, start, a, "b")
	while int(two.tick) < int(a.duration_ticks): two.step(b_frames[two.tick] if int(two.tick) < b_frames.size() else {})
	two.pass_turn()
	var pass_two: Dictionary = _json(two.export_recording())
	var three := Simulation.new()
	three.reset(level, STAGE, start, pass_two, "b", 0, [a])
	Witness._play(three, Witness.routes(TIDE)[STAGE].turns[2])
	while int(three.tick) < int(pass_two.duration_ticks) + 300: three.step({})
	three.pass_turn()
	var pass_three: Dictionary = _json(three.export_recording())
	var four := Simulation.new()
	_check(four.reset(level, STAGE, start, pass_three, "b", 0, [a, pass_two]), "Turn 4 starts over turn 3 (%s)" % four.error)
	var run := _screen(four, pass_three)
	var screen: Screen = run.screen
	while not four._at_goal(four.active_slot) and int(four.tick) < b_frames.size() and not four.finished: screen.advance_input(b_frames[four.tick])
	_check(four._at_goal(four.active_slot) and int(four.tick) < int(pass_three.duration_ticks) and four.can_end_early(), "The second pip reaches the goal while the memory still plays (tick %d of %d)" % [int(four.tick), int(pass_three.duration_ticks)])
	screen._finish()
	screen._skip_memory_wait()
	var guard := 0
	while screen.running and guard < 4000:
		screen._physics_process(1.0 / 30.0)
		guard += 1
	_check(screen.ended == "complete" and four.complete and int(four.tick) == int(pass_three.duration_ticks) and run.world.wakes == 1, "Both pips at the goal as the memory ends complete the stage (%s, tick %d)" % [screen.ended, int(four.tick)])
	var closing: Dictionary = _json(four.export_recording())
	_check(Simulation.derive_checkpoint(level, start, a, closing, [pass_two, pass_three]).valid, "The closing turn proves the stage")
	_free_screen(run)

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
