extends "res://presentation/keepsakes/keepsake_builder.gd"
## The Earlier islands keepsake: one lantern for each earlier island, lit once
## that island is cleared. Tap: a light runs along the line and each lantern it
## passes glows. Together (the free islands all done with a friend): a lower
## line of mint flags that flutter as the light comes back the other way. The
## earlier islands have no Hard, so it has no footing and no top.
## state "lanterns": one bool per island, lit or not (the base look: all unlit).
const P = preload("res://presentation/keepsakes/keepsake_parts.gd")
const SPAN := 0.56

func build(root: Node3D, state: Dictionary) -> Dictionary:
	var body := P.pivot(root, Vector3.ZERO, "Body")
	for x: float in [-SPAN, SPAN]:
		P.cyl(body, 0.08, 0.06, P.STONE_LIGHT, Vector3(x, 0.03, 0))
		P.box(body, Vector3(0.06, 0.8, 0.06), P.WOOD, Vector3(x, 0.4, 0))
		P.sph(body, 0.035, P.CREAM, Vector3(x, 0.82, 0))
	for i in range(4):
		var x0 := -SPAN + i * SPAN * 0.5
		P.bar(body, Vector3(x0, _rope(x0), 0), Vector3(x0 + SPAN * 0.5, _rope(x0 + SPAN * 0.5), 0), 0.012, P.CREAM)
	var lanterns: Array = state.get("lanterns", [false, false, false, false, false, false, false, false])
	for i in range(lanterns.size()):
		var at := _lantern(i, lanterns.size())
		P.box(body, Vector3(0.006, 0.05, 0.006), P.CREAM, at + Vector3(0, 0.075, 0))
		P.node(body, P.Primitives.shared_mesh("cylinder", 0.045, 0.09, 0.035), P.glow(P.LAMP, 0.9) if lanterns[i] else P.mat(P.LAMP_OFF), at)
		P.cyl(body, 0.03, 0.02, P.CORAL, at + Vector3(0, 0.055, 0))
	var parts := {"count": lanterns.size()}
	if state.get("together", false):
		var flags := P.pivot(body, Vector3(0, 0, 0.02), "Flags")
		for i in range(4):
			var x0 := -SPAN + i * SPAN * 0.5
			P.bar(flags, Vector3(x0, _low(x0), 0), Vector3(x0 + SPAN * 0.5, _low(x0 + SPAN * 0.5), 0), 0.01, P.MINT_DEEP)
		for i in range(9):
			var x := -SPAN + 0.08 + i * (2.0 * SPAN - 0.16) / 8.0
			P.prism(flags, Vector3(0.08, 0.1, 0.01), P.MINT if i % 2 == 0 else P.MINT_DEEP, Vector3(x, _low(x) - 0.055, 0), Vector3(0, 0, PI))
		parts.flags = flags
	return parts

static func _rope(x: float) -> float:
	return 0.76 - 0.12 * (1.0 - pow(x / SPAN, 2.0))

static func _low(x: float) -> float:
	return 0.5 - 0.09 * (1.0 - pow(x / SPAN, 2.0))

static func _lantern(index: int, count: int) -> Vector3:
	var x := -SPAN + 0.1 + index * (2.0 * SPAN - 0.2) / maxf(1.0, count - 1)
	return Vector3(x, _rope(x) - 0.1, 0)

func play(beat: String, anim: RefCounted, parts: Dictionary, state: Dictionary) -> void:
	var count: int = parts.count
	var sounds: Dictionary = state.get("sounds", {})
	match beat:
		"base":
			# One light runs along the line; each lantern glows as it passes.
			var light: MeshInstance3D = anim.spawn(anim.fx, P.low_sphere(0.07), P.clear(P.LAMP, 0.6, 1.4), _lantern(0, count))
			anim.set_at(light, "visible", true, 0.0)
			anim.path(light, func(t: float) -> Vector3: return _lantern(0, count).lerp(_lantern(count - 1, count), t), 0.0, 1.8, 0.5)
			anim.set_at(light, "visible", false, 1.85)
			for index in range(count):
				var at := 1.8 * (0.0 if count < 2 else float(index) / float(count - 1))
				var glow: MeshInstance3D = anim.spawn(anim.fx, P.low_sphere(0.075), P.clear(P.LAMP, 0.45, 1.6), _lantern(index, count))
				anim.set_at(glow, "visible", true, at)
				anim.set_at(glow, "visible", false, at + 0.35)
			anim.sound(str(sounds.get("base", "")), 0.0)
		"together":
			var flags: Node3D = parts.flags
			var back: MeshInstance3D = anim.spawn(anim.fx, P.low_sphere(0.05), P.clear(P.MINT, 0.6, 1.2), Vector3(SPAN, _low(SPAN), 0.04))
			anim.set_at(back, "visible", true, 0.0)
			anim.path(back, func(t: float) -> Vector3: return Vector3(lerpf(SPAN, -SPAN, t), _low(lerpf(SPAN, -SPAN, t)), 0.04), 0.0, 0.6, 0.5)
			anim.set_at(back, "visible", false, 0.62)
			anim.move(flags, "rotation:x", 0.35, 0.0, 0.15)
			anim.move(flags, "rotation:x", -0.25, 0.15, 0.2)
			anim.move(flags, "rotation:x", 0.0, 0.35, 0.25)
			anim.sound(str(sounds.get("together", "")), 0.0)

func full_state() -> Dictionary:
	return {"together": true, "lanterns": [true, true, true, false, false, false, false, false]}

func footing_size() -> Vector2:
	return Vector2(1.3, 0.3)

func footprint() -> Rect2:
	return Rect2(-0.64, -0.16, 1.28, 0.32)
