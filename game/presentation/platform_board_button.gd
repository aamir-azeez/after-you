extends Button
## The button in the leaderboard screen's chapter title row that opens the same chapter's board in
## Google Play Games (Android) or Game Center (iPhone), board 1 of the platform boards concept
## (claude-20261011 platform-boards). Everything it shows comes from PlatformGames
## (services/platform_games/platform_games.gd board_offered), so no screen branches on the
## platform: hidden on desktop, on a build without the platform, while the server has the boards
## off, for a chapter the platform has no board for, and once Game Center turned its sheet down
## this launch. Signed out, a tap signs in first, then opens the board. Offline it greys like
## every other server button (presentation/offline_hold.gd). One open at a time.
##
## The label is the platform's own name. Google's controller badge and Apple's Game Center
## artwork go beside it once their official files are in ICONS; until then it shows the name only.
const ThemeRules = preload("res://presentation/control_theme.gd")
const OfflineHold = preload("res://presentation/offline_hold.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const GamesProvider = preload("res://services/platform_games/games_provider.gd")
## The platforms' own artwork, as downloaded from Google and Apple (never redrawn).
const ICONS := {
	GamesProvider.PLAY_GAMES: "res://assets/ui/platform/google-play-games-badge.png",
	GamesProvider.GAME_CENTER: "res://assets/ui/platform/game-center-icon.png",
}

## Our board key ("<level_id>@<version>") whose platform board a tap opens.
var board := ""
## (text) -> void: where a reason goes (the screen's notice).
var say: Callable
var _service: Node

## The button for `service` (PlatformGames, or null without the autoload).
func _init(service: Node = null, notice: Callable = Callable()) -> void:
	_service = service
	say = notice
	name = "PlatformBoardButton"
	visible = false
	focus_mode = Control.FOCUS_ALL
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	expand_icon = true
	add_theme_constant_override("icon_max_width", 26)
	ThemeRules.secondary(self)
	pressed.connect(_open)

func _ready() -> void:
	OfflineHold.hold(self, say)
	if _service != null and not _service.changed.is_connected(refresh): _service.changed.connect(refresh)
	refresh()

func _exit_tree() -> void:
	if _service != null and _service.changed.is_connected(refresh): _service.changed.disconnect(refresh)

## Shows the button for our board `key` (or hides it).
func show_for(key: String) -> void:
	board = key
	refresh()

func refresh() -> void:
	var shown: bool = _service != null and not board.is_empty() and _service.board_offered(board)
	visible = shown
	if not shown: return
	var platform: String = _service.kind()
	text = PlayerCopy.PLATFORM_BOARD_PLAY_GAMES if platform == GamesProvider.PLAY_GAMES else PlayerCopy.PLATFORM_GAMES_GAME_CENTER
	accessibility_name = text
	tooltip_text = text
	var path: String = ICONS.get(platform, "")
	icon = load(path) if not path.is_empty() and ResourceLoader.exists(path) else null
	OfflineHold.set_enabled(self, not _service.board_showing())

func _open() -> void:
	if _service == null or board.is_empty() or _service.board_showing(): return
	var still := func() -> bool: return is_inside_tree() and is_visible_in_tree()
	await _service.show_board(board, still)
