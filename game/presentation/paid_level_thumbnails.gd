extends RefCounted
## Static actual-world pictures. No admission, preview, purchase or network path.
const Catalog = preload("res://services/paid_level_catalog.gd")
const ChapterThumbnails = preload("res://services/chapter_thumbnail_catalog.gd")
const ChapterRegistry = preload("res://services/chapter_registry.gd")
const Levels = preload("res://core/levels.gd")
const CREAM := Color("eceddb")
const MUTED := Color("a6c7bc")

static func row(key: String, actions: Control = null, show_title: bool = true) -> PanelContainer:
	var item := Catalog.entry(key)
	var title := str(item.get("title", ""))
	if title.is_empty(): title = _chapter_title(key)
	return chapter_row(key, title, actions, false, show_title, int(item.get("stages", 0)))

static func chapter_row(key: String, title_text: String, actions: Control = null, locked: bool = false, show_title: bool = true, stage_count: int = 0) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "ChapterThumbnail_" + key.replace("@", "_").replace("-", "_")
	panel.set_meta("chapter_thumbnail_key", key)
	panel.set_meta("chapter_locked", locked)
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
	var image_path := ChapterThumbnails.path(key)
	if not image_path.is_empty() and ResourceLoader.exists(image_path):
		picture.texture = load(image_path)
	if locked:
		picture.modulate = Color("77827b")
	line.add_child(picture)
	var body := VBoxContainer.new()
	body.name = "LevelDetails"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	body.mouse_filter = Control.MOUSE_FILTER_PASS
	body.add_theme_constant_override("separation", 10)
	line.add_child(body)
	if show_title:
		var title := _label(title_text, 23, CREAM)
		title.name = "ChapterTitle"
		body.add_child(title)
	var detail := "Full Journey" if locked else ("%d %s" % [stage_count, "stage" if stage_count == 1 else "stages"] if stage_count > 0 else "Earlier island")
	body.add_child(_label(("🔒  " if locked else "") + detail, 17, MUTED))
	if actions != null:
		actions.mouse_filter = Control.MOUSE_FILTER_PASS
		actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.add_child(actions)
	return panel

static func _chapter_title(key: String) -> String:
	if key.begins_with("legacy-"):
		return str(Levels.get_level(key.trim_prefix("legacy-")).get("title", "Earlier island"))
	if key == "sleeping-lighthouse": return "Sleeping Lighthouse"
	return str(ChapterRegistry.descriptor(key).get("title", key))

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
