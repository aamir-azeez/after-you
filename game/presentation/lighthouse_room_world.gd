extends "res://presentation/lighthouse_world.gd"
## sleeping-lighthouse@2 in the shared chapter screen. The chapter definition
## lists six stages, each embedding its native Lighthouse stage; the unchanged
## Lighthouse world draws whichever native stage is shown. Room checkpoints
## already carry the native level id, stage index and mechanisms, so remembered
## mechanisms come from the verified checkpoint exactly as in the solo screen.

## The six-stage chapter this world was given, kept for show_stage lookups.
var chapter_level: Dictionary = {}
## The chapter stage show_stage last built, while it is still as built: only
## one state, presented at once (the ready card's opening state), has been
## shown on it since. "" once anything else has been presented.
var _as_built_stage := ""
## That state's hash (0 before the first).
var _as_built_state := 0

func load_level(definition: Dictionary) -> void:
	var stages: Variant = definition.get("stages")
	if stages is Array and not stages.is_empty() and stages[0] is Dictionary and stages[0].get("native") is Dictionary:
		chapter_level = definition
		await show_stage(_opening_stage(stages))
		return
	_as_built_stage = ""
	await super.load_level(definition)

## A chapter stage ({id, native, ...}); the native stage is rebuilt each time,
## as the solo Lighthouse screen does at every turn, except one the world
## still shows as built (present_stage keeps it: Begin on the ready card).
func show_stage(stage: Dictionary) -> void:
	_as_built_stage = ""
	var native: Variant = stage.get("native")
	if not native is Dictionary: return
	await super.load_level(native)
	_as_built_stage = str(stage.get("id", ""))
	_as_built_state = 0

func _shows_as_built(stage_id: String) -> bool:
	return not _as_built_stage.is_empty() and stage_id == _as_built_stage

func present(state: Dictionary, immediate: bool = false) -> void:
	# A moving present (play, a replay) or a second, different state ends it.
	if not _as_built_stage.is_empty():
		var shown := state.hash()
		if not immediate or (_as_built_state != 0 and shown != _as_built_state): _as_built_stage = ""
		else: _as_built_state = shown
	super.present(state, immediate)

func _fold_key() -> String:
	return "sleeping-lighthouse@2"
