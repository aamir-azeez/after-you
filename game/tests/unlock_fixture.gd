extends RefCounted
## Chapter unlocks for tests that open chapters past First Steps
## (services/chapter_unlocks.gd). Progress is built through the gate's own
## progress(), from marks or from chapters already played, so the gate is
## never loosened. A test Main overrides _chapter_unlocks() with one of these.
const ChapterUnlocks = preload("res://services/chapter_unlocks.gd")

## Every chapter already played: all open, and no completion tick changes.
static func all_played(full_journey: bool = true) -> Dictionary:
	var touched := {}
	for key: String in ChapterUnlocks.chain(): touched[key] = true
	return ChapterUnlocks.progress({}, touched, full_journey)

## Marks with every chapter up to and including `last` finished in `mode`
## ("solo", "friend" or "duel"), as ChapterCompletion.chapters() gives them.
static func finished_through(last: String, mode: String = "solo") -> Dictionary:
	var marks := {}
	for key: String in ChapterUnlocks.chain():
		marks[key] = {mode: true}
		if key == last: break
	return marks

## For tests that run the real main.tscn: earns the first place of every
## chapter solo in the keepsake ledger (Main's, unless `path` names another),
## so each chapter counts as played and stays open while no chapter is
## finished. True once written.
static func seed_played(path: String = "") -> bool:
	var Ledger: GDScript = load("res://services/home_keepsakes.gd")
	var Catalog: GDScript = load("res://services/home_keepsake_catalog.gd")
	var marks := {}
	for key: String in ChapterUnlocks.chain():
		var places: Array[String] = Catalog.chapter_places(key)
		if not places.is_empty(): marks[places[0]] = {"solo": true}
	return Ledger.new(Ledger.PATH if path.is_empty() else path).adopt_earned(marks)
