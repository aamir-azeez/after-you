extends SceneTree

const Soundscape = preload("res://services/soundscape.gd")
const SoundCues = preload("res://services/sound_cues.gd")
const Celebration = preload("res://presentation/leaderboard_celebration.gd")
const ButtonTicks = preload("res://presentation/button_ticks.gd")
const ChapterControls = preload("res://presentation/chapter_controls.gd")

class Probe:
	extends "res://services/soundscape.gd"
	var pulses: Array[int] = []
	var last_key := ""
	func _emit_haptic(duration_ms: int) -> void:
		pulses.append(duration_ms)
	func _play_cue(key: String, step: float, gain: float, live_play: bool) -> void:
		super(key, step, gain, live_play)
		last_key = key

## A flow's host: Main, as far as play_on reads it.
class SoundHost:
	extends Object
	var soundscape: Node

## A screen, as far as the button tick reads it: a node with a soundscape.
class TickScreen:
	extends Control
	var soundscape: Node

## A world that only reports moving mechanisms.
class FakeWorld:
	extends Node3D
	signal mechanism_moving(kind: String, id: String, direction: int)
	func _process(_delta: float) -> void:
		pass

class Tuned:
	extends Probe
	var clock := 0
	func _now_msec() -> int:
		return clock

## Counts the button ticks it plays (the voice index wraps round its pool).
class TickProbe:
	extends Tuned
	var ticks := 0
	func _voice_cue(key: String, step: float, gain: float) -> void:
		super(key, step, gain)
		if key == ButtonTicks.CUE: ticks += 1

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _variation() -> void:
	_check_spread()
	_check_footsteps()
	_check_cues()
	_check_miss_below_catch()
	_check_reunion_phrase()
	_check_muted()
	var trace := _sequence(20261010, "go-on-ahead")
	_check(trace.size() == 66 and trace == _sequence(7, "go-on-ahead"), "Two fresh soundscapes give the same pitches for the same turn, whatever their private generator")
	_check(trace != _sequence(20261010, "back-for-you"), "A different stage gives its own pitches")
	_check_sources()
	_check_retry()
	_check_memory_matches_live()
	_check_turn_constraints()
	_check_turn_reunions()
	_check_global_rng()

func _tuned(seed_value: int) -> Tuned:
	var probe := Tuned.new()
	probe.variation.seed = seed_value
	# These checks play hundreds of cues inside one frame.
	probe.max_cues_per_frame = 0
	root.add_child(probe)
	probe.configure({"sound": true, "haptics": false})
	return probe

static func _semitones(pitch: float) -> float:
	return 12.0 * log(pitch) / log(2.0)

static func _last_cue(probe: Tuned) -> AudioStreamPlayer:
	if SoundCues.CUES.get(probe.last_key, {}).get("voice", "") == "long": return probe.long_voice
	return probe.voices[(probe.next_voice + probe.voices.size() - 1) % probe.voices.size()]

static func _last_step(probe: Tuned) -> AudioStreamPlayer:
	return probe.step_voices[(probe.next_step - 1) % probe.step_voices.size()]

func _check_footsteps() -> void:
	var probe := _tuned(11)
	var distinct := {}
	var previous := 0.0
	var previous_stream: AudioStream = null
	var separated := true
	var bounded := true
	var alternating := true
	for i in range(240):
		probe.play_footstep()
		var voice := _last_step(probe)
		var detune := _semitones(voice.pitch_scale)
		distinct[snappedf(detune, 0.01)] = true
		bounded = bounded and absf(detune) <= Soundscape.STEP_DETUNE + 0.001 and absf(voice.volume_db - Soundscape.STEP_DB) <= Soundscape.STEP_JITTER_DB + 0.001
		if i > 0:
			separated = separated and absf(detune - previous) >= Soundscape.STEP_MIN_MOVE - 0.001
			alternating = alternating and voice.stream != previous_stream
		previous = detune
		previous_stream = voice.stream
	_check(separated, "Consecutive footsteps never share a pitch")
	_check(bounded, "Footstep detune and gain stay within a subtle range around the original mix")
	_check(alternating and probe.next_step == 240, "Footsteps still alternate both contact samples without throttling")
	_check(distinct.size() >= 40, "Footsteps spread across many distinct pitches")
	probe.queue_free()

func _check_cues() -> void:
	var probe := _tuned(23)
	var keys: Array = Soundscape.CUE_RANGES.keys()
	_check(keys.size() == Soundscape.CLIPS.size(), "Every gameplay cue has its own pitch range")
	# A turn's cues; fixed cues have one pitch each (_check_fixed_cues).
	keys = keys.filter(func(key: String) -> bool: return not SoundCues.is_fixed(key))
	var order: Array = []
	for i in range(160):
		order.append(keys[i % keys.size()])
	for key: String in keys:
		for i in range(12):
			order.append(key)
	var last := {}
	var heard := {}
	var allowed := true
	var close := false
	var gains := true
	for key: String in order:
		probe.consume_events([key], false)
		var voice := _last_cue(probe)
		var step := _semitones(voice.pitch_scale)
		var span: Vector2 = Soundscape.CUE_RANGES[key]
		var family: String = Soundscape.CLIPS[key].resource_path
		allowed = allowed and voice.stream == Soundscape.CLIPS[key] and step >= span.x - 0.0001 and step <= span.y + 0.0001
		close = close or (last.has(family) and absf(step - last[family]) < Soundscape.CUE_MIN_MOVE - 0.0001)
		last[family] = step
		if not heard.has(key): heard[key] = []
		heard[key].append(step)
		var offset := voice.volume_db - Soundscape.CUE_DB - float(SoundCues.CUES[key].get("db", 0.0))
		var gain_span: Vector2 = SoundCues.CUES[key].get("gain", SoundCues.CUE_GAIN)
		gains = gains and offset >= gain_span.x - 0.001 and offset <= gain_span.y + 0.001
	var smooth := true
	for key: String in keys:
		var steps: Array = heard[key]
		var span: Vector2 = Soundscape.CUE_RANGES[key]
		var distinct := {}
		var off_grid := 0
		for step: float in steps:
			distinct[snappedf(step, 0.001)] = true
			if absf(step - roundf(step)) > 0.05: off_grid += 1
		smooth = smooth and distinct.size() == steps.size() and off_grid * 2 >= steps.size() and steps.max() - steps.min() >= (span.y - span.x) * 0.6
	_check(allowed, "One-shot cues stay inside their own pitch range")
	_check(not close, "No cue lands within the minimum move of its previous pitch, even when interleaved")
	_check(smooth, "Cue pitches slide across the whole range instead of a few fixed steps")
	_check(gains, "Cue gain varies around the existing level, and a miss is never louder")
	probe.queue_free()

func _check_miss_below_catch() -> void:
	var probe := _tuned(37)
	var miss_high := 0.0
	var catch_low := 100.0
	for i in range(60):
		probe.consume_events(["seed_caught"], true)
		catch_low = minf(catch_low, _last_cue(probe).pitch_scale)
		probe.consume_events(["seed_missed"], true)
		miss_high = maxf(miss_high, _last_cue(probe).pitch_scale)
	var ranges: Dictionary = Soundscape.CUE_RANGES
	_check(ranges.seed_missed.y <= 0.0 and ranges.seed_missed.y <= ranges.seed_caught.x, "The miss range never rises above the source pitch or any catch pitch")
	_check(miss_high <= catch_low + 0.00001 and miss_high <= 1.00001, "A played miss is never pitched above a played catch")
	probe.queue_free()

