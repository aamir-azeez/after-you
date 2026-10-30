extends "res://presentation/keepsakes/keepsake_builder.gd"
## The A House for Two keepsake: a little house the pip walks into. Walking up
## to the door (or a tap) swings the door and the shutters open and lights the
## windows. While the pip is at the door or inside, the roof and the front wall
## fade away the way raised floors fade in the chapters (kit/cutaway.gd), and
## the inside is there: a lamp on over two chairs at a table. Together: a mint
## mailbox by the path with a letter waiting, and two mugs on the table, one in
## the friend's mint. Hard: the house stands on a slate cellar with porch
## steps; a hatch in the floor glows and the cellar window lights. Together
## Hard: a gold chimney that puffs rings of smoke, and a gold fireplace inside.
## The inside is made only while the pip is there, and goes when it leaves.
const P = preload("res://presentation/keepsakes/keepsake_parts.gd")
const Cutaway = preload("res://presentation/kit/cutaway.gd")
## The house is drawn this much larger than its pieces.
const SIZE := 1.3
const W := 1.9
const D := 1.5
const H := 1.25
const CELLAR := 0.42
const DOOR_X := -0.45
const DOOR_W := 0.42
const MAILBOX := Vector3(1.4, 0, 0.95)

static func _y0(state: Dictionary) -> float:
	return CELLAR if state.get("hard", false) else 0.0

func build(root: Node3D, state: Dictionary) -> Dictionary:
	var house := P.grown(root, SIZE)
	var hard: bool = state.get("hard", false)
	var y0 := _y0(state)
	var windows := P.pivot(house, Vector3.ZERO, "Windows")
	if hard:
		# The cellar (Hard's footing): a slate storey under the house, porch
		# steps and a cellar window.
		var cellar := P.pivot(house, Vector3.ZERO, "Footing")
		P.box(cellar, Vector3(W + 0.1, y0, D + 0.1), P.SLATE, Vector3(0, y0 * 0.5, 0))
		P.box(windows, Vector3(0.42, 0.16, 0.03), P.LAMP_OFF, Vector3(0.5, y0 * 0.5, D * 0.5 + 0.06))
		P.prism(cellar, Vector3(0.26, 0.13, 0.03), P.SNOW, Vector3(-0.5, y0 * 0.5, D * 0.5 + 0.06))
		for index in range(2): P.box(cellar, Vector3(0.6, 0.21, 0.26), P.STONE_LIGHT, Vector3(DOOR_X + DOOR_W * 0.5, 0.105 + index * 0.21, D * 0.5 + 0.18 + (1 - index) * 0.24))
	# The floor stops just inside the walls, so no face lies on a wall's.
	P.box(house, Vector3(W - 0.04, 0.06, D - 0.04), P.WOOD_LIGHT, Vector3(0, y0 + 0.03, 0))
	# The back and side walls always stand.
	P.box(house, Vector3(W, H, 0.08), P.CREAM, Vector3(0, y0 + H * 0.5, -D * 0.5))
	for side: int in [-1, 1]: P.box(house, Vector3(0.08, H, D), P.CREAM, Vector3(side * W * 0.5, y0 + H * 0.5, 0))
	P.box(windows, Vector3(0.5, 0.38, 0.03), P.LAMP_OFF, Vector3(0.35, y0 + 0.75, -D * 0.5 + 0.05))
	# The front wall (round the doorway) and the roof cut away as one.
	var cut := P.pivot(house, Vector3.ZERO, "Cutaway")
	var left := DOOR_X + W * 0.5
	var right := W * 0.5 - (DOOR_X + DOOR_W)
	P.box(cut, Vector3(left, H, 0.08), P.CREAM, Vector3(-W * 0.5 + left * 0.5, y0 + H * 0.5, D * 0.5))
	P.box(cut, Vector3(right, H, 0.08), P.CREAM, Vector3(W * 0.5 - right * 0.5, y0 + H * 0.5, D * 0.5))
	P.box(cut, Vector3(DOOR_W, H - 0.86, 0.08), P.CREAM, Vector3(DOOR_X + DOOR_W * 0.5, y0 + 0.86 + (H - 0.86) * 0.5, D * 0.5))
	P.prism(cut, Vector3(W + 0.2, 0.85, D + 0.3), P.ROOF, Vector3(0, y0 + H + 0.42, 0))
	P.box(cut, Vector3(0.44, 0.36, 0.03), P.LAMP_OFF, Vector3(0.45, y0 + 0.72, D * 0.5 + 0.05))
	var door := P.pivot(cut, Vector3(DOOR_X, y0 + 0.06, D * 0.5 + 0.05), "Door")
	P.box(door, Vector3(DOOR_W, 0.8, 0.05), P.WOOD, Vector3(DOOR_W * 0.5, 0.4, 0))
	P.sph(door, 0.03, P.GOLD, Vector3(0.36, 0.4, 0.03))
	var parts := {"cutaway": cut, "door": door, "windows": windows}
	for side: int in [-1, 1]:
		var shutter := P.pivot(cut, Vector3(0.45 + side * 0.24, y0 + 0.72, D * 0.5 + 0.08), "Shutter")
		P.box(shutter, Vector3(0.2, 0.4, 0.03), P.PEACH, Vector3(-side * 0.1, 0, 0))
		parts["shutter_%s" % ("left" if side < 0 else "right")] = shutter
	P.box(house, Vector3(0.55, 0.02, 0.32), P.CORAL, Vector3(-0.25, 0.01, D * 0.5 + 0.35 + (0.4 if hard else 0.0)))
	if state.get("together", false):
		var at := MAILBOX
		P.box(house, Vector3(0.07, 0.85, 0.07), P.WOOD, at + Vector3(0, 0.42, 0))
		P.box(house, Vector3(0.28, 0.24, 0.42), P.MINT, at + Vector3(0, 0.95, 0))
		P.node(house, P.Primitives.shared_mesh("cylinder", 0.14, 0.42, 0.14), P.mat(P.MINT), at + Vector3(0, 1.07, 0), Vector3(PI / 2, 0, 0))
		var flag := P.pivot(house, at + Vector3(0.15, 0.95, -0.1), "MailFlag")
		flag.rotation.z = -PI / 2
		P.box(flag, Vector3(0.035, 0.24, 0.05), P.CORAL, Vector3(0, 0.12, 0))
		parts.mail_flag = flag
	if state.get("top", false):
		P.box(house, Vector3(0.24, 0.6, 0.24), P.GOLD_DEEP, Vector3(-0.35, y0 + H + 0.45, -D * 0.5 + 0.12)).material_override = P.gold()
		P.box(house, Vector3(0.3, 0.06, 0.3), P.GOLD, Vector3(-0.35, y0 + H + 0.78, -D * 0.5 + 0.12))
	return parts

