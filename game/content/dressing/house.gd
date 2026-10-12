extends RefCounted
## A House for Two at golden hour: wooden stairs and corridor floors, rugs,
## shelves and pictures on the back walls, and plants hanging in the sunroom.
## Wall pieces hang above head height against each room's back wall.

const DATA := {
	"look": "golden",
	"stairs": "timber",
	"bridges": "timber",
	"cables": "floor",
	"props": {"*": [
		{"kind": "rug", "at": [-520, 0], "surface": "foyer", "width": 80, "depth": 60, "color": "b5654a"},
		{"kind": "shelf", "at": [-520, -240], "surface": "foyer", "y": 120, "wall": true},
		{"kind": "frame", "at": [-300, -248], "surface": "foyer", "y": 125, "wall": true, "color": "e3c27a"},
		{"kind": "rug", "at": [-60, -170], "surface": "workshop", "width": 90, "depth": 50, "color": "8f6d4d"},
		{"kind": "shelf", "at": [-90, -240], "surface": "workshop", "y": 118, "wall": true, "size": 0.8},
		{"kind": "frame", "at": [450, -248], "surface": "loft", "y": 120, "wall": true, "color": "9cbf7e"},
		{"kind": "shelf", "at": [655, -240], "surface": "loft", "y": 118, "wall": true, "size": 0.7},
		{"kind": "rug", "at": [450, -170], "surface": "lower-hall", "width": 90, "depth": 60, "color": "c98f6a"},
		{"kind": "frame", "at": [640, -248], "surface": "lower-hall", "y": 115, "wall": true, "color": "e9a3a0"},
		{"kind": "rug", "at": [900, -120], "surface": "sunroom", "width": 120, "depth": 60, "color": "a5845f"},
		{"kind": "basket", "at": [850, -236], "surface": "sunroom", "y": 140, "wall": true},
		{"kind": "basket", "at": [1060, -236], "surface": "sunroom", "y": 140, "wall": true},
	]},
}
