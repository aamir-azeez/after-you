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
const SoftMist = preload("res://presentation/kit/soft_mist.gd")

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
## A bank's top layer: this thick (metres), its top face half of it above the
## bank's height, so it never shares a depth with the bank's sides.
const BANK_LAYER := 0.03
## A cobble wall's full height and depth (metres), nudged stones included.
const STONE_WALL_HEIGHT := 0.34
const STONE_WALL_DEPTH := 0.32
## A cobble wall's rows, bottom up: [centre height, least radius, radius
## spread, offset along the wall in stones, how far its stones wander].
const COBBLE_ROWS := [[0.075, 0.09, 0.02, 0.5, 0.7], [0.165, 0.088, 0.02, 0.0, 0.7], [0.255, 0.078, 0.016, 0.5, 1.0]]
## Warm stones that sit with terracotta and dusk light.
const STONES := [Color("d6b68a"), Color("a67f57"), Color("e3cca5"), Color("8f6f50"), Color("c49a6c")]
## The dark core behind the stones: the gaps between them read as shadow.
const STONE_CORE := Color("4f4034")
## Shell colours: cream, coral and pink.
const SHELLS := [Color("fbf4e4"), Color("f6a88e"), Color("f9c9d4"), Color("fde6cf")]

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
		"shells": radius = 0.15 * s; height = 0.02
		"waterfall": half = Vector2(float(spec.get("width", 120)) / 200.0 + WATERFALL_CHEEK, WATERFALL_DEPTH * 0.5 + MIST_REACH) * s; height = (float(spec.get("height", 260)) / 100.0 + 0.13) * s
		"mill_wheel": half = Vector2(MILL_WHEEL_RADIUS + 0.12, 0.25) * s; height = (MILL_WHEEL_RADIUS * 2.0 + 0.2) * s
		"post_box": radius = 0.2 * s; height = 1.19 * s
		"reeds": radius = 0.16 * s; height = 0.78 * s
		"stamp_desk": half = Vector2(0.38, 0.24) * s; height = 0.74 * s
		"washing_line": half = Vector2(0.76, 0.1) * s; height = 1.02 * s
		"fishing_rod": half = Vector2(0.14, 0.46) * s; height = 0.9 * s
		"rope_coil": radius = 0.17 * s; height = 0.08 * s
		"light_pool": radius = float(spec.get("radius", 80)) / 100.0 * s; height = 0.0
		"fence", "hedge", "wall", "stone_wall":
			var from := _point(spec.from)
			var to := _point(spec.to)
			var width := 0.06 if kind == "fence" else 0.36 * s if kind == "hedge" else STONE_WALL_DEPTH if kind == "stone_wall" else float(spec.get("thickness", 12)) / 100.0
			var rect := Rect2(from.min(to), Vector2.ZERO).expand(from.max(to)).grow(width * 0.5)
			var tall := 0.38 * s if kind == "fence" else 0.5 * s if kind == "hedge" else STONE_WALL_HEIGHT if kind == "stone_wall" else float(spec.get("height", 120)) / 100.0
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
			if spec.get("vary", false): vary(item, index, at.x)
			result.append(item)
	return result

## The `index`th prop of a varied row at `x` cm: a little smaller or larger
## and turned, the same every build.
static func vary(item: Dictionary, index: int, x: float) -> void:
	item["size"] = float(item.get("size", 1.0)) * (0.85 + 0.15 * absf(sin(float(index) * 2.3 + x)))
	item["rot"] = float(item.get("rot", 0)) + float(index) * 47.0

