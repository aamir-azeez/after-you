extends Control
## Draws a flat map plan (map_plan_model.gd) top down in the game's palette:
## floors shaded by height, crossings by what this stage does with them, every
## control with its owner's mark and its pair tile (the game's letter and
## colour), a line in the pair's colour to every gate it works, the goal and
## the pips' starts, a title and a key. Tiles and words are laid out first
## (_layout) so none covers another or a glyph. Set `plan`; canvas_size() gives
## the canvas; the caller renders it on a SubViewport (map_plan.gd).
const OwnerMark = preload("res://presentation/kit/owner_mark.gd")
const PairTags = preload("res://presentation/kit/pair_tags.gd")
const Props = preload("res://presentation/kit/props.gd")
const HEADING := preload("res://assets/fonts/fredoka.ttf")
const BODY := preload("res://assets/fonts/nunito.ttf")
const INK := Color("2b3634")
const SOFT_INK := Color("5d6a66")
const CREAM := Color("f6f1dc")
const WATER := Color("b4d3d1")
const WATER_LINE := Color("a2c6c4")
const PAPER := Color("eef3ee")
## Floors from lowest to highest: sand to pale stone.
const FLOOR_RAMP := [Color("d9c79b"), Color("c4d3a0"), Color("dccfb2"), Color("ece4d1"), Color("f6f1e4")]
const TIMBER := Props.TIMBER_LIGHT
const STONE := Props.STONE
## Pixels per metre, kept between these, and the largest map area wanted.
const MIN_SCALE := 48.0
const MAX_SCALE := 96.0
const FIT := Vector2(1700, 900)
const MARGIN := 48.0
const TITLE_HEIGHT := 78.0
const KEY_HEIGHT := 96.0
const TILE := 22.0

var plan: Dictionary = {}
var _scale := 60.0
var _origin := Vector2.ZERO
## Everything placed so far on the canvas, for _free().
var _taken: Array[Rect2] = []

## The canvas size this plan needs (px).
func canvas_size() -> Vector2i:
	var bounds: Rect2 = plan.get("bounds", Rect2(0, 0, 100, 100))
	var metres := bounds.size / 100.0
	_scale = clampf(minf(FIT.x / maxf(metres.x, 0.1), FIT.y / maxf(metres.y, 0.1)), MIN_SCALE, MAX_SCALE)
	_origin = Vector2(MARGIN, MARGIN + TITLE_HEIGHT) - bounds.position / 100.0 * _scale
	var drawn := metres * _scale
	return Vector2i(ceili(maxf(drawn.x + MARGIN * 2.0, 1100.0)), ceili(drawn.y + MARGIN * 2.0 + TITLE_HEIGHT + KEY_HEIGHT))

## A plan point (cm) on the canvas.
func at(point: Vector2) -> Vector2:
	return _origin + point / 100.0 * _scale

func box(rect: Rect2) -> Rect2:
	return Rect2(at(rect.position), rect.size / 100.0 * _scale)

func _draw() -> void:
	var size := Vector2(canvas_size())
	draw_rect(Rect2(Vector2.ZERO, size), PAPER)
	var sea := box(plan.bounds).grow(22.0)
	draw_rect(sea, WATER)
	for y in range(int(sea.position.y) + 14, int(sea.end.y), 28):
		draw_line(Vector2(sea.position.x, y), Vector2(sea.end.x, y), WATER_LINE, 1.0)
	_floors()
	for zone: Dictionary in plan.zones: _dashed_rect(box(zone.rect).grow(-2.0), OwnerMark.color(zone.owner).darkened(0.25), 2.0)
	for obstacle: Dictionary in plan.obstacles: _hatched(box(obstacle.rect), Color("8f7a5c"))
	_crossings()
	for drop: Dictionary in plan.drops: _drop(drop)
	var layout := _layout()
	for line: Array in layout.lines: draw_line(line[0], line[1], line[2], 2.0, true)
	_controls()
	_goal()
	_starts()
	for tile: Array in layout.tiles: _tile(tile[0], tile[1])
	for caption: Array in layout.captions: _place(caption[0], caption[1])
	_title(size)
	_key(size)

