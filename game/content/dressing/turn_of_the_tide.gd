extends RefCounted
## Turn of the Tide at dusk: pale sand beaches, terracotta terraces and honey
## cobbled quays. A harbour light, a boathouse, trees, lamps and a beached boat
## stand on the bank behind the quays; low flowers line the beach fronts, so
## nothing on the camera's side of the harbour can hide a spirit. Low bollards
## stand on the quay fenders and ivy hangs down the quay faces, off every
## walkable floor; lobster pots and barrels sit out on the foreshore.

const DATA := {
	"look": "dusk",
	"ground": {"*": "terracotta",
		"mole-beach": "sand", "w-beach": "sand", "m-beach": "sand", "e-beach": "sand", "r-beach": "sand",
		"mole-quay": "honey_cobble", "w-quay": "honey_cobble", "m-quay": "honey_cobble", "e-quay": "honey_cobble", "r-quay": "honey_cobble",
		"sea-chamber": "timber", "lock-chamber": "timber"},
	"stairs": "timber",
	"bridges": "timber",
	"fireflies": 12,
	"props": {"*": [
		# Behind the mole: the harbour light on its bank.
		{"kind": "bank", "rect": [-960, -690, -704, -490], "surface": "mole-quay", "height": 12},
		{"kind": "tower", "at": [-860, -605], "surface": "mole-quay", "y": 12, "size": 0.7},
		{"kind": "bush", "at": [-750, -540], "surface": "mole-quay", "y": 12, "size": 0.7},
		# Behind the west quay, west of the quay catwalk: a tree, a lamp and a bench.
		{"kind": "bank", "rect": [-512, -650, -224, -490], "surface": "w-quay", "height": 12},
		{"kind": "tree", "at": [-450, -575], "surface": "w-quay", "y": 12, "size": 0.85},
		{"kind": "lamp_post", "at": [-370, -530], "surface": "w-quay", "y": 12},
		{"kind": "bench", "at": [-290, -540], "surface": "w-quay", "y": 12},
		# Behind the mill quay's waiting steps, kept clear of the steps.
		{"kind": "bank", "rect": [0, -690, 384, -560], "surface": "m-quay", "height": 12},
		{"kind": "tree", "at": [60, -620], "surface": "m-quay", "y": 12, "size": 0.7},
		{"kind": "bush", "at": [190, -610], "surface": "m-quay", "y": 12, "size": 0.7},
		{"kind": "tree", "at": [325, -625], "surface": "m-quay", "y": 12, "size": 0.7, "variant": 1},
		# Behind the east quay: the boathouse, crates, a lamp and a beached boat.
		{"kind": "bank", "rect": [576, -700, 1152, -490], "surface": "e-quay", "height": 12},
		{"kind": "crate", "at": [650, -535], "surface": "e-quay", "y": 12, "stack": true},
		{"kind": "cottage", "at": [810, -605], "surface": "e-quay", "y": 12, "width": 170, "depth": 100, "size": 0.85},
		{"kind": "lamp_post", "at": [965, -530], "surface": "e-quay", "y": 12},
		{"kind": "boat", "at": [1070, -590], "surface": "e-quay", "y": 12, "rot": 12},
		# Behind the rock quay: trees and a lamp above the bell.
		{"kind": "bank", "rect": [1344, -670, 1728, -490], "surface": "r-quay", "height": 12},
		{"kind": "tree", "at": [1420, -585], "surface": "r-quay", "y": 12, "size": 0.85, "variant": 1},
		{"kind": "lamp_post", "at": [1540, -530], "surface": "r-quay", "y": 12},
		{"kind": "tree", "at": [1650, -595], "surface": "r-quay", "y": 12, "size": 0.8},
		# The beach fronts: low banks of flowers that never hide a spirit.
		{"kind": "bank", "rect": [-960, 484, -704, 514], "surface": "mole-beach", "height": 6},
		{"kind": "row", "of": {"kind": "flowers", "size": 0.45}, "from": [-925, 499], "to": [-740, 499], "count": 3, "surface": "mole-beach", "y": 6, "vary": true},
		{"kind": "bank", "rect": [-512, 484, -224, 514], "surface": "w-beach", "height": 6},
		{"kind": "row", "of": {"kind": "flowers", "size": 0.45}, "from": [-480, 499], "to": [-260, 499], "count": 3, "surface": "w-beach", "y": 6, "vary": true},
		{"kind": "bank", "rect": [0, 484, 192, 514], "surface": "m-beach", "height": 6},
		{"kind": "row", "of": {"kind": "flowers", "size": 0.45}, "from": [40, 499], "to": [150, 499], "count": 2, "surface": "m-beach", "y": 6, "vary": true},
		{"kind": "bank", "rect": [576, 484, 1152, 514], "surface": "e-beach", "height": 6},
		{"kind": "row", "of": {"kind": "flowers", "size": 0.45}, "from": [610, 499], "to": [1120, 499], "count": 5, "surface": "e-beach", "y": 6, "vary": true},
		{"kind": "bank", "rect": [1344, 484, 1728, 514], "surface": "r-beach", "height": 6},
		{"kind": "row", "of": {"kind": "flowers", "size": 0.45}, "from": [1375, 499], "to": [1700, 499], "count": 4, "surface": "r-beach", "y": 6, "vary": true},
		# Sea grass along the beaches' front edges: flat, and gone on low quality.
		{"kind": "row", "of": {"kind": "tuft", "detail": true}, "from": [-490, 468], "to": [-250, 468], "count": 5, "surface": "w-beach", "vary": true},
		{"kind": "row", "of": {"kind": "tuft", "detail": true}, "from": [600, 468], "to": [1130, 468], "count": 7, "surface": "e-beach", "vary": true},
		# Bollards on the quay fenders, just off each quay's front edge and clear of its steps.
		{"kind": "bollard", "at": [-948, -216], "surface": "mole-quay"}, {"kind": "bollard", "at": [-716, -216], "surface": "mole-quay"},
		{"kind": "bollard", "at": [-500, -216], "surface": "w-quay"}, {"kind": "bollard", "at": [-240, -216], "surface": "w-quay"},
		{"kind": "bollard", "at": [12, -216], "surface": "m-quay"}, {"kind": "bollard", "at": [372, -216], "surface": "m-quay"},
		{"kind": "bollard", "at": [588, -216], "surface": "e-quay"}, {"kind": "bollard", "at": [1140, -216], "surface": "e-quay"},
		{"kind": "bollard", "at": [1356, -216], "surface": "r-quay"}, {"kind": "bollard", "at": [1716, -216], "surface": "r-quay"},
		# The bollard step's own bollard, on the mill quay's back fender beside the
		# step: whoever holds the step stands on its spot, clear of it.
		{"kind": "bollard", "at": [266, -490], "surface": "m-quay"},
		# Ivy down the quay faces.
		{"kind": "ivy", "at": [-760, -213], "surface": "mole-quay", "length": 50}, {"kind": "ivy", "at": [-440, -213], "surface": "w-quay", "length": 45},
		{"kind": "ivy", "at": [-300, -213], "surface": "w-quay", "length": 55}, {"kind": "ivy", "at": [230, -213], "surface": "m-quay", "length": 50},
		{"kind": "ivy", "at": [850, -213], "surface": "e-quay", "length": 45}, {"kind": "ivy", "at": [1010, -213], "surface": "e-quay", "length": 55},
		{"kind": "ivy", "at": [1580, -213], "surface": "r-quay", "length": 50},
		# Out on the foreshore, below the beaches: lobster pots and barrels.
		{"kind": "lobster_pot", "at": [-430, 575], "surface": "w-beach", "y": -30, "rot": 12}, {"kind": "barrel", "at": [-300, 600], "surface": "w-beach", "y": -30},
		{"kind": "lobster_pot", "at": [700, 590], "surface": "e-beach", "y": -30, "rot": -20}, {"kind": "barrel", "at": [990, 585], "surface": "e-beach", "y": -30},
		{"kind": "lobster_pot", "at": [1470, 575], "surface": "r-beach", "y": -30, "rot": 30}, {"kind": "barrel", "at": [1620, 600], "surface": "r-beach", "y": -30},
		# Shells along the beach fronts: flat, so they may lie on the sand.
		{"kind": "row", "of": {"kind": "rug", "width": 8, "depth": 6, "color": "efe0cc"}, "from": [-470, 458], "to": [-280, 462], "count": 3, "surface": "w-beach", "vary": true},
		{"kind": "row", "of": {"kind": "rug", "width": 8, "depth": 6, "color": "e8c4b4"}, "from": [640, 460], "to": [1080, 456], "count": 4, "surface": "e-beach", "vary": true},
		{"kind": "row", "of": {"kind": "rug", "width": 8, "depth": 6, "color": "efe0cc"}, "from": [1400, 458], "to": [1680, 462], "count": 3, "surface": "r-beach", "vary": true},
	]},
}
