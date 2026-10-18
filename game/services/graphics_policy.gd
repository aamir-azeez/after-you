extends RefCounted
## Device presentation only. Never changes simulation ticks, input or recordings.
const DEFAULT_QUALITY := "balanced"
const QUALITIES := ["low", "balanced", "high"]

static func normalize(value: Variant) -> String:
	return value if value is String and value in QUALITIES else DEFAULT_QUALITY

## The 3D picture is drawn at most this many lines tall (the screen's short
## side) and scaled up: a 1440p phone would otherwise shade nearly twice the
## pixels of a 1080p one for a difference nobody sees at arm's length. High
## keeps the screen's own resolution. 0 = no limit.
const MAX_LINES := {"low": 720, "balanced": 1080, "high": 0}

## short_side: the screen's shorter side in pixels; 0 leaves only the quality's
## own scale.
static func render_scale(quality: Variant, short_side: int = 0) -> float:
	var name := normalize(quality)
	var scale := 0.75 if name == "low" else 1.0
	var lines: int = MAX_LINES[name]
	if lines > 0 and short_side > lines: scale = minf(scale, float(lines) / short_side)
	return scale

static func antialiasing(quality: Variant) -> Viewport.MSAA:
	return Viewport.MSAA_2X if normalize(quality) == "high" else Viewport.MSAA_DISABLED

static func mote_count(authored_count: int, quality: Variant) -> int:
	return ceili(authored_count * 0.25) if normalize(quality) == "low" else authored_count

static func apply_viewport(viewport: Viewport, quality: Variant) -> void:
	# Scale only the 3D buffer; UI and touch coordinates retain their full size.
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	viewport.scaling_3d_scale = render_scale(quality, _short_side(viewport))
	viewport.msaa_3d = antialiasing(quality)

static func _short_side(viewport: Viewport) -> int:
	var size := Vector2i.ZERO
	if viewport is Window: size = (viewport as Window).size
	elif viewport is SubViewport: size = (viewport as SubViewport).size
	return mini(size.x, size.y)

## The player's frame rate for play (services/frame_policy.gd): "30", "60" or
## "unlimited" (the screen's full refresh rate). Menus keep their own cap.
const FRAME_RATES := ["30", "60", "unlimited"]
const DEFAULT_FRAME_RATE := "60"

## The saved frame rate, or 60 for anything else.
static func frame_rate(settings: Dictionary) -> String:
	var value: Variant = settings.get("frame_rate")
	return value if value is String and value in FRAME_RATES else DEFAULT_FRAME_RATE

## Frames a second for play at a frame rate; 0 is no cap.
static func play_fps(rate: String) -> int:
	return 30 if rate == "30" else 0 if rate == "unlimited" else 60

## The frame rate a loaded save means. Builds before the choice saved only
## `unlimited_frame_rate`, and they keep writing it next to `frame_rate`, so
## where the two disagree the older build changed it last: its switch on means
## Unlimited, and its switch off ends an Unlimited choice (back to 60).
static func loaded_frame_rate(settings: Dictionary) -> String:
	var rate := frame_rate(settings)
	var unlimited: Variant = settings.get("unlimited_frame_rate")
	if not unlimited is bool: return rate
	if unlimited: return "unlimited"
	return DEFAULT_FRAME_RATE if rate == "unlimited" else rate

static func apply(world: Node3D, settings: Dictionary) -> void:
	if not is_instance_valid(world) or not world.is_node_ready(): return
	var frames := world.get_tree().root.get_node_or_null("FramePolicy")
	if frames != null: frames.play_fps = play_fps(frame_rate(settings))
	var quality := normalize(settings.get("graphics_quality"))
	apply_viewport(world.get_viewport(), quality)
	if world.has_method("apply_graphics_quality"):
		world.apply_graphics_quality(quality)
