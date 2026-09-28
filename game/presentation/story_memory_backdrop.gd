extends CanvasLayer
## A disposable illustration below the dialogue card, isolated from gameplay.
const MemoryWorld = preload("res://presentation/story_memory_world.gd")
var _serial := 0
var _generation := -1
var _passage := ""
var _root: Control
var _picture: TextureRect
var _caption: Label
var _viewport: SubViewport
var _world: Node3D
var _panel_rect := Rect2()
var _safe_rect := Rect2()

func _ready() -> void:
	layer = 29
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	set_process_input(false)

func present(generation: int, passage: String, chapter: String, phase: String, title: String, panel: Rect2, safe: Rect2) -> int:
	if not is_node_ready() or generation < 0 or passage.is_empty() or passage.length() > 256 or chapter not in MemoryWorld.KEYS or phase not in ["arrival","completion"] or title.is_empty() or title.length() > 96: return -1
	_dispose()
	_serial += 1
	_generation = generation
	_passage = passage
	_root = Control.new()
	_root.name = "StoryMemoryBackdrop"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	add_child(_root)
	var background := ColorRect.new()
	background.color = Color("102d35")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(background)
	_viewport = SubViewport.new()
	_viewport.name = "MemoryIllustration"
	_viewport.own_world_3d = true
	_viewport.world_3d = World3D.new()
	_viewport.handle_input_locally = false
	_viewport.gui_disable_input = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_root.add_child(_viewport)
	_world = MemoryWorld.new()
	_world.configure(chapter,phase)
	_viewport.add_child(_world)
	_picture = TextureRect.new()
	_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_SCALE
	_picture.texture = _viewport.get_texture()
	_root.add_child(_picture)
	_caption = Label.new()
	_caption.add_theme_font_override("font",preload("res://assets/fonts/nunito.ttf"))
	_caption.text = title+" · "+phase.capitalize()
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.add_theme_color_override("font_color",Color("eceddb"))
	_caption.add_theme_font_size_override("font_size",22)
	_root.add_child(_caption)
	frame(_serial,panel,safe)
	return _serial

func matches(token: int, generation: int, passage: String) -> bool:
	return token == _serial and generation == _generation and passage == _passage and is_instance_valid(_root)

func frame(token: int, panel: Rect2, safe: Rect2) -> bool:
	if token != _serial or not is_instance_valid(_root) or not is_instance_valid(_viewport): return false
	var bounds := get_viewport().get_visible_rect()
	var area := safe.intersection(bounds) if safe.has_area() else bounds
	if not area.has_area(): return false
	_panel_rect = panel
	_safe_rect = area
	_root.position = bounds.position
	_root.size = bounds.size
	var available := maxf(1.0,minf(panel.position.y-12.0,area.end.y)-area.position.y)
	var heading_height := minf(56.0,available)
	_caption.visible = available >= 40.0
	_picture.visible = available-heading_height >= 40.0
	_caption.position = area.position+Vector2(16,8)
	_caption.size = Vector2(maxf(1,area.size.x-32),maxf(1,heading_height-8))
	var next_rect := Rect2(area.position+Vector2(0,heading_height),Vector2(area.size.x,maxf(1,available-heading_height)))
	var old_rect := _picture.get_rect()
	_picture.position = next_rect.position
	_picture.size = next_rect.size
	# The picture needs no game ticks. Redraw only for a new passage or bounds.
	var render_scale := minf(1.0,1280.0/maxf(1,next_rect.size.x))
	var render_size := Vector2i(maxi(1,roundi(next_rect.size.x*render_scale)),maxi(1,mini(720,roundi(next_rect.size.y*render_scale))))
	if not _picture.visible:
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	elif old_rect != next_rect or _viewport.size != render_size:
		_viewport.size = render_size
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	return true

func clear(token: int) -> bool:
	if token != _serial: return false
	_serial += 1
	_generation = -1
	_passage = ""
	_dispose()
	return true

func refresh(token: int) -> bool:
	# A resumed graphics surface may need one redraw even at unchanged bounds.
	if token != _serial or not is_instance_valid(_viewport): return false
	if _picture.visible: _viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	return true

func _dispose() -> void:
	if is_instance_valid(_root):
		remove_child(_root)
		_root.queue_free()
	_root = null
	_picture = null
	_caption = null
	_viewport = null
	_world = null

func _exit_tree() -> void:
	_serial += 1
	_generation = -1
	_passage = ""
