extends RefCounted
## Device presentation only. Never changes simulation ticks, input or recordings.
const DEFAULT_QUALITY := "balanced"
const QUALITIES := ["low", "balanced", "high"]

static func normalize(value: Variant) -> String:
	return value if value is String and value in QUALITIES else DEFAULT_QUALITY

static func render_scale(quality: Variant) -> float:
	return 0.75 if normalize(quality) == "low" else 1.0

static func antialiasing(quality: Variant) -> Viewport.MSAA:
	return Viewport.MSAA_2X if normalize(quality) == "high" else Viewport.MSAA_DISABLED

static func shadows(quality: Variant) -> bool:
	return normalize(quality) != "low"

static func mote_count(authored_count: int, quality: Variant) -> int:
	return ceili(authored_count * 0.25) if normalize(quality) == "low" else authored_count

static func apply_viewport(viewport: Viewport, quality: Variant) -> void:
	# Scale only the 3D buffer; UI and touch coordinates retain their full size.
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	viewport.scaling_3d_scale = render_scale(quality)
	viewport.msaa_3d = antialiasing(quality)

static func apply(world: Node3D, settings: Dictionary) -> void:
	if not is_instance_valid(world) or not world.is_node_ready(): return
	var quality := normalize(settings.get("graphics_quality"))
	apply_viewport(world.get_viewport(), quality)
	if world.has_method("apply_graphics_quality"):
		world.apply_graphics_quality(quality)
