extends RefCounted
## Descriptor for the-falls@1. Fields: content/chapters/index.gd.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DATA := {
	"key": "the-falls@1",
	"family": "journey",
	"definition": ["res://core/journey/the_falls_catalog.gd", "definition"],
	"world": "res://presentation/the_falls_world.gd",
	"scene": "res://the_falls.tscn",
	"local_path": "user://the-falls-journey-v1.json",
	"released": false,
	"copy": {
		"title": PlayerCopy.THE_FALLS_TITLE,
		"summary": PlayerCopy.THE_FALLS_SUMMARY,
		"completion": PlayerCopy.THE_FALLS_COMPLETION,
	},
	"stage_copy": {
		"foot-of-the-falls": {
			"title": PlayerCopy.THE_FALLS_STAGE_1_TITLE,
			"hint_a": PlayerCopy.THE_FALLS_STAGE_1_HINT_A,
			"hint_b": PlayerCopy.THE_FALLS_STAGE_1_HINT_B,
		},
		"the-old-mill": {
			"title": PlayerCopy.THE_FALLS_STAGE_2_TITLE,
			"hint_a": PlayerCopy.THE_FALLS_STAGE_2_HINT_A,
			"hint_b": PlayerCopy.THE_FALLS_STAGE_2_HINT_B,
		},
		"behind-the-falls": {
			"title": PlayerCopy.THE_FALLS_STAGE_3_TITLE,
			"hint_a": PlayerCopy.THE_FALLS_STAGE_3_HINT_A,
			"hint_b": PlayerCopy.THE_FALLS_STAGE_3_HINT_B,
		},
		"the-last-stones": {
			"title": PlayerCopy.THE_FALLS_STAGE_4_TITLE,
			"hint_a": PlayerCopy.THE_FALLS_STAGE_4_HINT_A,
			"hint_b": PlayerCopy.THE_FALLS_STAGE_4_HINT_B,
		},
	},
	"thumbnail": "res://assets/chapter_thumbnails/the-falls.png",
	"keepsakes": [
		{"stage_id": "foot-of-the-falls", "title": PlayerCopy.THE_FALLS_STAGE_1_TITLE},
		{"stage_id": "the-old-mill", "title": PlayerCopy.THE_FALLS_STAGE_2_TITLE},
		{"stage_id": "behind-the-falls", "title": PlayerCopy.THE_FALLS_STAGE_3_TITLE},
		{"stage_id": "the-last-stones", "title": PlayerCopy.THE_FALLS_STAGE_4_TITLE},
	],
	# The chapter's keepsake on Home (presentation/keepsakes/).
	"home_keepsake": {
		"builder": "res://presentation/keepsakes/the_falls.gd",
		"island": "right",
		"slot": [0.0, 0.0],
		"copy": {
			"name": PlayerCopy.THE_FALLS_KEEPSAKE_NAME,
			"action": PlayerCopy.THE_FALLS_KEEPSAKE_ACTION,
			"together": PlayerCopy.THE_FALLS_KEEPSAKE_TOGETHER,
			"hard": PlayerCopy.THE_FALLS_KEEPSAKE_HARD,
			"top": PlayerCopy.THE_FALLS_KEEPSAKE_TOP,
		},
		"sounds": {"base": "garden_opened", "together": "lift_ready", "hard": "bell_rung", "top": "island_bloomed"},
	},
	"server": {"flag": "THE_FALLS_CHAPTER_ENABLED", "max_branches": 32},
}
