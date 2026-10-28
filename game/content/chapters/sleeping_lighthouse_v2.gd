extends RefCounted
## Descriptor for sleeping-lighthouse@2. Fields: content/chapters/index.gd.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DATA := {
	"key": "sleeping-lighthouse@2",
	"family": "lighthouse-room",
	"definition": ["res://core/lighthouse/room_catalog.gd", "definition"],
	"world": "res://presentation/lighthouse_room_world.gd",
	"scene": "res://sleeping_lighthouse_v2.tscn",
	"local_path": "user://sleeping-lighthouse-journey-v2.json",
	"version_of": "sleeping-lighthouse@1",
	"continues_earlier": ["res://services/lighthouse_migration.gd", "continuing_scene"],
	"leads_picker": true,
	"copy": {
		"summary": PlayerCopy.LIGHTHOUSE_PREVIEW_D440E74DF0F5,
		"completion": PlayerCopy.LIGHTHOUSE_PREVIEW_7F3B08F42FED,
	},
	"thumbnail": "res://assets/paid_levels/sleeping-lighthouse.png",
	"beds": ["water_far"],
	# The chapter's keepsake on Home (presentation/keepsakes/).
	"home_keepsake": {
		"builder": "res://presentation/keepsakes/little_lighthouse.gd",
		"island": "left",
		"slot": [-1.4, -1.3],
		"copy": {
			"name": PlayerCopy.KEEPSAKE_LIGHTHOUSE_NAME,
			"action": PlayerCopy.KEEPSAKE_LIGHTHOUSE_ACTION,
			"together": PlayerCopy.KEEPSAKE_LIGHTHOUSE_TOGETHER,
			"hard": PlayerCopy.KEEPSAKE_LIGHTHOUSE_HARD,
			"top": PlayerCopy.KEEPSAKE_LIGHTHOUSE_TOP,
		},
		"sounds": {"base": "garden_opened", "together": "waypoint", "hard": "tower_bell", "top": "island_bloomed"},
	},
	"server": {"flag": "LIGHTHOUSE_V2_CHAPTER_ENABLED", "max_branches": 7},
}