func _check_reunion_phrase() -> void:
	var probe := _tuned(53)
	var span: Vector2 = Soundscape.REUNION_RANGE
	var gains := true
	var valid := true
	var repeats := 0
	var rises := 0
	var falls := 0
	var notes: Array = []
	var previous := Soundscape.NO_PITCH
	for i in range(120):
		probe.clock += 1500 if i % 3 else 9000
		probe.play_reunion()
		var note := _semitones(probe.reunion_voice.pitch_scale)
		valid = valid and note >= span.x - 0.0001 and note <= span.y + 0.0001 and probe.reunion_voice.playing
		if previous != Soundscape.NO_PITCH:
			if absf(note - previous) < Soundscape.REUNION_MIN_MOVE - 0.0001: repeats += 1
			elif note > previous: rises += 1
			else: falls += 1
		notes.append(note)
		previous = note
		gains = gains and absf(probe.reunion_voice.volume_db - Soundscape.REUNION_DB) <= Soundscape.REUNION_JITTER_DB + 0.001
	_check(valid and repeats == 0, "Every meetup slides at least the minimum move away from the last one")
	_check(notes.min() <= span.x + 1.0 and notes.max() >= span.y - 1.0 and rises >= 20 and falls >= 20, "Meetup pitches wander up and down across the range instead of climbing a phrase")
	_check(gains, "Reunion gain stays around the existing level")
	probe.queue_free()

## The shared pitch picker: inclusive range, minimum move, deterministic.
func _check_spread() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var ok := true
	for i in range(2000):
		var low := rng.randf_range(-6.0, 6.0)
		var span := Vector2(low, low + rng.randf_range(0.5, 9.0))
		var gap := rng.randf_range(0.1, 2.0)
		var previous: float = Soundscape.NO_PITCH if i % 7 == 0 else rng.randf_range(span.x - 3.0, span.y + 3.0)
		var unit := 0.0 if i % 11 == 0 else 1.0 if i % 13 == 0 else rng.randf()
		var pitch := Soundscape.spread_pitch(span, previous, gap, unit)
		var blocked := previous - gap <= span.x and previous + gap >= span.y
		var inside := pitch >= span.x - 0.00001 and pitch <= span.y + 0.00001
		var apart := previous == Soundscape.NO_PITCH or blocked or absf(pitch - previous) >= gap - 0.00001
		ok = ok and inside and apart and pitch == Soundscape.spread_pitch(span, previous, gap, unit)
	_check(ok, "The pitch picker stays in range, keeps the minimum move and gives the same pitch for the same unit")
	_check(is_equal_approx(Soundscape.spread_pitch(Vector2(-1, 1), Soundscape.NO_PITCH, 0.3, 0.5), 0.0), "With no previous pitch the whole range is open")
	_check(is_equal_approx(Soundscape.spread_pitch(Vector2(0, 1), 0.5, 2.0, 0.25), 0.25), "If nothing is far enough away the whole range is used")

func _check_muted() -> void:
	var probe := _tuned(41)
	for setting: String in ["sound", "background"]:
		if setting == "sound":
			probe.configure({"sound": false, "haptics": false})
		else:
			probe.configure({"sound": true, "haptics": false})
			probe.set_backgrounded(true)
		var state := probe.variation.state
		for i in range(5):
			probe.play_footstep()
			probe.consume_events(["seed_caught", "seed_missed", "island_bloomed"], false)
			probe.play_reunion()
		var silent := not probe.reunion_voice.playing and not probe.ambience.playing
		for voice: AudioStreamPlayer in probe.voices + probe.step_voices:
			silent = silent and not voice.playing
		_check(silent and probe.next_step == 0 and probe.next_voice == 0 and probe.reunion_pitch == Soundscape.NO_PITCH, "Suppressed audio plays no footsteps, cues or reunions: " + setting)
		_check(probe.variation.state == state, "Suppressed Home meetups do not advance the private generator: " + setting)
	probe.queue_free()
	# A muted stretch of a turn still counts its events, so unmuting keeps the
	# pitches an always-audible run of the same turn would play.
	var heard := _turn_trace(_tuned(43), _turn_script(), -1)
	var resumed := _turn_trace(_tuned(44), _turn_script(), 9)
	_check(heard.size() == resumed.size() + 10 and heard.slice(10) == resumed, "Cues after a muted stretch keep the pitches of an unmuted turn")

func _sequence(seed_value: int, stage: String) -> Array:
	var probe := _tuned(seed_value)
	probe.begin_turn("the-wishing-well@1", stage)
	var keys: Array = Soundscape.CUE_RANGES.keys()
	var trace: Array = []
	for i in range(30):
		probe.play_footstep("p0")
		trace.append([_last_step(probe).pitch_scale, _last_step(probe).volume_db])
		probe.consume_events([keys[i % keys.size()]], false)
		trace.append([_last_cue(probe).pitch_scale, _last_cue(probe).volume_db])
		if i % 5 == 0:
			probe.clock += 9000 if i % 10 == 0 else 2500
			probe.play_reunion()
			trace.append([probe.reunion_voice.pitch_scale, probe.reunion_voice.volume_db])
	probe.queue_free()
	return trace

## A turn as [kind, cue or spirit, live role]: throws, a catch, footsteps and bridges.
func _turn_script() -> Array:
	var plan: Array = []
	for i in range(12):
		plan.append(["step", "p0" if i % 3 else "p1", "b"])
		if i == 2: plan.append(["event", "bridge_opened:west-relay", "b"])
		if i == 4: plan.append(["event", "seed_thrown", "b"])
		if i == 7: plan.append(["event", "seed_caught", "b"])
		if i == 9: plan.append(["event", "lever", "b"])
		if i == 10: plan.append(["event", "seed_thrown", "b"])
	return plan

## Plays a turn and returns each sound's pitch and gain. Sounds before
## `muted_until` play muted and are left out of the trace.
func _turn_trace(probe: Tuned, plan: Array, muted_until: int, chapter: String = "relay-isles@2", stage: String = "relay") -> Array:
	probe.begin_turn(chapter, stage)
	var trace: Array = []
	for index in range(plan.size()):
		var item: Array = plan[index]
		probe.configure({"sound": index > muted_until, "haptics": false})
		if item[0] == "step":
			probe.play_footstep(item[1])
			if index > muted_until: trace.append(["step", item[1], _last_step(probe).pitch_scale, _last_step(probe).volume_db])
		else:
			var cue: String = "seed_landed" if item[1] == "lever" else "bridge_opened" if str(item[1]).begins_with("bridge_opened") else item[1]
			probe.consume_turn_events([cue], [Soundscape.event_source(item[1], item[2])], false)
			if index > muted_until: trace.append([item[1], _last_cue(probe).pitch_scale, _last_cue(probe).volume_db])
	probe.queue_free()
	return trace

func _check_sources() -> void:
	_check(Soundscape.event_source("seed_thrown", "b") == "a|seed_thrown" and Soundscape.event_source("seed_thrown", "a") == "a|seed_thrown", "A throw always belongs to the first spirit, live or remembered")
	_check(Soundscape.event_source("seed_caught", "b") == "b|seed_caught" and Soundscape.event_source("island_bloomed", "b") == "b|island_bloomed", "Catch and bloom belong to the second spirit")
	_check(Soundscape.event_source("lever", "a") == "a|lever" and Soundscape.event_source("drop", "b") == "b|drop", "A lever or a drop belongs to whoever is playing")
	_check(Soundscape.event_source("bridge_opened:west-relay", "b") == "bridge_opened:west-relay|bridge_opened:west-relay", "A bridge is named by the bridge, not by a spirit")
	_check(Soundscape.event_source("selector:hall-lamp", "b") == Soundscape.event_source("selector:hall-lamp", "a"), "A switch sounds the same whether the memory or the live spirit sets it")
	_check(Soundscape.event_source("beacon_lit", "b") == "b|beacon_lit" and Soundscape.event_source("court_activated", "a") == "b|court_activated", "Lighting the beacon or the court belongs to the second spirit")

func _check_retry() -> void:
	var probe := _tuned(61)
	var first := _turn_trace(probe, _turn_script(), -1)
	var again := _tuned(61)
	again.begin_turn("relay-isles@2", "relay")
	for item: Array in _turn_script().slice(0, 6):
		if item[0] == "step": again.play_footstep(item[1])
	var retry := _turn_trace(again, _turn_script(), -1)
	_check(first == retry, "A retry restarts the turn and reproduces every pitch")
	# The retry throws later, after more steps: the first throw still sounds the same.
	var later := _turn_script()
	later.insert(4, ["step", "p0", "b"])
	later.insert(4, ["step", "p1", "b"])
	var delayed := _turn_trace(_tuned(62), later, -1)
	_check(_cue_pitches(first, "seed_thrown") == _cue_pitches(delayed, "seed_thrown") and _cue_pitches(first, "seed_caught") == _cue_pitches(delayed, "seed_caught"), "A throw that happens later in a retry keeps its pitch")
	_check(_turn_trace(_tuned(63), _turn_script(), -1, "relay-isles@2", "garden") != first, "Another stage gives the same events other pitches")

