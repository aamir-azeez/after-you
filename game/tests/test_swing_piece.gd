extends SceneTree
## The swinging bucket (core/physical/swings.gd, rules 20) on the shared
## journey engine, on the-wishing-well@2's Go On Ahead through the real engine:
## - the shapes: the level and its blocks are sound, a swing counts as a new
##   piece, and a lane off the level, a beat with no time hanging back or an
##   unknown outcome is named;
## - the beat: one counter a tick from the stage's start, a creak warn_ticks
##   before each sweep and the sweep itself, the same every beat, each pass
##   the other way;
## - a hit: a pip on the plank is knocked off only on a sweep tick and only
##   where the bucket is passing, into the sky (no water under the plank: the
##   shared knock-off rule), with the shared fall;
## - the drawn bucket: built by the swing piece from the same beat, its middle
##   is over the lane on exactly the sweep ticks, over a pip exactly when the
##   simulation knocks it off, and low enough to hit it; a knocked pip is
##   shoved past the lane's edge the bucket heads for, and falls from there
##   (kit/drowning.gd), never straight down through the plank;
## - the brake: held, it parks the bucket at the top of its next swing out of
##   the lane, held mid-swing too, a parked bucket never knocks anyone, and
##   letting go always gives the full warning;
## - the world: a stage with a swing saves and hashes its counter, a carry-over
##   turn starts from it, a stage without one saves exactly as before.
const Registry = preload("res://services/chapter_registry.gd")
const Swings = preload("res://core/physical/swings.gd")
const PiecesRules = preload("res://core/physical/pieces_rules.gd")
const StageBlocks = preload("res://core/blocks/stage_blocks.gd")
const Catalog = preload("res://core/journey/the_wishing_well_v2_catalog.gd")
const Journey = preload("res://core/journey/stage_catalog.gd")
const Runtime = preload("res://core/physical/runtime.gd")
const SwingPiece = preload("res://presentation/kit/pieces/swing.gd")
const Drowning = preload("res://presentation/kit/drowning.gd")
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
	_drawn()
	_fall()
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
		if step == 45: _check(snap.swings[ID] == {"phase": 45, "pass": 0, "held": false}, "The screen reads where the beat is: %s" % [snap.swings])
		if step == 100: _check(snap.swings[ID] == {"phase": 10, "pass": 0, "held": false}, "Its rest still finishes the pass before: %s" % [snap.swings])
		if step == 135: _check(snap.swings[ID] == {"phase": 45, "pass": 1, "held": false}, "The next pass goes the other way: %s" % [snap.swings])
	_check(_count(sim) == 180, "Unbraked, the counter goes up once a tick: %d" % _count(sim))
	_check(creaks == [30, 120] and sweeps == [60, 150], "It creaks warn_ticks before each sweep, every beat: %s, %s" % [creaks, sweeps])
	_check(Swings.resting(swing, 0) and Swings.warning(swing, 30) and Swings.sweeping(swing, 60) and Swings.resting(swing, 90), "A beat hangs back, warns, then sweeps")

