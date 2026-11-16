extends RefCounted
## Every chapter's stages as one floor plan: the floors, the crossings between
## them and what opens each, the spots a pip works or stands on, and where the
## pips walk. One function per family (services/chapter_families.gd "layout",
## a script with `static func plan(level, stage_id) -> Dictionary`) turns that
## family's definition into this shape, so the level tools (the map, the
## checker, the preview, the dressing lint) and scenery that places itself
## read every family alike. Read only: a plan is built fresh from the
## definition and never reaches a simulation, a recording or a save.
##
## A plan (centimetres, x across and z down the map):
##   "stage_id", "first_player_slot"
##   "islands":  floors [{id, rect_cm, height_cm}]
##   "bridges":  flat crossings [{id, rect_cm, height_cm, from_surface,
##               to_surface, owner_slot?}]
##   "stairs":   sloped crossings [{id, rect_cm, axis ("x"/"z"),
##               from_height_cm, to_height_cm, from_surface, to_surface,
##               owner_slot?}]
##   "gates":    what opens a crossing this stage [{route_id, pad_id?,
##               lever_id?, ...}] (a journey gate has "when"); a gate with no
##               key holds by itself (a beam, an open lift); a crossing with no
##               gate opens only when an earlier stage kept it
##   "controls", "levers", "pressure_pads": the spots a pip works, each with
##               position_cm, radius_cm, surface_id and its owner_slot (the pip
##               the engine lets work it; none on open controls); "live":
##               false on a spot that does nothing this stage (a Relay plate
##               another stage names), left out otherwise
##   "goal" {id, position_cm, radius_cm, surface_id} and "goal_policy" {kind}
##   "starts":   {slot: [x, z] or {position_cm, surface_id, height_cm}}
## A family keeps its other fields (drops, obstacles, access_zones, sockets,
## props, optics, a seed landing); spots() finds every placed thing in them.
## A journey plan on rules 16 also carries the level's "items" and
## "item_spots" (kind "item_spots" in spots()), the stage's "item_starts" and
## "current_legs", and "hands" on a crossing that needs both hands
## (core/physical/carried_items.gd); the level graph and the map read them.
const Index = preload("res://content/chapters/index.gd")
const Families = preload("res://services/chapter_families.gd")
const Registry = preload("res://services/chapter_registry.gd")
## A spot with no radius of its own is this wide (cm).
const SPOT_RADIUS_CM := 30

## The plan of `stage_id` of a registered chapter (its own definition unless
## `level` is given, as a tool does for an edited layout); {} if unknown.
static func for_key(key: String, stage_id: String, level: Dictionary = {}) -> Dictionary:
	return plan(family_of(key), Registry.definition(key) if level.is_empty() else level, stage_id)

## The plan of `stage_id` of `level`, a definition of `family`; {} if unknown.
static func plan(family: String, level: Dictionary, stage_id: String) -> Dictionary:
	var script := str(Families.row(family).get("layout", ""))
	if script.is_empty() or not stage_id in stage_ids(level): return {}
	return load(script).plan(level, stage_id)

## Whether `family` describes its stages as plans.
static func has_layout(family: String) -> bool:
	return not str(Families.row(family).get("layout", "")).is_empty()

static func family_of(key: String) -> String:
	return str(Index.data(key).get("family", ""))

## The stage ids of `level`, in play order.
static func stage_ids(level: Dictionary) -> Array:
	return level.get("stages", []).map(func(stage: Dictionary) -> String: return str(stage.id))

## Where pips walk: every floor and crossing of `plan` as {id, kind ("island",
## "bridge" or "stair"), rect_cm, height_cm (the lowest), rise_cm}. A stair
## spans its whole rise.
static func walking_areas(plan: Dictionary) -> Array:
	var areas: Array = []
	for island: Dictionary in plan.get("islands", []):
		areas.append({"id": str(island.id), "kind": "island", "rect_cm": island.rect_cm, "height_cm": int(island.get("height_cm", 0)), "rise_cm": 0})
	for bridge: Dictionary in plan.get("bridges", []):
		areas.append({"id": str(bridge.id), "kind": "bridge", "rect_cm": bridge.rect_cm, "height_cm": int(bridge.get("height_cm", 0)), "rise_cm": 0})
	for stair: Dictionary in plan.get("stairs", []):
		areas.append({"id": str(stair.id), "kind": "stair", "rect_cm": stair.rect_cm, "height_cm": mini(int(stair.from_height_cm), int(stair.to_height_cm)), "rise_cm": absi(int(stair.to_height_cm) - int(stair.from_height_cm))})
	return areas

