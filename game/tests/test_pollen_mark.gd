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
const USERS := ["res://presentation/wardrobe_page.gd", "res://presentation/pollen_result_line.gd", "res://presentation/kit/pollen_chip.gd", "res://presentation/pollen_breakdown_view.gd", "res://presentation/pollen_play_page.gd"]
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
	var mark: Control = PollenMark.make(34.0)
	_check(mark.custom_minimum_size == Vector2(34, 34) and mark.mouse_filter == Control.MOUSE_FILTER_IGNORE and mark.name == "PollenMark", "a mark is square at its size and takes no input")
	root.add_child(mark)
	await process_frame
	_check(mark.is_inside_tree(), "a mark draws in a page")
	mark.queue_free()
	for path: String in USERS:
		var text := FileAccess.get_file_as_string(path)
		_check(text.contains("PollenMark.beside(") and not text.contains("PollenMark.make("), "%s sizes its mark from the amount's font" % path)
	# Beside an amount, at every size the game sets one: the grain's middle is the line's middle, and it stays inside the line.
	for font_size: int in [16, 18, 22, 26, 32]:
		var row := HBoxContainer.new()
		root.add_child(row)
		var amount := Label.new()
		amount.text = "606"
		amount.add_theme_font_size_override("font_size", font_size)
		var beside := PollenMark.beside(font_size)
		row.add_child(beside)
		row.add_child(amount)
		await process_frame
		_check(absf(beside.get_global_rect().get_center().y - amount.get_global_rect().get_center().y) <= 0.5, "a mark at %d is centred on its amount: %s against %s" % [font_size, beside.get_global_rect(), amount.get_global_rect()])
		_check(beside.size.y <= amount.size.y and beside.size.y >= font_size * 0.8, "a mark at %d is as tall as the digits and a bit more, never past the line: %s" % [font_size, beside.size])
		row.queue_free()
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
