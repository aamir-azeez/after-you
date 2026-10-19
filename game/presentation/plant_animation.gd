extends Node3D
## A short planting beat, presentation only. When a presented snapshot turns the
## seed from carried into "planted", the view eases in on the planter while the
## white fruit, still above the spirit's head, swells and splits open; a small
## brown seed pops out and arcs down into the planter soil with a little puff;
## the garden's bloom starts just after it lands, and the view eases back.
## The real seed and the world's camera are never written: the beat draws its
## own copy of the fruit and looks through its own camera, all under one
## controller that frees itself after DURATION. Simulation, recordings and
## sound never see it.
##
## Optional and self-contained: set ENABLED to false to switch it off, or delete
## this file and its one call in island_world.gd _present_seed.
const ENABLED := true
const SCRIPT_PATH := "res://presentation/plant_animation.gd"
const SeedVisual = preload("res://presentation/seed_visual.gd")
const SpiritVisual = preload("res://presentation/spirit_visual.gd")
const Primitives = preload("res://presentation/kit/primitives.gd")
const NODE_NAME := "PlantAnimation"

## Timeline in seconds. Chapter screens hold the finished world for 3 s before
## their review card, so the whole beat, easing back included, fits inside it.
const ZOOM_IN := 0.45
const SWELL := 0.30
const SPLIT := 0.42
const LAND := 0.80
const SINK := 0.95
const PUFF_END := 1.20
## The bloom waits for the landing plus a short beat.
const BLOOM_START := 1.02
const ZOOM_OUT := 2.25
const DURATION := 2.95
## The eased-in view is this fraction of the chapter view, centred this high
## above the planter so the head and the bloom both stay in frame.
const ZOOM := 0.4
const FOCUS_HEIGHT := 0.6

const SEED_BROWN := Color("7a4b2b")
const SEED_TIP := Color("5e3820")
const PUFF := Color("b39a76")
const SPARK := Color("ffe2a0")
## Sizes for a fruit of vertical half extent 0.13 (every world's carried seed).
const REFERENCE := 0.13
const SEED_RADIUS := 0.052
const LIFT := 0.06
## How far past the soil's front edge, toward the camera, the seed's arc swings
## so it falls in front of the spirit's face rather than through it.
const ARC_OUT := 0.5
const ARC_UP := 0.32
## A carrier this close to the planter (in the snapshot) is planting it.
const CARRY_REACH := 1.6
const PUFF_BITS := 6
const SPARKS := 3

var _world: Node3D
var _carrier: Node3D
var _elapsed := 0.0
var _unit := 1.0
var _offset := Vector3.ZERO
var _start := Vector3.ZERO
var _land := Vector3.ZERO
var _toward := Vector3.BACK
var _arc_out := Vector3.ZERO
var _focus := Vector3.ZERO
var _fruit: Node3D
var _body: MeshInstance3D
var _glow: MeshInstance3D
var _halves: Array[Node3D] = []
var _half_materials: Array[StandardMaterial3D] = []
var _seed: Node3D
var _puff: Array[MeshInstance3D] = []
var _sparks: Array[MeshInstance3D] = []
var _camera: Camera3D
var _bloom_released := false
var _finished := false

## The one entry point. Starts the beat on a real transition to planted, and
## clears any running beat on an immediate present or any other status.
## Called before the world forgets who carried the seed.
static func on_seed(world: Node3D, seed: Node3D, was: String, value: Dictionary, target: Vector3, immediate: bool) -> void:
	var host: Node3D = world.get("terrain")
	if not is_instance_valid(host): return
	var status := str(value.get("status", ""))
	if immediate or status != "planted":
		cancel(host)
		return
	if was == "planted" or was.is_empty(): return
	cancel(host)
	if not ENABLED or bool(world.get("reduced_motion")) or not is_instance_valid(seed) or not seed is MeshInstance3D: return
	# A real planting carries the fruit to the planter. A jump to planted from a
	# seed held anywhere else (a seek or rewind) shows the end state directly.
	var actors: Dictionary = world.get("actors") if world.get("actors") is Dictionary else {}
	var holder := str(world.get("_seed_holder"))
	var carrier: Node3D = actors.get(holder, null)
	if carrier == null: return
	var targets: Dictionary = world.get("actor_targets") if world.get("actor_targets") is Dictionary else {}
	var carried_at: Vector3 = targets.get(holder, carrier.position)
	if Vector2(carried_at.x - target.x, carried_at.z - target.z).length() > CARRY_REACH: return
	var anim: Node3D = load(SCRIPT_PATH).new()
	anim.name = NODE_NAME
	# After the world and its camera exploration (100) each frame, so the view
	# and the held bloom are composed last, before the frame is drawn.
	anim.process_priority = 200
	host.add_child(anim)
	anim.call("_begin", world, seed as MeshInstance3D, carrier, soil(world, host, value, target))

