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
const KeepsakeCatalog = preload("res://services/home_keepsake_catalog.gd")
const ChapterIndex = preload("res://content/chapters/index.gd")
const GraphicsPolicy = preload("res://services/graphics_policy.gd")
const SpaceBackdrop = preload("res://presentation/kit/space_backdrop.gd")
const ObjectMotionTrail = preload("res://presentation/object_motion_trail.gd")
const SeedMotionTrail = preload("res://presentation/seed_motion_trail.gd")
const SeedVisual = preload("res://presentation/seed_visual.gd")
const Primitives = preload("res://presentation/kit/primitives.gd")
## The spirits' ownership marks (kit/owner_mark.gd), whose colours are the worlds' spirit colours.
const OwnerMark = preload("res://presentation/kit/owner_mark.gd")
const Badges = preload("res://presentation/kit/badges.gd")
const Look = preload("res://presentation/kit/look.gd")
## The piece kits' palette, shapes and glow (kit/pieces/parts.gd).
const Parts = preload("res://presentation/kit/pieces/parts.gd")
## Where the seed rests, is planted and lands (kit/pieces/socket.gd).
const SocketKit = preload("res://presentation/kit/pieces/socket.gd")
const Props = preload("res://presentation/kit/props.gd")
## Scenery as data (content/dressing) and the ground styles it names.
const DressingCatalog = preload("res://content/dressing/catalog.gd")
const Surfaces = preload("res://presentation/kit/surfaces.gd")
## A piece's style (content/dressing/piece_styles.gd) and the pad kit.
const PieceStyles = preload("res://content/dressing/piece_styles.gd")
const PadKit = preload("res://presentation/kit/pieces/pad.gd")
## A crossing that rises as it opens and sinks as it shuts (kit/pieces/bridge.gd).
const BridgeKit = preload("res://presentation/kit/pieces/bridge.gd")
## Each family's floors, crossings and spots (services/level_layout.gd).
const LevelLayout = preload("res://services/level_layout.gd")
## A piece's move players should notice: the view's shake and the phone's buzz.
const BigChange = preload("res://presentation/kit/big_change.gd")
## Gates, stair chains, zone ropes and locks: why a pip is refused.
const RouteBarriers = preload("res://presentation/kit/route_barriers.gd")
## The lettered tiles that tie a control to the gates it works.
const PairTags = preload("res://presentation/kit/pair_tags.gd")
const FIREFLY := Color("ffe9a8")
## This chapter's scenery data (content/dressing); empty keeps the plain world.
var dressing: Dictionary = {}
## Walkable surface roots by island id, where props on that surface belong.
var _surface_nodes: Dictionary = {}
var _fireflies: Array[MeshInstance3D] = []
const StaticBatch = preload("res://presentation/kit/static_batch.gd")
const ContactShadows = preload("res://presentation/kit/contact_shadows.gd")
## The world's soft contact shadows (kit/contact_shadows.gd).
var contact_shadows: Node3D
## Every world camera writes its size through this (tall screens keep the authored width).
const ViewFit = preload("res://presentation/kit/view_fit.gd")
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
var lift: Node3D
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
## The world's Environment, whose sky is the space backdrop (kit/space_backdrop.gd).
var environment: Environment
## The backdrop's own clock: the world's time while motion is allowed.
var _backdrop_clock := 0.0
## What the backdrop's layout was last read from: Home's owner and the loaded
## level (by reference), so the key is worked out only when one changes.
var _backdrop_from: Array = []
var bridge_ready := false
## Home Explore raises the bridge while the explorer is near it (home_stage.gd).
## It counts only while a Home presentation owns the view; load_level clears it.
var home_bridge_raised := false
## Plank height of a raised bridge; a lowered bridge sags well below it.
const BRIDGE_RAISED_Y := -0.10

## Plank `i`'s resting height, raised or lowered.
static func bridge_plank_y(i: int, raised: bool) -> float:
	return BRIDGE_RAISED_Y if raised else -0.85 - absf(i - 4) * 0.12
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

const CREAM := Parts.CREAM
const TEAL := OwnerMark.TEAL
const GOLD := OwnerMark.GOLD

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
	return mesh_node(Primitives.cached_box(size), color, pos, parent)

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
	environment = SpaceBackdrop.environment()
	environment_node.environment = environment
	add_child(environment_node)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52,-32,0)
	add_child(sun)
	var bounce := DirectionalLight3D.new()
	bounce.rotation_degrees=Vector3(28,145,0)
	add_child(bounce)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = ViewFit.viewport(14.4, self)
	camera.position = Vector3(10,13,15)
	add_child(camera)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	camera_exploration = CameraExploration.new()
	camera_exploration.camera = camera
	camera_exploration.reduced_motion = func() -> bool: return reduced_motion
	add_child(camera_exploration)
	SpaceBackdrop.apply_quality(environment, _motion_quality)
	# Soft contact shadows under everything marked in this world, one draw call.
	contact_shadows = ContactShadows.new()
	contact_shadows.set_quality(_motion_quality)
	add_child(contact_shadows)
	relight("day")
	get_tree().process_frame.connect(_on_tree_frame)

## Lights the world with a kit/look.gd preset at the current quality.
func relight(look: String) -> void:
	_look = look
	Look.apply(self, look, GraphicsPolicy.fill_light(_motion_quality))

## The kit/look.gd preset the world is lit with now.
func look_name() -> String:
	return _look

## The graphics quality the world draws at now (GraphicsPolicy.QUALITIES).
func graphics_quality() -> String:
	return _motion_quality

func apply_graphics_quality(quality: String) -> void:
	_motion_quality = GraphicsPolicy.normalize(quality)
	if is_instance_valid(contact_shadows): contact_shadows.set_quality(_motion_quality)
	for trail: Node3D in _motion_trails:
		if is_instance_valid(trail): trail.set_quality(_motion_quality)
	if not is_node_ready(): return
	relight(_look)
	SpaceBackdrop.apply_quality(environment, _motion_quality)
	for fly: MeshInstance3D in _fireflies:
		if is_instance_valid(fly): fly.visible = GraphicsPolicy.fireflies(quality)

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
	if not kept: show_stage(stage)

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

## A staged build paced by its owner instead of the tree's frames
## (services/world_prewarm.gd): once the budget is spent each _build_step
## waits for the owner's next build_tick, in or out of the tree. An owner that
## stops ticking and frees the world leaves the build where it was: a world
## freed while it waits on its own signal is never resumed.
signal build_tick
var paced_build := false