# --- Floors and crossings ---------------------------------------------------------

func _floor_colour(height: int) -> Color:
	var heights := _heights()
	if heights.size() <= 1: return FLOOR_RAMP[1]
	return FLOOR_RAMP[roundi(float(heights.find(height)) / float(heights.size() - 1) * float(FLOOR_RAMP.size() - 1))]

func _heights() -> Array:
	var heights: Array = []
	for item: Dictionary in plan.floors:
		if int(item.height) not in heights: heights.append(int(item.height))
	heights.sort()
	return heights

## Lowest first, so a floor above another covers it as seen from above; every
## edge is drawn again on top, so a floor under another still shows its shape.
func _floors() -> void:
	var floors: Array = plan.floors.duplicate()
	floors.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.height) < int(b.height))
	for item: Dictionary in floors:
		var rect := box(item.rect)
		var colour := _floor_colour(int(item.height))
		draw_rect(rect.grow(2.0), colour.darkened(0.28))
		draw_rect(rect, colour if item.reached else colour.lerp(WATER, 0.55))
	for item: Dictionary in floors:
		var rect := box(item.rect)
		draw_rect(rect, Color(_floor_colour(int(item.height)).darkened(0.35), 0.8), false, 1.0)
		if not item.reached: _dashed_rect(rect.grow(-3.0), SOFT_INK, 1.5)

func _crossings() -> void:
	for item: Dictionary in plan.crossings:
		var rect := box(item.rect)
		var shut: bool = item.state == "shut" or not item.reached
		if item.kind == "stair":
			draw_rect(rect, STONE.lerp(WATER, 0.5) if shut else STONE)
			_treads(rect, item)
		else:
			_planks(rect, TIMBER.lerp(WATER, 0.6) if shut else TIMBER)
		_crossing_edge(rect, str(item.state))
		if not str(item.owner).is_empty(): _owner_mark(item.owner, rect.get_center() + Vector2(0, -rect.size.y * 0.5 - 8.0), 6.0)

func _planks(rect: Rect2, colour: Color) -> void:
	draw_rect(rect, colour)
	var along_x := rect.size.x >= rect.size.y
	var t := 9.0
	while t < (rect.size.x if along_x else rect.size.y):
		if along_x: draw_line(Vector2(rect.position.x + t, rect.position.y), Vector2(rect.position.x + t, rect.end.y), Color(INK, 0.18), 1.0)
		else: draw_line(Vector2(rect.position.x, rect.position.y + t), Vector2(rect.end.x, rect.position.y + t), Color(INK, 0.18), 1.0)
		t += 9.0

## A crossing's edge says what this stage does with it: dashed when a control
## opens it, solid when always open, solid with a kept mark when an earlier
## stage left it open, hatched when nothing opens it this stage.
func _crossing_edge(rect: Rect2, state: String) -> void:
	match state:
		"gated": _dashed_rect(rect, INK, 2.0)
		"shut": _hatched(rect, Color(INK, 0.35))
		"kept":
			draw_rect(rect, Color(INK, 0.55), false, 1.5)
			var corner := rect.position + Vector2(4, 4)
			draw_rect(Rect2(corner, Vector2(10, 7)), CREAM)
			draw_rect(Rect2(corner + Vector2(3, -1), Vector2(4, 9)), OwnerMark.GOLD.darkened(0.2))
		_: draw_rect(rect, Color(INK, 0.55), false, 1.5)

