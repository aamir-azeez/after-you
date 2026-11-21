extends RefCounted
## World kit: how far everything walkable is drawn past its walkable edge.
## The engine keeps a pip's centre its walk radius (core/physical/runtime.gd
## PLAYER_RADIUS) inside a floor, but the drawn pip is wider than that, so a
## floor, crossing, stair or ramp drawn to its walkable rectangle shows a pip
## at its edge hanging over the side. Every walkable surface is drawn REACH_CM
## past each open side instead, and a wall that holds water stands that far
## out. Presentation only: the engine, navigation and recordings never read it.
##
## A side does not reach (or reaches less) where something else is near:
##  - a crossing (bridge or stair) reaches along its run only at an end that
##    meets nothing (a jetty's or a stub's far end);
##  - a surface that meets the side keeps it where it is along that stretch
##    (a floor's drawn shape is cut round it: pieces), so nothing new is drawn
##    over a floor someone walks; a crossing (not stepping stones) that meets
##    the side end-on at the side's own height or higher is the exception: the
##    side reaches under it (a bridge rests on its bank) and its deck is laid
##    only past that (open_span). A crossing met
##    along its run keeps that whole side;
##  - a crossing reaches two centimetres less than a floor;
##  - a surface across a gap leaves the gap at least KEEP_GAP_CM wide, the two
##    sides sharing what is left, so a gap still reads as a gap (a floor only
##    along the stretch that faces it);
##  - a surface that stands over a lower one (a balcony over its room) keeps
##    its edge where the floor below runs out past it: reaching would draw
##    over it.
##   var drawn := WalkReach.rect(level, surface)     # [x0, z0, x1, z1] cm, the bounds
##   var shape := WalkReach.pieces(level, surface)   # the rectangles a floor is drawn as
##   var edges := WalkReach.outline(shape)           # their outer edges, for trims and walls
## `level` is the plan the world draws (its islands, bridges and stairs);
## `surface` one of them. Worked out once per plan.

const DefinitionGeometry = preload("res://presentation/kit/definition_geometry.gd")
const Runtime = preload("res://core/physical/runtime.gd")

## The drawn pip's half-width (cm): its head, the widest part of it
## (presentation/spirit_visual.gd: 34.5 cm; the body 24, the feet 23).
const PIP_HALF_CM := 34
## How far each open side is drawn past the walkable edge (cm).
const REACH_CM := PIP_HALF_CM - Runtime.PLAYER_RADIUS
## The narrowest a gap between two surfaces is drawn (cm).
const KEEP_GAP_CM := 20
## How far (cm) a floor's cut stays clear of what it is cut round, so their
## faces never share a plane.
const NOTCH_CLEAR_CM := 2

## The drawn bounds of `surface` (cm), which `level` holds.
static func rect(level: Dictionary, surface: Dictionary, open: Array = []) -> Array:
	var found: Variant = layout(level, open).get(str(surface.get("id", "")))
	return (found.rect as Array).duplicate() if found != null else surface.rect_cm.duplicate()

## The rectangles (cm) `surface` is drawn as: its bounds less where a
## neighbour meets a side (a crossing is always one).
static func pieces(level: Dictionary, surface: Dictionary, open: Array = []) -> Array:
	var found: Variant = layout(level, open).get(str(surface.get("id", "")))
	return (found.pieces as Array).duplicate(true) if found != null else [surface.rect_cm.duplicate()]

## How far each side of `surface` reaches at most (cm): [west (-x), north
## (-z), east (+x), south (+z)].
static func sides(level: Dictionary, surface: Dictionary) -> Array:
	var drawn := rect(level, surface)
	var r: Array = surface.rect_cm
	return [int(r[0]) - int(drawn[0]), int(r[1]) - int(drawn[1]), int(drawn[2]) - int(r[2]), int(drawn[3]) - int(r[3])]