## In a staged build, waits one frame (or, paced, one build_tick) once the
## budget is spent. Await it.
func _build_step() -> void:
	if build_budget_usec <= 0 or (not paced_build and not is_inside_tree()): return
	if Time.get_ticks_usec() - _build_mark < build_budget_usec: return
	if paced_build: await build_tick
	else: await get_tree().process_frame
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
	sound_anchors.clear()
	flowers.clear()
	bloomed = false
	lift = null
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
	island_soil = Surfaces.soil(CLASSIC_GROUND)
	_make_island((min_x+left_edge)/2.0, z_center, left_edge-min_x, depth, grass)
	_make_island((right_edge+max_x)/2.0, z_center, max_x-right_edge, depth, grass)
	var bridge: Dictionary = level.get("bridge", {"z":0,"width":180})
	var bridge_z := float(bridge.get("z",0))/100.0
	var bridge_width := float(bridge.get("width",180))/100.0
	for i in range(9):
		var x := lerpf(left_edge,right_edge,float(i+0.5)/9.0)
		# Built where it rests (load_level leaves the bridge down), so a new
		# level never starts by lowering it: that reported a moving drawbridge
		# on the first frame, and its reel sounded through the launch splash.
		var plank := box(Vector3((right_edge-left_edge)/9.0-0.025,0.12,bridge_width),Color("c4b090"),Vector3(x,bridge_plank_y(i,false),bridge_z),terrain)
		bridge_parts.append(plank)
		# The one crossing sounds from its middle plank.
		if i == 4: mark_sound("bridge:", plank)
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
	SocketKit.landing(landing_marker)
	var goal := point(level.get("goal",[470,120]))
	garden = Node3D.new()
	garden.name="Garden"
	garden.position=goal
	terrain.add_child(garden)
	goal_ring = SocketKit.garden(garden,0.48,Color("dce2b3"))
	_create_garden(SocketKit.PLANTER + 0.02)
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
	# A chapter's corner shows its Home keepsake's first look.
	var home: Dictionary = {} if descriptor.is_empty() else ChapterIndex.home_keepsake(str(descriptor.family))
	if home.is_empty() or not is_instance_valid(terrain): return
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
	var prop := Node3D.new()
	prop.name = "Keepsake_" + str(descriptor.family).replace("-", "_")
	var builder: RefCounted = load(str(home.keepsake.builder)).new()
	builder.build(prop, {})
	prop.position.y = 0.17
	# Home's keepsakes are drawn large; the corner shows one as small as it fits.
	prop.scale = Vector3.ONE*builder.landmark_scale()
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

## The ground style (kit/surfaces.gd) under the classic islands, Home's:
## grass over soil.
const CLASSIC_GROUND := "grass"
## The soil (kit/surfaces.gd soil) under this world's islands and the islands
## a screen adds to them; {} keeps the plain green shell. Only the classic
## level build sets it.
var island_soil: Dictionary = {}

## variant 0 is the classic island (Home); chapter
## islands pass their index so neighbouring islands are not clones.
func _make_island(cx: float, cz: float, width: float, depth: float, grass: Color, variant: int = 0) -> void:
	_island_shell(cx,cz,width,depth,grass,null,island_soil)
	island_dressing(cx,cz,width,depth,variant,terrain)
	# Scenic edges stay outside the puzzle's readable central routes.
	if variant > 0:
		_vary_island(cx, cz, width, depth, variant)
		return
	for i in range(2):
		var tx := cx + (-0.85 if i==0 else 0.65)
		var tz := cz-depth/2+0.28
		# Each tree under its own root, grounded like any prop.
		var tree := Node3D.new()
		tree.name = "Tree"
		terrain.add_child(tree)
		ContactShadows.mark(tree)
		cylinder(0.07,0.8,Color("806f59"),Vector3(tx,0.4,tz),tree)
		var foliage := Color("659d86") if i==0 else Color("8daf83")
		for lobe in range(3):
			var crown := sphere(0.40,foliage.lightened(lobe*0.045),Vector3(tx+(lobe-1)*0.19,1.02+0.19*(1-abs(lobe-1)),tz),tree)
			crown.scale=Vector3(0.82,1.28,0.82)
			for j in range(3):
				sphere(0.065,Color("ebc28f"),Vector3(tx+sin(j*2.1)*0.29,0.95+0.12*j,tz+cos(j*2.1)*0.25),tree)

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

## An island's pebbles, grass tufts and hanging roots under `parent`: the
## level's islands, and the islands a screen adds (Home's keepsake isles).
func island_dressing(cx: float, cz: float, width: float, depth: float, variant: int, parent: Node3D) -> void:
	for n in range(16):
		var i := n + variant * 5
		var x := cx+sin(i*2.7)*(width/2-0.24)
		var z := cz+cos(i*1.8)*(depth/2-0.18)
		if i % 3 == 0:
			var pebble := sphere(0.09+0.025*(i%4),Color("d7d8bb"),Vector3(x,0.035,z),parent)
			pebble.scale=Vector3(1.4,0.55,1.0)
		else:
			for j in range(3):
				var blade := box(Vector3(0.025,0.13+j*0.05,0.035),Color("638d69"),Vector3(x+j*0.04,0.06+j*0.015,z),parent)
				blade.rotation.z=(j-1)*0.24
	# Small suspended roots make the islands legible as floating worlds.
	var root_color: Color = island_soil.get("root", Color("456b59"))
	for i in range(5):
		var root := cylinder(0.025,0.7+i*0.07,root_color,Vector3(cx+sin(i*2.8)*(width/2-0.2),-1.35,cz+cos(i)*depth/2),parent)
		root.rotation.z=sin(i)*0.3

## An island's floating landform under `parent`, for islands a screen adds
## to the level's own (Home's keepsake isles, presentation/keepsakes/home_isles.gd).
## Its sides match the level's islands (island_soil).
func island_shell(cx: float, cz: float, width: float, depth: float, grass: Color, parent: Node3D) -> void:
	_island_shell(cx, cz, width, depth, grass, parent, island_soil)

