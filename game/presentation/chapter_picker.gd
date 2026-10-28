extends ScrollContainer
## The chapter picker shared by Play Solo and Play with a friend: a scrolling grid
## of picture cards, free chapters first and then the Full Journey. Each card has
## a picture, its title, a completion tick and one square button. The screen that
## owns the picker decides what the button does through `chosen`.
const PlaySquare = preload("res://presentation/play_square.gd")
const Thumbnails = preload("res://services/chapter_thumbnail_catalog.gd")
const ThumbnailShelf = preload("res://presentation/chapter_thumbnail_shelf.gd")
const SessionRelease = preload("res://presentation/kit/session_release.gd")
const Registry = preload("res://services/chapter_registry.gd")
const CREAM := Color("eceddb")
const MINT := Color("a6d9c4")
const MUTED := Color("9dbeb4")
const GOLD := Color("f1c48a")
const SCROLLBAR_GAP := 12
const GRABBER := {"grabber": Color("466e63"), "grabber_highlight": Color("55806f"), "grabber_pressed": Color("6a9586")}
## Locked Full Journey art is mostly grey and dimmed toward the navy card, so it
## never reads brighter than owned art.
const LOCKED_PICTURE_TINT := Color(0.50,0.56,0.58)
const LOCKED_PICTURE_SATURATION := 0.3
const CARD_WIDTH := 460.0
const CHECK_ICON = preload("res://assets/ui/check.svg")
const CHOOSER_ICON = preload("res://assets/ui/social/chevron-right.svg")
const HardMode = preload("res://services/hard_mode.gd")
const HardModeView = preload("res://presentation/hard_mode_view.gd")

## A card's square button was pressed. `key` is the entry's key.
signal chosen(key: String)
## Android Back or ui_cancel while `back_enabled` and the picker is shown.
signal back_requested

## Completion mark each card shows: "solo" or "friend" (ChapterCompletion keys).
var variant := "solo"
## Read after each card's name: " · Solo" for play, " · Host a room" for hosting.
var action_name := "Solo"
## The square shows a chevron instead of the play triangle when it chooses a chapter.
var action_chevron := false
## Play Solo leaves Back to its page; a picker opened over another screen closes on it.
var back_enabled := false
## The hard mark each card shows after its tick: HardMode.SOLO or TOGETHER,
## or "" for none; hard_states is HardMode.states() (services/hard_mode.gd).
var hard_mode := ""
var hard_states: Dictionary = {}
var heading_font: Font
## Width the grid may use. A two-column grid widens the scroll's own minimum, so
## the owning screen measures from something that does not grow with it.
var available_width: Callable
var grid: GridContainer
var _signature := 0
var _buttons: Array[Button] = []

static var _surfaces: Dictionary = {}
static var _thumb_masks: Dictionary = {}
static var _locked_material: ShaderMaterial

func _init() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# Cards follow keyboard focus below. Pointer focus must not jump the list
	# when a drag starts on a part-visible card.
	follow_focus = false
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	# The scroll bar uses the cards' own border colour.
	var bar := get_v_scroll_bar()
	for state: String in GRABBER:
		var grabber := bar.get_theme_stylebox(state).duplicate() as StyleBox
		if grabber is StyleBoxFlat: (grabber as StyleBoxFlat).bg_color = GRABBER[state]
		bar.add_theme_stylebox_override(state,grabber)
	# A right gutter keeps the cards clear of the scroll bar.
	var gutter := MarginContainer.new()
	gutter.name = "JourneyGutter"
	gutter.mouse_filter = Control.MOUSE_FILTER_PASS
	gutter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gutter.add_theme_constant_override("margin_right",SCROLLBAR_GAP)
	add_child(gutter)
	grid = GridContainer.new()
	grid.name = "JourneyChapters"
	grid.mouse_filter = Control.MOUSE_FILTER_PASS
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation",16)
	grid.add_theme_constant_override("v_separation",14)
	gutter.add_child(grid)
	resized.connect(_fit)
	grid.minimum_size_changed.connect(func(): _fit.call_deferred())