func _check_memory_matches_live() -> void:
	# Turn A: the first spirit (slot p0) walks, opens the bridge and throws twice.
	var live: Array = []
	for i in range(8):
		live.append(["step", "p0", "a"])
		if i == 2: live.append(["event", "bridge_opened:west-relay", "a"])
		if i == 4: live.append(["event", "seed_thrown", "a"])
		if i == 6: live.append(["event", "seed_thrown", "a"])
	# Turn B replays that memory with the second spirit's own steps and catch
	# woven in at different moments.
	var remembered: Array = []
	for item: Array in live:
		remembered.append([item[0], item[1], "b"])
	for at: int in [0, 3, 3, 8, 11]: remembered.insert(at, ["step", "p1", "b"])
	remembered.insert(9, ["event", "seed_caught", "b"])
	var a_trace := _turn_trace(_tuned(71), live, -1)
	var b_trace := _turn_trace(_tuned(72), remembered, -1)
	var memory: Array = b_trace.filter(func(item): return item[0] == "seed_thrown" or str(item[0]).begins_with("bridge") or (item[0] == "step" and item[1] == "p0"))
	_check(memory.size() == a_trace.size() and memory == a_trace, "The memory's steps, bridge and throws sound exactly as they did live")

func _check_turn_constraints() -> void:
	var probe := _tuned(81)
	probe.begin_turn("first-steps@1", "a-place-to-grow")
	var previous := {}
	var repeated := false
	var miss_high := -100.0
	var catch_low := 100.0
	var step_previous := {}
	var separated := true
	for i in range(120):
		var spirit := "p0" if i % 2 else "p1"
		probe.play_footstep(spirit)
		var detune := _semitones(_last_step(probe).pitch_scale)
		if step_previous.has(spirit): separated = separated and absf(detune - step_previous[spirit]) >= Soundscape.STEP_MIN_MOVE - 0.001
		step_previous[spirit] = detune
		for event: String in ["seed_thrown", "seed_missed", "seed_caught"]:
			probe.consume_turn_events([event], [Soundscape.event_source(event, "b")], false)
			var step := _semitones(_last_cue(probe).pitch_scale)
			repeated = repeated or (previous.has(event) and absf(step - previous[event]) < Soundscape.CUE_MIN_MOVE - 0.0001)
			previous[event] = step
			if event == "seed_missed": miss_high = maxf(miss_high, step)
			if event == "seed_caught": catch_low = minf(catch_low, step)
	_check(not repeated and miss_high <= 0.0001 and catch_low >= -0.0001 and miss_high <= catch_low + 0.0001, "In a turn, a miss stays at or below its source, a catch at or above it, and a spirit's cues keep the minimum move")
	_check(separated, "Each spirit's neighbouring footsteps differ in a turn")
	probe.queue_free()

func _check_turn_reunions() -> void:
	var notes: Array = []
	for copy in range(2):
		var probe := _tuned(91 + copy)
		probe.begin_turn("relay-isles@2", "relay")
		var trace: Array = []
		for i in range(12):
			probe.play_reunion()
			trace.append(probe.reunion_voice.pitch_scale)
		notes.append(trace)
		probe.queue_free()
	var varied := true
	for i in range(1, notes[0].size()): varied = varied and absf(_semitones(notes[0][i]) - _semitones(notes[0][i - 1])) >= Soundscape.REUNION_MIN_MOVE - 0.0001
	_check(notes[0] == notes[1] and varied, "In a chapter the n-th meetup always plays the same pitch, well away from the last one")
	var home := _tuned(93)
	home.begin_turn("relay-isles@2", "relay")
	home.clear_turn()
	var heard: Array = []
	for i in range(40):
		home.play_reunion()
		heard.append(home.reunion_pitch)
	var changing := true
	for i in range(1, heard.size()): changing = changing and absf(heard[i] - heard[i - 1]) >= Soundscape.REUNION_MIN_MOVE - 0.0001
	var off_grid := 0
	for pitch: float in heard:
		if absf(pitch - roundf(pitch)) > 0.05: off_grid += 1
	_check(not home.in_turn() and changing and heard.size() == 40, "Back on Home the meetup chime is random again and always moves")
	_check(off_grid >= 20, "Home meetup pitches come from the continuous range, not whole semitones")
	home.queue_free()

static func _cue_pitches(trace: Array, cue: String) -> Array:
	return trace.filter(func(item): return item[0] == cue).map(func(item): return item[1])

func _check_global_rng() -> void:
	seed(4242)
	var expected: Array[int] = []
	for i in range(8):
		expected.append(randi())
	seed(4242)
	var probe := Tuned.new()
	root.add_child(probe)
	probe.configure({"sound": true, "haptics": false})
	var world := FakeWorld.new()
	root.add_child(world)
	probe.listen_to(world, "home")
	for i in range(40):
		probe.play_footstep()
		probe.consume_events(["seed_caught", "seed_missed", "seed_landed", "island_bloomed"], false)
		probe.clock += 7000 * (i % 2)
		probe.play_reunion()
		probe._on_call_due()
	var after: Array[int] = []
	for i in range(8):
		after.append(randi())
	_check(after == expected, "Audio variation never reads or advances the global random sequence")
	world.queue_free()
	probe.queue_free()
	randomize()

func _check_cue_table() -> void:
	var problems := SoundCues.problems()
	_check(problems.is_empty(), "Every cue, loop, mechanism and bed is complete: " + str(problems))
	_check(SoundCues.CUES.seed_missed.gain.y <= 0.0, "A miss is never louder than its source")
	for key: String in SoundCues.LOOPS:
		var looped := Soundscape._looping(SoundCues.LOOPS[key].clip)
		_check(looped.loop_mode == AudioStreamWAV.LOOP_FORWARD and looped.loop_end == roundi(looped.get_length() * looped.mix_rate), "Loop %s repeats across its whole length" % key)

## Bird calls: never the same variant twice running, each pitch inside its
## span and moved from the last, every gap inside the table's range, and the
## same seed gives the same calls.
func _check_call_picks() -> void:
	var spec: Dictionary = SoundCues.CALLS.birds
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	var last := -1
	var pitch := Soundscape.NO_PITCH
	var repeated := 0
	var outside := 0
	var still := 0
	var used := {}
	var picks: Array = []
	for i in range(2000):
		var pick := Soundscape.next_call(spec, rng, last, pitch)
		if pick.variant == last: repeated += 1
		if pick.gap < spec.gap.x or pick.gap > spec.gap.y or pick.gain < spec.gain.x or pick.gain > spec.gain.y or pick.pitch < spec.pitch.x - 0.001 or pick.pitch > spec.pitch.y + 0.001: outside += 1
		if pitch != Soundscape.NO_PITCH and absf(pick.pitch - pitch) < float(spec.min_move) - 0.001: still += 1
		used[pick.variant] = true
		last = pick.variant
		pitch = pick.pitch
		picks.append(pick)
	_check(repeated == 0, "Two bird calls in a row never use the same variant")
	_check(outside == 0, "Every bird call's gap, gain and pitch fall inside the table's spans")
	_check(still == 0, "Each bird call moves its pitch from the last one")
	_check(used.size() == spec.variants.size(), "Every bird variant gets its turn")
	rng.seed = 5150
	var again := Soundscape.next_call(spec, rng, -1, Soundscape.NO_PITCH)
	_check(again == picks[0], "The same seed gives the same bird calls")
	var lone := {"variants": [{"clip": SoundCues.BIRDS_1}], "pitch": Vector2.ZERO, "gain": Vector2.ZERO, "gap": Vector2(1.0, 1.0), "min_move": 0.0}
	_check(Soundscape.next_call(lone, rng, 0, 0.0).variant == 0, "A set with one variant still sings it")

