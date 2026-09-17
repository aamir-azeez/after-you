extends SceneTree

const Main = preload("res://main.gd")
const Storage = preload("res://services/local_save.gd")
const Levels = preload("res://core/levels.gd")
const Simulation = preload("res://core/simulation.gd")

class SoundProbe:
	extends "res://services/soundscape.gd"
	var deliveries: Array=[]
	var pulses: Array=[]
	var transitions: Array=[]
	var startup_sound := true
	func _ready() -> void:
		startup_sound=sound_enabled
		super._ready()
	func consume_events(events: Array, live_play: bool) -> void:
		deliveries.append({"events":events.duplicate(),"live":live_play})
		super.consume_events(events,live_play)
	func _emit_haptic(duration_ms: int) -> void:
		pulses.append(duration_ms)
	func set_backgrounded(value: bool) -> void:
		transitions.append(value)
		super.set_backgrounded(value)

var checks := 0
var failures := 0
var app: Node
var sound: SoundProbe
var first: Dictionary
var second: Dictionary
var frames: Array

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var path := "user://audio-integration-"+Crypto.new().generate_random_bytes(8).hex_encode()+".json"
	first=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/first-light-a.json"))
	second=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/first-light-b.json"))
	frames=Simulation.expand_recording_inputs(second)
	app=Main.new()
	app.saves=Storage.new(path)
	app.saves.data.settings.sound=false
	app.saves.data.settings.haptics=true
	app.saves.flush()
	sound=SoundProbe.new()
	app.soundscape=sound
	root.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	await process_frame
	_check(not sound.startup_sound and not sound.ambience.playing,"Main applies saved mute before Soundscape enters the tree")
	app.saves.data.settings.sound=true
	app._apply_settings()
	_check(sound.sound_enabled and sound.ambience.playing,"Settings controls configure the installed sound service")
	_test_preview_delivery()
	_test_live_delivery()
	_test_draft_reconstruction()
	_test_footstep_delivery()
	_test_background()
	sound.set_backgrounded(true)
	app.queue_free()
	await process_frame
	# This test compresses whole turns into synchronous calls. Let the audio
	# mixer retire its stopped playback handles before shutting down the engine.
	await create_timer(0.5).timeout
	for suffix: String in ["",".tmp",".backup"]:
		if FileAccess.file_exists(path+suffix):
			DirAccess.remove_absolute(path+suffix)
	print("AFTER YOU AUDIO INTEGRATION: %d checks, %d failures" % [checks,failures])
	quit(1 if failures>0 else 0)

func _prepare() -> void:
	app.level_index=0
	app.current_level=Levels.get_level(0)
	app.attempt={"a":first.duplicate(true),"b":{},"draft":{}}
	app.role="b"
	app.room_play=false
	sound.deliveries.clear()
	sound.pulses.clear()
	app._prepare_turn()

func _events() -> Array:
	var events: Array=[]
	for delivery: Dictionary in sound.deliveries:
		events.append_array(delivery.events)
	return events

func _test_preview_delivery() -> void:
	_prepare()
	app._preview(second,true)
	_check(sound.deliveries.is_empty(),"Preparing a replay does not replay setup or verification events")
	for _i: int in range(frames.size()+2):
		app._physics_process(1.0/30.0)
	_check(sound.deliveries.size()==int(second.duration_ticks),"Replay delivers events exactly once per advancing simulation tick")
	var events := _events()
	_check(events.count("seed_thrown")==1 and events.count("seed_caught")==1 and events.count("island_bloomed")==1,"Completed replay forwards throw, catch and bloom once each")
	var all_preview := true
	for delivery: Dictionary in sound.deliveries:
		all_preview=all_preview and not delivery.live
	_check(all_preview and sound.pulses.is_empty(),"Replay sound is never marked as live play and cannot vibrate")
	var before: int=sound.deliveries.size()
	app.running=true
	app.mode="play"
	app._physics_process(1.0/30.0)
	_check(sound.deliveries.size()==before,"A finished simulation snapshot cannot replay its final audio event")

