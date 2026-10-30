extends "res://presentation/keepsakes/keepsake_builder.gd"
## The Turn of the Tide keepsake: a round tide pool with a wheel on a post and
## a low weight stone at its edge. Stepping on the low stone sinks it under the
## pip, the wheel turns and the tide rises, lifting a row of stepping stones;
## the pip hops across them to the far side, and the tide goes out again. A tap
## turns the tide without the pip. Together: a mint rock pool joined by a
## channel, and its toy boat floats up. Hard: a tide post on a slate plinth;
## the water runs past the top mark and spills. Together Hard: a gold lantern
## on the wheel post that lights at high tide.
const P = preload("res://presentation/keepsakes/keepsake_parts.gd")
const RADIUS := 1.05
## The water's height at low and high tide.
const LOW := 0.18
const HIGH := 0.36
## The stepping stones' height at low tide: their tops 5 cm over the water.
const STONES_LOW := LOW + 0.01
const WEIGHT := Vector3(-1.3, 0.06, 0.55)
const ROCK_POOL := Vector3(1.55, 0, 0.6)
const MARK := Vector3(0.95, 0, -0.75)
const STONES: Array[Vector3] = [Vector3(-0.66, 0, 0), Vector3(-0.22, 0, 0.05), Vector3(0.22, 0, 0), Vector3(0.66, 0, 0.05)]
## Where the pip lands past the pool.
const LANDING := Vector3(1.38, 0, -0.18)

func build(root: Node3D, state: Dictionary) -> Dictionary:
	P.cyl(root, RADIUS + 0.05, 0.12, P.STONE, Vector3(0, 0.06, 0), RADIUS + 0.08)
	for y: float in [0.18, 0.3]: P.ring(root, RADIUS, 0.16, P.STONE, Vector3(0, y, 0))
	P.ring(root, RADIUS + 0.01, 0.09, P.CREAM, Vector3(0, 0.4, 0))
	var water := P.pivot(root, Vector3(0, 0.12, 0), "Water")
	water.scale = Vector3(1, LOW - 0.12, 1)
	P.cyl(water, RADIUS - 0.05, 1.0, P.TIDE, Vector3(0, 0.5, 0))
	# At low tide the stones' tops stand just clear of the water.
	var stones := P.pivot(root, Vector3(0, STONES_LOW, 0), "Stones")
	for at: Vector3 in STONES: P.cyl(stones, 0.15, 0.08, Color("d8cfba"), at, 0.17)
	P.box(root, Vector3(0.16, 1.9, 0.16), P.WOOD, Vector3(0, 0.95, -RADIUS - 0.05))
	var wheel := P.pivot(root, Vector3(0, 1.35, -RADIUS + 0.06), "Wheel")
	P.ring(wheel, 0.45, 0.08, P.PEACH, Vector3.ZERO, Vector3(PI / 2, 0, 0))
	for index in range(4): P.box(wheel, Vector3(0.05, 0.86, 0.05), P.WOOD_LIGHT, Vector3.ZERO, Vector3(0, 0, index * PI / 4))
	P.sph(wheel, 0.09, P.CREAM, Vector3(0, 0, 0.03))
	# The weight stone at the pool's edge sinks under the pip; a chain runs to the wheel.
	var weight := P.pivot(root, WEIGHT, "WeightStone")
	P.cyl(weight, 0.3, 0.12, P.STONE_LIGHT, Vector3.ZERO, 0.28)
	P.ring(weight, 0.29, 0.03, P.PEACH, Vector3(0, 0.06, 0))
	P.bar(root, Vector3(-1.3, 0.1, 0.4), Vector3(-0.12, 1.2, -RADIUS + 0.02), 0.03, P.SLATE_DARK)
	var parts := {"water": water, "stones": stones, "wheel": wheel, "weight": weight}
	if state.get("together", false):
		var at := ROCK_POOL
		P.cyl(root, 0.5, 0.22, P.STONE_LIGHT, at + Vector3(0, 0.11, 0), 0.52)
		P.ring(root, 0.5, 0.07, P.MINT, at + Vector3(0, 0.22, 0))
		P.cyl(root, 0.44, 0.02, P.WATER, at + Vector3(0, 0.14, 0))
		var boat := P.pivot(root, at + Vector3(0, 0.18, 0), "Boat")
		P.sph(boat, 0.14, P.MINT_DEEP, Vector3.ZERO, Vector3(1.05, 0.5, 1.05))
		P.cyl(boat, 0.01, 0.24, P.WOOD, Vector3(0, 0.14, 0))
		P.prism(boat, Vector3(0.14, 0.18, 0.015), P.SNOW, Vector3(0.06, 0.16, 0))
		P.bar(root, Vector3(0.95, 0.42, 0.35), at + Vector3(-0.4, 0.22, 0), 0.12, P.STONE_LIGHT)
		parts.boat = boat
	if state.get("hard", false):
		P.plinth(root, 0.5, 0.5, MARK)
		P.box(root, Vector3(0.1, 1.1, 0.1), P.WOOD_LIGHT, MARK + Vector3(0, 0.88, 0))
		for index in range(3): P.box(root, Vector3(0.2, 0.04, 0.04), P.PEACH if index == 2 else P.CREAM, MARK + Vector3(0, 0.6 + index * 0.25, 0.06))
	if state.get("top", false):
		var lamp := P.pivot(root, Vector3(0, 2.05, -RADIUS - 0.05), "Lantern")
		P.box(lamp, Vector3(0.22, 0.24, 0.22), P.LAMP_OFF, Vector3.ZERO)
		P.box(root, Vector3(0.3, 0.06, 0.3), P.GOLD_DEEP, Vector3(0, 1.92, -RADIUS - 0.05))
		P.box(root, Vector3(0.32, 0.06, 0.32), P.GOLD_DEEP, Vector3(0, 2.2, -RADIUS - 0.05))
		P.gold_ball(root, Vector3(0, 2.3, -RADIUS - 0.05), 0.06)
		parts.lantern = lamp
	return parts

