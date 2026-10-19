extends Control
## The Play with your friend icon (empty_state_art.gd "friends_squeeze"): two
## happy spirits cheek to cheek, and a heart. While its button is hovered by a
## mouse, held, or has keyboard focus, both squeeze their eyes shut and press
## together as the heart pops; on release they ease back. The eyes swap at once
## and the squish eases over about SQUISH_TIME; with reduced motion only the
## eyes change. Decorative: it ignores the mouse, so every tap reaches the
## button, and it draws only while its look changes, never on an idle frame.
## attach_to() follows the button from anywhere inside it (a slot in the
## redesigned pill); lead_label() also sits it just left of a button's centred
## label, as on today's Home button.

const Art = preload("res://presentation/empty_state_art.gd")
const Look = preload("res://presentation/spirit_look.gd")
const SCENE := "friends_squeeze"
## The redesigned pill's icon slot, and the size beside a 54 px button's label.
const SLOT_SIZE := Vector2(72, 58)
const LABEL_SIZE := Vector2(50, 40)
const LABEL_GAP := 8.0
## About 95% of the squish lands in this long, easing out.
const SQUISH_TIME := 0.12

## Only the eyes change, with no squish or pop.
var reduced_motion := false
## The eyes are squeezed shut (otherwise happy).
var squeezed := false
## 0 at rest to 1 pressed together.
var squish := 0.0
## Draw passes so far; tests read it to prove idle frames draw nothing.
var draw_count := 0
var _button: BaseButton
var _held := false
var _hovered := false
var _target := 0.0
var _placed_text := ""

func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	focus_mode = FOCUS_NONE
	custom_minimum_size = SLOT_SIZE
	set_process(false)

func _ready() -> void:
	# The engine turns _process on at ready; run only while easing.
	set_process(squish != _target)

## Follows `button`: hover, press and hold, and keyboard focus.
func attach_to(button: BaseButton) -> void:
	_button = button
	button.mouse_entered.connect(_on_hover.bind(true))
	button.mouse_exited.connect(_on_hover.bind(false))
	button.button_down.connect(_on_held.bind(true))
	button.button_up.connect(_on_held.bind(false))
	button.focus_entered.connect(_refresh)
	button.focus_exited.connect(_refresh)
	button.gui_input.connect(_on_button_input)
	_refresh()

## Adds the icon to `button` at LABEL_SIZE, just left of its centred label,
## and keeps it there as the button resizes or its text changes.
func lead_label(button: Button) -> void:
	custom_minimum_size = LABEL_SIZE
	size = LABEL_SIZE
	button.add_child(self)
	attach_to(button)
	button.resized.connect(_place_by_label)
	button.draw.connect(_follow_label)
	_place_by_label()

func _on_hover(on: bool) -> void:
	_hovered = on
	_refresh()

func _on_held(on: bool) -> void:
	_held = on
	_refresh()

func _on_button_input(event: InputEvent) -> void:
	# A finger leaves no pointer behind: once it lifts, the button is no longer
	# hovered, though the emulated mouse never left it.
	var lifted: bool = event is InputEventScreenTouch and not event.pressed
	var mouse := event as InputEventMouseButton
	if lifted or (mouse != null and not mouse.pressed and mouse.device == InputEvent.DEVICE_ID_EMULATION):
		_on_hover(false)

func _refresh() -> void:
	var want := is_instance_valid(_button) and not _button.disabled and (_held or _hovered or _button.has_focus(true))
	if want != squeezed:
		squeezed = want
		queue_redraw()
	_target = 1.0 if want and not reduced_motion else 0.0
	if reduced_motion and squish != _target:
		squish = _target
		queue_redraw()
	set_process(squish != _target)

func _process(delta: float) -> void:
	squish = lerpf(squish, _target, 1.0 - exp(-delta * 3.0 / SQUISH_TIME))
	if absf(squish - _target) < 0.01:
		squish = _target
		set_process(false)
	queue_redraw()

func _draw() -> void:
	draw_count += 1
	Art.scene(self, SCENE, Rect2(Vector2.ZERO, size), {"eyes": Look.SQUEEZE if squeezed else Look.HAPPY, "squish": squish})

func _follow_label() -> void:
	if _button is Button and (_button as Button).text != _placed_text: _place_by_label.call_deferred()

func _place_by_label() -> void:
	var button := _button as Button
	if button == null: return
	var font := button.get_theme_font("font")
	var text_width := font.get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, button.get_theme_font_size("font_size")).x
	var style := button.get_theme_stylebox("normal")
	var middle := (style.get_margin(SIDE_LEFT) + button.size.x - style.get_margin(SIDE_RIGHT)) * 0.5
	position = Vector2(maxf(4.0, middle - text_width * 0.5 - LABEL_GAP - size.x), (button.size.y - size.y) * 0.5).round()
	_placed_text = button.text