## `parent`: where the shell goes (the terrain when left out). `soil`
## (kit/surfaces.gd soil): the sides below the grass lip run soil down to a
## darker underside; {} keeps the plain green shell.
func _island_shell(cx: float, cz: float, width: float, depth: float, grass: Color, parent: Node3D = null, soil: Dictionary = {}) -> void:
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
	var sides: Array = [grass.darkened(0.08),soil.band,soil.soil] if not soil.is_empty() else [grass.darkened(0.08),Color("92a28b"),Color("759487")]
	var underside: Color = soil.get("underside", Color("648175"))
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_smooth_group(-1)
	for i in range(outline.size()):
		var next := (i+1)%outline.size()
		_shell_triangle(surface,Vector3(cx,-0.012,cz),layers[0][i],layers[0][next],grass)
		for layer in range(3):
			var color: Color=sides[layer]
			color=color.lightened(0.035*float(i%3))
			_shell_triangle(surface,layers[layer][i],layers[layer+1][i],layers[layer+1][next],color)
			_shell_triangle(surface,layers[layer][i],layers[layer+1][next],layers[layer][next],color)
		_shell_triangle(surface,layers[3][i],Vector3(cx+0.3,-2.32,cz-0.18),layers[3][next],underside.lightened(0.03*float(i%3)))
	surface.generate_normals()
	var shell := MeshInstance3D.new()
	shell.mesh=surface.commit()
	var shell_material := material(Color.WHITE)
	shell_material.vertex_color_use_as_albedo=true
	shell_material.cull_mode=BaseMaterial3D.CULL_DISABLED
	shell.material_override=shell_material
	(parent if parent != null else terrain).add_child(shell)
	# Its grass is a ground what stands on it is baked into (kit/contact_shadows.gd).
	ContactShadows.ground(parent if parent != null else terrain, Rect2(cx-hx, cz-hz, width, depth), 0.0, true)

func _shell_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	surface.set_color(color)
	surface.add_vertex(a)
	surface.add_vertex(b)
	surface.add_vertex(c)

func _role_badge_text(state: Dictionary, slot: String) -> String:
	var viewer: String = str(state.get("viewer_slot", ""))
	if viewer in ["p0", "p1"]: return "You" if slot == viewer else str(state.get("slot_names", {}).get(slot, "Friend"))
	return "You" if slot == str(state.active_slot) else "Memory" if state.players[slot].get("ghost", false) else "Waiting"

## What each slot's pip wears ({"p0": look, "p1": look}; presentation/slot_looks.gd).
## Kept here, so every pip a stage builds later wears its slot's look too.
var slot_looks: Dictionary = {}

## Dresses each slot's pip now and on every later stage. A slot left out wears the default look.
func wear_slots(looks: Dictionary) -> void:
	slot_looks = looks.duplicate(true)
	for slot_id: Variant in actors:
		var actor: Variant = actors[slot_id]
		if is_instance_valid(actor) and actor is Node3D and actor.has_method("wear"): actor.wear(slot_looks.get(slot_id, {}))

## A pip for `slot_id` (p0 or p1; "" for one that belongs to no room slot), in its slot's look.
func _create_spirit(color: Color, slot_id: String = "") -> Node3D:
	var spirit := SpiritVisual.new(color)
	if slot_looks.has(slot_id): spirit.wear(slot_looks[slot_id])
	spirit.stepped.connect(func():
		# Name the spirit by its slot so each one keeps its own step sounds.
		var slot: Variant = actors.find_key(spirit)
		if spirit.visible: footstep.emit("" if slot == null else str(slot)))
	spirit.reunion_started.connect(func():
		if spirit.visible: _reunion_pending=true)
	return spirit

## `leaf_height`: where the four leaves sit, just over the planter's drum
## (a SocketKit planter's is SocketKit.PLANTER).
func _create_garden(leaf_height: float = 0.16) -> void:
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
		radial.position = Vector3(sin(angle) * 0.33, leaf_height, cos(angle) * 0.33) / unstretch
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
	var was_ready := bridge_ready
	bridge_ready=bool(snapshot.bridge_open)
	if immediate: _settle_bridge()
	elif bridge_ready != was_ready: note_big_change("drawbridge", BigChange.SECONDS)
	Primitives.own_material(plate).albedo_color=Color("f5d990") if snapshot.plate_active else Color("b5a06e")
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
## the planting animation its soil height (plant_animation.gd). The route
## barriers' mesh shows and wiggles piece by piece, the ball rings follow the
## balls, and a pad's lit parts change.
func _static_keep() -> Array:
	var keep: Array = [garden] + route_barriers.moving_nodes()
	for piece: RefCounted in pad_pieces.values(): keep += piece.moving_parts()
	if not _marks_fold(): keep += owner_marks.made() + pair_tags.made()
	return keep

## Whether the stage's ownership marks and pair tags fold with the scenery:
## only where the terrain is built again with every stage. A world that keeps
## its terrain between stages keeps them whole, so the next stage takes them
## down (_clear_stage_marks).
func _marks_fold() -> bool:
	return false

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
## (mid-build). The sky follows the place and the view held there as well (its
## clock stays still), so a held world shows the sky it plays under.
func _on_tree_frame() -> void:
	# A world whose screen has left is out of the tree until it is freed.
	if not is_inside_tree() or not can_process(): return
	_fold_static_scenery_once()
	advance_backdrop(0.0)

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
	_advance_carriers(delta)
	for role in actors:
		if home_view and home_presentation_owner!=0:
			continue
		var actor: SpiritVisual=actors[role]
		if home_view:
			actor.visible=true
		var previous := actor.position
		# Whatever carries the spirit takes it along first; its own walk eases on top.
		var carried := _carry(role,actor)
		var target: Vector3=actor_targets[role]+carried
		actor.travel_target=target
		var ridden := actor.position-previous
		actor.position=actor.position.lerp(target,weight)
		actor.advance_motion(actor.position-previous-ridden,delta,reduced_motion)
	if not (home_view and home_presentation_owner!=0):
		finish_spirit_motion()
	_seed_launch_age+=delta
	_seed_snapshot_age+=delta
	_apply_seed_pose()
	for trail: Node3D in _motion_trails:
		if is_instance_valid(trail): trail.advance(delta, reduced_motion)
	_move_bridge(weight)
	for piece: RefCounted in crossing_pieces.values():
		if piece.moving(): piece.advance(delta)
	for piece: RefCounted in pad_pieces.values():
		if piece.moving(): piece.advance(delta)
	if route_barriers.moving(): route_barriers.advance(delta)
	_advance_garden_bloom(delta)
	_advance_fireflies()
	advance_backdrop(delta)
	_advance_camera(delta)

