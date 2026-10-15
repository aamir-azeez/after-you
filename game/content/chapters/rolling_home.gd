extends RefCounted
## Descriptor for rolling-home@1. Fields: content/chapters/index.gd.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DATA := {
	"key": "rolling-home@1",
	"family": "cooperative",
	"definition": ["res://core/cooperative/stage_catalog.gd", "definition", "rolling-home"],
	"world": "res://presentation/cooperative_world.gd",
	"scene": "res://rolling_home.tscn",
	"local_path": "user://rolling-home-journey-v1.json",
	"released": true,
	"superseded_by": "",
	"version_of": "",
	"copy": {
		"summary": PlayerCopy.COOPERATIVE_ROLLING_SUMMARY,
		"completion": PlayerCopy.COOPERATIVE_COMPLETION,
	},
	"stage_copy": {},
	"thumbnail": "res://assets/paid_levels/rolling-home.png",
	"keepsake_scale": "big",
	"keepsakes": [
		{"stage_id": "weight-of-a-friend", "title": "Weight of a Friend", "slot": [2.25, -5.45, 33]},
		{"stage_id": "bring-it-home", "title": "Bring It Home", "slot": [4.36, -5.39, 39]},
	],
	"dressing": "res://content/dressing/rolling_home.gd",
	"fold_static": true,
	"server": {"flag": "COOP_CHAPTERS_ENABLED", "max_branches": 32},
	"golden": {"replay": "replay_golden_physical", "fingerprint": "world_fingerprint_physical"},
}
