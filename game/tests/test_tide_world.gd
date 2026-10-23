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
const LabelBubble = preload("res://presentation/kit/label_bubble.gd")
const JourneyWorld = preload("res://presentation/journey_world.gd")
const ChapterIndex = preload("res://content/chapters/index.gd")
const StandSpot = preload("res://presentation/kit/stand_spot.gd")
const SpotChecks = preload("res://tests/stand_spot_checks.gd")
const Seven = preload("res://core/journey/seven_mechanisms.gd")
const STAIRS := ["w-steps-low", "w-steps-high", "mill-steps", "mill-ladder", "east-steps", "boathouse-steps", "rock-steps-low", "rock-steps-high"]
var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var level := TideCatalog.definition()
	var digest := Canonical.digest(level)
	await _first_stage(level)
	_memory_camera(level)
	await _second_stage(level)
	await _plain_pads(level)
	_crest_glyphs(level)
	_dressing(level)
	_keepsakes()
	_sound(level)
	_open_crossings_dry()
	var scene: PackedScene = load("res://turn_of_the_tide.tscn")
	var state := scene.get_state()
	var key := ""
	for index in range(state.get_node_property_count(0)):
		if state.get_node_property_name(0, index) == "chapter_key": key = str(state.get_node_property_value(0, index))
	_check(key == KEY, "The chapter scene opens Turn of the Tide on the shared chapter screen")
	_check(Canonical.digest(level) == digest, "Building and presenting the world never changes the definition")
	_check(preload("res://presentation/kit/primitives.gd").changed_shared_looks().is_empty(), "Every kit look shared between meshes is as it was made; code that changes a mesh's material takes its own copy (Primitives.own_material): %s" % [preload("res://presentation/kit/primitives.gd").changed_shared_looks()])
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
		_check(absf(world._physical_pads[pad.id].global_position.y - 0.96 - StandSpot.RIM_LIFT) < 0.01, "A waiting-step pad sits on its raised step: " + str(pad.id))
	for problem: String in SpotChecks.shapes(world, level.stages[0]) + SpotChecks.beacon_rings(world, level.stages[0]): _check(false, problem)
	_check(SpotChecks.held(world, level.stages[0], state).is_empty(), "No step's spot shows held while nobody stands on it")
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
	_bubbles(world, level.stages[0])
	_highlights(world, sim, level.stages[0])
	_slip_ramp(world, sim)
	# The first spirit at the tide wheel: its bubble rises clear of it and of the
	# waiting steps' gauges behind it.
	var at_wheel: Dictionary = sim.snapshot()
	at_wheel.players = at_wheel.players.duplicate(true)
	at_wheel.players.p0 = {"x": 192, "z": -352, "height": 96, "surface_id": "m-quay"}
	world.present(at_wheel, true)
	world._follow_center = world._camera_center()
	world._frame_camera()
	_check(world._journey_switches["tide"].bubble.lift > 0.0, "The tide bubble rises while the first spirit stands at its wheel")
	_lifted_clear(world, "set-the-tide, the first spirit at the tide wheel")
	# Behind and left of the tide wheel's lever: the bubble slides aside or
	# rises, and still clears the gauges and wheels in one placement.
	at_wheel.players.p0 = {"x": 147, "z": -387, "height": 96, "surface_id": "m-quay"}
	world.present(at_wheel, true)
	world._follow_center = world._camera_center()
	world._frame_camera()
	_lifted_clear(world, "set-the-tide, the first spirit behind and left of the tide lever")
	world.present(sim.snapshot(), true)
	var angles: Array = []
	var levels: Dictionary = {}
	for value: String in ["low", "half", "high"]:
		sim._mechanisms.controls.tide = value
		sim._refresh_routes()
		var current: Dictionary = sim.snapshot()
		var frozen := Canonical.digest(current)
		world.present(current, true)
		_check(Canonical.digest(current) == frozen, "Presenting leaves the snapshot unchanged at " + value)
		angles.append(world._wheels.tide.wheel.rotation.y)
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
	_walls(world, level, 0)
	# The first stage can keep only the low crossings it latches; nothing else
	# is walled for keeping (the sea never moves here, so its crossings stay
	# dry), and stepping stones stand in the channel unwalled.
	var kept: Array = world._kept_walled.duplicate()
	kept.sort()
	_check(kept == ["sand-1", "slipway"], "Stage one walls exactly the crossings it can keep under water: %s" % [kept])
	# Shut crossings stay in view as outlines; open ones show their deck.
	sim._mechanisms.controls.tide = "half"
	sim._refresh_routes()
	world.present(sim.snapshot(), true)
	_check(world._ghosts.has("sand-1") and world._ghosts["sand-1"].visible and not world._decks["sand-1"].visible, "At half water the shut sand bar shows as an outline")
	_check(world._ghosts.has("stones-1") and not world._ghosts["stones-1"].visible and world._decks["stones-1"].visible, "At half water the open stones show their deck, not the outline")
	_check(world._decks["stones-1"].find_children("SteppingStone*", "", true, false).size() >= 3 and world._decks["sand-1"].find_children("*", "MeshInstance3D", true, false).size() > 4, "Stones are built as stepping stones and the sand bar as a rippled hump")
	var bubble: LabelBubble = world._journey_switches["tide"].bubble
	var chips: Array = bubble.labels
	_check(chips[1].modulate == LabelBubble.ACTIVE_INK and (chips[1].get_meta("backing").material_override as StandardMaterial3D).albedo_color == LabelBubble.ACTIVE_FILL, "The current tide value is filled in its bubble")
	_check(chips[0].modulate.a < 0.5 and chips[2].modulate.a < 0.5 and (chips[0].get_meta("backing").material_override as StandardMaterial3D).albedo_color.a == 0.0, "The other tide values fade back")
	bubble.sync()
	_check(bubble.body.material_override == LabelBubble.body_material(false, false) and is_equal_approx(chips[0].pixel_size, LabelBubble.PIXEL_SIZE), "The tide wheel uses the shared cream bubble with dark letters")
	# The tide wheel is the control: a valve on the wheel's own spot, no lever
	# handle and no hand wheel beside it, its arrow a long bar, the harbour's
	# wave sign on the post behind it, and no water blue on the first spirit's
	# (orange) valve but that sign.
	var hand: Node3D = world._wheels.tide.wheel
	var valve: RefCounted = world._lever_looks.tide
	_check(valve.kind == "valve" and absf(hand.global_position.x - 1.92) < 0.001 and absf(hand.global_position.z + 3.52) < 0.001, "The tide valve turns on the control's own spot")
	_check(world.terrain.find_child("HandWheel_tide", false, false) == null and world.terrain.find_child("WheelDial_tide", false, false) == null and world._physical_levers.tide.get_child_count() == 0, "No lever handle and no hand wheel beside it")
	_check(hand.find_child("WheelPointer", false, false) is MeshInstance3D and (hand.find_child("WheelPointer", false, false).mesh as BoxMesh).size.z >= 0.15, "The valve's arrow is a long bar")
	var sign: Node3D = world.terrain.find_child("WaterIcon_tide", false, false)
	_check(sign != null and sign.position.distance_to(valve.sign_point()) < 0.001 and sign.position.y - hand.global_position.y > 0.15 and sign.position.z < hand.global_position.z and world.terrain.find_children("ChipRowWater*", "", false, false).is_empty(), "The tide valve carries the harbour's wave sign up behind it")
	var sign_box := AABB()
	for node: Node in sign.find_children("*", "MeshInstance3D", true, false):
		var piece: AABB = (node as MeshInstance3D).global_transform * (node as MeshInstance3D).get_aabb()
		sign_box = piece if sign_box.size == Vector3.ZERO else sign_box.merge(piece)
	var reach: float = valve.REACH
	_check(absf(sign_box.position.x - 1.92) <= reach and absf(sign_box.end.x - 1.92) <= reach and absf(sign_box.position.z + 3.52) <= reach and absf(sign_box.end.z + 3.52) <= reach, "The valve's sign stays inside the control's reach")
	var spoke: MeshInstance3D = valve.wheel().find_child("ValveSpoke", false, false)
	_check(spoke != null and (spoke.material_override as StandardMaterial3D).albedo_color.get_luminance() - valve.IRON.get_luminance() > 0.3, "The valve's spokes stand out light against its dark dial")
	var blue: Array = []
	for node: Node in valve.root.find_children("*", "MeshInstance3D", true, false):
		var colour: Color = ((node as MeshInstance3D).material_override as StandardMaterial3D).albedo_color
		for tint: Color in World.WHEEL_WATER.values():
			if colour.is_equal_approx(tint) or colour.is_equal_approx(tint.darkened(0.35)): blue.append(node.name)
	_check(blue.is_empty() and (valve.wheel().find_child("ValveRim", false, false).material_override as StandardMaterial3D).albedo_color == world.GOLD, "The first spirit's valve is in its own gold, no water blue on it: %s" % [blue])
	for id: String in world._gauges:
		_check(world._gauges[id].icon is Label3D and world._gauges[id].icon.fixed_size and world._gauges[id].bands[0].mesh.top_radius >= 0.1, "A gauge carries large bands and a wave sign that keeps its size: " + id)
	# Boats ride the harbour.
	_check(world._boats.size() == 3, "Three rowboats moor in the channels")
	for boat: Node3D in world._boats:
		_check(absf(boat.position.y - (World.HARBOUR_LEVELS.half - 0.02)) < 0.03, "A moored boat rides the harbour at half water")
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
	# On the wheel step's edge, outside its pad, the pad does not count and its
	# spot stays free; on the spot it counts, and the spot lights and sinks.
	sim._players.p0 = {"x": 214, "z": -494, "height": 96, "surface_id": "wheel-step"}
	var edge: Dictionary = sim.snapshot()
	world.present(edge, true)
	_check(not edge.hold_pads["wheel-step-pad"], "A spirit on the wheel step's edge is outside its pad")
	for problem: String in SpotChecks.held(world, level.stages[0], edge): _check(false, problem)
	sim._players.p0 = {"x": 192, "z": -512, "height": 96, "surface_id": "wheel-step"}
	var centre: Dictionary = sim.snapshot()
	world.present(centre, true)
	_check(centre.hold_pads["wheel-step-pad"], "A spirit on the wheel step's spot holds its pad")
	for problem: String in SpotChecks.held(world, level.stages[0], centre): _check(false, problem)
	world.present(edge, true)
	for problem: String in SpotChecks.held(world, level.stages[0], edge): _check(false, problem)
	world.present(centre, true)
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
	# The winch is no control here; the LOW history left it on slip.
	_check(state.controls.winch == "slip" and world._ramps.slipway.rotation.z == 0.0, "In Slack Water the ramp lies where the first stage left the winch")
	for lever: Dictionary in level.stages[1].levers:
		var lift: float = world._lever_looks[lever.id].anchor_lift() if world._lever_looks.has(lever.id) else 0.20
		_check(absf(world._physical_levers[lever.id].global_position.y - float(lever.height_cm) / 100.0 - lift) < 0.01, "A chain, bar, line, pin or key stands at its own stub's height: " + str(lever.id))
	# The chains are hand winches and the bars sliding bolts (descriptor
	# "lever_looks"); every other lever keeps its handle. A look shows the
	# snapshot's lever, pulled or not.
	var looks := {}
	for id: String in world._lever_looks: looks[id] = world._lever_looks[id].kind
	_check(looks == {"boom-chain": "winch", "punt-chain": "winch", "gate-bar": "bolt", "sea-bar": "bolt", "tide": "valve", "basin": "valve", "chamber": "valve"}, "The chains wind on winches, the bars slide as bolts and the water wheels are valves: %s" % [looks])
	var pulled := state.duplicate(true)
	pulled.levers = {"boom-chain": true, "gate-bar": true}
	world.present(pulled, true)
	_check(world._lever_looks["boom-chain"].shown() == 1.0 and world._lever_looks["gate-bar"].shown() == 1.0 and world._lever_looks["punt-chain"].shown() == 0.0 and world._lever_looks["sea-bar"].shown() == 0.0, "Each look shows its own lever's state")
	world.present(state, true)
	_check(world._lever_looks["boom-chain"].shown() == 0.0, "Let go in the snapshot, a look is let go")
	for id: String in ["boom-post-pad", "gate-post-pad", "punt-post-pad"]:
		_check(absf(world._physical_pads[id].global_position.y - 0.48 - StandSpot.RIM_LIFT) < 0.01, "A post pad sits on its raised post: " + id)
	for problem: String in SpotChecks.shapes(world, level.stages[1]) + SpotChecks.beacon_rings(world, level.stages[1]) + SpotChecks.held(world, level.stages[1], state): _check(false, problem)
	_check(world._wheels.size() == 3 and world._wheels.has("tide") and world._wheels.has("chamber") and world._wheels.has("basin"), "Tide, chamber and sea get hand wheels; the lock stays two-way")
	for id: String in world._journey_switches:
		for label: Label3D in world._journey_switches[id].labels:
			_check(label.position.y > World.HARBOUR_LEVELS.high + 0.05 and label.position.y > World.CHAMBER_WALL_TOP, "A wheel label rides above high water and the chamber walls: " + id)
	_check(world._journey_switches["basin"].labels.map(func(label: Label3D) -> String: return label.text) == ["SHUT", "LOW", "HALF", "HIGH"], "The sea wheel's bubble names all four values")
	_bubbles(world, level.stages[1])
	_highlights(world, sim, level.stages[1])
	_check(world._gauges.has("boom-jetty") and world._gauges.has("mole-steps") and world._gauges.has("race-stage") and not world._gauges.has("sea-gate-in"), "Second-stage tide crossings carry gauges; the chamber gate does not")
	_check(world._catwalks.size() == 1 and world._catwalks[0] == "gate-catwalk", "Only the gate catwalk reads slack")
	_check(world._dry_marks.keys().size() == 3 and world._dry_marks.has("bar-catwalk") and world._dry_marks.has("beach-catwalk") and world._dry_marks.has("quay-catwalk"), "The three catwalks that read the sea alone carry a dry mark")
	_check(world._post_marks.size() == 3 and world._post_marks["boom-post"].bands.size() == 2 and world._post_marks["gate-post"].bands.size() == 1 and world._post_marks["punt-post"].bands.size() == 3, "Each post's mouth shows the sea it rises at")
	for id: String in world._dry_marks:
		_check(world._dry_marks[id][0].get_meta("lit"), "A shut sea leaves every mooring catwalk dry: " + id)
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
	var kept_post: MeshInstance3D = world._memory_markers["wheel-step"].find_child("KeptPost", true, false)
	_check(kept_post != null and (kept_post.mesh as BoxMesh).size.y >= 0.5 and world._memory_markers["wheel-step"].find_children("KeptEdge*", "", true, false).size() == 2, "A kept crossing shows a tall mooring post and gold edges")
	_check(kept_post != null and kept_post.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "A kept crossing's post casts no shadow over its pennant")
	# A kept low crossing keeps its pennant above the water that covers it.
	var sand: Node3D = world._memory_markers["sand-1"]
	var pennant: Node3D = sand.find_child("KeptPennant", true, false)
	for tide: String in ["low", "half", "high"]:
		var risen := state.duplicate(true)
		risen.controls.tide = tide
		world.present(risen, true)
		var level_y: float = World.HARBOUR_LEVELS[tide]
		var post: Node3D = sand.find_child("KeptPost", true, false)
		var top := post.global_position.y + 0.25 * post.scale.y
		_check(pennant.global_position.y - 0.11 > level_y and top >= level_y + World.MAST_CLEARANCE - 0.01, "At %s tide the sand crossing's pennant stays above the water (%.2f over %.2f)" % [tide, pennant.global_position.y, level_y])
		if tide == "low": _check(is_equal_approx(post.scale.y, 1.0), "Over dry sand the post keeps its height")
	world.present(state, true)
	_walls(world, level, 1)
	for id: String in ["towpath", "punt-ferry", "sea-gate-in", "w-steps-low", "mill-steps", "mole-slip"]:
		_check(id in world._walled, "Stage two walls %s against the water it can stand open under" % id)
	# Open only while dry, but they can be kept (entered in this stage or the
	# first) and walked later under water: walled too, so a kept one can show
	# dry. The quay-high ones never flood.
	var kept: Array = world._kept_walled.duplicate()
	kept.sort()
	_check(kept == ["race-stage", "sand-1", "sea-gate-out", "slipway"], "Stage two walls exactly the crossings it can keep under water: %s" % [kept])
	for id: String in ["jetty-1", "boom-jetty"]:
		_check(id not in world._walled, "Stage two leaves %s in the water: no water reaches its deck" % id)
	# Stepping stones, and the stubs open only over dry water or standing above
	# every water, stand in the open water, never walled.
	for id: String in ["stones-1", "stones-2", "stones-3", "beach-catwalk", "quay-catwalk"]:
		_check(id not in world._walled, "Stage two leaves %s in the open water, unwalled" % id)
	# The posts and the gate and bar catwalks have gates that tie them to no
	# tide value: open at high tide over terrace-high decks, so walled dry like
	# any crossing.
	for id: String in ["boom-post", "gate-post", "punt-post", "gate-catwalk", "bar-catwalk"]:
		_check(id in world._walled, "Stage two walls %s, open whatever the tide" % id)
	# A spirit on a walled post sees past the walls in front of it: they fade
	# while it stands there (from the snapshot, so a replay agrees) and come
	# back once it leaves.
	# The boom post's south and east walls face the camera; the gate post's
	# mouth does, so only its east wall stands in front.
	world.present(_players(state, "p1", -268, 160, 48), true)
	var faded := _faded_walls(world)
	_check(world._wall_fade.faded_spots() == 1 and faded.size() == 2 and faded.all(func(wall: Node3D) -> bool: return str(wall.name).begins_with("CrossingWall_boom-post") and (wall.position.z > 1.92 or wall.position.x > -2.40)), "A spirit on the boom post fades exactly its south and east walls: %s" % [faded])
	world.present(_players(state, "p1", -268, -160, 48), true)
	faded = _faded_walls(world)
	_check(faded.size() == 1 and str(faded[0].name).begins_with("CrossingWall_gate-post") and faded[0].position.x > -2.40, "A spirit on the gate post, mouth toward the camera, fades only its east wall: %s" % [faded])
	world.present(_players(state, "p1", -268, -40, 48), true)
	_check(world._wall_fade.faded_spots() == 0 and _faded_walls(world).is_empty() and world._wall_fade.meshes().all(func(mesh: MeshInstance3D) -> bool: return mesh.material_override.albedo_color.a == 1.0), "They come back once it steps off")
	world.present(state, true)
	_check(not world._decks["punt-ferry"].visible and world._ghosts["punt-ferry"].visible, "The shut punt shows its outline in its dry pit")
	_check(world.terrain.find_child("KeySign_sea-gate-out", true, false) != null, "The sea gate out shows a large key sign")
	# Spirits by the wheels: every bubble rises clear of them, of the gauges and
	# of each other, as in every chapter.
	for spot: Array in [["p1", -268, -160, 48, "gate-post"], ["p1", -268, 160, 48, "boom-post"], ["p1", -312, -64, 48, "w-terrace"], ["p1", -608, 48, 48, "sea-chamber"], ["p0", 192, -352, 96, "m-quay"], ["p0", 147, -387, 96, "m-quay"], ["p1", -653, 13, 48, "sea-chamber"]]:
		var waiting: Dictionary = sim.snapshot()
		waiting.players = waiting.players.duplicate(true)
		waiting.players.p0 = {"x": 192, "z": -512, "height": 96, "surface_id": "wheel-step"}
		waiting.players[spot[0]] = {"x": spot[1], "z": spot[2], "height": spot[3], "surface_id": spot[4]}
		waiting["active_slot"] = spot[0]
		world.present(waiting, true)
		world._follow_center = world._camera_center()
		world._frame_camera()
		_check(_bubble_cover(world, "basin") <= JourneyWorld.SPIRIT_COVER + 0.001, "The sea wheel's bubble rises clear of a spirit at %s (covers %.2f)" % [spot[4], _bubble_cover(world, "basin")])
		_lifted_clear(world, "slack-water, %s at %s" % [spot[0], spot[4]])
	# The tide bubble may rise over the sea valve itself (scenery), but a spirit
	# at the sea valve never pushes it further.
	var spirit_at_lever: Dictionary = sim.snapshot()
	spirit_at_lever.players = spirit_at_lever.players.duplicate(true)
	spirit_at_lever.players.p1 = {"x": -312, "z": 40, "height": 48, "surface_id": "w-terrace"}
	world.present(spirit_at_lever, true)
	world._frame_camera()
	var without: float = world._journey_switches["tide"].bubble.lift
	spirit_at_lever.players.p1 = {"x": -312, "z": -64, "height": 48, "surface_id": "w-terrace"}
	world.present(spirit_at_lever, true)
	world._frame_camera()
	_check(world._journey_switches["tide"].bubble.lift == 0.0 and without == 0.0, "A spirit at the sea wheel never pushes the tide bubble off its lever (%.2f, %.2f)" % [world._journey_switches["tide"].bubble.lift, without])
	var chip: Label3D = world._journey_switches["basin"].labels[0]
	_check(not chip.no_depth_test and not (chip.get_meta("backing").material_override as StandardMaterial3D).no_depth_test, "Bubbles stand in the scene like every chapter's, not drawn over it")
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
		for id: String in world._dry_marks:
			_check(world._dry_marks[id][0].get_meta("lit") == (id == "quay-catwalk" and value != "high"), "A dry mark follows its catwalk: %s at %s" % [id, value])
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
	for at: Array in [[-484, -160, 48], [-268, 160, 48], [-832, 0, 48], [-172, 512, 0], [-172, -512, 96]]:
		sim._players.p1 = {"x": at[0], "z": at[1], "height": at[2], "surface_id": "w-terrace"}
		world.present(sim.snapshot(), true)
		_check(_on_screen(world, Vector3(float(at[0]) / 100.0, float(at[2]) / 100.0, float(at[1]) / 100.0)), "The camera frames the second spirit at %s" % str(at))
	_check(_textures(world), "Every second-stage mesh has geometry and a material")
	_check(world.terrain.find_children("*", "CollisionObject3D", true, false).is_empty(), "The world adds no collision")
	# Switching stages rebuilds cleanly.
	world.show_stage(level.stages[0])
	_check(world._catwalks.is_empty() and world._dry_marks.is_empty() and world._wheels.keys() == ["tide"] and world._chamber_lamps.size() == 2, "Returning to the first stage rebuilds its own wheels")
	world.queue_free()
	await process_frame

