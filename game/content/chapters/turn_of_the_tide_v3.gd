extends RefCounted
## Descriptor for turn-of-the-tide@3. Fields: content/chapters/index.gd.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DATA := {
	"key": "turn-of-the-tide@3",
	"family": "journey",
	"definition": ["res://core/journey/turn_of_the_tide_v3_catalog.gd", "definition"],
	"world": "res://presentation/tide_world.gd",
	"scene": "res://turn_of_the_tide_v3.tscn",
	"stair_gates": false,
	"local_path": "user://turn-of-the-tide-journey-v3.json",
	"version_of": "turn-of-the-tide@1",
	"released": false,
	"prewarm_world": true,
	"copy": {
		"title": PlayerCopy.TURN_OF_THE_TIDE_TITLE,
		"summary": PlayerCopy.TURN_OF_THE_TIDE_V3_SUMMARY,
		"completion": PlayerCopy.TURN_OF_THE_TIDE_COMPLETION,
	},
	"letter": {"stamp": "boat", "address": [PlayerCopy.LETTER_OLD_BOAT, PlayerCopy.LETTER_OLD_BOAT_LINE],
		"postmark": PlayerCopy.LETTER_POST_HARBOUR, "signoff": PlayerCopy.LETTER_WRITE_BACK_SOON},
	"stage_copy": {
		"set-the-tide": {
			"title": PlayerCopy.TURN_OF_THE_TIDE_SET_TITLE,
			"hint_a": PlayerCopy.TURN_OF_THE_TIDE_SET_HINT_A,
			# Open turns have no bell to ring, so the later turns show no line; the goal's beacon marks the place.
			"hint_b": "",
		},
		"slack-water": {
			"title": PlayerCopy.TURN_OF_THE_TIDE_SLACK_TITLE,
			"hint_a": PlayerCopy.TURN_OF_THE_TIDE_SLACK_HINT_A,
			"goal_a": PlayerCopy.TURN_OF_THE_TIDE_SLACK_GOAL_A,
			"hint_b": PlayerCopy.TURN_OF_THE_TIDE_V2_SLACK_HINT_B,
		},
	},
	"thumbnail": "res://assets/chapter_thumbnails/turn-of-the-tide.png",
	"dressing": "res://content/dressing/turn_of_the_tide.gd",
	"water": "res://content/water/turn_of_the_tide.gd",
	# Each turn's end spots (the steps, posts, bell and lantern) carry a beacon.
	"goal_beacon": true,
	"water_levels": {"tide": ["low", "half", "high"], "basin": ["shut", "low", "half", "high"], "chamber": ["low", "half", "high"]},
	"beds": ["water_near", "shore"],
	# No wait hints: on open controls a crossing has no live and memory parts to
	# tell apart (presentation/wait_hints.gd needs owned controls).
	# The winch reads as the slipway it moves.
	"selector_names": {"winch": {"stowed": PlayerCopy.TURN_OF_THE_TIDE_WINCH_STOWED, "slip": PlayerCopy.TURN_OF_THE_TIDE_WINCH_SLIP}},
	# Slack Water's chains wind onto hand winches and its bars are sliding
	# bolts; the button says what the pip pulls. The three water wheels are
	# valves the pip turns.
	# The chains, bars and water wheels are machines, and the mole's goal is its
	# harbour lantern; every other piece takes the dressing's pick.
	# The mooring lines are ropes you pull taut, the gangway a crank and the
	# sluice a water gate you lift (the owner's pick, 2026-11-16); each lever
	# shows its own state, so no lamp stands beside it.
	"piece_styles": {"boom-chain": "winch", "punt-chain": "winch", "gate-bar": "bolt", "sea-bar": "bolt", "stone-bar": "bolt", "tide": "valve", "basin": "valve", "chamber": "valve",
		"harbour-lantern": "harbour_lantern", "line": "rope", "punt-line": "rope", "gangway": "crank", "sluice": "water_gate"},
	"lever_lamps": false,
	"lever_actions": {"boom-chain": PlayerCopy.TURN_OF_THE_TIDE_PULL_CHAIN, "punt-chain": PlayerCopy.TURN_OF_THE_TIDE_PULL_CHAIN, "gate-bar": PlayerCopy.TURN_OF_THE_TIDE_PULL_BAR, "sea-bar": PlayerCopy.TURN_OF_THE_TIDE_PULL_BAR, "stone-bar": PlayerCopy.TURN_OF_THE_TIDE_PULL_BAR},
	"server": {"flag": "TURN_OF_THE_TIDE_V3_CHAPTER_ENABLED", "max_branches": 7},
}
