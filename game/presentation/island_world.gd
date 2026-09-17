extends Node3D

signal footstep
## Visuals consume simulation snapshots. No gameplay state is owned here.

const SpiritVisual = preload("res://presentation/spirit_visual.gd")
const CameraExploration = preload("res://presentation/camera_exploration.gd")

var terrain: Node3D
var actors: Dictionary = {}
var actor_targets: Dictionary = {}
var seed: MeshInstance3D
var _seed_holder := ""
var _seed_status := ""
var _seed_snapshot_position := Vector3.ZERO
var _seed_launch_offset := Vector3.ZERO
var _seed_launch_age := 1.0
var bridge_parts: Array[MeshInstance3D] = []
var plate: MeshInstance3D
var gate_plate: MeshInstance3D
var lift: Node3D
var lift_guides: Array[MeshInstance3D] = []
var landing_marker: Node3D
var garden: Node3D
var camera: Camera3D
var camera_exploration: Node
var current_level: Dictionary = {}
var time := 0.0
var reduced_motion := false
var bloomed := false
var flowers: Array[Node3D] = []
var motes: Array[MeshInstance3D] = []
var bridge_ready := false
var home_view := true
var home_presentation_owner := 0
var goal_ring: MeshInstance3D
var garden_activation: Node3D
var garden_petals: Array[Node3D] = []
var garden_state := "closed"

const CREAM := Color("e9edd6")
const TEAL := Color("91d6c6")
const GOLD := Color("f4c38d")

func material(color: Color, roughness: float = 0.9) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	if color.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat

func mesh_node(mesh: Mesh, color: Color, pos: Vector3, parent: Node3D) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material(color)
	node.position = pos
	parent.add_child(node)
	return node

func box(size: Vector3, color: Color, pos: Vector3, parent: Node3D) -> MeshInstance3D:
	var shape := BoxMesh.new()
	shape.size = size
	return mesh_node(shape, color, pos, parent)

func sphere(radius: float, color: Color, pos: Vector3, parent: Node3D) -> MeshInstance3D:
	var shape := SphereMesh.new()
	shape.radius = radius
	shape.height = radius * 2.0
	shape.radial_segments = 16
	shape.rings = 8
	return mesh_node(shape, color, pos, parent)

func cylinder(radius: float, height: float, color: Color, pos: Vector3, parent: Node3D) -> MeshInstance3D:
	var shape := CylinderMesh.new()
	shape.top_radius = radius
	shape.bottom_radius = radius
	shape.height = height
	shape.radial_segments = 24
	return mesh_node(shape, color, pos, parent)

func ring(radius: float, color: Color, pos: Vector3, parent: Node3D) -> MeshInstance3D:
	var shape := TorusMesh.new()
	shape.inner_radius = radius - 0.025
	shape.outer_radius = radius + 0.025
	shape.rings = 24
	shape.ring_segments = 8
	return mesh_node(shape, color, pos, parent)

func _ready() -> void:
	var environment_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("123a3d")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("c4e0d1")
	env.ambient_light_energy = 0.26
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment_node.environment = env
	add_child(environment_node)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52,-32,0)
	sun.light_color = Color("fff0cb")
	sun.light_energy = 0.65
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 32
	add_child(sun)
	var bounce := DirectionalLight3D.new()
	bounce.rotation_degrees=Vector3(28,145,0)
	bounce.light_color=Color("8ebbb2")
	bounce.light_energy=0.24
	add_child(bounce)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 14.4
	camera.position = Vector3(10,13,15)
	add_child(camera)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	camera_exploration = CameraExploration.new()
	camera_exploration.camera = camera
	camera_exploration.reduced_motion = func() -> bool: return reduced_motion
	add_child(camera_exploration)
	for i in range(32):
		var node := sphere(0.018 + (i % 3) * 0.008, Color("c1ddbd"), Vector3(sin(i*2.17)*11, -2+cos(i*1.23)*3,cos(i*0.91)*9), self)
		motes.append(node)