## Every wall that holds water stands to just above high water; no water strip
## covers a walled crossing, and a walled crossing that can shut floods.
func _walls(world: Node3D, level: Dictionary, index: int) -> void:
	var parapets: Array = world.terrain.find_children("Parapet*", "", true, false)
	_check(parapets.size() > 20, "Beach and terrace edges facing water carry parapets (%d)" % parapets.size())
	for wall: Node in parapets.filter(func(node: Node) -> bool: return node is MeshInstance3D and not str(node.name).contains("Coping")):
		var mesh := wall as MeshInstance3D
		var top := mesh.global_position.y + (mesh.mesh as BoxMesh).size.y * 0.5
		if absf(top - World.PARAPET_TOP) > 0.005:
			_check(false, "A parapet stands to just above high water: %s at %.3f" % [wall.name, top])
			return
	_check(world.terrain.find_children("SeaWall*", "", true, false).size() > 4, "The harbour's channel ends and the sea's reaches end in sea walls")
	_check(world.terrain.find_children("WaterMark_*", "", true, false).size() > 30, "Walls carry bands at the water marks")
	for body: Node3D in world._water.values():
		for rect: Rect2 in _water_rects(body):
			for id: String in world._walled:
				var r: Array = world._route(id).rect_cm
				if rect.grow(-0.01).intersects(Rect2(Vector2(float(r[0]), float(r[1])) / 100.0, Vector2(float(r[2] - r[0]), float(r[3] - r[1])) / 100.0)):
					_check(false, "Stage %d: no water strip covers walled %s" % [index + 1, id])
					return
		var water := body.get_child(0) as MeshInstance3D
		_check(_windings(water.mesh).keys() == _windings(BoxMesh.new()).keys(), "Stage %d: every face of %s is wound like the engine's own boxes, so it shows from the side it faces" % [index + 1, body.name])

