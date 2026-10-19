extends Node3D

signal footstep(spirit: String)
signal reunion
## A mechanism started moving (direction 1 up or out, -1 down or in) or
## stopped (0); sent on changes only. The soundscape plays its loop
## (services/sound_cues.gd MOTION). Reduce motion snaps instead of moving.
signal mechanism_moving(kind: String, id: String, direction: int)
## Visuals consume simulation snapshots. No gameplay state is owned here.

const SpiritVisual = preload("res://presentation/spirit_visual.gd")
const CameraExploration = preload("res://presentation/camera_exploration.gd")
const KeepsakeVisual = preload("res://presentation/keepsake_visual.gd")
const KeepsakeCatalog = preload("res://services/home_keepsake_catalog.gd")
const ChapterIndex = preload("res://content/chapters/index.gd")
const GraphicsPolicy = preload("res://services/graphics_policy.gd")
const ObjectMotionTrail = preload("res://presentation/object_motion_trail.gd")
const SeedMotionTrail = preload("res://presentation/seed_motion_trail.gd")
const SeedVisual = preload("res://presentation/seed_visual.gd")
const Primitives = preload("res://presentation/kit/primitives.gd")
const Badges = preload("res://presentation/kit/badges.gd")
const Look = preload("res://presentation/kit/look.gd")
const Props = preload("res://presentation/kit/props.gd")
const StaticBatch = preload("res://presentation/kit/static_batch.gd")
var _motion_quality := "balanced"
## The kit/look.gd preset the world shows, lit again when the quality changes.
var _look := "day"
var _motion_trails: Array[Node3D] = []
var _seed_trail: Node3D

var terrain: Node3D
var actors: Dictionary = {}
var actor_targets: Dictionary = {}
var seed: MeshInstance3D
var _seed_holder := ""
var _seed_status := ""
var _seed_snapshot_position := Vector3.ZERO
var _seed_previous_position := Vector3.ZERO
var _seed_snapshot_age := 0.0
const SEED_SNAPSHOT_INTERVAL := 1.0 / 30.0
var _seed_launch_offset := Vector3.ZERO
var _seed_launch_age := 1.0
## The thrown seed tumbles forward around a tilted axis while it flies. The angle
## comes from the distance flown since the throw, so a replay poses it the same.
const SEED_SPIN_PER_METRE := 2.6
const SEED_SPIN_TILT := 0.42
var _seed_launch_point := Vector3.ZERO
var _seed_spin_axis := Vector3.ZERO
var bridge_parts: Array[MeshInstance3D] = []
var plate: MeshInstance3D
var gate_plate: MeshInstance3D
var lift: Node3D
var lift_guides: Array[MeshInstance3D] = []
var landing_marker: Node3D
var garden: Node3D
var camera: Camera3D
var sun: DirectionalLight3D
var camera_exploration: Node
var current_level: Dictionary = {}
var time := 0.0
var reduced_motion := false
## Mechanisms moving now: id -> direction.
var _mechanism_motion: Dictionary = {}
var bloomed := false
var flowers: Array[Node3D] = []
var motes: Array[MeshInstance3D] = []
var _authored_motes: Array[MeshInstance3D] = []
var _graphics_authored := false
var bridge_ready := false
## Home Explore raises the bridge while the explorer is near it (home_stage.gd).
## It counts only while a Home presentation owns the view; load_level clears it.
var home_bridge_raised := false
## Plank height of a raised bridge; a lowered bridge sags well below it.
const BRIDGE_RAISED_Y := -0.10
## A mechanism within this many metres (or of its travel) of its goal is still.
const MOTION_SETTLED := 0.02
var home_view := true
var home_presentation_owner := 0
var _reunion_pending := false
var goal_ring: MeshInstance3D
var garden_activation: Node3D
var garden_petals: Array[Node3D] = []
var keepsake_landmark: Node3D
var garden_state := "closed"
const GARDEN_BLOOM_SECONDS := 2.6
var garden_bloom_age := GARDEN_BLOOM_SECONDS
var _garden_stable_pose := -1
var _garden_heads: Array[Node3D] = []
var _garden_cover: Array[Node3D] = []
var _garden_bed_bounds := Rect2()
var _garden_has_bounds := false

const CREAM := Color("e9edd6")
const TEAL := Color("91d6c6")
const GOLD := Color("f4c38d")

# Thin wrappers over the world kit. Keepsake art and every world call these.
# material() is a new material of the node's own, for a caller that changes
# it as it builds. The shape helpers give every mesh of one colour the kit's
# one cached material for that look (Primitives.shared_material), so a world
# makes a material per look, not per mesh; code that later recolours, glows
# or fades a mesh takes the mesh's own copy first (Primitives.own_material).
func material(color: Color, roughness: float = 0.9) -> StandardMaterial3D:
	return Primitives.fresh_material(color, roughness)

func mesh_node(mesh: Mesh, color: Color, pos: Vector3, parent: Node3D) -> MeshInstance3D:
	return Primitives.mesh_node(mesh, Primitives.shared_material(color), pos, parent)

# The shape helpers share one cached mesh per shape too (Primitives.cached_shape);
# code that resizes a mesh in place builds it with its own (Primitives.box_mesh).
func box(size: Vector3, color: Color, pos: Vector3, parent: Node3D) -> MeshInstance3D:
	return mesh_node(Primitives.cached_shape(Primitives.box_mesh(size)), color, pos, parent)

func sphere(radius: float, color: Color, pos: Vector3, parent: Node3D) -> MeshInstance3D:
	return mesh_node(Primitives.cached_shape(_sphere_mesh(radius)), color, pos, parent)

func _sphere_mesh(radius: float) -> SphereMesh:
	return Primitives.sphere_mesh(radius)

func cylinder(radius: float, height: float, color: Color, pos: Vector3, parent: Node3D) -> MeshInstance3D:
	return mesh_node(Primitives.cached_shape(Primitives.cylinder_mesh(radius, height)), color, pos, parent)

func ring(radius: float, color: Color, pos: Vector3, parent: Node3D) -> MeshInstance3D:
	return mesh_node(Primitives.cached_shape(Primitives.ring_mesh(radius)), color, pos, parent)

