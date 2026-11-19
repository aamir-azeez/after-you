extends RefCounted
## The Falls: a stream climbing beside a tall waterfall. Pale river stone at
## the water's edge, mossy flagstones on the ledges, timber on the mill loft
## and the lookout; ferns and moss along the backs, the mill wheel by the mill,
## the red post box on the little island. The reaches of the stream fall into
## each other through the locks kit's spillways ("falls").

const DATA := {
	"theme": "harbour",
	"look": "spray",
	"seabed": "pebbles",
	# PROTOTYPE: the close follow camera (island_world._follow_data): a view
	# 5.4 m tall that follows the pip across and up the tiers, pinching out
	# to at most today's view (5.8 x 1.6 = 9.3 m).
	"camera": {"follow": {"size": 5.8, "axes": "xz", "lift": 1.0, "inset": [5.0, 1.6], "zoom": [0.75, 1.6], "pan": [1.0, 0.7], "from": [6.0, 12.0, 20.0]}},
	"fireflies": 0,
	"ground": {"*": "mossy_flags",
		"beach": "river_stone", "isle": "river_stone", "bank": "river_stone", "rock": "river_stone", "big": "river_stone",
		"loft": "timber", "look": "timber"},
	"picks": {"lamp": "lantern", "shrub": "fern", "bank": "moss", "fence": "stone", "trim": "flowers", "clutter": "rock"},
	"tag": "stone_tile",
	"lever": "winch",
	"selector": "valve",
	"pad": "stand_spot",
	"spillway": "falls",
	"carried_item": "pipsport",
	"current": "ripples",
	"props": {"*": [
		# The falls: the tall one at the foot of the stream west of the mill
		# pool, the one in the gorge behind the rope bridge, and the grandest
		# past the far bank where the ending's pool is. Each stands with its
		# foot (its lowest lip) in its reach of the stream and grows back and
		# up in tiers behind the floors, clear of the camera's view of them.
		{"slot": "landmark", "style": "waterfall", "at": [-600, -470], "width": 300, "height": 900, "tiers": 3, "cheek": 0.85, "y": -36, "foot": 30},
		# PROTOTYPE: the gorge itself, towering behind every tier: the great
		# falls pouring from far above the lip, in five steps, its foot in the
		# gorge pool behind the path behind the falls.
		{"slot": "landmark", "style": "waterfall", "at": [6200, -1800], "width": 1100, "height": 3000, "tiers": 5, "cheek": 1.6, "y": 505},
		{"slot": "landmark", "style": "waterfall", "at": [2600, -1500], "width": 420, "height": 1500, "tiers": 4, "cheek": 1.3, "y": 185},
		{"slot": "landmark", "style": "waterfall", "at": [10500, -1650], "width": 520, "height": 1900, "tiers": 4, "cheek": 1.3, "y": 880},
		{"slot": "landmark", "style": "waterfall", "at": [7025, -650], "width": 260, "height": 760, "tiers": 3, "cheek": 0.55, "y": 505},
		{"slot": "landmark", "style": "waterfall", "at": [13020, -500], "width": 340, "height": 1100, "tiers": 3, "cheek": 0.75, "y": 900, "anchor": "falls_pool"},
		# The mill's big wheel turning behind the mill, in the pool it sets.
		{"slot": "landmark", "style": "mill", "at": [322, -605], "y": -36, "size": 1.35},
		# The red post box the pipsport starts in, on the little island's west
		# side, where it hides only water.
		{"kind": "post_box", "floor": "isle", "edge": "left", "along": 0.12, "size": 1.3},
		# Ferns and moss along the backs of the ledges, mossy rocks by the water.
		{"slot": "bank", "floor": "ledge", "edge": "back", "depth": 40, "height": 8, "gap": 12},
		{"slot": "shrub", "style": "wild_fern", "floor": "ledge", "edge": "back", "spacing": 85, "size": 1.15},
		{"slot": "bank", "floor": "loft", "edge": "back", "depth": 40, "height": 8, "gap": 12},
		{"slot": "shrub", "style": "wild_fern", "floor": "loft", "edge": "back", "spacing": 95, "size": 1.15},
		{"slot": "shrub", "style": "wild_fern", "floor": "mill", "edge": "left", "spacing": 80, "size": 1.15},
		{"slot": "shrub", "style": "wild_fern", "floor": "wledge", "edge": "left", "spacing": 100, "size": 1.15},
		{"slot": "bank", "floor": "wtop", "edge": "back", "depth": 40, "height": 8, "gap": 12},
		{"slot": "shrub", "style": "wild_fern", "floor": "wtop", "edge": "back", "spacing": 80, "size": 1.15},
		{"slot": "bank", "floor": "etop", "edge": "back", "depth": 40, "height": 8, "gap": 12},
		{"slot": "shrub", "style": "wild_fern", "floor": "etop", "edge": "back", "spacing": 80, "size": 1.15},
		{"slot": "bank", "floor": "look", "edge": "back", "depth": 40, "height": 8, "gap": 12},
		{"slot": "shrub", "style": "wild_fern", "floor": "look", "edge": "back", "spacing": 90, "size": 1.15},
		{"slot": "bank", "floor": "far", "edge": "back", "depth": 40, "height": 8, "gap": 12},
		{"slot": "shrub", "style": "wild_fern", "floor": "far", "edge": "back", "spacing": 80, "size": 1.15},
		{"slot": "shrub", "style": "wild_fern", "floor": "beach", "edge": "left", "spacing": 75, "size": 1.1},
		{"slot": "shrub", "style": "wild_fern", "floor": "yard", "edge": "back", "spacing": 90},
		{"slot": "shrub", "style": "wild_fern", "floor": "eledge", "edge": "right", "spacing": 90},
		{"slot": "shrub", "style": "wild_fern", "floor": "big", "edge": "left", "spacing": 90},
		{"slot": "clutter", "floor": "bank", "edge": "left", "spacing": 110, "moss": true},
		{"slot": "clutter", "floor": "big", "edge": "back", "spacing": 110, "moss": true},
		{"slot": "clutter", "floor": "beach", "edge": "left", "spacing": 120, "moss": true, "out": 70},
		{"slot": "clutter", "floor": "ledge-4", "edge": "back", "spacing": 110, "moss": true},
		{"slot": "clutter", "floor": "deck", "edge": "right", "spacing": 120, "moss": true},
		# Lived in: washing out on the line behind the ledge, pots of flowers
		# there and on the island, a bench by the bank and the big rock.
		{"kind": "washing_line", "floor": "ledge", "edge": "back", "along": 0.5},
		{"slot": "shrub", "style": "pot", "floor": "ledge", "edge": "back", "span": [0.0, 0.3], "spacing": 45},
		{"slot": "bank", "floor": "isle", "edge": "right", "depth": 36, "height": 8, "gap": 8},
		{"slot": "shrub", "style": "pot", "floor": "isle", "edge": "right", "spacing": 55},
		{"slot": "bank", "floor": "bank", "edge": "back", "depth": 50, "height": 8, "gap": 10},
		{"slot": "bench", "floor": "bank", "edge": "back", "along": 0.55},
		{"slot": "shrub", "style": "pot", "floor": "bank", "edge": "back", "span": [0.75, 1.0], "spacing": 40},
		{"slot": "bank", "floor": "wledge", "edge": "left", "depth": 40, "height": 8, "gap": 8, "span": [0.45, 1.0]},
		{"slot": "shrub", "style": "pot", "floor": "wledge", "edge": "left", "span": [0.45, 1.0], "spacing": 50},
		{"slot": "bank", "floor": "deck", "edge": "back", "depth": 30, "height": 8, "gap": 8, "span": [0.0, 0.45]},
		{"kind": "washing_line", "floor": "deck", "edge": "back", "along": 0.235, "size": 0.85},
		{"slot": "bank", "floor": "big", "edge": "back", "depth": 50, "height": 8, "gap": 10},
		{"slot": "bench", "floor": "big", "edge": "back", "along": 0.7},
		{"slot": "shrub", "style": "pot", "floor": "far", "edge": "back", "span": [0.6, 1.0], "spacing": 45},
	]},
}
