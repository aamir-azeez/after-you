extends Node
## Starts the game with live reload (live_reload.gd) watching the chapter on
## screen: run live_game.tscn as the main scene of an editor build, with
## `-- --live-root=<the worktree's game folder>` to read edits from there.
## It adds the watcher beside the screens (so a scene change keeps it) and
## opens main.tscn as usual. Under tests/, so no export includes it; an
## export template has no "editor" feature and stops here anyway.
const LiveReload = preload("res://tests/level_tools/live_reload.gd")

func _ready() -> void:
	if not OS.has_feature("editor"):
		push_error("Live reload runs only in an editor build.")
		get_tree().quit(1)
		return
	var live: Node = LiveReload.new()
	live.name = "LiveReload"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--live-root="): live.root_dir = argument.trim_prefix("--live-root=")
	get_tree().root.add_child.call_deferred(live)
	get_tree().change_scene_to_file.call_deferred("res://main.tscn")