func load_level(level: Dictionary) -> void:
	reset_camera_exploration()
	_reset_seed_pose()
	current_level = level
	if is_instance_valid(terrain):
		remove_child(terrain)
		terrain.queue_free()
	terrain = Node3D.new()
	add_child(terrain)
	actors.clear()
	actor_targets.clear()
	bridge_parts.clear()
	flowers.clear()
	bloomed = false
	gate_plate = null
	lift = null
	lift_guides.clear()
	var palettes := [Color("a6c9a0"),Color("9fc8b8"),Color("c5c7a3"),Color("abbfc5"),Color("8ec6b5"),Color("bbb4cd"),Color("d0bdac"),Color("adcbb1")]
	var index := int(level.get("index",0))
	var grass: Color = palettes[index % palettes.size()]
	var bounds: Array = level.get("bounds",[-600,-260,600,260])
	var min_x := float(bounds[0])/100.0
	var max_x := float(bounds[2])/100.0
	var min_z := float(bounds[1])/100.0
	var max_z := float(bounds[3])/100.0
	var gap: Array = level.get("gap",[-100,100])
	var left_edge := float(gap[0])/100.0
	var right_edge := float(gap[1])/100.0
	var z_center := (min_z+max_z)/2.0
	var depth := max_z-min_z
	_make_island((min_x+left_edge)/2.0, z_center, left_edge-min_x, depth, grass)
	_make_island((right_edge+max_x)/2.0, z_center, max_x-right_edge, depth, grass)
	var bridge: Dictionary = level.get("bridge", {"z":0,"width":180})
	var bridge_z := float(bridge.get("z",0))/100.0
	var bridge_width := float(bridge.get("width",180))/100.0
	for i in range(9):
		var x := lerpf(left_edge,right_edge,float(i+0.5)/9.0)
		var plank := box(Vector3((right_edge-left_edge)/9.0-0.025,0.12,bridge_width),Color("c4b090"),Vector3(x,-0.13,bridge_z),terrain)
		bridge_parts.append(plank)
		# The handrail posts travel with their plank when the bridge lowers.
		for side in [-1,1]:
			cylinder(0.045,0.40,Color("8b7964"),Vector3(0,0.25,side*(bridge_width/2-0.07)),plank)
	var p := point(level.get("plate",[-330,0]))
	plate = cylinder(0.52,0.10,Color("ecbe81"),p+Vector3(0,0.055,0),terrain)
	ring(0.56,CREAM,p+Vector3(0,0.115,0),terrain)
	box(Vector3(0.23,0.02,0.23),Color("976f3e"),p+Vector3(0,0.117,0),terrain).rotation.y=PI/4
	var landing := point(level.get("landing",[330,0]))
	landing_marker=Node3D.new()
	landing_marker.name="LandingMarker"
	landing_marker.position=landing
	terrain.add_child(landing_marker)
	ring(0.68,TEAL,Vector3(0,0.05,0),landing_marker)
	for i in range(8):
		var angle := float(i)*TAU/8
		box(Vector3(0.06,0.035,0.12),CREAM,Vector3(cos(angle)*0.85,0.03,sin(angle)*0.85),landing_marker).rotation.y=-angle
	var goal := point(level.get("goal",[470,120]))
	garden = Node3D.new()
	garden.name="Garden"
	garden.position=goal
	terrain.add_child(garden)
	cylinder(0.48,0.12,Color("6e8264"),Vector3(0,0.035,0),garden).name="Planter"
	cylinder(0.37,0.02,Color("394d40"),Vector3(0,0.11,0),garden).name="Soil"
	goal_ring = ring(0.49,Color("dce2b3"),Vector3(0,0.12,0),garden)
	goal_ring.name="GoalRing"
	_create_garden()
	if level.has("gate"):
		var gp := point(level.gate.plate)
		gate_plate=cylinder(0.48,0.10,Color("c0a6dc"),gp+Vector3(0,0.06,0),terrain)
		ring(0.53,CREAM,gp+Vector3(0,0.12,0),terrain)
	if level.has("lift"):
		_create_lift(level.lift.zone)
	for role in ["a","b"]:
		var actor := _create_spirit(GOLD if role=="a" else TEAL)
		actor.position=point(level.starts[role])
		terrain.add_child(actor)
		actors[role]=actor
		actor_targets[role]=actor.position
	seed = sphere(0.13,Color("ffda83"),actors.a.position+Vector3(0,0.8,0),terrain)
	var sm := seed.material_override as StandardMaterial3D
	sm.emission_enabled=true
	sm.emission=Color("e6b767")
	sm.emission_energy_multiplier=1.6
	var leaf := sphere(0.10,Color("bddd91"),Vector3(0.06,0.13,0),seed)
	leaf.scale=Vector3(0.5,1.0,0.22)
	leaf.rotation.z=-0.7
	bridge_ready=false

