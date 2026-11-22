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
## The ground the camera looks across per metre of height: a chapter camera
## sits at offset (3, 13, 10) unless its level stands it elsewhere (a stage
## view's "camera_from", content/dressing/placement.gd stage_view; sweep()).
const VIEW := Vector2(-3.0, -10.0) / 13.0

## The ground `view`'s camera looks across per metre of height.
static func sweep(view: Dictionary) -> Vector2:
	var from: Variant = view.get("camera_from")
	if not from is Vector3 or (from as Vector3).y <= 0.0: return VIEW
	return Vector2(-(from as Vector3).x, -(from as Vector3).z) / (from as Vector3).y
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
const SQUARE_KINDS := ["bench", "cottage", "rug", "path", "planter", "boat", "lobster_pot", "shelf", "frame", "fence", "hedge", "wall", "washing_line", "fishing_rod"]

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
	var along := sweep(view)
	return LevelLayout.walking_areas(view).map(func(area: Dictionary) -> Dictionary:
		return {"rect": rect(area.rect_cm), "y": float(area.height_cm) / 100.0, "rise": float(area.rise_cm) / 100.0, "name": "%s %s" % [names[area.kind], area.id], "id": str(area.id), "sweep": along})

## Interactive places (LevelLayout.spots: pads, levers, switches, goals,
## optics, starts) and drops, each as {rect, y, name}.
static func places(view: Dictionary, floor_heights: Dictionary) -> Array:
	var found: Array = []
	var starts: Array = []
	var along := sweep(view)
	for spot: Dictionary in LevelLayout.spots(view):
		var radius := float(spot.radius_cm) / 100.0
		var at := Vector2(float(spot.position_cm[0]), float(spot.position_cm[1])) / 100.0
		(starts if spot.kind == "start" else found).append({"rect": Rect2(at - Vector2.ONE * radius, Vector2.ONE * radius * 2.0), "y": float(spot.height_cm) / 100.0, "name": "%s %s" % [spot.kind, spot.id], "sweep": along})
	for drop: Dictionary in view.get("drops", []):
		found.append({"rect": rect(drop.rect_cm), "y": float(floor_heights.get(str(drop.get("surface_id", "")), 0.0)), "name": "drop " + str(drop.get("id", "")), "sweep": along})
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
## of height h at base b hides ground at y0 behind it, swept along the
## target's "sweep" (else VIEW) per metre of height between b - y0 - spirit
## and b + h - y0.
static func hides(footprint: Rect2, base: float, top: float, target: Dictionary) -> bool:
	var y0 := float(target.y)
	var near := maxf(0.0, base - y0 - SPIRIT - float(target.get("rise", 0.0)))
	var far := top - y0
	if far <= 0.0: return false
	var goal: Rect2 = (target.rect as Rect2).grow(MARGIN)
	var along: Vector2 = target.get("sweep", VIEW)
	var step := near
	while step <= far + 0.001:
		if Rect2(footprint.position + along * step, footprint.size).grow(-0.01).intersects(goal): return true
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

## --- Resting on the ground ------------------------------------------------------
## Every prop rests on ground (a floor with its lip LIP past its rectangle, a
## crossing's deck, a bank, or ground a world lays as data: the view's
## "grounds"), or stands in water down to its bed. A prop resting on nothing
## floats over the void or the water past an island's edge. The placer settles
## every prop onto ground (content/dressing/placement.gd settle()) and the lint
## measures every built prop (tests/test_dressing_lint.gd dressing_faults()).

## How far a floor's lip reaches past its rectangle (kit/surfaces.gd skirt).
const LIP := 0.05
## On the water a floor's edge carries a fender or a parapet up to this deep
## (kit/water_bodies.gd): a pole standing in the water stands clear of it.
const WATER_RIM := 0.10
## A prop's base may stand this far above its ground (a bank's top layer).
const REST := 0.04
## How far under a ground's top a prop may stand sunk in it (a post in its
## floor, a foot in a bank).
const SUNK := 0.45
## A prop standing in water reaches its bed to within this (metres).
const BED_GRACE := 0.05
## A foot point this near a ground's edge still rests on it.
const EDGE_GRACE := 0.01
## Two things meet only when they share more than this across, along and in
## height (metres): less is a touch.
const CUT := 0.04

