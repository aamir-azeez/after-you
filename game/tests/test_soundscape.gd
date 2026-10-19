extends SceneTree

const Soundscape = preload("res://services/soundscape.gd")
const SoundCues = preload("res://services/sound_cues.gd")

class Probe:
	extends "res://services/soundscape.gd"
	var pulses: Array[int] = []
	var last_key := ""
	func _emit_haptic(duration_ms: int) -> void:
		pulses.append(duration_ms)
	func _play_cue(key: String, step: float, gain: float, live_play: bool) -> void:
		super(key, step, gain, live_play)
		last_key = key

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
	probe.calling = "birds"
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
	probe._sync_loops()
	_check(probe.call_voice.playing and not probe._call_timer.is_stopped(), "The regular world check never restarts the birds")
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
	probe._on_call_due()
	probe.set_backgrounded(true)
	_check(not probe.call_voice.playing and probe._call_timer.is_stopped(), "Backgrounding silences the birds")
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
	for i in range(Soundscape.MAX_CUES_PER_FRAME + 4): burst.append("bridge_opened")
	capped.consume_turn_events(burst, [], false)
	free.consume_turn_events(burst, [], false)
	_check(capped.next_voice == Soundscape.MAX_CUES_PER_FRAME % Soundscape.CUE_VOICES, "One frame plays at most MAX_CUES_PER_FRAME cues")
	# The next frame's cue sounds as if nothing had been dropped.
	capped._cue_frame = -1
	capped.consume_turn_events(["seed_caught"], [], false)
	free.consume_turn_events(["seed_caught"], [], false)
	_check(is_equal_approx(_last_cue(capped).pitch_scale, _last_cue(free).pitch_scale), "Cues dropped in a hitch still count, so later pitches stay the same")
	capped.queue_free()
	free.queue_free()

func _check_loops() -> void:
	var probe := _tuned(83)
	var world := FakeWorld.new()
	root.add_child(world)
	probe.listen_to(world, "home")
	_check(probe.calling == "birds" and not probe._call_timer.is_stopped() and _all_loops_silent(probe), "Home sings its bird calls while its world is on screen, on no bed or loop voice")
	probe.begin_turn("turn-of-the-tide@1", "set-the-tide")
	await create_timer(0.2).timeout
	_check(_loop_playing(probe, "water_near") and probe.calling.is_empty() and probe._call_timer.is_stopped(), "A chapter swaps the birds for its own water")
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
	_check_call_picks()
	await _check_calls()
	await _check_loops()
	_check_reduced_motion()
	sound.queue_free()
	await process_frame
	# Let the audio thread consume its queued stop commands before shutting down.
	await create_timer(0.15).timeout
	print("AFTER YOU SOUNDSCAPE: %d checks, %d failures" % [checks,failures])
	quit(1 if failures>0 else 0)
