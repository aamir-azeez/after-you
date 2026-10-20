extends VBoxContainer
## Earlier versions on the What's new card: every version before this one, newest
## first, in a list that scrolls by dragging. Each row shows a version and its
## date; tapping it opens that version's highlights under it, in the card's look,
## built the first time the row opens. See all changes, where a build links the
## full notes, ends the list. The card builds this only when the list is opened.
const Kit = preload("res://presentation/whats_new_kit.gd")
const ControlTheme = preload("res://presentation/control_theme.gd")
const SettingsKit = preload("res://presentation/settings_kit.gd")
const PhotoDate = preload("res://presentation/photo_date.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const VersionOrder = preload("res://services/version_order.gd")
const CLOSED_ICON = preload("res://assets/ui/social/chevron-right.svg")
const OPEN_ICON = preload("res://assets/ui/social/chevron-down.svg")
const ROW := Color("24534b")
const ROW_HOVER := Color("2a5a50")
const MUTED := Color("afc6be")
const ROW_HEIGHT := 56.0
const DETAILS := "WhatsNewVersionHighlights"

var _scroll: ScrollContainer
var _rows: VBoxContainer
var _limit := 0.0

## `entries` are Changelog.earlier_entries(): [{"version", "date", "highlights"}].
func _init(entries: Array, see_all: Callable) -> void:
	add_theme_constant_override("separation", 0)
	_scroll = ScrollContainer.new()
	_scroll.name = "WhatsNewEarlierScroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	add_child(_scroll)
	_rows = VBoxContainer.new()
	_rows.name = "WhatsNewVersions"
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 8)
	_scroll.add_child(_rows)
	for entry: Dictionary in entries:
		_rows.add_child(_row(entry))
	if see_all.is_valid():
		var gap := Control.new()
		gap.custom_minimum_size.y = 6
		gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_rows.add_child(gap)
		var all := Button.new()
		all.name = "WhatsNewSeeAll"
		all.text = PlayerCopy.WHATS_NEW_SEE_ALL
		all.custom_minimum_size.y = 54
		all.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		all.pressed.connect(see_all)
		ControlTheme.secondary(all)
		_rows.add_child(all)
	ControlTheme.touch_scroll(_scroll)
	SettingsKit.style_scroll(_scroll, false)
	_rows.minimum_size_changed.connect(_refit, CONNECT_DEFERRED)

## The list's height: its rows, up to `limit`, past which it scrolls. The card
## calls this when the list shows and when the screen changes size; opening or
## closing a row refits it.
func fit(limit: float) -> void:
	_limit = maxf(ROW_HEIGHT, limit)
	_refit()

func _refit() -> void:
	_scroll.custom_minimum_size.y = minf(_rows.get_combined_minimum_size().y, _limit)

## A row's version line: "Version 0.4.16", or "Version 0.2.0 preview 9" for an
## early preview build (0.2.0-preview9).
static func version_text(version: String) -> String:
	var parts := VersionOrder.parse_listed(version)
	if parts.size() == 4 and parts[3] > 0:
		return PlayerCopy.WHATS_NEW_VERSION_PREVIEW % ["%d.%d.%d" % [parts[0], parts[1], parts[2]], parts[3]]
	return PlayerCopy.WHATS_NEW_VERSION % version

## "16 Oct 2026" from "2026-10-16", read from the text itself so no time zone can
## move the day.
static func date_text(date: String) -> String:
	var parts := date.split("-")
	if parts.size() != 3: return date
	var month := int(parts[1])
	if month < 1 or month > 12: return date
	return PlayerCopy.WHATS_NEW_DATE % [int(parts[2]), PhotoDate.MONTHS[month - 1], int(parts[0])]

func _row(entry: Dictionary) -> VBoxContainer:
	var holder := VBoxContainer.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_theme_constant_override("separation", 12)
	var version := version_text(str(entry.version))
	var date := date_text(str(entry.date))
	var button := Button.new()
	button.name = "WhatsNewVersionRow"
	button.accessibility_name = "%s, %s" % [version, date]
	button.custom_minimum_size.y = ROW_HEIGHT
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		var look := ControlTheme.rounded(ROW if state == "normal" else ROW_HOVER, 14)
		if state == "focus": look = ControlTheme.rounded(Color.TRANSPARENT, 14, Kit.CREAM)
		button.add_theme_stylebox_override(state, look)
	holder.add_child(button)
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	line.offset_left = 18.0
	line.offset_right = -16.0
	line.add_theme_constant_override("separation", 12)
	button.add_child(line)
	var title := _label(version, 21, Kit.TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(title)
	line.add_child(_label(date, 17, MUTED))
	var chevron := TextureRect.new()
	chevron.name = "WhatsNewChevron"
	chevron.texture = CLOSED_ICON
	chevron.custom_minimum_size = Vector2(18, 18)
	chevron.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	chevron.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	chevron.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chevron.self_modulate = Kit.ICON_TINT
	chevron.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(chevron)
	button.pressed.connect(_toggle.bind(holder, entry.highlights, chevron))
	return holder

func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_vertical = Control.SIZE_FILL
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label

## Opens or closes one version's highlights; the first open builds them.
func _toggle(holder: VBoxContainer, highlights: Array, chevron: TextureRect) -> void:
	var details := holder.get_node_or_null(DETAILS) as Control
	if details == null:
		var indent := MarginContainer.new()
		indent.name = DETAILS
		indent.mouse_filter = Control.MOUSE_FILTER_IGNORE
		indent.add_theme_constant_override("margin_left", 18)
		indent.add_theme_constant_override("margin_right", 16)
		indent.add_theme_constant_override("margin_bottom", 6)
		indent.add_child(Kit.highlight_list(highlights))
		holder.add_child(indent)
		details = indent
	else:
		details.visible = not details.visible
	chevron.texture = OPEN_ICON if details.visible else CLOSED_ICON
	var reveal := _reveal.bind(details)
	if details.visible and is_inside_tree() and not get_tree().process_frame.is_connected(reveal):
		get_tree().process_frame.connect(reveal, CONNECT_ONE_SHOT)

## Scrolls an opened version's highlights into view once the list has laid them out.
func _reveal(details: Control) -> void:
	if is_instance_valid(details) and details.is_visible_in_tree(): _scroll.ensure_control_visible(details)
