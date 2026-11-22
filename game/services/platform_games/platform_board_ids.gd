extends RefCounted
## The one place that says which platform leaderboard each of our boards posts to: our board key
## ("<level_id>@<version>", services/leaderboard_runs.gd board_key) to its Game Center id and its
## Play Games id. Game Center ids are ours to choose (letters, digits, dots and underscores); Play
## Console makes its own ("CgkI..."), filled in here once the boards exist. An empty id means that
## platform has no board for the chapter yet: nothing is posted there and no button shows.
##
## A new chapter version gets a new row with new ids; the old version's row goes with it, just as
## our own board starts fresh per version (tests/test_platform_boards.gd checks the rows against
## the offered chapters). A chapter whose definition changed since its board opened ranks on a fresh
## board of ours (leaderboard_runs.gd board_key) but keeps its version's platform ids: those boards
## are the platforms' own and keep their earlier times until they are reset in the consoles.

const BOARDS := {
	"first-steps@1": {"game_center": "afteryou.first_steps.v1", "play_games": "CgkIyOW9iLATEAIQAw"},
	"relay-isles@2": {"game_center": "afteryou.relay_isles.v2", "play_games": "CgkIyOW9iLATEAIQBA"},
	"high-and-low-3b6576ba@1": {"game_center": "afteryou.high_and_low.v1", "play_games": "CgkIyOW9iLATEAIQBQ"},
	"the-wishing-well-14cfffbd@1": {"game_center": "afteryou.the_wishing_well.v1", "play_games": "CgkIyOW9iLATEAIQBg"},
	"turn-of-the-tide-8e29d35f@2": {"game_center": "afteryou.turn_of_the_tide.v2", "play_games": "CgkIyOW9iLATEAIQBw"},
	"sleeping-lighthouse-925adf59@2": {"game_center": "afteryou.sleeping_lighthouse.v2", "play_games": "CgkIyOW9iLATEAIQCA"},
	"rolling-home-3362e8af@1": {"game_center": "afteryou.rolling_home.v1", "play_games": "CgkIyOW9iLATEAIQCQ"},
	"a-house-for-two-f14fb0ab@1": {"game_center": "afteryou.a_house_for_two.v1", "play_games": "CgkIyOW9iLATEAIQCg"},
	"conservatory-5e474141@1": {"game_center": "afteryou.conservatory.v1", "play_games": "CgkIyOW9iLATEAIQCw"},
	"long-way-home-9d91b918@2": {"game_center": "afteryou.long_way_home.v2", "play_games": "CgkIyOW9iLATEAIQDA"},
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
