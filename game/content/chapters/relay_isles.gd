extends RefCounted
## Descriptor for relay-isles@2. Fields: content/chapters/index.gd.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DATA := {
	"key": "relay-isles@2",
	"family": "relay",
	"definition": ["res://core/v2/stage_catalog.gd", "relay_isles"],
	"world": "res://presentation/relay_world.gd",
	"scene": "res://relay_preview.tscn",
	"local_path": "user://relay-journey-v2.json",
	"copy": {
		"summary": PlayerCopy.CHAPTER_REGISTRY_F78F85CE3DE5,
		"completion": PlayerCopy.CHAPTER_REGISTRY_E73948E6FDBC,
		"checkpoint_title": PlayerCopy.CHAPTER_REGISTRY_94722E207A11,
		"checkpoint_text": PlayerCopy.CHAPTER_REGISTRY_2ED96CFB54FE,
	},
	"thumbnail": "res://assets/chapter_thumbnails/relay-isles.png",
	"turn_intro": [PlayerCopy.RELAY_PREVIEW_2B224F3B19B0, PlayerCopy.RELAY_PREVIEW_5BED71BD3E00],
	"keepsakes": [
		{"stage_id": "relay", "title": "The Relay"},
		{"stage_id": "garden", "title": "The Garden"},
	],
	# The chapter's keepsake on Home (presentation/keepsakes/).
	"home_keepsake": {
		"builder": "res://presentation/keepsakes/relay_masts.gd",
		"island": "right",
		"slot": [-0.2, -1.2],
		"copy": {
			"name": PlayerCopy.KEEPSAKE_RELAY_MASTS_NAME,
			"action": PlayerCopy.KEEPSAKE_RELAY_MASTS_ACTION,
			"together": PlayerCopy.KEEPSAKE_RELAY_MASTS_TOGETHER,
			"hard": PlayerCopy.KEEPSAKE_RELAY_MASTS_HARD,
			"top": PlayerCopy.KEEPSAKE_RELAY_MASTS_TOP,
		},
		"sounds": {"base": "handoff_offered", "together": "seed_caught", "hard": "switch_set", "top": "receivers_joined"},
	},
	"server": {"flag": "", "max_branches": 32},
}