func _ready() -> void:
	# Every world starts in the day look; later lineages relight it. Colours and
	# energies come only from kit/look.gd.
	var environment_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment_node.environment = env
	add_child(environment_node)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52,-32,0)
	add_child(sun)
	var bounce := DirectionalLight3D.new()
	bounce.rotation_degrees=Vector3(28,145,0)
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
	# The motes share one material of the world's own: the look tints them all
	# at once (kit/look.gd).
	var mote_material := material(Color.WHITE)
	for i in range(32):
		var node := Primitives.mesh_node(_sphere_mesh(0.018 + (i % 3) * 0.008), mote_material, Vector3(sin(i*2.17)*11, -2+cos(i*1.23)*3,cos(i*0.91)*9), self)
		motes.append(node)
	relight("day")
	get_tree().process_frame.connect(_on_tree_frame)

## Lights the world with a kit/look.gd preset at the current quality.
func relight(look: String) -> void:
	_look = look
	Look.apply(self, look, GraphicsPolicy.fill_light(_motion_quality))

func apply_graphics_quality(quality: String) -> void:
	_motion_quality = GraphicsPolicy.normalize(quality)
	for trail: Node3D in _motion_trails:
		if is_instance_valid(trail): trail.set_quality(_motion_quality)
	# Call after the complete derived _ready: Lighthouse authors ten motes,
	# while the older island/Relay views author thirty-two. Never grow that set.
	if not is_node_ready(): return
	relight(_look)
	if not _graphics_authored:
		for mote: MeshInstance3D in motes:
			if mote.visible: _authored_motes.append(mote)
		_graphics_authored = true
	var visible_count := GraphicsPolicy.mote_count(_authored_motes.size(), quality)
	for index in range(_authored_motes.size()):
		_authored_motes[index].visible = index < visible_count

# --- Staged build: the one way a world is built over frames ---
# A chapter screen opened behind its card builds with build_staged; every
# other caller uses load_level, which builds the whole world in one call
# exactly as before. Builders mark the points where a staged build may give
# the frame back with `await _build_step()`, and worlds with stages build
# _opening_stage() first.

## While build_staged runs: the slice of each frame the build may use. 0
## outside it: _build_step never waits.
var build_budget_usec := 0
var _build_mark := 0
## While build_staged runs: the stage it opens on ("" for the first).
var _opening_stage_id := ""
## The stage the last staged build built itself, untouched since; see
## present_stage.
var _built_stage_id := ""

## A staged build's slice when its caller names none: half of the frame the
## device draws (its screen's refresh, or a lower frame cap), so the card keeps
## the frame rate the screen can hold while the build takes the rest. A loading
## card never needs more than 60 frames a second, so a faster screen still
## gets a 60 a second slice. The slice comes from the screen, never from timing
## the build's own frames: a frame the build made long would only lengthen
## the next slice and hold the card at a lower rate.
const BUILD_FRAME_SHARE := 0.5
const BUILD_FASTEST_FRAME_RATE := 60.0
const BUILD_BUDGET_RANGE_USEC := Vector2i(4000, 16000)

## The slice of each frame a staged build uses by default (microseconds) for a
## screen refreshing refresh_rate times a second under a frame cap of max_fps
## (0: none); a refresh rate the screen does not report counts as 60.
static func frame_budget_usec(refresh_rate: float = DisplayServer.screen_get_refresh_rate(), max_fps: int = Engine.max_fps) -> int:
	var rate := refresh_rate if refresh_rate > 0.0 else BUILD_FASTEST_FRAME_RATE
	if max_fps > 0: rate = minf(rate, float(max_fps))
	var frame_usec := 1000000.0 / minf(rate, BUILD_FASTEST_FRAME_RATE)
	return clampi(int(frame_usec * BUILD_FRAME_SHARE), BUILD_BUDGET_RANGE_USEC.x, BUILD_BUDGET_RANGE_USEC.y)

## Builds level over frames straight to the stage opening_stage (a stage id;
## "" for the first): opening on a later stage builds that stage once, never
## the first and then, in one frame, the saved one. Each frame it uses
## budget_usec, or for 0 a slice sized to the screen (frame_budget_usec). The
## world is the same, node for node, as load_level's. Await it.
func build_staged(level: Dictionary, budget_usec: int = 0, opening_stage: String = "") -> void:
	build_budget_usec = budget_usec if budget_usec > 0 else frame_budget_usec()
	_opening_stage_id = opening_stage
	_built_stage_id = ""
	_build_mark = Time.get_ticks_usec()
	await load_level(level)
	build_budget_usec = 0
	_opening_stage_id = ""

## A staged world shows over about this many frames (reveal_staged), a share
## of its meshes, labels and sprites each: drawing a whole chapter for the
## first time took one frame 16 to 35 ms on a desktop, Turn of the Tide the
## longest. A share is never below REVEAL_LEAST meshes, so a small world
## shows in fewer frames.
const REVEAL_FRAMES := 4
const REVEAL_LEAST := 100
var _revealing := false

## The most meshes reveal_staged shows for the first time in one frame, for a
## world that draws drawn of them.
static func reveal_share(drawn: int) -> int:
	return maxi(REVEAL_LEAST, ceili(float(drawn) / REVEAL_FRAMES))

## Shows a world a staged build left hidden, a few parts a frame, so that no
## frame draws the whole world for the first time. A part is a plain node (no
## script) shown when the reveal starts, with no more than reveal_share meshes
## under it, or else its own parts in turn; a node with a script is never
## hidden itself, only its parts are. Every node is left shown or hidden as
## it was before the world was hidden. The caller keeps the world from running meanwhile, as during the
## build. Await it.
func reveal_staged() -> void:
	_revealing = true
	# Shown and parts hidden again in this frame: nothing draws in between.
	visible = true
	var share := reveal_share(_drawn_meshes())
	var parts: Array[Array] = []
	_reveal_parts(self, parts, share)
	for part: Array in parts: (part[0] as Node3D).visible = false
	# Biggest parts first, each frame filled up with whatever still fits: near
	# the fewest frames. What is never hidden shows with the first.
	parts.sort_custom(func(a: Array, b: Array) -> bool: return int(a[1]) > int(b[1]))
	var shown := _drawn_meshes()
	while not parts.is_empty():
		var rest: Array[Array] = []
		for part: Array in parts:
			if shown > 0 and shown + int(part[1]) > share:
				rest.append(part)
				continue
			if is_instance_valid(part[0]): (part[0] as Node3D).visible = true
			shown += int(part[1])
		parts = rest
		if parts.is_empty() or not is_inside_tree(): break
		await get_tree().process_frame
		shown = 0
	for part: Array in parts:
		if is_instance_valid(part[0]): (part[0] as Node3D).visible = true
	_revealing = false
	_regather_scenery()

