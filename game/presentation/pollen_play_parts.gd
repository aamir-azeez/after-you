extends RefCounted
## The pieces Pollen from play's cards share (presentation/pollen_turns_view.gd
## and pollen_clears_view.gd): the card's inks, labels (presentation/kit/shop_kit.gd
## type, as the Purchases card), rules between rows, the summary box both cards
## open with (a big figure, its words, a bar and a line of rules under it, as
## the turn bank on pollen board 7b), and a chapter's small picture from the
## thumbnail shelf (loaded off the main thread, kept while Main is up; the
## frame keeps its size meanwhile, so nothing moves). The picture is square
## cornered: a rounded clip costs a drawing pass of its own per picture, and a
## long list of turns has up to 50. Pure building: it keeps nothing.
const ShopKit = preload("res://presentation/kit/shop_kit.gd")
const ControlTheme = preload("res://presentation/control_theme.gd")
const ChapterPicker = preload("res://presentation/chapter_picker.gd")
const ThumbnailShelf = preload("res://presentation/chapter_thumbnail_shelf.gd")
const Thumbnails = preload("res://services/chapter_thumbnail_catalog.gd")
const PollenHistory = preload("res://services/pollen_history.gd")

const BOX := Color("fbf8ec")
const BOX_EDGE := Color("e4dcc4")
const INK := ShopKit.INK
const SOFT_INK := Color("4e6660")
const TRACK := Color("ddd6c0")
const FILL := Color("e2b25a")
const ROW_SIZE := 17
const NOTE_SIZE := 14
const PICTURE := Vector2(64, 36)
const BIG := 34

## A box named `box_name` with `lead` (its big figure, see big()) beside `words`,
## the bar (named `box_name` + "Bar") at `value` of `most`, and `left_rule` and
## `right_rule` under it.
static func summary(box_name: String, lead: Control, words: String, value: int, most: int, left_rule: String, right_rule: String) -> PanelContainer:
	var box := PanelContainer.new()
	box.name = box_name
	box.add_theme_stylebox_override("panel", ControlTheme.padded(ControlTheme.rounded(BOX, 14, BOX_EDGE), 16.0, 12.0))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	box.add_child(column)
	var count := HBoxContainer.new()
	count.add_theme_constant_override("separation", 10)
	column.add_child(count)
	count.add_child(lead)
	var said := wrapped(words, ROW_SIZE, INK)
	said.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	count.add_child(said)
	var bar := ProgressBar.new()
	bar.name = box_name + "Bar"
	bar.show_percentage = false
	bar.max_value = maxi(most, 1)
	bar.value = value
	bar.custom_minimum_size.y = 10
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("background", ControlTheme.rounded(TRACK, 5))
	bar.add_theme_stylebox_override("fill", ControlTheme.rounded(FILL, 5))
	column.add_child(bar)
	var rules := HBoxContainer.new()
	column.add_child(rules)
	var left := text(left_rule, NOTE_SIZE, SOFT_INK)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rules.add_child(left)
	if not right_rule.is_empty(): rules.add_child(text(right_rule, NOTE_SIZE, SOFT_INK))
	return box

## A summary box's big figure in the title type.
static func big(value: String, title_font: Font) -> Label:
	return ShopKit.text(value, BIG, INK, title_type(title_font))

## The page's title font, or the shop pages' heading type without one.
static func title_type(title_font: Font) -> Font:
	return title_font if title_font != null else ShopKit.heading_font()

## The chapter's picture for a level id, small and rounded, or null when this build has none.
static func picture(level_id: String) -> Control:
	var key := PollenHistory.chapter_key(level_id)
	if key.is_empty() or not Thumbnails.has_picture(key): return null
	var frame := ChapterPicker.picture_frame(PICTURE, 0)
	frame.name = "ChapterPicture"
	ThumbnailShelf.fill(frame.get_child(0) as TextureRect, Thumbnails.path(key))
	return frame

static func rule() -> ColorRect:
	var line := ColorRect.new()
	line.color = Color(0, 0, 0, 0.08)
	line.custom_minimum_size.y = 1
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line

static func text(value: String, size: int, color: Color) -> Label:
	return ShopKit.text(value, size, color)

static func wrapped(value: String, size: int, color: Color) -> Label:
	var label := text(value, size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label

static func heading(column: VBoxContainer, title: String, note: String, title_font: Font) -> void:
	column.add_child(ShopKit.text(title, 23, INK, title_type(title_font)))
	column.add_child(wrapped(note, 15, SOFT_INK))
