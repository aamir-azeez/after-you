extends RefCounted
## Empty-state art kit: the two spirits, a few props and the dashed ghost
## cards, drawn straight onto a CanvasItem with no assets. Spirits are the game's
## (spirit_look.gd): the same body proportions, leaf and eye shapes, drawn flat;
## mood comes from the eyes, head tilt and lean.
## A scene is data: rows of [kind, position, options] in a 200 x 120 box
## centred on the origin, scaled to fit the picture slot it is drawn into.
## Everything is drawn in canvas coordinates, so strokes keep one width.

const Look = preload("res://presentation/spirit_look.gd")
const PEACH := Look.PEACH
const MINT := Look.MINT
## Ink for the props' fine lines.
const INK := Color("24433f")
const HEART := Color("f09a94")
const GOLD := Color("f4d77b")
const LINE := Color("eceddb")
const PAPER := Color("f6f1e1")
const PHOTO := Color("2f5f56")
const GRASS := Color("bfe3a6")
const CLIFF := Color("7fae88")
const SAND := Color("e5cf9c")
const STEP := Color("6f9f72")
## "memory" is the player's spirit as a faded recording: paler, so it reads as
## light rather than shadow on a dark page.
const SPIRITS := {"peach": PEACH, "mint": MINT, "memory": Color("f9d9af")}
const BOX := Vector2(200, 120)
## Spirit units per metre of the game's spirit; feet rest on the origin.
const UNIT := 105.0
const GROUND := Look.FOOT_REST.y - Look.FOOT_HALF.y
const HEAD := Vector2(0, -(Look.HEAD_CENTER.y - GROUND) * UNIT)
## The head tilts about the top of the torso.
const NECK := Vector2(0, -(Look.HEAD_CENTER.y - Look.HEAD_HALF.y - GROUND) * UNIT)
## The flat art's names for eyes, as the game's expressions.
const EYES := {"dot": Look.NORMAL, "wide": Look.SURPRISED, "soft": Look.SLEEPY}
## A spirit in a scene is this many scene units per in-game spirit unit.
const SPIRIT_SIZE := 0.42
## The player's spirit on the Solo island block.
const WALKER_SIZE := 0.5
## The faded memory, a little further away on the block.
const MEMORY_SIZE := 0.4
## Half the island block's top face: along its length and across its depth.
const BLOCK_LENGTH := Vector2(62, -15)
const BLOCK_DEPTH := Vector2(26, 15)
## A spirit's feet reach this far either side of its base point, in spirit units.
const FOOT_REACH := 24.0
## Each list's real card, copied by hand (update both together):
## room_hub_screen._add_room_card (154x96 thumbnail, 132x50 action, 14/12 pad),
## friends_screen._friend_row (116 tall, 64 px avatar, 16 pad) and
## replays_flow._replay_row_card (128x72 thumbnail, 28/20 pad). "slot" is the
## picture (thumbnail or avatar); "preview" adds the wide Replays preview card.
const CARDS := {
	"room": {"height": 120.0, "radius": 16.0, "pad": Vector2(14, 12), "slot": Vector2(154, 96), "slot_radius": 8.0, "button": Vector2(132, 50)},
	"friend": {"height": 116.0, "radius": 16.0, "pad": Vector2(16, 16), "slot": Vector2(64, 64), "slot_radius": 32.0, "button": Vector2(48, 48)},
	"replay": {"height": 112.0, "radius": 16.0, "pad": Vector2(28, 20), "slot": Vector2(128, 72), "slot_radius": 10.0, "button": Vector2(96, 50), "preview": true},
}
const SCENES := {
	"invite": [["face", Vector2(-58, 14), {"color": "peach", "look": Vector2(1, -0.2), "tilt": 0.22, "size": 0.62}], ["envelope", Vector2(4, 4), -0.12], ["outline", Vector2(70, 2)], ["sparkle", Vector2(36, -38), 7.0]],
	"finished": [["island", Vector2(0, 24), 150.0], ["flag", Vector2(46, 22)], ["spirit", Vector2(-24, 26), {"color": "peach", "eyes": "happy", "sit": true, "lean": 0.12, "tilt": 0.22}], ["spirit", Vector2(4, 26), {"color": "mint", "eyes": "happy", "sit": true, "lean": -0.12, "tilt": -0.22}], ["sparkle", Vector2(-64, -30), 6.0], ["sparkle", Vector2(70, -46), 5.0]],
	"friend": [["face", Vector2(-4, 4), {"color": "mint", "eyes": "happy", "size": 2.0}], ["heart", Vector2(72, -40), 16.0]],
	"friend_next": [["face", Vector2(66, 6), {"color": "peach", "eyes": "wide", "look": Vector2(-1, 0), "tilt": -0.3, "size": 1.5}]],
	"footprints": [["walk", Vector2(0, 8), {"from": Vector2(-0.5, 0.45), "to": Vector2(0.55, -0.4)}]],
	"polaroid": [["polaroid", Vector2(-10, 4), 0.08], ["heart", Vector2(62, -26), 11.0], ["sparkle", Vector2(66, 26), 7.0]],
	# The empty Your duels list (duels_screen.gd EMPTY_ART): after the race, both pairs sitting together on one island, then a hug across pairs, friends first.
	"duel_together": [["island", Vector2(0, 28), 176.0], ["spirit", Vector2(-54, 30), {"color": "peach", "eyes": "happy", "sit": true, "lean": 0.1, "tilt": 0.2, "size": 0.34}], ["spirit", Vector2(-28, 30), {"color": "mint", "eyes": "happy", "sit": true, "lean": 0.06, "tilt": 0.1, "size": 0.34}], ["spirit", Vector2(28, 30), {"color": "peach", "eyes": "happy", "sit": true, "lean": -0.06, "tilt": -0.1, "size": 0.34}], ["spirit", Vector2(54, 30), {"color": "mint", "eyes": "happy", "sit": true, "lean": -0.1, "tilt": -0.2, "size": 0.34}], ["heart", Vector2(0, -22), 9.0], ["sparkle", Vector2(-76, -34), 5.0], ["sparkle", Vector2(78, -40), 5.0]],
	"duel_hug": [["spirit", Vector2(-19, 32), {"color": "peach", "eyes": "happy", "lean": 0.16, "tilt": 0.2}], ["spirit", Vector2(19, 32), {"color": "mint", "eyes": "happy", "lean": -0.16, "tilt": -0.2}], ["heart", Vector2(0, -34), 11.0], ["sparkle", Vector2(-48, -20), 5.0], ["sparkle", Vector2(50, -30), 5.0]],
	# The empty Open duels column, three ways (duels_screen.gd OPEN_EMPTY_ART), drawn in the round friend picture.
	"open_letter": [["envelope", Vector2(0, 4), -0.14], ["sparkle", Vector2(36, -34), 9.0]],
	"open_peek": [["face", Vector2(-17, 4), {"color": "peach", "eyes": "wide", "look": Vector2(1, -0.3), "tilt": 0.2, "size": 0.72}], ["face", Vector2(17, 7), {"color": "mint", "eyes": "wide", "look": Vector2(1, -0.3), "tilt": -0.1, "size": 0.72}]],
	"open_hope": [["face", Vector2(-5, 6), {"color": "mint", "look": Vector2(0.6, -0.8), "tilt": 0.12, "size": 1.2}], ["sparkle", Vector2(30, -30), 9.0]],
	# The Play with your friend icon: two happy faces cheek to cheek, mint behind,
	# and a heart. Rows with "squish" or "pop" react to the scene state (scene()).
	"friends_squeeze": [["face", Vector2(21.5, 7), {"color": "mint", "eyes": "happy", "tilt": -0.18, "size": 0.66, "squish": -1.0}], ["face", Vector2(-21.5, 7), {"color": "peach", "eyes": "happy", "tilt": 0.18, "size": 0.66, "squish": 1.0}], ["heart", Vector2(40, -28), 8.5, {"pop": 0.28, "lift": Vector2(-2, -3)}]],
}
## Scenes drawn loose on a light surface rather than in a list picture: their
## own box, and a thin ink edge (box units) round each spirit and prop so
## peach, mint and pink hold on cream.
## The empty Open duels column's scenes fill their small round picture, drawn larger than a wide card's scene.
const SCENE_LOOKS := {"friends_squeeze": {"box": Vector2(120, 96), "edge": 2.8}, "open_letter": {"box": Vector2(110, 110)}, "open_peek": {"box": Vector2(110, 110)}, "open_hope": {"box": Vector2(110, 110)}}
## A squish (scene state "squish" 0..1) at its fullest, for rows with a
## "squish" direction (+1 toward +x): each face slides in, tips further toward
## the other and squashes about its chin. A heart row with "pop" grows by that
## fraction and moves by "lift".
const SQUISH_SHIFT := 6.5
const SQUISH_TIP := 0.07
const SQUISH_SQUASH := Vector2(0.05, 0.04)
static var _circle := PackedVector2Array()

