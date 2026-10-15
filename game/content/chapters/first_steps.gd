extends RefCounted
## Descriptor for first-steps@1. Fields: content/chapters/index.gd.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DATA := {
	"key": "first-steps@1",
	"family": "first-steps",
	"definition": ["res://core/first_steps/stage_catalog.gd", "definition"],
	"world": "res://presentation/first_steps_world.gd",
	"scene": "res://first_steps_preview.tscn",
	"local_path": "user://first-steps-journey-v1.json",
	"released": true,
	"superseded_by": "",
	"version_of": "",
	"copy": {
		"summary": PlayerCopy.CHAPTER_REGISTRY_49A82D1B1B0C,
		"completion": PlayerCopy.CHAPTER_REGISTRY_6DF48F693FD6,
		"checkpoint_title": PlayerCopy.CHAPTER_REGISTRY_6C521D717CA5,
		"checkpoint_text": PlayerCopy.CHAPTER_REGISTRY_DA6530899780,
	},
	"stage_copy": {},
	"thumbnail": "res://assets/chapter_thumbnails/first-steps.png",
	"keepsake_scale": "small",
	"keepsakes": [
		{"stage_id": "a-little-lift", "title": "A Little Lift", "slot": [1.78, 1.00, 30]},
		{"stage_id": "a-place-to-grow", "title": "A Place to Grow", "slot": [1.78, -0.30, 36]},
	],
	"dressing": "",
	"fold_static": true,
	"server": {"flag": "FIRST_STEPS_ENABLED", "max_branches": 32},
	"golden": {"replay": "replay_golden", "fingerprint": "world_fingerprint"},
}
