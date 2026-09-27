extends RefCounted
## The same small object can appear at its island and later at home. Geometry
## uses the existing world's material/mesh helpers and owns no gameplay state.
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
			world.sphere(0.24, accent, Vector3(0, 0.27, 0), root).scale = Vector3(0.8, 1.2, 0.8)
			_leaf(world, root, Vector3(-0.19, 0.53, 0), -0.65)
			_leaf(world, root, Vector3(0.17, 0.57, 0), 0.65)
		"long-way-home":
			for i in range(5): world.box(Vector3(0.18, 0.09, 0.49), WOOD, Vector3((i-2)*0.19, 0.18+sin(i*PI/4)*0.17, 0), root)
			for x: float in [-0.43, 0.43]: world.box(Vector3(0.08, 0.55, 0.08), accent, Vector3(x, 0.28, 0.27), root)
		"patient-garden", "a-place-to-grow":
			world.cylinder(0.28, 0.26, Color("ba8770"), Vector3(0, 0.13, 0), root)
			if id == "patient-garden":
				_flower(world, root, Vector3.ZERO, accent)
			else:
				world.cylinder(0.035, 0.65, WOOD, Vector3(0, 0.51, 0), root)
				for at: Vector3 in [Vector3(-0.15, 0.65, 0), Vector3(0.13, 0.84, 0), Vector3(0, 1.02, 0)]:
					world.sphere(0.19, GREEN, at, root).scale = Vector3(0.8, 1.1, 0.6)
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
		"a-little-lift":
			_frame(world, root, 0.78, 1.1, WOOD)
			_bell(world, root, Vector3(0, 0.77, 0), accent)
		"relay":
			world.cylinder(0.035, 1.05, WOOD, Vector3(-0.22, 0.53, 0), root)
			world.box(Vector3(0.62, 0.31, 0.04), accent, Vector3(0.06, 0.83, 0), root)
			world.sphere(0.07, CREAM, Vector3(-0.22, 1.13, 0), root)
		"garden":
			_frame(world, root, 0.85, 1.02, WOOD)
			for x: float in [-0.22, 0, 0.22]: world.box(Vector3(0.035, 0.85, 0.04), CREAM, Vector3(x, 0.49, 0), root)
			for y: float in [0.3, 0.55, 0.8]: world.box(Vector3(0.82, 0.035, 0.04), CREAM, Vector3(0, y, 0), root)
			_flower(world, root, Vector3(-0.29, 0, 0.13), accent)
		"borrowed-light":
			world.box(Vector3(0.64, 0.90, 0.12), accent, Vector3(0, 0.53, 0), root).rotation.z = -0.18
			world.box(Vector3(0.49, 0.73, 0.035), Color("b0dbd1"), Vector3(0, 0.54, 0.085), root).rotation.z = -0.18
		"missing-piece":
			world.cylinder(0.28, 0.13, WOOD, Vector3(0, 0.07, 0), root)
			world.cylinder(0.035, 0.39, accent, Vector3(0, 0.28, 0), root)
			world.ring(0.31, accent, Vector3(0, 0.69, 0), root).rotation.x = PI/2
			world.sphere(0.27, Color("b9dce4"), Vector3(0, 0.69, 0), root).scale.z = 0.18
		"two-promises":
			for i in range(2):
				world.cylinder(0.12, 0.50+i*0.16, CREAM, Vector3((i-0.5)*0.35, 0.25+i*0.08, 0), root)
				world.sphere(0.09, accent, Vector3((i-0.5)*0.35, 0.59+i*0.16, 0), root).scale = Vector3(0.7, 1.25, 0.7)
		"after-the-first-bell":
			world.box(Vector3(0.42, 0.59, 0.42), CREAM, Vector3(0, 0.3, 0), root)
			_frame(world, root, 0.58, 1.05, WOOD)
			_bell(world, root, Vector3(0, 0.83, 0), accent)
			_roof(world, root, Vector3(0, 1.23, 0), accent)
		"what-carried-you":
			world.box(Vector3(0.63, 0.23, 0.4), WOOD, Vector3(0, 0.38, 0), root)
			for x: float in [-0.24, 0.24]:
				for z: float in [-0.25, 0.25]: world.cylinder(0.12, 0.07, accent, Vector3(x, 0.20, z), root).rotation.x = PI/2
			world.box(Vector3(0.4, 0.06, 0.08), WOOD, Vector3(0.48, 0.43, 0), root).rotation.z = 0.3
		"a-welcome-left-on":
			world.cylinder(0.25, 0.75, CREAM, Vector3(0, 0.38, 0), root)
			world.cylinder(0.20, 0.24, Color("ffe4a5"), Vector3(0, 0.88, 0), root)
			world.ring(0.30, accent, Vector3(0, 0.73, 0), root)
			_roof(world, root, Vector3(0, 1.14, 0), accent)
		"upper-path":
			for i in range(4): world.box(Vector3(0.23, (i+1)*0.17, 0.54), accent if i%2==0 else CREAM, Vector3((i-1.5)*0.22, (i+1)*0.085, 0), root)
		"down-and-around":
			world.box(Vector3(0.80, 0.11, 0.66), WOOD, Vector3(0, 0.1, 0), root)
			world.box(Vector3(0.52, 0.035, 0.43), Color("294e48"), Vector3(0, 0.17, 0), root)
			var hatch: Node3D = world.box(Vector3(0.53, 0.08, 0.48), accent, Vector3(0, 0.39, -0.21), root)
			hatch.rotation.x = -1.0
			world.ring(0.075, CREAM, Vector3(0, 0.56, -0.07), root).rotation.x = 0.56
		"weight-of-a-friend", "bring-it-home":
			world.cylinder(0.37, 0.12, CREAM, Vector3(0, 0.07, 0), root)
			world.sphere(0.25, accent, Vector3(0, 0.39, 0), root)
			world.ring(0.253, CREAM, Vector3(0, 0.39, 0), root).rotation.z = 0.6
			if id == "bring-it-home":
				for side: int in [-1, 1]: world.box(Vector3(0.1, 0.43, 0.61), WOOD, Vector3(side*0.35, 0.25, 0), root).rotation.z = -side*0.25
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

static func _bell(world: Node3D, parent: Node3D, at: Vector3, color: Color) -> void:
	world.sphere(0.19, color, at, parent).scale = Vector3(1, 1.25, 1)
	world.ring(0.20, CREAM, at-Vector3(0, 0.13, 0), parent)
	world.sphere(0.055, WOOD, at-Vector3(0, 0.20, 0), parent)

static func _roof(world: Node3D, parent: Node3D, at: Vector3, color: Color) -> void:
	var shape := PrismMesh.new()
	shape.size = Vector3(0.73, 0.34, 0.59)
	world.mesh_node(shape, color, at, parent)
