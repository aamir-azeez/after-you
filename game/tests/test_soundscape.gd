extends SceneTree

const Soundscape = preload("res://services/soundscape.gd")

class Probe:
	extends "res://services/soundscape.gd"
	var pulses: Array[int] = []
	func _emit_haptic(duration_ms: int) -> void:
		pulses.append(duration_ms)

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
	_check_footsteps()
	_check_cues()
	_check_miss_below_catch()
	_check_reunion_phrase()
	_check_muted()
	var trace := _sequence(20261010)
	_check(trace.size() == 66 and trace == _sequence(20261010), "A seeded variation generator reproduces the same cue sequence")
	_check(trace != _sequence(7), "Different variation seeds give different cue sequences")
	_check_global_rng()

func _tuned(seed_value: int) -> Tuned:
	var probe := Tuned.new()
	probe.variation.seed = seed_value
	root.add_child(probe)
	probe.configure({"sound": true, "haptics": false})
	return probe

static func _semitones(pitch: float) -> float:
	return 12.0 * log(pitch) / log(2.0)

static func _last_cue(probe: Tuned) -> AudioStreamPlayer:
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
	var keys: Array = Soundscape.CUE_STEPS.keys()
	_check(keys.size() == Soundscape.CLIPS.size(), "Every gameplay cue has its own pitch steps")
	var order: Array = []
	for i in range(160):
		order.append(keys[i % keys.size()])
	for key: String in keys:
		for i in range(12):
			order.append(key)
	var last := {}
	var seen := {}
	var allowed := true
	var repeated := false
	var gains := true
	for key: String in order:
		probe.consume_events([key], false)
		var voice := _last_cue(probe)
		var step := roundi(_semitones(voice.pitch_scale))
		var family: String = Soundscape.CLIPS[key].resource_path
		allowed = allowed and voice.stream == Soundscape.CLIPS[key] and Soundscape.CUE_STEPS[key].has(step) and is_equal_approx(voice.pitch_scale, Soundscape.semitones_to_pitch(step))
		repeated = repeated or last.get(family, 1000) == step
		last[family] = step
		seen["%s:%d" % [key, step]] = true
		var offset := voice.volume_db - Soundscape.CUE_DB
		gains = gains and (offset >= -1.001 and offset <= 0.001 if key == "seed_missed" else absf(offset) <= Soundscape.CUE_JITTER_DB + 0.001)
	var complete := true
	for key: String in keys:
		for step: int in Soundscape.CUE_STEPS[key]:
			complete = complete and seen.has("%s:%d" % [key, step])
	_check(allowed, "One-shot cues only use their musical pitch steps")
	_check(not repeated, "No cue repeats its previous pitch step back to back, even when interleaved")
	_check(complete, "Every allowed pitch step is reachable for every cue")
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
	var steps: Dictionary = Soundscape.CUE_STEPS
	_check(steps.seed_missed.max() <= 0 and steps.seed_missed.max() <= steps.seed_caught.min(), "Miss steps never rise above the source pitch or any catch step")
	_check(miss_high <= catch_low + 0.00001 and miss_high <= 1.00001, "A played miss is never pitched above a played catch")
	probe.queue_free()

func _check_reunion_phrase() -> void:
	var probe := _tuned(53)
	var steps: Array = Soundscape.REUNION_STEPS
	var indices: Array[int] = []
	var gains := true
	for i in range(9):
		probe.clock += 1500
		probe.play_reunion()
		indices.append(steps.find(roundi(_semitones(probe.reunion_voice.pitch_scale))))
		gains = gains and absf(probe.reunion_voice.volume_db - Soundscape.REUNION_DB) <= Soundscape.REUNION_JITTER_DB + 0.001
	var climbing := indices[0] >= 0 and indices[0] < steps.size() - 1 and probe.reunion_voice.playing
	for i in range(1, indices.size()):
		climbing = climbing and indices[i] == (indices[i - 1] + 1) % steps.size()
	_check(climbing, "Meetups close together climb the reunion phrase and wrap")
	var fresh := true
	var starts := {}
	var previous: int = indices[-1]
	for i in range(60):
		probe.clock += Soundscape.REUNION_PHRASE_MS + 1
		probe.play_reunion()
		var index := steps.find(roundi(_semitones(probe.reunion_voice.pitch_scale)))
		fresh = fresh and index >= 0 and index < steps.size() - 1 and index != previous
		starts[index] = true
		previous = index
		gains = gains and absf(probe.reunion_voice.volume_db - Soundscape.REUNION_DB) <= Soundscape.REUNION_JITTER_DB + 0.001
	_check(fresh and starts.size() == steps.size() - 1, "Separate meetups start a fresh phrase on a different note with room to climb")
	_check(gains, "Reunion gain stays around the existing level")
	probe.queue_free()

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
		_check(silent and probe.next_step == 0 and probe.next_voice == 0 and probe.reunion_index == -1, "Suppressed audio plays no footsteps, cues or reunions: " + setting)
		_check(probe.variation.state == state and probe.last_steps.is_empty(), "Suppressed audio does not advance the variation sequence: " + setting)
	probe.queue_free()

func _sequence(seed_value: int) -> Array:
	var probe := _tuned(seed_value)
	var keys: Array = Soundscape.CUE_STEPS.keys()
	var trace: Array = []
	for i in range(30):
		probe.play_footstep()
		trace.append([_last_step(probe).pitch_scale, _last_step(probe).volume_db])
		probe.consume_events([keys[i % keys.size()]], false)
		trace.append([_last_cue(probe).pitch_scale, _last_cue(probe).volume_db])
		if i % 5 == 0:
			probe.clock += 9000 if i % 10 == 0 else 2500
			probe.play_reunion()
			trace.append([probe.reunion_voice.pitch_scale, probe.reunion_voice.volume_db])
	probe.queue_free()
	return trace

func _check_global_rng() -> void:
	seed(4242)
	var expected: Array[int] = []
	for i in range(8):
		expected.append(randi())
	seed(4242)
	var probe := Tuned.new()
	root.add_child(probe)
	probe.configure({"sound": true, "haptics": false})
	for i in range(40):
		probe.play_footstep()
		probe.consume_events(["seed_caught", "seed_missed", "seed_landed", "island_bloomed"], false)
		probe.clock += 7000 * (i % 2)
		probe.play_reunion()
	var after: Array[int] = []
	for i in range(8):
		after.append(randi())
	_check(after == expected, "Audio variation never reads or advances the global random sequence")
	probe.queue_free()
	randomize()

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
	sound.queue_free()
	await process_frame
	# Let the audio thread consume its queued stop commands before shutting down.
	await create_timer(0.15).timeout
	print("AFTER YOU SOUNDSCAPE: %d checks, %d failures" % [checks,failures])
	quit(1 if failures>0 else 0)
