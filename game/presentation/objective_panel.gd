extends PanelContainer
## Read-only progress display shared by chapter and earlier-island HUDs.
const ControlTheme = preload("res://presentation/control_theme.gd")

var label: Label
var value_label: Label
var detail_label: Label
var bar: ProgressBar

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size.x = 224
	var style := ControlTheme.rounded(Color("193f3aed"), 12)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	add_theme_stylebox_override("panel", style)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 5)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stack)
	label = _label(18)
	value_label = _label(26)
	detail_label = _label(16)
	detail_label.add_theme_color_override("font_color", Color("afc7bd"))
	bar = ProgressBar.new()
	bar.custom_minimum_size.y = 6
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("background", ControlTheme.rounded(Color("35584f"), 3))
	bar.add_theme_stylebox_override("fill", ControlTheme.rounded(Color("f1c48a"), 3))
	for child: Control in [label, value_label, bar, detail_label]:
		stack.add_child(child)
	minimum_size_changed.connect(_fit_height.call_deferred)
	visible = false

func _label(font_size: int) -> Label:
	var result := Label.new()
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", Color("eceddb"))
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result

func show_objective(data: Dictionary, fallback: String = "") -> void:
	label.text = str(data.get("label", fallback))
	detail_label.text = str(data.get("detail", ""))
	detail_label.visible = not detail_label.text.is_empty()
	var current := float(data.get("current", 0.0))
	var required := float(data.get("required", 0.0))
	var measured := data.has("current") and data.has("required") and is_finite(current) and is_finite(required) and required > 0.0
	value_label.visible = measured
	bar.visible = measured
	if measured:
		current = maxf(current, 0.0)
		value_label.text = "%.1f / %.1f s" % [current, required] if data.get("unit", "") == "seconds" else "%d / %d" % [int(current), int(required)]
		bar.max_value = required
		bar.value = clampf(current, 0.0, required)
	else:
		value_label.text = ""
	visible = not label.text.is_empty() or measured or detail_label.visible
	_fit_height.call_deferred()

func _fit_height() -> void:
	# Wrapped labels first measure at their old width, then report their real
	# minimum after the container lays them out. Follow that second measurement
	# as well: an early size.y=0 alone retains the temporary one-word-wide height.
	if is_inside_tree(): size.y = get_combined_minimum_size().y

static func legacy_progress(state: Dictionary, tick_rate: float) -> Dictionary:
	var required := int(state.get("bridge_charge_required", 0))
	if required <= 1 or tick_rate <= 0.0:
		return {}
	return {"label": "Bridge charge", "current": float(state.get("bridge_charge", 0)) / tick_rate,
		"required": float(required) / tick_rate, "unit": "seconds"}
