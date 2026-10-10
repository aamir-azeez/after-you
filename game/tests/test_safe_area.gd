extends SceneTree
## Real Window stretch transforms plus interactive UI under physical cutout insets.

const Main = preload("res://main.gd")
const Storage = preload("res://services/local_save.gd")
const SafeArea = preload("res://presentation/safe_area.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	checks+=1
	if not condition:
		failures+=1
		push_error(message)

func _same_rect(actual: Rect2, expected: Rect2, context: String) -> void:
	_check(actual.position.is_equal_approx(expected.position) and actual.size.is_equal_approx(expected.size),"%s: expected %s, received %s" % [context,expected,actual])

func _test_conversion() -> void:
	var viewport := Rect2(0,0,1100,650)
	_same_rect(SafeArea.viewport_rect(Rect2(60,20,980,580),Transform2D.IDENTITY,viewport),Rect2(60,20,980,580),"Unscaled insets keep both origin and extent")
	var scaled := Transform2D(Vector2(2,0),Vector2(0,3),Vector2(40,30))
	_same_rect(SafeArea.viewport_rect(Rect2(160,90,1960,1740),scaled,viewport),Rect2(60,20,980,580),"Native pixels are inverse-scaled and translated exactly once")
	_same_rect(SafeArea.viewport_rect(Rect2(-40,40,1200,500),Transform2D.IDENTITY,viewport),Rect2(0,40,1100,500),"Partially external native rectangle is clipped to the viewport")
	var offset_viewport := Rect2(30,15,900,600)
	_same_rect(SafeArea.viewport_rect(Rect2(20,40,980,500),Transform2D.IDENTITY,offset_viewport),Rect2(30,40,900,500),"Clipping respects a nonzero viewport origin")
	for invalid: Rect2 in [Rect2(),Rect2(20,30,-5,60),Rect2(1500,900,10,10)]:
		_same_rect(SafeArea.viewport_rect(invalid,Transform2D.IDENTITY,viewport),viewport,"Unavailable, inverted or wholly external rectangle falls back without hiding UI")
	var singular := Transform2D(Vector2.ZERO,Vector2(0,2),Vector2(50,20))
	_same_rect(SafeArea.viewport_rect(Rect2(10,10,800,600),singular,viewport),viewport,"Unavailable singular screen transform falls back before inversion")
	for invalid: Rect2 in [Rect2(Vector2(NAN,0),Vector2(800,600)),Rect2(Vector2.ZERO,Vector2(INF,600))]:
		_same_rect(SafeArea.viewport_rect(invalid,Transform2D.IDENTITY,viewport),viewport,"Non-finite native rectangle cannot become UI bounds")

func _settle_layout() -> void:
	# Container minimum sizes and Window stretch transforms settle on deferred frames.
	await process_frame
	await process_frame
	await process_frame

func _run() -> void:
	_test_conversion()
	var original := {
		"size":root.size,
		"content_scale_size":root.content_scale_size,
		"content_scale_mode":root.content_scale_mode,
		"content_scale_aspect":root.content_scale_aspect,
		"content_scale_factor":root.content_scale_factor,
	}
	_check(root.content_scale_mode==Window.CONTENT_SCALE_MODE_CANVAS_ITEMS,"The actual project Window boots with canvas-items scaling")
	_check(root.content_scale_aspect==Window.CONTENT_SCALE_ASPECT_EXPAND,"The actual project Window boots with expansion rather than letterboxing")
	root.content_scale_size=Vector2i(1280,720)
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect=Window.CONTENT_SCALE_ASPECT_EXPAND
	root.content_scale_factor=1.0
	var path := "user://safe-area-test-"+Crypto.new().generate_random_bytes(8).hex_encode()+".json"
	var app := Main.new()
	app.saves=Storage.new(path)
	app.saves.data.settings.sound=false
	app.saves.flush()
	root.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	_check(app.get_viewport()==root and app.world.get_viewport()==root,"UI and 3D world use the real root Window, not an unstretched SubViewport")
	for physical_size: Vector2i in [Vector2i(1280,720),Vector2i(2400,1080),Vector2i(3120,1440),Vector2i(1280,960)]:
		root.size=physical_size
		await _settle_layout()
		var viewport := root.get_visible_rect()
		var transform := root.get_screen_transform()
		_same_rect(transform*viewport,Rect2(Vector2.ZERO,Vector2(physical_size)),"Expanded Window content fills every native pixel at %s" % physical_size)
		_check(is_equal_approx(transform.x.length(),transform.y.length()),"Window expansion preserves proportions at %s" % physical_size)
		if physical_size.x*720>physical_size.y*1280:
			_check(viewport.size.x>1280 and is_equal_approx(viewport.size.y,720),"Wide Window reveals more horizontal space instead of keeping a 16:9 letterbox")
		elif physical_size.x*720<physical_size.y*1280:
			_check(viewport.size.y>720 and is_equal_approx(viewport.size.x,1280),"Tablet Window reveals more vertical space without clipping the base width")
		for insets: Vector4 in [Vector4(96,0,0,0),Vector4(136,0,0,0),Vector4(0,0,72,0),Vector4(64,18,48,24)]:
			var native_safe := Rect2(Vector2(insets.x,insets.y),Vector2(physical_size)-Vector2(insets.x+insets.z,insets.y+insets.w))
			var safe := SafeArea.viewport_rect(native_safe,transform,viewport)
			_same_rect(transform*safe,native_safe,"Safe UI projects back to native cutout bounds at %s" % physical_size)
			app._apply_safe_area(safe)
			await _settle_layout()
			_same_rect(app.ui.get_global_rect(),safe,"Main applies cutout insets once to its interactive root")
			await _test_controls(app,safe,physical_size)
			await _test_menus(app,safe,viewport)
			# Replacing an existing inset should also update the existing backdrop.
			app._apply_safe_area(viewport)
			await _settle_layout()
			_same_rect(app.ui.get_global_rect(),viewport,"Removing cutouts restores the full interactive root")
			_same_rect(app.overlay_shade.get_global_rect(),viewport,"Existing backdrop stays full-screen when insets disappear")
	app.queue_free()
	await _settle_layout()
	for property: String in original:
		root.set(property,original[property])
	await _settle_layout()
	_check(root.size==original.size and root.content_scale_size==original.content_scale_size and root.content_scale_mode==original.content_scale_mode and root.content_scale_aspect==original.content_scale_aspect and is_equal_approx(root.content_scale_factor,original.content_scale_factor),"Test restores all original Window size/scaling settings")
	await create_timer(0.15).timeout
	for suffix: String in ["",".tmp",".backup"]:
		if FileAccess.file_exists(path+suffix):
			DirAccess.remove_absolute(path+suffix)
	print("AFTER YOU SAFE AREA: %d checks, %d failures" % [checks,failures])
	quit(1 if failures>0 else 0)

func _test_controls(app: Node, safe: Rect2, physical_size: Vector2i) -> void:
	app._start_practice(0)
	app._close_overlay()
	app.running=false
	for left: bool in [false,true]:
		app.saves.data.settings.left_handed=left
		app._apply_settings()
		await _settle_layout()
		for control: Control in [app.stick,app.interact_button,app.finish_button,app.timer_label,app.progress,app.hint_label]:
			_check(safe.encloses(control.get_global_rect()),"Gameplay target stays inside cutout-safe bounds at %s, left-handed=%s: %s" % [physical_size,left,control.name])
		for button: Button in _buttons(app.hud):
			_check(safe.encloses(button.get_global_rect()),"HUD button is fully inside the safe area: "+button.text)
		_check(not app.stick.get_global_rect().intersects(app.interact_button.get_global_rect()) and not app.stick.get_global_rect().intersects(app.finish_button.get_global_rect()),"Cutout insets do not overlap movement and action targets")
		for control: Control in [app.stick,app.interact_button,app.finish_button]:
			_check(not app.hint_label.get_global_rect().intersects(control.get_global_rect()),"The actual First Light hint clears the full touch targets for either hand and cutout layout")
		_check(app.hint_label.get_line_count()==app.hint_label.get_visible_line_count(),"Every line of the wrapped First Light instruction remains visible")

func _test_menus(app: Node, safe: Rect2, viewport: Rect2) -> void:
	for method: String in ["_show_home","_show_journey","_show_settings","_show_collection"]:
		app.call(method)
		await _settle_layout()
		await _check_menu(app.overlay,safe,method)
		if method == "_show_home":
			# Friend-first Home column: the cream Play with your friend, then Play Solo
			# beside Friends, Replays, and Invite your friends; Settings is a cog at the
			# top right. Full Journey is a separate purchase offer, not navigation.
			var actions: Array[Button] = []
			for label: String in ["Play with your friend", "Play Solo", "Friends", "Replays", "Invite your friends"]:
				var matches := _buttons(app.overlay).filter(func(button: Button) -> bool: return button.text == label)
				_check(matches.size() == 1, "Home shows exactly one visible action: " + label)
				if matches.size() == 1: actions.append(matches[0])
			_check(_buttons(app.overlay).filter(func(button: Button) -> bool: return button.text == "Settings").is_empty(), "Settings is no longer a text button on Home")
			var friends: Button = app.overlay.find_child("HomeFriends", true, false)
			var invite: Button = app.overlay.find_child("HomeInvite", true, false)
			_check(friends != null and friends.is_visible_in_tree() and friends.text == "Friends" and friends.icon != null and friends.accessibility_name == "Friends", "Home keeps the labelled Friends action by its stable name")
			_check(invite != null and invite.is_visible_in_tree() and invite.icon != null and invite.text == "Invite your friends", "Home offers Invite your friends by its stable name")
			var cream := actions.filter(func(button: Button) -> bool: return not button.has_theme_stylebox_override("normal"))
			_check(cream.size() == 1 and actions.size() == 5 and cream[0] == actions[0], "Play with your friend is the only cream primary")
			if actions.size() == 5:
				var rects: Array[Rect2] = []
				for button: Button in actions: rects.append(button.get_global_rect())
				for index in range(1, actions.size()):
					_check(rects[0].end.y <= rects[index].position.y, "Play with your friend leads the Home actions")
				_check(is_equal_approx(rects[1].position.y, rects[2].position.y) and rects[1].end.x <= rects[2].position.x and rects[2].end.y <= rects[3].position.y and rects[3].end.y <= rects[4].position.y, "Play Solo sits beside Friends, then Replays, then Invite your friends")
				_check(absf(rects[1].size.x - rects[2].size.x) <= 1.0 and absf(rects[0].size.x - rects[3].size.x) <= 1.0 and absf(rects[3].size.x - rects[4].size.x) <= 1.0, "Half-width pair and full-width rows share the column")
				var column := Rect2(rects[0].position, Vector2.ZERO)
				for rect: Rect2 in rects: column = column.merge(rect)
				var top: Label = null
				for label: Label in app.overlay.find_children("*", "Label", true, false):
					if label.text == PlayerCopy.MAIN_5DA48958135C: top = label
				_check(top != null, "The Home heading is found for the centring check")
				if top != null:
					var above := top.get_global_rect().position.y - safe.position.y
					var below := safe.end.y - column.end.y
					_check(absf(above - below) <= 12.0, "The Home column is vertically centred in the safe area (%.0f above, %.0f below)" % [above, below])
			var settings: Button = app.overlay.find_child("HomeSettings", true, false)
			var offer: Button = app.overlay.find_child("HomeFullJourney", true, false)
			_check(settings != null and settings.is_visible_in_tree() and settings.text.is_empty() and settings.icon != null and settings.accessibility_name == "Settings" and settings.tooltip_text == "Settings", "Settings is a labelled cog icon")
			if settings != null and offer != null:
				var cog := settings.get_global_rect()
				_check(cog.size.x >= 54 and cog.size.y >= 54 and safe.encloses(cog), "The cog keeps a full target inside the safe area")
				if offer.visible:
					_check(is_equal_approx(cog.position.y, offer.get_global_rect().position.y) and absf(offer.get_global_rect().position.x - cog.end.x - 10.0) <= 0.5, "The cog sits just left of the Full Journey offer")
				else:
					_check(absf(cog.end.x - (safe.end.x - 32.0)) <= 0.5, "Without the offer the cog takes the top-right corner")
				for button: Button in actions:
					_check(not cog.intersects(button.get_global_rect()), "The cog never overlaps the Home column")
			if settings != null: actions.append(settings)
			for index in range(actions.size()):
				var action_name := actions[index].text if not actions[index].text.is_empty() else str(actions[index].name)
				_check(actions[index].size.x >= 54 and actions[index].size.y >= 54, "Home keeps a full-size touch target: " + action_name)
				for other in range(index + 1, actions.size()):
					_check(not actions[index].get_global_rect().intersects(actions[other].get_global_rect()), "Home actions remain distinct without overlap")
		if is_instance_valid(app.overlay_shade):
			_same_rect(app.overlay_shade.get_global_rect(),viewport,method+" backdrop covers the world beyond safe UI edges")
	var first: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/first-light-a.json"))
	app.room_play=false
	app.collection_preview=false
	app.attempt={"a":{},"b":{},"draft":{}}
	app.review_recording=first
	app._show_review()
	await _settle_layout()
	await _check_menu(app.overlay,safe,"Saved-turn review")
	_same_rect(app.overlay_shade.get_global_rect(),viewport,"Review backdrop still covers the entire native content area")

func _check_menu(node: Node, safe: Rect2, context: String) -> void:
	var buttons := _buttons(node)
	_check(not buttons.is_empty(),context+" has reachable actions")
	for button: Button in buttons:
		_check(_visible_inside(button,safe),context+" visible action is inside safe bounds: "+button.text)
	_check_text_and_panels(node,safe,context)
	for button: Button in buttons:
		var parents := _scroll_parents(button)
		if parents.is_empty(): continue
		var positions: Array[Vector2i] = []
		for scroll: ScrollContainer in parents:
			positions.append(Vector2i(scroll.scroll_horizontal,scroll.scroll_vertical))
			_check(safe.encloses(scroll.get_global_rect()),context+" scroll viewport remains inside cutout-safe bounds")
		for scroll: ScrollContainer in parents:
			scroll.ensure_control_visible(button)
			await _settle_layout()
		var rect := button.get_global_rect()
		var reachable := rect.has_area() and safe.encloses(rect)
		for scroll: ScrollContainer in parents:
			reachable = reachable and scroll.get_global_rect().grow(0.5).encloses(rect)
		_check(reachable and _drawn_rect(button).grow(0.5).encloses(rect),context+" action becomes fully reachable inside safe bounds: "+button.text)
		for index in range(parents.size()):
			parents[index].scroll_horizontal = positions[index].x
			parents[index].scroll_vertical = positions[index].y
		await _settle_layout()
	for index in range(buttons.size()):
		for other in range(index):
			_check(not _drawn_rect(buttons[index]).intersects(_drawn_rect(buttons[other])),context+" visible actions remain distinct after restoring scroll")

func _check_text_and_panels(node: Node, safe: Rect2, context: String) -> void:
	if (node is Label or node is PanelContainer) and node.is_visible_in_tree():
		_check(_visible_inside(node,safe),context+" visible text/panel is inside safe bounds: "+node.name)
	for child: Node in node.get_children():
		_check_text_and_panels(child,safe,context)

func _scroll_parents(control: Control) -> Array[ScrollContainer]:
	var result: Array[ScrollContainer] = []
	var ancestor := control.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer: result.append(ancestor)
		ancestor = ancestor.get_parent()
	return result

func _drawn_rect(control: Control) -> Rect2:
	var result := control.get_global_rect()
	var ancestor := control.get_parent()
	while ancestor != null:
		if ancestor is Control and ancestor.clip_contents: result = result.intersection(ancestor.get_global_rect())
		ancestor = ancestor.get_parent()
	return result

func _visible_inside(control: Control, safe: Rect2) -> bool:
	if _scroll_parents(control).is_empty(): return safe.encloses(control.get_global_rect())
	var drawn := _drawn_rect(control)
	return not drawn.has_area() or safe.encloses(drawn)

func _buttons(node: Node) -> Array[Button]:
	var result: Array[Button]=[]
	if node is Button and node.is_visible_in_tree():
		result.append(node)
	for child: Node in node.get_children():
		result.append_array(_buttons(child))
	return result
