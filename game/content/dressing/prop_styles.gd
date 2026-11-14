extends RefCounted
## Prop slots and their styles: the mixable half of a dressing. A dressing prop
## may name a slot ("slot": "lamp") instead of a kind; the level's pick for that
## slot (content/dressing/themes.gd, then the dressing's own "picks") says which
## style stands there. A style is the kit/props.gd fields it fixes (the kind
## and its look); the prop keeps everything about where it stands and how big
## it is, and a field the prop gives itself wins over the style's.
##
## A slot prop with "from" and "to" lays a line: a line kind (fence, hedge,
## wall) runs along it, and any other kind repeats along it as a kit row
## ("count", "vary"). "style" on one prop pins that prop to a style whatever
## the level picks.
##
## A style added here is offered to every level at once. Nothing here is new
## art: every style is a kit/props.gd kind with fixed fields.

const SLOTS := {
	"lamp": {
		"lantern": {"kind": "lantern"},
		"lamp_post": {"kind": "lamp_post"},
	},
	"tree": {
		"orchard": {"kind": "tree"},
		"pine": {"kind": "pine"},
		"potted_fern": {"kind": "fern"},
	},
	"shrub": {
		"flowering": {"kind": "bush"},
		"green": {"kind": "bush", "flowers": false},
		"fern": {"kind": "fern"},
		"pot": {"kind": "pot"},
	},
	# Low things along the front of a bank. Each stays under kit/props.gd LOW
	# laid at trim size on a bank's front lip, so it never hides a spirit
	# (tests/test_dressing_mixes.gd TRIM_SIZE, TRIM_LIP).
	"trim": {
		"flowers": {"kind": "flowers"},
		"bollards": {"kind": "bollard"},
	},
	# Low bits that may lie on walkable ground. Lay them along a floor's edges,
	# off the walking lines. Shells lay about half as many clusters as a line
	# asks for ("row_every"), always at its two ends, the floor's corners.
	"scatter": {
		"tufts": {"kind": "tuft", "detail": true},
		"shells": {"kind": "shells", "size": 2.6, "row_every": 2},
	},
	# The low planted bank edge props stand on.
	"bank": {
		"meadow": {"kind": "bank"},
		"terracotta": {"kind": "bank", "side": "b97b5a", "top": "6b5240"},
		"moss": {"kind": "bank", "top": "8fa56c"},
	},
	# A line along the ground at an island's side or back.
	"fence": {
		"hedge": {"kind": "hedge"},
		"picket": {"kind": "fence"},
		"stone": {"kind": "stone_wall"},
	},
	# A line along the back of a raised floor.
	"railing": {
		"picket": {"kind": "fence"},
		"timber": {"kind": "wall", "height": 32, "thickness": 8, "color": "8a6b4e"},
		"plaster": {"kind": "wall", "height": 36, "thickness": 10, "color": "efe2c4"},
	},
	"bench": {
		"bench": {"kind": "bench"},
		"crates": {"kind": "crate", "stack": true},
		"barrel": {"kind": "barrel"},
	},
	# Flat on the floor: never in a spirit's way.
	"path": {
		"stones": {"kind": "path"},
		"rug": {"kind": "rug"},
		"boards": {"kind": "rug", "color": "a5845f"},
	},
	# Small things left about on a bank or the foreshore.
	"clutter": {
		"crates": {"kind": "crate"},
		"barrel": {"kind": "barrel"},
		"lobster_pot": {"kind": "lobster_pot"},
		"rock": {"kind": "rock"},
	},
	"landmark": {
		"cottage": {"kind": "cottage"},
		"tower": {"kind": "tower"},
	},
	# Hung on a room's back wall above head height.
	"wall_hanging": {
		"shelf": {"kind": "shelf", "wall": true},
		"frame": {"kind": "frame", "wall": true},
		"basket": {"kind": "basket", "wall": true},
	},
	# Not a prop: the frame of the level's pair tags (presentation/kit/pair_tags.gd
	# FRAMES). The letter and its colour are the same in every style.
	"tag": {
		"painted_tile": {"frame": "painted_tile"},
		"wooden_plaque": {"frame": "wooden_plaque"},
		"stone_tile": {"frame": "stone_tile"},
	},
	# Not a prop: how the route barriers (presentation/kit/route_barriers.gd
	# EDGE_LOOKS) edge a zone that one pip may not enter.
	"barrier": {
		"rope": {"edge": "rope"},
		"rail": {"edge": "rail"},
	},
}

## Slots that pick a kit piece's look rather than a prop to stand: the resolved
## dressing carries the pick as a field of the same name ("tag": "stone_tile").
const LOOK_SLOTS := ["tag", "barrier"]

## The pick for a slot that neither the theme nor the level names.
const DEFAULT_PICKS := {
	"lamp": "lantern", "tree": "orchard", "shrub": "flowering", "trim": "flowers", "scatter": "tufts",
	"bank": "meadow", "fence": "hedge", "railing": "picket", "bench": "bench", "path": "stones",
	"clutter": "crates", "landmark": "cottage", "wall_hanging": "shelf", "tag": "painted_tile", "barrier": "rope",
}

## Kinds drawn along "from" to "to" by themselves; any other kind given a line
## repeats along it as a row.
const LINE_KINDS := ["fence", "hedge", "wall", "stone_wall"]
## The fields of a row itself; every other field of a slot line belongs to each prop in it.
const ROW_FIELDS := ["from", "to", "count", "surface", "y", "vary"]
## Style fields read only when a style is laid along a line: "row_every" N
## lays a line's count divided by N (rounded up, at least its two ends),
## spread evenly from end to end.
const LINE_FIELDS := ["row_every"]

static func has_style(slot: String, style: String) -> bool:
	return SLOTS.has(slot) and SLOTS[slot].has(style)

static func style(slot: String, name: String) -> Dictionary:
	return SLOTS.get(slot, {}).get(name, {})
