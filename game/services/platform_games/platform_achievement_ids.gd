extends RefCounted
## The one place that says which platform achievement each of our achievements unlocks: our
## achievement id (backend fruits.json, presentation/player_copy.gd FRUIT_GOALS) to its Game Center
## id and its Play Games id. Game Center ids are ours to choose ("afteryou.ach.<our id>"); Play
## Console makes its own ("CgkI..."). Both are filled in here once the achievements exist in the
## consoles. An empty id means that platform has no such achievement yet: nothing is sent there.
##
## The two keepsake goals are left out until the server counts them (a published Play
## achievement cannot be deleted). tests/test_platform_achievements.gd checks the rows against
## the game's goals.

const ACHIEVEMENTS := {
	"together_first": {"game_center": "", "play_games": "CgkIyOW9iLATEAIQEA"},
	"together_five": {"game_center": "", "play_games": "CgkIyOW9iLATEAIQFw"},
	"together_all": {"game_center": "", "play_games": "CgkIyOW9iLATEAIQEw"},
	"hard_first": {"game_center": "", "play_games": "CgkIyOW9iLATEAIQGg"},
	"hard_five": {"game_center": "", "play_games": "CgkIyOW9iLATEAIQGA"},
	"hard_all": {"game_center": "", "play_games": "CgkIyOW9iLATEAIQDQ"},
	"duel_win_first": {"game_center": "", "play_games": "CgkIyOW9iLATEAIQFQ"},
	"duel_win_ten": {"game_center": "", "play_games": "CgkIyOW9iLATEAIQGw"},
	"ghost_first": {"game_center": "", "play_games": "CgkIyOW9iLATEAIQHQ"},
	"ghost_five": {"game_center": "", "play_games": "CgkIyOW9iLATEAIQEg"},
	"public_duel_first": {"game_center": "", "play_games": "CgkIyOW9iLATEAIQGQ"},
	"public_win_first": {"game_center": "", "play_games": "CgkIyOW9iLATEAIQDw"},
	"public_win_five": {"game_center": "", "play_games": "CgkIyOW9iLATEAIQEQ"},
	"public_win_ten": {"game_center": "", "play_games": "CgkIyOW9iLATEAIQFA"},
	"public_win_twenty_five": {"game_center": "", "play_games": "CgkIyOW9iLATEAIQHw"},
	"public_win_fifty": {"game_center": "", "play_games": "CgkIyOW9iLATEAIQIA"},
	"public_win_hundred": {"game_center": "", "play_games": "CgkIyOW9iLATEAIQDg"},
	"public_win_two_hundred": {"game_center": "", "play_games": "CgkIyOW9iLATEAIQHg"},
	"top_ten": {"game_center": "", "play_games": "CgkIyOW9iLATEAIQFg"},
	"gold_leaf": {"game_center": "", "play_games": "CgkIyOW9iLATEAIQHA"},
}

## The platform's id for our achievement `achievement` on `kind` (games_provider.gd PLAY_GAMES or
## GAME_CENTER) in `table` (these rows, or a test's own), or "" when it has none.
static func id(achievement: String, kind: String, table: Dictionary = ACHIEVEMENTS) -> String:
	return str((table.get(achievement, {}) as Dictionary).get(kind, ""))
