extends VBoxContainer
## The leaderboard line on a together run's end-of-run card: where the run
## stands (services/board_status.gd) in plain words, and, when Forgiving
## catches kept it off the board while this phone still has it on, a button
## that turns it off in place. show_status() redraws it in place, so a board
## read that arrives later changes the words without rebuilding the card.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const BoardStatus = preload("res://services/board_status.gd")
const Runs = preload("res://services/leaderboard_runs.gd")
const CREAM := Color("eceddb")

## Turns Forgiving catches off on this phone; returns whether it was saved.
var turn_off_assistance: Callable
## Whether this phone has Forgiving catches on now.
var assistance_on: Callable

var _text: Label
var _button: Button
var _turned_off := false

func _init() -> void:
	name = "BoardStatusLine"
	add_theme_constant_override("separation", 8)
	_text = Label.new()
	_text.name = "BoardStatusText"
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text.add_theme_color_override("font_color", CREAM)
	add_child(_text)
	_button = Button.new()
	_button.name = "BoardStatusTurnOff"
	_button.text = PlayerCopy.BOARD_LINE_TURN_OFF
	_button.custom_minimum_size.y = 52
	_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_button.visible = false
	_button.pressed.connect(_turn_off)
	add_child(_button)
	visible = false

## The words for a status ({state, ticks, rank}), or "" for none.
static func text(status: Dictionary) -> String:
	var time := Runs.time_text(int(status.get("ticks", 0)))
	match str(status.get("state", "")):
		BoardStatus.OFF: return PlayerCopy.BOARD_LINE_OFF
		BoardStatus.ASSISTED: return PlayerCopy.BOARD_LINE_ASSISTED
		BoardStatus.CHECKING: return PlayerCopy.BOARD_LINE_CHECKING % time
		BoardStatus.NOT_LISTED: return PlayerCopy.BOARD_LINE_NOT_LISTED % time
		BoardStatus.RANKED:
			var rank := int(status.get("rank", 0))
			if rank >= 1 and rank <= PlayerCopy.LEADERBOARD_ORDINALS.size(): return PlayerCopy.BOARD_LINE_RANKED % [time, PlayerCopy.LEADERBOARD_ORDINALS[rank - 1]]
	return ""

func show_status(status: Dictionary) -> void:
	var words := text(status)
	var assisted := str(status.get("state", "")) == BoardStatus.ASSISTED
	if assisted and _turned_off: words = PlayerCopy.BOARD_LINE_TURNED_OFF
	_text.text = words
	_button.visible = assisted and not _turned_off and turn_off_assistance.is_valid() and assistance_on.is_valid() and bool(assistance_on.call())
	visible = not words.is_empty()

func _turn_off() -> void:
	if _turned_off or not turn_off_assistance.is_valid() or not bool(turn_off_assistance.call()): return
	_turned_off = true
	_text.text = PlayerCopy.BOARD_LINE_TURNED_OFF
	_button.visible = false
