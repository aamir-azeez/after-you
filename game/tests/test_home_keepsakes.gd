extends SceneTree
const Keepsakes = preload("res://services/home_keepsakes.gd")
const Catalog = preload("res://services/home_keepsake_catalog.gd")
const Save = preload("res://services/local_save.gd")
const Journey = preload("res://services/relay_journey.gd")
const Collection = preload("res://services/shared_replay_collection.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Coordinator = preload("res://services/relay_room_coordinator.gd")
const Registry = preload("res://services/chapter_registry.gd")
const HOST := "HHHHHHHHHHHHHHHHHHHHHH"
const GUEST := "GGGGGGGGGGGGGGGGGGGGGG"
const BAD := "BBBBBBBBBBBBBBBBBBBBBB"
const GOOD := "RRRRRRRRRRRRRRRRRRRRRR"
var count := 0
var failures := 0
var prefix := "user://keepsake-check-" + str(Time.get_ticks_usec())
var source_paths: Dictionary = {}
var current_player := HOST
var identity_epoch := 1

class FailingSave extends Save:
	var fail := false
	func update_values(changes: Dictionary, erase_keys: Array = []) -> bool:
		return false if fail else super.update_values(changes, erase_keys)

class Cache extends RefCounted:
	var values: Dictionary = {}
	var bad_scope := ""
	var calls: Array[String] = []
	func load_scope(scope: String) -> Dictionary:
		calls.append(scope)
		if scope == bad_scope: return {"ok": false}
		return {"ok": true, "found": values.has(scope), "value": values.get(scope, {}).duplicate(true)}
	func save_scope(scope: String, value: Dictionary) -> bool:
		values[scope] = value.duplicate(true)
		return true
	func save_room(scope: String, value: Dictionary) -> Dictionary:
		return {"ok": save_scope(scope, value)}

func _initialize() -> void: _run.call_deferred()
func _fixture(folder: String, name: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/" + folder + "/" + name + ".json"))
func _write(path: String, value: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(value if value is String else JSON.stringify(value))
	file.close()
func _check(okay: bool, message: String) -> void:
	count += 1
	if not okay:
		failures += 1
		push_error(message)
func _identity() -> Dictionary: return {"ready": true, "player_id": current_player, "epoch": identity_epoch}
func _offline(_request: Dictionary) -> Dictionary: return {"ok": false, "status": 0, "code": "offline"}
func _mark(service: RefCounted, id: String, variant: String) -> bool:
	for row: Dictionary in service.earned_descriptors():
		if row.id == id: return row[variant]
	return false

func _keepsakes(path: String, storage: RefCounted = null) -> RefCounted:
	return Keepsakes.new(path, storage, source_paths)

func _run() -> void:
	for chapter: String in Catalog.CHAPTERS: source_paths[chapter] = prefix + "-source-" + chapter.replace("@", "-") + ".json"
	Keepsakes._unclaimed.clear()
	_check(Catalog.all().size() == 22, "Exactly22 authored places")
	var ledger := _keepsakes(prefix + ".json")
	ledger.load_data()
	ledger.activate()
	_check(ledger.earned_descriptors().is_empty() and not ledger.read_only, "Fresh ledger has no earned items")
	var journey := Journey.new(prefix + "-journey.json", null, "relay-isles@2")
	journey.load_data()
	var a := _fixture("v2", "relay-a")
	var b := _fixture("v2", "relay-b")
	_check(journey.save_draft(a) and ledger.earned_descriptors().is_empty(), "Viable A rehearsal earns nothing")
	_check(journey.accept_recording(a) and ledger.earned_descriptors().is_empty(), "Durable A acceptance earns nothing")
	_check(journey.save_draft(b) and ledger.earned_descriptors().is_empty(), "Successful B rehearsal earns nothing")
	_check(journey.accept_recording(b) and _mark(ledger, "relay-isles/relay", "solo"), "Only durable accepted B earns solo place")
	var generation: int = ledger._storage.data.generation
	Keepsakes.record_solo_prefix("relay-isles@2", 1)
	_check(ledger._storage.data.generation == generation, "Repeated completion does not write a duplicate generation")
	Keepsakes.record_friend_prefix("relay-isles@2", 1)
	_check(_mark(ledger, "relay-isles/relay", "solo") and _mark(ledger, "relay-isles/relay", "friend"), "Solo and friend variants coexist")
	_check(journey.fork_from_stage(0) and _mark(ledger, "relay-isles/relay", "solo"), "Fork cannot revoke keepsake")
	var reopened := _keepsakes(prefix + ".json")
	reopened.load_data()
	_check(reopened.earned_descriptors() == ledger.earned_descriptors(), "Variants survive actual disk reload")
	Keepsakes.record_friend_prefix(Catalog.LIGHTHOUSE, 6)
	_check(ledger.earned_descriptors().size() == 1, "Lighthouse friend variants unavailable")
	var private_fields := FileAccess.get_file_as_string(prefix + ".json")
	_check(not private_fields.contains(HOST) and not private_fields.contains("room_id") and not private_fields.contains("recording"), "Ledger persists no private identity or replay fields")
	ledger.deactivate()
	var store := FailingSave.new(prefix + "-retry.json")
	var retry := _keepsakes(prefix + "-retry.json", store)
	retry.load_data()
	retry.activate()
	store.fail = true
	Keepsakes.record_legacy_solo("first-light")
	_check(retry.earned_descriptors().is_empty() and not retry.last_error.is_empty(), "Cosmetic I/O failure does not claim persisted unlock")
	store.fail = false
	_check(retry.advance_backfill() and _mark(retry, "earlier/first-light", "solo"), "Next reconciliation retries failed cosmetic award")
	retry.deactivate()
	var future := Save.defaults()
	future.home_keepsakes = {"schema_version": 2, "earned": {}}
	_write(prefix + "-future.json", future)
	var future_hash := FileAccess.get_sha256(prefix + "-future.json")
	var held := _keepsakes(prefix + "-future.json")
	held.load_data()
	_check(held.read_only and not held._award(["earlier/first-light"], "solo") and future_hash == FileAccess.get_sha256(prefix + "-future.json"), "Future save preserved byte-for-byte")
	_write(prefix + "-corrupt.json", "{broken")
	var corrupt := _keepsakes(prefix + "-corrupt.json")
	corrupt.load_data()
	_check(corrupt.read_only and FileAccess.get_file_as_string(prefix + "-corrupt.json") == "{broken", "Unrecoverable corrupt primary preserved")
	var recovery_path := prefix + "-recover.json"
	DirAccess.copy_absolute(prefix + ".json", recovery_path + ".backup")
	_write(recovery_path, "{interrupted")
	var recovery := _keepsakes(recovery_path)
	recovery.load_data()
	_check(not recovery.read_only and recovery.earned_descriptors().size() == 1, "Valid backup recovers interrupted primary")
	_check(FileAccess.file_exists(recovery_path + ".unreadable-" + "{interrupted".sha256_text()), "Interrupted bytes preserved before later writes")
	var cache := Cache.new()
	var bad_room := {"family": "chapter", "room_id": BAD, "host_id": HOST, "guest_id": GUEST, "chapter_key": "first-steps@1", "title": "First Steps"}
	var good_room := bad_room.duplicate(true)
	good_room.room_id = GOOD
	var rooms := {"chapter:" + BAD: bad_room, "chapter:" + GOOD: good_room}
	cache.values["shared-replays:" + HOST + ":index"] = {"schema_version": 1, "owner": HOST, "rooms": rooms}
	cache.bad_scope = "shared-replays:" + HOST + ":chapter:" + BAD
	var pair := {"pair_id": "p0-1", "branch": 0, "stage_index": 1, "a": _fixture("first_steps", "a-place-to-grow-a"), "b": _fixture("first_steps", "a-place-to-grow-b"), "checkpoint": _fixture("first_steps", "final-checkpoint")}
	var entry := {"schema_version": 1, "room": good_room, "pair": pair}
	cache.values["shared-replays:" + HOST + ":chapter:" + GOOD] = {"schema_version": 1, "owner": HOST, "entries": {"p0-1": entry}}
	var collection := Collection.new(null, _identity, cache)
	_check(Collection.verify_entry(entry, HOST) and not Collection.verify_entry(entry, BAD), "Native cache proof is participant-bound")
	var friends := _keepsakes(prefix + "-friends.json")
	friends.load_data()
	_check(not friends.reconcile_friend(collection) and friends.backfill_pending(), "Bad first cache does not erase pending later room")
	friends.advance_backfill()
	while friends.backfill_pending():
		friends.advance_backfill()
		await process_frame
	_check(not friends.backfill_pending() and _mark(friends, "first-steps/a-place-to-grow", "friend") and _mark(friends, "first-steps/a-little-lift", "friend"), "Later valid room recovers complete native-verified prefix despite bad first room")
	_check(cache.calls.count(cache.bad_scope) == 1, "Bad cache is not re-read repeatedly within same pass")
	var native_path := str(source_paths["high-and-low@1"])
	var native := Journey.new(native_path, null, "high-and-low@1")
	native.load_data()
	if native.pairs().is_empty():
		_check(native.accept_recording(_fixture("cooperative", "upper-path-a")) and native.accept_recording(_fixture("cooperative", "upper-path-b")), "Prepare accepted current journal")
		_check(native.accept_recording(_fixture("cooperative", "down-and-around-a")) and native.accept_recording(_fixture("cooperative", "down-and-around-b")), "Prepare completed native journal")
	if native.pairs().size() == 2: _check(native.fork_from_stage(0), "Archive completed source before fork")
	Keepsakes._unclaimed.clear()
	var lighthouse_source := Save.defaults()
	lighthouse_source.lighthouse = {"schema_version": 3, "simulation_version": 3, "level_id": "sleeping-lighthouse", "level_version": 1, "pairs": _fixture("lighthouse", "complete-six-v3").pairs, "a": {}, "draft": {}}
	_write(str(source_paths[Catalog.LIGHTHOUSE]), lighthouse_source)
	var historical := _keepsakes(prefix + "-historical.json")
	historical.load_data()
	var started := Time.get_ticks_usec()
	historical.reconcile_solo({"first-light": {"completed": true}})
	var enqueue_us := Time.get_ticks_usec() - started
	var longest_us := 0
	while historical.backfill_pending():
		started = Time.get_ticks_usec()
		historical.advance_backfill()
		longest_us = maxi(longest_us, Time.get_ticks_usec() - started)
		await process_frame
	_check(_mark(historical, "high-and-low/upper-path", "solo") and _mark(historical, "high-and-low/down-and-around", "solo"), "Retroactive archived accepted stages survive restart/fork")
	_check(not _mark(historical, "earlier/first-light", "solo"), "Legacy completed marker alone earns nothing")
	_check(_mark(historical, "sleeping-lighthouse/a-welcome-left-on", "solo"), "Complete six-stage Lighthouse history backfills through native validation")
	var cancelled := _keepsakes(prefix + "-cancelled.json")
	cancelled.load_data()
	cancelled.reconcile_solo()
	_check(cancelled._worker != null, "Historical native verification starts on a worker")
	cancelled.cancel_backfill()
	while cancelled.backfill_pending():
		cancelled.advance_backfill()
		await process_frame
	_check(cancelled.earned_descriptors().is_empty(), "Cancelled generation cannot apply a late worker award")
	var changed_owner := Collection.new(null, _identity, cache)
	cache.bad_scope = ""
	cache.values["shared-replays:" + HOST + ":chapter:" + BAD] = {"schema_version": 1, "owner": HOST, "entries": {}}
	var owner_ledger := _keepsakes(prefix + "-owner.json")
	owner_ledger.load_data()
	owner_ledger.reconcile_friend(changed_owner)
	current_player = BAD
	identity_epoch += 1
	while owner_ledger.backfill_pending():
		owner_ledger.advance_backfill()
		await process_frame
	_check(owner_ledger.earned_descriptors().is_empty(), "Identity replacement discards prior participant worker result")
	current_player = HOST
	identity_epoch += 1
	var lighthouse_path := str(source_paths[Catalog.LIGHTHOUSE])
	_write(lighthouse_path + ".backup", lighthouse_source)
	_write(lighthouse_path, "{interrupted-history")
	var untouched := FileAccess.get_sha256(lighthouse_path)
	var readonly_backfill := _keepsakes(prefix + "-readonly-backfill.json")
	readonly_backfill.load_data()
	readonly_backfill.reconcile_solo()
	while readonly_backfill.backfill_pending():
		readonly_backfill.advance_backfill()
		await process_frame
	_check(_mark(readonly_backfill, "sleeping-lighthouse/a-welcome-left-on", "solo") and FileAccess.get_sha256(lighthouse_path) == untouched and not FileAccess.file_exists(lighthouse_path + ".unreadable-" + untouched), "Worker can validate retained backup without repairing or writing the gameplay journal")
	await _late_receipt_cache()
	print("Keepsake checks: %d, failures: %d, enqueue_us: %d, longest_job_us: %d" % [count, failures, enqueue_us, longest_us])
	quit(1 if failures > 0 else 0)

func _late_receipt_cache() -> void:
	var room_id := "SSSSSSSSSSSSSSSSSSSSSS"
	var definition := Registry.definition(Registry.RELAY)
	var origin := {"schema_version": 2, "api_version": 2, "room_id": room_id, "revision": 4, "branch": 0, "stage_index": 1,
		"level_id": definition.id, "level_version": definition.version, "definition_hash": Canonical.digest(definition),
		"host_id": HOST, "guest_id": GUEST, "checkpoint": _fixture("v2", "relay-checkpoint"), "a_turn_id": "t0-1-a", "completed_pair_ids": ["p0-0"],
		"invite_code": "A1".repeat(10), "invite_expires_at": "2026-09-28T12:00:00Z", "created_at": "2026-09-27T12:00:00Z", "updated_at": "2026-09-27T12:00:00Z",
		"active_role": "b", "first_player_id": GUEST, "active_player_id": HOST, "player_slot": "p0", "stage_id": "garden", "recording_a": _fixture("v2", "garden-a"), "validation": "structural_client_replay_required"}
	var room_store := Cache.new()
	var replay_store := Cache.new()
	var replays := Collection.new(null, _identity, replay_store)
	var coordinator := Coordinator.new(_offline, room_store.load_scope, room_store.save_room, _identity)
	coordinator.accepted_pair_cache = replays.cache_accepted_receipt
	_check(coordinator.bind_room(room_id) and coordinator._accept_snapshot(origin), "Late receipt starts from native-verified second B context")
	var body := {"base_revision": 4, "branch": 0, "idempotency_key": "late-keepsake-receipt", "recording": _fixture("v2", "garden-b"), "checkpoint": _fixture("v2", "final-checkpoint")}
	_check(coordinator._prepare_pending("turns", body), "Exact final native proof is durable before submission")
	var forked := origin.duplicate(true)
	forked.merge({"revision": 6, "branch": 1, "stage_index": 0, "checkpoint": _fixture("v2", "initial-checkpoint"), "completed_pair_ids": [], "a_turn_id": null,
		"active_role": "a", "first_player_id": HOST, "active_player_id": HOST, "stage_id": "relay", "recording_a": null}, true)
	var receipt := {"schema_version": 2, "room_id": room_id, "idempotency_key": body.idempotency_key, "request_hash": Coordinator._request_hash("turns", body), "operation": "turns", "accepted_revision": 5,
		"branch": 0, "stage_index": 1, "stage_id": "garden", "turn_id": "t0-1-b", "recording_hash": body.recording.recording_hash, "pair_id": "p0-1", "checkpoint_hash": body.checkpoint.checkpoint_hash}
	Keepsakes._unclaimed.clear()
	var store := FailingSave.new(prefix + "-late.json")
	var failed_ledger := _keepsakes(prefix + "-late.json", store)
	failed_ledger.load_data()
	failed_ledger.activate()
	store.fail = true
	_check(coordinator._accept_receipt({"receipt": receipt, "room": forked}) and coordinator.pending().is_empty(), "Cosmetic failure never rolls back accepted B after partner fork")
	_check(failed_ledger.earned_descriptors().is_empty() and coordinator.snapshot().stage_index == 0, "New room no longer carries retired completion and failed ledger claims nothing")
	_check(replays.memories("chapter:" + room_id).size() == 2, "Retired accepted proof is preserved in existing participant replay cache")
	var refreshed_store := Cache.new()
	var refreshed_replays := Collection.new(null, _identity, Cache.new())
	var refreshed := Coordinator.new(_offline, refreshed_store.load_scope, refreshed_store.save_room, _identity)
	refreshed.accepted_pair_cache = refreshed_replays.cache_accepted_receipt
	_check(refreshed.bind_room(room_id) and refreshed._accept_snapshot(origin) and refreshed._prepare_pending("turns", body) and refreshed._accept_snapshot(forked), "A newer fork may be retained locally before the original response arrives")
	var old_complete := origin.duplicate(true)
	old_complete.merge({"revision": 5, "stage_index": 2, "checkpoint": body.checkpoint, "completed_pair_ids": ["p0-0", "p0-1"], "a_turn_id": null,
		"active_role": "complete", "first_player_id": null, "active_player_id": null, "stage_id": "", "recording_a": null}, true)
	_check(refreshed._accept_receipt({"receipt": receipt, "room": old_complete}) and refreshed.snapshot().branch == 1 and refreshed_replays.memories("chapter:" + room_id).size() == 2, "Older response still preserves accepted proof when newer fork was already retained locally")
	failed_ledger.deactivate()
	Keepsakes._unclaimed.clear()
	var reopened := Collection.new(null, _identity, replay_store)
	var recovered := _keepsakes(prefix + "-late-recovered.json")
	recovered.load_data()
	recovered.reconcile_friend(reopened)
	while recovered.backfill_pending():
		recovered.advance_backfill()
		await process_frame
	_check(_mark(recovered, "relay-isles/garden", "friend") and _mark(recovered, "relay-isles/relay", "friend"), "Restart restores retired accepted prefix from saved replay cache despite failed ledger write")