## Every running beat under `host`, oldest first.
static func running(host: Node) -> Array[Node]:
	var found: Array[Node] = []
	if not is_instance_valid(host): return found
	for child: Node in host.get_children():
		var script: Script = child.get_script()
		if script != null and script.resource_path == SCRIPT_PATH and not child.is_queued_for_deletion(): found.append(child)
	return found

static func cancel(host: Node) -> void:
	for anim: Node in running(host):
		host.remove_child(anim)
		anim.queue_free()

## Where the seed goes in: the soil's centre (global, at its top) and radius.
## The planter is the planted socket by id (First Steps, Relay), else the
## world's garden (the Earlier Islands), else a planter's depth below the pose.
static func soil(world: Node3D, host: Node3D, value: Dictionary, target: Vector3) -> Dictionary:
	var planter: Node3D = null
	var socket_id := str(value.get("socket_id", ""))
	if not socket_id.is_empty(): planter = host.get_node_or_null(NodePath(socket_id)) as Node3D
	if planter == null: planter = world.get("garden") as Node3D
	var top := -INF
	var radius := 0.3
	if is_instance_valid(planter) and Vector2(planter.global_position.x - target.x, planter.global_position.z - target.z).length() < 0.8:
		for child: Node in planter.get_children():
			var part := child as MeshInstance3D
			if part == null or not part.mesh is CylinderMesh: continue
			var shape := part.mesh as CylinderMesh
			var part_top := part.global_position.y + shape.height * 0.5
			if shape.bottom_radius >= 0.28 and part_top > top:
				top = part_top
				radius = shape.top_radius
	return {"center": Vector3(target.x, top if top > -INF else target.y - 0.34, target.z), "radius": radius}

func _begin(world: Node3D, seed: MeshInstance3D, carrier: Node3D, ground: Dictionary) -> void:
	_world = world
	_carrier = carrier
	var shape := seed.mesh as SphereMesh
	var half_height := shape.height * 0.5 if shape != null else REFERENCE
	var half_width := shape.radius if shape != null else REFERENCE
	_unit = half_height / REFERENCE
	var source := world.get("camera") as Camera3D
	var toward := Vector3(source.global_basis.z.x, 0, source.global_basis.z.z) if is_instance_valid(source) else Vector3.BACK
	_toward = toward.normalized() if toward.length() > 0.001 else Vector3.BACK
	var yaw := atan2(_toward.x, _toward.z)
	var center: Vector3 = ground.center
	var land_distance := float(ground.radius) * 0.85
	_land = to_local(center + _toward * land_distance + Vector3(0, SEED_RADIUS * _unit * 0.5, 0))
	_arc_out = to_local(center + _toward * (land_distance + ARC_OUT * _unit))
	_focus = to_local(center + Vector3(0, FOCUS_HEIGHT, 0))
	# The fruit stays where it was carried, following the spirit as it celebrates.
	_start = to_local(seed.global_position)
	if is_instance_valid(_carrier): _offset = _start - _carried()
	_fruit = Node3D.new()
	_fruit.name = "PlantFruit"
	add_child(_fruit)
	_fruit.global_basis = seed.global_basis
	var tint := seed.material_override as StandardMaterial3D
	_body = SeedVisual.create(world, half_height, tint.albedo_color, Vector3.ZERO, _fruit)
	_body.name = "PlantFruitBody"
	_body.remove_meta(SeedVisual.META)
	_body.material_override = tint.duplicate()
	_glow = _body.get_node_or_null("SeedGlow") as MeshInstance3D
	var source_glow := seed.get_node_or_null("SeedGlow") as MeshInstance3D
	if _glow != null and source_glow != null:
		(_glow.material_override as StandardMaterial3D).albedo_color = (source_glow.material_override as StandardMaterial3D).albedo_color
	# Two halves split across the view, left and right; the stem and leaf ride
	# away on the left one.
	var split := Node3D.new()
	split.name = "PlantSplit"
	_fruit.add_child(split)
	split.global_basis = Basis(Vector3.UP, yaw)
	for side: int in [-1, 1]:
		var pivot := Node3D.new()
		pivot.name = "PlantHalfL" if side < 0 else "PlantHalfR"
		pivot.position = Vector3(0, -half_height, 0)
		pivot.visible = false
		split.add_child(pivot)
		var dome := SphereMesh.new()
		dome.is_hemisphere = true
		dome.radius = half_height
		dome.height = half_width
		dome.radial_segments = 16
		dome.rings = 4
		var half: MeshInstance3D = world.mesh_node(dome, tint.albedo_color, Vector3(0, half_height, 0), pivot)
		half.rotation.z = -side * PI * 0.5
		var mat := tint.duplicate() as StandardMaterial3D
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		half.material_override = mat
		_half_materials.append(mat)
		_halves.append(pivot)
	_seed = Node3D.new()
	_seed.name = "PlantSeed"
	_seed.visible = false
	add_child(_seed)
	var r := SEED_RADIUS * _unit
	world.sphere(r, SEED_BROWN, Vector3.ZERO, _seed).name = "PlantSeedBody"
	var tip: MeshInstance3D = world.cylinder(r * 0.9, r * 1.8, SEED_TIP, Vector3(0, r * 1.1, 0), _seed)
	tip.name = "PlantSeedTip"
	# A cone of its own, not the shared cylinder the world's helper gives.
	tip.mesh = Primitives.cylinder_mesh(r * 0.9, r * 1.8, 0.0, 12)
	for i in range(PUFF_BITS):
		var bit: MeshInstance3D = world.sphere(0.034 * _unit, PUFF, Vector3.ZERO, self)
		bit.name = "PlantPuff%d" % i
		bit.visible = false
		bit.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_puff.append(bit)
	for i in range(SPARKS):
		var spark: MeshInstance3D = world.sphere(0.028 * _unit, SPARK, Vector3.ZERO, self)
		spark.name = "PlantSpark%d" % i
		spark.visible = false
		spark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		Primitives.own_material(spark).shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_sparks.append(spark)
	# The bloom is held from this very present: marking it bloomed now keeps the
	# world's garden presentation (which runs next) from restarting it at zero.
	# A state that is not a finished garden clears both again, as before.
	if "garden_bloom_age" in world and "bloomed" in world and is_instance_valid(world.get("garden")) and is_instance_valid(world.get("garden_activation")):
		world.set("bloomed", true)
		world.set("garden_bloom_age", -BLOOM_START)
	# The view eases in only when the world's own camera is the one on screen
	# and this is not Home; the world's camera itself is never moved.
	if is_instance_valid(source) and source.current and not bool(world.get("home_view")):
		_camera = Camera3D.new()
		_camera.name = "PlantCamera"
		add_child(_camera)
		_camera.tree_exiting.connect(_hand_back)
		_follow_camera()
		_camera.make_current()
	_pose()

