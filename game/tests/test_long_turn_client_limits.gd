extends SceneTree
## The phone's own bounds against the widest things a capped chapter
## (core/physical/runtime.gd INPUT_RULES, LONG_TURN_TICKS) can make: two stages
## at the development turn limits (content/chapters/index.gd), every record
## holding every change the cap allows at its widest, as the backend's
## long-turns.test.ts builds them. Each is checked as the phone holds it after a
## save and a load: JSON numbers read back as floats print wider ("-100.0").
## - a room snapshot and a turn reply (RelayRoomCoordinator._bounded);
## - a fetched pair (_pair_bounded) and a whole room journal (_journal_bounded);
## - the solo save (RelayJourney.MAX_SAVE_BYTES, the proof warmup's limit too);
## - the proof cache (JourneyProofs), four of the widest final checkpoints;
## - the race ghost's tick limit.
## Prints each size beside its bound.
const Catalog = preload("res://core/journey/stage_catalog.gd")
const Runtime = preload("res://core/physical/runtime.gd")
const Index = preload("res://content/chapters/index.gd")
const Coordinator = preload("res://services/relay_room_coordinator.gd")
const Journey = preload("res://services/relay_journey.gd")
const Warmup = preload("res://services/journey_proof_warmup.gd")
const Proofs = preload("res://services/journey_proofs.gd")
const Ghost = preload("res://services/race_ghost_track.gd")
const DIRECTORY := "res://tests/fixtures/journey/"
const HASH := "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
var checks := 0
var failures := 0
var rules: Dictionary = Runtime.INPUT_RULES[1]
var a_ticks: int = int(Index.DEVELOPMENT_TURN_LIMITS.a_ticks)
var b_ticks: int = int(Index.DEVELOPMENT_TURN_LIMITS.b_ticks)

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var initial: Dictionary = _load("turn-of-the-tide-v2-initial-checkpoint.json")
	var a1 := _widest(_load("turn-of-the-tide-v2-set-the-tide-a.json"), a_ticks)
	var b1 := _widest(_load("turn-of-the-tide-v2-set-the-tide-b.json"), b_ticks)
	var cp1 := _proven(_load("turn-of-the-tide-v2-set-the-tide-checkpoint.json"), initial, a1, b1)
	var a2 := _widest(_load("turn-of-the-tide-v2-slack-water-a.json"), a_ticks)
	var b2 := _widest(_load("turn-of-the-tide-v2-slack-water-b.json"), b_ticks)
	var cp2 := _proven(_load("turn-of-the-tide-v2-slack-water-checkpoint.json"), cp1, a2, b2)
	_check(a2.actions.size() == Runtime.max_action_entries(rules, a_ticks) and b2.actions.size() == Runtime.max_action_entries(rules, b_ticks), "Every record holds every change the cap allows")
	# Rooms as the server sends them: the second stage's receiver to play, and the run complete.
	var playing := _room(cp1, a2, "b")
	var complete := _room(cp2, {}, "complete")
	for room: Dictionary in [playing, complete]:
		_check(Coordinator._bounded(room) and Coordinator._bounded({"receipt": {}, "room": room}), "A %s room and its turn reply fit the room bound: %s" % [room.active_role, _size(room, Coordinator.MAX_ROOM_BYTES)])
	var pair: Variant = _read({"pair_id": "p3-1", "branch": 3, "stage_index": 1, "a": a2, "b": b2, "checkpoint": cp2})
	_check(Coordinator._pair_bounded(pair), "The widest pair fits the pair bound: " + _size(pair, Coordinator.MAX_PAIR_BYTES))
	# A journal at its widest: the room, a draft, every held draft and a receiver turn waiting for its reply, all at stage 2.
	var draft := {"origin": playing, "recording": b2}
	var journal: Variant = _read({"schema_version": 1, "api_version": 2, "owner_player_id": "A".repeat(22), "room_id": "c".repeat(22), "snapshot": playing, "draft": draft,
		"held_drafts": [draft, draft, draft, draft].slice(0, Coordinator.MAX_HELD), "pending": {"origin": playing, "body": {"recording": b2, "checkpoint": cp2}}, "last_receipt": {}, "auth_required": false})
	_check(Coordinator._journal_bounded(journal), "The widest journal fits the journal bound: %s, %d values of %d" % [_size(journal, Coordinator.MAX_BYTES), _values(journal), Coordinator.COMFORT_JOURNAL_NODES])
	# The solo save holds at most four records of a two-stage run: two pairs, or a pair, a first turn and a draft.
	var save: Variant = _read({"version": 1, "generation": 9, "settings": {}, "attempts": {}, "completed": {}, "replays": {}, "room": {},
		"relay": {"schema_version": 7, "simulation_version": 10, "level_id": "turn-of-the-tide", "level_version": 2, "definition_hash": HASH, "pairs": [{"a": a1, "b": b1}, {"a": a2, "b": b2}], "a": {}, "draft": {}}})
	_check(_bytes(save) <= Journey.MAX_SAVE_BYTES and Warmup.MAX_SAVE_BYTES == Journey.MAX_SAVE_BYTES, "The widest solo save fits the save bound, which the proof warmup reads too: " + _size(save, Journey.MAX_SAVE_BYTES))
	_proof_cache(cp2)
	_check(b_ticks <= Ghost.MAX_TICKS, "A race ghost keeps the longest turn: %d ticks of %d" % [b_ticks, Ghost.MAX_TICKS])
	print("LONG TURN CLIENT LIMITS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## Four of the widest final checkpoints, as many as the cache keeps a chapter, are written and read back whole.
func _proof_cache(checkpoint: Dictionary) -> void:
	Proofs.directory = "user://journey-proofs-long-" + Crypto.new().generate_random_bytes(6).hex_encode()
	var chapter := "long-turns-test"
	var entries: Array = []
	for index in range(Proofs.ENTRIES_PER_CHAPTER): entries.append(["key-%d" % index, HASH, _read(checkpoint)])
	Proofs._mutex.lock()
	Proofs._write(chapter, entries.duplicate(true))
	Proofs._chapters.clear()
	var read: Array = Proofs._entries(chapter)
	Proofs._mutex.unlock()
	var file := FileAccess.open(Proofs._path(chapter), FileAccess.READ)
	var length := file.get_length() if file != null else 0
	if file != null: file.close()
	_check(read.size() == Proofs.ENTRIES_PER_CHAPTER and str(read[-1][0]) == "key-%d" % (Proofs.ENTRIES_PER_CHAPTER - 1) and JSON.stringify(read[-1][2]) == JSON.stringify(entries[-1][2]),
		"The proof cache keeps all %d of the widest final checkpoints: file %d bytes of %d (%d before compression)" % [Proofs.ENTRIES_PER_CHAPTER, length, Proofs.MAX_FILE_BYTES, var_to_bytes(entries).size()])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Proofs._path(chapter)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Proofs.directory))

