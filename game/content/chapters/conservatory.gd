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
	"keepsake_scale": "big",
	"keepsakes": [
		{"stage_id": "a-light-above", "title": "A Light Above", "slot": [4.34, -8.21, 34]},
		{"stage_id": "the-way-light-returns", "title": "The Way Light Returns", "slot": [3.20, -9.65, 28]},
	],
	"dressing": "res://content/dressing/conservatory.gd",
	"server": {"flag": "JOURNEY_CHAPTERS_ENABLED", "max_branches": 32},
	"golden": {"replay": "replay_golden_journey", "fingerprint": "world_fingerprint_journey"},
}