func _drawn_meshes() -> int:
	var drawn := 0
	for mesh: Node in find_children("*", "GeometryInstance3D", true, false):
		if (mesh as GeometryInstance3D).is_visible_in_tree(): drawn += 1
	return drawn

## Whether reveal_staged is still showing this world's parts.
func revealing() -> bool:
	return _revealing

## The parts under node that reveal_staged hides and shows again, as
## [node, meshes].
func _reveal_parts(node: Node, parts: Array[Array], share: int) -> void:
	for child: Node in node.get_children():
		if not child is Node3D or not (child as Node3D).visible: continue
		var meshes := child.find_children("*", "GeometryInstance3D", true, false).size() + (1 if child is GeometryInstance3D else 0)
		if meshes == 0: continue
		if child.get_script() == null and meshes <= share: parts.append([child, meshes])
		else: _reveal_parts(child, parts, share)

## Called once a staged world shows whole (reveal_staged). A world whose
## presentation reads what is visible (bubble scenery) reads it again here.
func _regather_scenery() -> void:
	pass

## Shows stage as a chapter screen does: through the world's show_stage, except
## a stage the last staged build has just built itself, which stays as built.
## A world whose show_stage builds a stage again even when it shows it
## already (the Lighthouse) also keeps a stage it still shows as built.
func present_stage(stage: Dictionary) -> void:
	var id := str(stage.get("id", ""))
	var kept := (not _built_stage_id.is_empty() and id == _built_stage_id) or _shows_as_built(id)
	_built_stage_id = ""
	if not kept and has_method("show_stage"): call("show_stage", stage)

## Whether stage_id is the stage this world shows, still as its last build
## left it: nothing has been presented on it since but one opening state, so
## building it again and presenting that state would show the same world.
## Only a world that rebuilds a stage it already shows needs to say so.
func _shows_as_built(_stage_id: String) -> bool:
	return false

## Of a chapter's stages, the one load_level builds: a staged build's opening
## stage, else the first; {} for none.
func _opening_stage(stages: Array) -> Dictionary:
	var chosen: Dictionary = stages[0] if not stages.is_empty() and stages[0] is Dictionary else {}
	for stage: Variant in stages:
		if stage is Dictionary and not _opening_stage_id.is_empty() and str(stage.get("id", "")) == _opening_stage_id: chosen = stage
	if build_budget_usec > 0: _built_stage_id = str(chosen.get("id", ""))
	return chosen

## In a staged build, waits one frame once the budget is spent. Await it.
func _build_step() -> void:
	if build_budget_usec <= 0 or not is_inside_tree(): return
	if Time.get_ticks_usec() - _build_mark < build_budget_usec: return
	await get_tree().process_frame
	_build_mark = Time.get_ticks_usec()

func load_level(level: Dictionary) -> void:
	reset_camera_exploration()
	_clear_object_trails()
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
	seed = SeedVisual.create(self,0.13,Color("ffda83"),actors.a.position+Vector3(0,0.8,0),terrain)
	var sm := seed.material_override as StandardMaterial3D
	sm.emission_enabled=true
	sm.emission=Color("e6b767")
	sm.emission_energy_multiplier=1.6
	bridge_ready=false
	home_bridge_raised=false
	show_keepsake_landmark(str(level.get("id", "")))

func show_keepsake_landmark(stage_id: String) -> void:
	if is_instance_valid(keepsake_landmark):
		keepsake_landmark.get_parent().remove_child(keepsake_landmark)
		keepsake_landmark.queue_free()
	keepsake_landmark = null
	var descriptor: Dictionary = {}
	for item: Dictionary in KeepsakeCatalog.all():
		if item.stage_id == stage_id:
			descriptor = item
			break
	if descriptor.is_empty() or not is_instance_valid(terrain): return
	var rect: Array = current_level.get("bounds", [-560,-290,560,290]).duplicate()
	var height := 0.0
	if not current_level.get("islands", []).is_empty():
		var island: Dictionary = current_level.islands[0]
		rect = island.rect_cm
		height = float(island.get("height_cm", 0))/100.0
	else:
		rect[2] = current_level.get("gap", [-100,100])[0]
	if rect[2]-rect[0] < 180 or rect[3]-rect[1] < 180: return
	var occupied: Array[Vector2] = []
	_keepsake_points(current_level, occupied)
	var best := Vector2.ZERO
	var best_distance := -1.0
	for x: float in [float(rect[0])+70, float(rect[2])-70]:
		for z: float in [float(rect[1])+70, float(rect[3])-70]:
			var candidate := Vector2(x,z)
			var distance := INF
			for point_cm: Vector2 in occupied: distance = minf(distance,candidate.distance_to(point_cm))
			if distance > best_distance:
				best = candidate
				best_distance = distance
	keepsake_landmark = Node3D.new()
	keepsake_landmark.name = "IslandKeepsake"
	keepsake_landmark.position = Vector3(best.x/100.0,height,best.y/100.0)
	terrain.add_child(keepsake_landmark)
	cylinder(0.43,0.16,Color("a8a38a"),Vector3(0,0.08,0),keepsake_landmark)
	var prop := KeepsakeVisual.create(self,descriptor)
	prop.position.y = 0.17
	prop.scale = Vector3.ONE*0.62
	keepsake_landmark.add_child(prop)

func _keepsake_points(value: Variant, result: Array[Vector2]) -> void:
	if value is Dictionary:
		for child: Variant in value.values(): _keepsake_points(child,result)
	elif value is Array:
		if value.size() == 2 and (value[0] is int or value[0] is float) and (value[1] is int or value[1] is float):
			result.append(Vector2(float(value[0]),float(value[1])))
		else:
			for child: Variant in value: _keepsake_points(child,result)

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

## variant 0 is the classic island (Home and the legacy islands); chapter
## islands pass their index so neighbouring islands are not clones.
func _make_island(cx: float, cz: float, width: float, depth: float, grass: Color, variant: int = 0) -> void:
	_island_shell(cx,cz,width,depth,grass)
	for n in range(16):
		var i := n + variant * 5
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
	if variant > 0:
		_vary_island(cx, cz, width, depth, variant)
		return
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

