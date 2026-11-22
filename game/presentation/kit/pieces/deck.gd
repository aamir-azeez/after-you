extends RefCounted
## World kit: a crossing's deck in one of the new pieces' styles
## (content/dressing/prop_styles.gd "deck"; content/dressing/piece_styles.gd
## picks which, by the crossing's id). "plank" is the world's own deck
## (lighthouse_world._lay_deck); these are laid into the same deck node, which
## the world shows while the crossing is open and hides while it is shut, so
## the open deck is the visible cause either way:
##
##   "rope": a rope bridge (rules 20's crank_bridge block). Thin slats that sag
##       a little in the middle on two foot ropes, a rope handrail each side on
##       posts at both ends. Let out (shut), it hangs slack between the posts
##       (rope_ends()), as every held crossing's deck does
##       (kit/pieces/taut_bridge.gd), and is pulled taut as it opens.
##   "falls_path": the path behind a waterfall (falls_path). Wet flagstones
##       with a mossy lip, laid while the water gate holds the falls back;
##       while the falls run, their water pours over it off a rock lip
##       (kit/pieces/falls_curtain.gd), so the closed path shows why.
##   "stones": sinking stones (sinking_stones). Round flat stones, wet at the
##       rim, laid across the gap a hop apart with water between them. Under
##       water (shut) they are gone.
## Every part stays inside the crossing's rectangle and at or under its walk,
## except the handrails, which stand on its long edges.
const Parts = preload("res://presentation/kit/pieces/parts.gd")
const STYLES := ["rope", "stones", "falls_path"]
const ROPE := Color("c9b48a")
const SLAT := Color("a98a64")
const SAG := 0.05
const RAIL_HEIGHT := 0.5
## How far past a slat's end a foot rope's middle runs (m).
const FOOT_ROPE_OUT := 0.016
## The slats span this share of the crossing's width.
const SLAT_SHARE := 0.86
const FLAG := Color("8a8f8a")
const MOSS := Color("6f8f5a")
const STONE := Color("9a9890")
const STONE_WET := Color("6f746f")
## A stone every this far (m): a hop from stone to stone, with water showing
## between them, so a row of stones reads as stones, not a strip.
const STONE_STEP := 1.6
## How far a stone reaches down from its top (m) when its world gives no
## other (a water world builds each to its bed, water_world.gd stone_drop).
const STONE_DROP := 0.53

## Lays `style` into `deck` (a crossing `width` by `depth` m, along x when
## `across_x`), over its open span `low`..`high` (deck-local m along it); a
## "stones" stone reaches `drop` down from its top.
static func lay(style: String, deck: Node3D, width: float, depth: float, across_x: bool, low: float, high: float, drop: float = STONE_DROP) -> void:
	var length := high - low
	var middle := (low + high) * 0.5
	var span := depth if across_x else width
	match style:
		"rope":
			var count := maxi(6, roundi(length / 0.12))
			for index in range(count):
				var along := low + (float(index) + 0.5) * length / float(count)
				var sag := -SAG * (1.0 - pow((along - middle) / maxf(length * 0.5, 0.01), 2.0))
				var size := Vector3(length / float(count) - 0.025, 0.035, span * SLAT_SHARE) if across_x else Vector3(span * SLAT_SHARE, 0.035, length / float(count) - 0.025)
				Parts.box(size, SLAT.darkened(0.06 * float(index % 2)), _on(across_x, along, sag - 0.02, 0.0), deck)
			# The posts stand for good (rope_ends()).
			for side: int in [-1, 1]:
				var edge := float(side) * (span * 0.5 - 0.03)
				Parts.box(_along(across_x, length, 0.025), ROPE, _on(across_x, middle, RAIL_HEIGHT - SAG, edge), deck)
				# The foot rope runs just outside the slats' ends, so no face of
				# it lies on a slat's.
				Parts.box(_along(across_x, length, 0.02), ROPE, _on(across_x, middle, -0.04 - SAG * 0.5, float(side) * (span * 0.43 + FOOT_ROPE_OUT)), deck)
		"falls_path":
			var count := maxi(2, roundi(length / 0.4))
			for index in range(count):
				var along := low + (float(index) + 0.5) * length / float(count)
				# A centimetre short of each side: the path is drawn as wide as
				# the pip reaches (kit/walk_reach.gd).
				var size := Vector3(length / float(count) - 0.03, 0.08, span - 0.02) if across_x else Vector3(span - 0.02, 0.08, length / float(count) - 0.03)
				Parts.box(size, FLAG.darkened(0.08 * float(index % 2)), _on(across_x, along, -0.04, 0.0), deck)
			Parts.box(_along(across_x, length, 0.05, 0.04), MOSS, _on(across_x, middle, -0.015, span * 0.5 - 0.025), deck)
		"stones":
			var count := maxi(1, roundi(length / STONE_STEP))
			var radius := minf(span * 0.45, length / float(count) * 0.3)
			for index in range(count):
				var along := low + (float(index) + 0.5) * length / float(count)
				Parts.disc(radius, drop - 0.03, STONE_WET, _on(across_x, along, -0.03 - (drop - 0.03) * 0.5, 0.0), deck, radius * 0.9)
				Parts.disc(radius * 0.92, 0.06, STONE, _on(across_x, along, -0.03, 0.0), deck, radius * 0.8)

## A "rope" crossing's end posts, standing open or shut, under `parent` at
## the deck's own `place`, in the deck's terms (lay()); its deck hangs slack
## between them while it is shut (kit/pieces/taut_bridge.gd).
static func rope_ends(parent: Node3D, place: Vector3, width: float, depth: float, across_x: bool, low: float, high: float) -> Node3D:
	var span := depth if across_x else width
	var ends := Node3D.new()
	ends.name = "RopeEnds"
	ends.position = place
	parent.add_child(ends)
	for side: int in [-1, 1]:
		var edge := float(side) * (span * 0.5 - 0.03)
		for end: float in [low, high]: Parts.box(Vector3(0.05, RAIL_HEIGHT + 0.1, 0.05), Parts.TIMBER_DARK, _on(across_x, end, RAIL_HEIGHT * 0.5 - 0.05, edge), ends)
	return ends

static func _on(across_x: bool, along: float, y: float, side: float) -> Vector3:
	return Vector3(along, y, side) if across_x else Vector3(side, y, along)

static func _along(across_x: bool, length: float, thick: float, tall: float = -1.0) -> Vector3:
	var height := thick if tall < 0.0 else tall
	return Vector3(length, height, thick) if across_x else Vector3(thick, height, length)