## In both versions, a crossing that a stage's gate can hold open while its
## water (the harbour's at the tide, the outer sea's at the sea's value) stands
## above its deck is dry: no water surface lies over it, so a spirit the rules
## keep safe there never stands in the water. Gates are read by the journey
## rules themselves (seven_mechanisms) at every value of the wheels of this
## stage and the ones before it (a later stage reads what an earlier one
## left), with every such lever pulled and each spirit on any of this stage's
## pads or on none, so a
## moved or regated crossing is caught whatever the world walls. Kept crossings
## (open because entered earlier) are the kept-crossing checks' business.
func _open_crossings_dry() -> void:
	for key: String in ["turn-of-the-tide@1", "turn-of-the-tide@2"]:
		var level: Dictionary = Registry.definition(key)
		var checkpoint := JourneyCatalog.initial_checkpoint(level)
		for index in range(level.stages.size()):
			var stage: Dictionary = level.stages[index]
			var under := _open_under_water(level, index, checkpoint.mechanisms.controls)
			if str(stage.id) == "slack-water":
				for id: String in ["boom-post", "gate-post", "punt-post", "gate-catwalk", "bar-catwalk"]:
					_check(id in under, "%s: the rules can hold %s open under the high tide" % [key, id])
			var world := _world(level, index, checkpoint)
			if str(stage.id) == "set-the-tide": _check(world._wall_fade._spots.is_empty(), "%s: no walls fade in the first stage, which walls no post or catwalk" % key)
			if key == "turn-of-the-tide@2" and str(stage.id) == "slack-water":
				# The live row: the punt post, east end, fades its own south and east walls.
				world._wall_fade.occupy(PackedVector2Array([Vector2(-268, 160)]), true)
				var faded := _faded_walls(world)
				_check(faded.size() == 2 and faded.all(func(wall: Node3D) -> bool: return str(wall.name).begins_with("CrossingWall_punt-post") and (wall.position.z > 1.92 or wall.position.x > -2.40)), "@2: a spirit on the punt post fades exactly its south and east walls: %s" % [faded])
			var rects: Array[Rect2] = []
			for body: Node3D in world._water.values(): rects.append_array(_water_rects(body))
			for id: String in under:
				var r: Array = world._route(id).rect_cm
				var deck := Rect2(Vector2(float(r[0]), float(r[1])) / 100.0, Vector2(float(r[2] - r[0]), float(r[3] - r[1])) / 100.0).grow(-0.01)
				_check(not rects.any(func(rect: Rect2) -> bool: return rect.intersects(deck)), "%s %s: %s can stand open under its water, so no water lies over it" % [key, stage.id, id])
			world.free()