## Birds sing one call at a time on their own voice, wait out the call and
## its gap, and stop with the sound, the background or the hidden world.
func _check_calls() -> void:
	var probe := _tuned(97)
	var world := FakeWorld.new()
	root.add_child(world)
	var spec: Dictionary = SoundCues.CALLS.birds
	probe.listen_to(world, "home")
	_check(probe._call_timer.time_left >= spec.first.x - 0.05 and probe._call_timer.time_left <= spec.first.y, "Home's first bird waits inside its first span")
	_check(not probe.call_voice.playing, "No bird sings the moment Home shows")
	var last_stream: AudioStream = null
	var repeats := 0
	var gaps_inside := true
	for i in range(30):
		probe._on_call_due()
		var voice := probe.call_voice
		if voice.stream == last_stream: repeats += 1
		last_stream = voice.stream
		var gap := probe._call_timer.wait_time - voice.stream.get_length() / voice.pitch_scale
		if gap < spec.gap.x - 0.01 or gap > spec.gap.y + 0.01: gaps_inside = false
	_check(repeats == 0, "Consecutive bird calls on Home never play the same clip")
	_check(gaps_inside, "Each bird call waits for its own end and then a gap inside the table's range")
	_check(probe.call_voice.playing and probe.call_voice.volume_db <= float(spec.db) and probe.call_voice.pitch_scale < 1.0, "A bird sings below the table's level and below its recorded pitch")
	var due := probe._call_timer.time_left
	probe._sync_loops()
	_check(probe.call_voice.playing and is_equal_approx(probe._call_timer.time_left, due), "The regular world check never restarts the birds")
	probe._call_timer.stop()
	probe._sync_loops()
	_check(probe.calling == "birds" and not probe._call_timer.is_stopped(), "The world check arms a set of calls whose timer stopped")
	probe.begin_turn("relay-isles@2", "relay")
	_check(probe.calling.is_empty() and probe._call_timer.is_stopped(), "A chapter without birds stops them")
	probe.clear_turn()
	_check(probe.calling == "birds" and not probe._call_timer.is_stopped(), "Back on Home the birds wait to sing again")
	world.visible = false
	probe._sync_loops()
	_check(probe.calling.is_empty() and probe._call_timer.is_stopped(), "A hidden Home stops its birds")
	# A long frame of checks before this would fire the timer before the fade's step.
	await process_frame
	await create_timer(Soundscape.LOOP_FADE + 0.1).timeout
	_check(not probe.call_voice.playing, "A bird mid-call fades out when Home hides")
	world.visible = true
	probe._sync_loops()
	_check(probe.calling == "birds" and not probe.call_voice.playing and probe._call_timer.time_left >= spec.first.x - 0.05, "Showing Home again waits before the first bird")
	probe._on_call_due()
	probe.configure({"sound": false, "haptics": false})
	_check(not probe.call_voice.playing and probe._call_timer.is_stopped() and probe.calling.is_empty(), "Sound off silences a bird at once")
	probe._on_call_due()
	_check(not probe.call_voice.playing, "No bird sings while sound is off")
	probe.configure({"sound": true, "haptics": false})
	_check(probe.calling == "birds" and not probe._call_timer.is_stopped(), "Sound back on lets the birds sing again")
	probe._on_call_due()
	probe.set_backgrounded(true)
	_check(not probe.call_voice.playing and probe._call_timer.is_stopped(), "Backgrounding silences the birds")
	probe.set_backgrounded(false)
	_check(probe.calling == "birds" and not probe._call_timer.is_stopped(), "Coming back to the foreground lets the birds sing again")
	world.visible = false
	probe._on_call_due()
	_check(not probe.call_voice.playing, "No bird sings for a world that has hidden before the world check")
	probe.queue_free()
	world.queue_free()

## A bell rings out on its own voice; a hitch's pile of cues is thinned to a
## few per frame without changing the pitch of any cue after it.
func _check_long_voice_and_cap() -> void:
	var probe := _tuned(71)
	probe.consume_events(["bell_rung"], false)
	_check(probe.long_voice.playing and probe.long_voice.stream == SoundCues.BELL and probe.next_voice == 0, "The bell rings on its own voice")
	for i in range(Soundscape.CUE_VOICES + 2): probe.consume_events(["seed_landed"], false)
	_check(probe.long_voice.playing, "A burst of short cues never cuts the bell's tail")
	probe.queue_free()
	var capped := _tuned(71)
	var free := _tuned(71)
	capped.max_cues_per_frame = Soundscape.MAX_CUES_PER_FRAME
	capped.begin_turn("relay-isles@2", "relay")
	free.begin_turn("relay-isles@2", "relay")
	var burst: Array = []
	for key: String in SoundCues.CUES:
		if burst.size() < Soundscape.MAX_CUES_PER_FRAME + 4 and SoundCues.CUES[key].get("voice", "") != "long": burst.append(key)
	capped.consume_turn_events(burst, [], false)
	free.consume_turn_events(burst, [], false)
	_check(capped.next_voice == Soundscape.MAX_CUES_PER_FRAME % Soundscape.CUE_VOICES, "One frame plays at most MAX_CUES_PER_FRAME cues")
	var kept := Soundscape.choose_cues(burst, Soundscape.MAX_CUES_PER_FRAME)
	var ranked := true
	for index in range(burst.size()):
		for other in range(burst.size()):
			if kept[index] == 0 and kept[other] == 1: ranked = ranked and SoundCues.priority(burst[other]) >= SoundCues.priority(burst[index])
	_check(Array(kept).count(1) == Soundscape.MAX_CUES_PER_FRAME and ranked, "A crowded frame keeps its highest-priority cues: " + str(kept))
	_check(Soundscape.choose_cues(["bridge_opened", "bridge_opened", "bridge_opened"], 2) == PackedByteArray([1, 0, 0]), "Repeats of one cue in a crowded frame sound once, as the first")
	_check(Soundscape.choose_cues(["bridge_opened", "water_rise"], 0) == PackedByteArray([0, 0]), "A frame a hitch already filled plays nothing more")
	var repeated := _tuned(71)
	repeated.max_cues_per_frame = 2
	repeated.consume_events(["bridge_opened", "bridge_opened", "bridge_opened"], false)
	repeated.consume_events(["seed_landed"], false)
	_check(repeated.next_voice == 2, "Merged repeats leave the frame's room for the next cue")
	repeated.queue_free()
	# The next frame's cue sounds as if nothing had been dropped.
	capped._cue_frame = -1
	capped.consume_turn_events(["seed_caught"], [], false)
	free.consume_turn_events(["seed_caught"], [], false)
	_check(is_equal_approx(_last_cue(capped).pitch_scale, _last_cue(free).pitch_scale), "Cues dropped in a hitch still count, so later pitches stay the same")
	capped.queue_free()
	free.queue_free()

## Turn of the Tide's busiest pinned ticks (tests/fixtures/golden/sound_trace.json,
## turn-of-the-tide@2): six, seven and ten cues in one tick, more than the cue
## voices. Every kind of cue still sounds once, the water and the valve always,
## each at exactly the pitch and gain its identity gives it, the same in any
## fresh soundscape (live, memory, retry or replay).
const BUSY_TICKS := [
	[["crossing_closing", "closing:stones-1"], ["crossing_closing", "closing:stones-2"], ["bridge_opened", "bridge_opened:jetty-1"],
		["bridge_opened", "bridge_opened:jetty-2"], ["valve_turned", "selector:tide"], ["water_rise", "water:tide|water"]],
	[["crossing_closing", "closing:jetty-1"], ["crossing_closing", "closing:jetty-2"], ["bridge_opened", "bridge_opened:sand-1"],
		["bridge_opened", "bridge_opened:slipway"], ["bridge_opened", "bridge_opened:wheel-step"], ["valve_turned", "selector:tide"],
		["water_fall", "water:tide|water"]],
	[["crossing_closing", "closing:sand-1"], ["crossing_closing", "closing:slipway"], ["crossing_closing", "closing:wheel-step"],
		["crossing_closing", "closing:race-stage"], ["bridge_opened", "bridge_opened:stones-1"], ["bridge_opened", "bridge_opened:stones-2"],
		["bridge_opened", "bridge_opened:stones-3"], ["bridge_opened", "bridge_opened:bollard-step"], ["valve_turned", "selector:tide"],
		["water_rise", "water:tide|water"]],
]

