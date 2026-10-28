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
	# The chapter's keepsake on Home (presentation/keepsakes/).
	"home_keepsake": {
		"builder": "res://presentation/keepsakes/little_house.gd",
		"island": "left",
		"slot": [-1.4, 1.9],
		"copy": {
			"name": PlayerCopy.KEEPSAKE_HOUSE_NAME,
			"action": PlayerCopy.KEEPSAKE_HOUSE_ACTION,
			"together": PlayerCopy.KEEPSAKE_HOUSE_TOGETHER,
			"hard": PlayerCopy.KEEPSAKE_HOUSE_HARD,
			"top": PlayerCopy.KEEPSAKE_HOUSE_TOP,
		},
		"sounds": {"base": "bolt_drawn", "together": "seed_caught", "hard": "bolt_shot", "top": "garden_opened"},
	},
	"server": {"flag": "HOUSE_CHAPTER_ENABLED", "max_branches": 32},
}
