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
	"server": {"flag": "WISHING_WELL_CHAPTER_ENABLED", "max_branches": 32},
}
