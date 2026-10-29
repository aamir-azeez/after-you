extends "res://presentation/keepsakes/keepsake_builder.gd"
## The High and Low keepsake: Giant Steps the pip climbs, and a chute it rides
## back down to the grass. Walking up to the first step sets the pip climbing;
## a tap sends a peach ball up and down instead. Together: a mint seesaw flings
## a mint ball up after the pip. Hard: a slate tower with a ladder for a higher
## climb and a longer ride. Together Hard: a gold flag at the very top pops up
## as the pip arrives.
const P = preload("res://presentation/keepsakes/keepsake_parts.gd")
const STEP_WIDTH := 0.36
const TOWER := Vector3(1.15, 0, -0.45)
const SEESAW := Vector3(-1.4, 0, 0.3)

## The top of each step.
static func _tops() -> Array[Vector3]:
	var result: Array[Vector3] = []
	for index in range(5): result.append(Vector3(-0.7 + index * STEP_WIDTH, 0.24 * (index + 1), 0.1))
	return result

## The highest point the pip reaches: the top step, or the tower's top on Hard.
static func _high(state: Dictionary) -> Vector3:
	return Vector3(TOWER.x, 2.24, TOWER.z) if state.get("hard", false) else _tops()[4]

## The chute from the top down to the grass.
static func _chute(state: Dictionary) -> Array[Vector3]:
	var high := _high(state)
	var start := Vector3(high.x, high.y - 0.02, 0.45)
	return [start, Vector3(start.x + 0.2, start.y * 0.55, 1.05), Vector3(start.x + 0.32, start.y * 0.22, 1.45), Vector3(start.x + 0.36, 0.1, 1.75)]

func build(root: Node3D, state: Dictionary) -> Dictionary:
	var hard: bool = state.get("hard", false)
	for index in range(5):
		var height := 0.24 * (index + 1)
		P.box(root, Vector3(STEP_WIDTH, height, 0.8), P.PEACH if index % 2 == 0 else P.STEP, Vector3(-0.7 + index * STEP_WIDTH, height * 0.5, 0))
	var high := _high(state)
	if hard:
		P.plinth(root, 0.7, 0.7, TOWER)
		P.box(root, Vector3(0.36, 1.9, 0.36), P.SLATE, TOWER + Vector3(0, 0.34 + 0.95, 0))
		for index in range(8): P.box(root, Vector3(0.32, 0.03, 0.03), P.WOOD_LIGHT, TOWER + Vector3(0, 0.7 + index * 0.18, 0.2))
	# The chute: a wide trough with low sides, curling down to the grass.
	var chute := _chute(state)
	for index in range(3):
		P.bar(root, chute[index], chute[index + 1], 0.06, P.WOOD_LIGHT)
		P.bar(root, chute[index] + Vector3(0.16, 0.08, 0), chute[index + 1] + Vector3(0.16, 0.08, 0), 0.05, P.WOOD)
		P.bar(root, chute[index] + Vector3(-0.16, 0.08, 0), chute[index + 1] + Vector3(-0.16, 0.08, 0), 0.05, P.WOOD)
	for index in range(3): P.box(root, Vector3(0.06, chute[index].y, 0.06), P.WOOD, Vector3(chute[index].x, chute[index].y * 0.5, chute[index].z))
	var parts := {}
	if state.get("together", false):
		P.prism(root, Vector3(0.22, 0.22, 0.26), P.STONE_LIGHT, SEESAW + Vector3(0, 0.11, 0))
		var plank := P.pivot(root, SEESAW + Vector3(0, 0.24, 0), "Seesaw")
		plank.rotation.z = 0.3
		P.box(plank, Vector3(0.95, 0.05, 0.2), P.MINT_DEEP, Vector3.ZERO)
		P.sph(plank, 0.11, P.MINT, Vector3(-0.38, 0.14, 0))
		parts.seesaw = plank
	if state.get("top", false):
		P.cyl(root, 0.018, 0.6, P.WOOD, high + Vector3(-0.1, 0.3, -0.2))
		P.gold_ball(root, high + Vector3(-0.1, 0.63, -0.2), 0.06)
		var flag := P.pivot(root, high + Vector3(0.1, 0.47, -0.2), "GoldFlag")
		P.node(flag, P.Primitives.shared_mesh("prism", 0.24, 0.4, 0.02), P.gold(), Vector3.ZERO, Vector3(0, 0, -PI / 2))
		parts.flag = flag
	return parts

## The climb and the ride, in the keepsake's frame: [point, ...] hops up, then
## the chute, then the landing on the grass.
static func _climb(state: Dictionary, from: Vector3) -> Array:
	var points: Array = [from, Vector3(-0.7, 0, 0.55)]
	for top: Vector3 in _tops(): points.append(top)
	if state.get("hard", false):
		points.append(Vector3(TOWER.x, 1.2, TOWER.z + 0.42))
	return points

static func _landing(state: Dictionary) -> Vector3:
	var end: Vector3 = _chute(state)[3]
	return Vector3(end.x, 0, end.z + 0.3)