## Draws a scene into a slot rect, keeping the scene's aspect. State, read by
## the rows that react: "eyes" (the squishing spirits' expression) and
## "squish" (0 at rest to 1).
static func scene(ci: CanvasItem, scene_id: String, slot: Rect2, state: Dictionary = {}) -> void:
	var look: Dictionary = SCENE_LOOKS.get(scene_id, {})
	var box: Vector2 = look.get("box", BOX)
	var s := minf(slot.size.x / box.x, slot.size.y / box.y)
	var at := Transform2D(0.0, Vector2(s, s), 0.0, slot.get_center())
	var edge: float = look.get("edge", 0.0) * s
	for row: Array in SCENES.get(scene_id, []):
		var pos: Vector2 = row[1]
		match row[0]:
			"spirit", "face":
				var posed := pose(row, state)
				var options: Dictionary = posed.options
				if edge > 0.0:
					if is_same(options, row[2]): options = options.duplicate()
					options.edge = edge
				spirit(ci, at * posed.place, options, row[0] == "face")
			"outline": outline(ci, at, pos)
			"envelope": envelope(ci, at * Transform2D(row[2], pos))
			"island": island(ci, at, pos, row[2])
			"flag": flag(ci, at, pos)
			"heart":
				var posed := pose(row, state)
				heart(ci, at, posed.pos, posed.size, edge)
			"sparkle": sparkle(ci, at, pos, row[2])
			"walk": walk(ci, at, pos, row[2])
			"polaroid": polaroid(ci, at * Transform2D(row[2], Vector2(1.3, 1.3), 0.0, pos))