## Moves the planks `weight` of the way to their pose and reports the
## drawbridge moving while any is still away from it.
func _move_bridge(weight: float) -> void:
	var raised := _bridge_raised()
	var bridge_travel := 0.0
	for i in range(bridge_parts.size()):
		var desired := bridge_plank_y(i, raised)
		bridge_travel = maxf(bridge_travel, absf(desired - bridge_parts[i].position.y))
		bridge_parts[i].position.y=lerpf(bridge_parts[i].position.y,desired,weight)
	note_motion("drawbridge", "drawbridge", (1 if raised else -1) if bridge_travel > MOTION_SETTLED else 0)

## An immediate present puts the bridge in its pose at once: it never moves.
func _settle_bridge() -> void:
	var raised := _bridge_raised()
	for i in range(bridge_parts.size()): bridge_parts[i].position.y = bridge_plank_y(i, raised)
	note_motion("drawbridge", "drawbridge", 0)

func _bridge_raised() -> bool:
	return bridge_ready or (home_bridge_raised and home_view and home_presentation_owner!=0)

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

## The screen's buzz for a big change (Callable(ms, amplitude)): set only by
## a screen playing its own turn, live or with its memory, so a replay never
## buzzes; unset, nothing buzzes.
var big_change_haptic: Callable
## The Haptics setting, which a big change's shake follows like its buzz.
var big_change_shake := true

## A piece of a big change kind (kit/big_change.gd) started to move for
## `seconds`: the view shakes for that long, unless Haptics is off or Reduce
## motion on, and the screen's buzz plays. Call it when the piece's pose
## changes, never on an immediate present (a reset, a retry's first frame or
## a jump), wherever the piece is: off screen too.
func note_big_change(kind: String, seconds: float) -> void:
	if not BigChange.is_big(kind, _chapter_key()): return
	if big_change_shake and not reduced_motion and seconds > 0.0 and is_instance_valid(camera_exploration): camera_exploration.shake(seconds)
	if big_change_haptic.is_valid(): big_change_haptic.call(int(BigChange.HAPTIC.ms), float(BigChange.HAPTIC.amplitude))

## Each frame before the spirits move: whatever can carry a spirit moves
## first. Nothing does here.
func _advance_carriers(_delta: float) -> void:
	pass

## Each frame: moves `actor` (spirit `role`) with whatever carries it, and
## returns how far its carrier has it from its snapshot place. Nothing here.
func _carry(_role: String, _actor: Node3D) -> Vector3:
	return Vector3.ZERO

## A scrolling world eases its follow camera; Home and the older islands ease
## toward their own framing.
func _advance_camera(delta: float) -> void:
	if _uses_scrolling_camera():
		_ease_follow(delta)
		_frame_camera()
		return
	if is_instance_valid(camera) and not (home_view and home_presentation_owner!=0):
		var desired_size := 15.7 if home_view else 14.4
		camera.size=lerpf(camera.size,ViewFit.viewport(desired_size,self),delta*2)
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

## Pieces a turn's sounds come from, by "<kind>:<id>" (Soundscape.source_anchor):
## each world marks them as it builds them (mark_sound).
var sound_anchors: Dictionary = {}
## The live spirit's role and actor key (memory_wait.gd), so a sound caused by
## role "a" or "b" finds its pip in a world that names pips by slot.
var _sound_live_role := ""
var _sound_live_key := ""

func mark_sound(anchor: String, node: Node3D) -> void:
	sound_anchors[anchor] = node

func note_live_spirit(role: String, key: String) -> void:
	_sound_live_role = role
	_sound_live_key = key

## Where a sound is (soundscape placing): a marked piece or a pip
## ("spirit:" and its role or actor key); null when this world has no such
## place, and the sound plays unplaced.
func sound_point(anchor: String) -> Variant:
	var node: Variant = _sound_spirit(anchor.trim_prefix("spirit:")) if anchor.begins_with("spirit:") else sound_anchors.get(anchor)
	if not is_instance_valid(node) or not (node as Node3D).is_inside_tree(): return null
	return (node as Node3D).global_position

func _sound_spirit(key: String) -> Variant:
	if actors.has(key): return actors[key]
	if not key in ["a", "b"] or not actors.has(_sound_live_key): return null
	if key == _sound_live_role: return actors[_sound_live_key]
	for other: Variant in actors:
		if other != _sound_live_key: return actors[other]
	return null

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

# --- What earlier stages left (the checkpoint the shown stage opened from) ---

## The stage this world shows (show_stage), "" before one.
var displayed_stage_id := ""
## The crossings earlier stages left kept, from the checkpoint present_history
## was given.
var _latched_bridge_ids: Array = []

## Shows one stage of the chapter: a staged world builds it, its barriers,
## marks and tags with it. Home and the older islands have none.
func show_stage(_stage: Dictionary) -> void:
	pass

## Supply the checkpoint already verified by the chapter's coordinator (play,
## memories, replays and the level tools all call it before presenting).
## Remembered state is a landmark only: it adds no controls or collision. By
## default it notes the crossings kept; a world that draws more of the past
## (the Lighthouse's mirrors) extends it.
func present_history(checkpoint: Dictionary) -> void:
	_latched_bridge_ids = kept_crossings(checkpoint)

## The crossings a checkpoint keeps: its mechanisms' latched_bridges, or the
## top-level list an island family's checkpoint holds them in.
static func kept_crossings(checkpoint: Dictionary) -> Array:
	var mechanisms: Variant = checkpoint.get("mechanisms")
	if mechanisms is Dictionary and mechanisms.has("latched_bridges"): return Array(mechanisms.latched_bridges).duplicate()
	return Array(checkpoint.get("latched_bridges", [])).duplicate()

# --- The follow camera (the scrolling chapters) ---

## A scrolling world's camera follows the live spirit (or the memory it waits
## for, _camera_slot) at SCROLL_SIZE, and eases out to SCROLL_DONE_SIZE over a
## finished stage. Every scrolling world looks from camera_from(): the same
## yaw everywhere (a level's follow data may only lower the pitch), so the
## stick maps alike in all of them.
const SCROLL_SIZE := 9.2
const SCROLL_DONE_SIZE := 10.6
## How fast the camera closes on the spirit: 1 - e^(-rate t) of the way.
const FOLLOW_RATE := 8.0
var _active_player := "p0"
var _follow_center := Vector3.ZERO
var _follow_size := SCROLL_SIZE
var _completion_view := false

