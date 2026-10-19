extends CanvasLayer
const PlayerCopy = preload("res://presentation/player_copy.gd")
## Shared chapter controls. Puzzle progression and persistence stay with the owner.
signal pause_requested
signal action_requested
signal finish_requested
## Skip to end, while the live spirit waits for its friend's memory.
signal skip_wait_requested

const Joystick = preload("res://presentation/joystick.gd")
const SafeArea = preload("res://presentation/safe_area.gd")
const ControlTheme = preload("res://presentation/control_theme.gd")
const Actions = preload("res://presentation/action_buttons.gd")
const ObjectivePanel = preload("res://presentation/objective_panel.gd")
const SeedTimerBar = preload("res://presentation/seed_timer_bar.gd")
const HoldButton = preload("res://presentation/hold_button.gd")
const MemoryWaitBar = preload("res://presentation/memory_wait_bar.gd")
const FastForwardBadge = preload("res://presentation/fast_forward_badge.gd")
const CREAM := Color("eceddb")
const MUTED := Color("afc7bd")
var settings: Dictionary = {}
## Solo play: the partner is the player's own memory, so a line with a solo
## wording reads that (PlayerCopy.from_canonical).
var solo := false
var ui: Control
var hud: Control
var overlay: Control
var stick: Control
var action_button: Button
var finish_button: Button
var pause_button: Button
var timer_label: Label
var chapter_label: Label
var hint_label: Label
var progress_label: Label
var objective_panel: PanelContainer
var turn_progress: SeedTimerBar
var title_font: Font
var modal_shade: ColorRect
var modal_scroll: ScrollContainer
var modal_stack: VBoxContainer
## Shown once the player has pinched or panned the chapter view, as on Home.
var reset_view_button: Button
## "Waiting for Sam" and the memory still to play, under the chapter title.
var wait_row: HBoxContainer
var wait_label: Label
var wait_bar: MemoryWaitBar
## Hold to fast-forward and Skip to end take the action and finish places
## while the live spirit waits. Built once and only shown or hidden, so a
## finger on them never loses its press to a rebuild.
var fast_forward_button: HoldButton
var skip_wait_button: Button
## Over the world while the wait goes by faster (skipped or held).
var fast_forward_badge: FastForwardBadge
var _memory_wait := false
var _view_world: Node

func _ready() -> void:
	_build_ui()
	SafeArea.watch(self, _resize)
	_resize()

func show_play() -> void:
	overlay.visible = false
	hud.visible = true
	pause_button.visible = true
	Actions.apply(finish_button, "finish")

func show_moment(action_id: String) -> void:
	# The solved world stays visible until the player chooses to move on.
	show_play()
	hide_memory_wait()
	stick.release()
	stick.visible = false
	action_button.visible = false
	pause_button.visible = false
	finish_button.visible = true
	finish_button.disabled = false
	Actions.apply(finish_button, action_id)

func update_state(title: String, remaining: float, state: Dictionary, interactive: bool) -> void:
	chapter_label.text = title
	turn_progress.reduced_motion = bool(settings.get("reduced_motion", false))
	turn_progress.set_remaining(remaining, float(state.get("duration_ticks", 600)) / 30.0)
	hint_label.text = PlayerCopy.from_canonical(str(state.get("message", "")), solo)
	var objective: Dictionary = state.get("objective_display", ObjectivePanel.legacy_progress(state, 30.0))
	objective_panel.show_objective(objective, str(state.get("progress_message", "")))
	var action: Dictionary = state.get("context_action", {})
	action_button.text = PlayerCopy.from_canonical(str(action.get("label", "Interact")))
	action_button.disabled = not bool(action.get("enabled", false))
	finish_button.disabled = not bool(state.get("can_commit", false))
	stick.visible = interactive
	action_button.visible = interactive and not action_button.text.is_empty() and not _memory_wait
	finish_button.visible = interactive and not _memory_wait
	fast_forward_button.visible = interactive and _memory_wait
	skip_wait_button.visible = interactive and _memory_wait