## The ground of a stage: its floors and crossings, the view's own "grounds"
## and `banks`, each {rect (metres), top, name}.
static func grounds(view: Dictionary, banks: Array = []) -> Array:
	var found: Array = []
	for island: Dictionary in view.get("islands", []):
		found.append({"rect": rect(island.rect_cm).grow(LIP), "top": float(island.get("height_cm", 0)) / 100.0, "name": "floor " + str(island.id)})
	for route: Dictionary in view.get("bridges", []):
		found.append({"rect": rect(route.rect_cm), "top": float(route.get("height_cm", route.get("from_height_cm", 0))) / 100.0, "name": "crossing " + str(route.get("id", ""))})
	for ground: Dictionary in view.get("grounds", []):
		found.append({"rect": rect(ground.rect_cm), "top": float(ground.height_cm) / 100.0, "name": str(ground.get("id", "ground"))})
	for bank: Dictionary in banks: found.append(bank.merged({"name": "bank"}))
	return found

## A bank's ground: its top layer's top over its rectangle.
static func bank_ground(spec: Dictionary, floor_heights: Dictionary) -> Dictionary:
	return {"rect": Props.extent(spec).rect, "top": float(floor_heights.get(str(spec.get("surface", "")), 0.0)) + Props.bank_top(spec) / 100.0}

## Points over where a prop rests (kit/props.gd FOOT_SHARE of its footprint,
## a line along its length), metres; empty for a prop that rests on no floor
## (Props.HUNG, wall-hung) and for a bank, which is ground itself.
static func foot_points(spec: Dictionary) -> PackedVector2Array:
	var points := PackedVector2Array()
	var kind := str(spec.get("kind", ""))
	if kind in Props.HUNG or kind in Props.GLOWS or kind == "bank" or bool(spec.get("wall", false)): return points
	var extent := Props.extent(spec)
	if spec.has("from") and spec.has("to"):
		var from := Vector2(float(spec.from[0]), float(spec.from[1])) / 100.0
		var to := Vector2(float(spec.to[0]), float(spec.to[1])) / 100.0
		var across := (to - from).orthogonal().normalized()
		var half := minf((extent.rect as Rect2).size.x, (extent.rect as Rect2).size.y) * 0.5 - EDGE_GRACE
		var count := maxi(2, ceili(from.distance_to(to) / 0.1) + 1)
		for index in range(count):
			var at := from.lerp(to, float(index) / float(count - 1))
			for side: float in [-1.0, 0.0, 1.0]: points.append(at + across * half * side)
		return points
	var area: Rect2 = extent.rect
	var share := float(Props.FOOT_SHARE.get(kind, 1.0))
	area = Rect2(area.get_center() - area.size * share * 0.5, area.size * share).grow(-EDGE_GRACE)
	var round := kind not in SQUARE_KINDS
	for i in range(5):
		for j in range(5):
			var point := area.position + area.size * Vector2(float(i) / 4.0, float(j) / 4.0)
			if round and point.distance_to(area.get_center()) > area.size.x * 0.5 + 0.0001: continue
			points.append(point)
	return points

## Whether a foot point at `point`, the prop's base at `base` (metres), rests
## on `ground` ({rect, top}).
static func rests_on(point: Vector2, base: float, ground: Dictionary) -> bool:
	return base <= float(ground.top) + REST and base >= float(ground.top) - SUNK and (ground.rect as Rect2).grow(EDGE_GRACE).has_point(point)

## Whether a placed spec rests whole on `grounds`.
static func rests(spec: Dictionary, floor_heights: Dictionary, grounds: Array) -> bool:
	var base := float(floor_heights.get(str(spec.get("surface", "")), 0.0)) + float(Props.extent(spec).base)
	for point: Vector2 in foot_points(spec):
		if not grounds.any(func(ground: Dictionary) -> bool: return rests_on(point, base, ground)): return false
	return true

## Two solid props (solid()) stand in each other more than CUT every way:
## the stricter rule settled scenery keeps, as the lint measures it.
static func meet(one: Dictionary, two: Dictionary) -> bool:
	if one.is_empty() or two.is_empty(): return false
	if minf(float(one.high), float(two.high)) - maxf(float(one.low), float(two.low)) <= CUT: return false
	var shared := (one.rect as Rect2).intersection(two.rect)
	if shared.size.x <= CUT or shared.size.y <= CUT: return false
	# A round footprint meets only inside its circle.
	var centre := shared.get_center()
	return _covers_point(one, centre) and _covers_point(two, centre)

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

