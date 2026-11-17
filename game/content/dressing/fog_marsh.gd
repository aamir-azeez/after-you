extends RefCounted
## Fog Marsh: boardwalks over a still, reedy marsh under a soft fog that the
## lanterns clear (kit/fog.gd keeps every gate, gap, stair, water and control
## clear of it). Reeds stand in the water, the post office keeps its stamp
## desk by the door.

const DATA := {
	"theme": "harbour",
	"look": "fog",
	"fireflies": 8,
	"ground": {"*": "boardwalk", "path": "reed_bank", "reeds": "reed_bank", "bank": "reed_bank", "office": "timber"},
	"picks": {"lamp": "lantern", "shrub": "green", "bank": "moss", "fence": "picket", "trim": "flowers", "clutter": "barrel"},
	"tag": "wooden_plaque",
	"pad": "stand_spot",
	"fog": "mist",
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
		{"slot": "shrub", "style": "reeds", "floor": "office", "edge": "right", "spacing": 45, "y": -10},
		# Tall lanterns on posts by the boardwalks' backs, glowing through the fog.
		{"slot": "lamp", "floor": "path", "edge": "back", "along": 0.7, "size": 1.7},
		{"slot": "lamp", "floor": "jetty", "edge": "back", "along": 0.8, "size": 1.7},
		{"slot": "lamp", "floor": "dock", "edge": "back", "along": 0.5, "size": 1.7},
		{"slot": "lamp", "floor": "landing", "edge": "back", "along": 0.6, "size": 1.7},
		{"slot": "lamp", "floor": "jetty-3", "edge": "back", "along": 0.3, "size": 1.7},
		{"slot": "lamp", "floor": "office", "edge": "back", "along": 0.92, "size": 1.7},
		# The post office's stamp desk on a little landing by its door side.
		{"slot": "bank", "floor": "office", "edge": "left", "depth": 70, "height": 4, "gap": 12, "span": [0.45, 1.0]},
		{"kind": "stamp_desk", "floor": "office", "edge": "left", "along": 0.82, "rot": 90, "anchor": "stamp_desk"},
		{"slot": "clutter", "floor": "dock", "edge": "left", "spacing": 150},
	]},
}
