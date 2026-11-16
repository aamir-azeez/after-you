extends SceneTree
## Saved Games replay slots: the slot format round trips and refuses a flipped byte; items keep
## to their slot; newest first within the space, the rest counted for the backup-full notice;
## a phone's room history, duel runs and shared replays go up through the real sync and come back
## on an empty phone through their owners' checks, and a tampered or another player's item never
## does. Then the one backup-limit check.
const Bundle = preload("res://services/platform_games/cloud_replay_bundle.gd")
const Sources = preload("res://services/platform_games/cloud_replay_sources.gd")
const Sync = preload("res://services/platform_games/cloud_save_sync.gd")
const State = preload("res://services/platform_games/platform_games_state.gd")
const HistoryStore = preload("res://services/history_store.gd")
const DuelTheirRun = preload("res://services/duel_their_run.gd")
const SharedReplayStore = preload("res://services/shared_replay_store.gd")
const BlobCodec = preload("res://services/blob_codec.gd")
const BackupLimit = preload("res://services/backup_limit.gd")
const PhotoLibrary = preload("res://services/turn_photo_library.gd")

const OWNER := "PPPPPPPPPPPPPPPPPPPPPP"
const OTHER := "QQQQQQQQQQQQQQQQQQQQQQ"
const ROOM := "RRRRRRRRRRRRRRRRRRRRRR"
const SERVER := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
const DUEL := "0123456789abcdef0123456789abcdef"

## Saved Games with one stored copy a slot name.
class Slots extends "res://services/platform_games/games_provider.gd":
	var data := {}
	var _open := {}
	var commits := 0
	func snapshot_open(name: String) -> Dictionary:
		var handle := "%032d" % _open.size()
		_open[handle] = name
		return {"ok": true, "handle": handle, "data": data.get(name, PackedByteArray())}
	func snapshot_commit(handle: String, bytes: PackedByteArray, _description: String) -> Dictionary:
		commits += 1
		data[_open[handle]] = bytes
		return {"ok": true}
	func snapshot_discard(_handle: String) -> Dictionary: return {"ok": true}
	func snapshot_resolve(_handle: String, _bytes: PackedByteArray) -> Dictionary: return {"ok": false, "code": "failed"}

var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _item(at: int, size: int, rev: int = 0, digest: String = "a".repeat(64)) -> Dictionary:
	return {"kind": "shared", "owner": OWNER, "rev": rev, "at": at, "digest": digest, "data": "x".repeat(size), "meta": {}}

