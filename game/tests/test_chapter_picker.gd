extends "res://tests/test_scroll_lists.gd"
const Completion = preload("res://presentation/chapter_completion.gd")
const Keepsakes = preload("res://services/home_keepsakes.gd")
const KeepsakeCatalog = preload("res://services/home_keepsake_catalog.gd")

class Routes extends Main:
	var routed: Array = []
	var owned := false
	func _full_journey_access() -> bool: return owned
	func _open_first_steps() -> void: routed.append("solo:"+Chapters.FIRST_STEPS)
	func _open_relay_preview() -> void: routed.append("solo:"+Chapters.RELAY)
	func _open_cooperative_preview(key: String) -> void: routed.append("solo:"+key)
	func _show_relay_rooms(key: String = "") -> void: routed.append("together:"+key)
	func _show_friends() -> void: routed.append("friends")

func _run() -> void:
	var path := "user://chapter-picker-"+Crypto.new().generate_random_bytes(8).hex_encode()+".json"
	var storage := Storage.new(path)
	storage.data.settings.sound=false
	storage.data.settings.haptics=false
	_check(storage.flush(),"Use an isolated muted save")
	var saved := FileAccess.get_file_as_string(path)
	var viewport := SubViewport.new()
	viewport.size=Vector2i(1280,720)
	viewport.handle_input_locally=true
	root.add_child(viewport)
	var app := Routes.new()
	app.saves=storage
	app.home_keepsakes=Keepsakes.new(path+"-keepsakes")
	viewport.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	app.home_keepsakes.cancel_backfill()
	_test_completion()
	for size: Vector2i in [Vector2i(1280,720),Vector2i(960,540)]:
		viewport.size=size
		await _home_offer(app,viewport)
		await _picker(app,viewport)
	_check(FileAccess.get_file_as_string(path)==saved,"Menu visits and route clicks preserve the gameplay save")
	viewport.queue_free()
	await _settle()
	await create_timer(0.15).timeout
	for basename: String in [path,path+"-keepsakes"]:
		for suffix: String in ["",".tmp",".backup"]:
			if FileAccess.file_exists(basename+suffix): DirAccess.remove_absolute(basename+suffix)
	print("CHAPTER PICKER: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)

func _test_completion() -> void:
	var earned: Array[Dictionary] = []
	for chapter: String in KeepsakeCatalog.CHAPTERS:
		var places := KeepsakeCatalog.chapter_places(chapter)
		for index in range(places.size()):
			earned.append({"id":places[index],"solo":index<places.size()-1,"friend":true})
		var marks := Completion.chapters(earned)
		_check(not marks[chapter].solo,"A partial chapter is never marked complete: "+chapter)
		_check(marks[chapter].friend==(chapter!=KeepsakeCatalog.LIGHTHOUSE),"Friend progress is independent and Lighthouse has no Together completion")
		earned[-1].solo=true
		_check(Completion.chapters(earned)[chapter].solo,"Completing every authored stage earns the chapter tick: "+chapter)
	_check(not Completion.chapters([])[Chapters.FIRST_STEPS].solo,"A fresh profile shows no invented completion")

func _home_offer(app: Node, viewport: SubViewport) -> void:
	app.owned=false
	app._show_home()
	app.home_keepsakes.cancel_backfill()
	await _settle()
	var offer: Button=app.overlay.get_node("HomeFullJourney")
	var screen := Rect2(Vector2.ZERO,Vector2(viewport.size))
	var stage: Control=app.home_stage_view
	stage._zoom(0.8)
	stage._process(0.0)
	_check(stage._reset.is_visible_in_tree(),"Exploring home reveals Reset view while the purchase offer is present")
	_check(offer.visible and screen.encloses(offer.get_global_rect()),"Unowned home shows a bounded Full Journey entry")
	_check(offer.get_global_rect().position.x>viewport.size.x*0.65,"The purchase entry occupies the top-right corner")
	var friends: Button=app.overlay.find_child("HomeFriends",true,false)
	_check(friends.is_visible_in_tree() and screen.encloses(friends.get_global_rect()),"Friends has a visible home navigation entry")
	var row_labels: Array = friends.get_parent().get_children().filter(func(control: Node) -> bool: return control is Button).map(func(button: Button) -> String: return button.text)
	_check(friends.get_parent() is HBoxContainer and row_labels == ["Play Solo","","Settings"],"Friends sits between Play Solo and Settings in the navigation row")
	_check(friends.get_global_rect().size.x >= 48 and friends.get_global_rect().size.y >= 48 and friends.tooltip_text == "Friends","The Friends icon retains its label and full touch target")
	var routes_before: int=app.routed.size()
	_pointer(viewport,friends.get_global_rect().get_center(),true)
	_pointer(viewport,friends.get_global_rect().get_center(),false)
	_check(app.routed.size()==routes_before+1 and app.routed[-1]=="friends","The home Friends click dispatches the existing Friends entry")
	for button: Button in app.overlay.find_children("*","Button",true,false):
		if button==offer or not button.visible: continue
		_check(not offer.get_global_rect().intersects(button.get_global_rect()),"Home purchase entry does not overlap another action")
		_check(screen.encloses(button.get_global_rect()),"Home actions remain entirely visible on a short landscape screen")
	await _reset_beside_offer(app,viewport,screen)
	var inset := Rect2(Vector2(48,18),Vector2(viewport.size)-Vector2(80,42))
	app._apply_safe_area(inset)
	await _settle()
	await _reset_beside_offer(app,viewport,inset)
	app._apply_safe_area(screen)
	await _settle()
	_pointer(viewport,offer.get_global_rect().get_center(),true)
	_pointer(viewport,offer.get_global_rect().get_center(),false)
	await _settle()
	_check(app.mode=="paywall" and app.overlay.find_child("FullJourneyGallery",true,false)!=null,"Actual home tap opens the existing gallery and gated purchase flow")
	app.owned=true
	app._show_home()
	app.home_keepsakes.cancel_backfill()
	await _settle()
	_check(not app.overlay.get_node("HomeFullJourney").visible,"An existing owner is not prompted to buy again")
	stage=app.home_stage_view
	stage._zoom(0.8)
	stage._process(0.0)
	var owned_reset_y: float=stage._reset.global_position.y
	app.owned=false
	app._service_home_keepsakes(0.2)
	stage._process(0.0)
	_check(app.overlay.get_node("HomeFullJourney").visible,"A changed access state refreshes the current home entry")
	_check(stage._reset.global_position.y>owned_reset_y and not stage._reset.get_global_rect().intersects(app.overlay.get_node("HomeFullJourney").get_global_rect()),"An offer appearing while home is explored leaves Reset view reachable")
	app.owned=true
	app._service_home_keepsakes(0.2)
	stage._process(0.0)
	_check(not app.overlay.get_node("HomeFullJourney").visible,"A confirmed unlock removes the current home prompt")
	_check(is_equal_approx(stage._reset.global_position.y,owned_reset_y),"Reset returns to its original place after the offer hides")
	_pointer(viewport,stage._reset.get_global_rect().get_center(),true)
	_pointer(viewport,stage._reset.get_global_rect().get_center(),false)
	_check(is_equal_approx(stage.zoom_target,stage.DEFAULT_SIZE),"Reset view also receives real clicks after an unlock")
	app.owned=false

func _reset_beside_offer(app: Node, viewport: SubViewport, safe: Rect2) -> void:
	var stage: Control=app.home_stage_view
	var offer: Button=app.overlay.get_node("HomeFullJourney")
	stage._zoom(0.8)
	stage._process(0.0)
	var reset: Button=stage._reset
	_check(reset.is_visible_in_tree() and not reset.get_global_rect().intersects(offer.get_global_rect()),"Zoomed home keeps Reset view clear of Full Journey")
	_check(safe.encloses(reset.get_global_rect()) and safe.encloses(offer.get_global_rect()),"Both home actions fit the current safe area")
	_check(not stage._allowed(reset.get_global_rect().get_center()) and not stage._allowed(offer.get_global_rect().get_center()),"Home actions cannot capture scenery gestures")
	var friends: Button=app.overlay.find_child("HomeFriends",true,false)
	_check(safe.encloses(friends.get_global_rect()) and not friends.get_global_rect().intersects(offer.get_global_rect()) and not friends.get_global_rect().intersects(reset.get_global_rect()) and not stage._allowed(friends.get_global_rect().get_center()),"Friends stays in the cutout-safe navigation area and outside home gestures")
	_pointer(viewport,reset.get_global_rect().get_center(),true)
	_pointer(viewport,reset.get_global_rect().get_center(),false)
	await _settle()
	stage._process(0.0)
	_check(app.mode=="home" and is_equal_approx(stage.zoom_target,stage.DEFAULT_SIZE) and stage._exploration.pan.is_zero_approx() and not reset.visible,"Actual Reset click resets the camera without opening the purchase screen")

func _picker(app: Node, viewport: SubViewport) -> void:
	app.home_keepsakes._earned.clear()
	# The keepsake service is already covered at its replay-verification boundary;
	# seed its cosmetic output to exercise the real menu's separate mode marks.
	for id: String in KeepsakeCatalog.chapter_places(Chapters.FIRST_STEPS):
		app.home_keepsakes._earned[id]={"solo":true,"friend":false}
	for id: String in KeepsakeCatalog.chapter_places(Chapters.RELAY):
		app.home_keepsakes._earned[id]={"solo":false,"friend":true}
	app._show_journey()
	await _settle()
	var scroll: ScrollContainer=app.overlay.find_children("*","ScrollContainer",true,false)[0]
	var together_x := -1.0
	var buttons: Array = app.overlay.find_children("*","Button",true,false)
	var marked := 0
	for button: Button in buttons:
		if not button.has_meta("completion_chapter"): continue
		marked+=1
		var key: String=button.get_meta("completion_chapter")
		var variant: String=button.get_meta("completion_variant")
		var complete: bool=(key==Chapters.FIRST_STEPS and variant=="solo") or (key==Chapters.RELAY and variant=="friend")
		_check(button.text.ends_with("✓")==complete,"Only the completed mode has a tick: "+key+"/"+variant)
		_check(button.get_theme_color("font_color")==app.MINT if complete else button.get_theme_color("font_color")==app.CREAM,"Chapter text retains a readable color in both completion states")
		if variant=="friend":
			if together_x<0: together_x=button.get_global_rect().position.x
			_check(is_equal_approx(together_x,button.get_global_rect().position.x),"Together forms one column across old and new chapters")
		if key==KeepsakeCatalog.LIGHTHOUSE: continue
		scroll.ensure_control_visible(button)
		await _settle()
		_check(scroll.get_global_rect().grow(0.5).encloses(button.get_global_rect()),"Chapter action remains fully reachable at the smaller layout")
		var before: int=app.routed.size()
		_pointer(viewport,button.get_global_rect().get_center(),true)
		_pointer(viewport,button.get_global_rect().get_center(),false)
		_check(app.routed.size()==before+1 and app.routed[-1]==("solo:" if variant=="solo" else "together:")+key,"Actual menu tap selects this chapter and mode")
	_check(marked==Chapters.keys().size()*2+1,"Every chapter mode participates, including Lighthouse Solo")
	app.home_keepsakes._earned["first-steps/a-place-to-grow"].friend=true
	app.home_keepsakes._earned["first-steps/a-little-lift"].friend=true
	app._service_home_keepsakes(0.2)
	for button: Button in buttons:
		if button.get_meta("completion_chapter","")==Chapters.FIRST_STEPS:
			_check(button.text.ends_with("✓"),"A completed backfill updates marks without reopening the picker")
	for button: Button in buttons:
		if button.has_meta("completion_chapter"): button.add_theme_font_size_override("font_size",30)
	app._refresh_chapter_marks()
	await _settle()
	together_x=-1
	for button: Button in buttons:
		if button.get_meta("completion_variant","")!="friend": continue
		if together_x<0: together_x=button.get_global_rect().position.x
		_check(is_equal_approx(together_x,button.get_global_rect().position.x),"Completed and uncompleted Together labels remain aligned at larger text size")
