extends RefCounted
## Turn of the Tide at dusk: sand beaches, sandstone terraces and harbour-stone
## quays. A harbour light, a boathouse, trees, lamps and a beached boat stand on
## the bank behind the quays; low flowers line the beach fronts, so nothing on
## the camera's side of the harbour can hide a spirit.

const DATA := {
	"look": "dusk",
	"camera": "follow",
	"ground": {"*": "sandstone",
		"mole-beach": "sand", "w-beach": "sand", "m-beach": "sand", "e-beach": "sand", "r-beach": "sand",
		"mole-quay": "harbour", "w-quay": "harbour", "m-quay": "harbour", "e-quay": "harbour", "r-quay": "harbour",
		"sea-chamber": "timber", "lock-chamber": "timber"},
	"stairs": "timber",
	"bridges": "timber",
	"fireflies": 12,
	"props": {"*": [
		# Behind the mole: the harbour light on its bank.
		{"kind": "bank", "rect": [-960, -690, -704, -490], "surface": "mole-quay", "height": 12},
		{"kind": "tower", "at": [-860, -605], "surface": "mole-quay", "y": 12, "size": 0.7},
		{"kind": "bush", "at": [-750, -540], "surface": "mole-quay", "y": 12, "size": 0.7},
		# Behind the west quay: trees, a lamp and a bench.
		{"kind": "bank", "rect": [-512, -650, -128, -490], "surface": "w-quay", "height": 12},
		{"kind": "tree", "at": [-450, -575], "surface": "w-quay", "y": 12, "size": 0.85},
		{"kind": "lamp_post", "at": [-360, -530], "surface": "w-quay", "y": 12},
		{"kind": "bench", "at": [-265, -540], "surface": "w-quay", "y": 12},
		{"kind": "tree", "at": [-180, -585], "surface": "w-quay", "y": 12, "size": 0.75, "variant": 1},
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
		{"kind": "bank", "rect": [-512, 484, -128, 514], "surface": "w-beach", "height": 6},
		{"kind": "row", "of": {"kind": "flowers", "size": 0.45}, "from": [-480, 499], "to": [-160, 499], "count": 4, "surface": "w-beach", "y": 6, "vary": true},
		{"kind": "bank", "rect": [0, 484, 192, 514], "surface": "m-beach", "height": 6},
		{"kind": "row", "of": {"kind": "flowers", "size": 0.45}, "from": [40, 499], "to": [150, 499], "count": 2, "surface": "m-beach", "y": 6, "vary": true},
		{"kind": "bank", "rect": [576, 484, 1152, 514], "surface": "e-beach", "height": 6},
		{"kind": "row", "of": {"kind": "flowers", "size": 0.45}, "from": [610, 499], "to": [1120, 499], "count": 5, "surface": "e-beach", "y": 6, "vary": true},
		{"kind": "bank", "rect": [1344, 484, 1728, 514], "surface": "r-beach", "height": 6},
		{"kind": "row", "of": {"kind": "flowers", "size": 0.45}, "from": [1375, 499], "to": [1700, 499], "count": 4, "surface": "r-beach", "y": 6, "vary": true},
		# Sea grass along the beaches' front edges: flat, and gone on low quality.
		{"kind": "row", "of": {"kind": "tuft", "detail": true}, "from": [-490, 468], "to": [-150, 468], "count": 6, "surface": "w-beach", "vary": true},
		{"kind": "row", "of": {"kind": "tuft", "detail": true}, "from": [600, 468], "to": [1130, 468], "count": 7, "surface": "e-beach", "vary": true},
	]},
}