func point(coords: Array) -> Vector3:
	return Vector3(float(coords[0])/100.0,0,float(coords[1])/100.0)

func _create_lift(zone: Array) -> void:
	var width := float(zone[2]-zone[0])/100.0
	var depth := float(zone[3]-zone[1])/100.0
	var center := Vector3(float(zone[0]+zone[2])/200.0,0,float(zone[1]+zone[3])/200.0)
	lift=Node3D.new()
	lift.name="LiftDeck"
	lift.position=center
	terrain.add_child(lift)
	# The root is the simulation's walking surface. All structure stays below it;
	# the original rectangular footprint is covered even between the plank seams.
	box(Vector3(width,0.12,depth),Color("77614f"),Vector3(0,-0.14,0),lift).name="DeckBase"
	var planks := Node3D.new()
	planks.name="Planks"
	lift.add_child(planks)
	var plank_colors := [Color("bda27e"),Color("c9af8a"),Color("c2a481"),Color("b99b77")]
	for i in range(8):
		var z := -depth/2.0+(float(i)+0.5)*depth/8.0
		box(Vector3(width-0.12,0.08,depth/8.0-0.018),plank_colors[i%plank_colors.size()],Vector3(0,-0.04,z),planks)
	var beams := Node3D.new()
	beams.name="EdgeBeams"
	lift.add_child(beams)
	for side in [-1,1]:
		box(Vector3(0.12,0.18,depth),Color("917253"),Vector3(side*(width/2.0-0.06),-0.10,0),beams)
		box(Vector3(width-0.24,0.18,0.10),Color("917253"),Vector3(0,-0.10,side*(depth/2.0-0.05)),beams)
		box(Vector3(width-0.28,0.12,0.19),Color("685343"),Vector3(0,-0.23,side*depth*0.32),lift)
	# Small flush corner fasteners, with no rails across the approach or markers.
	for x_side in [-1,1]:
		for z_side in [-1,1]:
			cylinder(0.035,0.012,Color("d2b577"),Vector3(x_side*(width/2.0-0.06),-0.006,z_side*(depth/2.0-0.15)),lift)
	var mechanism := Node3D.new()
	mechanism.name="GuideMechanism"
	mechanism.position=center
	terrain.add_child(mechanism)
	for z_side in [-1,1]:
		box(Vector3(width-0.45,0.08,0.28),Color("796c58"),Vector3(0,-0.055,z_side*depth*0.32),mechanism)
		for x_side in [-1,1]:
			var guide_position := Vector3(x_side*width*0.29,0,z_side*depth*0.32)
			var guide := cylinder(0.07,1.0,Color("a1b9ae"),guide_position,mechanism)
			guide.name="GuideShaft%d" % lift_guides.size()
			guide.visible=false
			lift_guides.append(guide)
			cylinder(0.13,0.16,Color("aa8d5f"),guide_position+Vector3(0,-0.23,0),lift).name="GuideCollar%d" % (lift_guides.size()-1)

func _lift_surface_height(coords: Array, height: float) -> float:
	if not current_level.has("lift"):
		return 0.0
	var zone: Array=current_level.lift.zone
	return height if coords[0]>=zone[0] and coords[0]<=zone[2] and coords[1]>=zone[1] and coords[1]<=zone[3] else 0.0

