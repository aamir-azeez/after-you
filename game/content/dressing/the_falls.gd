extends RefCounted
## The Falls: a stream climbing beside a tall waterfall. Pale river stone at
## the water's edge, mossy flagstones on the ledges, timber on the mill loft
## and the lookout; ferns and moss along the backs, the mill wheel by the mill,
## the red post box on the little island. The reaches of the stream fall into
## each other through the locks kit's spillways ("falls").

const DATA := {
	"theme": "harbour",
	"look": "spray",
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
		# The falls: the tall one at the foot of the stream behind the mill
		# pool, the one in the gorge behind the rope bridge, and a last one
		# past the far bank where the ending's pool is. Each stands with its
		# foot in its reach of the stream, behind or beside the floors.
		{"slot": "landmark", "style": "waterfall", "at": [-220, -300], "width": 240, "height": 560, "y": -36, "foot": 30},
		{"slot": "landmark", "style": "waterfall", "at": [3000, -492], "width": 190, "height": 400, "y": 22},
		{"slot": "landmark", "style": "waterfall", "at": [5250, -260], "width": 140, "height": 220, "y": 80, "anchor": "falls_pool"},
		# The mill's big wheel turning behind the mill, in the pool it sets.
		{"slot": "landmark", "style": "mill", "at": [215, -432], "y": -36, "size": 1.35},
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