## `record` at `ticks` with every change the cap allows, each entry at its widest, and a check every second.
func _widest(record: Dictionary, ticks: int) -> Dictionary:
	var entries := Runtime.max_action_entries(rules, ticks)
	var actions: Array = []
	for index in range(entries): actions.append({"ticks": ticks / entries + (1 if index < ticks % entries else 0), "x": -100, "z": -100 if index % 2 == 0 else -99, "action": false})
	var replay_checks: Array = []
	var count := ticks / 30 + 1
	for index in range(count): replay_checks.append({"tick": ticks - count + 1 + index, "state_hash": HASH})
	var widened := record.duplicate(true)
	widened.duration_ticks = ticks
	widened.actions = actions
	widened.replay_checks = replay_checks
	widened.final_state_hash = HASH
	return widened

func _proven(template: Dictionary, previous: Dictionary, a: Dictionary, b: Dictionary) -> Dictionary:
	var checkpoint := template.duplicate(true)
	checkpoint.proof = {"checkpoint": previous, "a": a, "b": b}
	return checkpoint

func _room(checkpoint: Dictionary, recording_a: Dictionary, role: String) -> Dictionary:
	return _read({"schema_version": 2, "room_id": "c".repeat(22), "revision": 999, "branch": 3, "stage_index": int(checkpoint.stage_index), "level_id": "turn-of-the-tide",
		"level_version": 2, "definition_hash": str(checkpoint.definition_hash), "host_id": "A".repeat(22), "guest_id": "B".repeat(22), "checkpoint": checkpoint, "a_turn_id": "t3-1-a" if role == "b" else null,
		"completed_pair_ids": ["p3-0"], "invite_expires_at": "2026-11-13T00:00:00.000Z", "created_at": "2026-11-13T00:00:00.000Z", "updated_at": "2026-11-13T00:00:00.000Z",
		"api_version": 2, "active_role": role, "first_player_id": "A".repeat(22), "active_player_id": "B".repeat(22), "player_slot": "p1", "stage_id": "slack-water",
		"recording_a": recording_a, "validation": {}})

## As the phone holds a value after a save and a load: whole numbers become floats.
func _read(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value))

func _load(name: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(DIRECTORY + name))

func _bytes(value: Variant) -> int:
	return JSON.stringify(value).to_utf8_buffer().size()

func _size(value: Variant, bound: int) -> String:
	return "%d bytes of %d" % [_bytes(value), bound]

func _values(value: Variant) -> int:
	var count := 1
	if value is Dictionary:
		for key: Variant in value: count += _values(value[key])
	elif value is Array:
		for item: Variant in value: count += _values(item)
	return count

func _check(value: bool, label: String) -> void:
	checks += 1
	print(("ok   " if value else "FAIL ") + label)
	if not value:
		failures += 1
		push_error(label)
