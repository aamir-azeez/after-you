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
		{"slot": "landmark", "style": "waterfall", "at": [-200, -170], "width": 170, "height": 330, "y": -36},
		{"slot": "landmark", "style": "waterfall", "at": [3000, -492], "width": 150, "height": 300, "y": 22},
		{"slot": "landmark", "style": "waterfall", "at": [5250, -260], "width": 140, "height": 220, "y": 80, "anchor": "falls_pool"},
		# The mill's wheel behind the mill, in the pool it sets.
		{"slot": "landmark", "style": "mill", "at": [150, -440], "y": -36},
		# The red post box the pipsport starts in, on the little island's west
		# side, where it hides only water.
		{"kind": "post_box", "floor": "isle", "edge": "left", "along": 0.12},
		# Ferns and moss along the backs of the ledges, rocks by the water.
		{"slot": "bank", "floor": "ledge", "edge": "back", "depth": 40, "height": 8, "gap": 12},
		{"slot": "shrub", "style": "wild_fern", "floor": "ledge", "edge": "back", "spacing": 130},
		{"slot": "bank", "floor": "loft", "edge": "back", "depth": 40, "height": 8, "gap": 12},
		{"slot": "shrub", "style": "wild_fern", "floor": "loft", "edge": "back", "spacing": 150},
		{"slot": "shrub", "style": "wild_fern", "floor": "mill", "edge": "left", "spacing": 120},
		{"slot": "shrub", "style": "wild_fern", "floor": "wledge", "edge": "left", "spacing": 160},
		{"slot": "bank", "floor": "wtop", "edge": "back", "depth": 40, "height": 8, "gap": 12},
		{"slot": "shrub", "style": "wild_fern", "floor": "wtop", "edge": "back", "spacing": 120},
		{"slot": "bank", "floor": "etop", "edge": "back", "depth": 40, "height": 8, "gap": 12},
		{"slot": "shrub", "style": "wild_fern", "floor": "etop", "edge": "back", "spacing": 120},
		{"slot": "bank", "floor": "look", "edge": "back", "depth": 40, "height": 8, "gap": 12},
		{"slot": "shrub", "style": "wild_fern", "floor": "look", "edge": "back", "spacing": 140},
		{"slot": "bank", "floor": "far", "edge": "back", "depth": 40, "height": 8, "gap": 12},
		{"slot": "shrub", "style": "wild_fern", "floor": "far", "edge": "back", "spacing": 120},
		{"slot": "clutter", "floor": "bank", "edge": "left", "spacing": 170},
		{"slot": "clutter", "floor": "big", "edge": "back", "spacing": 160},
	]},
}
