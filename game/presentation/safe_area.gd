extends RefCounted
## The one place that decides display-cutout insets.
## Backdrops bleed: the world, page backgrounds and dimming scrims reach every
## screen edge, under the camera hole too (bleed). Content pads: buttons and text
## stay inside the safe rect (rect, pad).
## DisplayServer returns physical screen pixels; controls use viewport coordinates.
const PlatformSupport = preload("res://services/platform_support.gd")
const FullBleed = preload("res://presentation/full_bleed.gd")
const Watch = preload("res://presentation/safe_area_watch.gd")

## Tests and captures: a native safe rectangle to use instead of the display's.
## While set, the safe area applies on desktop too. Rect2() clears it.
static var _simulated := Rect2()

static func simulate(native_safe: Rect2) -> void:
	_simulated = native_safe

## Phones report notch, cutout and home-indicator insets; desktop windows use the full viewport.
static func applies() -> bool:
	return _simulated.has_area() or PlatformSupport.is_phone()

## The safe rectangle in this viewport's coordinates (the visible rect when nothing is inset).
static func rect(viewport: Viewport) -> Rect2:
	var visible := viewport.get_visible_rect()
	if not applies(): return visible
	var native := _simulated if _simulated.has_area() else Rect2(DisplayServer.get_display_safe_area())
	return viewport_rect(native, viewport.get_screen_transform(), visible)

static func viewport_rect(screen_safe: Rect2, screen_transform: Transform2D, viewport: Rect2) -> Rect2:
	if not screen_safe.is_finite() or not screen_transform.is_finite() or not screen_safe.has_area() or is_zero_approx(screen_transform.determinant()):
		return viewport
	var mapped := (screen_transform.affine_inverse() * screen_safe).intersection(viewport)
	return mapped if mapped.has_area() else viewport

## Insets a full-rect content root (anchored to the whole viewport) to `safe`.
static func inset(control: Control, safe: Rect2) -> void:
	var visible := control.get_viewport().get_visible_rect()
	control.offset_left = safe.position.x - visible.position.x
	control.offset_top = safe.position.y - visible.position.y
	control.offset_right = safe.end.x - visible.end.x
	control.offset_bottom = safe.end.y - visible.end.y

## Content margins for a full-rect MarginContainer: the safe insets of `safe` within
## `full`, plus the screen's own spacing on each side.
static func pad(margin: MarginContainer, full: Rect2, safe: Rect2, left: int, top: int, right: int, bottom: int) -> void:
	margin.add_theme_constant_override("margin_left", int(safe.position.x - full.position.x) + left)
	margin.add_theme_constant_override("margin_top", int(safe.position.y - full.position.y) + top)
	margin.add_theme_constant_override("margin_right", int(full.end.x - safe.end.x) + right)
	margin.add_theme_constant_override("margin_bottom", int(full.end.y - safe.end.y) + bottom)

## Keeps a backdrop (page background, dimming scrim) covering the whole visible
## viewport even inside an inset parent, and refits it whenever an ancestor or
## the viewport changes. Event-driven; nothing runs per frame.
static func bleed(control: Control) -> void:
	if control.get_node_or_null(NodePath(FullBleed.NAME)) != null: return
	var helper: Node = FullBleed.new()
	helper.name = FullBleed.NAME
	control.add_child(helper, false, Node.INTERNAL_MODE_BACK)

## Calls `relayout` whenever the safe rect may have changed: the viewport resized
## or the app returned to the foreground. One watcher per screen; event-driven.
static func watch(screen: Node, relayout: Callable) -> void:
	var helper: Node = screen.get_node_or_null(NodePath(Watch.NAME))
	if helper == null:
		helper = Watch.new()
		helper.name = Watch.NAME
		screen.add_child(helper, false, Node.INTERNAL_MODE_BACK)
	helper.relayout = relayout
