extends RefCounted
## Descriptor for a-house-for-two@1. Fields: content/chapters/index.gd.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DATA := {
	"key": "a-house-for-two@1",
	"family": "cooperative",
	"definition": ["res://core/cooperative/house_catalog.gd", "definition"],
	"world": "res://presentation/house_world.gd",
	"scene": "res://house.tscn",
	"local_path": "user://a-house-for-two-journey-v1.json",
	"released": true,
	"superseded_by": "",
	"version_of": "",
	"copy": {
		"summary": PlayerCopy.HOUSE_SUMMARY,
		"completion": PlayerCopy.HOUSE_COMPLETION,
	},
	"stage_copy": {},
	"thumbnail": "res://assets/paid_levels/a-house-for-two.png",
	"keepsake_scale": "big",
	"keepsakes": [
		{"stage_id": "open-the-house", "title": "Open the House", "slot": [3.40, -6.85, 31]},
		{"stage_id": "the-room-below", "title": "The Room Below", "slot": [2.20, -8.30, 37]},
	],
	"dressing": "res://content/dressing/house.gd",
	"fold_static": true,
	"server": {"flag": "HOUSE_CHAPTER_ENABLED", "max_branches": 32},
	"golden": {"replay": "replay_golden_physical", "fingerprint": "world_fingerprint_physical"},
}
