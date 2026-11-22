extends SceneTree
## The swinging bucket (core/physical/swings.gd, rules 20) on the shared
## journey engine, on the-wishing-well@2's Go On Ahead through the real engine:
## - the shapes: the level and its blocks are sound, a swing counts as a new
##   piece, and a lane off the level, a beat with no time hanging back or an
##   unknown outcome is named;
## - the beat: one counter a tick from the stage's start, a creak warn_ticks
##   before each sweep and the sweep itself, the same every beat;
## - a hit: a pip on the plank is knocked into the stream only on a sweep tick,
##   with the shared drown;
## - the brake: held while the bucket hangs back it parks it at once, held
##   mid-swing it parks it the next time it swings back, a parked bucket never
##   knocks anyone, and letting go always gives the full warning;
## - the world: a stage with a swing saves and hashes its counter, a carry-over
##   turn starts from it, a stage without one saves exactly as before.
const Registry = preload("res://services/chapter_registry.gd")
const Swings = preload("res://core/physical/swings.gd")
const PiecesRules = preload("res://core/physical/pieces_rules.gd")
const StageBlocks = preload("res://core/blocks/stage_blocks.gd")
const Catalog = preload("res://core/journey/the_wishing_well_v2_catalog.gd")
const Journey = preload("res://core/journey/stage_catalog.gd")
const KEY := "the-wishing-well@2"
const STAGE := "go-on-ahead"
const ID := "well-crane"
const PLANK := {"x": 200, "z": 220, "height": 0, "surface_id": "garden-plank"}
const BRAKE := {"x": 200, "z": -72, "height": 160, "surface_id": "cliff"}
const AWAY := {"x": 0, "z": -100, "height": 160, "surface_id": "cliff"}
var checks := 0
var failures := 0
var level: Dictionary
var swing: Dictionary

