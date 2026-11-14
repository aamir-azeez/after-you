extends RefCounted
## Descriptor for conservatory@2. Fields: content/chapters/index.gd.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DATA := {
	"key": "conservatory@2",
	"family": "journey",
	"definition": ["res://core/journey/conservatory_v2_catalog.gd", "definition"],
	"world": "res://presentation/conservatory_world.gd",
	"scene": "res://conservatory_v2.tscn",
	"local_path": "user://conservatory-journey-v2.json",
	"version_of": "conservatory@1",
	"released": false,
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
	"dressing": "res://content/dressing/conservatory.gd",
	"server": {"flag": "CONSERVATORY_V2_CHAPTER_ENABLED", "max_branches": 32},
}