## Controls and pieces drawn into each other (the level checker): every lever
## and selector stands CONTROL_TOP tall over its spot (kit/pieces/lever.gd's
## knob over its housing), every pad, plate, socket, goal, item spot, throw
## mark and throw landing lies flat, each as wide as it is drawn on its floor
## (a throw mark wholly inside a pad is the pad's, LevelLayout.mark_pad):
## its reach (radius_cm), or wider where its look is (a board's corners, a
## crank board's windlass, a bell's frame, a pedestal's cap, a landing's
## ticks: the kits' drawn_radius). A world adds what it builds beside a control
## (control_extras(spot) on its script: [{offset, radius, top}], metres, such
## as Tide's lamp beside each lever). Two bodies on one floor draw into each
## other when, each swept up its height along the camera's VIEW, they come
## nearer than their radii: the front one's top then stands over the back
## one's base.
const CONTROL_TOP := 0.6
const TALL_CONTROLS := ["levers", "controls"]
const FLAT_CONTROLS := ["pressure_pads", "ball_pads", "hold_pads", "plates", "plate", "sockets", "goal", "goals"]
const PAD_KINDS := LevelLayout.PAD_KINDS
const PadKit = preload("res://presentation/kit/pieces/pad.gd")
const GoalKit = preload("res://presentation/kit/pieces/goal.gd")
const SocketKit = preload("res://presentation/kit/pieces/socket.gd")

## The bodies of `view`'s controls and pieces: {id, at, radius, top, y};
## `extras` is the world script's control_extras (an invalid Callable adds
## none) and `styles` the chapter's piece style of a slot and piece id
## (content/dressing/piece_styles.gd style(); invalid: every piece as wide
## as its reach and no item spots, whose look it cannot tell).
static func control_bodies(view: Dictionary, extras: Callable = Callable(), styles: Callable = Callable()) -> Array:
	var found: Array = []
	var along := sweep(view)
	var landings: Dictionary = {}
	for thrown: Dictionary in view.get("throws", []): landings[str(thrown.get("to", ""))] = true
	for spot: Dictionary in LevelLayout.spots(view):
		var kind := str(spot.kind)
		var radius := drawn_radius(view, spot, styles, landings)
		if radius <= 0.0: continue
		var at := Vector2(float(spot.position_cm[0]), float(spot.position_cm[1])) / 100.0
		var y := float(spot.height_cm) / 100.0
		found.append({"id": str(spot.id), "at": at, "radius": radius, "top": CONTROL_TOP if kind in TALL_CONTROLS else 0.0, "y": y, "sweep": along})
		if not extras.is_valid() or not (kind in TALL_CONTROLS or kind in FLAT_CONTROLS): continue
		for extra: Dictionary in extras.call(spot):
			found.append({"id": str(spot.id), "at": at + (extra.offset as Vector2), "radius": float(extra.radius), "top": float(extra.top), "y": y, "sweep": along})
	return found

## How far from its centre `spot` (LevelLayout.spots) is drawn on its floor
## (metres; 0: not a piece, or not drawn). `landings` holds the item spots a
## throw lands on, drawn as the landing's ring of ticks.
static func drawn_radius(view: Dictionary, spot: Dictionary, styles: Callable, landings: Dictionary) -> float:
	var kind := str(spot.kind)
	var id := str(spot.id)
	var radius := float(spot.radius_cm) / 100.0
	if kind in TALL_CONTROLS: return radius
	if kind == "mark": return 0.0 if not LevelLayout.mark_pad(view, spot).is_empty() else radius + SocketKit.RING_TUBE
	if kind == "item_spots":
		var drawn := SocketKit.landing_radius(radius) if landings.has(id) else 0.0
		if not styles.is_valid(): return drawn
		var raw: Dictionary = {}
		for item: Dictionary in view.get("item_spots", []):
			if str(item.get("id", "")) == id: raw = item
		return maxf(drawn, SocketKit.drawn_radius(str(styles.call("item_spot", id)), raw))
	if kind not in FLAT_CONTROLS: return 0.0
	if not styles.is_valid(): return radius
	if kind in PAD_KINDS: return PadKit.drawn_radius(str(styles.call("pad", id)), radius)
	if kind in ["goal", "goals"]: return GoalKit.drawn_radius(str(styles.call("goal", id)), radius, GoalKit.GoalNeeds.terms(view.get("goal_policy", {}).get("when", {})).size())
	return radius

## Whether two control bodies (control_bodies) draw into each other.
static func bodies_touch(one: Dictionary, two: Dictionary) -> bool:
	if absf(float(one.y) - float(two.y)) > 0.01: return false
	var along: Vector2 = one.get("sweep", VIEW)
	var gap := _segments_apart(one.at, one.at + along * float(one.top), two.at, two.at + along * float(two.top))
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