func _run() -> void:
	var dir := "user://replay-slots-test-%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(dir)
	_codec()
	await _round_trip(dir)
	_limit(dir.path_join("limit.json"))
	_remove(dir)
	print("Platform games replays: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _codec() -> void:
	var bundle := Bundle.empty()
	bundle.items = {"shared/" + "b".repeat(64) + ".json": _item(5, 40, 3), "duel/%s/%s.json" % [OWNER, DUEL]: {"kind": "duel", "owner": OWNER, "rev": 0, "at": 4, "digest": "c".repeat(64), "data": "AAEC", "meta": {"byte_length": 3, "acked": true}}}
	var bytes := Bundle.encode(bundle)
	var back := Bundle.decode(bytes)
	_check(Bundle.fingerprint(back) == Bundle.fingerprint(bundle) and bundle.items.keys().all(func(key: String) -> bool: return back.items[key].data == bundle.items[key].data), "A slot round trips in the replay blob format")
	var flipped := bytes.duplicate()
	flipped[flipped.size() - 3] = flipped[flipped.size() - 3] ^ 1
	_check(Bundle.decode(flipped).is_empty() and Bundle.decode(bytes.slice(0, 20)).is_empty(), "A flipped byte or a cut slot is refused, so it is never written over")
	_check(Bundle.decode(PackedByteArray()) == Bundle.empty(), "An empty slot reads as a new one")
	for key: String in bundle.items: _check(Bundle.slot_of(key) == Bundle.slot_of(key) and Bundle.slot_of(key) in range(Bundle.SLOTS), "An item always goes to the same slot")
	# Space: newest first, the rest left out and counted, and the same answer either way round.
	var big := (Bundle.BUDGET - Bundle.ITEM_OVERHEAD * 3) / 2
	var crowded := {"shared/old.json": _item(1, big), "shared/mid.json": _item(2, big), "shared/new.json": _item(3, big)}
	var fitted := Bundle.fit(crowded)
	_check(fitted.items.keys().has("shared/new.json") and fitted.items.keys().has("shared/mid.json") and fitted.left_out == 1, "The newest that fit are kept; the oldest is left out and counted")
	var a := {"schema_version": 1, "items": {"shared/old.json": crowded["shared/old.json"]}}
	var b := {"schema_version": 1, "items": {"shared/mid.json": crowded["shared/mid.json"], "shared/new.json": crowded["shared/new.json"]}}
	_check(Bundle.fingerprint(Bundle.merge(a, b)) == Bundle.fingerprint(Bundle.merge(b, a)) and Bundle.merge(a, b).items.size() == 2, "Merging keeps the newest that fit, whichever copy is first")
	var merged := Bundle.merge(a, b)
	_check(Bundle.fingerprint(Bundle.merge(merged, merged)) == Bundle.fingerprint(merged) and not Bundle.adds_to(merged, merged), "Merging a copy with itself changes nothing")
	var older := {"schema_version": 1, "items": {"shared/x.json": _item(9, 10, 1, "d".repeat(64))}}
	var newer := {"schema_version": 1, "items": {"shared/x.json": _item(8, 10, 2, "e".repeat(64))}}
	_check(Bundle.merge(older, newer).items["shared/x.json"].rev == 2 and Bundle.merge(newer, older).items["shared/x.json"].rev == 2, "A rewritten shared file keeps its later revision")

## The real sources and sync: up from one phone, back down onto an empty one.
func _round_trip(dir: String) -> void:
	var phone := dir.path_join("phone")
	var bytes := "a recorded attempt".to_utf8_buffer()
	var record := {"position": 0, "link": "f".repeat(64), "digest": BlobCodec.digest(bytes), "byte_length": bytes.size()}
	_check(HistoryStore.new(phone.path_join("history")).save(SERVER, OWNER, ROOM, record, BlobCodec.encode(bytes)), "A kept room attempt")
	var run := "the other pair's run".to_utf8_buffer()
	var kept := {"digest": BlobCodec.digest(run), "byte_length": run.size(), "body": Marshalls.raw_to_base64(BlobCodec.encode(run)), "acked": true}
	_check(DuelTheirRun.restore(OWNER, DUEL + ".json", kept, phone.path_join("duel_runs")), "A kept duel run")
	var scope := "shared-replays:%s:index" % OWNER
	_check(SharedReplayStore.new(phone.path_join("shared-replays")).save_scope(scope, {"schema_version": 1, "rooms": ["one"]}), "A shared replay file")
	_check(SharedReplayStore.new(phone.path_join("shared-replays")).save_scope("shared-replays:%s:index" % OTHER, {"schema_version": 1, "rooms": ["theirs"]}), "Another player's shared file on the same phone")
	var image := Image.create(20, 16, false, Image.FORMAT_RGB8)
	image.fill(Color.CYAN)
	var jpeg := image.save_jpg_to_buffer(0.8)
	var photo := {"schema_version": 1, "turn_id": "t0-0-a", "owner_player_id": OTHER, "recording_hash": "e".repeat(64), "photo_revision": 1, "sha256": PhotoLibrary._digest(jpeg), "width": 20, "height": 16, "byte_length": jpeg.size(), "updated_at": "2026-11-15T12:00:00.000Z"}
	_check(PhotoLibrary.new(phone.path_join("photo-library")).store_cache(OWNER, ROOM, photo, jpeg).get("ok", false), "A friend's turn photo in this player's library")
	var slots := Slots.new()
	var state := State.new(dir.path_join("state.json"))
	var up := 0
	var phone_syncs: Array = []
	for index: int in Bundle.SLOTS:
		var sources := Sources.new(null, index, state)
		sources.root = phone
		sources.owner_override = OWNER
		sources.limit_path = dir.path_join("limit-up.json")
		var sync := Sync.new(slots, sources, state, Bundle.slot_name(index), Bundle, "r%d_" % (index + 1))
		phone_syncs.append(sync)
		var outcome: Dictionary = await sync.run()
		_check(outcome.ok, "Slot %d syncs: %s" % [index + 1, outcome])
		up += Bundle.decode(slots.data.get(Bundle.slot_name(index), PackedByteArray())).items.size()
		_check(sync.synced_once() and not (await sync.run()).get("wrote", true), "A slot with nothing new does no work")
	_check(up == 4 and slots.commits == slots.data.size(), "This player's attempt, duel run, shared file and photo go up, each once, and nothing of another player's")
	_check(slots.data.keys().filter(func(name: String) -> bool: return name.begins_with(Bundle.PHOTO_SLOT_PREFIX)).size() == 1, "The photo goes to a photo slot")
	# The phone that sent them deletes one: it is not sent back down to it.
	var room_slot := Bundle.slot_of("room/%s/%s/%s/0-%s" % [OWNER, SERVER.left(16), ROOM, "f".repeat(16)])
	_check(HistoryStore.new(phone.path_join("history")).erase_room(SERVER, OWNER, ROOM), "Start over drops the room's attempts here")
	phone_syncs[room_slot].flush(true)
	await phone_syncs[room_slot].run()
	_check(HistoryStore.new(phone.path_join("history")).read_attempt(SERVER, OWNER, ROOM, 0).get("code") == "history_missing", "and the slot does not put them back")
	# An empty phone pulls every slot and gets them back through their owners.
	var fresh := dir.path_join("fresh")
	var fresh_state := State.new(dir.path_join("fresh-state.json"))
	var fresh_syncs: Array = []
	for index: int in Bundle.SLOTS:
		var sources := Sources.new(null, index, fresh_state)
		sources.root = fresh
		sources.owner_override = OWNER
		sources.limit_path = dir.path_join("limit-down.json")
		fresh_syncs.append(Sync.new(slots, sources, fresh_state, Bundle.slot_name(index), Bundle, "r%d_" % (index + 1)))
		await fresh_syncs[index].run()
	_check(HistoryStore.new(fresh.path_join("history")).read_attempt(SERVER, OWNER, ROOM, 0).get("bytes") == bytes, "The room attempt is back and reads exactly")
	var duel_text := FileAccess.get_file_as_string(fresh.path_join("duel_runs").path_join(OWNER).path_join(DUEL + ".json"))
	var duel: Variant = JSON.parse_string(duel_text)
	_check(duel is Dictionary and duel.digest == kept.digest and BlobCodec.verified(Marshalls.base64_to_raw(duel.body), int(duel.byte_length), duel.digest, 1 << 20) == run, "The duel run is back and decodes to its digest")
	var shared := SharedReplayStore.new(fresh.path_join("shared-replays")).load_scope(scope)
	_check(shared.get("ok", false) and shared.get("found", false) and shared.value.rooms == ["one"], "The shared replay file is back and loads")
	var photo_back := PhotoLibrary.new(fresh.path_join("photo-library")).read_cache(OWNER, ROOM, {"turn_id": photo.turn_id, "recording_hash": photo.recording_hash})
	_check(photo_back.get("found", false) and photo_back.get("bytes") == jpeg, "The photo is back in the library, checked like a transferred one")
	_check(not FileAccess.file_exists(fresh.path_join("shared-replays").path_join(("shared-replays:%s:index" % OTHER).sha256_text() + ".json")), "Another player's file never comes down")
	# Restore runs once per player here: a replay deleted on this phone stays deleted.
	_check(SharedReplayStore.new(fresh.path_join("shared-replays")).remove_scope(scope), "The player deletes the shared replay")
	var shared_slot := Bundle.slot_of("shared/" + scope.sha256_text() + ".json")
	fresh_syncs[shared_slot].flush(true)
	await fresh_syncs[shared_slot].run()
	_check(not SharedReplayStore.new(fresh.path_join("shared-replays")).load_scope(scope).get("found", true), "and it does not come back from the slot")
	# Tampered items are never written.
	var bad := dir.path_join("bad")
	var sources := Sources.new(null, 0)
	sources.root = bad
	var history := HistoryStore.new(bad.path_join("history"))
	var cloud := Bundle.empty()
	for index: int in Bundle.SLOTS: cloud.items.merge(Bundle.decode(slots.data.get(Bundle.slot_name(index), PackedByteArray())).items)
	for key: String in cloud.items:
		var item: Dictionary = cloud.items[key].duplicate(true)
		if item.kind == "shared": item.data = item.data.replace("one", "two")
		else: item.digest = "0".repeat(64)
		_check(not sources.restore(history, key, item, OWNER), "A tampered %s item is refused" % item.kind)
	_check(not DirAccess.dir_exists_absolute(bad.path_join("shared-replays")) and history.read_attempt(SERVER, OWNER, ROOM, 0).get("code") == "history_missing" and not DirAccess.dir_exists_absolute(bad.path_join("duel_runs")), "and nothing of it reaches the phone")
	for key: String in cloud.items: _check(not sources.restore(history, key, cloud.items[key], OTHER), "An item is never restored for another player")

## One check for every backup: told once, again only when more stops fitting.
func _limit(path: String) -> void:
	_check(not BackupLimit.due(path), "Nothing left out, nothing to tell")
	BackupLimit.note("saved-games-1", 2, path)
	_check(BackupLimit.due(path), "Newer replays left out: the player is told")
	BackupLimit.acknowledge(path)
	_check(not BackupLimit.due(path), "OK is remembered")
	BackupLimit.note("phone", 1, path)
	_check(BackupLimit.due(path), "More stops fitting (here Android's backup): told again")
	BackupLimit.acknowledge(path)
	BackupLimit.note("saved-games-1", 0, path)
	BackupLimit.note("saved-games-1", 1, path)
	_check(BackupLimit.due(path), "After old replays were deleted, the next one that stops fitting is told again")

func _remove(path: String) -> void:
	for name: String in DirAccess.get_directories_at(path): _remove(path.path_join(name))
	for name: String in DirAccess.get_files_at(path): DirAccess.remove_absolute(path.path_join(name))
	DirAccess.remove_absolute(path)
