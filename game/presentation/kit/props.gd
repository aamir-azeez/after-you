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
const Models = preload("res://presentation/kit/models.gd")
const MODEL_DIR := "res://assets/models/"

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
const SOIL := Color("6b5240")
## The little lighthouse's red bands and cap.
const STRIPE := Color("c4574a")

## Kinds lower than this (metres) never hide a spirit or a control.
const LOW := 0.16
## Flat kinds that cover a patch of floor (rugs, and paths of stones or
## boards): small markers on the floor keep off them (island_world.floor_covers).
const FLOOR_COVERS := ["rug", "path"]
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
		"stone_wall": _stone_wall(root, _point(spec.from), _point(spec.to))
		"shells": _shells(root, s, int(absf(float(spec.at[0]) * 7.0 + float(spec.at[1]) * 3.0)))
		"wall": _wall(root, _point(spec.from), _point(spec.to), float(spec.get("height", 120)) / 100.0, float(spec.get("thickness", 12)) / 100.0, spec.get("color", "efe2c4"))
		_:
			root.free()
			return null
	return root

## A Blender model's still part (kit/models.gd), scaled from its foot.
static func _model(root: Node3D, model: String, part: String, colors: Dictionary, scale: Vector3) -> Node3D:
	var node := Models.still(MODEL_DIR + model + ".glb", part, colors, root)
	node.scale = scale
	return node

## A still part's one leaf straight under the prop as `name`, for a lamp or a
## pane its world finds by name and lights.
static func _model_leaf(root: Node3D, model: String, part: String, colors: Dictionary, scale: Vector3, name: String) -> MeshInstance3D:
	var holder := _model(root, model, part, colors, scale)
	var leaf := holder.get_child(0) as MeshInstance3D
	holder.remove_child(leaf)
	leaf.transform = holder.transform * leaf.transform
	root.add_child(leaf)
	holder.free()
	leaf.name = name
	return leaf

static func _m(color: Color, glow: float = 0.0) -> StandardMaterial3D:
	return Primitives.shared_material(color, 0.9, LAMP_GLOW if glow > 0.0 else Color(0, 0, 0, 0), glow)

static func _box(size: Vector3, color: Color, at: Vector3, parent: Node3D, glow: float = 0.0) -> MeshInstance3D:
	return Primitives.mesh_node(Primitives.shared_mesh("box", size.x, size.y, size.z), _m(color, glow), at, parent)

