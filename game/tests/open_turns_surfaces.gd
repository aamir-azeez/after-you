extends SceneTree
## Every open level (the registry's, never a hand list), finished from its
## witness route under carry-over turns, then opened again through every
## surface that reads a finished stage's turns. Each level is played once and
## its finished journal reused. A suite runs every SHARDS-th level from SHARD
## and one half of the surfaces (PART): test_open_turns_replays_<n>.gd the
## replay screens, test_open_turns_rooms_<n>.gd the rest, so each fits the CI time.
## - Solo: each stage's replay and the whole level ("Watch all parts") through
##   the real launch path (scan, context, hand-off file, chapter screen) to
##   their end with no error card; try again, resume a saved draft mid-stage
##   and Play my turn again (a pass, then a whole stage) play the turn as it was
##   and keep the same journal; Start over keeps the attempt, which still
##   replays; the save reopens the same (atomic round trip).
## - Records and Home: the keepsakes' check of the journal, a kept hard run
##   (finished, and a slip over a pass watched through the screen), the race
##   ghost's track of each stage's first and closing turn, the board's run (Our
##   run) as the replay viewer unwinds it, and the solo export.
## - Saves: the journal within the solo save cap, the cloud save bundle and its
##   restore through the journal's own check, and the phone backup plan.
## - The stage's last turn (its cap) over with the stage unfinished: Solo and
##   a room end it on the turn ending card (turn_endings.gd), never a dead
##   end; on the first level of each suite the screen's card offers Try again,
##   Redo last turn and Start over, and each works.
## - Reactions: a friend's reaction shows when their turn reaches its tick,
##   while the next turn watches it (at 1x and Fast-forward), beside the live
##   turn after the hand-off, and in the stage's replay.
## - Barrier bumps: the friend's pip bumps on its own slot and turn clock, the
##   same pushes its own turn bumped, whichever pip plays first.
## - Done: a level is marked done only once its last stage's goal is reached.
## - Online: two phones play the level through a room (tests/open_turns_server.gd),
##   each turn handed off as carry-over turns say; before each turn the mover
##   watches the friend's turn up to the hand-off (a later stage's first turn
##   the closing turn whole); a phone left mid-turn reopens on its draft; the
##   other phone watches each stage again from its own copies, its closing turn
##   played back to the same checkpoint, with each pip's photo turn.
const Registry = preload("res://services/chapter_registry.gd")
const Journey = preload("res://services/relay_journey.gd")
const Witness = preload("res://tests/chapter_witness.gd")
const Preview = preload("res://cooperative_preview.gd")
const OpenTurns = preload("res://core/physical/open_turns.gd")
const OpenTurnStore = preload("res://services/open_turn_store.gd")
const Collection = preload("res://services/solo_replay_collection.gd")
const ReplaysFlow = preload("res://presentation/replays_flow.gd")
const SoloReplayLaunch = preload("res://services/solo_replay_launch.gd")
const CheckpointPairs = preload("res://services/checkpoint_pairs.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const AtomicFile = preload("res://services/atomic_file.gd")
const HomeKeepsakes = preload("res://services/home_keepsakes.gd")
const HardMode = preload("res://services/hard_mode.gd")
const Track = preload("res://services/race_ghost_track.gd")
const LeaderboardReplay = preload("res://services/leaderboard_replay.gd")
const BlobCodec = preload("res://services/blob_codec.gd")
const RunExport = preload("res://services/run_export.gd")
const CloudBundle = preload("res://services/platform_games/cloud_save_bundle.gd")
const CloudSources = preload("res://services/platform_games/cloud_save_sources.gd")
const BackupPlan = preload("res://services/backup_plan.gd")
const Coordinator = preload("res://services/relay_room_coordinator.gd")
const Server = preload("res://tests/open_turns_server.gd")
const OnlineSession = preload("res://services/relay_online_session.gd")
const TurnEndings = preload("res://presentation/turn_endings.gd")
const RunReactionStore = preload("res://services/run_reaction_store.gd")
const RunReactionTrack = preload("res://services/run_reaction_track.gd")
const TurnTries = preload("res://services/turn_tries.gd")
const BarrierRefusals = preload("res://presentation/barrier_refusals.gd")
const RouteBarriers = preload("res://presentation/kit/route_barriers.gd")
const HomeKeepsakeCatalog = preload("res://services/home_keepsake_catalog.gd")
const ChapterCompletion = preload("res://presentation/chapter_completion.gd")
const Index = preload("res://content/chapters/index.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const STILL := {"move_x": 0.0, "move_z": 0.0, "interact": false}
## How long an idle first turn stands before it ends.
const IDLE_TICKS := 20
const HOST := "HHHHHHHHHHHHHHHHHHHHHH"
const GUEST := "GGGGGGGGGGGGGGGGGGGGGG"
const ROOM := "RRRRRRRRRRRRRRRRRRRRRR"

var checks := 0
var failures := 0
var directory := ""
var _screens := 0

class Phone:
	extends RefCounted
	var player := ""
	var disk: Dictionary = {}
	var keys := 0
	var room: RefCounted
	var _server: RefCounted
	var _root := ""
	func _init(player_id: String, server: RefCounted, root: String) -> void:
		player = player_id
		_server = server
		_root = root
		reopen()
	## A fresh coordinator on the same disk, as the app opened again.
	func reopen() -> void:
		room = Coordinator.new(Callable(_server, "transport"), load_store, save_store, identity, key)
		room.turn_store_root = _root
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

func _initialize() -> void:
	_run.call_deferred()

## [SHARD, SHARDS, PART] from the suite: its levels, and which half of the
## surfaces it opens ("replays": every replay screen; "rooms": the rest).
func _shard() -> Array:
	var constants: Dictionary = get_script().get_script_constant_map()
	return [int(constants.get("SHARD", 0)), int(constants.get("SHARDS", 1)), str(constants.get("PART", ""))]

func _timed(times: Array[String], label: String, work: Callable) -> void:
	var started := Time.get_ticks_msec()
	await work.call()
	times.append("%s %d" % [label, Time.get_ticks_msec() - started])

func _run() -> void:
	directory = "user://open-turns-surfaces-" + Crypto.new().generate_random_bytes(6).hex_encode()
	DirAccess.make_dir_recursive_absolute(directory)
	var shard := _shard()
	var chapters := open_chapters()
	_check(chapters.size() >= shard[1], "the registry has an open level for every shard (%d)" % chapters.size())
	for index in range(chapters.size()):
		if index % int(shard[1]) != int(shard[0]): continue
		var chapter: String = chapters[index]
		var started := Time.get_ticks_msec()
		var level := _finished(chapter)
		if level.is_empty(): continue
		var times: Array[String] = ["level %d" % (Time.get_ticks_msec() - started)]
		var part := str(shard[2])
		if part in ["", "replays"]:
			await _timed(times, "replays", _solo_replays.bind(level))
			await _timed(times, "start over", _start_over.bind(level))
			await _timed(times, "hard runs", _hard_runs.bind(level))
		if part in ["", "rooms"]:
			await _timed(times, "journal", _journal_flows.bind(level))
			await _timed(times, "records", _records.bind(level))
			await _timed(times, "saves", _saves.bind(level))
			await _timed(times, "online", _online.bind(level))
			await _timed(times, "last turn", _last_turn.bind(level, index / int(shard[1]) == 0))
			await _timed(times, "reactions", _reactions.bind(level))
			await _timed(times, "bumps", _bumps.bind(level))
			await _timed(times, "completion", _completion.bind(level))
		print("%s: %d ms (%s)" % [chapter, Time.get_ticks_msec() - started, ", ".join(times)])
	SoloReplayLaunch.discard()
	OpenTurnStore.erase_owner(HOST, directory)
	OpenTurnStore.erase_owner(GUEST, directory)
	print("OPEN TURNS SURFACES %s %d/%d: %d checks, %d failures" % [str(shard[2]), int(shard[0]) + 1, int(shard[1]), checks, failures])
	quit(1 if failures else 0)

## Every open level the registry has, in its order.
static func open_chapters() -> Array[String]:
	var found: Array[String] = []
	for key: String in Registry.keys():
		if OpenTurns.pinned(Registry.definition(key)): found.append(key)
	return found

# The finished level ---------------------------------------------------------

## The level played once from its witness and saved turn by turn in a Solo
## journal at its own file name: {chapter, stages (each stage's turns),
## checkpoints (before each stage, then the last), path, pairs, final}, or {}.
func _finished(chapter: String) -> Dictionary:
	var played := Witness.play(chapter, Witness.routes(chapter))
	var stages: Array = Registry.definition(chapter).stages
	if not _check(str(played.error).is_empty() and played.pairs.size() == stages.size(), "%s: the witness finishes the level (%s)" % [chapter, played.error]): return {}
	var turns: Array = played.pairs.map(func(pair: Dictionary) -> Array: return pair.turns)
	_check(turns.all(func(stage: Array) -> bool: return stage.size() >= 3 and stage.all(func(turn: Dictionary) -> bool: return turn.has(OpenTurns.HANDOFF_TICK))), chapter + ": every stage is played in carry-over turns, three or more")
	var path := _journal_path(chapter, "finished")
	var journey := _journal(chapter, path)
	for stage: Array in turns:
		for recorded: Dictionary in stage:
			if not _check(journey.accept_recording(recorded), "%s %s: Solo saves the turn (%s)" % [chapter, recorded.get("stage_id"), journey.last_error]): return {}
	if not _check(journey.chapter_complete() and journey.pairs().size() == stages.size(), chapter + ": Solo finishes the level"): return {}
	# The save reopens exactly as written.
	var reopened := _journal(chapter, path)
	_check(not reopened.read_only and reopened.chapter_complete() and Canonical.same(reopened.pairs(), journey.pairs()) and Canonical.same(reopened.checkpoint(), journey.checkpoint()), chapter + ": the finished journal reopens the same (%s)" % reopened.last_error)
	return {"chapter": chapter, "stages": turns, "checkpoints": played.checkpoints, "path": path, "pairs": journey.pairs(), "final": journey.checkpoint()}

## The journal's file at its descriptor's own name (the backup plan reads it), in this run's folder.
func _journal_path(chapter: String, label: String) -> String:
	var name := str(Registry.descriptor(chapter).get("local_path", chapter.validate_filename() + "-journey-v1.json")).get_file()
	var folder := directory.path_join(label)
	DirAccess.make_dir_recursive_absolute(folder)
	return folder.path_join(name)

func _journal(chapter: String, path: String) -> Journey:
	var journey := Journey.new(path, null, chapter)
	journey.load_data()
	return journey

## A copy of the finished journal at `label`.
func _copy(level: Dictionary, label: String) -> String:
	var path := _journal_path(level.chapter, label)
	AtomicFile.write_bytes(path, FileAccess.get_file_as_bytes(level.path))
	return path

## Plays `recorded` on `live` from the tick it stands at, then passes or
## finishes as the turn did: its recording, or {} when it played differently.
static func _play_live(live: RefCounted, recorded: Dictionary, stop_at: int = -1) -> Dictionary:
	if live == null: return {}
	live.catch_assistance = bool(recorded.get("catch_assistance", true))
	var frames: Array = live.get_script().expand_recording_inputs(recorded)
	for index in range(Journey.tick_of(live), frames.size()):
		if live.finished or index == stop_at: break
		live.step(frames[index])
	if stop_at >= 0: return {}
	if recorded.get("completed") == false and recorded.get("role") == "b" and not live.finished: live.pass_turn()
	var played: Dictionary = live.export_recording()
	return played if played.get("recording_hash") == recorded.get("recording_hash") else {}

# Solo replays ---------------------------------------------------------------

## The rows the replay list shows for `path`, from the same read-only scan.
func _rows(chapter: String, path: String, archived: bool) -> Array:
	var service := Collection.new({chapter: path}, path.get_base_dir().path_join("verified.json"))
	if not service.begin_scan(): return []
	var deadline := Time.get_ticks_msec() + 60000
	while service.scan_pending() and Time.get_ticks_msec() < deadline:
		service.advance_scan()
		await process_frame
	var rows: Array = service.items().filter(func(row: Dictionary) -> bool: return row.get("chapter_key") == chapter and bool(row.get("archived", false)) == archived)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.stage_index) < int(b.stage_index))
	return rows

