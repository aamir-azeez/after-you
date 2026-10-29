extends SceneTree
## The Pollen mark has one source, presentation/kit/pollen_mark.gd: no other
## script draws the grain or its colours, the places that show a Pollen amount
## with its mark get it from there, and the seed picture (the seed timer's own)
## never stands in for Pollen again.
const PollenMark = preload("res://presentation/kit/pollen_mark.gd")
const SOURCE := "res://presentation/kit/pollen_mark.gd"
## The grain's own colours: anything else drawing them is drawing a Pollen mark.
const GRAIN_COLOURS := ["f5c95e", "e7ac45", "eab44c", "dc9f3b"]
## Places that show an amount of Pollen with its mark.
const USERS := ["res://presentation/duels/duel_result_page.gd", "res://presentation/wardrobe_page.gd", "res://presentation/pollen_result_line.gd"]
const SEED := "seed.svg"
const SEED_OWNER := "res://presentation/seed_timer_bar.gd"

var checks := 0
var failures := 0
func _initialize() -> void: _run.call_deferred()
func _check(okay: bool, message: String) -> void:
	checks += 1
	if not okay: failures += 1; push_error(message)

func _run() -> void:
	var scripts: Array[String] = []
	for root_dir: String in ["res://presentation", "res://services", "res://core", "res://content"]: _collect(root_dir, scripts)
	scripts.append("res://main.gd")
	_check(scripts.size() > 100, "the scan reaches the game's scripts: %d" % scripts.size())
	for path: String in scripts:
		if path == SOURCE: continue
		var text := FileAccess.get_file_as_string(path).to_lower()
		for colour: String in GRAIN_COLOURS:
			_check(not text.contains(colour), "%s draws the Pollen grain's colour %s: use presentation/kit/pollen_mark.gd" % [path, colour])
		if path != SEED_OWNER: _check(not text.contains(SEED), "%s uses the seed picture, which is not the Pollen mark" % path)
	for path: String in USERS:
		_check(FileAccess.get_file_as_string(path).contains("res://presentation/kit/pollen_mark.gd"), "%s takes its Pollen mark from the one source" % path)
	var mark: Control = PollenMark.make(PollenMark.TOTAL)
	_check(mark.custom_minimum_size == Vector2(PollenMark.TOTAL, PollenMark.TOTAL) and mark.mouse_filter == Control.MOUSE_FILTER_IGNORE and mark.name == "PollenMark", "a mark is square at its size and takes no input")
	root.add_child(mark)
	await process_frame
	_check(mark.is_inside_tree(), "a mark draws in a page")
	mark.queue_free()
	await process_frame
	print("AFTER YOU POLLEN MARK: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _collect(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null: return
	for file: String in dir.get_files():
		if file.ends_with(".gd"): out.append(dir_path.path_join(file))
	for sub: String in dir.get_directories():
		_collect(dir_path.path_join(sub), out)
