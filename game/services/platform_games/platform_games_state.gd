extends RefCounted
## What platform games remembers on this phone, in one small file. It holds no credentials and no
## platform account ids: only a one-way player key, the After You id a link was confirmed for,
## the server's last answer about the feature, and cloud save bookkeeping. Losing it costs one
## extra server read or cloud sync, never progress. Written only when something changed.
const AtomicFile = preload("res://services/atomic_file.gd")
const Typed = preload("res://services/typed_values.gd")

const PATH := "user://platform-games-v1.json"
const MAX_BYTES := 8192
## The server's answer is read again after this long (a flag flip reaches phones within a day).
const CAPABILITY_TTL_MS := 24 * 3600 * 1000
## After "no link for this account", a phone without an identity asks again after this long.
const RESTORE_PROBE_TTL_MS := 24 * 3600 * 1000

var path := PATH
var data: Dictionary = {}

func _init(file_path: String = PATH) -> void:
	path = file_path
	load_data()

static func defaults() -> Dictionary:
	return {"schema_version": 1, "capability": {}, "links": {}, "cloud": {}, "restore_probe": {}}

func load_data() -> void:
	data = defaults()
	var text := AtomicFile.read_text(path, func(value: Variant) -> bool: return _valid(value)) if FileAccess.file_exists(path) else ""
	if text.is_empty(): return
	var parsed: Variant = JSON.parse_string(text)
	if _valid(parsed):
		for key: String in data: data[key] = parsed[key]

static func _valid(value: Variant) -> bool:
	if value is String:
		if value.length() > MAX_BYTES: return false
		value = JSON.parse_string(value)
	if not value is Dictionary or not Typed.equal(value.get("schema_version"), 1): return false
	for key: String in ["capability", "links", "cloud", "restore_probe"]:
		if not value.get(key) is Dictionary: return false
	return true

func save() -> bool:
	var text := JSON.stringify(data)
	if text.length() > MAX_BYTES: return false
	return AtomicFile.write_text(path, text)

static func now_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)

## The server's last answer, or {} when it is missing or older than a day.
func capability(now: int = now_ms()) -> Dictionary:
	var held: Dictionary = data.capability
	if not Typed.whole_number(held.get("checked_ms")) or now - int(held.checked_ms) > CAPABILITY_TTL_MS or now < int(held.checked_ms): return {}
	return held

func remember_capability(answer: Dictionary, now: int = now_ms()) -> void:
	data.capability = {"checked_ms": now, "play_games": answer.get("play_games") == true, "web_client_id": str(answer.get("web_client_id", "")), "game_center": answer.get("game_center") == true}
	save()

func forget_capability() -> void:
	if data.capability.is_empty(): return
	data.capability = {}
	save()

## The link this phone last confirmed for a provider: {"player_key", "player_id"} or {}.
func link(provider: String) -> Dictionary:
	var held: Variant = data.links.get(provider)
	return held if held is Dictionary and held.get("player_key") is String and held.get("player_id") is String else {}

func remember_link(provider: String, player_key: String, player_id: String) -> void:
	if link(provider) == {"player_key": player_key, "player_id": player_id}: return
	data.links[provider] = {"player_key": player_key, "player_id": player_id}
	save()

func forget_link(provider: String) -> void:
	if not data.links.has(provider): return
	data.links.erase(provider)
	save()

## A phone with no identity asked the server for this account's link and there was none.
func restore_probed(player_key: String, now: int = now_ms()) -> bool:
	var held: Dictionary = data.restore_probe
	return held.get("player_key") == player_key and Typed.whole_number(held.get("checked_ms")) and now - int(held.checked_ms) < RESTORE_PROBE_TTL_MS and now >= int(held.checked_ms)

func remember_restore_probe(player_key: String, now: int = now_ms()) -> void:
	data.restore_probe = {"player_key": player_key, "checked_ms": now}
	save()

func cloud(key: String, fallback: Variant = null) -> Variant:
	return data.cloud.get(key, fallback)

func set_cloud(values: Dictionary) -> void:
	var next: Dictionary = data.cloud.duplicate()
	next.merge(values, true)
	if next == data.cloud: return
	data.cloud = next
	save()