func _test_live_delivery() -> void:
	_prepare()
	app._begin_turn()
	var right: Vector3=app.world.camera.global_basis.x
	var forward: Vector3=app.world.camera.global_basis.z
	right=Vector3(right.x,0,right.z).normalized()
	forward=Vector3(forward.x,0,forward.z).normalized()
	for frame: Dictionary in frames:
		var movement := Vector3(frame.move_x,0,frame.move_z)
		app.stick.value=Vector2(movement.dot(right),movement.dot(forward))
		app.action_pressed=frame.interact
		app._physics_process(1.0/30.0)
	_check(app.sim.complete and app.mode=="completion","Real main controls complete the fixture's second turn before the review overlay")
	_check(sound.deliveries.size()==int(second.duration_ticks) and sound.pulses==[35,85],"Live catch and bloom produce exactly one haptic each")
	var events := _events()
	_check(events.count("seed_caught")==1 and events.count("island_bloomed")==1,"Rendering and autosave do not duplicate live success audio")

func _test_draft_reconstruction() -> void:
	_prepare()
	app._resume_draft(second)
	_check(app.mode=="review" and sound.deliveries.is_empty() and sound.pulses.is_empty(),"Completed draft reconstruction is silent despite historic catch and bloom events")
	var partial := Simulation.new()
	partial.reset(Levels.get_level(0),first,"b")
	for frame: Dictionary in frames.slice(0,40):
		partial.step(frame)
	_prepare()
	app._resume_draft(partial.export_recording())
	_check(app.running and app.sim.tick==40 and sound.deliveries.is_empty(),"Partial draft fast-forward is silent and resumes at its saved tick")
	app._physics_process(1.0/30.0)
	_check(sound.deliveries.size()==1,"Only the first new tick after reconstruction reaches the sound service")

func _test_footstep_delivery() -> void:
	_prepare()
	app._begin_turn()
	var before := sound.next_step
	var state_before := JSON.stringify(app.sim.snapshot())
	var contacts := 0
	for actor: Node3D in app.world.actors.values():
		if actor.visible:
			contacts += 1
			actor.advance_motion(Vector3(0.42,0,0),0.175,false)
	_check(contacts == 2 and sound.next_step == before + 2 and sound.step_voices.size() == 3,"Earlier Islands preserves simultaneous player and ghost footsteps through Main's real sound wiring")
	_check(JSON.stringify(app.sim.snapshot()) == state_before,"Earlier-island foot contacts remain presentation-only")

func _test_background() -> void:
	sound.transitions.clear()
	app._notification(Main.NOTIFICATION_APPLICATION_PAUSED)
	app._notification(Main.NOTIFICATION_APPLICATION_PAUSED)
	var before: int=sound.deliveries.size()
	app._physics_process(1.0/30.0)
	_check(sound.transitions==[true] and sound.backgrounded and not sound.ambience.playing and sound.deliveries.size()==before,"Background notification silences audio once and stops tick delivery")
	app._notification(Main.NOTIFICATION_APPLICATION_RESUMED)
	app._notification(Main.NOTIFICATION_APPLICATION_RESUMED)
	_check(sound.transitions==[true,false] and sound.ambience.playing and app.mode=="paused" and not app.running,"Resume restores ambience once while leaving the rehearsal paused")
	app.saves.data.settings.sound=false
	app.saves.data.settings.haptics=false
	app._apply_settings()
	app._notification(Main.NOTIFICATION_APPLICATION_PAUSED)
	app._notification(Main.NOTIFICATION_APPLICATION_RESUMED)
	_check(not sound.sound_enabled and not sound.haptics_enabled and not sound.ambience.playing,"Main preserves mute and haptic preferences through background transitions")

func _check(condition: bool, message: String) -> void:
	checks+=1
	if not condition:
		failures+=1
		push_error(message)