## The height (cm above its surface) a prop stands at on this bank: the top
## face of its top layer. Never the bank's own height, which is under it.
static func bank_top(spec: Dictionary) -> float:
	return float(spec.get("y", 0)) + float(spec.get("height", 12)) + BANK_LAYER * 50.0

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
		"rock": _rock(root, s, bool(spec.get("moss", false)))
		"lantern": _lantern(root, s, lit)
		"lamp_post": _lamp_post(root, s, lit)
		"bench": _bench(root, s)
		"pot": _pot(root, s)
		"fern": _fern(root, s, bool(spec.get("pot", true)))
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
		"stone_wall": _stone_wall(root, _point(spec.from), _point(spec.to))
		"shells": _shells(root, s, int(absf(float(spec.at[0]) * 7.0 + float(spec.at[1]) * 3.0)))
		"waterfall": _waterfall(root, s, float(spec.get("width", 120)) / 100.0, float(spec.get("height", 260)) / 100.0, float(spec.get("foot", 0)) / 100.0)
		"mill_wheel": _mill_wheel(root, s)
		"post_box": _post_box(root, s)
		"reeds": _reeds(root, s, int(absf(float(spec.at[0]) * 3.0 + float(spec.at[1]) * 7.0)))
		"stamp_desk": _stamp_desk(root, s)
		"washing_line": _washing_line(root, s)
		"fishing_rod": _fishing_rod(root, s)
		"rope_coil": _rope_coil(root, s)
		"light_pool": _light_pool(root, s, float(spec.get("radius", 80)) / 100.0)
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

## A rock and a pebble; a mossy one (moss) wears a green cushion on top.
static func _rock(root: Node3D, s: float, moss: bool = false) -> void:
	_ball(0.22 * s, STONE_DARK, Vector3(0, 0.07 * s, 0), root, Vector3(1.3, 0.62, 1.0))
	_ball(0.12 * s, STONE, Vector3(0.18 * s, 0.05 * s, 0.08 * s), root, Vector3(1.2, 0.6, 1.0))
	if moss:
		_ball(0.17 * s, MOSS, Vector3(-0.03 * s, 0.15 * s, -0.02 * s), root, Vector3(1.35, 0.32, 1.0))
		_ball(0.07 * s, MOSS.lightened(0.12), Vector3(0.17 * s, 0.09 * s, 0.07 * s), root, Vector3(1.3, 0.35, 1.0))

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

## A fern, in a pot or (pot false) growing straight out of the ground.
static func _fern(root: Node3D, s: float, pot: bool = true) -> void:
	if pot: Primitives.mesh_node(Primitives.shared_mesh("cylinder", 0.12 * s, 0.18 * s, 0.15 * s), _m(POT), Vector3(0, 0.09 * s, 0), root)
	for j in range(6):
		var a := float(j) * TAU / 6.0
		var frond := _ball(0.16 * s, LEAF_DARK if j % 2 == 0 else LEAF, Vector3(sin(a) * 0.12 * s, (0.27 if pot else 0.1) * s, cos(a) * 0.12 * s), root, Vector3(0.45, 0.22, 1.0))
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
	# The door and windows face the camera (+z), STANDOFF clear of the
	# plinth's front at any size.
	var face := d * 0.5 + 0.02 + STANDOFF
	_box(Vector3(0.34, 0.66, 0.03) * s, TIMBER, Vector3(-w * 0.18, 0.33 * s, face), root)
	_box(Vector3(0.05, 0.05, 0.04) * s, Color("e3c27a"), Vector3(-w * 0.18 + 0.1 * s, 0.33 * s, face + 0.02), root)
	for x: float in [w * 0.22]:
		var pane := _box(Vector3(0.34, 0.3, 0.03) * s, WINDOW_WARM if lit else Color("8fb3ad"), Vector3(x, 0.66 * s, face), root, 0.9 if lit else 0.0)
		pane.name = "CottageWindow"
		_box(Vector3(0.4, 0.05, 0.05) * s, TIMBER_DARK, Vector3(x, 0.49 * s, face + 0.015), root)
		_box(Vector3(0.025, 0.29, 0.035) * s, TIMBER_DARK, Vector3(x, 0.66 * s, face + 0.015), root)
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
	# The deck stands STANDOFF proud of the hull's rim at any size: equal
	# tops z-fight and flicker as the camera moves.
	_box(Vector3(1.0, 0.04, 0.36) * s, TIMBER_LIGHT, Vector3(0, 0.2 * s + STANDOFF, 0), root)
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

## Built-in standoff (metres) between parts of one prop that would otherwise
## share a face: never scaled with the prop, so no size or turn brings two
## faces within the lint's z-fight gap (test_dressing_lint COPLANAR).
const STANDOFF := 0.006

