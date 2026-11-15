extends SceneTree

const Main = preload("res://main.gd")
const Storage = preload("res://services/local_save.gd")
const ReunionAudio = preload("res://tests/reunion_audio_checks.gd")
const HomeStage = preload("res://presentation/home_stage.gd")

class SoundProbe:
	extends "res://services/soundscape.gd"
	var transitions: Array=[]
	var startup_sound := true
	var greetings := 0
	func _ready() -> void:
		startup_sound=sound_enabled
		super._ready()
	func set_backgrounded(value: bool) -> void:
		transitions.append(value)
		super.set_backgrounded(value)
	func play_reunion() -> void:
		greetings+=1
		super.play_reunion()

var checks := 0
var failures := 0
var app: Node
var sound: SoundProbe

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var path := "user://audio-integration-"+Crypto.new().generate_random_bytes(8).hex_encode()+".json"
	app=Main.new()
	app.saves=Storage.new(path)
	app.saves.data.settings.sound=false
	app.saves.data.settings.haptics=true
	# A save from a launch after the one-time settings change (LocalSave.settle_settings), so startup writes nothing.
	app.saves.data[Storage.SETTINGS_MIGRATION_KEY]=Storage.SETTINGS_MIGRATION
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
	_test_home_reunion()
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

func _test_home_reunion() -> void:
	var stage: Control
	for child: Node in app.overlay.get_children():
		if child is HomeStage: stage=child
	_check(stage!=null,"Home reunion test uses the real home movement owner")
	if stage==null: return
	stage.set_process(false)
	for actor: Node3D in app.world.actors.values(): actor.reset_motion()
	for role: String in stage._rests: stage._rests[role]=1000.0
	var before := sound.greetings
	var notes: Array[float] = []
	for encounter in range(3):
		ReunionAudio.place_pair(app.world,3.0)
		stage._process(1.0/60.0)
		ReunionAudio.place_pair(app.world,1.0)
		stage._process(1.0/60.0)
		_check(sound.greetings==before+encounter+1 and sound.reunion_voice.playing,"Home plays one shared greeting per repeated reunion")
		notes.append(12.0*log(sound.reunion_voice.pitch_scale)/log(2.0))
	var varied := true
	for i in range(notes.size()):
		varied = varied and notes[i] >= sound.REUNION_RANGE.x - 0.0001 and notes[i] <= sound.REUNION_RANGE.y + 0.0001
		if i > 0: varied = varied and absf(notes[i] - notes[i-1]) >= sound.REUNION_MIN_MOVE - 0.0001
	_check(varied,"Repeated Home reunions slide to a new pitch in range each time instead of repeating one")
	for frame in range(90): stage._process(1.0/60.0)
	_check(sound.greetings==before+3,"Home standing together does not repeat the greeting")
	stage.set_process(true)
	sound.stop_reunion()

func _test_background() -> void:
	sound.transitions.clear()
	app._notification(Main.NOTIFICATION_APPLICATION_PAUSED)
	app._notification(Main.NOTIFICATION_APPLICATION_PAUSED)
	_check(sound.transitions==[true] and sound.backgrounded and not sound.ambience.playing,"Background notification silences audio once")
	app._notification(Main.NOTIFICATION_APPLICATION_RESUMED)
	app._notification(Main.NOTIFICATION_APPLICATION_RESUMED)
	_check(sound.transitions==[true,false] and sound.ambience.playing,"Resume restores ambience once")
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
