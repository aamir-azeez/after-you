extends Control
const StaticBatch = preload("res://presentation/kit/static_batch.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
## Home-only presentation. No simulation, recordings, persistence or account I/O.
const CameraExploration = preload("res://presentation/camera_exploration.gd")
const KeepsakeDisplay = preload("res://presentation/home_keepsake_display.gd")
const KeepsakeCatalog = preload("res://services/home_keepsake_catalog.gd")
const SpiritVisual = preload("res://presentation/spirit_visual.gd")
const Joystick = preload("res://presentation/joystick.gd")
## Explore mode: the gold spirit walks the islands with the joystick and the
## camera follows it, closer in. Presentation only; nothing is saved.
const EXPLORE_SIZE := 9.5
const EXPLORE_SPEED := 2.2
## Walking this close to a keepsake (times its size) names it in the box.
const EXPLORE_NOTICE := 1.15
## The Home bridge rests lowered. Exploring raises it once the spirit walks
## within BRIDGE_NOTICE of it and lets it down past BRIDGE_RELEASE, so it never
## flickers at one distance and is never lowered under the spirit.
const BRIDGE_NOTICE := 1.0
const BRIDGE_RELEASE := 1.6
## Keepsake box rows: the browser, a status line and the count (same height in every state).
const BROWSER_HEIGHT := 50.0
const BOX_ROW_GAP := 4.0
const PAGE_FILL := Color("2f5d52")
const PAGE_BORDER := Color("466e63")
const PAGE_CHEVRON := Color("eceddb")
const PAGE_CHEVRON_HEIGHT := 22.0
const VARIANT_ICON := 22.0
const SOLO_ICON = preload("res://assets/ui/social/user.svg")
const TOGETHER_ICON = preload("res://assets/ui/social/users.svg")
## Variant icons light up in the spirits' colours once that variant is done.
const SOLO_LIT := Color("f4c38d")
const TOGETHER_LIT := Color("91d6c6")
const VARIANT_DIM := Color(0.71, 0.84, 0.78, 0.32)
const DEFAULT_SIZE := 15.7
const MIN_SIZE := 8.0
const MAX_SIZE := 25.0
const WALK_SPEED := 0.52
const SEPARATION := 0.92
# A tap is a short, nearly still press near a spirit; anything else stays a gesture.
const TAP_RADIUS := 56.0
const TAP_SLOP := 18.0
const TAP_MAX_MSEC := 450
const MOUSE_TAP := -2
# Menus and chapter scenes are transient; this view lasts only this app session.
static var _retained_view: Dictionary = {}
var zoom_target := DEFAULT_SIZE
var zoom_size := DEFAULT_SIZE
var _world: Node3D
var _active: Callable
var _terrain: Node3D
var _camera: Camera3D
var _actors: Dictionary = {}
var _saved: Dictionary = {}
var _goals: Dictionary = {}
var _rests: Dictionary = {}
var _floor := Rect2()
var _camera_transform := Transform3D.IDENTITY
var _camera_size := DEFAULT_SIZE
var _camera_offsets := Vector2.ZERO
var _exploration := CameraExploration.new()
var _touches: Dictionary:
	get: return _exploration.touches
var _pinch_span: float:
	get: return _exploration.pinch_span
var _foreground := true
var _random := RandomNumberGenerator.new()
var _reset: Button
var _header_actions: Array[Control] = []
var _hint: Label
var _keepsakes: Array[Dictionary] = []
var _keepsake_display: Node3D
var _keepsake_controls: Control
var _keepsake_title: Label
## Previous / next paging. Hidden while exploring: the camera follows the spirit
## there, and walking up to a keepsake names it instead.
var _page_buttons: Array[Button] = []
## Person / two-person icons for the selected keepsake, lit for each variant done.
var _keepsake_variant_icons: HBoxContainer
var _hidden_props: Array[Dictionary] = []
var _menu_backing: TextureRect
## Centred panel holding only keepsake content, the same height in every state:
## a browser over every island slot (title and variant icons), a line saying
## what the selected keepsake still needs, and the collection count. The
## keepsakes themselves stand on the island (home_keepsake_display.gd).
var _keepsake_box: PanelContainer
var _keepsake_content: VBoxContainer
var _keepsake_count: Label
var _keepsake_status: Label
var _tap: Dictionary = {}
var _exploring := false
var _explore_button: Button
var _explore_back: Button
var _stick: Control
var _explore_focus := Vector3.ZERO
var _explore_hidden: Array[CanvasItem] = []
var _explore_return: Dictionary = {}
var _greeting_left := 0.0

func configure(world: Node3D, active: Callable, keepsakes: Array[Dictionary] = []) -> void:
	_world = world
	_active = active
	_keepsakes = keepsakes.duplicate(true)

func set_keepsakes(items: Array[Dictionary]) -> void:
	if _keepsakes == items: return
	_keepsakes = items.duplicate(true)
	if not is_inside_tree() or not is_instance_valid(_terrain): return
	if not is_instance_valid(_keepsake_display): _create_keepsake_display()
	else: _keepsake_display.set_items(_keepsakes)
	_update_keepsake_labels()
	_layout()

func set_header_actions(actions: Array[Control]) -> void:
	_header_actions = actions.duplicate()
	_layout()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_exploration.manual = true
	_exploration.auto_return = false
	_exploration.minimum_zoom = MIN_SIZE / DEFAULT_SIZE
	_exploration.maximum_zoom = MAX_SIZE / DEFAULT_SIZE
	_exploration.maximum_pan = Vector2(0.20, 0.18)
	_exploration.allowed = _allowed
	add_child(_exploration)
	if not is_instance_valid(_world) or not is_instance_valid(_world.camera):
		return
	var retained: Dictionary = _retained_view
	zoom_target = float(retained.get("zoom_target", DEFAULT_SIZE))
	zoom_size = float(retained.get("zoom_size", zoom_target))
	_exploration.zoom_ratio = zoom_target / DEFAULT_SIZE
	_exploration.pan = retained.get("pan", Vector2.ZERO)
	_terrain = _world.terrain
	_camera = _world.camera
	_camera_transform = _world.camera.global_transform
	_camera_size = _world.camera.size
	_camera_offsets = Vector2(_world.camera.h_offset,_world.camera.v_offset)
	_random.seed = 64107
	var bounds: Array = _world.current_level.get("bounds",[-560,-290,560,290])
	var gap: Array = _world.current_level.get("gap",[-100,100])
	_floor = Rect2(float(bounds[0])/100.0+0.65,float(bounds[1])/100.0+0.85,
		float(gap[0]-bounds[0])/100.0-1.3,float(bounds[3]-bounds[1])/100.0-1.7)
	if _floor.size.x<2.0 or _floor.size.y<2.0:
		return
	for role: String in _world.actors:
		var actor: Node3D = _world.actors[role]
		_actors[role] = actor
		_saved[role] = {"position":actor.position,"target":_world.actor_targets[role],"visible":actor.visible}
		var center := _floor.get_center()
		var offset := Vector2(-0.68,0.42) if _actors.size()==1 else Vector2(0.68,-0.42)
		actor.position = Vector3(center.x+offset.x,0,center.y+offset.y)
		actor.visible = true
		actor.reset_motion()
		_world.actor_targets[role] = actor.position
		_goals[role] = actor.position
		_rests[role] = 0.7 if _actors.size()==1 else 1.4
	_world.home_presentation_owner = get_instance_id()
	_create_text_backing()
	_reset = Button.new()
	_reset.text = "Reset view"
	_reset.custom_minimum_size = Vector2(116,36)
	_reset.add_theme_font_size_override("font_size",16)
	_reset.pressed.connect(_reset_view)
	add_child(_reset)
	_hint = Label.new()
	_hint.text = PlayerCopy.HOME_STAGE_88876AC2DD42 if OS.has_feature("android") else PlayerCopy.HOME_STAGE_CA9AEFEB7961
	_hint.name = "HomeGestureHint"
	_hint.add_theme_font_size_override("font_size",16)
	_hint.add_theme_color_override("font_color",Color("a6c6b8"))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint)
	_create_keepsake_box()
	_create_explore_controls()
	_create_keepsake_display()
	# The island's static geometry draws as a few batches (kit/static_batch.gd);
	# everything the world, this stage or Main moves, hides or recolours stays
	# its own node.
	StaticBatch.fold(_terrain, [_world, self, get_tree().current_scene])
	_layout()
	_frame_camera()