func base_time() -> float:
	return 1.8

func upgrade_time(beat: String) -> float:
	return 0.7 if beat == "top" else 0.6

func play(beat: String, anim: RefCounted, parts: Dictionary, state: Dictionary) -> void:
	var sounds: Dictionary = state.get("sounds", {})
	var y0 := _y0(state)
	match beat:
		"base":
			# The door and the shutters swing open and the windows light.
			anim.move(parts.door, "rotation:y", -1.45, 0.0, 0.45, Tween.TRANS_BACK, Tween.EASE_OUT)
			anim.move(parts.shutter_left, "rotation:y", 1.3, 0.15, 0.4, Tween.TRANS_BACK, Tween.EASE_OUT)
			anim.move(parts.shutter_right, "rotation:y", -1.3, 0.2, 0.4, Tween.TRANS_BACK, Tween.EASE_OUT)
			_light(anim, parts.windows, 0.3)
			anim.sound(str(sounds.get("base", "")), 0.0)
		"together":
			# The mailbox flag pops up with a letter waiting.
			anim.move(parts.mail_flag, "rotation:z", 0.0, 0.0, 0.25, Tween.TRANS_BACK, Tween.EASE_OUT)
			var letter: MeshInstance3D = anim.spawn(anim.fx, P.Primitives.shared_mesh("box", 0.2 * SIZE, 0.13 * SIZE, 0.015 * SIZE), P.mat(P.SNOW), (MAILBOX + Vector3(0, 1.02, 0.23)) * SIZE, Vector3(0, 0, 0.15))
			anim.set_at(letter, "visible", true, 0.15)
			anim.move(letter, "position:y", (MAILBOX.y + 1.12) * SIZE, 0.15, 0.3, Tween.TRANS_BACK, Tween.EASE_OUT)
			anim.sound(str(sounds.get("together", "")), 0.0)
		"hard":
			anim.halo(anim.fx, Vector3(0.5, y0 * 0.5, D * 0.5 + 0.08) * SIZE, 0.25, P.LAMP, 0.0, 0.55)
			anim.sound(str(sounds.get("hard", "")), 0.0)
		"top":
			# The gold chimney puffs three rings of smoke.
			var chimney := Vector3(-0.35, y0 + H + 0.85, -D * 0.5 + 0.12) * SIZE
			for index in range(3):
				var ring: MeshInstance3D = anim.spawn(anim.fx, P.torus(0.12, 0.05), P.mat(P.SNOW), chimney, Vector3(PI / 2, 0, 0), Vector3.ONE * 0.6)
				anim.set_at(ring, "visible", true, index * 0.15)
				anim.move(ring, "position", chimney + Vector3(index * 0.12, 0.5 + index * 0.1, 0), index * 0.15, 0.45, Tween.TRANS_QUAD, Tween.EASE_OUT)
				anim.move(ring, "scale", Vector3.ONE * (1.1 + index * 0.25), index * 0.15, 0.45)
				anim.set_at(ring, "visible", false, index * 0.15 + 0.5)
			anim.sound(str(sounds.get("top", "")), 0.0)

## Lights every unlit window under `windows` from `at`.
func _light(anim: RefCounted, windows: Node3D, at: float) -> void:
	for found: Node in windows.get_children():
		if found is MeshInstance3D and (found as MeshInstance3D).material_override == P.mat(P.LAMP_OFF): anim.set_at(found, "material_override", P.glow(P.LAMP, 1.6), at)

