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
