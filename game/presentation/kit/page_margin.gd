extends MarginContainer
## Kit: the outer margin of a full-screen page that sits in Main's inset overlay
## (the Wardrobe, the Pollen store, Pollen from play). A phone keeps the page's
## own spacing. A screen taller than the phone (a 4:3 or 16:10 tablet, the
## iPhone Duo) centres a page block SafeArea.PAGE_HEIGHT tall instead of
## stretching the page's cards, the rule Friends, the room hub, Settings and the
## leaderboards already follow. Refits when it enters the tree or resizes.
const SafeArea = preload("res://presentation/safe_area.gd")

## Spacing on the left and right, and the least spacing above and below.
var side := 0
var ends := 0

func _init(side_margin: int, end_margin: int) -> void:
	side = side_margin
	ends = end_margin
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_theme_constant_override("margin_left", side)
	add_theme_constant_override("margin_right", side)
	_fit()

func _notification(what: int) -> void:
	if what in [NOTIFICATION_RESIZED, NOTIFICATION_ENTER_TREE]: _fit()

## The spacing above and below for a page `height` tall (the rule, for tests).
static func end_spacing(height: float, minimum: int) -> int:
	return SafeArea.centred(height, SafeArea.PAGE_HEIGHT, minimum)

func _fit() -> void:
	# The page's height, never this container's own: margins raise its minimum
	# size, and a container grown by its minimum must not grow its margins again.
	var spacing := end_spacing(get_parent_area_size().y if is_inside_tree() else 0.0, ends)
	if has_theme_constant_override("margin_top") and get_theme_constant("margin_top") == spacing: return
	add_theme_constant_override("margin_top", spacing)
	add_theme_constant_override("margin_bottom", spacing)
