extends RefCounted
## The Wishing Well @2 at dusk: @1's lit windows with flower boxes down the
## cliff face (content/dressing/the_wishing_well.gd), five along @2's cliff
## clear of the crane and both stairs, and fireflies over the
## planting. The well, its bucket, the winch house and every route stay the
## world's own (presentation/wishing_well_scenery.gd).

const DATA := {
	"look": "dusk",
	"fireflies": 10,
	# The well's lip is edged with a low rail.
	"barrier": "rail",
	"props": {"*": [
		# Windows and flower boxes on the cliff face, clear of both stairs and
		# the crane. The cliff face is drawn about 25 cm south of the level's
		# cliff edge (presentation/kit/walk_reach.gd), so they hang at z 32 and
		# 38 cm; any further north they sit inside the rock and never show.
		{"kind": "frame", "at": [-330, 32], "surface": "garden", "y": 74, "wall": true, "size": 2.0, "color": "ffcf6b"},
		{"kind": "shelf", "at": [-330, 38], "surface": "garden", "y": 31, "wall": true, "size": 0.85},
		{"kind": "frame", "at": [-90, 32], "surface": "garden", "y": 90, "wall": true, "size": 2.0, "color": "ffcf6b"},
		{"kind": "shelf", "at": [-90, 38], "surface": "garden", "y": 47, "wall": true, "size": 0.85},
		{"kind": "frame", "at": [370, 32], "surface": "garden-east", "y": 74, "wall": true, "size": 2.0, "color": "ffcf6b"},
		{"kind": "shelf", "at": [370, 38], "surface": "garden-east", "y": 31, "wall": true, "size": 0.85},
		{"kind": "frame", "at": [610, 32], "surface": "garden-east", "y": 90, "wall": true, "size": 2.0, "color": "ffcf6b"},
		{"kind": "shelf", "at": [610, 38], "surface": "garden-east", "y": 47, "wall": true, "size": 0.85},
		{"kind": "frame", "at": [850, 32], "surface": "garden-east", "y": 74, "wall": true, "size": 2.0, "color": "ffcf6b"},
		{"kind": "shelf", "at": [850, 38], "surface": "garden-east", "y": 31, "wall": true, "size": 0.85},
	]},
}
