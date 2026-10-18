extends RefCounted
## The room panel's closer view. While a player waits, and on their own turn
## before recording, the scene beside the panel frames both spirits (and, on
## their turn, the goal pieces) instead of the whole chapter. It never comes in
## closer than MAX_ZOOM and never pulls out past the whole-chapter view; when
## the spirits are too far apart to gain much, it keeps that view.
## A framing is {"position": Vector3, "size": float, "h": float, "v": float}
## for an orthographic camera.
const MAX_ZOOM := 1.7
## Coming in by less than this keeps the whole-chapter view.
const MIN_GAIN := 1.1
## World margins around the framed points: an island's half width to the
## sides, the spirit below, and its name label above.
const SIDE := 2.6
const BELOW := 1.4
const ABOVE := 2.6
## The framed points fill this share of the scene beside the panel.
const FILL := 0.9

static func of(camera: Camera3D) -> Dictionary:
	return {"position": camera.global_position, "size": camera.size, "h": camera.h_offset, "v": camera.v_offset}

static func apply(camera: Camera3D, framing: Dictionary) -> void:
	camera.global_position = framing.position
	camera.size = framing.size
	camera.h_offset = framing.h
	camera.v_offset = framing.v

static func blend(from: Dictionary, to: Dictionary, weight: float) -> Dictionary:
	return {"position": from.position.lerp(to.position, weight), "size": lerpf(from.size, to.size, weight), "h": lerpf(from.h, to.h, weight), "v": lerpf(from.v, to.v, weight)}

static func same(a: Dictionary, b: Dictionary) -> bool:
	return a.position.is_equal_approx(b.position) and is_equal_approx(a.size, b.size) and is_equal_approx(a.h, b.h) and is_equal_approx(a.v, b.v)

## The closer framing of `points` in `target` (viewport pixels), for `camera`
## as it shows the whole chapter there, or {} to keep that view.
static func closer(camera: Camera3D, points: Array[Vector3], target: Rect2, viewport: Rect2) -> Dictionary:
	if points.is_empty() or target.size.x <= 0.0 or target.size.y <= 0.0 or viewport.size.y <= 0.0: return {}
	var whole: float = camera.size
	var basis := camera.global_basis
	var centre := camera.global_position + basis.x * camera.h_offset + basis.y * camera.v_offset
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for point: Vector3 in points:
		var relative := point - centre
		var flat := Vector2(relative.dot(basis.x), relative.dot(basis.y))
		low = low.min(flat)
		high = high.max(flat)
	low -= Vector2(SIDE, BELOW)
	high += Vector2(SIDE, ABOVE)
	var extent := high - low
	var per_pixel: float = maxf(extent.x / (target.size.x * FILL), extent.y / (target.size.y * FILL))
	var needed := per_pixel * viewport.size.y
	if needed * MIN_GAIN >= whole: return {}
	var size := maxf(needed, whole / MAX_ZOOM)
	var middle := (low + high) / 2.0
	var position := centre + basis.x * middle.x + basis.y * middle.y
	# Put the framed middle at the middle of the scene beside the panel.
	var shift := viewport.get_center() - target.get_center()
	var units := size / viewport.size.y
	position += basis.x * shift.x * units - basis.y * shift.y * units
	return {"position": position, "size": size, "h": 0.0, "v": 0.0}