## Treads across the stair's axis and an arrow up toward its higher end.
func _treads(rect: Rect2, item: Dictionary) -> void:
	var along_x: bool = item.axis == "x"
	for index in range(1, 6):
		var t := float(index) / 6.0
		if along_x: draw_line(Vector2(rect.position.x + rect.size.x * t, rect.position.y), Vector2(rect.position.x + rect.size.x * t, rect.end.y), Color(INK, 0.3), 1.0)
		else: draw_line(Vector2(rect.position.x, rect.position.y + rect.size.y * t), Vector2(rect.end.x, rect.position.y + rect.size.y * t), Color(INK, 0.3), 1.0)
	# The from height is at the stair's low-coordinate end, the to height at its other end.
	var up := 1.0 if int(item.high) >= int(item.low) else -1.0
	var axis := Vector2(1, 0) if along_x else Vector2(0, 1)
	var centre := rect.get_center()
	var half := (rect.size.x if along_x else rect.size.y) * 0.3
	var tip := centre + axis * up * half
	draw_line(centre - axis * up * half, tip, INK, 2.0)
	var side := Vector2(-axis.y, axis.x) * 4.0
	draw_colored_polygon(PackedVector2Array([tip + axis * up * 5.0, tip + side, tip - side]), INK)

func _drop(drop: Dictionary) -> void:
	var rect := box(drop.rect)
	draw_rect(rect, Color("54605c"))
	var centre := rect.get_center()
	draw_line(centre + Vector2(0, -6), centre + Vector2(0, 5), CREAM, 2.0)
	draw_colored_polygon(PackedVector2Array([centre + Vector2(0, 8), centre + Vector2(-4, 3), centre + Vector2(4, 3)]), CREAM)

# --- Layout: where tiles and words go ----------------------------------------------

## Places every pair tile and caption clear of each other and of the glyphs,
## each searched outward from where it belongs: each gate's row of tiles (with
## the values a selector must stand at) by its crossing, each control's tile
## and name beside it, the pips' words beside them, floor names in their
## corners. Returns {tiles: [[pair, centre]], captions: [[lines, rect]],
## lines: [[from, to, colour]]}; a caption line is [text, colour, font, size].
func _layout() -> Dictionary:
	_taken.clear()
	var result := {"tiles": [], "captions": [], "lines": []}
	for item: Dictionary in plan.controls: _taken.append(Rect2(at(item.at) - Vector2(20, 20), Vector2(36, 34)))
	if not plan.goal.is_empty(): _taken.append(Rect2(at(plan.goal.at) - Vector2(16, 16), Vector2(32, 52)))
	for start: Dictionary in plan.starts: _taken.append(Rect2(at(start.at) - Vector2(11, 11), Vector2(22, 22)))
	for item: Dictionary in plan.floors:
		var rect := box(item.rect)
		var text := "%s  %d cm" % [item.id, int(item.height)]
		if _text_width(text, 13) > rect.size.x - 8.0: text = "%d cm" % int(item.height)
		var words := _free(Rect2(rect.position + Vector2(5, 3), Vector2(_text_width(text, 13) + 2, 16)))
		result.captions.append([[[text, SOFT_INK if item.reached else SOFT_INK.lerp(WATER, 0.4), BODY, 13]], words])
	# Each gate's row, by its crossing.
	var at_gate: Dictionary = {}
	for pair: Dictionary in plan.pairs:
		for gate: Dictionary in pair.gates:
			if not at_gate.has(gate.route): at_gate[gate.route] = {"at": gate.at, "row": []}
			at_gate[gate.route].row.append([pair, _values_note(pair, gate.values)])
	var gate_tiles: Dictionary = {}
	for route: String in at_gate:
		var row: Array = at_gate[route].row
		var width := row.size() * TILE + (row.size() - 1) * 4.0
		var notes: Array = row.filter(func(entry: Array) -> bool: return not str(entry[1]).is_empty())
		var note_width := 0.0
		for entry: Array in notes: note_width = maxf(note_width, _text_width(entry[1], 11) + 4.0)
		var block := Vector2(maxf(width, note_width), TILE + notes.size() * 14.0)
		var spot := _free(Rect2(at(at_gate[route].at) - Vector2(block.x * 0.5, TILE * 0.5), block))
		for index in range(row.size()):
			var centre := spot.position + Vector2((block.x - width) * 0.5 + TILE * 0.5 + index * (TILE + 4.0), TILE * 0.5)
			result.tiles.append([row[index][0], centre])
			if not gate_tiles.has(row[index][0].index): gate_tiles[row[index][0].index] = []
			gate_tiles[row[index][0].index].append(centre)
		for index in range(notes.size()):
			result.captions.append([[[notes[index][1], INK, BODY, 11]], Rect2(spot.position + Vector2(0, TILE + 2 + index * 14.0), Vector2(block.x, 13))])
	# What opens a crossing whose control shows no tile, in words by it.
	for item: Dictionary in plan.crossings:
		if item.get("unlettered", []).is_empty(): continue
		var lines: Array = item.unlettered.map(func(words: String) -> Array: return [words, INK, BODY, 11])
		var rect := box(item.rect)
		result.captions.append([lines, _free(_lines_rect(lines, rect.get_center() - Vector2(_lines_width(lines) * 0.5, 7.5 * lines.size())))])
	# Each control's own tile with a line to every gate tile, then its words.
	for pair: Dictionary in plan.pairs:
		var centre := _free(Rect2(at(pair.at) + Vector2(18, 0), Vector2.ONE * TILE)).get_center()
		result.tiles.append([pair, centre])
		for gate_centre: Vector2 in gate_tiles.get(pair.index, []):
			result.lines.append([centre, gate_centre, Color((pair.colour as Color).darkened(0.2), 0.75)])
	for item: Dictionary in plan.controls:
		var lines: Array = [[str(item.id), SOFT_INK, BODY, 12]]
		if item.has("values"):
			lines.append([" / ".join(item.values.map(func(v: Variant) -> String: return str(v).to_upper() if str(v) == str(item.initial) else str(v))), INK, BODY, 12])
		result.captions.append([lines, _free(_lines_rect(lines, at(item.at) + Vector2(-_lines_width(lines) * 0.5, 20)))])
	for start: Dictionary in plan.starts:
		var words := "%s pip%s" % ["Gold" if start.slot == "p0" else "Teal", " plays first" if start.slot == plan.first_slot else ""]
		var lines: Array = [[words, INK, HEADING, 12]]
		result.captions.append([lines, _free(_lines_rect(lines, at(start.at) + Vector2(14, -8)))])
	return result

