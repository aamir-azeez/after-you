extends SceneTree
## The one Pollen chip (presentation/kit/pollen_chip.gd, pollen board 1): one
## pill split in two, the mark and the amount with thousands commas on the left
## and the plus, only when asked for, on the right; each half its own button,
## at least 48 by 48, that answers only its own tap; a zero balance as the same
## plain chip; the mark level with the amount; and the gain shown on request
## and gone after a moment. With Fruits (Fruits board 2): the Fruit half on the
## Orchard plum between the Pollen half and the plus, its own target and tap,
## 0 for a player with none, and shown only while Fruits show (fruits_for).
const PollenChip = preload("res://presentation/kit/pollen_chip.gd")
const Orchard = preload("res://presentation/kit/orchard_surface.gd")
const PollenSurfaces = preload("res://services/pollen_surfaces.gd")
const FruitWallet = preload("res://services/fruit_wallet.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(800, 200)
	root.add_child(viewport)
	var chip := PollenChip.make(24000, true)
	viewport.add_child(chip)
	await _settle()
	var mark := chip.find_child("PollenMark", true, false) as Control
	_check(chip.amount_label.text == "24,000" and chip.plus_icon != null and not chip.gain_label.visible, "At rest: the amount with commas and a plus while the shop sells")
	_check(mark != null and absf(mark.get_global_rect().get_center().y - chip.amount_label.get_global_rect().get_center().y) <= 1.0, "The mark sits level with the amount")
	_check(chip.size.y >= 48.0 and chip.get_global_rect().encloses(chip.amount_label.get_global_rect()) and chip.get_global_rect().encloses(chip.plus_icon.get_global_rect()), "The chip is a 48 tall target that holds its amount and plus")
	var left: Rect2 = chip.amount_button.get_global_rect()
	var right: Rect2 = chip.plus_button.get_global_rect()
	_check(left.encloses(chip.amount_label.get_global_rect()) and right.encloses(chip.plus_icon.get_global_rect()) and right.size.x >= 48.0 and right.size.y >= 48.0 and absf(left.end.x - right.position.x) <= 0.5 and absf(left.position.y - right.position.y) <= 0.5,
		"One pill split in two: the amount on the left, the plus on the right, each a full target: %s %s" % [left, right])
	var taps: Array = []
	chip.amount_pressed.connect(func() -> void: taps.append("amount"))
	chip.plus_pressed.connect(func() -> void: taps.append("plus"))
	chip.amount_button.pressed.emit()
	chip.plus_button.pressed.emit()
	_check(taps == ["amount", "plus"], "Each half answers its own tap: " + str(taps))
	_check(chip.amount_button.get_theme_stylebox("normal").corner_radius_top_right == 0 and chip.plus_button.get_theme_stylebox("normal").corner_radius_top_left == 0 and chip.plus_button.get_theme_stylebox("normal").corner_radius_top_right > 0,
		"The halves meet square, the pill's ends stay round")
	chip.queue_free()
	chip = PollenChip.make(0, false)
	viewport.add_child(chip)
	await _settle()
	_check(chip.amount_label.text == "0" and chip.plus_icon == null and chip.plus_button == null and chip.amount_button.get_theme_stylebox("normal").corner_radius_top_right > 0, "A zero balance is the same plain chip; without a plus the balance half is the whole pill")
	var narrow := chip.size.x
	chip.show_gain(125, true)
	await _settle()
	_check(chip.gain_label.visible and chip.gain_label.text == "+125" and chip.size.x > narrow and chip.get_global_rect().encloses(chip.gain_label.get_global_rect()), "A gain shows beside the amount and the chip grows to hold it")
	chip.show_gain(0, true)
	_check(chip.gain_label.text == "+125", "A gain of nothing changes nothing")
	await create_timer(PollenChip.GAIN_HOLD + 0.3).timeout
	_check(not chip.gain_label.visible, "The gain goes after a moment (at once under Reduce motion, after the hold)")
	var fresh := PollenChip.make(1234567, false)
	fresh.show_gain(10, false)
	viewport.add_child(fresh)
	await _settle()
	_check(fresh.amount_label.text == "1,234,567" and fresh.gain_label.visible, "A gain asked for before the chip is shown waits for it")
	await _fruits(viewport)
	viewport.queue_free()
	await _settle()
	print("AFTER YOU POLLEN CHIP: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

## The Fruit half (Fruits board 2) and when it shows.
func _fruits(viewport: SubViewport) -> void:
	var chip := PollenChip.make(24000, true, [1101])
	viewport.add_child(chip)
	await _settle()
	var halves: Array = [chip.amount_button, chip.fruits_button, chip.plus_button]
	_check(chip.fruits_label.text == "1,101" and chip.fruits_button.find_child("FruitMark", true, false) != null and chip.amount_button.find_child("FruitMark", true, false) == null, "The Fruit half holds the Fruit mark and the grouped Fruit balance")
	var in_order := true
	for index in range(1, halves.size()):
		var before: Rect2 = halves[index - 1].get_global_rect()
		var after: Rect2 = halves[index].get_global_rect()
		in_order = in_order and absf(before.end.x - after.position.x) <= 0.5 and absf(before.position.y - after.position.y) <= 0.5
	_check(in_order and chip.fruits_button.size.y >= 48.0 and chip.fruits_button.size.x >= 48.0 and chip.fruits_button.get_global_rect().encloses(chip.fruits_label.get_global_rect()), "Pollen, Fruits, plus: one pill, each half a full target holding its amount")
	var plum: StyleBoxFlat = chip.fruits_button.get_theme_stylebox("normal")
	_check(plum.bg_color == Orchard.PLUM_DARK and plum.corner_radius_top_left == 0 and plum.corner_radius_top_right == 0 and chip.amount_button.get_theme_stylebox("normal").corner_radius_top_right == 0, "The Fruit half sits on the Orchard plum, square where it meets its neighbours")
	var taps: Array = []
	chip.amount_pressed.connect(func() -> void: taps.append("amount"))
	chip.fruits_pressed.connect(func() -> void: taps.append("fruits"))
	chip.plus_pressed.connect(func() -> void: taps.append("plus"))
	for half: Button in halves: half.pressed.emit()
	_check(taps == ["amount", "fruits", "plus"], "Each half answers its own tap: " + str(taps))
	chip.queue_free()
	chip = PollenChip.make(24000, false, [0])
	viewport.add_child(chip)
	await _settle()
	_check(chip.fruits_label.text == "0" and chip.fruits_button.get_theme_stylebox("normal").corner_radius_top_right > 0, "A player with no Fruits sees 0; without a plus the Fruit half closes the pill")
	chip.queue_free()
	chip = PollenChip.make(24000, false)
	viewport.add_child(chip)
	await _settle()
	_check(chip.fruits_button == null and chip.find_child("FruitMark", true, false) == null, "Without Fruits there is no Fruit half")
	chip.queue_free()
	var path := "user://test-pollen-chip-fruits-%s.json" % Crypto.new().generate_random_bytes(6).hex_encode()
	var fruits: RefCounted = FruitWallet.new(path)
	var scope := {"server": "https://chip.example.test", "owner": "cccccccccccccccccccccc"}
	_check(PollenChip.fruits_for(scope, PollenSurfaces.new(true), fruits) == [], "Fruits off on the server: no Fruit half")
	fruits.set_enabled(scope.server, scope.owner, true)
	_check(PollenChip.fruits_for(scope, PollenSurfaces.new(true), fruits) == [0], "Fruits on, nothing read yet: 0")
	fruits.note_view(scope.server, scope.owner, {"fruits": {"schema_version": 1.0, "balance": 101.0, "earned": 101.0, "achievements": []}})
	_check(PollenChip.fruits_for(scope, PollenSurfaces.new(true), fruits) == [101], "Fruits on: the kept balance")
	_check(PollenChip.fruits_for(scope, PollenSurfaces.new(false), fruits) == [] and PollenChip.fruits_for({}, PollenSurfaces.new(true), fruits) == [], "A build that sells nothing, or no player, shows no Fruit half")
	for suffix: String in ["", ".tmp", ".backup"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)

func _settle() -> void:
	for frame in range(4): await process_frame

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
