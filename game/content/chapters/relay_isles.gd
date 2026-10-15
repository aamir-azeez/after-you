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
	"released": true,
	"superseded_by": "",
	"version_of": "",
	"copy": {
		"summary": PlayerCopy.CHAPTER_REGISTRY_F78F85CE3DE5,
		"completion": PlayerCopy.CHAPTER_REGISTRY_E73948E6FDBC,
		"checkpoint_title": PlayerCopy.CHAPTER_REGISTRY_94722E207A11,
		"checkpoint_text": PlayerCopy.CHAPTER_REGISTRY_2ED96CFB54FE,
	},
	"stage_copy": {},
	"thumbnail": "res://assets/chapter_thumbnails/relay-isles.png",
	"keepsake_scale": "small",
	"keepsakes": [
		{"stage_id": "relay", "title": "The Relay", "slot": [2.70, -1.22, 33]},
		{
			"stage_id": "garden",
			"title": "The Garden",
			"slot": [4.00, -1.22, 39],
			"tweak": {"plinth": 0.56},
		},
	],
	"dressing": "",
	"fold_static": true,
	"server": {"flag": "", "max_branches": 32},
	"golden": {"replay": "replay_golden", "fingerprint": "world_fingerprint"},
}
