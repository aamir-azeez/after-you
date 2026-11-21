extends RefCounted
## Descriptor for first-steps@2. Fields: content/chapters/index.gd.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DATA := {
	"key": "first-steps@2",
	"family": "journey",
	"definition": ["res://core/journey/first_steps_v2_catalog.gd", "definition"],
	"world": "res://presentation/journey_world.gd",
	"scene": "res://first_steps_v2.tscn",
	"local_path": "user://first-steps-journey-v2.json",
	"version_of": "first-steps@1",
	"released": false,
	"copy": {
		"title": PlayerCopy.FIRST_STEPS_TITLE,
		"summary": PlayerCopy.CHAPTER_REGISTRY_49A82D1B1B0C,
		"completion": PlayerCopy.FIRST_STEPS_COMPLETION,
	},
	"stage_copy": {
		"a-little-lift": {
			"title": PlayerCopy.FIRST_STEPS_LIFT_TITLE,
			"hint_a": PlayerCopy.FIRST_STEPS_LIFT_HINT_A,
			"hint_b": PlayerCopy.FIRST_STEPS_LIFT_HINT_B,
		},
		"a-place-to-grow": {
			"title": PlayerCopy.FIRST_STEPS_GROW_TITLE,
			"hint_a": PlayerCopy.FIRST_STEPS_GROW_HINT_A,
			"hint_b": PlayerCopy.FIRST_STEPS_GROW_HINT_B,
		},
	},
	"thumbnail": "res://assets/chapter_thumbnails/first-steps.png",
	"dressing": "res://content/dressing/first_steps.gd",
	# The loft bell keeps its bell, the garden's lamp is a low crest beside the
	# planter, the seed is the seed every world draws, resting on @1's stone
	# pedestal or in the garden planter (kit/pieces/socket.gd).
	"piece_styles": {"loft-bell": "bell", "garden-lamp": "crest", "seed": "seed", "seed-pedestal": "pedestal", "garden": "planter"},
	"server": {"flag": "FIRST_STEPS_V2_CHAPTER_ENABLED", "max_branches": 7},
}