## Every placed thing of `plan` a pip works, carries or stands at: each entry
## anywhere in it with a position_cm, as {id, kind (the list or field it
## sits in), position_cm, radius_cm, surface_id, height_cm (its own when it
## has one, as a raised pad does, else its floor's), solid (it gives a solid
## footprint, core/solid_footprint.gd)}, then each start (kind "start").
## Floors and crossings are walking_areas().
static func spots(plan: Dictionary) -> Array:
	var heights: Dictionary = {}
	for island: Dictionary in plan.get("islands", []): heights[str(island.id)] = int(island.get("height_cm", 0))
	var found: Array = []
	_collect(plan, heights, found, "")
	var starts: Variant = plan.get("starts", {})
	if starts is Dictionary:
		for slot: String in starts:
			var start: Variant = starts[slot]
			var surface := str(start.get("surface_id", "")) if start is Dictionary else ""
			found.append({"id": slot, "kind": "start", "position_cm": start.position_cm if start is Dictionary else start, "radius_cm": SPOT_RADIUS_CM, "surface_id": surface, "height_cm": int(heights.get(surface, 0)), "solid": false})
	return found

static func _collect(value: Variant, heights: Dictionary, found: Array, kind: String) -> void:
	if value is Dictionary:
		if value.get("position_cm") is Array and value.position_cm.size() == 2:
			var surface := str(value.get("surface_id", ""))
			found.append({"id": str(value.get("id", "")), "kind": kind, "position_cm": value.position_cm, "radius_cm": int(value.get("radius_cm", SPOT_RADIUS_CM)), "surface_id": surface, "height_cm": int(value.get("height_cm", heights.get(surface, 0))), "solid": value.has("solid")})
		for child: Variant in value:
			if str(child) != "starts": _collect(value[child], heights, found, str(child))
	elif value is Array:
		for item: Variant in value: _collect(item, heights, found, kind)

# --- For the family scripts -------------------------------------------------------

## The first floor of `islands` whose rect holds `at` ([x, z] cm), "" if none.
static func surface_under(islands: Array, at: Array) -> String:
	for island: Dictionary in islands:
		var r: Array = island.rect_cm
		if int(at[0]) >= int(r[0]) and int(at[0]) <= int(r[2]) and int(at[1]) >= int(r[1]) and int(at[1]) <= int(r[3]): return str(island.id)
	return ""

## `entity` with its floor named (the island under it when it names none) and
## `owner` as its owner_slot when given.
static func placed(entity: Dictionary, islands: Array, owner: String = "") -> Dictionary:
	var result := entity.duplicate(true)
	if not result.has("surface_id"): result["surface_id"] = surface_under(islands, result.position_cm)
	if not owner.is_empty(): result["owner_slot"] = owner
	return result

## Starts as {slot: {position_cm, surface_id, height_cm}} on `islands`.
static func starts_on(starts: Dictionary, islands: Array) -> Dictionary:
	var result: Dictionary = {}
	for slot: String in starts:
		var at: Array = starts[slot]
		var surface := surface_under(islands, at)
		var height := 0
		for island: Dictionary in islands:
			if str(island.id) == surface: height = int(island.get("height_cm", 0))
		result[slot] = {"position_cm": at.duplicate(), "surface_id": surface, "height_cm": height}
	return result

## The pip who plays second on `stage`: who rings or plants at its goal.
static func second_slot(stage: Dictionary) -> String:
	return "p1" if str(stage.get("first_player_slot", "p0")) == "p0" else "p0"
