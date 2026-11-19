extends SceneTree
## kit/motion.gd and the pip moves made with it.
## - Every ease starts at 0 and ends at 1; back runs past the end, bounce
##   never does. settle starts at its amount and dies away; kick rises and
##   falls back to 0 inside its length; squash keeps the volume.
## - A pip that sets off crouches first, then stretches; one that stops after
##   a real walk squashes and nods (the leaf swinging on after the head), and
##   is back at exact rest about a second later. The same at 30, 60 and 120
##   frames a second; none of it with Reduce motion, and a reset clears it.
## - A quick turn leans the body into it, and the lean dies away as the facing
##   catches up. A drop down a step while walking squashes the body when it
##   lands; a lift, a walk up, a gentle slope and a ride never do. A carried
##   item on the back sways with the stride and swings on after a stop, and is
##   left alone once put down. Each settles to exact rest, agrees at 30, 60 and
##   120 frames a second, and does nothing with Reduce motion.
const Motion = preload("res://presentation/kit/motion.gd")
const Spirit = preload("res://presentation/spirit_visual.gd")
const CarriedItemKit = preload("res://presentation/kit/pieces/carried_item.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + message)
		print("FAIL: " + message)

func _run() -> void:
	_curves()
	_start_and_stop()
	_rates()
	_reduced()
	_turns()
	_landings()
	_carried()
	_carried_turns()
	print("MOTION: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _curves() -> void:
	for name: String in Motion.EASES:
		_check(absf(Motion.ease(name, 0.0)) < 0.0001 and absf(Motion.ease(name, 1.0) - 1.0) < 0.0001, "%s starts at 0 and ends at 1" % name)
	var most := 0.0
	var bounce_high := 0.0
	for step in range(101):
		most = maxf(most, Motion.ease("back", step / 100.0))
		bounce_high = maxf(bounce_high, Motion.ease("bounce", step / 100.0))
	_check(most > 1.05 and most < 1.15, "back runs about 10%% past the end: %.3f" % most)
	_check(bounce_high <= 1.0001, "bounce never passes the end")
	_check(is_equal_approx(Motion.settle(0.0, 0.2), 0.2) and absf(Motion.settle(1.5, 0.2)) < 0.001 and Motion.settle(-0.1, 0.2) == 0.0, "settle starts at its amount and dies away")
	var crossed := false
	for step in range(1, 40): crossed = crossed or Motion.settle(step / 100.0, 0.2, 3.0, 6.0) < 0.0
	_check(crossed, "settle swings past zero")
	_check(Motion.kick(-0.01, 0.2) == 0.0 and Motion.kick(0.2, 0.2) == 0.0 and is_equal_approx(Motion.kick(0.1, 0.2), 1.0), "kick is a bump inside its length")
	for amount: float in [-0.2, 0.0, 0.15]:
		var size := Motion.squash(amount)
		_check(absf(size.x * size.y * size.z - 1.0) < 0.0001, "squash %.2f keeps the volume" % amount)
	_check(Motion.squash(0.1).y < 1.0 and Motion.squash(-0.1).y > 1.0, "positive squashes, negative stretches")

## Walks for a second, stops, and records the body's height scale, the head's
## nod and the leaf's swing on every frame at `rate` frames a second.
func _walk_and_stop(rate: int, reduced: bool = false) -> Dictionary:
	var spirit := Spirit.new()
	root.add_child(spirit)
	var dt := 1.0 / float(rate)
	var start_low := 1.0
	var start_high := 1.0
	for frame in range(rate):
		spirit.advance_motion(Vector3(2.0 * dt, 0, 0), dt, reduced)
		if frame < rate / 4:
			start_low = minf(start_low, spirit.upper_body.scale.y)
	var nod_most := 0.0
	var nod_least := 0.0
	var squash_low := 1.0
	var leaf_at_nod_peak := 0.0
	var samples: Dictionary = {}
	for frame in range(rate * 2):
		spirit.advance_motion(Vector3.ZERO, dt, reduced)
		var nod := spirit.head.rotation.x
		if nod > nod_most:
			nod_most = nod
			leaf_at_nod_peak = spirit.sprout.rotation.x
		nod_least = minf(nod_least, nod)
		squash_low = minf(squash_low, spirit.upper_body.scale.y)
		for mark: float in [0.1, 0.3]:
			if absf(spirit.stop_age - mark) < dt * 0.5: samples[mark] = spirit.head.rotation.x
	var result := {"start_low": start_low, "nod_most": nod_most, "nod_least": nod_least, "squash_low": squash_low, "leaf": leaf_at_nod_peak,
		"rest_scale": spirit.upper_body.scale, "rest_nod": spirit.head.rotation.x, "samples": samples}
	spirit.free()
	return result

func _start_and_stop() -> void:
	var seen := _walk_and_stop(60)
	_check(seen.start_low < 0.97, "setting off crouches first: %.3f" % seen.start_low)
	_check(seen.nod_most > 0.1 and seen.nod_least < -0.01, "stopping nods and swings back: %.3f, %.3f" % [seen.nod_most, seen.nod_least])
	_check(seen.squash_low < 0.95, "stopping squashes the body: %.3f" % seen.squash_low)
	_check(seen.leaf > seen.nod_most, "the leaf swings further than the head")
	_check(seen.rest_scale == Vector3.ONE and seen.rest_nod == 0.0, "a stopped pip is back at exact rest")

func _rates() -> void:
	var at: Array = []
	for rate: int in [30, 60, 120]: at.append(_walk_and_stop(rate).samples)
	for mark: float in [0.1, 0.3]:
		var values: Array = []
		for sample: Dictionary in at: values.append(float(sample.get(mark, 99.0)))
		_check(absf(values[0] - values[1]) < 0.005 and absf(values[1] - values[2]) < 0.005, "the nod %.1f s after stopping is the same at 30, 60 and 120 fps: %s" % [mark, values])

func _reduced() -> void:
	var seen := _walk_and_stop(60, true)
	_check(seen.nod_most == 0.0 and seen.squash_low == 1.0 and seen.start_low == 1.0, "Reduce motion keeps the pip still")
	var spirit := Spirit.new()
	root.add_child(spirit)
	for _frame in range(30): spirit.advance_motion(Vector3(0.04, 0, 0), 1.0 / 60.0, false)
	spirit.advance_motion(Vector3.ZERO, 1.0 / 60.0, false)
	spirit.reset_motion()
	spirit.advance_motion(Vector3.ZERO, 1.0 / 60.0, false)
	_check(spirit.head.rotation.x == 0.0, "a reset clears a stop's nod")
	spirit.free()

## Walks each leg ({"v": velocity m/s, "t": seconds}) at `rate` frames a
## second, then stands for two seconds, calling `watch` with the spirit and the
## seconds since the walk began after every frame.
func _path(rate: int, legs: Array, reduced: bool, watch: Callable, spirit: Node3D = null) -> Node3D:
	if spirit == null:
		spirit = Spirit.new()
		root.add_child(spirit)
	var dt := 1.0 / float(rate)
	var frame := 0
	for leg: Dictionary in legs + [{"v": Vector3.ZERO, "t": 2.0}]:
		for _step in range(roundi(float(leg.t) * rate)):
			spirit.advance_motion(leg.v * dt, dt, reduced)
			frame += 1
			watch.call(spirit, frame * dt)
	return spirit

## East for half a second, then a sharp turn north.
func _turn_at(rate: int, reduced: bool = false) -> Dictionary:
	var seen := {"most": 0.0, "least": 0.0, "samples": {}}
	var dt := 1.0 / float(rate)
	var spirit := _path(rate, [{"v": Vector3(2, 0, 0), "t": 0.5}, {"v": Vector3(0, 0, 2), "t": 0.5}], reduced, func(pip: Node3D, at: float) -> void:
		if at > 0.5:
			seen.most = maxf(seen.most, pip.turn_lean())
			seen.least = minf(seen.least, pip.turn_lean())
		for mark: float in [0.6, 0.7]:
			if absf(at - mark) < dt * 0.5: seen.samples[mark] = pip.turn_lean())
	seen["rest"] = spirit.turn_lean() == 0.0 and spirit.upper_body.rotation == Vector3.ZERO
	spirit.free()
	return seen

func _turns() -> void:
	var seen := _turn_at(60)
	# East to north turns toward the pip's left (facing -X): it leans that way.
	_check(seen.least < -0.04 and seen.most == 0.0, "a sharp turn leans the body into it: %.3f, %.3f" % [seen.least, seen.most])
	_check(seen.rest, "the lean settles to exact rest")
	var at: Array = []
	for rate: int in [30, 60, 120]: at.append(_turn_at(rate).samples)
	for mark: float in [0.6, 0.7]:
		var values: Array = []
		for sample: Dictionary in at: values.append(float(sample.get(mark, 99.0)))
		_check(absf(values[0] - values[1]) < 0.003 and absf(values[1] - values[2]) < 0.003, "the turn's lean at %.1f s is the same at 30, 60 and 120 fps: %s" % [mark, values])
	var still := _turn_at(60, true)
	_check(still.least == 0.0 and still.most == 0.0 and still.samples.values().all(func(lean: float) -> bool: return lean == 0.0), "Reduce motion keeps a turn upright")

## Walks east, then `legs`, recording the landing squash and the body's height.
func _landing_at(rate: int, legs: Array, reduced: bool = false) -> Dictionary:
	var seen := {"most": 0.0, "low": 1.0, "landed": false, "samples": {}}
	var dt := 1.0 / float(rate)
	var spirit := _path(rate, [{"v": Vector3(2, 0, 0), "t": 0.5}] + legs, reduced, func(pip: Node3D, _at: float) -> void:
		seen.landed = seen.landed or pip.land_age < Spirit.MOTION_EVENT_END
		seen.most = maxf(seen.most, pip.landing_squash())
		seen.low = minf(seen.low, pip.upper_body.scale.y)
		for mark: float in [0.1, 0.3]:
			if absf(pip.land_age - mark) < dt * 0.5: seen.samples[mark] = pip.landing_squash())
	seen["rest"] = spirit.landing_squash() == 0.0 and spirit.upper_body.scale == Vector3.ONE
	spirit.free()
	return seen

const STEP_DOWN := [{"v": Vector3(2, -2, 0), "t": 0.1}, {"v": Vector3(2, 0, 0), "t": 0.4}]

func _landings() -> void:
	var seen := _landing_at(60, STEP_DOWN)
	_check(seen.landed and seen.most > 0.08 and seen.low < 0.95, "a step down squashes the body on landing: %.3f, %.3f" % [seen.most, seen.low])
	_check(seen.rest, "the landing settles to exact rest")
	var at: Array = []
	for rate: int in [30, 60, 120]: at.append(_landing_at(rate, STEP_DOWN).samples)
	for mark: float in [0.1, 0.3]:
		var values: Array = []
		for sample: Dictionary in at: values.append(float(sample.get(mark, 99.0)))
		_check(absf(values[0] - values[1]) < 0.003 and absf(values[1] - values[2]) < 0.003, "the landing %.1f s on is the same at 30, 60 and 120 fps: %s" % [mark, values])
	_check(not _landing_at(60, [{"v": Vector3.ZERO, "t": 0.3}, {"v": Vector3(0, -2, 0), "t": 0.3}]).landed, "a lift going down never lands")
	_check(not _landing_at(60, [{"v": Vector3(2, 2, 0), "t": 0.2}]).landed, "walking up a step never lands")
	_check(not _landing_at(60, [{"v": Vector3(2, -0.4, 0), "t": 0.5}]).landed, "a gentle slope never lands")
	var ride := Spirit.new()
	root.add_child(ride)
	for _frame in range(30):
		ride.position += Vector3(0.03, -0.03, 0)
		ride.advance_carried(1.0 / 60.0, false)
	_check(ride.land_age == Spirit.MOTION_EVENT_END, "a ride carried down never lands")
	ride.free()
	var still := _landing_at(60, STEP_DOWN, true)
	_check(not still.landed and still.low == 1.0, "Reduce motion keeps a landing still")

## A parcel on the back through a walk and a stop: how far it ever tipped, and
## its up direction at marks after the stop.
func _carry_at(rate: int, reduced: bool = false) -> Dictionary:
	var spirit := Spirit.new()
	root.add_child(spirit)
	var ground := Node3D.new()
	root.add_child(ground)
	var piece: RefCounted = CarriedItemKit.build("parcel", Vector3.ZERO, ground)
	piece.carry(spirit)
	var rest: Transform3D = piece.root.transform
	var seen := {"rest_first": rest.origin == CarriedItemKit.BACK, "most": 0.0, "moved": false, "samples": {}}
	var dt := 1.0 / float(rate)
	_path(rate, [{"v": Vector3(2, 0, 0), "t": 1.0}], reduced, func(pip: Node3D, _at: float) -> void:
		var item: Node3D = piece.root
		seen.moved = seen.moved or item.transform != rest
		seen.most = maxf(seen.most, item.basis.y.angle_to(Vector3.UP))
		for mark: float in [0.1, 0.3]:
			if absf(pip.stop_age - mark) < dt * 0.5: seen.samples[mark] = item.basis.y, spirit)
	seen["rest"] = piece.root.transform == rest and piece.root.position == CarriedItemKit.BACK
	piece.rest(Vector3(5, 0, 0), ground, false)
	for _frame in range(10): spirit.advance_motion(Vector3(0.04, 0, 0), 1.0 / 60.0, false)
	seen["left"] = piece.root.position == Vector3(5, 0, 0) and piece.root.basis == Basis.IDENTITY
	ground.free()
	spirit.free()
	return seen

func _carried() -> void:
	var seen := _carry_at(60)
	_check(seen.rest_first and seen.most > 0.04, "a carried parcel sways on the back: %.3f" % seen.most)
	_check(seen.samples.has(0.1) and seen.samples[0.1].angle_to(Vector3.UP) > 0.02, "it swings on after the pip stops")
	_check(seen.rest, "the parcel settles to exact rest")
	_check(seen.left, "put down, the pip leaves it alone")
	var at: Array = []
	for rate: int in [30, 60, 120]: at.append(_carry_at(rate).samples)
	for mark: float in [0.1, 0.3]:
		var values: Array = []
		for sample: Dictionary in at: values.append(sample.get(mark, Vector3(9, 9, 9)))
		_check(values[0].distance_to(values[1]) < 0.005 and values[1].distance_to(values[2]) < 0.005, "the parcel %.1f s after stopping is the same at 30, 60 and 120 fps: %s" % [mark, values])
	var still := _carry_at(60, true)
	_check(not still.moved, "Reduce motion keeps the parcel still")

## A pipsport carried while the pip walks each of the four ways in turn: it is
## on the pip's back, behind it, once the pip has turned and while it walks,
## and again once it stands and the sway has settled.
func _carried_turns() -> void:
	var spirit := Spirit.new()
	root.add_child(spirit)
	var ground := Node3D.new()
	root.add_child(ground)
	var piece: RefCounted = CarriedItemKit.build("pipsport", Vector3.ZERO, ground)
	piece.carry(spirit)
	var rest: Transform3D = piece.root.transform
	var dt := 1.0 / 60.0
	var behind := func(way: Vector3) -> float:
		var off: Vector3 = piece.root.global_position - spirit.global_position
		return Vector2(off.x, off.z).normalized().dot(-Vector2(way.x, way.z))
	for way: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD]:
		# Walk until the facing has caught up with the way (a fixed bound keeps it finite).
		var frames := 0
		spirit.advance_motion(way * 2.0 * dt, dt, false)
		while absf(angle_difference(spirit.facing.rotation.y, spirit.facing_target)) > 0.0001 and frames < 600:
			spirit.advance_motion(way * 2.0 * dt, dt, false)
			frames += 1
		var walking: float = behind.call(way)
		for _frame in range(120): spirit.advance_motion(Vector3.ZERO, dt, false)
		var standing: float = behind.call(way)
		var off: Vector3 = piece.root.global_position - spirit.global_position
		var settled: bool = piece.root.transform == rest and Vector2(off.x, off.z).length() > 0.19
		_check(frames < 600 and walking > 0.99 and standing > 0.999 and settled, "walking %s the pipsport rides behind the pip: %.4f walking, %.4f standing, at %s" % [way, walking, standing, off])
	ground.free()
	spirit.free()
