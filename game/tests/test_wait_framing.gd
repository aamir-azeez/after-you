extends SceneTree
## The room panel's closer view (presentation/wait_framing.gd): it frames the
## spirits beside the panel, comes in at most MAX_ZOOM, never pulls out past
## the whole-chapter view, keeps that view when the spirits are far apart, and
## blends between framings.
const WaitFraming = preload("res://presentation/wait_framing.gd")
const VIEWPORT := Rect2(0, 0, 1600, 738)
## The scene beside the panel at 1600x738.
const TARGET := Rect2(28, 210, 840, 500)

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(VIEWPORT.size)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = 24.0
	root.add_child(camera)
	camera.current = true
	camera.global_transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(-35.0), deg_to_rad(45.0), 0.0)), Vector3(20, 18, 20))
	var whole := WaitFraming.of(camera)
	# Two spirits a step apart: in as far as allowed.
	var near: Array[Vector3] = [Vector3(1, 0, 0), Vector3(2, 0, 1)]
	var close := WaitFraming.closer(camera, near, TARGET, VIEWPORT)
	_check(not close.is_empty() and is_equal_approx(close.size, whole.size / WaitFraming.MAX_ZOOM) and close.h == 0.0 and close.v == 0.0, "Spirits close together come in to the most zoom: " + str(close.get("size")))
	_check(_on_target(camera, close, near, TARGET), "The framed spirits sit in the scene beside the panel")
	# Spirits a little apart: closer than the whole view, but not all the way.
	var apart: Array[Vector3] = [camera.global_basis.x * -7.0, camera.global_basis.x * 7.0]
	var middle := WaitFraming.closer(camera, apart, TARGET, VIEWPORT)
	_check(not middle.is_empty() and middle.size > whole.size / WaitFraming.MAX_ZOOM and middle.size * WaitFraming.MIN_GAIN < whole.size, "Spirits a little apart come in only as far as both fit")
	_check(_on_target(camera, middle, apart, TARGET), "Both spirits a little apart stay in the scene beside the panel")
	# Spirits across the chapter: the whole view stays.
	var far: Array[Vector3] = [Vector3(-30, 0, -30), Vector3(30, 0, 30)]
	_check(WaitFraming.closer(camera, far, TARGET, VIEWPORT).is_empty(), "Spirits far apart keep the whole-chapter view")
	_check(WaitFraming.closer(camera, [] as Array[Vector3], TARGET, VIEWPORT).is_empty(), "No spirits keep the whole-chapter view")
	# Blending moves from one framing to the other and stops there.
	_check(WaitFraming.same(WaitFraming.blend(whole, close, 0.0), whole) and WaitFraming.same(WaitFraming.blend(whole, close, 1.0), close), "A blend starts and ends on its framings")
	var half := WaitFraming.blend(whole, close, 0.5)
	_check(is_equal_approx(half.size, (whole.size + close.size) / 2.0) and half.position.is_equal_approx(whole.position.lerp(close.position, 0.5)), "Halfway is halfway in size and position")
	WaitFraming.apply(camera, close)
	_check(WaitFraming.same(WaitFraming.of(camera), close), "A framing applies to the camera exactly")
	camera.queue_free()
	await process_frame
	print("WAIT FRAMING: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## Every point, framed, lands inside `target` on screen.
func _on_target(camera: Camera3D, framing: Dictionary, points: Array[Vector3], target: Rect2) -> bool:
	var before := WaitFraming.of(camera)
	WaitFraming.apply(camera, framing)
	var inside := true
	for point: Vector3 in points:
		var at := camera.unproject_position(point)
		inside = inside and target.grow(1.0).has_point(at)
	WaitFraming.apply(camera, before)
	return inside

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAILED: " + description)
