extends RefCounted
## Descriptor for long-way-home@3. Fields: content/chapters/index.gd.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DATA := {
	"key": "long-way-home@3",
	"family": "journey",
	"definition": ["res://core/journey/long_way_home_v3_catalog.gd", "definition"],
	"world": "res://presentation/long_way_home_v2_world.gd",
	"scene": "res://long_way_home_v3.tscn",
	"local_path": "user://long-way-home-journey-v3.json",
	"version_of": "long-way-home@1",
	"released": false,
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
	# The window inside the house stands in a short plaster wall; the finale's
	# selectors are the hall lamp's post, the walk's gate arch and the porch
	# shutter beside their levers.
	"piece_styles": {"second-window": "walled_window", "hall-lamp": "lamp_post", "walk-gate": "gate_arch", "porch-shutter": "shutter"},
	"server": {"flag": "LONG_WAY_HOME_V3_CHAPTER_ENABLED", "max_branches": 32},
}