## Where a spirit or heart row lands for a scene state: {place, options} for a
## spirit (its transform in scene units, and its options with the state's eyes
## and squish tilt), {pos, size} for a heart. Rows with no "squish" or "pop"
## come back as written.
static func pose(row: Array, state: Dictionary) -> Dictionary:
	var pos: Vector2 = row[1]
	var squish := clampf(float(state.get("squish", 0.0)), 0.0, 1.0)
	if row[0] == "heart":
		var pop: Dictionary = row[3] if row.size() > 3 else {}
		return {"pos": pos + pop.get("lift", Vector2.ZERO) * squish, "size": float(row[2]) * (1.0 + pop.get("pop", 0.0) * squish)}
	var options: Dictionary = row[2]
	if not options.has("squish"): return {"place": _place(pos, options), "options": options}
	options = options.duplicate()
	var toward: float = options.squish
	if state.has("eyes"): options.eyes = state.eyes
	options.tilt = options.get("tilt", 0.0) + toward * SQUISH_TIP * squish
	# Squashed about the chin, so the chin stays put.
	var rise := SQUISH_SQUASH.y * squish * Look.HEAD_HALF.y * UNIT * float(options.get("size", SPIRIT_SIZE))
	var squash := Vector2(1.0 - SQUISH_SQUASH.x * squish, 1.0 + SQUISH_SQUASH.y * squish)
	return {"place": _place(pos + Vector2(toward * SQUISH_SHIFT * squish, -rise), options) * Transform2D(0.0, squash, 0.0, Vector2.ZERO), "options": options}

