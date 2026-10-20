extends CanvasLayer
## A small menu for one room card, opened from its "..." button. It sits on its
## own canvas layer just above the hub, directly under the button with its right
## edge on the button's right edge and a small pointer up to the button. It
## looks like the chapter choice list (control_theme.gd ChoiceList): dark panel,
## light-green outline, rounded rows lit on focus. The rest of the screen dims;
## a tap outside, Escape or the hub's Back (go_back) closes it. Rows take focus
## only when the menu was opened from the keyboard or keys are used after a tap.
##
## Rows are {id, title, detail, icon, tone}; tone "danger" draws the row in
## soft pink, "muted" in the quiet grey of a row that only informs. Picking a row closes the menu, then emits chosen(id).
const ThemeRules = preload("res://presentation/control_theme.gd")
const CREAM := Color("eceddb")
const MUTED := Color("afc6be")
const DANGER_TEXT := Color("f2b8ae")
const WIDTH := 420.0
const POINTER := 9.0
const EDGE := 12.0

signal chosen(id: String)
signal closed

var anchor: Control
var shade: ColorRect
var panel: PanelContainer
var pointer: Polygon2D
var rows: Array[Button] = []
var keyboard := false
var _closed := false
## True when there was no room below the button and the menu opened above it.
var above := false

static func open(source: Control, entries: Array[Dictionary], use_keyboard: bool = false) -> CanvasLayer:
	if not is_instance_valid(source) or not source.is_inside_tree() or entries.is_empty(): return null
	var menu: CanvasLayer = load("res://presentation/room_card_menu.gd").new()
	menu.name = "RoomCardMenu"
	menu.anchor = source
	menu.keyboard = use_keyboard
	var host := source.get_canvas_layer_node()
	menu.layer = (host.layer if host != null else 0) + 1
	source.add_child(menu,false,Node.INTERNAL_MODE_BACK)
	menu._build(entries,source.get_theme_font("font"))
	return menu

func _build(entries: Array[Dictionary], font: Font) -> void:
	shade = ColorRect.new()
	shade.name = "RoomMenuShade"
	shade.color = Color(0.02,0.08,0.08,0.32)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	shade.theme = _theme(font)
	shade.gui_input.connect(_on_shade_input)
	add_child(shade)
	panel = PanelContainer.new()
	panel.name = "RoomMenuPanel"
	panel.add_theme_stylebox_override("panel",ThemeRules.padded(ThemeRules.rounded(ThemeRules.CHOICE_PANEL,14,ThemeRules.CHOICE_BORDER),8,8))
	shade.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",4)
	panel.add_child(column)
	for entry: Dictionary in entries:
		var row := _row(entry)
		column.add_child(row)
		rows.append(row)
	pointer = Polygon2D.new()
	pointer.name = "RoomMenuPointer"
	pointer.color = ThemeRules.CHOICE_BORDER
	shade.add_child(pointer)
	_wrap_focus()
	place()
	get_viewport().size_changed.connect(place)
	anchor.visibility_changed.connect(_on_anchor_visibility)
	anchor.tree_exiting.connect(close.bind(false))
	if keyboard: engage_keyboard()

func _row(entry: Dictionary) -> Button:
	var row := Button.new()
	row.name = "RoomMenu_" + str(entry.get("id",""))
	row.set_meta("menu_id",str(entry.get("id","")))
	row.focus_mode = Control.FOCUS_NONE
	row.accessibility_name = str(entry.get("title",""))
	row.accessibility_description = str(entry.get("detail",""))
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	var tint: Color = DANGER_TEXT if entry.get("tone") == "danger" else MUTED if entry.get("tone") == "muted" else CREAM
	var box := HBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation",14)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 14
	box.offset_right = -14
	row.add_child(box)
	var icon := TextureRect.new()
	icon.name = "RowIcon"
	icon.texture = entry.get("icon")
	icon.custom_minimum_size = Vector2(24,24)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.modulate = tint
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(icon)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	words.add_theme_constant_override("separation",0)
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(words)
	var title := Label.new()
	title.name = "RowTitle"
	title.text = str(entry.get("title",""))
	title.add_theme_color_override("font_color",tint)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.add_child(title)
	var detail := Label.new()
	detail.name = "RowDetail"
	detail.text = str(entry.get("detail",""))
	detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	detail.add_theme_font_size_override("font_size",16)
	detail.add_theme_color_override("font_color",MUTED)
	detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail.visible = not detail.text.is_empty()
	words.add_child(detail)
	row.pressed.connect(pick.bind(str(entry.get("id",""))))
	return row

