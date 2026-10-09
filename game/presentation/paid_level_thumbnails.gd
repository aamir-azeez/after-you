extends RefCounted
## Static actual-world pictures. No admission, preview, purchase or network path.
const Catalog = preload("res://services/paid_level_catalog.gd")
const CREAM := Color("eceddb")
const MUTED := Color("a6c7bc")

static func row(key: String, actions: Control = null, show_title: bool = true) -> PanelContainer:
	var item := Catalog.entry(key)
	var panel := PanelContainer.new()
	panel.name = "PaidLevel_" + key.replace("-", "_")
	panel.set_meta("paid_level_key", key)
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color("1b423c")
	style.border_color = Color("52796c")
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_PASS
	line.add_theme_constant_override("separation", 16)
	panel.add_child(line)
	var picture := TextureRect.new()
	picture.name = "LevelPicture"
	picture.custom_minimum_size = Vector2(224,126)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not item.is_empty() and ResourceLoader.exists(item.texture):
		picture.texture = load(item.texture)
	line.add_child(picture)
	var body := VBoxContainer.new()
	body.name = "LevelDetails"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	body.mouse_filter = Control.MOUSE_FILTER_PASS
	body.add_theme_constant_override("separation", 10)
	line.add_child(body)
	if show_title:
		var title := _label(str(item.get("title", "")), 23, CREAM)
		title.name = "LevelTitle"
		body.add_child(title)
	var count := int(item.get("stages", 0))
	var detail := "%d %s" % [count, "stage" if count == 1 else "stages"]
	if actions == null: detail += " · Solo · Together" if item.get("together",false) else " · Solo"
	body.add_child(_label(detail, 17, MUTED))
	if actions != null:
		actions.mouse_filter = Control.MOUSE_FILTER_PASS
		actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.add_child(actions)
	return panel

static func gallery(minimum_height: float = 260.0) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = "FullJourneyGallery"
	scroll.custom_minimum_size.y = minimum_height
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.focus_mode = Control.FOCUS_ALL
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.mouse_filter = Control.MOUSE_FILTER_PASS
	list.add_theme_constant_override("separation", 12)
	scroll.add_child(list)
	for key: String in Catalog.keys(): list.add_child(row(key))
	return scroll

static func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size",size)
	label.add_theme_color_override("font_color",color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