## A level opts into the close follow camera with its dressing's
## "camera": {"follow": {...}} (presentation only; nothing reaches the
## simulation or a recording):
##   size   view height in metres while a stage plays (else SCROLL_SIZE)
##   done   view height over a finished stage (else size * 1.15)
##   axes   "x" (the default, the old strip) or "xz": the plan axes it follows
##   lift   how much of the pip's height the view rises with (0 to 1)
##   inset  [x, z] metres the centre stays inside the floors' ends
##   zoom   [closest, farthest] pinch limits, times size
##   pan    [x, z] how far a drag may push the view, times size
##   from   [x, y, z] where the camera stands from the point it looks at (else
##          ViewFit.CAMERA_FROM): the same yaw, a lower pitch looks up a cliff;
##          stand it far enough back that low fog and tall tiers stay past the
##          orthographic camera's near plane
func _follow_data() -> Dictionary:
	var data: Variant = dressing.get("camera", {})
	return data.get("follow", {}) if data is Dictionary else {}

## Where this world's camera stands from the point it looks at
## (ViewFit.camera_from): what endings, pair tags and label bubbles face.
func camera_from() -> Vector3:
	return ViewFit.camera_from(dressing)

func _scroll_size() -> float:
	return float(_follow_data().get("size", SCROLL_SIZE))

func _scroll_done_size() -> float:
	var data := _follow_data()
	return float(data.get("done", float(data.size) * 1.15)) if data.has("size") else SCROLL_DONE_SIZE

## The pinch and drag limits a level's follow data sets (camera_exploration).
func _apply_follow_limits() -> void:
	var data := _follow_data()
	if data.is_empty() or not is_instance_valid(camera_exploration): return
	var zoom: Array = data.get("zoom", [0.7, 1.6])
	camera_exploration.minimum_zoom = float(zoom[0])
	camera_exploration.maximum_zoom = float(zoom[1])
	var pan: Array = data.get("pan", [0.9, 0.6])
	camera_exploration.maximum_pan = Vector2(float(pan[0]), float(pan[1]))

## Whether this world's camera follows the live spirit (else its own framing).
func _uses_scrolling_camera() -> bool:
	return false

## What the follow camera centres on: the live spirit, or the memory it waits for.
func _focus_point() -> Vector3:
	return actors[_camera_slot(_active_player)].position

## Where the follow camera looks: the focus, kept inside _follow_limits()
## while a stage plays; over a finished stage, between both spirits and the
## garden.
func _camera_center() -> Vector3:
	var target := _focus_point()
	if _completion_view:
		var left := target.x
		var right := target.x
		for actor: Node3D in actors.values():
			left = minf(left, actor.position.x)
			right = maxf(right, actor.position.x)
		if is_instance_valid(garden): right = maxf(right, garden.position.x + 1.0)
		target.x = (left + right) * 0.5
		target.z = 0
	else:
		var limits := _follow_limits()
		target.x = clampf(target.x, limits[0].x, limits[1].x)
		target.z = clampf(target.z, limits[0].y, limits[1].y)
	target.y *= clampf(float(_follow_data().get("lift", 0.0)), 0.0, 1.0)
	return target

## The follow camera's centre stays this far (metres) inside the floors'
## west and east ends while a stage plays.
const FOLLOW_INSET := 4.0

## The lowest and highest centre (x, z in metres) the follow camera takes
## while a stage plays: FOLLOW_INSET inside the floors' west and east ends,
## on the z axis.
func _follow_limits() -> Array[Vector2]:
	return _floors_follow_limits()

## FOLLOW_INSET inside the floors' west and east ends, on the z axis: the
## default limits, also for a world whose family keeps a fixed band but whose
## chapter runs longer (a long journey strip).
func _floors_follow_limits() -> Array[Vector2]:
	var floors := _floors_rect()
	var data := _follow_data()
	if str(data.get("axes", "x")) == "xz":
		var inset: Array = data.get("inset", [3.0, 1.5])
		var low := floors.position + Vector2(float(inset[0]), float(inset[1]))
		var high := floors.end - Vector2(float(inset[0]), float(inset[1]))
		return [low.min(floors.get_center()), high.max(floors.get_center())]
	return [Vector2(floors.position.x + FOLLOW_INSET, 0.0), Vector2(floors.end.x - FOLLOW_INSET, 0.0)]

## The level's floors together (metres, x and z).
func _floors_rect() -> Rect2:
	var found := Rect2()
	for island: Dictionary in current_level.get("islands", []):
		var r: Array = island.rect_cm
		var rect := Rect2(Vector2(float(r[0]), float(r[1])) / 100.0, Vector2(float(r[2] - r[0]), float(r[3] - r[1])) / 100.0)
		found = rect if found.size == Vector2.ZERO else found.merge(rect)
	return found

## The follow camera takes the snapshot's live spirit, and eases out over a
## finished stage; an immediate present puts it there at once.
func _present_follow(state: Dictionary, immediate: bool) -> void:
	_active_player = str(state.get("active_slot", _active_player))
	_completion_view = bool(state.get("complete", false))
	if immediate and _uses_scrolling_camera(): _snap_follow()

## Puts the follow camera on its spirit at once (an immediate present), so a
## kept world and one built again show the same.
func _snap_follow() -> void:
	if actors.has(_active_player): _follow_center = _camera_center()
	_follow_size = _scroll_done_size() if _completion_view else _scroll_size()
	_apply_follow_limits()
	_frame_camera()

## Eases the follow camera toward its spirit, once per rendered frame:
## snapshot delivery and pinch zoom never feed back into it.
func _ease_follow(delta: float, rate: float = FOLLOW_RATE) -> void:
	var weight := 1.0 if reduced_motion else 1.0 - exp(-rate * maxf(delta, 0.0))
	if actors.has(_active_player): _follow_center = _follow_center.lerp(_camera_center(), weight)
	_follow_size = lerpf(_follow_size, _scroll_done_size() if _completion_view else _scroll_size(), weight)

## Frames the view: a scrolling world over its follow point (_frame_follow);
## the others frame themselves.
func _frame_camera() -> void:
	if _uses_scrolling_camera(): _frame_follow()

## The camera over the follow point, at the follow size.
func _frame_follow() -> void:
	if not is_instance_valid(camera): return
	camera.position = _follow_center + camera_from()
	camera.look_at(to_global(_follow_center))
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = ViewFit.viewport(_follow_size, self)
	camera.h_offset = 0
	camera.v_offset = 0.2

