extends CanvasLayer
## What every duel page shares: the deep green page, a header with Back, a
## title, a quiet line beside it and an optional button at the right, and a
## body that lays out again only when the safe area changes. A page builds its
## body in _build() and redraws its content in _render(); it never redraws per
## frame. Back closes the page's own pop-up first, then the page.
const Kit = preload("res://presentation/duels/duel_kit.gd")
const ThemeRules = preload("res://presentation/control_theme.gd")
const SafeArea = preload("res://presentation/safe_area.gd")
const UiTokens = preload("res://presentation/ui_tokens.gd")
const SettingsKit = preload("res://presentation/settings_kit.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const BACK_ICON = preload("res://assets/ui/social/arrow-left.svg")
const ARROW_ICON = preload("res://assets/ui/social/arrow-right.svg")

signal closed
## A short line for the app's pop-up (presentation/toast.gd).
signal notice(text: String, news: bool)

## The layer this page draws on; a page opened over another draws one above it.
var stack_layer := 61
var root: Control
var body: Control
var compact := false
var _margin: MarginContainer
var _title: Label
var _subtitle: Label
var _header: HBoxContainer
var _alive := true
var _modal: Control

func _ready() -> void:
	layer = stack_layer
	root = Control.new()
	root.name = page_name()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = Theme.new()
	root.theme.default_font = SettingsKit.font(600)
	root.theme.default_font_size = 20
	root.theme.set_color("font_color", "Label", UiTokens.CREAM)
	ThemeRules.install_buttons(root.theme)
	add_child(root)
	var background := ColorRect.new()
	background.color = Kit.BACKGROUND
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(background)
	SafeArea.bleed(background)
	var behind := backdrop()
	if behind != null: root.add_child(behind)
	_margin = MarginContainer.new()
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(_margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	_margin.add_child(layout)
	_header = HBoxContainer.new()
	_header.add_theme_constant_override("separation", 18)
	layout.add_child(_header)
	var back := Button.new()
	back.name = page_name() + "Back"
	back.text = PlayerCopy.LEADERBOARD_BACK
	back.custom_minimum_size = Vector2(132, 52)
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ThemeRules.danger(back, BACK_ICON)
	back.pressed.connect(go_back)
	_header.add_child(back)
	_title = Kit.text(title_text(), 50, UiTokens.CREAM, true)
	_title.name = page_name() + "Title"
	_header.add_child(_title)
	_subtitle = Kit.text(subtitle_text(), 22, UiTokens.SOFT)
	_subtitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_subtitle.size_flags_vertical = Control.SIZE_SHRINK_END
	_subtitle.custom_minimum_size.y = 52
	_subtitle.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_header.add_child(_subtitle)
	var trailing := header_action()
	if trailing != null: _header.add_child(trailing)
	body = VBoxContainer.new()
	body.name = page_name() + "Body"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	(body as VBoxContainer).add_theme_constant_override("separation", 12)
	layout.add_child(body)
	SafeArea.watch(self, _layout)
	_layout()
	opened()

## The page's node name; overridden.
func page_name() -> String: return "DuelPage"
func title_text() -> String: return ""
func subtitle_text() -> String: return ""
## What draws between the page's green and its content, or null.
func backdrop() -> Control: return null
## A button at the header's right, or null.
func header_action() -> Control: return null
## Builds the body for the current size.
func _build() -> void: pass
## Called once, after the first build.
func opened() -> void: pass

func set_title(value: String, subtitle: String = "") -> void:
	if is_instance_valid(_title): _title.text = value
	if is_instance_valid(_subtitle): _subtitle.text = subtitle

func _layout() -> void:
	if not is_instance_valid(_margin): return
	var rect := get_viewport().get_visible_rect()
	var safe := SafeArea.rect(get_viewport())
	var now_compact := safe.size.x < 1100
	var side := SafeArea.centred(safe.size.x, 1240, 18)
	var tall := SafeArea.centred(safe.size.y, SafeArea.PAGE_HEIGHT, 12 if now_compact else 16)
	SafeArea.pad(_margin, rect, safe, side, tall, side, tall)
	_title.add_theme_font_size_override("font_size", 40 if now_compact else 50)
	if now_compact != compact or body.get_child_count() == 0:
		compact = now_compact
		Kit.clear(body)
		_build()

func close() -> void:
	if not _alive: return
	_alive = false
	closed.emit()
	queue_free()

func alive() -> bool:
	return _alive and is_inside_tree()

func go_back() -> void:
	if Kit.showing(_modal): _modal.go_back()
	else: close()

## Opens a question card over this page (presentation/in_game_modal.gd).
func ask(node_name: String, title: String, line: String, confirm_text: String, confirm: Callable, cancel_text: String) -> void:
	if Kit.showing(_modal) or not _alive: return
	_modal = preload("res://presentation/in_game_modal.gd").open(root, node_name, title)
	_modal.label(line)
	var send: Button = _modal.add_actions(confirm_text, func() -> void:
		_modal.close(false)
		confirm.call(), cancel_text)
	send.grab_focus()