func _solo_replays(level: Dictionary) -> void:
	var chapter: String = level.chapter
	var rows: Array = await _rows(chapter, level.path, false)
	var stages: int = level.stages.size()
	if not _check(rows.size() == stages, "%s: the replay list shows every stage (%d of %d)" % [chapter, rows.size(), stages]): return
	for row: Dictionary in rows:
		_check(ReplaysFlow._solo_turns(row).size() == level.stages[int(row.stage_index)].size(), "%s stage %d: the part's try pills show every turn" % [chapter, int(row.stage_index) + 1])
	for index in range(stages):
		await _watch_solo(chapter, level.path, rows, index, -1, "%s stage %d replay" % [chapter, index + 1])
	# Watch all parts plays on from part to part; on a long level from the part
	# before the last, the same path at half the cost.
	await _watch_solo(chapter, level.path, rows, stages - 1, maxi(0, stages - 2), chapter + " whole-level replay")
	_check(not RunExport.solo_blob(chapter, rows).is_empty(), chapter + ": the attempt exports within its cap")

## Opens the replay of `rows[index]` (from `start` when >= 0) as Watch does.
func _watch_solo(chapter: String, path: String, rows: Array, index: int, start: int, label: String) -> void:
	var context: Dictionary = ReplaysFlow._solo_replay_context_from_rows(chapter, rows, rows[index])
	if not _check(not context.is_empty(), label + ": the context builds"): return
	if start >= 0: context["start_stage_index"] = start
	if not _check(SoloReplayLaunch.write(context), label + ": the hand-off is written"): return
	await _watch_screen(chapter, path, index - (start if start >= 0 else index) + 1, label)