## The crossing walls the wall fade shows faded now.
func _faded_walls(world: Node3D) -> Array:
	return world._wall_fade.meshes().filter(func(mesh: MeshInstance3D) -> bool: return str(mesh.name).begins_with("CrossingWall_") and mesh.material_override.albedo_color.a < 1.0)

## The gated crossings of stage `index` that some state of the wheels and
## levers of it and the stages before it, and of its pads, holds open while
## their water stands above their lowest deck.
func _open_under_water(level: Dictionary, index: int, initial: Dictionary) -> Array[String]:
	var stage: Dictionary = level.stages[index]
	var wheels := {}
	var levers := {}
	for earlier: Dictionary in level.stages.slice(0, index + 1):
		for control: Dictionary in earlier.get("controls", []): wheels[control.id] = control.values
		for lever: Dictionary in earlier.get("levers", []): levers[lever.id] = true
	var combos: Array = [initial.duplicate()]
	for wheel: String in wheels:
		var grown: Array = []
		for combo: Dictionary in combos:
			for value: String in wheels[wheel]:
				var next: Dictionary = combo.duplicate()
				next[wheel] = value
				grown.append(next)
		combos = grown
	var nowhere := {"x": 100000, "z": 100000, "height": -1, "surface_id": ""}
	var spots := {"p0": [nowhere], "p1": [nowhere]}
	for pad: Dictionary in stage.get("pressure_pads", []):
		spots[pad.owner_slot].append({"x": pad.position_cm[0], "z": pad.position_cm[1], "height": int(pad.height_cm), "surface_id": pad.surface_id})
	var routes := {}
	for route: Dictionary in level.bridges + level.get("stairs", []): routes[route.id] = route
	var found: Array[String] = []
	for gate: Dictionary in stage.gates:
		var id := str(gate.route_id)
		var body := World._body_of(routes[id].rect_cm)
		if id in found or body.is_empty(): continue
		var deck := float(World._low_cm(routes[id])) / 100.0
		for controls: Dictionary in combos:
			var water: float = World.HARBOUR_LEVELS[controls.tide] if body == "harbour" else World.SEA_LEVELS[controls.get("basin", "shut")]
			if water <= deck: continue
			var open := false
			for a: Dictionary in spots.p0:
				for b: Dictionary in spots.p1:
					open = open or Seven.predicate(gate.get("when", {}), stage, {"p0": a, "p1": b}, {"controls": controls, "levers": levers})
			if open:
				found.append(id)
				break
	return found