## What a gate asks of a selector, when it asks only some of its values.
func _values_note(pair: Dictionary, values: Array) -> String:
	if values.is_empty(): return ""
	for item: Dictionary in plan.controls:
		if item.id == pair.control and item.has("values") and values.size() >= item.values.size(): return ""
	return "%s %s" % [pair.letter, " / ".join(values)]

func _lines_width(lines: Array) -> float:
	var width := 0.0
	for line: Array in lines: width = maxf(width, _text_width(line[0], line[3], line[2]))
	return width

func _lines_rect(lines: Array, top_left: Vector2) -> Rect2:
	return Rect2(top_left, Vector2(_lines_width(lines) + 2, 15.0 * lines.size()))

## The first place for `wanted` clear of everything taken so far, searched
## outward from it in rings; it is then taken.
func _free(wanted: Rect2) -> Rect2:
	for ring in range(0, 16):
		for turn in range(maxi(1, ring * 8)):
			var offset := Vector2.ZERO if ring == 0 else Vector2.from_angle(TAU * float(turn) / float(ring * 8)) * ring * 7.0
			var rect := Rect2(wanted.position + offset, wanted.size)
			if not _taken.any(func(other: Rect2) -> bool: return other.grow(1.0).intersects(rect)):
				_taken.append(rect)
				return rect
	_taken.append(wanted)
	return wanted

# --- Glyphs -----------------------------------------------------------------------------