func beats(state: Dictionary) -> Array:
	var result: Array = [{"beat": "base", "time": 2.45 if state.get("hard", false) else 2.1}]
	for beat: String in UPGRADES:
		if state.get(beat, false): result.append({"beat": beat, "time": {"together": 0.6, "hard": 0.5, "top": 0.55}[beat]})
	return result

func play(beat: String, anim: RefCounted, parts: Dictionary, state: Dictionary) -> void:
	var sounds: Dictionary = state.get("sounds", {})
	var high := _high(state)
	match beat:
		"base":
			# Up the steps (and the ladder on Hard), then down the chute.
			var start: Vector3 = anim.rider_from if anim.rider != null else Vector3(-0.7, 0.12, 0.55)
			var climb := _climb(state, start)
			var ball: MeshInstance3D = null
			if anim.rider == null:
				ball = anim.spawn(anim.fx, P.low_sphere(0.12), P.mat(P.PEACH), start + Vector3(0, 0.12, 0))
				anim.set_at(ball, "visible", true, 0.0)
			var t := 0.0
			var lifted := Vector3(0, 0.12, 0) if ball != null else Vector3.ZERO
			for index in range(climb.size() - 1):
				var hop: Callable = anim.arc(climb[index] + lifted, climb[index + 1] + lifted, 0.18)
				if ball != null: anim.path(ball, hop, t, 0.18)
				else: anim.carry(hop, t, 0.18)
				t += 0.18
			var top := Vector3(high.x, high.y, 0.45 if not state.get("hard", false) else high.z)
			var up: Callable = (func(s: float) -> Vector3: return (climb[climb.size() - 1] as Vector3).lerp(top, s) + lifted)
			if ball != null: anim.path(ball, up, t, 0.3)
			else: anim.carry(up, t, 0.3)
			t += 0.3
			anim.sound(str(sounds.get("base", "")), t)
			var chute := _chute(state)
			chute.push_front(top)
			chute.append(_landing(state))
			var slide := func(s: float) -> Vector3:
				var at := s * (chute.size() - 1)
				var index := mini(int(at), chute.size() - 2)
				return (chute[index] as Vector3).lerp(chute[index + 1], at - index) + lifted
			if ball != null:
				anim.path(ball, slide, t, 0.6, 1.0)
				anim.set_at(ball, "visible", false, t + 0.62)
			else: anim.carry(slide, t, 0.6)
			for index in range(4): anim.halo(anim.fx, _tops()[index] + Vector3(0, 0.2, 0.15), 0.05, P.SNOW, 0.18 * (index + 2), 0.4, 0.5)
		"together":
			# The seesaw flips and flings a mint ball up after the pip.
			var plank: Node3D = parts.seesaw
			anim.move(plank, "rotation:z", -0.3, 0.0, 0.12, Tween.TRANS_QUAD, Tween.EASE_IN)
			var ball: MeshInstance3D = anim.spawn(anim.fx, P.low_sphere(0.11), P.mat(P.MINT), SEESAW + Vector3(0.38, 0.4, 0))
			anim.set_at(ball, "visible", true, 0.1)
			anim.path(ball, anim.arc(SEESAW + Vector3(0.38, 0.4, 0), high + Vector3(0, 0.2, 0.3), 0.9), 0.1, 0.45, 0.5)
			anim.set_at(ball, "visible", false, 0.57)
			anim.sound(str(sounds.get("together", "")), 0.0)
		"hard":
			anim.burst(anim.fx, Vector3(TOWER.x, 2.3, TOWER.z), 6, 0.35, 0.0, 0.45)
			anim.sound(str(sounds.get("hard", "")), 0.0)
		"top":
			var flag: Node3D = parts.flag
			anim.move(flag, "position:y", flag.position.y + 0.12, 0.0, 0.2, Tween.TRANS_BACK, Tween.EASE_OUT)
			brighten(anim, flag, 0.0)
			anim.halo(flag, Vector3(0.12, 0, 0), 0.25, P.GOLD, 0.0, 0.5)
			anim.sound(str(sounds.get("top", "")), 0.0)

## Walking up to the first step.
func trigger() -> Dictionary:
	return {"area": Rect2(-0.95, 0.42, 0.6, 0.38)}

func solids(state: Dictionary) -> Array[Rect2]:
	var result: Array[Rect2] = [Rect2(-0.88, -0.4, 1.8, 0.8)]
	if state.get("hard", false): result.append(Rect2(TOWER.x - 0.35, TOWER.z - 0.35, 0.7, 0.7))
	if state.get("together", false): result.append(Rect2(SEESAW.x - 0.48, SEESAW.z - 0.15, 0.96, 0.3))
	for at: Vector3 in _chute(state).slice(0, 3): result.append(Rect2(at.x - 0.06, at.z - 0.06, 0.12, 0.12))
	return result

func footprint() -> Rect2:
	return Rect2(-1.9, -0.8, 3.55, 2.65)
