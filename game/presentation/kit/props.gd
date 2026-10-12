extends RefCounted
## World kit: scenery props built from a chapter's dressing data
## (content/dressing). Props are visual only: no collision, no state, never
## read by a simulation. Every kind also reports its extent, which the
## dressing lint uses to keep props off routes and out of the camera's view of
## the spirits and controls.
##
## A spec is a Dictionary: "kind", "at" [x_cm, z_cm], optional "surface"
## (island id whose height it stands on), "y" (cm above that), "size" (scale),
## "rot" (degrees about Y), and kind-specific fields. Line kinds (fence, hedge,
## row) take "from" and "to" instead of "at".

const Primitives = preload("res://presentation/kit/primitives.gd")

const TIMBER := Color("8a6b4e")
const TIMBER_LIGHT := Color("b08a62")
const TIMBER_DARK := Color("6b5038")
const TRUNK := Color("806f59")
const LEAF := Color("7fa36a")
const LEAF_DARK := Color("5f8a5a")
const LEAF_LIGHT := Color("9cbf7e")
const CROWN := Color("659d86")
const CROWN_LIGHT := Color("8daf83")
const FRUIT := Color("ebc28f")
const BLOSSOMS := [Color("f1c27d"), Color("e9a3a0"), Color("f4ecd0"), Color("d6b0e0")]
const LAMP := Color("ffd894")
const LAMP_GLOW := Color("f2a94e")
const STONE := Color("c9b79a")
const STONE_DARK := Color("a3906f")
const PLASTER := Color("efe2c4")
const ROOF := Color("b5654a")
const ROOF_DARK := Color("8f4b38")
const POT := Color("b97b5a")
const PICKET := Color("efe4c8")
const WINDOW_WARM := Color("ffe0a0")
const ROPE := Color("d1b98c")

## Kinds lower than this (metres) never hide a spirit or a control.
const LOW := 0.16

## Footprint (metres, world xz), height above its base and the base offset.
## "flat" props may lie on walkable floor; every other prop must stay off it.
static func extent(spec: Dictionary) -> Dictionary:
	var s := float(spec.get("size", 1.0))
	var kind := str(spec.get("kind", ""))
	var radius := 0.2 * s
	var height := 0.3 * s
	var half := Vector2.ZERO
	match kind:
		"tree": radius = 0.42 * s; height = 1.55 * s
		"pine": radius = 0.42 * s; height = 1.7 * s
		"bush": radius = 0.32 * s; height = 0.45 * s
		"flowers": radius = 0.32 * s; height = 0.14 * s
		"tuft": radius = 0.08 * s; height = 0.012
		"bank":
			var r: Array = spec.rect
			return {"rect": Rect2(Vector2(float(r[0]), float(r[1])) / 100.0, Vector2(float(r[2] - r[0]), float(r[3] - r[1])) / 100.0), "height": float(spec.get("height", 12)) / 100.0 + 0.3, "base": float(spec.get("y", 0)) / 100.0 - 0.3, "flat": false}
		"rock": radius = 0.28 * s; height = 0.2 * s
		"lantern": radius = 0.14 * s; height = 0.9 * s
		"lamp_post": radius = 0.16 * s; height = 1.45 * s
		"bench": half = Vector2(0.42, 0.16) * s; height = 0.45 * s
		"pot": radius = 0.12 * s; height = 0.34 * s
		"fern": radius = 0.28 * s; height = 0.4 * s
		"crate": radius = 0.2 * s; height = 0.32 * s * (2.0 if spec.get("stack", false) else 1.0)
		"signpost": radius = 0.3 * s; height = 1.05 * s
		"cottage": half = Vector2(float(spec.get("width", 160)), float(spec.get("depth", 110))) / 200.0 * s; height = 2.0 * s
		"tower": radius = 0.75 * s; height = 3.3 * s
		"post": radius = 0.07 * s; height = float(spec.get("height", 100)) / 100.0
		"rug", "path": half = Vector2(float(spec.get("width", 100)), float(spec.get("depth", 60))) / 200.0; height = 0.018
		"planter": half = Vector2(float(spec.get("width", 120)), float(spec.get("depth", 40))) / 200.0; height = 0.45 * s
		"basket": radius = 0.16 * s; height = 0.34 * s
		"ivy": radius = 0.07 * s; height = 0.0
		"boat": half = Vector2(0.62, 0.26) * s; height = 0.4 * s
		"bollard": radius = 0.08 * s; height = 0.15 * s
		"barrel": radius = 0.15 * s; height = 0.32 * s
		"lobster_pot": half = Vector2(0.20, 0.14) * s; height = 0.18 * s
		"shelf": half = Vector2(0.45, 0.1) * s; height = 0.5 * s
		"frame": half = Vector2(0.22, 0.03) * s; height = 0.3 * s
		"fence", "hedge", "wall":
			var from := _point(spec.from)
			var to := _point(spec.to)
			var width := 0.06 if kind == "fence" else 0.36 * s if kind == "hedge" else float(spec.get("thickness", 12)) / 100.0
			var rect := Rect2(from.min(to), Vector2.ZERO).expand(from.max(to)).grow(width * 0.5)
			var tall := 0.38 * s if kind == "fence" else 0.5 * s if kind == "hedge" else float(spec.get("height", 120)) / 100.0
			return {"rect": rect, "height": tall, "base": float(spec.get("y", 0)) / 100.0, "flat": false}
	if bool(spec.get("wall", false)): radius = minf(radius, 0.12)
	var at := _point(spec.get("at", [0, 0]))
	var footprint := Rect2(at - half, half * 2.0) if half != Vector2.ZERO else Rect2(at - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)
	if half != Vector2.ZERO and absf(fmod(float(spec.get("rot", 0)), 180.0)) > 45.0 and absf(fmod(float(spec.get("rot", 0)), 180.0)) < 135.0:
		footprint = Rect2(at - Vector2(half.y, half.x), Vector2(half.y, half.x) * 2.0)
	var base := float(spec.get("y", 0)) / 100.0
	if kind == "ivy": base -= float(spec.get("length", 60)) / 100.0
	return {"rect": footprint, "height": height, "base": base, "flat": height <= 0.02 or kind in ["ivy"], "wall": bool(spec.get("wall", false))}

