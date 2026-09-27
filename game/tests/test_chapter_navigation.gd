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
	app.purchases._configuration = {"purchase_mode":"test_store","entitlement_id":"full_journey"}
	app.purchases.customer_info = {}
	var item := Registry.descriptor(key)
	var solo_label := str(item.title) + " · Solo" + (" · Full Journey" if item.premium else "")
	app._show_journey()
	var solo := _button(app.overlay,solo_label)
	_check(solo != null,"Journey exposes the authored chapter: " + key)
	if solo == null: return
	var together := _button(solo.get_parent(),"Together")
	_check(together != null,"Journey pairs the chapter with its Together button: " + key)
	if together != null:
		together.pressed.emit()
		_check(app.selected_online_chapter == key,"Together selects this chapter before checking connection: " + key)
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
		# A configured synthetic test-store identity permits the real parent route.
		app.api.player_id = "HHHHHHHHHHHHHHHHHHHHHH"
		app.api.device_token = "DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD"
		app.store_owner = app.api.player_id
		app.store_configured = true
		app.purchases.customer_info = {"schema_version":1,"entitlements":{"full_journey":{"active":true}}}
		if practice: app._draw_relay_lobby()
		else: app._show_journey()
		_button(app.overlay,label).pressed.emit()
	app = null
	if not await _wait_for_scene(Registry.solo_scene(key)): return
	var chapter: Node = current_scene
	_check(chapter.chapter_key == key and chapter.mode == "ready" and chapter.world.get_script() == Registry.world_script(key),"The actual scene opens the correct chapter and presentation: " + key)
	chapter._leave()
	chapter = null
	_check(await _wait_for_scene("res://main.tscn"),"Back returns to the real home scene: " + key)

func _button(node: Node, label: String) -> Button:
	if node is Button and node.text == label: return node
	for child: Node in node.get_children():
		var found := _button(child,label)
		if found != null: return found
	return null
