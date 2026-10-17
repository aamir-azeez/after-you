extends SceneTree
## turn-of-the-tide@2's settled source (core/journey/simulation.gd _settled):
## the second spirit plays in the harbour the first spirit left, so its levers,
## wheels and crossings answer at once and it waits for the memory only at the
## bell or the lantern. @1 keeps playing exactly as published. Stage 1, the
## owner's gangway case and the cost here; stage 2's nine ways in
## test_turn_of_the_tide_settled_ways (each suite inside CI's 120 s).
const Simulation = preload("res://core/journey/simulation.gd")
const Catalog = preload("res://core/journey/stage_catalog.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Tide = preload("res://tests/turn_of_the_tide_witness.gd")
const Golden = preload("res://tests/golden_support.gd")
const ChapterSoundMap = preload("res://services/chapter_sound_map.gd")
const SoundTrace = preload("res://tests/test_sound_trace.gd")
const V1 := "turn-of-the-tide@1"
const V2 := "turn-of-the-tide@2"
## Stage-1 receivers that crossed on a tide the first spirit only passed
## through, and the crossing each used. Under a settled source only the tide
## it left is there, and in stage 1 only the first spirit turns the tide.
const PASSING_TIDE := {"low-jetty": "jetty-1", "low-half-first-stones": "stones-1", "half-early-sand": "sand-1", "high-early-sand": "sand-1", "high-spout": "sand-1"}
var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func _timed(part: Callable) -> Variant:
	var started := Time.get_ticks_msec()
	var result: Variant = part.call()
	print("TIME %s %d ms" % [part.get_method(), Time.get_ticks_msec() - started])
	return result

func _check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
	return ok

func _run() -> void:
	var v1 := Registry.definition(V1)
	var v2 := Registry.definition(V2)
	_parts(v1, v2)
	print("%s: %d checks, %d failures" % [_title(), checks, failures])
	quit(1 if failures else 0)

func _title() -> String:
	return "TURN OF THE TIDE SETTLED"

func _parts(v1: Dictionary, v2: Dictionary) -> void:
	_definition(v1, v2)
	_timed(_stage_one.bind(v1, v2))
	_timed(_gangway.bind(v1, v2))
	_timed(_cost.bind(v2))
	_timed(_memory_sounds.bind(v2))

## @2 is @1 with its version and the settled source, and nothing else.
func _definition(v1: Dictionary, v2: Dictionary) -> void:
	var stripped := v2.duplicate(true)
	_check(stripped.get("settled_source") == true and int(stripped.version) == 2 and int(stripped.simulation_version) == 9, "@2 is version 2 on rules 9 with a settled source")
	stripped.erase("settled_source")
	stripped.version = 1
	_check(Canonical.same(stripped, v1), "Apart from its version and the settled source, @2 is @1")
	_check(not v1.has("settled_source") and Canonical.digest(v1) != Canonical.digest(v2), "@1 has no settled source, and the two never share a definition hash")
	_check(Catalog.known(v2) and Catalog.known(v1), "The journey catalog knows both versions")

## Every stage-1 receiver route under @2: the ones that cross the tide the first
## spirit left never wait, and nothing opens for them but their own presses;
## the crossing a passing tide opened stays shut. The three histories prove
## their checkpoints in full.
func _stage_one(v1: Dictionary, v2: Dictionary) -> void:
	var start := Catalog.initial_checkpoint(v2)
	var sources: Dictionary = {}
	for name: String in Tide.PAIRS:
		var spec: Array = Tide.PAIRS[name]
		if name in PASSING_TIDE:
			if not sources.has(spec[0]): sources[spec[0]] = Tide.source(v2, Tide.SET, start, Tide.a_routes()[spec[0]], 0, Callable(), true).export_recording()
			var b := Simulation.new()
			_check(b.reset(v2, Tide.SET, start, sources[spec[0]], "b") and not bool(b._routes.get(PASSING_TIDE[name], true)), "Stage 1 %s: %s, open only on a passing tide, is shut under the tide left" % [name, PASSING_TIDE[name]])
			continue
		var pair := Tide.pair(v2, Tide.SET, start, Tide.a_routes()[spec[0]], Tide.b_routes()[spec[1]], name == spec[2])
		if not _check(pair.error.is_empty(), "Stage 1 %s plays under @2: %s" % [name, pair.error]): continue
		sources[spec[0]] = pair.a
		_receiver_checks(v2, start, pair, "Stage 1 " + name)
	# As published, the partner's memory opens crossings for the receiver.
	var published := Tide.pair(v1, Tide.SET, Catalog.initial_checkpoint(v1), Tide.a_routes()["high"], Tide.b_routes()["high"], false)
	if _check(published.error.is_empty(), "Stage 1 high still plays under @1"):
		_check(int(published.b_sim.get_meta("waited", 0)) > 0 and int(_replay(v1, Catalog.initial_checkpoint(v1), published).partner_openings) > 0, "@1 as published: the receiver waits while the memory opens its crossings")

## A receiver turn under @2: no tick spent waiting on the way, no crossing
## opened by anything but its own press, the press at the goal comes before
## the memory ends, and the recording verifies after a JSON round trip.
func _receiver_checks(level: Dictionary, checkpoint: Dictionary, pair: Dictionary, label: String) -> void:
	var b: RefCounted = pair.b_sim
	_check(int(b.get_meta("waited", 0)) == 0, label + ": the receiver never waits for the partner on the way")
	var replay := _replay(level, checkpoint, pair)
	_check(int(replay.partner_openings) == 0, label + ": every crossing opens on the receiver's own press")
	_check(int(pair.b.duration_ticks) == maxi(int(pair.a.duration_ticks), int(replay.ring_tick)), label + ": the stage ends when the memory ends, or at the ring if that is later")
	_check(bool(replay.final_hash == pair.b.final_state_hash), label + ": the receiver's recording replays to its own final state")

## The receiver's turn replayed from its checkpoint after a JSON round trip:
## crossings that opened on a tick it pressed nothing, the tick (1-based, as a
## turn's length counts) of its press at the goal, and the final state hash.
## The checked reset is _cost's; here the partner is trusted, as in Tide.pair.
func _replay(level: Dictionary, checkpoint: Dictionary, pair: Dictionary) -> Dictionary:
	var sim := Simulation.new()
	var result := {"partner_openings": 0, "ring_tick": -1, "final_hash": ""}
	sim.simulation_version = Tide.RULES
	sim._reset_trusted(level, str(pair.b.stage_id), Tide.json(checkpoint), Tide.json(pair.a), "b")
	for frame: Dictionary in Simulation.expand_recording_inputs(pair.b):
		var state: Dictionary = sim.step(frame)
		var pressed := false
		for event: String in state.events: pressed = pressed or event == "lever" or event.begins_with("selector:")
		for event: String in state.events:
			if event.begins_with("bridge_opened:") and not pressed: result.partner_openings += 1
		if result.ring_tick < 0 and bool(state.objective_done): result.ring_tick = int(state.tick)
	result.final_hash = sim.state_hash()
	return result

## The owner's case. On HIGH the partner pulls the mooring line and then holds
## the bollard step; the gangway's jetty needs both and the gangway. Under @1
## the gangway pulled first opens nothing until the memory is on the step;
## under @2 the jetty opens the tick the gangway is pulled.
func _gangway(v1: Dictionary, v2: Dictionary) -> void:
	for level: Dictionary in [v1, v2]:
		var label := "@%d" % int(level.version)
		var checkpoint := Catalog.initial_checkpoint(level)
		var a := Tide.source(level, Tide.SET, checkpoint, Tide.a_routes()["high"], 0, Callable(), true)
		if not _check(a.can_commit(), "The HIGH source commits " + label): continue
		var b := Simulation.new()
		if not _check(b.reset(level, Tide.SET, checkpoint, a.export_recording(), "b"), "The receiver starts " + label): continue
		# Straight to the gangway; @1 has to wait for the high water first.
		var route: Array = [["w",[-212,416]],["w",[-212,-326]]]
		if level == v1: route.append(["u","route:jetty-1"])
		route += [["w",[1104,-326]], Tide.T]
		_check(Tide.play(b, route).is_empty() and bool(b._mechanisms.levers.get("gangway", false)), "The receiver pulls the gangway " + label)
		var pad_tick := int(a._hold_start)
		_check(int(b.tick) < pad_tick, "The gangway is pulled before the memory reaches the bollard step " + label)
		if level == v2:
			_check(bool(b._routes.get("jetty-3", false)) and "bridge_opened:jetty-3" in b._events, "@2: jetty-3 opens on the tick the gangway is pulled")
			var shown: Dictionary = b.snapshot()
			_check(bool(shown.levers.get("line", false)) and str(shown.controls.tide) == "high", "@2: the harbour shows the tide and the line the partner left")
		else:
			_check(not bool(b._routes.get("jetty-3", false)), "@1 as published: the gangway alone opens nothing yet")
			_check(Tide.wait_until(b, "route:jetty-3") and int(b.tick) >= pad_tick, "@1 as published: jetty-3 opens only once the memory is on the step")

## Records each cue's identity-derived pitch and gain as the soundscape plays it.
class CueRecorder extends "res://services/soundscape.gd":
	var played: Array = []
	func _play_cue(key: String, step: float, gain: float, _live_play: bool) -> void:
		played.append([key, snappedf(step, 0.0001), snappedf(gain, 0.0001)])

## The memory sounds as it did live (as test_sound_trace checks for every
## pinned chapter): in @2's fixture turns, each lever pull, wheel turn and
## water change of the first spirit plays in the second turn at the same tick,
## pitch and gain as in the first, although the settled harbour never changes.
func _memory_sounds(v2: Dictionary) -> void:
	var at: Dictionary = Golden.fixture("journey/turn-of-the-tide-v2-initial-checkpoint.json")
	var matched := 0
	for stage: String in ["set-the-tide", "slack-water"]:
		var a: Dictionary = Golden.fixture("journey/turn-of-the-tide-v2-%s-a.json" % stage)
		var b: Dictionary = Golden.fixture("journey/turn-of-the-tide-v2-%s-b.json" % stage)
		var live := SoundTrace._by_cause(_cues(v2, at, a, {}))
		var memory := SoundTrace._by_cause(_cues(v2, at, b, a))
		for cause: String in live:
			if not SoundTrace._first_spirit(cause): continue
			var expected: Array = live[cause].filter(func(cue: Array) -> bool: return int(cue[0]) <= int(b.duration_ticks))
			_check(Canonical.same(expected, memory.get(cause, [])), "@2 %s: the memory's %s sounds as it did live (live %s, memory %s)" % [stage, cause, str(expected), str(memory.get(cause, []))])
			matched += expected.size()
		at = Golden.fixture("journey/turn-of-the-tide-v2-%s-checkpoint.json" % stage)
	_check(matched >= 10, "The fixture turns exercise the memory's levers, wheels and water (%d cues)" % matched)

## [[tick, cause, cue, step, gain]] for one fixture turn, as a chapter screen plays it.
func _cues(level: Dictionary, checkpoint: Dictionary, record: Dictionary, prior: Dictionary) -> Array:
	var sim := Simulation.new()
	if not _check(sim.reset(level, str(record.stage_id), checkpoint, prior, str(record.role)), "The fixture turn starts: %s %s" % [record.stage_id, record.role]): return []
	var sound := CueRecorder.new()
	sound.begin_turn(V2, str(record.stage_id))
	var seen := ChapterSoundMap.remember(sim.snapshot())
	var cues: Array = []
	for input: Dictionary in Simulation.expand_recording_inputs(record):
		var state: Dictionary = sim.step(input)
		var sounds := ChapterSoundMap.cues(V2, state, seen)
		var before: int = sound.played.size()
		sound.consume_turn_events(sounds.cues, sounds.sources, false)
		var played: Array = sound.played.slice(before)
		var heard := 0
		for index in range(sounds.cues.size()):
			if not sound.CLIPS.has(str(sounds.cues[index])): continue
			var pitch: Array = played[heard] if heard < played.size() else ["", 0.0, 0.0]
			heard += 1
			cues.append([int(state.tick), str(sounds.sources[index]), str(sounds.cues[index]), pitch[1], pitch[2]])
	sound.free()
	return cues

## A settled second turn reads the partner's end state from the check that
## reset() and the proofs already make, so it costs no extra replay; a trusted
## reset without that check plays the partner itself and gets the same world.
func _cost(v2: Dictionary) -> void:
	var checkpoint := Catalog.initial_checkpoint(v2)
	var pair := Tide.pair(v2, Tide.SET, checkpoint, Tide.a_routes()["low"], Tide.b_routes()["low"], false)
	if not _check(pair.error.is_empty(), "The LOW pair plays for the cost check"): return
	var started := Time.get_ticks_usec()
	var checked := Simulation.new()
	_check(checked.reset(v2, Tide.SET, checkpoint, pair.a, "b"), "A checked reset starts the receiver")
	var checked_usec := Time.get_ticks_usec() - started
	var trusted := Simulation.new()
	trusted.simulation_version = Tide.RULES
	trusted._reset_trusted(v2, Tide.SET, checkpoint, pair.a, "b")
	_check(Canonical.same(checked.snapshot(), trusted.snapshot()), "The handed-over and the replayed end state show the same world")
	# What is handed over is what settles (no second replay of the partner),
	# and it serves one reset only.
	var other: Dictionary = trusted.snapshot()
	other.controls = other.controls.duplicate()
	other.controls.tide = "high"
	var probe := Simulation.new()
	probe.simulation_version = Tide.RULES
	probe.hand_over_prior_end(other)
	probe._reset_trusted(v2, Tide.SET, checkpoint, pair.a, "b")
	_check(str(probe.snapshot().controls.tide) == "high", "A reset settles the end state handed to it instead of replaying the partner")
	probe._reset_trusted(v2, Tide.SET, checkpoint, pair.a, "b")
	_check(Canonical.same(probe.snapshot(), trusted.snapshot()), "A hand-over serves one reset only")
	for frame: Dictionary in Simulation.expand_recording_inputs(pair.b):
		checked.step(frame)
		trusted.step(frame)
	_check(checked.state_hash() == trusted.state_hash() and checked.state_hash() == pair.b.final_state_hash, "Both play the receiver's turn to its recorded final state")
	var published := Registry.definition(V1)
	var old_pair := Tide.pair(published, Tide.SET, Catalog.initial_checkpoint(published), Tide.a_routes()["low"], Tide.b_routes()["low"], false)
	started = Time.get_ticks_usec()
	Simulation.new().reset(published, Tide.SET, Catalog.initial_checkpoint(published), old_pair.a, "b")
	print("TIDE receiver reset: @2 %d usec, @1 %d usec, for a %d-tick memory" % [checked_usec, Time.get_ticks_usec() - started, int(pair.a.duration_ticks)])
