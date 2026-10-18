extends SceneTree
## Display cutouts: backdrops bleed to every screen edge, content stays safe.
## A phone in landscape has its camera hole on the left or the right edge; the
## owner's S24 Ultra showed a lighter strip there because the What's new dim
## stopped at the safe edge. SafeArea.simulate drives every screen on desktop.

const Main = preload("res://main.gd")
const Storage = preload("res://services/local_save.gd")
const SafeArea = preload("res://presentation/safe_area.gd")
const InGameModal = preload("res://presentation/in_game_modal.gd")

## The owner's screenshot: 66 px of 1600x738 at the cutout edge.
const SCREEN := Vector2i(1600, 738)
const INSET := 66.0

class FakeFriends extends "res://services/friends_client.gd":
	func context() -> Dictionary: return {"base_url": "https://cutout.invalid", "player_id": "CUTOUTCUTOUTCUTOUTCUT1"}
	func refresh(_manual: bool = false) -> bool: return false

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

func _frames(count: int = 3) -> void:
	for i in range(count): await process_frame

func _run() -> void:
	var original := {"size": root.size, "content_scale_size": root.content_scale_size, "content_scale_mode": root.content_scale_mode, "content_scale_aspect": root.content_scale_aspect}
	# The project's phone stretch at the owner's screen size.
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	root.size = SCREEN
	await _frames()
	_test_rect_and_pad()
	_test_export_preset()
	await _test_bleed_follows_ancestors()
	await _test_watch()
	await _test_screens()
	SafeArea.simulate(Rect2())
	for property: String in original: root.set(property, original[property])
	await _frames()
	print("AFTER YOU CUTOUT FULL BLEED: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

## Left, right and no cutout through the shared rect; the hook clears.
func _test_rect_and_pad() -> void:
	var visible := root.get_visible_rect()
	SafeArea.simulate(Rect2())
	_check(SafeArea.applies() == false, "A desktop window without a simulated cutout uses the full viewport")
	_same_rect(SafeArea.rect(root), visible, "No cutout: the safe rect is the visible rect")
	var transform := root.get_screen_transform()
	var native := transform * visible
	for side: String in ["left", "right"]:
		var inset := Rect2(native.position + Vector2(INSET if side == "left" else 0.0, 0), native.size - Vector2(INSET, 0))
		SafeArea.simulate(inset)
		var safe := SafeArea.rect(root)
		_check(SafeArea.applies(), "A simulated cutout applies on desktop")
		_same_rect(transform * safe, inset, "The %s cutout maps back to its native rectangle" % side)
	SafeArea.simulate(Rect2())
	_same_rect(SafeArea.rect(root), visible, "Clearing the simulation restores the full viewport")
	var margin := MarginContainer.new()
	SafeArea.pad(margin, Rect2(0, 0, 1000, 600), Rect2(60, 10, 900, 570), 20, 24, 20, 12)
	_check(margin.get_theme_constant("margin_left") == 80 and margin.get_theme_constant("margin_top") == 34 and margin.get_theme_constant("margin_right") == 60 and margin.get_theme_constant("margin_bottom") == 32, "pad adds each safe inset to the screen's own spacing")
	margin.free()

## Android draws under the landscape camera hole on every OS version.
func _test_export_preset() -> void:
	var presets := ConfigFile.new()
	_check(presets.load("res://export_presets.cfg") == OK, "The export presets load")
	var found := false
	for section: String in presets.get_sections():
		if section.ends_with(".options") or str(presets.get_value(section, "platform", "")) != "Android": continue
		var attributes: Variant = presets.get_value(section + ".options", "gradle_build/custom_theme_attributes", {})
		found = attributes is Dictionary and attributes.get("android:windowLayoutInDisplayCutoutMode") == "shortEdges" and attributes.get("[splash]android:windowLayoutInDisplayCutoutMode") == "shortEdges"
	_check(found, "The Android preset lets the window draw into short-edge cutouts in both themes")

## A backdrop under an inset parent keeps covering the viewport when the inset
## grows, swaps sides at the same width (a 180 degree flip) or disappears, and its
## helper lets go of the ancestors when the backdrop is freed.
func _test_bleed_follows_ancestors() -> void:
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var inset := Control.new()
	inset.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(inset)
	var page := Control.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inset.add_child(page)
	var shade := ColorRect.new()
	SafeArea.bleed(shade)
	SafeArea.bleed(shade)
	page.add_child(shade)
	_check(shade.get_children(true).size() == 1, "Bleeding twice adds one helper")
	var visible := root.get_visible_rect()
	for offsets: Vector4 in [Vector4(64, 0, 0, 0), Vector4(0, 0, -64, 0), Vector4(48, 12, -30, -20), Vector4.ZERO]:
		inset.offset_left = offsets.x
		inset.offset_top = offsets.y
		inset.offset_right = offsets.z
		inset.offset_bottom = offsets.w
		_same_rect(shade.get_global_rect(), visible, "The backdrop refits at once for parent offsets %s" % offsets)
	var connections := inset.item_rect_changed.get_connections().size()
	shade.free()
	_check(inset.item_rect_changed.get_connections().size() == connections - 1 and page.item_rect_changed.get_connections().is_empty(), "A freed backdrop leaves no connection on its ancestors")
	layer.free()

## A screen's watcher relays out on a size change and on returning to the foreground.
func _test_watch() -> void:
	var calls := [0]
	var screen := Node.new()
	SafeArea.watch(screen, func() -> void: calls[0] += 1)
	SafeArea.watch(screen, func() -> void: calls[0] += 1)
	root.add_child(screen)
	_check(screen.get_children(true).size() == 1, "Watching twice keeps one watcher")
	root.size_changed.emit()
	_check(calls[0] == 1, "A viewport size change relays out the screen")
	screen.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await process_frame
	_check(calls[0] == 2, "Returning to the foreground relays out the screen (a cutout can move without a resize)")
	screen.free()
	root.size_changed.emit()
	_check(calls[0] == 2, "A freed screen is not called again")

func _test_screens() -> void:
	var path := "user://cutout-full-bleed-" + Crypto.new().generate_random_bytes(8).hex_encode() + ".json"
	var app := Main.new()
	app.saves = Storage.new(path)
	app.saves.data.settings.sound = false
	app.saves.flush()
	root.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	await _frames()
	var visible := root.get_visible_rect()
	for side: String in ["left", "right", "none"]:
		var native := Rect2(Vector2.ZERO, Vector2(SCREEN))
		if side == "left": native = Rect2(INSET, 0, SCREEN.x - INSET, SCREEN.y)
		elif side == "right": native = Rect2(0, 0, SCREEN.x - INSET, SCREEN.y)
		SafeArea.simulate(native)
		# Rotation or multi-window: the viewport reports a change and every screen relays out.
		root.size_changed.emit()
		await _frames()
		var safe := SafeArea.rect(root)
		if side != "none":
			_check(safe.size.x < visible.size.x - 50.0 and (safe.position.x > 50.0) == (side == "left"), "The %s cutout insets the safe rect on that edge" % side)
		_same_rect(app.ui.get_global_rect(), safe, "Main's content root follows the %s cutout" % side)
		await _check_home(app, safe, visible, side)
		await _check_whats_new(app, safe, visible, side)
		await _check_settings(app, safe, visible, side)
		await _check_room_hub(app, safe, visible, side)
		await _check_friends(app, safe, visible, side)
		app._show_home()
		await _frames()
	app.queue_free()
	await _frames()
	for suffix: String in ["", ".tmp", ".backup"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)

func _check_home(app: Node, safe: Rect2, visible: Rect2, side: String) -> void:
	app._show_home()
	await _frames()
	_check_content(app.overlay, safe, "Home (%s)" % side)
	var stage: Control = app.home_stage_view
	if is_instance_valid(stage) and is_instance_valid(stage._menu_backing):
		var backing: Rect2 = stage._menu_backing.get_global_rect()
		_check(is_equal_approx(backing.position.x, visible.position.x) and is_equal_approx(backing.position.y, visible.position.y) and is_equal_approx(backing.size.y, visible.size.y), "Home's menu backing starts at the screen edge, under a %s cutout too" % side)

func _check_whats_new(app: Node, safe: Rect2, visible: Rect2, side: String) -> void:
	app._open_whats_new_card()
	await _frames()
	var modal: Control = app._whats_new_card
	_check(is_instance_valid(modal), "What's new opens from Home (%s)" % side)
	if not is_instance_valid(modal): return
	_check_scrim(modal, visible, "What's new (%s)" % side)
	_check_content(modal, safe, "What's new (%s)" % side)
	modal.close(false)
	await _frames()

func _check_settings(app: Node, safe: Rect2, visible: Rect2, side: String) -> void:
	app.settings_flow.show_settings()
	await _frames()
	var backdrop: Control = app.overlay.find_child("SettingsBackdrop", true, false)
	_check(backdrop != null, "Settings has its page backdrop (%s)" % side)
	if backdrop != null: _same_rect(backdrop.get_global_rect(), visible, "Settings colours the whole screen (%s)" % side)
	_check_content(app.overlay, safe, "Settings (%s)" % side)

func _check_room_hub(app: Node, safe: Rect2, visible: Rect2, side: String) -> void:
	app._show_home()
	await _frames()
	app.room_hub_flow.open_hub("", false)
	await _frames(4)
	var screen: CanvasLayer = app.room_hub_flow.screen
	_check(is_instance_valid(screen), "The room hub opens (%s)" % side)
	if not is_instance_valid(screen): return
	_check_page(screen._root, screen._margin, safe, visible, "Room hub (%s)" % side)
	app.room_hub_flow.drop()
	app.ui.visible = true
	await _frames()

func _check_friends(app: Node, safe: Rect2, visible: Rect2, side: String) -> void:
	app._show_home()
	await _frames()
	app.friends_client = FakeFriends.new(app.api, app._relay_identity)
	app.friends_flow.open(true)
	await _frames(4)
	var screen: CanvasLayer = app.friends_flow.screen
	_check(is_instance_valid(screen), "Friends opens (%s)" % side)
	if not is_instance_valid(screen): return
	_check_page(screen._root, screen._margin, safe, visible, "Friends (%s)" % side)
	app.mode = "home"
	app.friends_flow.close()
	app.ui.visible = true
	await _frames()

## A standalone page: its background reaches every edge, its content margin is
## the safe rect, and nothing it shows reaches into the cutout.
func _check_page(page_root: Control, margin: MarginContainer, safe: Rect2, visible: Rect2, context: String) -> void:
	var background: ColorRect = null
	for child: Node in page_root.get_children():
		if child is ColorRect:
			background = child
			break
	_check(background != null, context + " has a page background")
	if background != null: _same_rect(background.get_global_rect(), visible, context + " background reaches every screen edge")
	_check(safe.encloses(margin.get_global_rect().grow_individual(-float(margin.get_theme_constant("margin_left")), -float(margin.get_theme_constant("margin_top")), -float(margin.get_theme_constant("margin_right")), -float(margin.get_theme_constant("margin_bottom")))), context + " content margin keeps inside the safe rect")
	_check_content(margin, safe, context)

## Every dimming scrim in a modal covers the visible viewport.
func _check_scrim(modal: Control, visible: Rect2, context: String) -> void:
	var scrims := 0
	for child: Node in modal.get_children():
		if child is ColorRect:
			scrims += 1
			_same_rect((child as ColorRect).get_global_rect(), visible, context + " dim covers the whole screen, the cutout too")
	_check(scrims == 1, context + " has one dimming scrim")

## Buttons and text that are drawn stay inside the safe rect (clipped scroll
## content counts by its visible part).
func _check_content(node: Node, safe: Rect2, context: String) -> void:
	var seen := [0]
	_walk_content(node, safe, context, seen)
	_check(seen[0] > 0, context + " shows buttons or text")

func _walk_content(node: Node, safe: Rect2, context: String, seen: Array) -> void:
	if node is CanvasItem and not (node as CanvasItem).visible: return
	if (node is Button or node is Label) and (node as Control).is_visible_in_tree():
		var drawn := _drawn_rect(node)
		if drawn.has_area():
			seen[0] += 1
			_check(safe.grow(0.5).encloses(drawn), "%s: %s '%s' stays inside the safe rect (%s in %s)" % [context, node.get_class(), _text(node), drawn, safe])
	for child: Node in node.get_children():
		_walk_content(child, safe, context, seen)

func _text(node: Node) -> String:
	var value := str(node.get("text"))
	return value if not value.is_empty() else str(node.name)

func _drawn_rect(control: Control) -> Rect2:
	var result := control.get_global_rect()
	var ancestor := control.get_parent()
	while ancestor != null:
		if ancestor is Control and ancestor.clip_contents: result = result.intersection(ancestor.get_global_rect())
		ancestor = ancestor.get_parent()
	return result