func _initialize() -> void: _run.call_deferred()

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _run() -> void:
	level = Registry.definition(KEY)
	swing = level.stages[0].swings[0]
	_shapes()
	_beat()
	_hit()
	_brake()
	_world()
	print("SWING PIECE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _shapes() -> void:
	_check(PiecesRules.problems(level).is_empty(), "The level's pieces are sound: %s" % [PiecesRules.problems(level)])
	_check(StageBlocks.problems(Catalog.source()).is_empty(), "The catalog's blocks are sound: %s" % [StageBlocks.problems(Catalog.source())])
	_check("swings on %s" % STAGE in PiecesRules.uses(level), "A stage's swing counts as a new piece")
	_check(int(swing.period_ticks) == 90 and int(swing.sweep_ticks) == 30 and int(swing.warn_ticks) == 30 and swing.brake == {"pad_id": "brake-board"}, "The block writes a 3 s beat, 1 s across after 1 s of warning, braked by its board: %s" % [swing])
	var broken := level.duplicate(true)
	var bad: Dictionary = broken.stages[0].swings[0]
	bad.lane.surface_id = "nowhere"
	bad.warn_ticks = 60
	bad.outcome = "flew"
	var found := " ".join(Swings.problems(broken))
	_check("lane" in found and "hanging back" in found and "unknown outcome" in found, "A lane off the level, a beat with no rest and an unknown outcome are named: " + found)
	var source := Catalog.source()
	source.stages[0].blocks[4].brake = "no-such-board"
	_check(" ".join(StageBlocks.problems(source)).contains("brakes on no-such-board"), "A brake on a board the stage does not place is named")

## A first turn of Go On Ahead from the level's start, the other pip standing.
func _first() -> RefCounted:
	var sim: RefCounted = Registry.simulation_script(KEY).new()
	_check(Registry.reset_simulation(sim, KEY, level, STAGE, Journey.initial_checkpoint(level), {}, "a"), "The stage's first turn starts: " + str(sim.error))
	return sim

func _place(sim: RefCounted, slot: String, at: Dictionary) -> void:
	var player: Dictionary = sim._players[slot].duplicate()
	player.merge(at, true)
	sim._players[slot] = player

func _count(sim: RefCounted) -> int:
	return int(sim._swing_counts[ID])

func _beat() -> void:
	var sim := _first()
	var creaks: Array = []
	var sweeps: Array = []
	for step in range(1, 181):
		var snap: Dictionary = sim.step({})
		if "swing_creak:" + ID in snap.events: creaks.append(step)
		if "swing:" + ID in snap.events: sweeps.append(step)
		if step == 45: _check(snap.swings[ID] == {"phase": 45, "held": false}, "The screen reads where the beat is: %s" % [snap.swings])
	_check(_count(sim) == 180, "Unbraked, the counter goes up once a tick: %d" % _count(sim))
	_check(creaks == [30, 120] and sweeps == [60, 150], "It creaks warn_ticks before each sweep, every beat: %s, %s" % [creaks, sweeps])
	_check(Swings.resting(swing, 0) and Swings.warning(swing, 30) and Swings.sweeping(swing, 60) and Swings.resting(swing, 90), "A beat hangs back, warns, then sweeps")

func _hit() -> void:
	var sim := _first()
	_place(sim, sim.active_slot, PLANK)
	for step in range(59): sim.step({})
	_check(not sim.finished and sim._drowned.is_empty(), "Hanging back or creaking, the bucket knocks nobody off the plank")
	var snap: Dictionary = sim.step({})
	_check(sim.finished and str(snap.drowned.get("slot", "")) == sim.active_slot and str(snap.drowned.get("swing", "")) == ID and "knocked:" + ID in snap.events and "drowned:" + sim.active_slot in snap.events, "On its first sweep tick it knocks the pip on the plank into the stream: %s" % [snap.get("drowned", {})])
	# Off the lane the sweep passes by.
	var beside := _first()
	_place(beside, beside.active_slot, {"x": 100, "z": 220, "height": 0, "surface_id": "garden"})
	for step in range(200): beside.step({})
	_check(not beside.finished, "Beside the plank, the sweep passes by")

func _brake() -> void:
	# Held while it hangs back: parked at once, and nobody on the plank is hurt.
	var sim := _first()
	_place(sim, sim.memory_slot, BRAKE)
	_place(sim, sim.active_slot, PLANK)
	var events: Array = []
	for step in range(300): events.append_array(sim.step({}).events)
	_check(_count(sim) == 0 and not sim.finished and not events.any(func(event: String) -> bool: return event.begins_with("swing")), "Braked while it hangs back, it stays parked and the plank is safe: count %d" % _count(sim))
	_check(sim.snapshot().swings[ID].held, "The screen shows it held")
	# Let go: the full warning, then the sweep.
	_place(sim, sim.memory_slot, AWAY)
	_place(sim, sim.active_slot, AWAY)
	var creak := -1
	var sweep := -1
	for step in range(1, 91):
		var snap: Dictionary = sim.step({})
		if "swing_creak:" + ID in snap.events: creak = step
		if "swing:" + ID in snap.events: sweep = step
	_check(creak == 30 and sweep == 60, "Let go, it hangs back, creaks and only then sweeps: %d, %d" % [creak, sweep])
	# Held mid-swing: it finishes the swing and parks as it swings back.
	var late := _first()
	for step in range(70): late.step({})
	_place(late, late.memory_slot, BRAKE)
	for step in range(40): late.step({})
	_check(_count(late) == 90 and Swings.phase(swing, 90) == 0 and late.snapshot().swings[ID].held, "Braked mid-swing, it parks the next time it swings back: count %d" % _count(late))

func _world() -> void:
	var sim := _first()
	for step in range(17): sim.step({})
	var world: Dictionary = sim.save_world()
	_check(world.get("swings", {}) == {ID: 17}, "A stage with a swing saves its counter in the world: %s" % [world.get("swings")])
	var hash_before: String = sim.state_hash()
	var other := _first()
	world.swings[ID] = 50
	other.load_world(world, 0)
	_check(_count(other) == 50, "A turn starting from a world takes its counter over")
	other.step({})
	_check(_count(other) == 51 and other.state_hash() != hash_before, "The counter is in the state hash")
	var back: RefCounted = Registry.simulation_script(KEY).new()
	var checkpoint := Journey.initial_checkpoint(level)
	checkpoint.next_stage_id = "back-for-you"
	checkpoint.stage_index = 1
	checkpoint.checkpoint_hash = Journey.checkpoint_hash(checkpoint)
	back.simulation_version = int(level.simulation_version)
	back._reset_trusted(level, "back-for-you", checkpoint, {}, "a")
	_check(not back.save_world().has("swings") and not back._state_body().has("swings"), "A stage without a swing saves and hashes its world as before")
