extends RefCounted
## Names a room's chapter from the room's own level id and version. Every room
## title on the Friends screen, the hub, recent rooms and saved replays comes
## from here, so a title never comes from a picker choice or the first chapter.
## A chapter this build cannot name gets the caller's neutral fallback.
const Registry = preload("res://services/chapter_registry.gd")
const Levels = preload("res://core/levels.gd")
## The neutral name for a room whose chapter this build does not know.
const UNKNOWN := "Saved chapter"
## Room cards key an earlier island as legacy-<level id>.
const LEGACY_PREFIX := "legacy-"

## The registry key ("<id>@<version>") for a level id and version, or "".
static func key(level_id: Variant, version: Variant) -> String:
	if not level_id is String or level_id.is_empty() or level_id.contains("@") or not Registry._integer(version): return ""
	return "%s@%d" % [level_id, int(version)]

## The title of a chapter key, or of a legacy-<id> earlier island.
static func title(chapter_key: String, fallback: String = UNKNOWN) -> String:
	var text := ""
	if chapter_key.begins_with(LEGACY_PREFIX):
		text = legacy_title(chapter_key.trim_prefix(LEGACY_PREFIX), "")
	elif not chapter_key.is_empty():
		text = str(Registry.descriptor(chapter_key).get("title", ""))
	return text if not text.is_empty() else fallback

## The title of a chapter room from its level_id and level_version fields.
static func for_room(room: Dictionary, fallback: String = UNKNOWN) -> String:
	return title(key(room.get("level_id"), room.get("level_version")), fallback)

## The title of an earlier island room by its level id ("first-light").
static func legacy_title(level_id: Variant, fallback: String = UNKNOWN) -> String:
	# Levels.get_level clamps a number to the first island, so only a string id names one.
	if not level_id is String or level_id.is_empty(): return fallback
	var text := str(Levels.get_level(level_id).get("title", ""))
	return text if not text.is_empty() else fallback
