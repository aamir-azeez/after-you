extends SceneTree
## Ending scenes: every scene file is valid and every descriptor's "ending"
## names one; the timeline is a function of time alone, so a scene plays the
## same at any frame rate, fires each cue once in the same order, and a skip
## lands where playing through does; the first viewing cannot be skipped and
## later ones can; the cast follows the pipsport's holder; and the world gets
## its frame, camera and processing back with nothing of the scene left in it.
## The "back" and "bounce" eases start at 0 and end at 1 (back runs past it,
## bounce never does), and a Blender model prop (shape "model") checks, builds
## as its painted part at its scale, fades and moves like any prop. Letterbox
## bars slide in and out, a tint washes the screen, the camera circles its
## point and stays turned, and bad bars or tints are refused. A tracking
## camera follows a moving pip and hands on without a jump, a frame fits both
## pips on a narrow and a wide screen, a shake sways the view only while it
## runs and never with Reduce motion or Haptics off, and bad camera and shake
## steps are refused.
const EndingScene = preload("res://services/ending_scene.gd")
const EndingSeen = preload("res://services/ending_seen.gd")
const EndingPlayer = preload("res://presentation/ending_player.gd")
const EndingFlow = preload("res://presentation/ending_flow.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Index = preload("res://content/chapters/index.gd")
const Simulation = preload("res://core/journey/simulation.gd")
const Catalog = preload("res://core/journey/stage_catalog.gd")
const ViewFit = preload("res://presentation/kit/view_fit.gd")
const BigChange = preload("res://presentation/kit/big_change.gd")
const Backdrop = preload("res://presentation/kit/space_backdrop.gd")
const KEY := "turn-of-the-tide@3"
const SCENES := ["the_falls", "fog_marsh"]
## Frame patterns a scene is played with: 30 and 60 a second, and uneven ones.
const PATTERNS := [[1.0 / 30.0], [1.0 / 60.0], [0.011, 0.047, 0.023, 0.1, 0.004, 0.033]]

var checks := 0
var failures := 0
var directory := ""

class Host extends Node:
	var chapter := {}
	var chapter_key := "the-falls@1"
	var world: Node3D
	var sim: RefCounted
	var overlay := Control.new()
	var hud := Control.new()
	var soundscape: Node = null
	var settings := {"reduced_motion": false}
	var controls: Node = null
	var mode := "complete"
	var hard := false
	func _hard_on() -> bool: return hard

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	directory = "user://ending-scenes-%s" % Crypto.new().generate_random_bytes(8).hex_encode()
	DirAccess.make_dir_recursive_absolute(directory)
	_files()
	_descriptors()
	_timeline()
	_cast()
	var setup := _world()
	for name: String in SCENES:
		_frame_rates(setup, name)
		_skips(setup, name)
	_handover(setup)
	_kit(setup)
	_screen(setup)
	_camera(setup)
	_long_frame(setup)
	await _flow(setup)
	_seen_store()
	setup.world.free()
	for filename: String in DirAccess.get_files_at(directory): DirAccess.remove_absolute(directory.path_join(filename))
	DirAccess.remove_absolute(directory)
	print("ENDING SCENES: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

static func _data(name: String) -> Dictionary:
	return load("res://content/endings/%s.gd" % name).DATA

## Every file in content/endings is a valid scene, and both chapters' are there.
func _files() -> void:
	var found: Array = []
	for filename: String in DirAccess.get_files_at("res://content/endings"):
		if not filename.ends_with(".gd"): continue
		found.append(filename.get_basename())
		var problem := EndingScene.check(load("res://content/endings/" + filename).DATA)
		_check(problem.is_empty(), "The ending %s is a valid scene: %s" % [filename, problem])
	for name: String in SCENES: _check(name in found, "The %s ending exists" % name)
	_check(not EndingScene.check({"cast": {"fallback": "p0"}, "steps": [{"do": "sound", "cue": "spirit_drowned"}]}).is_empty(), "A scene plays fixed cues only, never a turn's")
	_check(not EndingScene.check({"cast": {"fallback": "p0"}, "steps": [{"do": "pose", "who": "carrier", "face": "nope"}]}).is_empty(), "A scene's faces are the pips' own")

## A descriptor's "ending" names a valid scene file.
func _descriptors() -> void:
	for key: String in Index.keys():
		var name := str(Index.data(key).get("ending", ""))
		if name.is_empty(): continue
		var path := "res://content/endings/%s.gd" % name
		_check(ResourceLoader.exists(path) and EndingScene.check(load(path).DATA).is_empty(), "%s's ending %s is a valid scene" % [key, name])

## state() is a function of t alone; the events between two times are each fired once.
func _timeline() -> void:
	for name: String in SCENES:
		var compiled := EndingScene.compile(_data(name), _start_at())
		var duration := float(compiled.duration)
		_check(duration > 5.0 and duration < EndingScene.LONGEST, "%s lasts a short scene: %.1f s" % [name, duration])
		for pattern: Array in PATTERNS:
			var fired: Array = []
			var t := 0.0
			var before := -1.0
			var index := 0
			while t < duration:
				t = minf(duration, t + float(pattern[index % pattern.size()]))
				index += 1
				fired.append_array(EndingScene.events_between(compiled, before, t))
				before = t
			_check(fired == compiled.events, "%s fires every event once, in order, at %s" % [name, pattern])
		_check(EndingScene.state(compiled, duration * 0.37) == EndingScene.state(EndingScene.compile(_data(name), _start_at()), duration * 0.37), "%s's state is the same each time it is worked out" % name)

func _start_at() -> Dictionary:
	return {"carrier": Vector3(1, 0, 0), "other": Vector3(-1, 0, 0.5), "origin": Vector3(0, 0, 0.25), "camera": Vector3.ZERO, "camera_size": 12.0}

## The carrier is the pipsport's holder in the final snapshot, else the fallback.
func _cast() -> void:
	var data := _data("the_falls")
	_check(EndingScene.cast(data, {"players": {"p0": {"carrying": ""}, "p1": {"carrying": "pipsport"}}}) == {"carrier": "p1", "other": "p0"}, "Teal carrying the pipsport is the one who slips")
	_check(EndingScene.cast(data, {"players": {"p0": {"carrying": "pipsport"}, "p1": {"carrying": ""}}}) == {"carrier": "p0", "other": "p1"}, "Gold carrying it is the one who slips")
	_check(EndingScene.cast(data, {}) == {"carrier": "p0", "other": "p1"}, "With no pipsport held, the fallback slot carries")

func _world() -> Dictionary:
	var level := Registry.definition(KEY)
	var world: Node3D = Registry.world_script(KEY).new()
	root.add_child(world)
	world.reduced_motion = true
	world.load_level(level)
	var stage: Dictionary = level.stages[0]
	world.show_stage(stage)
	var checkpoint := Catalog.initial_checkpoint(level)
	world.present_history(checkpoint)
	var sim := Simulation.new()
	_check(sim.reset(level, str(stage.id), checkpoint), "Tide's first stage starts for the scene's world")
	world.present(sim.snapshot(), true)
	world.set_process(true)
	return {"world": world, "sim": sim}

func _player(setup: Dictionary, data: Dictionary, skippable: bool) -> Node:
	var player: Node = EndingPlayer.new()
	player.skippable = skippable
	root.add_child(player)
	player.set_process(false)
	_check(player.start(setup.world, data, setup.sim.snapshot()), "The scene starts in Tide's world")
	return player

func _done(setup: Dictionary, player: Node) -> void:
	player.free()
	_check(setup.world.is_processing() and not setup.world.camera_exploration.manual, "A scene freed mid-play still hands the world back")
	setup.world.present(setup.sim.snapshot(), true)

## At every frame rate the pips stand where state(t) puts them, and they end
## in the same places.
func _frame_rates(setup: Dictionary, name: String) -> void:
	var data := _data(name)
	var ends: Array = []
	for pattern: Array in PATTERNS:
		var player := _player(setup, data, false)
		var exact := true
		var index := 0
		while player.playing:
			player.advance(float(pattern[index % pattern.size()]))
			index += 1
			if not player.playing: break
			var now := EndingScene.state(player.compiled, player.t)
			for role: String in EndingScene.ROLES:
				var actor: Node3D = setup.world.actors[player.slots[role]]
				if not setup.world.to_local(actor.global_position).is_equal_approx(now.actors[role].position): exact = false
		_check(exact, "%s puts the pips where the timeline says on every frame at %s" % [name, pattern])
		ends.append(_end_places(player))
		_done(setup, player)
	_check(ends[0] == ends[1] and ends[1] == ends[2], "%s ends the same at 30, 60 and uneven frame rates" % name)

func _end_places(player: Node) -> Array:
	var now := EndingScene.state(player.compiled, player.duration())
	return [now.actors.carrier.position.snapped(Vector3.ONE * 0.0001), now.actors.other.position.snapped(Vector3.ONE * 0.0001), now.camera.center.snapped(Vector3.ONE * 0.0001)]

## A long frame moves a scene on by at most a tenth of a second.
func _long_frame(setup: Dictionary) -> void:
	var player := _player(setup, _data("fog_marsh"), false)
	player.set_process(true)
	player._process(30.0)
	_check(player.playing and is_equal_approx(player.t, EndingPlayer.LONGEST_FRAME), "A hitch never jumps a must-watch scene to its end")
	_done(setup, player)

## A must-watch scene refuses a skip and holds taps; a seen one skips to the
## very end it would have played to.
func _skips(setup: Dictionary, name: String) -> void:
	var data := _data(name)
	var player := _player(setup, data, false)
	var results: Array = []
	player.finished.connect(func(watched: bool) -> void: results.append(watched))
	player.advance(0.5)
	_check(not player.skip() and player.playing, "%s cannot be skipped the first time" % name)
	var tap := InputEventMouseButton.new()
	tap.pressed = true
	player._tapped(tap)
	_check(player.playing and results.is_empty(), "A tap does not end a must-watch %s" % name)
	_done(setup, player)
	player = _player(setup, data, true)
	player.finished.connect(func(watched: bool) -> void: results.append(watched))
	player.advance(0.5)
	_check(player.skip() and not player.playing and results == [true], "A seen %s skips, and counts as watched" % name)
	var skipped := {}
	for role: String in EndingScene.ROLES: skipped[role] = setup.world.to_local(setup.world.actors[player.slots[role]].global_position)
	var end := EndingScene.state(player.compiled, player.duration())
	_check(skipped.carrier.is_equal_approx(end.actors.carrier.position) and skipped.other.is_equal_approx(end.actors.other.position), "A skipped %s ends where it plays to" % name)
	_done(setup, player)

## The world's own frame, camera, pan and zoom come back; the props go.
func _handover(setup: Dictionary) -> void:
	var world: Node3D = setup.world
	var camera: Camera3D = world.camera
	var transform := camera.transform
	var size := camera.size
	var player := _player(setup, _data("the_falls"), true)
	_check(not world.is_processing() and world.camera_exploration.manual, "The scene holds the world's frame and its pan and zoom")
	_check(player._badges.is_empty() or player._badges.all(func(badge: Node3D) -> bool: return not badge.visible), "The pips' role badges are hidden while the scene plays")
	_check(world.get_node_or_null("EndingScene") != null and world.get_node("EndingScene").get_child_count() == _data("the_falls").props.size(), "The scene builds its placeholder props when it starts")
	player.advance(3.0)
	_check(not camera.transform.is_equal_approx(transform), "The scene moves the world's camera")
	player.stop()
	_check(world.is_processing() and not world.camera_exploration.manual, "The world gets its frame back")
	_check(player._badges.is_empty(), "The role badges come back")
	_check(camera.transform.is_equal_approx(transform) and is_equal_approx(camera.size, size), "The world gets its camera back")
	player.free()
	_check(world.get_node_or_null("EndingScene") == null or world.get_node("EndingScene").is_queued_for_deletion(), "Nothing of the scene stays in the world")

## The flow: a first viewing is a must-watch and is marked seen only when it
## ends; then it skips. Hard runs and chapters without an ending play none.
func _flow(setup: Dictionary) -> void:
	var host := Host.new()
	host.chapter = {"ending": "the_falls"}
	host.world = setup.world
	host.sim = setup.sim
	host.add_child(host.overlay)
	host.add_child(host.hud)
	root.add_child(host)
	var flow: RefCounted = EndingFlow.new(host)
	flow.seen = EndingSeen.new(directory.path_join("seen.json"))
	var calls: Array = []
	_check(flow.offered(), "A chapter with an ending offers it on its card")
	_check(flow.play_once(func() -> void: calls.append("card")), "A finished chapter plays its ending")
	_check(host.mode == EndingFlow.MODE and not flow._player.skippable, "The first viewing is a must-watch")
	_check(flow.back() and calls == ["card"] and host.mode == "complete" and not flow.seen.seen("the-falls"), "Back ends it at once and shows the card, still unseen")
	await process_frame
	_check(not flow.play_once(func() -> void: calls.append("card")) and calls == ["card"], "A card drawn again does not start the ending by itself again")
	_check(flow.play(func() -> void: calls.append("card")), "The ending plays again from the card")
	while flow.playing(): flow._player.advance(0.25)
	_check(calls == ["card", "card"] and flow.seen.seen("the-falls"), "Watched to the end, it is seen")
	await process_frame
	_check(flow.play(func() -> void: pass) and flow._player.skippable, "A seen ending can be skipped")
	flow._player.skip()
	await process_frame
	host.hard = true
	_check(not flow.offered() and not flow.play(func() -> void: pass), "A hard run plays no ending")
	host.hard = false
	host.chapter = {}
	_check(not flow.offered() and not flow.play(func() -> void: pass), "A chapter without an ending plays none")
	host.free()

func _seen_store() -> void:
	var path := directory.path_join("store.json")
	var store := EndingSeen.new(path)
	_check(store.levels().is_empty(), "No file: nothing seen")
	_check(store.mark("fog-marsh") and store.mark("fog-marsh") and store.levels() == ["fog-marsh"], "A level is kept once")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("not json")
	file.close()
	_check(EndingSeen.new(path).levels().is_empty(), "A broken file reads as nothing seen")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("FAIL: " + message)

## The motion kit's eases and Blender model props (tests/fixtures/models).
func _kit(setup: Dictionary) -> void:
	for ease: String in ["back", "bounce"]:
		_check(absf(EndingScene._eased(ease, 0.0)) < 0.0001 and absf(EndingScene._eased(ease, 1.0) - 1.0) < 0.0001, "%s starts at 0 and ends at 1" % ease)
	var most := 0.0
	var low := 1.0
	var high := 0.0
	for step in range(101):
		most = maxf(most, EndingScene._eased("back", step / 100.0))
		low = minf(low, EndingScene._eased("bounce", step / 100.0))
		high = maxf(high, EndingScene._eased("bounce", step / 100.0))
	_check(most > 1.05, "back runs past the end before it settles: %.3f" % most)
	_check(low >= 0.0 and high <= 1.0001, "bounce stays between start and end")
	var data := {"cast": {"fallback": "p0"},
		"props": {"wheel": {"shape": "model", "model": "res://tests/fixtures/models/kit_sample.glb", "part": "sample_rim",
			"colors": {"wood": "8a6b4e", "metal": "4f5458"}, "at": [0, 1, 0], "scale": 2.0, "alpha": 0.5}},
		"steps": [{"do": "prop", "id": "wheel", "to": [1, 1, 0], "time": 1.0, "ease": "back", "spin": 90}, {"do": "wait", "time": 1.2}]}
	_check(EndingScene.check(data).is_empty(), "a model prop scene checks: %s" % EndingScene.check(data))
	var broken := data.duplicate(true)
	broken.props.wheel.model = "res://tests/fixtures/models/missing.glb"
	_check(not EndingScene.check(broken).is_empty(), "a model prop with no model file is refused")
	var player := _player(setup, data, true)
	var wheel: Variant = player._props.get("wheel")
	_check(wheel is MeshInstance3D and (wheel as MeshInstance3D).mesh != null, "the model prop is built as its painted part")
	if wheel is MeshInstance3D:
		_check((wheel as MeshInstance3D).scale.is_equal_approx(Vector3.ONE * 2.0), "the model prop stands at its scale")
		_check(((wheel as MeshInstance3D).material_override as StandardMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_ALPHA, "a fading model prop gets its own see-through look")
		var start: Vector3 = (wheel as MeshInstance3D).position
		player.advance(1.0)
		var placed: Vector3 = EndingScene.prop_position(player.compiled, "wheel", player.t)
		_check((wheel as MeshInstance3D).position.distance_to(placed) < 0.01 and placed.distance_to(start) > 0.9, "the model prop moves like any prop")
	_done(setup, player)

## A tracking camera, a framed one and a shake.
func _camera(setup: Dictionary) -> void:
	var tracking := {"cast": {"fallback": "p0"}, "steps": [
		{"do": "camera", "who": "carrier", "track": true, "size": 6.0, "time": 0.5}, {"do": "move", "who": "carrier", "to": [4, 0, 0], "time": 2.0},
		{"do": "wait", "time": 2.0}, {"do": "camera", "at": [0, 0, 0], "size": 6.0, "time": 1.0}, {"do": "wait", "time": 1.0}]}
	_check(EndingScene.check(tracking).is_empty(), "a tracking camera checks: %s" % EndingScene.check(tracking))
	var tracked := EndingScene.compile(tracking, _start_at())
	var mid := EndingScene.state(tracked, 1.2)
	_check(mid.camera.center.is_equal_approx(EndingScene.position_of(tracked, "carrier", 1.2)) and mid.camera.center.distance_to(_start_at().carrier) > 0.5, "a tracking camera follows its pip as it moves")
	var handed: Vector3 = EndingScene.state(tracked, 2.0).camera.center
	_check(handed.is_equal_approx(EndingScene.position_of(tracked, "carrier", 2.0)) and EndingScene.state(tracked, 2.001).camera.center.distance_to(handed) < 0.01, "the next camera step starts where the track left off")
	var aimed := tracking.duplicate(true)
	aimed.steps[0].erase("track")
	_check(EndingScene.state(EndingScene.compile(aimed, _start_at()), 1.2).camera.center.is_equal_approx(_start_at().carrier), "without track the camera stays where the pip stood")
	var framing := {"cast": {"fallback": "p0"}, "steps": [{"do": "camera", "frame": ["carrier", "other"], "margin": 0.5, "time": 1.0}, {"do": "wait", "time": 1.0}]}
	_check(EndingScene.check(framing).is_empty(), "a framing camera checks: %s" % EndingScene.check(framing))
	var apart := _start_at()
	apart.carrier = Vector3(6, 0, 0)
	apart.other = Vector3(-6, 0, 2)
	var axes := EndingScene.view_axes(0.0)
	for aspect: float in [4.0 / 3.0, 20.0 / 9.0]:
		apart.aspect = aspect
		var framed := EndingScene.compile(framing, apart)
		var end := EndingScene.state(framed, float(framed.duration))
		var high := ViewFit.fit(float(end.camera.size), aspect) * 0.5
		var wide := high * aspect
		var inside := true
		var most := Vector2.ZERO
		for role: String in EndingScene.ROLES:
			for lift: float in [0.0, EndingScene.FOLLOW_LIFT]:
				var away: Vector3 = apart[role] + Vector3.UP * lift - end.camera.center
				var flat := Vector2(absf(axes.x.dot(away)), absf(axes.y.dot(away)))
				most = Vector2(maxf(most.x, flat.x), maxf(most.y, flat.y))
				if flat.x > wide - 0.5 + 0.001 or flat.y > high - 0.5 + 0.001: inside = false
		_check(inside, "a frame keeps both pips and its margin on screen at %.2f" % aspect)
		_check(absf(most.x - (wide - 0.5)) < 0.001 or absf(most.y - (high - 0.5)) < 0.001, "a frame is snug on its tighter side at %.2f" % aspect)
	var shaking := {"cast": {"fallback": "p0"}, "steps": [{"do": "shake", "amount": 2.0, "for": 0.6}]}
	_check(EndingScene.check(shaking).is_empty(), "a shake checks: %s" % EndingScene.check(shaking))
	var shook := EndingScene.compile(shaking, _start_at())
	_check(is_equal_approx(float(shook.duration), 0.6), "a scene lasts until its shake ends")
	_check(EndingScene.state(shook, 0.3).camera.shake != Vector2.ZERO and EndingScene.state(shook, 0.6).camera.shake == Vector2.ZERO, "a shake sways while it runs and is gone when its time ends")
	_check(EndingScene.state(shook, 0.3).camera.shake.is_equal_approx(BigChange.offset(0.3, 0.6) * 2.0), "a shake is the big change's, times its amount")
	shaking.steps.append({"do": "wait", "time": 1.0})
	var camera: Camera3D = setup.world.camera
	# The world's frame is paused, yet the space behind it follows the scene's camera.
	var sky: ShaderMaterial = setup.world.environment.sky.sky_material
	var follow := _player(setup, tracking, true)
	var opening: Vector2 = sky.get_shader_parameter(Backdrop.PARALLAX)
	follow.advance(1.2)
	var followed: Vector2 = sky.get_shader_parameter(Backdrop.PARALLAX)
	_check(followed.is_equal_approx(Backdrop.pan_shift(camera)) and not followed.is_equal_approx(opening), "the space backdrop moves with an ending's camera")
	_done(setup, follow)
	var places: Array = []
	for setting: Array in [[false, true, [0.3]], [false, true, [0.1, 0.1, 0.1]], [true, true, [0.3]], [false, false, [0.3]], [false, true, [0.3, 0.4]]]:
		setup.world.big_change_shake = setting[1]
		var player := _player(setup, shaking, true)
		player.reduced_motion = setting[0]
		for step: float in setting[2]: player.advance(step)
		var now := EndingScene.state(player.compiled, player.t)
		places.append(camera.position.distance_to(now.camera.center + ViewFit.CAMERA_FROM))
		_done(setup, player)
	setup.world.big_change_shake = true
	_check(places[0] > 0.001 and absf(places[0] - places[1]) < 0.0001, "a shake sways the view the same at any frame rate")
	_check(places[2] < 0.0001 and places[3] < 0.0001, "Reduce motion or Haptics off keeps the view still")
	_check(places[4] < 0.0001, "the view is still once the shake ends")
	for bad: Dictionary in [{"do": "camera", "track": true, "size": 5.0}, {"do": "camera", "frame": []}, {"do": "camera", "frame": ["nobody"]}, {"do": "camera", "frame": [[1, 2]]},
			{"do": "camera", "frame": ["carrier"], "margin": -1.0}, {"do": "camera", "frame": ["carrier"], "who": "other"}, {"do": "shake", "amount": 0.0, "for": 0.5},
			{"do": "shake", "for": 0.0}, {"do": "shake", "for": 5.0}]:
		_check(not EndingScene.check({"cast": {"fallback": "p0"}, "steps": [bad, {"do": "wait", "time": 1.0}]}).is_empty(), "a bad step is refused: %s" % bad)

## Letterbox bars, a colour wash and a slow camera circle.
func _screen(setup: Dictionary) -> void:
	var data := {"cast": {"fallback": "p0"}, "steps": [
		{"do": "bars", "show": true, "time": 0.5}, {"do": "tint", "color": "ffcc88", "alpha": 0.4, "time": 0.5},
		{"do": "camera", "at": [0, 0, 0], "size": 8.0, "time": 1.0, "orbit": 30}, {"do": "wait", "time": 1.0},
		{"do": "bars", "show": false, "time": 0.5}, {"do": "tint", "color": "000000", "alpha": 1.0, "time": 0.5}, {"do": "wait", "time": 0.5}]}
	_check(EndingScene.check(data).is_empty(), "a scene with bars, a tint and an orbit checks: %s" % EndingScene.check(data))
	var compiled := EndingScene.compile(data, _start_at())
	var mid := EndingScene.state(compiled, 0.25)
	var held := EndingScene.state(compiled, 0.9)
	var end := EndingScene.state(compiled, float(compiled.duration))
	_check(float(mid.screen.bars) > 0.1 and float(mid.screen.bars) < 0.9 and is_equal_approx(float(held.screen.bars), 1.0) and is_equal_approx(float(end.screen.bars), 0.0), "the bars slide in, stay, then slide out")
	_check(is_equal_approx(float(held.screen.tint_alpha), 0.4) and held.screen.tint == Color("ffcc88") and is_equal_approx(float(end.screen.tint_alpha), 1.0) and end.screen.tint == Color.BLACK, "the tint washes warm, then fades to black")
	_check(float(held.camera.orbit) > 25.0 and is_equal_approx(float(end.camera.orbit), 30.0) and float(mid.camera.orbit) > 0.0, "the camera circles 30 degrees and stays turned")
	var homing := {"cast": {"fallback": "p0"}, "steps": [{"do": "camera", "at": [1, 0, 1], "size": 4.0, "time": 1.0, "orbit": 40}, {"do": "wait", "time": 1.0}, {"do": "camera", "home": true, "time": 1.0}, {"do": "wait", "time": 1.0}]}
	_check(EndingScene.check(homing).is_empty(), "a camera going home checks: %s" % EndingScene.check(homing))
	var homed := EndingScene.compile(homing, _start_at())
	var back := EndingScene.state(homed, float(homed.duration))
	var away := EndingScene.state(homed, 1.0)
	_check(back.camera.center == _start_at().camera and is_equal_approx(float(back.camera.size), float(_start_at().camera_size)) and is_equal_approx(float(back.camera.orbit), 0.0), "the camera glides home: the game's own view, unturned")
	_check(float(away.camera.orbit) > 30.0 and float(away.camera.size) < 5.0, "it was away before it went home")
	for bad: Dictionary in [{"do": "bars", "time": 0.5}, {"do": "tint", "color": "nope", "alpha": 0.5}, {"do": "tint", "color": "ffffff", "alpha": 2.0}]:
		_check(not EndingScene.check({"cast": {"fallback": "p0"}, "steps": [bad, {"do": "wait", "time": 1.0}]}).is_empty(), "a bad %s step is refused" % bad.do)
	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(overlay)
	var player: Node = EndingPlayer.new()
	player.skippable = true
	root.add_child(player)
	player.set_process(false)
	_check(player.start(setup.world, data, setup.sim.snapshot(), overlay), "the screen scene starts")
	player.advance(1.0)
	var top: ColorRect = player._bars[0]
	_check(top.visible and is_equal_approx(top.anchor_bottom, player.BAR_SHARE), "the top bar covers its share of the screen")
	_check(player._tint.visible and is_equal_approx(player._tint.color.a, 0.4), "the wash is drawn at its alpha")
	_done(setup, player)
	overlay.free()
