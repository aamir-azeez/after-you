extends "res://presentation/keepsakes/keepsake_builder.gd"
## The First Steps keepsake. Tap: a seed rides the little lift up to ring the
## bell and comes back down. Together: a mint lift on a second rope that comes
## down as yours goes up. Hard: the frame grows taller with a second bell, and
## the lift rings both. Together Hard: two gold leaves on top unfold, and the
## seed on the lift sprouts.
const P = preload("res://presentation/keepsakes/keepsake_parts.gd")
const TOP := 1.0
const LIFT_LOW := 0.1
const LIFT_HIGH := 0.6

func build(root: Node3D, state: Dictionary) -> Dictionary:
	var hard: bool = state.get("hard", false)
	if hard: P.footing(root, 0.94, 0.62)
	var body := P.body(root, state)
	P.box(body, Vector3(0.82, 0.05, 0.42), P.WOOD_LIGHT, Vector3(0, 0.025, 0))
	for x: float in [-0.35, 0.35]: P.box(body, Vector3(0.07, TOP, 0.07), P.WOOD, Vector3(x, TOP * 0.5, 0))
	P.box(body, Vector3(0.82, 0.07, 0.09), P.WOOD, Vector3(0, TOP, 0))
	for x: float in [-0.19, 0.19]: P.box(body, Vector3(0.012, TOP - LIFT_LOW, 0.012), P.CREAM, Vector3(x, (TOP + LIFT_LOW) * 0.5, 0))
	var bell := P.pivot(body, Vector3(0, TOP - 0.035, 0), "Bell")
	P.sph(bell, 0.085, P.PEACH, Vector3(0, -0.1, 0), Vector3(1, 1.2, 1))
	P.ring(bell, 0.085, 0.025, P.CREAM, Vector3(0, -0.17, 0))
	P.sph(bell, 0.025, P.WOOD, Vector3(0, -0.2, 0))
	var ride := P.pivot(body, Vector3(0, LIFT_LOW, 0), "Lift")
	P.box(ride, Vector3(0.42, 0.045, 0.3), P.CREAM, Vector3.ZERO)
	P.sph(ride, 0.07, Color("e8dfb8"), Vector3(0, 0.08, 0), Vector3(1, 1.15, 1))
	P.sph(ride, 0.03, P.LEAF, Vector3(0.02, 0.17, 0), Vector3(0.7, 1.3, 0.5))
	var parts := {"bell": bell, "lift": ride}
	if state.get("together", false):
		var up := lift(state)
		P.box(root, Vector3(0.06, 1.0 + up, 0.06), P.MINT_DEEP, Vector3(0.86, (1.0 + up) * 0.5, 0))
		P.bar(root, Vector3(0.38, up + TOP, 0), Vector3(0.86, up + TOP, 0), 0.045, P.MINT_DEEP)
		P.box(root, Vector3(0.012, TOP - 0.2, 0.012), P.CREAM, Vector3(0.66, up + (TOP + 0.2) * 0.5, 0))
		var mint := P.pivot(root, Vector3(0.66, up + LIFT_HIGH, 0), "MintLift")
		P.box(mint, Vector3(0.22, 0.04, 0.2), P.MINT, Vector3.ZERO)
		P.sph(mint, 0.05, P.MINT, Vector3(0, 0.06, 0), Vector3(1, 1.15, 1))
		parts.mint_lift = mint
	if hard:
		for x: float in [-0.35, 0.35]: P.box(body, Vector3(0.055, 0.32, 0.055), P.WOOD_LIGHT, Vector3(x, TOP + 0.19, 0))
		P.box(body, Vector3(0.78, 0.05, 0.07), P.WOOD_LIGHT, Vector3(0, TOP + 0.35, 0))
		var top_bell := P.pivot(body, Vector3(0, TOP + 0.32, 0), "TopBell")
		P.sph(top_bell, 0.06, P.PEACH, Vector3(0, -0.07, 0), Vector3(1, 1.2, 1))
		P.ring(top_bell, 0.06, 0.02, P.CREAM, Vector3(0, -0.12, 0))
		parts.top_bell = top_bell
	if state.get("top", false):
		var cap := TOP + (0.38 if hard else 0.04)
		P.cyl(body, 0.012, 0.1, P.LEAF, Vector3(0, cap + 0.05, 0))
		var leaves := P.pivot(body, Vector3(0, cap + 0.1, 0), "GoldLeaves")
		leaves.scale = Vector3.ONE * P.TOP_SCALE
		for side: int in [-1, 1]: P.node(leaves, P.low_sphere(0.07), P.gold(), Vector3(side * 0.06, 0.02, 0), Vector3(0, 0, side * 0.5), Vector3(1.0, 0.45, 0.6))
		parts.leaves = leaves
	return parts

func play(beat: String, anim: RefCounted, parts: Dictionary, state: Dictionary) -> void:
	var lift_part: Node3D = parts.lift
	var sounds: Dictionary = state.get("sounds", {})
	match beat:
		"base":
			anim.move(lift_part, "position:y", LIFT_HIGH, 0.0, 0.85)
			_ring_bell(anim, parts.bell, 0.85)
			anim.move(lift_part, "position:y", LIFT_LOW, 1.35, 0.8)
			anim.sound(str(sounds.get("base", "")), 0.85)
		"together":
			var mint: Node3D = parts.mint_lift
			var rest_y := mint.position.y
			anim.move(lift_part, "position:y", LIFT_HIGH, 0.0, 0.32)
			anim.move(mint, "position:y", rest_y - (LIFT_HIGH - LIFT_LOW), 0.0, 0.32)
			anim.move(lift_part, "position:y", LIFT_LOW, 0.38, 0.3)
			anim.move(mint, "position:y", rest_y, 0.38, 0.3)
			anim.sound(str(sounds.get("together", "")), 0.0)
		"hard":
			anim.move(lift_part, "position:y", TOP + 0.12, 0.0, 0.35)
			_ring_bell(anim, parts.top_bell, 0.35)
			anim.move(lift_part, "position:y", LIFT_LOW, 0.45, 0.25)
			anim.sound(str(sounds.get("hard", "")), 0.35)
		"top":
			var leaves: Node3D = parts.leaves
			anim.move(leaves, "scale", Vector3(1.5, 1.2, 1.5) * P.TOP_SCALE, 0.0, 0.3, Tween.TRANS_BACK, Tween.EASE_OUT)
			brighten(anim, leaves, 0.0)
			var sprout: MeshInstance3D = anim.spawn(lift_part, P.low_sphere(0.04), P.mat(P.LEAF), Vector3(0, 0.24, 0), Vector3.ZERO, Vector3(1.0, 0.45, 0.6))
			anim.set_at(sprout, "visible", true, 0.1)
			anim.move(sprout, "scale", Vector3(2.2, 0.9, 1.2), 0.1, 0.4, Tween.TRANS_BACK, Tween.EASE_OUT)
			anim.sound(str(sounds.get("top", "")), 0.0)

func _ring_bell(anim: RefCounted, bell: Node3D, at: float) -> void:
	anim.move(bell, "rotation:z", 0.4, at, 0.1)
	anim.move(bell, "rotation:z", -0.3, at + 0.1, 0.15)
	anim.move(bell, "rotation:z", 0.0, at + 0.25, 0.2)

func footing_size() -> Vector2:
	return Vector2(0.94, 0.62)

func footprint() -> Rect2:
	return Rect2(-0.47, -0.31, 1.4, 0.62)
