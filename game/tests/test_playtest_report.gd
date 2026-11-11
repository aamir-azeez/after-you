extends SceneTree
## The playtest report (tests/playtest_report.gd), on a folder it builds in
## the system temp folder from fixtures and freshly played turns, and removes
## by its exact name afterwards: published Tide turns with their checkpoints,
## a Tide @2 second turn that drowns on the sand bar, a room history blob and
## a try count. It never reads or writes this game's own save folder.
const Report = preload("res://tests/playtest_report.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Simulation = preload("res://core/journey/simulation.gd")
const Tide = preload("res://tests/turn_of_the_tide_witness.gd")
const FIXTURES := "res://tests/fixtures/"
const ON_THE_BAR := [["w", [-320, 352]], ["w", [-60, 352]]]

var checks := 0
var failures := 0
var _root := ""

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> bool:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
	return value

func _run() -> void:
	var temp := OS.get_environment("TEMP")
	if temp.is_empty(): temp = OS.get_environment("TMPDIR")
	if temp.is_empty(): temp = "/tmp"
	_root = temp.path_join("ay-playtest-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	var input := _root.path_join("input")
	DirAccess.make_dir_recursive_absolute(input.path_join("history"))
	var hashes := _write_input(input)
	var before := _listing(input)
	_check_refusals()
	var made := Report.report(input)
	_check(_listing(input) == before, "The report leaves its folder exactly as it found it")
	_check_rows(made, hashes)
	var shown := Report.text(made)
	print(shown)
	_check(shown.contains("turn-of-the-tide@2 / set-the-tide") and shown.contains("drowned 1") and shown.contains("stood still longest"), "The printed report names the stage, the drowning and the still spot")
	_remove(_root)
	_check(not DirAccess.dir_exists_absolute(_root), "The temp folder is gone")
	print("PLAYTEST REPORT SUITE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## Writes the input folder; returns the hashes the rows are checked by.
func _write_input(input: String) -> Dictionary:
	for name: String in ["set-the-tide-a", "set-the-tide-b", "set-the-tide-checkpoint", "slack-water-a", "slack-water-b"]:
		_save(input.path_join("tide-1/%s.json" % name), FileAccess.get_file_as_string(FIXTURES + "journey/%s.json" % name))
	# Tide @2: a LOW first turn, then a second spirit left on the sand bar as it shuts.
	var key := "turn-of-the-tide@2"
	var level := Registry.definition(key)
	var initial := Registry.initial_checkpoint(key)
	var a := Simulation.new()
	a.reset(level, "set-the-tide", initial, {}, "a")
	Tide.play(a, Tide.a_routes()["low"])
	var first: Dictionary = Tide.json(a.export_recording())
	var b := Simulation.new()
	_check(b.reset(level, "set-the-tide", initial, first, "b"), "The drowning turn starts")
	Tide.play(b, ON_THE_BAR)
	while not b.finished: b.step({})
	var drowned: Dictionary = Tide.json(b.export_recording())
	_check(not b.snapshot().drowned.is_empty(), "The second spirit drowns on the bar")
	_save(input.path_join("tide-2/turns.json"), JSON.stringify({"first": first, "second": drowned}))
	# A room history blob, exactly as the phone keeps it.
	var vectors: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURES + "history/vectors.json"))
	var record := {"position": 0, "link": vectors.links[0], "digest": vectors.digest, "byte_length": int(vectors.byte_length), "file": "0-%s.bin" % str(vectors.links[0]).left(16)}
	var blob := FileAccess.open(input.path_join("history/" + record.file), FileAccess.WRITE)
	blob.store_buffer(Marshalls.base64_to_raw(vectors.deflate_base64.zlib))
	blob.close()
	_save(input.path_join("history/index.json"), JSON.stringify({"schema_version": 1, "room_id": vectors.room.room_id, "attempts": [record]}))
	var first_tide: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURES + "journey/set-the-tide-a.json"))
	_save(input.path_join("turn-tries.json"), JSON.stringify({"schema_version": 1, "kept": {first_tide.recording_hash: 3}, "reads": {}}))
	return {"tide_a": str(first_tide.recording_hash)}

