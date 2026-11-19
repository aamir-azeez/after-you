extends RefCounted
## Descriptor for the-wishing-well@2. Fields: content/chapters/index.gd.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DATA := {
	"key": "the-wishing-well@2",
	"family": "cooperative",
	"definition": ["res://core/cooperative/the_wishing_well_v2_catalog.gd", "definition"],
	"world": "res://presentation/wishing_well_world.gd",
	"scene": "res://the_wishing_well_v2.tscn",
	"stair_gates": false,
	"local_path": "user://the-wishing-well-journey-v2.json",
	"version_of": "the-wishing-well@1",
	"released": false,
	# Scenery: lit windows down the cliff. The tower's lever is a hand winch.
	"dressing": "res://content/dressing/the_wishing_well.gd",
	"piece_styles": {"winch-lever": "winch"},
	"copy": {
		"title": PlayerCopy.WISHING_WELL_TITLE,
		"summary": PlayerCopy.WISHING_WELL_SUMMARY,
		"completion": PlayerCopy.WISHING_WELL_COMPLETION,
	},
	"letter": {"stamp": "coin", "address": [PlayerCopy.LETTER_OLD_WELL, PlayerCopy.LETTER_OLD_WELL_LINE],
		"postmark": PlayerCopy.LETTER_POST_CLIFF, "signoff": PlayerCopy.LETTER_SEE_YOU_SOON},
	"thumbnail": "res://assets/chapter_thumbnails/the-wishing-well.png",
	# The well mouth drops the spirit into the bucket at the bottom of the well.
	"sound_cues": {"drop": "well_plunk"},
	# Drops falling down the shaft while the well is on screen.
	"beds": ["well_drips"],
	"server": {"flag": "THE_WISHING_WELL_V2_CHAPTER_ENABLED", "max_branches": 7},
}
