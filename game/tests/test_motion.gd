extends SceneTree
## kit/motion.gd and the pip moves made with it.
## - Every ease starts at 0 and ends at 1; back runs past the end, bounce
##   never does. settle starts at its amount and dies away; kick rises and
##   falls back to 0 inside its length; squash keeps the volume.
## - A pip that sets off crouches first, then stretches; one that stops after
##   a real walk squashes and nods (the leaf swinging on after the head), and
##   is back at exact rest about a second later. The same at 30, 60 and 120
##   frames a second; none of it with Reduce motion, and a reset clears it.
const Motion = preload("res://presentation/kit/motion.gd")
const Spirit = preload("res://presentation/spirit_visual.gd")

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
