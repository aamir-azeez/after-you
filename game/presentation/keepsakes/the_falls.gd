extends "res://presentation/keepsakes/keepsake_builder.gd"
## The Falls keepsake, the Mill Wheel, from the Blender kit model keepsake_mill
## (claude-20261010/tools/blender/models/keepsake_mill.py): a stone mill pool
## with the big wheel standing in it, fed by a trough from a stone tank, and
## the mill house beside it with a loft ledge and stone steps. Walking up to
## the plank sets it off: the pip walks out and steps into the bucket at the
## wheel's foot, the trough spills past the wheel into the pool, the wheel
## turns and lifts the pip to the loft ledge, and the pip hops down the steps
## while the wheel comes round. A tap turns it without the pip.
## The bucket rides a plane RIDE_Z in front of the wheel and the pip a pip's
## depth clear of its spokes; the ledge ends left of the widest the ride
## reaches, so the pip rises past it and steps across.
## Together: a mint basket rides a line up to the tank as the wheel turns.
## Hard: the plank becomes a rope bridge from a slate footing that sways.
## Together Hard: a gold rainbow stands in the spray over the pool.
const P = preload("res://presentation/keepsakes/keepsake_parts.gd")
const Models = preload("res://presentation/kit/models.gd")
const SoftMist = preload("res://presentation/kit/soft_mist.gd")
const MODEL := "res://assets/models/keepsake_mill.glb"
const COLORS := {"timber": Color("8a6b4e"), "timber_light": Color("b08a62"), "timber_dark": Color("6b5038"), "iron": Color("4f5458"),
	"stone": P.STONE, "stone_light": P.STONE_LIGHT, "plaster": P.CREAM, "roof": P.ROOF, "water": P.TIDE, "glass": P.LAMP_OFF,
	"rope": Color("d1b98c"), "slate": P.SLATE, "mint": P.MINT, "mint_deep": P.MINT_DEEP}
## The model's measures (keepsake_mill.py): the axle, the pool's water, the
## bucket's plane and the radius its floor rides at, the loft ledge's top, the
## steps' tops and where they stand, the plank's top, the Hard bridge's ends.
const AXLE := Vector3(0.0, 1.0, 0.0)
const WATER := 0.1
const RIDE_Z := 0.6
const RIDE_R := 0.78
## The bucket's floor over the circle's own point, so at the foot it stands
## level with the pool wall's top.
const SEAT_LIFT := 0.05
const LEDGE_TOP := 1.42
## Where the pip stands on the ledge: a pip's half width out from the house.
const LEDGE_SPOT := Vector3(-1.36, LEDGE_TOP, RIDE_Z + 0.02)
## Where it walks to before it steps down: the ledge's front, toes at its edge.
const LEDGE_EDGE := Vector3(-1.4, LEDGE_TOP, 0.88)
const STEP_X := -1.44
const STEPS: Array[float] = [1.12, 0.84, 0.56, 0.28]
const STEP_Z0 := 1.09
const STEP_DEPTH := 0.28
## The pip stands at the front of each step, a torso's depth out from the
## higher step (or the ledge) behind it, so it never stands in that riser.
const STEP_STAND := 0.22
## Off the last step sideways onto the grass, clear of the steps.
const LANDING := Vector3(-1.95, 0.0, 2.15)
const PLANK_TOP := 0.29
const BRIDGE_LAND := 1.62
const BRIDGE_END := 0.3
const BRIDGE_SAG := 0.025
const BRIDGE_NEAR := BRIDGE_LAND - 0.14
const BRIDGE_FAR := 0.86
## Together: the basket line from its mint post's top to the tank's hook.
const POST_TOP := Vector3(1.95, 1.95, 1.25)
const HOOK := Vector3(0.66, 2.05, -1.05)
## Together Hard: the rainbow standing in the pool's spray.
const RAINBOW := Vector3(1.2, WATER, 0.72)
const RAINBOW_R := 0.4
const RAINBOW_YAW := 0.59
## The tap: the pip walks out (APPROACH), the wheel turns once (WHEEL_TIME),
## the pip rides until its bucket is level with the ledge and steps off.
const APPROACH := 1.05
const WHEEL_TIME := 2.75
const HOP := 0.3
const STEP_HOP := 0.22