## Within each stage every machine that opens a route has its own crest glyph.
func _crest_glyphs(level: Dictionary) -> void:
	for stage: Dictionary in level.stages:
		var seen: Dictionary = {}
		for gate: Dictionary in stage.gates:
			for id: String in _references(gate.get("when", {})):
				if id == "tide" or seen.has(id): continue
				_check(World.CRESTS.has(id), "%s: %s has its own crest" % [stage.id, id])
				seen[id] = "%s%d" % World.CRESTS.get(id, ["?", 0])
		var glyphs: Array = seen.values()
		var unique: Array = []
		for glyph: String in glyphs:
			if glyph not in unique: unique.append(glyph)
		_check(unique.size() == glyphs.size(), "%s: every machine's crest glyph is unique in its stage (%s)" % [stage.id, str(seen)])

func _references(predicate: Dictionary) -> Array:
	var found: Array = []
	for key: String in ["control_id", "lever_id", "pad_id"]:
		if predicate.has(key): found.append(str(predicate[key]))
	for child: Dictionary in predicate.get("all", []) + predicate.get("any", []):
		for id: String in _references(child):
			if id not in found: found.append(id)
	return found

## Every selector of a stage: one shared speech bubble naming its values,
## pointing at its lever (the kit default anchor, as in every chapter), whose
## settled tail lands within 1 cm of that lever; and, as the bubbles stand,
## clear of every spirit, gauge, hand wheel, other lever, pad and bubble.
## Measured on the fixed journey view plane in metres (LabelBubble.plane_rect,
## plane_point), never the live camera, so it holds on every platform.
func _bubbles(world: Node3D, stage: Dictionary) -> void:
	for control: Dictionary in stage.controls:
		var bubble: LabelBubble = world._journey_switches[control.id].bubble
		bubble.sync()
		var texts: Array = bubble.labels.map(func(label: Label3D) -> String: return label.text)
		var named: Dictionary = ChapterIndex.data(KEY).selector_names.get(str(control.id), {})
		var names: Array = control.values.map(func(value: String) -> String: return str(named.get(value, value)).to_upper())
		_check(bubble.values == control.values and texts == names, "%s names its values in one bubble" % control.id)
		if control.id == "winch": _check(texts == ["RAISED", "LOWERED"] and bubble.values == ["stowed", "slip"], "The winch bubble says RAISED and LOWERED while the catalog keeps stowed and slip")
		var knob: Vector3 = world._knob_top(str(control.id))
		var foot: Vector3 = world._at(control)
		_check(bubble.anchor.is_equal_approx(knob) and Vector2(knob.x - foot.x, knob.z - foot.z).length() < 0.3, "%s: %s's bubble points at its lever's knob" % [stage.id, control.id])
		var tip := LabelBubble.plane_point(world.terrain.to_global(bubble.anchor))
		_check(_plane_tail(bubble).distance_to(tip) < 0.01, "%s: %s's settled tail lands within 1 cm of its lever (%.3f m)" % [stage.id, control.id, _plane_tail(bubble).distance_to(tip)])
	_lifted_clear(world, str(stage.id) + " as placed")

