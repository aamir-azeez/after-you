extends SceneTree
const Memory = preload("res://presentation/story_memory_backdrop.gd")
const StoryPanel = preload("res://presentation/story_panel.gd")
const Registry = preload("res://services/chapter_registry.gd")
var checks := 0
var failures := 0
var capture_dir := ""

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): capture_dir = arg.trim_prefix("--capture-dir=")
	if not capture_dir.is_empty(): DirAccess.make_dir_recursive_absolute(capture_dir)
	for size: Vector2i in [Vector2i(1280,720),Vector2i(960,540)]:
		var c := await _setup(size)
		for key: String in Memory.MemoryWorld.KEYS:
			for phase: String in ["arrival","completion"]: await _passage(c,key,phase,1.0)
		await _passage(c,Registry.HOUSE,"arrival",1.5)
		await _tokens(c)
		await _safe_resize(c)
		c.viewport.queue_free()
		await process_frame
		await process_frame
	print("Story memory illustrations: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

func _setup(size: Vector2i) -> Dictionary:
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var current_world := Node3D.new()
	viewport.add_child(current_world)
	var camera := Camera3D.new()
	camera.position = Vector3(7,9,12)
	camera.size = 13
	current_world.add_child(camera)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	var backdrop := Memory.new()
	viewport.add_child(backdrop)
	var panel := StoryPanel.new()
	viewport.add_child(panel)
	await process_frame
	return {"viewport":viewport,"camera":camera,"backdrop":backdrop,"panel":panel,"transform":camera.transform,"camera_size":camera.size}

func _passage(c: Dictionary, key: String, phase: String, text_scale: float) -> void:
	c.panel.text_scale = text_scale
	_check(c.panel.present("Story",[{"speaker":"p0","text":"An earlier place, remembered together."}],true),"The actual dialogue panel opens above the illustration")
	await process_frame
	var token: int = c.backdrop.present(7,key+":"+phase,key,phase,Registry.descriptor(key).title,c.panel.card.get_global_rect(),c.viewport.get_visible_rect())
	_check(token > 0,"A bundled chapter/phase receives a distinct presentation token")
	await process_frame
	await process_frame
	_check(c.backdrop.frame(token,c.panel.card.get_global_rect(),c.viewport.get_visible_rect()),"A settled card controls the available picture bounds")
	_check(c.backdrop._picture.get_rect().end.y <= c.panel.card.get_global_rect().position.y-11,"The picture does not enter the dialogue card")
	if text_scale == 1.0 or c.viewport.size.y >= 700:
		_check(c.backdrop._picture.size.y >= 90,"The illustration retains useful height at normal and production large-text bounds")
	else:
		_check(not c.backdrop._picture.visible,"The logical small-viewport large-text stress case preserves the readable dialogue over a neutral backdrop")
	_check(c.backdrop._viewport.world_3d != c.viewport.world_3d and c.backdrop._viewport.gui_disable_input,"The illustration has its own world and cannot receive gameplay input")
	_check(c.camera.transform == c.transform and c.camera.size == c.camera_size and c.camera.current,"Presentation leaves the current gameplay camera untouched")
	_check(not c.backdrop._world.is_processing() and not c.backdrop._world.is_physics_processing() and not c.backdrop._world.is_processing_input(),"Inherited world motion and input remain stopped")
	_check(c.backdrop._caption.text == Registry.descriptor(key).title+" · "+phase.capitalize(),"The heading identifies the requested chapter and phase")
	var name: String = key.replace("@","-")+"-"+phase+"-"+str(c.viewport.size.x)+("-large" if text_scale > 1.0 else "")
	await _capture(c,name)
	_check(c.backdrop.clear(token),"Current passage teardown succeeds")
	c.panel.cancel()
	await process_frame
	await process_frame
	_check(c.backdrop._root == null and c.camera.transform == c.transform,"Closing releases the illustration without changing the active camera")

func _tokens(c: Dictionary) -> void:
	var rect := Rect2(30,330,c.viewport.size.x-60,200)
	var safe: Rect2 = c.viewport.get_visible_rect()
	var old: int = c.backdrop.present(15,"arrival",Registry.RELAY,"arrival","Relay Isles",rect,safe)
	var old_root: WeakRef = weakref(c.backdrop._root)
	var next: int = c.backdrop.present(15,"completion",Registry.RELAY,"completion","Relay Isles",rect,safe)
	_check(next > old and c.backdrop.matches(next,15,"completion"),"Consecutive beats sharing one hold still have distinct passage tokens")
	var picture: Rect2 = c.backdrop._picture.get_rect()
	_check(not c.backdrop.clear(old) and not c.backdrop.frame(old,Rect2(),Rect2()),"Old resize and disposal callbacks cannot affect the new beat")
	_check(not c.backdrop.refresh(old) and c.backdrop.refresh(next),"Only the current passage may request a one-frame redraw after resume")
	_check(c.backdrop._picture.get_rect() == picture and c.backdrop.matches(next,15,"completion"),"A stale callback preserves the current illustration")
	_check(c.backdrop.present(15,"invalid","unknown@1","arrival","Unknown",rect,safe) == -1 and c.backdrop.matches(next,15,"completion"),"Invalid content cannot replace a current illustration")
	await process_frame
	await process_frame
	_check(old_root.get_ref() == null,"The previous world is disposed between beats")
	_check(c.backdrop.clear(next) and not c.backdrop.frame(next,rect,safe),"A closed token cannot restore a dismissed illustration")
	await process_frame

func _capture(c: Dictionary, name: String) -> void:
	if capture_dir.is_empty(): return
	await process_frame
	await RenderingServer.frame_post_draw
	var texture: ViewportTexture = c.viewport.get_texture()
	_check(texture != null and texture.get_image().save_png(capture_dir.path_join(name+".png")) == OK,"Rendered memory capture: "+name)

func _safe_resize(c: Dictionary) -> void:
	var original: Vector2i = c.viewport.size
	var safe := Rect2(75,18,original.x-110,original.y-40)
	c.panel.safe_rect_override = safe
	c.panel.text_scale = 1.5
	_check(c.panel.present("Story",[{"speaker":"p1","text":"An earlier place, remembered together."}],true),"Large text opens inside an asymmetric safe area")
	await process_frame
	var token: int = c.backdrop.present(20,"safe",Registry.CONSERVATORY,"arrival",Registry.descriptor(Registry.CONSERVATORY).title,c.panel.card.get_global_rect(),safe)
	await process_frame
	var picture: Rect2 = c.backdrop._picture.get_rect()
	_check(safe.encloses(picture) and picture.end.y < c.panel.card.get_global_rect().position.y,"Cutouts constrain the picture independently from the dialogue card")
	await _capture(c,"conservatory-safe-"+str(original.x))
	c.viewport.size = Vector2i(1060,620)
	safe = Rect2(30,24,980,560)
	c.panel.safe_rect_override = safe
	c.panel._layout()
	await process_frame
	_check(c.backdrop.frame(token,c.panel.card.get_global_rect(),safe),"An active passage can reframe after resize without replacing its token")
	_check(safe.encloses(c.backdrop._picture.get_rect()) and c.backdrop._viewport.size.x <= 1280 and c.backdrop._viewport.size.y <= 720,"Resizing preserves safe bounds and the render budget")
	_check(c.camera.transform == c.transform and c.camera.current,"Safe-area resize leaves the playable camera untouched")
	var compact := Rect2(safe.position.x,safe.position.y+51,400,400)
	_check(c.backdrop.frame(token,compact,safe) and not c.backdrop._caption.visible and not c.backdrop._picture.visible,"Less than40pixels uses a neutral fallback without overlapping the dialogue")
	compact.position.y = safe.position.y+160
	_check(c.backdrop.frame(token,compact,safe) and c.backdrop._caption.visible and c.backdrop._picture.visible,"Making room restores the same passage's caption and illustration")
	_check(c.backdrop.clear(token),"Resized passage disposes normally")
	c.panel.cancel()
	c.viewport.size = original
	c.panel.safe_rect_override = Rect2()
	await process_frame

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
