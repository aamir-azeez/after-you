extends MarginContainer
## Ordinary online room presentation; the caller retains all turn/session actions.
const ThemeRules = preload("res://presentation/control_theme.gd")
const BACK = preload("res://assets/ui/social/arrow-left.svg")
const INFO = preload("res://assets/ui/social/info.svg")
var scene_space: Control
var actions: VBoxContainer
var header: HBoxContainer
var short_layout := false

func build(chapter: String, turn: String, hint: String, heading_font: Font, back: Callable, details: Callable = Callable()) -> VBoxContainer:
	# Empty turn/hint text and an invalid details callback omit those rows.
	short_layout = (get_parent() as Control).size.y < 640
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge: String in ["left","right","top","bottom"]:
		add_theme_constant_override("margin_"+edge,28)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation",24)
	add_child(page)
	header = HBoxContainer.new()
	header.add_theme_constant_override("separation",20)
	page.add_child(header)
	var back_button := Button.new()
	back_button.icon = BACK
	back_button.expand_icon = true
	back_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	back_button.custom_minimum_size = Vector2(48,48)
	back_button.tooltip_text = "Back"
	back_button.accessibility_name = "Back"
	ThemeRules.danger(back_button,BACK)
	back_button.pressed.connect(back)
	header.add_child(back_button)
	var title := _label(chapter,38)
	title.add_theme_font_override("font",heading_font)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation",28)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(columns)
	var introduction := VBoxContainer.new()
	introduction.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	introduction.size_flags_stretch_ratio = 1.25
	introduction.add_theme_constant_override("separation",16)
	columns.add_child(introduction)
	if not turn.is_empty():
		var stage := _label(turn,36)
		stage.add_theme_font_override("font",heading_font)
		introduction.add_child(stage)
	if not hint.is_empty(): introduction.add_child(_label(hint,20))
	scene_space = Control.new()
	scene_space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scene_space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	introduction.add_child(scene_space)
	var panel := PanelContainer.new()
	panel.name = "RoomActionsPanel"
	panel.custom_minimum_size.x = 380
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Hug the actions and sit at the top of the row; the scroll viewport caps the
	# height and owns any overflow, so no empty space trails the last action.
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	panel.add_theme_stylebox_override("panel",ThemeRules.rounded(Color("163c36"),20,Color("54766a")))
	columns.add_child(panel)
	var inset := MarginContainer.new()
	inset.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var padding := 20 if short_layout else 28
	for edge: String in ["left","right","top","bottom"]:
		inset.add_theme_constant_override("margin_"+edge,padding)
	panel.add_child(inset)
	var scroll := ScrollContainer.new()
	scroll.name = "RoomActionsScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	inset.add_child(scroll)
	actions = VBoxContainer.new()
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_theme_constant_override("separation",12 if short_layout else 20)
	scroll.add_child(actions)
	var fit := func():
		if not is_inside_tree() or not is_instance_valid(scroll): return
		# Keep the panel within the available row height. The scroll viewport
		# owns overflow when invitation, presence, and action rows do not fit.
		var available_row_height := maxf(0,get_viewport_rect().size.y-56-header.get_combined_minimum_size().y-24-2*padding)
		scroll.custom_minimum_size.y = minf(actions.get_combined_minimum_size().y,available_row_height)
	actions.minimum_size_changed.connect(fit.call_deferred)
	columns.resized.connect(fit.call_deferred)
	fit.call_deferred()
	return actions

func _add_about(introduction: VBoxContainer, details: Callable) -> void:
	var about := Button.new()
	about.text = "About this chapter  ›"
	about.tooltip_text = "About this chapter"
	about.accessibility_name = "About this chapter"
	about.icon = INFO
	about.expand_icon = false
	about.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	about.alignment = HORIZONTAL_ALIGNMENT_LEFT
	about.add_theme_constant_override("icon_max_width",26)
	about.add_theme_constant_override("h_separation",12)
	about.custom_minimum_size.y = 48
	about.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	for state: String in ["normal","hover","pressed","hover_pressed","disabled"]:
		var fill := Color("20433e") if state in ["hover","pressed","hover_pressed"] else Color.TRANSPARENT
		about.add_theme_stylebox_override(state,ThemeRules.rounded(fill,12))
		var color := Color("afc7bd") if state in ["normal","disabled"] else ThemeRules.CREAM
		about.add_theme_color_override("font_color" if state == "normal" else "font_"+state+"_color",color)
		about.add_theme_color_override("icon_"+state+"_color",color)
	about.pressed.connect(details)
	introduction.add_child(about)
	ThemeRules.inset_button(about,8,10)

func _label(value: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size",font_size)
	return label
