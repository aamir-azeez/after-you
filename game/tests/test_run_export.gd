extends "res://tests/test_solo_replay_remove_part.gd"
## Export this run in Replays, the owner's phone only:
## - the capabilities read (asked with X-AfterYou-Run-Export) is what turns it
##   on, kept per player so a launch knows it, and nothing else does;
## - without it the preview row is as before ("Options" keeps its label); with
##   it "Export this run" sits between Watch all parts and the "…" Options icon,
##   on the wide preview and the narrow parts card;
## - a solo attempt leaves as every part in the blob format, a Together attempt
##   as the exact bytes this phone keeps, named after the chapter and attempt;
## - a double tap opens one sheet, and no file or no sheet says so.
## Synthetic ids only.
const Switches = preload("res://services/tester_switches.gd")
const RunExport = preload("res://services/run_export.gd")
const FileShare = preload("res://services/file_share.gd")
const BlobCodec = preload("res://services/blob_codec.gd")
const HistoryStore = preload("res://services/history_store.gd")
const RelayOnline = preload("res://services/relay_online_session.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const MemoryStore = preload("res://tests/test_relay_online.gd").MemoryStore

const SERVER := "https://run-export.example.test"
const ME := "eeeeeeeeeeeeeeeeeeeeee"
const ROOM := "rrrrrrrrrrrrrrrrrrrrrr"

## Answers capabilities reads from a queue.
class CapabilityApi:
	extends Node
	var base_url := SERVER
	var player_id := ME
	var device_token := "synthetic-device-token"
	var replies: Array = []
	func request_json(_method: int, _path: String, _body: Dictionary = {}, _still: Callable = Callable()) -> Dictionary:
		await Engine.get_main_loop().process_frame
		return replies.pop_front() if not replies.is_empty() else {"ok": false, "status": 0, "code": "connection_interrupted"}

## Records what reaches the share sheet.
class ShareSpy:
	extends RefCounted
	var calls: Array = []
	var answer := true
	func share(bytes: PackedByteArray, file_name: String) -> bool:
		calls.append({"bytes": bytes, "file_name": file_name})
		return answer

var switches: RefCounted

func _run() -> void:
	directory = "user://run-export-" + Crypto.new().generate_random_bytes(6).hex_encode()
	DirAccess.make_dir_recursive_absolute(directory)
	switches = Switches.new(directory + "/switches.json")
	Switches.use_shared(switches)
	_own_scope()
	_naming()
	await _capabilities_gate()
	var paths := _seed()
	await _solo_wide(paths)
	await _solo_narrow(paths)
	await _together(paths)
	Switches.use_shared(null)
	print("RUN EXPORT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _naming() -> void:
	_check(RunExport.file_name("relay-isles@2", 1) == "relay-isles-attempt-1.afteryou", "The Relay Isles' first attempt is relay-isles-attempt-1.afteryou")
	_check(RunExport.file_name("sleeping-lighthouse@1", 3) == "sleeping-lighthouse-attempt-3.afteryou", "A chapter's id names it, with its attempt")
	_check(RunExport.file_name("A House For Two!@1", 0) == "a-house-for-two-attempt-1.afteryou", "Anything else is lowercased and hyphenated, from attempt 1")
	_check(RunExport.file_name("@1", 2) == "run-attempt-2.afteryou" and RunExport.file_name("../..@1", 1) == "run-attempt-1.afteryou", "A key with no usable id is still a plain name")
	for name: String in ["relay-isles-attempt-1.afteryou", RunExport.file_name("sleeping-lighthouse@1", 12)]:
		_check(FileShare.valid_name(name), "Both plugins keep %s unchanged" % name)
	for name: String in ["", "../x.afteryou", "Relay.afteryou", "-x.afteryou", "a b.afteryou", "a".repeat(FileShare.MAX_NAME + 1)]:
		_check(not FileShare.valid_name(name), "A name the plugins would change is refused: '%s'" % name)
	_check(not FileShare.share_file(PackedByteArray([1, 2, 3]), "relay-isles-attempt-1.afteryou"), "A desktop build has no share sheet")
	_check(not FileShare.share_file(PackedByteArray(), "relay-isles-attempt-1.afteryou"), "and nothing is offered for no bytes")

func _capabilities_gate() -> void:
	var api := CapabilityApi.new()
	root.add_child(api)
	var session: RefCounted = RelayOnline.new(api, func() -> Dictionary: return {"ready": true, "player_id": ME, "epoch": 1}, MemoryStore.new())
	var base := {"api_version": 2, "simulation_version": 2, "recording_version": 2, "mutations_enabled": true, "validation": "structural_client_replay_required", "chapters": []}
	var owner := base.duplicate()
	owner.run_export_version = 1
	api.replies = [{"ok": true, "status": 200, "data": JSON.parse_string(JSON.stringify(owner))}]
	_check(await session.load_capabilities(), "A reply with run_export_version still reads as valid capabilities")
	_check(session.run_export_allowed() and switches.run_export(), "It allows the export and keeps that for this player")
	_check(_kept(), "A restart still knows it")
	for value: Variant in [2, "1", true]:
		var odd := base.duplicate()
		odd.run_export_version = value
		session.capabilities = odd
		_check(not session.run_export_allowed(), "Only version 1 allows it: %s" % [value])
	api.replies = [{"ok": true, "status": 200, "data": base.duplicate()}]
	_check(await session.load_capabilities() and not session.run_export_allowed() and not switches.run_export(), "A read without it takes it away")
	_check(not _kept(), "on disk too")
	api.replies = [{"ok": true, "status": 200, "data": JSON.parse_string(JSON.stringify(owner))}]
	await session.load_capabilities()
	api.replies = [{"ok": false, "status": 0, "code": "connection_interrupted"}]
	_check(not await session.load_capabilities() and switches.run_export(), "An offline launch keeps the last answer")
	api.queue_free()

## Main points the shared switches at its own player when it starts; these tests' player is ME.
func _own_scope() -> void:
	switches.scope_source = func() -> Dictionary: return {"server": SERVER, "owner": ME}

func _kept() -> bool:
	var again: RefCounted = Switches.new(directory + "/switches.json")
	again.scope_source = func() -> Dictionary: return {"server": SERVER, "owner": ME}
	return again.run_export()

func _solo_wide(paths: Dictionary) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1600, 738)
	root.add_child(viewport)
	switches.note_run_export(SERVER, ME, false)
	var app := await _app(viewport, paths, "export-wide")
	_own_scope()
	var flow: Node = app.replays_flow
	_check(_export(app.overlay) == null, "Without the capability there is no Export this run")
	var options := _button(app.overlay, "Options")
	_check(options != null and options.icon == null, "and Options keeps its label")
	switches.note_run_export(SERVER, ME, true)
	var spy := ShareSpy.new()
	flow.share_file = spy.share
	flow.show_collection()
	await _frames(2)
	var export := _export(app.overlay)
	_check(export != null and export.text == "Export this run" and export.icon != null, "With it the preview offers Export this run with the share icon")
	if export == null:
		viewport.queue_free()
		return
	var row: Array = export.get_parent().get_children().filter(func(node: Node) -> bool: return node is Button)
	var dots: Button = row[row.find(export) + 1] if row.find(export) + 1 < row.size() else null
	_check(row.size() == 4 and row[0].text == "Watch all parts" and row[1] == export and row[3].tooltip_text.begins_with("Delete replay:"), "The row reads Watch all parts, Export this run, the Options icon, delete")
	_check(dots != null and dots.text.is_empty() and dots.icon != null and dots.accessibility_name == "Options" and dots.tooltip_text == "Options", "Options is the dots icon beside it, still named Options")
	_check(str(export.get_meta("export_file_name", "")) == "relay-isles-attempt-1.afteryou", "The file is named after the chapter and attempt")
	var entry: Dictionary = flow._selected_solo_attempt
	var journal: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(str(paths[Registry.RELAY])))
	export.pressed.emit()
	export.pressed.emit()
	_check(spy.calls.size() == 1, "A double tap opens one share sheet (%d)" % spy.calls.size())
	_check(export.disabled, "and the button waits while it opens")
	if not spy.calls.is_empty():
		var sent: PackedByteArray = spy.calls[0].bytes
		_check(spy.calls[0].file_name == "relay-isles-attempt-1.afteryou", "The sheet gets the file's name")
		_check(sent == RunExport.solo_blob(Registry.RELAY, entry.playback_rows), "and exactly the attempt's blob")
		_check(sent.size() > 1 and sent[0] == BlobCodec.ENCODING_DEFLATE, "in the deflate blob format, never raw JSON")
		var canonical := sent.slice(1).decompress_dynamic(HistoryStore.MAX_ATTEMPT_BYTES, FileAccess.COMPRESSION_DEFLATE)
		var document: Variant = JSON.parse_string(canonical.get_string_from_utf8())
		_check(document is Dictionary and document.get("format") == RunExport.FORMAT and document.get("chapter_key") == Registry.RELAY and Canonical.same(document.get("pairs"), journal.relay.pairs), "Its every part is the journal's, in order")
		_check(BlobCodec.verified(sent, canonical.size(), BlobCodec.digest(canonical), HistoryStore.MAX_ATTEMPT_BYTES) == canonical, "and it decodes and checks like any stored blob")
	# No sheet on this device: a short note, and the next tap tries again.
	flow._export_settle_until = 0
	spy.answer = false
	export.pressed.emit()
	_check(spy.calls.size() == 2 and app.toast.text == PlayerCopy.EXPORT_RUN_FAILED, "No share sheet says so: %s" % app.toast.text)
	_check(flow._export_settle_until == 0, "and does not hold the next tap")
	# No file to send: the same note, and nothing reaches the sheet.
	spy.answer = true
	var empty: Button = flow._export_button(func() -> PackedByteArray: return PackedByteArray(), "relay-isles-attempt-1.afteryou")
	app.toast.text = ""
	empty.pressed.emit()
	_check(spy.calls.size() == 2 and app.toast.text == PlayerCopy.EXPORT_RUN_FAILED, "A run with no file says so too")
	empty.free()
	_check(RunExport.solo_blob(Registry.RELAY, [entry.playback_rows[1]]).is_empty(), "An attempt missing its first part exports nothing")
	viewport.queue_free()
	await process_frame