func build(root: Node3D, state: Dictionary) -> Dictionary:
	for part: String in ["mill_house", "mill_tank", "mill_frame", "mill_pool"]: Models.still(MODEL, part, COLORS, root)
	var wheel := P.pivot(root, AXLE, "Wheel")
	Models.moving(MODEL, "mill_rim", COLORS, wheel, false)
	var seat := P.pivot(root, _seat(0.0), "Seat")
	Models.moving(MODEL, "mill_seat", COLORS, seat, false)
	var parts := {"wheel": wheel, "pour": _pour(root), "seat": seat}
	if state.get("hard", false):
		P.plinth(root, 0.96, 0.36, Vector3(0, 0, BRIDGE_LAND))
		# It hangs from its hand ropes: it sways about a point over its deck.
		var bridge := P.pivot(root, Vector3(0, 1.2, 1.25), "Bridge")
		var span := Models.still(MODEL, "mill_bridge", COLORS, bridge)
		span.position = -bridge.position
		parts.bridge = bridge
	else:
		Models.still(MODEL, "mill_plank", COLORS, root)
	if state.get("together", false):
		Models.still(MODEL, "basket_post", COLORS, root)
		var basket := P.pivot(root, _basket(0.12), "Basket")
		Models.moving(MODEL, "mill_basket", COLORS, basket, false)
		parts.basket = basket
	if state.get("top", false):
		var rainbow := P.pivot(root, RAINBOW, "Rainbow")
		rainbow.rotation = Vector3(PI / 2, RAINBOW_YAW, 0)
		P.node(rainbow, P.torus(RAINBOW_R, 0.06), P.gold(), Vector3.ZERO)
		P.node(rainbow, P.torus(RAINBOW_R - 0.075, 0.05), P.mat(P.GOLD), Vector3.ZERO)
		P.node(rainbow, P.torus(RAINBOW_R - 0.14, 0.04), P.mat(P.PEACH), Vector3.ZERO)
		var foot := Vector3(cos(RAINBOW_YAW), 0, -sin(RAINBOW_YAW)) * RAINBOW_R
		for side: float in [-1.0, 1.0]: P.box(root, Vector3(0.15, 0.14, 0.15), P.STONE_LIGHT, RAINBOW + foot * side + Vector3(0, -0.03, 0))
		parts.top = rainbow
	return parts

## The water spilling over the trough's side, down outside the wheel's rim
## into the pool, with foam and spray where it lands. Shown while it turns.
func _pour(root: Node3D) -> Node3D:
	var pour := P.pivot(root, Vector3.ZERO, "Pour")
	pour.visible = false
	# Down the right of the wheel, a hand's width clear of its buckets (radius 0.95).
	var points: Array[Vector3] = [Vector3(0.47, 2.15, 0), Vector3(0.62, 2.13, 0), Vector3(0.8, 2.02, 0), Vector3(0.96, 1.75, 0), Vector3(1.07, 1.3, 0),
		Vector3(1.1, 0.7, 0), Vector3(1.1, WATER, 0)]
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := Vector3(0, 0, 0.12)
	for index in range(points.size() - 1):
		var a := points[index]
		var b := points[index + 1]
		for corner: Vector3 in [a - half, b - half, b + half, a - half, b + half, a + half]: tool.add_vertex(corner)
	tool.generate_normals()
	P.node(pour, tool.commit(), P.clear(P.TIDE, 0.78), Vector3.ZERO)
	P.node(pour, P.low_sphere(0.16, 0.03), P.mat(P.SNOW), Vector3(1.1, WATER + 0.01, 0), Vector3.ZERO, Vector3(1.3, 1, 1.1))
	SoftMist.build([[Vector3(1.12, 0.22, 0.12), Vector2(0.6, 0.38), "front"], [Vector3(1.12, WATER + 0.02, 0.0), Vector2(0.55, 0.45), "up"]], Color(0.97, 0.99, 0.99, 0.6), pour)
	return pour

func base_time() -> float:
	return APPROACH + WHEEL_TIME

func upgrade_time(_beat: String) -> float:
	return 0.5

func _basket(t: float) -> Vector3:
	return POST_TOP.lerp(HOOK, t)

