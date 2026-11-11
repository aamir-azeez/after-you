extends Node
## Starts the game with live reload (live_reload.gd) watching the chapter on
## screen: run live_game.tscn as the main scene of an editor build, with
## `-- --live-root=<the worktree's game folder>` to read edits from there.
## It adds the watcher beside the screens (so a scene change keeps it) and
## opens main.tscn as usual. Under tests/, so no export includes it, and
## refusal() stops it outside an editor build, with a server set or with the
## real user folder.
const LiveReload = preload("res://tests/level_tools/live_reload.gd")

func _ready() -> void:
	var reason := refusal()
	if not reason.is_empty():
		push_error("Live reload will not start: " + reason)
		get_tree().quit(1)
		return
	var live: Node = LiveReload.new()
	live.name = "LiveReload"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--live-root="): live.root_dir = argument.trim_prefix("--live-root=")
	get_tree().root.add_child.call_deferred(live)
	get_tree().change_scene_to_file.call_deferred("res://main.tscn")

## Why this game may not run with live reload, or "": only an editor build,
## only a game copy with no server (app_config's api_base_url blank) and only
## with its own user folder (on Windows, APPDATA moved off the real one), so
## live play never reaches the server or a player's saves.
static func refusal() -> String:
	if not OS.has_feature("editor"): return "it runs only in an editor build"
	var config: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://app_config.json"))
	if not config is Dictionary or not str((config as Dictionary).get("api_base_url", "")).is_empty(): return "the game copy has a server set (blank app_config's api_base_url)"
	if OS.get_name() == "Windows":
		var real := OS.get_environment("USERPROFILE").path_join("AppData").path_join("Roaming")
		if OS.get_environment("APPDATA").replace("\\", "/").to_lower() == real.replace("\\", "/").to_lower(): return "APPDATA is the real one (give the game its own user folder)"
	return ""
