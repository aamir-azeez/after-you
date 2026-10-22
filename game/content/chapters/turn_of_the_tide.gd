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
	"superseded_by": "turn-of-the-tide@2",
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
			"goal_a": PlayerCopy.TURN_OF_THE_TIDE_SLACK_GOAL_A,
			"hint_b": PlayerCopy.TURN_OF_THE_TIDE_SLACK_HINT_B,
		},
	},
	"thumbnail": "res://assets/chapter_thumbnails/turn-of-the-tide.png",
	"keepsakes": [
		{"stage_id": "set-the-tide", "title": "Set the Tide"},
		{"stage_id": "slack-water", "title": "Slack Water"},
	],
	"dressing": "res://content/dressing/turn_of_the_tide.gd",
	# Each turn's end spots (the steps, posts, bell and lantern) carry a beacon.
	"goal_beacon": true,
	# The waiting steps and posts are wider than their pads: each pad shows
	# exactly where it counts.
	"stand_spots": true,
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
	# The winch reads as the slipway it moves.
	"selector_names": {"winch": {"stowed": PlayerCopy.TURN_OF_THE_TIDE_WINCH_STOWED, "slip": PlayerCopy.TURN_OF_THE_TIDE_WINCH_SLIP}},
	# Slack Water's chains wind onto hand winches and its bars are sliding
	# bolts; the button says what the pip pulls.
	"lever_looks": {"boom-chain": "winch", "punt-chain": "winch", "gate-bar": "bolt", "sea-bar": "bolt"},
	"lever_actions": {"boom-chain": PlayerCopy.TURN_OF_THE_TIDE_PULL_CHAIN, "punt-chain": PlayerCopy.TURN_OF_THE_TIDE_PULL_CHAIN, "gate-bar": PlayerCopy.TURN_OF_THE_TIDE_PULL_BAR, "sea-bar": PlayerCopy.TURN_OF_THE_TIDE_PULL_BAR},
	"server": {"flag": "TURN_OF_THE_TIDE_CHAPTER_ENABLED", "max_branches": 7},
}