## The hoops stand STANDOFF proud of the staves at every size.
static func _barrel(root: Node3D, s: float) -> void:
	_rod(0.13 * s, 0.30 * s, TIMBER_LIGHT, Vector3(0, 0.15 * s, 0), root)
	for y: float in [0.06, 0.24]: _rod(0.13 * s + STANDOFF, 0.025 * s, TIMBER_DARK, Vector3(0, y * s, 0), root)

## A slatted timber lobster pot with a rope loop. The slats stop STANDOFF
## short of the base's and lid's sides, so the pot turned any way never
## lines a slat's end up with them.
static func _lobster_pot(root: Node3D, s: float) -> void:
	_box(Vector3(0.38, 0.03, 0.26) * s, TIMBER_DARK, Vector3(0, 0.015 * s, 0), root)
	for x: float in [-0.16, -0.05, 0.05, 0.16]:
		_box(Vector3(0.025 * s, 0.16 * s, 0.26 * s - STANDOFF * 2.0), TIMBER_LIGHT, Vector3(x * s, 0.09 * s, 0), root)
	_box(Vector3(0.38, 0.025, 0.26) * s, TIMBER, Vector3(0, 0.17 * s, 0), root)

static func _shelf(root: Node3D, s: float) -> void:
	_box(Vector3(0.9, 0.04, 0.2) * s, TIMBER_LIGHT, Vector3(0, 0.0, 0), root)
	for x: float in [-0.3, -0.12, 0.08]:
		_box(Vector3(0.08, 0.22, 0.14) * s, BLOSSOMS[int(absf(x) * 10) % BLOSSOMS.size()].darkened(0.25), Vector3(x * s, 0.13 * s, 0), root)
	Primitives.mesh_node(Primitives.shared_mesh("cylinder", 0.06 * s, 0.12 * s, 0.07 * s), _m(POT), Vector3(0.3 * s, 0.08 * s, 0), root)
	_ball(0.08 * s, LEAF, Vector3(0.3 * s, 0.2 * s, 0), root)

## The picture stands STANDOFF proud of its frame and no deeper behind it, so
## the frame's back is the only face against a wall at any size.
static func _frame(root: Node3D, s: float, color: Variant) -> void:
	_box(Vector3(0.4, 0.3, 0.03) * s, TIMBER_DARK, Vector3.ZERO, root)
	_box(Vector3(0.32 * s, 0.22 * s, 0.03 * s), Color(str(color)), Vector3(0, 0, STANDOFF), root)

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
	_box(Vector3(width - 0.02, BANK_LAYER, depth - 0.02), top, center + Vector3(0, height, 0), root)

static func _wall(root: Node3D, from: Vector2, to: Vector2, height: float, thickness: float, color: Variant) -> void:
	var middle := (from + to) * 0.5
	var bar := _box(Vector3(from.distance_to(to), height, thickness), Color(str(color)), Vector3(middle.x, height * 0.5, middle.y), root)
	bar.rotation.y = -atan2(to.y - from.y, to.x - from.x)

## 0..1 from an index and a salt, the same every build.
static func _jitter(index: int, salt: float) -> float:
	var value := sin(float(index) * 12.9898 + salt * 78.233) * 43758.5453
	return value - floor(value)

## A low eight-sided pebble of this radius and height, about a fifth of a kit
## sphere's triangles. Its mesh is cached by those two sizes and the node
## keeps an even scale, so the static fold batches it.
static func _pebble(radius: float, height: float, color: Color, at: Vector3, parent: Node3D) -> MeshInstance3D:
	var shape := SphereMesh.new()
	shape.radius = radius
	shape.height = height
	shape.radial_segments = 8
	shape.rings = 4
	return Primitives.mesh_node(Primitives.cached_shape(shape), _m(color), at, parent)

## A cone or drum of few sides and no rings: shells are tiny, so a sixth of
## a kit cone's triangles reads the same.
static func _low_drum(radius: float, height: float, top: float, color: Color, at: Vector3, parent: Node3D) -> MeshInstance3D:
	var shape := CylinderMesh.new()
	shape.bottom_radius = radius
	shape.top_radius = top
	shape.height = height
	shape.radial_segments = 8
	shape.rings = 0
	return Primitives.mesh_node(Primitives.cached_shape(shape), _m(color), at, parent)

