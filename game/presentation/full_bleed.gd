extends Node
## Internal child of a backdrop Control (see SafeArea.bleed). Keeps the backdrop
## covering the whole visible viewport, whatever inset or offset its ancestors
## have: it refits when any Control ancestor's rect or the viewport size changes,
## never per frame.
const NAME := "FullBleed"

var _watched: Array[Dictionary] = []

func _enter_tree() -> void:
	var target := get_parent() as Control
	if target == null: return
	target.set_anchors_preset(Control.PRESET_FULL_RECT)
	var node := target.get_parent()
	while node is Control:
		_watch(node, &"item_rect_changed")
		node = node.get_parent()
	_watch(get_viewport(), &"size_changed")
	fit()

func _exit_tree() -> void:
	for entry: Dictionary in _watched:
		var source: Object = entry.source
		if is_instance_valid(source) and source.is_connected(entry.signal, fit): source.disconnect(entry.signal, fit)
	_watched.clear()

func _watch(source: Object, signal_name: StringName) -> void:
	if source.is_connected(signal_name, fit): return
	source.connect(signal_name, fit)
	_watched.append({"source": source, "signal": signal_name})

## Offsets that put the backdrop exactly on the visible viewport, through its
## parent's global transform (so a scaled or shifted parent is handled too).
func fit() -> void:
	var target := get_parent() as Control
	if target == null or not target.is_inside_tree(): return
	var host := target.get_parent() as Control
	var edges := Vector4.ZERO
	if host != null:
		var local := host.get_global_transform().affine_inverse() * target.get_viewport().get_visible_rect()
		edges = Vector4(local.position.x, local.position.y, local.end.x - host.size.x, local.end.y - host.size.y)
	if not edges.is_equal_approx(Vector4(target.offset_left, target.offset_top, target.offset_right, target.offset_bottom)):
		target.offset_left = edges.x
		target.offset_top = edges.y
		target.offset_right = edges.z
		target.offset_bottom = edges.w
