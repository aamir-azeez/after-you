extends "res://tests/test_scroll_lists.gd"
const PaidCatalog = preload("res://services/paid_level_catalog.gd")
const Thumbnails = preload("res://presentation/paid_level_thumbnails.gd")

class Routes extends Main:
	var routed: Array = []
	func _open_lighthouse_preview() -> void: routed.append("lighthouse")
	func _open_cooperative_preview(key: String) -> void: routed.append("solo:"+key)
	func _show_relay_rooms(key: String = "") -> void: routed.append("together:"+key)
	func _start_practice(index: int) -> void: routed.append("legacy:"+str(index))

func _run() -> void:
	var expected := ["sleeping-lighthouse","rolling-home","a-house-for-two","conservatory","long-way-home","legacy-rising-together","legacy-across-the-blue","legacy-lantern-crossing","legacy-two-beats","legacy-after-you"]
	_check(PaidCatalog.keys()==expected,"All ten paid entries include Lighthouse and the separate earlier islands")
	var total := 0
	for key: String in PaidCatalog.keys():
		var entry := PaidCatalog.entry(key)
		total += int(entry.stages)
		_check(ResourceLoader.exists(entry.texture),"Bundled actual-world thumbnail exists: "+key)
		if ResourceLoader.exists(entry.texture):
			var texture: Texture2D = load(entry.texture)
			_check(texture.get_size()==Vector2(640,360),"Each menu asset has a bounded16:9 size: "+key)
	_check(total==19 and PaidCatalog.entry("legacy-long-way-home").is_empty(),"Paid catalog has19 stages and excludes the free earlier Long Way Home")
	var path := "user://paid-thumbnails-"+Crypto.new().generate_random_bytes(8).hex_encode()+".json"
	var storage := Storage.new(path)
	storage.data.settings.sound=false
	storage.data.settings.haptics=false
	_check(storage.flush(),"Use an isolated muted save")
	var original := FileAccess.get_file_as_string(path)
	var viewport := SubViewport.new()
	viewport.size=Vector2i(1280,720)
	viewport.handle_input_locally=true
	root.add_child(viewport)
	var app := Routes.new()
	app.saves=storage
	viewport.add_child(app)
	app.set_process(false); app.set_physics_process(false)
	var original_emulation := Input.emulate_touch_from_mouse
	Input.emulate_touch_from_mouse=true
	_check(DisplayServer.is_touchscreen_available(),"Real native scroll gestures are enabled, including Headless")
	for size: Vector2i in [Vector2i(1280,720),Vector2i(960,540)]:
		viewport.size=size
		await _paid_journey(app,viewport)
		await _paid_earlier(app,viewport)
		await _gallery(app,viewport,false)
		await _gallery(app,viewport,true)
	Input.emulate_touch_from_mouse=original_emulation
	_check(FileAccess.get_file_as_string(path)==original,"Viewing pictures and exercising isolated route callbacks never writes gameplay")
	viewport.queue_free()
	await _settle()
	await create_timer(0.15).timeout
	for suffix: String in ["",".tmp",".backup"]:
		if FileAccess.file_exists(path+suffix): DirAccess.remove_absolute(path+suffix)
	print("PAID LEVEL THUMBNAILS: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)

func _paid_journey(app: Node, viewport: SubViewport) -> void:
	app._show_journey()
	await _settle()
	var scroll := app.overlay.find_children("*","ScrollContainer",true,false)[0] as ScrollContainer
	var cards := _cards(scroll)
	_check(cards.size()==5,"Journey shows all five paid chapters without moving free choices")
	for card: Control in cards:
		await _picture_drag(app,viewport,scroll,card)
		for button: Button in card.find_children("*","Button",true,false):
			scroll.ensure_control_visible(button)
			await _settle()
			var before: int=app.routed.size()
			await _drag(viewport,button.get_global_rect().get_center(),Vector2(0,80 if scroll.scroll_vertical>0 else -80))
			_check(app.routed.size()==before,"Dragging a paid action does not activate Solo/Together")
			scroll.ensure_control_visible(button)
			await _settle()
			_pointer(viewport,button.get_global_rect().get_center(),true)
			_pointer(viewport,button.get_global_rect().get_center(),false)
			_check(app.routed.size()==before+1,"Actual paid-row tap retains its existing callback")
	_check(_fixed_back(app,viewport,"Back"),"Journey Back remains outside and below the scroll body")

func _paid_earlier(app: Node, viewport: SubViewport) -> void:
	app._show_earlier_islands()
	await _settle()
	var scroll := app.overlay.find_children("*","ScrollContainer",true,false)[0] as ScrollContainer
	_check(_cards(scroll).size()==5 and _rows(scroll).size()==8,"Earlier islands keeps three free and all five paid entries")
	for card: Control in _cards(scroll):
		await _picture_drag(app,viewport,scroll,card)
		var button := card.find_children("*","Button",true,false)[0] as Button
		scroll.ensure_control_visible(button); await _settle()
		var before: int=app.routed.size()
		_pointer(viewport,button.get_global_rect().get_center(),true)
		_pointer(viewport,button.get_global_rect().get_center(),false)
		_check(app.routed.size()==before+1 and str(app.routed[-1]).begins_with("legacy:"),"Earlier thumbnail retains the existing gated practice callback")
	_check(_fixed_back(app,viewport,"Back to chapters"),"Earlier islands Back stays fixed")

func _gallery(app: Node, viewport: SubViewport, large: bool) -> void:
	var card: VBoxContainer=app._card(800)
	card.add_child(app._label("Full Journey",32))
	var gallery := Thumbnails.gallery(minf(248,float(viewport.size.y)-360))
	card.add_child(gallery)
	for label: String in ["Get it on Google Play","Tester code","Back to chapters"]:
		card.add_child(app._button(label,func(): pass,false))
	if large:
		for label: Label in gallery.find_children("*","Label",true,false):
			label.add_theme_font_size_override("font_size",roundi(float(label.get_theme_font_size("font_size"))*1.5))
	await _settle()
	_check(_cards(gallery).size()==10,"Read-only paywall gallery contains every paid entry")
	_check(_rows(gallery).is_empty(),"Pictures do not provide an ungated gameplay or hidden preview action")
	var screen := Rect2(Vector2.ZERO,Vector2(viewport.size))
	_check(screen.encloses(gallery.get_global_rect()),"Gallery is bounded at both sizes and text scales")
	for row: Control in _cards(gallery):
		gallery.ensure_control_visible(row); await _settle()
		_check(gallery.get_global_rect().grow(0.5).encloses(row.get_global_rect()),"Every complete thumbnail row is reachable: "+str(row.get_meta("paid_level_key")))
		for label: Label in row.find_children("*","Label",true,false):
			_check(row.get_global_rect().encloses(label.get_global_rect()),"Large wrapped caption remains inside its thumbnail row")
	for button: Button in app.overlay.find_children("*","Button",true,false):
		_check(screen.encloses(button.get_global_rect()),"Access and Back actions stay fixed and reachable")

func _cards(node: Node) -> Array[Control]:
	var result: Array[Control]=[]
	for child: Control in node.find_children("PaidLevel_*","PanelContainer",true,false): result.append(child)
	return result

func _picture_drag(app: Node, viewport: SubViewport, scroll: ScrollContainer, card: Control) -> void:
	scroll.ensure_control_visible(card); await _settle()
	var picture := card.find_child("LevelPicture",true,false) as TextureRect
	_check(picture!=null and picture.texture!=null and picture.mouse_filter==Control.MOUSE_FILTER_IGNORE,"Thumbnail loads as a non-interactive static picture")
	var before: int=app.routed.size()
	var position := scroll.scroll_vertical
	await _drag(viewport,picture.get_global_rect().get_center(),Vector2(0,80 if position>0 else -80))
	_check(scroll.scroll_vertical!=position and app.routed.size()==before,"Dragging the image scrolls without opening or granting a level")

func _fixed_back(app: Node, viewport: SubViewport, label: String) -> bool:
	for button: Button in app.overlay.find_children("*","Button",true,false):
		if button.text==label: return Rect2(Vector2.ZERO,Vector2(viewport.size)).encloses(button.get_global_rect()) and not button.get_parent() is ScrollContainer
	return false
