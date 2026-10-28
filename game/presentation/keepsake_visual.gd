extends RefCounted
## An earlier island's small keepsake, at its island's corner and in the story
## memories (which also show two chapter pieces kept here). A chapter's corner
## shows its Home keepsake instead (presentation/keepsakes/). Geometry uses the
## world's material and mesh helpers and owns no gameplay state.
const SeedVisual = preload("res://presentation/seed_visual.gd")
const WOOD := Color("a17d60")
const CREAM := Color("eee4c7")
const GOLD := Color("efba73")
const TEAL := Color("83cab8")
const GREEN := Color("82a87a")

static func create(world: Node3D, item: Dictionary, shared: bool = false) -> Node3D:
	var root := Node3D.new()
	root.name = "Keepsake_" + str(item.get("stage_id", "unknown")).replace("-", "_") + ("_friend" if shared else "_solo")
	var accent := TEAL if shared else GOLD
	var id := str(item.get("stage_id", ""))
	match id:
		"first-light":
			# The canonical seed, at its own keepsake size.
			SeedVisual.create(world, SeedVisual.BODY_HALF_HEIGHT, accent, Vector3(0, 0.27, 0), root)
		"long-way-home":
			for i in range(5): world.box(Vector3(0.18, 0.09, 0.49), WOOD, Vector3((i-2)*0.19, 0.18+sin(i*PI/4)*0.17, 0), root)
			for x: float in [-0.43, 0.43]: world.box(Vector3(0.08, 0.55, 0.08), accent, Vector3(x, 0.28, 0.27), root)
		"patient-garden":
			world.cylinder(0.28, 0.26, Color("ba8770"), Vector3(0, 0.13, 0), root)
			_flower(world, root, Vector3.ZERO, accent)
		"rising-together":
			_frame(world, root, 0.78, 1.0, accent)
			world.cylinder(0.025, 0.36, CREAM, Vector3(0, 0.80, 0), root)
			world.cylinder(0.23, 0.30, WOOD, Vector3(0, 0.47, 0), root)
			world.ring(0.22, accent, Vector3(0, 0.63, 0), root)
		"across-the-blue":
			world.sphere(0.45, WOOD, Vector3(0, 0.18, 0), root).scale = Vector3(1.25, 0.32, 0.60)
			world.cylinder(0.025, 0.85, WOOD, Vector3(0, 0.55, 0), root)
			var sail := PrismMesh.new()
			sail.size = Vector3(0.52, 0.55, 0.035)
			world.mesh_node(sail, accent, Vector3(0.2, 0.66, 0), root)
		"lantern-crossing":
			_frame(world, root, 0.48, 0.71, WOOD)
			world.box(Vector3(0.52, 0.09, 0.42), accent, Vector3(0, 0.16, 0), root)
			world.sphere(0.19, Color("ffe6a8"), Vector3(0, 0.44, 0), root)
			world.ring(0.13, accent, Vector3(0, 0.90, 0), root).rotation.x = PI/2
		"two-beats":
			world.box(Vector3(0.75, 0.09, 0.13), WOOD, Vector3(0, 0.93, 0), root)
			for i in range(3):
				world.cylinder(0.018, 0.23, CREAM, Vector3((i-1)*0.24, 0.78, 0), root)
				world.cylinder(0.07, 0.32+i*0.1, accent, Vector3((i-1)*0.24, 0.51-i*0.05, 0), root)
		"after-you":
			world.box(Vector3(0.90, 0.10, 0.4), WOOD, Vector3(0, 0.36, 0), root)
			world.box(Vector3(0.90, 0.32, 0.09), accent, Vector3(0, 0.60, -0.2), root)
			for x: float in [-0.32, 0.32]: world.box(Vector3(0.10, 0.31, 0.36), WOOD, Vector3(x, 0.16, 0), root)
		"a-light-above":
			# A small glasshouse carries the chapter's open roof outline home.
			world.box(Vector3(0.85,0.10,0.60),WOOD,Vector3(0,0.05,0),root)
			for z: float in [-0.23,0.23]:
				_frame_at(world,root,0.68,0.70,accent,Vector3(0,0.10,z))
				for side: int in [-1,1]:
					var rib: Node3D = world.box(Vector3(0.45,0.05,0.05),accent,Vector3(side*0.17,0.91,z),root)
					rib.rotation.z = -side*0.58
			# The ridge ends inside the ribs, never flush with their faces.
			world.box(Vector3(0.05,0.05,0.48),CREAM,Vector3(0,1.03,0),root)
			world.sphere(0.19,Color("ffe4a5"),Vector3(0,0.42,0),root)
		"the-path-you-leave":
			world.cylinder(0.26,0.10,CREAM,Vector3(0,0.05,0),root)
			world.box(Vector3(0.09,1.06,0.09),WOOD,Vector3(0,0.56,0),root)
			for index in range(2):
				var side := 1 if index == 0 else -1
				var y := 0.85-index*0.30
				world.box(Vector3(0.58,0.19,0.06),accent,Vector3(side*0.11,y,0.055),root)
				var tip: Node3D = world.box(Vector3(0.14,0.14,0.06),accent,Vector3(side*0.39,y,0.055),root)
				tip.rotation.z = PI/4
		_: world.sphere(0.25, accent, Vector3(0, 0.27, 0), root)
	if shared:
		# Two linked leaves alter the silhouette as well as the color. Both
		# versions coexist; the shared object never replaces the solo keepsake.
		_leaf(world, root, Vector3(-0.40, 0.18, 0.30), -0.5, GOLD)
		_leaf(world, root, Vector3(0.40, 0.18, 0.30), 0.5, TEAL)
		world.box(Vector3(0.65, 0.045, 0.05), CREAM, Vector3(0, 0.09, 0.30), root)
	return root

static func _leaf(world: Node3D, parent: Node3D, at: Vector3, tilt: float, color: Color = GREEN) -> void:
	var leaf: Node3D = world.sphere(0.19, color, at, parent)
	leaf.scale = Vector3(0.5, 1.0, 0.28)
	leaf.rotation.z = tilt

static func _flower(world: Node3D, parent: Node3D, at: Vector3, color: Color) -> void:
	world.cylinder(0.025, 0.54, GREEN, at+Vector3(0, 0.42, 0), parent)
	for i in range(5):
		var a := i*TAU/5
		world.sphere(0.12, color, at+Vector3(cos(a)*0.15, 0.73+sin(a)*0.15, 0), parent).scale.z = 0.45
	world.sphere(0.10, CREAM, at+Vector3(0, 0.73, 0.045), parent)

static func _frame(world: Node3D, parent: Node3D, width: float, height: float, color: Color) -> void:
	for side: int in [-1, 1]: world.box(Vector3(0.07, height, 0.07), color, Vector3(side*width/2, height/2, 0), parent)
	world.box(Vector3(width+0.10, 0.075, 0.08), color, Vector3(0, height, 0), parent)

static func _frame_at(world: Node3D, parent: Node3D, width: float, height: float, color: Color, at: Vector3) -> void:
	var frame := Node3D.new()
	frame.position = at
	parent.add_child(frame)
	_frame(world,frame,width,height,color)