## The chapter screen opened on a replay hand-off (Solo's or a hard run's),
## played to its end as its own tick does: `blooms` stages bloom, no error
## card shows on the way, and the screen leaves once the last one ends.
func _watch_screen(chapter: String, path: String, blooms: int, label: String) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 360)
	root.add_child(viewport)
	var screen := Preview.new()
	screen.chapter_key = chapter
	screen.journey = Journey.new(path, null, chapter)
	screen.settings = {"sound": false, "haptics": false, "reduced_motion": true, "assistance": true, "left_handed": false}
	viewport.add_child(screen)
	screen.set_physics_process(false)
	screen.set_process(false)
	for frame in range(3): await process_frame
	if _check(screen.mode == "replay" and screen._solo_replay_only and not screen._solo_replay_context_error, "%s: the replay opens (mode %s)" % [label, screen.mode]):
		var bloomed := {}
		var steps := 0
		while steps < 400000:
			steps += 1
			if screen.mode == "replay" and screen.running: screen._physics_process(0.0)
			elif screen.mode == "replay" and not screen.running and screen._replay_hold > 0:
				# A turn that does not bloom holds a moment, then ends.
				screen._replay_hold += 1
				screen._replay_ended()
			elif screen.mode == "bloom" and screen._completion_is_replay:
				bloomed[screen.replay_pair_index] = true
				screen._replay_ended()
			else: break
		_check(screen.mode == "leaving" and bloomed.size() == blooms, "%s: plays to its end and leaves, %d of %d stages bloom (mode %s)" % [label, bloomed.size(), blooms, screen.mode])
	viewport.queue_free()
	for frame in range(2): await process_frame

# Solo journal flows ----------------------------------------------------------

## On the last stage: Play my turn again on its first pass, then try again and
## a draft left mid-turn on its third turn (over that pass); then Play my
## turn again on the whole finished stage.
func _journal_flows(level: Dictionary) -> void:
	var chapter: String = level.chapter
	var last: int = level.stages.size() - 1
	var turns: Array = level.stages[last]
	var mid_path := _journal_path(chapter, "mid")
	var mid := _journal(chapter, mid_path)
	var saved := true
	for stage in range(last):
		for recorded: Dictionary in level.stages[stage]: saved = saved and mid.accept_recording(recorded)
	saved = saved and mid.accept_recording(turns[0]) and mid.accept_recording(turns[1])
	if not _check(saved and mid.passes().size() == 1, "%s: a journal stands on the last stage's third turn (%s)" % [chapter, mid.last_error]): return
	# Play my turn again on a pass: the first turn is the memory again.
	var plan: Dictionary = mid.redo_plan()
	if _check(plan.get("kind") == "pass" and mid.begin_replace(plan) and mid.passes().is_empty(), "%s: Play my turn again takes the pass back (%s, %s)" % [chapter, plan.get("kind"), mid.last_error]):
		var again := _play_live(mid.create_live_simulation(false), turns[1])
		_check(not again.is_empty() and mid.accept_recording(again) and mid.passes().size() == 1 and not mid.replacing(), "%s: the pass played again is saved in its place (%s)" % [chapter, mid.last_error])
	var third: Dictionary = turns[2]
	var half := maxi(1, int(third.duration_ticks) / 2)
	# Try again: the turn starts over and plays as it was.
	_play_live(mid.create_live_simulation(false), third, half)
	_check(not _play_live(mid.create_live_simulation(false), third).is_empty(), chapter + ": Try again plays the third turn over the pass as it was")
	# Leave mid-turn: the draft reopens from disk and plays on to the same turn.
	var live: RefCounted = mid.create_live_simulation(false)
	_play_live(live, third, half)
	if not _check(mid.save_live_draft(live), "%s: the mid-turn draft saves (%s)" % [chapter, mid.last_error]): return
	var reopened := _journal(chapter, mid_path)
	_check(not reopened.read_only and reopened.has_draft() and Canonical.same(reopened.playback(), mid.playback()), "%s: the draft reopens with the same hand-off (%s)" % [chapter, reopened.last_error])
	var resumed := _play_live(reopened.create_live_simulation(true), third)
	if not _check(not resumed.is_empty() and reopened.accept_recording(resumed), "%s: the resumed draft plays on to the same turn and saves (%s)" % [chapter, reopened.last_error]): return
	for recorded: Dictionary in turns.slice(3): saved = saved and reopened.accept_recording(recorded)
	_check(saved and reopened.chapter_complete() and Canonical.same(reopened.pairs(), level.pairs), "%s: the level finishes on the same journal (%s)" % [chapter, reopened.last_error])
	# Play my turn again on a finished stage: its turns come back, the closing one is played again.
	var redo := _journal(chapter, _copy(level, "redo"))
	plan = redo.redo_plan()
	if _check(plan.get("kind") == "stage" and redo.begin_replace(plan) and redo.passes().size() == turns.size() - 2, "%s: Play my turn again reopens the last stage at its closing turn (%s, %s)" % [chapter, plan.get("kind"), redo.last_error]):
		var closing := _play_live(redo.create_live_simulation(false), turns[-1])
		_check(not closing.is_empty() and redo.accept_recording(closing) and redo.chapter_complete() and Canonical.same(redo.pairs(), level.pairs), "%s: the closing turn played again finishes the level the same (%s)" % [chapter, redo.last_error])