# --- The island build: floors, pads and scenery from the definition ---

## The shown stage's route barriers (kit/route_barriers.gd), from its owned
## crossings, stairs, zones and controls: every world keeps them here.
var route_barriers := RouteBarriers.new(self)

## The level's route barrier look (kit/route_barriers.gd): its dressing's
## "barrier" look slot pick (content/dressing/prop_styles.gd), or "" for the
## default.
func _barrier_style() -> String:
	return str(dressing.get("barrier", ""))

## Scenery of the world's own that pair tags, ownership marks and route
## barriers keep clear of (kit/pair_tags.gd, kit/owner_mark.gd,
## kit/floor_spots.gd): the route barriers by default. A world that adds its
## own appends to this.
func _pair_keep_clear() -> Array:
	return route_barriers.discs()

## The floor point a pair tag's control stands on (kit/pair_tags.gd).
func _pair_control_anchor(entity: Dictionary) -> Vector3:
	return _at(entity)

## The shown stage's ownership marks (kit/owner_mark.gd) and pair tags
## (kit/pair_tags.gd, from its control-to-gate wiring): every world keeps
## them here, beside its route barriers.
var owner_marks := OwnerMark.new(self)
var pair_tags := PairTags.new(self)

## Takes down the shown stage's barriers, marks and tags (another is coming).
func _clear_stage_marks() -> void:
	owner_marks.clear()
	pair_tags.clear()
	route_barriers.clear()

## Puts up the shown stage's route barriers, ownership marks and pair tags
## from its plan (services/level_layout.gd), once the world's own scenery
## stands: the barriers, then what the world adds beside them
## (_build_barrier_extras), then the marks and the tags, which keep clear of
## all of it. `tag_view` is the plan the marks and tags read where it differs.
## A stand spot pad already wears its owner's mark (kit/stand_spot.gd); a pad
## either pip holds (open controls) has no owner to mark.
func _build_stage_marks(view: Dictionary, tag_view: Dictionary = {}) -> void:
	route_barriers.build(view)
	_build_barrier_extras()
	var tagged := view if tag_view.is_empty() else tag_view
	for pad: Dictionary in tagged.get("pressure_pads", []):
		var piece: Variant = pad_pieces.get(str(pad.id))
		if piece != null and piece.spot != null and pad.has("owner_slot"): owner_marks.record(str(pad.get("owner_slot", "")), &"spot", str(pad.id), piece.spot.mark.position, piece.spot)
	owner_marks.build(tagged)
	pair_tags.prepare(tagged)

## What a world adds beside its route barriers before the marks are placed
## (cooperative_world's ball rings). Nothing by default.
func _build_barrier_extras() -> void:
	pass

## Shows the snapshot on the stage's pair tags and route barriers, in the
## shared terms they read (_marks_state).
func _present_stage_marks(state: Dictionary) -> void:
	var shared := _marks_state(state)
	pair_tags.present(shared)
	_present_barriers(shared)

## The snapshot in the terms the barriers and tags read: "bridges" (route id
## -> open) and "hold_pads" (pad id -> held). A family whose engine names
## them otherwise adds them here.
func _marks_state(state: Dictionary) -> Dictionary:
	return state

## Shows the snapshot on the route barriers; a new push into one (the
## snapshot's "refused") bumps the spirit back.
func _present_barriers(state: Dictionary) -> void:
	route_barriers.set_reduced_motion(reduced_motion)
	for event: Variant in route_barriers.present(state):
		var slot := str(event.get("slot", "")) if event is Dictionary else ""
		if actors.has(slot): actors[slot].play_bump(reduced_motion)

# Where the marks and tags go (kit/owner_mark.gd, kit/pair_tags.gd ask these).

## The floors a crossing's ends are read against: the level's own.
func _route_islands() -> Array:
	return current_level.get("islands", [])

## A floor's walking height (metres) by its id; 0 for none.
func _surface_height(id: String) -> float:
	for island: Dictionary in _route_islands():
		if island.id == id: return float(island.get("height_cm", 0)) / 100.0
	return 0.0

## The cables and ropes the stage lays on its floors ({rect, y, what} each),
## which ownership marks keep off. None by default.
func floor_cables() -> Array:
	return []

## The dressing's flat floor covers (rugs, and paths of stones or boards) on
## the shown stage, as {rect, y, what} on their floors: pair tags and
## ownership marks never lie on them (kit/floor_spots.gd scenery), the same
## in every world and at every graphics level. Gate posts may stand on them.
func floor_covers() -> Array:
	var found: Array = []
	for spec: Dictionary in Props.expand(DressingCatalog.stage_props(dressing, _dressing_stage_id())):
		var kind := str(spec.get("kind", ""))
		if kind not in Props.FLOOR_COVERS: continue
		found.append({"rect": Props.extent(spec).rect, "y": _surface_height(str(spec.get("surface", ""))) + float(spec.get("y", 0)) / 100.0, "what": "the dressing's " + kind})
	return found

## Whether an owned crossing gets an ownership mark at each end. A world that
## shows its owner some other way says no, so no mark is made only to be freed.
func _marks_route_owner(_definition: Dictionary) -> bool:
	return true

## Whether an owned goal carries its owner's mark; a world whose goal piece
## wears one says so.
func _marks_goal(_goal: Dictionary) -> bool:
	return false

## Where an owned stair's mark wants to sit (kit/owner_mark.gd): before its
## foot, stepping away from it, or past its head when the foot has no room.
func _mark_stair(stair: Dictionary) -> Dictionary:
	var r: Array = stair.rect_cm
	var along_x: bool = stair.axis == "x"
	var entrance := point([r[0], (r[1] + r[3]) * 0.5] if along_x else [(r[0] + r[2]) * 0.5, r[1]]) + Vector3(0, float(stair.from_height_cm) / 100.0, 0)
	var top := point([r[2], (r[1] + r[3]) * 0.5] if along_x else [(r[0] + r[2]) * 0.5, r[3]]) + Vector3(0, float(stair.get("to_height_cm", stair.from_height_cm)) / 100.0, 0)
	var reach := float(OwnerMark.KINDS[&"stair"].reach)
	return {"anchor": entrance, "away": Vector3.LEFT if along_x else Vector3.FORWARD, "kind": &"stair", "head": top + (Vector3.RIGHT if along_x else Vector3.BACK) * reach}