## Picture size for a screen this wide: roomy on a landscape phone, smaller below 900.
static func picture_for(width: float) -> Vector2:
	return Vector2(192,108) if width >= 900.0 else Vector2(144,81)

## A card entry for a registry chapter. Screens set "locked", "tag", "note" and so on after.
static func entry(key: String) -> Dictionary:
	var item := Registry.descriptor(key)
	return {"key": key, "title": str(item.get("title",key)), "premium": bool(item.get("premium",false)),
		"level_key": str(item.get("level_id",key.get_slice("@",0))), "mark": key, "stage_count": int(item.get("stage_count",1))}

## Builds one card per entry. Nothing is rebuilt when the entries, picture size,
## mark and action are unchanged since the last call.
func set_entries(entries: Array[Dictionary], picture: Vector2) -> void:
	var signature := hash([entries,picture,variant,action_name,action_chevron,hard_mode,hard_states])
	if signature == _signature and grid.get_child_count() > 0: return
	_signature = signature
	for card: Node in grid.get_children():
		grid.remove_child(card)
		card.queue_free()
	_buttons.clear()
	for item: Dictionary in shown_order(entries): grid.add_child(_card(item,picture))
	_fit()

## The entries in the order their cards show (Registry.picker_rank): free
## chapters lead; every Full Journey chapter follows. Within each, chapters that
## lead the pickers come first, then the rest, each in the order given.
static func shown_order(entries: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for rank: int in 4:
		for item: Dictionary in entries:
			if Registry.picker_rank(str(item.get("key","")),bool(item.get("premium",false))) == rank: result.append(item)
	return result

## Completion ticks and the done tint from ChapterCompletion.chapters(); cards are
## restyled only when their state changes, since Play Solo refreshes on a timer.
func refresh_marks(marks: Dictionary) -> void:
	for open: Button in _buttons:
		if not is_instance_valid(open): continue
		var complete: bool = marks.get(open.get_meta("completion_chapter"),{}).get(open.get_meta("completion_variant"),false)
		open.set_meta("chapter_complete",complete)
		open.completed = complete
		var card := open.get_meta("card") as PanelContainer
		var tick := card.find_child("ChapterDone",true,false) as Control
		if tick != null: tick.visible = complete
		if not card.has_meta("surface_complete") or bool(card.get_meta("surface_complete")) != complete:
			card.set_meta("surface_complete",complete)
			card.add_theme_stylebox_override("panel",surface(complete,bool(card.get_meta("full_journey_locked",false))))

## Hard marks from HardMode.states(), restyled in place.
func refresh_hard(states: Dictionary) -> void:
	hard_states = states.duplicate(true)
	if hard_mode.is_empty(): return
	for card: Node in grid.get_children():
		var state: Variant = states.get(str(card.get_meta("chapter_key","")))
		var mark := card.find_child("HardMarkSolo" if hard_mode == HardMode.SOLO else "HardMarkTogether",true,false)
		if mark != null and state is Dictionary: mark.set_look(str(state.get(hard_mode, HardMode.LOCKED)))

## The card for `key`, if shown.
func card_for(key: String) -> PanelContainer:
	for card: Node in grid.get_children():
		if str(card.get_meta("chapter_key","")) == key: return card as PanelContainer
	return null

## Scrolls `key`'s card into view and gives its button focus, so the current
## choice is where the list opens and a keyboard can accept it straight away.
func reveal(key: String) -> void:
	var card := card_for(key)
	if card == null: return
	await get_tree().process_frame
	if not is_instance_valid(card) or not is_visible_in_tree(): return
	ensure_control_visible(card)
	(card.find_child("ChapterOpen",true,false) as Control).grab_focus()

## Card fill: clearly darker while a Full Journey chapter is locked, a brighter
## green-teal with a solid mint edge once completed, otherwise the plain card colour.
static func surface(complete: bool, locked: bool) -> StyleBoxFlat:
	var id := int(complete)*2+int(locked)
	if not _surfaces.has(id):
		var style := StyleBoxFlat.new()
		style.bg_color = Color("112d2b") if locked else Color("2a5c51") if complete else Color("1b443e")
		style.set_corner_radius_all(18)
		style.border_color = MINT if complete else Color.TRANSPARENT
		style.set_border_width_all(2 if complete else 0)
		for edge: String in ["left","top","right","bottom"]: style.set("content_margin_"+edge,0)
		_surfaces[id] = style
	return _surfaces[id]

static func locked_picture_material() -> ShaderMaterial:
	if _locked_material == null:
		var shader := Shader.new()
		shader.code = "shader_type canvas_item;\nuniform float saturation = 0.3;\nvoid fragment() {\n\tfloat grey = dot(COLOR.rgb, vec3(0.299, 0.587, 0.114));\n\tCOLOR.rgb = mix(vec3(grey), COLOR.rgb, saturation);\n}\n"
		_locked_material = ShaderMaterial.new()
		_locked_material.shader = shader
		_locked_material.set_shader_parameter("saturation",LOCKED_PICTURE_SATURATION)
		# The shader is a GPU resource: let it go before the renderer stops.
		SessionRelease.on_exit(Callable(load("res://presentation/chapter_picker.gd"), "release_cached"))
	return _locked_material

## Lets go of the kept locked picture look (SessionRelease calls this at shutdown).
static func release_cached() -> void:
	_locked_material = null

## A steady framed chapter picture that keeps a full 16:9/2:1 cover crop instead
## of a thin sliver. The art runs edge to edge and the frame's rounded corners
## clip it. The picture is loaded here, from the thumbnail catalog.
static func thumbnail(key: String, min_size: Vector2, radius: int) -> Control:
	var frame := picture_frame(min_size, radius)
	(frame.get_child(0) as TextureRect).texture = Thumbnails.texture(key)
	return frame

## The frame with its picture still empty: its own dark fill shows until the
## picture is set, at the same size, so setting it later moves nothing. Its
## picture is its only child. Square frames (radius 0) skip the rounded clip.
static func picture_frame(min_size: Vector2, radius: int) -> PanelContainer:
	var frame := PanelContainer.new()
	frame.custom_minimum_size = min_size
	frame.clip_contents = true
	if radius > 0: frame.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	if min_size.x > 0: frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not _thumb_masks.has(radius):
		var mask := StyleBoxFlat.new()
		mask.bg_color = Color("0d2a27")
		mask.set_corner_radius_all(radius)
		for edge: String in ["left","top","right","bottom"]: mask.set("content_margin_"+edge,0)
		_thumb_masks[radius] = mask
	frame.add_theme_stylebox_override("panel",_thumb_masks[radius])
	var picture := TextureRect.new()
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(picture)
	return frame

## The button that opens a picker from another screen: the current chapter's
## title with a chevron, in the outlined secondary look of the old dropdown.
static func chooser(title: String) -> Button:
	var button := Button.new()
	button.name = "ChapterChoice"
	button.text = title
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.icon = CHOOSER_ICON
	button.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	button.custom_minimum_size.y = 50
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.mouse_filter = Control.MOUSE_FILTER_PASS
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.focus_mode = Control.FOCUS_ALL
	for state: String in ["normal","hover","pressed","hover_pressed","disabled"]:
		var fill := Color("203f39") if state == "disabled" else Color("254b45") if state == "normal" else Color("315e53")
		var style := StyleBoxFlat.new()
		style.bg_color = fill
		style.set_corner_radius_all(14)
		style.set_border_width_all(1)
		style.border_color = Color("54766a")
		style.content_margin_left = 18
		style.content_margin_right = 16
		style.content_margin_top = 10
		style.content_margin_bottom = 10
		button.add_theme_stylebox_override(state,style)
		button.add_theme_color_override("font_color" if state == "normal" else "font_"+state+"_color",Color("9aaaa3") if state == "disabled" else CREAM)
	for color_name: String in ["icon_normal_color","icon_hover_color","icon_pressed_color","icon_hover_pressed_color","icon_focus_color"]:
		button.add_theme_color_override(color_name,CREAM)
	button.add_theme_color_override("font_focus_color",CREAM)
	var ring := StyleBoxFlat.new()
	ring.bg_color = Color.TRANSPARENT
	ring.set_corner_radius_all(14)
	ring.set_border_width_all(1)
	ring.border_color = MINT
	button.add_theme_stylebox_override("focus",ring)
	button.add_theme_constant_override("icon_max_width",20)
	return button

func _card(item: Dictionary, picture: Vector2) -> PanelContainer:
	var key := str(item.get("key",""))
	var premium := bool(item.get("premium",false))
	var locked := bool(item.get("locked",false))
	var level_key := str(item.get("level_key",key.get_slice("@",0)))
	var title_text := str(item.get("title",key))
	var card := PanelContainer.new()
	card.name = ("PaidLevel_" if premium else "FreeChapter_") + level_key.replace("-","_")
	if premium: card.set_meta("paid_level_key",level_key)
	card.set_meta("chapter_key",key)
	# A plain panel: a press here only reaches the list, so it can start a scroll.
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Wide enough that small screens keep one roomy column.
	card.custom_minimum_size.x = CARD_WIDTH
	# Locked Full Journey chapters are shaded; owned ones lose it when the picker redraws.
	card.set_meta("full_journey_locked",locked)
	card.add_theme_stylebox_override("panel",surface(false,locked))
	var content := MarginContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left","top","right","bottom"]: content.add_theme_constant_override("margin_"+side,12)
	card.add_child(content)
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation",16)
	content.add_child(line)
	# The picture comes from the shelf Main keeps: at once when it holds it,
	# else loaded off the main thread and filled in (chapter_thumbnail_shelf.gd).
	var frame := picture_frame(picture,12)
	frame.get_child(0).name = "LevelPicture"
	ThumbnailShelf.fill(frame.get_child(0) as TextureRect,Thumbnails.path(key))
	if locked:
		var art := frame.get_child(0) as CanvasItem
		art.self_modulate = LOCKED_PICTURE_TINT
		art.material = locked_picture_material()
	line.add_child(frame)
	var details := VBoxContainer.new()
	details.name = "LevelDetails"
	details.mouse_filter = Control.MOUSE_FILTER_IGNORE
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	details.add_theme_constant_override("separation",2)
	line.add_child(details)
	# Placed by hand rather than in a container so the title wraps instead of
	# widening the card, and the tick can follow the title text directly.
	var heading := Control.new()
	heading.name = "LevelHeading"
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	details.add_child(heading)
	var title := _text(title_text,26,CREAM)
	if heading_font != null: title.add_theme_font_override("font",heading_font)
	title.name = "LevelTitle"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.add_child(title)
	# Shown once the chapter is completed in this picker's mode; see refresh_marks.
	var tick := TextureRect.new()
	tick.name = "ChapterDone"
	tick.texture = CHECK_ICON
	tick.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tick.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tick.custom_minimum_size = Vector2(24,24)
	tick.self_modulate = MINT
	tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tick.visible = false
	heading.add_child(tick)
	# The chapter's hard mark, once open or done, follows the tick (or takes
	# its place while there is none).
	var hard_mark: Control = null
	if not hard_mode.is_empty() and hard_states.get(key) is Dictionary and str(hard_states[key].get(hard_mode, HardMode.LOCKED)) != HardMode.LOCKED:
		hard_mark = HardModeView.mark(hard_mode, str(hard_states[key].get(hard_mode, HardMode.LOCKED)), 24.0)
		heading.add_child(hard_mark)
	var reserve := 34.0 + (32.0 if hard_mark != null else 0.0)
	# Room for the tick is always kept, so a title never reflows when it appears.
	# A title too long for one line wraps and the tick ends its first line.
	var place := func():
		if not is_instance_valid(title): return
		var text := title.get_theme_font("font").get_string_size(title.text,HORIZONTAL_ALIGNMENT_LEFT,-1,title.get_theme_font_size("font_size")).x
		var width := minf(ceilf(text)+2.0,maxf(1.0,heading.size.x-reserve))
		title.position = Vector2.ZERO
		title.size = Vector2(width,0)
		title.size = Vector2(width,title.get_combined_minimum_size().y)
		var first_line := title.size.y/maxf(1.0,float(title.get_line_count()))
		tick.position = Vector2(width+10.0,(first_line-24.0)*0.5)
		tick.size = Vector2(24,24)
		if is_instance_valid(hard_mark):
			hard_mark.position = Vector2(width+(42.0 if tick.visible else 10.0),(first_line-24.0)*0.5)
			hard_mark.size = Vector2(24,24)
		heading.custom_minimum_size.y = title.size.y
	heading.resized.connect(place)
	title.minimum_size_changed.connect(func(): place.call_deferred())
	if hard_mark != null: tick.visibility_changed.connect(func(): place.call_deferred())
	# Locked Full Journey chapters keep their gold marker; owned ones go quiet.
	# A screen may name why a chapter is locked in "note", in place of the marker.
	var note := str(item.get("note",""))
	var access := _text((note if not note.is_empty() else "Full Journey" if premium else "Free to play")+str(item.get("tag","")),18,GOLD if locked else MUTED)
	access.name = "ChapterAccess"
	if not note.is_empty() or not str(item.get("tag","")).is_empty(): access.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	access.set_meta("full_journey_locked",locked)
	details.add_child(access)
	# The only tap and focus target. Locked chapters use the same control; the
	# owning screen keeps its own access and purchase gates behind `chosen`.
	var open := PlaySquare.new(64.0 if picture.x >= 192.0 else 56.0)
	open.name = "ChapterOpen"
	open.locked = locked
	open.chevron = action_chevron
	open.accessibility_name = title_text+(" · "+(note if not note.is_empty() else "Full Journey") if locked else " · "+action_name)
	open.pressed.connect(func(): chosen.emit(key))
	open.set_meta("completion_chapter",str(item.get("mark",key)))
	open.set_meta("completion_variant",variant)
	open.set_meta("card",card)
	# Keyboard focus brings the whole card, not only its button, into view.
	var follow := func():
		if is_instance_valid(open) and open.has_focus(true): ensure_control_visible(card)
	open.focus_entered.connect(follow,CONNECT_DEFERRED)
	line.add_child(open)
	_buttons.append(open)
	return card

func _text(value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

## Re-measures columns and row heights, e.g. when the owning screen resizes.
func refit() -> void:
	_fit()

func _fit() -> void:
	if not is_instance_valid(grid) or not is_inside_tree(): return
	# Two columns whenever both fit beside the scroll bar; one on narrow screens.
	var widest := 0.0
	for card: Control in grid.get_children(): widest = maxf(widest,card.get_combined_minimum_size().x)
	var width: float = available_width.call() if available_width.is_valid() else size.x
	var columns := 2 if width-16.0-SCROLLBAR_GAP >= widest*2.0+16.0 else 1
	if grid.columns != columns: grid.columns = columns
	_fit_rows()

func _fit_rows() -> void:
	# When the grid scrolls, keep a quarter to three quarters of the next row in
	# view as a cue. Rows only grow, and only as far as that takes.
	if grid.get_child_count() == 0 or size.y <= 0.0: return
	var natural := 0.0
	for card: Control in grid.get_children(): natural = maxf(natural,card.get_minimum_size().y)
	var gap := float(grid.get_theme_constant("v_separation"))
	var rows := ceili(float(grid.get_child_count())/float(grid.columns))
	var shown := size.y/(natural+gap)
	var target := shown
	if rows > shown:
		var whole := floorf(shown)
		if shown-whole > 0.75: target = whole+0.75
		elif shown-whole < 0.25 and whole >= 2.0: target = whole-0.25
	var height := floorf(size.y/target-gap) if target < shown else 0.0
	for card: Control in grid.get_children():
		if card.custom_minimum_size.y != height: card.custom_minimum_size.y = height

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and back_enabled and is_visible_in_tree():
		# Deferred: the owner may rebuild the screen, which the tree refuses
		# while it is still delivering this notification.
		back_requested.emit.call_deferred()

func _input(event: InputEvent) -> void:
	# Taken before main's Escape handling, which would otherwise go Home.
	if back_enabled and is_visible_in_tree() and event.is_action_pressed("ui_cancel"):
		# Handled first: the owner may free this picker while handling the signal.
		get_viewport().set_input_as_handled()
		back_requested.emit()