func _controls() -> void:
	for item: Dictionary in plan.controls:
		var centre := at(item.at)
		match str(item.kind):
			"pad", "ball pad":
				var radius := maxf(item.radius / 100.0 * _scale, 7.0)
				draw_circle(centre, radius, Color(CREAM, 0.9))
				draw_arc(centre, radius, 0.0, TAU, 32, INK, 2.0)
				if item.kind == "ball pad": draw_circle(centre, radius * 0.45, Color("c8806a"))
			"lever":
				draw_rect(Rect2(centre - Vector2(4, 8), Vector2(8, 16)), INK)
				draw_circle(centre + Vector2(0, -8), 5.0, Color("c9a443"))
			"selector":
				draw_circle(centre, 11.0, CREAM)
				draw_arc(centre, 11.0, 0.0, TAU, 32, INK, 2.5)
				for spoke in range(3):
					draw_line(centre, centre + Vector2.from_angle(TAU * float(spoke) / 3.0 - PI / 2.0) * 9.0, INK, 2.0)
		if not str(item.owner).is_empty(): _owner_mark(item.owner, centre + Vector2(-15, -12), 5.5)

## Caption lines on a soft backing in `rect`.
func _place(lines: Array, rect: Rect2) -> void:
	draw_rect(rect.grow(1.5), Color(PAPER, 0.8))
	for index in range(lines.size()):
		_text(lines[index][0], rect.position + Vector2(1, 12 + 15 * index), lines[index][3], lines[index][1], lines[index][2])

func _tile(pair: Dictionary, centre: Vector2) -> void:
	var rect := Rect2(centre - Vector2.ONE * TILE * 0.5, Vector2.ONE * TILE)
	var colour: Color = pair.colour
	draw_rect(rect.grow(1.5), colour.darkened(0.35))
	draw_rect(rect, colour)
	for band in range(int(pair.band)):
		draw_rect(rect.grow(-3.0 - band * 3.0), Color(INK, 0.6), false, 1.0)
	var letter: String = pair.letter
	_text(letter, centre + Vector2(-_text_width(letter, 15, HEADING) * 0.5, 5.5), 15, INK, HEADING)

func _goal() -> void:
	if plan.goal.is_empty(): return
	var centre := at(plan.goal.at)
	var points := PackedVector2Array()
	for index in range(10):
		points.append(centre + Vector2.from_angle(-PI / 2.0 + PI * float(index) / 5.0) * (15.0 if index % 2 == 0 else 7.0))
	draw_colored_polygon(points, OwnerMark.color(str(plan.goal.owner)))
	points.append(points[0])
	draw_polyline(points, INK, 2.0)
	_text("goal", centre + Vector2(-_text_width("goal", 13, HEADING) * 0.5, 30), 13, INK, HEADING)

func _starts() -> void:
	for start: Dictionary in plan.starts:
		var centre := at(start.at)
		var colour := OwnerMark.color(str(start.slot))
		draw_circle(centre, 10.0, colour)
		draw_arc(centre, 10.0, 0.0, TAU, 24, colour.darkened(0.45), 2.0)
		draw_circle(centre + Vector2(-3.5, -1.5), 1.6, INK)
		draw_circle(centre + Vector2(3.5, -1.5), 1.6, INK)

# --- Title and key ------------------------------------------------------------------

func _title(size: Vector2) -> void:
	_text(str(plan.title), Vector2(MARGIN, 44), 30, INK, HEADING)
	_text("Stage %d of %d: %s" % [int(plan.stage_index) + 1, int(plan.stage_count), plan.stage_title], Vector2(MARGIN, 70), 18, SOFT_INK, BODY)
	var note := "Flat map plan, drawn from the stage's definition"
	_text(note, Vector2(size.x - MARGIN - _text_width(note, 13), 44), 13, SOFT_INK, BODY)

