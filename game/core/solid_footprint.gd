extends RefCounted
## A solid prop pips walk around instead of into, for the levels that opt in.
## An entity with a spot (a socket, a pedestal, a nest) opts in by giving
## "solid": {"radius_cm": r, "reach_cm": d}. A pip's centre is then kept out
## of the circle r plus its own body radius, and it takes or places there from
## anywhere within d of that edge, the spot's radius_cm no longer counting.
## An entity without the field is the plain spot it always was: a pip stands
## inside radius_cm. Integer cm only, so recordings replay exactly.
##
## An engine opts in by calling blocked() from its walkable_at() with the
## level's entities, and within_reach() wherever it now asks whether a pip is
## near an entity. First Steps @2's pedestal was its first user. The dressing
## lint stops judging a solid entity's spot as one a pip stands inside
## (presentation/kit/prop_rules.gd).
##
## Hand controls (owner, 2026-11-20, every level and version): each stage's
## levers and controls (switches, selectors, mirrors: what a pip works by
## hand) are solid by with_hands(), the one rule the chapter catalogs apply,
## so a pip stands beside one, never inside it, and its pull shows. HAND is
## their one size: the kept-out circle (radius_cm plus the pip's body, 32 cm)
## clears every lever and selector style, which all stand inside 28 cm
## (presentation/kit/pieces/lever.gd REACH), and a pip works it from that
## circle out to reach_cm further (52 cm from its centre). A control whose own
## floor has no room for that (fits(): a catwalk the pip stands on) keeps its
## plain spot. Pads, ball pads and goals stay spots a pip stands on. Sleeping
## Lighthouse @2's mirrors and selector take the same rule inside each stage's
## embedded native stage (core/lighthouse/borrowed_light.gd plays them); solo
## @1 keeps its plain catalog.

## A pip's body radius (core/physical/runtime.gd PLAYER_RADIUS).
const BODY_CM := 12
const HAND := {"radius_cm": 20, "reach_cm": 20}
## The narrowest way past a footprint fits() leaves open (two steps, cm).
const GAP_CM := 16
## The stage lists whose entries a pip works by hand.
const HAND_LISTS := ["levers", "controls"]

## The entity's solid footprint, or {} when it has none.
static func of(entity: Dictionary) -> Dictionary:
	var solid: Variant = entity.get("solid", {})
	return solid if solid is Dictionary and solid.has("radius_cm") else {}

## True when a pip of `body_cm` radius centred at `at` would stand in any of
## `entities`' solid footprints.
static func blocked(entities: Array, at: Vector2i, body_cm: int) -> bool:
	for entity: Dictionary in entities:
		var solid := of(entity)
		if solid.is_empty(): continue
		var keep := int(solid.radius_cm) + body_cm
		if _centre(entity).distance_squared_to(at) < keep * keep: return true
	return false

## True when a step from `from` to `to` ends in one of `entities`' footprints
## without leaving it: a pip already inside one (a checkpoint or a ride left
## it there) may always step further out, never further in.
static func blocks_step(entities: Array, from: Vector2i, to: Vector2i, body_cm: int) -> bool:
	for entity: Dictionary in entities:
		var solid := of(entity)
		if solid.is_empty(): continue
		var keep := int(solid.radius_cm) + body_cm
		var centre := _centre(entity)
		var after := centre.distance_squared_to(to)
		if after < keep * keep and after <= centre.distance_squared_to(from): return true
	return false

## True when a pip of `body_cm` radius centred at `at` may take or place at
## `entity`: within reach_cm of a solid footprint's edge, else inside the
## spot's radius_cm.
static func within_reach(entity: Dictionary, at: Vector2i, body_cm: int) -> bool:
	var solid := of(entity)
	var reach := int(entity.radius_cm) if solid.is_empty() else int(solid.radius_cm) + body_cm + int(solid.get("reach_cm", 0))
	return _centre(entity).distance_squared_to(at) <= reach * reach

static func _centre(entity: Dictionary) -> Vector2i:
	return Vector2i(int(entity.position_cm[0]), int(entity.position_cm[1]))

## Those of `entities` that have a solid footprint.
static func solids(entities: Array) -> Array:
	return entities.filter(func(entity: Variant) -> bool: return entity is Dictionary and not of(entity).is_empty())