func _hit() -> void:
	var sim := _first()
	_place(sim, sim.active_slot, PLANK)
	for step in range(59): sim.step({})
	_check(not sim.finished and sim._drowned.is_empty(), "Hanging back or creaking, the bucket knocks nobody off the plank")
	var snap: Dictionary = sim.step({})
	var knocked: Dictionary = snap.get("drowned", {})
	_check(sim.finished and str(knocked.get("slot", "")) == sim.active_slot and str(knocked.get("swing", "")) == ID and "knocked:" + ID in snap.events and "fell:" + sim.active_slot in snap.events, "On its first sweep tick it knocks the pip on the plank's near half off: %s" % [knocked])
	_check(knocked.get("fell", false) and knocked.get("sky", false) and sim.commit_reason() == Runtime.FELL_YOU, "With no water under the plank it falls into the sky, as any knock-off there does: %s" % [knocked])
	# On the far half it is struck only once the bucket gets there.
	var far := _first()
	_place(far, far.active_slot, {"x": 200, "z": 248, "height": 0, "surface_id": "garden-plank"})
	var struck := -1
	for step in range(1, 91):
		far.step({})
		if far.finished:
			struck = step
			break
	var pip: Dictionary = far._players[far.active_slot]
	var expected := range(60, 90).filter(func(count: int) -> bool: return Swings.struck(swing, count, pip))
	_check(not expected.is_empty() and struck == expected[0] and struck > 60, "On the far half of the plank it is struck later in the sweep, where the bucket is: tick %d" % struck)
	# Off the bucket's stretch of the plank, or beside it, the sweep passes by.
	for spot: Dictionary in [{"x": 100, "z": 220, "height": 0, "surface_id": "garden"}, {"x": 155, "z": 220, "height": 0, "surface_id": "garden-plank"}]:
		var beside := _first()
		_place(beside, beside.active_slot, spot)
		for step in range(200): beside.step({})
		_check(not beside.finished, "Where the bucket never passes, the sweep passes by: %s" % [spot])

## The swing piece drawn from the simulation's own beat, tick by tick, over
## two passes: the bucket's middle is over the lane exactly on the sweep
## ticks, over a pip exactly when Swings.struck knocks it off, and low enough
## to hit it there.
func _drawn() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var piece: RefCounted = SwingPiece.build("crane_bucket", swing, 0.0, 0.0, holder)
	var lane: Array = swing.lane.rect_cm
	var wrong: Array = []
	var off: Array = []
	for count in range(0, 2 * int(swing.period_ticks) + 5):
		piece.set_beat(Swings.view(swing, count, false), true)
		var at: Vector3 = piece.bucket_point() * 100.0
		var over := at.z > float(lane[1]) and at.z < float(lane[3]) and absf(at.x - 200.0) < 1.0
		if over != Swings.sweeping(swing, count): off.append(count)
		if not Swings.sweeping(swing, count): continue
		if at.y > 80.0: wrong.append("%d high %.0f" % [count, at.y])
		for z in range(190, 252, 6):
			var spot := {"x": 200, "z": z, "surface_id": "garden-plank"}
			var gap := absf(at.z - float(z))
			if Swings.struck(swing, count, spot) and gap > 32.5: wrong.append("%d struck %d away" % [count, gap])
			if not Swings.struck(swing, count, spot) and gap < 31.5: wrong.append("%d passes %d over" % [count, gap])
	_check(off.is_empty(), "The drawn bucket is over the lane on exactly the sweep ticks: off on %s" % [off])
	_check(wrong.is_empty(), "On each sweep tick it is over and low enough to hit exactly the pips the simulation knocks off: %s" % [wrong])
	# Parked by the brake it hangs still at the top of its swing, off the lane.
	var parked := Swings.view(swing, 29, true)
	piece.set_beat(parked, true)
	var still: Vector3 = piece.bucket_point()
	for frame in range(30): piece.advance(1.0 / 60.0)
	_check(parked.held and piece.bucket_point().is_equal_approx(still) and not piece.moving() and still.z * 100.0 < float(lane[1]), "Held, it waits still at the top of its swing, off the lane")
	# Between snapshots it runs on smoothly at the tick rate, never far ahead.
	piece.set_beat(Swings.view(swing, 61, false), true)
	var before: Vector3 = piece.bucket_point()
	piece.advance(1.0 / 60.0)
	var moved: float = piece.bucket_point().distance_to(before)
	_check(moved > 0.0 and moved < 0.05, "Between snapshots it moves on a little each frame: %.3f m" % moved)
	# A knocked pip is shoved past the edge the bucket heads for.
	piece.set_beat(Swings.view(swing, 60, false), true)
	var out: Vector3 = piece.shove(Vector3(2.0, 0.0, 2.2))
	piece.set_beat(Swings.view(swing, 150, false), true)
	var back: Vector3 = piece.shove(Vector3(2.0, 0.0, 2.2))
	_check(out.z > float(lane[3]) / 100.0 + 0.2 and back.z < float(lane[1]) / 100.0 - 0.2 and is_equal_approx(out.x, 2.0), "A knocked pip is shoved past the lane's edge the bucket heads for: %s, %s" % [out, back])
	holder.free()

