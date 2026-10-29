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
	"copy": {
		"summary": PlayerCopy.CHAPTER_REGISTRY_49A82D1B1B0C,
		"completion": PlayerCopy.CHAPTER_REGISTRY_6DF48F693FD6,
		"checkpoint_title": PlayerCopy.CHAPTER_REGISTRY_6C521D717CA5,
		"checkpoint_text": PlayerCopy.CHAPTER_REGISTRY_DA6530899780,
	},
	"thumbnail": "res://assets/chapter_thumbnails/first-steps.png",
	"turn_intro": [PlayerCopy.RELAY_PREVIEW_9A01DAC077E3, PlayerCopy.RELAY_PREVIEW_4238BDD23E08],
	"keepsakes": [
		{"stage_id": "a-little-lift", "title": "A Little Lift"},
		{"stage_id": "a-place-to-grow", "title": "A Place to Grow"},
	],
	# The chapter's keepsake on Home (presentation/keepsakes/).
	"home_keepsake": {
		"builder": "res://presentation/keepsakes/bell_arch.gd",
		"island": "right",
		"slot": [-1.8, 0.0],
		"yaw": PI / 2,
		"copy": {
			"name": PlayerCopy.KEEPSAKE_BELL_ARCH_NAME,
			"action": PlayerCopy.KEEPSAKE_BELL_ARCH_ACTION,
			"together": PlayerCopy.KEEPSAKE_BELL_ARCH_TOGETHER,
			"hard": PlayerCopy.KEEPSAKE_BELL_ARCH_HARD,
			"top": PlayerCopy.KEEPSAKE_BELL_ARCH_TOP,
		},
		"sounds": {"base": "bell_rung", "together": "lift_ready", "hard": "tower_bell", "top": "island_bloomed"},
	},
	"server": {"flag": "FIRST_STEPS_ENABLED", "max_branches": 32},
}