## Start over keeps the finished attempt in Replays, where it still plays.
func _start_over(level: Dictionary) -> void:
	var chapter: String = level.chapter
	var path := _copy(level, "start-over")
	var journey := _journal(chapter, path)
	if not _check(journey.fork_from_stage(0) and journey.pairs().is_empty(), "%s: Start over (%s)" % [chapter, journey.last_error]): return
	var attempts := journey.archived_attempts()
	_check(attempts.size() == 1 and Canonical.same(journey.archived_pairs(str(attempts[0].get("id", ""))), level.pairs), "%s: the attempt is kept whole (%s)" % [chapter, journey.last_error])
	var rows: Array = await _rows(chapter, path, true)
	if _check(rows.size() == level.stages.size(), "%s: Replays lists the kept attempt (%d parts)" % [chapter, rows.size()]):
		await _watch_solo(chapter, path, rows, rows.size() - 1, -1, chapter + " kept attempt's last stage")
	var plan := BackupPlan.entries(path.get_base_dir())
	var names: Array = plan.map(func(entry: Dictionary) -> String: return str(entry.path))
	_check(names.has(path.get_file()) and names.any(func(name: String) -> bool: return name.begins_with(path.get_file() + ".attempt-")), "%s: the phone backup keeps the journal and the kept attempt" % chapter)

# Records and Home ------------------------------------------------------------

## A kept hard run, finished and slipped: it saves, reads back and is watched.
func _hard_runs(level: Dictionary) -> void:
	var chapter: String = level.chapter
	var last: int = level.stages.size() - 1
	var turns: Array = level.stages[last]
	var finished := HardMode.run_record(chapter, HardMode.SOLO, HardMode.COMPLETE, "", "", level.pairs.size(), "", level.pairs, {})
	var slip := HardMode.kept_slip(turns[2], level.checkpoints[last], turns[1], [turns[0]])
	var failed := HardMode.run_record(chapter, HardMode.SOLO, HardMode.FAILED, "failed_turn", "you", last, "b", level.pairs.slice(0, last), slip)
	var read: Variant = HardMode._parse_runs(HardMode._runs_text(chapter, [finished, failed]), chapter)
	_check(read is Array and read.size() == 2 and Canonical.same(HardMode.watch_pairs(read[0]), level.pairs), chapter + ": a kept hard run saves within its cap and reads back whole")
	if not read is Array or read.size() != 2: return
	var parts := HardMode.watch_pairs(read[1])
	_check(parts.size() == last + 1 and OpenTurns.pair_turns(parts[-1]).size() == 3, chapter + ": the slip is watched over the turns before it")
	HardMode.hand_over({"chapter_key": chapter, "kind": "watch", "run": read[1], "part": last})
	await _watch_screen(chapter, level.path, int(bool(turns[2].get("completed", false))), chapter + " hard run slip")
	HardMode.drop()

func _records(level: Dictionary) -> void:
	var chapter: String = level.chapter
	# Keepsakes: Home's check of the journal places one per finished stage.
	var validator := _journal(chapter, level.path)
	var state: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(level.path)).get("relay", {})
	var checked: Dictionary = HomeKeepsakes._check_state(validator, state, null, false)
	_check(checked.get("valid", false) and state.get("pairs", []).size() == level.stages.size(), "%s: Home's keepsake check takes the finished journal (%s)" % [chapter, checked.get("error", "")])
	# The run a room posts: every stage unwinds from its checkpoint, the board's replay included.
	var pairs := CheckpointPairs.pairs(chapter, level.final, 0)
	_check(pairs.size() == level.stages.size() and range(pairs.size()).all(func(index: int) -> bool: return _hashes(OpenTurns.pair_turns(pairs[index])) == _hashes(level.stages[index])), chapter + ": each stage's turns unwind from the final checkpoint")
	var canonical := JSON.stringify(Canonical.normalized(level.final), "", true, true).to_utf8_buffer()
	var body := Marshalls.raw_to_base64(BlobCodec.encode(canonical))
	var parts := LeaderboardReplay.checkpoint_parts(body, canonical.size(), BlobCodec.digest(canonical), chapter)
	_check(parts.size() == level.stages.size() and BlobCodec.encode(canonical).size() <= LeaderboardReplay.MAX_BODY_BYTES, "%s: the board's run (Our run) unwinds whole and fits the board's replay (%d bytes)" % [chapter, BlobCodec.encode(canonical).size()])
	# The race ghost: each stage's first and closing turn as the raced run played them.
	for pair: Dictionary in pairs:
		for role: String in ["a", "b"]:
			var track := Track.build(chapter, pair, role)
			_check(not track.is_empty() and int(track.duration_ticks) > 0, "%s stage %d: the race ghost walks the %s turn" % [chapter, int(pair.stage_index) + 1, "first" if role == "a" else "closing"])

