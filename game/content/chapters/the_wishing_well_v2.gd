extends RefCounted
## Descriptor for the-wishing-well@2. Fields: content/chapters/index.gd.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DATA := {
	"key": "the-wishing-well@2",
	"family": "journey",
	"definition": ["res://core/journey/the_wishing_well_v2_catalog.gd", "definition"],
	# The steps' looks come from the blocks (content/blocks/defaults.gd).
	"block_source": ["res://core/journey/the_wishing_well_v2_catalog.gd", "source"],
	# @1's cliff, well, rope bucket and winch house on the journey world.
	"world": "res://presentation/wishing_well_v2_world.gd",
	"scene": "res://the_wishing_well_v2.tscn",
	"stair_gates": false,
	"local_path": "user://the-wishing-well-journey-v2.json",
	"version_of": "the-wishing-well@1",
	"released": false,
	# Scenery: lit windows down the cliff.
	"dressing": "res://content/dressing/the_wishing_well_v2.gd",
	# The winch handle, the winch it fits and the old crane's bucket.
	"piece_styles": {"handle": "winch_handle", "winch": "winch", "well-crane": "crane_bucket"},
	"copy": {
		"title": PlayerCopy.WISHING_WELL_TITLE,
		"summary": PlayerCopy.WISHING_WELL_SUMMARY,
		"completion": PlayerCopy.WISHING_WELL_COMPLETION,
	},
	# @1's words until the owner's text pass (PENDING-OWNER.md).
	"stage_copy": {
		"go-on-ahead": {
			"title": PlayerCopy.WISHING_WELL_AHEAD_TITLE,
			"hint_a": PlayerCopy.WISHING_WELL_AHEAD_HINT_A,
			"hint_b": PlayerCopy.WISHING_WELL_AHEAD_HINT_B,
		},
		"back-for-you": {
			"title": PlayerCopy.WISHING_WELL_BACK_TITLE,
			"hint_a": PlayerCopy.WISHING_WELL_BACK_HINT_A,
			"hint_b": PlayerCopy.WISHING_WELL_BACK_HINT_B,
		},
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
