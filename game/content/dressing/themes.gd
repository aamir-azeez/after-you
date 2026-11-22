extends RefCounted
## Themes: saved sets of dressing picks. A dressing names one with "theme" and
## gets its look, ground, stairs, bridges, cables and fireflies, and a style for
## every prop slot (content/dressing/prop_styles.gd). Anything the dressing
## gives itself wins, slot by slot ("picks") and island by island ("ground").
##
## Each theme was taken from a published chapter, so that chapter's own picks
## come out exactly (tests/test_dressing_mixes.gd): garden from High and Low,
## harbour from Turn of the Tide, house from A House for Two.
##
## Each theme also grows its own edging along the floors a dressing names in
## "edged" (content/dressing/placement.gd): a planted bank behind, a low lip
## of trim in front where the camera looks across, a bank with the level's
## fence down the left and a lip of trim down the right. Every piece is cut
## around crossings, controls and starts by the dressing lint's own rules.

## Edge -> props grown along it (cm): "depth" and "height" of a bank, the
## "spacing" of a repeated prop, the "inset" of a line from its ends.
const EDGING := {
	"back": [{"slot": "bank", "depth": 80, "height": 12}],
	"front": [{"slot": "bank", "depth": 50, "height": 6}, {"slot": "trim", "spacing": 95, "vary": true}],
	"left": [{"slot": "bank", "depth": 60, "height": 12}, {"slot": "fence", "inset": 30}],
	"right": [{"slot": "bank", "depth": 40, "height": 6}, {"slot": "trim", "spacing": 95, "vary": true}],
}

const THEMES := {
	"garden": {
		"edging": EDGING,
		"look": "meadow", "ground": {"*": "grass"}, "stairs": "timber", "bridges": "timber", "cables": "floor",
		"picks": {"lamp": "lantern", "tree": "orchard", "shrub": "flowering", "trim": "flowers", "scatter": "tufts",
			"bank": "meadow", "fence": "hedge", "railing": "picket", "bench": "bench", "path": "stones",
			"clutter": "crates", "landmark": "cottage", "wall_hanging": "basket", "tag": "painted_tile", "barrier": "rope",
			"lever": "plain", "selector": "plain", "pad": "board", "goal": "bell", "lift": "plain", "deck": "plank", "raft": "logs", "ladder": "rope", "fog": "mist", "spillway": "trickle", "carried_item": "parcel", "current": "ripples", "pulley": "lantern_hook", "seabed": "sand", "item_spot": "none"},
	},
	"harbour": {
		"edging": EDGING,
		"look": "dusk", "ground": {"*": "terracotta"}, "stairs": "timber", "bridges": "timber", "fireflies": 12,
		"picks": {"lamp": "lamp_post", "tree": "orchard", "shrub": "flowering", "trim": "flowers", "scatter": "tufts",
			"bank": "meadow", "fence": "stone", "railing": "timber", "bench": "bench", "path": "boards",
			"clutter": "barrel", "landmark": "tower", "wall_hanging": "frame", "tag": "wooden_plaque", "barrier": "rope",
			"lever": "brass", "selector": "brass", "pad": "board", "goal": "bell", "lift": "plain", "deck": "plank", "raft": "logs", "ladder": "rope", "fog": "mist", "spillway": "trickle", "carried_item": "parcel", "current": "ripples", "pulley": "theme_hanger", "seabed": "sand", "item_spot": "none"},
	},
	"house": {
		"edging": EDGING,
		"look": "golden", "stairs": "timber", "bridges": "timber", "cables": "floor",
		"picks": {"lamp": "lantern", "tree": "potted_fern", "shrub": "pot", "trim": "flowers", "scatter": "tufts",
			"bank": "terracotta", "fence": "stone", "railing": "plaster", "bench": "bench", "path": "rug",
			"clutter": "crates", "landmark": "cottage", "wall_hanging": "shelf", "tag": "painted_tile", "barrier": "rope",
			"lever": "plain", "selector": "plain", "pad": "board", "goal": "bell", "lift": "plain", "deck": "plank", "raft": "logs", "ladder": "rope", "fog": "mist", "spillway": "trickle", "carried_item": "parcel", "current": "ripples", "pulley": "little_roof", "seabed": "sand", "item_spot": "none"},
	},
}
