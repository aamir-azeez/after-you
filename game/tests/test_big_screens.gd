extends SceneTree
## Big screens on the real root Window stretch (canvas_items, expand): the iPad
## 13-inch and 11-inch, Android 10-inch and 7-inch tablets, and the iPhone Duo's
## inner (2853x2007) and outer (2034x1398) displays with the camera column on
## either side. Every screen keeps a safe area at least the authored 1280 units
## wide (SafeArea.fit_width), Main's content follows it, Home, Settings and the
## HUD stay inside it, and the Wardrobe, the Pollen store and Pollen from play
## centre a phone-height page block (kit/page_margin.gd) instead of stretching.

const Main = preload("res://main.gd")
const Storage = preload("res://services/local_save.gd")
const SafeArea = preload("res://presentation/safe_area.gd")
const PageMargin = preload("res://presentation/kit/page_margin.gd")
const WardrobePage = preload("res://presentation/wardrobe_page.gd")
const PollenStorePage = preload("res://presentation/pollen_store_page.gd")
const PollenPlayPage = preload("res://presentation/pollen_play_page.gd")

## [physical pixels, native insets (left, top, right, bottom) in pixels, name].
## The Duo's insets are an estimate until a device or Device Hub run reads them:
## an 84 pt column on the camera side at 3x (252 px) and the home indicator.
const SCREENS := [
	[Vector2i(2732, 2048), Vector4(0, 0, 0, 40), "iPad 13-inch"],
	[Vector2i(2388, 1668), Vector4(0, 0, 0, 40), "iPad 11-inch"],
	[Vector2i(2560, 1600), Vector4.ZERO, "Android 10-inch"],
	[Vector2i(1920, 1200), Vector4.ZERO, "Android 7-inch"],
	[Vector2i(2853, 2007), Vector4(0, 0, 252, 60), "iPhone Duo inner, camera right"],
	[Vector2i(2853, 2007), Vector4(252, 0, 0, 60), "iPhone Duo inner, camera left"],
	[Vector2i(2034, 1398), Vector4(252, 0, 0, 63), "iPhone Duo outer, camera left"],
	[Vector2i(2034, 1398), Vector4(0, 0, 252, 63), "iPhone Duo outer, camera right"],
	[Vector2i(2034, 1398), Vector4(0, 252, 0, 63), "iPhone Duo outer, camera band on top"],
]

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _same_rect(actual: Rect2, expected: Rect2, context: String) -> void:
	_check(actual.position.is_equal_approx(expected.position) and actual.size.is_equal_approx(expected.size), "%s: expected %s, received %s" % [context, expected, actual])

func _settle() -> void:
	for i in range(4): await process_frame