static func _hashes(turns: Array) -> Array:
	return turns.map(func(turn: Dictionary) -> String: return str(turn.get("recording_hash", "")))

# Saves -----------------------------------------------------------------------

func _saves(level: Dictionary) -> void:
	var chapter: String = level.chapter
	var bytes := FileAccess.get_file_as_bytes(level.path)
	_check(bytes.size() > 0 and bytes.size() <= Journey.MAX_SAVE_BYTES, "%s: the finished journal fits the solo save cap (%d of %d bytes)" % [chapter, bytes.size(), Journey.MAX_SAVE_BYTES])
	var name: String = str(level.path).get_file()
	var bundle := CloudBundle.collect({}, 0, {}, {name: JSON.parse_string(bytes.get_string_from_utf8())})
	var copy := CloudBundle.decode(CloudBundle.encode(bundle))
	if not _check(copy.get("journals", {}).has(name) and int(copy.journals[name].stages) == level.stages.size(), chapter + ": the cloud save carries the journal"): return
	var sources := CloudSources.new(null, null)
	sources.staging = directory.path_join("cloud-staging")
	var target := _journal_path(chapter, "cloud")
	_check(sources._adopt_journal({"chapter": chapter, "path": target}, copy.journals[name]) and Canonical.same(_journal(chapter, target).pairs(), level.pairs), chapter + ": a new phone restores it through the journal's own check")

# Barrier bumps ---------------------------------------------------------------

## Every turn of the level played over its memory as a replay plays it, each
## tick through the screen's refusal finder (presentation/barrier_refusals.gd):
## the friend's pip is judged on its own slot and its own turn's clock, so
## each push it made into an owner gate or a zone edge bumps again, on the
## same tick of its turn, while the next turn replays it beside the live pip.
func _bumps(level: Dictionary) -> void:
	var chapter: String = level.chapter
	var definition := Registry.definition(chapter)
	var engine: Script = Registry.simulation_script(chapter)
	var live_bumps := {}
	var memory_bumps := {}
	var wrong: Array[String] = []
	for stage in range(level.stages.size()):
		var turns: Array = level.stages[stage]
		for index in range(turns.size()):
			var turn: Dictionary = turns[index]
			var prior: Dictionary = turns[index - 1] if index > 0 else {}
			var sim: RefCounted = engine.new()
			if not Registry.reset_simulation(sim, chapter, definition, str(turn.stage_id), level.checkpoints[stage], prior, str(turn.role), turn, turns.slice(0, maxi(0, index - 1))):
				wrong.append("%d.%d does not set up (%s)" % [stage + 1, index + 1, sim.error])
				continue
			var refusals := BarrierRefusals.new()
			refusals.begin(chapter, definition, sim.snapshot(), prior if index > 0 else null)
			var start: Dictionary = sim.snapshot()
			if index > 0 and refusals._memory_slot != str(prior.player_slot): wrong.append("%d.%d judges the friend's pip as %s, not %s" % [stage + 1, index + 1, refusals._memory_slot, prior.player_slot])
			var from := int(start.get("handoff_tick", 0))
			for input: Dictionary in engine.expand_recording_inputs(turn):
				var state: Dictionary = refusals.annotate(sim.step(input), input)
				for event: Dictionary in state.get("refused", []):
					if event.kind not in [RouteBarriers.OWNER, RouteBarriers.ZONE]: continue
					var tick := int(state.tick)
					if event.slot == str(turn.player_slot): live_bumps["%d.%d@%d" % [stage, index, tick]] = event.id
					else: memory_bumps["%d.%d@%d" % [stage, index - 1, tick + from]] = event.id
				if bool(state.get("finished", false)): break
	# A friend's push replayed beside the next turn is one the friend's own turn bumped on that tick.
	for key: String in memory_bumps:
		if live_bumps.get(key) != memory_bumps[key]: wrong.append("the friend's bump %s (%s) is not its own turn's" % [key, memory_bumps[key]])
	_check(wrong.is_empty(), "%s: both pips bump the same, live and replayed (%d live bumps, %d replayed: %s)" % [chapter, live_bumps.size(), memory_bumps.size(), ", ".join(wrong.slice(0, 4))])

## A level is done (its keepsake places all earned, chapter_completion.gd) only
## once its last stage's goal is reached, Solo and with a friend alike, on its
## places whether or not it is released yet (a test build releases them all).
func _completion(level: Dictionary) -> void:
	var chapter: String = level.chapter
	var places: Array = Index.data(chapter).get("keepsakes", []).map(func(place: Dictionary) -> String: return str(place.stage_id))
	if places.is_empty(): places = HomeKeepsakeCatalog.chapter_places(chapter)
	if not _check(not places.is_empty(), chapter + ": the level has keepsake places"): return
	var stages: int = level.stages.size()
	var marks: Array = range(stages + 1).map(func(done: int) -> bool: return HomeKeepsakes.earned_places(places, stages, done).size() == places.size())
	_check(marks == range(stages + 1).map(func(done: int) -> bool: return done == stages), "%s: the level is done only after its last stage (%s by stages finished)" % [chapter, str(marks)])
	if HomeKeepsakeCatalog.chapter_places(chapter).is_empty(): return
	var earned: Array[Dictionary] = []
	for place: String in HomeKeepsakes._prefix_places(chapter, stages - 1): earned.append({"id": place, "solo": true, "friend": true})
	_check(not ChapterCompletion.chapters(earned).get(chapter, {}).get("solo", false), chapter + ": the menu does not tick it before its last stage")

# Reactions on the turn's clock -----------------------------------------------

