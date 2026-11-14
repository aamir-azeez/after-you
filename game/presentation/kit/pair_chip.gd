extends Control
## World kit, on the play screen: the action pop-up's pair chip. It shows the
## letter of the input the live pip is at (kit/pair_tags.gd prompt(): a
## lever, a selector, a pressure pad), in the pair's colour and the level's
## tag frame, lit while the input is on, so it matches that pair's floor tiles
## at the gates. The kit decides the letter, colour, frame and state and draws
## them (PairTags.draw_chip); this only holds the last chip and redraws when it
## changes, so a tick that changes nothing draws nothing.
const PairTags = preload("res://presentation/kit/pair_tags.gd")

var chip: Dictionary = {}

func _init() -> void:
	name = "PairChip"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(PairTags.CHIP, PairTags.CHIP)
	custom_minimum_size = size
	visible = false

## Shows `next` (a PairTags badge, {} for none).
func show_chip(next: Dictionary) -> void:
	visible = not next.is_empty()
	if next == chip: return
	chip = next
	queue_redraw()

func _draw() -> void:
	PairTags.draw_chip(self, Rect2(Vector2.ZERO, size), chip)