## The live spirit is waiting for its friend's memory: `text` names the friend
## and `ratio` is how much of the memory is left (1 to 0); `skipping` is true
## while Skip to end runs. Cheap to call every tick; nothing is rebuilt and
## unchanged values change nothing.
func show_memory_wait(text: String, ratio: float, skipping: bool = false) -> void:
	fast_forward_badge.reduced_motion = bool(settings.get("reduced_motion", false))
	fast_forward_badge.set_active(skipping or fast_forward_button.held())
	if wait_label.text != text: wait_label.text = text
	wait_bar.value = ratio
	if not wait_row.visible:
		wait_row.visible = true
		_place_wait_row.call_deferred()
	_memory_wait = true

## True while the fast-forward mark shows (a skipped or fast-forwarded wait).
func fast_forwarding() -> bool:
	return fast_forward_badge.active()

## The wait is over (or there is none). Fast-forward lets go of its fingers.
func hide_memory_wait() -> void:
	fast_forward_badge.set_active(false)
	if not _memory_wait and not wait_row.visible: return
	_memory_wait = false
	wait_row.visible = false
	fast_forward_button.visible = false
	skip_wait_button.visible = false

func memory_wait_shown() -> bool:
	return _memory_wait

## The stick fades while Fast-forward plays the memory, since the live
## spirit stands still meanwhile.
func dim_stick(dim: bool) -> void:
	var alpha := 0.45 if dim else 1.0
	if not is_equal_approx(stick.modulate.a, alpha): stick.modulate.a = alpha

## True while a finger or the mouse holds Fast-forward.
func fast_forward_held() -> bool:
	return _memory_wait and fast_forward_button.held()

## The row sits just under the chapter title, however many lines it wraps to.
func _place_wait_row() -> void:
	if not is_instance_valid(wait_row) or not is_instance_valid(chapter_label): return
	wait_row.position = Vector2(chapter_label.position.x, chapter_label.position.y + chapter_label.get_combined_minimum_size().y + 4.0)

