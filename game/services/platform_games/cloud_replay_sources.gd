extends RefCounted
## This phone's side of one replay or photo slot (cloud_replay_bundle.gd), for cloud_save_sync.gd:
## the current player's kept room history attempts, shared replay files, friend duel runs and photo
## library entries whose keys go to this slot. Built by Main's platform games flow; lives only while Main does.
##
## Restore runs once per player on this install (a new phone, a reinstall, or an identity brought
## back here), so a replay deleted or started over on this phone never comes back from the slot.
## It merges by key and never overwrites: an item this phone lacks is written through its
## owner after the owner's own checks, as if it had just been downloaded (HistoryStore.restore
## checks length and SHA-256, and history_sync.gd still checks the chain link against the server
## before use; a duel run must decode to its digest; a shared replay file must be the envelope
## its name and scope say, for this player; a photo goes through TurnPhotoLibrary.import_entry, the
## photo transfer's own checks of its JPEG, size and hash). Another player's items are kept in the
## slot, untouched. Photos deleted here are never sent.
## Items that no longer fit the slot are counted for the backup-limit notice (backup_limit.gd).
const Bundle = preload("res://services/platform_games/cloud_replay_bundle.gd")
const HistoryStore = preload("res://services/history_store.gd")
const DuelTheirRun = preload("res://services/duel_their_run.gd")
const SharedReplayStore = preload("res://services/shared_replay_store.gd")
const PhotoLibrary = preload("res://services/turn_photo_library.gd")
const BlobCodec = preload("res://services/blob_codec.gd")
const AtomicFile = preload("res://services/atomic_file.gd")
const BackupLimit = preload("res://services/backup_limit.gd")
const Typed = preload("res://services/typed_values.gd")

const DUEL_NAME := "^(ghost-)?[a-f0-9]{32}\\.json$"
const SHARED_NAME := "^[a-f0-9]{64}\\.json$"
const SERVER := "^[a-f0-9]{16}$"
const PHOTO_ENTRY := "^[a-f0-9]{64}\\.json$"

var slot := 0
## Tests: where the files are, the owner id and the backup-limit file.
var root := "user://"
var owner_override := ""
var limit_path := BackupLimit.PATH
var _host: WeakRef
var _state: RefCounted
var _wrote_shared := false

## state: the platform games state, which remembers the player this slot was restored for.
func _init(host: Node, slot_index: int, state: RefCounted = null) -> void:
	_host = weakref(host)
	slot = slot_index
	_state = state

func _main() -> Node:
	var host: Variant = _host.get_ref()
	return host if host is Node and is_instance_valid(host) else null

func owner() -> String:
	if not owner_override.is_empty(): return owner_override
	var host := _main()
	var api: Variant = host.get("api") if host != null else null
	var id: Variant = api.get("player_id") if api is Object and is_instance_valid(api) else ""
	return id if Typed.valid_id(id) else ""

## An identity is needed: its items are the ones collected and restored.
func ready() -> bool:
	return not owner().is_empty()

func at_home() -> bool:
	var host := _main()
	return owner_override != "" or (host != null and host.mode == "home")

## Every candidate file of this slot, by size and modified time, with no reads.
func stamp() -> String:
	var parts := PackedStringArray([owner()])
	for entry: Array in listing(root, owner()):
		if Bundle.slot_of(entry[0]) == slot: parts.append("%s:%d:%d" % [entry[0], FileAccess.get_modified_time(entry[1]), _size(entry[1])])
	return "|".join(parts).sha256_text()

## [key, path] of every file that may hold this player's items. Room keys are per attempt and
## are filled in from each room's index when collected.
static func listing(base: String, player: String) -> Array:
	var out: Array = []
	if player.is_empty(): return out
	var history := base.path_join("history")
	for server: String in _folders(history):
		for room: String in _folders(history.path_join(server).path_join(player)):
			var folder := history.path_join(server).path_join(player).path_join(room)
			for name: String in _files(folder):
				if name.ends_with(".bin"): out.append(["room/%s/%s/%s/%s" % [player, server, room, name.trim_suffix(".bin")], folder.path_join(name)])
	var duels := base.path_join("duel_runs").path_join(player)
	for name: String in _files(duels):
		if _matches(name, DUEL_NAME): out.append(["duel/%s/%s" % [player, name], duels.path_join(name)])
	var shared := base.path_join("shared-replays")
	for name: String in _files(shared):
		if _matches(name, SHARED_NAME): out.append(["shared/" + name, shared.path_join(name)])
	var photos := base.path_join("photo-library").path_join(player.sha256_text()).path_join("entries")
	for name: String in _files(photos):
		if _matches(name, PHOTO_ENTRY): out.append(["photo/%s/%s" % [player, name.trim_suffix(".json")], photos.path_join(name)])
	return out

