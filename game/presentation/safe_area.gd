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
## The native safe rectangle at the last poll (follow_turns).
static var _seen := Rect2()
## How often a phone reads its safe rectangle again (follow_turns).
const TURN_POLL_SECONDS := 0.5
const TURNS_META := &"safe_area_turns"

static func simulate(native_safe: Rect2) -> void:
	_simulated = native_safe

## Phones report notch, cutout and home-indicator insets; desktop windows use the full viewport.
static func applies() -> bool:
	return _simulated.has_area() or PlatformSupport.is_phone()

## The safe rectangle in this viewport's coordinates (the visible rect when nothing is inset).
static func rect(viewport: Viewport) -> Rect2:
	var visible := viewport.get_visible_rect()
	if not applies(): return visible
	return viewport_rect(native(), viewport.get_screen_transform(), visible)

## The native safe rectangle in screen pixels, or Rect2() where none applies.
static func native() -> Rect2:
	if not applies(): return Rect2()
	return _simulated if _simulated.has_area() else Rect2(DisplayServer.get_display_safe_area())

## Both landscape sides are allowed (sensor landscape). A half turn keeps the
## screen size and sends no event, yet moves the cutout to the other edge, so
## one timer under the tree's root (it outlives every scene change, solo
## chapters included) reads the safe rectangle again twice a second and every
## watched screen relays out when it moved. The first watcher installs it.
static func follow_turns(tree: SceneTree) -> void:
	var root := tree.root
	if root.has_meta(TURNS_META): return
	root.set_meta(TURNS_META, true)
	_seen = native()
	fit_width(root)
	root.size_changed.connect(func() -> void: fit_width(root))
	var timer := Timer.new()
	timer.name = "SafeAreaTurns"
	timer.wait_time = TURN_POLL_SECONDS
	timer.autostart = true
	timer.timeout.connect(func() -> void: poll(timer.get_tree()))
	# The root may be busy adding the very screen that asked.
	root.add_child.call_deferred(timer, false, Node.INTERNAL_MODE_BACK)

## Relays out every watched screen (watch) when the native safe rectangle
## moved since the last poll. Returns whether it moved.
static func poll(tree: SceneTree) -> bool:
	var now := native()
	if now == _seen: return false
	_seen = now
	fit_width(tree.root)
	tree.call_group(Watch.GROUP, "relayout_now")
	return true

## The narrowest the safe area may be: the authored width (project.godot's
## base). The expand stretch already keeps the whole screen at least this wide;
## an inset column (the iPhone Duo's camera side holds 84 pt, a sixth of its
## outer display) would leave the safe area narrower than any phone gives, and
## pages wrap and cut their text. Such a screen draws everything a little
## smaller instead, down to MIN_WIDTH_SCALE (about an iPhone mini's size).
## Phones wider than 16:9 always have room to spare and never change; a screen
## 16:9 or narrower with any side inset (an Android foldable's inner screen with
## a camera hole) draws just enough smaller to keep the authored width.
const SAFE_WIDTH := 1280.0
const MIN_WIDTH_SCALE := 0.8
## The factor this module last wrote to the root (1 until a screen needs one).
static var _width_scale := 1.0

## The root's content scale factor that keeps a `safe_width` wide native safe
## area at least SAFE_WIDTH units wide in a `window` sized screen stretched
## from `base` (canvas_items, expand). 1 when it already is.
static func width_scale(window: Vector2, base: Vector2, safe_width: float) -> float:
	if not (window.x > 0.0 and window.y > 0.0 and base.x > 0.0 and base.y > 0.0 and safe_width > 0.0): return 1.0
	var stretch := minf(window.x / base.x, window.y / base.y)
	return clampf(safe_width / (SAFE_WIDTH * stretch), MIN_WIDTH_SCALE, 1.0)

## Applies width_scale to `root` from the current safe area. Only a screen with
## a safe area (a phone or tablet, or a simulated one) changes; anything else
## goes back to 1 if this module changed it. Called on a resize and when the
## safe area moves, never per frame; the factor depends on screen pixels only,
## so the resize it causes changes nothing further.
static func fit_width(root: Window) -> void:
	if root == null or root.content_scale_mode != Window.CONTENT_SCALE_MODE_CANVAS_ITEMS or root.content_scale_aspect != Window.CONTENT_SCALE_ASPECT_EXPAND: return
	var safe := native()
	var wanted := 1.0
	if safe.has_area():
		var screen := Rect2(Vector2.ZERO, Vector2(root.size))
		wanted = width_scale(screen.size, Vector2(root.content_scale_size), screen.intersection(safe).size.x)
	elif is_equal_approx(_width_scale, 1.0):
		return # never changed here: leave the root's own factor alone
	if is_equal_approx(wanted, _width_scale) and is_equal_approx(root.content_scale_factor, wanted): return
	_width_scale = wanted
	root.content_scale_factor = wanted

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

## The tallest a page grows: the phone's height. A taller screen (a 4:3 or
## 16:10 tablet) centres a page block this tall instead of stretching its
## panels, as a wide screen centres a page no wider than the page allows.
const PAGE_HEIGHT := 720.0

## Spacing on each side that centres content no longer than `cap` along
## `length` (a page's width or height), never less than `minimum`.
static func centred(length: float, cap: float, minimum: int) -> int:
	return maxi(minimum, int((length - cap) * 0.5))

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
