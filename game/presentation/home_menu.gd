extends Control
## Home's menu (layout A): a solid panel down the left edge with the wordmark,
## the line under it, Play with your friend, Play Solo, Friends and Replays
## rows (and Wardrobe, while the server has the wardrobe on: show_wardrobe),
## Invite your friends, and What's new beside the Settings cog at the bottom.
## Full Journey sits apart at the island's top right, with the Pollen chip
## (kit/pollen_chip.gd, set_pollen_chip) left of it. Main builds it
## with build() and owns every action; this script only lays the menu out.
## Layout runs on resize and when the What's new tip comes or goes, never per
## frame.
##
## The Play button has an empty icon slot, HomePlayIcon (PLAY_ICON_SIZE, left in
## the pill). set_play_icon() drops a Control into it, and the label moves right
## to make room; set_play_icon(null) empties it and the label returns. The icon
## gets the whole slot and never takes input. If it has attach_to(button) (as
## presentation/friend_play_icon.gd does), set_play_icon() calls it with the Play button, so the icon can follow hover
## and press (mouse_entered/mouse_exited, button_down/button_up).
const UiTokens = preload("res://presentation/ui_tokens.gd")
const ControlTheme = preload("res://presentation/control_theme.gd")
const SafeArea = preload("res://presentation/safe_area.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const WhatsNewCard = preload("res://presentation/whats_new_card.gd")
const PipAvatar = preload("res://presentation/kit/pip_avatar.gd")
## The Wardrobe row's icon: the player's own pip in its look, a still picture
## from the shared renderer (kit/pip_snapshots.gd), so Home gains no live view.
const WARDROBE_PIP := Vector2(30, 38)

const PANEL_WIDTH := UiTokens.HOME_PANEL_WIDTH
## The column runs from 64 to 32 short of the panel's edge; the bottom row
## starts 12 further left, so its icons line up with the rows' icons.
const BOTTOM_LEFT := 52.0
const COLUMN_INDENT := 12.0
const RIGHT := 32.0
const PLAY_ICON_SIZE := Vector2(72, 58)
const PLAY_ICON_LEFT := 10.0
const PLAY_ICON_GAP := 12.0
## set_play_icon() calls this on the icon, if it has it, with the Play button.
const PLAY_ICON_FOLLOW := "attach_to"
## The Play label's inset when the slot is empty.
const PLAY_TEXT_INSET := 24.0
## Room above What's new for its tip while the notes are unseen.
const TIP_ROOM := 50.0
const CHEVRON := preload("res://assets/ui/settings/chevron.svg")
## Sizes for a full-height screen, and for one with less room (cutout insets).
const REGULAR := {"wordmark": 88, "subtitle": 20, "play": 76, "row": 52, "invite": 56, "gaps": [14, 24, 8, 10, 14], "top": 24, "bottom": 16, "play_font": 23, "row_font": 21}
const COMPACT := {"wordmark": 64, "subtitle": 18, "play": 64, "row": 48, "invite": 52, "gaps": [6, 14, 4, 6, 8], "top": 16, "bottom": 12, "play_font": 21, "row_font": 20}
## For a short window (a desktop one, say): every target still 48 high.
const TIGHT := {"wordmark": 50, "subtitle": 16, "play": 60, "row": 48, "invite": 48, "gaps": [4, 8, 2, 4, 4], "top": 10, "bottom": 8, "play_font": 20, "row_font": 19}
## Largest first; the menu takes the first that fits its height.
const DENSITIES := {"regular": REGULAR, "compact": COMPACT, "tight": TIGHT}

var play_button: Button
var play_icon_slot: Control
var solo_button: Button
var friends_button: Button
var replays_button: Button
var wardrobe_button: Button
var _wardrobe_pip: Control
var invite_button: Button
var whats_new_button: Button
var settings_button: Button
var journey_offer: Button
## The Pollen chip's slot, at the top right left of Full Journey (or in its place when it is hidden).
var pollen_slot: HBoxContainer
var compact := false
var _panel: Control
var _margin: MarginContainer
var _wordmark: Label
var _wordmark_box: Control
var _subtitle: Label
var _gaps: Array[Control] = []
var _tip_room: Control
var _bottom_rule: ColorRect
## The tip sits beside What's new while it fits there, else above it.
var _tip_above := false
var _heading_font: Font
var _density := ""

## Builds the menu and adds Full Journey beside it in the same parent.
## `actions`: play (called with the Play button), solo, friends, replays,
## invite, whats_new, settings, full_journey, and wardrobe (optional).
func build(actions: Dictionary, heading_font: Font) -> void:
	name = "HomeMenu"
	_heading_font = heading_font
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel = Control.new()
	_panel.name = "HomePanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	# The panel's colour reaches the screen's edges, under a cutout too.
	SafeArea.bleed(_panel)
	_panel.draw.connect(_draw_panel)
	_panel.item_rect_changed.connect(_panel.queue_redraw)
	item_rect_changed.connect(_panel.queue_redraw)
	_margin = MarginContainer.new()
	_margin.name = "HomeMenuMargin"
	_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_margin.anchor_bottom = 1.0
	_margin.offset_right = PANEL_WIDTH
	_margin.add_theme_constant_override("margin_left", int(BOTTOM_LEFT))
	_margin.add_theme_constant_override("margin_right", int(RIGHT))
	add_child(_margin)
	var stack := _vbox(_margin)
	# The column sits centred in the room above the bottom row.
	stack.add_child(_spacer())
	var indent := MarginContainer.new()
	indent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	indent.add_theme_constant_override("margin_left", int(COLUMN_INDENT))
	stack.add_child(indent)
	var column := _vbox(indent)
	column.name = "HomeColumn"
	# The wordmark's lines sit 0.84 of its size apart, as in the logo. A label's
	# first line always holds the font's full height, so the label sits in a box
	# of the two lines' height, nudged up by half the difference.
	_wordmark_box = Control.new()
	_wordmark_box.name = "HomeWordmarkBox"
	_wordmark_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_wordmark_box)
	_wordmark = _label("After\nYou", UiTokens.CREAM, _wordmark_box)
	_wordmark.name = "HomeWordmark"
	_wordmark.add_theme_font_override("font", heading_font)
	_gaps.append(_gap(column))
	_subtitle = _label(PlayerCopy.MAIN_6A7ECC3FD1B9, UiTokens.MUTED, column)
	_subtitle.name = "HomeSubtitle"
	_gaps.append(_gap(column))
	play_button = _play(column)
	play_button.pressed.connect(actions.play.bind(play_button))
	_gaps.append(_gap(column))
	solo_button = _row(column, "Play Solo", preload("res://assets/ui/social/user.svg"), actions.solo, "HomeSolo")
	friends_button = _row(column, "Friends", preload("res://assets/ui/social/users.svg"), actions.friends, "HomeFriends")
	friends_button.tooltip_text = "Friends"
	friends_button.accessibility_name = "Friends"
	replays_button = _row(column, "Replays", preload("res://assets/ui/play-circle.svg"), actions.replays, "HomeReplays")
	wardrobe_button = _wardrobe_row(column, actions.get("wardrobe", Callable()))
	_gaps.append(_gap(column))
	var rule := ColorRect.new()
	rule.name = "HomeRule"
	rule.color = UiTokens.RULE
	rule.custom_minimum_size = Vector2(0, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(rule)
	_gaps.append(_gap(column))
	invite_button = _row(column, PlayerCopy.HOME_INVITE, preload("res://assets/ui/social/share-network.svg"), actions.invite, "HomeInvite")
	invite_button.tooltip_text = PlayerCopy.INVITE_LINK_SHARE
	_outline(invite_button, 18, 22.0)
	stack.add_child(_spacer())
	_tip_room = Control.new()
	_tip_room.name = "HomeTipRoom"
	_tip_room.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip_room.custom_minimum_size.y = TIP_ROOM
	_tip_room.visible = false
	stack.add_child(_tip_room)
	var bottom := HBoxContainer.new()
	bottom.name = "HomeBottomRow"
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_theme_constant_override("separation", 0)
	stack.add_child(bottom)
	whats_new_button = _flat(PlayerCopy.WHATS_NEW, actions.whats_new)
	whats_new_button.name = "HomeWhatsNew"
	whats_new_button.icon = preload("res://assets/ui/whats_new/gift.svg")
	whats_new_button.add_theme_constant_override("h_separation", 12)
	_pad(whats_new_button, 12.0, 12.0)
	whats_new_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bottom.add_child(whats_new_button)
	bottom.add_child(_spacer(true))
	var bar := ColorRect.new()
	_bottom_rule = bar
	bar.name = "HomeBottomRule"
	bar.color = UiTokens.RULE
	bar.custom_minimum_size = Vector2(1, 28)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(bar)
	var gap := Control.new()
	gap.custom_minimum_size.x = 18
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(gap)
	settings_button = _flat("", actions.settings)
	settings_button.name = "HomeSettings"
	settings_button.icon = preload("res://assets/ui/social/gear.svg")
	settings_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	settings_button.expand_icon = true
	settings_button.add_theme_constant_override("icon_max_width", 28)
	settings_button.tooltip_text = "Settings"
	settings_button.accessibility_name = "Settings"
	_pad(settings_button, 12.0, 12.0)
	settings_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bottom.add_child(settings_button)
	journey_offer = _journey(actions.full_journey)
	get_parent().add_child(journey_offer)
	pollen_slot = HBoxContainer.new()
	pollen_slot.name = "HomePollenSlot"
	pollen_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pollen_slot.visible = false
	pollen_slot.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	pollen_slot.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	pollen_slot.offset_top = UiTokens.HOME_TOP
	pollen_slot.offset_bottom = UiTokens.HOME_TOP + 54.0
	get_parent().add_child(pollen_slot)
	# The chip follows Full Journey's width and whether it shows; never per frame.
	journey_offer.resized.connect(_place_pollen)
	journey_offer.visibility_changed.connect(_place_pollen)
	_place_pollen()
	resized.connect(_fit)
	_fit()
	# A wrapped line knows its height once laid out; check the fit again then.
	_fit.call_deferred()

## Fills the Play button's icon slot (or empties it, with null). The icon fills
## the whole PLAY_ICON_SIZE slot and never takes input. An icon with a
## PLAY_ICON_FOLLOW method is handed the Play button, so it can follow hover
## and press.
func set_play_icon(icon: Control) -> void:
	for child: Node in play_icon_slot.get_children():
		play_icon_slot.remove_child(child)
		child.queue_free()
	if icon != null:
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		play_icon_slot.add_child(icon)
		if icon.has_method(PLAY_ICON_FOLLOW): icon.call(PLAY_ICON_FOLLOW, play_button)
	_pad_play()

## Shows or hides the Wardrobe row (the server's wardrobe capability), then
## fits the column to the height again. Its pip is drawn only while it shows.
func show_wardrobe(available: bool) -> void:
	if not is_instance_valid(wardrobe_button) or wardrobe_button.visible == available: return
	wardrobe_button.visible = available
	if available: refresh_wardrobe_look()
	_density = ""
	if is_inside_tree(): _fit()

## The row's pip follows what the player wears (services/own_look.gd).
func refresh_wardrobe_look() -> void:
	if not is_instance_valid(wardrobe_button) or not wardrobe_button.visible: return
	if is_instance_valid(_wardrobe_pip):
		wardrobe_button.remove_child(_wardrobe_pip)
		_wardrobe_pip.queue_free()
	_wardrobe_pip = PipAvatar.new(true, PipAvatar.PEACH, WARDROBE_PIP, true, true)
	_wardrobe_pip.name = "HomeWardrobePip"
	_wardrobe_pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wardrobe_pip.anchor_top = 0.5
	_wardrobe_pip.anchor_bottom = 0.5
	_wardrobe_pip.offset_left = 9.0
	_wardrobe_pip.offset_right = 9.0 + WARDROBE_PIP.x
	_wardrobe_pip.offset_top = -WARDROBE_PIP.y * 0.5 - 2.0
	_wardrobe_pip.offset_bottom = WARDROBE_PIP.y * 0.5 - 2.0
	wardrobe_button.add_child(_wardrobe_pip)

## The Wardrobe row: like the others, with an empty icon the size of theirs so
## its words line up, and the pip drawn over that slot. Hidden until the server
## has the wardrobe on.
func _wardrobe_row(parent: Container, action: Callable) -> Button:
	var blank := Image.create(24, 24, false, Image.FORMAT_RGBA8)
	var button := _row(parent, PlayerCopy.WARDROBE_OPEN, ImageTexture.create_from_image(blank), action, "HomeWardrobe")
	button.tooltip_text = PlayerCopy.WARDROBE_OPEN
	button.accessibility_name = PlayerCopy.WARDROBE_OPEN
	button.visible = false
	return button

func has_play_icon() -> bool:
	for child: Node in play_icon_slot.get_children():
		if not child.is_queued_for_deletion() and (not child is CanvasItem or (child as CanvasItem).visible): return true
	return false

## The What's new dot (on the gift) and its tip, until the card opens. The tip
## sits beside the button, over the bottom row's empty run, while it fits there;
## a longer one goes above the button, and the column makes room for it.
func mark_whats_new_unseen(version: String) -> void:
	WhatsNewCard.mark_unseen(whats_new_button, version, WhatsNewCard.BESIDE)
	if not whats_new_button.child_exiting_tree.is_connected(_on_mark_leaving):
		whats_new_button.child_exiting_tree.connect(_on_mark_leaving)
	_show_tip_room()

func _on_mark_leaving(_child: Node) -> void:
	_show_tip_room.call_deferred()

## Keeps room for the tip only while it shows.
func _show_tip_room() -> void:
	if is_inside_tree() and is_instance_valid(_tip_room): _fit()

func _tip_showing() -> bool:
	var tip := whats_new_button.get_node_or_null("WhatsNewTip")
	return tip != null and not tip.is_queued_for_deletion() and tip.is_inside_tree()

## The controls Home's stage must leave to their own input.
func header_actions() -> Array[Control]:
	return [journey_offer, pollen_slot, settings_button, whats_new_button]

## Puts the Pollen chip left of Full Journey, or takes it away (null).
func set_pollen_chip(chip: Control) -> void:
	for child: Node in pollen_slot.get_children():
		pollen_slot.remove_child(child)
		child.queue_free()
	if chip != null: pollen_slot.add_child(chip)
	pollen_slot.visible = chip != null
	_place_pollen()

func _place_pollen() -> void:
	if not is_instance_valid(pollen_slot): return
	var right := RIGHT + (journey_offer.size.x + 14.0 if journey_offer.visible else 0.0)
	pollen_slot.offset_right = -right
	pollen_slot.offset_left = -right - 1.0

func _fit() -> void:
	var tip := whats_new_button.get_node_or_null("WhatsNewTip") as Control if _tip_showing() else null
	for attempt in range(2):
		_tip_room.visible = tip != null and _tip_above
		# Full sizes when they fit the height, else the first smaller set that does.
		for density_name: String in DENSITIES:
			_apply(density_name)
			if _margin.get_combined_minimum_size().y <= size.y + 0.5: break
		if tip == null: break
		# Beside: from just after What's new (its own padding gives the gap) to just before the cog.
		var room := PANEL_WIDTH - BOTTOM_LEFT - RIGHT - whats_new_button.get_combined_minimum_size().x - settings_button.custom_minimum_size.x - 8.0
		var above := tip.get_combined_minimum_size().x > room
		if above == _tip_above: break
		_tip_above = above
	if tip != null: WhatsNewCard.place_tip(whats_new_button, WhatsNewCard.ABOVE if _tip_above else WhatsNewCard.BESIDE)
	# The tip beside the button covers the bottom row's rule.
	_bottom_rule.visible = tip == null or _tip_above
	# Too short even then (a small desktop window): the tip gives its room back
	# and sits over the gap above the bottom row, still on screen.
	if _tip_room.visible and _margin.get_combined_minimum_size().y > size.y + 0.5:
		_tip_room.visible = false
	compact = _density != "regular"
	# A margin grown for the taller sizes keeps that height; fit it to the menu again.
	_margin.set_deferred("size", Vector2(PANEL_WIDTH, maxf(size.y, _margin.get_combined_minimum_size().y)))

func _apply(density_name: String) -> void:
	if _density == density_name: return
	_density = density_name
	var density: Dictionary = DENSITIES[density_name]
	_margin.add_theme_constant_override("margin_top", int(density.top))
	_margin.add_theme_constant_override("margin_bottom", int(density.bottom))
	var mark := int(density.wordmark)
	_wordmark.add_theme_font_size_override("font_size", mark)
	var line := roundf(mark * 0.84)
	var height := _heading_font.get_height(mark)
	_wordmark.add_theme_constant_override("line_spacing", roundi(line - height))
	_wordmark_box.custom_minimum_size.y = line * 2.0
	_wordmark.position = Vector2(0, roundf((line - height) * 0.5))
	_wordmark.size = _wordmark.get_combined_minimum_size()
	_subtitle.add_theme_font_size_override("font_size", int(density.subtitle))
	# The line already breaks after "friend"; its two lines sit 1.4 of the size apart.
	var body := _subtitle.get_theme_font("font")
	_subtitle.add_theme_constant_override("line_spacing", roundi(int(density.subtitle) * 1.4 - body.get_height(int(density.subtitle))))
	for index in range(_gaps.size()): _gaps[index].custom_minimum_size.y = density.gaps[index]
	play_button.custom_minimum_size.y = density.play
	play_button.add_theme_font_size_override("font_size", int(density.play_font))
	for row: Button in [solo_button, friends_button, replays_button, wardrobe_button, whats_new_button]:
		row.custom_minimum_size.y = density.row
		row.add_theme_font_size_override("font_size", int(density.row_font) - (2 if row == whats_new_button else 0))
	settings_button.custom_minimum_size = Vector2(density.row, density.row)
	invite_button.custom_minimum_size.y = density.invite
	invite_button.add_theme_font_size_override("font_size", int(density.row_font))

func _draw_panel() -> void:
	# From the screen's left edge to the panel's right edge, with a fine edge line.
	var right := global_position.x + PANEL_WIDTH - _panel.global_position.x
	_panel.draw_rect(Rect2(0, 0, right, _panel.size.y), UiTokens.PANEL)
	_panel.draw_rect(Rect2(right - 1.0, 0, 1.0, _panel.size.y), UiTokens.PANEL_EDGE)

func _play(parent: Container) -> Button:
	var button := Button.new()
	button.name = "HomePlay"
	button.text = "Play with your friend"
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var bold := FontVariation.new()
	bold.base_font = preload("res://assets/fonts/nunito.ttf")
	bold.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 700.0}
	button.add_theme_font_override("font", bold)
	parent.add_child(button)
	# The theme's cream primary, rounder; Play keeps its own fills per state.
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		var style := button.get_theme_stylebox(state).duplicate() as StyleBoxFlat
		if style == null: continue
		style.set_corner_radius_all(22)
		style.content_margin_right = 20.0
		style.content_margin_top = 0.0
		style.content_margin_bottom = 0.0
		button.add_theme_stylebox_override(state, style)
	play_icon_slot = Control.new()
	play_icon_slot.name = "HomePlayIcon"
	play_icon_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	play_icon_slot.anchor_top = 0.5
	play_icon_slot.anchor_bottom = 0.5
	play_icon_slot.offset_left = PLAY_ICON_LEFT
	play_icon_slot.offset_right = PLAY_ICON_LEFT + PLAY_ICON_SIZE.x
	play_icon_slot.offset_top = -PLAY_ICON_SIZE.y * 0.5
	play_icon_slot.offset_bottom = PLAY_ICON_SIZE.y * 0.5
	button.add_child(play_icon_slot)
	play_icon_slot.child_entered_tree.connect(func(_child: Node) -> void: _pad_play.call_deferred())
	play_icon_slot.child_exiting_tree.connect(func(_child: Node) -> void: _pad_play.call_deferred())
	play_button = button
	_pad_play()
	return button

