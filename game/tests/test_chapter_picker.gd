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
	func _open_lighthouse_preview() -> void: routed.append("solo:"+KeepsakeCatalog.LIGHTHOUSE)
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
		if size==Vector2i(1280,720): await _peek_heights(app,viewport)
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
	await _picker_structure(app,viewport,scroll)
	var context := " at "+str(viewport.size)
	# The whole card is the only control per chapter: it opens the chapter solo.
	# Playing together starts from Play with your friend, so nothing else is offered.
	var buttons: Array = scroll.find_children("*","Button",true,false)
	_check(not buttons.any(func(button: Button) -> bool: return not button.text.is_empty() or button.get_meta("completion_variant","")!="solo"),"Play Solo cards carry no separate Solo or Together buttons")
	var grid: GridContainer=scroll.find_child("JourneyChapters",true,false)
	var cards: Array = grid.get_children() if grid != null else []
	_check(buttons.size()==cards.size() and cards.size()==Chapters.keys().size()+1,"Every chapter card, including Lighthouse, is exactly one tap target")
	for card: Control in cards:
		var key := str(card.get_meta("chapter_key",""))
		var mark := KeepsakeCatalog.LIGHTHOUSE if key=="sleeping-lighthouse" else key
		var targets: Array[Node]=card.find_children("*","Button",true,false)
		_check(targets.size()==1,"One tap target per card: "+key)
		if targets.size()!=1: continue
		var open: Button=targets[0]
		var title := card.find_child("LevelTitle",true,false) as Label
		_check(open.get_meta("completion_chapter","")==mark and open.get_meta("completion_variant","")=="solo","The card target keeps this chapter's solo completion identity: "+key)
		_check(open.mouse_filter==Control.MOUSE_FILTER_PASS and open.focus_mode==Control.FOCUS_ALL and title != null and open.accessibility_name==title.text+" · Solo","The card is a focusable, named tap target that lets drags reach the list: "+key)
		_check(open.get_global_rect().is_equal_approx(card.get_global_rect()) and open.get_global_rect().size.x>=48 and open.get_global_rect().size.y>=48,"The tap target covers the whole card with a full touch target: "+key+context)
		var blocking: Array=card.find_children("*","Control",true,false).filter(func(node: Node) -> bool: return node != open and (node as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE)
		_check(blocking.is_empty(),"Picture, text and layout inside the card never take the pointer: "+key)
		_check((open.get_theme_stylebox("normal") as StyleBoxFlat).bg_color==Color("1b443e") and (open.get_theme_stylebox("hover") as StyleBoxFlat).bg_color==Color("23504a") and (open.get_theme_stylebox("pressed") as StyleBoxFlat).bg_color==Color("2b5a53"),"The card brightens on hover and again while pressed: "+key)
		var ring := open.get_theme_stylebox("focus") as StyleBoxFlat
		_check(ring != null and ring.border_color==app.MINT and ring.border_width_left>=1 and ring.bg_color.a==0.0,"Keyboard focus draws a mint ring around the card: "+key)
		var complete: bool=key==Chapters.FIRST_STEPS
		var tick := card.find_child("ChapterDone",true,false) as TextureRect
		_check(tick != null and tick.texture != null and tick.visible==complete and open.get_meta("chapter_complete",not complete)==complete,"Only a chapter completed solo shows the tick: "+key)
		_check(title != null and title.get_theme_color("font_color")==app.CREAM,"The title stays cream in both completion states: "+key)
		if complete and tick != null and title != null:
			var mark_rect := tick.get_global_rect()
			_check(mark_rect.size.x>=22 and mark_rect.size.x<=26 and tick.self_modulate==app.MINT and tick.mouse_filter==Control.MOUSE_FILTER_IGNORE,"The tick is a mint icon about 24 units wide")
			_check(mark_rect.position.x>=title.get_global_rect().end.x-0.5 and mark_rect.position.x<=title.get_global_rect().end.x+12.0 and mark_rect.get_center().y>title.get_global_rect().position.y and mark_rect.get_center().y<title.get_global_rect().end.y and card.get_global_rect().encloses(mark_rect),"The tick directly follows the title text inside the card")
		scroll.ensure_control_visible(card)
		await _settle()
		_check(scroll.get_global_rect().grow(0.5).encloses(card.get_global_rect()),"Each card can be brought fully into view: "+key+context)
		var picture := card.find_child("LevelPicture",true,false) as Control
		var spare := Vector2(card.get_global_rect().end.x-6.0,card.get_global_rect().get_center().y)
		for spot: Vector2 in [picture.get_global_rect().get_center(),title.get_global_rect().get_center(),spare]:
			var before: int=app.routed.size()
			_pointer(viewport,spot,true)
			_check(open.get_draw_mode()==BaseButton.DRAW_PRESSED and app.routed.size()==before,"A press shows the pressed card before release: "+key)
			_pointer(viewport,spot,false)
			_check(app.routed.size()==before+1 and app.routed[-1]=="solo:"+mark,"A real tap on the picture, title or empty card space opens this chapter solo: "+key+context)
	# Keyboard focus on an off-screen card shows its ring and scrolls it into
	# view, and accepting it opens the chapter just like a tap.
	if not cards.is_empty():
		var last: Control = cards[-1]
		var target := last.get_node("ChapterOpen") as Button
		viewport.gui_release_focus()
		scroll.scroll_vertical = 0
		await _settle()
		_check(not scroll.get_global_rect().grow(0.5).encloses(target.get_global_rect()),"The last card starts out of view"+context)
		target.grab_focus()
		await _settle()
		_check(target.has_focus(true) and scroll.get_global_rect().grow(0.5).encloses(target.get_global_rect()),"A keyboard-focused card is shown and brought fully into view"+context)
		var before: int=app.routed.size()
		for pressed: bool in [true,false]:
			var accept := InputEventAction.new()
			accept.action = "ui_accept"
			accept.pressed = pressed
			viewport.push_input(accept)
		_check(app.routed.size()==before+1 and app.routed[-1]=="solo:"+str(last.get_meta("chapter_key")),"Accepting a focused card opens it solo"+context)
		viewport.gui_release_focus()
	var relay_card: Control=grid.get_node_or_null("FreeChapter_relay_isles") if grid != null else null
	var relay_title: Label = relay_card.find_child("LevelTitle",true,false) if relay_card != null else null
	var untouched: Rect2 = relay_title.get_global_rect() if relay_title != null else Rect2()
	for id: String in KeepsakeCatalog.chapter_places(Chapters.RELAY):
		app.home_keepsakes._earned[id].solo=true
	app._service_home_keepsakes(0.2)
	await _settle()
	for card: Control in cards:
		var key := str(card.get_meta("chapter_key",""))
		var tick := card.find_child("ChapterDone",true,false) as Control
		_check(tick != null and tick.visible==(key in [Chapters.FIRST_STEPS,Chapters.RELAY]),"A completed backfill updates ticks without reopening the picker: "+key)
	_check(relay_title != null and relay_title.get_global_rect().is_equal_approx(untouched),"A tick appearing never reflows its title")
	for card: Control in cards: (card.find_child("LevelTitle",true,false) as Label).add_theme_font_size_override("font_size",34)
	app._refresh_chapter_marks()
	await _settle()
	await _settle()
	var shown := 0
	for card: Control in cards:
		var title := card.find_child("LevelTitle",true,false) as Label
		var tick := card.find_child("ChapterDone",true,false) as Control
		_check(card.get_global_rect().encloses(title.get_global_rect()) and card.get_global_rect().position.x>=scroll.get_global_rect().position.x-0.5 and card.get_global_rect().end.x<=scroll.get_global_rect().end.x+0.5,"Larger titles wrap inside the card without horizontal overflow: "+str(card.get_meta("chapter_key")))
		_check(title.get_line_count()==title.get_visible_line_count() and title.get_global_rect().size.y>=title.get_line_count()*30.0,"Every line of a larger title stays visible: "+str(card.get_meta("chapter_key")))
		if not tick.visible: continue
		shown += 1
		var mark_rect := tick.get_global_rect()
		_check(not mark_rect.intersects(title.get_global_rect()) and mark_rect.position.x<=title.get_global_rect().end.x+12.0 and card.get_global_rect().encloses(mark_rect),"The tick still follows a larger title inside its card")
	_check(shown==2,"Both completed chapters keep their tick at the larger text size")

func _peek_heights(app: Node, viewport: SubViewport) -> void:
	# Safe areas of any height keep part of the next row in view without
	# bloating the cards.
	var screen := Rect2(Vector2.ZERO,Vector2(viewport.size))
	for trim: float in [0.0,40.0,80.0,100.0,120.0,160.0]:
		app._apply_safe_area(Rect2(Vector2(0,trim*0.5),Vector2(viewport.size.x,viewport.size.y-trim)))
		app._show_journey()
		await _settle()
		await _settle()
		var scroll: ScrollContainer=app.overlay.find_children("*","ScrollContainer",true,false)[0]
		var grid: GridContainer=scroll.find_child("JourneyChapters",true,false)
		var view := scroll.get_global_rect()
		var cut := 0.0
		var natural := 0.0
		var tallest := 0.0
		for card: Control in grid.get_children():
			natural = maxf(natural,card.get_minimum_size().y)
			tallest = maxf(tallest,card.size.y)
			var rect := card.get_global_rect()
			if rect.intersects(view) and not view.grow(0.5).encloses(rect): cut = maxf(cut,rect.intersection(view).size.y/rect.size.y)
		var context := " with a %d-unit list" % roundi(view.size.y)
		_check(cut>=0.2 and cut<=0.9,"Part of the next row peeks into view"+context)
		_check(tallest<=natural*1.25,"Cards grow only modestly to keep that peek"+context)
	app._apply_safe_area(screen)
	await _settle()

func _picker_structure(app: Node, viewport: SubViewport, scroll: ScrollContainer) -> void:
	var screen := Rect2(Vector2.ZERO,Vector2(viewport.size))
	var context := " at "+str(viewport.size)
	# Header: a labelled Back and the page title, then Chapters/Earlier islands tabs.
	var back := _find_button(app.overlay,"Back")
	_check(back != null and not scroll.is_ancestor_of(back) and screen.encloses(back.get_global_rect()) and back.get_global_rect().end.y <= scroll.get_global_rect().position.y,"A labelled Back stays fixed above the chapter grid"+context)
	_check(_label_contains(app.overlay,"Your journey") and not _label_contains(app.overlay,PlayerCopy.MAIN_1DB48306B203) and not _label_contains(app.overlay,PlayerCopy.MAIN_F88B3CEBD7BA),"The picker is titled Your journey without the old First Steps heading"+context)
	var chapters := _find_button(app.overlay,"Chapters")
	var earlier := _find_button(app.overlay,"Earlier islands")
	_check(chapters != null and chapters.disabled and earlier != null and not earlier.disabled and not scroll.is_ancestor_of(chapters) and not scroll.is_ancestor_of(earlier),"Chapters is the selected tab beside an available Earlier islands tab"+context)
	if chapters != null and earlier != null:
		_check(chapters.get_global_rect().size.y>=48 and earlier.get_global_rect().size.y>=48 and not chapters.get_global_rect().intersects(earlier.get_global_rect()),"Both tabs keep full, distinct touch targets"+context)
	# Every chapter is a picture card; free chapters lead, then Full Journey.
	var grid: GridContainer = scroll.find_child("JourneyChapters",true,false)
	var expected: Array[String] = []
	for key: String in Chapters.keys():
		if not Chapters.descriptor(key).premium: expected.append(key)
	expected.append("sleeping-lighthouse")
	for key: String in Chapters.keys():
		if Chapters.descriptor(key).premium: expected.append(key)
	var order: Array[String] = []
	if grid != null:
		for card: Control in grid.get_children(): order.append(str(card.get_meta("chapter_key","")))
	_check(order == expected,"Free chapters come first, then every Full Journey chapter in registry order"+context)
	_check(grid != null and grid.columns == (2 if viewport.size.x >= 1280 else 1),"Chapters fill two columns on a landscape phone and one on a narrow screen"+context)
	if grid == null: return
	for card: Control in grid.get_children():
		var key := str(card.get_meta("chapter_key",""))
		var premium: bool = key == "sleeping-lighthouse" or Chapters.descriptor(key).premium
		var picture := card.find_child("LevelPicture",true,false) as TextureRect
		_check(picture != null and picture.texture != null and picture.mouse_filter == Control.MOUSE_FILTER_IGNORE,"Every chapter card shows its picture: "+key)
		var title := card.find_child("LevelTitle",true,false) as Label
		_check(title != null and not title.text.is_empty() and title.get_theme_font("font") == app.title_font,"Every chapter card names its chapter in the heading font: "+key)
		var access := card.find_child("ChapterAccess",true,false) as Label
		_check(access != null and access.text == ("Full Journey" if premium else "Free to play"),"Every chapter card says whether it is free or Full Journey: "+key)
		_check(card.name.begins_with("PaidLevel_") == premium,"Only Full Journey chapters keep the paid picture-card identity: "+key)
		_check(card is PanelContainer and is_equal_approx(card.custom_minimum_size.x,460.0),"Each card keeps its roomy minimum width: "+key)
		_check(card.get_global_rect().position.x >= scroll.get_global_rect().position.x - 0.5 and card.get_global_rect().end.x <= scroll.get_global_rect().end.x + 0.5,"Chapter card stays within the grid width without horizontal overflow: "+key+context)
	# A scrolled grid always shows part of the next row as a cue to keep going.
	scroll.scroll_vertical = 0
	await _settle()
	_check(scroll.get_v_scroll_bar().max_value > scroll.get_v_scroll_bar().page,"The chapter grid scrolls internally"+context)
	var partial := false
	for card: Control in grid.get_children():
		var rect := card.get_global_rect()
		if rect.intersects(scroll.get_global_rect()) and not scroll.get_global_rect().grow(0.5).encloses(rect) and rect.intersection(scroll.get_global_rect()).size.y >= 24.0: partial = true
	_check(partial,"Part of the next row of chapters peeks into view"+context)
