extends "res://presentation/keepsakes/keepsake_builder.gd"
## The Rolling Home keepsake: a Rolling Rail that curves overhead from a
## boarding stand, with a peach cart. Walking up to the stand sets the pip
## climbing into the cart, and it rides the rail to the far end and hops off;
## a tap sends the cart along empty. Together: a mint catch cup at the end of
## the rail that the pip slides into. Hard: a loop in the middle, and the ride
## goes all the way round it. Together Hard: a gold bell over the dip rings as
## the pip passes under.
const P = preload("res://presentation/keepsakes/keepsake_parts.gd")
const CUP := Vector3(1.75, 0, 0.2)
const LOOP := Vector3(0.0, 1.25, 0.0)
const LOOP_RADIUS := 0.42
## Where the pip sits in the cart, over the cart's middle.
const SEAT := Vector3(0, 0.2, 0)

## The rail's points from the stand to the far end.
static func _rail() -> Array[Vector3]:
	var result: Array[Vector3] = []
	for index in range(13):
		var s := index / 12.0
		result.append(Vector3(-1.3 + s * 2.6, 1.55 - 0.85 * sin(s * PI) + (0.3 if s < 0.12 else 0.0), sin(s * PI * 2.0) * 0.18))
	return result

func build(root: Node3D, state: Dictionary) -> Dictionary:
	var hard: bool = state.get("hard", false)
	var rail := _rail()
	for index in range(12):
		var color := P.WOOD if index % 2 == 0 else P.WOOD_LIGHT
		for side: float in [0.14, -0.14]: P.bar(root, rail[index] + Vector3(0, 0, side), rail[index + 1] + Vector3(0, 0, side), 0.05, color)
	for index: int in [0, 3, 6, 9, 12]: P.box(root, Vector3(0.09, rail[index].y, 0.09), P.WOOD, Vector3(rail[index].x, rail[index].y * 0.5, rail[index].z - 0.2))
	# The boarding stand: three steps up to the cart.
	for index in range(3): P.box(root, Vector3(0.3, 0.28 * (index + 1), 0.5), P.STEP, Vector3(-1.95 + index * 0.28, 0.14 * (index + 1), 0))
	var cart := P.pivot(root, _cart_rest(), "Cart")
	P.cyl(cart, 0.3, 0.26, P.PEACH, Vector3(0, 0.13, 0), 0.34)
	P.ring(cart, 0.34, 0.05, P.CREAM, Vector3(0, 0.26, 0))
	for side: int in [-1, 1]: P.node(cart, P.Primitives.shared_mesh("cylinder", 0.07, 0.05, 0.07), P.mat(P.WOOD), Vector3(side * 0.18, -0.02, 0.15), Vector3(PI / 2, 0, 0))
	var parts := {"cart": cart}
	if hard:
		P.plinth(root, 0.6, 0.6, Vector3(0, 0, -0.55))
		P.ring(root, LOOP_RADIUS, 0.07, P.WOOD_LIGHT, LOOP, Vector3(PI / 2, 0, 0))
		var post := LOOP.y - LOOP_RADIUS - P.PLINTH_TOP
		P.box(root, Vector3(0.08, post, 0.08), P.WOOD, Vector3(0, P.PLINTH_TOP + post * 0.5, -0.55))
		P.bar(root, Vector3(0, LOOP.y - LOOP_RADIUS, -0.55), Vector3(0, LOOP.y - LOOP_RADIUS, -0.02), 0.06, P.WOOD)
	if state.get("together", false):
		P.cyl(root, 0.42, 0.3, P.MINT_DEEP, CUP + Vector3(0, 0.15, 0), 0.46)
		P.ring(root, 0.45, 0.06, P.MINT, CUP + Vector3(0, 0.3, 0))
		P.bar(root, rail[12], CUP + Vector3(-0.35, 0.34, 0), 0.08, P.WOOD_LIGHT)
	if state.get("top", false):
		P.box(root, Vector3(0.07, 2.4, 0.07), P.WOOD, Vector3(0, 1.2, -0.75))
		P.bar(root, Vector3(0, 2.4, -0.75), Vector3(0, 2.4, 0), 0.06, P.WOOD)
		var bell := P.pivot(root, Vector3(0, 2.4, 0), "GoldBell")
		P.node(bell, P.low_sphere(0.17, 0.41), P.gold(), Vector3(0, -0.2, 0))
		P.ring(bell, 0.17, 0.05, P.GOLD, Vector3(0, -0.34, 0))
		parts.bell = bell
	return parts

static func _cart_rest() -> Vector3:
	return _rail()[0] + Vector3(0.12, 0.12, 0)

