extends RefCounted
## The one place that says which platform leaderboard each of our boards posts to: our board key
## ("<level_id>@<version>", services/leaderboard_runs.gd board_key) to its Game Center id and its
## Play Games id. Game Center ids are ours to choose (letters, digits, dots and underscores); Play
## Console makes its own ("CgkI..."), filled in here once the boards exist. An empty id means that
## platform has no board for the chapter yet: nothing is posted there and no button shows.
##
## A new chapter version gets a new row with new ids; the old version's row goes with it, just as
## our own board starts fresh per version (tests/test_platform_boards.gd checks the rows against
## the offered chapters).

const BOARDS := {
	"first-steps@1": {"game_center": "afteryou.first_steps.v1", "play_games": ""},
	"relay-isles@2": {"game_center": "afteryou.relay_isles.v2", "play_games": ""},
	"high-and-low@1": {"game_center": "afteryou.high_and_low.v1", "play_games": ""},
	"the-wishing-well@1": {"game_center": "afteryou.the_wishing_well.v1", "play_games": ""},
	"turn-of-the-tide@2": {"game_center": "afteryou.turn_of_the_tide.v2", "play_games": ""},
	"sleeping-lighthouse@2": {"game_center": "afteryou.sleeping_lighthouse.v2", "play_games": ""},
	"rolling-home@1": {"game_center": "afteryou.rolling_home.v1", "play_games": ""},
	"a-house-for-two@1": {"game_center": "afteryou.a_house_for_two.v1", "play_games": ""},
	"conservatory@1": {"game_center": "afteryou.conservatory.v1", "play_games": ""},
	"long-way-home@2": {"game_center": "afteryou.long_way_home.v2", "play_games": ""},
}

## The platform's id for our board `board` on `kind` (games_provider.gd PLAY_GAMES or GAME_CENTER), or "".
static func id(board: String, kind: String) -> String:
	return str((BOARDS.get(board, {}) as Dictionary).get(kind, ""))

## Our boards that have a board on `kind`.
static func boards(kind: String) -> Array[String]:
	var found: Array[String] = []
	for board: String in BOARDS:
		if not id(board, kind).is_empty(): found.append(board)
	return found