static func _place(pos: Vector2, options: Dictionary) -> Transform2D:
	var size: float = options.get("size", SPIRIT_SIZE)
	return Transform2D(0.0, Vector2(size, size), 0.0, pos)

## One spirit with its feet at the origin, or only its head centred on the
## origin (face). Options: color, alpha, eyes (dot, wide, happy, soft, or any
## spirit_look expression), look (where the eyes glance), tilt, lean, sit, and
## edge (an ink outline this many canvas pixels outside the whole spirit).
static func spirit(ci: CanvasItem, at: Transform2D, options: Dictionary, face := false) -> void:
	var color: Color = SPIRITS[options.get("color", "peach")]
	var alpha: float = options.get("alpha", 1.0)
	var tilt: float = options.get("tilt", 0.0)
	var head := at * Transform2D(tilt, Vector2.ZERO) * Transform2D(0.0, -HEAD)
	# [transform, outline, colour], back to front.
	var parts: Array = []
	if not face:
		var body := at * Transform2D(options.get("lean", 0.0), Vector2.ZERO)
		head = body * Transform2D(tilt, NECK) * Transform2D(0.0, -NECK)
		if not options.get("sit", false):
			for side: float in [-1.0, 1.0]: parts.append([at, _rounded(_flat(Look.FOOT_REST + Vector3(side * Look.FOOT_SPREAD, 0, 0)), _flat_size(Look.FOOT_HALF), 2.0), color.darkened(Look.FOOT_SHADE + 0.08)])
		parts.append([body, _rounded(_flat(Look.TORSO_CENTER), _flat_size(Look.TORSO_HALF), Look.TORSO_POWER), color.darkened(0.04)])
	parts.append([head * Transform2D(-Look.LEAF_LEAN, _flat(Look.LEAF_PIVOT)), _leaf(), Look.LEAF])
	parts.append([head, _rounded(HEAD, _flat_size(Look.HEAD_HALF), Look.HEAD_POWER), color])
	var edge: float = options.get("edge", 0.0)
	if edge > 0.0:
		for part: Array in parts: edged(ci, part[0], part[1], edge, Color(INK, alpha))
	for part: Array in parts: fill(ci, part[0], part[1], Color(part[2], alpha))
	var look: Vector2 = options.get("look", Vector2.ZERO)
	var name := str(options.get("eyes", "dot"))
	var expression: StringName = EYES.get(name, StringName(name))
	if not Look.has(expression): expression = Look.NORMAL
	for index: int in range(2):
		var anchor := HEAD + Vector2(Look.EYE_X * (-1.0 if index == 0 else 1.0), -Look.EYE_Y) * UNIT + look * Vector2(4, 2)
		var eye := head * Transform2D(0.0, Vector2(UNIT, -UNIT), 0.0, anchor)
		var shape: Dictionary = Look.eye_contours(expression, index)
		for polygon: PackedVector2Array in shape.outer: fill(ci, eye, polygon, Color(Look.CREAM, alpha))
		for polygon: PackedVector2Array in shape.pupil: fill(ci, eye, polygon, Color(Look.PUPIL, alpha))
		var width := maxf(1.0, shape.width * UNIT * at.get_scale().x)
		for line: PackedVector2Array in shape.strokes:
			var points := eye * line
			ci.draw_polyline(points, Color(Look.PUPIL, alpha), width, true)
			# Round ends, as the face shader draws them.
			ci.draw_circle(points[0], width * 0.5, Color(Look.PUPIL, alpha), true, -1.0, true)
			ci.draw_circle(points[points.size() - 1], width * 0.5, Color(Look.PUPIL, alpha), true, -1.0, true)

