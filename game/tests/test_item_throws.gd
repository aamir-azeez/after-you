extends SceneTree
## Rules 16's throws and solid item spots on the shared journey engine
## (core/physical/carried_items.gd, core/solid_footprint.gd), on first-steps@2's
## second stage through the real engine:
## - the shapes: the level is sound, a throw to no spot or with a short flight
##   is named;
## - a solid spot (the seed pedestal): a pip walking at it stops at its edge
##   from any side, takes the seed from beside it up to reach_cm off the drum
##   and no further, and puts it back from beside; the same spot without
##   "solid" is the plain spot it was;
## - a throw: only from its mark, with the item in hand; the item flies on its
##   arc, nobody can pick it up, the stage cannot complete while it flies, and
##   with nobody at the landing it lands at the landing spot;
## - catches: the live pip catches the friend's replayed throw (the witness's
##   turn 2), and the friend's replay catches a seed still flying at the
##   hand-off (turn 3); on carry-over turns nothing is thrown twice. Every turn
##   replays exactly.
const Registry = preload("res://services/chapter_registry.gd")
const CarriedItems = preload("res://core/physical/carried_items.gd")
const Solid = preload("res://core/solid_footprint.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Witness = preload("res://tests/first_steps_v2_witness.gd")
const Walk = preload("res://tests/cooperative_witness.gd")
const KEY := "first-steps@2"
const STAGE := "a-place-to-grow"
const PEDESTAL := Vector2i(230, -90)
const MARK := [140, -90]
var checks := 0
var failures := 0
var level: Dictionary
var checkpoint: Dictionary

func _initialize() -> void: _run.call_deferred()

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _run() -> void:
	level = Registry.definition(KEY)
	var evidence: Dictionary = Witness.new().chapter()
	_check(evidence.error.is_empty() and evidence.checkpoints.size() == 3, "The witness plays both stages: " + str(evidence.error))
	if evidence.error.is_empty():
		checkpoint = evidence.checkpoints[1]
		_shapes()
		_solid_spot()
		_throw_and_land()
		_catches(evidence.pairs[1].turns)
	print("ITEM THROWS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _shapes() -> void:
	_check(CarriedItems.problems(level).is_empty(), "first-steps@2's items, spots and throws are sound: %s" % [CarriedItems.problems(level)])
	_check("throws on %s" % STAGE in CarriedItems.uses(level), "A stage's throws count as the new pieces")
	var broken := level.duplicate(true)
	broken.stages[1].throws[0].to = "nowhere"
	broken.stages[1].throws[0].flight_ticks = 5
	var found := " ".join(CarriedItems.problems(broken))
	_check("lands at nowhere" in found and "flight_ticks" in found, "A throw to no spot, or one too short to catch, is named: " + found)

## A first turn (p1 first, both at the loft bell).
func _first() -> RefCounted:
	var sim: RefCounted = Registry.simulation_script(KEY).new()
	_check(Registry.reset_simulation(sim, KEY, level, STAGE, checkpoint, {}, "a"), "The stage's first turn starts: " + str(sim.error))
	return sim

func _at(sim: RefCounted) -> Vector2i:
	var player: Dictionary = sim.snapshot().players[sim.active_slot]
	return Vector2i(int(player.x), int(player.z))

func _solid_spot() -> void:
	var spot := CarriedItems.spot(level, "seed-pedestal")
	var keep := int(spot.solid.radius_cm) + CarriedItems.BODY_CM
	var reach := keep + int(spot.solid.reach_cm)
	# Walking straight at the drum from its east side stops at its edge (clear
	# of the other pip, still at the bell, so the press is no hand over).
	var sim := _first()
	Walk.walk(sim, [330, 0])
	Walk.walk(sim, [330, -90])
	Walk.walk(sim, [230, -90])
	_check(_at(sim) == Vector2i(PEDESTAL.x + keep, PEDESTAL.y), "A pip walking at the pedestal stops at its edge: %s" % _at(sim))
	_check(sim.context_action().id == "take", "From the edge, the seed is there to pick up")
	Walk.tap(sim)
	_check(CarriedItems.held_by(sim._mechanisms.items, sim.active_slot) == "seed", "It takes the seed from beside the pedestal")
	Walk.tap(sim)
	_check(str(sim._mechanisms.items.seed.spot) == "seed-pedestal", "Put back from beside, the seed rests on the pedestal again")
	# Every side: the pip stops at the drum, and the reach ends reach_cm off it.
	for side: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		for distance: int in [keep, reach, reach + 1]:
			var at := PEDESTAL + side * distance
			var player := {"x": at.x, "z": at.y, "height": 160, "surface_id": "loft"}
			_check(CarriedItems.can_pick(player, sim._mechanisms.items.seed, level) == (distance <= reach), "From %s, %d cm off the middle, the seed %s" % [side, distance, "is in reach" if distance <= reach else "is out of reach"])
			_check(sim._in_solid(player) == (distance < keep), "From %s, %d cm off the middle, a pip %s" % [side, distance, "may stand" if distance >= keep else "may not stand"])
	var plain := level.duplicate(true)
	plain.item_spots[0].erase("solid")
	var near := {"x": PEDESTAL.x, "z": PEDESTAL.y + 50, "height": 160, "surface_id": "loft"}
	_check(not CarriedItems.can_pick(near, sim._mechanisms.items.seed, plain) and CarriedItems.can_pick({"x": PEDESTAL.x, "z": PEDESTAL.y, "height": 160, "surface_id": "loft"}, sim._mechanisms.items.seed, plain), "Without \"solid\" the spot is the plain one: picked up inside, not from 50 cm")
	_check(Solid.solids(plain.item_spots).is_empty() and Solid.solids(level.item_spots).size() == 1, "Only a spot that says so is solid")

func _throw_and_land() -> void:
	var sim := _first()
	Walk.walk(sim, [230, -40])
	Walk.tap(sim)
	_check(sim.context_action().id != "throw", "Away from its mark there is no throw")
	Walk.walk(sim, [140, -40])
	Walk.walk(sim, MARK)
	_check(sim.context_action().id == "throw", "In the mark with the seed, the action is a throw")
	Walk.tap(sim)
	var thrown: Dictionary = level.stages[1].throws[0]
	var seed: Dictionary = sim._mechanisms.items.seed
	_check(CarriedItems.in_flight(seed) and "item_thrown:seed" in sim.snapshot().events, "Thrown, the seed is in the air")
	var highest := 0
	var landed_at := -1
	for tick in range(int(thrown.flight_ticks) + 2):
		var snap: Dictionary = sim.step({})
		seed = sim._mechanisms.items.seed
		if CarriedItems.in_flight(seed):
			highest = maxi(highest, int(seed.height))
			_check(not CarriedItems.can_pick(snap.players[sim.active_slot], seed, level), "Nobody picks up a seed in the air")
			_check(not sim._may_complete(), "A stage never completes while the seed flies")
		if "item_landed:seed" in snap.events: landed_at = tick
	_check(highest > 160 + CarriedItems.THROW_LIFT_CM, "It flies on an arc over the thrower's head: %d cm" % highest)
	_check(landed_at >= 0 and str(sim._mechanisms.items.seed.spot) == str(thrown.to) and sim._may_complete(), "With nobody at the landing it lands there, and the stage may complete again")

## The witness's turns: the memory throws and the live pip catches (turn 2);
## turn 3 takes over from turn 2's world while the seed is still in the air,
## so the friend's replay makes that catch and nobody throws again (carry-over
## turns: nothing acts twice). Each replays exactly.
func _catches(turns: Array) -> void:
	_check(turns.size() == 3, "The witness's stage takes three turns")
	if turns.size() != 3: return
	for index in [1, 2]:
		var sim: RefCounted = Registry.simulation_script(KEY).new()
		_check(Registry.reset_simulation(sim, KEY, level, STAGE, checkpoint, turns[index - 1], "b", turns[index], turns.slice(0, index - 1)), "Turn %d starts: %s" % [index + 1, sim.error])
		var thrower := ""
		var catcher := ""
		for input: Dictionary in sim.expand_recording_inputs(turns[index]):
			var snap: Dictionary = sim.step(input)
			if "item_thrown:seed" in snap.events: thrower = sim.memory_slot if index == 1 else sim.active_slot
			if "item_caught:seed" in snap.events: catcher = str(sim._mechanisms.items.seed.holder)
		var live := str(sim.active_slot)
		if index == 1: _check(thrower == sim.memory_slot and catcher == live, "Turn 2: the memory throws and the live pip catches (%s, %s)" % [thrower, catcher])
		else: _check(thrower.is_empty() and catcher == sim.memory_slot, "Turn 3: nothing is thrown again, and the friend's replay catches the seed still flying at the hand-off (%s, %s)" % [thrower, catcher])
		_check(Canonical.same(sim.export_recording(), turns[index]), "Turn %d replays exactly" % [index + 1])
