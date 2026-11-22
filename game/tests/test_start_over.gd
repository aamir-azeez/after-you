extends SceneTree
## Start over on a chapter save that could not be verified (relay_preview.gd
## _show_error, RelayJourney.start_over, LighthouseJourney.start_over): the
## card offers it beside Back, every copy of the save moves aside whole under
## a recovery name, the chapter opens fresh from its first stage, and every
## other save stays byte for byte.
const RelayPreview = preload("res://relay_preview.gd")
const RelayJournal = preload("res://services/relay_journey.gd")
const LighthouseJournal = preload("res://services/lighthouse_journey.gd")
const AtomicFile = preload("res://services/atomic_file.gd")
const Registry = preload("res://services/chapter_registry.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")

var checks := 0
var failures := 0
var directory := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	directory = "user://start-over-test-" + Crypto.new().generate_random_bytes(6).hex_encode()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	await _relay_card()
	_lighthouse_journal()
	_verified_journal_stays()
	for name: String in DirAccess.get_files_at(directory): DirAccess.remove_absolute(directory.path_join(name))
	DirAccess.remove_absolute(directory)
	print("AFTER YOU START OVER: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


## A journal on rules this build does not play, with a backup copy beside it,
## another chapter's journal and an archived attempt of this one.
func _relay_card() -> void:
	var chapter := Registry.RELAY
	var path := directory.path_join("relay.json")
	var state: Dictionary = RelayJournal.new(path, null, chapter)._empty_state()
	state.simulation_version = 999
	var unsupported := JSON.stringify({"version": 1, "generation": 2, "relay": state})
	_write(path, unsupported)
	_write(path + AtomicFile.BACKUP, JSON.stringify({"version": 1, "generation": 1, "relay": state}))
	var others := {directory.path_join("first-steps.json"): "{\"version\": 1}", path + ".attempt-0123.json": "{\"kept\": true}"}
	for other: String in others: _write(other, others[other])
	var before := _hashes()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	root.add_child(viewport)
	var app := RelayPreview.new()
	app.chapter_key = chapter
	app.journey = RelayJournal.new(path, null, chapter)
	app.settings = {"sound": false, "haptics": false, "reduced_motion": true, "assistance": true, "left_handed": false}
	viewport.add_child(app)
	app.set_physics_process(false)
	app.set_process(false)
	app.world.set_process(false)
	await _settle()
	app.backgrounded = false
	_check(app.mode == "error" and app.journey.read_only and str(app.journey.last_error).ends_with(PlayerCopy.LIGHTHOUSE_JOURNEY_3277AC1A21BD), "An unsupported journal holds the chapter on its error card (%s)" % app.journey.last_error)
	var start_over := _find_action(app.controls.overlay, "start_over")
	_check(start_over != null and not start_over.disabled and start_over.text == "Start over", "The error card offers Start over")
	_check(_find_action(app.controls.overlay, "back") != null, "Back stays beside it")
	if start_over == null:
		viewport.queue_free()
		await _settle()
		return
	start_over.pressed.emit()
	await _settle()
	_check(app.mode == "ready" and not app.journey.read_only, "Start over opens the chapter ready to play (%s)" % app.mode)
	_check(app.journey.pairs().is_empty() and app.journey.prior_recording().is_empty() and app.journey.stage_id() == str(Registry.initial_checkpoint(chapter).next_stage_id), "The chapter opens fresh from its first stage")
	_check(not FileAccess.file_exists(path) and not FileAccess.file_exists(path + AtomicFile.BACKUP), "No copy of the unusable journal is left where the chapter reads")
	for copy: String in [path, path + AtomicFile.BACKUP]:
		var hash: String = before[copy]
		var aside := copy + AtomicFile.STARTED_OVER + hash + ".json"
		_check(FileAccess.file_exists(aside) and FileAccess.get_sha256(aside) == hash, "The old copy is kept byte for byte under a recovery name: " + copy.get_file())
	for other: String in others:
		_check(FileAccess.get_sha256(other) == before[other], "Another save stays as it was: " + other.get_file())
	_check(_find_action(app.controls.overlay, "start_over") == null, "A fresh chapter no longer offers Start over")
	viewport.queue_free()
	await _settle()


## The @1 Lighthouse journal starts over the same way.
func _lighthouse_journal() -> void:
	var path := directory.path_join("lighthouse.json")
	var state: Dictionary = LighthouseJournal.new(path)._empty_state()
	state.simulation_version = 999
	_write(path, JSON.stringify({"version": 1, "generation": 1, "lighthouse": state}))
	var hash := FileAccess.get_sha256(path)
	var journey := LighthouseJournal.new(path)
	journey.load_data()
	_check(journey.read_only and journey.can_start_over(), "An unsupported Lighthouse journal is held and can start over")
	_check(journey.start_over() and not journey.read_only and journey.pairs().is_empty() and journey.stage_id() == str(LighthouseJournal.Catalog.STAGE_IDS[0]),"The Lighthouse journal opens fresh")
	_check(not FileAccess.file_exists(path) and FileAccess.get_sha256(path + AtomicFile.STARTED_OVER + hash + ".json") == hash, "The old Lighthouse journal is kept under a recovery name")


## A journal that verifies is never moved.
func _verified_journal_stays() -> void:
	var path := directory.path_join("fresh.json")
	var journey := RelayJournal.new(path, null, Registry.RELAY)
	journey.load_data()
	_check(not journey.read_only and not journey.can_start_over() and not journey.start_over(), "A journal that loads does not start over")


func _hashes() -> Dictionary:
	var result := {}
	for name: String in DirAccess.get_files_at(directory):
		result[directory.path_join(name)] = FileAccess.get_sha256(directory.path_join(name))
	return result


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _find_action(node: Node, action_id: String) -> Button:
	if node is Button and node.is_visible_in_tree() and node.get_meta("action_id", "") == action_id: return node
	for child: Node in node.get_children():
		var found := _find_action(child, action_id)
		if found != null: return found
	return null


func _settle() -> void:
	await process_frame
	await process_frame


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
