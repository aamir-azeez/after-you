extends RefCounted
## Separate account-scoped safety state; never shares gameplay/photo journals.
const Save = preload("res://services/local_save.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const MAX_FILE := 96 * 1024
static var suppressed_rooms: Dictionary = {}
var directory := "user://safety"

func _init(path: String = "user://safety") -> void:
	directory = path

static func matches(value: Variant, pattern: String) -> bool:
	if not value is String: return false
	var regex := RegEx.new()
	regex.compile(pattern)
	return regex.search(value) != null

static func id(value: Variant) -> bool: return matches(value, "^[A-Za-z0-9_-]{22}$")
static func empty(owner: String) -> Dictionary:
	return {"schema_version": 1, "owner": owner, "blocked_players": [], "blocked_rooms": {}, "pending": {}, "receipt": {}}

static func valid_report(body: Variant) -> bool:
	if not body is Dictionary or body.size() != 6 or not body.has("photo") or body.get("schema_version") != 1 or body.get("room_family") not in ["legacy", "relay"] or not id(body.get("room_id")) or not matches(body.get("idempotency_key"), "^[A-Za-z0-9_-]{16,80}$") or body.get("reason") not in ["sexual_content", "child_safety", "harassment", "hate", "privacy", "other"]: return false
	if body.get("photo") == null: return true
	var photo: Variant = body.photo
	if body.room_family != "relay" or not photo is Dictionary or photo.size() != 3 or not matches(photo.get("turn_id"), "^t(?:[0-9]|[12][0-9]|3[01])-[01]-[ab]$") or not matches(photo.get("sha256"), "^[a-f0-9]{64}$"): return false
	var revision: Variant = photo.get("photo_revision")
	return (revision is int or revision is float) and is_finite(float(revision)) and revision == floor(float(revision)) and revision >= 1 and revision <= 1000000

static func valid_receipt(value: Variant) -> bool:
	return value is Dictionary and value.size() == 4 and value.get("schema_version") == 1 and value.get("received") == true and matches(value.get("report_id"), "^[a-f0-9]{64}$") and matches(value.get("request_hash"), "^[a-f0-9]{64}$")

static func valid(value: Variant, owner: String) -> bool:
	if not value is Dictionary or value.size() != 6 or value.get("schema_version") != 1 or value.get("owner") != owner or not value.get("blocked_players") is Array or value.blocked_players.size() > 128 or not value.get("blocked_rooms") is Dictionary or value.blocked_rooms.size() > 128 or not value.get("pending") is Dictionary or not value.get("receipt") is Dictionary: return false
	var seen: Array = []
	for player: Variant in value.blocked_players:
		if not id(player) or player == owner or player in seen: return false
		seen.append(player)
	for room: Variant in value.blocked_rooms:
		if not matches(room, "^(legacy|relay):[A-Za-z0-9_-]{22}$") or not id(value.blocked_rooms[room]) or value.blocked_rooms[room] == owner or value.blocked_rooms[room] not in value.blocked_players: return false
	return (value.pending.is_empty() or valid_report(value.pending)) and (value.receipt.is_empty() or valid_receipt(value.receipt))

func read(owner: String) -> Dictionary:
	if not id(owner): return {"ok": false}
	var path := directory.path_join(owner.sha256_text() + ".json")
	var exists := false
	for suffix: String in ["", ".tmp", ".backup"]:
		if not FileAccess.file_exists(path + suffix): continue
		exists = true
		var file := FileAccess.open(path + suffix, FileAccess.READ)
		if file == null or file.get_length() > MAX_FILE: return {"ok": false}
		var parser := JSON.new()
		var error := parser.parse(file.get_as_text())
		file.close()
		if error == OK and parser.data is Dictionary:
			if parser.data.get("version") != 1 or not parser.data.has("safety") or not valid(parser.data.safety, owner): return {"ok": false}
	var save := Save.new(path)
	save.load_data()
	if save.read_only or (exists and save.loaded_from.is_empty()): return {"ok": false}
	var value: Variant = save.data.get("safety", empty(owner))
	return {"ok": true, "value": value.duplicate(true), "save": save} if valid(value, owner) else {"ok": false}

func write(owner: String, value: Dictionary, expected: Dictionary) -> bool:
	if not valid(value, owner): return false
	var latest := read(owner)
	if not latest.get("ok", false) or not Canonical.same(latest.value, expected): return false
	if DirAccess.make_dir_recursive_absolute(directory) != OK: return false
	return latest.save.update_values({"safety": value.duplicate(true)})

func partner_allowed(owner: String, family: String, room: String, peer: String = "") -> bool:
	if suppressed_rooms.has(owner + ":" + family + ":" + room): return false
	var result := read(owner)
	return result.get("ok", false) and not result.value.blocked_rooms.has(family + ":" + room) and (peer.is_empty() or peer not in result.value.blocked_players)

func erase(owner: String) -> bool:
	if not id(owner): return false
	var path := directory.path_join(owner.sha256_text() + ".json")
	for suffix: String in ["", ".tmp", ".backup"]:
		if FileAccess.file_exists(path + suffix) and DirAccess.remove_absolute(path + suffix) != OK: return false
	for key: String in suppressed_rooms.keys():
		if key.begins_with(owner + ":"): suppressed_rooms.erase(key)
	return true
