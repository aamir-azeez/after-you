extends SceneTree
## A pip carrying something at a crossing that needs both hands ("hands",
## core/physical/carried_items.gd) on the witness level
## (tests/carried_items_level.gd: dock --ladder--> loft), from the real
## engine's snapshots into the journey world:
## - carrying, near the ladder's foot, the foot shows the two hands sign
##   (kit/hands_signs.gd), and only then (a two-way ladder has one at each
##   end, a one-way rope ladder at its foot only);
## - stepping onto the ladder carrying, it drops the item (the engine's
##   "dropped"; tests/test_carried_items.gd plays the rule and its replays):
##   the pipsport lands at the foot, the pip is startled where it stands
##   (kit/drowning.gd, the shared outcome path), the turn ends with the shared
##   ending card's "dropped" kind and its line names the item and the
##   crossing in the world's words, the sound map thuds, and the sign goes;
## - empty-handed the pip climbs onto the loft and no sign ever shows;
## - the line's words: each kind of crossing, the friend's and the memory's.
const World = preload("res://presentation/journey_world.gd")
const Simulation = preload("res://core/journey/simulation.gd")
const Level = preload("res://tests/carried_items_level.gd")
const TurnEndings = preload("res://presentation/turn_endings.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const ChapterSoundMap = preload("res://services/chapter_sound_map.gd")
const SpiritLook = preload("res://presentation/spirit_look.gd")
const HandsSigns = preload("res://presentation/kit/hands_signs.gd")
var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var level := Level.definition()
	var world: Node3D = World.new()
	world.descriptor_override = {"piece_styles": {"pipsport": "pipsport"}}
	root.add_child(world)
	world.reduced_motion = true
	world.set_process(false)
	await world.load_level(level)
	var signs: RefCounted = world.hands_signs
	_check(signs.signs.size() == 2 and signs.signs.all(func(entry: Dictionary) -> bool: return entry.route == "ladder") and int(signs.signs[0].end.height) == 0 and int(signs.signs[1].end.height) == 48 and signs.shown().is_empty(), "The two-way ladder gets a hidden sign at each end: %s" % [signs.signs])
	_check(HandsSigns.feet({"id": "rope", "rect_cm": [0, 0, 64, 100], "axis": "z", "from_height_cm": 0, "to_height_cm": 80, "one_way": "up"}).size() == 1, "A one-way rope ladder has a sign at its foot only")
	_check(world._bubbles.has(signs.signs[0].bubble), "The sign is one of the world's bubbles, placed and bobbed with them")
	_check(world.hands_crossing("ladder") == "ladder", "The witness ladder is a ladder")
	_carrying(level, world)
	_empty_handed(level, world)
	_words()
	world.queue_free()
	await process_frame
	print("HANDS FULL: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## Fetches the pipsport from the post box, waits by the ladder, then walks onto it.
func _carrying(level: Dictionary, world: Node3D) -> void:
	var sim := _sim(level, world)
	_walk(sim, world, [-350, 60])
	_tick(sim, world, {})
	_tick(sim, world, {"interact": true})
	_check(str(sim.snapshot().players.p0.get("carrying", "")) == "pipsport", "p0 picks up the pipsport")
	_check(world.hands_signs.shown().is_empty(), "Far from the ladder, no sign shows")
	_walk(sim, world, [-130, 0])
	_check(world.hands_signs.shown() == ["ladder"] and not sim.finished, "Carrying, by the ladder's foot, the two hands sign shows")
	var piece: RefCounted = world._item_pieces.pipsport
	var p0: Node3D = world.actors.p0
	_check(piece.holder == p0, "The pipsport is still over the pip's head")
	var shown := {}
	for index in range(20):
		shown = _tick(sim, world, {"move_x": 1.0})
		if sim.finished: break
	_check(sim.finished and str(shown.drowned.get("dropped", "")) == "pipsport" and str(shown.players.p0.surface_id) == "ladder", "Walking onto the ladder carrying, the pip drops the pipsport and the turn ends: %s" % [shown.get("drowned", {})])
	var foot: Vector3 = world._at({"position_cm": [-100, 0], "surface_id": "dock"})
	_check(piece.holder == null and piece.root.get_parent() == world.terrain and piece.root.position.is_equal_approx(foot) and not p0.carrying_seed, "The pipsport lands at the ladder's foot, off the pip's head")
	_check(world.drowning.slot == "p0" and world.drowning._dropped and p0.expression() == SpiritLook.SURPRISED and world.camera_focus == "p0", "The pip is startled where it stands, through the shared outcome kit, the camera on it")
	_check(world.hands_signs.shown().is_empty(), "Its hands empty, the sign goes")
	var ending := TurnEndings.of(shown, false, world)
	_check(ending.get("kind") == "dropped" and ending.rows == TurnEndings.KINDS.drowned.rows and ending.slot == "p0", "The turn ends on the shared ending card as a drop, with the same buttons: %s" % [ending])
	_check(ending.get("line") == "You dropped the pipsport. It's hard to hold onto it on a ladder.", "The card says what dropped where: %s" % ending.get("line"))
	_check(TurnEndings.line_parts(str(ending.line)) == ["You dropped the pipsport.", "It's hard to hold onto it on a ladder."], "Its title splits after the first sentence")
	var cues := ChapterSoundMap.cues("the-falls@1", {"role": "a", "first_player_slot": "p0", "events": ["dropped:p0"], "players": {}}, {})
	_check(cues.cues == ["seed_landed"] and cues.sources == ["dropped:p0|dropped:p0"], "A drop lands with a thud from the pip: %s" % [cues])
	# A retry (a snapshot with no drop) puts the outcome away.
	world.present(_sim(level, world).snapshot(), true)
	_check(world.drowning.slot.is_empty() and p0.expression() != SpiritLook.SURPRISED, "A fresh start puts the startled face away")

## From the start, empty-handed, straight east up the ladder.
func _empty_handed(level: Dictionary, world: Node3D) -> void:
	var sim := _sim(level, world)
	var seen := false
	for index in range(50):
		_tick(sim, world, {"move_x": 1.0})
		if not world.hands_signs.shown().is_empty(): seen = true
	var at: Dictionary = sim.snapshot().players.p0
	_check(not seen and not sim.finished, "Empty-handed, no sign ever shows and nothing ends the turn")
	_check(str(at.surface_id) == "loft" and int(at.height) == 48, "Empty-handed, the pip climbs onto the loft: %s" % [at])

func _words() -> void:
	_check(PlayerCopy.dropped_line(true, false, "pipsport", "rope_ladder") == "You dropped the pipsport. It's hard to hold onto it on a rope ladder.", "A rope ladder is named as one")
	_check(PlayerCopy.dropped_line(false, false, "seed", "rope_bridge") == "Your friend dropped the seed. It's hard to hold onto it on a rope bridge.", "The friend's drop on a rope bridge")
	_check(PlayerCopy.dropped_line(false, true, "handle", "wheel") == "Your memory dropped the handle. It's hard to hold onto it on a wheel.", "In solo play the memory dropped it, on the wheel")
	_check(PlayerCopy.dropped_line(true, false, "tea-pot", "") == "You dropped the tea pot. It's hard to hold onto it on a ladder.", "An unnamed item shows as itself and an unknown crossing as a ladder")

func _sim(level: Dictionary, world: Node3D) -> RefCounted:
	var sim := Simulation.new()
	sim.simulation_version = int(level.simulation_version)
	sim._reset_trusted(level, "hand-up", Level.initial_checkpoint(level), {}, "a")
	world.present(sim.snapshot(), true)
	return sim

func _tick(sim: RefCounted, world: Node3D, input: Dictionary) -> Dictionary:
	var shown: Dictionary = sim.step(input)
	world.present(shown, true)
	return shown

func _walk(sim: RefCounted, world: Node3D, target: Array) -> void:
	for axis: String in ["x", "z"]:
		for _step in range(300):
			var distance := int(target[0 if axis == "x" else 1]) - int(sim._players[sim.active_slot][axis])
			if absi(distance) <= 1 or sim.finished: break
			_tick(sim, world, {"move_" + axis: clampf(float(distance) / 8.0, -1.0, 1.0)})

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
		print("FAIL: " + message)