## A low cobble wall along from..to: three rows of rounded stones in mixed
## warm tones over a dark core, so every gap between them reads as shadow.
## Each row is staggered against the one below, and every stone gets its own
## fixed nudge along and across the wall and its own size, from a hash of its
## place, so the wall reads hand laid and builds the same every time. The
## chapter cameras look down on it, so the wandering top row carries the look.
static func _stone_wall(root: Node3D, from: Vector2, to: Vector2) -> void:
	var length := from.distance_to(to)
	var pivot := Node3D.new()
	pivot.name = "StoneWall"
	root.add_child(pivot)
	pivot.position = Vector3(from.x, 0, from.y)
	pivot.rotation.y = -atan2(to.y - from.y, to.x - from.x)
	var salt := from.x * 3.1 + from.y * 1.7
	_box(Vector3(maxf(length - 0.04, 0.02), 0.2, STONE_WALL_DEPTH - 0.12), STONE_CORE, Vector3(length * 0.5, 0.1, 0), pivot)
	var count := maxi(2, int(length / 0.2))
	var step := length / float(count)
	for row in range(COBBLE_ROWS.size()):
		var spec: Array = COBBLE_ROWS[row]
		for index in range(count):
			var key := index * 7 + row * 131
			var r: float = spec[1] + spec[2] * _jitter(key, salt)
			# Up to a fifth of a stone along the wall and a quarter across it.
			var along := (float(index) + float(spec[3])) * step + 0.4 * r * (_jitter(key + 1, salt) - 0.5)
			var across := 0.5 * r * (_jitter(key + 2, salt) - 0.5) * 2.0 * float(spec[4])
			var lift := 0.016 * (_jitter(key + 3, salt) - 0.5) * float(spec[4])
			var color: Color = STONES[int(_jitter(key + 4, salt) * STONES.size())]
			# One cached unit pebble for every stone, scaled evenly: sizes vary
			# without a mesh per stone, and the fold still batches them.
			var stone := _pebble(1.0, 1.6, color, Vector3(clampf(along, 0.08, maxf(length - 0.08, 0.08)), float(spec[0]) + lift, across), pivot)
			stone.scale = Vector3.ONE * r
			stone.rotation.y = TAU * _jitter(key + 5, salt)

## A loose cluster of small shells lying on the sand, all about 2 cm high: two
## scallops, a spiral whelk and two little clams.
const SHELL_KINDS := ["scallop", "whelk", "clam", "scallop", "clam"]

static func _shells(root: Node3D, s: float, salt: int) -> void:
	for index in range(SHELL_KINDS.size()):
		var angle := float(index) * 2.39996 + float(salt % 7)
		var reach := (0.03 + 0.08 * _jitter(index, float(salt))) * s
		var holder := Node3D.new()
		root.add_child(holder)
		holder.position = Vector3(sin(angle) * reach, 0.0, cos(angle) * reach)
		holder.rotation.y = angle * 1.7
		var color: Color = SHELLS[(index + salt) % SHELLS.size()]
		match str(SHELL_KINDS[index]):
			"scallop": _scallop(holder, s, color)
			"whelk": _whelk(holder, s, color)
			_: _clam(holder, s, color)

## Shell pieces grow with the cluster's size across the sand but never in
## height: every one stays about 2 cm high, and every node keeps scale 1 so
## the static fold batches it.

## A fan of five ribs from the hinge, every other one a shade darker.
static func _scallop(holder: Node3D, s: float, color: Color) -> void:
	for rib in range(5):
		var a := (float(rib) - 2.0) * 0.36
		var shade := color if rib % 2 == 0 else color.darkened(0.14)
		var piece := _box(Vector3(0.016 * s, 0.01, 0.046 * s), shade, Vector3(sin(a) * 0.02 * s, 0.008 + 0.002 * float(rib % 2), cos(a) * 0.02 * s), holder)
		piece.rotation.y = a
	_box(Vector3(0.024 * s, 0.008, 0.01 * s), color.darkened(0.2), Vector3(0, 0.007, -0.004 * s), holder)

