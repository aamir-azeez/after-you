extends Control
const PlayerCopy = preload("res://presentation/player_copy.gd")
## Home-only presentation. No simulation, recordings, persistence or account I/O.
const CameraExploration = preload("res://presentation/camera_exploration.gd")
const KeepsakeDisplay = preload("res://presentation/home_keepsake_display.gd")
const KeepsakeCatalog = preload("res://services/home_keepsake_catalog.gd")
const KeepsakeTeaser = preload("res://presentation/keepsake_teaser.gd")
const SpiritVisual = preload("res://presentation/spirit_visual.gd")
const TEASER_LARGE := 4
const TEASER_SMALL := 3
## Keepsake box rows: the browser, then the keepsake strip (same height in every state).
const BROWSER_HEIGHT := 50.0
const STRIP_HEIGHT := 48.0
const STRIP_CELL_LARGE := 48.0
const STRIP_CELL_SMALL := 40.0
const BOX_ROW_GAP := 4.0
const PAGE_FILL := Color("2f5d52")
const PAGE_BORDER := Color("466e63")
const PAGE_CHEVRON := Color("eceddb")
const PAGE_CHEVRON_HEIGHT := 22.0
const VARIANT_ICON := 22.0
const SOLO_ICON = preload("res://assets/ui/social/user.svg")
const TOGETHER_ICON = preload("res://assets/ui/social/users.svg")
const DEFAULT_SIZE := 15.7
const MIN_SIZE := 8.0
const MAX_SIZE := 18.5
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
## Person / two-person icons for the selected keepsake's earned variants, beside its title.
var _keepsake_variant_icons: HBoxContainer
var _hidden_props: Array[Dictionary] = []
var _menu_backing: TextureRect
## Centred panel holding only keepsake content, the same height in every state:
## the earned browser (when anything is earned), a strip of keepsakes (the next
## unearned ones as silhouettes, or recent earned ones once all are earned), the
## collection count, and the invitation line while nothing is earned.
var _keepsake_box: PanelContainer
var _keepsake_content: VBoxContainer
var _keepsake_strip_row: CenterContainer
var _keepsake_strip: TextureRect
var _keepsake_count: Label
var _keepsake_invite: Label
var _teaser_ids := ""
var _tap: Dictionary = {}
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
	_create_keepsake_display()
	_layout()
	_frame_camera()

func _stage_rect() -> Rect2:
	var rect := get_global_rect()
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
	_reset.visible = not is_equal_approx(zoom_target,DEFAULT_SIZE) or not _exploration.pan.is_zero_approx()
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
		_keepsake_invite.custom_minimum_size.x = inner
		# One box height for every state: the taller of browser + strip + count and
		# strip + count + invitation (which may wrap).
		var count_height := _keepsake_count.get_combined_minimum_size().y
		var invite_font := _keepsake_invite.get_theme_font("font")
		var invite_height := invite_font.get_multiline_string_size(_keepsake_invite.text, HORIZONTAL_ALIGNMENT_CENTER, inner, _keepsake_invite.get_theme_font_size("font_size")).y
		_keepsake_content.custom_minimum_size.y = ceilf(maxf(BROWSER_HEIGHT, invite_height) + STRIP_HEIGHT + count_height + BOX_ROW_GAP * 2.0)
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
	if _keepsakes.is_empty() or not is_instance_valid(_terrain): return
	var bounds: Array = _world.current_level.get("bounds", [-560,-290,560,290])
	var gap: Array = _world.current_level.get("gap", [-100,100])
	var center := Vector3(float(gap[1]+bounds[2])/200.0, 0.04, 0)
	_keepsake_display = KeepsakeDisplay.new()
	_terrain.add_child(_keepsake_display)
	_keepsake_display.configure(_world, _keepsakes, center)
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
	# Earned browser. Explicit bounds avoid wrapped-label minimum height feeding back
	# through a container before its first width is assigned by the home layout.
	_keepsake_controls = Control.new()
	_keepsake_controls.name = "KeepsakeBrowser"
	_keepsake_controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_keepsake_content.add_child(_keepsake_controls)
	for offset: int in [-1, 1]:
		var button := _page_button(offset)
		_keepsake_controls.add_child(button)
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
		icon.self_modulate = Color("b5d6c7")
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_keepsake_variant_icons.add_child(icon)
	# One strip row in every state, so the box keeps its height.
	_keepsake_strip_row = CenterContainer.new()
	_keepsake_strip_row.name = "KeepsakeStrip"
	_keepsake_strip_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_keepsake_strip_row.custom_minimum_size.y = STRIP_HEIGHT
	_keepsake_content.add_child(_keepsake_strip_row)
	_keepsake_count = _box_label(18, Color("eceddb"), _keepsake_content)
	_keepsake_count.name = "KeepsakeCount"
	_keepsake_invite = _box_label(15, Color("a6c6b8"), _keepsake_content)
	_keepsake_invite.name = "KeepsakeInvite"
	_keepsake_invite.text = PlayerCopy.KEEPSAKE_TEASER
	_keepsake_invite.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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

