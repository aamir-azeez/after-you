extends SceneTree
## The fog cover's cleared fog (kit/fog_cover.gd) comes only from the stage's
## recorded history (kit/turn_paths.gd), so every way of showing a turn shows
## the same, on Fog Marsh's witness routes (Catch the Pipsport's turns):
## - an earlier turn read from its kept memory trace, the same turn simulated
##   again (no trace kept) and the squares kept on disk (a restart) are the same,
##   and a turn with no inputs or from another stage is left out;
## - the history holds both starts, every earlier turn's path and the lantern
##   the second turn lit, and nothing of the turn being played;
## - a cover built again mid-turn paints the same mask as the one that watched
##   every tick, and going back to tick 0 (a retry) paints the history's mask
##   again at once, whatever the turn had opened;
## - the next turn paints only what it added, and then shows what a cover
##   built on its history shows; a new view keeps the old mask on screen
##   until the new one is whole;
## - the turn being played opens more as its pip walks.
const Witness = preload("res://tests/fog_marsh_witness.gd")
const Registry = preload("res://services/chapter_registry.gd")
const TurnPaths = preload("res://presentation/kit/turn_paths.gd")
const FogCover = preload("res://presentation/kit/fog_cover.gd")
const MemoryTrace = preload("res://core/physical/memory_trace.gd")
const PathsStore = preload("res://services/turn_paths_store.gd")
const KEY := "fog-marsh@1"
const STAGE := 1
## The lantern stands on a raised floor (m), so a new view moves where it is seen.
const LANTERN_LIFT := 1.2

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + message)
		print("FAIL: " + message)