func _key(size: Vector2) -> void:
	var y := size.y - KEY_HEIGHT + 30.0
	var x := MARGIN
	_text("Floors", Vector2(x, y - 12), 12, SOFT_INK, HEADING)
	for height: int in _heights():
		draw_rect(Rect2(x, y, 26, 16), _floor_colour(height))
		draw_rect(Rect2(x, y, 26, 16), Color(INK, 0.4), false, 1.0)
		_text("%d cm" % height, Vector2(x + 30, y + 13), 12, INK, BODY)
		x += 30.0 + _text_width("%d cm" % height, 12) + 14.0
	x += 16.0
	_text("Crossings", Vector2(x, y - 12), 12, SOFT_INK, HEADING)
	for sample: Array in [["opens with a control", "gated"], ["always open", "open"], ["kept open from before", "kept"], ["shut this stage", "shut"]]:
		var rect := Rect2(x, y, 26, 16)
		_planks(rect, TIMBER.lerp(WATER, 0.6) if sample[1] == "shut" else TIMBER)
		_crossing_edge(rect, str(sample[1]))
		_text(sample[0], Vector2(x + 30, y + 13), 12, INK, BODY)
		x += 30.0 + _text_width(sample[0], 12) + 14.0
	y += 34.0
	x = MARGIN
	_owner_mark("p0", Vector2(x + 8, y + 8), 6.0)
	_text("the gold pip's", Vector2(x + 20, y + 13), 12, INK, BODY)
	x += 120.0
	_owner_mark("p1", Vector2(x + 8, y + 8), 6.0)
	_text("the teal pip's", Vector2(x + 20, y + 13), 12, INK, BODY)
	x += 120.0
	var faded := Rect2(x, y, 26, 16)
	draw_rect(faded, FLOOR_RAMP[2].lerp(WATER, 0.55))
	_dashed_rect(faded.grow(-2.0), SOFT_INK, 1.5)
	_text("no pip reaches it this stage", Vector2(x + 30, y + 13), 12, INK, BODY)
	x += 30.0 + _text_width("no pip reaches it this stage", 12) + 24.0
	_tile({"letter": "A", "band": 0, "colour": PairTags.colour_of(0)}, Vector2(x + 11, y + 8))
	draw_line(Vector2(x + 24, y + 8), Vector2(x + 70, y + 8), Color(PairTags.colour_of(0).darkened(0.2), 0.75), 2.0, true)
	_tile({"letter": "A", "band": 0, "colour": PairTags.colour_of(0)}, Vector2(x + 83, y + 8))
	_text("a control's letter, and the same letter at every gate it works", Vector2(x + 100, y + 13), 12, INK, BODY)

# --- Helpers ------------------------------------------------------------------------

func _owner_mark(slot: String, centre: Vector2, radius: float) -> void:
	var colour := OwnerMark.color(slot)
	if slot == "p0":
		var diamond := PackedVector2Array([centre + Vector2(0, -radius), centre + Vector2(radius, 0), centre + Vector2(0, radius), centre + Vector2(-radius, 0)])
		draw_colored_polygon(diamond, colour)
		diamond.append(diamond[0])
		draw_polyline(diamond, colour.darkened(0.45), 1.5)
	else:
		draw_arc(centre, radius, 0.0, TAU, 24, colour.darkened(0.2), 3.0)

func _dashed_rect(rect: Rect2, colour: Color, width: float) -> void:
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	for index in range(4): _dashed_line(corners[index], corners[(index + 1) % 4], colour, width, 7.0, 4.0)

func _dashed_line(from: Vector2, to: Vector2, colour: Color, width: float, dash: float, gap: float) -> void:
	var length := from.distance_to(to)
	if length < 0.5: return
	var step := (to - from) / length
	var t := 0.0
	while t < length:
		draw_line(from + step * t, from + step * minf(t + dash, length), colour, width)
		t += dash + gap

func _hatched(rect: Rect2, colour: Color) -> void:
	var outline := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
	var t := -rect.size.y
	while t < rect.size.x:
		var stroke := PackedVector2Array([Vector2(rect.position.x + t, rect.position.y), Vector2(rect.position.x + t + rect.size.y, rect.end.y)])
		for line: PackedVector2Array in Geometry2D.intersect_polyline_with_polygon(stroke, outline): draw_line(line[0], line[line.size() - 1], colour, 1.0)
		t += 8.0
	draw_rect(rect, colour, false, 1.0)

func _text(text: String, at_point: Vector2, size: int, colour: Color, font: Font = BODY) -> void:
	draw_string(font, at_point, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, colour)

static func _text_width(text: String, size: int, font: Font = BODY) -> float:
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