func _stage_rect() -> Rect2:
	var rect := get_global_rect()
	# Exploring hides the menu, so the whole screen is the stage.
	if _exploring: return Rect2(rect.position + Vector2(24, 40), Vector2(maxf(100, rect.size.x - 48), maxf(100, rect.size.y - 138)))
	var left := minf(470.0,rect.size.x*0.52)
	return Rect2(rect.position+Vector2(left,40),Vector2(maxf(100,rect.size.x-left-24),maxf(100,rect.size.y-138)))

func _create_text_backing() -> void:
	# The camera can bring bright terrain beneath the fixed menu and captions.
	# Fade in a quiet backdrop as the player explores, without blocking gestures.
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.82, 1.0])
	gradient.colors = PackedColorArray([Color("123c3c"), Color("123c3c"), Color(0.07,0.24,0.24,0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2.ZERO
	texture.fill_to = Vector2.RIGHT
	_menu_backing = TextureRect.new()
	_menu_backing.texture = texture
	_menu_backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_menu_backing)

func _layout() -> void:
	if not is_instance_valid(_reset): return
	var rect := _stage_rect()
	_menu_backing.position = Vector2.ZERO
	_menu_backing.size = Vector2(rect.position.x-global_position.x+80, size.y)
	var backing_strength := clampf(maxf((DEFAULT_SIZE-zoom_size)/(DEFAULT_SIZE-MIN_SIZE)*2.0,_exploration.pan.length()*10.0),0,1)
	_menu_backing.modulate.a = backing_strength
	_reset.position = rect.position-global_position+Vector2(rect.size.x-116,0)
	_reset.size = Vector2(116,36)
	for action: Control in _header_actions:
		if not is_instance_valid(action) or not action.is_visible_in_tree(): continue
		var header := action.get_global_rect()
		if _reset.get_global_rect().intersects(header.grow(12)):
			_reset.position = Vector2(header.end.x-116,maxf(rect.position.y,header.end.y+12))-global_position
	# The gesture hint sits in the footer band (the bottom 64 units), right-aligned;
	# the keepsake box always ends above that band.
	var band_left := rect.position.x-global_position.x
	_hint.position = Vector2(band_left, size.y-64)
	_hint.size = Vector2(maxf(1, size.x-30-band_left), 50)
	_reset.visible = not _exploring and (not is_equal_approx(zoom_target,DEFAULT_SIZE) or not _exploration.pan.is_zero_approx())
	_hint.visible = not _exploring
	if is_instance_valid(_explore_button):
		_explore_button.position = rect.position-global_position
		_explore_back.position = Vector2(24, 24)
		_stick.position = Vector2(24, size.y-_stick.size.y-24)
	if is_instance_valid(_keepsake_box):
		var width := clampf(rect.size.x-24, 300, 500)
		var inner := width-28
		_keepsake_controls.custom_minimum_size = Vector2(inner, BROWSER_HEIGHT)
		_keepsake_controls.get_child(0).position = Vector2.ZERO
		_keepsake_controls.get_child(0).size = Vector2(52, BROWSER_HEIGHT)
		_keepsake_controls.get_child(2).position = Vector2(inner-52, 0)
		_keepsake_controls.get_child(2).size = Vector2(52, BROWSER_HEIGHT)
		_place_keepsake_heading(inner)
		_keepsake_count.custom_minimum_size.x = inner
		_keepsake_status.custom_minimum_size.x = inner
		# One box height for every state: the browser, the tallest status line
		# (which may wrap) and the count.
		var count_height := _keepsake_count.get_combined_minimum_size().y
		var status_font := _keepsake_status.get_theme_font("font")
		var status_height := 0.0
		for line: String in STATUS_LINES:
			status_height = maxf(status_height, status_font.get_multiline_string_size(line, HORIZONTAL_ALIGNMENT_CENTER, inner, _keepsake_status.get_theme_font_size("font_size")).y)
		_keepsake_status.custom_minimum_size.y = ceilf(status_height)
		_keepsake_content.custom_minimum_size.y = ceilf(BROWSER_HEIGHT + status_height + count_height + BOX_ROW_GAP * 2.0)
		var height := _keepsake_box.get_combined_minimum_size().y
		_keepsake_box.size = Vector2(width, height)
		# Low in the stage, just above the hint band, so it covers as little island as possible.
		_keepsake_box.position = Vector2(rect.get_center().x-global_position.x-width*0.5, size.y-70-height)

## Centres the selected keepsake's title and its variant icons as one group between
## the paging buttons; a title too long for one line wraps beside the icons.
func _place_keepsake_heading(inner: float) -> void:
	var area := maxf(1, inner-120)
	var icons := 0
	for icon: Control in _keepsake_variant_icons.get_children():
		if icon.visible: icons += 1
	var icons_width := icons * VARIANT_ICON + maxi(0, icons-1) * _keepsake_variant_icons.get_theme_constant("separation")
	var gap := 8.0 if icons > 0 else 0.0
	var font := _keepsake_title.get_theme_font("font")
	var text_width := ceilf(font.get_string_size(_keepsake_title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, _keepsake_title.get_theme_font_size("font_size")).x) + 2.0
	var title_width := minf(text_width, area-icons_width-gap)
	var start := 60.0 + (area-(title_width+gap+icons_width))*0.5
	_keepsake_title.position = Vector2(start, 0)
	_keepsake_title.size = Vector2(maxf(1, title_width), BROWSER_HEIGHT)
	_keepsake_variant_icons.position = Vector2(start+title_width+gap, (BROWSER_HEIGHT-VARIANT_ICON)*0.5)
	_keepsake_variant_icons.size = Vector2(icons_width, VARIANT_ICON)

func _create_keepsake_display() -> void:
	if not is_instance_valid(_terrain): return
	_keepsake_display = KeepsakeDisplay.new()
	_terrain.add_child(_keepsake_display)
	_keepsake_display.configure(_world, _keepsakes)
	for prop: Variant in [_world.garden, _world.goal_ring, _world.seed, _world.landing_marker, _world.keepsake_landmark]:
		if is_instance_valid(prop):
			_hidden_props.append({"node":prop,"visible":prop.visible})
			prop.visible = false
	_update_keepsake_labels()

func _create_keepsake_box() -> void:
	_keepsake_box = PanelContainer.new()
	_keepsake_box.name = "KeepsakeBox"
	# The panel itself passes presses on to the stage; _allowed keeps them from
	# starting a camera gesture, and its buttons still take their own taps.
	_keepsake_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055,0.19,0.20,0.96)
	style.set_corner_radius_all(16)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	_keepsake_box.add_theme_stylebox_override("panel", style)
	add_child(_keepsake_box)
	_keepsake_content = VBoxContainer.new()
	_keepsake_content.name = "KeepsakeContent"
	_keepsake_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_keepsake_content.alignment = BoxContainer.ALIGNMENT_CENTER
	_keepsake_content.add_theme_constant_override("separation", int(BOX_ROW_GAP))
	_keepsake_box.add_child(_keepsake_content)
	# Slot browser. Explicit bounds avoid wrapped-label minimum height feeding back
	# through a container before its first width is assigned by the home layout.
	_keepsake_controls = Control.new()
	_keepsake_controls.name = "KeepsakeBrowser"
	_keepsake_controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_keepsake_content.add_child(_keepsake_controls)
	for offset: int in [-1, 1]:
		var button := _page_button(offset)
		_keepsake_controls.add_child(button)
		_page_buttons.append(button)
		if offset < 0:
			_keepsake_title = Label.new()
			_keepsake_title.name = "KeepsakeTitle"
			_keepsake_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_keepsake_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			_keepsake_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_keepsake_title.clip_text = true
			_keepsake_title.max_lines_visible = 2
			_keepsake_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_keepsake_title.add_theme_font_size_override("font_size", 18)
			_keepsake_title.add_theme_color_override("font_color", Color("eceddb"))
			_keepsake_controls.add_child(_keepsake_title)
	_keepsake_variant_icons = HBoxContainer.new()
	_keepsake_variant_icons.name = "KeepsakeVariants"
	_keepsake_variant_icons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_keepsake_variant_icons.add_theme_constant_override("separation", 4)
	_keepsake_controls.add_child(_keepsake_variant_icons)
	for variant: Array in [["KeepsakeSolo", SOLO_ICON, "Solo"], ["KeepsakeTogether", TOGETHER_ICON, "With a friend"]]:
		var icon := TextureRect.new()
		icon.name = variant[0]
		icon.texture = variant[1]
		icon.tooltip_text = variant[2]
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		icon.custom_minimum_size = Vector2(VARIANT_ICON, VARIANT_ICON)
		icon.self_modulate = VARIANT_DIM
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_keepsake_variant_icons.add_child(icon)
	_keepsake_status = _box_label(15, Color("a6c6b8"), _keepsake_content)
	_keepsake_status.name = "KeepsakeStatus"
	_keepsake_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_keepsake_count = _box_label(18, Color("eceddb"), _keepsake_content)
	_keepsake_count.name = "KeepsakeCount"
	_update_keepsake_labels()

## Secondary-style paging button with a drawn chevron; the 52x50 button is the hit area.
func _page_button(offset: int) -> Button:
	var button := Button.new()
	button.name = "KeepsakePrevious" if offset < 0 else "KeepsakeNext"
	button.tooltip_text = "Previous keepsake" if offset < 0 else "Next keepsake"
	button.accessibility_name = button.tooltip_text
	button.custom_minimum_size = Vector2(52, BROWSER_HEIGHT)
	var fills := {"normal": PAGE_FILL, "hover": Color("3a6b5f"), "pressed": Color("4a7c6f"), "hover_pressed": Color("4a7c6f"), "disabled": PAGE_FILL}
	for state: String in fills:
		var style := StyleBoxFlat.new()
		style.bg_color = fills[state]
		style.border_color = PAGE_BORDER
		style.set_border_width_all(1)
		style.set_corner_radius_all(14)
		button.add_theme_stylebox_override(state, style)
	var ring := StyleBoxFlat.new()
	ring.bg_color = Color.TRANSPARENT
	ring.border_color = Color("a6d9c4")
	ring.set_border_width_all(2)
	ring.set_corner_radius_all(14)
	button.add_theme_stylebox_override("focus", ring)
	button.draw.connect(func():
		var middle := button.size * 0.5
		var half := PAGE_CHEVRON_HEIGHT * 0.5
		var reach := half * 0.55 * float(offset)
		button.draw_polyline(PackedVector2Array([
			middle + Vector2(-reach * 0.5, -half),
			middle + Vector2(reach * 0.5, 0),
			middle + Vector2(-reach * 0.5, half)]), PAGE_CHEVRON, 3.0, true))
	button.pressed.connect(func():
		if not is_instance_valid(_keepsake_display): return
		_keepsake_display.select_offset(offset)
		_update_keepsake_labels())
	return button

func _box_label(font_size: int, color: Color, parent: Node) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

## Every line the status row can show, for one box height in every state.
const STATUS_LINES := [PlayerCopy.KEEPSAKE_TEASER, PlayerCopy.KEEPSAKE_TEASER_SOLO_ONLY, PlayerCopy.KEEPSAKE_NEEDS_FRIEND, PlayerCopy.KEEPSAKE_NEEDS_SOLO, PlayerCopy.KEEPSAKE_FINISHED, PlayerCopy.KEEPSAKE_FINISHED_SOLO]

## What the selected keepsake still needs, or that it is finished.
static func status_line(item: Dictionary) -> String:
	var together: bool = item.get("friend_available", true)
	match str(item.get("state", "none")):
		"complete": return PlayerCopy.KEEPSAKE_FINISHED if together else PlayerCopy.KEEPSAKE_FINISHED_SOLO
		"solo": return PlayerCopy.KEEPSAKE_NEEDS_FRIEND
		"friend": return PlayerCopy.KEEPSAKE_NEEDS_SOLO
	return PlayerCopy.KEEPSAKE_TEASER if together else PlayerCopy.KEEPSAKE_TEASER_SOLO_ONLY

func _update_keepsake_labels() -> void:
	if not is_instance_valid(_keepsake_box): return
	var item: Dictionary = _keepsake_display.selected_item() if is_instance_valid(_keepsake_display) else {}
	# Progress counts variants (solo, and together where it exists), not places.
	var total := KeepsakeCatalog.variant_total()
	var earned := mini(KeepsakeCatalog.variant_count(_keepsakes), total)
	_keepsake_controls.visible = not item.is_empty()
	_keepsake_count.text = "Keepsakes · %d / %d" % [earned, total]
	_keepsake_status.text = status_line(item) if not item.is_empty() else PlayerCopy.KEEPSAKE_TEASER
	if item.is_empty(): return
	_keepsake_title.text = str(item.title)
	var solo: TextureRect = _keepsake_variant_icons.get_child(0)
	var together: TextureRect = _keepsake_variant_icons.get_child(1)
	solo.self_modulate = SOLO_LIT if item.get("solo", false) else VARIANT_DIM
	together.visible = item.get("friend_available", true)
	together.self_modulate = TOGETHER_LIT if item.get("friend", false) else VARIANT_DIM
	if _keepsake_controls.custom_minimum_size.x > 0:
		_place_keepsake_heading(_keepsake_controls.custom_minimum_size.x)

func _is_active() -> bool:
	return is_inside_tree() and is_visible_in_tree() and _foreground and is_instance_valid(_world) and _world.visible and _world.home_view and _world.terrain==_terrain and _world.home_presentation_owner==get_instance_id() and _active.is_valid() and _active.call()

func _allowed(point: Vector2) -> bool:
	for action: Control in _header_actions:
		if is_instance_valid(action) and action.is_visible_in_tree() and action.get_global_rect().has_point(point): return false
	if is_instance_valid(_keepsake_box) and _keepsake_box.visible and _keepsake_box.get_global_rect().has_point(point): return false
	for control: Control in [_explore_button, _explore_back, _stick]:
		if is_instance_valid(control) and control.is_visible_in_tree() and control.get_global_rect().has_point(point): return false
	return _stage_rect().has_point(point) and not (is_instance_valid(_reset) and _reset.visible and _reset.get_global_rect().has_point(point))

func _input(event: InputEvent) -> void:
	if not _is_active():
		_cancel_gesture()
		return
	_track_tap(event)
	# While exploring the camera follows the spirit, so gestures do not move it.
	if _exploring: return
	_exploration.zoom_ratio = zoom_target / DEFAULT_SIZE
	if _exploration.handle_event(event): get_viewport().set_input_as_handled()
	_sync_zoom()

func _gui_input(event: InputEvent) -> void:
	if not _is_active(): return
	# Taps begin only here, so menus and dialogs above the stage keep their input.
	if event is InputEventScreenTouch and event.pressed and not event.canceled:
		_begin_tap(event.index, event.position + global_position)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and event.device != CameraExploration.SYNTHETIC_MOUSE:
		_begin_tap(MOUSE_TAP, event.position + global_position)
	# GUI events use local positions; the shared controller takes viewport ones.
	if not _exploring and (event is InputEventMouse or event is InputEventGesture):
		var screen_event := event.duplicate()
		screen_event.position += global_position
		_exploration.zoom_ratio = zoom_target / DEFAULT_SIZE
		if _exploration.handle_event(screen_event): accept_event()
		_sync_zoom()

func _sync_zoom() -> void:
	zoom_target = clampf(_exploration.zoom_ratio * DEFAULT_SIZE, MIN_SIZE, MAX_SIZE)
	if is_equal_approx(zoom_target, MIN_SIZE): zoom_target = MIN_SIZE
	if is_equal_approx(zoom_target, MAX_SIZE): zoom_target = MAX_SIZE

func _zoom(factor: float) -> void:
	_exploration.zoom_ratio = zoom_target / DEFAULT_SIZE
	_exploration.zoom(factor)
	_sync_zoom()

func _cancel_gesture() -> void:
	_exploration.cancel_gesture()
	_tap = {}

func _begin_tap(index: int, point: Vector2) -> void:
	_tap = {}
	if _touches.size() > 1 or not _allowed(point): return
	# Spirits win a tap near them; otherwise a tap near a keepsake selects it.
	var keepsake := ""
	if _greeting_left > 0.0 or not _spirit_near(point):
		if is_instance_valid(_keepsake_display): keepsake = _keepsake_display.pick(_world.camera, point)
		if keepsake.is_empty(): return
	_tap = {"index": index, "start": point, "msec": Time.get_ticks_msec(), "keepsake": keepsake}

func _track_tap(event: InputEvent) -> void:
	# Any second finger, drag, wheel, pan button or long hold turns a tap into a gesture.
	if _tap.is_empty(): return
	var index: int = _tap.index
	if event is InputEventScreenTouch:
		if event.index != index or event.canceled: _tap = {}
		elif not event.pressed: _finish_tap(event.position)
	elif event is InputEventScreenDrag:
		if event.index == index and event.position.distance_to(_tap.start) > TAP_SLOP: _tap = {}
	elif event is InputEventMouse:
		if event.device == CameraExploration.SYNTHETIC_MOUSE: return
		if event is InputEventMouseButton:
			if event.button_index != MOUSE_BUTTON_LEFT or index != MOUSE_TAP: _tap = {}
			elif not event.pressed: _finish_tap(event.position)
		elif index == MOUSE_TAP and event.position.distance_to(_tap.start) > TAP_SLOP: _tap = {}
	elif event is InputEventGesture:
		_tap = {}

func _finish_tap(point: Vector2) -> void:
	var tap := _tap
	_tap = {}
	if point.distance_to(tap.start) <= TAP_SLOP and Time.get_ticks_msec() - int(tap.msec) <= TAP_MAX_MSEC:
		if str(tap.keepsake).is_empty(): _greet()
		else: select_keepsake(str(tap.keepsake))

## Shows a keepsake slot in the box: its name and what it still needs.
func select_keepsake(id: String) -> bool:
	if not is_instance_valid(_keepsake_display) or not _keepsake_display.select_id(id): return false
	_update_keepsake_labels()
	return true

func _greet() -> void:
	# Presentation only: both spirits share the meet greeting, then wander again.
	if _greeting_left > 0.0 or not _is_active() or not _world.greet_home_spirits(): return
	_greeting_left = SpiritVisual.GREETING_DURATION
	for role: String in _rests:
		_rests[role] = maxf(float(_rests[role]), SpiritVisual.GREETING_DURATION)

func _spirit_near(point: Vector2) -> bool:
	# Each spirit projects to a feet-to-crown segment with a generous radius.
	var camera: Camera3D = _world.camera
	if not is_instance_valid(camera): return false
	for role: String in _actors:
		var actor: Node3D = _actors[role]
		if not is_instance_valid(actor) or not actor.is_visible_in_tree(): continue
		var feet := actor.to_global(Vector3(0,0.1,0))
		var crown := actor.to_global(Vector3(0,1.0,0))
		if camera.is_position_behind(feet) or camera.is_position_behind(crown): continue
		var closest := Geometry2D.get_closest_point_to_segment(point,camera.unproject_position(feet),camera.unproject_position(crown))
		if closest.distance_to(point) <= TAP_RADIUS: return true
	return false

func _reset_view() -> void:
	_exploration.reset_view()
	zoom_target = DEFAULT_SIZE

func _process(delta: float) -> void:
	if not _is_active():
		_cancel_gesture()
		return
	var step := clampf(delta,0.0,0.05)
	# Same clock as the spirits' own greeting, so the debounce ends with it.
	_greeting_left = maxf(0.0,_greeting_left-step)
	# Home's own refresh can turn part of the menu back on (the Full Journey
	# offer); it stays hidden until Back.
	if _exploring:
		for node: CanvasItem in _explore_hidden:
			if is_instance_valid(node) and node.visible: node.visible = false
	_layout()
	zoom_size = zoom_target if _world.reduced_motion else lerpf(zoom_size,zoom_target,1.0-exp(-12.0*step))
	_frame_camera()
	_world.update_spirit_attention()
	for role: String in _actors:
		var actor: Node3D = _actors[role]
		var previous := actor.position
		if _exploring and role == "a":
			_walk(actor, step)
		elif not _world.reduced_motion:
			if float(_rests[role])>0:
				_rests[role] = maxf(0,float(_rests[role])-step)
			elif actor.position.distance_to(_goals[role])<0.025:
				_choose_goal(role)
			else:
				var candidate := actor.position.move_toward(_goals[role],WALK_SPEED*step)
				if _clear_position(role,candidate):
					actor.position = candidate
				else:
					_choose_goal(role)
		_world.actor_targets[role] = actor.position
		actor.advance_motion(actor.position-previous,step,_world.reduced_motion)
	_world.finish_spirit_motion()

func _frame_camera() -> void:
	var camera: Camera3D = _world.camera
	var viewport := get_viewport_rect()
	var rect := _stage_rect()
	var zoom := clampf((DEFAULT_SIZE-zoom_size)/(DEFAULT_SIZE-MIN_SIZE),0,1)
	var center := _floor.get_center()
	# Zoom toward the spirits; the keepsakes on the other island are a pan away.
	var focus_target := Vector3(center.x,0.35,center.y)
	var focus := Vector3.ZERO.lerp(focus_target,zoom)
	if _exploring: focus = _explore_focus + Vector3(0, 0.35, 0)
	camera.global_transform = _camera_transform
	camera.global_position += _world.global_basis*focus
	camera.size = zoom_size
	# KEEP_HEIGHT is the existing orthographic camera mode. Offsets place the
	# world in the clear right-side stage at every supported landscape width.
	var units_per_pixel := zoom_size/maxf(viewport.size.y,1)
	var offset := rect.get_center()-viewport.get_center()
	camera.h_offset = -offset.x*units_per_pixel
	camera.v_offset = offset.y*units_per_pixel
	if not _exploring: _exploration.apply_pan(camera, DEFAULT_SIZE)

## The Explore button, and while exploring a Back button and the joystick.
func _create_explore_controls() -> void:
	_explore_button = Button.new()
	_explore_button.name = "HomeExplore"
	_explore_button.text = PlayerCopy.HOME_EXPLORE
	_explore_button.custom_minimum_size = Vector2(124, 48)
	_explore_button.add_theme_font_size_override("font_size", 18)
	_explore_button.pressed.connect(set_exploring.bind(true))
	add_child(_explore_button)
	_explore_back = Button.new()
	_explore_back.name = "HomeExploreBack"
	_explore_back.text = PlayerCopy.HOME_EXPLORE_BACK
	_explore_back.custom_minimum_size = Vector2(116, 48)
	_explore_back.add_theme_font_size_override("font_size", 18)
	_explore_back.pressed.connect(set_exploring.bind(false))
	_explore_back.visible = false
	add_child(_explore_back)
	_stick = Joystick.new()
	_stick.name = "HomeExploreStick"
	_stick.visible = false
	add_child(_stick)
	_stick.size = Vector2(Joystick.HIT_SIZE, Joystick.HIT_SIZE)

func is_exploring() -> bool:
	return _exploring

## The controls that belong to each mode: Explore and the keepsake paging
## arrows outside it, Back and the joystick inside it.
func _show_explore_controls() -> void:
	_stick.visible = _exploring
	_explore_back.visible = _exploring
	_explore_button.visible = not _exploring
	for page: Button in _page_buttons: page.visible = not _exploring

## Switches Home into explore mode and back. The menu and header hide while
## exploring and come back as they were; the gold spirit returns to where it
## started.
func set_exploring(on: bool) -> void:
	if on == _exploring or not _actors.has("a"): return
	var actor: Node3D = _actors.a
	_cancel_gesture()
	_exploring = on
	if on:
		_explore_return = {"position": actor.position, "zoom_target": zoom_target}
		_exploration.reset_view()
		_explore_hidden.clear()
		if get_parent() != null:
			for node: Node in get_parent().get_children():
				if node != self and node is CanvasItem and (node as CanvasItem).visible:
					_explore_hidden.append(node)
					(node as CanvasItem).visible = false
		_explore_focus = actor.position
		zoom_target = EXPLORE_SIZE
	else:
		for node: CanvasItem in _explore_hidden:
			if is_instance_valid(node): node.visible = true
		_explore_hidden.clear()
		actor.position = _explore_return.get("position", actor.position)
		actor.reset_motion()
		_world.actor_targets["a"] = actor.position
		_goals["a"] = actor.position
		zoom_target = float(_explore_return.get("zoom_target", DEFAULT_SIZE))
		_world.home_bridge_raised = false
	_stick.release()
	_show_explore_controls()
	if _world.reduced_motion: zoom_size = zoom_target
	_layout()
	_frame_camera()

## One explore step: the joystick moves the spirit across the screen's ground
## directions, anywhere a Home island or bridge is underfoot and no keepsake
## stands; the camera follows and a keepsake close by is named in the box.
func _walk(actor: Node3D, step: float) -> void:
	var push: Vector2 = _stick.value
	if push.length() > 0.0:
		var across := Vector3(0.832, 0, -0.555)
		var away := Vector3(-0.555, 0, -0.832)
		var move := (across * push.x - away * push.y) * EXPLORE_SPEED * step
		# Straight on, else slide along x or z.
		for attempt in range(3):
			var candidate := actor.position + (move if attempt == 0 else Vector3(move.x, 0, 0) if attempt == 1 else Vector3(0, 0, move.z))
			if _keepsake_display.walkable(candidate):
				actor.position = candidate
				break
	# The bridge rises as the spirit comes near and carries it only once its
	# planks are drawn up (home_keepsake_display.gd).
	var reach := BRIDGE_RELEASE if _world.home_bridge_raised else BRIDGE_NOTICE
	_world.home_bridge_raised = _keepsake_display.near_lowering_crossing(actor.position, reach)
	_explore_focus = actor.position if _world.reduced_motion else _explore_focus.lerp(actor.position, 1.0 - exp(-8.0 * step))
	var near: String = _keepsake_display.nearest(actor.position, EXPLORE_NOTICE)
	if not near.is_empty() and near != str(_keepsake_display.selected_item().get("id", "")): select_keepsake(near)

func _clear_position(role: String, candidate: Vector3) -> bool:
	if not _floor.has_point(Vector2(candidate.x,candidate.z)): return false
	for other: String in _actors:
		if other!=role and candidate.distance_to(_actors[other].position)<SEPARATION:
			return false
	var safe := _stage_rect().grow(-42)
	return safe.has_point(_world.camera.unproject_position(_world.to_global(candidate))) and safe.has_point(_world.camera.unproject_position(_world.to_global(candidate+Vector3(0,1.15,0))))

func _choose_goal(role: String) -> void:
	var actor: Node3D = _actors[role]
	for attempt in range(12):
		var candidate := Vector3(_random.randf_range(_floor.position.x,_floor.end.x),0,_random.randf_range(_floor.position.y,_floor.end.y))
		if actor.position.distance_to(candidate)>0.65 and _clear_position(role,candidate):
			_goals[role] = candidate
			_rests[role] = _random.randf_range(0.6,1.6)
			return
	_goals[role] = actor.position
	_rests[role] = 0.8

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT,NOTIFICATION_APPLICATION_PAUSED]:
		_foreground = false
		_cancel_gesture()
		# A held joystick must not keep walking the spirit after a resume.
		if is_instance_valid(_stick): _stick.release()
	elif what in [NOTIFICATION_APPLICATION_FOCUS_IN,NOTIFICATION_APPLICATION_RESUMED]:
		_foreground = true
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST and _exploring and _is_active():
		# The system Back leaves Explore like the Back button.
		set_exploring(false)

