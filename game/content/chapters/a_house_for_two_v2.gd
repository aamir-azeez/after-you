extends RefCounted
## Descriptor for a-house-for-two@2. Fields: content/chapters/index.gd.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DATA := {
	"key": "a-house-for-two@2",
	"family": "cooperative",
	"definition": ["res://core/cooperative/a_house_for_two_v2_catalog.gd", "definition"],
	"world": "res://presentation/house_world.gd",
	"scene": "res://a_house_for_two_v2.tscn",
	"local_path": "user://a-house-for-two-journey-v2.json",
	"version_of": "a-house-for-two@1",
	"released": false,
	"copy": {
		"summary": PlayerCopy.HOUSE_SUMMARY,
		"completion": PlayerCopy.HOUSE_COMPLETION,
	},
	"letter": {"stamp": "house", "address": [PlayerCopy.LETTER_NEW_HOUSE, PlayerCopy.LETTER_NEW_HOUSE_LINE],
		"postmark": PlayerCopy.LETTER_POST_HOUSE, "signoff": PlayerCopy.LETTER_BACK_IN_A_BIT},
	"thumbnail": "res://assets/paid_levels/a-house-for-two.png",
	"dressing": "res://content/dressing/house.gd",
	"server": {"flag": "A_HOUSE_FOR_TWO_V2_CHAPTER_ENABLED", "max_branches": 7},
}
