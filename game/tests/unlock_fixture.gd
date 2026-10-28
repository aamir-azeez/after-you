extends RefCounted
## Chapter unlocks for tests that open chapters past First Steps
## (services/chapter_unlocks.gd). Progress is built through the gate's own
## progress(), from the same keepsake marks Home reads or from chapters
## already played, so the gate is never loosened. A test Main overrides
## _chapter_unlocks() with one of these (tests/unlocked_main.gd).
const ChapterUnlocks = preload("res://services/chapter_unlocks.gd")
const Catalog = preload("res://services/home_keepsake_catalog.gd")

## Every chapter already played: all open, and no completion tick changes.
static func all_played(full_journey: bool = true) -> Dictionary:
	var touched := {}
	for key: String in ChapterUnlocks.chain(): touched[key] = true
	return ChapterUnlocks.progress([], {}, touched, full_journey)

## One chapter's keepsake ledger places, every one earned in `mode` ("solo" or
## "friend"), as HomeKeepsakes.earned_descriptors() lists them.
static func cleared(key: String, mode: String = "solo") -> Array:
	var earned: Array = []
	for id: String in Catalog.chapter_places(key): earned.append({"id": id, "solo": mode == "solo", "friend": mode == "friend"})
	return earned

## The places of every chapter up to and including `last`, cleared in `mode`.
static func cleared_through(last: String, mode: String = "solo") -> Array:
	var earned: Array = []
	for key: String in ChapterUnlocks.chain():
		earned.append_array(cleared(key, mode))
		if key == last: break
	return earned

## For tests that run the real main.tscn: earns the first place of every
## chapter solo in the keepsake ledger (Main's, unless `path` names another),
## so each chapter counts as played and stays open while no chapter is
## cleared. True once written.
static func seed_played(path: String = "") -> bool:
	var Ledger: GDScript = load("res://services/home_keepsakes.gd")
	var marks := {}
	for key: String in ChapterUnlocks.chain():
		var places: Array[String] = Catalog.chapter_places(key)
		if not places.is_empty(): marks[places[0]] = {"solo": true}
	return Ledger.new(Ledger.PATH if path.is_empty() else path).adopt_earned(marks)
