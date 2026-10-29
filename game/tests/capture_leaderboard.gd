extends SceneTree
## Development tool, not a suite: captures the leaderboard page and its four
## celebrations through the game's own screens (presentation/leaderboard_screen.gd,
## presentation/leaderboard_celebration.gd, still and live pips), with a fake
## board transport and example names and times. tests/ is never exported, so
## no player build has it. Needs a GPU (a rendered, not headless, run) at
## 1280x720, from a copy of the game whose window starts off screen:
##   godot --path <copy> --position -20000,-20000 --resolution 1280x720 --script res://tests/capture_leaderboard.gd -- --out=<dir>
## Writes <dir>/leaderboard-board.png, leaderboard-board-empty.png, and
## celebration-<tier>-motion.png and celebration-<tier>.png for each tier, plus
## celebration-third-reduced.png (Reduce motion's final pose).
## --size=WxH draws into a SubViewport of that size instead (the page laid out
## 720 high, as the phone's stretch does), and --only=board skips the
## celebrations. The rows wear the pairs' looks, as in the approved art 01.
const Runs = preload("res://services/leaderboard_runs.gd")
const Placings = preload("res://services/leaderboard_placings.gd")
const Client = preload("res://services/leaderboard_client.gd")
const TurnLooks = preload("res://services/turn_looks.gd")
const Wardrobe = preload("res://services/wardrobe.gd")
const Outfit = preload("res://services/outfit.gd")
const Snapshots = preload("res://presentation/kit/pip_snapshots.gd")
const Screen = preload("res://presentation/leaderboard_screen.gd")
const Celebration = preload("res://presentation/leaderboard_celebration.gd")
const Registry = preload("res://services/chapter_registry.gd")
const OWNER := "OOOOOOOOOOOOOOOOOOOOOO"
const PARTNER := "GGGGGGGGGGGGGGGGGGGGGG"
const MINE := "a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1"
const NEWEST := "a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3"
const HASH := "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
const TICKS_PER_SECOND := 30
## The example board: [names or null, seconds, the pair's looks in slot order], hats and daisies as in art 01.
const HAT := {"hat": "straw_hat"}
const DAISY := {"hat": "daisy"}
const BOARD_ROWS := [[["Finn", "Noor"], 198, [HAT, DAISY]], [["Lee", "Sam"], 204, [HAT, HAT]], [["Ana", "Bo"], 208, [DAISY, HAT]], [null, 211, [HAT, DAISY]], [["Ari", "Sol"], 213, [HAT, DAISY]],
	[["Noah", "Ivy"], 216, [DAISY, HAT]], [null, 219, [HAT, HAT]], [["You", "Maya"], 222, [HAT, DAISY]], [["Ben", "Em"], 226, [DAISY, HAT]], [["Kai", "Luz"], 231, [HAT, HAT]]]
## The page's layout height when drawn at --size, as the phone's stretch lays it out.
const BASE_HEIGHT := 720
## Each tier's moment mid motion (seconds) and its example place and time.
const TIERS := {Placings.TOP_TEN: [0.45, 8, 222], Placings.THIRD: [0.75, 3, 207], Placings.SECOND: [1.0, 2, 202], Placings.FIRST: [1.0, 1, 196]}

## The player's own pip in a straw hat, as in the art.
class Dressed extends RefCounted:
	func active_look() -> Dictionary: return {"hat": "straw_hat"}

class FakeApi extends Node:
	var replies: Dictionary = {}
	func request_json(method: int, path: String, _body: Dictionary = {}, _still: Callable = Callable()) -> Dictionary:
		await Engine.get_main_loop().process_frame
		var name: String = {HTTPClient.METHOD_GET: "GET", HTTPClient.METHOD_PUT: "PUT", HTTPClient.METHOD_POST: "POST"}.get(method, "?")
		return replies.get(name + " " + path, {"ok": false, "code": "not_found"}).duplicate(true)

var _out := "."
var _size := Vector2i.ZERO
var _only := ""
## Where screens are added and read back: the root, or a SubViewport at --size.
var _stage: Node

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): _out = argument.trim_prefix("--out=")
		if argument.begins_with("--only="): _only = argument.trim_prefix("--only=")
		if argument.begins_with("--size="):
			var parts := argument.trim_prefix("--size=").split("x")
			if parts.size() == 2: _size = Vector2i(int(parts[0]), int(parts[1]))
	_run.call_deferred()

