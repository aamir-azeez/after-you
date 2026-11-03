extends VBoxContainer
## The leaderboard line on a together run's end-of-run card: where the run
## stands (services/board_status.gd) in plain words, and, when Forgiving
## catches kept it off the board while this phone still has it on, a button
## that turns it off in place. show_status() redraws it in place, so a board
## read that arrives later changes the words without rebuilding the card.
## A run waiting for its check has no words: its place is celebrated at once
## (presentation/board_feedback_flow.gd), and Home says it is being checked later.
## A run the server kept off for want of a platform account (PLATFORM) says
## who must sign in, and, when it is this player and this phone offers it, a
## Sign in button starts the same sign-in and link as Settings.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const BoardStatus = preload("res://services/board_status.gd")
const Runs = preload("res://services/leaderboard_runs.gd")
const GamesProvider = preload("res://services/platform_games/games_provider.gd")
const PlatformSupport = preload("res://services/platform_support.gd")
const CREAM := Color("eceddb")

## Turns Forgiving catches off on this phone; returns whether it was saved.
var turn_off_assistance: Callable
## Whether this phone has Forgiving catches on now.
var assistance_on: Callable
## Starts the platform sign-in and link, then posts the run again (presentation/board_feedback_flow.gd).
var sign_in: Callable
## Whether this phone can sign in to its platform now (services/platform_games/platform_games.gd offered()).
var sign_in_offered: Callable
## "Play Games" or "Game Center", for the words.
var platform_name := PlayerCopy.PLATFORM_GAMES_PLAY_GAMES

var _text: Label
var _button: Button
var _sign_in_button: Button
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
	_sign_in_button = Button.new()
	_sign_in_button.name = "BoardStatusSignIn"
	_sign_in_button.text = PlayerCopy.BOARD_LINE_SIGN_IN
	_sign_in_button.custom_minimum_size.y = 52
	_sign_in_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_sign_in_button.visible = false
	_sign_in_button.pressed.connect(_sign_in)
	add_child(_sign_in_button)
	visible = false

## "Game Center" on an iPhone, else "Play Games": the platform service's own
## name when it has a provider (services/platform_games/platform_games.gd; null for none).
static func platform_of(games: Node) -> String:
	if games != null and games.kind() != GamesProvider.NONE: return games.display_name()
	return PlayerCopy.PLATFORM_GAMES_GAME_CENTER if PlatformSupport.is_ios() else PlayerCopy.PLATFORM_GAMES_PLAY_GAMES

## The words for a status ({state, ticks, rank, refused}), or "" for none.
## `platform`: "Play Games" or "Game Center", for a PLATFORM status.
static func text(status: Dictionary, platform: String = PlayerCopy.PLATFORM_GAMES_PLAY_GAMES) -> String:
	var time := Runs.time_text(int(status.get("ticks", 0)))
	match str(status.get("state", "")):
		BoardStatus.PLATFORM: return PlayerCopy.BOARD_LINE_PLATFORM_YOU % platform if status.get("refused") == Runs.REFUSED_YOU else PlayerCopy.BOARD_LINE_PLATFORM_PARTNER
		BoardStatus.OFF: return PlayerCopy.BOARD_LINE_OFF
		BoardStatus.ASSISTED: return PlayerCopy.BOARD_LINE_ASSISTED
		BoardStatus.NOT_LISTED: return PlayerCopy.BOARD_LINE_NOT_LISTED % time
		BoardStatus.RANKED:
			var rank := int(status.get("rank", 0))
			if rank >= 1 and rank <= PlayerCopy.LEADERBOARD_ORDINALS.size(): return PlayerCopy.BOARD_LINE_RANKED % [time, PlayerCopy.LEADERBOARD_ORDINALS[rank - 1]]
	return ""

func show_status(status: Dictionary) -> void:
	var words := text(status, platform_name)
	var assisted := str(status.get("state", "")) == BoardStatus.ASSISTED
	if assisted and _turned_off: words = PlayerCopy.BOARD_LINE_TURNED_OFF
	_text.text = words
	_button.visible = assisted and not _turned_off and turn_off_assistance.is_valid() and assistance_on.is_valid() and bool(assistance_on.call())
	var mine: bool = str(status.get("state", "")) == BoardStatus.PLATFORM and status.get("refused") == Runs.REFUSED_YOU
	_sign_in_button.visible = mine and sign_in.is_valid() and sign_in_offered.is_valid() and bool(sign_in_offered.call())
	_sign_in_button.disabled = false
	visible = not words.is_empty()

## One sign-in at a time: the button waits until the flow shows a new status.
func _sign_in() -> void:
	if _sign_in_button.disabled or not sign_in.is_valid(): return
	_sign_in_button.disabled = true
	sign_in.call()

func _turn_off() -> void:
	if _turned_off or not turn_off_assistance.is_valid() or not bool(turn_off_assistance.call()): return
	_turned_off = true
	_text.text = PlayerCopy.BOARD_LINE_TURNED_OFF
	_button.visible = false
