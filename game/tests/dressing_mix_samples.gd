extends RefCounted
## High and Low's dressing written with prop slots and the garden theme
## (content/dressing/prop_styles.gd, themes.gd), and three mixes of it. The
## garden mix resolves to the published file exactly
## (tests/test_dressing_mixes.gd); the other two only change picks. Used by
## the mixes suite and by the private prop-mix board capture.

const KEY := "high-and-low@1"
const STAGE := "upper-path"

const HIGH_AND_LOW := {
	"theme": "garden",
	"ground": {"loft": "deck"},
	"props": {"*": [
		{"slot": "bank", "rect": [-700, -330, -240, -240], "surface": "shore", "height": 12},
		{"slot": "bank", "rect": [-730, -240, -640, 260], "surface": "shore", "height": 12},
		{"slot": "bank", "rect": [-640, 240, -240, 272], "surface": "shore", "height": 6},
		{"slot": "tree", "at": [-600, -292], "surface": "shore", "y": 12, "size": 0.95},
		{"slot": "bench", "at": [-480, -288], "surface": "shore", "y": 12},
		{"slot": "lamp", "at": [-405, -282], "surface": "shore", "y": 12},
		{"slot": "shrub", "at": [-345, -295], "surface": "shore", "y": 12, "size": 0.9},
		{"slot": "tree", "at": [-280, -296], "surface": "shore", "y": 12, "size": 0.8, "variant": 1},
		{"slot": "fence", "from": [-690, -200], "to": [-690, 220], "surface": "shore", "y": 12},
		{"kind": "signpost", "at": [-700, 230], "surface": "shore", "y": 12, "size": 0.8, "rot": -20},
		{"slot": "trim", "size": 0.6, "from": [-610, 262], "to": [-270, 262], "count": 5, "surface": "shore", "y": 6, "vary": true},
		{"slot": "scatter", "from": [-610, -220], "to": [-280, -220], "count": 6, "surface": "shore", "vary": true},
		{"slot": "railing", "from": [-74, -256], "to": [314, -256], "surface": "loft"},
		{"kind": "post", "at": [150, -115], "y": -30, "height": 170},
		{"kind": "post", "at": [300, -115], "y": -30, "height": 170},
		{"slot": "bank", "rect": [330, -170, 576, -96], "surface": "lower-ledge", "height": 10},
		{"slot": "bank", "rect": [128, 192, 576, 222], "surface": "lower-ledge", "height": 6},
		{"slot": "shrub", "at": [400, -145], "surface": "lower-ledge", "y": 10, "size": 0.8},
		{"slot": "lamp", "at": [470, -130], "surface": "lower-ledge", "y": 10},
		{"slot": "trim", "at": [535, -150], "surface": "lower-ledge", "y": 10, "size": 0.7},
		{"slot": "trim", "size": 0.5, "from": [160, 212], "to": [545, 212], "count": 5, "surface": "lower-ledge", "y": 6, "vary": true},
		{"slot": "bank", "rect": [736, -270, 1088, -176], "surface": "garden", "height": 12},
		{"slot": "bank", "rect": [1088, -270, 1180, 200], "surface": "garden", "height": 12},
		{"slot": "bank", "rect": [736, 176, 1088, 206], "surface": "garden", "height": 6},
		{"slot": "tree", "at": [790, -228], "surface": "garden", "y": 12, "size": 0.9, "variant": 1},
		{"slot": "lamp", "at": [870, -215], "surface": "garden", "y": 12},
		{"slot": "shrub", "at": [950, -220], "surface": "garden", "y": 12},
		{"slot": "tree", "at": [1040, -232], "surface": "garden", "y": 12, "size": 1.0},
		{"slot": "fence", "from": [1140, -150], "to": [1140, 160], "surface": "garden", "y": 12},
		{"slot": "trim", "size": 0.5, "from": [765, 194], "to": [1060, 194], "count": 4, "surface": "garden", "y": 6, "vary": true},
	]},
}

## Name -> {"theme", optional "picks" and other fields}: each mix is the
## slot dressing above with these fields over it.
const MIX_FIELDS := {
	"garden": {},
	"harbour": {"theme": "harbour", "ground": {"loft": "timber"}, "picks": {"scatter": "shells"}},
	"garden_mixed": {"look": "golden", "fireflies": 10,
		"picks": {"tree": "pine", "lamp": "lamp_post", "fence": "picket", "bank": "moss", "trim": "bollards", "bench": "crates"}},
}

## Name -> the full dressing of that mix.
static func mixes() -> Dictionary:
	var result: Dictionary = {}
	for name: String in MIX_FIELDS:
		var mix: Dictionary = HIGH_AND_LOW.duplicate(true)
		mix.merge(MIX_FIELDS[name].duplicate(true), true)
		result[name] = mix
	return result