## Every walkable surface's drawn shape by id: {"rect", "pieces"}. `open`
## names the crossings laid as stepping stones: discs in the water, so they
## keep their rectangle, and a floor never reaches under one (it would cover
## a stone): it is cut round it instead.
static func layout(level: Dictionary, open: Array = []) -> Dictionary:
	var surfaces := walkable(level)
	var key := [&"walk_reach", surfaces, open]
	if DefinitionGeometry.has(key): return DefinitionGeometry.kept(key)
	var crossings: Dictionary = {}
	for surface: Dictionary in level.get("bridges", []) + level.get("stairs", []): crossings[str(surface.id)] = true
	# Crossings first: a floor is cut round a crossing that meets it as drawn.
	var found: Dictionary = {}
	for surface: Dictionary in surfaces:
		if crossings.has(str(surface.id)): found[str(surface.id)] = _drawn(surface, surfaces, crossings, {}, open)
	for surface: Dictionary in surfaces:
		if not crossings.has(str(surface.id)): found[str(surface.id)] = _drawn(surface, surfaces, crossings, found, open)
	return DefinitionGeometry.keep(key, found)

## The stretch of `crossing`'s run (cm, [low, high] along it) no floor reaches
## over: a deck is laid there, so the floor's top and the deck's never share
## a plane.
static func open_span(level: Dictionary, crossing: Dictionary, open: Array = []) -> Array:
	var surfaces := walkable(level)
	var axis := run_axis(crossing, surfaces)
	var drawn := rect(level, crossing, open)
	var r: Array = crossing.rect_cm
	var low := float(drawn[axis])
	var high := float(drawn[axis + 2])
	if str(crossing.get("id", "")) in open: return [low, high]
	for other: Dictionary in level.get("islands", []):
		var o: Array = other.rect_cm
		if int(o[1 - axis]) >= int(r[3 - axis]) or int(o[3 - axis]) <= int(r[1 - axis]): continue
		var shown := rect(level, other, open)
		if int(o[axis + 2]) == int(r[axis]) and _rests_under(other, crossing, axis + 2, surfaces): low = maxf(low, float(shown[axis + 2]))
		if int(o[axis]) == int(r[axis + 2]) and _rests_under(other, crossing, axis, surfaces): high = minf(high, float(shown[axis]))
	return [low, high] if high - low >= 8.0 else [float(drawn[axis]), float(drawn[axis + 2])]

## The outer edges of `shape` (rectangles that never overlap, cm), the
## stretches no other rectangle of it meets: [[from, to], line, outward,
## along_x] each, as the water kit's wall runs read them.
static func outline(shape: Array) -> Array:
	var found: Array = []
	for rect: Array in shape:
		for side in range(4):
			var along_x := side % 2 == 1
			var line := float(rect[side])
			var outward := 1.0 if side >= 2 else -1.0
			var spans: Array = [[float(rect[0 if along_x else 1]), float(rect[2 if along_x else 3])]]
			for other: Array in shape:
				if other == rect or float(other[(side + 2) % 4]) != line: continue
				spans = _less(spans, float(other[0 if along_x else 1]), float(other[2 if along_x else 3]))
			for span: Array in spans: found.append([span, line, outward, along_x])
	return found

## The walkable surfaces of `level`: its islands, bridges and stairs, and a
## lift car's shaft (First Steps' "lift").
static func walkable(level: Dictionary) -> Array:
	var lift: Variant = level.get("lift")
	return level.get("islands", []) + level.get("bridges", []) + level.get("stairs", []) + ([lift] if lift is Dictionary and lift.has("rect_cm") else [])

## The axis a crossing runs along: 0 (x) or 1 (z). A stair names it; a bridge
## runs between the surfaces that meet its ends, else along its longer side.
static func run_axis(surface: Dictionary, surfaces: Array = []) -> int:
	if surface.has("axis"): return 0 if str(surface.axis) == "x" else 1
	var r: Array = surface.rect_cm
	var ends := [0, 0]
	for other: Dictionary in surfaces:
		if other == surface: continue
		var o: Array = other.rect_cm
		for axis in range(2):
			var across := int(o[1 - axis]) < int(r[3 - axis]) and int(o[3 - axis]) > int(r[1 - axis])
			if across and (int(o[axis + 2]) == int(r[axis]) or int(o[axis]) == int(r[axis + 2])): ends[axis] += 1
	if ends[0] != ends[1]: return 0 if ends[0] > ends[1] else 1
	return 0 if int(r[2]) - int(r[0]) >= int(r[3]) - int(r[1]) else 1