## The label starts after the icon when the slot holds one, else near the edge.
func _pad_play() -> void:
	if not is_instance_valid(play_button): return
	var left := PLAY_ICON_LEFT + PLAY_ICON_SIZE.x + PLAY_ICON_GAP if has_play_icon() else PLAY_TEXT_INSET
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		if not play_button.has_theme_stylebox_override(state): continue
		var style := play_button.get_theme_stylebox(state)
		if style.content_margin_left != left: style.content_margin_left = left

## A labelled row on the panel: icon, label and a chevron at the right.
func _row(parent: Container, text: String, icon: Texture2D, action: Callable, node_name: String) -> Button:
	var button := _flat(text, action)
	button.name = node_name
	button.icon = icon
	button.add_theme_constant_override("h_separation", 18)
	_pad(button, 12.0, 44.0)
	parent.add_child(button)
	var chevron := TextureRect.new()
	chevron.name = "Chevron"
	chevron.texture = CHEVRON
	chevron.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	chevron.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	chevron.self_modulate = UiTokens.MUTED
	chevron.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chevron.anchor_left = 1.0
	chevron.anchor_right = 1.0
	chevron.anchor_top = 0.5
	chevron.anchor_bottom = 0.5
	chevron.offset_left = -34.0
	chevron.offset_right = -10.0
	chevron.offset_top = -12.0
	chevron.offset_bottom = 12.0
	button.add_child(chevron)
	return button

