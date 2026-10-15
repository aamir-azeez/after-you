extends RefCounted
## Descriptor for long-way-home@2. Fields: content/chapters/index.gd.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DATA := {
	"key": "long-way-home@2",
	"family": "journey",
	"definition": ["res://core/journey/long_way_home_catalog.gd", "definition_v2"],
	"world": "res://presentation/long_way_home_v2_world.gd",
	"scene": "res://long_way_home_v2.tscn",
	"local_path": "user://long-way-home-journey-v2.json",
	"released": true,
	"superseded_by": "",
	"version_of": "long-way-home@1",
	"copy": {
		"title": PlayerCopy.LONG_WAY_HOME_TITLE,
		"summary": PlayerCopy.LONG_WAY_HOME_SUMMARY,
		"completion": PlayerCopy.LONG_WAY_HOME_COMPLETION,
	},
	"stage_copy": {
		"the-path-you-leave": {
			"title": PlayerCopy.LONG_WAY_HOME_PATH_TITLE,
			"hint_a": PlayerCopy.LONG_WAY_HOME_PATH_HINT_A,
			"hint_b": PlayerCopy.LONG_WAY_HOME_PATH_HINT_B,
		},
		"a-place-beside-you": {
			"title": PlayerCopy.LONG_WAY_HOME_PLACE_TITLE,
			"hint_a": PlayerCopy.LONG_WAY_HOME_V2_PLACE_HINT_A,
			"hint_b": PlayerCopy.LONG_WAY_HOME_V2_PLACE_HINT_B,
		},
	},
	"thumbnail": "res://assets/paid_levels/long-way-home.png",
	"keepsake_scale": "",
	"keepsakes": [],
	"dressing": "res://content/dressing/long_way_home_v2.gd",
	"fold_static": true,
	"server": {"flag": "LONG_WAY_HOME_V2_CHAPTER_ENABLED", "max_branches": 32},
	"golden": {"replay": "replay_golden_journey", "fingerprint": "world_fingerprint_journey"},
}
