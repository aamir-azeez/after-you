extends RefCounted
## Descriptor for the-falls@1. Fields: content/chapters/index.gd.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DATA := {
	"key": "the-falls@1",
	"family": "journey",
	"definition": ["res://core/journey/the_falls_catalog.gd", "definition"],
	"world": "res://presentation/the_falls_world.gd",
	"scene": "res://the_falls.tscn",
	"local_path": "user://the-falls-journey-v1.json",
	"released": false,
	# Free, shown right after High and Low.
	"shown_after": "high-and-low",
	"copy": {
		"title": PlayerCopy.THE_FALLS_TITLE,
		"summary": PlayerCopy.THE_FALLS_SUMMARY,
		"completion": PlayerCopy.THE_FALLS_COMPLETION,
	},
	# The envelope About this chapter shows (presentation/letter/letter_view.gd):
	# placeholder words until the owner's text.
	"letter": {"stamp": "waterfall", "address": [PlayerCopy.THE_FALLS_LETTER_PLACE, PlayerCopy.THE_FALLS_LETTER_PLACE_LINE],
		"postmark": PlayerCopy.THE_FALLS_LETTER_POSTMARK, "signoff": PlayerCopy.LETTER_SEE_YOU_SOON},
	"stage_copy": {
		"foot-of-the-falls": {
			"title": PlayerCopy.THE_FALLS_STAGE_1_TITLE,
			"hint_a": PlayerCopy.THE_FALLS_STAGE_1_HINT_A,
			"hint_b": PlayerCopy.THE_FALLS_STAGE_1_HINT_B,
		},
		"the-old-mill": {
			"title": PlayerCopy.THE_FALLS_STAGE_2_TITLE,
			"hint_a": PlayerCopy.THE_FALLS_STAGE_2_HINT_A,
			"hint_b": PlayerCopy.THE_FALLS_STAGE_2_HINT_B,
		},
		"behind-the-falls": {
			"title": PlayerCopy.THE_FALLS_STAGE_3_TITLE,
			"hint_a": PlayerCopy.THE_FALLS_STAGE_3_HINT_A,
			"hint_b": PlayerCopy.THE_FALLS_STAGE_3_HINT_B,
		},
		"the-last-stones": {
			"title": PlayerCopy.THE_FALLS_STAGE_4_TITLE,
			"hint_a": PlayerCopy.THE_FALLS_STAGE_4_HINT_A,
			"hint_b": PlayerCopy.THE_FALLS_STAGE_4_HINT_B,
		},
	},
	"thumbnail": "res://assets/chapter_thumbnails/the-falls.png",
	"keepsakes": [
		{"stage_id": "foot-of-the-falls", "title": PlayerCopy.THE_FALLS_STAGE_1_TITLE},
		{"stage_id": "the-old-mill", "title": PlayerCopy.THE_FALLS_STAGE_2_TITLE},
	],
	# The chapter's keepsake on Home (presentation/keepsakes/).
	"home_keepsake": {
		"builder": "res://presentation/keepsakes/the_falls.gd",
		"island": "brook",
		"slot": [0.3, -2.4],
		"yaw": 0.0,
		"copy": {
			"name": PlayerCopy.THE_FALLS_KEEPSAKE_NAME,
			"action": PlayerCopy.THE_FALLS_KEEPSAKE_ACTION,
			"together": PlayerCopy.THE_FALLS_KEEPSAKE_TOGETHER,
			"hard": PlayerCopy.THE_FALLS_KEEPSAKE_HARD,
			"top": PlayerCopy.THE_FALLS_KEEPSAKE_TOP,
		},
		"sounds": {"base": "water_rise", "together": "winch_wound", "hard": "bridge_opened", "top": "receivers_joined"},
	},
	"dressing": "res://content/dressing/the_falls.gd",
	"water": "res://content/water/the_falls.gd",
	"water_levels": {"pool": ["LOW", "HIGH"], "stream": ["LOW", "MID", "HIGH"]},
	"beds": ["water_near"],
	"ending": "the_falls",
	# Each block's own looks (content/blocks/defaults.gd), and the pieces no
	# block styles: the stepping stones, water wheels as valves, and the pool's
	# current (from the bucket spot) as the hoist that winds the bucket up.
	"block_source": ["res://core/journey/the_falls_catalog.gd", "source"],
	"piece_styles": {"stones": "stones", "pool": "valve", "stream": "valve", "bucket": "bucket"},
	"server": {"flag": "THE_FALLS_CHAPTER_ENABLED", "max_branches": 7},
}