func _build_ui() -> void:
	ui = Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ui)
	var theme := Theme.new()
	var body := FontVariation.new()
	body.base_font = preload("res://assets/fonts/nunito.ttf")
	body.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 600.0}
	theme.default_font = body
	var heading := FontVariation.new()
	heading.base_font = preload("res://assets/fonts/fredoka.ttf")
	heading.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 600.0}
	title_font = heading
	theme.default_font_size = 20
	theme.set_color("font_color", "Label", CREAM)
	ControlTheme.install_buttons(theme)
	ui.theme = theme
	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(hud)
	var brand := _label("AFTER YOU",22)
	brand.add_theme_font_override("font",title_font)
	_protect_world_label(brand)
	brand.position=Vector2(36,26)
	hud.add_child(brand)
	chapter_label = _label("THE SLEEPING LIGHTHOUSE",18)
	chapter_label.add_theme_color_override("font_color",MUTED)
	_protect_world_label(chapter_label)
	chapter_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	chapter_label.position = Vector2(36,61)
	hud.add_child(chapter_label)
	chapter_label.minimum_size_changed.connect(_fit_chapter_title.call_deferred)
	wait_row = HBoxContainer.new()
	wait_row.name = "MemoryWait"
	wait_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wait_row.add_theme_constant_override("separation", 10)
	wait_row.visible = false
	hud.add_child(wait_row)
	wait_label = _label("", 16)
	_protect_world_label(wait_label)
	wait_row.add_child(wait_label)
	wait_bar = MemoryWaitBar.new()
	wait_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	wait_row.add_child(wait_bar)
	# The shared seed timer owns the remaining-seconds number above its track.
	turn_progress = SeedTimerBar.new()
	turn_progress.reduced_motion = bool(settings.get("reduced_motion", false))
	hud.add_child(turn_progress)
	_anchor_rect(turn_progress, Control.PRESET_CENTER_TOP, Rect2(-160, 24, 320, SeedTimerBar.MIN_SIZE.y))
	timer_label = turn_progress.label
	objective_panel = ObjectivePanel.new()
	hud.add_child(objective_panel)
	_anchor_rect(objective_panel, Control.PRESET_TOP_RIGHT, Rect2(-248, 124, 224, 0))
	progress_label = objective_panel.label
	pause_button = button_for("pause", func(): pause_requested.emit())
	pause_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	pause_button.position = Vector2(-156, 20)
	pause_button.size = Vector2(132, 50)
	hud.add_child(pause_button)
	reset_view_button = Button.new()
	reset_view_button.name = "ChapterResetView"
	reset_view_button.text = "Reset view"
	reset_view_button.custom_minimum_size = Vector2(116, 36)
	reset_view_button.add_theme_font_size_override("font_size", 16)
	reset_view_button.pressed.connect(_reset_view)
	reset_view_button.visible = false
	reset_view_button.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	reset_view_button.position = Vector2(-58, 92)
	reset_view_button.size = Vector2(116, 36)
	hud.add_child(reset_view_button)
	hint_label = _label("", 21)
	_protect_world_label(hint_label)
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint_label.position = Vector2(-340, -94)
	hint_label.size = Vector2(680, 78)
	hud.add_child(hint_label)
	stick = Joystick.new()
	stick.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	stick.position = Vector2(8, -218)
	stick.size = Vector2(Joystick.HIT_SIZE, Joystick.HIT_SIZE)
	hud.add_child(stick)
	action_button = button("Interact", func(): action_requested.emit())
	action_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	action_button.position = Vector2(-240, -178)
	action_button.size = Vector2(210, 64)
	hud.add_child(action_button)
	finish_button = button_for("finish", func(): finish_requested.emit())
	finish_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	finish_button.position = Vector2(-240, -100)
	finish_button.size = Vector2(210, 54)
	hud.add_child(finish_button)
	fast_forward_button = HoldButton.new()
	fast_forward_button.name = "FastForward"
	fast_forward_button.custom_minimum_size.y = 50
	fast_forward_button.mouse_filter = Control.MOUSE_FILTER_STOP
	fast_forward_button.focus_mode = Control.FOCUS_NONE
	Actions.apply(fast_forward_button, "fast_forward")
	fast_forward_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	fast_forward_button.position = Vector2(-240, -178)
	fast_forward_button.size = Vector2(210, 64)
	fast_forward_button.visible = false
	hud.add_child(fast_forward_button)
	# Skip acts on release, so the turn ends after the finger has lifted.
	skip_wait_button = button_for("skip_wait", func(): skip_wait_requested.emit())
	skip_wait_button.name = "SkipWait"
	skip_wait_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	skip_wait_button.position = Vector2(-240, -100)
	skip_wait_button.size = Vector2(210, 54)
	skip_wait_button.visible = false
	hud.add_child(skip_wait_button)
	fast_forward_badge = FastForwardBadge.new()
	hud.add_child(fast_forward_badge)
	var badge := FastForwardBadge.SIZE
	_anchor_rect(fast_forward_badge, Control.PRESET_CENTER, Rect2(-badge * 0.5, -badge * 0.5 - 60.0, badge, badge))
	if settings.get("left_handed", false):
		_anchor_rect(stick, Control.PRESET_BOTTOM_RIGHT, Rect2(-200, -218, Joystick.HIT_SIZE, Joystick.HIT_SIZE))
		_anchor_rect(action_button, Control.PRESET_BOTTOM_LEFT, Rect2(28, -178, 210, 64))
		_anchor_rect(finish_button, Control.PRESET_BOTTOM_LEFT, Rect2(28, -100, 210, 54))
		_anchor_rect(fast_forward_button, Control.PRESET_BOTTOM_LEFT, Rect2(28, -178, 210, 64))
		_anchor_rect(skip_wait_button, Control.PRESET_BOTTOM_LEFT, Rect2(28, -100, 210, 54))
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(overlay)


## The chapter world whose pinch-and-pan view the Reset view chip restores.
func watch_view(world: Node) -> void:
	_view_world = world

func _process(_delta: float) -> void:
	if not is_instance_valid(reset_view_button): return
	var exploration: Node = _view_world.get("camera_exploration") if is_instance_valid(_view_world) else null
	var explored := is_instance_valid(exploration) and (not is_equal_approx(float(exploration.zoom_ratio), 1.0) or not Vector2(exploration.pan).is_zero_approx())
	if reset_view_button.visible != explored: reset_view_button.visible = explored

func _reset_view() -> void:
	if is_instance_valid(_view_world) and _view_world.has_method("reset_camera_exploration"): _view_world.reset_camera_exploration()
	reset_view_button.visible = false

