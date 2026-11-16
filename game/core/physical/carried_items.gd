extends RefCounted
## Carried items and currents, two generic journey pieces under rules 16
## (open_controls.gd PIECES_RULES_VERSION: the tide rules with open controls
## and open turns, 15, plus the new pieces). They play only where a definition
## declares them, so a rules 16 level without items plays exactly as before.
##
## The definition (all optional):
##   "items": [{"id", "at", "carry"}]: things a pip can carry ("carry" true,
##       the default: the pipsport) or that only float ("carry": false: a
##       raft). "at" is where it starts: an item spot id, or "p0"/"p1" on that
##       pip's back. Looks come from the "carried_item" piece slot.
##   "item_spots": [{"id", "surface_id", "position_cm", "height_cm",
##       "radius_cm"?}]: named places an item rests (a post box, a stamp desk,
##       a hook) or floats ("surface_id": "": out on the water, out of reach).
##   a bridge or stair with "hands": true (a ladder, a rope bridge): it needs
##       both hands, so a pip carrying an item never steps onto it.
## Each stage (optional):
##   "item_starts": {item id: spot id or "p0"/"p1"}: where the item is when the
##       stage starts; otherwise where the stage before left it.
##   "current_legs": [{"from", "to", "control_id", "value", "when"?, "stop"?}]:
##       the current. An item resting at spot `from` moves to spot `to` on any
##       tick its control shows `value`, `when` holds and `stop` does not (both
##       Seven.predicate trees: a held water-gate board stops it, and it drifts
##       on once the board is let go or a gate the leg needs opens). Then it
##       takes no other leg on that same value until the wheel turns or a pip
##       handles it: one leg per turn of the wheel, never two legs a tick.
##       So an item put on a lift's hook with its wheel right goes up at once,
##       and one resting at a leg's start with the wheel already right drifts
##       on the stage's first tick (as the design solver's start settle does).
##
## The state: mechanisms.items {id: {"holder", "spot", "x", "z", "height",
## "surface_id"}}, in the checkpoint like controls, so it rides into the next
## stage. Held: holder "p0"/"p1", the rest empty. Resting: holder "", at a spot
## (spot id and its place) or loose on an island where it was put down (spot "").
##
## Playing (core/journey/simulation.gd): one action button, as for levers
## ("Pick up", "Put down", "Hand over"), after controls and levers. A pip
## holds one item. Pick up within PICK_REACH_CM on the item's floor and
## height. Put down only on an island (snapped to an item spot it stands in).
## Hand over to the other pip, live or the memory, when they meet: on one
## floor within HAND_REACH_CM, or at the two ends of a "hands" crossing (hand
## it up the ladder). A pip on a "hands" crossing takes nothing.
## The memory: its own turn's take, put and give replay on the ticks it did
## them, against the live state, the memory's going first on a shared tick, as
## its control presses do. A take finds nothing if the live pip took the item
## first ("the replay sees it gone"); a give out of reach puts the item down
## at the memory's feet; a memory that steps onto a "hands" crossing loaded
## (it was handed something it never had) puts it down where it last stood.
## Limits: a raft opens crossings through gates ({"item_id", "spot_id"});
## carrying a pip with it is a platform's job (pieces_rules.gd), not the
## current's.
##
## Predicate terms (Seven.predicate, the level graph, the server's
## protocol-items.ts): {"item_id", "carried": true} while a pip holds it;
## {"item_id", "spot_id"} while it rests at that spot.
## Pure static code shared by the engine, the catalogs, the level tools and
## the server's mirror; it preloads only open_controls.gd.
const OpenControls = preload("res://core/physical/open_controls.gd")
const RULES := [OpenControls.PIECES_RULES_VERSION]
## How near a pip's centre must be to an item to pick it up (cm).
const PICK_REACH_CM := 40
## How near two pips' centres must be to hand an item over on one floor, and
## how near each must stand to its end of a "hands" crossing (cm).
const HAND_REACH_CM := 56
## A spot's radius when it gives none (cm).
const SPOT_RADIUS_CM := 30
## Heights within this many cm count as level (stair ends, pip heights).
const LEVEL_CM := 2
const ACTS := ["take", "put", "give"]
const LABELS := {"take": "Pick up", "put": "Put down", "give": "Hand over"}
const STATE_KEYS := ["holder", "spot", "x", "z", "height", "surface_id"]

## Whether rules `version` play carried items and currents.
static func on(version: int) -> bool:
	return version in RULES

## Whether `level` declares any item (and so keeps mechanisms.items).
static func declared(level: Dictionary) -> bool:
	return not level.get("items", []).is_empty()

## The item state on `slot`'s back.
static func held(slot: String) -> Dictionary:
	return {"holder": slot, "spot": "", "x": 0, "z": 0, "height": 0, "surface_id": ""}

