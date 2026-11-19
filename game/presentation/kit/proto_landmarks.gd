extends RefCounted
## PROTOTYPE ONLY (train/falls-rethink-proto, never lands): rough set pieces
## for the rethink board, built from primitives so the scale and the reveal
## read before anything is modelled. The full build models each in Blender.
##   marsh(): landmarks looming half seen out of the fog (a sunken boat, an
##            old leaning windmill, a hut on stilts, dead trees, reed beds),
##            paled toward the fog the higher they stand.
## World metres on the spread maps (core/journey/proto_spread.gd).
const Primitives = preload("res://presentation/kit/primitives.gd")
const SoftMist = preload("res://presentation/kit/soft_mist.gd")

const FOG := Color("dde2da")
const WOOD := Color("5e4a3a")
const WOOD_DARK := Color("43362b")
const BARK := Color("4a443b")
const ROOF := Color("6e5a48")
const REED := Color("8a8a56")
const REED_HEAD := Color("5d4a33")

static func marsh(root: Node3D) -> void:
	var holder := Node3D.new()
	holder.name = "ProtoLandmarks"
	root.add_child(holder)
	_sunken_boat(holder, Vector3(19.0, -0.25, 8.6), 0.35)
	_sunken_boat(holder, Vector3(62.0, -0.25, -9.0), -2.6)
	_windmill(holder, Vector3(30.0, 0.0, -11.5))
	_stilt_hut(holder, Vector3(57.0, 0.0, -10.5))
	_stilt_hut(holder, Vector3(104.0, 0.0, 9.5))
	for at: Vector3 in [Vector3(6, 0, -9.5), Vector3(12, 0, 9.2), Vector3(41, 0, -9.8), Vector3(47, 0, 9.4), Vector3(73, 0, 9.0), Vector3(83, 0, -10.2), Vector3(95, 0, -9.6), Vector3(113, 0, -9.0)]:
		_dead_tree(holder, at, int(at.x) % 3)
	for at: Vector3 in [Vector3(4, 0, 7.4), Vector3(23, 0, -8.2), Vector3(35, 0, 8.0), Vector3(52, 0, -8.0), Vector3(80, 0, 7.6), Vector3(87, 0, 5.9), Vector3(91, 0, 8.1), Vector3(99, 0, -8.0)]:
		_reeds(holder, at, 22)

## A dark silhouette colour, paled toward the fog only where it stands above the fog's sheets (m).
static func _faded(color: Color, y: float) -> Color:
	return color.darkened(0.25).lerp(FOG, clampf((y - 3.0) / 9.0, 0.0, 0.55))

static func _part(mesh: Mesh, color: Color, at: Vector3, parent: Node3D) -> MeshInstance3D:
	var node := Primitives.mesh_node(mesh, Primitives.shared_material(_faded(color, at.y + parent.position.y)), at, parent)
	return node

static func _sunken_boat(parent: Node3D, at: Vector3, turn: float) -> void:
	var boat := Node3D.new()
	boat.position = at
	boat.scale = Vector3.ONE * 1.3
	boat.rotation = Vector3(0.18, turn, 0.32)
	parent.add_child(boat)
	_part(Primitives.box_mesh(Vector3(3.2, 0.5, 1.2)), WOOD, Vector3(0, 0, 0), boat)
	for side: float in [-1.0, 1.0]:
		_part(Primitives.box_mesh(Vector3(3.4, 0.55, 0.1)), WOOD_DARK, Vector3(0, 0.22, side * 0.62), boat)
	_part(Primitives.box_mesh(Vector3(0.9, 0.7, 1.15)), WOOD_DARK, Vector3(1.6, 0.2, 0), boat).rotation.z = 0.5
	var mast := _part(Primitives.cylinder_mesh(0.06, 2.6), WOOD_DARK, Vector3(-0.3, 1.3, 0), boat)
	mast.rotation.z = -0.35

