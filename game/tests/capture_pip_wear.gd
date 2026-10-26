extends SceneTree
## Development tool, not a suite: renders every cosmetic with art on the pip
## through the game's own still pip path (kit/pip_snapshots.gd, kit/pip_stage.gd,
## SpiritVisual.wear), unreleased items included, so the art can be compared
## with its concept board. tests/ is never exported, so no player build has it.
## Needs a GPU (a rendered, not headless, run):
##   godot --path game --script res://tests/capture_pip_wear.gd -- --out=<dir>
## Writes <dir>/pip-<item>-<view>-<colour>.png for the Settings header, the
## name page and the Friends chip sizes, peach and mint, plus the default look.
const Snapshots = preload("res://presentation/kit/pip_snapshots.gd")
const Outfit = preload("res://services/outfit.gd")
const Catalog = preload("res://services/cosmetic_catalog.gd")
const Look = preload("res://presentation/spirit_look.gd")
const Preview = preload("res://presentation/kit/spirit_preview.gd")

## The views by name: their control size (drawn at Preview.RENDER_SCALE).
const VIEWS := {"settings": Vector2(72, 100), "name": Vector2(180, 236), "chip": Vector2(42, 56), "large": Vector2(360, 472)}
const COLOURS := {"peach": Look.PEACH, "mint": Look.MINT}

var _out := "."
var _waiting := 0

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): _out = argument.trim_prefix("--out=")
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("CAPTURE needs a rendered run; headless draws nothing.")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_out)
	var items: Array[String] = ["plain"]
	for id: String in Catalog.ids():
		if not Catalog.art(id).is_empty(): items.append(id)
	for id: String in items:
		var outfit := {} if id == "plain" else Outfit.of(id, true)
		for view: String in VIEWS:
			for colour: String in COLOURS:
				var path := "%s/pip-%s-%s-%s.png" % [_out, id, view, colour]
				_waiting += 1
				Snapshots.request(COLOURS[colour], outfit, Vector2i(VIEWS[view] * Preview.RENDER_SCALE), Preview.REST_YAW, _saver(path))
	var frames := 0
	while _waiting > 0 and frames < 6000:
		await process_frame
		frames += 1
	print("CAPTURE DONE %d left after %d frames" % [_waiting, frames])
	quit(0 if _waiting == 0 else 1)

func _saver(path: String) -> Callable:
	return func(_key: String, texture: Texture2D) -> void:
		var image := texture.get_image()
		print("SAVED %s %s %s" % [path, image.get_size(), error_string(image.save_png(path))])
		_waiting -= 1
