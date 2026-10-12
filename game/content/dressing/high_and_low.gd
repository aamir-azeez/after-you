extends RefCounted
## High and Low: a sunny meadow. Grass islands, a wooden loft deck held up by
## posts at the back of the lower ledge, wooden stairs, floor-bound gate cables,
## and planted banks along the back and sides of every island.


const DATA := {
	"look": "meadow",
	"ground": {"*": "grass", "loft": "deck"},
	"stairs": "timber",
	"cables": "floor",
	"bridges": "timber",
	"props": {"*": [
		# Shore: a planted bank behind and to the left, flowers along the front.
		{"kind": "bank", "rect": [-700, -330, -240, -240], "surface": "shore", "height": 12},
		{"kind": "bank", "rect": [-730, -240, -640, 260], "surface": "shore", "height": 12},
		{"kind": "bank", "rect": [-640, 240, -240, 272], "surface": "shore", "height": 6},
		{"kind": "tree", "at": [-600, -292], "surface": "shore", "y": 12, "size": 0.95},
		{"kind": "bench", "at": [-480, -288], "surface": "shore", "y": 12},
		{"kind": "lantern", "at": [-405, -282], "surface": "shore", "y": 12},
		{"kind": "bush", "at": [-345, -295], "surface": "shore", "y": 12, "size": 0.9},
		{"kind": "tree", "at": [-280, -296], "surface": "shore", "y": 12, "size": 0.8, "variant": 1},
		{"kind": "hedge", "from": [-690, -200], "to": [-690, 220], "surface": "shore", "y": 12},
		{"kind": "signpost", "at": [-700, 230], "surface": "shore", "y": 12, "size": 0.8, "rot": -20},
		{"kind": "row", "of": {"kind": "flowers", "size": 0.6}, "from": [-610, 262], "to": [-270, 262], "count": 5, "surface": "shore", "y": 6, "vary": true},
		{"kind": "row", "of": {"kind": "tuft", "detail": true}, "from": [-610, -220], "to": [-280, -220], "count": 6, "surface": "shore", "vary": true},
		# The loft deck: a rail along its back, two posts down to the ledge's back.
		{"kind": "fence", "from": [-74, -256], "to": [314, -256], "surface": "loft"},
		{"kind": "post", "at": [150, -115], "y": -30, "height": 170},
		{"kind": "post", "at": [300, -115], "y": -30, "height": 170},
		# Lower ledge: a bank of planting behind its open end, flowers in front.
		{"kind": "bank", "rect": [330, -170, 576, -96], "surface": "lower-ledge", "height": 10},
		{"kind": "bank", "rect": [128, 192, 576, 222], "surface": "lower-ledge", "height": 6},
		{"kind": "bush", "at": [400, -145], "surface": "lower-ledge", "y": 10, "size": 0.8},
		{"kind": "lantern", "at": [470, -130], "surface": "lower-ledge", "y": 10},
		{"kind": "flowers", "at": [535, -150], "surface": "lower-ledge", "y": 10, "size": 0.7},
		{"kind": "row", "of": {"kind": "flowers", "size": 0.5}, "from": [160, 212], "to": [545, 212], "count": 5, "surface": "lower-ledge", "y": 6, "vary": true},
		# Garden: trees and a bank behind, a hedge to the right, flowers in front.
		{"kind": "bank", "rect": [736, -270, 1088, -176], "surface": "garden", "height": 12},
		{"kind": "bank", "rect": [1088, -270, 1180, 200], "surface": "garden", "height": 12},
		{"kind": "bank", "rect": [736, 176, 1088, 206], "surface": "garden", "height": 6},
		{"kind": "tree", "at": [790, -228], "surface": "garden", "y": 12, "size": 0.9, "variant": 1},
		{"kind": "lantern", "at": [870, -215], "surface": "garden", "y": 12},
		{"kind": "bush", "at": [950, -220], "surface": "garden", "y": 12},
		{"kind": "tree", "at": [1040, -232], "surface": "garden", "y": 12, "size": 1.0},
		{"kind": "hedge", "from": [1140, -150], "to": [1140, 160], "surface": "garden", "y": 12},
		{"kind": "row", "of": {"kind": "flowers", "size": 0.5}, "from": [765, 194], "to": [1060, 194], "count": 4, "surface": "garden", "y": 6, "vary": true},
	]},
}
