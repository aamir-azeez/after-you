extends RefCounted
## The Wishing Well @2 at dusk: @1's lit windows with flower boxes down the
## cliff face (content/dressing/the_wishing_well.gd) where @2's shorter cliff
## still has them, less the one behind the old crane, and fireflies over the
## planting. The well, its bucket, the winch house and every route stay the
## world's own (presentation/wishing_well_scenery.gd).

const DATA := {
	"look": "dusk",
	"fireflies": 10,
	# The well's lip is edged with a low rail.
	"barrier": "rail",
	"props": {"*": [
		# Windows and flower boxes on the cliff face, between the ivy and clear
		# of both stairs and the crane.
		{"kind": "frame", "at": [-300, -12], "surface": "garden", "y": 74, "wall": true, "size": 2.0, "color": "ffcf6b"},
		{"kind": "shelf", "at": [-300, -2], "surface": "garden", "y": 31, "wall": true, "size": 0.85},
		{"kind": "frame", "at": [-122, -12], "surface": "garden", "y": 90, "wall": true, "size": 2.0, "color": "ffcf6b"},
		{"kind": "shelf", "at": [-122, -2], "surface": "garden", "y": 47, "wall": true, "size": 0.85},
		{"kind": "frame", "at": [498, -12], "surface": "garden-east", "y": 90, "wall": true, "size": 2.0, "color": "ffcf6b"},
		{"kind": "shelf", "at": [498, -2], "surface": "garden-east", "y": 47, "wall": true, "size": 0.85},
		{"kind": "frame", "at": [808, -12], "surface": "garden-east", "y": 74, "wall": true, "size": 2.0, "color": "ffcf6b"},
		{"kind": "shelf", "at": [808, -2], "surface": "garden-east", "y": 31, "wall": true, "size": 0.85},
	]},
}
