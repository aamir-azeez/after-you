extends Control
## The room left at the foot of a Pollen from play card (pollen boards 1 and
## 7b). While that room is really spare it shows the player's own pip at rest
## among a few loose grains, the board's picture of Pollen earned by playing;
## a shorter room shows nothing, so it never makes a card scroll. It asks for
## no height of its own and takes no input. The pip is a still picture
## (kit/pip_avatar.gd still mode: one shared render, no processing), made the
## first time the room is big enough; layout only runs when the room resizes.
const PipAvatar = preload("res://presentation/kit/pip_avatar.gd")
const PollenMark = preload("res://presentation/kit/pollen_mark.gd")

const PIP := 112.0
## The least room that shows the picture: the pip, its grains and a margin around them.
const ROOM := Vector2(220, 136)
## The loose grains in a row on the ground beside the pip, largest first (pollen board 1's
## Play tile): each its size and its gap after the one before.
const GRAINS := [[26.0, 6.0], [20.0, 8.0], [15.0, 8.0]]
## How far the pip's feet sit above the bottom of its picture.
const FEET := 8.0

var _pip: Control
var _grains: Array[Control] = []

func _init() -> void:
	name = "PollenPlaySpare"
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_place)

## Whether the picture shows (tests).
func showing() -> bool:
	return _pip != null and _pip.visible

func _place() -> void:
	var room := size.x >= ROOM.x and size.y >= ROOM.y
	if room and _pip == null: _make()
	if _pip == null: return
	_pip.visible = room
	for grain: Control in _grains: grain.visible = room
	if not room: return
	# The pip and its grains as one group, centred in the room; the grains rest where its feet do.
	var row := PIP
	for grain: Array in GRAINS: row += float(grain[0]) + float(grain[1])
	var corner := Vector2(roundf((size.x - row) * 0.5), roundf((size.y - PIP) * 0.5))
	_pip.position = corner
	_pip.size = Vector2(PIP, PIP)
	var x := corner.x + PIP
	for index in range(_grains.size()):
		var side: float = GRAINS[index][0]
		x += float(GRAINS[index][1])
		_grains[index].position = Vector2(x, corner.y + PIP - FEET - side)
		_grains[index].size = Vector2(side, side)
		x += side

func _make() -> void:
	_pip = PipAvatar.new(true, PipAvatar.PEACH, Vector2(PIP, PIP), true, true)
	_pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_pip)
	for grain: Array in GRAINS:
		var mark := PollenMark.make(grain[0])
		_grains.append(mark)
		add_child(mark)
