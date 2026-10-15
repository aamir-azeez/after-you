extends RefCounted
## Descriptor for a-house-for-two@1. Fields: content/chapters/index.gd.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DATA := {
	"key": "a-house-for-two@1",
	"family": "cooperative",
	"definition": ["res://core/cooperative/house_catalog.gd", "definition"],
	"world": "res://presentation/house_world.gd",
	"scene": "res://house.tscn",
	"local_path": "user://a-house-for-two-journey-v1.json",
	"copy": {
		"summary": PlayerCopy.HOUSE_SUMMARY,
		"completion": PlayerCopy.HOUSE_COMPLETION,
	},
	"thumbnail": "res://assets/paid_levels/a-house-for-two.png",
	"keepsakes": [
		{"stage_id": "open-the-house", "title": "Open the House"},
		{"stage_id": "the-room-below", "title": "The Room Below"},
	],
	"dressing": "res://content/dressing/house.gd",
	"server": {"flag": "HOUSE_CHAPTER_ENABLED", "max_branches": 32},
}
