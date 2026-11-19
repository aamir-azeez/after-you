extends RefCounted
## Fog Marsh: boardwalks over a still, reedy marsh under a soft fog that the
## lanterns clear (kit/fog.gd keeps every gate, gap, stair, water and control
## clear of it). Reeds stand in the water, the post office keeps its stamp
## desk by the door.

const DATA := {
	"theme": "harbour",
	"look": "fog",
	"seabed": "mud",
	# PROTOTYPE: the close follow camera (island_world._follow_data).
	"camera": {"follow": {"size": 5.8, "axes": "xz", "lift": 1.0, "inset": [5.0, 1.6], "zoom": [0.75, 1.6], "pan": [1.0, 0.7]}},
	"fireflies": 30,
	"ground": {"*": "boardwalk", "path": "reed_bank", "reeds": "reed_bank", "bank": "reed_bank", "office": "timber"},
	"picks": {"lamp": "lantern", "shrub": "green", "bank": "moss", "fence": "picket", "trim": "flowers", "clutter": "barrel"},
	"tag": "wooden_plaque",
	"pad": "stand_spot",
	# PROTOTYPE: the cover (kit/fog_cover.gd) is the whole fog now; the old low
	# banks drew over it as white patches.
	"fog": "none",
	"carried_item": "pipsport",
	"current": "chevrons",
	"props": {"*": [
		# Reeds standing thick in the marsh along the backs and sides of the
		# low boardwalks, never in front where they would hide a pip; the
		# placer leaves out any clump that would hide a floor or a crossing.
		{"slot": "shrub", "style": "reeds", "floor": "path", "edge": "left", "spacing": 45, "y": -10},
		{"slot": "shrub", "style": "reeds", "floor": "path", "edge": "back", "spacing": 45, "y": -10},
		{"slot": "shrub", "style": "reeds", "floor": "middle", "edge": "back", "spacing": 45, "y": -10},
		{"slot": "shrub", "style": "reeds", "floor": "middle", "edge": "right", "spacing": 45, "y": -10},
		{"slot": "shrub", "style": "reeds", "floor": "boat-steps", "edge": "right", "spacing": 45, "y": -10},
		{"slot": "shrub", "style": "reeds", "floor": "jetty", "edge": "back", "spacing": 45, "y": -10},
		{"slot": "shrub", "style": "reeds", "floor": "jetty", "edge": "right", "spacing": 45, "y": -10},
		{"slot": "shrub", "style": "reeds", "floor": "dock", "edge": "back", "spacing": 50, "y": -10},
		{"slot": "shrub", "style": "reeds", "floor": "north", "edge": "back", "spacing": 45, "y": -10},
		{"slot": "shrub", "style": "reeds", "floor": "bend", "edge": "left", "spacing": 40, "y": -10},
		{"slot": "shrub", "style": "reeds", "floor": "bend", "edge": "right", "spacing": 40, "y": -10},
		{"slot": "shrub", "style": "reeds", "floor": "landing", "edge": "back", "spacing": 45, "y": -10},
		{"slot": "shrub", "style": "reeds", "floor": "reeds", "edge": "back", "spacing": 40, "y": -10},
		{"slot": "shrub", "style": "reeds", "floor": "reeds", "edge": "right", "spacing": 40, "y": -10},
		{"slot": "shrub", "style": "reeds", "floor": "bank", "edge": "left", "spacing": 45, "y": -10},
		{"slot": "shrub", "style": "reeds", "floor": "bank", "edge": "right", "spacing": 45, "y": -10},
		{"slot": "shrub", "style": "reeds", "floor": "landing-3", "edge": "back", "spacing": 45, "y": -10},
		{"slot": "shrub", "style": "reeds", "floor": "office", "edge": "right", "spacing": 45, "y": -106},
		# Reeds filling the channels: a second row further out in the water,
		# off the crossings, the raft's way and the current's.
		{"slot": "shrub", "style": "reeds", "floor": "path", "edge": "left", "spacing": 32, "out": 70, "y": -10},
		{"slot": "shrub", "style": "reeds", "floor": "middle", "edge": "back", "spacing": 32, "out": 75, "y": -10},
		{"slot": "shrub", "style": "reeds", "floor": "jetty", "edge": "left", "spacing": 34, "out": 48, "y": -10, "span": [0.0, 0.74]},
		{"slot": "shrub", "style": "reeds", "floor": "jetty", "edge": "left", "spacing": 34, "out": 85, "y": -10, "span": [0.0, 0.74]},
		{"slot": "shrub", "style": "reeds", "floor": "jetty", "edge": "right", "spacing": 34, "out": 80, "y": -10},
		{"slot": "shrub", "style": "reeds", "floor": "dock", "edge": "left", "spacing": 34, "out": 48, "y": -10, "span": [0.0, 0.42]},
		{"slot": "shrub", "style": "reeds", "floor": "dock", "edge": "back", "spacing": 34, "out": 56, "y": -10},
		{"slot": "shrub", "style": "reeds", "floor": "north", "edge": "left", "spacing": 32, "out": 48, "y": -10},
		{"slot": "shrub", "style": "reeds", "floor": "landing", "edge": "left", "spacing": 32, "out": 48, "y": -10, "span": [0.0, 0.6]},
		{"slot": "shrub", "style": "reeds", "floor": "landing", "edge": "right", "spacing": 34, "out": 48, "y": -10},
		{"slot": "shrub", "style": "reeds", "floor": "landing-3", "edge": "right", "spacing": 34, "out": 50, "y": -10, "span": [0.0, 0.4]},
		{"slot": "shrub", "style": "reeds", "floor": "reeds", "edge": "right", "spacing": 34, "out": 80, "y": -10},
		{"slot": "shrub", "style": "reeds", "floor": "office", "edge": "right", "spacing": 34, "out": 80, "y": -106},
		{"slot": "shrub", "style": "reeds", "floor": "jetty-3", "edge": "right", "spacing": 34, "out": 50, "y": -106},
		# Tall lanterns on posts by the boardwalks' backs, glowing through the
		# fog, each throwing a warm pool on the boards in front of it.
		{"slot": "lamp", "floor": "path", "edge": "back", "along": 0.7, "size": 2.0},
		{"kind": "light_pool", "floor": "path", "edge": "back", "along": 0.7, "out": -62, "radius": 70},
		{"slot": "lamp", "floor": "jetty", "edge": "back", "along": 0.12, "size": 2.0},
		{"kind": "light_pool", "floor": "jetty", "edge": "back", "along": 0.12, "out": -55, "radius": 52},
		{"slot": "lamp", "floor": "dock", "edge": "back", "along": 0.5, "size": 2.0},
		{"kind": "light_pool", "floor": "dock", "edge": "back", "along": 0.5, "out": -62, "radius": 70},
		{"slot": "lamp", "floor": "landing", "edge": "back", "along": 0.6, "size": 2.0},
		{"kind": "light_pool", "floor": "landing", "edge": "back", "along": 0.45, "out": -60, "radius": 58},
		{"slot": "lamp", "floor": "jetty-3", "edge": "back", "along": 0.3, "size": 2.0},
		{"kind": "light_pool", "floor": "jetty-3", "edge": "back", "along": 0.3, "out": -55, "radius": 52},
		{"slot": "lamp", "floor": "office", "edge": "back", "along": 0.92, "size": 1.7},
		{"kind": "light_pool", "floor": "office", "edge": "back", "along": 0.8, "out": -55, "radius": 52},
		# The post office's stamp desk on a little landing by its door side.
		{"slot": "bank", "floor": "office", "edge": "left", "depth": 70, "height": 4, "gap": 12, "span": [0.45, 1.0]},
		{"kind": "stamp_desk", "floor": "office", "edge": "left", "along": 0.82, "rot": 90, "anchor": "stamp_desk"},
		{"slot": "clutter", "floor": "dock", "edge": "left", "spacing": 150},
		# Lived in: a little boat tied up off the dock, someone's fishing rod
		# out over the water off the jetty, coils of rope left on the landings.
		{"kind": "boat", "floor": "dock", "edge": "left", "along": 0.82, "out": 55, "y": -20, "rot": 90, "size": 0.9},
		{"slot": "bank", "floor": "jetty", "edge": "left", "depth": 75, "height": 4, "gap": 8, "span": [0.78, 0.98]},
		{"kind": "fishing_rod", "floor": "jetty", "edge": "left", "along": 0.95, "out": 62, "rot": 90},
		{"kind": "rope_coil", "floor": "jetty", "edge": "left", "along": 0.8, "out": 40},
		{"kind": "rope_coil", "floor": "office", "edge": "left", "along": 0.55, "out": 40},
	]},
}
