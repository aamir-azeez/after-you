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
	_check(Simulation.verify_checkpoint(level, checkpoint).valid, "The four turn checkpoint proves from scratch")
	var shuffled: Dictionary = checkpoint.duplicate(true)
	shuffled.proof.turns = [a, pass_three, pass_two, closing]
	_check(not Simulation.verify_checkpoint(level, shuffled).valid, "Turns out of order are refused")

## Ten turns of passes, each pip's own route again: every one replays and
## may be a memory, and one check of the latest covers the chain. Prints how
## long that check takes, nested memories and all.
func _ten_turns() -> void:
	var level := Registry.definition(TIDE)
	var start := Registry.initial_checkpoint(TIDE)
	var a := _fixture("turn-of-the-tide-v3-set-the-tide-a.json")
	var routes := [Simulation.expand_recording_inputs(a), Simulation.expand_recording_inputs(_fixture("turn-of-the-tide-v3-set-the-tide-b.json"))]
	var turns: Array = [a]
	for n in range(2, 11):
		var sim := Simulation.new()
		if not sim.reset(level, STAGE, start, turns[-1], "b", 0, turns.slice(0, turns.size() - 1)):
			_check(false, "Turn %d starts (%s)" % [n, sim.error])
			return
		var frames: Array = routes[1 if n % 2 == 0 else 0]
		while int(sim.tick) < int(a.duration_ticks) and not sim.finished: sim.step(frames[sim.tick] if int(sim.tick) < frames.size() else {})
		if not sim.can_pass():
			_check(false, "Turn %d may pass (%s)" % [n, sim.commit_reason()])
			return
		sim.pass_turn()
		turns.append(_json(sim.export_recording()))
	var started := Time.get_ticks_msec()
	var checked := Simulation.verify_recording(level, turns[-1], start, turns[-2], turns.slice(0, turns.size() - 2))
	var elapsed := Time.get_ticks_msec() - started
	print("OPEN TURNS: turn 10's check over its nine memories took %d ms (%d ticks a turn)" % [elapsed, int(a.duration_ticks)])
	_check(checked.valid and checked.get("ready", false), "Turn 10's pass checks over nine nested memories (%s)" % str(checked.get("error", "")))

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