## The bucket's floor (where the pip's feet stand) at `angle` round the axle.
static func _on_wheel(angle: float) -> Vector3:
	return Vector3(AXLE.x + cos(angle) * RIDE_R, AXLE.y + sin(angle) * RIDE_R + SEAT_LIFT, RIDE_Z)

## The bucket over the wheel's one turn, `u` 0 to 1: from its rest at the foot
## up the left side, over the top and round to the foot again.
static func _seat(u: float) -> Vector3:
	return _on_wheel(-PI / 2 - TAU * u)

## How far round the turn the bucket stands level with the ledge.
static func step_off() -> float:
	var level := asin((LEDGE_TOP - AXLE.y - SEAT_LIFT) / RIDE_R)
	return _turn_to(PI - level)

## The share of the turn from the foot (-PI/2) clockwise to `angle`.
static func _turn_to(angle: float) -> float:
	return fposmod(-PI / 2 - angle, TAU) / TAU

## The pip's way out to the bucket: along the plank (or the Hard bridge's
## deck) from where it stood, each piece [callable, seconds].
static func approach(state: Dictionary, from: Vector3) -> Array:
	var bucket := _seat(0.0)
	if state.get("hard", false):
		var below := Vector3(0, 0, BRIDGE_LAND + 0.48)
		var footing := Vector3(0, P.PLINTH_TOP, BRIDGE_LAND)
		var deck := func(t: float) -> Vector3:
			var z := lerpf(BRIDGE_NEAR, BRIDGE_FAR + 0.1, t)
			var along := (BRIDGE_NEAR - z) / (BRIDGE_NEAR - BRIDGE_FAR)
			return Vector3(0, BRIDGE_END - BRIDGE_SAG * sin(clampf(along, 0.0, 1.0) * PI), z)
		var onto := func(t: float) -> Vector3: return footing.lerp(deck.call(0.0), t)
		return [[func(t: float) -> Vector3: return from.lerp(below, t), 0.15], [Anim.hop_leg(below, footing, 0.14), HOP], [onto, 0.05],
			[deck, 0.25], [Anim.hop_leg(deck.call(1.0), bucket, 0.12), HOP]]
	var foot := Vector3(0, 0, 1.5)
	var board := Vector3(0, PLANK_TOP, 1.12)
	var end := Vector3(0, PLANK_TOP, 0.95)
	return [[func(t: float) -> Vector3: return from.lerp(foot, t), 0.3], [Anim.hop_leg(foot, board, 0.14), HOP],
		[func(t: float) -> Vector3: return board.lerp(end, t), 0.15], [Anim.hop_leg(end, bucket, 0.12), HOP]]

## A hop down one step: out over the edge first, then down, so the step it
## leaves stays in front of the pip's middle; it touches down at the hop's
## contact (keepsake_anim.gd HOP_CONTACT) as every hop does.
static func step_down(from: Vector3, to: Vector3, height: float) -> Callable:
	return func(t: float) -> Vector3:
		var u := minf(t / Anim.HOP_CONTACT, 1.0)
		var out := 1.0 - (1.0 - u) * (1.0 - u)
		var flat := from.lerp(to, out)
		return Vector3(flat.x, lerpf(from.y, to.y, u * u) + sin(u * PI) * height, flat.z)

## From the ledge's front down the steps to the grass.
static func climb_down() -> Array:
	var points: Array = [LEDGE_EDGE]
	for index in range(STEPS.size()): points.append(Vector3(STEP_X, STEPS[index], STEP_Z0 - STEP_DEPTH * 0.5 + STEP_STAND + index * STEP_DEPTH))
	points.append(LANDING)
	return points

