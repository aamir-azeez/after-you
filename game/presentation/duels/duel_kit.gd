extends RefCounted
## The duel pages' shared pieces (presentation/duels/): panels, text, the two
## button looks, a pair of still pips, a chapter picture and a row of step
## dots. Every page builds from these, so the lobby, the duel page and the
## result page look the same. Pips are always still (kit/pip_avatar.gd), so a
## page of tiles runs no 3D views and draws nothing per frame. Every pip wears
## its player's look: this player's own from services/own_look.gd, anyone
## else's as the server sent it, cleaned by services/outfit.gd, so an item
## this build is not offered never shows. A friend the duel replies say nothing
## about (the party page's friends, Start a duel's list) wears the look this
## phone last heard them wear in a room (last_seen).
const ThemeRules = preload("res://presentation/control_theme.gd")
const UiTokens = preload("res://presentation/ui_tokens.gd")
const SettingsKit = preload("res://presentation/settings_kit.gd")
const PipAvatar = preload("res://presentation/kit/pip_avatar.gd")
const ChapterPicker = preload("res://presentation/chapter_picker.gd")
const ThumbnailShelf = preload("res://presentation/chapter_thumbnail_shelf.gd")
const Thumbnails = preload("res://services/chapter_thumbnail_catalog.gd")
const Dots = preload("res://presentation/duels/duel_dots.gd")
const Outfit = preload("res://services/outfit.gd")
const TurnLooks = preload("res://services/turn_looks.gd")
const BACKGROUND := Color("123936")
const PANEL_FILL := Color("163f3b")
const PANEL_EDGE := Color("2d5a53")
const CARD_FILL := Color("1b4641")
const LANE_FILL := Color("123531")
const HIGHLIGHT_EDGE := Color("a6d9c4")
## The worlds' pips by slot, as the leaderboard rows draw them.
const FIRST_PIP := Color("f4c38d")
const SECOND_PIP := Color("91d6c6")

static func text(value: String, font_size: int, ink: Color = UiTokens.CREAM, heading: bool = false) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", ink)
	label.add_theme_font_override("font", SettingsKit.font(600, heading))
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label

static func wrapped(value: String, font_size: int, ink: Color = UiTokens.SOFT) -> Label:
	var label := text(value, font_size, ink)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

static func panel(node_name: String, fill: Color = PANEL_FILL, edge: Color = PANEL_EDGE, radius: int = 18, pad: float = 14.0) -> PanelContainer:
	var box := PanelContainer.new()
	box.name = node_name
	var style := ThemeRules.rounded(fill, radius, edge)
	ThemeRules.padded(style, pad, pad * 0.75)
	box.add_theme_stylebox_override("panel", style)
	return box

## The cream primary (the theme's own button) or the outlined secondary.
static func button(label: String, action: Callable, primary: bool = true, height: float = 52.0) -> Button:
	var made := Button.new()
	made.text = label
	made.custom_minimum_size = Vector2(0, height)
	made.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if not primary: ThemeRules.secondary(made)
	if action.is_valid(): made.pressed.connect(action)
	return made

## Puts `texture` on `made` at a fixed size, at its right end unless `left`.
static func icon_on(made: Button, texture: Texture2D, left: bool = false, width: int = 24) -> void:
	made.icon = texture
	made.expand_icon = true
	made.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT if left else HORIZONTAL_ALIGNMENT_RIGHT
	made.add_theme_constant_override("icon_max_width", width)
	made.add_theme_constant_override("h_separation", 14)

## A small rounded label: mint for "Your turn", glass for anything else.
static func pill(value: String, lit: bool, font_size: int = 17) -> PanelContainer:
	var box := PanelContainer.new()
	var style := ThemeRules.rounded(UiTokens.MINT if lit else Color("204d47"), 10, Color.TRANSPARENT if lit else PANEL_EDGE)
	ThemeRules.padded(style, 14.0, 3.0)
	box.add_theme_stylebox_override("panel", style)
	box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := text(value, font_size, UiTokens.INK if lit else UiTokens.CREAM, lit)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(label)
	return box

## A pair's two still pips in slot order (services/duel_model.gd members and
## looks): the member who is `me` is this player's own pip in their own look,
## wherever they sit; every other wears `looks` at its slot.
static func pips(pip_size: Vector2, members: Array = [null, null], me: String = "", looks: Array = [], separation: int = 4) -> HBoxContainer:
	var pair := HBoxContainer.new()
	pair.add_theme_constant_override("separation", separation)
	pair.alignment = BoxContainer.ALIGNMENT_CENTER
	pair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for index in range(2):
		var member: Variant = members[index] if index < members.size() else null
		pair.add_child(pip(pip_size, FIRST_PIP if index == 0 else SECOND_PIP, member != null and not me.is_empty() and member == me, looks[index] if index < looks.size() else {}))
	return pair

## A single still pip: the player's own when `own`, otherwise wearing `look`.
static func pip(pip_size: Vector2, color: Color, own: bool = false, look: Variant = {}) -> Control:
	var made := PipAvatar.new(true, color, pip_size, true, own)
	made.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if not own: made.wear(Outfit.from(look))
	return made

## The look this phone last heard `id` wear in a room (services/turn_looks.gd
## members), or {} for someone it never shared a room with. No request.
static func last_seen(id: Variant) -> Dictionary:
	return TurnLooks.shared().member(str(id)) if id is String else {}

## The chapter's real capture in a rounded frame, loaded off the main thread.
static func picture(key: String, frame_size: Vector2, radius: int = 12) -> PanelContainer:
	var frame := ChapterPicker.picture_frame(frame_size, radius)
	ThumbnailShelf.fill(frame.get_child(0) as TextureRect, Thumbnails.path(key))
	return frame

## Step dots no wider than `width`: a long chapter's dots shrink, down to 8 pixels.
static func dots_within(done: int, total: int, width: float, largest: float = 24.0) -> Control:
	return dots(done, total, clampf(width / maxf(1.0, total * 1.45), 8.0, largest))

## A result's stages: a dot per stage on one joined line that ends in the chapter's round badge.
static func stage_line(done: int, total: int, key: String, width: float, badge: float = 44.0) -> HBoxContainer:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 0)
	line.alignment = BoxContainer.ALIGNMENT_CENTER
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dot := clampf((width - badge - 12.0) / maxf(1.0, total * 2.0 - 1.0), 8.0, 24.0)
	var row := Dots.new()
	row.name = "ResultStages"
	row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.setup(done, total, dot, 12.0)
	line.add_child(row)
	var frame := picture(key, Vector2(badge, badge), int(badge * 0.5))
	frame.name = "ResultChapterBadge"
	line.add_child(frame)
	return line

static func dots(done: int, total: int, dot: float = 16.0) -> Control:
	var row := Dots.new()
	row.setup(done, total, dot)
	return row

## Removes children at once, so new ones keep their names.
static func clear(holder: Node) -> void:
	for child: Node in holder.get_children():
		holder.remove_child(child)
		child.queue_free()

static func showing(node: Variant) -> bool:
	return is_instance_valid(node) and not node.is_queued_for_deletion()