func _check_busy_ticks() -> void:
	for tick: Array in BUSY_TICKS:
		var keys: Array = []
		var sources: Array = []
		for cue: Array in tick:
			keys.append(cue[0])
			sources.append(cue[1] if str(cue[1]).contains("|") else cue[1] + "|" + cue[1])
		# What each cue's identity gives it, one cue per frame so nothing is capped.
		var free := _tuned(91)
		free.begin_turn("turn-of-the-tide@2", "set-the-tide")
		var owed := {}
		for index in range(keys.size()):
			free.consume_turn_events([keys[index]], [sources[index]], true)
			if not owed.has(keys[index]): owed[keys[index]] = _voice_sound(_last_cue(free))
		free.queue_free()
		var expected: Array = owed.values()
		expected.sort()
		var heard: Array = []
		for run in range(2):
			var capped := _tuned(92 + run)
			capped.max_cues_per_frame = Soundscape.MAX_CUES_PER_FRAME
			capped.begin_turn("turn-of-the-tide@2", "set-the-tide")
			capped.consume_turn_events(keys, sources, run == 0)
			var sounding: Array = []
			for voice: AudioStreamPlayer in capped.voices + [capped.long_voice]:
				if voice.playing: sounding.append(_voice_sound(voice))
			sounding.sort()
			heard.append(sounding)
			capped.queue_free()
		_check(heard[0] == expected, "A busy tick of %d cues plays each kind once at its own pitch, the water and the valve included: %s vs %s" % [keys.size(), heard[0], expected])
		_check(heard[0] == heard[1], "A busy tick sounds the same in a fresh soundscape, live or replayed")
	# A crowded tick whose first cue waits for the memory (memory_wait.gd): the
	# held cue takes no place, the rest are chosen, and the held ones are
	# chosen again when they sound.
	var waiting := _tuned(95)
	waiting.max_cues_per_frame = 2
	waiting.consume_turn_events(["bridge_opened", "seed_landed", "bridge_closed", "water_rise"], [], false, PackedInt32Array([0]))
	_check(_sounding(waiting) == [SoundCues.LAND.resource_path, SoundCues.WATER_SURGE.resource_path] and waiting.held_cue_count() == 1, "A crowded tick's held cue takes no place; the water and the first other cue sound: " + str(_sounding(waiting)))
	waiting.queue_free()
	var held := _tuned(96)
	held.consume_turn_events(["bridge_opened", "bridge_opened", "water_rise"], [], false, PackedInt32Array([0, 1, 2]))
	held.max_cues_per_frame = 1
	_check(held.release_held_cues() == 3 and _sounding(held) == [SoundCues.WATER_SURGE.resource_path], "Held cues released into a crowded frame keep the water first: " + str(_sounding(held)))
	held.queue_free()

static func _sounding(probe: Tuned) -> Array:
	var paths: Array = []
	for voice: AudioStreamPlayer in probe.voices:
		if voice.playing: paths.append(voice.stream.resource_path)
	paths.sort()
	return paths

static func _voice_sound(voice: AudioStreamPlayer) -> Array:
	return [voice.stream.resource_path, snappedf(voice.pitch_scale, 0.00001), snappedf(voice.volume_db, 0.0001)]

func _check_loops() -> void:
	var probe := _tuned(83)
	var world := FakeWorld.new()
	root.add_child(world)
	probe.listen_to(world, "home")
	_check(probe.calling == "birds" and not probe._call_timer.is_stopped() and _all_loops_silent(probe), "Home sings its bird calls while its world is on screen, on no bed or loop voice")
	probe.begin_turn("turn-of-the-tide@1", "set-the-tide")
	await create_timer(0.2).timeout
	_check(_loop_playing(probe, "water_near") and probe.calling == "shore" and not probe._call_timer.is_stopped(), "A chapter swaps the birds for its own water and its shore")
	world.mechanism_moving.emit("bucket", "bucket", -1)
	var reel := _loop_voice(probe, "reel")
	_check(reel != null and is_equal_approx(reel.pitch_scale, 1.0), "A lowering bucket turns the shared reel at its own pitch")
	world.mechanism_moving.emit("bucket", "bucket", 1)
	_check(reel != null and is_equal_approx(reel.pitch_scale, Soundscape.semitones_to_pitch(SoundCues.MOTION.bucket.rise)), "Winding the bucket up raises the reel")
	world.mechanism_moving.emit("ladder", "ladder", -1)
	world.mechanism_moving.emit("fold", "cliff-steps", 1)
	world.mechanism_moving.emit("fold", "long-stair", 1)
	var turning := 0
	for voice: AudioStreamPlayer in probe.loop_voices:
		if voice.playing and str(voice.get_meta("sounding", "")) != "": turning += 1
	_check(turning == Soundscape.LOOP_VOICES, "Mechanism loops never exceed their voices")
	for id: String in ["bucket", "ladder", "cliff-steps", "long-stair"]:
		world.mechanism_moving.emit("fold" if id.contains("-") else id, id, 0)
	_check(_loop_voice(probe, "reel") == null, "A mechanism that stops lets its loop go")
	# A world that keeps reporting a move it never finishes goes quiet after
	# the move's time; a turn starts the time again; running water never does.
	world.mechanism_moving.emit("drawbridge", "drawbridge", -1)
	_check(_loop_voice(probe, "reel") != null, "A lowering drawbridge turns the reel")
	probe._motions.drawbridge.since -= int(SoundCues.MOTION_MAX_SECONDS * 1000.0) + 1
	probe._sync_loops()
	_check(_loop_voice(probe, "reel") == null and probe._motions.has("drawbridge"), "A move still reported after its time lets its reel go")
	world.mechanism_moving.emit("drawbridge", "drawbridge", 1)
	_check(_loop_voice(probe, "reel") != null, "Turning the other way sounds again")
	world.mechanism_moving.emit("drawbridge", "drawbridge", 0)
	_check(not Soundscape.motion_spent({"kind": "spout", "since": 0}, 3600000) and Soundscape.motion_spent({"kind": "lift", "since": 0}, int(SoundCues.MOTION_MAX_SECONDS * 1000.0) + 1), "Running water pours as long as it runs; a winch's move is bounded")
	world.mechanism_moving.emit("bucket", "bucket", -1)
	world.process_mode = Node.PROCESS_MODE_DISABLED
	probe._sync_loops()
	_check(_loop_voice(probe, "reel") == null, "A world whose frames do not run moves nothing")
	world.process_mode = Node.PROCESS_MODE_INHERIT
	world.mechanism_moving.emit("bucket", "bucket", 0)
	world.mechanism_moving.emit("spout", "spout", 1)
	world.set_process(false)
	await create_timer(Soundscape.WORLD_CHECK_SECONDS + 0.15).timeout
	_check(_loop_voice(probe, "spout") == null and _loop_playing(probe, "water_near"), "A paused world keeps its bed but stills its mechanisms")
	world.set_process(true)
	world.visible = false
	await create_timer(Soundscape.WORLD_CHECK_SECONDS + 0.15).timeout
	_check(not _loop_playing(probe, "water_near") and _loop_voice(probe, "spout") == null, "A hidden world plays no bed or loop")
	world.visible = true
	await create_timer(Soundscape.WORLD_CHECK_SECONDS + 0.15).timeout
	_check(_loop_playing(probe, "water_near") and _loop_voice(probe, "spout") != null, "Showing the world again brings back what still sounds")
	# The pause card: the screen says paused, and the regular check hushes the water.
	var paused := [false]
	probe.quiet_while = func() -> bool: return paused[0]
	probe._on_call_due()
	_check(probe.call_voice.playing, "A shore wash plays when its call is due")
	probe.call_voice.stop()
	paused[0] = true
	probe._on_call_due()
	_check(not probe.call_voice.playing, "No shore wash starts once the screen is paused")
	await create_timer(Soundscape.WORLD_CHECK_SECONDS + 0.15).timeout
	_check(not _loop_playing(probe, "water_near") and _loop_voice(probe, "spout") == null and probe.calling.is_empty() and probe._call_timer.is_stopped(), "A paused screen hushes its bed, its loops and its shore")
	_check(not probe._world_check.is_stopped(), "and keeps checking, so it hears the pause end")
	paused[0] = false
	await create_timer(Soundscape.WORLD_CHECK_SECONDS + 0.15).timeout
	_check(_loop_playing(probe, "water_near") and probe.calling == "shore" and not probe._call_timer.is_stopped(), "Leaving the pause brings the water and the shore back")
	probe.quiet_while = Callable()
	probe.configure({"sound": false, "haptics": false})
	_check(_all_loops_silent(probe), "Sound off stops every loop and bed at once")
	probe.configure({"sound": true, "haptics": false})
	probe.set_backgrounded(true)
	_check(_all_loops_silent(probe), "Backgrounding stops every loop and bed at once")
	probe.queue_free()
	world.queue_free()

