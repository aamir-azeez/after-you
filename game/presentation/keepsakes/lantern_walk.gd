extends "res://presentation/keepsakes/keepsake_builder.gd"
## The earlier islands keepsake: the Lantern Walk, a high line of lanterns on
## two posts over a path of stepping stones, one lantern and one stone for each
## earlier island, the lantern lit once its island is cleared. Walking the
## stones lights each lit lantern brightly over the pip as it passes; a tap
## runs a light along the line. Together (the free islands all done with a
## friend): a lower mint bunting line that flutters back the other way. The
## earlier islands have no Hard, so it has no plinth and no gold piece.
## state "lanterns": one bool per island, lit or not (the base look: all unlit).
const P = preload("res://presentation/keepsakes/keepsake_parts.gd")
const SPAN := 1.55
const PATH_HALF := 0.32

func build(root: Node3D, state: Dictionary) -> Dictionary:
	for x: float in [-SPAN, SPAN]:
		P.cyl(root, 0.18, 0.1, P.STONE_LIGHT, Vector3(x, 0.05, 0))
		P.box(root, Vector3(0.12, 2.0, 0.12), P.WOOD, Vector3(x, 1.0, 0))
		P.sph(root, 0.07, P.CREAM, Vector3(x, 2.05, 0))
	for index in range(6):
		var x0 := -SPAN + index * SPAN / 3.0
		var x1 := x0 + SPAN / 3.0
		P.bar(root, Vector3(x0, _rope(x0), 0), Vector3(x1, _rope(x1), 0), 0.02, P.CREAM)
	var lanterns: Array = state.get("lanterns", [false, false, false, false, false, false, false, false])
	var count := lanterns.size()
	for index in range(count):
		var x := _x(index, count)
		P.cyl(root, 0.15, 0.03, Color("ddd6c0"), Vector3(x, 0.015, 0))
		var at := _lantern(index, count)
		P.box(root, Vector3(0.008, 0.12, 0.008), P.CREAM, at + Vector3(0, 0.13, 0))
		P.node(root, P.Primitives.shared_mesh("cylinder", 0.09, 0.17, 0.075), P.glow(P.LAMP, 1.1) if lanterns[index] else P.mat(P.LAMP_OFF), at)
		P.cyl(root, 0.06, 0.03, P.CORAL, at + Vector3(0, 0.1, 0))
	var parts := {"count": count}
	if state.get("together", false):
		var flags := P.pivot(root, Vector3(0, 0, 0.05), "Flags")
		for index in range(6):
			var x0 := -SPAN + index * SPAN / 3.0
			var x1 := x0 + SPAN / 3.0
			P.bar(flags, Vector3(x0, _low(x0), 0), Vector3(x1, _low(x1), 0), 0.015, P.MINT_DEEP)
		for index in range(13):
			var x := -SPAN + 0.12 + index * (2.0 * SPAN - 0.24) / 12.0
			P.prism(flags, Vector3(0.14, 0.18, 0.012), P.MINT if index % 2 == 0 else P.MINT_DEEP, Vector3(x, _low(x) - 0.1, 0), Vector3(0, 0, PI))
		parts.flags = flags
	return parts

static func _rope(x: float) -> float:
	return 1.95 - 0.28 * (1.0 - pow(x / SPAN, 2.0))

static func _low(x: float) -> float:
	return 1.35 - 0.2 * (1.0 - pow(x / SPAN, 2.0))

static func _x(index: int, count: int) -> float:
	return -SPAN + 0.2 + index * (2.0 * SPAN - 0.4) / maxf(1.0, count - 1)

static func _lantern(index: int, count: int) -> Vector3:
	var x := _x(index, count)
	return Vector3(x, _rope(x) - 0.22, 0)

func base_time() -> float:
	return 2.0

func upgrade_time(_beat: String) -> float:
	return 0.7