func _process(delta: float) -> void:
	# The beat keeps the world's clock: a backgrounded or paused world holds it too.
	if is_instance_valid(_world) and not _world.is_processing(): return
	advance(delta)

## Moves the beat on by `delta` seconds; frees it at the end or under reduced motion.
func advance(delta: float) -> void:
	if _finished: return
	if not is_instance_valid(_world) or bool(_world.get("reduced_motion")):
		_finish()
		return
	_elapsed += delta
	if _elapsed >= DURATION:
		_finish()
		return
	_hold_bloom()
	_pose()
	_follow_camera()

func elapsed() -> float:
	return _elapsed

## The world's camera, or null if the beat is not easing the view.
func view_camera() -> Camera3D:
	return _camera

func _finish() -> void:
	_finished = true
	_hand_back()
	visible = false
	set_process(false)
	queue_free()

## Gives the screen back to the world's camera, if this beat still holds it.
func _hand_back() -> void:
	if not is_instance_valid(_camera) or not _camera.current: return
	var source := _world.get("camera") as Camera3D if is_instance_valid(_world) else null
	if is_instance_valid(source) and source.is_inside_tree(): source.make_current()
	else: _camera.clear_current(false)

## Until just after the landing the bloom stays closed, on the beat's clock;
## from then on the world grows it as usual.
func _hold_bloom() -> void:
	if _bloom_released or not bool(_world.get("bloomed")) or not ("garden_bloom_age" in _world): return
	var age := _elapsed - BLOOM_START
	if age >= 0.0:
		_bloom_released = true
		if float(_world.get("garden_bloom_age")) >= age: return
	_world.set("garden_bloom_age", age)
	_world.call("_advance_garden_bloom", 0.0)

func _carried() -> Vector3:
	var actor := _carrier as SpiritVisual if _carrier != null else null
	if actor == null: return _start
	return to_local(actor.get_parent().to_global(actor.position + actor.carry_anchor_position()))

## The world camera's current view, eased toward the planter for the middle of the beat.
func _follow_camera() -> void:
	if not is_instance_valid(_camera): return
	var source := _world.get("camera") as Camera3D
	if not is_instance_valid(source): return
	_camera.global_transform = source.global_transform
	for property: String in ["projection", "size", "fov", "near", "far", "keep_aspect", "cull_mask", "environment", "attributes", "h_offset", "v_offset", "frustum_offset", "compositor", "doppler_tracking"]:
		_camera.set(property, source.get(property))
	var zoom := smoothstep(0.0, ZOOM_IN, _elapsed) * (1.0 - smoothstep(ZOOM_OUT, DURATION, _elapsed))
	if zoom <= 0.0: return
	var focus := to_global(_focus)
	var forward := -_camera.global_basis.z
	var reach := focus - _camera.global_position
	var lateral := reach - forward * reach.dot(forward)
	_camera.global_position += lateral * zoom
	_camera.h_offset = lerpf(source.h_offset, 0.0, zoom)
	_camera.v_offset = lerpf(source.v_offset, 0.0, zoom)
	if _camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		_camera.size = source.size * lerpf(1.0, ZOOM, zoom)
	else:
		_camera.global_position += forward * reach.dot(forward) * (1.0 - ZOOM) * zoom