static func _all_loops_silent(probe: Tuned) -> bool:
	for voice: AudioStreamPlayer in probe.loop_voices + probe.bed_voices:
		if voice.playing: return false
	return true

## The voice playing a loop's clip, if any (loops play a looping copy).
static func _loop_voice(probe: Tuned, loop: String) -> AudioStreamPlayer:
	var clip: AudioStreamWAV = SoundCues.LOOPS[loop].clip
	var db: float = SoundCues.LOOPS[loop].db
	for voice: AudioStreamPlayer in probe.loop_voices + probe.bed_voices:
		if voice.playing and str(voice.get_meta("sounding", "")) != "" and voice.stream.data == clip.data and is_equal_approx(float(voice.get_meta("target_db", 0.0)), db):
			return voice
	return null

static func _loop_playing(probe: Tuned, loop: String) -> bool:
	return _loop_voice(probe, loop) != null

## Fixed cues (keepsakes and screens): one pitch per cue and variant, the
## keepsakes' first pitch as it always was, and no turn's pitch ever moves.
func _check_fixed_cues() -> void:
	var unchanged := true
	for key: String in SoundCues.CUES:
		var span: Vector2 = SoundCues.CUES[key].range
		unchanged = unchanged and Soundscape.fixed_pitch(key) == lerpf(span.x, span.y, Soundscape.identity_unit(["keepsake", key]))
	_check(unchanged, "Every keepsake beat keeps the one pitch it had before drops had variants")
	var pinned := {"well_plunk": -0.387539, "water_rise": 0.764946, "island_bloomed": 3.383716, "bell_rung": 0.767959}
	for key: String in pinned:
		_check(absf(Soundscape.fixed_pitch(key) - float(pinned[key])) < 0.00001, "The %s keepsake beat keeps its pinned pitch: %f" % [key, Soundscape.fixed_pitch(key)])
	var drops: Array = []
	var walk := true
	var drip_span: Vector2 = SoundCues.CUES.drip.range
	for variant in range(8):
		var pitch := Soundscape.fixed_pitch("drip", variant)
		walk = walk and pitch >= drip_span.x and pitch <= drip_span.y and pitch == Soundscape.fixed_pitch("drip", variant)
		if variant > 0: walk = walk and absf(pitch - float(drops[-1])) >= Soundscape.CUE_MIN_MOVE - 0.0001
		drops.append(pitch)
	_check(walk, "A run of drops stays in its span, moves each drop and is the same run every time: " + str(drops))
	var exact := true
	for key: String in SoundCues.CUES:
		if key.begins_with("ui_"): exact = exact and SoundCues.is_fixed(key) and SoundCues.CUES[key].range.x == SoundCues.CUES[key].range.y and Soundscape.fixed_pitch(key, 3) == SoundCues.CUES[key].range.x
	_check(exact, "Each screen confirmation has one exact pitch")
	for kind: String in Celebration.TIERS:
		_check(SoundCues.CUES.has(str(Celebration.TIERS[kind].get("cue", ""))), "The %s celebration names a cue" % kind)
	# The same turn with fixed cues between its events sounds exactly the same.
	var plain := _tuned(41)
	var busy := _tuned(42)
	var heard: Array = [[], []]
	for index in range(2):
		var probe: Tuned = [plain, busy][index]
		probe.begin_turn("turn-of-the-tide@2", "slack-water")
		for event: String in ["water_rise", "bridge_opened", "water_rise", "bridge_closed"]:
			if probe == busy:
				# A keepsake beat and screen sounds on the turn's own clips, and water.
				probe.play_fixed_cue("drip", 2)
				probe.play_fixed_cue("water_rise")
				probe.play_fixed_cue("ui_worn")
				probe.play_fixed_cue("ui_first")
			probe.consume_turn_events([event], ["b|" + event], true)
			heard[index].append(_voice_sound(_last_cue(probe)))
	_check(heard[0] == heard[1], "Keepsake and screen cues never move a turn's pitches: %s" % [heard])
	var played := busy.next_voice
	busy.configure({"sound": false, "haptics": false})
	busy.play_fixed_cue("ui_bought")
	busy.configure({"sound": true, "haptics": false})
	busy.set_backgrounded(true)
	busy.play_fixed_cue("ui_bought")
	busy.set_backgrounded(false)
	_check(busy.next_voice == played, "Sound off or the app in the background plays no fixed cue")
	# A new frame: the turn above already rang ui_first in this one.
	await process_frame
	busy.play_fixed_cue("ui_first")
	_check(busy.long_voice.playing and busy.long_voice.stream == SoundCues.BELL and is_equal_approx(busy.long_voice.pitch_scale, 1.0), "First place rings the bell on its own voice at its pitch")
	busy.play_fixed_cue("not-a-cue")
	_check(busy.next_voice == played, "An unknown fixed cue is silent")
	var host := Node.new()
	Soundscape.play_on(host, "ui_bought")
	Soundscape.play_on(null, "ui_bought")
	_check(busy.next_voice == played, "A host with no soundscape plays nothing and does not fail")
	host.free()
	var owner := Tuned.new()
	owner.max_cues_per_frame = 0
	root.add_child(owner)
	owner.configure({"sound": true, "haptics": false})
	var main_like := SoundHost.new()
	main_like.soundscape = owner
	Soundscape.play_on(main_like, "ui_bought")
	_check(owner.next_voice == 1 and owner.voices[0].playing and owner.voices[0].stream == SoundCues.BLOOM, "A host's soundscape plays the cue asked of it")
	# Two Pollen lines on one card: the same cue twice in a frame sounds once.
	owner.play_fixed_cue("ui_pollen")
	owner.play_fixed_cue("ui_pollen")
	owner.play_fixed_cue("drip", 1)
	owner.play_fixed_cue("drip", 2)
	_check(owner.next_voice == 4, "The same fixed cue twice in one frame sounds once; another variant still sounds")
	await process_frame
	owner.play_fixed_cue("ui_pollen")
	_check(owner.next_voice == 0, "and the next frame may sound it again")
	main_like.free()
	owner.queue_free()
	plain.queue_free()
	busy.queue_free()

