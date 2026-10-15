extends RefCounted
## Shared touch rules for every screen.
##
## A finger never lands perfectly still. Android forwards even sub-pixel moves
## here (project.godot disables its own scroll slop for the pinch and stick
## controls), and a ScrollContainer starts scrolling on the first pixel by
## default, which cancels the press on whatever button the finger is on. Lists
## therefore get a physical slop, about the size of Android's own, before a
## press turns into a scroll.

const SCROLL_DEADZONE_SETTING := "gui/common/default_scroll_deadzone"
## About 10 dp: Android's touch slop is 8 dp, and a tap on a phone held in two
## hands drifts a little further.
const SLOP_INCHES := 0.0625
const MIN_DEADZONE := 8
const MAX_DEADZONE := 32
## Used when the display does not report a density (headless, some desktops).
const FALLBACK_DPI := 160

## The slop in the viewport's own canvas units. canvas_items stretching
## scales a tiny screen and a tablet to the same 720-unit height, so the same
## finger travel is a different number of units on each.
static func scroll_deadzone(viewport: Viewport = null) -> int:
	var target := viewport
	if target == null:
		var tree := Engine.get_main_loop() as SceneTree
		target = tree.root if tree != null else null
	var scale := 1.0
	if target != null: scale = absf(target.get_final_transform().get_scale().y)
	return deadzone_for(DisplayServer.screen_get_dpi(), scale)

## `dpi` is physical pixels per inch; `scale` is physical pixels per canvas unit.
static func deadzone_for(dpi: int, scale: float) -> int:
	var density := float(dpi if dpi > 0 else FALLBACK_DPI)
	return clampi(roundi(SLOP_INCHES * density / maxf(scale, 0.01)), MIN_DEADZONE, MAX_DEADZONE)

## Every ScrollContainer built after this call starts with the slop. The app
## calls it once at start and again when the window size changes.
static func install(viewport: Viewport = null) -> int:
	var deadzone := scroll_deadzone(viewport)
	if int(ProjectSettings.get_setting(SCROLL_DEADZONE_SETTING, 0)) != deadzone:
		ProjectSettings.set_setting(SCROLL_DEADZONE_SETTING, deadzone)
	return deadzone

## For a list that already exists, or one built by a screen opened on its own.
static func apply(scroll: ScrollContainer) -> void:
	var deadzone := scroll_deadzone(scroll.get_viewport() if scroll.is_inside_tree() else null)
	if scroll.scroll_deadzone < deadzone: scroll.scroll_deadzone = deadzone

## True while a finger or mouse is pressing a button inside `node`. A refresh
## that would free that button must wait for the release, or the tap is lost:
## a button that leaves the tree drops its press and the new copy never saw it.
## Toggle buttons report their toggle state instead, so they are not counted.
static func press_held(node: Node) -> bool:
	if not is_instance_valid(node) or not node.is_inside_tree(): return false
	for found: Node in node.find_children("*", "BaseButton", true, false):
		var button := found as BaseButton
		if not button.toggle_mode and button.is_pressed() and button.is_visible_in_tree(): return true
	return false

## Waits until no finger or mouse is pressing a button inside `node`, for at
## most `limit_ms` so a poll can never stall behind a lost release. Returns at
## once when nothing is pressed, so callers redraw in the same frame then.
## Callers check their own state again afterwards: the screen may have changed.
static func until_released(node: Node, limit_ms: int = 5000) -> void:
	var deadline := Time.get_ticks_msec() + limit_ms
	while press_held(node) and Time.get_ticks_msec() < deadline:
		await node.get_tree().process_frame

## The one rule for a redraw that was not tapped (a poll, a download or a task
## that ended): wait until no finger is pressing a button inside `node`, then
## run `redraw` only if `still`, the caller's own check of its screen, holds.
## True when it redrew.
static func redraw_when_released(node: Node, still: Callable, redraw: Callable) -> bool:
	await until_released(node)
	if not still.call(): return false
	redraw.call()
	return true
