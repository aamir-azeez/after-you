extends SceneTree
## Hosting follows what the server can create: the newest offered version of a
## chapter id, else the previous one, else "unavailable online". Solo always
## plays the offered version.
const Registry = preload("res://services/chapter_registry.gd")
const Main = preload("res://main.gd")
const Save = preload("res://services/local_save.gd")
const Session = preload("res://services/relay_online_session.gd")
const Fakes = preload("res://tests/test_relay_online.gd")
const V1 := "long-way-home@1"
const V2 := "long-way-home@2"
var checks := 0
var failures := 0
var paths: Array[String] = []

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	_rule()
	await _chooser()
	for path: String in paths:
		for suffix: String in ["", ".tmp", ".backup"]:
			if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	print("LONG WAY HOME HOSTING: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _rule() -> void:
	var none := func(_key: String) -> bool: return false
	var only_v1 := func(key: String) -> bool: return key == V1
	var both := func(key: String) -> bool: return key in [V1, V2]
	var only_v2 := func(key: String) -> bool: return key == V2
	_check(Registry.hosting_key(V2, none) == V2, "Neither listed: hosting stays on @2 (shown as unavailable)")
	_check(Registry.hosting_key(V2, only_v1) == V1, "Only @1 listed: hosting falls back to @1")
	_check(Registry.hosting_key(V2, both) == V2 and Registry.hosting_key(V2, only_v2) == V2, "@2 listed: hosting uses @2")
	_check(Registry.hosting_key(V1, both) == V1, "Never hosts a version newer than asked for")
	_check(Registry.hosting_key(Registry.CONSERVATORY, both) == Registry.CONSERVATORY and Registry.hosting_key(Registry.CONSERVATORY, none) == Registry.CONSERVATORY, "Other chapters are unaffected")
	_check(V1 not in Registry.offered_keys() and V2 in Registry.offered_keys(), "Solo pickers still offer only @2")

func _caps(listed: Array) -> Dictionary:
	var chapters: Array = []
	for key: String in Registry.keys():
		if key.begins_with("long-way-home@") and key not in listed: continue
		var value := Registry.descriptor(key)
		chapters.append({"level_id": value.level_id, "level_version": value.level_version, "definition_hash": value.definition_hash,
			"premium": value.premium, "recording_version": value.recording_version, "simulation_version": value.simulation_version})
	return {"api_version": 2, "recording_version": 2, "simulation_version": 2, "mutations_enabled": true,
		"validation": "structural_client_replay_required", "chapters": chapters}

func _chooser() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	root.add_child(viewport)
	var app := Main.new()
	var path := "user://lwh-hosting-%s.json" % Crypto.new().generate_random_bytes(8).hex_encode()
	paths.append(path)
	app.saves = Save.new(path)
	app.saves.data.settings.sound = false
	viewport.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	var api := Fakes.FakeApi.new()
	app.add_child(api)
	app.api = api
	var identity := Fakes.Identity.new()
	app.relay_session = Session.new(api, identity.get_value, Fakes.MemoryStore.new())
	for state: Array in [[[], V2, false], [[V1], V1, true], [[V1, V2], V2, true], [[V2], V2, true]]:
		var listed: Array = state[0]
		api.responder = func(request: Dictionary) -> Dictionary:
			return {"ok": true, "data": _caps(listed) if request.path == "/v2/capabilities" else {"rooms": []}}
		_check(await app.relay_session.load_lobby(), "Lobby loads with Long Way Home listed as %s" % str(listed))
		app.selected_online_chapter = V2
		app._draw_relay_lobby()
		await process_frame
		var choices: OptionButton = app.overlay.find_children("*", "OptionButton", true, false)[0]
		var found: Array = []
		for index in range(choices.item_count):
			if str(choices.get_item_metadata(index)).begins_with("long-way-home@"): found.append(index)
		_check(found.size() == 1, "Exactly one Long Way Home choice: " + str(listed))
		if found.size() != 1: continue
		var text := choices.get_item_text(found[0])
		_check(choices.get_item_metadata(found[0]) == state[1] and text.begins_with("Long Way Home") and text.contains("unavailable online") != state[2], "The choice hosts %s and is %s: %s" % [state[1], "available" if state[2] else "unavailable", str(listed)])
		_check(app.selected_online_chapter == state[1] and choices.selected == found[0], "The selected chapter follows the server: " + str(listed))
		var create: Button = null
		for button: Button in app.overlay.find_children("*", "Button", true, false):
			if button.text == "Create this chapter": create = button
		_check(create != null and create.disabled != state[2], "Create follows the hosted version: " + str(listed))
	api.responder = Callable()
	app.relay_session.invalidate_identity()
	app.relay_session = null
	viewport.queue_free()
	await process_frame

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
