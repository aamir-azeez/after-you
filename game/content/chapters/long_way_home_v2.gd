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
	"dressing": "res://content/dressing/long_way_home_v2.gd",
	# The chapter's keepsake on Home (presentation/keepsakes/).
	"home_keepsake": {
		"builder": "res://presentation/keepsakes/signpost.gd",
		"island": "left",
		"slot": [0.9, 1.8],
		"copy": {
			"name": PlayerCopy.KEEPSAKE_SIGNPOST_NAME,
			"action": PlayerCopy.KEEPSAKE_SIGNPOST_ACTION,
			"together": PlayerCopy.KEEPSAKE_SIGNPOST_TOGETHER,
			"hard": PlayerCopy.KEEPSAKE_SIGNPOST_HARD,
			"top": PlayerCopy.KEEPSAKE_SIGNPOST_TOP,
		},
		"sounds": {"base": "valve_turned", "together": "waypoint", "hard": "winch_wound", "top": "island_bloomed"},
	},
	"server": {"flag": "LONG_WAY_HOME_V2_CHAPTER_ENABLED", "max_branches": 32},
}