## Every button's tick: one hook under the root, a confirmed press only, on the
## nearest screen's soundscape, quiet in-run controls, once per frame.
func _check_button_ticks() -> void:
	var tap: Dictionary = SoundCues.CUES[ButtonTicks.CUE]
	_check(Soundscape.CUE_DB + float(tap.db) < Soundscape.STEP_DB - Soundscape.STEP_JITTER_DB, "A button's tick plays under the quietest footstep")
	ButtonTicks.install(self)
	ButtonTicks.install(self)
	await process_frame
	var hooks := root.get_children().filter(func(child: Node) -> bool: return child.get_script() == ButtonTicks)
	_check(hooks.size() == 1, "Installing the tick twice in one frame keeps one hook under the root")
	var screen := TickScreen.new()
	root.add_child(screen)
	# As in the app: the screen showing is the tree's current scene.
	current_scene = screen
	var probe := TickProbe.new()
	probe.max_cues_per_frame = 0
	screen.add_child(probe)
	probe.configure({"sound": true, "haptics": false})
	screen.soundscape = probe
	var box := VBoxContainer.new()
	screen.add_child(box)
	var button := Button.new()
	box.add_child(button)
	button.mouse_entered.emit()
	button.focus_entered.emit()
	button.button_down.emit()
	_check(probe.ticks == 0, "Hover, focus and a press going down make no tick")
	button.pressed.emit()
	var voice := probe.voices[0]
	_check(probe.ticks == 1 and voice.stream == SoundCues.TICK and is_equal_approx(voice.volume_db, Soundscape.CUE_DB + float(tap.db)) and is_equal_approx(voice.pitch_scale, 1.0), "A confirmed press ticks on its screen's soundscape")
	var toggle := CheckButton.new()
	box.add_child(toggle)
	toggle.pressed.emit()
	button.pressed.emit()
	_check(probe.ticks == 1, "Presses in one frame tick once")
	await process_frame
	# A card that closes itself first (its handler runs before the tick) still ticks.
	var closer := Button.new()
	closer.pressed.connect(func() -> void: box.remove_child(closer))
	box.add_child(closer)
	closer.pressed.emit()
	_check(probe.ticks == 2 and not closer.is_inside_tree(), "A button its own press takes out of the tree ticks on the screen still showing")
	closer.free()
	await process_frame
	# Leaving a room: its handler takes the whole room away before the tick, so
	# the tick lands on the screen left showing, never on the room's (gone) one.
	var room := TickScreen.new()
	screen.add_child(room)
	var room_sound := TickProbe.new()
	room_sound.max_cues_per_frame = 0
	room.add_child(room_sound)
	room_sound.configure({"sound": true, "haptics": false})
	room.soundscape = room_sound
	var leave := Button.new()
	leave.pressed.connect(func() -> void: screen.remove_child(room))
	room.add_child(leave)
	leave.pressed.emit()
	_check(probe.ticks == 3 and room_sound.ticks == 0, "Leave ticks on the screen it returns to: %d %d" % [probe.ticks, room_sound.ticks])
	room.free()
	await process_frame
	# Quiet: the controls a run is played with, and a button that plays its own sound.
	var controls := ChapterControls.new()
	screen.add_child(controls)
	await process_frame
	for control: Button in [controls.action_button, controls.finish_button, controls.fast_forward_button]: control.pressed.emit()
	var reactions := Control.new()
	var face := Button.new()
	reactions.add_child(face)
	controls.dock_beside_finish(reactions, Vector2(120, 54))
	face.pressed.emit()
	_check(probe.ticks == 3 and ButtonTicks.soundscape_for(controls.action_button) == null, "The controls a run is played with never tick over its cues")
	controls.pause_button.pressed.emit()
	_check(probe.ticks == 4, "Pause ticks: it makes no cue of its own")
	await process_frame
	var card_button := controls.button("Play", func() -> void: pass)
	controls.overlay.add_child(card_button)
	card_button.pressed.emit()
	_check(probe.ticks == 5, "A card's button over the chapter ticks")
	await process_frame
	var own := Button.new()
	ButtonTicks.quiet(own)
	box.add_child(own)
	own.pressed.emit()
	_check(probe.ticks == 5, "A button that plays its own sound does not tick as well")
	ButtonTicks.quiet(own, false)
	own.pressed.emit()
	_check(probe.ticks == 6, "A button let tick again ticks (the Wardrobe's button toward Buy)")
	await process_frame
	# The nearest screen's soundscape: a room inside Main ticks on the room's.
	var inner := TickScreen.new()
	screen.add_child(inner)
	var inner_sound := TickProbe.new()
	inner_sound.max_cues_per_frame = 0
	inner.add_child(inner_sound)
	inner_sound.configure({"sound": true, "haptics": false})
	inner.soundscape = inner_sound
	var room_button := Button.new()
	inner.add_child(room_button)
	room_button.pressed.emit()
	_check(inner_sound.ticks == 1 and probe.ticks == 6, "A button ticks on the nearest screen's soundscape only")
	await process_frame
	probe.configure({"sound": false, "haptics": false})
	button.pressed.emit()
	probe.configure({"sound": true, "haptics": false})
	probe.set_backgrounded(true)
	button.pressed.emit()
	probe.set_backgrounded(false)
	_check(probe.ticks == 6, "Sound off or the app in the background makes no tick")
	# A press that opens a room or a replay covers its screen first, then ticks.
	var opener := Button.new()
	opener.pressed.connect(func() -> void: probe.set_covered(true))
	box.add_child(opener)
	opener.pressed.emit()
	_check(probe.covered and probe.ticks == 7, "A press that covers its own screen (opening a room or a replay) still ticks")
	await process_frame
	# Photo transfer: a child with no sound of its own over the covered screen.
	var transfer := Control.new()
	screen.add_child(transfer)
	var transfer_button := Button.new()
	transfer.add_child(transfer_button)
	transfer_button.pressed.emit()
	_check(probe.ticks == 8, "A button on a child with no sound ticks on the covered screen under it")
	transfer.free()
	probe.set_covered(false)
	await process_frame
	var bare := Button.new()
	root.add_child(bare)
	bare.pressed.emit()
	_check(probe.ticks == 8, "A button under no screen with sound is silent and does not fail")
	bare.free()
	# Real clicks: a release over the button ticks, and a Sound tile turned off
	# is silent (its toggled runs before pressed).
	var view := SubViewport.new()
	view.size = Vector2i(400, 300)
	view.handle_input_locally = true
	screen.add_child(view)
	var panel := TickScreen.new()
	panel.soundscape = probe
	panel.size = Vector2(400, 300)
	view.add_child(panel)
	var plain := Button.new()
	plain.position = Vector2(10, 10)
	plain.size = Vector2(120, 50)
	panel.add_child(plain)
	var tile := CheckButton.new()
	tile.button_pressed = true
	tile.position = Vector2(10, 100)
	tile.size = Vector2(120, 50)
	tile.toggled.connect(func(on: bool) -> void: probe.configure({"sound": on, "haptics": false}))
	panel.add_child(tile)
	await process_frame
	_click(view, Vector2(40, 30), true)
	_check(probe.ticks == 8, "Pressing down on a button makes no tick")
	_click(view, Vector2(40, 30), false)
	_check(probe.ticks == 9, "Letting go over it ticks")
	await process_frame
	_click(view, Vector2(40, 120), true)
	_click(view, Vector2(40, 120), false)
	_check(not tile.button_pressed and probe.ticks == 9, "Turning the Sound tile off makes no tick")
	await process_frame
	_click(view, Vector2(40, 120), true)
	_click(view, Vector2(40, 120), false)
	_check(tile.button_pressed and probe.ticks == 10, "Turning it back on ticks")
	current_scene = null
	screen.queue_free()
	for hook: Node in hooks: hook.queue_free()
	await process_frame

## Covered by a full-screen child: the world hushes, a fixed cue still plays.
func _check_covered() -> void:
	var probe := _tuned(71)
	var world := FakeWorld.new()
	root.add_child(world)
	probe.listen_to(world, "home")
	probe.begin_turn("turn-of-the-tide@1", "set-the-tide")
	await create_timer(0.2).timeout
	probe.consume_turn_events(["water_rise"], ["b|water_rise"], false)
	var sounding: AudioStreamPlayer = _last_cue(probe)
	_check(probe.ambience.playing and _loop_playing(probe, "water_near") and sounding.playing, "Before covering: ambience, bed and a cue sound")
	probe.set_covered(true)
	_check(not probe.ambience.playing and _all_loops_silent(probe) and probe.calling.is_empty(), "Covering hushes the ambience, beds and calls at once")
	_check(sounding.playing, "A cue already sounding finishes under the cover (the opening press's tick)")
	var played := probe.next_voice
	probe.consume_turn_events(["bridge_opened"], ["bridge_opened:x|bridge_opened:x"], false)
	probe.play_footstep("a")
	probe.play_reunion()
	_check(probe.next_voice == played and not probe.reunion_voice.playing and not probe.step_voices.any(func(voice: AudioStreamPlayer) -> bool: return voice.playing), "Covered, no turn cue, step or meetup sounds")
	probe.play_fixed_cue("ui_tap")
	_check(probe.next_voice != played, "Covered, a button's tick still plays")
	await process_frame
	probe.set_backgrounded(true)
	played = probe.next_voice
	probe.play_fixed_cue("ui_tap")
	_check(probe.next_voice == played and not sounding.playing, "In the background nothing plays, not even a tick")
	probe.set_backgrounded(false)
	_check(probe.covered and not probe.ambience.playing, "Coming back from the background keeps a covered screen hushed")
	probe.set_covered(false)
	await create_timer(Soundscape.WORLD_CHECK_SECONDS + 0.15).timeout
	_check(probe.ambience.playing and _loop_playing(probe, "water_near") and probe.calling == "shore", "Uncovering brings the ambience, bed and shore back")
	probe.queue_free()
	world.queue_free()