## The ride along the rail, t from 0 to 1: the cart's place (round the loop on Hard).
static func _ride(hard: bool) -> Array[Vector3]:
	var rail := _rail()
	var result: Array[Vector3] = []
	for index in range(13):
		result.append(rail[index] + Vector3(0, 0.12, 0))
		if hard and index == 6:
			for step in range(1, 13):
				var angle := -PI / 2 + step * TAU / 12.0
				result.append(LOOP + Vector3(cos(angle) * (LOOP_RADIUS - 0.2), sin(angle) * (LOOP_RADIUS - 0.2), 0))
			result.append(rail[6] + Vector3(0, 0.12, 0))
	result[0] = _cart_rest()
	return result

static func _along(points: Array[Vector3]) -> Callable:
	var lengths: Array[float] = [0.0]
	for index in range(1, points.size()): lengths.append(lengths[index - 1] + points[index - 1].distance_to(points[index]))
	var total: float = lengths[lengths.size() - 1]
	return func(t: float) -> Vector3:
		var at := clampf(t, 0.0, 1.0) * total
		var index := 1
		while index < lengths.size() - 1 and lengths[index] < at: index += 1
		var span := maxf(0.0001, lengths[index] - lengths[index - 1])
		return points[index - 1].lerp(points[index], (at - lengths[index - 1]) / span)

## Where the pip ends: in the mint cup with Together, else on the grass past the end.
static func _off(state: Dictionary) -> Vector3:
	return CUP + Vector3(0, 0.2, 0) if state.get("together", false) else Vector3(1.55, 0, 0.5)

func beats(state: Dictionary) -> Array:
	var result: Array = [{"beat": "base", "time": 2.45 if state.get("hard", false) else 2.15}]
	for beat: String in UPGRADES:
		if state.get(beat, false): result.append({"beat": beat, "time": 0.55})
	return result

func play(beat: String, anim: RefCounted, parts: Dictionary, state: Dictionary) -> void:
	var sounds: Dictionary = state.get("sounds", {})
	var hard: bool = state.get("hard", false)
	var cart: Node3D = parts.cart
	match beat:
		"base":
			# Up the stand and into the cart.
			var steps: Array = [anim.rider_from, Vector3(-1.95, 0.28, 0.0), Vector3(-1.67, 0.56, 0.0), Vector3(-1.39, 0.84, 0.0), _cart_rest() + SEAT]
			var t: float = anim.hops(steps, 0.0, 0.16, 0.18)
			if anim.rider == null: t = 0.3
			# The ride along the rail, round the loop on Hard.
			var path := _ride(hard)
			var where := _along(path)
			var ride := 1.25 if hard else 0.95
			anim.path(cart, where, t, ride)
			anim.carry(func(s: float) -> Vector3: return where.call(s) + SEAT, t, ride)
			anim.sound(str(sounds.get("base", "")), t)
			for index in range(4): anim.halo(anim.fx, _rail()[3 + index * 2] + Vector3(0, 0.3, 0), 0.05, P.SNOW, t + ride * (0.25 + index * 0.18), 0.35, 0.5)
			t += ride
			# Off at the end, and the cart rolls home along the rail.
			anim.carry(anim.arc(path[path.size() - 1] + SEAT, _off(state), 0.35), t, 0.3)
			anim.path(cart, func(s: float) -> Vector3: return where.call(1.0 - s), t + 0.05, 0.45)
		"together":
			# Out of the mint cup and onto the grass.
			anim.carry(anim.arc(_off(state), CUP + Vector3(0, 0, 0.75), 0.4), 0.0, 0.35)
			anim.halo(anim.fx, CUP + Vector3(0, 0.35, 0), 0.4, P.MINT, 0.0, 0.3, 0.25)
			anim.sound(str(sounds.get("together", "")), 0.0)
		"hard":
			anim.burst(anim.fx, LOOP, 8, LOOP_RADIUS, 0.0, 0.5)
			anim.sound(str(sounds.get("hard", "")), 0.0)
		"top":
			var bell: Node3D = parts.bell
			anim.move(bell, "rotation:z", 0.45, 0.0, 0.12)
			anim.move(bell, "rotation:z", -0.35, 0.12, 0.18)
			anim.move(bell, "rotation:z", 0.0, 0.3, 0.2)
			brighten(anim, bell, 0.0)
			anim.sound(str(sounds.get("top", "")), 0.0)

## Walking up to the front of the boarding stand.
func trigger() -> Dictionary:
	return {"area": Rect2(-2.15, 0.3, 0.9, 0.45)}

func solids(state: Dictionary) -> Array[Rect2]:
	var rail := _rail()
	var result: Array[Rect2] = [Rect2(-2.1, -0.25, 0.86, 0.5)]
	for index: int in [3, 6, 9, 12]: result.append(Rect2(rail[index].x - 0.08, rail[index].z - 0.28, 0.16, 0.16))
	if state.get("together", false): result.append(Rect2(CUP.x - 0.46, CUP.z - 0.46, 0.92, 0.92))
	if state.get("hard", false): result.append(Rect2(-0.3, -0.85, 0.6, 0.6))
	return result

func footprint() -> Rect2:
	return Rect2(-2.2, -0.9, 4.45, 1.75)
