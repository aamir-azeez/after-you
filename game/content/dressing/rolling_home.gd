extends RefCounted
## Rolling Home: a sunny meadow walk to a cottage. The ball rolls home to the
## cottage garden; the garden bed is a timber flower bed; banks of planting
## line the back of every island.

const DATA := {
	"look": "meadow",
	"ground": {"*": "grass"},
	"bridges": "timber",
	"cables": "floor",
	"obstacles": "flowerbed",
	"props": {"*": [
		# Shore.
		{"kind": "bank", "rect": [-690, -300, -240, -208], "surface": "shore", "height": 12},
		{"kind": "bank", "rect": [-730, -208, -640, 240], "surface": "shore", "height": 12},
		{"kind": "bank", "rect": [-640, 208, -240, 240], "surface": "shore", "height": 6},
		{"kind": "tree", "at": [-590, -262], "surface": "shore", "y": 12, "size": 0.9},
		{"kind": "bush", "at": [-480, -262], "surface": "shore", "y": 12, "size": 0.8},
		{"kind": "lantern", "at": [-400, -252], "surface": "shore", "y": 12},
		{"kind": "tree", "at": [-300, -264], "surface": "shore", "y": 12, "size": 0.8, "variant": 1},
		{"kind": "hedge", "from": [-688, -180], "to": [-688, 200], "surface": "shore", "y": 12},
		{"kind": "row", "of": {"kind": "flowers", "size": 0.5}, "from": [-610, 226], "to": [-270, 226], "count": 5, "surface": "shore", "y": 6, "vary": true},
		# Middle island.
		{"kind": "bank", "rect": [-80, -300, 400, -208], "surface": "middle", "height": 12},
		{"kind": "bank", "rect": [-80, 208, 400, 240], "surface": "middle", "height": 6},
		{"kind": "tree", "at": [-20, -264], "surface": "middle", "y": 12, "size": 0.85, "variant": 2},
		{"kind": "bench", "at": [110, -256], "surface": "middle", "y": 12},
		{"kind": "lantern", "at": [195, -252], "surface": "middle", "y": 12},
		{"kind": "bush", "at": [270, -262], "surface": "middle", "y": 12, "size": 0.8},
		{"kind": "tree", "at": [350, -266], "surface": "middle", "y": 12, "size": 0.9, "variant": 1},
		{"kind": "row", "of": {"kind": "flowers", "size": 0.5}, "from": [-50, 226], "to": [370, 226], "count": 5, "surface": "middle", "y": 6, "vary": true},
		{"kind": "row", "of": {"kind": "tuft", "detail": true}, "from": [-50, -190], "to": [370, -190], "count": 7, "surface": "middle", "vary": true},
		# Far bank.
		{"kind": "bank", "rect": [560, -300, 960, -208], "surface": "far-bank", "height": 12},
		{"kind": "bank", "rect": [560, 208, 960, 240], "surface": "far-bank", "height": 6},
		{"kind": "tree", "at": [620, -264], "surface": "far-bank", "y": 12, "size": 0.9, "variant": 1},
		{"kind": "signpost", "at": [720, -256], "surface": "far-bank", "y": 12, "size": 0.85},
		{"kind": "bush", "at": [800, -262], "surface": "far-bank", "y": 12, "size": 0.8},
		{"kind": "lantern", "at": [880, -252], "surface": "far-bank", "y": 12},
		{"kind": "row", "of": {"kind": "flowers", "size": 0.5}, "from": [590, 226], "to": [930, 226], "count": 4, "surface": "far-bank", "y": 6, "vary": true},
		# Home: the cottage the ball rolls home to, in its own fenced garden.
		{"kind": "bank", "rect": [1110, -430, 1530, -208], "surface": "home", "height": 12},
		{"kind": "bank", "rect": [1520, -208, 1600, 240], "surface": "home", "height": 12},
		{"kind": "bank", "rect": [1120, 208, 1520, 240], "surface": "home", "height": 6},
		{"kind": "cottage", "at": [1400, -330], "surface": "home", "y": 12, "width": 180, "depth": 120},
		{"kind": "tree", "at": [1180, -320], "surface": "home", "y": 12, "size": 1.0},
		{"kind": "lamp_post", "at": [1290, -300], "surface": "home", "y": 12},
		{"kind": "fence", "from": [1125, -224], "to": [1335, -224], "surface": "home", "y": 12},
		{"kind": "fence", "from": [1420, -224], "to": [1515, -224], "surface": "home", "y": 12},
		{"kind": "path", "at": [1368, -140], "surface": "home", "width": 40, "depth": 120},
		{"kind": "hedge", "from": [1572, -180], "to": [1572, 200], "surface": "home", "y": 12},
		{"kind": "row", "of": {"kind": "flowers", "size": 0.5}, "from": [1150, 226], "to": [1490, 226], "count": 5, "surface": "home", "y": 6, "vary": true},
	]},
}