## Places the panel under the anchor, right edges aligned, inside the window.
func place() -> void:
	if _closed or not is_instance_valid(anchor) or not anchor.is_inside_tree(): return
	var view := anchor.get_viewport().get_visible_rect()
	var transform := anchor.get_global_transform_with_canvas()
	var rect := Rect2(transform.origin,anchor.size * transform.get_scale())
	var width := minf(WIDTH,view.size.x - 2.0 * EDGE)
	panel.size = Vector2(width,0)
	for row: Button in rows:
		var box := row.get_child(0) as Control
		row.custom_minimum_size = Vector2(0,maxf(60.0,box.get_combined_minimum_size().y + 16.0))
	panel.reset_size()
	panel.size.x = width
	var height := panel.get_combined_minimum_size().y
	var x := clampf(rect.end.x - width,view.position.x + EDGE,view.end.x - EDGE - width)
	var room_below := view.end.y - EDGE - rect.end.y - POINTER
	var room_above := rect.position.y - POINTER - view.position.y - EDGE
	# Under the button whenever it fits; above only when that fits and below
	# does not; on a window too short for either, the roomier side, kept inside.
	above = room_below < height and (room_above >= height or room_above > room_below)
	var y := rect.position.y - POINTER - height if above else rect.end.y + POINTER
	y = clampf(y,view.position.y + EDGE,maxf(view.position.y + EDGE,view.end.y - EDGE - height))
	panel.position = Vector2(x,y)
	panel.size = Vector2(width,height)
	# The pointer sits under the button's centre, inside the panel's rounded corner.
	var tip_x := clampf(rect.get_center().x,x + 22.0,x + width - 22.0)
	if above: pointer.polygon = PackedVector2Array([Vector2(tip_x - POINTER,y + height),Vector2(tip_x + POINTER,y + height),Vector2(tip_x,y + height + POINTER)])
	else: pointer.polygon = PackedVector2Array([Vector2(tip_x - POINTER,y),Vector2(tip_x + POINTER,y),Vector2(tip_x,y - POINTER)])

## The panel's rectangle on screen, for tests and captures.
func panel_rect() -> Rect2:
	return Rect2(panel.position,panel.size)

func pick(id: String) -> void:
	if _closed: return
	close(false)
	chosen.emit(id)

func close(restore_focus: bool = true) -> void:
	if _closed: return
	_closed = true
	if restore_focus and is_instance_valid(anchor) and anchor.is_inside_tree() and anchor.is_visible_in_tree(): anchor.grab_focus()
	# Freed at the end of the frame, so the press that closed it lands here
	# and never on whatever lies beneath.
	queue_free()
	closed.emit()

func is_closed() -> bool:
	return _closed

func engage_keyboard() -> void:
	keyboard = true
	for row: Button in rows: row.focus_mode = Control.FOCUS_ALL
	if not rows.is_empty(): rows[0].grab_focus()

func _wrap_focus() -> void:
	for index: int in range(rows.size()):
		var row := rows[index]
		var up := row.get_path_to(rows[(index - 1 + rows.size()) % rows.size()])
		var down := row.get_path_to(rows[(index + 1) % rows.size()])
		row.focus_neighbor_top = up
		row.focus_previous = up
		row.focus_neighbor_bottom = down
		row.focus_next = down
		row.focus_neighbor_left = NodePath(".")
		row.focus_neighbor_right = NodePath(".")

func _input(event: InputEvent) -> void:
	if _closed: return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
	elif not keyboard:
		for action: String in ["ui_up","ui_down","ui_focus_next","ui_focus_prev"]:
			if event.is_action_pressed(action):
				get_viewport().set_input_as_handled()
				engage_keyboard()
				return

func _on_shade_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.pressed:
		shade.accept_event()
		close(keyboard)

func _on_anchor_visibility() -> void:
	if not is_instance_valid(anchor) or not anchor.is_visible_in_tree(): close(false)

func _theme(font: Font) -> Theme:
	var look := Theme.new()
	look.default_font = font
	look.default_font_size = 20
	var plain := StyleBoxEmpty.new()
	var lit := ThemeRules.rounded(ThemeRules.CHOICE_HIGHLIGHT,10)
	for state: String in ["normal","disabled"]: look.set_stylebox(state,"Button",plain)
	for state: String in ["hover","pressed","hover_pressed","focus"]: look.set_stylebox(state,"Button",lit)
	look.set_color("font_color","Label",CREAM)
	return look
