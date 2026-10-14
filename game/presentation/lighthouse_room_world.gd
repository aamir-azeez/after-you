extends "res://presentation/lighthouse_world.gd"
## sleeping-lighthouse@2 in the shared chapter screen. The chapter definition
## lists six stages, each embedding its native Lighthouse stage; the unchanged
## Lighthouse world draws whichever native stage is shown. Room checkpoints
## already carry the native level id, stage index and mechanisms, so remembered
## mechanisms come from the verified checkpoint exactly as in the solo screen.

## The six-stage chapter this world was given, kept for show_stage lookups.
var chapter_level: Dictionary = {}

func load_level(definition: Dictionary) -> void:
	var stages: Variant = definition.get("stages")
	if stages is Array and not stages.is_empty() and stages[0] is Dictionary and stages[0].get("native") is Dictionary:
		chapter_level = definition
		show_stage(stages[0])
		return
	await super.load_level(definition)

## A chapter stage ({id, native, ...}); the native stage is rebuilt each time,
## as the solo Lighthouse screen does at every turn.
func show_stage(stage: Dictionary) -> void:
	var native: Variant = stage.get("native")
	if native is Dictionary: await super.load_level(native)
