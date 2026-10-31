extends Control
## The Pollen mark, and the one place it is drawn: a soft gold grain with
## little bumps round its edge, a highlight and a few dimples, as the owner's
## Pollen board draws it (pollen-concepts board-1, "Soft gold, little bumps
## round the edge"). Every Pollen icon in the game is one of these, made with
## make(SIZE) or drawn with draw_grain(); test_pollen_mark.gd fails if a Pollen
## colour is drawn anywhere else. Change the grain here and it changes everywhere.
##
## Flat shapes, no outline and no texture, so it is sharp at every size and
## costs one draw per change, never per frame.

## Beside an amount the grain is sized from the amount's font: its digits
## stand about 0.7 of the font size tall, and the grain is about 1.3 times
## that, so it reads as part of the line, centred on the digits, and never
## reaches past the line into a rule or a row above or below.
const BESIDE := 0.92
const BODY := Color("f5c95e")
const SHADE := Color("e7ac45")
const BUMP := Color("eab44c")
const DIMPLE := Color("dc9f3b")
const HIGHLIGHT := Color("fff3cc")
const BUMPS := 18
const DIMPLES := [Vector2(0.28, -0.12), Vector2(0.42, 0.28), Vector2(-0.06, 0.38), Vector2(-0.4, 0.12), Vector2(0.08, -0.48), Vector2(0.12, 0.08)]

## A mark sized for an amount set at `font_size`, to sit in the same row.
static func beside(font_size: int) -> Control:
	return make(roundf(font_size * BESIDE))

## A mark `side` pixels square.
static func make(side: float) -> Control:
	var mark: Control = load("res://presentation/kit/pollen_mark.gd").new()
	mark.name = "PollenMark"
	mark.custom_minimum_size = Vector2(side, side)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.accessibility_name = "Pollen"
	return mark

func _draw() -> void:
	# The bumps reach about 1.12 of the grain's radius, so the grain is sized to fit inside.
	draw_grain(self, size * 0.5, minf(size.x, size.y) * 0.5 / 1.12)

## Draws one grain of radius `radius` round `centre` into `canvas` (any CanvasItem, in its own draw).
static func draw_grain(canvas: CanvasItem, centre: Vector2, radius: float) -> void:
	for part: Array in _parts(centre, radius): _draw_part(canvas, part)

## One grain cut to the polygon `clip`, as data to keep: art that holds grains
## inside a shape (kit/bundle_art.gd's jar) builds this once and draws it with
## draw_cut. Parts inside the clip stay round; only the parts that cross its
## edge become polygons (Geometry2D at build time, never in a draw), and the
## parts outside it are left out.
static func grain_cut(centre: Vector2, radius: float, clip: PackedVector2Array) -> Array:
	var kept := []
	for part: Array in _parts(centre, radius):
		var outline := _part_polygon(part, 1.02)
		if Geometry2D.clip_polygons(outline, clip).is_empty():
			kept.append(part)
			continue
		for piece: PackedVector2Array in Geometry2D.intersect_polygons(_part_polygon(part, 1.0), clip):
			# A round part cut by a plain outline leaves no holes, only pieces.
			if piece.size() > 2: kept.append([piece, part[2]])
	return kept

## Draws grain_cut's parts with every point and radius moved by `at` (a
## translation and a uniform scale), so one kept cut serves every size.
static func draw_cut(canvas: CanvasItem, parts: Array, at: Transform2D) -> void:
	var scale := at.get_scale().x
	for part: Array in parts:
		if part[0] is PackedVector2Array: canvas.draw_colored_polygon(at * (part[0] as PackedVector2Array), part[1])
		else: _draw_part(canvas, [at * (part[0] as Vector2), float(part[1]) * scale, part[2], part[3], part[4]])

## The grain's round parts in draw order: [centre, radius, colour, turn, squash].
static func _parts(centre: Vector2, radius: float) -> Array:
	var parts := []
	for index in range(BUMPS):
		var angle := TAU * index / BUMPS + 0.12
		parts.append([centre + Vector2(cos(angle), sin(angle)) * radius * 0.97, radius * 0.15, BUMP, 0.0, 1.0])
	parts.append([centre, radius, SHADE, 0.0, 1.0])
	parts.append([centre + Vector2(-0.07, -0.08) * radius, radius * 0.9, BODY, 0.0, 1.0])
	for index in range(DIMPLES.size()):
		parts.append([centre + DIMPLES[index] * radius, radius * (0.07 if index == 5 else 0.085), Color(DIMPLE, 0.85), 0.0, 1.0])
	parts.append([centre + Vector2(-0.32, -0.38) * radius, radius * 0.3, HIGHLIGHT, deg_to_rad(-28.0), 0.6])
	return parts

static func _draw_part(canvas: CanvasItem, part: Array) -> void:
	if part[4] == 1.0:
		canvas.draw_circle(part[0], part[1], part[2], true, -1.0, true)
		return
	canvas.draw_set_transform(part[0], part[3], Vector2(1.0, part[4]))
	canvas.draw_circle(Vector2.ZERO, part[1], part[2], true, -1.0, true)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## A part's outline as a polygon, `grow` times its radius.
static func _part_polygon(part: Array, grow: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var count := 24
	var turn := Transform2D(float(part[3]), Vector2(1.0, float(part[4])), 0.0, Vector2.ZERO)
	for index in range(count):
		var angle := TAU * index / count
		points.append(part[0] + turn.basis_xform(Vector2(cos(angle), sin(angle)) * float(part[1]) * grow))
	return points
