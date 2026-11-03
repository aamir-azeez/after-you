extends RefCounted
## Where the raced run's player stood on each tick of one turn, worked out once
## per stage and role from the run's recordings (race-picker BUILD-NOTES: a
## precomputed track, never a second simulation stepped beside the live one).
##
## A turn on stage k in role a or b races the raced run's own stage k turn of
## the same role, re-simulated from that run's own stage set-up (its previous
## checkpoint) and inputs, with its turn a as the memory of a turn b, exactly
## as the shared replay viewer plays it (presentation/shared_replay_view.gd).
## The sim is deterministic at 30 ticks a second, so the track is the same on
## every phone and every try; the live turn reads it by its own tick, so pause,
## backgrounding, retries and fast-forward stay in step for free.
##
## A track is {slot, points, duration_ticks}: `points` holds x, height and z in
## centimetres (the worlds' own units) for ticks 0..duration_ticks, three
## floats a tick. Pure: no nodes, files or requests, so it runs on a worker
## (services/worker_reaper.gd). {} when the run can't be played on this build
## (rules it does not have, a stage or role it lacks): the race goes on with no ghost.
const Registry = preload("res://services/chapter_registry.gd")
## A turn is never longer than this (the longest chapter turn, with room to spare).
const MAX_TICKS := 30 * 60 * 10

## The track of the raced run's `role` turn in `pair` (services/checkpoint_pairs.gd), or {}.
static func build(chapter_key: String, pair: Dictionary, role: String) -> Dictionary:
	if not role in ["a", "b"] or not pair.get(role) is Dictionary or not pair.get("checkpoint") is Dictionary: return {}
	var recording: Dictionary = pair[role]
	var slot := str(recording.get("player_slot", ""))
	var engine: Script = Registry.simulation_script(chapter_key)
	if engine == null or slot.is_empty(): return {}
	var sim: RefCounted = engine.new()
	var start := Registry.previous_checkpoint(chapter_key, pair.checkpoint)
	var prior: Dictionary = pair.a if role == "b" and pair.get("a") is Dictionary else {}
	if not Registry.reset_simulation(sim, chapter_key, Registry.definition(chapter_key), str(recording.get("stage_id", "")), start, prior, role, recording): return {}
	# As every replay plays a turn: with the Forgiving catches its player had (shared_replay_view.gd).
	sim.catch_assistance = bool(recording.get("catch_assistance", true))
	var frames: Array = engine.expand_recording_inputs(recording)
	if frames.is_empty() or frames.size() > MAX_TICKS: return {}
	var points := PackedFloat32Array()
	if not _note(points, sim.snapshot(), slot): return {}
	for input: Variant in frames:
		var state: Dictionary = sim.step(input)
		if not _note(points, state, slot): return {}
		if bool(state.get("finished", false)): break
	return {"slot": slot, "points": points, "duration_ticks": points.size() / 3 - 1}

## Where the track stands at `tick` (centimetres), its last point past the end.
static func point(track: Dictionary, tick: int) -> Vector3:
	var points: PackedFloat32Array = track.get("points", PackedFloat32Array())
	var count := points.size() / 3
	if count == 0: return Vector3.ZERO
	var at := clampi(tick, 0, count - 1) * 3
	return Vector3(points[at], points[at + 1], points[at + 2])

static func _note(points: PackedFloat32Array, state: Dictionary, slot: String) -> bool:
	var players: Variant = state.get("players")
	var player: Variant = players.get(slot) if players is Dictionary else null
	if not player is Dictionary or not _number(player.get("x")) or not _number(player.get("z")): return false
	points.append(float(player.x))
	points.append(float(player.get("height", 0.0)) if _number(player.get("height", 0.0)) else 0.0)
	points.append(float(player.z))
	return true

static func _number(value: Variant) -> bool:
	return value is int or value is float