## The item state resting at item spot `spot`.
static func at_spot(spot: Dictionary) -> Dictionary:
	return {"holder": "", "spot": str(spot.id), "x": int(spot.position_cm[0]), "z": int(spot.position_cm[1]), "height": int(spot.get("height_cm", 0)), "surface_id": str(spot.get("surface_id", ""))}

## The state of an item placed at `place`: a slot, or an item spot id ({} if neither).
static func placed(level: Dictionary, place: String) -> Dictionary:
	if place in ["p0", "p1"]: return held(place)
	var found := spot(level, place)
	return {} if found.is_empty() else at_spot(found)

## mechanisms.items for `level` as it starts: each item at its "at".
static func initial(level: Dictionary) -> Dictionary:
	var items: Dictionary = {}
	for item: Dictionary in level.get("items", []): items[str(item.id)] = placed(level, str(item.get("at", "")))
	return items

static func spot(level: Dictionary, id: String) -> Dictionary:
	for found: Dictionary in level.get("item_spots", []):
		if str(found.id) == id: return found
	return {}

static func item(level: Dictionary, id: String) -> Dictionary:
	for found: Dictionary in level.get("items", []):
		if str(found.id) == id: return found
	return {}

## Whether `item` (a definition entry) can be carried at all.
static func carriable(item: Dictionary) -> bool:
	return bool(item.get("carry", true))

## Whether `value` is an item term.
static func is_term(value: Dictionary) -> bool:
	return value.has("item_id")

## An item term on `mechanisms` (see the header).
static func holds(value: Dictionary, mechanisms: Dictionary) -> bool:
	var state: Variant = mechanisms.get("items", {}).get(str(value.item_id))
	if not state is Dictionary: return false
	if value.has("carried"): return (not str(state.holder).is_empty()) == bool(value.carried)
	if value.has("spot_id"): return str(state.holder).is_empty() and str(state.spot) == str(value.spot_id)
	return false

## The item `slot` holds, or "".
static func held_by(items: Dictionary, slot: String) -> String:
	var ids := items.keys()
	ids.sort()
	for id: Variant in ids:
		if str(items[id].holder) == slot: return str(id)
	return ""

## The ids of `level`'s crossings that need both hands.
static func hands_routes(level: Dictionary) -> Dictionary:
	var found: Dictionary = {}
	for route: Dictionary in level.get("bridges", []) + level.get("stairs", []):
		if bool(route.get("hands", false)): found[str(route.id)] = true
	return found

## A crossing's two ends as [{"x", "z", "height"}]: a stair's foot and head
## along its axis, a bridge's ends along its longer side.
static func route_ends(route: Dictionary) -> Array:
	var rect: Array = route.rect_cm
	var axis := 0 if str(route.get("axis", "x" if int(rect[2]) - int(rect[0]) >= int(rect[3]) - int(rect[1]) else "z")) == "x" else 1
	var across := (int(rect[1 - axis]) + int(rect[3 - axis])) / 2
	var low := int(route.get("from_height_cm", route.get("height_cm", 0)))
	var high := int(route.get("to_height_cm", route.get("height_cm", 0)))
	var ends: Array = []
	for at: Array in [[int(rect[axis]), low], [int(rect[axis + 2]), high]]:
		var point := Vector2i.ZERO
		point[axis] = int(at[0])
		point[1 - axis] = across
		ends.append({"x": point.x, "z": point.y, "height": int(at[1])})
	return ends

## Whether `player` stands within `reach` of `point` ({x, z, height}) at its height.
static func _by(player: Dictionary, point: Dictionary, reach: int) -> bool:
	return absi(int(player.height) - int(point.height)) <= LEVEL_CM and Vector2i(int(player.x), int(player.z)).distance_squared_to(Vector2i(int(point.x), int(point.z))) <= reach * reach

## Whether `player` can pick up an item resting as `state`: on its floor, at its height, within reach.
static func can_pick(player: Dictionary, state: Dictionary) -> bool:
	return str(state.holder).is_empty() and not str(state.surface_id).is_empty() and str(player.surface_id) == str(state.surface_id) and _by(player, state, PICK_REACH_CM)

## Whether `giver` can hand an item to `taker`: on one floor within reach, or
## at the two ends of one "hands" crossing, neither standing on it.
static func can_hand(level: Dictionary, hands: Dictionary, giver: Dictionary, taker: Dictionary) -> bool:
	if hands.has(str(giver.surface_id)) or hands.has(str(taker.surface_id)): return false
	if str(giver.surface_id) == str(taker.surface_id) and _by(giver, taker, HAND_REACH_CM): return true
	for route: Dictionary in level.get("bridges", []) + level.get("stairs", []):
		if not hands.has(str(route.id)): continue
		var ends := route_ends(route)
		if (_by(giver, ends[0], HAND_REACH_CM) and _by(taker, ends[1], HAND_REACH_CM)) or (_by(giver, ends[1], HAND_REACH_CM) and _by(taker, ends[0], HAND_REACH_CM)): return true
	return false