## Expands rows into single props; every other spec passes through.
static func expand(specs: Array) -> Array:
	var result: Array = []
	for spec: Dictionary in specs:
		if str(spec.get("kind", "")) != "row":
			result.append(spec)
			continue
		var count := int(spec.get("count", 2))
		var from := Vector2(float(spec.from[0]), float(spec.from[1]))
		var to := Vector2(float(spec.to[0]), float(spec.to[1]))
		for index in range(count):
			var item: Dictionary = spec.of.duplicate(true)
			var at := from.lerp(to, float(index) / float(maxi(count - 1, 1)))
			item["at"] = [at.x, at.y]
			for key: String in ["surface", "y"]:
				if spec.has(key) and not item.has(key): item[key] = spec[key]
			if spec.get("vary", false):
				item["size"] = float(item.get("size", 1.0)) * (0.85 + 0.15 * absf(sin(float(index) * 2.3 + at.x)))
				item["rot"] = float(item.get("rot", 0)) + float(index) * 47.0
			result.append(item)
	return result

static func _point(coords: Array) -> Vector2:
	return Vector2(float(coords[0]), float(coords[1])) / 100.0

## Builds one prop under parent at base height base_y (metres). lit: lanterns
## and windows glow. Returns the prop root, or null for an unknown kind.
static func build(spec: Dictionary, parent: Node3D, base_y: float, lit: bool) -> Node3D:
	var kind := str(spec.get("kind", ""))
	var root := Node3D.new()
	root.name = "Prop_" + kind
	root.set_meta("dressing_kind", kind)
	parent.add_child(root)
	var s := float(spec.get("size", 1.0))
	if spec.has("at"):
		var at := _point(spec.at)
		root.position = Vector3(at.x, base_y + float(spec.get("y", 0)) / 100.0, at.y)
		root.rotation.y = deg_to_rad(float(spec.get("rot", 0)))
	else:
		root.position = Vector3(0, base_y + float(spec.get("y", 0)) / 100.0, 0)
	match kind:
		"tree": _tree(root, s, int(spec.get("variant", 0)))
		"pine": _pine(root, s)
		"bush": _bush(root, s, spec.get("flowers", true))
		"flowers": _flowers(root, s)
		"tuft": _tuft(root, s)
		"rock": _rock(root, s)
		"lantern": _lantern(root, s, lit)
		"lamp_post": _lamp_post(root, s, lit)
		"bench": _bench(root, s)
		"pot": _pot(root, s)
		"fern": _fern(root, s)
		"crate": _crate(root, s, bool(spec.get("stack", false)))
		"signpost": _signpost(root, s)
		"cottage": _cottage(root, s, float(spec.get("width", 160)) / 100.0, float(spec.get("depth", 110)) / 100.0, lit)
		"tower": _tower(root, s, lit)
		"post": _post(root, float(spec.get("height", 100)) / 100.0, s)
		"rug": _rug(root, float(spec.get("width", 100)) / 100.0, float(spec.get("depth", 60)) / 100.0, spec.get("color", "c98f6a"))
		"path": _path(root, float(spec.get("width", 100)) / 100.0, float(spec.get("depth", 60)) / 100.0)
		"planter": _planter(root, float(spec.get("width", 120)) / 100.0, float(spec.get("depth", 40)) / 100.0, s)
		"basket": _basket(root, s)
		"ivy": _ivy(root, float(spec.get("length", 60)) / 100.0)
		"boat": _boat(root, s)
		"bollard": _bollard(root, s)
		"barrel": _barrel(root, s)
		"lobster_pot": _lobster_pot(root, s)
		"shelf": _shelf(root, s)
		"frame": _frame(root, s, spec.get("color", "9cbf7e"))
		"fence": _fence(root, _point(spec.from), _point(spec.to), s)
		"hedge": _hedge(root, _point(spec.from), _point(spec.to), s)
		"bank": _bank(root, spec)
		"wall": _wall(root, _point(spec.from), _point(spec.to), float(spec.get("height", 120)) / 100.0, float(spec.get("thickness", 12)) / 100.0, spec.get("color", "efe2c4"))
		_:
			root.free()
			return null
	return root