## The follow camera's authored view height (metres). The gauges' waves keep
## their size on screen: this share of it.
const VIEW_HEIGHT := 9.2

## Where a bubble's tail tip lands on the journey view plane (metres, y down),
## as the body shader draws it: the body's centre, then sideways by its scale
## code and down by half the body, the tail and the stretch.
func _plane_tail(bubble: LabelBubble) -> Vector2:
	var body: MeshInstance3D = bubble.body
	var stretch: Variant = body.get_instance_shader_parameter(LabelBubble.STRETCH)
	return LabelBubble.plane_point(body.global_position) + Vector2(body.scale.z - LabelBubble.TAIL_CODE, (body.scale.y - LabelBubble.TAIL) * 0.5 + LabelBubble.TAIL + (float(stretch) if stretch != null else 0.0))

## The winch's ramp lowers into the slipway the moment the winch is turned,
## at any water, and stands up again when it is raised; the snapshot's
## crossings are untouched by it.
func _slip_ramp(world: Node3D, sim: Simulation) -> void:
	var hinge: Node3D = world._ramps.get("slipway")
	_check(hinge != null and hinge.name == "SlipRamp_slipway" and hinge in world._static_keep(), "The slipway has a winch ramp the scenery fold leaves free to move")
	if hinge == null: return
	var kept: Dictionary = sim._mechanisms.controls.duplicate()
	for tide: String in ["low", "half", "high"]:
		for winch: String in ["stowed", "slip"]:
			sim._mechanisms.controls.tide = tide
			sim._mechanisms.controls.winch = winch
			sim._refresh_routes()
			var routes: Dictionary = sim.snapshot().bridges.duplicate()
			world.present(sim.snapshot(), true)
			var lowered := absf(hinge.rotation.z) < 0.001
			_check(lowered == (winch == "slip") and Canonical.same(sim.snapshot().bridges, routes), "At %s water the %s winch leaves the ramp %s" % [tide, winch, "lowered" if winch == "slip" else "raised"])
	# Turned while the world runs, the ramp swings there over a few frames.
	sim._mechanisms.controls.winch = "stowed"
	world.reduced_motion = false
	world.present(sim.snapshot(), false)
	var start := hinge.rotation.z
	world._advance_water(0.2)
	_check(start == 0.0 and hinge.rotation.z > 0.0 and hinge.rotation.z < World.RAMP_RAISED, "A raised winch swings the ramp up over time (%.2f)" % hinge.rotation.z)
	world._advance_water(5.0)
	_check(is_equal_approx(hinge.rotation.z, World.RAMP_RAISED), "and it comes to rest raised")
	# Reduce motion: the ramp is where the winch says at once, whatever the call.
	world.reduced_motion = true
	sim._mechanisms.controls.winch = "slip"
	world.present(sim.snapshot(), false)
	_check(world.reduced_motion and hinge.rotation.z == 0.0, "Under Reduce motion the ramp lowers at once")
	sim._mechanisms.controls = kept
	sim._refresh_routes()
	world.present(sim.snapshot(), true)

