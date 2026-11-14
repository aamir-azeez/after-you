extends RefCounted
## Themes: saved sets of dressing picks. A dressing names one with "theme" and
## gets its look, ground, stairs, bridges, cables and fireflies, and a style for
## every prop slot (content/dressing/prop_styles.gd). Anything the dressing
## gives itself wins, slot by slot ("picks") and island by island ("ground").
##
## Each theme was taken from a published chapter, so that chapter's own picks
## come out exactly (tests/test_dressing_mixes.gd): garden from High and Low,
## harbour from Turn of the Tide, house from A House for Two.

const THEMES := {
	"garden": {
		"look": "meadow", "ground": {"*": "grass"}, "stairs": "timber", "bridges": "timber", "cables": "floor",
		"picks": {"lamp": "lantern", "tree": "orchard", "shrub": "flowering", "trim": "flowers", "scatter": "tufts",
			"bank": "meadow", "fence": "hedge", "railing": "picket", "bench": "bench", "path": "stones",
			"clutter": "crates", "landmark": "cottage", "wall_hanging": "basket", "tag": "painted_tile",
			"lever": "plain", "selector": "plain", "pad": "plain", "goal": "bell"},
	},
	"harbour": {
		"look": "dusk", "ground": {"*": "terracotta"}, "stairs": "timber", "bridges": "timber", "fireflies": 12,
		"picks": {"lamp": "lamp_post", "tree": "orchard", "shrub": "flowering", "trim": "flowers", "scatter": "tufts",
			"bank": "meadow", "fence": "stone", "railing": "timber", "bench": "bench", "path": "boards",
			"clutter": "barrel", "landmark": "tower", "wall_hanging": "frame", "tag": "wooden_plaque",
			"lever": "brass", "selector": "brass", "pad": "stand_spot", "goal": "bell"},
	},
	"house": {
		"look": "golden", "stairs": "timber", "bridges": "timber", "cables": "floor",
		"picks": {"lamp": "lantern", "tree": "potted_fern", "shrub": "pot", "trim": "flowers", "scatter": "tufts",
			"bank": "terracotta", "fence": "stone", "railing": "plaster", "bench": "bench", "path": "rug",
			"clutter": "crates", "landmark": "cottage", "wall_hanging": "shelf", "tag": "painted_tile",
			"lever": "plain", "selector": "plain", "pad": "plain", "goal": "bell"},
	},
}
