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
	"server": {"flag": "COOP_CHAPTERS_ENABLED", "max_branches": 32},
}
