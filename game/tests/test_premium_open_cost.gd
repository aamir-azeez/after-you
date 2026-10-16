extends SceneTree
## What one paid chapter open costs on a store-gated phone, from the tap on
## Home until the chapter is ready: secure-store calls, opening cards and
## chapter control layers. The secure store is a stand-in for the phone's
## native plugin, so every read Main and the chapter make is counted where it
## leaves the game.
const Main = preload("res://main.gd")
const Card = preload("res://presentation/chapter_loading_card.gd")
const Controls = preload("res://presentation/chapter_controls.gd")
const ChapterAccess = preload("res://services/chapter_access.gd")
const TesterAccess = preload("res://services/tester_access.gd")
const NativeBridge = preload("res://services/native_bridge.gd")
const PlatformSupport = preload("res://services/platform_support.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Storage = preload("res://services/local_save.gd")
const Proofs = preload("res://services/journey_proofs.gd")
const AccessTests = preload("res://tests/test_chapter_access.gd")
const BASE := "https://test.example.invalid"
const OWNER := "TTTTTTTTTTTTTTTTTTTTTT"
const TOKEN := "DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD"
const CHAPTER := Registry.ROLLING_HOME
const SCENE := "res://rolling_home.tscn"
## The pinned cost of one open behind Main's opening card.
const OPEN_COST := {"main_reads": 0, "chapter_reads": 0, "cards": 1, "controls": 1}
## One full read of the saved receipt: the identity twice around the receipt.
const FULL_READ := 5

var checks := 0
var failures := 0
var native: FakeNative
var counts := {}
## The store the chapter's admission asks, when a test answers it.
var store: Node
var paths: Array[String] = []

## The native secure store: answers on the next idle moment, as the plugin does.
class FakeNative extends Object:
	signal secure_result(request_id: String, operation: String, payload_json: String)
	signal secure_error(request_id: String, operation: String, code: String)
	var values: Dictionary = {}
	var calls: Array[String] = []
	## Who is calling: "main" until the chapter scene enters the tree.
	var caller := "main"
	func secure_get(name: String, request_id: String) -> void:
		calls.append(caller + ": get " + name)
		secure_result.emit.call_deferred(request_id, "get", JSON.stringify({"found": values.has(name), "value": values.get(name)}))
	func secure_put(name: String, value: String, request_id: String) -> void:
		calls.append(caller + ": put " + name)
		values[name] = value
		secure_result.emit.call_deferred(request_id, "put", JSON.stringify({"stored": true}))
	func secure_remove(name: String, request_id: String) -> void:
		calls.append(caller + ": remove " + name)
		values.erase(name)
		secure_result.emit.call_deferred(request_id, "remove", JSON.stringify({"removed": true}))

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	Card.costs_path = "user://chapter-open-times-cost-%s.json" % Crypto.new().generate_random_bytes(4).hex_encode()
	var proofs_before := Proofs.directory
	Proofs.directory = "user://journey-proofs-cost-%s" % Crypto.new().generate_random_bytes(4).hex_encode()
	native = FakeNative.new()
	Engine.register_singleton(NativeBridge.ANDROID, native)
	native.values["player_identity"] = JSON.stringify({"player_id": OWNER, "device_token": TOKEN})
	node_added.connect(_counted)
	await _tester_open()
	await _store_unavailable()
	await _buyer_open()
	await _cover_leaves()
	await _hand_over_rules()
	node_added.disconnect(_counted)
	PlatformSupport.override_platform = ""
	Engine.unregister_singleton(NativeBridge.ANDROID)
	native.free()
	_remove_saves()
	if DirAccess.dir_exists_absolute(Proofs.directory):
		for name: String in DirAccess.get_files_at(Proofs.directory): DirAccess.remove_absolute(ProjectSettings.globalize_path(Proofs.directory.path_join(name)))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Proofs.directory))
	Proofs.directory = proofs_before
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Card.costs_path))
	await create_timer(0.15).timeout
	print("PREMIUM OPEN COST: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## A tester whose grant Main read at startup taps a paid chapter on Home.
func _tester_open() -> void:
	_check(Registry.solo_scene(CHAPTER) == SCENE and Registry.descriptor(CHAPTER).premium, "Fixture: the chapter is a paid one opened in its own scene")
	native.values[TesterAccess._scope(BASE, OWNER, TOKEN)] = _envelope()
	var app := await _home()
	if app == null: return
	_check(app._tester_active(), "Fixture: Main read the saved tester grant at startup")
	var opened := await _measure(func(): app._open_solo_chapter(CHAPTER))
	var screen: Node = current_scene
	_check(opened.ready and screen.admission.is_granted() and screen.admission.reason == "tester", "The tester's chapter opens to its ready card through tester admission")
	_check(_same(opened, OPEN_COST), "One tester open costs %s (pinned %s)" % [_cost(opened), OPEN_COST])
	print("TESTER OPEN: %s, %d frames" % [_cost(opened), opened.frames])
	await _leave_chapter()

## A player without a tester grant: Main's read found none, so the chapter goes
## straight to the store check (a GitHub build's store answers "unavailable").
func _store_unavailable() -> void:
	native.values.erase(TesterAccess._scope(BASE, OWNER, TOKEN))
	var app := await _home()
	if app == null: return
	_check(not app._tester_active() and app.tester_access.cache_loaded_for(BASE, OWNER, TOKEN), "Fixture: Main read that there is no tester grant")
	var opened := await _measure(func(): app._open_chapter_preview(SCENE), func(screen: Node): return screen.mode == "access" and screen.admission.state == "hold")
	var screen: Node = current_scene
	_check(not screen._prepared and screen.admission.reason == "provider_unavailable", "Without a grant the chapter holds on the store check, never admitted")
	_check(_same(opened, OPEN_COST), "One open the store cannot confirm costs %s (pinned %s)" % [_cost(opened), OPEN_COST])
	print("STORE UNAVAILABLE: %s, %d frames" % [_cost(opened), opened.frames])
	native.calls.clear()
	screen.admission.check_access(true)
	var deadline := Time.get_ticks_msec() + 5000
	while screen.admission.state == "checking" and Time.get_ticks_msec() < deadline: await process_frame
	_check(native.calls.size() == FULL_READ and screen.admission.state == "hold", "Check again reads the saved receipt again in full (%d calls)" % native.calls.size())
	await _leave_chapter()

## A buyer: the store answers "entitled" a few frames after the chapter asks,
## while Main's opening card still covers the chapter.
func _buyer_open() -> void:
	var app := await _home()
	if app == null: return
	store = _store()
	var asked := [-1]
	var answer := func(frame: int):
		if asked[0] < 0 and store.requests.size() == 1: asked[0] = frame
		elif asked[0] >= 0 and frame == asked[0] + 3: store.answer(store.requests[0], true)
	var opened := await _measure(func(): app._open_chapter_preview(SCENE), Callable(), answer)
	var screen: Node = current_scene
	_check(opened.ready and screen.admission.reason == "purchase" and store.requests.size() == 1, "The buyer's chapter opens to its ready card on the store's answer")
	_check(_same(opened, OPEN_COST), "One buyer open costs %s (pinned %s)" % [_cost(opened), OPEN_COST])
	print("BUYER OPEN: %s, %d frames" % [_cost(opened), opened.frames])
	store = null
	await _leave_chapter()

## When Main's card goes while the store check is still out, the access card
## shows the check at once; a grant then opens the chapter behind its own card.
func _cover_leaves() -> void:
	var app := await _home()
	if app == null: return
	store = _store()
	Card._record(SCENE, Card.SHOW_AFTER_USEC)
	PlatformSupport.override_platform = PlatformSupport.ANDROID
	counts = {"cards": 0, "controls": 0}
	app._open_chapter_preview(SCENE)
	var deadline := Time.get_ticks_msec() + 20000
	while (current_scene == null or current_scene.scene_file_path != SCENE or store.requests.is_empty()) and Time.get_ticks_msec() < deadline: await process_frame
	var screen: Node = current_scene
	var card: Node = root.get_node_or_null("ChapterLoadingCard")
	_check(card != null and screen.building() and not is_instance_valid(screen.controls), "Under Main's card the store check draws nothing and keeps the card up")
	if card != null: card.cancel()
	await process_frame
	_check(screen.mode == "access" and is_instance_valid(screen.controls) and screen.admission.state == "checking", "Once the card has gone the access card shows the check")
	store.answer(store.requests[0], true)
	while not (screen._prepared and screen.mode == "ready" and root.get_node_or_null("ChapterLoadingCard") == null) and Time.get_ticks_msec() < deadline: await process_frame
	_check(screen._prepared and screen.mode == "ready" and counts.cards == 2, "The grant then opens the chapter behind its own card")
	store = null
	await _leave_chapter()

## Main's read reaches only the scene it opened, at the same API, for the
## identity that read it.
func _hand_over_rules() -> void:
	var scene := SCENE
	ChapterAccess.hand_over(scene, BASE, true)
	_check(ChapterAccess._take_hand_over("res://house.tscn", BASE).is_empty() and ChapterAccess._take_hand_over(scene, BASE).is_empty(), "Another scene's claim drops the hand-off unused")
	ChapterAccess.hand_over(scene, "https://other.example.invalid", true)
	_check(ChapterAccess._take_hand_over(scene, BASE).is_empty(), "A read for another API is never used")
	ChapterAccess.hand_over(scene, BASE, true)
	_check(ChapterAccess._take_hand_over(scene, BASE).get("granted") == true and ChapterAccess._take_hand_over(scene, BASE).is_empty(), "The hand-off is used once")
	ChapterAccess.hand_over(scene, BASE, true)
	await process_frame
	await process_frame
	_check(ChapterAccess._take_hand_over(scene, BASE).is_empty(), "A hand-off no scene change took in time is never used")
	native.values[TesterAccess._scope(BASE, OWNER, TOKEN)] = _envelope()
	var app := await _home()
	if app == null: return
	app._hand_over_tester_check(scene)
	_check(ChapterAccess._take_hand_over(scene, BASE).get("granted") == true, "Main hands over its read for the identity in use")
	app.tester_access.forget_cache_check()
	app.tester_access.invalidate()
	app._hand_over_tester_check(scene)
	_check(ChapterAccess._take_hand_over(scene, BASE).is_empty(), "After an identity change Main hands over nothing; the scene reads the receipt itself")
	root.remove_child(app)
	app.queue_free()
	current_scene = null
	for _frame in range(4): await process_frame

## Home with a saved identity on a phone, its startup receipt read finished.
func _home() -> Node:
	PlatformSupport.override_platform = ""
	var app: Node = Main.new()
	var path := "user://test-premium-cost-%d.json" % Time.get_ticks_usec()
	paths.append(path)
	app.saves = Storage.new(path)
	app.tester_access_factory = func(): return TesterAccess.new()
	root.add_child(app)
	current_scene = app
	app.api.base_url = BASE
	var deadline := Time.get_ticks_msec() + 5000
	while (app._tester_context().is_empty() or app.tester_access.cache_checked_context != app._tester_context()) and Time.get_ticks_msec() < deadline:
		await process_frame
	if app.tester_access.cache_checked_context.is_empty():
		_check(false, "Fixture: Home finished its startup receipt read")
		return null
	await process_frame
	return app

## Runs one open from its tap and counts its costs until the chapter is
## settled (ready, or `settled` says so) and the opening card has gone.
## `each_frame`, when given, runs every frame with the frame's number.
func _measure(tap: Callable, settled: Callable = Callable(), each_frame: Callable = Callable()) -> Dictionary:
	# The card shows, as on a chapter's first open on a phone.
	Card._record(SCENE, Card.SHOW_AFTER_USEC)
	PlatformSupport.override_platform = PlatformSupport.ANDROID
	counts = {"cards": 0, "controls": 0}
	native.calls.clear()
	native.caller = "main"
	var main_reads := 0
	var frames := 0
	tap.call()
	var deadline := Time.get_ticks_msec() + 20000
	var done := false
	while Time.get_ticks_msec() < deadline:
		await process_frame
		frames += 1
		if each_frame.is_valid(): each_frame.call(frames)
		var screen: Node = current_scene
		if native.caller != "chapter" or not is_instance_valid(screen) or root.get_node_or_null("ChapterLoadingCard") != null: continue
		if settled.is_valid(): done = settled.call(screen)
		else: done = screen._prepared and screen.mode == "ready" and not screen.building()
		if done: break
	for call: String in native.calls:
		if call.begins_with("main:"): main_reads += 1
	return {"main_reads": main_reads, "chapter_reads": native.calls.size() - main_reads, "cards": counts.cards, "controls": counts.controls, "frames": frames, "ready": done}

func _counted(node: Node) -> void:
	if node.get_script() == Card: counts.cards = int(counts.get("cards", 0)) + 1
	elif node.get_script() == Controls: counts.controls = int(counts.get("controls", 0)) + 1
	# The chapter reads the API address from the build's config, which a test copy leaves empty.
	elif node.get_script() == ChapterAccess:
		node.api_base_url = BASE
		if store != null: node.purchase_service_factory = func(): return store
	if node.scene_file_path == SCENE: native.caller = "chapter"

func _leave_chapter() -> void:
	PlatformSupport.override_platform = ""
	var screen: Node = current_scene
	if is_instance_valid(screen):
		root.remove_child(screen)
		screen.queue_free()
	current_scene = null
	for _frame in range(4): await process_frame

func _store() -> Node:
	var value: Node = AccessTests.Store.new()
	value._configuration = {"purchase_mode": "google_play", "entitlement_id": "full_journey_play"}
	return value

func _envelope() -> String:
	var receipt := {"schema_version": 1, "granted": true, "access_source": "tester_grant", "entitlement": "full_journey", "player_id": OWNER, "granted_at": "2026-01-01T00:00:00.000Z"}
	return JSON.stringify({"schema_version": 1, "authority": BASE, "player_id": OWNER, "credential_hash": TOKEN.sha256_text(), "receipt": receipt})

func _remove_saves() -> void:
	var saved: Array[String] = paths.duplicate()
	saved.append(str(Registry.descriptor(CHAPTER).get("local_path", "")))
	for path: String in saved:
		if path.is_empty(): continue
		for suffix: String in ["", ".tmp", ".backup"]:
			if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))

static func _same(measured: Dictionary, pinned: Dictionary) -> bool:
	for key: String in pinned:
		if measured.get(key) != pinned[key]: return false
	return true

static func _cost(measured: Dictionary) -> String:
	return "%d Main reads, %d chapter reads, %d cards, %d control layers" % [measured.main_reads, measured.chapter_reads, measured.cards, measured.controls]

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
		print("FAIL: " + message)
