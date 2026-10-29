extends "res://presentation/keepsakes/keepsake_builder.gd"
## The Relay Isles keepsake: two tall masts with a line between them, and a
## basket of fruit. Tugging the rope at the first mast (walking up to it, or a
## tap) runs the flag up the mast and along the line to the far one. Together:
## a mint third mast, so the flag is handed on twice. Hard: both masts stand on
## slate plinths with crossbars whose signal flags flick out as the flag passes.
## Together Hard: gold lamps on the mast tops light one after the other.
const P = preload("res://presentation/keepsakes/keepsake_parts.gd")
const POLE := 2.4
const ENDS: Array[float] = [-1.3, 1.3]
const HARD_LIFT := 0.34
const MINT_MAST := Vector3(2.0, 0, 0.5)

static func _y0(state: Dictionary) -> float:
	return HARD_LIFT if state.get("hard", false) else 0.0

func build(root: Node3D, state: Dictionary) -> Dictionary:
	var hard: bool = state.get("hard", false)
	var y0 := _y0(state)
	var parts := {}
	for index in range(2):
		var x: float = ENDS[index]
		if hard: P.plinth(root, 0.6, 0.6, Vector3(x, 0, 0))
		P.cyl(root, 0.26, 0.12, P.STONE_LIGHT, Vector3(x, y0 + 0.06, 0), 0.24)
		P.cyl(root, 0.05, POLE, P.WOOD, Vector3(x, y0 + POLE * 0.5, 0))
		P.sph(root, 0.07, P.CREAM, Vector3(x, y0 + POLE + 0.05, 0))
		if hard:
			# The crossbar's two signal flags flick out together, one row per mast.
			P.box(root, Vector3(0.7, 0.05, 0.05), P.WOOD, Vector3(x, y0 + POLE - 0.3, 0))
			var flags := P.pivot(root, Vector3(x, y0 + POLE - 0.32, 0), "Signals")
			for side: int in [-1, 1]: P.box(flags, Vector3(0.14, 0.18, 0.015), P.CORAL if side < 0 else P.CREAM, Vector3(side * 0.39, -0.1, 0))
			parts["signals_%d" % index] = flags
	P.bar(root, Vector3(ENDS[0], y0 + POLE - 0.08, 0), Vector3(ENDS[1], y0 + POLE - 0.08, 0), 0.02, P.CREAM)
	# The pull rope hangs from the first mast to the pip's height, with a wooden toggle.
	var rope := P.pivot(root, Vector3(ENDS[0] + 0.12, y0 + POLE - 0.1, 0.12), "Rope")
	var drop := POLE - 0.55
	P.box(rope, Vector3(0.025, drop, 0.025), P.CREAM, Vector3(0, -drop * 0.5, 0))
	P.box(rope, Vector3(0.16, 0.06, 0.06), P.WOOD_LIGHT, Vector3(0, -drop, 0))
	# The basket of fruit the relay carries.
	P.cyl(root, 0.24, 0.18, P.WOOD_LIGHT, Vector3(ENDS[0] - 0.45, 0.09, -0.35), 0.27)
	for index in range(4): P.sph(root, 0.08, P.LEAF if index % 2 == 0 else P.CORAL, Vector3(ENDS[0] - 0.55 + index * 0.07, 0.24, -0.39 + (index % 2) * 0.08))
	var flag := P.pivot(root, _flag_rest(state), "Flag")
	P.prism(flag, Vector3(0.36, 0.56, 0.02), P.PEACH, Vector3(0.28, 0, 0), Vector3(0, 0, -PI / 2))
	parts.rope = rope
	parts.flag = flag
	if state.get("together", false):
		var m := MINT_MAST
		P.cyl(root, 0.22, 0.1, P.STONE_LIGHT, m + Vector3(0, 0.05, 0), 0.2)
		P.cyl(root, 0.04, POLE * 0.85, P.MINT_DEEP, m + Vector3(0, POLE * 0.425, 0))
		P.sph(root, 0.06, P.MINT, m + Vector3(0, POLE * 0.85 + 0.04, 0))
		P.bar(root, Vector3(ENDS[1], y0 + POLE - 0.08, 0), m + Vector3(0, POLE * 0.85 - 0.08, 0), 0.018, P.CREAM)
		P.prism(root, Vector3(0.24, 0.38, 0.02), P.MINT, m + Vector3(-0.2, POLE * 0.6, 0), Vector3(0, 0, PI / 2))
	if state.get("top", false):
		for index in range(2):
			var lamp := P.pivot(root, Vector3(ENDS[index], y0 + POLE + 0.2, 0), "Lamp")
			P.gold_ball(lamp, Vector3.ZERO, 0.1)
			P.ring(lamp, 0.15, 0.025, P.GOLD_DEEP, Vector3.ZERO, Vector3(PI / 2, 0, 0))
			parts["lamp_%d" % index] = lamp
	return parts

