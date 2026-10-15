extends SceneTree
## What every pinned chapter's fixture turns sound like, played through the
## real engines and services/chapter_sound_map.gd as the chapter screens do.
## 1. The memory sounds as it did live: in each second turn, every cue the
##    first spirit caused (its levers, switches, mirrors, water, hand-offs,
##    drops, throws) plays at exactly the pitch and gain it had in the first
##    turn, even where its engine replays the action without an event.
## 2. The trace of cues and who caused them, per tick, matches
##    tests/fixtures/golden/<suite>.json (regenerate per golden_support.gd).
## The chapters are split over three suites like the replay goldens
## (test_replay_golden.gd SUITES), to stay well inside CI's 120 s limit.
const Golden = preload("res://tests/golden_support.gd")
const Registry = preload("res://services/chapter_registry.gd")
const ReplayGolden = preload("res://tests/test_replay_golden.gd")
const ChapterSoundMap = preload("res://services/chapter_sound_map.gd")
## Causes that are the first spirit's own actions: named objects it turns,
## and its throws, drops and hand-offs. (Where its seed lands is an outcome the
## second spirit can pre-empt with a catch, so it is not compared.)
const FIRST_SPIRIT_CAUSES := ["lever:", "selector:", "mirror:", "route:", "water:"]
const FIRST_SPIRIT_ACTIONS := ["a|seed_taken", "a|seed_thrown", "a|drop", "a|handoff_offer", "a|lens_offered", "a|lens_taken"]
var checks := 0
var failures := 0

## Records each cue's identity-derived pitch and gain as the soundscape plays it.
class CueRecorder extends "res://services/soundscape.gd":
	var played: Array = []
	func _play_cue(key: String, step: float, gain: float, _live_play: bool) -> void:
		played.append([key, snappedf(step, 0.0001), snappedf(gain, 0.0001)])

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> bool:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
	return value

func _suite() -> String:
	return "sound_trace"

func _run() -> void:
	var started := Time.get_ticks_msec()
	var suite := _suite()
	var chapters := {}
	var memory_cues := 0
	for key: String in ReplayGolden.SUITES.get(suite.replace("sound_trace", "replay_golden"), []):
		# The solo Lighthouse is outside the registry; its engine is pinned as @2.
		if key not in Golden.GOLDEN_KEYS: continue
		var stages := _stages(key)
		if not _check(not stages.is_empty(), "Chapter has fixture turns: " + key): continue
		var level := Registry.definition(key)
		var traces := []
		for stage: Dictionary in stages:
			var a := _turn(key, level, stage, "a")
			var b := _turn(key, level, stage, "b")
			memory_cues += _check_memory(key, str(stage.a.stage_id), a, b)
			traces.append({"stage_id": str(stage.a.stage_id), "a": a.trace, "b": b.trace})
		chapters[key] = traces
	_check(memory_cues > 0, "The fixtures exercise the memory's own cues")
	var golden := suite + ".json"
	var result := Golden.check(golden, {"chapters": chapters})
	for message: String in result.messages: push_error(message)
	_check(result.ok, "Cue traces match golden " + golden)
	print("%s time %d ms" % [suite, Time.get_ticks_msec() - started])
	print("%s: %d checks, %d failures, %d memory cues matched" % [suite.to_upper().replace("_", " "), checks, failures, memory_cues])
	quit(1 if failures else 0)

## The first fixture chain's turns: [{a, b, checkpoint}] in stage order.
func _stages(key: String) -> Array:
	var chains: Dictionary = ReplayGolden.CHAINS.get(key, {})
	if chains.is_empty(): return []
	var spec: Dictionary = chains.values()[0]
	var pairs: Array = []
	var starts: Array = [Registry.initial_checkpoint(key)]
	if spec.has("bundle"):
		var bundle := Golden.fixture(spec.bundle)
		var source: Dictionary = bundle.get(spec.entry, {}) if not str(spec.entry).is_empty() else bundle
		for pair: Dictionary in source.get("pairs", []):
			pairs.append(pair)
			if pair.has("checkpoint"): starts.append(pair.checkpoint)
		if source.get("checkpoints") is Array and source.checkpoints.size() == pairs.size() + 1: starts = source.checkpoints
	else:
		for files: Array in spec.stages:
			pairs.append({"a": Golden.fixture(files[0]), "b": Golden.fixture(files[1])})
			starts.append(Golden.fixture(files[2]))
	var stages: Array = []
	for index in range(pairs.size()):
		if index < starts.size(): stages.append({"a": pairs[index].a, "b": pairs[index].b, "checkpoint": starts[index]})
	return stages

