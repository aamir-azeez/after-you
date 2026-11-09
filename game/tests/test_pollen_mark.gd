extends SceneTree
## The Pollen mark has one source, presentation/kit/pollen_mark.gd: no other
## script draws the grain or its colours, the places that show a Pollen amount
## with its mark get it from there, and the seed picture (the seed timer's own)
## never stands in for Pollen again. The Fruit mark is the same:
## presentation/kit/fruit_mark.gd is the only script with the Fruit's rose, it
## draws flat up to its SMALL size and the game's render above it, and
## kit/currency_mark.gd hands out the right mark for each currency.
const PollenMark = preload("res://presentation/kit/pollen_mark.gd")
const FruitMark = preload("res://presentation/kit/fruit_mark.gd")
const CurrencyMark = preload("res://presentation/kit/currency_mark.gd")
const SOURCE := "res://presentation/kit/pollen_mark.gd"
const FRUIT_SOURCE := "res://presentation/kit/fruit_mark.gd"
## The Fruit's own rose (board 1): anything else writing it is drawing a Fruit.
const FRUIT_COLOURS := ["f8bcc8", "c25f7a"]
## The grain's own colours: anything else drawing them is drawing a Pollen mark.
const GRAIN_COLOURS := ["f5c95e", "e7ac45", "eab44c", "dc9f3b"]
## Places that show an amount of Pollen with its mark.
const USERS := ["res://presentation/kit/shop_kit.gd", "res://presentation/pollen_result_line.gd", "res://presentation/kit/pollen_chip.gd", "res://presentation/pollen_breakdown_view.gd", "res://presentation/duels/duels_screen.gd"]
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
		var text := FileAccess.get_file_as_string(path).to_lower()
		if path != FRUIT_SOURCE:
			for colour: String in FRUIT_COLOURS:
				_check(not text.contains(colour), "%s writes the Fruit's colour %s: use presentation/kit/fruit_mark.gd" % [path, colour])
		if path == SOURCE: continue
		for colour: String in GRAIN_COLOURS:
			_check(not text.contains(colour), "%s draws the Pollen grain's colour %s: use presentation/kit/pollen_mark.gd" % [path, colour])
		if path != SEED_OWNER: _check(not text.contains(SEED), "%s uses the seed picture, which is not the Pollen mark" % path)
	for path: String in USERS:
		var source := FileAccess.get_file_as_string(path)
		_check(source.contains("res://presentation/kit/pollen_mark.gd") or source.contains("res://presentation/kit/currency_mark.gd"), "%s takes its Pollen mark from the one source (or the currency mark, which hands it out)" % path)
	var mark: Control = PollenMark.make(34.0)
	_check(mark.custom_minimum_size == Vector2(34, 34) and mark.mouse_filter == Control.MOUSE_FILTER_IGNORE and mark.name == "PollenMark", "a mark is square at its size and takes no input")
	root.add_child(mark)
	await process_frame
	_check(mark.is_inside_tree(), "a mark draws in a page")
	mark.queue_free()
	for path: String in USERS:
		var text := FileAccess.get_file_as_string(path)
		_check((text.contains("PollenMark.beside(") or text.contains("CurrencyMark.beside(")) and not text.contains("PollenMark.make(") and not text.contains("CurrencyMark.make("), "%s sizes its mark from the amount's font" % path)
	# Beside an amount, at every size the game sets one: the grain's middle is the line's middle, and it stays inside the line.
	for font_size: int in [16, 18, 22, 26, 32, 34]:
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
	await _fruit()
	print("AFTER YOU POLLEN MARK: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _collect(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null: return
	for file: String in dir.get_files():
		if file.ends_with(".gd"): out.append(dir_path.path_join(file))
	for sub: String in dir.get_directories():
		_collect(dir_path.path_join(sub), out)

func _fruit() -> void:
	_check(FruitMark.ROSE_LIGHT == Color("f8bcc8") and FruitMark.ROSE_DEEP == Color("c25f7a") and FruitMark.GREEN == Color("a2bd81"), "the Fruit is the board's rose with the seed's green")
	_check(FruitMark.SMALL == 26.0 and FruitMark.is_flat(26.0) and not FruitMark.is_flat(27.0), "the Fruit is flat up to 26 px and the game's render above that")
	_check(ResourceLoader.exists(FruitMark.RENDER) and load(FruitMark.RENDER) is Texture2D, "the Fruit's render is in the game")
	var fruit: Control = FruitMark.make(34.0)
	_check(fruit.custom_minimum_size == Vector2(34, 34) and fruit.mouse_filter == Control.MOUSE_FILTER_IGNORE and fruit.name == "FruitMark" and fruit.accessibility_name == "Fruits", "a Fruit mark is square at its size, takes no input and reads as Fruits")
	fruit.free()
	for side: float in [16.0, 20.0, 24.0, 40.0]:
		var drawn: Control = FruitMark.make(side)
		root.add_child(drawn)
		await process_frame
		_check(drawn.is_inside_tree() and drawn.size == Vector2(side, side), "a Fruit mark at %d draws in a page" % side)
		drawn.queue_free()
	# The mark for each currency comes from its own source; anything else is Pollen.
	for currency: String in ["pollen", "fruits", "", "gems"]:
		var made: Control = CurrencyMark.make(currency, 20.0)
		var beside: Control = CurrencyMark.beside(currency, 22)
		var expect := "FruitMark" if currency == "fruits" else "PollenMark"
		var source := FRUIT_SOURCE if currency == "fruits" else SOURCE
		var own: Control = FruitMark.beside(22) if currency == "fruits" else PollenMark.beside(22)
		_check(made.name == expect and (made.get_script() as Script).resource_path == source and made.custom_minimum_size == Vector2(20, 20), "currency_mark makes the %s for '%s'" % [expect, currency])
		_check(beside.name == expect and beside.custom_minimum_size == own.custom_minimum_size, "and sizes it beside an amount as its own mark does")
		for each: Control in [made, beside, own]: each.free()
	for font_size: int in [16, 18, 22, 26, 32, 34]:
		var row := HBoxContainer.new()
		root.add_child(row)
		var amount := Label.new()
		amount.text = "606"
		amount.add_theme_font_size_override("font_size", font_size)
		var beside := CurrencyMark.beside("fruits", font_size)
		row.add_child(beside)
		row.add_child(amount)
		await process_frame
		_check(absf(beside.get_global_rect().get_center().y - amount.get_global_rect().get_center().y) <= 0.5, "a Fruit at %d is centred on its amount: %s against %s" % [font_size, beside.get_global_rect(), amount.get_global_rect()])
		_check(beside.size.y <= amount.size.y and beside.size.y >= font_size * 0.8, "a Fruit at %d is as tall as the digits and a bit more, never past the line: %s" % [font_size, beside.size])
		row.queue_free()
	await process_frame
