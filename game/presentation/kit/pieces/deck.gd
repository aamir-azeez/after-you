extends RefCounted
## World kit: a crossing's deck in one of the new pieces' styles
## (content/dressing/prop_styles.gd "deck"; content/dressing/piece_styles.gd
## picks which, by the crossing's id). "plank" is the world's own deck
## (lighthouse_world._lay_deck); these are laid into the same deck node, which
## the world shows while the crossing is open and hides while it is shut, so
## the open deck is the visible cause either way:
##
##   "rope": a rope bridge (rules 16's crank_bridge block). Thin slats that sag
##       a little in the middle on two foot ropes, a rope handrail each side on
##       posts at both ends. Wound in (shut), nothing spans the gap.
##   "dam": a dam bridge (dam_bridge). A stone dam wall down into the water
##       under a plank walk with a coping each side: the planks are only laid
##       while the water behind stands at its level.
##   "stones": sinking stones (sinking_stones). Round flat stones, wet at the
##       rim, laid across the gap one per pip's step. Under water (shut) they
##       are gone.
## Every part stays inside the crossing's rectangle and at or under its walk,
## except the handrails, which stand on its long edges.
const Parts = preload("res://presentation/kit/pieces/parts.gd")
const STYLES := ["rope", "dam", "stones"]
const ROPE := Color("c9b48a")
const SLAT := Color("a98a64")
const SAG := 0.05
const RAIL_HEIGHT := 0.5
const DAM_STONE := Color("8f8a7e")
const DAM_DEPTH := 1.1
const STONE := Color("9a9890")
const STONE_WET := Color("6f746f")
const STONE_STEP := 0.34

## Lays `style` into `deck` (a crossing `width` by `depth` m, along x when
## `across_x`), over its open span `low`..`high` (deck-local m along it).
static func lay(style: String, deck: Node3D, width: float, depth: float, across_x: bool, low: float, high: float) -> void:
	var length := high - low
	var middle := (low + high) * 0.5
	var span := depth if across_x else width
	match style:
		"rope":
			var count := maxi(6, roundi(length / 0.12))
			for index in range(count):
				var along := low + (float(index) + 0.5) * length / float(count)
				var sag := -SAG * (1.0 - pow((along - middle) / maxf(length * 0.5, 0.01), 2.0))
				var size := Vector3(length / float(count) - 0.025, 0.035, span * 0.86) if across_x else Vector3(span * 0.86, 0.035, length / float(count) - 0.025)
				Parts.box(size, SLAT.darkened(0.06 * float(index % 2)), _on(across_x, along, sag - 0.02, 0.0), deck)
			for side: int in [-1, 1]:
				var edge := float(side) * (span * 0.5 - 0.03)
				for end: float in [low, high]: Parts.box(Vector3(0.05, RAIL_HEIGHT + 0.1, 0.05), Parts.TIMBER_DARK, _on(across_x, end, RAIL_HEIGHT * 0.5 - 0.05, edge), deck)
				Parts.box(_along(across_x, length, 0.025), ROPE, _on(across_x, middle, RAIL_HEIGHT - SAG, edge), deck)
				Parts.box(_along(across_x, length, 0.02), ROPE, _on(across_x, middle, -0.04 - SAG * 0.5, edge * 0.9), deck)
		"dam":
			Parts.box(_along(across_x, length, span, DAM_DEPTH), DAM_STONE, _on(across_x, middle, -0.08 - DAM_DEPTH * 0.5, 0.0), deck)
			for side: int in [-1, 1]: Parts.box(_along(across_x, length, 0.06, 0.06), DAM_STONE.lightened(0.12), _on(across_x, middle, -0.03, float(side) * (span * 0.5 - 0.03)), deck)
			for index in range(4):
				var along := low + (float(index) + 0.5) * length / 4.0
				var size := Vector3(length / 4.0 - 0.02, 0.05, span - 0.14) if across_x else Vector3(span - 0.14, 0.05, length / 4.0 - 0.02)
				Parts.box(size, Parts.TIMBER_LIGHT.darkened(0.05 * float(index % 2)), _on(across_x, along, -0.025, 0.0), deck)
		"stones":
			var count := maxi(1, roundi(length / STONE_STEP))
			var radius := minf(span * 0.45, length / float(count) * 0.48)
			for index in range(count):
				var along := low + (float(index) + 0.5) * length / float(count)
				Parts.disc(radius, 0.5, STONE_WET, _on(across_x, along, -0.28, 0.0), deck, radius * 0.9)
				Parts.disc(radius * 0.92, 0.06, STONE, _on(across_x, along, -0.03, 0.0), deck, radius * 0.8)

static func _on(across_x: bool, along: float, y: float, side: float) -> Vector3:
	return Vector3(along, y, side) if across_x else Vector3(side, y, along)

static func _along(across_x: bool, length: float, thick: float, tall: float = -1.0) -> Vector3:
	var height := thick if tall < 0.0 else tall
	return Vector3(length, height, thick) if across_x else Vector3(thick, height, length)