## Plays one turn: {trace: ["tick cue source"], cues: [[tick, source, cue, step, gain]], ticks}.
func _turn(key: String, level: Dictionary, stage: Dictionary, role: String) -> Dictionary:
	var record: Dictionary = stage[role]
	var prior: Dictionary = stage.a if role == "b" else {}
	var engine: Script = Registry.simulation_script(key)
	var sim: RefCounted = engine.new()
	sim.catch_assistance = bool(record.get("catch_assistance", true))
	var label := "%s %s %s" % [key, record.get("stage_id", ""), role]
	if not _check(Registry.reset_simulation(sim, key, level, str(record.stage_id), stage.checkpoint, prior, role, record), "Fixture turn resets: " + label):
		return {"trace": [], "cues": [], "ticks": 0}
	var sound := CueRecorder.new()
	sound.begin_turn(key, str(record.stage_id))
	var seen := ChapterSoundMap.remember(sim.snapshot())
	var trace: Array = []
	var cues: Array = []
	var tick := 0
	for input: Dictionary in engine.expand_recording_inputs(record):
		var state: Dictionary = sim.step(input)
		tick += 1
		var sounds := ChapterSoundMap.cues(key, state, seen)
		_check(sounds.cues.size() == sounds.sources.size(), "Every cue names who caused it: " + label)
		var before: int = sound.played.size()
		sound.consume_turn_events(sounds.cues, sounds.sources, false)
		var played: Array = sound.played.slice(before)
		var heard := 0
		for index in range(sounds.cues.size()):
			var cue := str(sounds.cues[index])
			trace.append("%d %s %s" % [tick, cue, sounds.sources[index]])
			if not sound.CLIPS.has(cue): continue
			var pitch: Array = played[heard] if heard < played.size() else [cue, 0.0, 0.0]
			heard += 1
			cues.append([tick, str(sounds.sources[index]), cue, pitch[1], pitch[2]])
	sound.free()
	return {"trace": trace, "cues": cues, "ticks": tick}

## Each first-spirit cause sounds the same in the second turn as in the
## first, cue for cue, until the second turn ends. Returns how many matched.
func _check_memory(key: String, stage_id: String, a: Dictionary, b: Dictionary) -> int:
	var live := _by_cause(a.cues)
	var memory := _by_cause(b.cues)
	var last_tick := int(b.ticks)
	var matched := 0
	for cause: String in live:
		if not _first_spirit(cause): continue
		var expected: Array = live[cause].filter(func(cue: Array) -> bool: return int(cue[0]) <= last_tick)
		var heard: Array = memory.get(cause, [])
		# Equal counts: a double-fired memory cue in the second turn fails here too.
		var same := heard.size() == expected.size()
		for index in range(mini(expected.size(), heard.size())):
			same = same and expected[index].slice(1) == heard[index].slice(1)
		_check(same, "The memory's %s sounds as it did live: %s %s (live %s, memory %s)" % [cause, key, stage_id, str(expected), str(heard)])
		matched += expected.size()
	# The memory never does what the first spirit did not (switches and levers
	# heard only now may be the second spirit's own, so only actions count).
	for cause: String in memory:
		_check(cause not in FIRST_SPIRIT_ACTIONS or live.has(cause), "The memory plays no action the first turn lacked: %s %s %s" % [key, stage_id, cause])
	return matched

static func _by_cause(cues: Array) -> Dictionary:
	var result := {}
	for cue: Array in cues:
		var cause := str(cue[1])
		if not result.has(cause): result[cause] = []
		result[cause].append(cue)
	return result

static func _first_spirit(cause: String) -> bool:
	if cause in FIRST_SPIRIT_ACTIONS: return true
	for prefix: String in FIRST_SPIRIT_CAUSES:
		if cause.begins_with(prefix): return true
	return false
