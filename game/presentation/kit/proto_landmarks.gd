extends RefCounted
## PROTOTYPE ONLY (train/falls-rethink-proto, never lands): rough set pieces
## for the rethink board, built from primitives so the scale and the reveal
## read before anything is modelled. The full build models each in Blender.
##   marsh(): landmarks looming half seen out of the fog (a sunken boat, an
##            old leaning windmill, a hut on stilts, dead trees, reed beds),
##            paled toward the fog the higher they stand.
##   falls(): solid rock under each raised reach so the tiers read as cliff,
##            a long band of the Blender cliff's rock along the gorge's back,
##            and rainbows in the spray of the great falls.
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
const CLIFF := Color("6c7262")

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

static func falls(world: Node3D) -> void:
	var root: Node3D = world.terrain
	var holder := Node3D.new()
	holder.name = "ProtoRainbows"
	root.add_child(holder)
	# Solid rock under every raised reach, up to just under its water: the
	# tiers read as cliff, each pour falls down a rock face, and nothing
	# shows through nine metres of clear water. (The full build gives each
	# reach its own bed in the water kit.)
	var seabed: float = world.waters.seabed()
	for body: Dictionary in world.waters.water.get("bodies", []):
		var low := INF
		for level: Variant in body.levels.values(): low = minf(low, float(level))
		if low < 0.5: continue
		for r: Array in body.rects:
			var size := Vector3((float(r[2]) - float(r[0])) / 100.0, low - 0.3 - seabed, (float(r[3]) - float(r[1])) / 100.0)
			var centre := Vector3((float(r[0]) + float(r[2])) / 200.0, seabed + size.y * 0.5, (float(r[1]) + float(r[3])) / 200.0)
			Primitives.mesh_node(Primitives.box_mesh(size), Primitives.shared_material(CLIFF), centre, holder).name = "TierRock"	# The gorge's back wall: one long band of the falls' layered, mossy rock
	# (the Blender cliff's cheeks, big) behind every tier, standing on each
	# reach's water, open where the great falls pour through it.
	var Models: Script = load("res://presentation/kit/models.gd")
	var Props: Script = load("res://presentation/kit/props.gd")
	var gaps := [Vector2(52.0, 72.0), Vector2(22.5, 29.5), Vector2(99.5, 110.5)]
	var x := -12.0
	var index := 0
	while x < 138.0:
		var open := gaps.any(func(g: Vector2) -> bool: return x > g.x and x < g.y)
		if not open:
			var level := 0.0
			for body: Dictionary in world.waters.water.get("bodies", []):
				for r: Array in body.rects:
					if x * 100.0 >= float(r[0]) and x * 100.0 < float(r[2]):
						level = 99.0
						for v: Variant in body.levels.values(): level = minf(level, float(v))
			var size := 3.4 + 0.9 * fposmod(float(index) * 0.618, 1.0)
			var part := "falls_cheek_left" if index % 2 == 0 else "falls_cheek_right"
			var rock: Node3D = Models.still(Props.FALLS_MODEL, part, Props.FALLS_COLORS, holder)
			rock.position = Vector3(x, level - 0.4, -8.4 - 1.0 * fposmod(float(index) * 0.37, 1.0))
			rock.scale = Vector3.ONE * size
			rock.rotation.y = 0.35 * (fposmod(float(index) * 0.73, 1.0) - 0.5)
		x += 3.6
		index += 1	# Rainbows hang in the spray in front of the great falls and the mill falls.
	_rainbow(holder, Vector3(62.0, 5.6, -14.0), 6.5)
	_rainbow(holder, Vector3(26.0, 2.2, -11.8), 3.2)
	_rainbow(holder, Vector3(-6.0, -0.2, -3.4), 2.4)

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

## A soft rainbow arc of `radius` (m) standing in the spray, facing the camera.
static func _rainbow(parent: Node3D, centre: Vector3, radius: float) -> void:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bands := [Color(0.95, 0.42, 0.38), Color(0.98, 0.72, 0.36), Color(0.98, 0.93, 0.48), Color(0.52, 0.86, 0.52), Color(0.45, 0.66, 0.95), Color(0.62, 0.48, 0.88)]
	var width := radius * 0.035
	var segments := 28
	for band in range(bands.size()):
		var r0 := radius - width * band
		var r1 := r0 - width
		var color: Color = bands[band]
		for index in range(segments):
			var a0 := PI * (0.1 + 0.8 * float(index) / segments)
			var a1 := PI * (0.1 + 0.8 * float(index + 1) / segments)
			var fade0 := sin((float(index) / segments) * PI) * 0.42
			var fade1 := sin((float(index + 1) / segments) * PI) * 0.42
			var quad := [Vector3(cos(a0) * r0, sin(a0) * r0, 0), Vector3(cos(a1) * r0, sin(a1) * r0, 0), Vector3(cos(a1) * r1, sin(a1) * r1, 0), Vector3(cos(a0) * r1, sin(a0) * r1, 0)]
			var fades := [fade0, fade1, fade1, fade0]
			for corner: int in [0, 1, 2, 0, 2, 3]:
				tool.set_color(Color(color.r, color.g, color.b, fades[corner]))
				tool.add_vertex(quad[corner])
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.render_priority = 2
	var arc := MeshInstance3D.new()
	arc.mesh = tool.commit()
	arc.material_override = mat
	arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	arc.position = centre
	# Face the camera's view (ViewFit.CAMERA_FROM is (3, 13, 10)): turned to it
	# across, and tipped back so the arc stands up on screen.
	arc.rotation = Vector3(-0.35, atan2(3.0, 10.0), 0)
	parent.add_child(arc)