static func _whelk(holder: Node3D, s: float, color: Color) -> void:
	var spire := _low_drum(0.015, 0.06 * s, 0.0, color, Vector3(0, 0.005, 0), holder)
	spire.rotation.z = PI * 0.5
	for band in range(3):
		var radius := 0.0145 - band * 0.0035
		var ring := _low_drum(radius, 0.005 * s, radius, color.darkened(0.22), Vector3((0.01 - band * 0.012) * s, 0.005, 0), holder)
		ring.rotation.z = PI * 0.5
	_pebble(0.009 * s, 0.016, SHELLS[2].darkened(0.08), Vector3(0.03 * s, 0.005, 0), holder)

static func _clam(holder: Node3D, s: float, color: Color) -> void:
	_pebble(0.032 * s, 0.026, color, Vector3(0, 0.002, 0), holder)
	_box(Vector3(0.046 * s, 0.004, 0.006 * s), color.darkened(0.18), Vector3(0, 0.0135, 0.004 * s), holder)


# --- The Falls and Fog Marsh (rules 16's scenery) ---

## A waterfall's cliff reaches this far past each side of its water (m at
## size 1), and the cliff is this deep front to back.
const WATERFALL_CHEEK := 0.42
const WATERFALL_DEPTH := 0.7
const CLIFF := Color("7d8272")
const CLIFF_DARK := Color("666b5d")
const MOSS := Color("6f8f5a")
const FALLING := Color(0.80, 0.91, 0.94, 0.82)
const FOAM := Color("f4f8f8")
const SPRAY := Color(0.97, 0.99, 0.99, 0.9)
## How far the foam and mist reach out over the pool past the cliff's face (m
## at size 1); the extent's depth covers it on both sides.
const MIST_REACH := 0.8