## The floor points a gate's pair tags go by, nearest first: before a
## crossing's west end (its end mark's place) then past its east end; a
## stair's foot then its head.
func _pair_gate_anchors(route: Dictionary) -> Array:
	var r: Array = route.rect_cm
	if route.has("axis"):
		var along_x: bool = str(route.get("axis", "x")) == "x"
		var foot := point([r[0], (r[1] + r[3]) * 0.5] if along_x else [(r[0] + r[2]) * 0.5, r[1]]) + Vector3(-0.24 if along_x else 0.0, float(route.from_height_cm) / 100.0, 0.0 if along_x else -0.24)
		var head := point([r[2], (r[1] + r[3]) * 0.5] if along_x else [(r[0] + r[2]) * 0.5, r[3]]) + Vector3(0.24 if along_x else 0.0, float(route.get("to_height_cm", route.from_height_cm)) / 100.0, 0.0 if along_x else 0.24)
		return [foot, head]
	var height := Vector3(0, float(route.get("height_cm", route.get("from_height_cm", 0))) / 100.0, 0)
	var ends := OwnerMark.route_ends_of(route, _route_islands())
	return [ends[0] + height, ends[1] + height]

## The pad pieces by id (_build_pad), for present() to light.
var pad_pieces: Dictionary = {}
## The crossing pieces by id (_build_crossings), for present() to open.
var crossing_pieces: Dictionary = {}

## What every island world builds from its definition and dressing alone: the
## chapter's dressing, its floors (_build_floors), its pads (_build_pads), its
## scenery (_build_dressing) and its crossings (_build_crossings). A staged
## build gets the frame back between pieces. Await it.
func _build_island_ground(definition: Dictionary) -> void:
	_load_dressing()
	await _build_floors(definition.get("islands", []))
	await _build_pads(_layout_pads())
	await _build_dressing()
	await _build_crossings(definition.get("bridges", []))

## Each crossing of the definition as the bridge kit draws it, shut until
## present() opens it (crossing_pieces); its sounds come from its root, which
## that also holds, so the static fold batches the planks under it.
func _build_crossings(bridges: Array) -> void:
	crossing_pieces.clear()
	for bridge: Dictionary in bridges:
		var piece: RefCounted = BridgeKit.build(bridge, terrain)
		crossing_pieces[str(bridge.id)] = piece
		mark_sound("bridge:%s" % bridge.id, piece.root)
		await _build_step()

## Opens each crossing the snapshot's bridges hold open. One that starts to
## rise or sink is a "crossing" big change (kit/big_change.gd), off unless a
## chapter turns it on.
func _present_crossings(bridges: Dictionary, immediate: bool) -> void:
	for id: String in crossing_pieces:
		var open := bool(bridges.get(id, false))
		if not immediate and open != crossing_pieces[id].is_open(): note_big_change("crossing", BigChange.SECONDS)
		crossing_pieces[id].reduced_motion = reduced_motion
		crossing_pieces[id].set_open(open, immediate)

## The seed an island family throws (seed_visual.gd, glowing warm; its flight
## is _present_seed's) and the ring where it lands (SocketKit.landing), named
## `landing_name`, both under the terrain.
func _build_seed_throw(landing_name: String) -> void:
	seed = SeedVisual.create(self, 0.13, Color("ffda83"), Vector3.ZERO, terrain)
	var glow := seed.material_override as StandardMaterial3D
	glow.emission_enabled = true
	glow.emission = Color("e6b767")
	glow.emission_energy_multiplier = 1.2
	landing_marker = Node3D.new()
	landing_marker.name = landing_name
	terrain.add_child(landing_marker)
	SocketKit.landing(landing_marker)

## Each floor in the dressing's ground style (kit/surfaces.gd), else as this
## world's plain floor (_plain_floor), under its floor root (_floor_root),
## which is kept as its surface when it is not the terrain itself: dressing
## props and pieces on that floor go under it.
func _build_floors(islands: Array) -> void:
	for index in range(islands.size()):
		var island: Dictionary = islands[index]
		var root := _floor_root(island)
		var shared := terrain
		terrain = root
		if not _dressed_ground(island, root): _plain_floor(island, index)
		terrain = shared
		if root != terrain: _surface_nodes[str(island.id)] = root
		await _build_step()

## Builds `island` in the dressing's ground style under `parent`; false, with
## nothing built, when the dressing gives it none.
func _dressed_ground(island: Dictionary, parent: Node3D) -> bool:
	var style := _ground_style(str(island.id))
	if style.is_empty(): return false
	Surfaces.build(island, style, parent)
	return true