## Rear-edge scenery that differs per island: tree count and placement, fruit
## or blossom, a flowering bush or a bench. Static props share materials.
func _vary_island(cx: float, cz: float, width: float, depth: float, variant: int) -> void:
	var rear := cz - depth / 2.0 + 0.28
	var span := maxf(0.4, width / 2.0 - 0.55)
	var layouts := [[-0.85, 0.65], [-0.35, 0.95], [-1.0], [0.4, -0.95]]
	var trees: Array = layouts[variant % layouts.size()]
	var props := Node3D.new()
	props.name = "IslandScenery"
	terrain.add_child(props)
	for t in range(trees.size()):
		var tx := cx + clampf(float(trees[t]), -span, span)
		Props.build({"kind": "tree", "at": [tx * 100.0, rear * 100.0], "size": 0.95 + 0.08 * float((variant + t) % 2), "variant": variant + t}, props, 0.0, false)
	match variant % 3:
		1: Props.build({"kind": "bush", "at": [(cx + clampf(0.2, -span, span)) * 100.0, (rear - 0.02) * 100.0], "size": 0.85}, props, 0.0, false)
		2:
			Props.build({"kind": "bench", "at": [(cx + clampf(0.35, -span, span)) * 100.0, (rear - 0.04) * 100.0], "size": 0.9}, props, 0.0, false)
			Props.build({"kind": "flowers", "at": [(cx + clampf(1.0, -span, span)) * 100.0, rear * 100.0], "size": 0.8}, props, 0.0, false)
		_: Props.build({"kind": "flowers", "at": [(cx + clampf(-0.1, -span, span)) * 100.0, rear * 100.0], "size": 0.9}, props, 0.0, false)

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

func _role_badge_text(state: Dictionary, slot: String) -> String:
	var viewer: String = str(state.get("viewer_slot", ""))
	if viewer in ["p0", "p1"]: return "You" if slot == viewer else str(state.get("slot_names", {}).get(slot, "Friend"))
	return "You" if slot == str(state.active_slot) else "Memory" if state.players[slot].get("ghost", false) else "Waiting"

func _create_spirit(color: Color) -> Node3D:
	var spirit := SpiritVisual.new(color)
	spirit.stepped.connect(func():
		# Name the spirit by its slot so each one keeps its own step sounds.
		var slot: Variant = actors.find_key(spirit)
		if spirit.visible: footstep.emit("" if slot == null else str(slot)))
	spirit.reunion_started.connect(func():
		if spirit.visible: _reunion_pending=true)
	return spirit

func _create_garden() -> void:
	# Four leaves make availability readable without relying on color or bloom.
	# Everything stays under the existing planter root, including on a lift.
	_garden_stable_pose = -1
	garden_petals.clear()
	_garden_heads.clear()
	_garden_cover.clear()
	garden_bloom_age = GARDEN_BLOOM_SECONDS
	_find_garden_bounds()
	# A stretched planter keeps its layout; leaves keep their own proportions.
	# A uniform garden scale leaves this at exactly one.
	var footprint := sqrt(absf(garden.scale.x * garden.scale.z))
	var uniform := is_equal_approx(garden.scale.x, garden.scale.y) and is_equal_approx(garden.scale.x, garden.scale.z)
	var unstretch := Vector3.ONE if uniform else Vector3.ONE * footprint / garden.scale
	garden_activation = Node3D.new()
	garden_activation.name = "GardenActivation"
	garden_activation.scale = unstretch
	garden.add_child(garden_activation)
	for index in range(4):
		var angle := PI / 4.0 + float(index) * TAU / 4.0
		var radial := Node3D.new()
		radial.position = Vector3(sin(angle) * 0.33, 0.16, cos(angle) * 0.33) / unstretch
		radial.rotation.y = angle
		garden_activation.add_child(radial)
		var petal := Node3D.new()
		petal.name = "Petal%d" % index
		radial.add_child(petal)
		var leaf := sphere(0.25, Color("82927c"), Vector3(0, 0, 0.18), petal)
		leaf.name = "Leaf"
		leaf.scale = Vector3(0.65, 0.26, 1.0)
		garden_petals.append(petal)
	# A broad, low bed remains after the celebration. It never conceals the
	# goal or becomes collision, and its perimeter follows the authored island.
	for i in range(24):
		var angle := float(i) * 2.39996
		var radius := 0.78 + float(i % 4) * 0.43
		var at := _garden_bed_point(Vector3(sin(angle) * radius, 0.025, cos(angle) * radius), 0.48, 0.30)
		var occupied := false
		for previous: Node3D in _garden_cover:
			if previous.position.distance_to(at) < 0.22: occupied = true
		if occupied: continue
		var cover := Node3D.new()
		cover.name = "GardenLeafBed%d" % i
		cover.position = at
		garden.add_child(cover)
		var holder := cover
		if unstretch.is_equal_approx(Vector3.ONE): cover.rotation.y = angle
		else:
			holder = Node3D.new()
			holder.scale = unstretch
			cover.add_child(holder)
		var leaf := sphere(0.34, Color("739d76") if i % 2 == 0 else Color("97b982"), Vector3.ZERO, holder)
		if holder != cover: leaf.rotation.y = angle
		leaf.scale = Vector3(0.85, 0.095, 1.35)
		_grow(cover, Vector3.ZERO)
		_garden_cover.append(cover)
	var petal_shape := _sphere_mesh(0.225)
	for i in range(13):
		var flower := Node3D.new()
		flower.name = "GardenFlower%d" % i
		var radius := 0.0 if i == 0 else 0.50 + float(i % 4) * 0.36
		flower.position = _garden_bed_point(Vector3(sin(i * 2.39) * radius, 0, cos(i * 2.39) * radius), 0.50, 0.60)
		garden.add_child(flower)
		# A narrow planter changes the planting layout, not the shape of each
		# blossom. Keep growth on the flower root and normalize its geometry.
		var geometry := Node3D.new()
		geometry.name = "FlowerGeometry"
		geometry.scale = Vector3.ONE * minf(garden.scale.x, garden.scale.y) / garden.scale
		flower.add_child(geometry)
		# Rear blooms create a taller silhouette; the approach stays low enough
		# for both spirits and the bell/cradle to remain readable.
		var camera_side := Vector2(flower.position.x, flower.position.z).dot(Vector2(0.55, 0.83)) > -0.05
		var height := (1.06 + float(i % 3) * 0.17) * (0.34 if camera_side else 1.0)
		cylinder(0.035, height, Color("6e996f"), Vector3(0, height / 2, 0), geometry)
		for side in [-1, 1]:
			var leaf := sphere(0.24, Color("95b987"), Vector3(side * 0.12, height * 0.4, 0), geometry)
			leaf.scale = Vector3(1.0, 0.20, 0.52)
			leaf.rotation.z = side * 0.46
		var head := Node3D.new()
		head.name = "Blossom"
		head.position.y = height
		geometry.add_child(head)
		var color := GOLD if i % 3 == 0 else Color("e6b7c7") if i % 3 == 1 else Color("e8dfab")
		for petal in range(6):
			var a := float(petal) * TAU / 6
			var mesh := mesh_node(petal_shape, color, Vector3(cos(a) * 0.25, 0, sin(a) * 0.25), head)
			mesh.scale = Vector3(1.10, 0.34, 0.70)
			mesh.rotation.y = -a
		sphere(0.145, Color("fff0bf"), Vector3(0, 0.055, 0), head)
		_garden_heads.append(head)
		_grow(flower, Vector3.ZERO)
		flowers.append(flower)
	_present_garden(false, false, true)