## A borderless control on the dark panel: cream text and icon in every state,
## a faint fill on hover and the selected teal while pressed.
func _flat(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_constant_override("icon_max_width", 24)
	button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	var fills := {"normal": Color.TRANSPARENT, "hover": UiTokens.ROW_HOVER, "pressed": UiTokens.SELECTED, "hover_pressed": UiTokens.SELECTED, "disabled": Color.TRANSPARENT}
	for state: String in fills:
		button.add_theme_stylebox_override(state, ControlTheme.rounded(fills[state], 14))
	button.add_theme_stylebox_override("focus", ControlTheme.rounded(Color.TRANSPARENT, 14, UiTokens.MINT))
	for key: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color", "icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color", "icon_focus_color"]:
		button.add_theme_color_override(key, UiTokens.CREAM)
	button.add_theme_color_override("font_disabled_color", UiTokens.MUTED)
	button.add_theme_color_override("icon_disabled_color", UiTokens.MUTED)
	if action.is_valid(): button.pressed.connect(action)
	return button

## Content insets on every state of a control's own styles.
static func _pad(button: Button, left: float, right: float) -> void:
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		if not button.has_theme_stylebox_override(state): continue
		var style := button.get_theme_stylebox(state)
		style.content_margin_left = left
		style.content_margin_right = right
		style.content_margin_top = 0.0
		style.content_margin_bottom = 0.0

## An outlined pill: a fine edge, transparent until hovered or pressed.
static func _outline(button: Button, radius: int, left: float) -> void:
	var fills := {"normal": Color.TRANSPARENT, "hover": UiTokens.ROW_HOVER, "pressed": UiTokens.SELECTED, "hover_pressed": UiTokens.SELECTED, "disabled": Color.TRANSPARENT}
	for state: String in fills:
		var style := ControlTheme.rounded(fills[state], radius, UiTokens.SECONDARY_BORDER)
		style.set_border_width_all(2)
		button.add_theme_stylebox_override(state, style)
	var ring := ControlTheme.rounded(Color.TRANSPARENT, radius, UiTokens.MINT)
	ring.set_border_width_all(2)
	button.add_theme_stylebox_override("focus", ring)
	_pad(button, left, 44.0)

## Full Journey: an outlined pill over the island, label then arrow.
func _journey(action: Callable) -> Button:
	var button := Button.new()
	button.name = "HomeFullJourney"
	button.text = "Full Journey"
	button.icon = preload("res://assets/ui/social/arrow-right.svg")
	button.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_constant_override("icon_max_width", 24)
	button.add_theme_constant_override("h_separation", 14)
	button.add_theme_font_override("font", _heading_font)
	button.add_theme_font_size_override("font_size", 21)
	var fills := {"normal": UiTokens.NIGHT_GLASS, "hover": UiTokens.SECONDARY, "pressed": UiTokens.SELECTED, "hover_pressed": UiTokens.SELECTED, "disabled": UiTokens.NIGHT_GLASS}
	for state: String in fills:
		var style := ControlTheme.rounded(fills[state], 16, UiTokens.SECONDARY_BORDER)
		style.set_border_width_all(2)
		button.add_theme_stylebox_override(state, ControlTheme.padded(style, 22.0, 0.0))
	var ring := ControlTheme.rounded(Color.TRANSPARENT, 16, UiTokens.MINT)
	ring.set_border_width_all(2)
	button.add_theme_stylebox_override("focus", ControlTheme.padded(ring, 22.0, 0.0))
	for key: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color", "icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color", "icon_focus_color"]:
		button.add_theme_color_override(key, UiTokens.CREAM)
	if action.is_valid(): button.pressed.connect(action)
	button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	button.offset_right = -RIGHT
	button.offset_left = -RIGHT - 1.0
	button.offset_top = UiTokens.HOME_TOP
	button.offset_bottom = UiTokens.HOME_TOP + 54.0
	return button

static func _vbox(parent: Node) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 0)
	parent.add_child(box)
	return box

static func _spacer(horizontal := false) -> Control:
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if horizontal: spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else: spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return spacer

static func _gap(parent: Node) -> Control:
	var gap := Control.new()
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(gap)
	return gap

static func _label(text: String, color: Color, parent: Node) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label
