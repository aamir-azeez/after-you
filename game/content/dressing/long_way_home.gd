extends RefCounted
## Long Way Home at golden hour: grass banks and courts, a raised plank lane on
## posts, a timber house, lamps lit along the way and fireflies in the garden.
## Version 2 shares this layout (content/dressing/long_way_home_v2.gd).

const DATA := {
	"look": "golden",
	"ground": {"*": "grass", "upper-lane": "deck", "service-landing": "deck", "home-room": "timber", "near-porch": "sandstone"},
	"stairs": "timber",
	"bridges": "timber",
	"fireflies": 14,
	"props": {"*": [
		# Source court: trees and a lamp behind, a hedge to the west.
		{"kind": "bank", "rect": [-660, -440, -256, -352], "surface": "source-court", "height": 12},
		{"kind": "bank", "rect": [-730, -352, -640, 160], "surface": "source-court", "height": 12},
		{"kind": "tree", "at": [-580, -412], "surface": "source-court", "y": 12, "size": 0.9},
		{"kind": "lamp_post", "at": [-470, -392], "surface": "source-court", "y": 12},
		{"kind": "bush", "at": [-390, -398], "surface": "source-court", "y": 12, "size": 0.8},
		{"kind": "tree", "at": [-310, -404], "surface": "source-court", "y": 12, "size": 0.75, "variant": 1},
		{"kind": "hedge", "from": [-688, -320], "to": [-688, 130], "surface": "source-court", "y": 12},
		# Partner bank: a bench and a lamp on its west bank, flowers in front.
		{"kind": "bank", "rect": [-740, 224, -640, 560], "surface": "partner-bank", "height": 12},
		{"kind": "bank", "rect": [-640, 544, -256, 574], "surface": "partner-bank", "height": 6},
		{"kind": "bench", "at": [-694, 420], "surface": "partner-bank", "y": 12, "rot": 90},
		{"kind": "lamp_post", "at": [-700, 290], "surface": "partner-bank", "y": 12},
		{"kind": "row", "of": {"kind": "flowers", "size": 0.45}, "from": [-610, 559], "to": [-290, 559], "count": 4, "surface": "partner-bank", "y": 6, "vary": true},
		# The raised lane: a rail along its back and posts under it.
		{"kind": "fence", "from": [-58, -366], "to": [634, -366], "surface": "upper-lane"},
		{"kind": "post", "at": [-40, -335], "y": -40, "height": 180},
		{"kind": "post", "at": [230, -335], "y": -40, "height": 180},
		{"kind": "post", "at": [470, -335], "y": -40, "height": 180},
		# The service landing on its posts.
		{"kind": "post", "at": [884, -112], "y": -30, "height": 104},
		{"kind": "post", "at": [1004, -112], "y": -30, "height": 104},
		# Garden and the walk home: flowers along the front edges, clear of the
		# version 2 walk gate.
		{"kind": "bank", "rect": [384, 320, 700, 350], "surface": "garden", "height": 6},
		{"kind": "row", "of": {"kind": "flowers", "size": 0.45}, "from": [410, 335], "to": [680, 335], "count": 4, "surface": "garden", "y": 6, "vary": true},
		{"kind": "bank", "rect": [900, 480, 1184, 510], "surface": "garden-walk", "height": 6},
		{"kind": "row", "of": {"kind": "flowers", "size": 0.45}, "from": [930, 495], "to": [1160, 495], "count": 4, "surface": "garden-walk", "y": 6, "vary": true},
		# Home: a planted bank on the east side and a rug inside.
		{"kind": "bank", "rect": [1504, -100, 1590, 330], "surface": "home-room", "height": 12},
		{"kind": "hedge", "from": [1548, -70], "to": [1548, 300], "surface": "home-room", "y": 12},
		{"kind": "rug", "at": [1300, 240], "surface": "home-room", "width": 80, "depth": 50, "color": "b5654a"},
	]},
}