## A point of the game's spirit (metres, facing the camera) in spirit units.
static func _flat(point: Vector3) -> Vector2:
	return Vector2(point.x, -(point.y - GROUND)) * UNIT

static func _flat_size(half: Vector3) -> Vector2:
	return Vector2(half.x, half.y) * UNIT

## A rounded box outline: |x/a|^p + |y/b|^p = 1 (p 2 is an ellipse).
static func _rounded(center: Vector2, half: Vector2, power: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for step: int in range(72):
		var direction := Vector2.from_angle(step * TAU / 72.0)
		var reach := pow(pow(absf(direction.x / half.x), power) + pow(absf(direction.y / half.y), power), -1.0 / power)
		points.append(center + direction * reach)
	return points

## The leaf's outline, stalk at the origin, pointing up.
static func _leaf() -> PackedVector2Array:
	var points := PackedVector2Array()
	var steps := 12
	for step: int in range(steps + 1):
		var t := float(step) / steps
		points.append(Vector2(Look.leaf_half_width(t) * Look.LEAF_WIDTH * 0.5, -t * Look.LEAF_LENGTH) * UNIT)
	for step: int in range(steps - 1, 0, -1):
		var t := float(step) / steps
		points.append(Vector2(-Look.leaf_half_width(t) * Look.LEAF_WIDTH * 0.5, -t * Look.LEAF_LENGTH) * UNIT)
	return points

## The friend who is not there yet: a dashed head with a question mark.
static func outline(ci: CanvasItem, at: Transform2D, pos: Vector2) -> void:
	dashed(ci, at * ellipse(pos, Vector2(23, 21)), Color(MINT, 0.9), 1.6, 5.0, 4.0)
	var hook := PackedVector2Array()
	for step: int in range(9): hook.append(pos + Vector2(0, -6) + Vector2.from_angle(PI + step * PI * 0.17) * 6.0)
	hook.append(pos + Vector2(0, 4))
	stroke(ci, at, hook, Color(MINT, 0.95), 3.0)
	fill(ci, at, ellipse(pos + Vector2(0, 10), Vector2(1.9, 1.9)), Color(MINT, 0.95))

static func envelope(ci: CanvasItem, at: Transform2D) -> void:
	var paper := Rect2(-38, -25, 76, 50)
	fill(ci, at, round_rect(paper, 4.0), PAPER)
	stroke(ci, at, PackedVector2Array([Vector2(-36, -22), Vector2(0, 4), Vector2(36, -22)]), Color(INK, 0.35), 2.0)
	stroke(ci, at, PackedVector2Array([Vector2(-36, 23), Vector2(-10, 2)]), Color(INK, 0.18), 1.6)
	stroke(ci, at, PackedVector2Array([Vector2(36, 23), Vector2(10, 2)]), Color(INK, 0.18), 1.6)
	heart(ci, at, Vector2(0, 3), 7.0)

## The soft rounded island: grass over a rounded earth underside.
static func island(ci: CanvasItem, at: Transform2D, pos: Vector2, width: float) -> void:
	var half := width * 0.5
	var under := PackedVector2Array()
	for step: int in range(17): under.append(pos + Vector2(cos(PI * step / 16.0) * half * (1.0 - 0.25 * sin(PI * step / 16.0)), sin(PI * step / 16.0) * width * 0.24))
	fill(ci, at, under, CLIFF)
	fill(ci, at, ellipse(pos, Vector2(half, width * 0.1)), GRASS)

static func flag(ci: CanvasItem, at: Transform2D, pos: Vector2) -> void:
	stroke(ci, at, PackedVector2Array([pos, pos + Vector2(0, -56)]), LINE, 2.6)
	fill(ci, at, PackedVector2Array([pos + Vector2(1, -56), pos + Vector2(26, -48), pos + Vector2(1, -40)]), GOLD)

## A heart; edge as spirit()'s.
static func heart(ci: CanvasItem, at: Transform2D, pos: Vector2, size: float, edge := 0.0) -> void:
	var parts: Array[PackedVector2Array] = []
	for side: float in [-1.0, 1.0]: parts.append(ellipse(pos + Vector2(side * 0.5, -0.3) * size, Vector2(0.56, 0.56) * size))
	parts.append(PackedVector2Array([pos + Vector2(-1.04, -0.1) * size, pos + Vector2(1.04, -0.1) * size, pos + Vector2(0, 1.0) * size]))
	if edge > 0.0:
		for part: PackedVector2Array in parts: edged(ci, at, part, edge, INK)
	for part: PackedVector2Array in parts: fill(ci, at, part, HEART)

static func sparkle(ci: CanvasItem, at: Transform2D, pos: Vector2, size: float) -> void:
	var points := PackedVector2Array()
	for step: int in range(8): points.append(pos + Vector2.from_angle(step * PI * 0.25 - PI * 0.5) * size * (1.0 if step % 2 == 0 else 0.3))
	fill(ci, at, points, GOLD)

## The game's island block: a grass top over two sandy sides, flat shaded.
## Points on its top face are given as (along, across) in -1..1.
static func block_point(pos: Vector2, on_top: Vector2) -> Vector2:
	return pos + BLOCK_LENGTH * on_top.x + BLOCK_DEPTH * on_top.y

static func block_top(pos: Vector2) -> PackedVector2Array:
	return PackedVector2Array([block_point(pos, Vector2(-1, -1)), block_point(pos, Vector2(1, -1)), block_point(pos, Vector2(1, 1)), block_point(pos, Vector2(-1, 1))])

## The player's spirit near the front of the block, glancing back at its faded
## memory walking off at the far end, six footprints between them. Returns the
## spirit, memory and step points, which tests keep on the top face.
static func walk_points(pos: Vector2, options: Dictionary) -> Dictionary:
	var you := block_point(pos, options.from)
	var memory := block_point(pos, options.to)
	var steps: Array[Vector2] = []
	for step: int in range(6): steps.append(you.lerp(memory, 0.14 + 0.72 * step / 5.0))
	return {"you": you, "memory": memory, "steps": steps}

static func walk(ci: CanvasItem, at: Transform2D, pos: Vector2, options: Dictionary) -> void:
	var top := block_top(pos)
	var drop := Vector2(0, 20)
	fill(ci, at, PackedVector2Array([top[3], top[2], top[2] + drop, top[3] + drop]), SAND)
	fill(ci, at, PackedVector2Array([top[0], top[3], top[3] + drop, top[0] + drop]), SAND.darkened(0.12))
	fill(ci, at, top, GRASS)
	var points := walk_points(pos, options)
	var heading: Vector2 = (points.memory - points.you).normalized()
	for step: int in range(6):
		var side := heading.orthogonal() * (2.4 if step % 2 == 0 else -2.4)
		fill(ci, at * Transform2D(heading.angle(), points.steps[step] + side), ellipse(Vector2.ZERO, Vector2(3.2, 2.0)), Color(STEP, 0.3 + 0.08 * step))
	spirit(ci, at * _place(points.memory, {"size": MEMORY_SIZE}), {"color": "memory", "alpha": 0.4, "look": Vector2(1, -0.4), "lean": 0.1})
	sparkle(ci, at, points.memory + Vector2(18, -36), 5.0)
	spirit(ci, at * _place(points.you, {"size": WALKER_SIZE}), {"color": "peach", "look": Vector2(1, -0.6), "tilt": 0.16})

## A taped photo of both spirits smiling.
static func polaroid(ci: CanvasItem, at: Transform2D) -> void:
	fill(ci, at, round_rect(Rect2(-34, -40, 68, 80), 3.0), PAPER)
	fill(ci, at, round_rect(Rect2(-28, -34, 56, 52), 1.5), PHOTO)
	for pair: Array in [[-12.0, "peach", 0.12], [12.0, "mint", -0.12]]:
		spirit(ci, at * Transform2D(0.0, Vector2(0.36, 0.36), 0.0, Vector2(pair[0], -6)), {"color": pair[1], "eyes": "happy", "tilt": pair[2]}, true)
	fill(ci, at * Transform2D(-0.12, Vector2(0, -41)), round_rect(Rect2(-15, -5, 30, 10), 1.0), Color(LINE, 0.6))

## Something passing from one row's picture to another's. "plane": a paper
## plane on a dotted trail, leaving the top of one picture and arriving just
## under the other's, clear of the row text.
static func link(ci: CanvasItem, kind: String, from_slot: Rect2, to_slot: Rect2) -> void:
	match kind:
		"plane": plane_trail(ci, Vector2(from_slot.end.x + 6, from_slot.position.y - 4), Vector2(to_slot.end.x + 24, to_slot.end.y + 4), -14.0)

static func plane_trail(ci: CanvasItem, from: Vector2, to: Vector2, bow: float) -> void:
	var control := (from + to) * 0.5 + Vector2(bow, 0)
	var dots := 7
	for step: int in range(dots):
		var t := float(step) / dots
		var point := from.lerp(control, t).lerp(control.lerp(to, t), t)
		fill(ci, Transform2D.IDENTITY, ellipse(point, Vector2(1.6, 1.6)), Color(LINE, 0.25 + 0.4 * t))
	var at := Transform2D((to - control).angle(), to)
	fill(ci, at, PackedVector2Array([Vector2(12, 0), Vector2(-10, -8), Vector2(-4, 1)]), PAPER)
	fill(ci, at, PackedVector2Array([Vector2(12, 0), Vector2(-4, 1), Vector2(-7, 7)]), PAPER.darkened(0.22))

## A ghost card: dashed outlines of the card, its picture slot and its button,
## plus faint text bars unless the card carries the real text.
static func ghost_card(ci: CanvasItem, spec: Dictionary, rect: Rect2, fade: float, bars: bool) -> Dictionary:
	var parts := card_parts(spec, rect)
	dashed(ci, round_rect(rect, spec.radius), Color(LINE, 0.3 * fade), 1.5, 7.0, 6.0)
	if parts.has("slot"): dashed(ci, round_rect(parts.slot, spec.slot_radius), Color(LINE, 0.22 * fade), 1.5, 5.0, 5.0)
	if parts.has("button"): dashed(ci, round_rect(parts.button, minf(14.0, parts.button.size.y * 0.5)), Color(LINE, 0.18 * fade), 1.5, 5.0, 5.0)
	if bars:
		var text: Rect2 = parts.text
		for line: Vector3 in [Vector3(0.62, 14, -18), Vector3(0.38, 10, 8)]:
			var bar := Rect2(text.position.x, text.get_center().y + line.z, text.size.x * line.x, line.y)
			fill(ci, Transform2D.IDENTITY, round_rect(bar, line.y * 0.5), Color(LINE, 0.07 * fade))
	return parts

## The wide Replays preview card (replays_flow._begin_replay_split): a picture
## over the text, with the full-width button outline at the bottom.
static func ghost_preview(ci: CanvasItem, panel: Rect2, picture: Rect2) -> void:
	dashed(ci, round_rect(panel, 20.0), Color(LINE, 0.3), 1.5, 7.0, 6.0)
	dashed(ci, round_rect(picture, 16.0), Color(LINE, 0.22), 1.5, 5.0, 5.0)
	var inner := panel.grow(-16.0)
	dashed(ci, round_rect(Rect2(inner.position.x, inner.end.y - 50, inner.size.x, 50), 14.0), Color(LINE, 0.18), 1.5, 5.0, 5.0)

## Where a card's picture slot, text and button sit, as in the real card.
## Narrow cards drop the slot and button so the text keeps its room.
static func card_parts(spec: Dictionary, rect: Rect2) -> Dictionary:
	var pad: Vector2 = spec.pad
	var slot: Vector2 = spec.slot
	var button: Vector2 = spec.button
	var inner := rect.grow_individual(-pad.x, -pad.y, -pad.x, -pad.y)
	var parts := {"text": inner}
	if inner.size.x - slot.x - button.x - 24.0 >= 180.0:
		parts.slot = Rect2(Vector2(inner.position.x, inner.get_center().y - slot.y * 0.5), slot)
		parts.button = Rect2(Vector2(inner.end.x - button.x, inner.get_center().y - button.y * 0.5), button)
		parts.text = Rect2(inner.position.x + slot.x + 12.0, inner.position.y, inner.size.x - slot.x - button.x - 24.0, inner.size.y)
	return parts

static func ellipse(center: Vector2, radius: Vector2) -> PackedVector2Array:
	if _circle.is_empty():
		for step: int in range(32): _circle.append(Vector2.from_angle(step * TAU / 32.0))
	return Transform2D(0.0, radius, 0.0, center) * _circle

static func round_rect(rect: Rect2, radius: float) -> PackedVector2Array:
	var r := minf(radius, minf(rect.size.x, rect.size.y) * 0.5)
	var points := PackedVector2Array()
	var corners := [Vector2(rect.end.x - r, rect.position.y + r), Vector2(rect.end.x - r, rect.end.y - r), Vector2(rect.position.x + r, rect.end.y - r), Vector2(rect.position.x + r, rect.position.y + r)]
	for corner: int in range(4):
		for step: int in range(7): points.append(corners[corner] + Vector2.from_angle(-PI * 0.5 + (corner + step / 6.0) * PI * 0.5) * r)
	return points

## A filled shape with a one-pixel antialiased edge.
static func fill(ci: CanvasItem, at: Transform2D, points: PackedVector2Array, color: Color) -> void:
	var placed := at * points
	ci.draw_colored_polygon(placed, color)
	placed.append(placed[0])
	ci.draw_polyline(placed, color, 1.0, true)

## A shape grown `edge` canvas pixels, round at the corners: drawn under the
## shape's own fill, it leaves a thin edge.
static func edged(ci: CanvasItem, at: Transform2D, points: PackedVector2Array, edge: float, color: Color) -> void:
	for grown: PackedVector2Array in Geometry2D.offset_polygon(at * points, edge, Geometry2D.JOIN_ROUND):
		fill(ci, Transform2D.IDENTITY, grown, color)

static func stroke(ci: CanvasItem, at: Transform2D, points: PackedVector2Array, color: Color, width: float) -> void:
	ci.draw_polyline(at * points, color, maxf(1.0, width * at.get_scale().x), true)

## A closed dashed outline in canvas pixels, drawn as one multiline.
static func dashed(ci: CanvasItem, points: PackedVector2Array, color: Color, width: float, dash: float, gap: float) -> void:
	var segments := PackedVector2Array()
	var phase := 0.0
	for index: int in range(points.size()):
		var a := points[index]
		var b := points[(index + 1) % points.size()]
		var length := a.distance_to(b)
		var along := 0.0
		while along < length:
			var end := minf(length, along + (dash if phase < dash else dash + gap) - phase)
			if phase < dash:
				segments.append(a.lerp(b, along / length))
				segments.append(a.lerp(b, end / length))
			phase = fmod(phase + end - along, dash + gap)
			along = end
	if not segments.is_empty(): ci.draw_multiline(segments, color, width, true)