## Every selector fills exactly its current value's pill, at every value.
func _highlights(world: Node3D, sim: Simulation, stage: Dictionary) -> void:
	for control: Dictionary in stage.controls:
		var id := str(control.id)
		var kept: String = sim._mechanisms.controls[id]
		var bubble: LabelBubble = world._journey_switches[id].bubble
		for chosen in range(control.values.size()):
			sim._mechanisms.controls[id] = control.values[chosen]
			sim._refresh_routes()
			world.present(sim.snapshot(), true)
			var right := true
			for index in range(bubble.labels.size()):
				var pill := (bubble.labels[index].get_meta("backing") as MeshInstance3D).material_override as StandardMaterial3D
				right = right and pill.albedo_color == (LabelBubble.ACTIVE_FILL if index == chosen else LabelBubble.CLEAR) and (bubble.labels[index].modulate == LabelBubble.ACTIVE_INK) == (index == chosen)
			_check(right, "%s: the %s bubble fills only %s" % [stage.id, id, control.values[chosen]])
		sim._mechanisms.controls[id] = kept
		sim._refresh_routes()
		world.present(sim.snapshot(), true)

## However the bubbles stand (settled or raised), none covers more than the
## journey worlds' share (10%) of a spirit, a gauge's waves and bands, a hand
## wheel, another lever's knob or a pad, and no two bubbles touch. On the fixed
## journey view plane in metres, like the lift itself. A bubble's body counts
## for scenery; its thin tail may pass in front.
func _lifted_clear(world: Node3D, label: String) -> void:
	var marks: Dictionary = {}
	for id: String in world._gauges:
		var icon: Label3D = world._gauges[id].icon
		var foot := LabelBubble.plane_point(icon.global_position)
		var tall := VIEW_HEIGHT * icon.font_size * icon.pixel_size * 0.5
		var low := LabelBubble.plane_point(world._gauges[id].bands[-1].global_position).y
		marks["gauge " + id] = Rect2(foot.x - tall * float(icon.text.length()) * 0.25, foot.y - tall * 0.8, tall * float(icon.text.length()) * 0.5, low - foot.y + tall * 0.8)
	for id: String in world._wheels:
		var hub := LabelBubble.plane_point(world._wheels[id].wheel.global_position)
		var reach := Vector2(World.VALVE_MARK_REACH, World.VALVE_MARK_REACH * LabelBubble.screen_up().y)
		marks["wheel " + id] = Rect2(hub - reach, reach * 2.0)
	for id: String in world._physical_levers:
		var knob := LabelBubble.plane_point((world._physical_levers[id] as Node3D).global_transform * Vector3(0, 0.4, 0))
		marks["knob " + id] = Rect2(knob - Vector2.ONE * 0.09, Vector2.ONE * 0.18)
	for id: String in world._physical_pads:
		var pad := world._physical_pads[id] as MeshInstance3D
		var radius: float = (pad.mesh as TorusMesh).outer_radius
		var at := LabelBubble.plane_point(pad.global_position)
		marks["pad " + id] = Rect2(at - Vector2(radius, radius * 0.8), Vector2(radius * 2.0, radius * 1.6))
	_check(world.scenery_backstop <= 0.0, "%s: the shared placement already clears the harbour's scenery (the backstop climbed %.2f m)" % [label, world.scenery_backstop])
	var ids: Array = world._journey_switches.keys()
	for i in range(ids.size()):
		var rect: Rect2 = world._journey_switches[ids[i]].bubble.plane_rect()
		var body := Rect2(rect.position, rect.size - Vector2(0, LabelBubble.TAIL))
		_check(_bubble_cover(world, ids[i]) <= JourneyWorld.SPIRIT_COVER + 0.001, "%s: the %s bubble clears every spirit" % [label, ids[i]])
		for name: String in marks:
			if name == "knob " + str(ids[i]) or name == "wheel " + str(ids[i]): continue
			var mark: Rect2 = marks[name]
			var share := body.intersection(mark).get_area() / mark.get_area()
			_check(share <= SCENERY_SHARE, "%s: the %s bubble leaves %s in view (covers %.2f)" % [label, ids[i], name, share])
		for j in range(i + 1, ids.size()):
			_check(not rect.intersects(world._journey_switches[ids[j]].bubble.plane_rect()), "%s: the %s and %s bubbles stay apart" % [label, ids[i], ids[j]])

