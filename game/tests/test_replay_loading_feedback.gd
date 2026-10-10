extends SceneTree
## Replays loading feedback on the real Main screens: Solo shows a progress bar
## (never "nothing saved") while its read-only scan runs, fills in by itself,
## keeps selection and scroll, and draws the last finished list at once from a
## display-only snapshot whose rows stay unplayable until checked. Together
## shows its bar on every local loading path. A Watch tap disables the control
## and shows a wait before any scene load.
const Main = preload("res://main.gd")
const Storage = preload("res://services/local_save.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Journey = preload("res://services/relay_journey.gd")
const Archive = preload("res://services/attempt_archive.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Levels = preload("res://core/levels.gd")
const Solo = preload("res://services/solo_replay_collection.gd")
const Index = preload("res://services/solo_replay_index.gd")
const Visibility = preload("res://services/solo_replay_visibility.gd")
const Shared = preload("res://services/shared_replay_collection.gd")
const FakeApi = preload("res://tests/fake_rooms_api.gd")
const Retained = preload("res://tests/retained_chapter_fixture.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const HOST := "HHHHHHHHHHHHHHHHHHHHHH"
const GUEST := "GGGGGGGGGGGGGGGGGGGGGG"
const ROOM := "RRRRRRRRRRRRRRRRRRRRRR"
const OTHER := "SSSSSSSSSSSSSSSSSSSSSS"

class Memory extends RefCounted:
	var values: Dictionary = {}
	func load_scope(scope: String) -> Dictionary:
		return {"ok": true, "found": values.has(scope), "value": values.get(scope, {}).duplicate(true)}
	func save_scope(scope: String, value: Dictionary) -> bool:
		values[scope] = value.duplicate(true)
		return true

class OnlineMemory extends Memory:
	func save_game(scope: String, value: Dictionary) -> Dictionary:
		save_scope(scope, value)
		return {"ok": true}

var checks := 0
var failures := 0
var directory := ""
var api: Node
var journal_names: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	directory = "user://replay-loading-feedback-" + Crypto.new().generate_random_bytes(6).hex_encode()
	DirAccess.make_dir_recursive_absolute(directory)
	var paths := _seed_solo()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	root.add_child(viewport)
	var app := Main.new()
	app.saves = Storage.new(directory + "/save.json")
	app.saves.data.settings.sound = false
	app.saves.data.settings.haptics = false
	viewport.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	app.world.set_process(false)
	app.api.queue_free()
	api = FakeApi.new()
	app.add_child(api)
	app.api = api
	app.application_backgrounded = false
	app.solo_replay_index = Index.new(directory + "/index.json")
	app.solo_replay_visibility = Visibility.new(directory + "/visibility.json")
	for value: Variant in paths.values(): journal_names.append(str(value).get_file())
	await process_frame
	await _solo_scan(app, paths)
	await _solo_finished_empty(app, paths)
	await _watch_wait(app, paths)
	await _snapshot(app, paths)
	await _together(app)
	_check(api.calls.is_empty(), "Loading feedback, snapshot rows and Together local checks send no network request")
	viewport.queue_free()
	await process_frame
	print("REPLAY LOADING FEEDBACK: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## Completed First Steps and Relay journals plus a Relay archive, in a private
## directory. Every other chapter path is left missing.
func _seed_solo() -> Dictionary:
	var paths := {"sleeping-lighthouse@1": directory + "/lighthouse.json"}
	for chapter: String in Registry.keys(): paths[chapter] = directory + "/" + chapter.validate_filename() + ".json"
	for spec: Dictionary in [{"chapter": Registry.FIRST_STEPS, "folder": "first_steps"}, {"chapter": Registry.RELAY, "folder": "v2"}]:
		var chapter := str(spec.chapter)
		var level := Registry.definition(chapter)
		var validator := Journey.new(str(paths[chapter]), null, chapter)
		var complete := {}
		for rules: Variant in Registry.supported_rules(chapter):
			var pairs: Array = []
			for stage: Dictionary in level.stages:
				pairs.append({"a": _fixture(str(spec.folder) + "/" + str(stage.id) + "-a"), "b": _fixture(str(spec.folder) + "/" + str(stage.id) + "-b")})
			var state := {"schema_version": level.schema_version, "simulation_version": int(rules), "level_id": level.id, "level_version": level.version, "definition_hash": Canonical.digest(level), "pairs": pairs, "a": {}, "draft": {}}
			if validator._validate_state(state).get("valid", false):
				complete = state
				break
		_check(not complete.is_empty(), "Published fixtures form a complete accepted journal: " + chapter)
		var envelope := Storage.defaults()
		envelope.generation = 1
		envelope["relay"] = complete
		_write(str(paths[chapter]), envelope)
		if chapter == Registry.RELAY and not complete.is_empty():
			var prefix := complete.duplicate(true)
			prefix.pairs = [complete.pairs[0]]
			_check(Archive.save(str(paths[chapter]), "relay", prefix, Journey.MAX_SAVE_BYTES, Journey.MAX_ARCHIVED_ATTEMPTS).is_empty(), "An archived earlier Relay attempt is available")
	return paths

func _solo_scan(app: Node, paths: Dictionary) -> void:
	Solo._verified.clear()
	# Eight layout-only earlier-island rows make the list scroll; they are
	# never played or verified here.
	var replays := {}
	for index in range(8): replays[Levels.get_level(index).id] = {"b": {"layout_fixture": true}}
	app.saves.data.replays = replays
	app.solo_replays = Solo.new(paths, "")
	app._solo_collection_started = false
	app._show_collection()
	var bar: Control = app._solo_scan_bar
	_check(app.solo_replays.scan_pending() and is_instance_valid(bar) and bar.is_inside_tree(), "Opening Solo shows the loading bar in the same frame the screen is built")
	_check(not _has_text(app.overlay, Main.EMPTY_SOLO_COLLECTION), "While scanning, the empty message is never shown")
	_check(bar.status.text.ends_with("0 / 3") and bar.status.text.begins_with(Main.SOLO_COLLECTION_SCANNING), "The bar counts real sources (0 of 3) and reuses the existing scanning copy")
	_check(_chapter_rows(app).is_empty() and _rows(app).size() == 8, "Only already known rows are listed before any chapter is checked")
	# Select an earlier island deliberately, then scroll the list.
	var chosen: Button = _rows(app)[3]
	chosen.pressed.emit()
	var chosen_key := str(app._selected_solo_attempt.get("key", ""))
	await _frames(3)
	var scroll: ScrollContainer = app._bounded_card_scroll
	_check(scroll.get_v_scroll_bar().max_value > scroll.size.y + 60, "The eight-row list is long enough to scroll")
	scroll.scroll_vertical = 60
	await _frames(1)
	# Zero chapter rows found yet: the bar stays and the empty text stays away.
	var guard := 0
	var redraws := 0
	var previous: Control = app._solo_scan_bar
	var partial_seen := false
	var progress_moved := false
	while app.solo_replays.scan_pending() and guard < 6000:
		# Desktop checks are fast; let the first settled chapter draw without
		# waiting out the reveal interval so the partial state is observable.
		if not partial_seen and int(app.solo_replays.scan_progress().settled) > 0: app._solo_collection_redraw_at = 0
		app._service_solo_collection()
		if app._solo_scan_bar != previous:
			redraws += 1
			previous = app._solo_scan_bar
		if is_instance_valid(app._solo_scan_bar) and app._solo_scan_bar.bar.value > 0.0: progress_moved = true
		if app.solo_replays.scan_pending() and not _chapter_rows(app).is_empty():
			if not partial_seen:
				partial_seen = true
				await _frames(2)
				_check(is_instance_valid(app._solo_scan_bar) and app._solo_scan_bar.is_visible_in_tree(), "Partial results keep the loading bar beside the rows")
				_check(_chapter_rows(app).all(func(button: Button) -> bool: return button.text.begins_with("First Steps")), "Only fully checked chapters are listed while others are still checked")
				_check(str(app._selected_solo_attempt.get("key", "")) == chosen_key, "Arriving rows keep the player's selection")
				_check(app._bounded_card_scroll.scroll_vertical == 60, "Arriving rows keep the list's scroll position")
		_check(app.mode == "collection" and not _has_text(app.overlay, Main.EMPTY_SOLO_COLLECTION), "No empty state appears at any point of the scan")
		guard += 1
		await process_frame
	_check(partial_seen and progress_moved, "Some found: rows appear with a moving determinate bar before the scan ends (%s, %s)" % [partial_seen, progress_moved])
	_check(redraws <= 4, "Arrivals redraw a bounded number of times (%d)" % redraws)
	# Finished: the open screen fills in by itself, without navigation.
	app._service_solo_collection()
	await _frames(2)
	_check(app.mode == "collection" and not is_instance_valid(app._solo_scan_bar) and app._solo_scan_bar == null, "The bar goes away when the scan finishes")
	var titles: Array = _chapter_rows(app).map(func(button: Button) -> String: return button.text)
	var relay_title := str(Registry.descriptor(Registry.RELAY).title)
	_check(titles.has("First Steps · Attempt 1") and titles.has(relay_title + " · Attempt 1") and titles.has(relay_title + " · Attempt 2"), "Finished results appear on the open screen without leaving it: " + str(titles))
	_check(str(app._selected_solo_attempt.get("key", "")) == chosen_key and app._bounded_card_scroll.scroll_vertical == 60, "Selection and scroll survive the final redraw")
	_check(not _has_text(app.overlay, Main.EMPTY_SOLO_COLLECTION), "A populated finished scan never shows the empty message")
	var settled: int = app._solo_collection_entries().size()
	app._service_solo_collection()
	await _frames(2)
	_check(app._solo_collection_entries().size() == settled and not app._solo_collection_dirty, "A finished scan stops redrawing")

func _solo_finished_empty(app: Node, paths: Dictionary) -> void:
	# A journal with no accepted pair: scanning shows the bar, and only the
	# finished scan shows the empty message.
	app.saves.data.replays = {}
	var empty_paths := paths.duplicate()
	for chapter: String in empty_paths: empty_paths[chapter] = directory + "/none-" + chapter.validate_filename() + ".json"
	_check(Retained.seed(str(empty_paths[Registry.RELAY]), Registry.RELAY), "An unfinished Relay journal has no accepted pair")
	app.solo_replays = Solo.new(empty_paths, "")
	app.solo_replay_index = Index.new(directory + "/index-none.json")
	app._solo_collection_started = false
	app._show_collection()
	_check(app.solo_replays.scan_pending() and is_instance_valid(app._solo_scan_bar) and not _has_text(app.overlay, Main.EMPTY_SOLO_COLLECTION), "Zero found while scanning: bar, not the empty message")
	_check(app._solo_scan_bar.status.text.begins_with("Loading saved replays") and app._solo_scan_bar.bar.indeterminate == not app._solo_scan_bar.reduced_motion, "Nothing found yet uses the general loading text and an activity bar")
	var guard := 0
	while (app.solo_replays.scan_pending() or app._solo_collection_dirty) and guard < 3000:
		app._service_solo_collection()
		guard += 1
		await process_frame
	_check(_has_text(app.overlay, Main.EMPTY_SOLO_COLLECTION) and app._solo_scan_bar == null, "The empty message appears only after the scan has finished with nothing")
	var missing := paths.duplicate()
	for chapter: String in missing: missing[chapter] = directory + "/missing/" + chapter.validate_filename() + ".json"
	app.solo_replays = Solo.new(missing, "")
	app._solo_collection_started = false
	app._show_collection()
	_check(not app.solo_replays.scan_pending() and _has_text(app.overlay, Main.EMPTY_SOLO_COLLECTION) and app._solo_scan_bar == null, "With no saved source at all the finished empty state shows at once")

func _watch_wait(app: Node, paths: Dictionary) -> void:
	app.solo_replay_index = Index.new(directory + "/index.json")
	app.solo_replays = Solo.new(paths, "")
	app._solo_collection_started = false
	app._show_collection()
	var guard := 0
	while (app.solo_replays.scan_pending() or app._solo_collection_dirty) and guard < 3000:
		app._service_solo_collection()
		guard += 1
		await process_frame
	var row: Button = _chapter_rows(app)[0]
	row.pressed.emit()
	var watch := _button(app.overlay, "Watch replay")
	_check(watch != null and watch.has_meta("replay_launch") and not watch.disabled, "A chapter attempt offers a Watch replay launch")
	if watch == null: return
	var context_path := "user://solo-replay-playback.json"
	if FileAccess.file_exists(context_path): DirAccess.remove_absolute(ProjectSettings.globalize_path(context_path))
	watch.pressed.emit()
	var waits: Array[Node] = app.overlay.find_children("ReplayLaunchWait", "", true, false)
	_check(watch.disabled and waits.size() == 1 and (waits[0] as Control).is_visible_in_tree(), "Tapping Watch replay disables it and shows the wait at once")
	_check(waits.size() == 1 and waits[0].status.text == "Preparing replay…", "The wait reuses the existing preparing copy")
	_check(_buttons(app.overlay).filter(func(button: Button) -> bool: return button.has_meta("replay_launch")).all(func(button: Button) -> bool: return button.disabled), "Every Watch and Play control waits with it")
	watch.pressed.emit()
	(_button(app.overlay, "Play") as Button).pressed.emit()
	_check(app.overlay.find_children("ReplayLaunchWait", "", true, false).size() == 1, "A second tap cannot start a second launch")
	app._solo_collection_dirty = true
	app._service_solo_collection()
	_check(app.overlay.find_children("ReplayLaunchWait", "", true, false).size() == 1 and watch.disabled, "List redraws hold off while the launch is waiting")
	# The launch is refused (transport busy): the same screen gets its controls back.
	api.busy = true
	await _frames(4)
	api.busy = false
	_check(is_instance_valid(watch) and not watch.disabled and app.overlay.find_children("ReplayLaunchWait", "", true, false).is_empty() and app._replay_launch_view == -1, "A refused launch restores the controls on the same screen")
	_check(app.mode == "collection" and not FileAccess.file_exists(context_path), "A refused launch writes no playback context")
	app._solo_collection_dirty = false

func _snapshot(app: Node, paths: Dictionary) -> void:
	var index_path := directory + "/index.json"
	var stored := Index.new(index_path).rows()
	_check(stored.size() == 5 and not FileAccess.get_file_as_string(index_path).contains("\"pair\""), "A finished scan leaves a display snapshot with no recording payloads")
	var before := _hashes()
	# A cold launch: nothing remembered in this process, no recorded checks.
	await _cold_open(app, paths, index_path)
	var entries: Array = app._solo_collection_entries()
	_check(_chapter_rows(app).size() == 3 and entries.all(func(entry: Dictionary) -> bool: return entry.get("checking", false)), "Rows from the snapshot are listed at once, before any check")
	_check(is_instance_valid(app._solo_scan_bar) and not _has_text(app.overlay, Main.EMPTY_SOLO_COLLECTION), "Snapshot rows show with the loading bar and no empty message")
	var plays: Array = _buttons(app.overlay).filter(func(button: Button) -> bool: return button.text in ["Play", "Watch replay", "Watch all parts"])
	_check(not plays.is_empty() and plays.all(func(button: Button) -> bool: return button.disabled), "Every Play and Watch control of an unchecked row is disabled")
	for button: Button in plays: button.pressed.emit()
	app._play_solo_entry(entries[0], 0)
	_check(app.mode == "collection" and app.overlay.find_children("ReplayLaunchWait", "", true, false).is_empty() and not FileAccess.file_exists("user://solo-replay-playback.json"), "An unchecked row can never start playback")
	await _finish_scan(app)
	_check(app._solo_collection_entries().all(func(entry: Dictionary) -> bool: return not entry.get("checking", false)) and _chapter_rows(app).size() == 3, "Checked rows become playable on the same screen")
	_check(_buttons(app.overlay).filter(func(button: Button) -> bool: return button.text == "Play").all(func(button: Button) -> bool: return not button.disabled), "Play is enabled once the row is verified")
	# A removed part stays removed even while only the snapshot knows it.
	var single: Dictionary = stored.filter(func(row: Dictionary) -> bool: return row.archived)[0]
	_check(app.solo_replay_visibility.hide(single), "One snapshot part can be removed on this device")
	await _cold_open(app, paths, index_path)
	_check(_chapter_rows(app).size() == 2, "Visibility removals apply to snapshot rows")
	await _finish_scan(app)
	_check(_chapter_rows(app).size() == 2, "Visibility removals apply to the verified rows too")
	app.solo_replay_visibility = Visibility.new(directory + "/visibility-reset.json")
	# A source that disappeared is dropped when its chapter is checked.
	var archive := ""
	for name: String in DirAccess.get_files_at(directory):
		if ".attempt-" in name: archive = directory + "/" + name
	var archive_bytes := FileAccess.get_file_as_bytes(archive)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(archive))
	await _cold_open(app, paths, index_path)
	_check(_chapter_rows(app).size() == 3, "The snapshot still lists the vanished attempt while it is checked")
	await _finish_scan(app)
	_check(_chapter_rows(app).size() == 2 and Index.new(index_path).rows().size() == 4, "A vanished attempt is removed after the scan and from the snapshot")
	var restored := FileAccess.open(archive, FileAccess.WRITE)
	restored.store_buffer(archive_bytes)
	restored.close()
	# A damaged snapshot is ignored: bar only, never the empty message mid-scan.
	var damaged := FileAccess.open(directory + "/index-damaged.json", FileAccess.WRITE)
	damaged.store_string("{\"schema_version\":1,\"rows\":[{\"id\":\"forged\"}]}")
	damaged.close()
	await _cold_open(app, paths, directory + "/index-damaged.json")
	_check(_chapter_rows(app).is_empty() and is_instance_valid(app._solo_scan_bar) and not _has_text(app.overlay, Main.EMPTY_SOLO_COLLECTION), "A damaged snapshot is ignored and the scan shows only its bar")
	await _finish_scan(app)
	_check(_chapter_rows(app).size() == 3, "The scan still lists every verified attempt")
	_check(_hashes() == before, "Snapshot reads and writes never touch a journal or archive")

func _cold_open(app: Node, paths: Dictionary, index_path: String) -> void:
	Solo._verified.clear()
	app._show_home()
	app.solo_replay_index = Index.new(index_path)
	app.solo_replays = Solo.new(paths, "")
	app._solo_collection_started = false
	app._selected_solo_attempt = {}
	app._show_collection()
	await process_frame

func _finish_scan(app: Node) -> void:
	var guard := 0
	while (app.solo_replays.scan_pending() or app._solo_collection_dirty) and guard < 4000:
		app._service_solo_collection()
		guard += 1
		await process_frame

func _together(app: Node) -> void:
	app.shared_replays = null
	app.identity_read_state = Main.IdentityReadState.LOADING
	app.identity_loading = true
	app._shared_identity_wait_until = -1
	app._show_shared_replays()
	_check(app.mode == "shared_replays" and is_instance_valid(app._shared_replay_loading_bar) and not _has_text(app.overlay, PlayerCopy.MAIN_1E12325B0B49), "Cold start: Together shows its bar while the saved account is read")
	app.identity_loading = false
	app.identity_read_state = Main.IdentityReadState.LOADED
	app.identity_data = {"player_id": HOST, "device_token": "synthetic-token"}
	api.player_id = HOST
	api.device_token = "synthetic-token"
	# Two saved rooms, each with a verified earlier-island replay.
	var cache := Memory.new()
	var seed := Shared.new(api, app._relay_identity, cache, OnlineMemory.new())
	var legacy := {"room_id": ROOM, "host_id": HOST, "guest_id": GUEST, "level_id": "first-light", "attempt": 3, "first_player_id": GUEST, "active_role": "complete", "recordings": {"a": _fixture("first-light-a"), "b": _fixture("first-light-b")}}
	var other := legacy.duplicate(true)
	other.room_id = OTHER
	_check(seed.load_saved(legacy) and seed.load_saved(other), "Two shared rooms are saved on this device")
	# First open of a cold process: nothing is checked yet.
	app.shared_replays = Shared.new(api, app._relay_identity, cache, OnlineMemory.new())
	app._service_shared_replays()
	_check(app._shared_identity_wait_until == -1, "The account wait ends once the account is read")
	app._show_shared_replays()
	_check(app.shared_replays.local_loading() and is_instance_valid(app._shared_replay_loading_bar) and app._shared_replay_loading_bar.is_inside_tree(), "First open shows the Together bar in its first frame")
	_check(not _has_text(app.overlay, PlayerCopy.MAIN_87534286A315) and not _has_text(app.overlay, PlayerCopy.MAIN_DE8FFD26387B), "No nothing-saved text before the local check finishes")
	var guard := 0
	while app.shared_replays.local_loading() and guard < 4000:
		app._service_shared_replays()
		if app.shared_replays.local_loading(): _check(is_instance_valid(app._shared_replay_loading_bar) and not _has_text(app.overlay, PlayerCopy.MAIN_87534286A315) and not _has_text(app.overlay, PlayerCopy.MAIN_DE8FFD26387B), "Every loading frame keeps the bar and no empty text")
		guard += 1
		await process_frame
	_check(app.mode == "shared_memories" and app._listed_shared_rooms().size() == 2 and app._shared_replay_loading_bar == null, "Finished local check opens a room, with the bar gone")
	# Reopen while the active room is re-checked, then switch rooms meanwhile.
	app.saves.data.room = legacy.duplicate(true)
	app._show_shared_replays()
	_check(app.shared_replays.local_loading() and app.mode == "shared_memories" and is_instance_valid(app._shared_replay_loading_bar) and _rows(app).size() == 1, "Reopening shows the saved rows together with the bar")
	var selector: OptionButton = app.overlay.find_children("*", "OptionButton", true, false)[0]
	var target := 1 - selector.selected
	selector.select(target)
	selector.item_selected.emit(target)
	_check(app.shared_replay_room == str(selector.get_item_metadata(target)) and app.shared_replays.local_loading() and is_instance_valid(app._shared_replay_loading_bar) and not _has_text(app.overlay, PlayerCopy.MAIN_DE8FFD26387B), "Choosing another room during the check keeps the bar and no empty text")
	guard = 0
	while app.shared_replays.local_loading() and guard < 4000:
		app._service_shared_replays()
		guard += 1
		await process_frame
	_check(app.mode == "shared_memories" and app._shared_replay_loading_bar == null and _rows(app).size() == 1, "The switched room finishes without the bar")
	app.saves.data.room = {}

func _chapter_rows(app: Node) -> Array:
	return _rows(app).filter(func(button: Button) -> bool: return " · Attempt " in button.text)

func _rows(app: Node) -> Array:
	return _buttons(app.overlay).filter(func(button: Button) -> bool: return button.has_meta("replay_row"))

func _buttons(node: Node) -> Array:
	var result: Array = []
	for child: Node in node.find_children("*", "Button", true, false): result.append(child)
	return result

func _button(node: Node, text: String) -> Button:
	for button: Button in _buttons(node):
		if button.text == text: return button
	return null

func _has_text(node: Node, fragment: String) -> bool:
	if node is Label and fragment in node.text and node.is_visible_in_tree(): return true
	for child: Node in node.get_children():
		if _has_text(child, fragment): return true
	return false

func _hashes() -> Dictionary:
	# Every seeded journal and archive (cache files are not replay sources).
	var result := {}
	for name: String in DirAccess.get_files_at(directory):
		for journal: String in journal_names:
			if name.begins_with(journal): result[name] = FileAccess.get_sha256(directory + "/" + name)
	return result

func _frames(count: int) -> void:
	for frame in range(count): await process_frame

func _fixture(name: String) -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/" + name + ".json"))
	return value if value is Dictionary else {}

func _write(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()

func _check(condition: bool, message: String) -> void:
	checks += 1
	if condition: return
	failures += 1
	push_error(message)