static func _m(color: Color, glow: float = 0.0) -> StandardMaterial3D:
	return Primitives.shared_material(color, 0.9, LAMP_GLOW if glow > 0.0 else Color(0, 0, 0, 0), glow)

static func _box(size: Vector3, color: Color, at: Vector3, parent: Node3D, glow: float = 0.0) -> MeshInstance3D:
	return Primitives.mesh_node(Primitives.shared_mesh("box", size.x, size.y, size.z), _m(color, glow), at, parent)

static func _ball(radius: float, color: Color, at: Vector3, parent: Node3D, squash: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var node := Primitives.mesh_node(Primitives.shared_mesh("sphere", radius), _m(color), at, parent)
	node.scale = squash
	return node

static func _rod(radius: float, height: float, color: Color, at: Vector3, parent: Node3D) -> MeshInstance3D:
	return Primitives.mesh_node(Primitives.shared_mesh("cylinder", radius, height, radius), _m(color), at, parent)

static func _tree(root: Node3D, s: float, variant: int) -> void:
	_rod(0.07 * s, 0.85 * s, TRUNK, Vector3(0, 0.42 * s, 0), root)
	var tints := [CROWN, CROWN_LIGHT, LEAF] if variant % 2 == 0 else [LEAF_DARK, CROWN, LEAF_LIGHT]
	for lobe in range(3):
		_ball(0.4 * s, tints[lobe], Vector3((lobe - 1) * 0.2 * s, (1.02 + 0.2 * (1 - absi(lobe - 1))) * s, 0.02 * lobe * s), root, Vector3(0.84, 1.22, 0.84))
	if variant % 3 != 2:
		for j in range(3):
			_ball(0.06 * s, FRUIT if variant % 3 == 0 else BLOSSOMS[1], Vector3(sin(j * 2.1) * 0.29 * s, (0.96 + 0.12 * j) * s, cos(j * 2.1) * 0.24 * s + 0.08 * s), root)

static func _pine(root: Node3D, s: float) -> void:
	_rod(0.06 * s, 0.5 * s, TRUNK, Vector3(0, 0.25 * s, 0), root)
	for tier in range(3):
		var cone := Primitives.mesh_node(Primitives.shared_mesh("cone", (0.42 - tier * 0.1) * s, 0.6 * s), _m(LEAF_DARK if tier % 2 == 0 else CROWN), Vector3(0, (0.62 + tier * 0.36) * s, 0), root)
		cone.name = "Tier%d" % tier

static func _bush(root: Node3D, s: float, flowered: Variant) -> void:
	for lobe in range(3):
		_ball(0.2 * s, LEAF.darkened(0.06 * lobe), Vector3((lobe - 1) * 0.16 * s, 0.2 * s, 0.03 * (lobe % 2) * s), root, Vector3(1.1, 0.95, 0.95))
	if flowered:
		for j in range(3):
			_ball(0.045 * s, BLOSSOMS[j % BLOSSOMS.size()], Vector3((j - 1) * 0.15 * s, 0.36 * s, 0.1 * s), root)

static func _flowers(root: Node3D, s: float) -> void:
	for j in range(7):
		var a := float(j) * 2.39996
		var r := (0.06 + 0.04 * float(j % 4)) * s * 1.5
		var at := Vector3(sin(a) * r, 0.0, cos(a) * r)
		_rod(0.012 * s, 0.12 * s, LEAF_DARK, at + Vector3(0, 0.06 * s, 0), root)
		_ball(0.045 * s, BLOSSOMS[j % BLOSSOMS.size()], at + Vector3(0, 0.125 * s, 0), root)
	_ball(0.16 * s, LEAF, Vector3(0, 0.02 * s, 0), root, Vector3(1.6, 0.25, 1.4))

static func _tuft(root: Node3D, s: float) -> void:
	for j in range(3):
		var blade := _box(Vector3(0.022, 0.08 + j * 0.03, 0.03) * s, Color("6f9a64"), Vector3((j - 1) * 0.035 * s, (0.04 + j * 0.012) * s, 0), root)
		blade.rotation.z = (j - 1) * 0.3

static func _rock(root: Node3D, s: float) -> void:
	_ball(0.22 * s, STONE_DARK, Vector3(0, 0.07 * s, 0), root, Vector3(1.3, 0.62, 1.0))
	_ball(0.12 * s, STONE, Vector3(0.18 * s, 0.05 * s, 0.08 * s), root, Vector3(1.2, 0.6, 1.0))

static func _lantern(root: Node3D, s: float, lit: bool) -> void:
	var h := 0.85 * s
	_box(Vector3(0.05, h, 0.05) * Vector3(s, 1, s), TIMBER_DARK, Vector3(0, h * 0.5, 0), root)
	_box(Vector3(0.17, 0.03, 0.03) * s, TIMBER_DARK, Vector3(0.06 * s, h - 0.02 * s, 0), root)
	var glass := _box(Vector3(0.12, 0.15, 0.12) * s, LAMP, Vector3(0.12 * s, h - 0.13 * s, 0), root, 0.8 if lit else 0.0)
	glass.name = "LanternGlass"
	_box(Vector3(0.16, 0.035, 0.16) * s, TIMBER_DARK, Vector3(0.12 * s, h - 0.04 * s, 0), root)

static func _lamp_post(root: Node3D, s: float, lit: bool) -> void:
	_rod(0.1 * s, 0.06 * s, TIMBER_DARK, Vector3(0, 0.03 * s, 0), root)
	_rod(0.03 * s, 1.2 * s, Color("4f4a44"), Vector3(0, 0.6 * s, 0), root)
	var glass := _ball(0.13 * s, LAMP, Vector3(0, 1.3 * s, 0), root, Vector3(0.9, 1.1, 0.9))
	glass.material_override = _m(LAMP, 1.1 if lit else 0.0)
	glass.name = "LampGlass"
	var cap := Primitives.mesh_node(Primitives.shared_mesh("cone", 0.17 * s, 0.12 * s), _m(Color("4f4a44")), Vector3(0, 1.45 * s, 0), root)
	cap.name = "LampCap"

static func _bench(root: Node3D, s: float) -> void:
	_box(Vector3(0.82, 0.05, 0.24) * s, TIMBER_LIGHT, Vector3(0, 0.25 * s, 0), root)
	_box(Vector3(0.82, 0.16, 0.04) * s, TIMBER_LIGHT, Vector3(0, 0.38 * s, -0.11 * s), root)
	for x: float in [-0.34, 0.34]: _box(Vector3(0.05, 0.25, 0.2) * s, TIMBER, Vector3(x * s, 0.125 * s, 0), root)

static func _pot(root: Node3D, s: float) -> void:
	Primitives.mesh_node(Primitives.shared_mesh("cylinder", 0.08 * s, 0.14 * s, 0.11 * s), _m(POT), Vector3(0, 0.07 * s, 0), root)
	_ball(0.11 * s, LEAF, Vector3(0, 0.2 * s, 0), root, Vector3(1.1, 0.9, 1.1))
	_ball(0.04 * s, BLOSSOMS[0], Vector3(0.05 * s, 0.29 * s, 0.03 * s), root)

static func _fern(root: Node3D, s: float) -> void:
	Primitives.mesh_node(Primitives.shared_mesh("cylinder", 0.12 * s, 0.18 * s, 0.15 * s), _m(POT), Vector3(0, 0.09 * s, 0), root)
	for j in range(6):
		var a := float(j) * TAU / 6.0
		var frond := _ball(0.16 * s, LEAF_DARK if j % 2 == 0 else LEAF, Vector3(sin(a) * 0.12 * s, 0.27 * s, cos(a) * 0.12 * s), root, Vector3(0.45, 0.22, 1.0))
		frond.rotation = Vector3(-0.5, a, 0)

static func _crate(root: Node3D, s: float, stack: bool) -> void:
	_box(Vector3(0.32, 0.3, 0.32) * s, TIMBER_LIGHT, Vector3(0, 0.15 * s, 0), root)
	_box(Vector3(0.34, 0.04, 0.34) * s, TIMBER, Vector3(0, 0.29 * s, 0), root)
	if stack:
		var top := _box(Vector3(0.24, 0.22, 0.24) * s, TIMBER_LIGHT.lightened(0.08), Vector3(0.02 * s, 0.42 * s, 0.01 * s), root)
		top.rotation.y = 0.3

static func _signpost(root: Node3D, s: float) -> void:
	_box(Vector3(0.07, 1.0, 0.07) * Vector3(s, s, s), TIMBER, Vector3(0, 0.5 * s, 0), root)
	var one := _box(Vector3(0.46, 0.12, 0.035) * s, TIMBER_LIGHT, Vector3(0.14 * s, 0.86 * s, 0.03 * s), root)
	one.rotation.y = 0.15
	var two := _box(Vector3(0.4, 0.11, 0.035) * s, TIMBER_LIGHT.lightened(0.06), Vector3(-0.12 * s, 0.66 * s, 0.03 * s), root)
	two.rotation.y = -0.2

static func _cottage(root: Node3D, s: float, width: float, depth: float, lit: bool) -> void:
	var w := width * s
	var d := depth * s
	var wall_h := 1.15 * s
	_box(Vector3(w, wall_h, d), PLASTER, Vector3(0, wall_h * 0.5, 0), root)
	_box(Vector3(w + 0.06, 0.12 * s, d + 0.04), STONE_DARK, Vector3(0, 0.06 * s, 0), root)
	var roof := Primitives.mesh_node(Primitives.shared_mesh("prism", w + 0.24 * s, 0.72 * s, d + 0.22 * s), _m(ROOF), Vector3(0, wall_h + 0.36 * s, 0), root)
	roof.name = "CottageRoof"
	_box(Vector3(0.14, 0.42, 0.14) * s, ROOF_DARK, Vector3(w * 0.28, wall_h + 0.55 * s, -d * 0.15), root)
	# The door and windows face the camera (+z).
	_box(Vector3(0.34, 0.66, 0.03) * s, TIMBER, Vector3(-w * 0.18, 0.33 * s, d * 0.5 + 0.015), root)
	_box(Vector3(0.05, 0.05, 0.04) * s, Color("e3c27a"), Vector3(-w * 0.18 + 0.1 * s, 0.33 * s, d * 0.5 + 0.035), root)
	for x: float in [w * 0.22]:
		var pane := _box(Vector3(0.34, 0.3, 0.03) * s, WINDOW_WARM if lit else Color("8fb3ad"), Vector3(x, 0.66 * s, d * 0.5 + 0.015), root, 0.9 if lit else 0.0)
		pane.name = "CottageWindow"
		_box(Vector3(0.4, 0.05, 0.05) * s, TIMBER_DARK, Vector3(x, 0.49 * s, d * 0.5 + 0.03), root)
		_box(Vector3(0.025, 0.29, 0.035) * s, TIMBER_DARK, Vector3(x, 0.66 * s, d * 0.5 + 0.03), root)
	for x: float in [-w * 0.36, w * 0.38]:
		_ball(0.13 * s, LEAF, Vector3(x, 0.12 * s, d * 0.5 + 0.12 * s), root, Vector3(1.2, 0.85, 0.9))

static func _tower(root: Node3D, s: float, lit: bool) -> void:
	# A small striped lighthouse: tapered body, gallery, lamp room and cap.
	Primitives.mesh_node(Primitives.shared_mesh("cylinder", 0.62 * s, 0.32 * s, 0.6 * s), _m(STONE_DARK), Vector3(0, 0.16 * s, 0), root)
	for band in range(4):
		var color := PLASTER if band % 2 == 0 else Color("c4574a")
		var radius := (0.5 - band * 0.05) * s
		Primitives.mesh_node(Primitives.shared_mesh("cylinder", radius, 0.55 * s, radius - 0.05 * s), _m(color), Vector3(0, (0.6 + band * 0.55) * s, 0), root)
	Primitives.mesh_node(Primitives.shared_mesh("cylinder", 0.42 * s, 0.06 * s, 0.42 * s), _m(TIMBER_DARK), Vector3(0, 2.62 * s, 0), root)
	var lamp := Primitives.mesh_node(Primitives.shared_mesh("cylinder", 0.24 * s, 0.4 * s, 0.24 * s), _m(LAMP, 1.6 if lit else 0.0), Vector3(0, 2.85 * s, 0), root)
	lamp.name = "TowerLamp"
	Primitives.mesh_node(Primitives.shared_mesh("cone", 0.32 * s, 0.32 * s), _m(Color("c4574a")), Vector3(0, 3.21 * s, 0), root)
	var door := _box(Vector3(0.24, 0.42, 0.05) * s, TIMBER, Vector3(0, 0.47 * s, 0.49 * s), root)
	door.name = "TowerDoor"

static func _post(root: Node3D, height: float, s: float) -> void:
	# A support post standing from its base up to the floor it holds.
	_box(Vector3(0.11 * s, height, 0.11 * s), TIMBER, Vector3(0, height * 0.5, 0), root)
	_box(Vector3(0.18 * s, 0.05, 0.18 * s), STONE_DARK, Vector3(0, 0.025, 0), root)

## Two layers clear of floor seams (up to 1 cm) and of each other, so no
## face of the rug shares a depth with the floor's.
static func _rug(root: Node3D, width: float, depth: float, color: Variant) -> void:
	_box(Vector3(width, 0.010, depth), Color(str(color)), Vector3(0, 0.009, 0), root)
	_box(Vector3(width - 0.1, 0.010, depth - 0.1), Color(str(color)).lightened(0.22), Vector3(0, 0.0125, 0), root)

static func _path(root: Node3D, width: float, depth: float) -> void:
	var count := maxi(1, int(maxf(width, depth) / 0.36))
	var along_x := width >= depth
	for index in range(count):
		var t := (float(index) + 0.5) / float(count) - 0.5
		var at := Vector3(t * width, 0.005, 0.04 * sin(index * 2.0)) if along_x else Vector3(0.04 * sin(index * 2.0), 0.005, t * depth)
		var stone := _ball(0.13, STONE, at, root, Vector3(1.2, 0.05, 0.95))
		stone.rotation.y = index * 0.7

static func _planter(root: Node3D, width: float, depth: float, s: float) -> void:
	_box(Vector3(width, 0.22 * s, depth), TIMBER, Vector3(0, 0.11 * s, 0), root)
	_box(Vector3(width - 0.06, 0.03, depth - 0.06), Color("6b5240"), Vector3(0, 0.215 * s, 0), root)
	var count := maxi(2, int(width / 0.28))
	for index in range(count):
		var x := (float(index) + 0.5) / float(count) * width - width * 0.5
		_ball(0.13 * s, LEAF if index % 2 == 0 else LEAF_LIGHT, Vector3(x, 0.3 * s, 0), root, Vector3(1.1, 0.8, minf(1.0, depth / 0.3)))
		if index % 2 == 1: _ball(0.045 * s, BLOSSOMS[index % BLOSSOMS.size()], Vector3(x, 0.42 * s, 0.04), root)

static func _basket(root: Node3D, s: float) -> void:
	_rod(0.008, 0.4 * s, ROPE, Vector3(0, 0.4 * s, 0), root)
	Primitives.mesh_node(Primitives.shared_mesh("cylinder", 0.08 * s, 0.1 * s, 0.13 * s), _m(TIMBER_LIGHT), Vector3(0, 0.15 * s, 0), root)
	for j in range(4):
		var a := float(j) * TAU / 4.0
		_ball(0.08 * s, LEAF if j % 2 == 0 else LEAF_DARK, Vector3(sin(a) * 0.1 * s, 0.13 * s - 0.04 * s * float(j % 2), cos(a) * 0.1 * s), root, Vector3(1.0, 1.3, 1.0))

static func _ivy(root: Node3D, length: float) -> void:
	_box(Vector3(0.12, length, 0.015), LEAF_DARK, Vector3(0, -length * 0.5, 0), root)
	for index in range(int(length / 0.18)):
		_ball(0.07, LEAF if index % 2 == 0 else LEAF_LIGHT, Vector3(0.05 * (1 if index % 2 == 0 else -1), -0.1 - float(index) * 0.18, 0.012), root, Vector3(1.2, 0.8, 0.35))

static func _boat(root: Node3D, s: float) -> void:
	_box(Vector3(1.1, 0.22, 0.44) * s, TIMBER, Vector3(0, 0.11 * s, 0), root)
	# The deck stands a few millimetres proud of the hull's rim: equal tops
	# z-fight and flicker as the camera moves.
	_box(Vector3(1.0, 0.04, 0.36) * s, TIMBER_LIGHT, Vector3(0, 0.206 * s, 0), root)
	_box(Vector3(0.06, 0.05, 0.4) * s, TIMBER_DARK, Vector3(0.15 * s, 0.24 * s, 0), root)

## A squat harbour bollard with a coil of rope at its foot.
static func _bollard(root: Node3D, s: float) -> void:
	_rod(0.055 * s, 0.12 * s, Color("3f4448"), Vector3(0, 0.06 * s, 0), root)
	_rod(0.075 * s, 0.03 * s, Color("3f4448"), Vector3(0, 0.135 * s, 0), root)
	var coil := MeshInstance3D.new()
	coil.mesh = Primitives.ring_mesh(0.065 * s)
	coil.material_override = _m(ROPE)
	coil.position = Vector3(0, 0.02, 0)
	root.add_child(coil)

static func _barrel(root: Node3D, s: float) -> void:
	_rod(0.13 * s, 0.30 * s, TIMBER_LIGHT, Vector3(0, 0.15 * s, 0), root)
	for y: float in [0.06, 0.24]: _rod(0.135 * s, 0.025 * s, TIMBER_DARK, Vector3(0, y * s, 0), root)

## A slatted timber lobster pot with a rope loop.
static func _lobster_pot(root: Node3D, s: float) -> void:
	_box(Vector3(0.38, 0.03, 0.26) * s, TIMBER_DARK, Vector3(0, 0.015 * s, 0), root)
	for x: float in [-0.16, -0.05, 0.05, 0.16]:
		_box(Vector3(0.025, 0.16, 0.26) * s, TIMBER_LIGHT, Vector3(x * s, 0.09 * s, 0), root)
	_box(Vector3(0.38, 0.025, 0.26) * s, TIMBER, Vector3(0, 0.17 * s, 0), root)

static func _shelf(root: Node3D, s: float) -> void:
	_box(Vector3(0.9, 0.04, 0.2) * s, TIMBER_LIGHT, Vector3(0, 0.0, 0), root)
	for x: float in [-0.3, -0.12, 0.08]:
		_box(Vector3(0.08, 0.22, 0.14) * s, BLOSSOMS[int(absf(x) * 10) % BLOSSOMS.size()].darkened(0.25), Vector3(x * s, 0.13 * s, 0), root)
	Primitives.mesh_node(Primitives.shared_mesh("cylinder", 0.06 * s, 0.12 * s, 0.07 * s), _m(POT), Vector3(0.3 * s, 0.08 * s, 0), root)
	_ball(0.08 * s, LEAF, Vector3(0.3 * s, 0.2 * s, 0), root)

static func _frame(root: Node3D, s: float, color: Variant) -> void:
	_box(Vector3(0.4, 0.3, 0.03) * s, TIMBER_DARK, Vector3.ZERO, root)
	_box(Vector3(0.32, 0.22, 0.04) * s, Color(str(color)), Vector3.ZERO, root)

static func _fence(root: Node3D, from: Vector2, to: Vector2, s: float) -> void:
	var length := from.distance_to(to)
	var direction := (to - from).normalized()
	var start := Vector3(from.x, 0, from.y)
	var end := Vector3(to.x, 0, to.y)
	for y: float in [0.13, 0.27]:
		Primitives.bar_between(start + Vector3(0, y * s, 0), end + Vector3(0, y * s, 0), 0.035, _m(PICKET), root)
	var count := maxi(2, int(length / 0.42) + 1)
	for index in range(count):
		var at := from + direction * length * float(index) / float(count - 1)
		_box(Vector3(0.05, 0.36, 0.05) * Vector3(1, s, 1), PICKET, Vector3(at.x, 0.18 * s, at.y), root)

static func _hedge(root: Node3D, from: Vector2, to: Vector2, s: float) -> void:
	var length := from.distance_to(to)
	var direction := (to - from).normalized()
	var count := maxi(2, int(length / 0.3) + 1)
	for index in range(count):
		var at := from + direction * length * float(index) / float(count - 1)
		_ball(0.2 * s, LEAF.darkened(0.06 * float(index % 3)), Vector3(at.x, 0.24 * s, at.y), root, Vector3(1.15, 1.2, 0.95))
		if index % 4 == 2: _ball(0.045 * s, BLOSSOMS[index % BLOSSOMS.size()], Vector3(at.x, 0.46 * s, at.y + 0.12), root)

## A low planted bank or trough just outside a floor's edge: never walkable,
## it gives edge props real ground to stand on. It reaches down past the floor.
static func _bank(root: Node3D, spec: Dictionary) -> void:
	var r: Array = spec.rect
	var width := float(r[2] - r[0]) / 100.0
	var depth := float(r[3] - r[1]) / 100.0
	var height := float(spec.get("height", 12)) / 100.0
	var center := Vector3(float(r[0] + r[2]) / 200.0, 0, float(r[1] + r[3]) / 200.0)
	var side := Color(str(spec.get("side", "8a6b4e")))
	var top := Color(str(spec.get("top", "7fa36a")))
	_box(Vector3(width, height + 0.30, depth), side, center + Vector3(0, (height - 0.30) * 0.5, 0), root)
	_box(Vector3(width - 0.02, 0.03, depth - 0.02), top, center + Vector3(0, height, 0), root)

static func _wall(root: Node3D, from: Vector2, to: Vector2, height: float, thickness: float, color: Variant) -> void:
	var middle := (from + to) * 0.5
	var bar := _box(Vector3(from.distance_to(to), height, thickness), Color(str(color)), Vector3(middle.x, height * 0.5, middle.y), root)
	bar.rotation.y = -atan2(to.y - from.y, to.x - from.x)
