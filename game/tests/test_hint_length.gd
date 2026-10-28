extends SceneTree
## Every chapter's stage hints fit the chapter HUD's hint line in two lines at
## most, measured on the real label (presentation/chapter_controls.gd) in its
## tightest layout: a 1280x720 screen with the reactions pill docked beside
## Finish, which leaves the hint about 616 px. A phone (1560x720 and wider)
## gives it 680. Each hint is read as the player reads it: from the chapter's
## stage presentation (stage copy, the authored stage or the native stage),
## through PlayerCopy.from_canonical, online and solo. New chapters are
## covered from the registry alone.
const Registry = preload("res://services/chapter_registry.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const ChapterControls = preload("res://presentation/chapter_controls.gd")
const RunReactions = preload("res://presentation/run_reactions.gd")
const MAX_LINES := 2
var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var controls := ChapterControls.new()
	root.add_child(controls)
	controls.dock_beside_finish(Control.new(), RunReactions.SIZE)
	await process_frame
	await process_frame
	var width := controls.hint_label.size.x
	_check(width >= 600.0 and width <= 640.0, "The tightest layout leaves the hint about 616 px (%.0f)" % width)
	var seen: Dictionary = {}
	for key: String in Registry.keys():
		var level := Registry.definition(key)
		for stage: Dictionary in level.get("stages", []):
			var shown := Registry.stage_presentation(key, stage)
			for role: String in ["a", "b"]:
				for solo: bool in [false, true]:
					var hint := PlayerCopy.from_canonical(str(shown.get("hint_" + role, "")), solo)
					if hint.is_empty() or seen.has(hint): continue
					seen[hint] = true
					var lines := _lines(controls, hint, solo)
					_check(lines <= MAX_LINES, "%s %s hint_%s%s takes %d lines: %s" % [key, stage.get("id", ""), role, " solo" if solo else "", lines, hint])
	_check(seen.size() > 20, "Every chapter's hints were read (%d)" % seen.size())
	print("HINT LENGTH: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## The hint's line count on the HUD's own label, set through update_state.
func _lines(controls: Node, hint: String, solo: bool) -> int:
	controls.solo = solo
	# update_state reads the message through from_canonical; the hint passed
	# here is already the player's line, which maps to itself.
	controls.update_state("", 10.0, {"tick": 0, "duration_ticks": 600, "message": hint, "can_commit": false, "context_action": {}}, true)
	return controls.hint_label.get_line_count()

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