func _find_garden_bounds() -> void:
	_garden_has_bounds = false
	var center := Vector2(garden.position.x, garden.position.z)
	var closest_height := INF
	for island: Dictionary in current_level.get("islands", []):
		var r: Array = island.rect_cm
		var rect := Rect2(Vector2(float(r[0]), float(r[1])) / 100.0, Vector2(float(r[2] - r[0]), float(r[3] - r[1])) / 100.0)
		var difference := absf(float(island.get("height_cm", 0)) / 100.0 - garden.position.y)
		if rect.has_point(center) and difference < closest_height:
			_garden_bed_bounds = rect
			_garden_has_bounds = true
			closest_height = difference
	if _garden_has_bounds or not current_level.has("bounds"): return
	var r: Array = current_level.bounds
	var gap: Array = current_level.get("gap", [-100, 100])
	var left := float(r[0]) / 100.0 if center.x < float(gap[0]) / 100.0 else float(gap[1]) / 100.0
	var right := float(gap[0]) / 100.0 if center.x < float(gap[0]) / 100.0 else float(r[2]) / 100.0
	_garden_bed_bounds = Rect2(Vector2(left, float(r[1]) / 100.0), Vector2(right - left, float(r[3] - r[1]) / 100.0))
	_garden_has_bounds = true

func _garden_bed_point(local_point: Vector3, margin: float, clearance: float) -> Vector3:
	# Every existing garden is a child of terrain, including gardens on lifts.
	# Work in that shared space so a decorative root's scale cannot move plants
	# beyond a shore. The optional clear point is also in terrain coordinates.
	var transformed := garden.transform * local_point
	var point_xz := Vector2(transformed.x, transformed.z)
	var clear_point: Variant = garden.get_meta("celebration_clear_point") if garden.has_meta("celebration_clear_point") else Vector2(garden.position.x, garden.position.z)
	if clear_point is Vector2 and point_xz.distance_to(clear_point) < clearance:
		var away: Vector2 = (point_xz - clear_point).normalized()
		if away.is_zero_approx(): away = Vector2(0, -1)
		point_xz = clear_point + away * clearance
	if _garden_has_bounds:
		var padded := _garden_bed_bounds.grow(-margin)
		point_xz.x = clampf(point_xz.x, padded.position.x, padded.end.x)
		point_xz.y = clampf(point_xz.y, padded.position.y, padded.end.y)
	transformed.x = point_xz.x
	transformed.z = point_xz.y
	return garden.transform.affine_inverse() * transformed

func _present_garden(ready: bool, completed: bool, immediate: bool) -> void:
	for actor: SpiritVisual in actors.values():
		actor.set_celebration(completed, immediate, reduced_motion)
	if not is_instance_valid(garden) or not is_instance_valid(garden_activation):
		return
	if not completed:
		garden_bloom_age = 0.0
	elif immediate or reduced_motion:
		garden_bloom_age = GARDEN_BLOOM_SECONDS
	elif not bloomed:
		garden_bloom_age = 0.0
	bloomed = completed
	garden_state = "completed" if completed else "ready" if ready else "closed"
	# Availability has no animation delay: a replay seek and reduced motion show
	# the same readable pose immediately. These leaves never obstruct physics.
	var petal_angle := 0.08 if completed else -0.32 if ready else -2.18
	for petal: Node3D in garden_petals:
		petal.rotation.x = petal_angle
		var leaf := petal.get_node("Leaf") as MeshInstance3D
		var leaf_material := Primitives.own_material(leaf)
		leaf_material.albedo_color = Color("e4bb7a") if ready or completed else Color("82927c")
		leaf_material.emission_enabled = ready or completed
		leaf_material.emission = Color("ffd398")
		leaf_material.emission_energy_multiplier = 0.24 if ready or completed else 0.0
	if is_instance_valid(goal_ring):
		goal_ring.visible = ready or completed
		var ring_material := Primitives.own_material(goal_ring)
		ring_material.albedo_color = Color("f4cc8e")
		ring_material.emission_enabled = ready or completed
		ring_material.emission = Color("ffd398")
		ring_material.emission_energy_multiplier = 0.45 if completed else 1.05 if ready else 0.0
	_advance_garden_bloom(0.0)

func _advance_garden_bloom(delta: float) -> void:
	if not is_instance_valid(garden): return
	if bloomed:
		garden_bloom_age = GARDEN_BLOOM_SECONDS if reduced_motion else minf(GARDEN_BLOOM_SECONDS, garden_bloom_age + delta)
	var settled := garden_bloom_age >= GARDEN_BLOOM_SECONDS
	var stable_pose := 0 if not bloomed else 1 if settled else -1
	if stable_pose >= 0 and stable_pose == _garden_stable_pose: return
	_garden_stable_pose = stable_pose
	for i in range(flowers.size()):
		var flower: Node3D = flowers[i]
		var age := garden_bloom_age - Vector2(flower.position.x, flower.position.z).length() * 0.17 - float(i % 3) * 0.035
		var growth := clampf(age / 0.62, 0.0, 1.0) if bloomed else 0.0
		var opened := clampf((age - 0.23) / 0.48, 0.0, 1.0) if bloomed else 0.0
		var size := 1.0 if settled and bloomed else 1.0 - pow(1.0 - growth, 3.0)
		var width := 1.0 if settled and bloomed else size + sin(growth * PI) * 0.07
		_grow(flower, Vector3(width, size, width))
		var sway := pow(1.0 - clampf(garden_bloom_age / GARDEN_BLOOM_SECONDS, 0.0, 1.0), 2.0)
		flower.rotation.z = sin(maxf(age, 0.0) * 8.0 + float(i) * 0.7) * 0.085 * sway * growth if bloomed and not settled and not reduced_motion else 0.0
		if i < _garden_heads.size():
			_grow(_garden_heads[i], Vector3.ONE * (1.0 - pow(1.0 - opened, 3.0)))
	for cover: Node3D in _garden_cover:
		var delay := Vector2(cover.position.x, cover.position.z).length() * 0.14
		var spread := clampf((garden_bloom_age - delay) / 0.40, 0.0, 1.0) if bloomed else 0.0
		_grow(cover, Vector3.ONE * (1.0 - pow(1.0 - spread, 3.0)))