## Where a floor is built: a root named for it at its height.
func _floor_root(island: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = str(island.id)
	root.position.y = float(island.get("height_cm", 0)) / 100.0
	terrain.add_child(root)
	return root

## A floor with no ground style: the floating island shell and its scenery,
## each island varied by its place in the list (built in `terrain`, here the
## floor's root).
func _plain_floor(island: Dictionary, index: int) -> void:
	var rect: Array = island.rect_cm
	_make_island(float(rect[0] + rect[2]) / 200.0, float(rect[1] + rect[3]) / 200.0,
		float(rect[2] - rect[0]) / 100.0, float(rect[3] - rect[1]) / 100.0, _plain_floor_colour(), index + 1)

## The grass of a plain floor.
func _plain_floor_colour() -> Color:
	return Color("a4c9aa")

## The pads as this world's family lays them out (services/level_layout.gd),
## each with its floor and the pip whose part it is.
func _layout_pads() -> Array:
	var stages := LevelLayout.stage_ids(current_level)
	if stages.is_empty(): return []
	return LevelLayout.for_key(_chapter_key(), str(stages[0]), current_level).get("pressure_pads", [])

func _build_pads(pads: Array) -> void:
	for pad: Dictionary in pads:
		pad_pieces[str(pad.id)] = _build_pad(pad, _floor_point(pad.position_cm, str(pad.get("surface_id", ""))))
	await _build_step()

## A pad in its style (piece_styles.gd "pad", kit/pieces/pad.gd) in its pip's colour.
func _build_pad(pad: Dictionary, at: Vector3) -> Variant:
	var style := PieceStyles.style("pad", str(pad.id), ChapterIndex.data(_chapter_key()), dressing)
	return PadKit.build(style, at, float(pad.radius_cm) / 100.0, terrain, {"owner": str(pad.get("owner_slot", "")), "id": str(pad.id)})

## A placed thing's spot on its floor (its walking height), in metres.
func _at(value: Dictionary) -> Vector3:
	return _floor_point(value.position_cm, str(value.get("surface_id", "")))

## A spot on a floor of the level (its walking height), in metres.
func _floor_point(position_cm: Array, surface: String) -> Vector3:
	for island: Dictionary in current_level.get("islands", []):
		if island.id == surface:
			return Vector3(float(position_cm[0]) / 100.0, float(island.get("height_cm", 0)) / 100.0, float(position_cm[1]) / 100.0)
	return point(position_cm)

# --- Dressing: one host for every world (content/dressing) ---

## The registry key this world's dressing is filed under; "" has none.
func _chapter_key() -> String:
	return ""

## Reads the chapter's dressing and its light; call at the start of a build.
func _load_dressing() -> void:
	dressing = DressingCatalog.for_key(_chapter_key())
	if dressing.has("look"): relight(str(dressing.look))
	_surface_nodes.clear()
	_fireflies.clear()

func _dressing_stage_id() -> String:
	return str(current_level.get("stage_id", ""))

## Height of a surface whose props have no surface root of their own.
func _surface_base(_surface_id: String) -> float:
	return 0.0

## The ground style for an island from the dressing; "" keeps the plain shore.
func _ground_style(island_id: String) -> String:
	var ground: Dictionary = dressing.get("ground", {})
	var style := str(ground.get(island_id, ground.get("*", "")))
	return style if Surfaces.has_style(style) else ""

## Props from the dressing data: visual only, never collision or state. A
## staged build gets the frame back between props. Await it.
func _build_dressing() -> void:
	var specs := Props.expand(DressingCatalog.stage_props(dressing, _dressing_stage_id()))
	var lit := bool(dressing.get("lit", true))
	# Lamp light on the ground draws where this world's look says (under a fog cover).
	var glow_order: Variant = Look.preset(str(dressing.get("look", ""))).get("glow_order")
	var anchors: Array[Vector3] = []
	for spec: Dictionary in specs:
		await _build_step()
		if glow_order != null:
			spec = spec.duplicate()
			spec["glow_order"] = glow_order
		if not GraphicsPolicy.detail_dressing(_motion_quality) and bool(spec.get("detail", false)): continue
		if _takes_prop(spec): continue
		var surface := str(spec.get("surface", ""))
		var parent: Node3D = _surface_nodes.get(surface, terrain)
		var base := 0.0 if _surface_nodes.has(surface) else _surface_base(surface)
		var prop := Props.build(spec, parent, base, lit)
		if prop == null: continue
		prop.set_meta("dressing", true)
		if str(spec.kind) in ["tree", "bush", "hedge", "flowers", "fern", "planter", "lantern", "lamp_post"]:
			anchors.append(parent.position + prop.position)
		_dressed_prop(prop)
	_build_fireflies(int(dressing.get("fireflies", 0)), anchors)

## Small warm lights drifting near the planting. GraphicsPolicy.fireflies hides
## them on Low.
func _build_fireflies(count: int, anchors: Array[Vector3]) -> void:
	if count <= 0 or anchors.is_empty(): return
	var root := Node3D.new()
	root.name = "Fireflies"
	terrain.add_child(root)
	var glow := Primitives.shared_material(FIREFLY, 0.9, FIREFLY, 2.2)
	for index in range(count):
		var anchor: Vector3 = anchors[(index * 7) % anchors.size()]
		var at := anchor + Vector3(sin(index * 2.3) * 0.5, 0.45 + 0.25 * float(index % 3), cos(index * 1.7) * 0.35)
		var fly := Primitives.mesh_node(Primitives.shared_mesh("sphere", 0.028), glow, at, root)
		fly.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		fly.set_meta("rest", at)
		fly.visible = GraphicsPolicy.fireflies(_motion_quality)
		_fireflies.append(fly)

## Moves the space backdrop on by delta seconds of the world's time (none
## under Reduce motion) and shifts it with the camera on screen. An ending
## (ending_player.gd) calls it while the world's own frame is paused.
func advance_backdrop(delta: float) -> void:
	if not reduced_motion: _backdrop_clock += delta
	var definition: Variant = get("chapter_definition")
	if _backdrop_from.size() != 3 or _backdrop_from[0] != home_presentation_owner or not is_same(_backdrop_from[1], current_level) or not is_same(_backdrop_from[2], definition):
		_backdrop_from = [home_presentation_owner, current_level, definition]
		SpaceBackdrop.set_layout(environment, backdrop_layout_key())
	SpaceBackdrop.advance(environment, _backdrop_clock, camera, get_viewport() if is_inside_tree() else null, reduced_motion)

## Which far islands and wisps this world shows (SpaceBackdrop.layout_seed):
## Home's own while Home holds the world, else the chapter's, the same on every
## visit.
func backdrop_layout_key() -> String:
	var key := _chapter_key()
	return SpaceBackdrop.HOME if home_presentation_owner != 0 or key.is_empty() else key

func _advance_fireflies() -> void:
	if reduced_motion: return
	for index in range(_fireflies.size()):
		var fly := _fireflies[index]
		if not is_instance_valid(fly): continue
		var rest: Vector3 = fly.get_meta("rest")
		var phase := time * 0.7 + float(index) * 1.9
		fly.position = rest + Vector3(sin(phase) * 0.18, sin(phase * 1.3) * 0.08, cos(phase * 0.8) * 0.12)

## Where the dressing prop whose "anchor" is `anchor_name` stands (its foot,
## in the world's space): an ending scene's origin (services/ending_scene.gd).
## null when the shown stage's dressing names none.
func ending_anchor(anchor_name: String) -> Variant:
	for spec: Dictionary in DressingCatalog.stage_props(dressing, _dressing_stage_id()):
		if str(spec.get("anchor", "")) != anchor_name or not spec.has("at"): continue
		var surface := str(spec.get("surface", ""))
		var base := (_surface_nodes[surface] as Node3D).position.y if _surface_nodes.has(surface) else _surface_base(surface)
		var at := Vector3(float(spec.at[0]) / 100.0, base + float(spec.get("y", 0)) / 100.0, float(spec.at[1]) / 100.0)
		return to_local(terrain.to_global(at))
	return null

## A built dressing prop, for a world that wakes a part of it later.
func _dressed_prop(_prop: Node3D) -> void:
	pass

## Whether this world builds dressing prop `spec` its own way instead (a water
## world floats a boat that stands over water); false builds it as a prop.
func _takes_prop(_spec: Dictionary) -> bool:
	return false