static func _click(view: SubViewport, at: Vector2, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = at
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	event.pressed = down
	view.push_input(event, true)

## Under Reduce motion a mechanism snaps, so the world reports no movement.
func _check_reduced_motion() -> void:
	var world: Node3D = preload("res://presentation/island_world.gd").new()
	var heard: Array = []
	world.mechanism_moving.connect(func(kind: String, id: String, direction: int): heard.append([kind, id, direction]))
	world.note_motion("ladder", "ladder", -1)
	world.note_motion("ladder", "ladder", -1)
	world.note_motion("ladder", "ladder", 0)
	_check(heard == [["ladder", "ladder", -1], ["ladder", "ladder", 0]], "A world reports a mechanism only when it starts and stops")
	heard.clear()
	world.reduced_motion = true
	world.note_motion("ladder", "ladder", 1)
	world.note_motion("spout", "spout", 1, false)
	_check(heard == [["spout", "spout", 1]], "Reduce motion silences moving mechanisms but not running water")
	world.free()

## A new level, as Home builds at launch, starts with its bridge at rest: it
## reports no moving drawbridge (whose reel sounded through the splash), and
## an immediate present with the bridge open raises it at once, silently.
func _check_bridge_at_rest() -> void:
	var world: Node3D = preload("res://presentation/island_world.gd").new()
	var heard: Array = []
	world.mechanism_moving.connect(func(kind: String, id: String, direction: int): heard.append([kind, id, direction]))
	root.add_child(world)
	var level: Dictionary = preload("res://core/levels.gd").all_levels()[0]
	world.load_level(level)
	var sim: RefCounted = preload("res://core/simulation.gd").new()
	sim.reset(level)
	world.present(sim.snapshot(), true)
	for i in range(4): await process_frame
	_check(heard.is_empty(), "A new level reports no moving bridge: %s" % [heard])
	var open: Dictionary = sim.snapshot()
	open.bridge_open = true
	world.present(open, true)
	for i in range(3): await process_frame
	_check(heard.is_empty() and world.bridge_parts.all(func(plank: Node3D) -> bool: return is_equal_approx(plank.position.y, world.BRIDGE_RAISED_Y)), "An immediate open bridge is raised at once, with no reel: %s" % [heard])
	world.queue_free()

func _check(condition: bool, message: String) -> void:
	checks+=1
	if not condition:
		failures+=1
		push_error(message)

func _run() -> void:
	var sound := Probe.new()
	sound.configure({"sound":false,"haptics":true})
	root.add_child(sound)
	await process_frame
	_check(not sound.ambience.playing,"Saved mute is respected before the audio node enters the tree")
	sound.play_footstep()
	_check(sound.next_step==0,"Saved mute also suppresses walking sounds")
	sound.play_reunion()
	_check(not sound.reunion_voice.playing,"Saved mute suppresses reunion sound")
	_check(is_equal_approx(sound.REUNION.get_length(),0.65),"Reunion uses the single approved greeting, not the repeated audition")
	var bed := sound.ambience.stream as AudioStreamWAV
	_check(bed.loop_end==roundi(bed.get_length()*bed.mix_rate),"Imported compressed audio loops across its full duration")
	_check(bed.loop_end>=bed.mix_rate*15,"The ambient loop is not truncated to encoded-byte length")
	sound.consume_events(["seed_caught"],true)
	_check(sound.next_voice==0 and sound.pulses==[35],"Haptic catch feedback works independently of sound mute")
	sound.pulses.clear()
	sound.configure({"sound":true,"haptics":false})
	_check(sound.ambience.playing,"Enabling sound starts ambience")
	sound.play_reunion()
	_check(sound.reunion_voice.playing and sound.pulses.is_empty(),"Reunion plays independently without adding vibration")
	sound.play_footstep()
	var first_step: AudioStream = sound.step_voices[0].stream
	sound.play_footstep()
	_check(sound.next_step == 2 and sound.step_voices[0].playing and sound.step_voices[1].playing, "Simultaneous player and ghost contacts remain independently audible")
	_check(sound.step_voices[1].stream != first_step, "Overlapping contacts retain the alternating sound variants")
	sound.play_footstep()
	_check(sound.next_step == 3 and sound.step_voices.size() == 3 and sound.step_voices[2].playing and sound.step_voices[2].stream == first_step, "The third contact is not rate-limited or coalesced")
	_check(absf(sound.step_voices[0].volume_db - Soundscape.STEP_DB) <= Soundscape.STEP_JITTER_DB + 0.001 and Soundscape.STEP_DB == -23.0 and sound.step_voices[0].stream.get_length() <= 0.11, "The original overlapping mix uses the short revised clips")
	sound.consume_events(["seed_caught","island_bloomed"],true)
	_check(sound.next_voice==2 and sound.pulses.is_empty(),"Disabling haptics leaves audible gameplay feedback enabled")
	sound.configure({"sound":true,"haptics":true})
	sound.consume_events(["seed_caught","island_bloomed"],false)
	_check(sound.next_voice==4 and sound.pulses.is_empty(),"Replay events play sound without vibrating the device")
	sound.set_backgrounded(true)
	_check(not sound.reunion_voice.playing,"Backgrounding stops an in-flight reunion")
	sound.play_reunion()
	_check(not sound.reunion_voice.playing,"Background suppresses new reunion audio")
	_check(not sound.ambience.playing,"Backgrounding stops ambience")
	var all_stopped := true
	for voice in sound.voices:
		all_stopped=all_stopped and not voice.playing
	_check(all_stopped,"Backgrounding stops in-flight effects")
	sound.play_footstep()
	_check(sound.next_step==3 and not sound.step_voices[0].playing and not sound.step_voices[1].playing and not sound.step_voices[2].playing,"Backgrounding stops and suppresses every overlapping walking sound")
	var before := sound.next_voice
	sound.consume_events(["seed_caught","island_bloomed"],true)
	_check(sound.next_voice==before and sound.pulses.is_empty(),"Background events cause neither audio nor vibration")
	sound.set_backgrounded(false)
	_check(sound.ambience.playing,"Returning foreground resumes allowed ambience")
	sound.play_reunion()
	_check(sound.reunion_voice.playing,"A new foreground reunion plays immediately")
	sound.stop_reunion()
	_check(not sound.reunion_voice.playing and sound.ambience.playing,"Pausing a reunion leaves the ambience preference alone")
	sound.play_reunion()
	sound.play_footstep()
	_check(sound.next_step == 4, "Returning foreground permits a new contact immediately")
	sound.configure({"sound":false,"haptics":false})
	_check(not sound.reunion_voice.playing,"Turning sound off stops an in-flight reunion")
	sound.set_backgrounded(true)
	sound.set_backgrounded(false)
	_check(not sound.ambience.playing,"Returning foreground preserves the saved mute setting")
	sound.consume_events(["unknown_event"],true)
	_check(sound.next_voice==before and sound.pulses.is_empty(),"Unrecognized simulation events remain silent")
	_variation()
	_check_cue_table()
	_check_long_voice_and_cap()
	_check_busy_ticks()
	_check_call_picks()
	await _check_calls()
	await _check_loops()
	_check_reduced_motion()
	await _check_bridge_at_rest()
	await _check_fixed_cues()
	await _check_button_ticks()
	await _check_covered()
	sound.queue_free()
	await process_frame
	# Let the audio thread consume its queued stop commands before shutting down.
	await create_timer(0.15).timeout
	print("AFTER YOU SOUNDSCAPE: %d checks, %d failures" % [checks,failures])
	quit(1 if failures>0 else 0)