## The screen's reaction player, noting the tick each reaction shows on.
class ReactionProbe extends "res://presentation/run_reaction_player.gd":
	var shown: Array = []
	var _now := 0
	var phase := ""
	func step(tick: int) -> void:
		_now = tick
		super.step(tick)
	func show_reaction(slot: String, track: Array, index: int, caption: String = "") -> void:
		shown.append({"id": str(track[index].get("id", "")), "tick": _now, "phase": phase})

## The friend's turn 2 of stage 1 carries a reaction before turn 3's hand-off
## and one after it. Each shows when the friend's turn reaches its tick: while
## turn 3 first watches it, at 1x and at Fast-forward, then beside the live
## turn after the hand-off, and in the stage's replay.
func _reactions(level: Dictionary) -> void:
	var chapter: String = level.chapter
	var turns: Array = level.stages[0]
	var handoff := int(turns[2].get(OpenTurns.HANDOFF_TICK, 0))
	var length := int(turns[1].duration_ticks)
	var before := mini(handoff - 1, 3)
	var after := handoff + mini(length - handoff - 1, 3 + RunReactionTrack.COOLDOWN_TICKS)
	if not _check(before >= 1 and after - before >= RunReactionTrack.COOLDOWN_TICKS and after < length, "%s: turn 3 takes over at %d of turn 2's %d ticks, room for a reaction on each side" % [chapter, handoff, length]): return
	RunReactionStore.new().keep(str(turns[1].recording_hash), [{"tick": before, "id": "happy"}, {"tick": after, "id": "sad"}])
	var path := _journal_path(chapter, "reactions")
	var journey := _journal(chapter, path)
	if not _check(journey.accept_recording(turns[0]) and journey.accept_recording(turns[1]), "%s: turn 3 is next (%s)" % [chapter, journey.last_error]): return
	for fast: bool in [false, true]:
		var label := "%s reactions%s" % [chapter, " at Fast-forward" if fast else ""]
		var screen := await _open_screen(chapter, path)
		var probe := ReactionProbe.new()
		screen.run_player = probe
		screen._begin()
		if not _check(screen.mode == "watch", "%s: turn 3 first watches turn 2 (mode %s)" % [label, screen.mode]):
			await _close_screen(screen)
			continue
		var steps := 0
		while screen.mode in ["watch", "play"] and steps < 20000 and (screen.mode == "watch" or int(screen.sim.tick) <= after - handoff + 2):
			steps += 1
			probe.phase = screen.mode
			if screen.mode == "watch":
				if fast: screen._wait().fast_forward_tick(screen._advance_watch, func() -> bool: return screen.mode == "watch")
				else: screen._advance_watch(STILL)
				if screen.mode == "watch" and not screen.memory_wait.waiting(): screen._hand_off()
			# Fast-forward holds while the friend's turn still plays, as the screen's own tick does.
			elif fast and screen.memory_wait.waiting(): screen._wait().fast_forward_tick(screen.advance_input, screen._playing_turn)
			else: screen.advance_input(STILL)
		_check(probe.shown == [{"id": "happy", "tick": before, "phase": "watch"}, {"id": "sad", "tick": after - handoff, "phase": "play"}], "%s: each shows when turn 2 reaches its tick, before and after the hand-off (%s; ended on tick %d, mode %s, %d steps)" % [label, str(probe.shown), int(screen.sim.tick), screen.mode, steps])
		await _close_screen(screen)
	# The stage's replay: turn 2 plays to the hand-off, then beside turn 3.
	var rows: Array = await _rows(chapter, level.path, false)
	if rows.is_empty(): return
	var context: Dictionary = ReplaysFlow._solo_replay_context_from_rows(chapter, rows, rows[0])
	if not _check(SoloReplayLaunch.write(context), chapter + " reactions replay: the hand-off is written"): return
	var screen := await _open_screen(chapter, level.path)
	var probe := ReactionProbe.new()
	screen.run_player = probe
	screen._play_collection_pair()
	var shown_at: Array = []
	var steps := 0
	while screen.mode == "replay" and screen.running and steps < 100000 and probe.shown.size() < 2:
		steps += 1
		screen._physics_process(0.0)
		if probe.shown.size() > shown_at.size(): shown_at.append(int(screen._replay_turns.find(screen._replay_runs[0])) if not screen._replay_runs.is_empty() else -1)
	_check(probe.shown.map(func(item: Dictionary) -> Array: return [item.id, item.tick]) == [["happy", before], ["sad", after - handoff]] and shown_at == [1, 2], "%s reactions replay: each shows at turn 2's tick, the second beside turn 3 (%s, %s)" % [chapter, str(probe.shown), str(shown_at)])
	await _close_screen(screen)

## The level's chapter screen on the journal at `path`, its journal loaded
## (a long one loads on a worker, which the screen's own frame finishes).
func _open_screen(chapter: String, path: String, size: Vector2i = Vector2i(640, 360)) -> Node:
	var viewport := SubViewport.new()
	viewport.size = size
	root.add_child(viewport)
	var screen := Preview.new()
	screen.chapter_key = chapter
	screen.journey = _journal(chapter, path)
	# Each screen counts its own tries, so every one is a turn's first.
	_screens += 1
	screen.turn_tries = TurnTries.new(directory.path_join("tries-%d.json" % _screens))
	screen.settings = {"sound": false, "haptics": false, "reduced_motion": true, "assistance": true, "left_handed": false}
	viewport.add_child(screen)
	screen.set_physics_process(false)
	for frame in range(3): await process_frame
	var frames := 0
	while screen._journal_loader != null and frames < 1200:
		await process_frame
		frames += 1
	screen.set_process(false)
	return screen

func _close_screen(screen: Node) -> void:
	screen.get_parent().queue_free()
	for frame in range(2): await process_frame

# The last turn ---------------------------------------------------------------