func _run() -> void:
	var evidence: Dictionary = Witness.new().chapter()
	_check(evidence.error.is_empty(), "the witness routes play: " + str(evidence.error))
	if evidence.error.is_empty(): _paths(evidence)
	print("FOG REVEAL: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _sim(evidence: Dictionary, turn: int) -> RefCounted:
	var level: Dictionary = evidence.definition
	var turns: Array = evidence.pairs[STAGE].turns
	var sim: RefCounted = Registry.simulation_script(KEY).new()
	var ok := Registry.reset_simulation(sim, KEY, level, level.stages[STAGE].id, evidence.checkpoints[STAGE], turns[turn - 2], "b", {}, turns.slice(0, turn - 2))
	_check(ok, "turn %d starts: %s" % [turn, sim.error])
	return sim

func _paths(evidence: Dictionary) -> void:
	var level: Dictionary = evidence.definition
	var turns: Array = evidence.pairs[STAGE].turns
	_check(turns.size() >= 3, "Catch the Pipsport takes three turns")
	var sim := _sim(evidence, 3)
	TurnPaths.forget()
	var kept := TurnPaths.of(sim, turns[1], [turns[0]])
	TurnPaths.forget()
	MemoryTrace.enabled = false
	var again := TurnPaths.of(sim, turns[1], [turns[0]])
	MemoryTrace.enabled = true
	_check(kept.points.size() > 300 and kept.points == again.points, "a kept trace and the turn simulated again give the same squares (%d, %d)" % [kept.points.size() / 3, again.points.size() / 3])
	_check(kept.levers == again.levers and kept.levers.has("north-lantern") and kept.levers.has("boards-lever"), "and the same lit levers: %s" % [kept.levers.keys()])
	var folder := "user://fog-reveal-%d" % Time.get_ticks_usec()
	PathsStore.attach(folder)
	TurnPaths.forget()
	TurnPaths.of(sim, turns[1], [turns[0]])
	TurnPaths.forget()
	MemoryTrace.enabled = false
	var restarted := TurnPaths.of(sim, turns[1], [turns[0]])
	MemoryTrace.enabled = true
	PathsStore.detach()
	_check(restarted.points == kept.points and restarted.levers == kept.levers and DirAccess.get_files_at(folder).size() == 2, "after a restart the kept files give the same, one file a turn")
	for name: String in DirAccess.get_files_at(folder): DirAccess.remove_absolute(folder.path_join(name))
	DirAccess.remove_absolute(folder)
	var stripped: Dictionary = turns[1].duplicate()
	stripped.erase("packed")
	stripped.erase("actions")
	var odd := TurnPaths.of(sim, stripped, [evidence.pairs[0].turns[1]])
	_check(odd.points.size() <= 6 and odd.levers.is_empty(), "a turn with no inputs or from another stage is left out: only the starts")
	var first := TurnPaths.of(sim, {}, [])
	_check(first.points.size() in [3, 6] and first.levers.is_empty(), "a stage's first turn has only the starts")
	# The second turn, played live over the first.
	var paths := TurnPaths.new()
	paths.set_history(TurnPaths.of(sim, turns[0], []))
	var holder := Node3D.new()
	root.add_child(holder)
	var lanterns := {}
	for lever: Dictionary in level.stages[STAGE].levers:
		if str(lever.id) == "north-lantern": lanterns[lever.id] = Vector3(float(lever.position_cm[0]) / 100.0, LANTERN_LIFT, float(lever.position_cm[1]) / 100.0)
	var watching: RefCounted = FogCover.build("fog", level.islands, [], lanterns, holder)
	_check(watching != null, "the fog look has a cover")
	if watching == null:
		holder.free()
		return
	watching.show_paths(paths)
	var clock := _settle(watching, 0.0)
	var history_mask: PackedByteArray = watching.mask_bytes().duplicate()
	var history_stamps: int = watching.stamp_count()
	var live := _sim(evidence, 2)
	var inputs: Array = live.expand_recording_inputs(turns[1])
	var half := inputs.size() / 2
	for index in range(half):
		var state: Dictionary = live.step(inputs[index])
		watching.paths_changed(paths.note(state))
		clock += 1.0 / 30.0
		watching.advance(1.0 / 30.0, clock)
	for _frame in range(200):
		clock += 0.1
		watching.advance(0.1, clock)
	_check(watching.stamp_count() > history_stamps, "the turn being played opens more as its pip walks (%d stamps, %d before)" % [watching.stamp_count(), history_stamps])
	var built: RefCounted = FogCover.build("fog", level.islands, [], lanterns, holder)
	built.show_paths(paths)
	_settle(built, clock)
	_check(built.mask_bytes() == watching.mask_bytes(), "a cover built again mid-turn paints the same mask as the one that watched every tick")
	watching.paths_changed(paths.note(_sim(evidence, 2).snapshot()))
	_check(watching.mask_bytes() == history_mask and paths.live_points.is_empty(), "back at tick 0 (a retry) the mask is the history's again, at once")
	_check(built.mask_bytes() != history_mask, "and the walked turn had opened more than the history")
	# The whole turn walked, then the next turn starts over its new history.
	var replayed := _sim(evidence, 2)
	for input: Dictionary in replayed.expand_recording_inputs(turns[1]):
		watching.paths_changed(paths.note(replayed.step(input)))
		clock += 1.0 / 30.0
		watching.advance(1.0 / 30.0, clock)
	clock = _settle(watching, clock)
	paths.set_history(kept)
	watching.show_paths(paths)
	var started := clock
	clock = _settle(watching, clock)
	var fresh: RefCounted = FogCover.build("fog", level.islands, [], lanterns, holder)
	fresh.show_paths(paths)
	var fresh_frames := roundi((_settle(fresh, clock) - clock) * 60.0)
	var turn_frames := roundi((clock - started) * 60.0)
	_check(watching.mask_bytes() == fresh.mask_bytes() and watching.stamp_count() == fresh.stamp_count(), "a new turn's cover shows the same as one built on its history (%d stamps, %d)" % [watching.stamp_count(), fresh.stamp_count()])
	_check(turn_frames < fresh_frames, "painting only what the turn added (%d frames, %d for the whole)" % [turn_frames, fresh_frames])
	# A new view paints a second mask and shows it once it is whole.
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	holder.add_child(camera)
	camera.look_at_from_position(Vector3(-8, 10, 4), Vector3.ZERO)
	camera.make_current()
	var shown: PackedByteArray = watching.mask_bytes().duplicate()
	clock += 1.0 / 60.0
	watching.advance(1.0 / 60.0, clock)
	_check(watching.painting() and watching.mask_bytes() == shown, "a new view keeps the old mask on screen while the new one paints")
	_settle(watching, clock)
	var viewed: RefCounted = FogCover.build("fog", level.islands, [], lanterns, holder)
	viewed.show_paths(paths)
	_settle(viewed, clock)
	var moved := 0
	for index in range(shown.size()): moved += int(watching.mask_bytes()[index] != shown[index])
	_check(moved > 0, "the new view moves what is seen above the lowest floor (%d texels)" % moved)
	_check(watching.mask_bytes() == viewed.mask_bytes(), "then shows the same as a cover built under that view")
	holder.free()

## Advances `cover` frame by frame until it owes no paint.
func _settle(cover: RefCounted, clock: float) -> float:
	var frames := 0
	while cover.painting() and frames < 3000:
		clock += 1.0 / 60.0
		cover.advance(1.0 / 60.0, clock)
		frames += 1
	_check(not cover.painting(), "the cover's paint finishes within bounded frames (%d)" % frames)
	return clock