func _anchor_rect(control: Control, preset: int, rect: Rect2) -> void:
	# Set offsets, not absolute positions, after the control has a parent.
	control.set_anchors_and_offsets_preset(preset)
	control.offset_left = rect.position.x
	control.offset_top = rect.position.y
	control.offset_right = rect.end.x
	control.offset_bottom = rect.end.y


func _resize() -> void:
	if not is_inside_tree() or not is_instance_valid(ui):
		return
	SafeArea.inset(ui, SafeArea.rect(get_viewport()))
	if is_instance_valid(hint_label):
		_anchor_rect(hint_label, Control.PRESET_BOTTOM_LEFT, ControlTheme.hint_bounds(ui.size.x, bool(settings.get("left_handed", false))))
	if is_instance_valid(chapter_label):
		# Long stage names wrap in the title column instead of covering the
		# timer and progress text in the centre of the display.
		chapter_label.size.x = maxf(240.0, ui.size.x * 0.5 - 244.0)
		_fit_chapter_title.call_deferred()
	_layout_card.call_deferred()


func _fit_chapter_title() -> void:
	# Wrapping recomputes its minimum height after the width/text changes.
	# Release any height retained from the earlier narrow layout so its real
	# rectangle does not invisibly cover the playfield or suppress photo bubbles.
	if is_instance_valid(chapter_label):
		chapter_label.size.y = 0.0
	_place_wait_row()


func _style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(16)
	style.set_border_width_all(1)
	style.border_color = Color("54766a")
	return style


func _label(text: String, size: int = 20) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _protect_world_label(label: Label) -> void:
	# Scrolling rooms can put pale walls behind the HUD. Keep its lettering
	# readable without adding a panel across the visible route.
	label.add_theme_color_override("font_outline_color", Color("101f31"))
	label.add_theme_constant_override("outline_size", 4)
	# A soft dark halo behind the letters keeps the title readable over
	# bright grass, plaster and tile in every chapter.
	label.add_theme_color_override("font_shadow_color", Color(0.04, 0.09, 0.13, 0.62))
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.add_theme_constant_override("shadow_outline_size", 12)


func button_for(action_id: String, callback: Callable) -> Button:
	return Actions.create(action_id, callback)


func button(text: String, callback: Callable, primary: bool=true) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 50
	button.mouse_filter = Control.MOUSE_FILTER_PASS
	button.pressed.connect(callback)
	if not primary: ControlTheme.secondary(button)
	return button


func card(title: String, body: String) -> VBoxContainer:
	stick.release()
	hud.visible = false
	for child in overlay.get_children():
		overlay.remove_child(child)
		child.queue_free()
	overlay.visible = true
	modal_shade = ColorRect.new()
	modal_shade.color = Color(0.025, 0.10, 0.10, 0.73)
	modal_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Controls respect display cutouts; the dimming backdrop covers the whole
	# world, including those insets. Otherwise a bright side strip remains.
	SafeArea.bleed(modal_shade)
	overlay.add_child(modal_shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 610
	panel.add_theme_stylebox_override("panel", _style(Color("163c36")))
	center.add_child(panel)
	var margin := MarginContainer.new()
	for edge: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 22)
	panel.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 12)
	modal_scroll = ScrollContainer.new()
	modal_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	modal_scroll.follow_focus = true
	margin.add_child(modal_scroll)
	modal_scroll.add_child(stack)
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	modal_stack = stack
	stack.minimum_size_changed.connect(func(): _layout_card.call_deferred())
	var heading_label := _label(title, 32)
	heading_label.add_theme_font_override("font", title_font)
	heading_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading_label.custom_minimum_size.x = 550
	stack.add_child(heading_label)
	var paragraph := _label(body, 20)
	paragraph.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	paragraph.custom_minimum_size.x = 550
	paragraph.add_theme_color_override("font_color", MUTED)
	stack.add_child(paragraph)
	_layout_card.call_deferred()
	return stack

func _layout_card() -> void:
	if not is_instance_valid(modal_scroll) or not is_instance_valid(modal_stack): return
	# Long checkpoint lists scroll inside the card instead of pushing the
	# final button beyond the safe display area.
	var limit := maxf(120.0, ui.size.y - 84.0)
	var required := modal_stack.get_combined_minimum_size().y
	modal_scroll.custom_minimum_size = Vector2(566.0, minf(required, limit))