func _make_island(cx: float, cz: float, width: float, depth: float, grass: Color) -> void:
	_island_shell(cx,cz,width,depth,grass)
	for i in range(16):
		var x := cx+sin(i*2.7)*(width/2-0.24)
		var z := cz+cos(i*1.8)*(depth/2-0.18)
		if i % 3 == 0:
			var pebble := sphere(0.09+0.025*(i%4),Color("d7d8bb"),Vector3(x,0.035,z),terrain)
			pebble.scale=Vector3(1.4,0.55,1.0)
		else:
			for j in range(3):
				var blade := box(Vector3(0.025,0.13+j*0.05,0.035),Color("638d69"),Vector3(x+j*0.04,0.06+j*0.015,z),terrain)
				blade.rotation.z=(j-1)*0.24
	# Small suspended roots make the islands legible as floating worlds.
	for i in range(5):
		var root := cylinder(0.025,0.7+i*0.07,Color("456b59"),Vector3(cx+sin(i*2.8)*(width/2-0.2),-1.35,cz+cos(i)*depth/2),terrain)
		root.rotation.z=sin(i)*0.3
	# Scenic edges stay outside the puzzle's readable central routes.
	for i in range(2):
		var tx := cx + (-0.85 if i==0 else 0.65)
		var tz := cz-depth/2+0.28
		cylinder(0.07,0.8,Color("806f59"),Vector3(tx,0.4,tz),terrain)
		var foliage := Color("659d86") if i==0 else Color("8daf83")
		for lobe in range(3):
			var crown := sphere(0.40,foliage.lightened(lobe*0.045),Vector3(tx+(lobe-1)*0.19,1.02+0.19*(1-abs(lobe-1)),tz),terrain)
			crown.scale=Vector3(0.82,1.28,0.82)
			for j in range(3):
				sphere(0.065,Color("ebc28f"),Vector3(tx+sin(j*2.1)*0.29,0.95+0.12*j,tz+cos(j*2.1)*0.25),terrain)

func _island_shell(cx: float, cz: float, width: float, depth: float, grass: Color) -> void:
	# A faceted floating landform encloses the full rectangular simulation floor.
	# Decorative bevels extend outwards; they never remove a walkable corner.
	var hx := width/2.0
	var hz := depth/2.0
	var outline: Array[Vector2] = [Vector2(-hx,-hz-0.18),Vector2(hx,-hz-0.18),Vector2(hx+0.18,-hz),Vector2(hx+0.18,hz),Vector2(hx,hz+0.18),Vector2(-hx,hz+0.18),Vector2(-hx-0.18,hz),Vector2(-hx-0.18,-hz)]
	var layers: Array = []
	for layer in range(4):
		var points: Array[Vector3] = []
		for i in range(outline.size()):
			var p: Vector2=outline[i]
			var scale_value := 1.0
			var y := -0.012
			if layer==1:
				scale_value=1.035
				y=-0.25
			elif layer==2:
				scale_value=0.91+sin(i*1.8)*0.025
				y=-0.8+cos(i*2.3)*0.1
			elif layer==3:
				scale_value=0.58+sin(i*2.7)*0.10
				y=-1.66+cos(i*2.0)*0.24
			points.append(Vector3(cx+p.x*scale_value,y,cz+p.y*scale_value))
		layers.append(points)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_smooth_group(-1)
	for i in range(outline.size()):
		var next := (i+1)%outline.size()
		_shell_triangle(surface,Vector3(cx,-0.012,cz),layers[0][i],layers[0][next],grass)
		for layer in range(3):
			var color: Color=[grass.darkened(0.08),Color("92a28b"),Color("759487")][layer]
			color=color.lightened(0.035*float(i%3))
			_shell_triangle(surface,layers[layer][i],layers[layer+1][i],layers[layer+1][next],color)
			_shell_triangle(surface,layers[layer][i],layers[layer+1][next],layers[layer][next],color)
		_shell_triangle(surface,layers[3][i],Vector3(cx+0.3,-2.32,cz-0.18),layers[3][next],Color("648175").lightened(0.03*float(i%3)))
	surface.generate_normals()
	var shell := MeshInstance3D.new()
	shell.mesh=surface.commit()
	var shell_material := material(Color.WHITE)
	shell_material.vertex_color_use_as_albedo=true
	shell_material.cull_mode=BaseMaterial3D.CULL_DISABLED
	shell.material_override=shell_material
	terrain.add_child(shell)

func _shell_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	surface.set_color(color)
	surface.add_vertex(a)
	surface.add_vertex(b)
	surface.add_vertex(c)

func _create_spirit(color: Color) -> Node3D:
	var spirit := SpiritVisual.new(color)
	spirit.stepped.connect(func():
		if spirit.visible: footstep.emit())
	return spirit

