extends "res://presentation/journey_world.gd"
## The Wishing Well @2 on the journey world: @1's cliff, well, rope bucket,
## folding stairs, rope ladder, rope-walks and winch house
## (presentation/wishing_well_scenery.gd, shared with @1's world), fitted to
## @2's shorter level, with the journey world's own items, throws, swings and
## gate links. Everything here is presentation; movement and gates come from
## the snapshot.
const Scenery = preload("res://presentation/wishing_well_scenery.gd")
const BUCKET_RAISE := Scenery.BUCKET_RAISE
var well := Scenery.new(self)
## What the well's rig moves, named here so the scenery fold keeps it
## (kit/static_batch.gd reads a world's script variables).
var _well_held: Array:
	get: return well.held()

## A folding stair's mark sits before its foot; the rope ladder's past its roll.
func _mark_stair(stair: Dictionary) -> Dictionary:
	return well.stair_mark(stair, super._mark_stair(stair))

## Marks keep clear of the notch rim and its hatch, which lie at their height.
func _init() -> void:
	well.keep_clear()

func _ready() -> void:
	super._ready()
	# Dusk instead of the Lighthouse night: warmer sky, ambient and sun.
	relight("dusk")

## Low keeps the lanterns glowing but leaves out the light they cast.
func apply_graphics_quality(quality: String) -> void:
	super.apply_graphics_quality(quality)
	well.apply_graphics_quality(quality)

func show_stage(stage: Dictionary) -> void:
	if str(stage.get("id", "")) == displayed_stage_id: return
	well.reset(stage)
	await super.show_stage(stage)
	await well.build(stage)

func _has_completion_garden(stage_id: String) -> bool:
	return well.has_completion_garden(stage_id)

func _completion_garden_position(goal: Dictionary) -> Vector3:
	return well.completion_garden_position(goal)

func _completion_garden_scale() -> float:
	return 0.5

## The well is an open notch in the cliff, so nothing ever covers the pit and the
## waiting friend stays in view. The garden is never beneath the cliff either.
func _uses_lower_cutaway() -> bool: return false

func _camera_center() -> Vector3:
	return well.camera_center(super._camera_center())

func _shore(island: Dictionary, color: Color) -> void:
	if not well.shore(island): super._shore(island, well.shore_color(island, color))

func _build_physical_pad(pad: Dictionary, heavy: bool) -> void:
	if Scenery.is_bucket_pad(pad): well.build_bucket(pad)
	else: super._build_physical_pad(pad, heavy)

## Where this world draws a spirit standing that the chapter does not list:
## a rider stands in the bucket (wishing_well_scenery.gd).
func spirit_supports() -> Array:
	return well.spirit_supports()

func _build_obstacle(obstacle: Dictionary) -> void:
	if not well.build_obstacle(obstacle): super._build_obstacle(obstacle)

## The rope-walks hang at the cliff height with posts and hand ropes; the
## garden plank keeps the world's own deck.
func _build_bridge(definition: Dictionary) -> void:
	var before := terrain.get_child_count()
	super._build_bridge(definition)
	well.dress_bridge(definition, before, true)

func _build_stair(stair: Dictionary) -> void:
	well.build_stair(stair)

## The rope-walks and the rope ladder draw their own rungs and hand ropes
## (wishing_well_scenery.gd), so no journey rungs lie across them.
func _ladder_rungs(_route: Dictionary) -> void:
	pass

func present(state: Dictionary, immediate: bool = false) -> void:
	super.present(state, immediate)
	well.present(state, immediate)

func _advance_camera(delta: float) -> void:
	well.advance(delta)
	super._advance_camera(delta)
