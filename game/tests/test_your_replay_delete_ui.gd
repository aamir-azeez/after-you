extends "res://tests/test_shared_replays.gd"

class FailingSave extends Save:
	var reject_write := false
	func flush() -> bool:
		if reject_write:
			last_error="Injected replay save failure."
			return false
		return super.flush()

func _run() -> void:
	var saved := {"a":_fixture("","first-light-a"),"b":_fixture("","first-light-b"),"draft":{}}
	_storage_cases(saved)
	var viewport := SubViewport.new()
	viewport.size=Vector2i(960,540)
	root.add_child(viewport)
	var storage := FailingSave.new("user://your-replay-delete-ui-%d.json" % Time.get_ticks_usec())
	storage.data.settings.sound=false
	storage.data.settings.haptics=false
	_check(storage.save_attempt("first-light",saved,true),"Seed a real completed solo replay")
	var app := Main.new()
	app.saves=storage
	viewport.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	app.api.queue_free()
	var api := Api.new()
	app.add_child(api)
	app.api=api
	var live_attempt: Dictionary=app.attempt.duplicate(true)
	var live_level: Dictionary=app.current_level.duplicate(true)
	app._show_collection()
	await process_frame
	await process_frame
	var remove := _delete_icon(app.overlay)
	_check(remove != null and remove.text.is_empty() and remove.icon != null and remove.custom_minimum_size.x >= 48 and remove.custom_minimum_size.y >= 48,"Your replays exposes an icon-only Delete action with a 48px target")
	if remove == null:
		viewport.queue_free()
		quit(1)
		return
	_check(remove.accessibility_name == remove.tooltip_text and remove.tooltip_text.begins_with("Delete replay:"),"The icon has an accessible name and descriptive tooltip")
	_check(viewport.get_visible_rect().encloses(remove.get_global_rect()),"Delete fits the narrow viewport")
	var before := Canonical.digest(storage.data)
	remove.pressed.emit()
	_check(app.mode == "confirm_delete_replay" and _has_text(app.overlay,"Remove this replay from Your replays on this phone? Progress, unfinished attempts and keepsakes will stay."),"Confirmation explains local collection deletion and preserved progress")
	_button(app.overlay,"Cancel").pressed.emit()
	_check(app.mode == "collection" and Canonical.digest(storage.data) == before,"Cancel keeps the completed replay")
	_delete_icon(app.overlay).pressed.emit()
	app._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	_check(app.mode == "collection" and Canonical.digest(storage.data) == before,"Android Back cancels solo deletion")
	_delete_icon(app.overlay).pressed.emit()
	var stale := _button(app.overlay,"Delete")
	app._show_collection()
	stale.pressed.emit()
	_check(Canonical.digest(storage.data) == before,"A retired confirmation cannot delete after navigation")
	_delete_icon(app.overlay).pressed.emit()
	storage.reject_write=true
	_button(app.overlay,"Delete").pressed.emit()
	_check(app.mode == "collection" and _delete_icon(app.overlay) != null and Canonical.digest(storage.data) == before and _has_text(app.overlay,storage.last_error),"A persistence failure keeps the replay visible and reports the failure")
	storage.reject_write=false
	_delete_icon(app.overlay).pressed.emit()
	var confirm := _button(app.overlay,"Delete")
	confirm.pressed.emit()
	var after := Canonical.digest(storage.data)
	confirm.pressed.emit()
	_check(app.mode == "collection" and _delete_icon(app.overlay) == null and _has_text(app.overlay,"Replay deleted"),"Successful deletion returns to an empty collection")
	_check(Canonical.digest(storage.data) == after and Canonical.same(app.attempt,live_attempt) and Canonical.same(app.current_level,live_level),"Double activation changes neither the saved result nor the current gameplay selection")
	_check(api.calls.is_empty(),"Solo replay deletion sends no network request")
	var cold := Save.new(storage.path)
	cold.load_data()
	app.saves=cold
	app._show_collection()
	_check(_delete_icon(app.overlay) == null and Canonical.same(cold.attempt("first-light"),saved),"Cold reopening keeps the replay hidden while retaining its completed gameplay state")
	viewport.queue_free()
	await process_frame
	print("YOUR REPLAY DELETE UI: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _storage_cases(saved: Dictionary) -> void:
	var storage := Save.new("user://your-replay-delete-storage-%d.json" % Time.get_ticks_usec())
	_check(storage.save_attempt("first-light",saved,true) and storage.save_attempt("another-island",saved,true),"Independent solo replay copies are saved")
	var draft := {"a":saved.a.duplicate(true),"b":{},"draft":{"role":"b","duration_ticks":12,"actions":[]}}
	_check(storage.save_attempt("first-light",draft),"A new unfinished attempt can coexist with the earlier replay")
	_check(storage.update_values({"attempt_archive":[{"level_id":"first-light","attempt":saved}],"pending_turn":{"id":"retained"},"room":{"room_id":"retained"},"home_keepsakes":{"earned":{"earlier/first-light":{"solo":true}}}}),"Unrelated progress and recovery namespaces are retained")
	var before := storage.data.duplicate(true)
	_check(storage.remove_replay("first-light",saved),"Deleting the old replay succeeds while a newer draft exists")
	var expected := before.duplicate(true)
	expected.replays.erase("first-light")
	expected.generation=storage.data.generation
	expected.removed_replays=storage.data.removed_replays.duplicate(true)
	_check(Canonical.same(storage.data,expected) and Canonical.same(storage.attempt("first-light"),draft),"Only the selected replay copy and removal marker change; draft, other level, completion, room, archive, pending turn and keepsake data remain")
	var cold := Save.new(storage.path)
	cold.load_data()
	_check(cold.replay("first-light").b.is_empty() and not cold.replay("another-island").b.is_empty(),"Cold restore preserves removal and unrelated replay visibility")
	_check(cold.save_attempt("first-light",saved,true) and cold.replay("first-light").b.is_empty(),"Recaching the identical retained gameplay pair cannot restore a deleted replay")
	# The selector is a storage boundary, not a native replay verifier. Change
	# fixture metadata only to model a distinct saved recording at this boundary.
	var distinct := saved.duplicate(true)
	distinct.b["saved_version_fixture"]=2
	_check(cold.save_attempt("first-light",distinct,true) and Canonical.same(cold.replay("first-light"),distinct),"A distinct newly completed recording remains eligible for the collection")
	var changed := Canonical.digest(cold.data)
	_check(not cold.remove_replay("first-light",saved) and Canonical.digest(cold.data) == changed,"A stale expected pair cannot remove a replacement replay")

func _delete_icon(node: Node) -> Button:
	if node is Button and node.tooltip_text.begins_with("Delete replay:"): return node
	for child: Node in node.get_children():
		var found := _delete_icon(child)
		if found != null: return found
	return null

func _has_text(node: Node, text: String) -> bool:
	if node is Label and node.text == text: return true
	for child: Node in node.get_children():
		if _has_text(child,text): return true
	return false
