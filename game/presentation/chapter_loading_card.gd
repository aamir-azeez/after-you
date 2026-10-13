extends CanvasLayer
## The small "Opening your chapter" card every chapter opens behind.
## A chapter screen builds its world and sets up its turn in one frame, so the
## card is drawn first (two frames) and stays on top, above the scene change,
## until the chapter has drawn its own first frame. Every open is timed; the
## card shows only when this chapter took 300 ms or more to open last time on
## this device, or has not been timed here yet.
const ReplayLoadingBar = preload("res://presentation/replay_loading_bar.gd")
const TITLE := "Opening your chapter"
const SHOW_AFTER_USEC := 300000
const COSTS_PATH := "user://chapter-open-times.json"
const MAX_COSTS_BYTES := 16384
const MAX_COSTS := 64
const LAYER := 90
## Frames a scene change may take before the card gives up waiting for it.
const MAX_WAIT_FRAMES := 600
const CREAM := Color("eceddb")

static var costs_path := COSTS_PATH
static var _costs: Dictionary = {}
static var _costs_from := ""

var key := ""
var shown := false
var _started := 0
var _closed := false


## Whether an open of key is expected to take long enough to show the card.
static func expected_slow(open_key: String) -> bool:
	var cost := last_cost_usec(open_key)
	return cost < 0 or cost >= SHOW_AFTER_USEC

## The last measured open of key on this device, or -1.
static func last_cost_usec(open_key: String) -> int:
	_load_costs()
	return int(_costs.get(open_key, -1))


## Adds the card for an open of open_key under the tree's root, which outlives
## the scene change. Hidden when the open is expected to be quick.
func start(tree: SceneTree, open_key: String, reduced_motion: bool = false) -> void:
	key = open_key
	name = "ChapterLoadingCard"
	layer = LAYER
	shown = expected_slow(key)
	visible = shown
	if shown: _build(reduced_motion)
	tree.root.add_child(self)
	_started = Time.get_ticks_usec()

## Returns once the card is on screen: two frames when it shows, none when
## it does not. Timing starts after it, with the work.
func drawn() -> void:
	if shown and is_inside_tree():
		await get_tree().process_frame
		await get_tree().process_frame
	_started = Time.get_ticks_usec()

## Call right after a successful change_scene_to_file: times the open and
## leaves once the new scene has drawn its first frame.
func follow_scene_change(previous: Node) -> void:
	if _closed or not is_inside_tree(): return
	var tree := get_tree()
	var previous_id := previous.get_instance_id() if is_instance_valid(previous) else 0
	var frames := 0
	while is_inside_tree() and frames < MAX_WAIT_FRAMES and (tree.current_scene == null or tree.current_scene.get_instance_id() == previous_id):
		await tree.process_frame
		frames += 1
	if not is_inside_tree(): return
	await tree.process_frame
	_finish(frames < MAX_WAIT_FRAMES)

## Runs work behind the card (after it is drawn) and leaves after the next
## frame. For a chapter that builds itself in place, outside a scene change.
func run(work: Callable) -> void:
	await drawn()
	if _closed: return
	work.call()
	if not is_inside_tree(): return
	await get_tree().process_frame
	_finish(true)

## Leaves without recording a time: the open did not happen.
func cancel() -> void:
	_closed = true
	if is_inside_tree(): get_parent().remove_child(self)
	queue_free()

func _finish(measured: bool) -> void:
	if _closed: return
	_closed = true
	if measured: _record(key, Time.get_ticks_usec() - _started)
	if is_inside_tree(): get_parent().remove_child(self)
	queue_free()


func _build(reduced_motion: bool) -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var theme := Theme.new()
	var body := FontVariation.new()
	body.base_font = preload("res://assets/fonts/nunito.ttf")
	body.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 600.0}
	theme.default_font = body
	theme.default_font_size = 20
	theme.set_color("font_color", "Label", CREAM)
	root.theme = theme
	add_child(root)
	# The same dimming as a chapter card; it also keeps taps off the screen
	# underneath while the chapter opens.
	var shade := ColorRect.new()
	shade.color = Color(0.025, 0.10, 0.10, 0.73)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.name = "OpeningCard"
	panel.custom_minimum_size.x = 380
	var style := StyleBoxFlat.new()
	style.bg_color = Color("163c36")
	style.set_corner_radius_all(16)
	style.set_border_width_all(1)
	style.border_color = Color("54766a")
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for edge: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 22)
	panel.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 6)
	margin.add_child(stack)
	var title := Label.new()
	title.text = TITLE
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var heading := FontVariation.new()
	heading.base_font = preload("res://assets/fonts/fredoka.ttf")
	heading.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 600.0}
	title.add_theme_font_override("font", heading)
	title.add_theme_font_size_override("font_size", 28)
	stack.add_child(title)
	var bar := ReplayLoadingBar.new()
	bar.name = "OpeningProgress"
	bar.reduced_motion = reduced_motion
	stack.add_child(bar)
	bar.update_progress({})


static func _load_costs() -> void:
	if _costs_from == costs_path: return
	_costs_from = costs_path
	_costs = {}
	if not FileAccess.file_exists(costs_path): return
	var file := FileAccess.open(costs_path, FileAccess.READ)
	if file == null: return
	if file.get_length() < 1 or file.get_length() > MAX_COSTS_BYTES:
		file.close()
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	# Anything unexpected is ignored; the next open writes a fresh record.
	if not parsed is Dictionary or parsed.get("schema_version") != 1 or not parsed.get("costs") is Dictionary: return
	for name: Variant in parsed.costs:
		var value: Variant = parsed.costs[name]
		if name is String and (value is int or value is float) and value >= 0 and _costs.size() < MAX_COSTS: _costs[name] = int(value)

static func _record(open_key: String, usec: int) -> void:
	if open_key.is_empty() or usec < 0: return
	_load_costs()
	_costs.erase(open_key)
	_costs[open_key] = usec
	while _costs.size() > MAX_COSTS: _costs.erase(_costs.keys()[0])
	var text := JSON.stringify({"schema_version": 1, "costs": _costs})
	var file := FileAccess.open(costs_path, FileAccess.WRITE)
	if file == null: return
	file.store_string(text)
	file.close()