static func _ball(radius: float, color: Color, at: Vector3, parent: Node3D, squash: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var node := Primitives.mesh_node(Primitives.shared_mesh("sphere", radius), _m(color), at, parent)
	node.scale = squash
	return node
static func _tree(root: Node3D, s: float, variant: int) -> void:
	var tints := [CROWN, CROWN_LIGHT, LEAF] if variant % 2 == 0 else [LEAF_DARK, CROWN, LEAF_LIGHT]
	_model(root, "orchard_tree", "orchard_tree", {"trunk": TRUNK, "crown_a": tints[0], "crown_b": tints[1], "crown_c": tints[2]}, Vector3.ONE * s)
	if variant % 3 != 2: _model(root, "orchard_tree", "orchard_tree_fruit", {"fruit": FRUIT if variant % 3 == 0 else BLOSSOMS[1]}, Vector3.ONE * s)

static func _pine(root: Node3D, s: float) -> void:
	_model(root, "wild_bits", "pine", {"trunk": TRUNK, "needle_a": LEAF_DARK, "needle_b": CROWN}, Vector3.ONE * s)

static func _bush(root: Node3D, s: float, flowered: Variant) -> void:
	_model(root, "bush", "bush", {"leaf_a": LEAF, "leaf_b": LEAF.darkened(0.06), "leaf_c": LEAF.darkened(0.12)}, Vector3.ONE * s)
	if flowered: _model(root, "bush", "bush_blooms", {"bloom_a": BLOSSOMS[0], "bloom_b": BLOSSOMS[1], "bloom_c": BLOSSOMS[2]}, Vector3.ONE * s)

static func _flowers(root: Node3D, s: float) -> void:
	_model(root, "flower_patch", "flower_patch", {"leaf": LEAF, "stem": LEAF_DARK, "bloom_a": BLOSSOMS[0], "bloom_b": BLOSSOMS[1], "bloom_c": BLOSSOMS[2], "bloom_d": BLOSSOMS[3]}, Vector3.ONE * s)

static func _tuft(root: Node3D, s: float) -> void:
	_model(root, "wild_bits", "tuft", {"grass": Color("6f9a64")}, Vector3.ONE * s)

static func _rock(root: Node3D, s: float) -> void:
	_model(root, "wild_bits", "rock", {"stone": STONE_DARK, "stone_light": STONE}, Vector3.ONE * s)

static func _lantern(root: Node3D, s: float, lit: bool) -> void:
	_model(root, "post_lantern", "post_lantern", {"post": TIMBER_DARK, "cap": TIMBER_DARK}, Vector3.ONE * s)
	var glass := _model(root, "post_lantern", "post_lantern_glass", {"glass": {"color": LAMP, "glow": LAMP_GLOW, "energy": 0.8} if lit else LAMP}, Vector3.ONE * s)
	glass.name = "LanternGlass"

static func _lamp_post(root: Node3D, s: float, lit: bool) -> void:
	_model(root, "lamp_post", "lamp_post", {"base": TIMBER_DARK, "iron": Color("4f4a44")}, Vector3.ONE * s)
	# Tide finds and lights the glass by name.
	_model_leaf(root, "lamp_post", "lamp_post_glass", {"glass": {"color": LAMP, "glow": LAMP_GLOW, "energy": 1.1} if lit else LAMP}, Vector3.ONE * s, "LampGlass")

static func _bench(root: Node3D, s: float) -> void:
	_model(root, "bench", "bench", {"seat": TIMBER_LIGHT, "frame": TIMBER}, Vector3.ONE * s)

## Potted plants (assets/models/garden_pots.glb).
static func _pot(root: Node3D, s: float) -> void:
	_model(root, "garden_pots", "potted_plant", {"pot": POT, "soil": SOIL, "leaf": LEAF, "leaf_dark": LEAF_DARK, "bloom": BLOSSOMS[0]}, Vector3.ONE * s)

static func _fern(root: Node3D, s: float) -> void:
	_model(root, "garden_pots", "fern", {"pot": POT, "soil": SOIL, "leaf": LEAF, "leaf_dark": LEAF_DARK}, Vector3.ONE * s)

## The crate and its stacked twin (assets/models/harbour_bits.glb).
static func _crate(root: Node3D, s: float, stack: bool) -> void:
	_model(root, "harbour_bits", "crate", {"board": TIMBER_LIGHT, "frame": TIMBER}, Vector3.ONE * s)
	if stack:
		var top := _model(root, "harbour_bits", "crate", {"board": TIMBER_LIGHT.lightened(0.08), "frame": TIMBER.lightened(0.08)}, Vector3.ONE * 0.75 * s)
		top.position = Vector3(0.02, 0.335, 0.01) * s
		top.rotation.y = 0.3

## A post with two arms (assets/models/signpost.glb, shared with the Crossroads
## keepsake): one on the front pointing right, one on the back pointing left.
static func _signpost(root: Node3D, s: float) -> void:
	_model(root, "signpost", "signpost_post", {"post": TIMBER, "cap": TIMBER_DARK}, Vector3.ONE * s)
	var one := _model(root, "signpost", "signpost_arm", {"board": TIMBER_LIGHT, "nail": TIMBER_DARK}, Vector3(0.46, 0.12 / 0.22, 0.7) * s)
	one.position = Vector3(-0.05, 0.86, 0.035) * s
	one.rotation.y = 0.15
	var two := _model(root, "signpost", "signpost_arm", {"board": TIMBER_LIGHT.lightened(0.06), "nail": TIMBER_DARK}, Vector3(0.4, 0.11 / 0.22, 0.7) * s)
	two.position = Vector3(0.05, 0.66, -0.035) * s
	two.rotation.y = PI - 0.2

static func _cottage(root: Node3D, s: float, width: float, depth: float, lit: bool) -> void:
	var scale := Vector3(width / 1.6, 1.0, depth / 1.1) * s
	_model(root, "cottage", "cottage", {"wall": PLASTER, "plinth": STONE_DARK, "roof": ROOF, "trim": ROOF_DARK, "door": TIMBER, "knob": Color("e3c27a"), "frame": TIMBER_DARK, "leaf": LEAF}, scale)
	var pane := _model(root, "cottage", "cottage_window", {"window": {"color": WINDOW_WARM, "glow": LAMP_GLOW, "energy": 0.9} if lit else Color("8fb3ad")}, scale)
	pane.name = "CottageWindow"

static func _tower(root: Node3D, s: float, lit: bool) -> void:
	# A small striped lighthouse: stone foot, banded body, gallery, lamp room and cap
	# (assets/models/harbour_more.glb). The Lighthouse finds and lights the lamp by name.
	_model(root, "harbour_more", "tower", {"stone": STONE_DARK, "plaster": PLASTER, "stripe": STRIPE, "rail": TIMBER_DARK, "roof": STRIPE, "door": TIMBER}, Vector3.ONE * s)
	_model_leaf(root, "harbour_more", "tower_lamp", {"glass": {"color": LAMP, "glow": LAMP_GLOW, "energy": 1.6} if lit else LAMP}, Vector3.ONE * s, "TowerLamp")

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
	_box(Vector3(width - 0.06, 0.03, depth - 0.06), SOIL, Vector3(0, 0.215 * s, 0), root)
	var count := maxi(2, int(width / 0.28))
	for index in range(count):
		var x := (float(index) + 0.5) / float(count) * width - width * 0.5
		_ball(0.13 * s, LEAF if index % 2 == 0 else LEAF_LIGHT, Vector3(x, 0.3 * s, 0), root, Vector3(1.1, 0.8, minf(1.0, depth / 0.3)))
		if index % 2 == 1: _ball(0.045 * s, BLOSSOMS[index % BLOSSOMS.size()], Vector3(x, 0.42 * s, 0.04), root)

static func _basket(root: Node3D, s: float) -> void:
	_model(root, "garden_pots", "hanging_basket", {"rope": ROPE, "basket": TIMBER_LIGHT, "leaf": LEAF, "leaf_dark": LEAF_DARK}, Vector3.ONE * s)

static func _ivy(root: Node3D, length: float) -> void:
	_box(Vector3(0.12, length, 0.015), LEAF_DARK, Vector3(0, -length * 0.5, 0), root)
	for index in range(int(length / 0.18)):
		_ball(0.07, LEAF if index % 2 == 0 else LEAF_LIGHT, Vector3(0.05 * (1 if index % 2 == 0 else -1), -0.1 - float(index) * 0.18, 0.012), root, Vector3(1.2, 0.8, 0.35))

## The rowboat (assets/models/rowboat.glb), in today's timber tones.
const ROWBOAT := "res://assets/models/rowboat.glb"
static func rowboat_colors() -> Dictionary:
	return {"hull": TIMBER, "strake": TIMBER.lightened(0.08), "inside": TIMBER_DARK, "rim": TIMBER_LIGHT, "seat": TIMBER_LIGHT, "oar": ROPE.lightened(0.1)}

static func _boat(root: Node3D, s: float) -> void:
	Models.still(ROWBOAT, "rowboat", rowboat_colors(), root).scale = Vector3.ONE * s

## A squat harbour bollard with a coil of rope at its foot (assets/models/harbour_bits.glb).
static func _bollard(root: Node3D, s: float) -> void:
	_model(root, "harbour_bits", "bollard", {"iron": Color("3f4448"), "rope": ROPE}, Vector3.ONE * s)
## Bulging staves, a sunk lid and two hoops (assets/models/harbour_bits.glb).
static func _barrel(root: Node3D, s: float) -> void:
	_model(root, "harbour_bits", "barrel", {"stave": TIMBER_LIGHT, "hoop": TIMBER_DARK, "lid": TIMBER}, Vector3.ONE * s)

## A creel: a base board under hoops and slats, a rope loop on top
## (assets/models/harbour_more.glb).
static func _lobster_pot(root: Node3D, s: float) -> void:
	_model(root, "harbour_more", "lobster_pot", {"base": TIMBER_DARK, "hoop": TIMBER, "slat": TIMBER_LIGHT, "rope": ROPE}, Vector3.ONE * s)

## A shelf on brackets with books and a potted plant (assets/models/wall_bits.glb).
static func _shelf(root: Node3D, s: float) -> void:
	_model(root, "wall_bits", "wall_shelf", {"board": TIMBER_LIGHT, "bracket": TIMBER, "book_a": BLOSSOMS[3].darkened(0.25), "book_b": BLOSSOMS[1].darkened(0.25), "book_c": BLOSSOMS[0].darkened(0.25), "pot": POT, "leaf": LEAF}, Vector3.ONE * s)

## A moulded frame round a picture of a hill in the spec's colour
## (assets/models/wall_bits.glb); its back is the only face against a wall.
static func _frame(root: Node3D, s: float, color: Variant) -> void:
	_model(root, "wall_bits", "wall_frame", {"frame": TIMBER_DARK, "picture": Color(str(color)), "hill": Color(str(color)).darkened(0.18)}, Vector3.ONE * s)

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