func play(beat: String, anim: RefCounted, parts: Dictionary, state: Dictionary) -> void:
	var count: int = parts.count
	var sounds: Dictionary = state.get("sounds", {})
	var lanterns: Array = state.get("lanterns", [])
	match beat:
		"base":
			# One light runs along the line; each lit lantern flares as it passes.
			var light: MeshInstance3D = anim.spawn(anim.fx, P.low_sphere(0.09), P.clear(P.LAMP, 0.6, 1.4), _lantern(0, count))
			anim.set_at(light, "visible", true, 0.0)
			anim.path(light, func(t: float) -> Vector3: return _lantern(0, count).lerp(_lantern(count - 1, count), t), 0.0, 1.8, 0.5)
			anim.set_at(light, "visible", false, 1.85)
			for index in range(count):
				if index < lanterns.size() and not lanterns[index]: continue
				var at := 1.8 * (0.0 if count < 2 else float(index) / float(count - 1))
				anim.halo(anim.fx, _lantern(index, count), 0.2, P.LAMP, at, 0.35, 0.28)
			anim.sound(str(sounds.get("base", "")), 0.0)
		"together":
			var flags: Node3D = parts.flags
			var back: MeshInstance3D = anim.spawn(anim.fx, P.low_sphere(0.06), P.clear(P.MINT, 0.6, 1.2), Vector3(SPAN, _low(SPAN), 0.08))
			anim.set_at(back, "visible", true, 0.0)
			anim.path(back, func(t: float) -> Vector3: return Vector3(lerpf(SPAN, -SPAN, t), _low(lerpf(SPAN, -SPAN, t)) - 0.05, 0.08), 0.0, 0.6, 0.5)
			anim.set_at(back, "visible", false, 0.62)
			anim.move(flags, "rotation:x", 0.35, 0.0, 0.15)
			anim.move(flags, "rotation:x", -0.25, 0.15, 0.2)
			anim.move(flags, "rotation:x", 0.0, 0.35, 0.25)
			anim.sound(str(sounds.get("together", "")), 0.0)

# --- walking the stones ---------------------------------------------------------------

## The stones under the line.
func stay() -> Rect2:
	return Rect2(-SPAN - 0.1, -PATH_HALF, SPAN * 2.0 + 0.2, PATH_HALF * 2.0)

func arrive(visit: Node3D, _parts: Dictionary, _state: Dictionary) -> String:
	var glow := P.node(visit, P.low_sphere(0.2), P.clear(P.LAMP, 0.32, 1.4), Vector3.ZERO)
	glow.name = "Glow"
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glow.visible = false
	visit.set_meta("lantern", -1)
	return ""

## The lit lantern over the pip glows brightly, and chimes as the pip reaches it.
func follow(visit: Node3D, _parts: Dictionary, state: Dictionary, at: Vector2) -> String:
	var lanterns: Array = state.get("lanterns", [])
	var count := lanterns.size()
	if count == 0: return ""
	var index := clampi(roundi((at.x + SPAN - 0.2) / ((2.0 * SPAN - 0.4) / maxf(1.0, count - 1))), 0, count - 1)
	if int(visit.get_meta("lantern", -1)) == index: return ""
	visit.set_meta("lantern", index)
	var glow := visit.get_node("Glow") as MeshInstance3D
	glow.visible = bool(lanterns[index])
	glow.position = _lantern(index, count)
	return str(state.get("sounds", {}).get("base", "")) if lanterns[index] else ""

func solids(_state: Dictionary) -> Array[Rect2]:
	var result: Array[Rect2] = []
	for x: float in [-SPAN, SPAN]: result.append(Rect2(x - 0.18, -0.18, 0.36, 0.36))
	return result

func full_state() -> Dictionary:
	return {"together": true, "lanterns": [true, true, true, true, true, false, false, false]}

func footprint() -> Rect2:
	return Rect2(-SPAN - 0.2, -0.4, SPAN * 2.0 + 0.4, 0.8)
