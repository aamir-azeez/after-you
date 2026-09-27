extends RefCounted
## Menu marks use the existing verified keepsake ledger, never draft flags.
const Catalog = preload("res://services/home_keepsake_catalog.gd")

static func chapters(earned: Array[Dictionary]) -> Dictionary:
	var places: Dictionary = {}
	for item: Dictionary in earned:
		places[str(item.get("id", ""))] = item
	var result: Dictionary = {}
	for expected: Dictionary in Catalog.all():
		if expected.chapter_key.is_empty(): continue
		var mark: Dictionary = result.get(expected.chapter_key,{"solo":true,"friend":true})
		var item: Dictionary = places.get(expected.id,{})
		mark.solo = mark.solo and item.get("solo",false)==true
		mark.friend = mark.friend and item.get("friend",false)==true and expected.friend_available
		result[expected.chapter_key] = mark
	return result
