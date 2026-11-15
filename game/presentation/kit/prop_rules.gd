extends RefCounted
## Where scenery may stand: the dressing lint's rules as shared code. The lint
## (tests/test_dressing_lint.gd), the level checker's prop overlap, the
## self-placing dressing (content/dressing/placement.gd) and the level tools'
## quick prop check all judge a prop here, so a prop the placer lays is one
## the lint passes.
##
## Metres, x across and z toward the camera. A stage view is a stage merged
## over its level (content/dressing/placement.gd stage_view()). A prop's
## footing (footing()) is its kit extent (kit/props.gd) raised onto its surface.
const Props = preload("res://presentation/kit/props.gd")
const Look = preload("res://presentation/spirit_look.gd")

## A spirit's height: a prop shares a walking space it reaches into up to this
## far above the floor.
const SPIRIT := 1.0
## About a spirit's body radius beyond the rectangle its centre walks in.
const MARGIN := 0.12
## How far a prop keeps clear of a control's, start's or drop's circle.
const CLEAR := 0.1
## The ground the camera looks across per metre of height: every chapter
## camera sits at offset (3, 13, 10).
const VIEW := Vector2(-3.0, -10.0) / 13.0
## The largest size a trim row is laid at, on a bank's front lip this high
## (metres): every trim style stays under Props.LOW there.
const TRIM_SIZE := 0.6
const TRIM_LIP := 0.06
## Two props whose footprints share more of the smaller one than this stand
## in each other.
const PROP_SHARE := 0.3
## A spot a pip stands inside to take, place or hold something (a seed
## pedestal, socket, nest or cradle, a pad or plate, a goal, a seed landing)
## is drawn so standing in it looks natural: a low step-on base with the thing
## it holds floating or on a slim stand (kit/pieces/socket.gd stand()). No body
## wider than SMALL_STAND reaches into a pip there (stands_in()): from STEP_ON
## over the spot's floor to the top of its head (STEP_HEAD; a lantern or bell
## hung above it is fine), within the spot's radius less MARGIN. STEP_ON
## clears every pad and plate rim already shipped (8 to 12 cm, the Lighthouse
## cradles' and plates' rings).
const STEP_ON := 0.15
const STEP_HEAD := Look.HEAD_CENTER.y + Look.HEAD_HALF.y
const SMALL_STAND := 0.18
## The view lists whose spots a pip stands inside.
const STAND_IN := ["sockets", "props", "plates", "plate", "pressure_pads", "ball_pads", "hold_pads", "goals", "goal", "landing"]
## Kinds whose footprint is a rectangle; every other kind is judged as a circle.
const SQUARE_KINDS := ["bench", "cottage", "rug", "path", "planter", "boat", "lobster_pot", "shelf", "frame", "fence", "hedge", "wall"]

static func rect(r: Array) -> Rect2:
	return Rect2(Vector2(float(r[0]), float(r[1])) / 100.0, Vector2(float(r[2] - r[0]), float(r[3] - r[1])) / 100.0)

