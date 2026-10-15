extends RefCounted
## Descriptor for turn-of-the-tide@1. Fields: content/chapters/index.gd.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DATA := {
	"key": "turn-of-the-tide@1",
	"family": "journey",
	"definition": ["res://core/journey/turn_of_the_tide_catalog.gd", "definition"],
	"world": "res://presentation/tide_world.gd",
	"scene": "res://turn_of_the_tide.tscn",
	"local_path": "user://turn-of-the-tide-journey-v1.json",
	"copy": {
		"title": PlayerCopy.TURN_OF_THE_TIDE_TITLE,
		"summary": PlayerCopy.TURN_OF_THE_TIDE_SUMMARY,
		"completion": PlayerCopy.TURN_OF_THE_TIDE_COMPLETION,
	},
	"stage_copy": {
		"set-the-tide": {
			"title": PlayerCopy.TURN_OF_THE_TIDE_SET_TITLE,
			"hint_a": PlayerCopy.TURN_OF_THE_TIDE_SET_HINT_A,
			"hint_b": PlayerCopy.TURN_OF_THE_TIDE_SET_HINT_B,
		},
		"slack-water": {
			"title": PlayerCopy.TURN_OF_THE_TIDE_SLACK_TITLE,
			"hint_a": PlayerCopy.TURN_OF_THE_TIDE_SLACK_HINT_A,
			"hint_b": PlayerCopy.TURN_OF_THE_TIDE_SLACK_HINT_B,
		},
	},
	"thumbnail": "res://assets/chapter_thumbnails/turn-of-the-tide.png",
	"keepsakes": [
		{"stage_id": "set-the-tide", "title": "Set the Tide"},
		{"stage_id": "slack-water", "title": "Slack Water"},
	],
	"dressing": "res://content/dressing/turn_of_the_tide.gd",
	"server": {"flag": "TURN_OF_THE_TIDE_CHAPTER_ENABLED", "max_branches": 7},
}