## This slot's bundle: the newest of this player's items that fit. Files are read on a worker.
func collect() -> Dictionary:
	var player := owner()
	if player.is_empty(): return {}
	warm()
	var task_root := root
	var task_slot := slot
	var result := {}
	var task := WorkerThreadPool.add_task(func() -> void: result.merge(gather(task_root, player, task_slot)))
	var tree := Engine.get_main_loop() as SceneTree
	while not WorkerThreadPool.is_task_completed(task):
		await tree.process_frame
	WorkerThreadPool.wait_for_task_completion(task)
	if player != owner(): return {}
	var fitted := Bundle.fit(result)
	BackupLimit.note("saved-games-%d" % (slot + 1), int(fitted.left_out), limit_path)
	var bundle := Bundle.empty()
	bundle.items = fitted.items
	return bundle

## Worker: key -> item for this player's files in `slot`. Reads only; skips anything odd.
static func gather(base: String, player: String, slot_index: int) -> Dictionary:
	var items := {}
	var indexes := {}
	for entry: Array in listing(base, player):
		var key: String = entry[0]
		var path: String = entry[1]
		if Bundle.slot_of(key) != slot_index: continue
		var at := FileAccess.get_modified_time(path)
		var kind := key.get_slice("/", 0)
		if kind == "room":
			var folder := path.get_base_dir()
			var room := folder.get_file()
			if not indexes.has(folder): indexes[folder] = HistoryStore.index_in(folder, room)
			for record: Dictionary in indexes[folder].values():
				if record.file != path.get_file(): continue
				var tagged := FileAccess.get_file_as_bytes(path)
				if HistoryStore.verified_bytes(tagged, record).is_empty(): continue
				items[key] = {"kind": kind, "owner": player, "rev": 0, "at": at, "digest": record.digest, "data": Marshalls.raw_to_base64(tagged),
					"meta": {"server": folder.get_base_dir().get_base_dir().get_file(), "room": room, "position": record.position, "link": record.link, "byte_length": record.byte_length}}
		elif kind == "duel":
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if parsed is Dictionary and parsed.get("digest") is String and Bundle._matches(parsed.digest, Bundle.DIGEST) and Typed.whole_number(parsed.get("byte_length")) and parsed.get("body") is String:
				items[key] = {"kind": kind, "owner": player, "rev": 0, "at": at, "digest": parsed.digest, "data": parsed.body, "meta": {"byte_length": int(parsed.byte_length), "acked": parsed.get("acked") == true}}
		elif kind == "photo":
			var exported: Dictionary = PhotoLibrary.new(base.path_join("photo-library")).export_entry(player, key.get_slice("/", 2))
			if exported.get("ok", false) and not exported.entry.deleted:
				var created := int(Time.get_unix_time_from_datetime_string(str(exported.entry.created_at).left(19)))
				items[key] = {"kind": kind, "owner": player, "rev": int(exported.entry.photo_revision), "at": maxi(0, created), "digest": exported.entry.sha256, "data": JSON.stringify(exported.entry), "meta": {}}
		elif _size(path) <= SharedReplayStore.MAX_TRANSFER_BYTES:
			var text := FileAccess.get_file_as_string(path)
			var parsed: Variant = JSON.parse_string(text)
			if parsed is Dictionary and _shared_owner(parsed, path.get_file()) == player:
				items[key] = {"kind": kind, "owner": player, "rev": int(parsed.get("generation", 0)), "at": at, "digest": text.sha256_text(), "data": text, "meta": {}}
	return items

## The player a shared replay file belongs to (its scope's id), or "" unless the file is named by that scope.
static func _shared_owner(value: Dictionary, file_name: String) -> String:
	var scope: Variant = value.get("shared_replay_scope")
	if not scope is String or scope.sha256_text() + ".json" != file_name: return ""
	return scope.get_slice(":", 1)

