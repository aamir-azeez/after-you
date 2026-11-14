extends RefCounted
## The community rules as a card in the public duel card kit (owner-approved board A, 2026-11-14,
## claude-20261011\rules-page\board.png): the photo flow's rules view (safety_screen.gd, rules only) and the
## public duel entry card (duels/public_sheets.gd rules_entry) build from these, so both read the same.
const Kit = preload("res://presentation/duels/duel_kit.gd")
const UiTokens = preload("res://presentation/ui_tokens.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const OfflineHold = preload("res://presentation/offline_hold.gd")
const CAMERA = preload("res://assets/ui/room/camera.svg")
const NOPE = preload("res://assets/ui/social/minus-circle.svg")
const INFO = preload("res://assets/ui/social/info.svg")
const WIDTH := 940.0
const RULE_SIZE := 26
const ACTION_HEIGHT := 56.0
const LINKS := [["Read community rules", "/community-rules"], ["Privacy policy", "/privacy"], ["Account deletion information", "/account-deletion"]]

## The player's own pip and a second one (wearing `look`) before the card's title.
static func pips(header: HBoxContainer, look: Variant = {}) -> void:
	var pair := HBoxContainer.new()
	pair.name = "RulesPips"
	pair.add_theme_constant_override("separation", 2)
	pair.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pair.add_child(Kit.pip(Vector2(40, 48), Kit.FIRST_PIP, true))
	pair.add_child(Kit.pip(Vector2(40, 48), Kit.SECOND_PIP, false, look))
	header.add_child(pair)
	header.move_child(pair, 0)

## The two rules, each whole with its icon.
static func rules(content: VBoxContainer) -> void:
	content.add_theme_constant_override("separation", 14)
	content.add_child(row(CAMERA, PlayerCopy.RULES_SHARE, RULE_SIZE, UiTokens.MINT))
	content.add_child(row(NOPE, PlayerCopy.RULES_NOT_ALLOWED, RULE_SIZE, UiTokens.SOLO))

static func row(icon: Texture2D, words: String, size: int, tint: Color) -> HBoxContainer:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 14)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mark := TextureRect.new()
	mark.texture = icon
	mark.modulate = tint
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.custom_minimum_size = Vector2(28, 28)
	mark.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	line.add_child(mark)
	var label := Kit.wrapped(words, size, UiTokens.CREAM)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(label)
	return line

## The three public pages side by side; open(path) opens one.
static func links(open: Callable) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.name = "RulesLinks"
	box.add_theme_constant_override("separation", 10)
	for link: Array in LINKS:
		var path: String = link[1]
		var made := Kit.button(link[0], func() -> void: open.call(path), false, 46.0)
		made.add_theme_font_size_override("font_size", 18)
		made.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(made)
	return box

## A quiet line under the rules (what accepting means, the check, a refusal). It keeps two lines' room once in
## the card (keep_room), so the card stays put when the line changes while it checks.
static func note(words: String) -> Label:
	var label := Kit.wrapped(words, 20, UiTokens.SOFT)
	label.name = "RulesNote"
	return label

static func keep_room(label: Label) -> void:
	label.custom_minimum_size.y = label.get_line_height() * 2 + label.get_theme_constant("line_spacing")

## Rules accepted: the line with its mark.
static func accepted(words: String) -> HBoxContainer:
	var line := row(INFO, words, 22, UiTokens.MINT)
	line.name = "RulesAccepted"
	return line

## The bottom buttons: [label, action, primary, name] each, side by side at the same height.
static func actions(buttons: Array) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.name = "RulesActions"
	box.add_theme_constant_override("separation", 14)
	for spec: Array in buttons:
		var made := Kit.button(spec[0], spec[1], spec[2], ACTION_HEIGHT)
		made.name = spec[3]
		made.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(made)
	return box

## Holds the card while it checks: every action greyed, `waiting` (Checking…) on the one named `busy_name`.
static func hold(box: Control, busy: bool, busy_name: String, idle_text: String) -> void:
	for made: Button in box.find_children("*", "Button", true, false):
		if made.get_parent().name != "RulesActions": continue
		# A button held while offline stays greyed until the connection is back (offline_hold.gd).
		OfflineHold.set_enabled(made, not busy)
		if made.name != busy_name: continue
		made.text = PlayerCopy.RULES_CHECKING if busy else idle_text
		# A held button shows no focus ring (board A).
		if busy and made.has_focus(): made.release_focus()
