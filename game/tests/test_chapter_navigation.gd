extends "res://tests/test_home_scene_navigation.gd"
## Exercise the real menu buttons and packed scene changes in an isolated,
## offline test profile. Store responses are synthetic; no purchase is made.
const Registry = preload("res://services/chapter_registry.gd")
const Session = preload("res://services/relay_online_session.gd")

func _run() -> void:
	root.size = Vector2i(1280,720)
	for key: String in Registry.keys():
		var scene := Registry.solo_scene(key)
		_check(not scene.is_empty() and ResourceLoader.exists(scene),"Every bundled chapter has a loadable solo scene: " + key)
		if not Registry.is_cooperative(key): continue
		await _navigate(key,false)
		await _navigate(key,true)
	if is_instance_valid(current_scene):
		current_scene.queue_free()
		await process_frame
		await process_frame
	await create_timer(0.2).timeout
	print("CHAPTER NAVIGATION: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _navigate(key: String, practice: bool) -> void:
	change_scene_to_file("res://main.tscn")
	if not await _wait_for_scene("res://main.tscn"): return
	var app: Node = current_scene
	_check(not app.api.configured(),"Navigation test has no live service configuration")
	if app.api.configured(): return
	app.set_process(false)
	app.set_physics_process(false)
	app.identity_loading = false
	app.identity_busy = false
	app.identity_restart_required = false
	app.config.purchase_mode = "google_play"
	app.config.entitlement_id = "full_journey_play"
	app.purchases._configuration = {"purchase_mode":"google_play","entitlement_id":"full_journey_play"}
	app.purchases.customer_info = {}
	var item := Registry.descriptor(key)
	var solo_label := str(item.title) + " · Solo" + (" · Full Journey" if item.premium else "")
	app._show_journey()
	var solo := _chapter_solo(app,key)
	_check(solo != null,"Journey exposes the authored chapter: " + key)
	if solo == null: return
	_check(_button(solo.get_parent(),"Together") == null,"Play Solo offers no Together button: " + key)
	# Playing together starts from Play with your friend; hosting there opens
	# the same chapter lobby through _show_relay_rooms.
	app._show_relay_rooms(key)
	_check(app.selected_online_chapter == key,"Hosting selects this chapter before checking connection: " + key)
	if practice:
		app.relay_session = Session.new(app.api,app._relay_identity)
		app._draw_relay_lobby()
		solo = _button(app.overlay,"Practice this chapter solo")
		_check(solo != null,"The real chapter lobby exposes Practice: " + key)
		if solo == null: return
	var label := "Practice this chapter solo" if practice else solo_label
	solo.pressed.emit()
	if item.premium:
		await process_frame
		_check(current_scene == app and app.mode == "paywall","A nonbuyer reaches Full Journey from " + label)
		# A configured synthetic Play identity permits the real parent route.
		app.api.player_id = "HHHHHHHHHHHHHHHHHHHHHH"
		app.api.device_token = "DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD"
		app.store_owner = app.api.player_id
		app.store_configured = true
		app.purchases.customer_info = {"schema_version":1,"mode":"google_play","entitlements":{"full_journey_play":{"active":true,"store":"PLAY_STORE","product_id":"after_you_full_journey"}}}
		if practice: app._draw_relay_lobby()
		else: app._show_journey()
		(_button(app.overlay,label) if practice else _chapter_solo(app,key)).pressed.emit()
	app = null
	if not await _wait_for_scene(Registry.solo_scene(key)): return
	var chapter: Node = current_scene
	_check(chapter.chapter_key == key and chapter.mode == "ready" and chapter.world.get_script() == Registry.world_script(key),"The actual scene opens the correct chapter and presentation: " + key)
	chapter._leave()
	chapter = null
	_check(await _wait_for_scene("res://main.tscn"),"Back returns to the real home scene: " + key)

func _chapter_solo(app: Node, key: String) -> Button:
	## The chooser shows each chapter as one card: its title and a Free to play
	## or Full Journey line. The whole card is its only tap target and opens the
	## chapter solo. Return that target.
	var item := Registry.descriptor(key)
	for card: Node in app.overlay.find_children("*","PanelContainer",true,false):
		if card.get_meta("chapter_key","") != key: continue
		var title: Label = card.find_child("LevelTitle",true,false)
		var access: Label = card.find_child("ChapterAccess",true,false)
		if title == null or title.text != str(item.title) or access == null: return null
		if access.text != ("Full Journey" if item.premium else "Free to play"): return null
		var targets: Array[Node] = card.find_children("*","Button",true,false)
		if targets.size() != 1 or targets[0].get_parent() != card or targets[0].get_meta("completion_variant","") != "solo": return null
		return targets[0]
	return null

func _button(node: Node, label: String) -> Button:
	if node is Button and node.text == label: return node
	for child: Node in node.get_children():
		var found := _button(child,label)
		if found != null: return found
	return null
