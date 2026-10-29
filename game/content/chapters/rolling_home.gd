extends RefCounted
## Descriptor for rolling-home@1. Fields: content/chapters/index.gd.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DATA := {
	"key": "rolling-home@1",
	"family": "cooperative",
	"definition": ["res://core/cooperative/stage_catalog.gd", "definition", "rolling-home"],
	"world": "res://presentation/cooperative_world.gd",
	"scene": "res://rolling_home.tscn",
	"local_path": "user://rolling-home-journey-v1.json",
	"copy": {
		"summary": PlayerCopy.COOPERATIVE_ROLLING_SUMMARY,
		"completion": PlayerCopy.COOPERATIVE_COMPLETION,
	},
	"thumbnail": "res://assets/paid_levels/rolling-home.png",
	"keepsakes": [
		{"stage_id": "weight-of-a-friend", "title": "Weight of a Friend"},
		{"stage_id": "bring-it-home", "title": "Bring It Home"},
	],
	"dressing": "res://content/dressing/rolling_home.gd",
	# The ball rolled home.
	"sound_cues": {"prop_fitted": "ball_home"},
	# The chapter's keepsake on Home (presentation/keepsakes/).
	"home_keepsake": {
		"builder": "res://presentation/keepsakes/rolling_rail.gd",
		"island": "journey_right",
		"slot": [-0.2, 2.5],
		"yaw": 0.0,
		"copy": {
			"name": PlayerCopy.KEEPSAKE_ROLLING_RAIL_NAME,
			"action": PlayerCopy.KEEPSAKE_ROLLING_RAIL_ACTION,
			"together": PlayerCopy.KEEPSAKE_ROLLING_RAIL_TOGETHER,
			"hard": PlayerCopy.KEEPSAKE_ROLLING_RAIL_HARD,
			"top": PlayerCopy.KEEPSAKE_ROLLING_RAIL_TOP,
		},
		"sounds": {"base": "ball_home", "together": "seed_landed", "hard": "switch_set", "top": "bell_rung"},
	},
	"server": {"flag": "COOP_CHAPTERS_ENABLED", "max_branches": 32},
}
