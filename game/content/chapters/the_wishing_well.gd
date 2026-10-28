extends RefCounted
## Descriptor for the-wishing-well@1. Fields: content/chapters/index.gd.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DATA := {
	"key": "the-wishing-well@1",
	"family": "cooperative",
	"definition": ["res://core/cooperative/wishing_well_catalog.gd", "definition"],
	"world": "res://presentation/wishing_well_world.gd",
	"scene": "res://the_wishing_well.tscn",
	"local_path": "user://the-wishing-well-journey-v1.json",
	"copy": {
		"title": PlayerCopy.WISHING_WELL_TITLE,
		"summary": PlayerCopy.WISHING_WELL_SUMMARY,
		"completion": PlayerCopy.WISHING_WELL_COMPLETION,
	},
	"thumbnail": "res://assets/chapter_thumbnails/the-wishing-well.png",
	"keepsakes": [
		{"stage_id": "go-on-ahead", "title": "Go On Ahead"},
		{"stage_id": "back-for-you", "title": "Back for You"},
	],
	# The well mouth drops the spirit into the bucket at the bottom of the well.
	"sound_cues": {"drop": "well_plunk"},
	# The chapter's keepsake on Home (presentation/keepsakes/).
	"home_keepsake": {
		"builder": "res://presentation/keepsakes/wishing_well.gd",
		"island": "right",
		"slot": [-0.3, 0.5],
		"copy": {
			"name": PlayerCopy.KEEPSAKE_WISHING_WELL_NAME,
			"action": PlayerCopy.KEEPSAKE_WISHING_WELL_ACTION,
			"together": PlayerCopy.KEEPSAKE_WISHING_WELL_TOGETHER,
			"hard": PlayerCopy.KEEPSAKE_WISHING_WELL_HARD,
			"top": PlayerCopy.KEEPSAKE_WISHING_WELL_TOP,
		},
		"sounds": {"base": "well_plunk", "together": "seed_caught", "hard": "seed_landed", "top": "receivers_joined"},
	},
	"server": {"flag": "WISHING_WELL_CHAPTER_ENABLED", "max_branches": 32},
}
