extends SceneTree
## The solo draft saved once a second of play is exported, checked and written
## on a worker (RelayJourney.save_live_draft periodic), because all three grow
## with the turn's recording and on the main thread they hitched every second.
## - A still copy of each engine family exports exactly the live engine's bytes,
##   for a first and a second turn, and keeps them while the turn plays on.
## - A periodic save returns with its writer still to join and writes exactly
##   what the synchronous save writes.
## - Accepting, saving again or leaving with a write in flight never leaves an
##   older draft on disk after a newer state.
## - The chapter screen hands its once-a-second save to the writer.
const Registry = preload("res://services/chapter_registry.gd")
const Journey = preload("res://services/relay_journey.gd")
const Frozen = preload("res://services/frozen_simulation.gd")
const Preview = preload("res://cooperative_preview.gd")
const Canonical = preload("res://core/v2/canonical.gd")

var checks := 0
var failures := 0
var directory := ""

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	directory = "user://solo-draft-writer-" + Crypto.new().generate_random_bytes(6).hex_encode()
	DirAccess.make_dir_recursive_absolute(directory)
	var families := 0
	# The Lighthouse facade exports through the engine it holds.
	for chapter: String in [Registry.CONSERVATORY, Registry.WISHING_WELL, Registry.FIRST_STEPS, Registry.RELAY, Registry.LIGHTHOUSE_V2]:
		if _frozen_exports(chapter, "a"): families += 1
	_check(families == 5, "Journey, cooperative, First Steps, Relay and Lighthouse engines are covered (%d)" % families)
	var seconds := 0
	# Conservatory's bundled first-turn fixture predates its current rules; the
	# Tide covers the journey engine's second turn.
	for chapter: String in [Registry.TURN_OF_THE_TIDE, Registry.WISHING_WELL, Registry.FIRST_STEPS]:
		if _frozen_exports(chapter, "b"): seconds += 1
	_check(seconds == 3, "Second turns, which replay the partner's turn beside them, are covered (%d)" % seconds)
	_periodic_matches_synchronous(Registry.CONSERVATORY)
	_periodic_matches_synchronous(Registry.FIRST_STEPS)
	_periodic_matches_synchronous(Registry.LIGHTHOUSE_V2)
	_in_flight_ordering(Registry.WISHING_WELL)
	await _screen_uses_writer(Registry.CONSERVATORY)
	print("SOLO DRAFT WRITER: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _fixture(name: String) -> Dictionary:
	for folder: String in ["journey", "cooperative", "first_steps", "v2"]:
		var path := "res://tests/fixtures/" + folder + "/" + name + ".json"
		if FileAccess.file_exists(path): return JSON.parse_string(FileAccess.get_file_as_string(path))
	return {}

func _first_turn(chapter: String) -> Dictionary:
	return _fixture(str(Registry.definition(chapter).stages[0].id) + "-a")

func _journey(chapter: String, label: String) -> Journey:
	var journey := Journey.new(directory.path_join("%s-%s.json" % [chapter.validate_filename(), label]), null, chapter)
	journey.load_data()
	return journey

## A slow wander with an occasional interact: a new action almost every tick.
static func _input(t: int) -> Dictionary:
	return {"move_x": sin(t * 0.045) * 0.9, "move_z": cos(t * 0.031) * 0.9, "interact": t % 150 == 75}

static func _tick(simulation: RefCounted) -> int:
	return int(Journey.tick_of(simulation))

func _frozen_exports(chapter: String, role: String) -> bool:
	var label := "%s %s" % [chapter, role]
	var journey := _journey(chapter, "frozen-" + role)
	if role == "b":
		var first := _first_turn(chapter)
		if first.is_empty() or not journey.accept_recording(first):
			_check(false, label + ": first turn fixture accepted (" + journey.last_error + ")")
			return false
	var live: RefCounted = journey.create_live_simulation(false)
	if live == null:
		_check(false, label + ": live turn set up (" + journey.last_error + ")")
		return false
	var compared := 0
	var t := 0
	while not live.finished and t < 10000:
		t += 1
		live.step(_input(t))
		if _tick(live) not in [1, 30, 300, 600] and not live.finished: continue
		var frozen: RefCounted = Frozen.of(live)
		var expected := var_to_bytes(live.export_recording())
		_check(var_to_bytes(frozen.export_recording()) == expected, "%s tick %d: the still copy exports the live engine's bytes" % [label, _tick(live)])
		if not live.finished:
			for more in range(7):
				t += 1
				live.step(_input(t))
			_check(var_to_bytes(frozen.export_recording()) == expected, "%s tick %d: the still copy keeps its bytes while the turn plays on" % [label, _tick(frozen)])
		compared += 1
	_check(compared >= 4 and live.finished, "%s: compared through the end of the turn (%d)" % [label, compared])
	return compared >= 4

static func _journal(path: String) -> Variant:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed.get("relay") if parsed is Dictionary else null

func _periodic_matches_synchronous(chapter: String) -> void:
	var background := _journey(chapter, "periodic")
	var direct := _journey(chapter, "direct")
	var a: RefCounted = background.create_live_simulation(false)
	var b: RefCounted = direct.create_live_simulation(false)
	for t in range(1, 301):
		a.step(_input(t))
		b.step(_input(t))
		if t % 30 != 0: continue
		var draft_before: Dictionary = background._state.draft
		var started: bool = background.save_live_draft(a, true)
		_check(started and background._draft_writer != null, "%s tick %d: a periodic save returns with its writer still to join" % [chapter, t])
		_check(background._state.draft == draft_before, "%s tick %d: the journey keeps its last saved state until the write is joined" % [chapter, t])
		_check(background.finish_live_draft_save(), "%s tick %d: the periodic write succeeds" % [chapter, t])
		_check(direct.save_live_draft(b), "%s tick %d: the synchronous save succeeds" % [chapter, t])
		_check(var_to_bytes(background._state) == var_to_bytes(direct._state), "%s tick %d: both saves leave the same journey state" % [chapter, t])
		_check(var_to_bytes(_journal(background._path)) == var_to_bytes(_journal(direct._path)), "%s tick %d: both saves write the same journal" % [chapter, t])
	_check(not background._state.draft.is_empty() and background.has_draft(), chapter + ": the periodic draft is the journey's draft")
	var reopened := _journey(chapter, "periodic")
	_check(Canonical.same(reopened.draft(), background._state.draft) and reopened.last_error.is_empty(), chapter + ": a reopened journey resumes the periodic draft after its full check")

func _in_flight_ordering(chapter: String) -> void:
	# Accept with a periodic write in flight: the accepted turn wins on disk.
	var journey := _journey(chapter, "accept-in-flight")
	var live: RefCounted = journey.create_live_simulation(false)
	for t in range(1, 61): live.step(_input(t))
	_check(journey.save_live_draft(live, true), chapter + ": periodic save started before accepting")
	var first := _first_turn(chapter)
	_check(journey.accept_recording(first), chapter + ": accepting joins the writer and saves the turn (" + journey.last_error + ")")
	_check(journey._draft_writer == null, chapter + ": no writer is left after accepting")
	var disk: Variant = _journal(journey._path)
	_check(disk is Dictionary and Canonical.same(disk.a, first) and disk.draft.is_empty(), chapter + ": the journal holds the accepted turn and no older draft")
	# A pause or finish save with a periodic write in flight: the later draft wins.
	var paused := _journey(chapter, "pause-in-flight")
	var turn: RefCounted = paused.create_live_simulation(false)
	for t in range(1, 31): turn.step(_input(t))
	_check(paused.save_live_draft(turn, true), chapter + ": periodic save started before pausing")
	for t in range(31, 46): turn.step(_input(t))
	_check(paused.save_live_draft(turn), chapter + ": the pause save joins the writer and saves")
	disk = _journal(paused._path)
	_check(disk is Dictionary and int(disk.draft.get("duration_ticks", 0)) == 45 and int(paused._state.draft.duration_ticks) == 45, chapter + ": the journal holds the later pause draft")
	# A second periodic save while one is in flight is skipped, never waited for.
	var skipped := _journey(chapter, "skip-in-flight")
	var again: RefCounted = skipped.create_live_simulation(false)
	for t in range(1, 31): again.step(_input(t))
	_check(skipped.save_live_draft(again, true), chapter + ": first periodic save started")
	for t in range(31, 61): again.step(_input(t))
	_check(skipped.save_live_draft(again, true) and skipped._draft_writer != null, chapter + ": the next periodic save never fails and leaves one writer to join")
	_check(skipped.finish_live_draft_save() and int(skipped._state.draft.duration_ticks) in [30, 60], chapter + ": the joined draft is one of the two periodic drafts")
	# Leaving with a write in flight: the journey is freed after joining it.
	var left := _journey(chapter, "leave-in-flight")
	var path: String = left._path
	var leaving: RefCounted = left.create_live_simulation(false)
	for t in range(1, 31): leaving.step(_input(t))
	_check(left.save_live_draft(leaving, true), chapter + ": periodic save started before leaving")
	left = null
	leaving = null
	var after := Journey.new(path, null, chapter)
	after.load_data()
	_check(after.last_error.is_empty() and int(after.draft().get("duration_ticks", 0)) == 30, chapter + ": the draft written while leaving is complete and resumable")

func _screen_uses_writer(chapter: String) -> void:
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
	for t in range(1, 31): screen.advance_input(_input(t))
	_check(screen.journey._draft_writer != null, chapter + " screen: the once-a-second save runs on the writer")
	var guard := 0
	while screen.journey._draft_writer != null and guard < 600:
		await process_frame
		guard += 1
	_check(screen.journey._draft_writer == null and screen.journey.has_draft() and screen.mode == "play", chapter + " screen: the frame loop takes the finished write and play goes on")
	var reopened := Journey.new(path, null, chapter)
	reopened.load_data()
	_check(int(reopened.draft().get("duration_ticks", 0)) == 30, chapter + " screen: the journal holds the draft from the writer")
	viewport.queue_free()
	for frame in range(3): await process_frame

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
		print("FAIL: " + message)
