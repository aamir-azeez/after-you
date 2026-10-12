extends SceneTree
## Turn of the Tide world, built from the chapter's own catalog:
## decks and markers stand at their heights, the three waters follow the
## snapshot without changing it, the wheels show three and four values, the
## camera reaches the whole harbour, the dressing passes the scenery lint, and
## every mesh has its geometry and material.
const TideCatalog = preload("res://core/journey/turn_of_the_tide_catalog.gd")
const KEY := "turn-of-the-tide@1"
const JourneyCatalog = preload("res://core/journey/stage_catalog.gd")
const Simulation = preload("res://core/journey/simulation.gd")
const CooperativeCatalog = preload("res://core/cooperative/stage_catalog.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const World = preload("res://presentation/tide_world.gd")
const Dressing = preload("res://content/dressing/catalog.gd")
const Props = preload("res://presentation/kit/props.gd")
const Lint = preload("res://tests/test_dressing_lint.gd")
const Soundscape = preload("res://services/soundscape.gd")
const SoundMap = preload("res://services/chapter_sound_map.gd")
const Registry = preload("res://services/chapter_registry.gd")
const KeepsakeVisual = preload("res://presentation/keepsake_visual.gd")
const STAIRS := ["w-steps-low", "w-steps-high", "mill-steps", "mill-ladder", "east-steps", "boathouse-steps", "rock-steps-low", "rock-steps-high"]
var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var level := TideCatalog.definition()
	var digest := Canonical.digest(level)
	await _first_stage(level)
	await _second_stage(level)
	_dressing(level)
	_keepsakes()
	_sound(level)
	var scene: PackedScene = load("res://turn_of_the_tide.tscn")
	var state := scene.get_state()
	var key := ""
	for index in range(state.get_node_property_count(0)):
		if state.get_node_property_name(0, index) == "chapter_key": key = str(state.get_node_property_value(0, index))
	_check(key == KEY, "The chapter scene opens Turn of the Tide on the shared chapter screen")
	_check(Canonical.digest(level) == digest, "Building and presenting the world never changes the definition")
	print("TIDE WORLD: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _first_stage(level: Dictionary) -> void:
	var checkpoint := JourneyCatalog.initial_checkpoint(level)
	var sim := _sim(level, "set-the-tide", checkpoint)
	var world := _world(level, 0, checkpoint)
	var state: Dictionary = sim.snapshot()
	world.present(state, true)
	for island: Dictionary in level.islands:
		_check(is_equal_approx(world._surface_nodes[island.id].position.y, float(island.height_cm) / 100.0), "Island deck stands at its height: " + str(island.id))
	for route: Dictionary in level.bridges:
		_check(world._decks.has(route.id) and is_equal_approx(world._decks[route.id].position.y, float(route.height_cm) / 100.0), "Crossing deck stands at its height, not on the ground: " + str(route.id))
	for pad: Dictionary in level.stages[0].pressure_pads:
		_check(absf(world._physical_pads[pad.id].global_position.y - 1.025) < 0.01, "A waiting-step pad sits on its raised step: " + str(pad.id))
	_check(world._weights.keys() == ["lock-west", "lock-east"] and absf(world._weights["lock-west"].get_meta("rest_y") - 0.93) < 0.01, "Only the lock gates keep a pulley, lifted to the terrace")
	for route: Dictionary in level.bridges:
		if route.to_surface != route.id: continue
		var frame: Node3D = world.terrain.find_child("StubFrame_" + str(route.id), false, false)
		_check(frame != null and absf(frame.get_child(0).position.y - float(route.height_cm) / 100.0 + 0.07) < 0.01, "A stub keeps its frame in view while its boards are up: " + str(route.id))
	_check(world._gauges.size() == 11, "Eleven tide crossings carry a gauge instead of eleven cables")
	for id: String in world._gauges:
		var gate := _gate(level.stages[0], id)
		var value: String = gate.when.value if gate.when.has("value") else ""
		for child: Dictionary in gate.when.get("all", []):
			if child.get("control_id", "") == "tide": value = child.value
		_check(world._gauges[id].bands.size() == ["low", "half", "high"].find(value) + 1, "A gauge's bands count its tide: " + id)
	_check(_crests(world, "").size() > 0 and _crests(world, "tide").is_empty(), "Crests mark the other machines but never the tide")
	# Wheels: the tide wheel shows three values; the winch and lock stay two-way.
	_check(world._wheels.keys() == ["tide"], "Only the three-way tide wheel gets a hand wheel in the first stage")
	var labels: Array = world._journey_switches["tide"].labels
	_check(absf(labels[1].position.x - labels[0].position.x - 0.80) < 0.001 and labels.size() == 3, "Tide labels sit 0.8 m apart")
	var angles: Array = []
	var levels: Dictionary = {}
	for value: String in ["low", "half", "high"]:
		sim._mechanisms.controls.tide = value
		sim._refresh_routes()
		var current: Dictionary = sim.snapshot()
		var frozen := Canonical.digest(current)
		world.present(current, true)
		_check(Canonical.digest(current) == frozen, "Presenting leaves the snapshot unchanged at " + value)
		angles.append(world._wheels.tide.wheel.rotation.z)
		_check(world._wheels.tide.wheel.get_meta("value") == value, "The tide wheel's pointer shows " + value)
		levels[value] = world._water.harbour.position.y
		_check(is_equal_approx(world._water.harbour.position.y, World.HARBOUR_LEVELS[value]), "Harbour water stands at the " + value + " level")
		for id: String in world._gauges:
			_check(world._gauges[id].post.get_meta("lit") == (value in world._gauges[id].values), "Gauge lights only for its own tide: %s at %s" % [id, value])
	_check(levels.low < 0.0 and levels.half > 0.0 and levels.half < 0.48 and levels.high > 0.48 and levels.high < 0.96, "Low is below the beaches, half below the terraces, high below the quays")
	_check(angles[0] > angles[1] and angles[1] > angles[2], "The pointer swings one way from low through half to high")
	_check(is_equal_approx(world._water.sea.position.y, World.SEA_LEVELS.shut) and is_equal_approx(world._water.chamber.position.y, World.HARBOUR_LEVELS.half), "The outer sea rests shut and the chamber at half in the first stage")
	# A real press at the wheel turns it; the water eases over without touching the turn.
	world.reduced_motion = false
	sim._mechanisms.controls.tide = "low"
	sim._players.p0 = {"x": 192, "z": -352, "height": 96, "surface_id": "m-quay"}
	sim._refresh_routes()
	world.present(sim.snapshot(), true)
	var pressed: Dictionary = sim.step({"move_x": 0.0, "move_z": 0.0, "interact": true})
	_check(pressed.controls.tide == "half" and "selector:tide" in pressed.events, "A press at the wheel turns the tide to half")
	var hash_after := sim.state_hash()
	world.present(pressed)
	var harbour: Node3D = world._water.harbour
	_check(is_equal_approx(harbour.position.y, World.HARBOUR_LEVELS.low) and is_equal_approx(harbour.get_meta("target"), World.HARBOUR_LEVELS.half), "The water starts from where it was")
	world._advance_camera(0.1)
	_check(harbour.position.y > World.HARBOUR_LEVELS.low and harbour.position.y < World.HARBOUR_LEVELS.half, "The water rises over a short moment")
	for frame in range(20): world._advance_camera(0.05)
	_check(is_equal_approx(harbour.position.y, World.HARBOUR_LEVELS.half) and is_equal_approx(harbour.scale.y, World.HARBOUR_LEVELS.half - World.SEABED), "The water settles at half, reaching down to the harbour floor")
	_check(sim.state_hash() == hash_after, "Water easing never changes the simulation")
	world.reduced_motion = true
	_check(_dry_decks(world, level), "No water strip covers an island deck")
	# The spout and the sluice lamp follow the lever.
	_check(not world._spout.visible and not world._lever_lamps.sluice.lamp.get_meta("lit"), "The spout is dry while the sluice is off")
	sim._mechanisms.levers["sluice"] = true
	world.present(sim.snapshot(), true)
	_check(world._spout.visible and world._lever_lamps.sluice.lamp.get_meta("lit") and not world._lever_lamps.line.lamp.get_meta("lit"), "The spout runs and its lamp lights only while the sluice is on")
	# Cutaway: only the aqueduct ever fades, and only over a spirit it hides.
	var span: Node3D = world._surface_nodes["aq-span"]
	var quay: Node3D = world._surface_nodes["m-quay"]
	_check(world._should_cutaway(span, _players(state, "p0", 624, 288, 0)), "The aqueduct fades over a spirit landing from the spout")
	_check(not world._should_cutaway(span, _players(state, "p0", 900, 420, 0)) and not world._should_cutaway(span, _players(state, "p0", 624, 288, 48)), "The aqueduct stays solid when nobody is under it")
	_check(not world._should_cutaway(quay, _players(state, "p0", 100, 300, 0)), "A quay never fades for a spirit on the beach in front of it")
	var water_alpha: float = (world._water.harbour.get_child(0).material_override as StandardMaterial3D).albedo_color.a
	sim._players.p0 = {"x": 624, "z": 288, "height": 0, "surface_id": "e-beach"}
	world.present(sim.snapshot(), true)
	var faded: MeshInstance3D = span.find_child("aq-spanFloor", true, false)
	_check(faded != null and faded.material_override.albedo_color.a < 0.5, "The spout landing shows through the faded aqueduct")
	_check(is_equal_approx((world._water.harbour.get_child(0).material_override as StandardMaterial3D).albedo_color.a, water_alpha), "Water never fades with a floor")
	# Camera: follows anywhere in the harbour, clamped to its full extent.
	for case: Array in [[-1400, 0, -9.6, 0.0], [2200, 0, 17.28, 0.0], [300, -900, 3.0, -5.44], [300, 900, 3.0, 5.44], [-500, -160, -5.0, -1.6]]:
		world.actors["p0"].position = Vector3(float(case[0]) / 100.0, 0, float(case[1]) / 100.0)
		var center: Vector3 = world._camera_center()
		_check(is_equal_approx(center.x, case[2]) and is_equal_approx(center.z, case[3]), "Camera centre clamps to the harbour: %s" % str(case))
	sim._players.p0 = {"x": 192, "z": -512, "height": 96, "surface_id": "wheel-step"}
	world.present(sim.snapshot(), true)
	for pad: Dictionary in level.stages[0].pressure_pads:
		_check(_on_screen(world, world._physical_pads[pad.id].global_position), "All three waiting steps are framed from the wheel step: " + str(pad.id))
	_check(_textures(world), "Every first-stage mesh has geometry and a material")
	world.queue_free()
	await process_frame

func _second_stage(level: Dictionary) -> void:
	var checkpoint := _history(level)
	var sim := _sim(level, "slack-water", checkpoint)
	var world := _world(level, 1, checkpoint)
	_check(world.terrain.name == "TurnOfTheTide" and world.displayed_stage_id == "slack-water", "The second stage builds")
	var state: Dictionary = sim.snapshot()
	world.present(state, true)
	for id: String in ["boom-chain", "gate-bar", "punt-chain", "punt-line"]:
		_check(absf(world._physical_levers[id].global_position.y - 0.68) < 0.01, "A chain or line on its raised stub stands at the stub's height: " + id)
	for id: String in ["boom-post-pad", "gate-post-pad", "punt-post-pad"]:
		_check(absf(world._physical_pads[id].global_position.y - 0.545) < 0.01, "A post pad sits on its raised post: " + id)
	_check(world._wheels.size() == 3 and world._wheels.has("tide") and world._wheels.has("chamber") and world._wheels.has("basin"), "Tide, chamber and sea get hand wheels; the lock stays two-way")
	for id: String in world._journey_switches:
		for label: Label3D in world._journey_switches[id].labels:
			_check(label.position.y > World.HARBOUR_LEVELS.high + 0.05 and label.position.y > World.CHAMBER_WALL_TOP, "A wheel label rides above high water and the chamber walls: " + id)
	var labels: Array = world._journey_switches["basin"].labels
	_check(labels.size() == 4 and absf(labels[3].position.x - labels[0].position.x - 2.40) < 0.001, "Four sea labels span 2.4 m instead of 3.8 m")
	_check(world._gauges.has("boom-jetty") and world._gauges.has("mole-steps") and world._gauges.has("race-stage") and not world._gauges.has("sea-gate-in"), "Second-stage tide crossings carry gauges; the chamber gate does not")
	_check(world._catwalks.size() == 3, "The three catwalks read slack")
	_check(world._post_marks.size() == 3 and world._post_marks["boom-post"].bands.size() == 3 and world._post_marks["gate-post"].bands.size() == 1 and world._post_marks["punt-post"].bands.size() == 2, "Each post's mouth shows the sea it rises at")
	_check(_crests(world, "basin").size() == 4, "Sea crests mark the wheel once and the three mouth crossings, not the stubs")
	for crest: Node3D in _crests(world, "boom-chain") + _crests(world, "punt-line"):
		var on_floor := false
		for route: Dictionary in level.bridges + level.islands:
			var r: Array = route.rect_cm
			if crest.position.x * 100.0 > r[0] and crest.position.x * 100.0 < r[2] and crest.position.z * 100.0 > r[1] and crest.position.z * 100.0 < r[3]: on_floor = true
		_check(on_floor, "A crest sits on a floor, never over a gap: " + str(crest.get_meta("crest")))
	# Kept crossings from the first stage show at their own heights.
	var markers: Array = world._remembered.get_children()
	_check(markers.size() == 2 * checkpoint.mechanisms.latched_bridges.filter(func(id: String) -> bool: return not id in STAIRS).size(), "Every kept crossing has its marker")
	var index := 0
	for route: Dictionary in level.bridges:
		if route.id not in checkpoint.mechanisms.latched_bridges: continue
		_check(absf(markers[index].position.y - float(route.height_cm) / 100.0 - 0.02) < 0.01, "A kept marker sits on its crossing: " + str(route.id))
		index += 2
	_check(world._decks["wheel-step"].visible and world._memory_markers["wheel-step"].visible and world._memory_markers["wheel-step"].find_child("KeptPennant", true, false) != null, "The kept waiting step shows its pennant")
	# The outer sea, its gates and the mouth lamps follow the basin.
	_check(not world._sea_gates[0].get_meta("open") and is_equal_approx(world._water.sea.position.y, World.SEA_LEVELS.shut), "The sea gate is shut at a neutral level")
	for value: String in ["low", "half", "high"]:
		sim._mechanisms.controls.basin = value
		sim._refresh_routes()
		world.present(sim.snapshot(), true)
		_check(is_equal_approx(world._water.sea.position.y, World.SEA_LEVELS[value]) and world._sea_gates[0].get_meta("open"), "The outer sea opens and stands at " + value)
		for other: String in world._mouth_lamps:
			_check(world._mouth_lamps[other].get_meta("lit") == (other == value), "Only the %s mouth lamp lights for a %s sea" % [other, value])
		_check(world._wheels.basin.wheel.get_meta("value") == value, "The sea wheel shows " + value)
		for post: String in world._post_marks:
			_check(world._post_marks[post].bands[0].material_override.emission_enabled == (world._post_marks[post].value == value), "Only the matching post mark glows: %s at %s" % [post, value])
	# Dry at slack: the catwalks read the remembered tide, not the live wheel.
	sim._mechanisms.controls.basin = "low"
	sim._mechanisms.controls.tide = "half"
	sim._refresh_routes()
	var moved: Dictionary = sim.snapshot()
	world.present(moved)
	_check(not bool(moved.bridges["gate-catwalk"]) and world._decks["gate-catwalk"].visible and world._decks["gate-catwalk"].get_meta("dry"), "A catwalk stays dry at slack after the first spirit turns the tide")
	sim._mechanisms.controls.basin = "half"
	sim._refresh_routes()
	world.present(sim.snapshot())
	_check(not world._decks["gate-catwalk"].visible, "A catwalk is wet once the sea leaves the remembered tide")
	# The chamber matches the harbour.
	sim._mechanisms.controls.chamber = "half"
	sim._refresh_routes()
	world.present(sim.snapshot(), true)
	_check(world._chamber_lamps.size() == 2 and world._chamber_lamps[0].get_meta("lit") and is_equal_approx(world._water.chamber.position.y, World.HARBOUR_LEVELS.half), "The chamber lamps light while chamber and harbour match")
	sim._mechanisms.controls.chamber = "high"
	world.present(sim.snapshot(), true)
	_check(not world._chamber_lamps[0].get_meta("lit") and is_equal_approx(world._water.chamber.position.y, World.HARBOUR_LEVELS.high), "The chamber fills and its lamps go out off the harbour level")
	var lantern: MeshInstance3D = world.terrain.find_child("HarbourLantern", true, false)
	_check(lantern != null and absf(lantern.get_parent().position.y - 0.48) < 0.01, "The goal is the harbour lantern on the mole terrace")
	# Framing the stubs, and the lantern from the mole.
	for at: Array in [[-484, -160], [-268, 160], [-832, 0]]:
		sim._players.p1 = {"x": at[0], "z": at[1], "height": 48, "surface_id": "w-terrace"}
		world.present(sim.snapshot(), true)
		_check(_on_screen(world, Vector3(float(at[0]) / 100.0, 0.48, float(at[1]) / 100.0)), "The camera frames the second spirit at %s" % str(at))
	_check(_textures(world), "Every second-stage mesh has geometry and a material")
	_check(world.terrain.find_children("*", "CollisionObject3D", true, false).is_empty(), "The world adds no collision")
	# Switching stages rebuilds cleanly.
	world.show_stage(level.stages[0])
	_check(world._catwalks.is_empty() and world._wheels.keys() == ["tide"] and world._chamber_lamps.size() == 2, "Returning to the first stage rebuilds its own wheels")
	world.queue_free()
	await process_frame

func _dressing(level: Dictionary) -> void:
	var data := Dressing.for_key(KEY)
	_check(data.get("look", "") == "dusk" and data.get("camera", "") == "follow", "The harbour is dressed at dusk with the follow camera")
	# The scenery lint's own rules, run against this chapter's geometry.
	var lint: Object = Lint.new()
	for stage: Dictionary in level.stages:
		lint._lint(KEY, str(stage.id), CooperativeCatalog.stage_definition(level, str(stage.id)), data)
	_check(lint.checks > 50 and lint.failures == 0, "Every harbour prop passes the dressing lint (%d checks, %d failures)" % [lint.checks, lint.failures])
	lint.free()
	var world := _world(level, 0, JourneyCatalog.initial_checkpoint(level))
	for stage: Dictionary in level.stages:
		world.show_stage(stage)
		var built: Array = world.terrain.find_children("*", "Node3D", true, false).filter(func(node: Node) -> bool: return node.has_meta("dressing_kind"))
		_check(built.size() == Props.expand(Dressing.stage_props(data, str(stage.id))).size(), "Every dressing prop is built: " + str(stage.id))
		var floors := 0
		for island: Dictionary in level.islands:
			var node: Node3D = world._surface_nodes[island.id]
			if node.find_child(str(island.id) + "Floor", true, false) != null: floors += 1
		_check(floors == level.islands.size(), "Every island has its dressed floor: " + str(stage.id))
	world.free()

func _keepsakes() -> void:
	var host: Node3D = World.new()
	root.add_child(host)
	for id: String in ["set-the-tide", "slack-water"]:
		var keepsake := KeepsakeVisual.create(host, {"stage_id": id})
		_check(keepsake.get_child_count() > 4, "The %s keepsake has its own shape, not the fallback ball" % id)
		keepsake.free()
	host.free()

func _sound(level: Dictionary) -> void:
	# Each wheel names its own cue identity, so every switch keeps its own pitch.
	var sources: Array = []
	for stage: Dictionary in level.stages:
		for control: Dictionary in stage.controls:
			var source := Soundscape.event_source("selector:" + str(control.id), "a")
			if source not in sources: sources.append(source)
	_check(sources.size() == 5, "Five wheels give five cue identities")
	# Journey keys already map the spout and the wheels; checked once registered.
	if Registry.is_journey(KEY):
		var mapped := SoundMap.cues(KEY, {"events": ["drop", "selector:tide", "selector:basin"], "role": "b"})
		_check(mapped.cues == ["seed_landed", "switch_set", "switch_set"] and mapped.sources[1] != mapped.sources[2], "The spout lands with a thud and each wheel turns with its own switch cue")

func _sim(level: Dictionary, stage_id: String, checkpoint: Dictionary) -> Simulation:
	# A trusted reset opens the turn without the proof's catalog check; every
	# rule after that is the real journey facade.
	var sim := Simulation.new()
	sim.simulation_version = 9
	sim._reset_trusted(level, stage_id, checkpoint, {}, "a")
	return sim

func _world(level: Dictionary, index: int, checkpoint: Dictionary) -> Node3D:
	var world: Node3D = World.new()
	root.add_child(world)
	world.reduced_motion = true
	world.set_process(false)
	world.load_level(level)
	world.show_stage(level.stages[index])
	world.present_history(checkpoint)
	return world

## The stage-one completion for the Low plan: the first spirit on the wheel
## step, the second at the bell, the low-plan crossings kept.
func _history(level: Dictionary) -> Dictionary:
	var checkpoint := JourneyCatalog.initial_checkpoint(level)
	checkpoint.stage_index = 1
	checkpoint.completed_stage_id = "set-the-tide"
	checkpoint.next_stage_id = "slack-water"
	checkpoint.players = {"p0": {"x": 192, "z": -512, "height": 96, "surface_id": "wheel-step"}, "p1": {"x": 1440, "z": 0, "height": 48, "surface_id": "r-terrace"}}
	checkpoint.mechanisms.controls.winch = "slip"
	checkpoint.mechanisms.levers = {"sluice": true}
	var latched: Array = STAIRS.duplicate()
	latched.append_array(["sand-1", "slipway", "wheel-step", "lock-west"])
	latched.sort()
	checkpoint.mechanisms.latched_bridges = latched
	return checkpoint

func _gate(stage: Dictionary, route_id: String) -> Dictionary:
	for gate: Dictionary in stage.gates:
		if gate.route_id == route_id: return gate
	return {}

func _players(state: Dictionary, slot: String, x: int, z: int, height: int) -> Dictionary:
	var value := state.duplicate(true)
	value.players[slot] = {"x": x, "z": z, "height": height}
	value["active_slot"] = slot
	return value

func _on_screen(world: Node3D, at: Vector3) -> bool:
	var camera: Camera3D = world.camera
	world._follow_center = world._camera_center()
	world._frame_camera()
	if camera.is_position_behind(at): return false
	return Rect2(Vector2.ZERO, Vector2(root.size)).grow(-24).has_point(camera.unproject_position(at))

func _dry_decks(world: Node3D, level: Dictionary) -> bool:
	for body: Node3D in world._water.values():
		for strip: MeshInstance3D in body.get_children():
			var size: Vector3 = (strip.mesh as BoxMesh).size
			var rect := Rect2(Vector2(strip.position.x - size.x * 0.5, strip.position.z - size.z * 0.5), Vector2(size.x, size.z)).grow(-0.01)
			for island: Dictionary in level.islands:
				var r: Array = island.rect_cm
				if rect.intersects(Rect2(Vector2(float(r[0]), float(r[1])) / 100.0, Vector2(float(r[2] - r[0]), float(r[3] - r[1])) / 100.0)): return false
	return true

func _textures(world: Node3D) -> bool:
	for node: Node in world.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null or mesh.get_active_material(0) == null: return false
	for node: Node in world.find_children("*", "Label3D", true, false):
		if (node as Label3D).font == null: return false
	return true

func _crests(world: Node3D, id: String) -> Array:
	return world.terrain.find_children("*", "Node3D", true, false).filter(func(node: Node) -> bool: return node.has_meta("crest") and (id.is_empty() or node.get_meta("crest") == id))

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