## The shared fall with a shove (kit/drowning.gd): the pip goes over the edge
## to where it is shoved first, tipping that way, and only then drops, so it
## never falls straight down through the plank.
func _fall() -> void:
	var world := FallWorld.new()
	root.add_child(world)
	var top := Vector3(2.0, 0.0, 2.2)
	var shoved := Vector3(2.0, 0.0, 2.82)
	world.actor_targets["p0"] = top
	var kit: RefCounted = Drowning.new(world)
	kit.show({"slot": "p0", "route": "garden-plank", "fell": true, "sky": true}, shoved)
	var dropped_on_plank := false
	var reached := false
	var tipped := false
	for frame in range(int(Drowning.SHOVE * 60.0) + 40):
		kit.advance(1.0 / 60.0)
		var at: Vector3 = (world.actors.p0 as Node3D).position
		if at.y < top.y - 0.05 and at.z < 2.52: dropped_on_plank = true
		if kit._age >= Drowning.SHOVE and not reached: reached = absf(at.z - shoved.z) < 0.08
		if (world.actors.p0 as Node3D).rotation.x > 0.3: tipped = true
	_check(reached and tipped and not dropped_on_plank, "Knocked off, the pip is shoved over the edge, tipping that way, and drops only past it")
	world.free()

## The least a world gives the fall kit: its pip, targets and terrain.
class FallWorld extends Node3D:
	var actors := {}
	var actor_targets := {}
	var reduced_motion := false
	var camera_focus := ""
	var terrain: Node3D
	func _init() -> void:
		terrain = Node3D.new()
		add_child(terrain)
		actors["p0"] = FallPip.new()
		terrain.add_child(actors.p0)
	func sphere(radius: float, color: Color, at: Vector3, parent: Node3D) -> MeshInstance3D:
		var ball := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = radius
		ball.mesh = mesh
		ball.position = at
		var look := StandardMaterial3D.new()
		look.albedo_color = color
		ball.material_override = look
		parent.add_child(ball)
		return ball

class FallPip extends Node3D:
	func pose() -> StringName: return &"rest"
	func set_pose(_pose: StringName, _params: Dictionary, _now: bool) -> void: pass
	func set_expression(_face: Variant, _now: bool) -> void: pass

func _brake() -> void:
	# Held from the start: it swings up out of the lane and parks at the top,
	# and nobody on the plank is hurt.
	var sim := _first()
	_place(sim, sim.memory_slot, BRAKE)
	_place(sim, sim.active_slot, PLANK)
	var events: Array = []
	for step in range(300): events.append_array(sim.step({}).events)
	_check(_count(sim) == 29 and Swings.parked(swing, 29) and not sim.finished and not events.any(func(event: String) -> bool: return event.begins_with("swing")), "Braked, it parks at the top of its swing and the plank is safe: count %d" % _count(sim))
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
	_check(creak == 1 and sweep == 31, "Let go, it creaks and swings in through the full warning, and only then sweeps: %d, %d" % [creak, sweep])
	# Held mid-swing: it finishes the swing and parks at the top of the next.
	var late := _first()
	for step in range(70): late.step({})
	_place(late, late.memory_slot, BRAKE)
	for step in range(60): late.step({})
	_check(_count(late) == 119 and Swings.phase(swing, 119) == 29 and late.snapshot().swings[ID].held, "Braked mid-swing, it parks at the top of its next swing: count %d" % _count(late))

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
