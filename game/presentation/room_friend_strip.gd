extends RefCounted
## The room's friend strip: the friend's avatar, name and status line. It tops
## the wide room panel and, with the stage line, is Room options' card. Before
## a friend joins it shows a quiet placeholder avatar and the caller's title.
const ControlTheme = preload("res://presentation/control_theme.gd")
const PlayerAvatar = preload("res://presentation/player_avatar.gd")
const USERS_ICON = preload("res://assets/ui/social/users.svg")
const CREAM := Color("eceddb")
const MUTED := Color("afc7bd")

## friend_id: the joined friend's player id, or "" before anyone joins.
## status: the line under the title (a presence badge or a plain label), or null.
static func build(friend_id: String, title: String, status: Label, heading_font: Font, avatar_size: float) -> HBoxContainer:
	var strip := HBoxContainer.new()
	strip.name = "RoomFriendStrip"
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_theme_constant_override("separation", 14)
	strip.add_child(_avatar(friend_id, avatar_size))
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_theme_constant_override("separation", 0)
	strip.add_child(text)
	var name := Label.new()
	# Tests and the legacy room page read the friend's status under this name.
	name.name = "RoomFriendStatus"
	name.text = title
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name.add_theme_font_override("font", heading_font)
	name.add_theme_font_size_override("font_size", 26 if avatar_size >= 48.0 else 23)
	name.add_theme_color_override("font_color", CREAM)
	text.add_child(name)
	if status != null: text.add_child(status)
	return strip

## A plain status line for the strip, in its muted colour.
static func line(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", MUTED)
	return label

## Room options' card: the strip on a darker panel, the stage line at its right.
static func card(strip: HBoxContainer, stage_line: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "RoomFriendCard"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", ControlTheme.padded(ControlTheme.rounded(Color("173f39"), 16, Color("3f6b61")), 16.0, 12.0))
	if not stage_line.is_empty():
		var stage := line(stage_line)
		stage.name = "RoomFriendCardStage"
		stage.autowrap_mode = TextServer.AUTOWRAP_OFF
		stage.add_theme_font_size_override("font_size", 18)
		stage.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		strip.add_child(stage)
	panel.add_child(strip)
	return panel

static func _avatar(friend_id: String, size: float) -> Control:
	if not friend_id.is_empty():
		var avatar := TextureRect.new()
		avatar.name = "FriendAvatar"
		avatar.texture = PlayerAvatar.texture_for(friend_id)
		_fit(avatar, size)
		return avatar
	var placeholder := PanelContainer.new()
	placeholder.name = "FriendAvatarPlaceholder"
	placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	placeholder.custom_minimum_size = Vector2(size, size)
	placeholder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var inset := roundf(size * 0.26)
	placeholder.add_theme_stylebox_override("panel", ControlTheme.padded(ControlTheme.rounded(Color("2a5952"), int(size / 2.0)), inset, inset))
	var people := TextureRect.new()
	people.texture = USERS_ICON
	people.self_modulate = MUTED
	_fit(people, 0.0)
	placeholder.add_child(people)
	return placeholder

static func _fit(picture: TextureRect, size: float) -> void:
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.size_flags_vertical = Control.SIZE_SHRINK_CENTER if size > 0.0 else Control.SIZE_FILL
	if size > 0.0: picture.custom_minimum_size = Vector2(size, size)
