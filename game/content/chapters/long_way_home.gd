extends RefCounted
## Descriptor for long-way-home@1. Fields: content/chapters/index.gd.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DATA := {
	"key": "long-way-home@1",
	"family": "journey",
	"definition": ["res://core/journey/long_way_home_catalog.gd", "definition"],
	"world": "res://presentation/long_way_home_world.gd",
	"scene": "res://long_way_home.tscn",
	"local_path": "user://long-way-home-journey-v1.json",
	"superseded_by": "long-way-home@2",
	"copy": {
		"title": PlayerCopy.LONG_WAY_HOME_TITLE,
		"summary": PlayerCopy.LONG_WAY_HOME_SUMMARY,
		"completion": PlayerCopy.LONG_WAY_HOME_COMPLETION,
	},
	"stage_copy": {
		"the-path-you-leave": {
			"title": PlayerCopy.LONG_WAY_HOME_PATH_TITLE,
			"hint_a": PlayerCopy.LONG_WAY_HOME_PATH_HINT_A,
			"hint_b": PlayerCopy.LONG_WAY_HOME_PATH_HINT_B,
		},
		"a-place-beside-you": {
			"title": PlayerCopy.LONG_WAY_HOME_PLACE_TITLE,
			"hint_a": PlayerCopy.LONG_WAY_HOME_PLACE_HINT_A,
			"hint_b": PlayerCopy.LONG_WAY_HOME_PLACE_HINT_B,
		},
	},
	"thumbnail": "res://assets/paid_levels/long-way-home.png",
	"keepsakes": [
		{"stage_id": "the-path-you-leave", "title": "The Path You Leave"},
		{"stage_id": "a-place-beside-you", "title": "A Place Beside You"},
	],
	"dressing": "res://content/dressing/long_way_home.gd",
	"server": {"flag": "JOURNEY_CHAPTERS_ENABLED", "max_branches": 32},
}
