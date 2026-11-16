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
## near an entity. No published definition has the field. First Steps @2 and
## Relay Isles @3 are its first users (agent-docs ADDING-A-CHAPTER.md, notes
## for planned versions). The dressing lint stops judging a solid entity's
## spot as one a pip stands inside (presentation/kit/prop_rules.gd).

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

## True when a pip of `body_cm` radius centred at `at` may take or place at
## `entity`: within reach_cm of a solid footprint's edge, else inside the
## spot's radius_cm.
static func within_reach(entity: Dictionary, at: Vector2i, body_cm: int) -> bool:
	var solid := of(entity)
	var reach := int(entity.radius_cm) if solid.is_empty() else int(solid.radius_cm) + body_cm + int(solid.get("reach_cm", 0))
	return _centre(entity).distance_squared_to(at) <= reach * reach

static func _centre(entity: Dictionary) -> Vector2i:
	return Vector2i(int(entity.position_cm[0]), int(entity.position_cm[1]))