func _create_garden() -> void:
	# Four leaves make availability readable without relying on color or bloom.
	# Everything stays under the existing planter root, including on a lift.
	garden_petals.clear()
	garden_activation = Node3D.new()
	garden_activation.name = "GardenActivation"
	garden.add_child(garden_activation)
	for index in range(4):
		var angle := PI / 4.0 + float(index) * TAU / 4.0
		var radial := Node3D.new()
		radial.position = Vector3(sin(angle) * 0.33, 0.16, cos(angle) * 0.33)
		radial.rotation.y = angle
		garden_activation.add_child(radial)
		var petal := Node3D.new()
		petal.name = "Petal%d" % index
		radial.add_child(petal)
		var leaf := sphere(0.25, Color("82927c"), Vector3(0, 0, 0.18), petal)
		leaf.name = "Leaf"
		leaf.scale = Vector3(0.65, 0.26, 1.0)
		garden_petals.append(petal)
	for i in range(13):
		var flower := Node3D.new()
		var radius := 0.0 if i==0 else 0.3+float(i%4)*0.35
		flower.position=Vector3(sin(i*2.39)*radius,0,cos(i*2.39)*radius)
		garden.add_child(flower)
		var height := 0.65+float(i%3)*0.2
		cylinder(0.025,height,Color("7fa875"),Vector3(0,height/2,0),flower)
		for petal in range(5):
			var a := float(petal)*TAU/5
			var mesh := sphere(0.16,GOLD if i%2==0 else Color("dfb9be"),Vector3(cos(a)*0.18,height,sin(a)*0.18),flower)
			mesh.scale.y=0.5
		sphere(0.105,Color("f8e6a0"),Vector3(0,height+0.04,0),flower)
		flower.scale=Vector3.ONE*0.001
		flowers.append(flower)
	_present_garden(false, false, true)

func _present_garden(ready: bool, completed: bool, immediate: bool) -> void:
	if not is_instance_valid(garden) or not is_instance_valid(garden_activation):
		return
	bloomed = completed
	garden_state = "completed" if completed else "ready" if ready else "closed"
	# Availability has no animation delay: a replay seek and reduced motion show
	# the same readable pose immediately. These leaves never obstruct physics.
	var petal_angle := 0.08 if completed else -0.32 if ready else -2.18
	for petal: Node3D in garden_petals:
		petal.rotation.x = petal_angle
		var leaf := petal.get_node("Leaf") as MeshInstance3D
		var leaf_material := leaf.material_override as StandardMaterial3D
		leaf_material.albedo_color = Color("e4bb7a") if ready or completed else Color("82927c")
		leaf_material.emission_enabled = ready or completed
		leaf_material.emission = Color("ffd398")
		leaf_material.emission_energy_multiplier = 0.24 if ready or completed else 0.0
	if is_instance_valid(goal_ring):
		goal_ring.visible = ready or completed
		var ring_material := goal_ring.material_override as StandardMaterial3D
		ring_material.albedo_color = Color("f4cc8e")
		ring_material.emission_enabled = ready or completed
		ring_material.emission = Color("ffd398")
		ring_material.emission_energy_multiplier = 0.45 if completed else 1.05 if ready else 0.0
	if immediate or reduced_motion:
		for flower: Node3D in flowers:
			flower.scale = Vector3.ONE * (1.0 if completed else 0.001)
			flower.rotation.z = 0.0

func present(snapshot: Dictionary, immediate: bool=false) -> void:
	if immediate: reset_camera_exploration()
	if snapshot.is_empty() or not is_instance_valid(seed):
		return
	for role in ["a","b"]:
		var data: Dictionary=snapshot.players[role]
		actor_targets[role]=Vector3(float(data.x)/100.0,float(data.get("height",0))/100.0,float(data.z)/100.0)
		if immediate:
			actors[role].position=actor_targets[role]
			actors[role].reset_motion()
		actors[role].visible=not (role=="b" and snapshot.role=="a")
	_present_seed(snapshot.seed,immediate)
	bridge_ready=bool(snapshot.bridge_open)
	(plate.material_override as StandardMaterial3D).albedo_color=Color("f5d990") if snapshot.plate_active else Color("b5a06e")
	if is_instance_valid(gate_plate):
		(gate_plate.material_override as StandardMaterial3D).albedo_color=Color("d5c5fa") if snapshot.get("gate_open",false) else Color("907ea8")
	if is_instance_valid(lift):
		var height := float(snapshot.get("lift_height",0))/100.0
		lift.position.y=height
		for guide: MeshInstance3D in lift_guides:
			# Guide shafts extend from the fixed footings into the moving collars.
			var extension := maxf(0.001,height-0.165)
			guide.scale.y=extension
			guide.position.y=-0.015+extension/2.0
			guide.visible=height>0.165
		garden.position.y=_lift_surface_height(current_level.goal,height)
		landing_marker.position.y=_lift_surface_height(current_level.landing,height)
	_present_garden(bool(snapshot.get("gate_open", false)) and bool(snapshot.get("lift_ready", false)), bool(snapshot.complete), immediate)

