extends RefCounted
## The one check for every backup that can run out of space: each backup keeps the newest it can
## and reports how many files it left out (the replay slots in Saved Games, cloud_replay_sources.gd;
## Android's backup agent, through PHONE_FILE). The player is told once (platform_games_flow.gd's
## backup-full notice); OK remembers the total, so the notice shows again only when more stops
## fitting. When fewer are left out (old replays deleted), the remembered total drops with it.
const AtomicFile = preload("res://services/atomic_file.gd")
const Typed = preload("res://services/typed_values.gd")

const PATH := "user://backup-limit.json"
## Written by AfterYouBackupAgent after each Android backup: how many planned files did not fit.
const PHONE_FILE := "user://backup-left-out.txt"
const SOURCE := "^[a-z0-9-]{1,32}$"
const MAX_SOURCES := 16

static func _read(path: String) -> Dictionary:
	var value: Variant = AtomicFile.read_json(path, func(candidate: Variant) -> bool: return candidate is Dictionary) if FileAccess.file_exists(path) else null
	var out := {"left_out": {}, "seen": 0}
	if not value is Dictionary or not value.get("left_out") is Dictionary or not Typed.whole_number(value.get("seen")): return out
	for source: Variant in value.left_out:
		if source is String and RegEx.create_from_string(SOURCE).search(source) != null and Typed.whole_number(value.left_out[source]): out.left_out[source] = maxi(0, int(value.left_out[source]))
	out.seen = maxi(0, int(value.seen))
	return out

## How many files `source` left out of its last backup.
static func note(source: String, left_out: int, path: String = PATH) -> void:
	if RegEx.create_from_string(SOURCE).search(source) == null: return
	var held := _read(path)
	var count := maxi(0, left_out)
	if int(held.left_out.get(source, 0)) == count: return
	if count == 0: held.left_out.erase(source)
	elif held.left_out.size() < MAX_SOURCES or held.left_out.has(source): held.left_out[source] = count
	held.seen = mini(int(held.seen), total(held))
	AtomicFile.write_text(path, JSON.stringify(held))

## Reads the count Android's backup agent left (none on other platforms).
static func note_phone(path: String = PATH, phone_file: String = PHONE_FILE) -> void:
	if not FileAccess.file_exists(phone_file): return
	var text := FileAccess.get_file_as_string(phone_file).strip_edges()
	if text.is_valid_int(): note("phone", int(text), path)

static func total(held: Dictionary) -> int:
	var sum := 0
	for source: String in held.left_out: sum += int(held.left_out[source])
	return sum

## Whether more is left out than the player has already been told about.
static func due(path: String = PATH) -> bool:
	var held := _read(path)
	return total(held) > int(held.seen)

## OK (or Open replays): remembered until more stops fitting.
static func acknowledge(path: String = PATH) -> void:
	var held := _read(path)
	if int(held.seen) == total(held): return
	held.seen = total(held)
	AtomicFile.write_text(path, JSON.stringify(held))
