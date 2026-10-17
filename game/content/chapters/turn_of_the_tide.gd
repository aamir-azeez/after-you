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
	"water_levels": {"tide": ["low", "half", "high"], "basin": ["shut", "low", "half", "high"], "chamber": ["low", "half", "high"]},
	"beds": ["water_near"],
	# Only what a crossing here can wait on (test_chapter_descriptors checks):
	# jetty-3 on the first stage; the boom jetty, the sea gate and the punt
	# ferry on the second.
	"wait_hints": {
		"reasons": {
			"tide": {"too_low": PlayerCopy.TURN_OF_THE_TIDE_WAIT_TIDE_LOW},
			"basin": PlayerCopy.TURN_OF_THE_TIDE_WAIT_SEA,
			"gate-bar": PlayerCopy.TURN_OF_THE_TIDE_WAIT_BAR,
			"sea-bar": PlayerCopy.TURN_OF_THE_TIDE_WAIT_BAR,
			"boom-chain": PlayerCopy.TURN_OF_THE_TIDE_WAIT_BOOM_CHAIN,
			"punt-chain": PlayerCopy.TURN_OF_THE_TIDE_WAIT_PUNT_CHAIN,
			"bollard-pad": PlayerCopy.TURN_OF_THE_TIDE_WAIT_BOLLARD_STEP,
		},
		"fallback": PlayerCopy.TURN_OF_THE_TIDE_WAIT_NOT_YET,
		"never": PlayerCopy.TURN_OF_THE_TIDE_WAIT_STAYS_SHUT,
		"crossings": {
			"jetty-3": PlayerCopy.TURN_OF_THE_TIDE_CROSSING_JETTY,
			"boom-jetty": PlayerCopy.TURN_OF_THE_TIDE_CROSSING_JETTY,
		},
	},
	# The bollard step's own bollard: whoever holds the step sits on it.
	"seats": {"bollard-pad": {"kind": "bollard", "size": 1.6}},
	"server": {"flag": "TURN_OF_THE_TIDE_CHAPTER_ENABLED", "max_branches": 7},
}
