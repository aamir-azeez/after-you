extends RefCounted
## The Conservatory on a sunny day: warm terracotta tiles, a timber stair,
## ferns in troughs behind the glass, baskets hanging inside it, and a garden
## with trees and a hedge. Nothing stands on a route or near a lamp.

const DATA := {
	"look": "meadow",
	"ground": {"*": "tile", "garden": "grass"},
	"stairs": "timber",
	"bridges": "timber",
	"props": {"*": [
		# Court: ferns in a trough behind the glass, baskets hung inside it.
		{"kind": "bank", "rect": [-650, -540, -150, -448], "surface": "court", "height": 14, "side": "b97b5a", "top": "6b5240"},
		{"kind": "fern", "at": [-580, -494], "surface": "court", "y": 14},
		{"kind": "fern", "at": [-460, -496], "surface": "court", "y": 14, "size": 0.9},
		{"kind": "fern", "at": [-340, -494], "surface": "court", "y": 14},
		{"kind": "fern", "at": [-220, -496], "surface": "court", "y": 14, "size": 0.85},
		{"kind": "basket", "at": [-520, -436], "surface": "court", "y": 150, "wall": true},
		{"kind": "basket", "at": [-300, -436], "surface": "court", "y": 150, "wall": true},
		{"kind": "bank", "rect": [-730, -448, -640, 330], "surface": "court", "height": 14, "side": "b97b5a", "top": "6b5240"},
		{"kind": "row", "of": {"kind": "pot", "size": 1.1}, "from": [-686, -380], "to": [-686, 260], "count": 5, "surface": "court", "y": 14, "vary": true},
		{"kind": "bank", "rect": [-640, 320, -480, 350], "surface": "court", "height": 6, "side": "b97b5a", "top": "6b5240"},
		{"kind": "bank", "rect": [-350, 320, -160, 350], "surface": "court", "height": 6, "side": "b97b5a", "top": "6b5240"},
		{"kind": "row", "of": {"kind": "flowers", "size": 0.45}, "from": [-610, 336], "to": [-510, 336], "count": 2, "surface": "court", "y": 6},
		{"kind": "row", "of": {"kind": "flowers", "size": 0.45}, "from": [-320, 336], "to": [-190, 336], "count": 2, "surface": "court", "y": 6},
		# Gallery: a trough of ferns behind its glass and baskets from the ribs.
		{"kind": "bank", "rect": [32, -540, 672, -448], "surface": "gallery", "height": 14, "side": "b97b5a", "top": "6b5240"},
		{"kind": "fern", "at": [100, -494], "surface": "gallery", "y": 14, "size": 0.9},
		{"kind": "fern", "at": [260, -496], "surface": "gallery", "y": 14},
		{"kind": "fern", "at": [470, -494], "surface": "gallery", "y": 14, "size": 0.85},
		{"kind": "fern", "at": [610, -496], "surface": "gallery", "y": 14},
		{"kind": "basket", "at": [130, -436], "surface": "gallery", "y": 150, "wall": true},
		{"kind": "basket", "at": [560, -436], "surface": "gallery", "y": 150, "wall": true},
		# Garden: trees behind, a hedge to the east, flowers in front.
		{"kind": "bank", "rect": [672, -270, 880, -128], "surface": "garden", "height": 12},
		{"kind": "bank", "rect": [864, -128, 950, 330], "surface": "garden", "height": 12},
		{"kind": "bank", "rect": [680, 320, 864, 350], "surface": "garden", "height": 6},
		{"kind": "tree", "at": [770, -210], "surface": "garden", "y": 12, "size": 0.8, "variant": 1},
		{"kind": "lantern", "at": [845, -200], "surface": "garden", "y": 12},
		{"kind": "hedge", "from": [912, -100], "to": [912, 300], "surface": "garden", "y": 12},
		{"kind": "row", "of": {"kind": "flowers", "size": 0.45}, "from": [710, 336], "to": [840, 336], "count": 3, "surface": "garden", "y": 6, "vary": true},
	]},
}
