extends SceneTree
## Finish on arrival under carry-over turns (claude-20261011/carry-over-turns/
## design.md, "Owner change"): a stage ends the first moment both pips are at
## the lit goal, whoever got there first, the rest of the friend's replay
## dropped. Each stage is played turn by turn through the real Solo journal
## (services/relay_journey.gd) and the real room coordinator against the
## server double (tests/open_turns_server.gd), from their own live turns:
## - the live pip arrives where the friend's replay already stands: the stage
##   ends that tick, the live pip short of where its walk was going;
## - the live pip is at the lit goal first: it waits (objective_done), and the
##   stage ends the tick the friend's replay arrives, before the replay is over;
## - both pips at the goal with its light out (the lantern not lit, the
##   pipsport not carried) never finish, as the goal asks;
## - the closing turn is taken, its checkpoint derives and verifies, and the
##   completion scene sets the closing turn up again over its passes and
##   replays it complete (Journey.final_scene_job_for, CheckpointPairs
##   replay_closing), on The Falls, Fog Marsh and First Steps@2.
## The turns are the witness routes (tests/routes) with waits added to set
## who arrives first.
const Registry = preload("res://services/chapter_registry.gd")
const Witness = preload("res://tests/chapter_witness.gd")
const Walk = preload("res://tests/cooperative_witness.gd")
const Journey = preload("res://services/relay_journey.gd")
const Coordinator = preload("res://services/relay_room_coordinator.gd")
const Server = preload("res://tests/open_turns_server.gd")
const OpenTurns = preload("res://core/physical/open_turns.gd")
const OpenTurnStore = preload("res://services/open_turn_store.gd")
const CheckpointPairs = preload("res://services/checkpoint_pairs.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const HOST := "AAAAAAAAAAAAAAAAAAAAAA"
const GUEST := "BBBBBBBBBBBBBBBBBBBBBB"
const ROOM := "CCCCCCCCCCCCCCCCCCCCCC"
const ROOT := "user://open-turns-arrival-test"
## Stage 1 of each level with waits put into its witness turns ([turn, step,
## ticks]: before that step), and how its closing turn arrives: "live_first",
## "friend_first" (its last `tail` steps walk the live pip to the goal), "dark"
## (its last `tail` steps are dropped: both stand at the goal with its light
## out) or "" (the witness as it is).
const CASES := [
	{"chapter": "the-falls@1", "arrive": "friend_first", "waits": [[3, 8, 600]], "tail": 2},
	{"chapter": "the-falls@1", "arrive": "live_first", "waits": [[2, 4, 900]]},
	{"chapter": "fog-marsh@1", "arrive": "friend_first", "waits": [[2, 4, 300]], "tail": 2},
	{"chapter": "fog-marsh@1", "arrive": "live_first", "waits": [[1, 5, 900]]},
	{"chapter": "fog-marsh@1", "arrive": "dark", "drop": [[2, 2]]},
	{"chapter": "first-steps@2", "arrive": "", "stages": 2},
]
var checks := 0
var failures := 0
var directory := ""

class Phone:
	extends RefCounted
	var player := ""
	var disk: Dictionary = {}
	var keys := 0
	var room: RefCounted
	func _init(player_id: String, server: RefCounted) -> void:
		player = player_id
		room = Coordinator.new(Callable(server, "transport"), load_store, save_store, identity, key)
		room.turn_store_root = ROOT
	func identity() -> Dictionary:
		return {"ready": true, "player_id": player, "epoch": 1}
	func load_store(scope: String) -> Dictionary:
		return {"ok": true, "found": disk.has(scope), "value": disk.get(scope, {}).duplicate(true)}
	func save_store(scope: String, value: Dictionary) -> Dictionary:
		disk[scope] = JSON.parse_string(JSON.stringify(value))
		return {"ok": true}
	func key() -> String:
		keys += 1
		return "%s-operation-%04d" % [player.left(4), keys]

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	directory = "user://open-turns-arrival-" + Crypto.new().generate_random_bytes(6).hex_encode()
	DirAccess.make_dir_recursive_absolute(directory)
	for index in range(CASES.size()):
		for flow: String in ["solo", "room"]:
			var started := Time.get_ticks_msec()
			await _case(CASES[index], flow, index)
			print("%s %s %s: %d ms" % [CASES[index].chapter, CASES[index].arrive, flow, Time.get_ticks_msec() - started])
	print("OPEN TURNS ARRIVAL: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## The case's turns, stage by stage: the witness's with its waits put in and its drops taken out.
static func _routes(spec: Dictionary) -> Array:
	var routes: Dictionary = Witness.routes(str(spec.chapter))
	var level := Registry.definition(str(spec.chapter))
	var stages: Array = []
	for index in range(int(spec.get("stages", 1))):
		var turns: Array = Witness._turn_steps(routes.get(level.stages[index].id)).duplicate(true)
		if index == 0:
			for wait: Array in spec.get("waits", []): turns[wait[0]].insert(wait[1], ["wait", wait[2]])
			for drop: Array in spec.get("drop", []): turns[drop[0]].remove_at(drop[1])
		stages.append(turns)
	return stages

func _case(spec: Dictionary, flow: String, index: int) -> void:
	var chapter := str(spec.chapter)
	var label := "%s %s (%s)" % [chapter, spec.arrive if not str(spec.arrive).is_empty() else "witness", flow]
	var level := Registry.definition(chapter)
	var engine: Script = Registry.simulation_script(chapter)
	var journey: Journey = null
	var server: RefCounted = null
	var phones: Array = []
	if flow == "solo":
		journey = Journey.new(directory.path_join("solo-%d.json" % index), null, chapter)
		journey.load_data()
	else:
		for player: String in [HOST, GUEST]: OpenTurnStore.erase_owner(player, ROOT)
		server = Server.new(chapter, ROOM, HOST, GUEST)
		phones = [Phone.new(HOST, server), Phone.new(GUEST, server)]
		for phone: Phone in phones: phone.room.bind_room(ROOM)
	var start := Registry.initial_checkpoint(chapter)
	var stages := _routes(spec)
	var holder: RefCounted = journey
	for stage_index in range(stages.size()):
		var turns: Array = stages[stage_index]
		var played: Array = []
		for turn_index in range(turns.size()):
			var closing := turn_index == turns.size() - 1
			var phone: Phone = null
			if flow == "room":
				for each: Phone in phones:
					if await each.room.refresh() and each.room.my_turn(): phone = each
				if not _check(phone != null, "%s: someone has turn %d" % [label, turn_index + 1]): return
			var live: RefCounted = journey.create_live_simulation(false) if flow == "solo" else phone.room.create_live_simulation(false)
			if not _check(live != null, "%s: turn %d starts (%s)" % [label, turn_index + 1, journey.last_error if flow == "solo" else phone.room.last_code]): return
			var steps: Array = turns[turn_index]
			var arrive := str(spec.arrive) if closing and stage_index == 0 else ""
			if arrive == "friend_first":
				var tail := int(spec.tail)
				Witness._play(live, steps.slice(0, steps.size() - tail))
				_check(not live.finished and live._at_goal(live.memory_slot) and not live._at_goal(live.active_slot), "%s: the friend's replay stands at the lit goal before the live pip comes (%s)" % [label, Witness._where(live)])
				var target: Array = steps[-1][1]
				Witness._play(live, steps.slice(steps.size() - tail))
				var player: Dictionary = live.snapshot().players[live.active_slot]
				_check(live.complete and live.finished and live._at_goal(live.active_slot) and Vector2i(player.x, player.z) != Vector2i(int(target[0]), int(target[1])), "%s: the stage ends the moment the live pip arrives, short of its walk's end (%s)" % [label, Witness._where(live)])
			elif arrive == "live_first":
				Witness._play(live, steps)
				_check(not live.finished and live.snapshot().objective_done and not live._at_goal(live.memory_slot) and live.tick < live.replay_ticks(), "%s: the live pip waits at the lit goal first, the friend's replay still coming (%s)" % [label, Witness._where(live)])
				while not live.finished and live.tick < live.duration_limit(): live.step({})
				_check(live.complete and live._at_goal(live.memory_slot) and live.tick < live.replay_ticks(), "%s: the stage ends the tick the friend's replay arrives, before it is over (tick %d of %d)" % [label, live.tick, live.replay_ticks()])
			elif arrive == "dark":
				Witness._play(live, steps)
				while not live.finished and live.tick < live.replay_ticks() + 60: live.step({})
				_check(not live.complete and live._near_entity(live._players[live.active_slot], live.stage.goal) and live._near_entity(live._players[live.memory_slot], live.stage.goal) and not live.snapshot().objective_done, "%s: both pips at the goal with its light out never finish (%s)" % [label, Witness._where(live)])
				return
			else:
				Witness._play(live, steps)
				if closing:
					while not live.finished and live.tick < live.duration_limit(): live.step({})
			if turn_index == 0:
				# A first turn ends whenever its pip likes; it has nothing to pass.
				if not _check(live.can_commit(), "%s: turn 1 may end (%s)" % [label, Witness._where(live)]): return
			elif not closing:
				while not live.finished and not live.can_pass() and live.tick < live.duration_limit(): live.step({})
				live.pass_turn()
				if not _check(live.passed, "%s: turn %d passes (%s)" % [label, turn_index + 1, Witness._where(live)]): return
			elif not _check(live.complete, "%s: the closing turn completes the stage (%s)" % [label, Witness._where(live)]): return
			var recording: Dictionary = live.export_recording()
			played.append(recording)
			var taken: bool = journey.accept_recording(recording) if flow == "solo" else await phone.room.commit(recording)
			if not _check(taken, "%s: turn %d is taken (%s)" % [label, turn_index + 1, journey.last_error if flow == "solo" else phone.room.last_code]): return
			if flow == "room": holder = phone.room
		start = _closed(label, flow, chapter, level, engine, start, played, holder, stage_index == stages.size() - 1 and stages.size() == level.stages.size())
		if start.is_empty(): return
	if flow == "room":
		for player: String in [HOST, GUEST]: OpenTurnStore.erase_owner(player, ROOT)

## After a stage closes: its checkpoint derives from its turns and verifies,
## the flow holds it, and the completion scene's two ways (the worker's job
## and the rebuild without it) set the closing turn up and replay it complete.
## The checkpoint after the stage, or {}.
## `holder`: the Solo journal or the room's coordinator that took the turns.
func _closed(label: String, flow: String, chapter: String, level: Dictionary, engine: Script, previous: Dictionary, turns: Array, holder: RefCounted, last_stage: bool) -> Dictionary:
	var pair := {"a": turns[0], "b": turns[-1], "passes": turns.slice(1, turns.size() - 1)}
	var derived: Dictionary = CheckpointPairs.derive(engine, level, previous, JSON.parse_string(JSON.stringify(pair)))
	if not _check(derived.get("valid", false), "%s: the stage's checkpoint derives from its %d turns (%s)" % [label, turns.size(), derived.get("error", "")]): return {}
	var checkpoint: Dictionary = derived.checkpoint
	_check(engine.verify_checkpoint(level, checkpoint).get("valid", false), "%s: the derived checkpoint verifies" % label)
	var held: Dictionary = holder.checkpoint()
	_check(str(held.get("checkpoint_hash", "")) == str(checkpoint.checkpoint_hash), "%s: the %s holds that checkpoint" % [label, "journal" if flow == "solo" else "room"])
	var rebuilt: RefCounted = engine.new()
	var replayed := CheckpointPairs.replay_closing(rebuilt, engine, chapter, level, previous, pair)
	_check(replayed.get("valid", false) and rebuilt.complete and rebuilt.export_recording().recording_hash == turns[-1].recording_hash, "%s: the completion scene rebuilt without its worker replays the closing turn complete (%s)" % [label, replayed.get("error", "")])
	var full: Dictionary = holder.checkpoint() if flow == "solo" else holder.full_checkpoint()
	var pairs: Array = holder.pairs() if flow == "solo" else CheckpointPairs.pairs(chapter, full, 0)
	var job: Dictionary = Journey.final_scene_job_for(chapter, engine, level, full, pairs[-1] if not pairs.is_empty() else {})
	if last_stage and flow == "solo": _check(holder.chapter_complete() and Canonical.same(holder.final_scene_job(), job), "%s: the finished journal's completion scene is that job" % label)
	var built: Dictionary = Journey.build_final_scene(job) if not job.is_empty() else {}
	_check(built.get("ok", false) and built.simulation.complete and built.simulation.export_recording().recording_hash == turns[-1].recording_hash, "%s: the completion scene's worker sets the closing turn up over its passes and replays it complete" % label)
	return checkpoint

func _check(condition: bool, message: String) -> bool:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
		print("FAIL: " + message)
	return condition