## The surface's height (cm) at `at` (cm, along its run for a stair).
static func height_at(surface: Dictionary, at: Vector2) -> float:
	if not surface.has("axis"): return float(surface.get("height_cm", surface.get("from_height_cm", 0)))
	var r: Array = surface.rect_cm
	var axis := 0 if str(surface.axis) == "x" else 1
	var fraction := clampf((at[axis] - float(r[axis])) / maxf(1.0, float(r[axis + 2]) - float(r[axis])), 0.0, 1.0)
	return lerpf(float(surface.from_height_cm), float(surface.to_height_cm), fraction)

## The lowest a surface stands (cm).
static func _low(surface: Dictionary) -> float:
	if surface.has("axis"): return minf(float(surface.from_height_cm), float(surface.to_height_cm))
	return float(surface.get("height_cm", surface.get("bottom_height_cm", 0)))

## `surface`'s drawn shape; `drawn_crossings` holds the crossings' shapes, for a floor.
static func _drawn(surface: Dictionary, surfaces: Array, crossings: Dictionary, drawn_crossings: Dictionary, open: Array) -> Dictionary:
	var r: Array = surface.rect_cm
	var crossing := crossings.has(str(surface.id))
	# Stepping stones are discs in the water: their rectangle stays as it is.
	# A crossing reaches two centimetres less than a floor, so a crossing and
	# a floor reaching side by side never put two faces in one plane.
	var most := REACH_CM - (2 if crossing else 0)
	var reach := [0, 0, 0, 0] if str(surface.id) in open else [most, most, most, most]
	# Stretches of a floor's side a neighbour limits: [side, from, to, depth]
	# (cm along it; how far it may still reach there).
	var notches: Array = []
	for other: Dictionary in surfaces:
		if other == surface: continue
		var o: Array = other.rect_cm
		# A lift's stops share one footprint: the car is drawn as one.
		if o == r: continue
		var shown: Array = drawn_crossings[str(other.id)].rect if drawn_crossings.has(str(other.id)) else o
		# A floor keeps clear of stepping stones' mouth by a reach either side,
		# so the open water round the stones stays open.
		if str(other.id) in open:
			var run := run_axis(other, surfaces)
			shown = o.duplicate()
			shown[1 - run] = int(o[1 - run]) - REACH_CM
			shown[3 - run] = int(o[3 - run]) + REACH_CM
		# The gaps between the two along x and z: negative where they overlap.
		var dx := maxi(int(o[0]) - int(r[2]), int(r[0]) - int(o[2]))
		var dz := maxi(int(o[1]) - int(r[3]), int(r[1]) - int(o[3]))
		if dx < 0 and dz < 0:
			# One stands over the other: the higher keeps its edge wherever
			# reaching would draw over the floor below.
			if _low(other) < _low(surface):
				for side in range(4):
					var axis := side % 2
					var beyond := int(o[axis + 2]) > int(r[axis + 2]) if side >= 2 else int(o[axis]) < int(r[axis])
					if not beyond: continue
					if crossing: reach[side] = 0
					else: notches.append([side, int(shown[1 - axis]), int(shown[3 - axis]), 0])
			continue
		var gap := maxi(dx, dz)
		if gap >= 2 * REACH_CM + KEEP_GAP_CM: continue
		# The side that faces it: across the axis they are furthest apart on.
		var axis := 0 if dx >= dz else 1
		var side := axis + (2 if int(o[axis]) >= int(r[axis + 2]) else 0)
		var touching := gap == 0 and (dx < 0 or dz < 0)
		if touching and crossings.has(str(other.id)) and str(other.id) not in open and _rests_under(surface, other, side, surfaces): continue
		# What is left of the gap once it keeps KEEP_GAP_CM, shared by its sides.
		var depth := 0 if touching else maxi(0, (gap - KEEP_GAP_CM) / 2)
		if crossing: reach[side] = mini(reach[side], depth)
		# A floor is cut round it (a crossing as drawn, widened across its run;
		# past a corner as far as the gap), only along the stretch it faces.
		else: notches.append([side, int(shown[1 - axis]) - gap - NOTCH_CLEAR_CM, int(shown[3 - axis]) + gap + NOTCH_CLEAR_CM, depth])
	var drawn := [int(r[0]) - reach[0], int(r[1]) - reach[1], int(r[2]) + reach[2], int(r[3]) + reach[3]]
	for notch: Array in notches:
		var side: int = notch[0]
		var axis := side % 2
		var whole: bool = int(notch[1]) <= int(r[1 - axis]) - reach[1 - axis] and int(notch[2]) >= int(r[3 - axis]) + reach[3 - axis]
		# A neighbour along the whole side limits the side itself.
		if whole: reach[side] = mini(reach[side], int(notch[3]))
	drawn = [int(r[0]) - reach[0], int(r[1]) - reach[1], int(r[2]) + reach[2], int(r[3]) + reach[3]]
	var shape: Array = [drawn]
	for notch: Array in notches:
		var side: int = notch[0]
		var axis := side % 2
		var depth: int = notch[3]
		if reach[side] <= depth: continue
		# The strip past the side's walkable edge (and its depth), along the stretch.
		var cut := drawn.duplicate()
		cut[(side + 2) % 4] = int(r[side]) + (depth if side >= 2 else -depth)
		cut[1 - axis] = maxi(int(drawn[1 - axis]), int(notch[1]))
		cut[3 - axis] = mini(int(drawn[3 - axis]), int(notch[2]))
		if cut[3 - axis] <= cut[1 - axis]: continue
		var next: Array = []
		for piece: Array in shape: next.append_array(minus(piece, cut))
		shape = next
	return {"rect": drawn, "pieces": shape}