static func _ease_out(value: float) -> float:
	var v := clampf(value, 0.0, 1.0)
	return 1.0 - pow(1.0 - v, 3.0)

static func _phase(t: float, from: float, to: float) -> float:
	return clampf((t - from) / (to - from), 0.0, 1.0)

func _pose() -> void:
	var t := _elapsed
	# 1. Above the head: the fruit rises a touch, wobbles, then swells.
	var lift := _ease_out(t / SWELL)
	var held := (_carried() + _offset if is_instance_valid(_carrier) else _start) + Vector3(0, LIFT * _unit * lift, 0)
	_fruit.position = held
	var swell := _phase(t, SWELL, SPLIT)
	var wobble := sin(t * 26.0) * 0.12 * _phase(t, 0.12, SWELL) * (1.0 - swell)
	_fruit.rotation.z = wobble
	_fruit.scale = Vector3(1.0 + 0.14 * swell, 1.0 + 0.06 * swell, 1.0 + 0.14 * swell)
	# 2. It splits: two halves tip outward, then shrink and fade.
	var split := t >= SPLIT
	_body.visible = not split
	var opened := _ease_out(_phase(t, SPLIT, SPLIT + 0.26))
	var gone := _phase(t, SPLIT + 0.16, SPLIT + 0.46)
	for i in range(_halves.size()):
		var side := -1.0 if i == 0 else 1.0
		var pivot := _halves[i]
		pivot.visible = split and gone < 1.0
		pivot.rotation.z = -side * 1.25 * opened
		pivot.position.x = side * 0.04 * _unit * opened
		pivot.scale = Vector3.ONE * maxf(0.001, 1.0 - gone)
		_half_materials[i].albedo_color.a = 1.0 - gone
	if split and _glow != null and _glow.get_parent() == _body:
		_glow.reparent(_fruit, true)
		for name: String in ["SeedStem", "SeedLeaf0"]:
			var part := _body.get_node_or_null(name) as Node3D
			if part != null: part.reparent(_halves[0].get_child(0), true)
	if _glow != null:
		var glow_mat := _glow.material_override as StandardMaterial3D
		glow_mat.albedo_color.a = SeedVisual.GLOW_ALPHA * (1.0 - _phase(t, SPLIT, SPLIT + 0.2))
	# 3. The small seed pops up out of the fruit and arcs down into the soil,
	#    swinging out in front of the spirit on the way.
	var r := SEED_RADIUS * _unit
	_seed.visible = t >= SPLIT and t < SINK
	if t < LAND:
		var u := _phase(t, SPLIT, LAND)
		var control := Vector3(_arc_out.x, held.y + ARC_UP * _unit, _arc_out.z)
		_seed.position = held.lerp(control, u).lerp(control.lerp(_land, u), u)
		_seed.scale = Vector3.ONE * lerpf(0.4, 1.0, _ease_out(u / 0.25))
		_seed.rotation.z = sin(u * PI) * 0.7
	else:
		var sink := _phase(t, LAND, SINK)
		_seed.position = _land - Vector3(0, r * 2.4 * sink, 0)
		_seed.scale = Vector3.ONE * (1.0 - 0.4 * sink)
		_seed.rotation.z = 0.0
	# 4. A tiny soil puff and a few sparks where it went in.
	var puff := _phase(t, LAND, PUFF_END)
	var landed := t >= LAND
	for i in range(_puff.size()):
		var bit := _puff[i]
		var angle := float(i) * TAU / float(_puff.size()) + 0.4
		var out := (0.05 + 0.18 * _ease_out(puff)) * _unit
		bit.visible = landed and puff < 1.0
		bit.position = _land + Vector3(cos(angle) * out, (0.01 + 0.08 * sin(puff * PI)) * _unit, sin(angle) * out)
		bit.scale = Vector3.ONE * maxf(0.001, (1.0 - puff) * (0.8 + 0.3 * float(i % 2)))
	for i in range(_sparks.size()):
		var spark := _sparks[i]
		spark.visible = landed and puff < 1.0
		spark.position = _land + Vector3((float(i) - 1.0) * 0.1 * _unit, (0.08 + 0.34 * _ease_out(puff) + 0.05 * float(i % 2)) * _unit, 0)
		spark.scale = Vector3.ONE * maxf(0.001, sin(puff * PI))