## `level` with every hand control that fits on its floor made solid (HAND).
## Changes and returns `level`. A hand control's "solid" is this rule's
## alone: it is worked out again each time, so a catalog built on another's
## definition gets the answer for its own floors.
static func with_hands(level: Dictionary) -> Dictionary:
	var floors := _floors(level)
	for stage: Variant in level.get("stages", []):
		if not stage is Dictionary: continue
		# A Lighthouse stage (core/lighthouse/room_catalog.gd) embeds its own
		# stage: its own floors, its mirrors and selectors, Borrowed Light's
		# one mirror_control, each on the island it stands in.
		var native: Variant = stage.get("native")
		if native is Dictionary:
			var own := _floors(native)
			var hands: Array = native.get("controls", []) + ([native.mirror_control] if native.get("mirror_control") is Dictionary else [])
			for control: Variant in hands:
				if control is Dictionary and control.get("position_cm") is Array: _hand(control, _floor_under(own, control))
			continue
		for list: String in HAND_LISTS:
			for control: Variant in stage.get(list, []):
				if control is Dictionary and control.get("position_cm") is Array: _hand(control, floors.get(str(control.get("surface_id", "")), {}))
	return level

## One hand control on `floor` ({} for none): solid where it fits.
static func _hand(control: Dictionary, floor: Dictionary) -> void:
	control.erase("solid")
	if not floor.is_empty() and fits(control, floor.rect_cm, HAND, BODY_CM): control["solid"] = HAND.duplicate()

## Floor id -> floor, of `level`'s islands, bridges and stairs.
static func _floors(level: Dictionary) -> Dictionary:
	var floors: Dictionary = {}
	for list: String in ["islands", "bridges", "stairs"]:
		for floor: Variant in level.get(list, []):
			if floor is Dictionary: floors[str(floor.get("id", ""))] = floor
	return floors

## The first of `floors` whose rect holds `entity`'s centre, else {}.
static func _floor_under(floors: Dictionary, entity: Dictionary) -> Dictionary:
	var at := _centre(entity)
	for floor: Dictionary in floors.values():
		var rect: Array = floor.get("rect_cm", [])
		if rect.size() == 4 and at.x >= mini(rect[0], rect[2]) and at.x <= maxi(rect[0], rect[2]) and at.y >= mini(rect[1], rect[3]) and at.y <= maxi(rect[1], rect[3]): return floor
	return {}

## Whether a footprint `solid` at `entity` leaves its floor (`rect`: [x0, z0,
## x1, z1] cm) whole for a pip of `body_cm`: where the pip's centre may stand
## (the floor less its body all round), the kept-out circle comes within
## GAP_CM of neither two opposite sides nor both sides of a corner it leaves
## out, and some spot within reach is left. Floors beside it only add room,
## so this is the cautious answer; tests/test_hand_reach.gd walks every stage
## with the engine to be sure.
static func fits(entity: Dictionary, rect: Array, solid: Dictionary, body_cm: int) -> bool:
	var at := _centre(entity)
	var x0 := mini(int(rect[0]), int(rect[2])) + body_cm
	var z0 := mini(int(rect[1]), int(rect[3])) + body_cm
	var x1 := maxi(int(rect[0]), int(rect[2])) - body_cm
	var z1 := maxi(int(rect[1]), int(rect[3])) - body_cm
	var keep := int(solid.radius_cm) + body_cm
	# A side counts as reached when less than GAP_CM is left between: a gap
	# that narrow is no way through for a player's thumb.
	var near := keep + GAP_CM
	var west := at.x - near < x0
	var east := at.x + near > x1
	var north := at.y - near < z0
	var south := at.y + near > z1
	if (west and east) or (north and south): return false
	for corner: Array in [[x0, z0, west, north], [x1, z0, east, north], [x0, z1, west, south], [x1, z1, east, south]]:
		if corner[2] and corner[3] and at.distance_squared_to(Vector2i(corner[0], corner[1])) > near * near: return false
	# Integers only, so every phone builds the same definition (its hash).
	var stand := keep + int(solid.get("reach_cm", 0)) / 2
	var slant := stand * 707 / 1000
	for offset: Vector2i in [Vector2i(stand, 0), Vector2i(-stand, 0), Vector2i(0, stand), Vector2i(0, -stand), Vector2i(slant, slant), Vector2i(-slant, slant), Vector2i(slant, -slant), Vector2i(-slant, -slant)]:
		var spot := at + offset
		if spot.x >= x0 and spot.x <= x1 and spot.y >= z0 and spot.y <= z1: return true
	return false
