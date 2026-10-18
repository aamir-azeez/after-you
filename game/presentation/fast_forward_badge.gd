extends PanelContainer
## The fast-forward mark over the world while a wait goes by faster: Skip to
## end (tapped, or Always skip waits) or a held Fast-forward. It fades in as
## that starts and out as the friend arrives, breathes gently unless Reduce
## motion is on, and never takes a touch. Built once by ChapterControls; each
## change of state starts its tweens, and nothing runs per frame otherwise.
const Actions = preload("res://presentation/action_buttons.gd")
const ControlTheme = preload("res://presentation/control_theme.gd")
const SIZE := 72.0
const ICON := 36.0
const FADE_IN := 0.18
const FADE_OUT := 0.3
## One breath (out and back) and how far it swells.
const PULSE := 1.2
const PULSE_SCALE := 1.08

var reduced_motion := false
var _active := false
var _fade: Tween
var _pulse: Tween

func _init() -> void:
	name = "FastForwarding"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	visible = false
	modulate.a = 0.0
	custom_minimum_size = Vector2(SIZE, SIZE)
	pivot_offset = Vector2(SIZE, SIZE) * 0.5
	var style := StyleBoxFlat.new()
	style.bg_color = Color(ControlTheme.CHOICE_PANEL, 0.86)
	style.border_color = ControlTheme.CHOICE_BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(int(SIZE * 0.5))
	add_theme_stylebox_override("panel", style)
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.texture = Actions.ICONS.fast_forward
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(ICON, ICON)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.modulate = ControlTheme.CREAM
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(icon)

## True from the start of a faster wait until the friend arrives.
func active() -> bool:
	return _active

## Cheap to call every tick: only a change of state starts a tween.
func set_active(on: bool) -> void:
	if on == _active: return
	_active = on
	if _fade != null: _fade.kill()
	if _pulse != null: _pulse.kill()
	_pulse = null
	scale = Vector2.ONE
	if not is_inside_tree():
		visible = on
		modulate.a = 1.0 if on else 0.0
		return
	_fade = create_tween()
	if on:
		visible = true
		_fade.tween_property(self, "modulate:a", 1.0, maxf(0.01, FADE_IN * (1.0 - modulate.a)))
		if not reduced_motion:
			_pulse = create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			_pulse.tween_property(self, "scale", Vector2.ONE * PULSE_SCALE, PULSE * 0.5)
			_pulse.tween_property(self, "scale", Vector2.ONE, PULSE * 0.5)
	else:
		_fade.tween_property(self, "modulate:a", 0.0, maxf(0.01, FADE_OUT * modulate.a))
		_fade.tween_callback(hide)
