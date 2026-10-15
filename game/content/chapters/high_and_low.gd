extends RefCounted
## Descriptor for high-and-low@1. Fields: content/chapters/index.gd.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DATA := {
	"key": "high-and-low@1",
	"family": "cooperative",
	"definition": ["res://core/cooperative/stage_catalog.gd", "definition", "high-and-low"],
	"world": "res://presentation/cooperative_world.gd",
	"scene": "res://high_and_low.tscn",
	"local_path": "user://high-and-low-journey-v1.json",
	"copy": {
		"summary": PlayerCopy.COOPERATIVE_HIGH_SUMMARY,
		"completion": PlayerCopy.COOPERATIVE_COMPLETION,
	},
	"thumbnail": "res://assets/chapter_thumbnails/high-and-low.png",
	"keepsakes": [
		{"stage_id": "upper-path", "title": "Upper Path"},
		{"stage_id": "down-and-around", "title": "Down and Around"},
	],
	"dressing": "res://content/dressing/high_and_low.gd",
	"server": {"flag": "COOP_CHAPTERS_ENABLED", "max_branches": 32},
}
