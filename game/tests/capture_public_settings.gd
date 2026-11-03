extends SceneTree
## Development tool, not a suite: captures board 6.1 of the public duels boards,
## the real Settings (Main's own), Friends & notifications, with the Public duels
## switch and the name row as it reads while public duels are open. The server's
## public switches come from the kept switches (services/server_switches.gd), so
## no server is asked. Needs a rendered run from an invisible copy of the game:
##   godot --path <copy> --resolution 1600x738 --script res://tests/capture_public_settings.gd -- --out=<dir> --suffix=-1600x738
## Writes public-6a-settings. Synthetic ids only.
const Main = preload("res://main.gd")
const ServerSwitches = preload("res://services/server_switches.gd")
const Rows = preload("res://presentation/settings_rows.gd")
const PLAYER := "PPPPPPPPPPPPPPPPPPPPPP"
const SERVER := "https://capture.example.test"

class App extends Main:
	func _tester_checks_enabled() -> bool: return false
	func _tester_active() -> bool: return false
	func _relay_identity() -> Dictionary: return {"ready": true, "player_id": PLAYER, "epoch": 1}

var _out := "."
var _suffix := ""

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): _out = argument.trim_prefix("--out=")
		if argument.begins_with("--suffix="): _suffix = argument.trim_prefix("--suffix=")
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("CAPTURE needs a rendered run; headless draws nothing.")
		quit(1)
		return
	var switches := ServerSwitches.new("user://capture-switches.json")
	switches.note(SERVER, {"duels": true, "leaderboards": true, "public_duels": true})
	ServerSwitches.use_shared(switches)
	var app := App.new()
	root.add_child(app)
	for i in range(30): await process_frame
	app.saves.data.settings.merge({"sound": false, "haptics": false, "reduced_motion": true, "graphics_quality": "high"}, true)
	app._apply_settings()
	app.identity_loading = false
	app.home_keepsakes.cancel_backfill()
	app.api.base_url = SERVER
	app.api.player_id = PLAYER
	var badge := root.get_node_or_null("VersionBadge")
	if badge != null: badge.visible = false
	app.settings_flow.show_settings(Rows.FRIENDS)
	await _save("public-6a-settings")
	quit(0)

func _save(name: String) -> void:
	for i in range(40): await process_frame
	await RenderingServer.frame_post_draw
	var path := "%s/%s%s.png" % [_out, name, _suffix]
	print("SAVED %s %s" % [path, error_string(root.get_texture().get_image().save_png(path))])
