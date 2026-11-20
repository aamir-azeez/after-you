extends RefCounted
## Descriptor for rolling-home@2. Fields: content/chapters/index.gd.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DATA := {
	"key": "rolling-home@2",
	"family": "cooperative",
	"definition": ["res://core/cooperative/rolling_home_v2_catalog.gd", "definition"],
	"world": "res://presentation/cooperative_world.gd",
	"scene": "res://rolling_home_v2.tscn",
	"local_path": "user://rolling-home-journey-v2.json",
	"version_of": "rolling-home@1",
	"released": false,
	"copy": {
		"summary": PlayerCopy.COOPERATIVE_ROLLING_SUMMARY,
		"completion": PlayerCopy.COOPERATIVE_COMPLETION,
	},
	"letter": {"stamp": "bee", "address": [PlayerCopy.LETTER_LONG_WAY_ROUND, PlayerCopy.LETTER_LONG_WAY_ROUND_LINE],
		"postmark": PlayerCopy.LETTER_POST_MEADOW, "signoff": PlayerCopy.LETTER_SEE_YOU_SOON},
	"thumbnail": "res://assets/paid_levels/rolling-home.png",
	"dressing": "res://content/dressing/rolling_home.gd",
	# The ball rolled home.
	"sound_cues": {"prop_fitted": "ball_home"},
	"server": {"flag": "ROLLING_HOME_V2_CHAPTER_ENABLED", "max_branches": 7},
}