## `rect` less `cut` (both [x0, z0, x1, z1]), as up to four rectangles.
static func minus(rect: Array, cut: Array) -> Array:
	if cut[0] >= rect[2] or cut[2] <= rect[0] or cut[1] >= rect[3] or cut[3] <= rect[1]: return [rect]
	var found: Array = []
	var top := maxi(int(rect[1]), int(cut[1]))
	var bottom := mini(int(rect[3]), int(cut[3]))
	if cut[1] > rect[1]: found.append([rect[0], rect[1], rect[2], top])
	if cut[3] < rect[3]: found.append([rect[0], bottom, rect[2], rect[3]])
	if cut[0] > rect[0]: found.append([rect[0], top, cut[0], bottom])
	if cut[2] < rect[2]: found.append([cut[2], top, rect[2], bottom])
	return found

## `spans` ([from, to] each) less the stretch from..to.
static func _less(spans: Array, from: float, to: float) -> Array:
	var found: Array = []
	for span: Array in spans:
		if to <= span[0] or from >= span[1]:
			found.append(span)
			continue
		if from > span[0]: found.append([span[0], from])
		if to < span[1]: found.append([to, span[1]])
	return found

## Whether `surface`'s `side` may reach under `other`, which meets it there:
## `other` is a crossing whose end lies on that side and which stays at the
## side's height or over it for the whole reach.
static func _rests_under(surface: Dictionary, other: Dictionary, side: int, surfaces: Array) -> bool:
	var axis := side % 2
	if run_axis(other, surfaces) != axis: return false
	var r: Array = surface.rect_cm
	var o: Array = other.rect_cm
	var line := float(r[axis + 2] if side >= 2 else r[axis])
	var middle := (maxf(float(r[1 - axis]), float(o[1 - axis])) + minf(float(r[3 - axis]), float(o[3 - axis]))) * 0.5
	var outward := 1.0 if side >= 2 else -1.0
	var near := Vector2.ZERO
	var far := Vector2.ZERO
	near[axis] = line
	near[1 - axis] = middle
	far[axis] = line + outward * float(REACH_CM)
	far[1 - axis] = middle
	var own := height_at(surface, near)
	return height_at(other, near) >= own - 1.0 and height_at(other, far) >= own - 1.0
