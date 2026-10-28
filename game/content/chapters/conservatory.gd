extends RefCounted
## Descriptor for conservatory@1. Fields: content/chapters/index.gd.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DATA := {
	"key": "conservatory@1",
	"family": "journey",
	"definition": ["res://core/journey/conservatory_catalog.gd", "definition"],
	"world": "res://presentation/conservatory_world.gd",
	"scene": "res://conservatory.tscn",
	"local_path": "user://conservatory-journey-v1.json",
	"copy": {
		"title": PlayerCopy.CONSERVATORY_TITLE,
		"summary": PlayerCopy.CONSERVATORY_SUMMARY,
		"completion": PlayerCopy.CONSERVATORY_COMPLETION,
	},
	"stage_copy": {
		"a-light-above": {
			"title": PlayerCopy.CONSERVATORY_ABOVE_TITLE,
			"hint_a": PlayerCopy.CONSERVATORY_ABOVE_HINT_A,
			"hint_b": PlayerCopy.CONSERVATORY_ABOVE_HINT_B,
		},
		"the-way-light-returns": {
			"title": PlayerCopy.CONSERVATORY_RETURNS_TITLE,
			"hint_a": PlayerCopy.CONSERVATORY_RETURNS_HINT_A,
			"hint_b": PlayerCopy.CONSERVATORY_RETURNS_HINT_B,
		},
	},
	"thumbnail": "res://assets/paid_levels/conservatory.png",
	"keepsakes": [
		{"stage_id": "a-light-above", "title": "A Light Above"},
		{"stage_id": "the-way-light-returns", "title": "The Way Light Returns"},
	],
	"dressing": "res://content/dressing/conservatory.gd",
	# The chapter's keepsake on Home (presentation/keepsakes/).
	"home_keepsake": {
		"builder": "res://presentation/keepsakes/glasshouse.gd",
		"island": "left",
		"slot": [0.1, 1.3],
		"copy": {
			"name": PlayerCopy.KEEPSAKE_GLASSHOUSE_NAME,
			"action": PlayerCopy.KEEPSAKE_GLASSHOUSE_ACTION,
			"together": PlayerCopy.KEEPSAKE_GLASSHOUSE_TOGETHER,
			"hard": PlayerCopy.KEEPSAKE_GLASSHOUSE_HARD,
			"top": PlayerCopy.KEEPSAKE_GLASSHOUSE_TOP,
		},
		"sounds": {"base": "island_bloomed", "together": "water_rise", "hard": "garden_opened", "top": "receivers_joined"},
	},
	"server": {"flag": "JOURNEY_CHAPTERS_ENABLED", "max_branches": 32},
}