## A turn standing still, for IDLE_TICKS at least: a first turn ends once it
## may be saved, a later one passes once the friend's replay is over; the
## cap's turn runs to its limit.
static func _idle_turn(live: RefCounted) -> Dictionary:
	if live == null: return {}
	var limit := int(live.duration_limit())
	for tick in range(limit):
		if live.finished or (tick >= IDLE_TICKS and ((int(live.turn_number) == 1 and live.can_commit()) or live.can_pass())): break
		live.step(STILL)
	if live.can_pass(): live.pass_turn()
	return live.export_recording()

## Stage 1 played to its cap in idle turns, Solo and in a room.
func _last_turn(level: Dictionary, on_screen: bool) -> void:
	var chapter: String = level.chapter
	var cap := OpenTurns.cap(Registry.definition(chapter).stages[0])
	var path := _journal_path(chapter, "last-turn")
	var journey := _journal(chapter, path)
	for turn in range(1, cap):
		var idle := _idle_turn(journey.create_live_simulation(false))
		if not _check(journey.accept_recording(idle), "%s: idle turn %d of %d is saved (%s)" % [chapter, turn, cap, journey.last_error]): return
	var open := journey.open_turns()
	if not _check(int(open.get("turn", 0)) == cap and bool(open.get("must_finish", false)), "%s: turn %d is the stage's last" % [chapter, cap]): return
	var last := _idle_turn(journey.create_live_simulation(false))
	var verified: Dictionary = journey.verify_turn(last)
	var ending := TurnEndings.of(verified.get("snapshot", {}), true)
	_check(ending.get("kind") == "last_turn" and ending.get("rows") == [["try_again"], ["preview", "redo"], ["start_over"]], "%s: Solo's last turn over unfinished ends on the turn ending card (%s)" % [chapter, ending.get("kind")])
	_check(not OpenTurns.keepable(verified, last) and not journey.accept_recording(last) and int(journey.open_turns().get("turn", 0)) == cap, "%s: the last turn is never saved as a pass past the cap" % chapter)
	if on_screen: await _last_turn_screen(chapter, path, cap)
	await _last_turn_room(chapter, cap)

## The screen on the last turn: its card offers each way on, and each works.
func _last_turn_screen(chapter: String, path: String, cap: int) -> void:
	var start_over_path := _journal_path(chapter, "last-turn-start-over")
	for option: String in ["Try again", PlayerCopy.REDO_PLAY_AGAIN, PlayerCopy.START_OVER_ASK]:
		var label := "%s screen, last turn, %s" % [chapter, option]
		var used := path
		if option == PlayerCopy.START_OVER_ASK:
			AtomicFile.write_bytes(start_over_path, FileAccess.get_file_as_bytes(path))
			used = start_over_path
		var screen := await _open_screen(chapter, used, Vector2i(1280, 720))
		screen._begin()
		# The still turn runs on unseen to just before its limit; the screen plays its end.
		while screen.mode == "play" and int(screen.sim.tick) < int(screen.sim.duration_limit()) - 2:
			screen.sim.step(STILL)
		var steps := 0
		while screen.mode == "play" and steps < 100000:
			screen.advance_input(STILL)
			steps += 1
		var texts := _texts(screen)
		var title: Node = screen.find_child("EndingTitle", true, false)
		var offered := ["Try again", "Preview", PlayerCopy.REDO_PLAY_AGAIN, PlayerCopy.START_OVER_ASK].all(func(want: String) -> bool: return texts.has(want))
		if _check(screen.mode == "review" and title is Label and (title as Label).text == PlayerCopy.OPEN_TURNS_OUT_OF_TURNS and offered and _button(screen, "Save turn") == null, "%s: the card offers every way on (mode %s, %s)" % [label, screen.mode, str(texts)]):
			_button(screen, option).pressed.emit()
			for frame in range(2): await process_frame
			var turn := int(screen.journey.open_turns().get("turn", 0))
			if option == "Try again":
				_check(screen.mode == "play" and turn == cap, "%s: the last turn starts again (mode %s, turn %d)" % [label, screen.mode, turn])
			elif option == PlayerCopy.REDO_PLAY_AGAIN:
				_check(screen.journey.replacing() and turn == cap - 1, "%s: the turn before it is played again (turn %d)" % [label, turn])
			else:
				var modal: Node = screen.find_child("StartOverConfirm", true, false)
				var confirm := _button(modal, PlayerCopy.START_OVER_CONFIRM) if modal != null else null
				if _check(confirm != null, label + ": Start over asks first"):
					confirm.pressed.emit()
					for frame in range(2): await process_frame
					turn = int(screen.journey.open_turns().get("turn", 0))
					_check(screen.journey.pairs().is_empty() and turn == 1 and screen.journey.passes().is_empty(), "%s: the level starts over from its first turn (turn %d)" % [label, turn])
		await _close_screen(screen)

## A room on its last turn: the cap's turn may not pass and ends on the same card.
func _last_turn_room(chapter: String, cap: int) -> void:
	OpenTurnStore.erase_owner(HOST, directory)
	OpenTurnStore.erase_owner(GUEST, directory)
	var server := Server.new(chapter, ROOM, HOST, GUEST)
	var phones := {HOST: Phone.new(HOST, server, directory), GUEST: Phone.new(GUEST, server, directory)}
	for phone: Phone in phones.values():
		if not _check(phone.room.bind_room(ROOM) and await phone.room.refresh(), "%s room: each phone opens the room (%s)" % [chapter, phone.room.last_code]): return
	for turn in range(1, cap + 1):
		var mover: Phone = phones[server._player_of(turn)]
		if not _check(await mover.room.refresh() and mover.room.my_turn(), "%s room: turn %d is its pip's (%s)" % [chapter, turn, mover.room.last_code]): return
		var live: RefCounted = mover.room.create_live_simulation()
		var idle := _idle_turn(live)
		if turn == cap:
			var ending := TurnEndings.of(live.snapshot(), false)
			_check(bool(mover.room.open_turns().get("must_finish", false)) and ending.get("kind") == "last_turn" and not live.can_pass(), "%s room: the last turn over unfinished ends on the turn ending card (%s)" % [chapter, ending.get("kind")])
			return
		if not _check(await mover.room.commit(idle), "%s room: idle turn %d is taken (%s)" % [chapter, turn, mover.room.last_code]): return