func _check_refusals() -> void:
	_check(not Report.refusal("").is_empty(), "No folder is refused")
	_check(not Report.refusal(_root.path_join("missing")).is_empty(), "A missing folder is refused")
	_check(not Report.refusal(OS.get_user_data_dir()).is_empty(), "This game's own save folder is refused")
	var saves := _root.path_join("AppData/Roaming/AfterYou")
	DirAccess.make_dir_recursive_absolute(saves)
	_check(not Report.refusal(saves).is_empty(), "A folder that is the game's save folder is refused")
	_check(Report.refusal(_root.path_join("input")).is_empty(), "A folder of copies is read")

func _check_rows(made: Dictionary, hashes: Dictionary) -> void:
	var stages: Dictionary = made.stages
	var drowning: Dictionary = stages.get("turn-of-the-tide@2 / set-the-tide", {})
	_check(drowning.get("b", {}).get("drowned", 0) == 1 and drowning.get("b", {}).get("unfinished", 0) == 1, "The drowned second turn is counted, unfinished: %s" % drowning.get("b", {}))
	_check(int(drowning.get("b", {}).get("closing", 0)) >= 1, "The crossing closing under it is counted")
	_check(drowning.get("a", {}).get("drowned", -1) == 0 and drowning.get("a", {}).get("unfinished", -1) == 0, "The first turn finished dry")
	var set_one: Dictionary = stages.get("turn-of-the-tide@1 / set-the-tide", {})
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURES + "journey/set-the-tide-a.json"))
	_check(set_one.get("a", {}).get("seconds", []) == [snappedf(float(fixture.duration_ticks) / 30.0, 0.1)], "A turn's time is its recorded ticks in seconds")
	_check(set_one.get("a", {}).get("tries", 0) == 3 and set_one.get("a", {}).get("tries_known", 0) == 1, "The kept try count for that turn is read")
	var still: Dictionary = set_one.get("a", {}).get("still", {})
	_check(float(still.get("seconds", 0.0)) > 0.0 and not str(still.get("where", "")).is_empty() and still.get("turn") == hashes.tide_a.left(8), "The longest still spot names its place and turn: %s" % still)
	var slack: Dictionary = stages.get("turn-of-the-tide@1 / slack-water", {})
	_check(slack.get("a", {}).get("turns", 0) == 1 and slack.get("b", {}).get("turns", 0) == 1, "The second stage's turns replay from the first stage's checkpoint")
	_check(int(made.blobs) == 1 and stages.keys().any(func(name: String) -> bool: return name.begins_with("relay-isles@2")), "The history blob is read through its check")
	_check(made.notes.any(func(note: String) -> bool: return note.contains("relay-isles") and note.contains("time only")), "Turns of a family not replayed here still report their time")
	_check(not made.notes.any(func(note: String) -> bool: return note.contains("turn-of-the-tide")), "Every Tide turn replays: %s" % [made.notes])
	_check(int(made.replayed) == 6, "Six Tide turns replay (%d)" % made.replayed)

func _save(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()

func _listing(folder: String) -> Array:
	var result: Array = []
	for path: String in Report._files(folder):
		result.append([path, FileAccess.get_file_as_bytes(path).size(), FileAccess.get_modified_time(path)])
	return result

## Removes only what this suite made, under its own folder.
func _remove(folder: String) -> void:
	if not folder.get_file().begins_with("ay-playtest-"): return
	for child: String in DirAccess.get_directories_at(folder): _remove_tree(folder.path_join(child))
	for file: String in DirAccess.get_files_at(folder): DirAccess.remove_absolute(folder.path_join(file))
	DirAccess.remove_absolute(folder)

func _remove_tree(folder: String) -> void:
	for child: String in DirAccess.get_directories_at(folder): _remove_tree(folder.path_join(child))
	for file: String in DirAccess.get_files_at(folder): DirAccess.remove_absolute(folder.path_join(file))
	DirAccess.remove_absolute(folder)
