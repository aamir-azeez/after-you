extends SceneTree

const Chapter = preload("res://relay_preview.gd")
const Lighthouse = preload("res://lighthouse_preview.gd")
const Journey = preload("res://services/relay_journey.gd")
const LighthouseJourney = preload("res://services/lighthouse_journey.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Soundscape = preload("res://services/soundscape.gd")
const Retained = preload("res://tests/retained_chapter_fixture.gd")

var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	for chapter: String in [Registry.FIRST_STEPS, Registry.RELAY, "lighthouse"]:
		await _chapter(chapter)
	await create_timer(0.2).timeout
	print("CHAPTER FOOTSTEPS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _chapter(key: String) -> void:
	var path := "user://chapter-footsteps-" + Crypto.new().generate_random_bytes(8).hex_encode() + ".json"
	var screen: Node3D
	var journal: RefCounted
	var first: Dictionary
	if key == "lighthouse":
		screen = Lighthouse.new()
		journal = LighthouseJourney.new(path)
		first = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/lighthouse/first-two-v3.json")).pairs[0].a
	else:
		screen = Chapter.new()
		screen.chapter_key = key
		_check(Retained.seed(path,key),"Retained walking fixtures load their exact earlier journal pin")
		journal = Journey.new(path, null, key)
		var file := "first_steps/a-little-lift-a" if key == Registry.FIRST_STEPS else "v2/relay-a"
		first = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/" + file + ".json"))
	journal.load_data()
	_check(journal.accept_recording(first), "An authentic source recording prepares player-plus-ghost walking: " + key)
	screen.journey = journal
	screen.settings = {"sound": true, "haptics": false, "reduced_motion": false}
	root.add_child(screen)
	screen.set_physics_process(false)
	screen.world.set_process(false)
	var deadline := Time.get_ticks_msec() + 30000
	while screen.mode == "loading" and Time.get_ticks_msec() < deadline: await process_frame
	screen.set_process(false)
	_check(screen.mode == "ready" and screen.role == "b", "Real chapter admission keeps its verified source: " + key)
	var sound: Node = screen.soundscape
	_check(sound.get_script() == Soundscape and sound.step_voices.size() == 3 and absf(sound.step_voices[0].volume_db - Soundscape.STEP_DB) <= Soundscape.STEP_JITTER_DB + 0.001, "Every chapter preserves the shared overlapping mixer: " + key)
	screen._begin()
	var state_before: String = Canonical.digest(screen.sim.snapshot())
	var save_before := FileAccess.get_sha256(path)
	_contacts(screen, false)
	_check(sound.next_step == 2 and sound.step_voices[0].playing and sound.step_voices[1].playing, "Two actual visible spirits stepping together retain both overlapping contacts: " + key)
	var first_clips: Array = [sound.step_voices[0].stream, sound.step_voices[1].stream]
	_check(first_clips[0] != first_clips[1], "Two spirits stepping together use both contact samples: " + key)
	var pitches: Array[float] = [sound.step_voices[0].pitch_scale, sound.step_voices[1].pitch_scale]
	_contacts(screen, true)
	_check(sound.next_step == 4 and sound.step_voices[2].stream != first_clips[0] and sound.step_voices[0].stream != first_clips[1], "Reduced motion retains each spirit's alternating contacts without throttling: " + key)
	pitches.append_array([sound.step_voices[2].pitch_scale, sound.step_voices[0].pitch_scale])
	var varied := true
	for i in range(1, pitches.size()):
		varied = varied and not is_equal_approx(pitches[i], pitches[i - 1])
	_check(varied, "Consecutive player and source contacts are pitched apart in the actual scene: " + key)
	_check(Canonical.digest(screen.sim.snapshot()) == state_before and FileAccess.get_sha256(path) == save_before, "Visual walking and audio never mutate simulation or saved proof: " + key)
	sound.configure({"sound": false, "haptics": false})
	_contacts(screen, false)
	_check(sound.next_step == 4 and not sound.step_voices[0].playing, "Saved sound-off suppresses contacts in the actual scene: " + key)
	sound.configure({"sound": true, "haptics": false})
	screen._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	_contacts(screen, false)
	_check(sound.next_step == 4 and sound.backgrounded and not sound.step_voices[0].playing, "Backgrounding stops the footstep and scene emission path: " + key)
	screen._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	_contacts(screen, false)
	_check(sound.next_step == 4 and not screen.running, "Returning to a paused turn does not replay queued footsteps: " + key)
	if key != Registry.FIRST_STEPS: _recorded_pitches(screen, key)
	screen.queue_free()
	await process_frame
	for suffix: String in ["", ".tmp", ".backup"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)

## The second turn's cues, live, after a retry and as a replay, through the
## chapter's own sound wiring. The memory's bridge is part of every run.
func _recorded_pitches(screen: Node, key: String) -> void:
	var second: Dictionary
	if key == "lighthouse":
		second = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/lighthouse/first-two-v3.json")).pairs[0].b
	else:
		second = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/v2/relay-b.json"))
	screen.soundscape.configure({"sound": true, "haptics": false})
	screen._begin()
	var live := _drive(screen, second)
	screen._begin()
	var retry := _drive(screen, second)
	screen.review = second.duplicate(true)
	screen._preview_turn()
	var replay := _drive(screen, second)
	_check(not live.is_empty() and live.any(func(cue): return cue[0] == "bridge_opened"), "The second turn plays the memory's bridge and its own cues: " + key)
	_check(retry == live and replay == live, "A retry and a replay play the live turn's exact pitches: " + key)
	# Several cues share a clip, so a pitch only has to fit one of that clip's ranges.
	var ranged := true
	for cue: Array in live:
		var semitones := 12.0 * log(float(cue[1])) / log(2.0)
		var fits := false
		for name: String in Soundscape.CUE_RANGES:
			var span: Vector2 = Soundscape.CUE_RANGES[name]
			fits = fits or (Soundscape.CLIPS[name] == Soundscape.CLIPS[cue[0]] and semitones >= span.x - 0.0001 and semitones <= span.y + 0.0001)
		ranged = ranged and fits
	_check(ranged, "Every recorded cue pitch stays inside a range for its clip: " + key)

func _drive(screen: Node, recording: Dictionary) -> Array:
	var sound: Node = screen.soundscape
	var heard: Array = []
	for input: Dictionary in screen.sim.expand_recording_inputs(recording):
		if screen.mode not in ["play", "replay"]: break
		var before: int = sound.next_voice
		screen.advance_input(input)
		var index := before
		while index != sound.next_voice:
			var voice: AudioStreamPlayer = sound.voices[index]
			heard.append([_cue_name(voice.stream), voice.pitch_scale, voice.volume_db])
			index = (index + 1) % sound.voices.size()
	return heard

static func _cue_name(stream: AudioStream) -> String:
	for cue: String in Soundscape.CLIPS:
		if Soundscape.CLIPS[cue] == stream: return cue
	return ""

func _contacts(screen: Node, reduced: bool) -> void:
	var visible := 0
	for actor: Node3D in screen.world.actors.values():
		if actor.visible:
			visible += 1
			actor.advance_motion(Vector3(0.42, 0, 0), 0.175, reduced)
	_check(visible == 2, "The tested contacts use both visible player and source spirits")

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