## The smallest scale a growing garden piece is given (never zero, which a
## basis cannot invert).
const UNGROWN := 0.001

## Sizes a growing garden piece. One not yet grown is hidden, not drawn as a
## speck: a hidden node costs no draw call.
static func _grow(node: Node3D, size: Vector3) -> void:
	node.visible = size.x > UNGROWN and size.y > UNGROWN and size.z > UNGROWN
	node.scale = size.max(Vector3.ONE * UNGROWN)

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
	Primitives.own_material(plate).albedo_color=Color("f5d990") if snapshot.plate_active else Color("b5a06e")
	if is_instance_valid(gate_plate):
		Primitives.own_material(gate_plate).albedo_color=Color("d5c5fa") if snapshot.get("gate_open",false) else Color("907ea8")
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
	if is_instance_valid(_seed_trail): _seed_trail.reset()
	_seed_holder=""
	_seed_status=""
	_seed_launch_offset=Vector3.ZERO
	_seed_launch_age=1.0
	_seed_snapshot_age=0.0
	_seed_spin_axis=Vector3.ZERO

func _clear_object_trails() -> void:
	for trail: Node3D in _motion_trails:
		if is_instance_valid(trail): trail.reset()
	_motion_trails.clear()
	_seed_trail = null

func _present_seed(value: Dictionary, immediate: bool) -> void:
	if not is_instance_valid(_seed_trail):
		_seed_trail = SeedMotionTrail.new()
		_seed_trail.configure(self, seed, 0.13)
		terrain.add_child(_seed_trail)
		_seed_trail.set_quality(_motion_quality)
		_motion_trails.append(_seed_trail)
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
	if status=="flying" and (immediate or _seed_status!="flying"):
		_seed_launch_point=target
		_seed_spin_axis=Vector3.ZERO
	if immediate or status != "flying" or _seed_status != "flying":
		_seed_previous_position=target
		_seed_snapshot_age=SEED_SNAPSHOT_INTERVAL
	elif not target.is_equal_approx(_seed_snapshot_position):
		# Interpolate one recorded tick behind. Do not predict or alter catches.
		_seed_previous_position=_seed_snapshot_position
		_seed_snapshot_age=0.0
	preload("res://presentation/plant_animation.gd").on_seed(self, seed, _seed_status, value, target, immediate)
	_seed_status=status
	_seed_holder=holder if actors.has(holder) else ""
	_seed_snapshot_position=target
	var material := seed.material_override as StandardMaterial3D
	var carry_color := GOLD if _seed_holder in ["a", "p0"] else TEAL if _seed_holder in ["b", "p1"] else CREAM
	# The icon's seed is white; the holder only tints it, and the glow carries their colour.
	material.albedo_color = SeedVisual.WHITE.lerp(carry_color, 0.4 if _seed_holder != "" else 0.0)
	material.emission = carry_color
	# A soft glow that keeps the carried hue visible instead of clipping it to white.
	material.emission_energy_multiplier = 0.22
	SeedVisual.tint_glow(seed, carry_color)
	for slot: String in actors:
		actors[slot].carrying_seed=slot==_seed_holder
	seed.visible=status not in ["planted","missed"]
	_seed_trail.tint = carry_color
	_seed_trail.set_motion_allowed(status == "flying" and seed.visible, immediate)
	_apply_seed_pose()

func _create_object_trail(object: Node3D, radius: float) -> Node3D:
	var trail := ObjectMotionTrail.new()
	trail.configure(self, object, radius)
	terrain.add_child(trail)
	trail.set_quality(_motion_quality)
	_motion_trails.append(trail)
	return trail

func _apply_seed_pose() -> void:
	if not is_instance_valid(seed) or _seed_status.is_empty(): return
	if actors.has(_seed_holder):
		var actor: SpiritVisual=actors[_seed_holder]
		seed.position=actor.position+actor.carry_anchor_position()
	else:
		var launch_blend := maxf(0.0,1.0-_seed_launch_age/0.16) if _seed_status=="flying" and not reduced_motion else 0.0
		var flight_position := _seed_previous_position.lerp(_seed_snapshot_position, clampf(_seed_snapshot_age / SEED_SNAPSHOT_INTERVAL, 0.0, 1.0)) if _seed_status=="flying" else _seed_snapshot_position
		seed.position=flight_position+_seed_launch_offset*launch_blend
		if _seed_status=="flying" and not reduced_motion:
			_spin_seed(flight_position)
			return
	_upright_seed()

func _spin_seed(flight_position: Vector3) -> void:
	var travel := flight_position-_seed_launch_point
	var distance := travel.length()
	if _seed_spin_axis.is_zero_approx():
		var level := Vector3(travel.x,0.0,travel.z)
		if level.length() < 0.02:
			_upright_seed()
			return
		# Lock the axis once per throw: across the flight, tipped toward the sky.
		var side := Vector3.UP.cross(level.normalized())
		_seed_spin_axis=(side*cos(SEED_SPIN_TILT)+Vector3.UP*sin(SEED_SPIN_TILT)).normalized()
	_set_seed_rotation(Quaternion(_seed_spin_axis,distance*SEED_SPIN_PER_METRE))

func _upright_seed() -> void:
	_set_seed_rotation(Quaternion.IDENTITY)

func _set_seed_rotation(rotation_value: Quaternion) -> void:
	if seed.quaternion.is_equal_approx(rotation_value): return
	seed.quaternion=rotation_value
	# The soft halo is a billboard; keep its own transform unrotated as well.
	var glow := seed.get_node_or_null("SeedGlow") as Node3D
	if glow != null: glow.quaternion=rotation_value.inverse()

