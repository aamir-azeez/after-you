extends RefCounted
## Exercise the actual world -> controller -> audio path without changing a turn.

static func chapter(app: Node) -> Array[String]:
	var errors: Array[String] = []
	var world: Node3D = app.world
	var sound: Node = app.soundscape
	var before := JSON.stringify(app.sim.snapshot())
	var greetings := [0]
	var count := func(): greetings[0]+=1
	world.reunion.connect(count)
	world.set_process(false)
	sound.configure({"sound": true, "haptics": false})
	world.reduced_motion=false
	for actor: Node3D in world.actors.values(): actor.reset_motion()
	approach(world)
	if sound.reunion_voice.playing: errors.append("Ready screen played an unsolicited greeting")
	for playback: String in ["play", "replay"]:
		app.mode=playback
		app.running=true
		for encounter in range(3):
			var previous: int=greetings[0]
			approach(world)
			if greetings[0]!=previous+1 or not sound.reunion_voice.playing:
				errors.append("Pair did not play exactly one greeting in %s encounter %d" % [playback,encounter])
			for frame in range(45): world._process(1.0/60.0)
			if greetings[0]!=previous+1: errors.append("Standing together repeated the greeting")
	app._pause()
	if sound.reunion_voice.playing: errors.append("Pause did not stop the greeting")
	approach(world)
	if sound.reunion_voice.playing: errors.append("Paused chapter played a greeting")
	app.mode="replay"
	app.running=true
	sound.configure({"sound": false, "haptics": false})
	approach(world)
	if sound.reunion_voice.playing: errors.append("Muted chapter played a greeting")
	sound.configure({"sound": true, "haptics": false})
	sound.set_backgrounded(true)
	approach(world)
	if sound.reunion_voice.playing: errors.append("Background chapter played a greeting")
	sound.set_backgrounded(false)
	world.reduced_motion=true
	var previous: int=greetings[0]
	approach(world)
	if greetings[0]!=previous or sound.reunion_voice.playing: errors.append("Reduced Motion triggered a reunion")
	if JSON.stringify(app.sim.snapshot())!=before: errors.append("Greeting changed simulation state")
	world.reunion.disconnect(count)
	sound.stop_reunion()
	sound.configure(app.settings)
	world.reduced_motion=bool(app.settings.get("reduced_motion",false))
	app._show_ready()
	world.set_process(true)
	return errors

static func approach(world: Node3D) -> void:
	place_pair(world,3.0)
	world._process(1.0/60.0)
	place_pair(world,1.0)
	world._process(1.0/60.0)

static func place_pair(world: Node3D, distance: float) -> void:
	var slots: Array=world.actors.keys()
	for index in range(slots.size()):
		var point := Vector3(float(index)*distance,0,0)
		world.actors[slots[index]].position=point
		world.actor_targets[slots[index]]=point