func base_time() -> float:
	return 2.4

func upgrade_time(beat: String) -> float:
	return 0.55 if beat == "top" else 0.6

func play(beat: String, anim: RefCounted, parts: Dictionary, state: Dictionary) -> void:
	var sounds: Dictionary = state.get("sounds", {})
	match beat:
		"base":
			# The stone sinks, the wheel turns, the tide and the stepping stones rise.
			var weight: Node3D = parts.weight
			anim.move(weight, "position:y", WEIGHT.y - 0.16, 0.0, 0.25, Tween.TRANS_QUAD, Tween.EASE_OUT)
			anim.move(parts.wheel, "rotation:z", -TAU, 0.15, 1.6)
			anim.move(parts.water, "scale:y", HIGH - 0.12, 0.2, 0.7)
			anim.move(parts.stones, "position:y", HIGH + 0.05, 0.25, 0.65)
			anim.sound(str(sounds.get("base", "")), 0.2)
			# The pip hops across the risen stones to the far side.
			var top := HIGH + 0.05 + 0.04
			var path: Array = [anim.rider_from, WEIGHT + Vector3(0, -0.1, 0)]
			for at: Vector3 in STONES: path.append(at + Vector3(0, top, 0))
			path.append(LANDING)
			anim.carry(anim.arc(path[0], path[1], 0.05), 0.0, 0.25)
			anim.hops(path.slice(1), 0.9, 0.22, 0.25)
			for index in range(4): anim.halo(anim.fx, STONES[index] + Vector3(0, top + 0.04, 0), 0.08, P.SNOW, 0.95 + index * 0.22, 0.25, 0.5)
			# And the tide goes out again.
			anim.move(parts.water, "scale:y", LOW - 0.12, 1.95, 0.45)
			anim.move(parts.stones, "position:y", STONES_LOW, 1.95, 0.45)
			anim.move(weight, "position:y", WEIGHT.y, 1.95, 0.4)
		"together":
			var boat: Node3D = parts.boat
			anim.move(boat, "position:y", ROCK_POOL.y + 0.27, 0.0, 0.3, Tween.TRANS_BACK, Tween.EASE_OUT)
			anim.move(boat, "rotation:z", 0.2, 0.1, 0.2)
			anim.move(boat, "rotation:z", -0.15, 0.3, 0.2)
			anim.move(boat, "position:y", ROCK_POOL.y + 0.18, 0.35, 0.25)
			anim.move(boat, "rotation:z", 0.0, 0.45, 0.15)
			anim.sound(str(sounds.get("together", "")), 0.0)
		"hard":
			# The water runs past the top mark and spills over the rim.
			anim.move(parts.water, "scale:y", HIGH + 0.04, 0.0, 0.25)
			for index in range(3):
				var spill: MeshInstance3D = anim.spawn(anim.fx, P.low_sphere(0.12, 0.06), P.mat(P.TIDE), Vector3(-0.5 + index * 0.5, 0.42, RADIUS - 0.05))
				anim.set_at(spill, "visible", true, 0.2 + index * 0.05)
				anim.move(spill, "position", Vector3(-0.5 + index * 0.5, 0.03, RADIUS + 0.18), 0.2 + index * 0.05, 0.3, Tween.TRANS_QUAD, Tween.EASE_IN)
				anim.set_at(spill, "visible", false, 0.58)
			anim.move(parts.water, "scale:y", LOW - 0.12, 0.3, 0.3)
			anim.sound(str(sounds.get("hard", "")), 0.0)
		"top":
			var lamp: Node3D = parts.lantern
			for found: Node in lamp.get_children():
				if found is MeshInstance3D: anim.set_at(found, "material_override", P.glow(P.GOLD, 2.0), 0.0)
			anim.halo(lamp, Vector3.ZERO, 0.4, P.GOLD, 0.0, 0.6)
			anim.sound(str(sounds.get("top", "")), 0.0)

## Stepping on the low stone.
func trigger() -> Dictionary:
	return {"area": Rect2(WEIGHT.x - 0.3, WEIGHT.z - 0.3, 0.6, 0.6)}

func solids(state: Dictionary) -> Array[Rect2]:
	var result: Array[Rect2] = [Rect2(-RADIUS - 0.1, -RADIUS - 0.15, RADIUS * 2.0 + 0.2, RADIUS * 2.0 + 0.25)]
	if state.get("together", false): result.append(Rect2(ROCK_POOL.x - 0.52, ROCK_POOL.z - 0.5, 1.04, 1.02))
	if state.get("hard", false): result.append(Rect2(MARK.x - 0.25, MARK.z - 0.25, 0.5, 0.5))
	return result

func footprint() -> Rect2:
	return Rect2(-1.65, -1.2, 3.75, 2.35)
