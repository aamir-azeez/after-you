extends RefCounted
## Descriptor for sleeping-lighthouse@3. Fields: content/chapters/index.gd.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DATA := {
	"key": "sleeping-lighthouse@3",
	"family": "journey",
	"definition": ["res://core/journey/sleeping_lighthouse_v3_catalog.gd", "definition"],
	"world": "res://presentation/journey_world.gd",
	"scene": "res://sleeping_lighthouse_v3.tscn",
	"local_path": "user://sleeping-lighthouse-journey-v3.json",
	"version_of": "sleeping-lighthouse@1",
	"released": false,
	"copy": {
		"title": PlayerCopy.SLEEPING_LIGHTHOUSE_TITLE,
		"summary": PlayerCopy.LIGHTHOUSE_SUMMARY,
		"completion": PlayerCopy.LIGHTHOUSE_PREVIEW_7F3B08F42FED,
	},
	"stage_copy": {
		"borrowed-light": {
			"title": PlayerCopy.SLEEPING_LIGHTHOUSE_BORROWED_TITLE,
			"hint_a": PlayerCopy.SLEEPING_LIGHTHOUSE_BORROWED_HINT_A,
			"hint_b": PlayerCopy.SLEEPING_LIGHTHOUSE_BORROWED_HINT_B,
		},
		"missing-piece": {
			"title": PlayerCopy.SLEEPING_LIGHTHOUSE_MISSING_TITLE,
			"hint_a": PlayerCopy.SLEEPING_LIGHTHOUSE_MISSING_HINT_A,
			"hint_b": PlayerCopy.SLEEPING_LIGHTHOUSE_MISSING_HINT_B,
		},
		"two-promises": {
			"title": PlayerCopy.SLEEPING_LIGHTHOUSE_PROMISES_TITLE,
			"hint_a": PlayerCopy.SLEEPING_LIGHTHOUSE_PROMISES_HINT_A,
			"hint_b": PlayerCopy.SLEEPING_LIGHTHOUSE_PROMISES_HINT_B,
		},
		"after-the-first-bell": {
			"title": PlayerCopy.SLEEPING_LIGHTHOUSE_BELL_TITLE,
			"hint_a": PlayerCopy.SLEEPING_LIGHTHOUSE_BELL_HINT_A,
			"hint_b": PlayerCopy.SLEEPING_LIGHTHOUSE_BELL_HINT_B,
		},
		"what-carried-you": {
			"title": PlayerCopy.STAGE_CATALOG_7EF4E1C96BAC,
			"hint_a": PlayerCopy.SLEEPING_LIGHTHOUSE_CARRIED_HINT_A,
			"hint_b": PlayerCopy.SLEEPING_LIGHTHOUSE_CARRIED_HINT_B,
		},
		"a-welcome-left-on": {
			"title": PlayerCopy.SLEEPING_LIGHTHOUSE_WELCOME_TITLE,
			"hint_a": PlayerCopy.SLEEPING_LIGHTHOUSE_WELCOME_HINT_A,
			"hint_b": PlayerCopy.SLEEPING_LIGHTHOUSE_WELCOME_HINT_B,
		},
	},
	"thumbnail": "res://assets/paid_levels/sleeping-lighthouse.png",
	"dressing": "res://content/dressing/sleeping_lighthouse_v3.gd",
	"beds": ["water_far", "shore"],
	# The court and tower bells keep their bells, the crests where the light
	# ends are low crests, and the lens is the Lighthouse's lens.
	"piece_styles": {"court-bell": "bell", "tower-bell": "bell", "lens-crest": "crest", "promise-crest": "crest", "projector-crest": "crest", "beacon-crest": "crest", "lens": "lens"},
	"server": {"flag": "SLEEPING_LIGHTHOUSE_V3_CHAPTER_ENABLED", "max_branches": 7},
}
