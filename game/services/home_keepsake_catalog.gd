extends RefCounted
## Public, authored keepsake identities. No room, player or friend information.
const LIGHTHOUSE := "sleeping-lighthouse@1"
const CHAPTERS := ["first-steps@1", "relay-isles@2", LIGHTHOUSE, "high-and-low@1", "rolling-home@1", "a-house-for-two@1", "conservatory@1", "long-way-home@1"]
const ROWS := [
	["earlier", "first-light", "First Light"],
	["earlier", "long-way-home", "Long Way Home"],
	["earlier", "patient-garden", "Patient Garden"],
	["earlier", "rising-together", "Rising Together"],
	["earlier", "across-the-blue", "Across the Blue"],
	["earlier", "lantern-crossing", "Lantern Crossing"],
	["earlier", "two-beats", "Two Beats"],
	["earlier", "after-you", "After You"],
	["first-steps@1", "a-little-lift", "A Little Lift"],
	["first-steps@1", "a-place-to-grow", "A Place to Grow"],
	["relay-isles@2", "relay", "The Relay"],
	["relay-isles@2", "garden", "The Garden"],
	[LIGHTHOUSE, "borrowed-light", "Borrowed Light"],
	[LIGHTHOUSE, "missing-piece", "The Missing Piece"],
	[LIGHTHOUSE, "two-promises", "Two Promises"],
	[LIGHTHOUSE, "after-the-first-bell", "After the First Bell"],
	[LIGHTHOUSE, "what-carried-you", "What Carried You Can Come With You"],
	[LIGHTHOUSE, "a-welcome-left-on", "A Welcome, Left On"],
	["high-and-low@1", "upper-path", "Upper Path"],
	["high-and-low@1", "down-and-around", "Down and Around"],
	["rolling-home@1", "weight-of-a-friend", "Weight of a Friend"],
	["rolling-home@1", "bring-it-home", "Bring It Home"],
	["a-house-for-two@1", "open-the-house", "Open the House"],
	["a-house-for-two@1", "the-room-below", "The Room Below"],
	["conservatory@1", "a-light-above", "A Light Above"],
	["conservatory@1", "the-way-light-returns", "The Way Light Returns"],
	["long-way-home@1", "the-path-you-leave", "The Path You Leave"],
	["long-way-home@1", "a-place-beside-you", "A Place Beside You"]]

static func all() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for row: Array in ROWS:
		var family := str(row[0]).get_slice("@", 0)
		result.append({"id": family + "/" + str(row[1]), "title": row[2], "family": family,
			"chapter_key": "" if family == "earlier" else row[0], "stage_id": row[1],
			"friend_available": row[0] != LIGHTHOUSE})
	return result

static func by_id(id: String) -> Dictionary:
	for item: Dictionary in all():
		if item.id == id: return item
	return {}

static func chapter_place(chapter_key: String, stage_id: String) -> String:
	for item: Dictionary in all():
		if item.chapter_key == chapter_key and item.stage_id == stage_id: return item.id
	return ""

static func chapter_places(chapter_key: String) -> Array[String]:
	var result: Array[String] = []
	for item: Dictionary in all():
		if item.chapter_key == chapter_key: result.append(item.id)
	return result

static func local_path(chapter_key: String) -> String:
	match chapter_key:
		"relay-isles@2": return "user://relay-journey-v2.json"
		"first-steps@1": return "user://first-steps-journey-v1.json"
		LIGHTHOUSE: return "user://lighthouse-journey-v3.json"
		"high-and-low@1": return "user://high-and-low-journey-v1.json"
		"rolling-home@1": return "user://rolling-home-journey-v1.json"
		"a-house-for-two@1": return "user://a-house-for-two-journey-v1.json"
		"conservatory@1": return "user://conservatory-journey-v1.json"
		"long-way-home@1": return "user://long-way-home-journey-v1.json"
	return ""