func update_spirit_attention() -> void:
	# Rendered positions drive expression only; no snapshot or input is changed.
	_reunion_pending=false
	for role: String in actors:
		var actor: SpiritVisual=actors[role]
		actor.set_expression_role(role)
		var partner: Node3D=null
		for other: String in actors:
			if other!=role and actors[other].visible:
				partner=actors[other]
				break
		actor.set_partner_offset(actor.to_local(partner.global_position) if partner!=null else Vector3.ZERO,actor.visible and partner!=null)

func finish_spirit_motion() -> void:
	# Both spirits greet in the same frame; their pair shares one sound.
	if not _reunion_pending: return
	_reunion_pending=false
	reunion.emit()

func greet_home_spirits() -> bool:
	# Home-only tap flourish. Gameplay and replays never call this.
	if not home_view or home_presentation_owner==0: return false
	var pair: Array[SpiritVisual] = []
	for role: String in actors:
		var actor: SpiritVisual=actors[role]
		if not actor.visible: continue
		# An active greeting or reunion finishes before another can start.
		if actor.is_happy(): return false
		pair.append(actor)
	if pair.is_empty(): return false
	for actor: SpiritVisual in pair:
		actor.play_greeting(reduced_motion)
		if not reduced_motion and is_instance_valid(camera):
			actor.facing_target=_greeting_facing(actor,pair)
	# The pair shares one sound through the existing reunion route.
	reunion.emit()
	return true

func _greeting_facing(actor: SpiritVisual, pair: Array[SpiritVisual]) -> float:
	# Face the viewer, turned a little toward the partner, so the eyes read.
	var inverse := actor.global_basis.inverse()
	var toward := inverse*camera.global_basis.z
	var direction := Vector2(toward.x,toward.z).normalized()
	for other: SpiritVisual in pair:
		if other==actor: continue
		var offset := inverse*(other.global_position-actor.global_position)
		direction+=Vector2(offset.x,offset.z).normalized()*0.6
	return actor.facing_target if direction.is_zero_approx() else atan2(direction.x,direction.y)

## Chapters whose worlds draw their finished terrain as a few batches
## (kit/static_batch.gd), folded from the first frame after a build: a staged
## build cannot process until it is whole, and a new stage builds a new
## terrain. Home folds its island itself (home_stage.gd).
## A registered chapter says so in its descriptor ("fold_static").
static var STATIC_FOLD_CHAPTERS: Array[String] = _static_fold_chapters()
## Folded keys that are not registered chapters.
const OTHER_STATIC_FOLD_CHAPTERS: Array[String] = ["sleeping-lighthouse@1"]

static func _static_fold_chapters() -> Array[String]:
	var result: Array[String] = OTHER_STATIC_FOLD_CHAPTERS.duplicate()
	for key: String in ChapterIndex.keys():
		if ChapterIndex.data(key).fold_static: result.append(key)
	result.make_read_only()
	return result

## The chapter key this world shows, for STATIC_FOLD_CHAPTERS. Home and the
## older islands have none.
func _fold_key() -> String:
	return ""

func _folds_static_scenery() -> bool:
	return _fold_key() in STATIC_FOLD_CHAPTERS

## A chapter screen sets this so a big world folds over frames instead of in
## one frame; otherwise the fold finishes on its first frame. Over frames it
## takes FOLD_FRAME_USEC a frame while the world runs (play), and while it is
## held still behind a card (the ready and waiting cards, before the first
## turn) the slice a staged build takes at the screen's own rate
## (frame_budget_usec, never stretched by the card's lower frame cap): nothing
## else moves then, so the fold is done in a few frames instead of running on
## for seconds after the card.
var fold_over_frames := false
const FOLD_FRAME_USEC := 3000

## The held slice, worked out once per fold (the screen's rate is a native
## call on a phone).
var _fold_held_usec := FOLD_FRAME_USEC

## The slice of this frame the fold takes (microseconds; 0 for all of it).
func _fold_slice_usec() -> int:
	if not fold_over_frames: return 0
	return FOLD_FRAME_USEC if is_processing() else _fold_held_usec

var _fold_job: Dictionary = {}

## Nodes whose children are looked up or walked one by one after the build;
## they and everything under them stay as built. The planter's cylinders give
## the planting animation its soil height (plant_animation.gd).
func _static_keep() -> Array:
	return [garden]

## Held nodes that are held only to be found: they never move, hide, fade or
## recolour, so their plain leaves fold with the scenery around them
## (StaticBatch "still"). None here; a world adds the ones it owns.
func _still_held() -> Array:
	return []

## How this world's terrain folds (kit/static_batch.gd): every held container's
## plain leaves batch under it, what _static_keep names stays whole, and what
## _still_held names folds with the scenery around it.
func _fold_options() -> Dictionary:
	return {"containers": true, "keep": _static_keep(), "still": _still_held()}

var _fold_frame := -1

## A chapter screen keeps its world from running behind the ready card; the
## scenery folds then too, but never while the world cannot process at all
## (mid-build).
func _on_tree_frame() -> void:
	# A world whose screen has left is out of the tree until it is freed.
	if is_inside_tree() and can_process(): _fold_static_scenery_once()

## Over frames, one fold step per engine frame, from whichever of _process
## and the tree's frame comes first. A fold done in one go needs no guard.
func _fold_static_scenery_once() -> void:
	var frame := Engine.get_process_frames()
	if fold_over_frames and frame == _fold_frame: return
	_fold_frame = frame
	_fold_static_scenery()

## Whether this world's terrain still has a fold to start or finish.
func scenery_folding() -> bool:
	return not _fold_job.is_empty() or (is_instance_valid(terrain) and not terrain.has_meta(StaticBatch.FOLDED_META) and _folds_static_scenery())

## Starts or continues folding the current terrain. Returns the fold's job
## ({} when there is nothing to fold); its "done" says whether it finished.
func _fold_static_scenery() -> Dictionary:
	if not _fold_job.is_empty() and (not is_instance_valid(terrain) or int(_fold_job.root_id) != terrain.get_instance_id()): _fold_job = {}
	if _fold_job.is_empty():
		if not is_instance_valid(terrain) or terrain.has_meta(StaticBatch.FOLDED_META) or not _folds_static_scenery(): return {}
		# The screen holding this world may name its nodes as well. Only the
		# nearest scripted holder: further up sit Main and its saves, whose
		# journals and recordings would take seconds to look through and hold
		# none of this world's nodes.
		var owners: Array = [self]
		var holder := get_parent()
		while holder != null and holder.get_script() == null: holder = holder.get_parent()
		if holder != null: owners.append(holder)
		_fold_job = StaticBatch.start(terrain, owners, _fold_options())
		if _fold_job.is_empty(): return {}
		_fold_held_usec = frame_budget_usec(DisplayServer.screen_get_refresh_rate(), 0)
	var job := _fold_job
	if StaticBatch.step(job, _fold_slice_usec()): _fold_job = {}
	return job