## The most of any gauge, wheel, knob or pad a bubble may cover: the journey
## worlds' share over a spirit.
const SCENERY_SHARE := 0.10

## The largest share of a spirit's box (with its badge) that a selector's
## bubble covers, as the journey lift measures it: on the view plane, from
## where the snapshot puts each spirit.
func _bubble_cover(world: Node3D, id: String) -> float:
	var rect: Rect2 = world._journey_switches[id].bubble.plane_rect()
	var worst := 0.0
	for slot: String in world.actors:
		var actor: Node3D = world.actors[slot]
		if not actor.visible or not world.actor_targets.has(slot): continue
		var at: Vector3 = (actor.get_parent() as Node3D).global_transform * (world.actor_targets[slot] as Vector3)
		var feet := LabelBubble.plane_point(at)
		var top := LabelBubble.plane_point(at + Vector3(0, JourneyWorld.SPIRIT_TOP, 0))
		var spirit := Rect2(feet.x - JourneyWorld.SPIRIT_HALF_WIDTH, top.y, JourneyWorld.SPIRIT_HALF_WIDTH * 2.0, feet.y - top.y)
		worst = maxf(worst, rect.intersection(spirit).get_area() / spirit.get_area())
	return worst

func _dressing(level: Dictionary) -> void:
	var data := Dressing.for_key(KEY)
	# The follow camera is every physical world's (test_scrolling_camera).
	_check(data.get("look", "") == "dusk", "The harbour is dressed at dusk")
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
		_check(mapped.cues == ["seed_landed", "valve_turned", "valve_turned"] and mapped.sources[1] != mapped.sources[2], "The spout lands with a thud and each valve turns with its own cue identity")

## While the second spirit waits for its friend's memory (memory_wait.gd), the
## harbour camera follows the memory, as every chapter's does; otherwise it
## follows the live spirit.
func _memory_camera(level: Dictionary) -> void:
	var checkpoint := JourneyCatalog.initial_checkpoint(level)
	var world := _world(level, 0, checkpoint)
	var state: Dictionary = _sim(level, "set-the-tide", checkpoint).snapshot()
	state.active_slot = "p1"
	world.present(state, true)
	world.actors.p0.position = Vector3(2.0, 0.0, -3.0)
	world.actors.p1.position = Vector3(-3.0, 0.0, 3.0)
	var live: Vector3 = world._camera_center()
	world.show_memory_wait("p1", "p0", true)
	var waiting: Vector3 = world._camera_center()
	world.end_memory_wait("p1")
	_check(is_equal_approx(live.x, -3.0) and is_equal_approx(waiting.x, 2.0) and is_equal_approx(waiting.z, -3.0), "The harbour camera follows the memory while the spirit waits, and the live spirit otherwise")
	_check(is_equal_approx(world._camera_center().x, -3.0), "After the wait the camera follows the live spirit again")
	world.free()

## Without the descriptor's "stand_spots" a pad keeps the shared plain look
## (a dark disc and a ring centred on its radius): the spots are this
## chapter's own.
func _plain_pads(level: Dictionary) -> void:
	var world: Node3D = World.new()
	var descriptor: Dictionary = ChapterIndex.data(KEY).duplicate(true)
	descriptor.stand_spots = false
	world.descriptor_override = descriptor
	root.add_child(world)
	world.reduced_motion = true
	world.set_process(false)
	world.load_level(level)
	world.show_stage(level.stages[0])
	_check(world._stand_spots.is_empty() and world.terrain.find_children("StandSpot*", "", true, false).is_empty(), "Without stand_spots no pad wears a stand spot")
	for pad: Dictionary in level.stages[0].pressure_pads:
		var ring := (world._physical_pads[pad.id] as MeshInstance3D).mesh as TorusMesh
		_check(ring != null and is_equal_approx(ring.outer_radius, float(pad.radius_cm) / 100.0 + 0.025), "Without stand_spots a pad keeps its plain ring: " + str(pad.id))
	world.queue_free()
	await process_frame

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
		for rect: Rect2 in _water_rects(body):
			for island: Dictionary in level.islands:
				var r: Array = island.rect_cm
				if rect.grow(-0.01).intersects(Rect2(Vector2(float(r[0]), float(r[1])) / 100.0, Vector2(float(r[2] - r[0]), float(r[3] - r[1])) / 100.0)): return false
	return true

## The way each triangle of a mesh turns against its normal: 1, -1 or both.
func _windings(mesh: Mesh) -> Dictionary:
	var arrays := mesh.surface_get_arrays(0)
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var order := PackedInt32Array(range(points.size()))
	if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array: order = arrays[Mesh.ARRAY_INDEX]
	var signs: Dictionary = {}
	for i in range(0, order.size(), 3):
		var a := points[order[i]]
		signs[signf((a - points[order[i + 2]]).cross(a - points[order[i + 1]]).dot(normals[order[i]]))] = true
	return signs

## Where a body's water stands, seen from above (metres): each upward face of
## its surface mesh.
func _water_rects(body: Node3D) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for child: MeshInstance3D in body.get_children():
		var arrays := child.mesh.surface_get_arrays(0)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for i in range(0, points.size(), 3):
			if normals[i].y < 0.99: continue
			var rect := Rect2(Vector2(points[i].x, points[i].z), Vector2.ZERO)
			for k in range(1, 3): rect = rect.expand(Vector2(points[i + k].x, points[i + k].z))
			rects.append(rect)
	return rects

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
