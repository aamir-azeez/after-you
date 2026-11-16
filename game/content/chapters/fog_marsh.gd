extends RefCounted
## Descriptor for fog-marsh@1. Fields: content/chapters/index.gd.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DATA := {
	"key": "fog-marsh@1",
	"family": "journey",
	"definition": ["res://core/journey/fog_marsh_catalog.gd", "definition"],
	"world": "res://presentation/fog_marsh_world.gd",
	"scene": "res://fog_marsh.tscn",
	"local_path": "user://fog-marsh-journey-v1.json",
	"released": false,
	"copy": {
		"title": PlayerCopy.FOG_MARSH_TITLE,
		"summary": PlayerCopy.FOG_MARSH_SUMMARY,
		"completion": PlayerCopy.FOG_MARSH_COMPLETION,
	},
	"stage_copy": {
		"where-the-stream-went": {
			"title": PlayerCopy.FOG_MARSH_STAGE_1_TITLE,
			"hint_a": PlayerCopy.FOG_MARSH_STAGE_1_HINT_A,
			"hint_b": PlayerCopy.FOG_MARSH_STAGE_1_HINT_B,
		},
		"catch-the-pipsport": {
			"title": PlayerCopy.FOG_MARSH_STAGE_2_TITLE,
			"hint_a": PlayerCopy.FOG_MARSH_STAGE_2_HINT_A,
			"hint_b": PlayerCopy.FOG_MARSH_STAGE_2_HINT_B,
		},
		"carry-it-home": {
			"title": PlayerCopy.FOG_MARSH_STAGE_3_TITLE,
			"hint_a": PlayerCopy.FOG_MARSH_STAGE_3_HINT_A,
			"hint_b": PlayerCopy.FOG_MARSH_STAGE_3_HINT_B,
		},
	},
	"thumbnail": "res://assets/chapter_thumbnails/fog-marsh.png",
	"keepsakes": [
		{"stage_id": "where-the-stream-went", "title": PlayerCopy.FOG_MARSH_STAGE_1_TITLE},
		{"stage_id": "catch-the-pipsport", "title": PlayerCopy.FOG_MARSH_STAGE_2_TITLE},
		{"stage_id": "carry-it-home", "title": PlayerCopy.FOG_MARSH_STAGE_3_TITLE},
	],
	# The chapter's keepsake on Home (presentation/keepsakes/).
	"home_keepsake": {
		"builder": "res://presentation/keepsakes/fog_marsh.gd",
		"island": "right",
		"slot": [0.0, 0.0],
		"copy": {
			"name": PlayerCopy.FOG_MARSH_KEEPSAKE_NAME,
			"action": PlayerCopy.FOG_MARSH_KEEPSAKE_ACTION,
			"together": PlayerCopy.FOG_MARSH_KEEPSAKE_TOGETHER,
			"hard": PlayerCopy.FOG_MARSH_KEEPSAKE_HARD,
			"top": PlayerCopy.FOG_MARSH_KEEPSAKE_TOP,
		},
		"sounds": {"base": "garden_opened", "together": "lift_ready", "hard": "bell_rung", "top": "island_bloomed"},
	},
	"server": {"flag": "FOG_MARSH_CHAPTER_ENABLED", "max_branches": 32},
}