## {surface id: floor height}.
static func heights(view: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for island: Dictionary in view.get("islands", []): result[str(island.id)] = float(island.get("height_cm", 0)) / 100.0
	return result

## Walking spaces: {rect, y, rise, name}. Stairs span their whole rise.
static func walkable(view: Dictionary) -> Array:
	var spaces: Array = []
	for island: Dictionary in view.get("islands", []):
		spaces.append({"rect": rect(island.rect_cm), "y": float(island.get("height_cm", 0)) / 100.0, "rise": 0.0, "name": "island " + str(island.id), "id": str(island.id)})
	for bridge: Dictionary in view.get("bridges", []):
		spaces.append({"rect": rect(bridge.rect_cm), "y": float(bridge.get("height_cm", 0)) / 100.0, "rise": 0.0, "name": "route " + str(bridge.id), "id": str(bridge.id)})
	for stair: Dictionary in view.get("stairs", []):
		var low := minf(float(stair.from_height_cm), float(stair.to_height_cm)) / 100.0
		spaces.append({"rect": rect(stair.rect_cm), "y": low, "rise": absf(float(stair.to_height_cm - stair.from_height_cm)) / 100.0, "name": "stair " + str(stair.id), "id": str(stair.id)})
	return spaces

## Interactive places: pads, levers, switches, goals, starts, drops, optics
## (anything with a position_cm), each as {rect, y, name}.
static func places(view: Dictionary, floor_heights: Dictionary) -> Array:
	var found: Array = []
	_collect(view, floor_heights, found, "")
	for drop: Dictionary in view.get("drops", []):
		found.append({"rect": rect(drop.rect_cm), "y": float(floor_heights.get(str(drop.get("surface_id", "")), 0.0)), "name": "drop " + str(drop.get("id", ""))})
	var starts: Dictionary = view.get("starts", {}) if view.get("starts") is Dictionary else {}
	for slot: String in starts:
		var start: Variant = starts[slot]
		var at: Array = start.position_cm if start is Dictionary else start
		found.append({"rect": Rect2(Vector2(float(at[0]), float(at[1])) / 100.0 - Vector2.ONE * 0.3, Vector2.ONE * 0.6), "y": float(floor_heights.get(str(start.get("surface_id", "")), 0.0)) if start is Dictionary else 0.0, "name": "start " + slot})
	return found

static func _collect(value: Variant, floor_heights: Dictionary, found: Array, path: String) -> void:
	if value is Dictionary:
		if value.has("position_cm") and value.position_cm is Array and value.position_cm.size() == 2:
			var radius := float(value.get("radius_cm", 30)) / 100.0
			var at := Vector2(float(value.position_cm[0]), float(value.position_cm[1])) / 100.0
			found.append({"rect": Rect2(at - Vector2.ONE * radius, Vector2.ONE * radius * 2.0), "y": float(floor_heights.get(str(value.get("surface_id", "")), 0.0)), "name": "%s %s" % [path, value.get("id", "")]})
		for child: Variant in value:
			if str(child) != "starts": _collect(value[child], floor_heights, found, str(child))
	elif value is Array:
		for item: Variant in value: _collect(item, floor_heights, found, path)

## Everything a stage's props are judged against, worked out once per stage.
static func scene(view: Dictionary) -> Dictionary:
	var floor_heights := heights(view)
	return {"heights": floor_heights, "spaces": walkable(view), "places": places(view, floor_heights)}

## Where a prop stands: {rect (footprint), inner, base, top, ground (its
## surface's height), flat, wall}.
static func footing(spec: Dictionary, floor_heights: Dictionary) -> Dictionary:
	var extent := Props.extent(spec)
	var ground := float(floor_heights.get(str(spec.get("surface", "")), 0.0))
	var base := ground + float(extent.base)
	var footprint: Rect2 = extent.rect
	return {"rect": footprint, "inner": footprint.grow(-0.01), "base": base, "top": base + float(extent.height), "ground": ground, "flat": bool(extent.flat), "wall": bool(extent.get("wall", false))}

## The prop stands in a walking space it shares (flat props never do; a
## wall-hung prop over its own room's back wall does not).
static func on_walkable(foot: Dictionary, space: Dictionary) -> bool:
	if bool(foot.flat): return false
	if bool(foot.wall) and on_back_wall(foot.rect, float(foot.base), space): return false
	var shares := float(foot.top) > float(space.y) + 0.02 and float(foot.base) < float(space.y) + float(space.rise) + SPIRIT
	return shares and (foot.inner as Rect2).intersects(space.rect)

## The prop stands over a control, start or drop.
static func covers(foot: Dictionary, place: Dictionary) -> bool:
	return float(foot.top) > float(place.y) and float(foot.base) < float(place.y) + SPIRIT and (foot.inner as Rect2).intersects((place.rect as Rect2).grow(CLEAR))

## Low enough (or flat) never to hide anything from the camera.
static func low(foot: Dictionary) -> bool:
	return float(foot.top) - float(foot.ground) <= Props.LOW or bool(foot.flat)

## The prop hides `target` (a walking space or a place) from the camera.
static func hides_target(foot: Dictionary, target: Dictionary) -> bool:
	# A wall-hung prop sits above head height against its own room's back wall.
	if bool(foot.wall) and on_back_wall(foot.rect, float(foot.base), target): return false
	return hides(foot.rect, float(foot.base), float(foot.top), target)

static func on_back_wall(footprint: Rect2, base: float, target: Dictionary) -> bool:
	var area: Rect2 = target.rect
	return base >= float(target.y) + 1.1 and footprint.position.x >= area.position.x - 0.05 and footprint.end.x <= area.end.x + 0.05 and footprint.position.y <= area.position.y + 0.25

## The prop's view shadow at the target's height overlaps the target: a prop
## of height h at base b hides ground at y0 behind it, swept along VIEW per
## metre of height between b - y0 - spirit and b + h - y0.
static func hides(footprint: Rect2, base: float, top: float, target: Dictionary) -> bool:
	var y0 := float(target.y)
	var near := maxf(0.0, base - y0 - SPIRIT - float(target.get("rise", 0.0)))
	var far := top - y0
	if far <= 0.0: return false
	var goal: Rect2 = (target.rect as Rect2).grow(MARGIN)
	var step := near
	while step <= far + 0.001:
		if Rect2(footprint.position + VIEW * step, footprint.size).grow(-0.01).intersects(goal): return true
		step += 0.05
	return false

## Every rule the prop breaks on this stage, as {rule, target}: "walkable",
## "covers" or "hides" ({} rules: it may stand there).
static func faults(spec: Dictionary, stage: Dictionary) -> Array:
	var found: Array = []
	var foot := footing(spec, stage.heights)
	for space: Dictionary in stage.spaces:
		if on_walkable(foot, space): found.append({"rule": "walkable", "target": space.name})
	for place: Dictionary in stage.places:
		if covers(foot, place): found.append({"rule": "covers", "target": place.name})
	if low(foot): return found
	for target: Dictionary in stage.spaces + stage.places:
		if hides_target(foot, target):
			found.append({"rule": "hides", "target": target.name})
			break
	return found

## A prop as the overlap rule sees it ({} for one nothing stands in: flat
## props and banks): {rect, round, low, high}.
static func solid(spec: Dictionary, floor_heights: Dictionary) -> Dictionary:
	var extent := Props.extent(spec)
	if bool(extent.flat) or str(spec.get("kind", "")) == "bank": return {}
	var base := float(floor_heights.get(str(spec.get("surface", "")), 0.0)) + float(extent.base)
	return {"rect": extent.rect, "round": str(spec.get("kind", "")) not in SQUARE_KINDS, "low": base, "high": base + float(extent.height)}

## Two solid props stand in each other.
static func clash(one: Dictionary, two: Dictionary) -> bool:
	if one.is_empty() or two.is_empty(): return false
	if float(one.high) <= float(two.low) + 0.01 or float(two.high) <= float(one.low) + 0.01: return false
	return share(one, two) > PROP_SHARE

## How much of the smaller footprint the two share, from 0 to 1 (a circle is
## sampled on a 9 by 9 grid over its square).
static func share(one: Dictionary, two: Dictionary) -> float:
	var small: Dictionary = one if _area(one) <= _area(two) else two
	var large: Dictionary = two if small == one else one
	if not (small.rect as Rect2).intersects(large.rect): return 0.0
	var inside := 0
	var total := 0
	var area: Rect2 = small.rect
	for i in range(9):
		for j in range(9):
			var point := area.position + area.size * Vector2((float(i) + 0.5) / 9.0, (float(j) + 0.5) / 9.0)
			if not _covers_point(small, point): continue
			total += 1
			if _covers_point(large, point): inside += 1
	return float(inside) / float(maxi(total, 1))

static func _covers_point(item: Dictionary, point: Vector2) -> bool:
	var area: Rect2 = item.rect
	if not item.round: return area.has_point(point)
	return point.distance_to(area.get_center()) <= area.size.x * 0.5

static func _area(item: Dictionary) -> float:
	var area: Rect2 = item.rect
	return area.get_area() * (PI / 4.0 if item.round else 1.0)

## The spots a pip stands inside (STAND_IN lists): {at, radius, y (the spot's
## own height_cm, else its surface's), kind, id}. A solid entity (core/
## solid_footprint.gd) is reached from beside, never stood in, so it is left out.
static func stand_spots(view: Dictionary) -> Array:
	var found: Array = []
	_stand_spots(view, heights(view), found, "")
	return found

static func _stand_spots(value: Variant, floor_heights: Dictionary, found: Array, path: String) -> void:
	if value is Dictionary:
		if path in STAND_IN and not value.has("solid") and value.has("position_cm") and value.position_cm is Array and value.position_cm.size() == 2:
			var y := float(value.height_cm) / 100.0 if value.has("height_cm") else float(floor_heights.get(str(value.get("surface_id", "")), 0.0))
			found.append({"at": Vector2(float(value.position_cm[0]), float(value.position_cm[1])) / 100.0, "radius": float(value.get("radius_cm", 30)) / 100.0, "y": y, "kind": path, "id": str(value.get("id", ""))})
		for child: Variant in value:
			if str(child) != "starts": _stand_spots(value[child], floor_heights, found, str(child) if value[child] is Array or value[child] is Dictionary else path)
	elif value is Array:
		for item: Variant in value: _stand_spots(item, floor_heights, found, path)

## A body with this outline (convex, x and z) from `bottom` to `top` stands
## where a pip must stand in `spot` (stand_spots()).
static func stands_in(outline: PackedVector2Array, bottom: float, top: float, spot: Dictionary) -> bool:
	var y := float(spot.y)
	if top - y <= STEP_ON + 0.005 or bottom - y >= STEP_HEAD: return false
	var width := _bounds(outline).size
	if maxf(width.x, width.y) <= SMALL_STAND: return false
	return _outside(outline, spot.at) < float(spot.radius) - MARGIN

static func _bounds(outline: PackedVector2Array) -> Rect2:
	var area := Rect2(outline[0], Vector2.ZERO)
	for point: Vector2 in outline: area = area.expand(point)
	return area

## How far `point` lies outside a convex outline (0 inside).
static func _outside(outline: PackedVector2Array, point: Vector2) -> float:
	if Geometry2D.is_point_in_polygon(point, outline): return 0.0
	var best := INF
	for index in range(outline.size()):
		best = minf(best, point.distance_to(Geometry2D.get_closest_point_to_segment(point, outline[index], outline[(index + 1) % outline.size()])))
	return best
