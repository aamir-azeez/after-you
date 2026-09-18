extends SceneTree

const Chapter = preload("res://relay_preview.gd")
const Lighthouse = preload("res://lighthouse_preview.gd")
const Journey = preload("res://services/relay_journey.gd")
const LighthouseJourney = preload("res://services/lighthouse_journey.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Soundscape = preload("res://services/soundscape.gd")

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
	_check(sound.get_script() == Soundscape and sound.step_voices.size() == 3 and sound.step_voices[0].volume_db == -23.0, "Every chapter preserves the shared overlapping mixer: " + key)
	screen._begin()
	var state_before: String = Canonical.digest(screen.sim.snapshot())
	var save_before := FileAccess.get_sha256(path)
	_contacts(screen, false)
	_check(sound.next_step == 2 and sound.step_voices[0].playing and sound.step_voices[1].playing, "Two actual visible spirits stepping together retain both overlapping contacts: " + key)
	var first_clip: AudioStream = sound.step_voices[0].stream
	_contacts(screen, true)
	_check(sound.next_step == 4 and sound.step_voices[2].stream == first_clip and sound.step_voices[0].stream != first_clip, "Reduced motion retains both alternating contacts without throttling: " + key)
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
	screen.queue_free()
	await process_frame
	for suffix: String in ["", ".tmp", ".backup"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)

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