func _run() -> void:
	_test_rules()
	var original := {"size": root.size, "content_scale_size": root.content_scale_size, "content_scale_mode": root.content_scale_mode,
		"content_scale_aspect": root.content_scale_aspect, "content_scale_factor": root.content_scale_factor}
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	root.content_scale_factor = 1.0
	var path := "user://big-screens-test-" + Crypto.new().generate_random_bytes(8).hex_encode() + ".json"
	var app := Main.new()
	app.saves = Storage.new(path)
	app.saves.data.settings.sound = false
	app.saves.data.settings.haptics = false
	app.saves.flush()
	root.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	await _settle()
	for screen: Array in SCREENS:
		await _test_screen(app, screen[0], screen[1], screen[2])
	await _test_fold(app)
	SafeArea.simulate(Rect2())
	SafeArea.poll(self)
	await _settle()
	_check(is_equal_approx(root.content_scale_factor, 1.0), "Clearing the safe area gives the root its own scale back")
	app.queue_free()
	await _settle()
	for property: String in original: root.set(property, original[property])
	await _settle()
	await create_timer(0.15).timeout
	for suffix: String in ["", ".tmp", ".backup"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	print("AFTER YOU BIG SCREENS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

## The two rules as plain arithmetic.
func _test_rules() -> void:
	var base := Vector2(1280, 720)
	# Phones never change: their safe area is already wider than the authored width.
	_check(is_equal_approx(SafeArea.width_scale(Vector2(2340, 1080), base, 2340 - 136), 1.0), "A 19.5:9 Android phone with a camera hole keeps its scale")
	_check(is_equal_approx(SafeArea.width_scale(Vector2(2556, 1179), base, 2556 - 2 * 186), 1.0), "An iPhone in landscape with both side insets keeps its scale")
	_check(is_equal_approx(SafeArea.width_scale(Vector2(2732, 2048), base, 2732), 1.0), "An iPad keeps its scale")
	# The Duo's camera column: the safe area comes back to 1280 units.
	var outer := SafeArea.width_scale(Vector2(2034, 1398), base, 2034 - 252)
	_check(outer < 1.0 and is_equal_approx((2034 - 252) / (2034.0 / 1280.0 * outer), 1280.0), "The Duo's outer display draws a little smaller so its safe area is 1280 units wide (%.3f)" % outer)
	var inner := SafeArea.width_scale(Vector2(2853, 2007), base, 2853 - 252)
	_check(inner < 1.0 and inner > outer, "The inner display needs less (%.3f)" % inner)
	_check(is_equal_approx(SafeArea.width_scale(Vector2(1000, 1000), base, 300), SafeArea.MIN_WIDTH_SCALE), "Nothing draws smaller than the floor")
	_check(is_equal_approx(SafeArea.width_scale(Vector2.ZERO, base, 100), 1.0) and is_equal_approx(SafeArea.width_scale(Vector2(100, 100), base, 0), 1.0), "No screen or no safe area keeps the scale")
	# Pages: a phone keeps its own spacing, a taller page centres 720 units.
	_check(PageMargin.end_spacing(680, 20) == 20 and PageMargin.end_spacing(720, 22) == 22, "A phone page keeps its spacing above and below")
	_check(PageMargin.end_spacing(960, 20) == 120 and PageMargin.end_spacing(800, 20) == 40, "A taller page centres a 720 unit block")

func _test_screen(app: Node, size: Vector2i, insets: Vector4, name: String) -> void:
	root.size = size
	var native := Rect2(insets.x, insets.y, size.x - insets.x - insets.z, size.y - insets.y - insets.w)
	SafeArea.simulate(native)
	SafeArea.poll(self)
	await _settle()
	var visible := root.get_visible_rect()
	var transform := root.get_screen_transform()
	_same_rect(transform * visible, Rect2(Vector2.ZERO, Vector2(size)), name + ": the stretch fills every pixel")
	_check(visible.size.x >= 1280.0 - 0.5 and visible.size.y >= 720.0 - 0.5, name + ": the screen is at least the authored 1280x720 units, got %s" % visible.size)
	var safe := SafeArea.rect(root)
	_same_rect(transform * safe, native, name + ": the safe area maps back to the native one")
	_check(safe.size.x >= 1280.0 - 0.5, name + ": the safe area is at least 1280 units wide, got %.1f" % safe.size.x)
	_check(root.content_scale_factor >= SafeArea.MIN_WIDTH_SCALE and root.content_scale_factor <= 1.0, name + ": the root scale stays within its floor")
	if insets.x == 0.0 and insets.z == 0.0:
		_check(is_equal_approx(root.content_scale_factor, 1.0), name + ": no side inset, so nothing draws smaller")
	_same_rect(app.ui.get_global_rect(), safe, name + ": Main's content root is the safe area")
	app._show_home()
	await _settle()
	_check_inside(app.overlay, safe, name + " Home")
	app.settings_flow.show_settings()
	await _settle()
	_check_inside(app.overlay, safe, name + " Settings")
	for page: Control in [WardrobePage.new(false), PollenStorePage.new(), PollenPlayPage.new()]:
		await _check_page(app, page, safe, name)
	await _check_hud(app, safe, name)
	app._show_home()
	await _settle()

## A shop page centres a phone-height block in the safe area and keeps its own spacing on the sides.
func _check_page(app: Node, page: Control, safe: Rect2, name: String) -> void:
	app._clear_overlay()
	app.overlay.add_child(page)
	await _settle()
	var margin: PageMargin = null
	for child: Node in page.get_children():
		if child is PageMargin: margin = child
	_check(margin != null, "%s: %s lays out through the shared page margin" % [name, page.name])
	if margin == null: return
	var block := (margin.get_child(0) as Control).get_global_rect()
	_check(safe.encloses(block), "%s: %s stays inside the safe area" % [name, page.name])
	var above := block.position.y - safe.position.y
	var below := safe.end.y - block.end.y
	if safe.size.y > SafeArea.PAGE_HEIGHT:
		_check(block.size.y <= SafeArea.PAGE_HEIGHT + 1.5 and absf(above - below) <= 1.5, "%s: %s centres a page block no taller than the phone's (%.0f tall, %.0f above, %.0f below)" % [name, page.name, block.size.y, above, below])
	else:
		_check(absf(above - margin.ends) <= 1.0 and absf(below - margin.ends) <= 1.0, "%s: %s keeps its spacing on a short screen (%.1f above, %.1f below)" % [name, page.name, above, below])
	_check(is_equal_approx(block.position.x - safe.position.x, float(margin.side)), "%s: %s keeps its side spacing" % [name, page.name])
	_check_inside(page, safe, "%s %s" % [name, page.name])
	app._clear_overlay()

## The chapter HUD: every control inside the safe area and none on another.
func _check_hud(app: Node, safe: Rect2, name: String) -> void:
	app._start_practice(0)
	app._close_overlay()
	app.running = false
	await _settle()
	var controls: Array[Control] = [app.stick, app.interact_button, app.finish_button, app.timer_label, app.progress, app.hint_label]
	for control: Control in controls:
		_check(safe.encloses(control.get_global_rect()), "%s: the HUD's %s stays in the safe area" % [name, control.name])
	_check(not app.stick.get_global_rect().intersects(app.interact_button.get_global_rect()) and not app.interact_button.get_global_rect().intersects(app.finish_button.get_global_rect()), name + ": the HUD's touch targets stay apart")
	_check(app.hint_label.get_line_count() == app.hint_label.get_visible_line_count(), name + ": every line of the hint shows")

## Unfolding the Duo resizes the window: the root scale follows with no extra call.
func _test_fold(app: Node) -> void:
	SafeArea.simulate(Rect2(252, 0, 2034 - 252, 1398 - 63))
	root.size = Vector2i(2034, 1398)
	SafeArea.poll(self)
	await _settle()
	var outer := root.content_scale_factor
	SafeArea.simulate(Rect2(252, 0, 2853 - 252, 2007 - 60))
	root.size = Vector2i(2853, 2007)
	await _settle()
	var inner := root.content_scale_factor
	_check(outer < inner and inner < 1.0, "Opening the Duo moves the root scale with the window (%.3f to %.3f)" % [outer, inner])
	_same_rect(app.ui.get_global_rect(), SafeArea.rect(root), "Main follows the unfolded safe area")

func _check_inside(node: Node, safe: Rect2, context: String) -> void:
	if node is Control and node.is_visible_in_tree() and (node is Button or node is Label or node is PanelContainer) and not _scrolled(node):
		_check(safe.grow(0.5).encloses((node as Control).get_global_rect()), "%s: %s is inside the safe area" % [context, node.name])
	for child: Node in node.get_children():
		_check_inside(child, safe, context)

func _scrolled(control: Control) -> bool:
	var ancestor := control.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer: return true
		ancestor = ancestor.get_parent()
	return false
