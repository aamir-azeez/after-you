extends RefCounted
## Descriptor for relay-isles@3. Fields: content/chapters/index.gd.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const DATA := {
	"key": "relay-isles@3",
	"family": "journey",
	"definition": ["res://core/journey/relay_isles_v3_catalog.gd", "definition"],
	# The plates' and crank boards' looks and the rope deck come from the blocks
	# (content/blocks/defaults.gd).
	"block_source": ["res://core/journey/relay_isles_v3_catalog.gd", "source"],
	"world": "res://presentation/journey_world.gd",
	"scene": "res://relay_isles_v3.tscn",
	"local_path": "user://relay-isles-journey-v3.json",
	"version_of": "relay-isles@2",
	"released": false,
	"copy": {
		"title": PlayerCopy.RELAY_ISLES_TITLE,
		"summary": PlayerCopy.CHAPTER_REGISTRY_F78F85CE3DE5,
		"completion": PlayerCopy.RELAY_ISLES_COMPLETION,
	},
	"stage_copy": {
		"relay": {
			"title": PlayerCopy.RELAY_ISLES_RELAY_TITLE,
			"hint_a": PlayerCopy.RELAY_ISLES_RELAY_HINT_A,
			"hint_b": PlayerCopy.RELAY_ISLES_RELAY_HINT_B,
		},
		"garden": {
			"title": PlayerCopy.RELAY_ISLES_GARDEN_TITLE,
			"hint_a": PlayerCopy.RELAY_ISLES_GARDEN_HINT_A,
			"hint_b": PlayerCopy.RELAY_ISLES_GARDEN_HINT_B,
		},
	},
	"thumbnail": "res://assets/chapter_thumbnails/relay-isles.png",
	# @2's garden crossing: the meadow shores, the plank relay isle and the
	# cottage garden.
	"dressing": "res://content/dressing/relay_isles.gd",
	# The seed is the seed every world draws, its pedestal First Steps' stone drum,
	# its nest @2's relay socket and the garden @2's planter (kit/pieces/socket.gd).
	"piece_styles": {"seed": "seed", "seed-pedestal": "pedestal", "relay-socket": "nest", "garden": "planter"},
	"server": {"flag": "RELAY_ISLES_V3_CHAPTER_ENABLED", "max_branches": 7},
}
