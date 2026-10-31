extends "res://tests/test_audio_integration.gd"
## A full-screen child that covered Home's sound when it opened (a Together
## replay, Photo transfer) keeps it covered after the app is paused and resumed;
## only Home itself, with no such child, plays its ambience again. A covered
## Home still plays a button's tick (a fixed cue).

func _run() -> void:
	var path := "user://resume-child-sound-"+Crypto.new().generate_random_bytes(8).hex_encode()+".json"
	app=Main.new()
	app.saves=Storage.new(path)
	app.saves.data.settings.sound=true
	app.saves.data.settings.haptics=false
	app.saves.flush()
	sound=SoundProbe.new()
	app.soundscape=sound
	root.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	await process_frame
	for child: String in ["shared_replay_child","photo_transfer_child"]:
		var screen: Node = Node3D.new() if child == "shared_replay_child" else Node.new()
		app.add_child(screen)
		app.set(child,screen)
		app.soundscape.set_covered(true)
		app._notification(Main.NOTIFICATION_APPLICATION_PAUSED)
		app._notification(Main.NOTIFICATION_APPLICATION_RESUMED)
		_check(sound.covered and not sound.backgrounded and not sound.ambience.playing,"Home's ambience stays off under %s after a pause and resume" % child)
		# One tick per frame: each child gets its own frame.
		await process_frame
		var played: int = sound.next_voice
		sound.play_fixed_cue("ui_tap")
		_check(sound.next_voice != played,"A button on %s still ticks on covered Home" % child)
		app.set(child,null)
		screen.queue_free()
		app.soundscape.set_covered(false)
	app._notification(Main.NOTIFICATION_APPLICATION_PAUSED)
	app._notification(Main.NOTIFICATION_APPLICATION_RESUMED)
	_check(not sound.backgrounded and not sound.covered and sound.ambience.playing,"Home plays its ambience again after a pause and resume")
	sound.set_backgrounded(true)
	app.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	for suffix: String in ["",".tmp",".backup"]:
		if FileAccess.file_exists(path+suffix): DirAccess.remove_absolute(path+suffix)
	print("RESUME CHILD SOUND: %d checks, %d failures" % [checks,failures])
	quit(1 if failures>0 else 0)