func _solo_narrow(paths: Dictionary) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(900, 600)
	root.add_child(viewport)
	switches.note_run_export(SERVER, ME, true)
	var app := await _app(viewport, paths, "export-narrow")
	_own_scope()
	app.replays_flow.show_collection()
	var row: Button = _chapter_rows(app)[0] if not _chapter_rows(app).is_empty() else null
	_check(row != null, "The narrow list shows the attempt")
	if row != null:
		row.pressed.emit()
		var export := _export(app.overlay)
		_check(app.mode == ReplaysFlow.MODE_SOLO_REPLAY_ATTEMPT and export != null and str(export.get_meta("export_file_name", "")) == "relay-isles-attempt-1.afteryou", "The narrow parts card offers Export this run too")
	switches.note_run_export(SERVER, ME, false)
	app.replays_flow.show_collection()
	row = _chapter_rows(app)[0] if not _chapter_rows(app).is_empty() else null
	if row != null:
		row.pressed.emit()
		_check(_export(app.overlay) == null, "and only with the capability")
	viewport.queue_free()
	await process_frame

## A Together attempt leaves as the bytes this phone keeps for the selected part's branch.
func _together(paths: Dictionary) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1600, 738)
	root.add_child(viewport)
	var app := await _app(viewport, paths, "export-together")
	var api := CapabilityApi.new()
	root.add_child(api)
	var session: RefCounted = RelayOnline.new(api, func() -> Dictionary: return {"ready": true, "player_id": ME, "epoch": 1}, MemoryStore.new())
	session.history_store = HistoryStore.new(directory + "/history")
	app.relay_session = session
	var canonical := JSON.stringify({"format": "after-you.attempt", "format_version": 1, "room_id": ROOM, "position": 1}).to_utf8_buffer()
	var tagged := BlobCodec.encode(canonical)
	var record := {"position": 1, "link": "a".repeat(64), "digest": BlobCodec.digest(canonical), "byte_length": canonical.size()}
	_check(session.history_store.save(SERVER.sha256_text(), ME, ROOM, record, tagged), "This phone keeps a room's second attempt")
	_check(session.history_attempt(ROOM, 1) == tagged, "The session reads it back byte for byte")
	_check(session.history_attempt(ROOM, 0).is_empty() and session.history_attempt("x".repeat(22), 1).is_empty(), "and nothing for an attempt it does not keep")
	var flow: Node = app.replays_flow
	var spy := ShareSpy.new()
	flow.share_file = spy.share
	flow.run_export_allowed = func() -> bool: return false
	var room := {"family": "chapter", "room_id": ROOM, "chapter_key": Registry.RELAY}
	_check(flow._shared_export_button(room, {"id": "p1-0"}) == null, "Together offers nothing without the capability")
	flow.run_export_allowed = func() -> bool: return true
	_check(flow._shared_export_button({"family": "legacy", "room_id": ROOM, "chapter_key": ""}, {"id": "a1"}) == null, "nor for an earlier-islands room")
	var export: Button = flow._shared_export_button(room, {"id": "p1-0"})
	_check(export != null and str(export.get_meta("export_file_name", "")) == "relay-isles-attempt-2.afteryou", "A Together part offers its attempt, named by the attempt's place")
	if export != null:
		app.overlay.add_child(export)
		export.pressed.emit()
		_check(spy.calls.size() == 1 and spy.calls[0].bytes == tagged, "The sheet gets the kept attempt byte for byte")
		export.queue_free()
	var missing: Button = flow._shared_export_button(room, {"id": "p0-1"})
	flow._export_settle_until = 0
	app.toast.text = ""
	missing.pressed.emit()
	_check(spy.calls.size() == 1 and app.toast.text == PlayerCopy.EXPORT_RUN_FAILED, "An attempt this phone does not keep says so")
	missing.free()
	api.queue_free()
	viewport.queue_free()
	await process_frame

func _export(node: Node) -> Button:
	for button: Button in _buttons(node):
		if button.name == "ExportRun" and button.is_visible_in_tree(): return button
	return null
