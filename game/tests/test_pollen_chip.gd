extends SceneTree
## The one Pollen chip (presentation/kit/pollen_chip.gd, pollen board 1): the
## mark and the amount with thousands commas, the plus only while the shop
## sells, a zero balance as the same plain chip, at least 48 tall, the mark
## level with the amount, and the gain shown on request and gone after a moment.
const PollenChip = preload("res://presentation/kit/pollen_chip.gd")

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
	chip.queue_free()
	chip = PollenChip.make(0, false)
	viewport.add_child(chip)
	await _settle()
	_check(chip.amount_label.text == "0" and chip.plus_icon == null, "A zero balance is the same plain chip; no plus while the shop is off")
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
	viewport.queue_free()
	await _settle()
	print("AFTER YOU POLLEN CHIP: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _settle() -> void:
	for frame in range(4): await process_frame

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
