extends "res://presentation/island_world.gd"
## A frozen illustration. It never represents a recorded route or a checkpoint.
const WindowVisual = preload("res://presentation/house_window.gd")
const KEYS := ["first-steps@1","relay-isles@2","high-and-low@1","rolling-home@1","a-house-for-two@1","conservatory@1","long-way-home@1"]
var chapter_key := ""
var phase := ""

func configure(key: String, passage_phase: String) -> bool:
	if is_inside_tree() or key not in KEYS or passage_phase not in ["arrival","completion"]: return false
	chapter_key = key
	phase = passage_phase
	return true

func _ready() -> void:
	# Do not start IslandWorld's camera exploration, motion or reunion effects.
	set_process(false)
	set_physics_process(false)
	set_process_input(false)
	set_process_unhandled_input(false)
	terrain = Node3D.new()
	terrain.name = "MemoryScenery"
	add_child(terrain)
	var scene_environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("102d35")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("c8ddd0")
	env.ambient_light_energy = 0.58
	scene_environment.environment = env
	add_child(scene_environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48,-30,0)
	sun.light_color = Color("ffe7be")
	sun.light_energy = 0.9
	add_child(sun)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = 6.6
	camera.position = Vector3(5,7,11)
	add_child(camera)
	camera.look_at(Vector3(0,0.25,0))
	camera.current = true
	if chapter_key in KEYS: _build_memory()

func _build_memory() -> void:
	var completed := phase == "completion"
	match chapter_key:
		"first-steps@1":
			_island_shell(-1.8,0,2.6,2.4,Color("739b7d"))
			_island_shell(1.8,0,2.6,2.4,Color("739b7d"))
			if completed:
				for i in range(6): box(Vector3(0.26,0.12,0.70),Color("ac8e66"),Vector3(-0.65+i*0.26,0.08,0),terrain)
			_spirit("p0",Vector3(1.1 if completed else -1.4,0.05,0.3))
			_spirit("p1",Vector3(2.1 if completed else 1.3,0.05,0.3))
		"relay-isles@2":
			_island_shell(0,0,5.6,3.1,Color("6f9279"))
			var bed := box(Vector3(2.4,0.13,1.2),Color("87694e"),Vector3(0,0.065,-0.45),terrain)
			bed.name = "BloomedGarden" if completed else "EmptyGarden"
			if completed:
				for i in range(9): KeepsakeVisual._flower(self,terrain,Vector3((i%3-1)*0.65,0.04,-0.9+floori(i/3.0)*0.40),GOLD if i%2 == 0 else TEAL)
			else: sphere(0.09,GOLD,Vector3(-0.7,0.16,-0.35),terrain)
			_pair(Vector3(-0.5,0.03,0.8),completed)
		"high-and-low@1":
			_island_shell(0,0.5,5.4,2.2,Color("799580"))
			for i in range(3):
				var at := Vector3((i-1)*2.4,0,-2.2-abs(i-1)*0.4)
				_island_shell(at.x,at.z,1.9,1.6,Color("647f72"))
				var district := Node3D.new()
				district.position = at
				district.name = "DistantRooftop"+str(i)
				terrain.add_child(district)
				var height := 0.9+i*0.20
				box(Vector3(1.4,height,1.1),Color("8ba496"),Vector3(0,height*0.5,0),district)
				_roof(district,Vector3(0,height+0.15,0),Vector3(1.8,0.65,1.5),Color("657f7b"))
			_pair(Vector3(-0.5,0.03,0.9),completed)
		"rolling-home@1":
			_island_shell(0,0,5.8,3.2,Color("758f77"))
			_house(Vector3(0,0,-0.7),false,1.3)
			_pair(Vector3(-0.5,0.03,1.0),completed)
		"a-house-for-two@1":
			_island_shell(0,0,5.8,3.4,Color("779983"))
			box(Vector3(3.8,0.14,2.0),Color("ad8c67"),Vector3(0,0.08,-0.3),terrain)
			box(Vector3(3.8,1.85,0.12),Color("e2d6b6"),Vector3(0,0.95,-1.25),terrain)
			var window := WindowVisual.build(self,terrain,Vector3(0,0.2,-1.15),1.3,Color("80664e"),Color("729b95"),CREAM)
			WindowVisual.present(self,window,true,Color("ffe4a5"))
			_keepsake("after-you",Vector3(0,0.16,-0.15),1.4)
			_pair(Vector3(-0.5,0.18,0.5),true)
		"conservatory@1":
			_island_shell(0,0,5.8,3.3,Color("739d80"))
			_keepsake("a-light-above",Vector3(0,0,-0.55),2.5)
			for i in range(4): KeepsakeVisual._flower(self,terrain,Vector3(-1.8+i*1.2,0.02,0.15),TEAL if i%2 == 0 else GOLD)
			_pair(Vector3(-0.5,0.03,1.0),completed)
		"long-way-home@1":
			_island_shell(0,0,6.4,3.6,Color("688c7a"))
			_house(Vector3(0.9,0,-0.65),true,1.4)
			_keepsake("the-path-you-leave",Vector3(-1.75,0,0.1),1.1)
			for i in range(5): box(Vector3(0.42,0.06,0.5),Color("af9b77"),Vector3(-0.7+i*0.38,0.05,0.45),terrain)
			_pair(Vector3(-0.5,0.03,1.2),completed)

