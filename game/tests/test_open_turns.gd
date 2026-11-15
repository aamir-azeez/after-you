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
## - a published two turn stage still proves the published way.
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
const TRACES := "user://open-turns-test-traces"
const TIDE := "turn-of-the-tide@3"
const STAGE := "set-the-tide"
var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	_rules()
	_chain()
	_ten_turns()
	_published()
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
	_check(journal.accept_recording(closing) and journal.passes().is_empty() and journal.pairs()[0].get("passes", []).size() == 2 and Canonical.same(journal.checkpoint(), checkpoint), "The closing turn ends the stage with its passes in the pair (%s)" % journal.last_error)
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

func _check(okay: bool, label: String) -> void:
	checks += 1
	if not okay:
		failures += 1
		push_error("FAIL " + label)
