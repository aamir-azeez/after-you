extends SceneTree
## Removing one part of a chapter replay from Your replays, on the wide list
## (every phone in landscape) and the narrow one: the trash icon asks first,
## Cancel and Android Back go back where they came from, and the parts left
## still play. Before, the wide icon did nothing, the narrow Cancel did
## nothing, and a part after a removed one would not open.
const Main = preload("res://main.gd")
const Storage = preload("res://services/local_save.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Journey = preload("res://services/relay_journey.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Solo = preload("res://services/solo_replay_collection.gd")
const Index = preload("res://services/solo_replay_index.gd")
const Visibility = preload("res://services/solo_replay_visibility.gd")
const FakeApi = preload("res://tests/fake_rooms_api.gd")
const ReplaysFlow = preload("res://presentation/replays_flow.gd")

## Records a chapter open instead of changing the scene.
class SpyMain extends Main:
	var opened: Array = []
	func _open_chapter_preview(scene: String, replay_context: Dictionary = {}, hard: Dictionary = {}) -> void:
		opened.append({"scene": scene, "context": replay_context.duplicate(true)})

var checks := 0
var failures := 0
var directory := ""

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	directory = "user://solo-replay-remove-part-" + Crypto.new().generate_random_bytes(6).hex_encode()
	DirAccess.make_dir_recursive_absolute(directory)
	var paths := _seed()
	await _wide(paths)
	await _narrow(paths)
	print("SOLO REPLAY REMOVE PART: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _wide(paths: Dictionary) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	root.add_child(viewport)
	var app := await _app(viewport, paths, "wide")
	_check(app.replays_flow._solo_preview_box != null, "The wide list shows the selected attempt's preview")
	var remove := _delete_icon(app.overlay)
	_check(remove != null and not remove.disabled, "The preview offers a Remove icon for the shown part")
	if remove == null:
		viewport.queue_free()
		return
	remove.pressed.emit()
	_check(app.mode == ReplaysFlow.MODE_CONFIRM_DELETE and _has_text(app.overlay, "Remove this replay?"), "Tapping it asks to remove the part: " + str(app.mode))
	var cancel := _button(app.overlay, "Cancel")
	if cancel != null: cancel.pressed.emit()
	_check(app.mode == ReplaysFlow.MODE_COLLECTION and _parts(app) == 2, "Cancel goes back to the list with both parts")
	_delete_icon(app.overlay).pressed.emit()
	app._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	_check(app.mode == ReplaysFlow.MODE_COLLECTION and _parts(app) == 2, "Android Back cancels too")
	# Remove part 1; part 2 is left and still plays from the chapter's start.
	_delete_icon(app.overlay).pressed.emit()
	var confirm := _button(app.overlay, "Remove")
	if confirm != null: confirm.pressed.emit()
	_check(app.mode == ReplaysFlow.MODE_COLLECTION and _parts(app) == 1, "Remove leaves one part listed: %d" % _parts(app))
	var watch := _button(app.overlay, "Watch replay")
	_check(watch != null and not watch.disabled, "The part left can be watched")
	if watch != null:
		watch.pressed.emit()
		await _frames(3)
	var context: Dictionary = app.opened[-1].context if not app.opened.is_empty() else {}
	_check(int(context.get("selected_stage_index", -1)) == 1 and context.get("accepted_pairs", []).size() == 2, "It opens part 2 with the removed part 1 still before it: " + str(context.get("selected_stage_index", "nothing opened")))
	viewport.queue_free()
	await process_frame

func _narrow(paths: Dictionary) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(900, 600)
	root.add_child(viewport)
	var app := await _app(viewport, paths, "narrow")
	var row: Button = _chapter_rows(app)[0] if not _chapter_rows(app).is_empty() else null
	_check(row != null, "The narrow list shows the attempt")
	if row == null:
		viewport.queue_free()
		return
	row.pressed.emit()
	_check(app.mode == ReplaysFlow.MODE_SOLO_REPLAY_ATTEMPT, "A row opens its parts")
	_delete_icon(app.overlay).pressed.emit()
	_check(app.mode == ReplaysFlow.MODE_CONFIRM_DELETE, "A part's Remove icon asks first")
	var cancel := _button(app.overlay, "Cancel")
	if cancel != null: cancel.pressed.emit()
	_check(app.mode == ReplaysFlow.MODE_SOLO_REPLAY_ATTEMPT, "Cancel goes back to the parts: " + str(app.mode))
	_delete_icon(app.overlay).pressed.emit()
	app._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	_check(app.mode == ReplaysFlow.MODE_SOLO_REPLAY_ATTEMPT, "Android Back goes back to the parts: " + str(app.mode))
	viewport.queue_free()
	await process_frame

func _app(viewport: SubViewport, paths: Dictionary, name: String) -> Node:
	var app := SpyMain.new()
	app.saves = Storage.new(directory + "/save-%s.json" % name)
	app.saves.data.settings.sound = false
	app.saves.data.settings.haptics = false
	viewport.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	app.world.set_process(false)
	app.api.queue_free()
	var api := FakeApi.new()
	app.add_child(api)
	app.api = api
	app.application_backgrounded = false
	app.replays_flow.solo_replay_index = Index.new(directory + "/index-%s.json" % name)
	app.replays_flow.solo_replay_visibility = Visibility.new(directory + "/visibility-%s.json" % name)
	app.replays_flow.solo_replays = Solo.new(paths, "")
	app.replays_flow._solo_collection_started = false
	await process_frame
	app.replays_flow.show_collection()
	var guard := 0
	while (app.replays_flow.solo_replays.scan_pending() or app.replays_flow._solo_collection_dirty) and guard < 6000:
		app.replays_flow._solo_collection_redraw_at = 0
		app.replays_flow.service_solo_collection()
		guard += 1
		await process_frame
	app.replays_flow.show_collection()
	await _frames(2)
	return app

func _parts(app: Node) -> int:
	return int(app.replays_flow._selected_solo_attempt.get("parts", 0))

## One completed two-stage Relay journal; every other chapter is missing.
func _seed() -> Dictionary:
	var paths := {"sleeping-lighthouse@1": directory + "/lighthouse.json"}
	for chapter: String in Registry.keys(): paths[chapter] = directory + "/" + chapter.validate_filename() + ".json"
	var level := Registry.definition(Registry.RELAY)
	var validator := Journey.new(str(paths[Registry.RELAY]), null, Registry.RELAY)
	var complete := {}
	for rules: Variant in Registry.supported_rules(Registry.RELAY):
		var pairs: Array = []
		for stage: Dictionary in level.stages:
			pairs.append({"a": _fixture("v2/" + str(stage.id) + "-a"), "b": _fixture("v2/" + str(stage.id) + "-b")})
		var state := {"schema_version": level.schema_version, "simulation_version": int(rules), "level_id": level.id, "level_version": level.version, "definition_hash": Canonical.digest(level), "pairs": pairs, "a": {}, "draft": {}}
		if validator._validate_state(state).get("valid", false):
			complete = state
			break
	_check(complete.get("pairs", []).size() == 2, "Published fixtures form a complete two-stage Relay journal")
	var envelope := Storage.defaults()
	envelope.generation = 1
	envelope["relay"] = complete
	var file := FileAccess.open(str(paths[Registry.RELAY]), FileAccess.WRITE)
	file.store_string(JSON.stringify(envelope))
	file.close()
	return paths

func _chapter_rows(app: Node) -> Array:
	return _buttons(app.overlay).filter(func(button: Button) -> bool: return button.has_meta("replay_row") and " · Attempt " in button.text)

func _delete_icon(node: Node) -> Button:
	for button: Button in _buttons(node):
		if button.tooltip_text.begins_with("Delete replay:") and button.is_visible_in_tree(): return button
	return null

func _buttons(node: Node) -> Array:
	var result: Array = []
	for child: Node in node.find_children("*", "Button", true, false): result.append(child)
	return result

func _button(node: Node, text: String) -> Button:
	for button: Button in _buttons(node):
		if button.text == text and button.is_visible_in_tree(): return button
	return null

func _has_text(node: Node, fragment: String) -> bool:
	if node is Label and fragment in node.text and node.is_visible_in_tree(): return true
	for child: Node in node.get_children():
		if _has_text(child, fragment): return true
	return false

func _frames(count: int) -> void:
	for frame in range(count): await process_frame

func _fixture(name: String) -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/" + name + ".json"))
	return value if value is Dictionary else {}

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + message)
		print("FAIL: " + message)
