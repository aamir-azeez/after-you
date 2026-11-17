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
## Each family's floors, crossings and spots (services/level_layout.gd).
const LevelLayout = preload("res://services/level_layout.gd")

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

## Walking spaces (LevelLayout.walking_areas): {rect, y, rise, name, id}.
## Stairs span their whole rise.
static func walkable(view: Dictionary) -> Array:
	var names := {"island": "island", "bridge": "route", "stair": "stair"}
	return LevelLayout.walking_areas(view).map(func(area: Dictionary) -> Dictionary:
		return {"rect": rect(area.rect_cm), "y": float(area.height_cm) / 100.0, "rise": float(area.rise_cm) / 100.0, "name": "%s %s" % [names[area.kind], area.id], "id": str(area.id)})

## Interactive places (LevelLayout.spots: pads, levers, switches, goals,
## optics, starts) and drops, each as {rect, y, name}.
static func places(view: Dictionary, floor_heights: Dictionary) -> Array:
	var found: Array = []
	var starts: Array = []
	for spot: Dictionary in LevelLayout.spots(view):
		var radius := float(spot.radius_cm) / 100.0
		var at := Vector2(float(spot.position_cm[0]), float(spot.position_cm[1])) / 100.0
		(starts if spot.kind == "start" else found).append({"rect": Rect2(at - Vector2.ONE * radius, Vector2.ONE * radius * 2.0), "y": float(spot.height_cm) / 100.0, "name": "%s %s" % [spot.kind, spot.id]})
	for drop: Dictionary in view.get("drops", []):
		found.append({"rect": rect(drop.rect_cm), "y": float(floor_heights.get(str(drop.get("surface_id", "")), 0.0)), "name": "drop " + str(drop.get("id", ""))})
	return found + starts

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

## Controls drawn into each other (the level checker): every lever and
## selector stands CONTROL_TOP tall over its spot (kit/pieces/lever.gd's knob
## over its housing), every pad, plate, socket and goal lies flat, each as
## wide as its reach (radius_cm). A world adds what it builds beside a control
## (control_extras(spot) on its script: [{offset, radius, top}], metres, such as
## Tide's lamp beside each lever). Two bodies on one floor draw into each other
## when, each swept up its height along the camera's VIEW, they come nearer
## than their radii: the front one's top then stands over the back one's base.
const CONTROL_TOP := 0.6
const TALL_CONTROLS := ["levers", "controls"]
const FLAT_CONTROLS := ["pressure_pads", "ball_pads", "hold_pads", "plates", "plate", "sockets", "goal", "goals"]

## The bodies of `view`'s controls: {id, at, radius, top, y}; `extras` is the
## world script's control_extras (an invalid Callable adds none).
static func control_bodies(view: Dictionary, extras: Callable = Callable()) -> Array:
	var found: Array = []
	for spot: Dictionary in LevelLayout.spots(view):
		var kind := str(spot.kind)
		if kind not in TALL_CONTROLS and kind not in FLAT_CONTROLS: continue
		var at := Vector2(float(spot.position_cm[0]), float(spot.position_cm[1])) / 100.0
		var y := float(spot.height_cm) / 100.0
		found.append({"id": str(spot.id), "at": at, "radius": float(spot.radius_cm) / 100.0, "top": CONTROL_TOP if kind in TALL_CONTROLS else 0.0, "y": y})
		if not extras.is_valid(): continue
		for extra: Dictionary in extras.call(spot):
			found.append({"id": str(spot.id), "at": at + (extra.offset as Vector2), "radius": float(extra.radius), "top": float(extra.top), "y": y})
	return found

## Whether two control bodies (control_bodies) draw into each other.
static func bodies_touch(one: Dictionary, two: Dictionary) -> bool:
	if absf(float(one.y) - float(two.y)) > 0.01: return false
	var gap := _segments_apart(one.at, one.at + VIEW * float(one.top), two.at, two.at + VIEW * float(two.top))
	return gap < float(one.radius) + float(two.radius)

## The shortest distance between segments a0-a1 and b0-b1.
static func _segments_apart(a0: Vector2, a1: Vector2, b0: Vector2, b1: Vector2) -> float:
	var pair := Geometry2D.get_closest_points_between_segments(a0, a1, b0, b1)
	return pair[0].distance_to(pair[1])

## The spots a pip stands inside (LevelLayout.spots of the STAND_IN kinds):
## {at, radius, y, kind, id}. A solid one (core/solid_footprint.gd) is reached
## from beside, never stood in, so it is left out.
static func stand_spots(view: Dictionary) -> Array:
	var found: Array = []
	for spot: Dictionary in LevelLayout.spots(view):
		if str(spot.kind) not in STAND_IN or bool(spot.solid): continue
		found.append({"at": Vector2(float(spot.position_cm[0]), float(spot.position_cm[1])) / 100.0, "radius": float(spot.radius_cm) / 100.0, "y": float(spot.height_cm) / 100.0, "kind": str(spot.kind), "id": str(spot.id)})
	return found

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