## A tall waterfall facing the camera (+z): a mossy stone cliff `width` plus
## both cheeks wide and `height` tall, its water falling down the middle into
## white foam, with a soft spray over the foot. The water and the spray are
## one translucent look each; the stone, moss, streaks and foam are plain
## leaves the static fold batches. Stand it with its foot at the water; where
## the water rises and falls, stand it at the low level and give "foot" (cm)
## up to the usual one, where a second heap of foam and the spray sit.
static func _waterfall(root: Node3D, s: float, width: float, height: float, foot: float = 0.0) -> void:
	var w := width * s
	var h := height * s
	var cheek := WATERFALL_CHEEK * s
	var deep := WATERFALL_DEPTH * s
	# The cliff behind the water, and a cheek of stacked blocks each side.
	# Its back stops short of the cheeks' backs, so turned round no faces meet.
	_box(Vector3(w + 0.02, h + 0.08 * s, deep * 0.5 - STANDOFF * 2.0), CLIFF_DARK, Vector3(0, (h + 0.08 * s) * 0.5, -deep * 0.25 + STANDOFF), root)
	for side: float in [-1.0, 1.0]:
		var y := 0.0
		var index := 0
		while y < h - 0.01:
			var tall := minf(h - y, (0.42 + 0.16 * float((index * 5 + int(side + 1.0)) % 3)) * s)
			var inset := 0.03 * s * float(index % 2)
			_box(Vector3(cheek - inset, tall - STANDOFF, deep - inset * 2.0), CLIFF if index % 2 == 0 else CLIFF.lightened(0.06), Vector3(side * (w * 0.5 + cheek * 0.5 + STANDOFF), y + tall * 0.5, 0), root)
			# A cushion of moss on every ledge, and a little more on every other.
			_ball((0.11 + 0.03 * float(index % 2)) * s, MOSS if index % 2 else MOSS.lightened(0.1), Vector3(side * (w * 0.5 + cheek * 0.45 + STANDOFF), y + tall + 0.01 * s, deep * 0.32), root, Vector3(1.4, 0.45, 0.9))
			if index % 2 == 1: _ball(0.08 * s, MOSS.darkened(0.08), Vector3(side * (w * 0.5 + cheek * 0.75), y + tall * 0.55, deep * 0.5 + 0.02 * s), root, Vector3(1.0, 1.3, 0.5))
			y += tall
			index += 1
	# The lip the water pours over, and moss along its top.
	_box(Vector3(w + cheek * 2.0 + 0.04 * s, 0.1 * s, deep + 0.04 * s), CLIFF.darkened(0.08), Vector3(0, h + 0.05 * s + STANDOFF, 0), root)
	_box(Vector3(w + cheek * 2.0 + 0.06 * s, 0.03 * s, deep * 0.5), MOSS, Vector3(0, h + 0.115 * s + STANDOFF * 2.0, deep * 0.12), root)
	# The falling water, its pale streaks, the foam at its foot and the spray.
	var water := Primitives.mesh_node(Primitives.shared_mesh("box", w, h, 0.06 * s), Primitives.fresh_material(FALLING, 0.2), Vector3(0, h * 0.5, deep * 0.5 - 0.04 * s), root)
	(water.material_override as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var streaks := maxi(3, roundi(w / 0.14))
	for index in range(streaks):
		var x := (float(index) + 0.5) / float(streaks) * w - w * 0.5
		var long := h * (0.35 + 0.2 * float(index % 3))
		_box(Vector3(0.025 * s, long, 0.012 * s), FOAM, Vector3(x, h - long * 0.5 - h * 0.08 * float(index % 4), deep * 0.5 + STANDOFF), root)
	# A heap of white foam at the foot, two rows spreading out onto the pool.
	# A foot above the base (foot, m) is where the pool usually stands: the
	# foam lies there too, and the spray rises from it.
	var puffs := maxi(4, roundi((w + cheek) / 0.16) + 2)
	for level: float in ([0.0, foot] if foot > 0.0 else [0.0]):
		for row in range(2):
			for index in range(puffs - row):
				var x := ((float(index) + 0.5 + 0.5 * float(row)) / float(puffs) - 0.5) * (w + cheek * (0.2 + 0.3 * float(row)))
				var r := (0.12 + 0.045 * float((index + row) % 3)) * s
				_ball(r, FOAM if (index + row) % 3 else FOAM.darkened(0.04), Vector3(x, level + 0.02 * s, deep * 0.5 + (0.05 + 0.2 * float(row) + 0.04 * float(index % 2)) * s), root, Vector3(1.4, 0.55, 1.0))
	# Soft spray rising off the foot, and mist lying out over the pool: one
	# see-through mesh (kit/soft_mist.gd), all of it within the prop's extent.
	var blots: Array = []
	var front := deep * 0.5
	# Billows of spray all along the foot, out over the cheeks too, so they
	# show against the stone and not only on the white water; a few more
	# rising above them.
	var reach := w * 0.5 + cheek - 0.42 * s
	var billows := maxi(4, roundi((reach * 2.0) / (0.42 * s)) + 1)
	for index in range(billows):
		var x := -reach + reach * 2.0 * float(index) / float(billows - 1)
		blots.append([Vector3(x, foot + (0.22 + 0.12 * float(index % 3)) * s, front + (0.22 + 0.08 * float(index % 2)) * s), Vector2(0.84, 0.66 + 0.1 * float(index % 2)) * s, "front"])
	for index in range(3):
		var x := (float(index) - 1.0) * minf(w * 0.32, reach)
		blots.append([Vector3(x, foot + (0.75 + 0.15 * float(index % 2)) * s, front + 0.12 * s), Vector2(0.84, 0.7) * s, "front"])
	for index in range(3):
		var x := (float(index) - 1.0) * w * 0.3
		blots.append([Vector3(x, foot + 0.12 * s, front + MIST_REACH * s * 0.5), Vector2(w * 0.45 + cheek * 0.8, MIST_REACH * s * 0.95), "up"])
	SoftMist.build(blots, SPRAY, root)

## A mill wheel's radius (m at size 1).
const MILL_WHEEL_RADIUS := 0.62

## Radians a second a turning mill wheel goes round: a slow, steady turn.
const MILL_WHEEL_SPIN := -0.45

## A timber mill wheel on its axle, facing the camera (+z): a rim of planks,
## three spokes across, a paddle at every rim plank and a post each side
## under the axle. The wheel itself is one node, "Spin", whose meta "spin" is
## its turn rate: the world turns it (presentation/water_world.gd); the posts
## stand still.
static func _mill_wheel(root: Node3D, s: float) -> void:
	var r := MILL_WHEEL_RADIUS * s
	var hub := Vector3(0, r + 0.08 * s, 0)
	var wheel := Node3D.new()
	wheel.name = "Spin"
	wheel.position = hub
	wheel.set_meta("spin", MILL_WHEEL_SPIN)
	root.add_child(wheel)
	var planks := 12
	for index in range(planks):
		var a := float(index) / float(planks) * TAU
		var rim := _box(Vector3(r * TAU / float(planks) + 0.01 * s, 0.06 * s, 0.16 * s), TIMBER, Vector3(cos(a), sin(a), 0) * r, wheel)
		rim.rotation.z = a + PI * 0.5
		var paddle := _box(Vector3(0.03 * s, 0.17 * s, 0.24 * s), TIMBER_LIGHT, Vector3(cos(a), sin(a), 0) * (r + 0.08 * s), wheel)
		paddle.rotation.z = a
	for index in range(3):
		var spoke := _box(Vector3(r * 2.0 - 0.06 * s, 0.05 * s, 0.05 * s), TIMBER_DARK, Vector3.ZERO, wheel)
		spoke.rotation.z = float(index) / 3.0 * PI + 0.2
	var axle := _rod(0.09 * s, 0.34 * s, TIMBER_DARK, Vector3.ZERO, wheel)
	axle.rotation.x = PI * 0.5
	for side: float in [-1.0, 1.0]:
		_box(Vector3(0.08 * s, hub.y - 0.08 * s, 0.08 * s), TIMBER_DARK, Vector3(0, (hub.y - 0.08 * s) * 0.5, side * 0.21 * s), root)

## A red post box on a timber post: a slot across its front and a little
## pitched roof.
static func _post_box(root: Node3D, s: float) -> void:
	_box(Vector3(0.07, 0.71, 0.07) * s, TIMBER_DARK, Vector3(0, 0.355 * s, 0), root)
	_box(Vector3(0.3, 0.34, 0.24) * s, Color("c0483c"), Vector3(0, 0.89 * s, 0), root)
	_box(Vector3(0.18 * s, 0.03 * s, 0.24 * s + STANDOFF * 2.0), Color("3c1e1a"), Vector3(0, 0.96 * s, 0), root)
	var roof := Primitives.mesh_node(Primitives.shared_mesh("prism", 0.36 * s, 0.12 * s, 0.3 * s), _m(Color("96382f")), Vector3(0, 1.12 * s + STANDOFF, 0), root)
	roof.name = "PostBoxRoof"

const REED := Color("6f8a56")
const REED_DARK := Color("586f45")
const CATTAIL := Color("7a5a3c")

## A clump of reeds: thin stalks leaning a little apart, a brown cattail head
## on some, and two flat blades. `seed` varies the clump, the same every build.
static func _reeds(root: Node3D, s: float, seed: int) -> void:
	var count := 5 + seed % 3
	for index in range(count):
		var a := float(index) * 2.4 + float(seed % 7)
		var tall := (0.5 + 0.08 * float((index + seed) % 4)) * s
		var at := Vector3(cos(a), 0, sin(a)) * 0.07 * s * float(index % 3)
		var lean := Vector3(sin(a) * 0.12, 0, cos(a) * 0.12)
		var stalk := _box(Vector3(0.016 * s, tall, 0.016 * s), REED if index % 2 == 0 else REED_DARK, at + Vector3(0, tall * 0.5, 0), root)
		stalk.rotation = lean
		if (index + seed) % 2 == 0:
			# The head sits just above the stalk's end, so no face of it lies on one of the stalk's.
			var top := stalk.transform * Vector3(0, tall * 0.5 + 0.057 * s, 0)
			var head := _box(Vector3(0.034, 0.11, 0.034) * s, CATTAIL, top, root)
			head.rotation = lean
	for side: float in [-1.0, 1.0]:
		var blade := _box(Vector3(0.05, 0.36, 0.008) * s, REED_DARK, Vector3(side * 0.05 * s, 0.17 * s, 0.02 * s), root)
		blade.rotation = Vector3(0, side * 0.6, side * 0.35)

## A small timber desk with the post office's red ink pad and a stack of
## forms. The stamp itself is Fog Marsh's ending's own, which comes down on it.
static func _stamp_desk(root: Node3D, s: float) -> void:
	_box(Vector3(0.72, 0.05, 0.44) * s, TIMBER_LIGHT, Vector3(0, 0.66 * s, 0), root)
	for x: float in [-0.31, 0.31]:
		for z: float in [-0.18, 0.18]: _box(Vector3(0.05, 0.625, 0.05) * s, TIMBER, Vector3(x * s, 0.3125 * s, z * s), root)
	_box(Vector3(0.66, 0.16, 0.03) * s, TIMBER, Vector3(0, 0.55 * s, -0.15 * s), root)
	_box(Vector3(0.14, 0.02, 0.1) * s, Color("b0473c"), Vector3(0.18 * s, 0.695 * s + STANDOFF, 0.04 * s), root)
	var forms := _box(Vector3(0.2, 0.03, 0.26) * s, PICKET, Vector3(-0.22 * s, 0.7 * s + STANDOFF, -0.02 * s), root)
	forms.rotation.y = 0.12

# --- Lived-in touches: a washing line, a fishing rod, a coil of rope, and the
# warm pool a lantern throws on the boards ---

const CLOTHS := [Color("f4ecd8"), Color("a9c6d8"), Color("e6aaa0"), Color("b7c99a")]
const LAMP_POOL := Color(1.0, 0.78, 0.45, 0.42)

## Two posts and a line between them along x, with four cloths pegged on it.
## Each cloth hangs below the line, so no face of one meets the line's.
static func _washing_line(root: Node3D, s: float) -> void:
	for x: float in [-0.7, 0.7]: _box(Vector3(0.05, 1.0, 0.05) * s, TIMBER_DARK, Vector3(x * s, 0.5 * s, 0), root)
	_box(Vector3(1.4, 0.012, 0.012) * s, ROPE, Vector3(0, 0.95 * s, 0), root)
	var x := -0.52
	for index in range(CLOTHS.size()):
		var wide := 0.2 + 0.05 * float(index % 2)
		var tall := 0.22 + 0.07 * float((index + 1) % 3)
		_box(Vector3(wide, tall, 0.02) * s, CLOTHS[index], Vector3((x + wide * 0.5) * s, (0.935 - tall * 0.5) * s, 0), root)
		x += wide + 0.05

## A rod propped on a forked stick, leaning out along -z over the water, its
## line hanging from the tip to a red float, and a little bucket at its butt.
static func _fishing_rod(root: Node3D, s: float) -> void:
	for side: float in [-1.0, 1.0]:
		var stick := _box(Vector3(0.025, 0.32, 0.025) * s, TIMBER_DARK, Vector3(side * 0.035 * s, 0.15 * s, 0.05 * s), root)
		stick.rotation.z = side * 0.25
	var butt := Vector3(0, 0.06, 0.4) * s
	var tip := Vector3(0, 0.86, -0.44) * s
	var rod := _box(Vector3(0.022 * s, butt.distance_to(tip), 0.022 * s), TIMBER, (butt + tip) * 0.5, root)
	rod.rotation.x = atan2(tip.z - butt.z, tip.y - butt.y)
	_rod(0.004 * s, 0.96 * s, Color("e8e2d0"), Vector3(0, 0.38 * s, tip.z), root)
	_ball(0.035 * s, Color("c0483c"), Vector3(0, -0.1 * s, tip.z), root)
	Primitives.mesh_node(Primitives.shared_mesh("cylinder", 0.07 * s, 0.12 * s, 0.06 * s), _m(Color("7f8a8a")), Vector3(0.09 * s, 0.06 * s, 0.32 * s), root)

## Three loops of rope lying in a low heap.
static func _rope_coil(root: Node3D, s: float) -> void:
	for loop in range(3):
		var coil := MeshInstance3D.new()
		coil.mesh = Primitives.ring_mesh((0.13 - 0.025 * float(loop)) * s)
		coil.material_override = _m(ROPE if loop % 2 == 0 else ROPE.darkened(0.12))
		coil.position = Vector3(0.01 * float(loop) * s, (0.015 + 0.022 * float(loop)) * s, 0)
		root.add_child(coil)

## The warm light a lantern throws on the ground: a soft see-through glow,
## `radius` m (at size 1) round its foot, just over the floor and under a
## pip's shadow's reach (kit/soft_mist.gd).
static func _light_pool(root: Node3D, s: float, radius: float) -> void:
	var across := radius * 2.0 * s
	SoftMist.build([[Vector3(0, 0.035, 0), Vector2(across, across), "up"]], LAMP_POOL, root, true)