## Real catalog keepsakes not yet earned, in the order chapters are played.
func next_unearned(limit: int) -> Array[Dictionary]:
	var earned := {}
	for item: Dictionary in _keepsakes: earned[str(item.get("id",""))] = true
	var ordered: Array[Dictionary] = []
	for chapter: String in KeepsakeCatalog.CHAPTERS:
		for item: Dictionary in KeepsakeCatalog.all():
			if item.chapter_key == chapter: ordered.append(item)
	for item: Dictionary in KeepsakeCatalog.all():
		if item.chapter_key.is_empty(): ordered.append(item)
	var result: Array[Dictionary] = []
	for item: Dictionary in ordered:
		if result.size() >= limit: break
		if not earned.has(item.id): result.append(item)
	return result

## Up to limit earned keepsakes, most recently earned last, as catalog items.
func recent_earned(limit: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index in range(_keepsakes.size()-1, -1, -1):
		if result.size() >= limit: break
		var item := KeepsakeCatalog.by_id(str(_keepsakes[index].get("id","")))
		if not item.is_empty(): result.push_front(item)
	return result

func _refresh_teasers() -> void:
	if not is_instance_valid(_keepsake_box) or not is_instance_valid(_world): return
	var empty := _keepsakes.is_empty()
	var shown := next_unearned(TEASER_LARGE if empty else TEASER_SMALL)
	# A complete collection shows recent earned keepsakes in colour instead.
	var earned_view := shown.is_empty() and not empty
	if earned_view: shown = recent_earned(TEASER_SMALL)
	var kind := "large" if empty else "earned" if earned_view else "small"
	var ids := kind + ":" + ",".join(shown.map(func(item: Dictionary) -> String: return str(item.id)))
	if ids == _teaser_ids: return
	_teaser_ids = ids
	if is_instance_valid(_keepsake_strip):
		_keepsake_strip.get_parent().remove_child(_keepsake_strip)
		_keepsake_strip.queue_free()
	_keepsake_strip = null
	if shown.is_empty(): return
	var strip := KeepsakeTeaser.new()
	strip.configure(_world, shown, STRIP_CELL_LARGE if empty else STRIP_CELL_SMALL, not earned_view)
	strip.name = {"large": "KeepsakeTeaserLarge", "small": "KeepsakeTeaserSmall", "earned": "KeepsakeEarned"}[kind]
	_keepsake_strip_row.add_child(strip)
	_keepsake_strip = strip

func _update_keepsake_labels() -> void:
	if not is_instance_valid(_keepsake_box): return
	var item: Dictionary = _keepsake_display.selected_item() if is_instance_valid(_keepsake_display) else {}
	# Progress counts variants (solo, and together where it exists), not places.
	var total := KeepsakeCatalog.variant_total()
	var earned := mini(KeepsakeCatalog.variant_count(_keepsakes), total)
	_keepsake_controls.visible = not item.is_empty()
	_keepsake_invite.visible = item.is_empty()
	_keepsake_count.text = "Keepsakes · %d / %d" % [earned, total]
	_refresh_teasers()
	if item.is_empty(): return
	_keepsake_title.text = str(item.title)
	_keepsake_variant_icons.get_child(0).visible = bool(item.get("solo", false))
	_keepsake_variant_icons.get_child(1).visible = bool(item.get("friend", false))
	if _keepsake_controls.custom_minimum_size.x > 0:
		_place_keepsake_heading(_keepsake_controls.custom_minimum_size.x)

func _is_active() -> bool:
	return is_inside_tree() and is_visible_in_tree() and _foreground and is_instance_valid(_world) and _world.visible and _world.home_view and _world.terrain==_terrain and _world.home_presentation_owner==get_instance_id() and _active.is_valid() and _active.call()

func _allowed(point: Vector2) -> bool:
	for action: Control in _header_actions:
		if is_instance_valid(action) and action.is_visible_in_tree() and action.get_global_rect().has_point(point): return false
	if is_instance_valid(_keepsake_box) and _keepsake_box.visible and _keepsake_box.get_global_rect().has_point(point): return false
	return _stage_rect().has_point(point) and not (is_instance_valid(_reset) and _reset.visible and _reset.get_global_rect().has_point(point))

func _input(event: InputEvent) -> void:
	if not _is_active():
		_cancel_gesture()
		return
	_track_tap(event)
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
	if event is InputEventMouse or event is InputEventGesture:
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
	if _greeting_left > 0.0 or _touches.size() > 1 or not _allowed(point) or not _spirit_near(point): return
	_tap = {"index": index, "start": point, "msec": Time.get_ticks_msec()}

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
		_greet()

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
	_layout()
	zoom_size = zoom_target if _world.reduced_motion else lerpf(zoom_size,zoom_target,1.0-exp(-12.0*step))
	_frame_camera()
	_world.update_spirit_attention()
	for role: String in _actors:
		var actor: Node3D = _actors[role]
		var previous := actor.position
		if not _world.reduced_motion:
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
	var focus_target := Vector3(center.x,0.35,center.y)
	if is_instance_valid(_keepsake_display) and _keepsake_display.visible:
		focus_target = _keepsake_display.center + Vector3(0,0.65,0)
	var focus := Vector3.ZERO.lerp(focus_target,zoom)
	camera.global_transform = _camera_transform
	camera.global_position += _world.global_basis*focus
	camera.size = zoom_size
	# KEEP_HEIGHT is the existing orthographic camera mode. Offsets place the
	# world in the clear right-side stage at every supported landscape width.
	var units_per_pixel := zoom_size/maxf(viewport.size.y,1)
	var offset := rect.get_center()-viewport.get_center()
	camera.h_offset = -offset.x*units_per_pixel
	camera.v_offset = offset.y*units_per_pixel
	_exploration.apply_pan(camera, DEFAULT_SIZE)

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
	elif what in [NOTIFICATION_APPLICATION_FOCUS_IN,NOTIFICATION_APPLICATION_RESUMED]:
		_foreground = true

func _exit_tree() -> void:
	_cancel_gesture()
	if is_instance_valid(_keepsake_display): _keepsake_display.queue_free()
	if not is_instance_valid(_world) or _world.home_presentation_owner!=get_instance_id(): return
	for saved_prop: Dictionary in _hidden_props:
		if is_instance_valid(saved_prop.node): saved_prop.node.visible = saved_prop.visible
	# Keep normalized exploration, never the already-composed camera transform.
	_retained_view = {"zoom_target": zoom_target, "zoom_size": zoom_size, "pan": _exploration.pan}
	_world.home_presentation_owner = 0
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