## The first time for this player here, writes what this phone lacks of their items. True:
## anything that failed its check is left in the slot and never written here.
func apply(merged: Dictionary) -> bool:
	var player := owner()
	if player.is_empty() or not at_home(): return false
	var restored_key := "r%d_restored_for" % (slot + 1)
	if _state != null and _state.cloud(restored_key) == player: return true
	var history := HistoryStore.new(root.path_join("history"))
	_wrote_shared = false
	for key: String in merged.get("items", {}):
		var item: Dictionary = merged.items[key]
		if item.owner == player and Bundle.slot_of(key) == slot: restore(history, key, item, player)
	settled()
	# The shared replay collection keeps its index in memory: it reads the restored files afresh.
	var host := _main()
	var collection: Variant = host.get("shared_replays") if host != null else null
	if _wrote_shared and collection is Object and collection.has_method("invalidate_identity"): collection.invalidate_identity()
	return true

## A run finished with this phone and the slot joined: from now on nothing is restored here for
## this player, whatever the slot holds that the phone has let go.
func settled() -> void:
	var player := owner()
	if _state != null and not player.is_empty(): _state.set_cloud({"r%d_restored_for" % (slot + 1): player})

## One item through its owner's checks; true once this phone has it.
func restore(history: RefCounted, key: String, item: Dictionary, player: String) -> bool:
	var parts := key.split("/")
	var meta: Dictionary = item.meta
	if item.kind == "room" and parts.size() == 5 and parts[1] == player and _matches(parts[2], SERVER) and str(meta.get("server")) == parts[2] and str(meta.get("room")) == parts[3]:
		var record := {"position": int(meta.get("position", -1)), "link": meta.get("link"), "digest": item.digest, "byte_length": int(meta.get("byte_length", 0))}
		if parts[4] != "%d-%s" % [record.position, str(record.link).left(16)]: return false
		return history.restore(parts[2], player, parts[3], record, Marshalls.base64_to_raw(item.data))
	if item.kind == "duel" and parts.size() == 3 and parts[1] == player and _matches(parts[2], DUEL_NAME):
		var length := int(meta.get("byte_length", 0))
		if BlobCodec.verified(Marshalls.base64_to_raw(item.data), length, item.digest, DuelTheirRun.LeaderboardReplay.MAX_CANONICAL_BYTES).is_empty(): return false
		return DuelTheirRun.restore(player, parts[2], {"digest": item.digest, "byte_length": length, "body": item.data, "acked": meta.get("acked") == true}, root.path_join("duel_runs"))
	if item.kind == "photo" and parts.size() == 3 and parts[1] == player:
		var entry: Variant = JSON.parse_string(item.data)
		if not entry is Dictionary or entry.get("entry_id") != parts[2] or entry.get("sha256") != item.digest or entry.get("deleted") != false: return false
		var library := PhotoLibrary.new(root.path_join("photo-library"))
		if library.export_entry(player, parts[2]).get("ok", false): return true
		return library.import_entry(player, entry).get("ok", false)
	if item.kind == "shared" and parts.size() == 2 and _matches(parts[1], SHARED_NAME):
		var text: String = item.data
		var parsed: Variant = JSON.parse_string(text)
		if text.sha256_text() != item.digest or not parsed is Dictionary or _shared_owner(parsed, parts[1]) != player: return false
		var checked := SharedReplayStore.decode_scope({"ok": true, "scope": parsed.shared_replay_scope, "raw": [text.to_utf8_buffer()]})
		if not checked.get("ok", false) or not checked.get("found", false): return false
		var path := root.path_join("shared-replays").path_join(parts[1])
		for candidate: String in AtomicFile.read_candidates(path):
			if FileAccess.file_exists(candidate): return true
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		_wrote_shared = AtomicFile.write_text(path, text) or _wrote_shared
		return _wrote_shared
	return false

static func _files(path: String) -> Array:
	return Array(DirAccess.get_files_at(path)) if DirAccess.dir_exists_absolute(path) else []

static func _folders(path: String) -> Array:
	return Array(DirAccess.get_directories_at(path)) if DirAccess.dir_exists_absolute(path) else []

static func _size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return 0
	var length := file.get_length()
	file.close()
	return length

## Compiles every pattern on the main thread, so the worker only reads the cache.
static func warm() -> void:
	Bundle.warm()
	for pattern: String in [DUEL_NAME, SHARED_NAME, SERVER, PHOTO_ENTRY]: _matches("", pattern)

static func _matches(text: String, pattern: String) -> bool:
	return Bundle._matches(text, pattern)