func play(beat: String, anim: RefCounted, parts: Dictionary, state: Dictionary) -> void:
	var sounds: Dictionary = state.get("sounds", {})
	match beat:
		"base":
			# The trough spills and the wheel turns once, its bucket coming round with it.
			anim.set_at(parts.pour, "visible", true, APPROACH - 0.15)
			anim.move(parts.wheel, "rotation:z", -TAU, APPROACH, WHEEL_TIME, Tween.TRANS_LINEAR)
			anim.path(parts.seat, _seat, APPROACH, WHEEL_TIME)
			anim.set_at(parts.pour, "visible", false, APPROACH + WHEEL_TIME - 0.05)
			anim.sound(str(sounds.get("base", "")), APPROACH - 0.15)
			anim.sound("slosh", APPROACH + 0.3)
			if state.get("together", false):
				# The wheel winds the basket up its line, and it waits at the top.
				anim.path(parts.basket, func(t: float) -> Vector3: return _basket(lerpf(0.12, 0.85, t)), APPROACH, 1.6)
			# The pip walks out, steps in, rides up to the ledge and hops down the steps.
			var t := 0.0
			for leg: Array in approach(state, anim.rider_from):
				anim.carry(leg[0], t, leg[1])
				if leg[1] == HOP: anim.rider_call(&"play_hop", [HOP, Anim.HOP_CONTACT], t)
				t += float(leg[1])
			var off := step_off()
			anim.carry(func(u: float) -> Vector3: return _seat(u * off), APPROACH, WHEEL_TIME * off)
			var landed: float = anim.hop_steps([_seat(off), LEDGE_SPOT], APPROACH + WHEEL_TIME * off, HOP, 0.15)
			anim.carry(func(u: float) -> Vector3: return LEDGE_SPOT.lerp(LEDGE_EDGE, u), landed, 0.15)
			var down := climb_down()
			for index in range(down.size() - 1):
				var at := landed + 0.15 + index * STEP_HOP
				anim.carry(step_down(down[index], down[index + 1], 0.05), at, STEP_HOP)
				anim.rider_call(&"play_hop", [STEP_HOP, Anim.HOP_CONTACT], at)
		"together":
			# It tips at the top and rides back down the line.
			var basket: Node3D = parts.basket
			anim.move(basket, "rotation:z", 0.25, 0.0, 0.12)
			anim.move(basket, "rotation:z", 0.0, 0.12, 0.2)
			anim.path(basket, func(t: float) -> Vector3: return _basket(lerpf(0.85, 0.12, t)), 0.05, 0.45)
			anim.sound(str(sounds.get("together", "")), 0.0)
		"hard":
			# The water surges and the rope bridge sways on its ropes.
			anim.move(parts.bridge, "rotation:z", 0.05, 0.0, 0.15)
			anim.move(parts.bridge, "rotation:z", -0.04, 0.15, 0.17)
			anim.move(parts.bridge, "rotation:z", 0.0, 0.32, 0.16)
			anim.sound(str(sounds.get("hard", "")), 0.0)
		"top":
			brighten(anim, parts.top, 0.0)
			anim.burst(anim.fx, RAINBOW + Vector3(0, RAINBOW_R + 0.05, 0), 8, 0.3, 0.0, 0.45)
			anim.sound(str(sounds.get("top", "")), 0.0)

## Walking up to the plank's land end (in front of Hard's footing).
func trigger() -> Dictionary:
	return {"area": Rect2(-0.25, 1.9, 0.5, 0.35)}

## Set off from beside or behind the mill, the pip goes round to the plank first.
func ride_start(_state: Dictionary, from: Vector3) -> Variant:
	return start_in(trigger().area, from)

## The house, the ledge's post, the steps, the pool with the wheel and plank,
## the wheel's pit wall and the trough's post, the tank; the together post;
## Hard's footing and the bridge over the gap to it.
func solids(state: Dictionary) -> Array[Rect2]:
	var result: Array[Rect2] = [Rect2(-2.75, -0.7, 1.05, 1.3), Rect2(-1.25, 0.31, 0.1, 0.1), Rect2(-1.62, 0.93, 0.36, 1.16),
		Rect2(-1.2, -0.47, 2.95, 1.75), Rect2(-1.1, -0.8, 2.3, 0.27), Rect2(0.0, -1.5, 0.7, 0.7)]
	if state.get("together", false): result.append(Rect2(1.88, 1.18, 0.14, 0.14))
	if state.get("hard", false): result.append_array([Rect2(-0.48, 1.44, 0.96, 0.4), Rect2(-0.42, 1.26, 0.84, 0.2)])
	return result

func footprint() -> Rect2:
	return Rect2(-2.8, -1.5, 4.85, 3.8)
