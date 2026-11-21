extends SceneTree
## Solo open turns keep their draft through every turn of a level, as in play:
## each turn is set up by the journey (create_live_simulation), steps its
## witness route's recorded input, and saves its draft once a second on the
## worker (save_live_draft periodic), then is saved as the turn (a pass or the
## stage's last). From turn 3 a turn plays over a pass, not over the stage's
## first turn; the draft must check the pass it plays over, or every later
## turn stopped on "This moment is still here".
## - The Falls and Fog Marsh play their first two stages (8 and 6 turns) and
##   High and Low plays to the end with no draft save error, and a later
##   turn's draft, saved while its memory still plays, reopens from disk.
## - A periodic save that failed never strands the turn: the next save writes,
##   and the chapter screen plays on without the save problem card.
const Registry = preload("res://services/chapter_registry.gd")
const Journey = preload("res://services/relay_journey.gd")
const Witness = preload("res://tests/chapter_witness.gd")
const Preview = preload("res://cooperative_preview.gd")

## How many stages each level plays (0: all of them), within a suite's time.
const CHAPTERS := {"the-falls@1": 2, "fog-marsh@1": 2, "high-and-low@2": 0}

var checks := 0
var failures := 0
var directory := ""
var _witnesses := {}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	directory = "user://open-turns-solo-drafts-" + Crypto.new().generate_random_bytes(6).hex_encode()
	DirAccess.make_dir_recursive_absolute(directory)
	for chapter: String in CHAPTERS:
		var started := Time.get_ticks_msec()
		_play_through(chapter, int(CHAPTERS[chapter]))
		print("%s: %d ms" % [chapter, Time.get_ticks_msec() - started])
	_failed_periodic_recovers("high-and-low@2")
	await _screen_plays_on("high-and-low@2")
	print("OPEN TURNS SOLO DRAFTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## The witness's turns for `chapter`'s first `stages` stages (0: all), played once.
func _witness(chapter: String, stages: int) -> Array:
	if not _witnesses.has(chapter):
		var routes: Dictionary = Witness.routes(chapter)
		var level := Registry.definition(chapter)
		var wanted := {}
		for index in range(level.stages.size() if stages <= 0 else stages):
			wanted[level.stages[index].id] = routes.get(level.stages[index].id)
		var played := Witness.play(chapter, wanted)
		var rows: Array = played.stages.slice(0, wanted.size())
		var ok: bool = played.pairs.size() == wanted.size() and rows.all(func(row: Dictionary) -> bool: return row.ok)
		_check(ok, "%s: the witness plays %d stages (%s)" % [chapter, wanted.size(), played.error])
		_witnesses[chapter] = played.pairs if ok else []
	return _witnesses[chapter]

func _journey(chapter: String, label: String) -> Journey:
	var journey := Journey.new(directory.path_join("%s-%s.json" % [chapter.validate_filename(), label]), null, chapter)
	journey.load_data()
	return journey

## Plays `recorded` again on the journey's own live turn, saving its draft
## every 30 ticks on the worker as the screen does. "" or why it stopped.
func _play_turn(journey: Journey, recorded: Dictionary, reopen: bool) -> String:
	var live: RefCounted = journey.create_live_simulation(false)
	if live == null: return "the turn did not start: " + journey.last_error
	live.catch_assistance = bool(recorded.get("catch_assistance", true))
	var frames: Array = live.get_script().expand_recording_inputs(recorded)
	var saves := 0
	for frame: Dictionary in frames:
		if live.finished: break
		live.step(frame)
		if Journey.tick_of(live) % 30 != 0 or live.finished: continue
		# The worker is joined at once, so every write is checked in order.
		if not journey.save_live_draft(live, true) or not journey.finish_live_draft_save():
			return "the periodic draft at tick %d failed: %s" % [Journey.tick_of(live), journey.last_error]
		saves += 1
		if reopen and saves == 2:
			# A draft saved over this turn's memory reopens from disk and replays.
			var again := Journey.new(journey._path, null, journey.chapter_key())
			again.load_data()
			if again.draft().is_empty() or again.read_only: return "the saved draft did not reopen: " + again.last_error
	if saves == 0: return "no periodic draft was saved"
	# A pause saves at once, on the main thread.
	if not journey.save_live_draft(live): return "the paused draft failed: " + journey.last_error
	# A first turn ends once it may be saved; a pass hands the stage on.
	if recorded.get("completed") == false and recorded.get("role") == "b": live.pass_turn()
	var played: Dictionary = live.export_recording()
	if played.get("recording_hash") != recorded.get("recording_hash"): return "the turn played differently from its witness"
	if not journey.accept_recording(played): return "the turn was not saved: " + journey.last_error
	return ""

func _play_through(chapter: String, stages: int) -> void:
	var pairs := _witness(chapter, stages)
	if pairs.is_empty(): return
	var journey := _journey(chapter, "solo")
	var turn := 0
	var over_pass := 0
	for pair: Dictionary in pairs:
		for recorded: Dictionary in pair.turns:
			turn += 1
			var memory_is_pass := not journey.passes().is_empty()
			# The first stage's later turns also reopen their draft from disk mid-memory.
			var problem := _play_turn(journey, recorded, journey.role() == "b" and journey.pairs().is_empty())
			_check(problem.is_empty(), "%s turn %d (%s): %s" % [chapter, turn, journey.stage_id(), problem])
			if not problem.is_empty(): return
			if memory_is_pass: over_pass += 1
	_check(over_pass >= pairs.size() and turn >= 6, "%s: %d turns, %d of them over a pass" % [chapter, turn, over_pass])
	_check(journey.pairs().size() == pairs.size() and journey.last_error.is_empty(), "%s: Solo saves every stage it played" % chapter)
	if stages <= 0: _check(journey.chapter_complete(), "%s: Solo finishes the level" % chapter)

## A periodic write that failed (a full disk, a lost worker) is reported once
## and the next save writes the whole turn; nothing stays stuck.
func _failed_periodic_recovers(chapter: String) -> void:
	var pairs := _witness(chapter, int(CHAPTERS[chapter]))
	if pairs.is_empty(): return
	var turns: Array = pairs[0].turns
	var journey := _journey(chapter, "recover")
	_check(journey.accept_recording(turns[0]) and journey.accept_recording(turns[1]), chapter + ": turn 1 and a pass are saved (%s)" % journey.last_error)
	var live: RefCounted = journey.create_live_simulation(false)
	for t in range(60): live.step({"move_x": 0.5, "move_z": 0.2, "interact": false})
	for lost: Variant in [{"ok": false, "error": "disk full"}, null]:
		journey._draft_writer = Thread.new()
		journey._draft_writer.start(func() -> Variant: return lost)
		_check(not journey.finish_live_draft_save() and not journey.last_error.is_empty(), chapter + ": a failed periodic write is reported (%s)" % str(lost))
		_check(journey.save_live_draft(live, true) and journey.finish_live_draft_save() and journey.has_draft(), chapter + ": the next periodic save writes (%s)" % journey.last_error)
		journey._draft_writer = Thread.new()
		journey._draft_writer.start(func() -> Variant: return lost)
		_check(journey.save_live_draft(live), chapter + ": a pause after a failed periodic write still saves (%s)" % journey.last_error)
	var reopened := _journey(chapter, "recover")
	var kept: Dictionary = reopened.draft()
	_check(int(kept.get("duration_ticks", 0)) == 60 and not reopened.read_only, chapter + ": the journal holds the latest draft (%d ticks, %s)" % [int(kept.get("duration_ticks", 0)), reopened.last_error])
	# The draft is a turn still inside its memory: it checks, but is no pass.
	_check(not journey.accept_recording(live.export_recording()) and journey.passes().size() == 1, chapter + ": a turn still inside its memory is not saved as a pass")

## The chapter screen keeps playing when a periodic write fails; the next one saves.
func _screen_plays_on(chapter: String) -> void:
	var path := directory.path_join("screen.json")
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 360)
	root.add_child(viewport)
	var screen := Preview.new()
	screen.chapter_key = chapter
	screen.journey = Journey.new(path, null, chapter)
	screen.settings = {"sound": false, "haptics": false, "reduced_motion": true, "assistance": true, "left_handed": false}
	viewport.add_child(screen)
	screen.set_physics_process(false)
	for frame in range(3): await process_frame
	screen._begin()
	_check(screen.mode == "play", chapter + " screen: the turn starts")
	screen.journey._draft_writer = Thread.new()
	screen.journey._draft_writer.start(func() -> Variant: return {"ok": false, "error": "disk full"})
	var guard := 0
	while screen.journey._draft_writer != null and guard < 600:
		await process_frame
		guard += 1
	_check(screen.mode == "play", chapter + " screen: a failed periodic write does not stop the turn (%s)" % screen.mode)
	for t in range(1, 31): screen.advance_input({"move_x": 0.4, "move_z": 0.3, "interact": false})
	guard = 0
	while screen.journey._draft_writer != null and guard < 600:
		await process_frame
		guard += 1
	_check(screen.mode == "play" and screen.journey.has_draft(), chapter + " screen: the next periodic save writes and play goes on")
	viewport.queue_free()
	for frame in range(3): await process_frame

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
		print("FAIL: " + message)
