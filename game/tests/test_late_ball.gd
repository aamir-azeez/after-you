extends SceneTree
## Native Rolling Home deadline witness. Uses recorded inputs, never state injection.
const Physical = preload("res://core/cooperative/simulation.gd")
const Catalog = preload("res://core/cooperative/stage_catalog.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const REACTION_TICKS := 90
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_late_ball_case()
	print("LATE BALL: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _late_ball_case() -> void:
	var level := Catalog.definition("rolling-home")
	var checkpoint := _first_pair(level)
	if checkpoint.is_empty(): return
	var a := Physical.new()
	if not _check(a.reset(level, "bring-it-home", checkpoint, {}, "a", 8), "Second stage uses a genuine native version8 prefix"): return
	var source_frames := Physical.expand_recording_inputs(_fixture("bring-it-home-a"))
	var latest := mini(a.duration_limit(), a.receiver_deadline() - a.source_budget_ticks() - 1)
	if not _check(latest >= source_frames.size() and latest < a.duration_limit(), "The route has a reachable latest acceptance tick before A expires"): return
	# Delay the whole source route. The offer itself, not merely Save, is late.
	_wait_until(a, latest - source_frames.size())
	_play(a, source_frames)
	if not _check(a.error.is_empty() and a.tick == latest and a.can_commit(), "A's real lever, push and offer route reaches its latest accepted tick"): return
	var first := a.export_recording()
	var first_digest := Canonical.digest(first)
	var source_state := a.snapshot()
	var offer_tick := int(source_state.offer_tick)
	_check(offer_tick == latest - 1, "The accepted offer occurs on A's last recorded input")
	_check(source_state.props["round-ball"].status == "offered", "A actually leaves the ball for B")
	var handoff: Dictionary = level.stages[1].handoff
	var offered: Dictionary = source_state.props["round-ball"]
	_check(int(offered.x) == int(handoff.position_cm[0]) and int(offered.z) == int(handoff.position_cm[1]) and offered.surface_id == handoff.surface_id, "The late source offers at the real authored handoff marker")
	var first_check := Physical.verify_recording(level, first, checkpoint)
	if not _check(first_check.valid and first_check.get("snapshot", {}).get("can_commit", false), "The latest accepted A independently replays as viable"): return
	# Retain the accepted dictionary before probing the rejected next boundary.
	a.step({})
	_check(a.tick == latest + 1 and not a.can_commit(), "One later idle tick crosses the actual source acceptance boundary")
	var too_late := a.export_recording()
	var rejected := Physical.new()
	_check(not rejected.reset(level, "bring-it-home", checkpoint, too_late, "b", 8), "A receiver cannot begin from the one-tick-too-late source")
	_check(Canonical.digest(first) == first_digest, "Boundary probing leaves the accepted source dictionary unchanged")
	print("LATE BALL BOUNDARY: ", JSON.stringify({"budget": a.source_budget_ticks(), "latest_accepted_a": latest, "offer_tick": offer_tick, "rejected_next_tick": a.tick}))

	var receiver_frames := Physical.expand_recording_inputs(_fixture("bring-it-home-b"))
	var claim_index := -1
	for index: int in range(receiver_frames.size()):
		if bool(receiver_frames[index].get("interact", false)):
			claim_index = index
			break
	if not _check(claim_index > 0, "The receiver witness contains its actual claim action"): return
	# The published witness approaches the handoff, waits, then claims. Reuse
	# its approach and post-claim route while replacing only its waiting time.
	var approach_end := 0
	while approach_end < claim_index:
		var input: Dictionary = receiver_frames[approach_end]
		if float(input.get("move_x", 0.0)) == 0.0 and float(input.get("move_z", 0.0)) == 0.0: break
		approach_end += 1
	if not _check(approach_end > 0 and approach_end < claim_index, "The receiver approach is separated from its waiting interval"): return
	var b := Physical.new()
	if not _check(b.reset(level, "bring-it-home", checkpoint, first, "b", 8), "B accepts the preserved latest viable source"): return
	_play(b, receiver_frames.slice(0, approach_end))
	var arrival: Dictionary = b.snapshot().players[b.active_slot]
	_check(int(arrival.x) == 208 and int(arrival.z) == 0, "B reaches the authored approach beside the handoff before waiting")
	var reaction_end := int(first.duration_ticks) + REACTION_TICKS
	_wait_until(b, reaction_end)
	if not _check(not b.finished and b.tick == reaction_end and b.tick - offer_tick >= REACTION_TICKS, "B spends three real seconds reacting after the latest recorded handoff"): return
	var waiting := b.snapshot()
	_check(waiting.props["round-ball"].status == "offered", "The offered ball remains available throughout the reaction interval")
	_check(int(waiting.props["round-ball"].x) == int(offered.x) and int(waiting.props["round-ball"].z) == int(offered.z) and waiting.props["round-ball"].surface_id == offered.surface_id, "B observes the same offered ball at the actual handoff marker")
	var action := b.context_action()
	if not _check(action.id == "claim" and bool(action.enabled), "B can explicitly claim from the real waiting position"): return
	_play(b, receiver_frames.slice(claim_index))
	print("LATE BALL RESULT: ", JSON.stringify({"reaction_end": reaction_end, "receiver_tick": b.tick, "receiver_complete": b.complete, "receiver_limit": b.duration_limit(), "ball": b.snapshot().props["round-ball"]}))
	if not _check(b.error.is_empty() and b.complete and b.tick <= b.duration_limit(), "B claims, pulls the route lever and rolls home after the reaction interval"): return
	_check(b.tick > Physical.MAX_TICKS, "The completed ball route actually uses receiver grace beyond the old deadline")
	var final_state := b.snapshot()
	var final_ball: Dictionary = final_state.props["round-ball"]
	var goal: Dictionary = level.stages[1].goal
	_check(final_ball.status == "fitted" and int(final_ball.x) == int(goal.position_cm[0]) and int(final_ball.z) == int(goal.position_cm[1]) and final_ball.surface_id == goal.surface_id, "The same ball finishes snapped to the authored home cradle")
	var accepted_pose: Dictionary = source_state.players[a.first_player_slot]
	var replayed_pose: Dictionary = final_state.players[a.first_player_slot]
	_check(int(accepted_pose.x) == int(replayed_pose.x) and int(accepted_pose.z) == int(replayed_pose.z) and int(accepted_pose.height) == int(replayed_pose.height) and accepted_pose.surface_id == replayed_pose.surface_id, "Receiver grace preserves A's accepted final pose")
	var second := b.export_recording()
	var receiver_check := Physical.verify_recording(level, second, checkpoint, first)
	_check(receiver_check.valid and receiver_check.get("snapshot", {}).get("complete", false), "The full delayed B recording independently replays")
	var derived := Physical.derive_checkpoint(level, checkpoint, first, second)
	_check(derived.valid, "The latest A and delayed B derive the real second-stage checkpoint")
	if derived.valid:
		_check(Physical.verify_checkpoint(level, derived.checkpoint).valid and int(derived.checkpoint.stage_index) == 2 and str(derived.checkpoint.next_stage_id).is_empty(), "The completed recursive proof verifies both native pairs")
	_check(Canonical.digest(first) == first_digest, "B playback and checkpoint verification never change accepted A evidence")
	print("LATE BALL TIMING: ", JSON.stringify({"budget": a.source_budget_ticks(), "latest_accepted_a": latest, "offer_tick": offer_tick, "reaction_end": reaction_end, "receiver_complete": b.tick, "receiver_limit": b.duration_limit()}))

func _first_pair(level: Dictionary) -> Dictionary:
	var start := Catalog.initial_checkpoint(level)
	var a := Physical.new()
	if not _check(a.reset(level, "weight-of-a-friend", start, {}, "a", 8), "First native pair starts under version8"): return {}
	_play(a, Physical.expand_recording_inputs(_fixture("weight-of-a-friend-a")))
	if not _check(a.error.is_empty() and a.can_commit(), "Original first-stage source inputs remain viable under version8"): return {}
	var first := a.export_recording()
	var b := Physical.new()
	if not _check(b.reset(level, "weight-of-a-friend", start, first, "b", 8), "First-stage receiver admits actual source evidence"): return {}
	_play(b, Physical.expand_recording_inputs(_fixture("weight-of-a-friend-b")))
	if not _check(b.error.is_empty() and b.complete, "First-stage receiver inputs finish the native puzzle"): return {}
	var derived := Physical.derive_checkpoint(level, start, first, b.export_recording())
	if not _check(derived.valid, "Stage2 starts from a verified version8 checkpoint"): return {}
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

func _check(value: bool, label: String) -> bool:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
	return value
