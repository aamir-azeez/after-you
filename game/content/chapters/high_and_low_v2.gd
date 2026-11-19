extends RefCounted
## Descriptor for high-and-low@2. Fields: content/chapters/index.gd.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DATA := {
	"key": "high-and-low@2",
	"family": "cooperative",
	"definition": ["res://core/cooperative/high_and_low_v2_catalog.gd", "definition"],
	"world": "res://presentation/cooperative_world.gd",
	"scene": "res://high_and_low_v2.tscn",
	"local_path": "user://high-and-low-journey-v2.json",
	"version_of": "high-and-low@1",
	"released": false,
	"copy": {
		"summary": PlayerCopy.COOPERATIVE_HIGH_SUMMARY,
		"completion": PlayerCopy.COOPERATIVE_COMPLETION,
	},
	"letter": {"stamp": "daisy", "address": [PlayerCopy.LETTER_DECK, PlayerCopy.LETTER_DECK_LINE],
		"postmark": PlayerCopy.LETTER_POST_MEADOW, "signoff": PlayerCopy.LETTER_WRITE_BACK_SOON},
	"thumbnail": "res://assets/chapter_thumbnails/high-and-low.png",
	"dressing": "res://content/dressing/high_and_low_v2.gd",
	"server": {"flag": "HIGH_AND_LOW_V2_CHAPTER_ENABLED", "max_branches": 7},
}
