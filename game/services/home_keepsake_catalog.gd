extends RefCounted
## Public, authored keepsake identities. No room, player or friend information.
## A registered chapter lists its places in its descriptor ("keepsakes", in
## content/chapters/); this file adds the entries that are not registered
## chapters and works out the browse order.
const Index = preload("res://content/chapters/index.gd")
const LIGHTHOUSE := "sleeping-lighthouse@1"
## The earlier islands' places, first in browse order.
const EARLIER_ROWS := [
	["earlier", "first-light", "First Light"],
	["earlier", "long-way-home", "Long Way Home"],
	["earlier", "patient-garden", "Patient Garden"],
	["earlier", "rising-together", "Rising Together"],
	["earlier", "across-the-blue", "Across the Blue"],
	["earlier", "lantern-crossing", "Lantern Crossing"],
	["earlier", "two-beats", "Two Beats"],
	["earlier", "after-you", "After You"]]
## Keys that are not registered chapters: their browse position, places and save.
const OTHER_CHAPTERS := {
	LIGHTHOUSE: {"position": 2, "local_path": "user://lighthouse-journey-v3.json", "places": [
		["borrowed-light", "Borrowed Light"],
		["missing-piece", "The Missing Piece"],
		["two-promises", "Two Promises"],
		["after-the-first-bell", "After the First Bell"],
		["what-carried-you", "What Carried You Can Come With You"],
		["a-welcome-left-on", "A Welcome, Left On"]]},
}
## Browse order. A registered chapter that is a version of a key Home knows
## only by that key (the Lighthouse @2 of @1) is browsed under it.
static var CHAPTERS: Array = _chapters()
## A later version of a chapter earns the same places as the version it replaces.
static var ALIASES: Dictionary = _aliases()
## [chapter key or "earlier", stage id, title] per place, in browse order.
static var ROWS: Array = _rows()

static func _chapters() -> Array:
	var result: Array = []
	for key: String in Index.keys():
		var version_of: String = Index.data(key).version_of
		if version_of.is_empty() or version_of in Index.keys(): result.append(key)
	for key: String in OTHER_CHAPTERS: result.insert(OTHER_CHAPTERS[key].position, key)
	result.make_read_only()
	return result

static func _aliases() -> Dictionary:
	var result: Dictionary = {}
	for key: String in Index.keys():
		if not Index.data(key).version_of.is_empty(): result[key] = Index.data(key).version_of
	result.make_read_only()
	return result

static func _rows() -> Array:
	var result: Array = EARLIER_ROWS.duplicate()
	for key: String in CHAPTERS:
		if OTHER_CHAPTERS.has(key):
			for place: Array in OTHER_CHAPTERS[key].places: result.append([key, place[0], place[1]])
		else:
			for place: Dictionary in Index.data(key).keepsakes: result.append([key, place.stage_id, place.title])
	for row: Array in result: row.make_read_only()
	result.make_read_only()
	return result

static func all() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var lighthouse_together := lighthouse_together()
	for row: Array in ROWS:
		var family := str(row[0]).get_slice("@", 0)
		result.append({"id": family + "/" + str(row[1]), "title": row[2], "family": family,
			"chapter_key": "" if family == "earlier" else row[0], "stage_id": row[1],
			"friend_available": row[0] != LIGHTHOUSE or lighthouse_together})
	return result

## The Lighthouse's six places gain together variants when its six-stage
## chapter (sleeping-lighthouse@2) is released, which is when it can be played
## with a friend. Loaded, not preloaded: the registry's worlds preload this file.
static func lighthouse_together() -> bool:
	return not load("res://services/chapter_registry.gd").UNRELEASED.has("sleeping-lighthouse@2")

## Collectable variants: every place solo, plus together where a friend variant exists.
static func variant_total() -> int:
	var total := 0
	for item: Dictionary in all(): total += 2 if item.friend_available else 1
	return total

## Earned variants in descriptors carrying solo/friend marks.
static func variant_count(earned: Array) -> int:
	var count := 0
	for item: Variant in earned:
		if not item is Dictionary: continue
		var place := by_id(str(item.get("id", "")))
		if place.is_empty(): continue
		if item.get("solo", false) == true: count += 1
		if item.get("friend", false) == true and place.friend_available: count += 1
	return count

static func by_id(id: String) -> Dictionary:
	for item: Dictionary in all():
		if item.id == id: return item
	return {}

static func chapter_place(chapter_key: String, stage_id: String) -> String:
	chapter_key = str(ALIASES.get(chapter_key, chapter_key))
	for item: Dictionary in all():
		if item.chapter_key == chapter_key and item.stage_id == stage_id: return item.id
	return ""

static func chapter_places(chapter_key: String) -> Array[String]:
	chapter_key = str(ALIASES.get(chapter_key, chapter_key))
	var result: Array[String] = []
	for item: Dictionary in all():
		if item.chapter_key == chapter_key: result.append(item.id)
	return result

static func local_path(chapter_key: String) -> String:
	if OTHER_CHAPTERS.has(chapter_key): return OTHER_CHAPTERS[chapter_key].local_path
	return str(Index.data(chapter_key).local_path) if chapter_key in CHAPTERS else ""
