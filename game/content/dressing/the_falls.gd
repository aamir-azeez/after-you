extends RefCounted
## The Falls: a climb up one gorge, each stage on its own tier. Pale river
## stone at the water's edge, mossy flagstones on the ledges, timber on the
## mill loft and the lookout; ferns and moss along the backs, the mill wheel
## by the mill, the red post box on the little island. The pools of the
## stream pour into each other over rock steps (the locks kit's "falls"
## spillways on the water's own beds), the gorge's rock wall stands behind
## every tier, the great falls pours through it behind the rope bridge and
## rainbows hang in the spray.

const DATA := {
	"theme": "harbour",
	"look": "spray",
	"seabed": "pebbles",
	# The close follow camera (island_world._follow_data): a view 5.8 m tall
	# that follows the pip across, in depth and up the tiers, from a lower
	# angle than the game's (the same yaw), pinching out to at most 9.3 m.
	"camera": {"follow": {"size": 5.8, "axes": "xz", "lift": 1.0, "inset": [5.0, 1.6], "zoom": [0.75, 1.6], "pan": [1.0, 0.7], "from": [6.0, 12.0, 20.0]}},
	# The gorge (kit/gorge.gd): its rock wall 2.7 m behind the floors' back
	# edge, open where each falls pours through, and the rainbows.
	"gorge": {
		"wall": {"from": -1300, "to": 14790, "front": -900, "rise": 500,
			"open": [[-900, -300], [3150, 3700], [6280, 6620], [7800, 8960], [10300, 10820], [13740, 14290]]},
		"rainbows": [{"at": [8380, 690, -880], "radius": 380}, {"at": [3420, 300, -880], "radius": 210}, {"at": [-600, 140, -400], "radius": 200}]},
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
		# The falls, each pouring through the gorge wall into its own pool:
		# west of the mill pool, behind the bank into the mill race, behind the
		# west ledge, the great falls behind the rope bridge (its foot in the
		# gorge pool, so it shows behind the bridge mid-play), behind the
		# lookout, and past the far bank where the ending's pool is.
		{"slot": "landmark", "style": "waterfall", "at": [-600, -470], "width": 300, "height": 900, "tiers": 3, "cheek": 0.85, "y": -36, "foot": 30},
		{"slot": "landmark", "style": "waterfall", "at": [3420, -950], "width": 380, "height": 1400, "tiers": 3, "cheek": 1.0, "y": 145},
		{"slot": "landmark", "style": "waterfall", "at": [6450, -950], "width": 240, "height": 900, "tiers": 3, "cheek": 0.7, "y": 485},
		{"slot": "landmark", "style": "waterfall", "at": [8380, -1000], "width": 900, "height": 2200, "tiers": 4, "cheek": 1.4, "y": 485},
		{"slot": "landmark", "style": "waterfall", "at": [10560, -1000], "width": 420, "height": 1500, "tiers": 4, "cheek": 1.1, "y": 865},
		{"slot": "landmark", "style": "waterfall", "at": [14010, -500], "width": 340, "height": 1100, "tiers": 3, "cheek": 0.75, "y": 900, "anchor": "falls_pool"},
		# The mill's big wheel turning behind the mill, in the pool it sets.
		{"slot": "landmark", "style": "mill", "at": [558, -605], "y": -36, "size": 1.35},
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
		# More to see on the longer first two stages (no more controls): a boat
		# tied off the beach, a rod and rope by the water, lanterns along the
		# mill's bank and the island, washing on the mill deck, a bench in the
		# yard, ferns down the island's far side.
		{"kind": "boat", "floor": "beach", "edge": "front", "along": 0.3, "out": 70, "y": -20, "rot": 0, "size": 0.9},
		{"kind": "fishing_rod", "floor": "beach", "edge": "front", "along": 0.75, "out": 55},
		{"kind": "rope_coil", "floor": "beach", "edge": "front", "along": 0.6, "out": 40},
		{"slot": "lamp", "floor": "mill", "edge": "back", "along": 0.55, "size": 1.6},
		{"slot": "lamp", "floor": "isle", "edge": "back", "along": 0.35, "size": 1.6},
		{"slot": "shrub", "style": "wild_fern", "floor": "isle", "edge": "front", "span": [0.0, 0.45], "spacing": 70},
		{"slot": "bench", "floor": "yard", "edge": "front", "along": 0.5},
		{"kind": "rope_coil", "floor": "bank", "edge": "front", "along": 0.4, "out": 40},
		{"slot": "lamp", "floor": "loft", "edge": "back", "along": 0.85, "size": 1.6},
	]},
}
