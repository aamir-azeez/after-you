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
		"builder": "res://presentation/keepsakes/crossroads.gd",
		"island": "journey_right",
		"slot": [-0.3, -1.0],
		"copy": {
			"name": PlayerCopy.KEEPSAKE_CROSSROADS_NAME,
			"action": PlayerCopy.KEEPSAKE_CROSSROADS_ACTION,
			"together": PlayerCopy.KEEPSAKE_CROSSROADS_TOGETHER,
			"hard": PlayerCopy.KEEPSAKE_CROSSROADS_HARD,
			"top": PlayerCopy.KEEPSAKE_CROSSROADS_TOP,
		},
		"sounds": {"base": "valve_turned", "together": "waypoint", "hard": "winch_wound", "top": "island_bloomed"},
	},
	"server": {"flag": "LONG_WAY_HOME_V2_CHAPTER_ENABLED", "max_branches": 32},
}