func _process(delta: float) -> void:
	_fold_static_scenery_once()
	# A full frame may move anything; the next card settles again.
	_idle_card_settled=false
	if is_instance_valid(camera_exploration): camera_exploration.restore_frame()
	time+=delta
	var weight := minf(delta*14.0,1.0)
	if not (home_view and home_presentation_owner!=0):
		update_spirit_attention()
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
	if not (home_view and home_presentation_owner!=0):
		finish_spirit_motion()
	_seed_launch_age+=delta
	_seed_snapshot_age+=delta
	_apply_seed_pose()
	for trail: Node3D in _motion_trails:
		if is_instance_valid(trail): trail.advance(delta, reduced_motion)
	var raised := bridge_ready or (home_bridge_raised and home_view and home_presentation_owner!=0)
	var bridge_travel := 0.0
	for i in range(bridge_parts.size()):
		var desired: float = BRIDGE_RAISED_Y if raised else -0.85-abs(i-4)*0.12
		bridge_travel = maxf(bridge_travel, absf(desired - bridge_parts[i].position.y))
		bridge_parts[i].position.y=lerpf(bridge_parts[i].position.y,desired,weight)
	note_motion("drawbridge", "drawbridge", (1 if raised else -1) if bridge_travel > MOTION_SETTLED else 0)
	_advance_garden_bloom(delta)
	if not reduced_motion:
		for i in range(motes.size()):
			if motes[i].visible:
				motes[i].position.y+=sin(time*0.4+i)*delta*0.07
	_advance_camera(delta)

## On a card over a held world (a chapter's ready and waiting screens) only
## the spirits keep breathing: nothing else in the world moves, and the pose
## is written IDLE_CARD_HZ times a second, so a calm screen that draws only on
## change draws that often. Spirit motion is closed-form in its own clock, so
## coarse steps reach the same pose. Under Reduce motion one step settles
## them and the rest write nothing, so a still card draws nothing. Returns
## whether this call moved them.
const IDLE_CARD_HZ := 12.0
var _idle_card_clock := 0.0
var _idle_card_settled := false

func advance_idle(delta: float) -> bool:
	if home_view and home_presentation_owner!=0: return false
	if not reduced_motion: _idle_card_settled=false
	elif _idle_card_settled: return false
	_idle_card_clock+=maxf(delta,0.0)
	if _idle_card_clock<1.0/IDLE_CARD_HZ: return false
	var step := _idle_card_clock
	_idle_card_clock=0.0
	update_spirit_attention()
	for role in actors:
		var actor: SpiritVisual=actors[role]
		actor.advance_motion(Vector3.ZERO,step,reduced_motion)
	finish_spirit_motion()
	_idle_card_frame()
	_idle_card_settled=reduced_motion
	return true

## The rest of a card frame: what a spirit carries back on its carry anchor
## (worlds add their own, such as Lighthouse lenses and settled bubbles).
func _idle_card_frame() -> void:
	if is_instance_valid(seed) and not _seed_status.is_empty() and actors.has(_seed_holder):
		seed.position=actors[_seed_holder].position+actors[_seed_holder].carry_anchor_position()

## Reports a mechanism's movement on change only. Under Reduce motion an
## animated mechanism snaps into place, so it never starts a loop; `animated`
## false is for running water and the like, which sound either way.
func note_motion(kind: String, id: String, direction: int, animated: bool = true) -> void:
	if animated and reduced_motion: direction = 0
	if int(_mechanism_motion.get(id, 0)) == direction: return
	if direction == 0: _mechanism_motion.erase(id)
	else: _mechanism_motion[id] = direction
	mechanism_moving.emit(kind, id, direction)

func _advance_camera(delta: float) -> void:
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

# --- Waiting for the friend's memory (presentation/memory_wait.gd) ---

## How close (metres) a dozing spirit must be to its goal to lean on it.
const DOZE_LEAN_REACH := 1.6
## The spirit the camera follows in place of the live one while the live one
## waits for its friend's memory; empty otherwise. Worlds with a following
## camera read it through _camera_slot().
var camera_focus := ""

## The spirit a following camera tracks: the memory while the live spirit
## waits, otherwise `live`.
func _camera_slot(live: String) -> String:
	return camera_focus if not camera_focus.is_empty() and actors.has(camera_focus) else live

## The live spirit has done its part: it dozes by its goal and the camera
## eases over to the memory. Called every tick of the wait; cheap when unchanged.
func show_memory_wait(live: String, memory: String, immediate: bool = false) -> void:
	camera_focus = memory if actors.has(memory) else ""
	if not actors.has(live) or not actors[live].has_method("set_pose"): return
	var actor: Node3D = actors[live]
	var params := {}
	var anchor: Variant = _doze_anchor(actor)
	if anchor is Vector3: params["toward"] = anchor
	actor.set_pose(&"doze", params, immediate)

## The memory has ended: the dozing spirit wakes with a start.
func wake_from_memory_wait(live: String, reduced: bool) -> void:
	if actors.has(live) and actors[live].has_method("play_wake"): actors[live].play_wake(reduced)

## The wait is over and the goal has rung: the camera returns to its own rules.
func end_memory_wait(live: String) -> void:
	camera_focus = ""
	if not actors.has(live) or not actors[live].has_method("pose"): return
	if actors[live].pose() == &"doze": actors[live].set_pose(&"rest")

## Goal pieces a waiting spirit may lean on; worlds add their bells.
func _doze_anchors() -> Array[Node3D]:
	var anchors: Array[Node3D] = []
	if is_instance_valid(garden): anchors.append(garden)
	return anchors

## The nearest goal piece within reach, as a global point, or null.
func _doze_anchor(actor: Node3D) -> Variant:
	if not actor.is_inside_tree(): return null
	var best: Variant = null
	var reach := DOZE_LEAN_REACH
	for anchor: Node3D in _doze_anchors():
		if not is_instance_valid(anchor) or not anchor.is_inside_tree(): continue
		var at := anchor.global_position
		var distance := Vector2(at.x - actor.global_position.x, at.z - actor.global_position.z).length()
		if distance <= reach:
			reach = distance
			best = at
	return best
