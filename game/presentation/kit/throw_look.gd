extends RefCounted
## World kit: THE look of anything thrown (First Steps' seed, a carried item
## of any style: kit/pieces/carried_item.gd), the one First Steps @1 was
## tuned with. It eases off the thrower's head onto the recorded arc, flies
## one recorded tick behind the simulation (interpolated, never predicted, so
## every catch stays the simulation's), tumbles forward around a tilted axis
## by the distance it has flown, and leaves the shared path blur behind it
## (seed_motion_trail.gd, tuned by motion_blur_profile.gd and the graphics
## quality's motion blur). A catch or a landing stops all of it at once.
##
## The pose is a function of the snapshots and the world's clock alone, so a
## live throw, a memory's, a replay and carry-over playback draw the same.
## Under Reduce motion it neither eases, tumbles nor blurs.
##
## The world builds one per thrown thing (island_world.gd throw_look), which
## also keeps its blur with the world's other blurs. present() takes each
## snapshot; advance() each frame ages it and, in flight, poses the body: its
## middle on the arc, turned about that middle.
const SeedMotionTrail = preload("res://presentation/seed_motion_trail.gd")
const Runtime = preload("res://core/physical/runtime.gd")
## The simulation's tick: a flight is drawn this far behind its newest snapshot.
const SNAPSHOT_INTERVAL := 1.0 / Runtime.TICK_RATE
## Seconds to ease from where the thrower's head held it onto the arc.
const LAUNCH_EASE := 0.16
## Tumble per metre flown, and how far its axis tips toward the sky.
const SPIN_PER_METRE := 2.6
const SPIN_TILT := 0.42
## A glowing halo (seed_visual.gd) is a billboard: it stays unturned.
const GLOW := "SeedGlow"

## The path blur behind it.
var trail: Node3D
var flying := false
var _body: Node3D
var _middle := Vector3.ZERO
var _glows: Array[Node] = []
var _previous := Vector3.ZERO
var _snapshot := Vector3.ZERO
var _snapshot_age := 0.0
var _launch_offset := Vector3.ZERO
var _launch_age := 1.0
var _launch_point := Vector3.ZERO
var _spin_axis := Vector3.ZERO

## `body` thrown, its `middle` (its own space) on the arc and turned about,
## blurred as wide as `radius`. Its blur follows that middle.
func _init(world: Node3D, body: Node3D, radius: float, middle: Vector3 = Vector3.ZERO) -> void:
	_body = body
	_middle = middle
	_glows = body.find_children(GLOW, "", true, false)
	var followed := body
	if not middle.is_zero_approx():
		followed = Node3D.new()
		followed.name = "ThrowMiddle"
		followed.position = middle
		body.add_child(followed)
	trail = SeedMotionTrail.new()
	trail.configure(world, followed, radius)

func reset() -> void:
	trail.reset()
	flying = false
	_launch_offset = Vector3.ZERO
	_launch_age = 1.0
	_snapshot_age = 0.0
	_spin_axis = Vector3.ZERO

## One snapshot: in flight its middle is at `target` (the body's parent's
## space), else it is not thrown now. A throw that starts from a head eases
## off `thrown_from` (where its middle was drawn). `shown` false keeps the
## blur off; `tint` colours it.
func present(is_flying: bool, target: Vector3, shown: bool, tint: Color, immediate: bool, thrown_from: Variant = null) -> void:
	if immediate: reset()
	elif is_flying and not flying and thrown_from is Vector3:
		_launch_offset = thrown_from - target
		_launch_age = 0.0
	if is_flying and (immediate or not flying):
		_launch_point = target
		_spin_axis = Vector3.ZERO
	if immediate or not is_flying or not flying:
		_previous = target
		_snapshot_age = SNAPSHOT_INTERVAL
	elif not target.is_equal_approx(_snapshot):
		# Interpolate one recorded tick behind. Do not predict or alter catches.
		_previous = _snapshot
		_snapshot_age = 0.0
	flying = is_flying
	_snapshot = target
	trail.tint = tint
	trail.set_motion_allowed(is_flying and shown, immediate)

## Where the newest snapshot has its middle.
func at() -> Vector3:
	return _snapshot

## A frame on the world's clock; in flight it poses the body.
func advance(delta: float, reduced_motion: bool) -> void:
	_launch_age += delta
	_snapshot_age += delta
	pose(reduced_motion)

## In flight, the body on its arc and tumbling; false (untouched) otherwise.
func pose(reduced_motion: bool) -> bool:
	if not flying: return false
	var launch_blend := maxf(0.0, 1.0 - _launch_age / LAUNCH_EASE) if not reduced_motion else 0.0
	var flight := _previous.lerp(_snapshot, clampf(_snapshot_age / SNAPSHOT_INTERVAL, 0.0, 1.0))
	var rotation := Quaternion.IDENTITY if reduced_motion else _spin(flight)
	_body.position = flight + _launch_offset * launch_blend - rotation * _middle
	turn(rotation)
	return true

## The tumble for the middle at `flight`: its axis locked once per throw,
## across the flight and tipped toward the sky; upright until it has moved.
func _spin(flight: Vector3) -> Quaternion:
	var travel := flight - _launch_point
	if _spin_axis.is_zero_approx():
		var level := Vector3(travel.x, 0.0, travel.z)
		if level.length() < 0.02: return Quaternion.IDENTITY
		var side := Vector3.UP.cross(level.normalized())
		_spin_axis = (side * cos(SPIN_TILT) + Vector3.UP * sin(SPIN_TILT)).normalized()
	return Quaternion(_spin_axis, travel.length() * SPIN_PER_METRE)

## The body turned by `rotation`, its halo kept unturned.
func turn(rotation: Quaternion) -> void:
	if _body.quaternion.is_equal_approx(rotation): return
	_body.quaternion = rotation
	for glow: Node in _glows: (glow as Node3D).quaternion = rotation.inverse()
