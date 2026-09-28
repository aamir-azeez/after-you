extends SceneTree
## Complete Rolling Home witness with the ball offered before A pulls the lever.
const Physical = preload("res://core/cooperative/simulation.gd")
const Catalog = preload("res://core/cooperative/stage_catalog.gd")
const Canonical = preload("res://core/v2/canonical.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_offer_before_lever()
	print("ROLLING OFFER: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _offer_before_lever() -> void:
	var level := Catalog.definition("rolling-home")
	var checkpoint := _first_pair(level)
	if checkpoint.is_empty(): return
	var stage: Dictionary = level.stages[1]
	var lever_id := str(stage.source_policy.lever_id)
	var prop_id := str(stage.source_policy.prop_id)
	var a := Physical.new()
	if not _check(a.reset(level, str(stage.id), checkpoint, {}, "a", 8), "Second A starts from the actual first pair under version8"): return
	var source_frames := Physical.expand_recording_inputs(_fixture("bring-it-home-a"))
	if not _check(source_frames.size() > 4 and bool(source_frames[1].get("interact", false)), "Retained source begins with its known lever tap"): return
	# Keep the original movement, removing only the starting lever interaction.
	_play(a, source_frames.slice(2, source_frames.size() - 2))
	var before := a.snapshot()
	var action := a.context_action()
	if not _check(not bool(before.levers.get(lever_id, false)) and action.id == "offer" and bool(action.enabled), "A can leave the ball at the handoff before pulling the home lever"): return
	_play(a, source_frames.slice(source_frames.size() - 2))
	var offered := a.snapshot()
	var offer_tick := int(offered.offer_tick)
	var handoff: Dictionary = stage.handoff
	var offered_ball: Dictionary = offered.props[prop_id]
	_check(not bool(offered.levers.get(lever_id, false)) and offered_ball.status == "offered", "The actual offer succeeds while the home lever is still off")
	_check(int(offered_ball.x) == int(handoff.position_cm[0]) and int(offered_ball.z) == int(handoff.position_cm[1]) and offered_ball.surface_id == handoff.surface_id, "The offered ball snaps to the authored handoff")
	_check(not a.can_commit(), "A still needs to open the partner's final route before saving")
	# Return via the authored middle bridge and p1's upper lane. This is the
	# same real-input return route already covered by the comfort overlap case.
	for target: Array in [[208,-80],[352,-80],[352,0],[608,0],[608,128],[896,128],[896,96]]:
		if not _move(a, target): return
	_tap(a)
	if not _check(a.error.is_empty() and a.can_commit() and bool(a.snapshot().levers.get(lever_id, false)), "A pulls the lever after leaving the ball and can save a viable turn"): return
	var first := a.export_recording()
	var first_digest := Canonical.digest(first)
	var source_final := a.snapshot()
	var checked_first := Physical.verify_recording(level, first, checkpoint)
	if not _check(checked_first.valid and checked_first.get("snapshot", {}).get("can_commit", false), "The reordered A route independently replays as viable"): return
	_check(int(source_final.offer_tick) == offer_tick and offer_tick < int(first.duration_ticks) - 1, "The accepted recording retains its early offer before the final lever tap")

	var receiver_frames := Physical.expand_recording_inputs(_fixture("bring-it-home-b"))
	var claim_index := -1
	for index: int in range(receiver_frames.size()):
		if bool(receiver_frames[index].get("interact", false)):
			claim_index = index
			break
	if not _check(claim_index > 0, "Retained B inputs contain the claim action"): return
	var approach_end := 0
	while approach_end < claim_index:
		var input: Dictionary = receiver_frames[approach_end]
		if float(input.get("move_x", 0.0)) == 0.0 and float(input.get("move_z", 0.0)) == 0.0: break
		approach_end += 1
	if not _check(approach_end > 0 and approach_end < claim_index, "The original approach is separate from the original wait"): return
	var b := Physical.new()
	if not _check(b.reset(level, str(stage.id), checkpoint, first, "b", 8), "B starts with the exact reordered A recording"): return
	_play(b, receiver_frames.slice(0, approach_end))
	for _tick: int in range(b.duration_limit()):
		if b.finished or not b.error.is_empty() or b.snapshot().props[prop_id].status == "offered": break
		b.step({})
	var waiting := b.snapshot()
	var claim := b.context_action()
	if not _check(not bool(waiting.levers.get(lever_id, false)) and claim.id == "claim" and bool(claim.enabled), "B can take the actual offered ball before A's later lever interaction replays"): return
	b.step(receiver_frames[claim_index])
	var claim_tick := int(b.tick)
	if not _check(b.snapshot().props[prop_id].status == "claimed" and not bool(b.snapshot().levers.get(lever_id, false)), "B's early claim really succeeds while the home lever is still off"): return
	# The ball can be taken immediately. Wait for the independent source to
	# finish opening the final gate, then reuse B's entire remaining input route.
	_wait_until(b, int(first.duration_ticks))
	if not _check(not b.finished and bool(b.snapshot().levers.get(lever_id, false)) and b.snapshot().props[prop_id].status == "claimed", "A's later lever opens without taking the claimed ball back"): return
	_play(b, receiver_frames.slice(claim_index + 1))
	var final_state := b.snapshot()
	print("ROLLING OFFER RESULT: ", JSON.stringify({"offer_tick":offer_tick,"claim_tick":claim_tick,"source_end":first.duration_ticks,"receiver_end":b.tick,"complete":b.complete,"ball":final_state.props[prop_id]}))
	if not _check(b.error.is_empty() and b.complete and b.tick <= b.duration_limit(), "B completes the real home route after claiming before the lever"): return
	var final_ball: Dictionary = final_state.props[prop_id]
	var goal: Dictionary = stage.goal
	_check(final_ball.status == "fitted" and int(final_ball.x) == int(goal.position_cm[0]) and int(final_ball.z) == int(goal.position_cm[1]) and final_ball.surface_id == goal.surface_id, "The same ball finishes in its authored home cradle")
	var source_pose: Dictionary = source_final.players[a.first_player_slot]
	var replayed_pose: Dictionary = final_state.players[a.first_player_slot]
	_check(int(source_pose.x) == int(replayed_pose.x) and int(source_pose.z) == int(replayed_pose.z) and int(source_pose.height) == int(replayed_pose.height) and source_pose.surface_id == replayed_pose.surface_id, "B's route preserves A's accepted final pose")
	var second := b.export_recording()
	var checked_second := Physical.verify_recording(level, second, checkpoint, first)
	_check(checked_second.valid and checked_second.get("snapshot", {}).get("complete", false), "The whole reordered B recording independently replays")
	var derived := Physical.derive_checkpoint(level, checkpoint, first, second)
	if _check(derived.valid, "The reordered pair derives its real final checkpoint"):
		_check(Physical.verify_checkpoint(level, derived.checkpoint).valid and int(derived.checkpoint.stage_index) == 2 and str(derived.checkpoint.next_stage_id).is_empty(), "Both native pairs verify as the completed chapter")
	_check(Canonical.digest(first) == first_digest, "Claim, replay and checkpoint derivation preserve accepted A evidence")

func _first_pair(level: Dictionary) -> Dictionary:
	var start := Catalog.initial_checkpoint(level)
	var a := Physical.new()
	if not _check(a.reset(level, "weight-of-a-friend", start, {}, "a", 8), "First pair starts under version8"): return {}
	_play(a, Physical.expand_recording_inputs(_fixture("weight-of-a-friend-a")))
	if not _check(a.error.is_empty() and a.can_commit(), "Retained first A inputs produce a viable turn"): return {}
	var first := a.export_recording()
	var b := Physical.new()
	if not _check(b.reset(level, "weight-of-a-friend", start, first, "b", 8), "First B accepts real source evidence"): return {}
	_play(b, Physical.expand_recording_inputs(_fixture("weight-of-a-friend-b")))
	if not _check(b.error.is_empty() and b.complete, "Retained first B inputs complete the first puzzle"): return {}
	var derived := Physical.derive_checkpoint(level, start, first, b.export_recording())
	if not _check(derived.valid, "The second stage receives an actual derived version8 checkpoint"): return {}
	return derived.checkpoint

func _fixture(name: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/cooperative/" + name + ".json"))
	_check(parsed is Dictionary, "Retained input fixture loads: " + name)
	return parsed if parsed is Dictionary else {}

func _play(simulation: RefCounted, frames: Array) -> void:
	for input: Dictionary in frames:
		if simulation.finished or not str(simulation.error).is_empty(): return
		simulation.step(input)

func _wait_until(simulation: RefCounted, target: int) -> void:
	for _tick: int in range(maxi(0, target - int(simulation.tick))):
		if simulation.finished or not str(simulation.error).is_empty(): return
		simulation.step({})

func _move(simulation: RefCounted, target: Array) -> bool:
	for axis: String in ["x", "z"]:
		for _tick: int in range(simulation.duration_limit()):
			if simulation.finished or not str(simulation.error).is_empty(): break
			var player: Dictionary = simulation.snapshot().players[simulation.active_slot]
			var distance := int(target[0 if axis == "x" else 1]) - int(player[axis])
			if absi(distance) <= 1: break
			simulation.step({"move_" + axis: clampf(float(distance) / 8.0, -1.0, 1.0)})
	var final_player: Dictionary = simulation.snapshot().players[simulation.active_slot]
	return _check(absi(int(final_player.x) - int(target[0])) <= 1 and absi(int(final_player.z) - int(target[1])) <= 1, "A reaches the next real return-route waypoint")

func _tap(simulation: RefCounted) -> void:
	simulation.step({})
	simulation.step({"interact": true})

func _check(value: bool, label: String) -> bool:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
	return value