# --- inside -----------------------------------------------------------------------------

## Walking up to the door.
func trigger() -> Dictionary:
	return {"area": Rect2((DOOR_X - 0.15) * SIZE, D * 0.5 * SIZE + 0.05, (DOOR_W + 0.3) * SIZE, 0.55)}

## At the door and inside.
func stay() -> Rect2:
	return Rect2((-W * 0.5 + 0.04) * SIZE, (-D * 0.5 + 0.04) * SIZE, (W - 0.08) * SIZE, (D - 0.04) * SIZE + 0.75)

## The roof and front wall fade, and the inside is made under `visit`.
func arrive(visit: Node3D, parts: Dictionary, state: Dictionary) -> String:
	Cutaway.set_faded(parts.cutaway, true)
	var room := P.grown(visit, SIZE)
	var y0 := _y0(state)
	# A lamp on over two chairs at a table.
	P.cyl(room, 0.32, 0.06, P.WOOD, Vector3(0.1, y0 + 0.48, -0.2))
	P.cyl(room, 0.05, 0.42, P.WOOD, Vector3(0.1, y0 + 0.24, -0.2))
	for side: int in [-1, 1]:
		var color := P.PEACH if side < 0 else P.MINT
		P.box(room, Vector3(0.24, 0.05, 0.24), color, Vector3(0.1 + side * 0.48, y0 + 0.3, -0.2))
		P.box(room, Vector3(0.05, 0.32, 0.24), color, Vector3(0.1 + side * 0.6, y0 + 0.46, -0.2))
	P.cyl(room, 0.02, 0.9, P.WOOD, Vector3(-0.75, y0 + 0.45, -0.5))
	P.node(room, P.Primitives.shared_mesh("cone", 0.16, 0.18), P.glow(P.LAMP, 1.4), Vector3(-0.75, y0 + 0.96, -0.5))
	_glow(room, Vector3(-0.75, y0 + 0.9, -0.5), 0.35, P.LAMP, 0.18)
	if state.get("together", false):
		P.cyl(room, 0.045, 0.09, P.MINT, Vector3(0.25, y0 + 0.56, -0.15))
		P.cyl(room, 0.045, 0.09, P.PEACH, Vector3(-0.05, y0 + 0.56, -0.25))
	if state.get("hard", false):
		P.box(room, Vector3(0.4, 0.02, 0.4), Color("6e5b47"), Vector3(-0.55, y0 + 0.07, 0.15))
		_glow(room, Vector3(-0.55, y0 + 0.05, 0.15), 0.22, P.LAMP, 0.22)
	if state.get("top", false):
		P.node(room, P.Primitives.shared_mesh("box", 0.6, 0.55, 0.18), P.gold(), Vector3(-0.35, y0 + 0.3, -D * 0.5 + 0.12))
		P.node(room, P.Primitives.shared_mesh("box", 0.3, 0.25, 0.05), P.glow(Color("f09a3e"), 1.6), Vector3(-0.35, y0 + 0.22, -D * 0.5 + 0.22))
	# The door's own play sounds as the pip walks up; going in is quiet.
	return ""

static func _glow(parent: Node3D, at: Vector3, radius: float, color: Color, alpha: float) -> void:
	var glow := P.node(parent, P.low_sphere(radius), P.clear(color, alpha, 1.4), at)
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func depart(parts: Dictionary, _state: Dictionary) -> void:
	if is_instance_valid(parts.get("cutaway")): Cutaway.set_faded(parts.cutaway, false)

## The house's floor inside, and the porch on Hard.
func floor(state: Dictionary, at: Vector2) -> float:
	var y0 := _y0(state) * SIZE
	var inside := 0.06 * SIZE + y0
	var front := D * 0.5 * SIZE
	if at.y <= front: return inside
	if not state.get("hard", false): return 0.0
	return lerpf(inside, 0.0, clampf((at.y - front) / 0.65, 0.0, 1.0))

func solids(state: Dictionary) -> Array[Rect2]:
	var s := SIZE
	var t := 0.06 * s
	var x0 := -W * 0.5 * s
	var z0 := -D * 0.5 * s
	var z1 := D * 0.5 * s
	var door0 := DOOR_X * s
	var door1 := (DOOR_X + DOOR_W) * s
	var result: Array[Rect2] = [Rect2(x0, z0 - t, W * s, t * 2.0), Rect2(x0 - t, z0, t * 2.0, D * s), Rect2(-x0 - t, z0, t * 2.0, D * s),
		Rect2(x0, z1 - t, door0 - x0, t * 2.0), Rect2(door1, z1 - t, -x0 - door1, t * 2.0)]
	if state.get("together", false): result.append(Rect2((MAILBOX.x - 0.15) * s, (MAILBOX.z - 0.22) * s, 0.3 * s, 0.44 * s))
	return result

func footprint() -> Rect2:
	return Rect2(-1.4, -1.2, 3.85, 3.4)