## A SubViewport of --size laid out BASE_HEIGHT high, or the root.
func _make_stage() -> Node:
	if _size.x <= 0 or _size.y <= 0: return root
	var view := SubViewport.new()
	view.name = "CaptureStage"
	view.size = _size
	view.size_2d_override = Vector2i(roundi(float(BASE_HEIGHT) * _size.x / _size.y), BASE_HEIGHT)
	view.size_2d_override_stretch = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.set("oversampling_override", float(_size.y) / BASE_HEIGHT)
	root.add_child(view)
	return view

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("CAPTURE needs a rendered run; headless draws nothing.")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_out)
	_stage = _make_stage()
	Outfit.show_unreleased = true
	Wardrobe.use_shared(Dressed.new())
	TurnLooks.use_shared(TurnLooks.new("user://capture-leaderboard-looks.json"))
	TurnLooks.shared().note_member(PARTNER, {"hat": "daisy"})
	Runs.use_path("user://capture-leaderboard-runs.json")
	var file := FileAccess.open("user://capture-leaderboard-runs.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"schema_version": 1, "players": {OWNER: [
		{"board": _board(), "entry_id": MINE, "ticks": 222 * TICKS_PER_SECOND, "assisted": false, "finished_at": "2026-10-20T10:00:00Z", "partner": PARTNER},
		{"board": _board(), "entry_id": NEWEST, "ticks": 207 * TICKS_PER_SECOND, "assisted": false, "finished_at": "2026-10-22T10:00:00Z", "partner": PARTNER}]}}))
	file.close()
	Runs.use_path("user://capture-leaderboard-runs.json")
	Placings.use_shared(Placings.new("user://capture-leaderboard-placings.json"))
	# The board capture is of the page itself; its own celebration is captured on its own.
	Placings.shared().mark_shown(OWNER, MINE)
	await _board_captures()
	if _only != "board": await _celebrations()
	print("CAPTURE DONE")
	quit(0)

static func _board() -> String:
	return Runs.board_key(Registry.LIGHTHOUSE_V2)

func _board_captures() -> void:
	var api := FakeApi.new()
	root.add_child(api)
	var top: Array = []
	for index in range(BOARD_ROWS.size()):
		var entry := MINE if index == 7 else ("%02d" % (index + 1)).repeat(16)
		top.append({"rank": index + 1, "entry_id": entry, "ticks": int(BOARD_ROWS[index][1]) * TICKS_PER_SECOND, "finished_on": "2026-10-20", "names": BOARD_ROWS[index][0], "gold_leaf": index == 0, "replay_hash": HASH, "looks": BOARD_ROWS[index][2]})
	var path := "GET /v1/leaderboards/" + _board()
	api.replies[path] = {"ok": true, "data": {"schema_version": 1, "board": _board(), "top": top, "checking": [NEWEST]}}
	api.replies["GET /v1/leaderboards/me"] = {"ok": true, "data": {"schema_version": 1, "show_name": true}}
	var screen := _screen(api)
	await _save("leaderboard-board")
	screen.close()
	api.replies[path] = {"ok": true, "data": {"schema_version": 1, "board": _board(), "top": [], "checking": []}}
	var empty := _screen(api)
	await _save("leaderboard-board-empty")
	empty.close()
	api.queue_free()

func _screen(api: Node) -> CanvasLayer:
	var screen := Screen.new()
	screen.client = Client.new(api, OWNER, "user://capture-leaderboard-name.json")
	screen.player_id = OWNER
	screen.chapter_key = Registry.LIGHTHOUSE_V2
	screen.reduced_motion = true
	_stage.add_child(screen)
	return screen

func _celebrations() -> void:
	var holder := Control.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stage.add_child(holder)
	for tier: String in TIERS:
		var spec: Array = TIERS[tier]
		var placing := {"entry_id": MINE, "board": _board(), "rank": spec[1], "ticks": int(spec[2]) * TICKS_PER_SECOND, "names": ["You", "Maya"], "gold_leaf": tier == Placings.FIRST, "partner": PARTNER}
		var made: Control = Celebration.open(holder, placing, false)
		while made.elapsed() < float(spec[0]): await process_frame
		await _save("celebration-%s-motion" % tier.replace("_", "-"), 0)
		while not made.settled(): await process_frame
		await _save("celebration-%s" % tier.replace("_", "-"))
		made.close()
		await process_frame
	var reduced: Control = Celebration.open(holder, {"entry_id": MINE, "board": _board(), "rank": 3, "ticks": 207 * TICKS_PER_SECOND, "names": null, "gold_leaf": false, "partner": PARTNER}, true)
	await _save("celebration-third-reduced")
	reduced.close()

## Saves the window once every still pip is drawn and `frames` more have passed.
func _save(name: String, frames: int = 20) -> void:
	var waited := 0
	while (Snapshots.pending() > 0 or waited < frames) and waited < 600:
		await process_frame
		waited += 1
	await RenderingServer.frame_post_draw
	var path := "%s/%s.png" % [_out, name]
	var image := (_stage as Viewport).get_texture().get_image()
	print("SAVED %s %s %s" % [path, image.get_size(), error_string(image.save_png(path))])