func _texts(screen: Node) -> Array:
	var out: Array = []
	for node: Node in screen.find_children("*", "", true, false):
		if node is Button and (node as Button).is_visible_in_tree(): out.append((node as Button).text)
		elif node is Label and (node as Label).is_visible_in_tree(): out.append((node as Label).text)
	return out

func _button(screen: Node, text: String) -> Button:
	for node: Node in screen.find_children("*", "Button", true, false):
		if (node as Button).is_visible_in_tree() and (node as Button).text == text: return node
	return null

# Online ----------------------------------------------------------------------

## Two phones play the level through a room, one turn at a time.
func _online(level: Dictionary) -> void:
	var chapter: String = level.chapter
	OpenTurnStore.erase_owner(HOST, directory)
	OpenTurnStore.erase_owner(GUEST, directory)
	var server := Server.new(chapter, ROOM, HOST, GUEST)
	var phones := {HOST: Phone.new(HOST, server, directory), GUEST: Phone.new(GUEST, server, directory)}
	for phone: Phone in phones.values():
		if not _check(phone.room.bind_room(ROOM) and await phone.room.refresh(), "%s: each phone opens the room (%s)" % [chapter, phone.room.last_code]): return
	var closed: Array = []
	for stage in range(level.stages.size()):
		var turns: Array = level.stages[stage]
		for index in range(turns.size()):
			var recorded: Dictionary = turns[index]
			var label := "%s online stage %d turn %d" % [chapter, stage + 1, index + 1]
			var mover: Phone = phones[HOST if recorded.player_slot == "p0" else GUEST]
			var other: Phone = phones[GUEST if mover.player == HOST else HOST]
			if not _check(await mover.room.refresh() and mover.room.my_turn(), "%s: it is %s's turn (%s)" % [label, recorded.player_slot, mover.room.last_code]): return
			_check_playback(mover.room.playback(), turns.slice(0, index), closed, label)
			if index == 2:
				# Left mid-turn: the app opens again on the draft, watching the same hand-off.
				var live: RefCounted = mover.room.create_live_simulation()
				_play_live(live, recorded, maxi(1, int(recorded.duration_ticks) / 2))
				var draft: Dictionary = live.export_recording() if live != null else {}
				_check(not draft.is_empty() and mover.room.save_draft(draft), "%s: the mid-turn draft saves (%s)" % [label, mover.room.last_code])
				mover.reopen()
				_check(mover.room.bind_room(ROOM) and await mover.room.refresh() and mover.room.my_turn() and Canonical.same(mover.room.draft(), draft), "%s: the reopened room is on the draft (%s)" % [label, mover.room.last_code])
				_check_playback(mover.room.playback(), turns.slice(0, index), closed, label + " reopened")
			if not _check(await mover.room.commit(recorded), "%s: the turn is taken (%s)" % [label, mover.room.last_code]): return
			if not _check(await other.room.refresh(), "%s: the friend takes it (%s)" % [label, other.room.last_code]): return
		closed = turns
		# Watch again on the phone that did not close it: each stage from its own copies.
		var watcher: Phone = phones[GUEST if turns[-1].player_slot == "p0" else HOST]
		var whole: Dictionary = watcher.room.full_checkpoint()
		var pairs := CheckpointPairs.pairs(chapter, whole, 0)
		if not _check(pairs.size() == stage + 1 and _hashes(OpenTurns.pair_turns(pairs[stage])) == _hashes(turns), "%s stage %d: the friend watches the stage again, every turn" % [chapter, stage + 1]): continue
		var pair: Dictionary = pairs[stage]
		var replayed := CheckpointPairs.replay_closing(Registry.simulation_script(chapter).new(), Registry.simulation_script(chapter), chapter, Registry.definition(chapter), Registry.previous_checkpoint(chapter, pair.checkpoint), pair)
		_check(replayed.get("valid", false) and replayed.checkpoint.get("checkpoint_hash") == pair.checkpoint.get("checkpoint_hash"), "%s stage %d: the closing turn plays back to the stage's checkpoint (%s)" % [chapter, stage + 1, replayed.get("error", "")])
		var room: Dictionary = watcher.room.snapshot()
		var photos := OnlineSession.photo_turns(room, stage, pair, watcher.player)
		var slots: Array = photos.map(func(turn: Dictionary) -> String: return str(turn.player_slot))
		_check(photos.size() == 2 and "p0" in slots and "p1" in slots and photos.all(func(turn: Dictionary) -> bool: return _hashes(turns).has(turn.recording_hash)), "%s stage %d: the replay shows each pip's photo turn (%s)" % [chapter, stage + 1, str(photos.map(func(turn: Dictionary) -> String: return str(turn.turn_id)))])
	_check(phones[HOST].room.chapter_complete() and phones[GUEST].room.chapter_complete(), chapter + ": the room finishes on both phones")

## What the next turn watches before its hand-off, against the design's
## timeline: `played` is the stage's turns so far, `closed` the stage before's.
func _check_playback(shown: Dictionary, played: Array, closed: Array, label: String) -> void:
	var watched: Array = played if not played.is_empty() else closed
	var ticks: int = -1 if played.is_empty() else (OpenTurns.handoff_tick(watched.map(func(t: Dictionary) -> int: return int(t.duration_ticks)), played.size() + 1) if played.size() >= 2 else 0)
	if watched.is_empty() or ticks == 0:
		_check(shown.is_empty(), label + ": nothing to watch before the hand-off")
	else:
		_check(shown.get("turns", []).size() == watched.size() and shown.turns[-1].recording_hash == watched[-1].recording_hash and int(shown.ticks) == ticks, label + ": watches the friend's turn up to the hand-off (%d ticks)" % ticks)

func _check(condition: bool, message: String) -> bool:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
		print("FAIL: " + message)
	return condition