## Where an item put down by `player` rests: snapped to an item spot on its
## floor it stands in, else at its feet; {} off an island (a crossing).
static func lay(level: Dictionary, player: Dictionary) -> Dictionary:
	var surface := str(player.surface_id)
	if not level.get("islands", []).any(func(island: Dictionary) -> bool: return str(island.id) == surface): return {}
	for found: Dictionary in level.get("item_spots", []):
		if str(found.get("surface_id", "")) == surface and _by(player, {"x": found.position_cm[0], "z": found.position_cm[1], "height": found.get("height_cm", 0)}, int(found.get("radius_cm", SPOT_RADIUS_CM))): return at_spot(found)
	return {"holder": "", "spot": "", "x": int(player.x), "z": int(player.z), "height": int(player.height), "surface_id": surface}

## What in `level` needs these pieces. [] when none.
static func uses(level: Dictionary) -> Array:
	var found: Array = []
	if declared(level): found.append("items")
	if not hands_routes(level).is_empty(): found.append("hands crossings")
	for stage: Dictionary in level.get("stages", []):
		if not stage.get("current_legs", []).is_empty(): found.append("current on %s" % stage.id)
		if not stage.get("item_starts", {}).is_empty(): found.append("item starts on %s" % stage.id)
	return found

## Shapes the engine relies on. [] when sound.
static func problems(level: Dictionary) -> Array:
	var found: Array = []
	if not uses(level).is_empty() and not on(int(level.get("simulation_version", 0))):
		found.append("items, currents and hands crossings need rules %d" % OpenControls.PIECES_RULES_VERSION)
	var islands: Dictionary = {}
	for island: Dictionary in level.get("islands", []): islands[str(island.id)] = island
	var spots: Dictionary = {}
	for place: Variant in level.get("item_spots", []):
		if not place is Dictionary or not place.has("id") or not place.get("position_cm") is Array or place.position_cm.size() != 2:
			found.append("an item spot needs an id and a position_cm")
			continue
		var surface := str(place.get("surface_id", ""))
		if spots.has(str(place.id)) or str(place.id) in ["p0", "p1"]: found.append("item spot %s is named twice or as a pip" % place.id)
		if not surface.is_empty() and not islands.has(surface): found.append("item spot %s stands on %s, which is not an island" % [place.id, surface])
		spots[str(place.id)] = place
	var ids: Dictionary = {}
	for entry: Variant in level.get("items", []):
		if not entry is Dictionary or not entry.has("id"):
			found.append("an item needs an id")
			continue
		if ids.has(str(entry.id)): found.append("item %s is listed twice" % entry.id)
		ids[str(entry.id)] = entry
		var at := str(entry.get("at", ""))
		if not spots.has(at) and not (at in ["p0", "p1"] and carriable(entry)): found.append("item %s starts at %s, no item spot%s" % [entry.id, at, "" if carriable(entry) else " (a float never rides a pip)"])
	var held_at_start: Dictionary = {}
	for entry: Dictionary in ids.values():
		if str(entry.get("at", "")) in ["p0", "p1"]:
			if held_at_start.has(entry.at): found.append("%s starts holding two items" % entry.at)
			held_at_start[entry.at] = true
	for stage: Dictionary in level.get("stages", []):
		var controls: Dictionary = {}
		for control: Dictionary in stage.get("controls", []): controls[str(control.id)] = control
		var starts: Variant = stage.get("item_starts", {})
		if not starts is Dictionary: found.append("%s: item_starts must map item ids to places" % stage.id)
		else:
			for id: Variant in starts:
				if not ids.has(str(id)) or placed(level, str(starts[id])).is_empty(): found.append("%s: item_starts puts %s at %s" % [stage.id, id, starts[id]])
		for leg: Variant in stage.get("current_legs", []):
			if not leg is Dictionary:
				found.append("%s: a current leg must be a dictionary" % stage.id)
				continue
			if not spots.has(str(leg.get("from", ""))) or not spots.has(str(leg.get("to", ""))) or str(leg.get("from", "")) == str(leg.get("to", "")): found.append("%s: a current leg runs from %s to %s, two different item spots" % [stage.id, leg.get("from", ""), leg.get("to", "")])
			var control: Dictionary = controls.get(str(leg.get("control_id", "")), {})
			if control.is_empty() or str(leg.get("value", "")) not in control.get("values", []).map(func(v: Variant) -> String: return str(v)): found.append("%s: a current leg from %s turns on %s=%s, which no selector of the stage shows" % [stage.id, leg.get("from", ""), leg.get("control_id", ""), leg.get("value", "")])
			for key: String in ["when", "stop"]:
				if leg.has(key) and not leg[key] is Dictionary: found.append("%s: a current leg's %s must be a predicate" % [stage.id, key])
	return found
