extends "res://main.gd"
## Main for tests that open chapters past First Steps: every chapter counts as
## already played (tests/unlock_fixture.gd), so the gate itself is unchanged
## and no completion tick moves. A test sets `unlocks` to draw with other
## progress, or `real` for what Main works out itself from the player's marks,
## journals and rooms.
const UnlockFixture = preload("res://tests/unlock_fixture.gd")

var unlocks: Variant = null
var real := false

func _chapter_unlocks() -> Dictionary:
	if real: return super._chapter_unlocks()
	return UnlockFixture.all_played(_full_journey_access()) if unlocks == null else unlocks
