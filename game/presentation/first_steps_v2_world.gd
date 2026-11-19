extends "res://presentation/journey_world.gd"
## first-steps@2 on the shared journey world: floors, pads, the lift (a weight
## lift, kit/new_pieces.gd in the dressing's "rope_tower" style), the goals
## and the seed (a carried item, "seed" style) are the journey world's. This
## world adds only the looks of the item spots First Steps keeps: a solid spot
## (core/solid_footprint.gd) is @1's stone pedestal, its drum exactly the solid
## circle a pip walks round, and every other spot but a throw's landing (the
## journey world rings that) the garden planter. A seed resting at either sits
## on top, where @1 showed it.
const Solid = preload("res://core/solid_footprint.gd")
## @1's pedestal (first_steps_world.gd): a stone drum, a cream cap a little
## wider and a gold ring, metres over the loft. The seed rests on the cap, 45 cm
## up (@1's seed_height_cm 205 on the 160 cm loft).
const DRUM_HEIGHT := 0.35
const CAP := Vector2(0.37, 0.10)
const PEDESTAL_TOP := 0.45
const STONE := Color("bbccb5")

func show_stage(stage: Dictionary) -> void:
	if str(stage.get("id", "")) == displayed_stage_id: return
	await super.show_stage(stage)
	var landings := _landings()
	for spot: Dictionary in chapter_definition.get("item_spots", []):
		if str(spot.id) not in landings: _build_spot(spot)

## Every throw's landing spot in the chapter: the journey world rings them on
## the stage that throws, and they are never a planter.
func _landings() -> Array:
	var found: Array = []
	for stage: Dictionary in chapter_definition.get("stages", []):
		for thrown: Dictionary in stage.get("throws", []): found.append(str(thrown.to))
	return found

## A pedestal for a solid spot, a planter for any other.
func _build_spot(spot: Dictionary) -> void:
	var root := Node3D.new()
	root.name = str(spot.id)
	root.position = _at(spot)
	terrain.add_child(root)
	var solid := Solid.of(spot)
	if solid.is_empty():
		SocketKit.garden(root, float(spot.radius_cm) / 100.0, GOLD)
		return
	cylinder(float(solid.radius_cm) / 100.0, DRUM_HEIGHT, STONE, Vector3(0, DRUM_HEIGHT * 0.5, 0), root)
	cylinder(CAP.x, CAP.y, CREAM, Vector3(0, DRUM_HEIGHT + CAP.y * 0.5 - 0.01, 0), root)
	ring(0.31, GOLD, Vector3(0, PEDESTAL_TOP + 0.005, 0), root)

## Pair tags and ownership marks keep off the dressing's stone path up to the
## lift (content/dressing/first_steps.gd), shared with @1's world: a tile at
## the lift's entrance would lie under its stone.
func _pair_keep_clear() -> Array:
	var found: Array = super._pair_keep_clear()
	for spec: Dictionary in Props.expand(DressingCatalog.stage_props(dressing, _dressing_stage_id())):
		if str(spec.get("kind", "")) == "path": found.append({"rect": Props.extent(spec).rect, "what": "the stone path"})
	return found

## An item resting at a spot sits on its pedestal or in its planter's soil.
func _item_point(state: Dictionary) -> Vector3:
	var at := super._item_point(state)
	if state.is_empty() or str(state.get("spot", "")).is_empty(): return at
	for spot: Dictionary in chapter_definition.get("item_spots", []):
		if str(spot.id) != str(state.spot): continue
		if not Solid.of(spot).is_empty(): return at + Vector3(0, PEDESTAL_TOP, 0)
		if str(spot.id) not in _landings(): return at + Vector3(0, SocketKit.PLANTER + 0.02, 0)
	return at