static func _flag_rest(state: Dictionary) -> Vector3:
	return Vector3(ENDS[0] + 0.05, _y0(state) + 0.6, 0)

func upgrade_time(beat: String) -> float:
	return 0.8 if beat == "together" else 0.6

func play(beat: String, anim: RefCounted, parts: Dictionary, state: Dictionary) -> void:
	var sounds: Dictionary = state.get("sounds", {})
	var flag: Node3D = parts.flag
	var y0 := _y0(state)
	var high := y0 + POLE - 0.35
	match beat:
		"base":
			# A tug on the rope runs the flag up the first mast and across to the far one.
			var rope: Node3D = parts.rope
			anim.move(rope, "rotation:x", 0.25, 0.0, 0.18)
			anim.move(rope, "position:y", rope.position.y - 0.12, 0.0, 0.18)
			anim.move(rope, "rotation:x", 0.0, 0.2, 0.25)
			anim.move(rope, "position:y", rope.position.y, 0.2, 0.25)
			anim.sound(str(sounds.get("base", "")), 0.0)
			anim.move(flag, "position", Vector3(ENDS[0] + 0.05, high, 0), 0.1, 0.8)
			anim.move(flag, "position", Vector3(ENDS[1] - 0.45, high, 0), 1.0, 1.1)
			for index in range(3): anim.halo(anim.fx, Vector3(lerpf(ENDS[0], ENDS[1], 0.25 + index * 0.25), high + 0.1, 0), 0.06, P.SNOW, 1.2 + index * 0.25, 0.45, 0.6)
		"together":
			var m := MINT_MAST
			anim.move(flag, "position", Vector3(m.x - 0.45, POLE * 0.85 - 0.4, m.z), 0.0, 0.7)
			anim.sound(str(sounds.get("together", "")), 0.0)
		"hard":
			for index in range(2):
				var flags: Node3D = parts["signals_%d" % index]
				anim.move(flags, "rotation:x", -1.1, index * 0.12, 0.15)
				anim.move(flags, "rotation:x", 0.0, 0.3 + index * 0.08, 0.2)
			anim.sound(str(sounds.get("hard", "")), 0.0)
		"top":
			for index in range(2):
				var lamp: Node3D = parts["lamp_%d" % index]
				brighten(anim, lamp, index * 0.25)
				anim.halo(lamp, Vector3.ZERO, 0.24, P.GOLD, index * 0.25, 0.35)
			anim.sound(str(sounds.get("top", "")), 0.0)

## Walking up to the rope at the first mast tugs it.
func trigger() -> Dictionary:
	return {"area": Rect2(-1.45, 0.34, 0.7, 0.5)}

func solids(state: Dictionary) -> Array[Rect2]:
	var half := 0.3 if state.get("hard", false) else 0.26
	var result: Array[Rect2] = []
	for x: float in ENDS: result.append(Rect2(x - half, -half, half * 2.0, half * 2.0))
	result.append(Rect2(ENDS[0] - 0.72, -0.62, 0.54, 0.54))
	if state.get("together", false): result.append(Rect2(MINT_MAST.x - 0.22, MINT_MAST.z - 0.22, 0.44, 0.44))
	return result

func footprint() -> Rect2:
	return Rect2(-2.05, -0.7, 4.35, 1.6)