func _spirit(slot: String, at: Vector3) -> void:
	var spirit := SpiritVisual.new(GOLD if slot == "p0" else TEAL)
	spirit.name = "Memory_"+slot
	spirit.position = at
	spirit.rotation.y = -0.1 if slot == "p0" else 0.1
	terrain.add_child(spirit)
	spirit.process_mode = Node.PROCESS_MODE_DISABLED

func _pair(at: Vector3, together: bool) -> void:
	_spirit("p0",at)
	_spirit("p1",at+Vector3(1.0 if together else 1.9,0,0))

func _keepsake(stage: String, at: Vector3, size: float) -> void:
	var item := KeepsakeVisual.create(self,{"stage_id":stage})
	item.position = at
	item.scale = Vector3.ONE*size
	terrain.add_child(item)

func _roof(parent: Node3D, at: Vector3, size: Vector3, color: Color) -> void:
	var roof := PrismMesh.new()
	roof.size = size
	mesh_node(roof,color,at,parent)

func _house(at: Vector3, lit: bool, size: float) -> void:
	var house := Node3D.new()
	house.name = "LitHome" if lit else "UnlitHouse"
	house.position = at
	house.scale = Vector3.ONE*size
	terrain.add_child(house)
	box(Vector3(1.7,1.2,1.1),CREAM,Vector3(0,0.6,0),house)
	_roof(house,Vector3(0,1.5,0),Vector3(2.05,0.75,1.5),Color("92a388"))
	box(Vector3(0.37,0.80,0.08),Color("80664e"),Vector3(0,0.40,0.59),house)
	box(Vector3(0.27,0.70,0.09),Color("54776c"),Vector3(0,0.36,0.64),house)
	sphere(0.028,GOLD,Vector3(0.085,0.36,0.70),house)
	for x: float in [-0.45,0.45]:
		box(Vector3(0.45,0.6,0.06),Color("80664e"),Vector3(x,0.65,0.58),house)
		var pane := box(Vector3(0.33,0.46,0.07),Color("ffe4a5") if lit else Color("354d50"),Vector3(x,0.65,0.62),house)
		_glow(pane,Color("ffe4a5"),0.45 if lit else 0.0)
		box(Vector3(0.035,0.46,0.08),CREAM,Vector3(x,0.65,0.66),house)

func _glow(node: MeshInstance3D, color: Color, energy: float) -> void:
	var mat := node.material_override as StandardMaterial3D
	mat.emission_enabled = energy > 0.0
	mat.emission = color
	mat.emission_energy_multiplier = energy
