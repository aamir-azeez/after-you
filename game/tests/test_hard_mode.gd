extends SceneTree
## Hard mode's own pieces (services/hard_mode.gd, presentation/hard_mode_view.gd):
## its rules, which chapters have it and when it unlocks, the marks it keeps,
## the bounded archive of runs, the hand-off that opens a chapter in hard
## mode, the room client's checks, and the marks on the pickers and Home.
const HardMode = preload("res://services/hard_mode.gd")
const HardRun = preload("res://services/hard_run.gd")
const HardRoomClient = preload("res://services/hard_room_client.gd")
const HardModeView = preload("res://presentation/hard_mode_view.gd")
const ChapterCompletion = preload("res://presentation/chapter_completion.gd")
const ChapterPicker = preload("res://presentation/chapter_picker.gd")
const Catalog = preload("res://services/home_keepsake_catalog.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Journey = preload("res://services/relay_journey.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const Replays = preload("res://presentation/replays_flow.gd")
const RoomActions = preload("res://presentation/room_actions.gd")
const Simulation = preload("res://core/v2/simulation_v2.gd")
const KEY := "relay-isles@2"
const HOST := "HHHHHHHHHHHHHHHHHHHHHH"
const GUEST := "GGGGGGGGGGGGGGGGGGGGGG"
var checks := 0
var failures := 0
var _paths: Array[String] = []

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	_rules()
	_unlocks()
	_marks_store()
	_archive()
	_hand_off()
	_solo_journal()
	_room_checks()
	await _marks_look()
	_room_actions()
	for path: String in _paths:
		for suffix: String in ["", ".tmp", ".backup"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	_clear_runs()
	print("Hard mode: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _path(label: String) -> String:
	var path := "user://hard-mode-test-%s-%s.json" % [label, Crypto.new().generate_random_bytes(6).hex_encode()]
	_paths.append(path)
	return path

func _clear_runs() -> void:
	for key: String in HardMode.eligible_keys():
		for suffix: String in ["", ".tmp", ".backup"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(HardMode.runs_path(key) + suffix))

func _rules() -> void:
	for id: String in ["retry", "try_again", "restart", "checkpoints", "solo_redo", "redo", "redo_answer"]:
		_check(not HardMode.offers(id), "A hard run never offers " + id)
	for id: String in ["resume", "record", "save", "preview", "back", "continue", "pause", "leave_draft"]:
		_check(HardMode.offers(id), "A hard run still offers " + id)
	_check(not HardMode.slipped(1) and HardMode.slipped(2) and HardMode.slipped(9), "Only a second start of a turn ends the run")
	_check(HardMode.failure({"valid": true, "snapshot": {"can_commit": true}}).is_empty(), "A turn that can be kept goes on")
	_check(HardMode.failure({"valid": true, "snapshot": {"can_commit": false}}) == "failed_turn", "A turn that cannot be kept ends the run")
	_check(HardMode.failure({"valid": true, "snapshot": {"can_commit": false, "drowned": {"slot": "p0"}}}) == "drowned", "A drowning ends the run as a drowning")
	_check(HardMode.failure({"valid": false, "error": "x"}) == "failed_turn", "A turn that fails its check ends the run rather than leaving no way on")
	_check(HardMode.tries_key(KEY) != KEY and HardMode.tries_key(KEY).begins_with(KEY), "A solo hard run counts tries apart from the chapter")
	var solo: RefCounted = HardRun.solo(KEY, _path("rules-marks"))
	_check(solo.active() and not solo.together and solo.tries_key(KEY) == HardMode.tries_key(KEY), "A solo run is always hard and counts in its own scope")
	_check(HardMode.notice_text("Sam", 1) == PlayerCopy.HARD_FRIEND_NOTICE % ["Sam", 2] and HardMode.notice_text("", 0) == PlayerCopy.HARD_FRIEND_NOTICE % [PlayerCopy.HARD_FRIEND_FALLBACK, 1], "The friend's note names them, or says your friend")

func _unlocks() -> void:
	var keys := HardMode.eligible_keys()
	_check(keys.size() >= 8 and KEY in keys, "Every offered chapter with its own solo screen has hard plays (%d)" % keys.size())
	for key: String in keys: _check(not Registry.is_lighthouse(key) and key in Registry.offered_keys(), key + " is an offered chapter that is not the Lighthouse")
	_check(not HardMode.eligible("sleeping-lighthouse@2") and not HardMode.eligible("earlier") and not HardMode.eligible(""), "The Lighthouse and earlier islands have no hard plays")
	var none: Array[Dictionary] = []
	var marks := ChapterCompletion.chapters(none)
	_check(not HardMode.unlocked(marks, KEY), "Hard stays locked before the chapter is finished")
	var places: Array[Dictionary] = []
	places.assign(Catalog.all().filter(func(item: Dictionary) -> bool: return item.chapter_key == KEY))
	var half: Array[Dictionary] = []
	for index in range(places.size()):
		var item: Dictionary = places[index].duplicate()
		item.solo = index == 0
		item.friend = false
		half.append(item)
	_check(not HardMode.unlocked(ChapterCompletion.chapters(half), KEY) or places.size() == 1, "Part of a chapter does not unlock it")
	for mode: String in ["solo", "friend"]:
		var done: Array[Dictionary] = []
		for place: Dictionary in places:
			var item := place.duplicate()
			item.solo = mode == "solo"
			item.friend = mode == "friend"
			done.append(item)
		var finished := ChapterCompletion.chapters(done)
		_check(HardMode.unlocked(finished, KEY), "Finishing the chapter " + mode + " unlocks both hard plays")
		var store := HardMode.new(_path("unlock-" + mode))
		_check(store.state(finished, KEY, HardMode.SOLO) == HardMode.OPEN and store.state(finished, KEY, HardMode.TOGETHER) == HardMode.OPEN, "Both marks read open once unlocked (" + mode + ")")
		_check(store.state(marks, KEY, HardMode.SOLO) == HardMode.LOCKED, "The marks read locked before")

func _marks_store() -> void:
	var path := _path("marks")
	var store := HardMode.new(path)
	var counted: Array = store.count()
	_check(counted[0] == 0 and counted[1] == HardMode.eligible_keys().size() * 2, "Hard counts two plays per chapter, none done at first")
	_check(store.record(KEY, HardMode.SOLO) and store.completed(KEY, HardMode.SOLO) and not store.completed(KEY, HardMode.TOGETHER), "A finished hard solo run is marked")
	_check(HardMode.new(path).completed(KEY, HardMode.SOLO), "The mark is on disk")
	_check(store.record(KEY, HardMode.SOLO) and store.record(KEY, HardMode.TOGETHER) and HardMode.new(path).count()[0] == 2, "Marks only ever turn on; both count")
	_check(not store.record(KEY, "other"), "Only the two hard plays are marks")
	var none: Array[Dictionary] = []
	_check(store.state(ChapterCompletion.chapters(none), KEY, HardMode.SOLO) == HardMode.DONE, "A done mark reads done")
	var damaged := _path("marks-damaged")
	var file := FileAccess.open(damaged, FileAccess.WRITE)
	file.store_string("{\"schema_version\":1,\"marks\":[]}")
	file.close()
	_check(HardMode.new(damaged).count()[0] == 0, "A damaged marks file reads as no marks")
	var backup := FileAccess.open(damaged + ".backup", FileAccess.WRITE)
	backup.store_string(JSON.stringify({"schema_version": 1, "marks": {KEY: {"solo": true, "together": "yes"}}}))
	backup.close()
	var recovered := HardMode.new(damaged)
	_check(recovered.completed(KEY, HardMode.SOLO) and not recovered.completed(KEY, HardMode.TOGETHER), "A damaged file falls back to its backup, and only true counts")

func _record(kind: String, mode: String, index: int) -> Dictionary:
	var slip := {"recording": {"recording_hash": "%064d" % index, "role": "a", "stage_id": "relay"}, "checkpoint": {"checkpoint_hash": "c"}, "prior": {}}
	var run := HardMode.run_record(KEY, mode, kind, "failed_turn" if kind == HardMode.FAILED else "", "you" if kind == HardMode.FAILED else "", index % 3, "a", [], slip if kind == HardMode.FAILED else {})
	run.at = 1000 + index
	run.id = "run-%s-%s-%d" % [kind, mode, index]
	return run

func _archive() -> void:
	_clear_runs()
	for index in range(8): _check(HardMode.save_run(_record(HardMode.FAILED, HardMode.SOLO, index)), "Failed solo run %d is kept" % index)
	for index in range(3): HardMode.save_run(_record(HardMode.FAILED, HardMode.TOGETHER, 20 + index))
	for index in range(2): HardMode.save_run(_record(HardMode.COMPLETE, HardMode.SOLO, 40 + index))
	var kept := HardMode.runs(KEY)
	var solo := kept.filter(func(run: Dictionary) -> bool: return run.mode == HardMode.SOLO and run.kind == HardMode.FAILED)
	_check(solo.size() == HardMode.MAX_FAILED and solo[0].id == "run-failed-solo-3" and solo[-1].id == "run-failed-solo-7", "Only the newest five failed solo runs are kept, oldest first")
	_check(kept.filter(func(run: Dictionary) -> bool: return run.mode == HardMode.TOGETHER).size() == 3, "Failed runs with a friend are kept apart from solo ones")
	var complete := kept.filter(func(run: Dictionary) -> bool: return run.kind == HardMode.COMPLETE)
	_check(complete.size() == 1 and complete[0].id == "run-complete-solo-41", "Only the newest finished solo run is kept")
	var size := kept.size()
	HardMode.save_run(_record(HardMode.FAILED, HardMode.SOLO, 7))
	_check(HardMode.runs(KEY).size() == size, "A run already kept is not kept twice")
	var all := HardMode.all_runs()
	_check(all.size() == size and int(all[0].at) >= int(all[-1].at), "Every chapter's runs list newest first")
	var bad := _record(HardMode.FAILED, HardMode.SOLO, 99)
	bad.reason = "bored"
	_check(not HardMode.save_run(bad), "A run with an unknown reason is refused")
	bad = _record(HardMode.FAILED, HardMode.SOLO, 98)
	bad.slip = {"recording": {}, "checkpoint": {}, "prior": {}}
	_check(not HardMode.save_run(bad), "A slip without a recording is refused")
	bad = _record(HardMode.FAILED, HardMode.SOLO, 97)
	bad.extra = true
	_check(not HardMode.save_run(bad), "A run with extra fields is refused")
	# The whole file stays under its byte cap: big runs push the oldest out.
	var big := _record(HardMode.FAILED, HardMode.TOGETHER, 60)
	big.slip.recording.padding = "x".repeat(HardMode.MAX_RUNS_BYTES / 2)
	_check(HardMode.save_run(big), "A large run is kept")
	var heavy := FileAccess.get_file_as_bytes(HardMode.runs_path(KEY)).size()
	_check(heavy <= HardMode.MAX_RUNS_BYTES, "The run file stays within its cap (%d bytes)" % heavy)
	for suffix: String in ["", ".backup"]:
		var file := FileAccess.open(HardMode.runs_path(KEY) + suffix, FileAccess.WRITE)
		file.store_string("not json")
		file.close()
	_check(HardMode.runs(KEY).is_empty(), "A damaged run file (and backup) reads as no runs")
	_clear_runs()
	var run := _record(HardMode.FAILED, HardMode.SOLO, 1)
	run.pairs = [{"a": {"stage_id": "relay"}, "b": {"stage_id": "relay"}}]
	var pairs := HardMode.watch_pairs(run)
	_check(pairs.size() == 2 and pairs[1].start == run.slip.checkpoint and pairs[1].b == run.slip.recording and pairs[1].a == {}, "A watch plays the stages before, then the slip from its own checkpoint")
	run.slip = {}
	run.pairs = []
	_check(HardMode.watch_pairs(run).is_empty() and not HardMode.watchable(run), "A slip before the first move has nothing to watch")
	var entry := Replays.hard_entry(_record(HardMode.FAILED, HardMode.TOGETHER, 5))
	_check(entry.family == "hard" and entry.title == PlayerCopy.HARD_RUN_FAILED % Registry.descriptor(KEY).title and str(entry.caption).contains(PlayerCopy.HARD_YOU_SLIPPED % 3), "A failed run lists under its chapter, marked as a hard run, with who slipped where")
	var friend := _record(HardMode.FAILED, HardMode.TOGETHER, 6)
	friend.by = "friend"
	friend.friend = "Sam"
	friend.reason = "drowned"
	_check(str(Replays.hard_entry(friend).caption) == PlayerCopy.HARD_RUN_TOGETHER % "Sam" + " · " + PlayerCopy.HARD_FRIEND_WENT_UNDER % ["Sam", 1], "A friend's slip names the friend")
	_check(Replays.hard_entry(_record(HardMode.COMPLETE, HardMode.SOLO, 7)).title == PlayerCopy.HARD_RUN_DONE % Registry.descriptor(KEY).title, "A finished run says so")

func _hand_off() -> void:
	HardMode.hand_over({"chapter_key": KEY, "kind": "play"})
	_check(HardMode.claim("high-and-low@1").is_empty() and HardMode.claim(KEY).is_empty(), "A hand-off for another chapter is dropped, never kept for a later open")
	HardMode.hand_over({"chapter_key": KEY, "kind": "play"})
	_check(HardMode.claim(KEY).kind == "play" and HardMode.claim(KEY).is_empty(), "A hard open is claimed once")
	HardMode.hand_over({"chapter_key": KEY, "kind": "play"})
	HardMode.hand_over({})
	_check(HardMode.claim(KEY).is_empty(), "An ordinary open clears any hard open left before it")
	HardMode.hand_over({"chapter_key": KEY, "kind": "play"})
	HardMode.drop()
	_check(HardMode.claim(KEY).is_empty(), "An open that failed drops its hand-off")

func _solo_journal() -> void:
	var target := HardMode.journal_path(KEY)
	_check(target.ends_with("-hard.json") and target != str(Registry.descriptor(KEY).local_path), "The hard run has its own journal beside the chapter's")
	var journey := Journey.new(target, null, KEY)
	journey.load_data()
	_check(not journey.read_only, "The hard journal loads: " + journey.last_error)
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/v2/relay-a.json"))
	var live: RefCounted = journey.create_live_simulation()
	for input: Dictionary in Simulation.expand_recording_inputs(fixture): live.step(input)
	_check(journey.accept_recording(live.export_recording()) and journey.role() == "b", "A first turn is kept in the hard journal: " + journey.last_error)
	var normal := Journey.new("", null, KEY)
	normal.load_data()
	_check(normal.role() == "a", "The chapter's own journal is untouched by the hard run")
	_check(HardMode.clear_journal(journey) and journey.role() == "a" and journey.pairs().is_empty(), "Clearing the hard journal starts the run at stage 1")
	_check(not FileAccess.file_exists(target) and journey.archived_attempts().is_empty(), "Clearing leaves no file and no archived attempt behind")
	var reloaded := Journey.new(target, null, KEY)
	reloaded.load_data()
	_check(reloaded.role() == "a" and reloaded.pairs().is_empty(), "A reload after clearing reads an empty run")

func _room() -> Dictionary:
	return {"room_id": "RRRRRRRRRRRRRRRRRRRRRR", "host_id": HOST, "guest_id": GUEST}

func _room_checks() -> void:
	var room := _room()
	_check(HardRoomClient.valid_view({"schema_version": 1, "failures": 0, "over": false, "last": null}, room), "A fresh hard room's view checks")
	var last := {"by": GUEST, "stage_index": 1, "role": "b", "reason": "drowned", "at": "2026-10-19T00:00:00Z"}
	_check(HardRoomClient.valid_view({"schema_version": 1, "failures": 2, "over": false, "last": last}, room), "A room's last slip checks")
	_check(not HardRoomClient.valid_view({"schema_version": 1, "failures": 1, "over": false, "last": null}, room), "Failures without a last slip are refused")
	var stranger := last.duplicate()
	stranger.by = "SSSSSSSSSSSSSSSSSSSSSS"
	_check(not HardRoomClient.valid_view({"schema_version": 1, "failures": 1, "over": false, "last": stranger}, room), "A slip by someone outside the room is refused")
	_check(not HardRoomClient.valid_view({"schema_version": 1, "failures": 1, "over": "no", "last": last}, room), "A malformed view is refused")
	var item := last.duplicate()
	item.slip = {"recording": {"role": "b"}, "checkpoint": {"checkpoint_hash": "c"}, "prior": {"role": "a"}}
	_check(HardRoomClient.valid_failures({"schema_version": 1, "failures": 3, "list": [item]}, room), "A read of kept failures checks")
	item.slip = null
	_check(HardRoomClient.valid_failures({"schema_version": 1, "failures": 3, "list": [item]}, room), "A failure without a slip checks")
	_check(not HardRoomClient.valid_failures({"schema_version": 1, "failures": 3, "list": [item, item, item, item, item, item]}, room), "More than five kept failures are refused")
	var journal := {"schema_version": 1, "owner_player_id": HOST, "room_id": room.room_id, "server_hash": "h", "pending": {}, "seen": 0}
	_check(HardRoomClient.valid_journal(journal, HOST, room.room_id, "h"), "An empty reset journal checks")
	journal.pending = {"base_revision": 3, "branch": 0, "idempotency_key": "k", "reason": "retry", "stage_index": 0, "role": "a"}
	_check(HardRoomClient.valid_journal(journal, HOST, room.room_id, "h"), "A kept reset checks")
	_check(not HardRoomClient.valid_journal(journal, GUEST, room.room_id, "h") and not HardRoomClient.valid_journal(journal, HOST, room.room_id, "other"), "Another player's or server's journal is never used")
	journal.pending.reason = "bored"
	_check(not HardRoomClient.valid_journal(journal, HOST, room.room_id, "h"), "A kept reset with an unknown reason is refused")

func _marks_look() -> void:
	for mode: String in HardMode.MODES:
		for state: String in [HardMode.LOCKED, HardMode.OPEN, HardMode.DONE]:
			var mark := HardModeView.mark(mode, state, 22.0)
			root.add_child(mark)
			await process_frame
			_check(mark.name == ("HardMarkSolo" if mode == HardMode.SOLO else "HardMarkTogether") and mark.look == state, "A %s mark reads %s" % [mode, state])
			var lock := mark.get_node_or_null("HardLock")
			_check((lock != null and lock.visible) == (state == HardMode.LOCKED), "Only a locked mark shows its lock (%s %s)" % [mode, state])
			mark.free()
	var chip := HardModeView.chip(false)
	_check(chip.toggle_mode and not chip.button_pressed and chip.text == PlayerCopy.HARD_CHIP, "The Hard chip starts off")
	HardModeView.set_chip(chip, true)
	_check(chip.button_pressed and chip.tooltip_text == PlayerCopy.HARD_CHIP_ON, "The chip reads on once set")
	chip.free()
	# The end card's hook: the slot sits between the band and the buttons.
	var card := VBoxContainer.new()
	card.add_child(Button.new())
	var seen := []
	HardModeView.ending_extras_provider = func(extras: VBoxContainer, context: Dictionary) -> void: seen.append([str(extras.name), str(context.kind)])
	var extras := HardModeView.add_band(card, "Back to the start", "You slipped on stage 2.", {"badge": &"knocked_out", "color": "peach"}, null, HardMode.SOLO)
	HardModeView.fill_extras(extras, {"kind": "failed"})
	_check(card.get_child(0).name == "HardBand" and card.get_child(1) == extras and extras.name == "EndingExtras" and card.get_child(2) is Button, "A hard end card holds its EndingExtras between the band and the buttons")
	_check(seen == [["EndingExtras", "failed"]], "The end card hook is called once with the card's extras and context")
	HardModeView.ending_extras_provider = Callable()
	card.free()
	# The picker shows each card's hard mark after its tick.
	var picker := ChapterPicker.new()
	picker.size = Vector2(1000, 600)
	root.add_child(picker)
	picker.hard_mode = HardMode.SOLO
	picker.hard_states = {KEY: {"solo": HardMode.OPEN, "together": HardMode.LOCKED}, "high-and-low@1": {"solo": HardMode.LOCKED, "together": HardMode.LOCKED}}
	var entries: Array[Dictionary] = [ChapterPicker.entry(KEY), ChapterPicker.entry("high-and-low@1")]
	for item: Dictionary in entries: item.locked = false
	picker.set_entries(entries, Vector2(192, 108))
	await process_frame
	await process_frame
	var relay_mark: Variant = picker.card_for(KEY).find_child("HardMarkSolo", true, false)
	_check(relay_mark != null and relay_mark.look == HardMode.OPEN, "A Play Solo card shows its hard solo mark")
	var tick: Control = picker.card_for(KEY).find_child("ChapterDone", true, false)
	_check(relay_mark != null and relay_mark.position.x > tick.position.x + 20.0, "The hard mark sits after the tick's place")
	picker.refresh_hard({KEY: {"solo": HardMode.DONE, "together": HardMode.LOCKED}})
	_check(relay_mark.look == HardMode.DONE, "Marks restyle in place")
	picker.free()

func _room_actions() -> void:
	var facts := func(hard: bool, draft: bool, accept: bool = false) -> Callable:
		return func(name: String, _state: String = "") -> bool:
			match name:
				"hard": return hard
				"resume_only": return hard and draft
				"draft": return draft
				"redo_accept": return accept
			return true
	for id: String in ["restart", "checkpoints", "solo_redo", "redo", "redo_answer"]:
		var accept := id == "redo_answer"
		_check(RoomActions.applies(id, facts.call(false, false, accept)) and not RoomActions.applies(id, facts.call(true, false, accept)), id + " is offered in normal play only")
	_check(RoomActions.applies("record", facts.call(true, false)) and not RoomActions.applies("record", facts.call(true, true)) and RoomActions.applies("record", facts.call(false, true)), "With a hard draft saved, only Resume goes on")
	_check(RoomActions.applies("hard_again", facts.call(true, false)) and not RoomActions.applies("hard_again", facts.call(false, false)), "Play Hard again shows only for a hard run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