static func _windmill(parent: Node3D, at: Vector3) -> void:
	var mill := Node3D.new()
	mill.position = at
	mill.scale = Vector3.ONE * 1.6
	mill.rotation = Vector3(0.05, 0.4, -0.14)
	parent.add_child(mill)
	_part(Primitives.cylinder_mesh(1.1, 5.6, 0.75, 8), Color("7d7462"), Vector3(0, 2.8, 0), mill)
	_part(Primitives.cylinder_mesh(0.95, 1.2, 0.0, 8), ROOF, Vector3(0, 6.2, 0), mill)
	var hub := Node3D.new()
	hub.position = Vector3(0, 5.2, 0.95)
	hub.rotation.z = 0.35
	mill.add_child(hub)
	for index in range(4):
		var arm := Node3D.new()
		arm.rotation.z = PI * 0.5 * index
		hub.add_child(arm)
		_part(Primitives.box_mesh(Vector3(0.12, 3.4, 0.08)), WOOD, Vector3(0, 1.7, 0), arm)
		# Torn sailcloth on two of the arms.
		if index % 2 == 0: _part(Primitives.box_mesh(Vector3(0.7, 2.2, 0.03)), Color("b9b2a0"), Vector3(0.42, 2.0, 0.03), arm)
	_part(Primitives.box_mesh(Vector3(0.5, 0.9, 0.1)), WOOD_DARK, Vector3(0, 0.45, 1.02), mill)

static func _stilt_hut(parent: Node3D, at: Vector3) -> void:
	var hut := Node3D.new()
	hut.position = at
	hut.scale = Vector3.ONE * 1.35
	hut.rotation = Vector3(0.0, -0.3, 0.05)
	parent.add_child(hut)
	for x: float in [-1.1, 1.1]:
		for z: float in [-0.9, 0.9]:
			_part(Primitives.cylinder_mesh(0.08, 2.6, -1.0, 6), WOOD_DARK, Vector3(x, 1.1, z), hut)
	_part(Primitives.box_mesh(Vector3(2.8, 0.12, 2.3)), WOOD, Vector3(0, 2.4, 0), hut)
	_part(Primitives.box_mesh(Vector3(2.2, 1.6, 1.8)), Color("6d604f"), Vector3(0, 3.2, 0), hut)
	var roof := _part(Primitives.cylinder_mesh(0.0, 1.0, 1.9, 4), ROOF, Vector3(0, 4.4, 0), hut)
	roof.rotation.y = PI * 0.25
	roof.scale = Vector3(1.0, 1.0, 0.85)
	# One warm window, still lit.
	var glow := Primitives.mesh_node(Primitives.box_mesh(Vector3(0.45, 0.45, 0.04)), Primitives.shared_material(Color("f2c46d"), 0.9, Color("f2b85a"), 1.4), Vector3(0.4, 3.3, 0.92), hut)
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ladder := _part(Primitives.box_mesh(Vector3(0.5, 2.6, 0.06)), WOOD, Vector3(-0.6, 1.2, 1.25), hut)
	ladder.rotation.x = -0.3

static func _dead_tree(parent: Node3D, at: Vector3, kind: int) -> void:
	var tree := Node3D.new()
	tree.position = at
	tree.scale = Vector3.ONE * 1.4
	tree.rotation = Vector3(0.06 * (kind - 1), 0.7 * kind, 0.08 * (1 - kind))
	parent.add_child(tree)
	var tall := 3.4 + 1.1 * kind
	_part(Primitives.cylinder_mesh(0.12, tall, 0.22, 6), BARK, Vector3(0, tall * 0.5 - 0.3, 0), tree)
	for index in range(3 + kind):
		var y := tall * (0.45 + 0.15 * index)
		var branch := Node3D.new()
		branch.position = Vector3(0, y, 0)
		branch.rotation = Vector3(0, 1.9 * index + kind, 0.75 + 0.15 * (index % 2))
		tree.add_child(branch)
		var reach := 1.4 - 0.2 * index
		_part(Primitives.cylinder_mesh(0.03, reach, 0.07, 5), BARK, Vector3(0, reach * 0.5, 0), branch)

static func _reeds(parent: Node3D, at: Vector3, count: int) -> void:
	var bed := Node3D.new()
	bed.position = at
	parent.add_child(bed)
	var stem := Primitives.cylinder_mesh(0.018, 1.0, 0.025, 4)
	var head := Primitives.cylinder_mesh(0.045, 0.22, 0.045, 5)
	for index in range(count):
		var angle := float(index) * 2.399
		var r := 0.25 + 0.9 * sqrt(float(index) / float(count))
		var tall := 0.9 + 0.5 * fposmod(float(index) * 0.618, 1.0)
		var p := Vector3(cos(angle) * r, 0, sin(angle) * r * 0.7)
		var reed := Primitives.mesh_node(stem, Primitives.shared_material(REED), p + Vector3(0, tall * 0.5 - 0.1, 0), bed)
		reed.scale = Vector3(1, tall, 1)
		reed.rotation.z = 0.12 * sin(angle * 3.0)
		Primitives.mesh_node(head, Primitives.shared_material(REED_HEAD), p + Vector3(0.12 * sin(angle * 3.0) * tall, tall - 0.05, 0), bed)