func _reset_seed_pose() -> void:
	_seed_holder=""
	_seed_status=""
	_seed_launch_offset=Vector3.ZERO
	_seed_launch_age=1.0

func _present_seed(value: Dictionary, immediate: bool) -> void:
	var status := str(value.get("status",""))
	var holder := str(value.get("owner","")) if status=="held" else status.trim_prefix("held_") if status.begins_with("held_") else ""
	var target := Vector3(float(value.x)/100.0,float(value.get("height",0))/100.0+0.16,float(value.z)/100.0)
	if immediate:
		_reset_seed_pose()
	elif status=="flying" and _seed_status!="flying" and actors.has(_seed_holder):
		actors[_seed_holder].play_throw()
		# Ease only the visual handoff from the higher head to the existing arc.
		# The recorded trajectory and every catch window remain in simulation.
		_seed_launch_offset=seed.position-target
		_seed_launch_age=0.0
	_seed_status=status
	_seed_holder=holder if actors.has(holder) else ""
	_seed_snapshot_position=target
	for slot: String in actors:
		actors[slot].carrying_seed=slot==_seed_holder
	seed.visible=status not in ["planted","missed"]
	_apply_seed_pose()

func _apply_seed_pose() -> void:
	if not is_instance_valid(seed) or _seed_status.is_empty(): return
	if actors.has(_seed_holder):
		var actor: SpiritVisual=actors[_seed_holder]
		seed.position=actor.position+actor.carry_anchor_position()
	else:
		var launch_blend := maxf(0.0,1.0-_seed_launch_age/0.16) if _seed_status=="flying" and not reduced_motion else 0.0
		seed.position=_seed_snapshot_position+_seed_launch_offset*launch_blend

func _process(delta: float) -> void:
	if is_instance_valid(camera_exploration): camera_exploration.restore_frame()
	time+=delta
	var weight := minf(delta*14.0,1.0)
	for role in actors:
		if home_view and home_presentation_owner!=0:
			continue
		var actor: SpiritVisual=actors[role]
		if home_view:
			actor.visible=true
		var target: Vector3=actor_targets[role]
		var previous := actor.position
		actor.position=actor.position.lerp(target,weight)
		actor.advance_motion(actor.position-previous,delta,reduced_motion)
	_seed_launch_age+=delta
	_apply_seed_pose()
	for i in range(bridge_parts.size()):
		var desired: float = -0.10 if bridge_ready else -0.85-abs(i-4)*0.12
		bridge_parts[i].position.y=lerpf(bridge_parts[i].position.y,desired,weight)
	for i in range(flowers.size()):
		var size_target := 1.0 if bloomed else 0.001
		if reduced_motion:
			flowers[i].scale = Vector3.ONE * size_target
			flowers[i].rotation.z = 0.0
		else:
			flowers[i].scale=flowers[i].scale.lerp(Vector3.ONE*size_target,minf(delta*(2.4+i*0.08),1))
			flowers[i].rotation.z=sin(time*1.2+i)*0.035
	if not reduced_motion:
		for i in range(motes.size()):
			motes[i].position.y+=sin(time*0.4+i)*delta*0.07
	if is_instance_valid(camera) and not (home_view and home_presentation_owner!=0):
		var desired_size := 15.7 if home_view else 14.4
		camera.size=lerpf(camera.size,desired_size,delta*2)
		var center := Vector3(-2.5,0,0) if home_view else Vector3(0,0,0)
		camera.h_offset=lerpf(camera.h_offset,center.x,delta*2)

func configure_camera_exploration(active_view: Callable, allowed_point: Callable) -> void:
	camera_exploration.active = func() -> bool: return is_visible_in_tree() and home_presentation_owner == 0 and active_view.is_valid() and active_view.call()
	camera_exploration.allowed = allowed_point

func reset_camera_exploration() -> void:
	if is_instance_valid(camera_exploration): camera_exploration.reset_view()
