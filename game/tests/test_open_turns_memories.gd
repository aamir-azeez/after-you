extends "res://tests/test_open_turns.gd"
## The hand-off (nothing acts twice, divergence only from the live pip, a
## drowned friend fails the turn), ten turns of passes, and the save, load and
## step round trip; see test_open_turns.gd.

func _suite() -> String:
	return "open_turns_memories"
