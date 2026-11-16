extends "res://tests/chapter_witness.gd"
## turn-of-the-tide@3 played through with real inputs: its recorded routes
## (tests/routes/turn-of-the-tide@3.json, written by scripts/chapter_recording.py) once it
## has them, until then its family's witness (res://tests/journey_witness.gd), which picks
## each stage's routes by stage id.
const KEY := "turn-of-the-tide@3"
const FamilyWitness = preload("res://tests/journey_witness.gd")

func chapter() -> Dictionary:
	return super() if not routes(KEY).is_empty() else FamilyWitness.chapter(KEY)