func _exit_tree() -> void:
	_cancel_gesture()
	for node: CanvasItem in _explore_hidden:
		if is_instance_valid(node): node.visible = true
	_explore_hidden.clear()
	if is_instance_valid(_keepsake_display): _keepsake_display.queue_free()
	if not is_instance_valid(_world) or _world.home_presentation_owner!=get_instance_id(): return
	for saved_prop: Dictionary in _hidden_props:
		if is_instance_valid(saved_prop.node): saved_prop.node.visible = saved_prop.visible
	# Keep normalized exploration, never the already-composed camera transform.
	# Leaving mid-Explore keeps the zoom from before it, not the close follow.
	if _exploring:
		var before := float(_explore_return.get("zoom_target", DEFAULT_SIZE))
		_retained_view = {"zoom_target": before, "zoom_size": before, "pan": Vector2.ZERO}
	else:
		_retained_view = {"zoom_target": zoom_target, "zoom_size": zoom_size, "pan": _exploration.pan}
	_world.home_presentation_owner = 0
	_world.home_bridge_raised = false
	# The greeting is Home-only; never carry it into the next screen.
	if _greeting_left > 0.0:
		for role: String in _actors:
			if is_instance_valid(_actors[role]) and _world.actors.get(role)==_actors[role]: _actors[role].end_greeting()
	_greeting_left = 0.0
	# Gameplay can set home_view=false before removing the menu. Its static
	# camera still needs the home-only focus translation and offsets restored.
	if is_instance_valid(_camera) and _world.camera==_camera:
		_camera.global_transform = _camera_transform
		_camera.size = _camera_size
		_camera.h_offset = _camera_offsets.x
		_camera.v_offset = _camera_offsets.y
	if not _world.home_view or _world.terrain!=_terrain: return
	for role: String in _saved:
		if is_instance_valid(_actors[role]) and _world.actors.get(role)==_actors[role]:
			_actors[role].position = _saved[role].position
			_actors[role].visible = _saved[role].visible
			_actors[role].reset_motion()
			_world.actor_targets[role] = _saved[role].target
