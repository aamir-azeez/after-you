extends SceneTree
## turn-of-the-tide@2 is offered in @1's place. @1 stays loadable for its saves,
## replays and rooms; progress made in either version counts for both (Home's
## places, the chapter marks, hard unlocks and hard marks); a room is hosted at
## @1 while the server cannot create @2, hard rooms included.
const Registry = preload("res://services/chapter_registry.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Journey = preload("res://services/relay_journey.gd")
const Keepsakes = preload("res://services/home_keepsake_catalog.gd")
const Completion = preload("res://presentation/chapter_completion.gd")
const Thumbnails = preload("res://services/chapter_thumbnail_catalog.gd")
const HardMode = preload("res://services/hard_mode.gd")
const ChapterPicker = preload("res://presentation/chapter_picker.gd")
const Main = preload("res://main.gd")
const V1 := "turn-of-the-tide@1"
const V2 := "turn-of-the-tide@2"
## The hashes the server pins (backend/src/v2/protocol-journey.ts).
const HASH_V1 := "3a6d111455aa69e60c440cc6f04a0656292ed9c40b31c66a7f999c85cd2a911a"
const HASH_V2 := "1f88aabb592fbf14640b50dd0644755d6afe522cae39d844524ac68b491f0a43"
const PLACES := ["turn-of-the-tide/set-the-tide", "turn-of-the-tide/slack-water"]
var checks := 0
var failures := 0
var paths: Array[String] = []

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	_registry()
	_keepsakes()
	_hard()
	_hosting()
	for path: String in paths:
		for suffix: String in ["", ".tmp", ".backup"]:
			if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	print("TURN OF THE TIDE VERSIONS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _registry() -> void:
	var v1 := Registry.descriptor(V1)
	var v2 := Registry.descriptor(V2)
	print("TIDE V2 DEFINITION HASH " + Canonical.digest(Registry.definition(V2)))
	_check(Canonical.digest(Registry.definition(V1)) == HASH_V1 and v1.definition_hash == HASH_V1, "@1 keeps its published hash")
	_check(Canonical.digest(Registry.definition(V2)) == HASH_V2 and v2.definition_hash == HASH_V2, "@2 is the definition the server pins")
	_check(Registry.keys().has(V1) and Registry.keys().has(V2), "Both versions stay loadable")
	_check(V1 not in Registry.offered_keys() and V2 in Registry.offered_keys() and Registry.offered_key(V1) == V2 and Registry.offered_key(V2) == V2, "Only @2 is offered; @1 maps to it")
	_check(V1 not in Registry.UNRELEASED and V2 not in Registry.UNRELEASED, "Neither version is held back")
	_check(Registry.resolve(v1) == V1 and Registry.resolve(v2) == V2, "Each version resolves to its own key, so @1 rooms still open")
	_check(v2.local_path != v1.local_path and v1.local_path == "user://turn-of-the-tide-journey-v1.json", "@2 keeps its own journal and @1's is unchanged")
	_check(not v2.premium and v2.premium == v1.premium and v2.title == v1.title and v2.stage_count == v1.stage_count, "@2 is the same free chapter, title and length")
	_check(Thumbnails.path(V2) == Thumbnails.path(V1) and not Thumbnails.path(V2).is_empty(), "@2 reuses the chapter thumbnail")
	_check(Main._own_solo_card(V2) and ChapterPicker.entry(V2).mark == V2, "Play Solo has an @2 card marked under its own key")
	var shared := Journey.new(v1.local_path, null, V2)
	shared.load_data()
	_check(shared.read_only, "@2 never writes into the @1 journal")

func _keepsakes() -> void:
	_check(Keepsakes.chapter_places(V2) == PLACES and Keepsakes.chapter_places(V1) == PLACES, "@2 earns @1's two places")
	_check(Keepsakes.all().all(func(item: Dictionary) -> bool: return item.chapter_key != V2), "@2 adds no places of its own")
	_check(V1 in Keepsakes.CHAPTERS and V2 in Keepsakes.CHAPTERS, "Home reads both journals for the places")
	_check(Keepsakes.local_path(V2) == Registry.descriptor(V2).local_path and Keepsakes.local_path(V1) == Registry.descriptor(V1).local_path, "Each version's places back-fill from its own journal")
	for mode: String in ["solo", "friend"]:
		var earned: Array[Dictionary] = []
		for id: String in PLACES: earned.append({"id": id, "solo": mode == "solo", "friend": mode == "friend"})
		var marks := Completion.chapters(earned)
		_check(bool(marks.get(V2, {}).get(mode, false)) and bool(marks.get(V1, {}).get(mode, false)), "Finishing either version %s marks both cards" % mode)

func _hard() -> void:
	_check(HardMode.eligible(V2) and HardMode.eligible(V1), "Both versions have hard plays: @1 for a room hosted at @1")
	_check(V2 in HardMode.eligible_keys() and V1 not in HardMode.eligible_keys(), "The chapter is counted once, as @2")
	var none: Array[Dictionary] = []
	_check(not HardMode.unlocked(Completion.chapters(none), V2), "Hard stays locked before the chapter is finished")
	var earned: Array[Dictionary] = []
	for id: String in PLACES: earned.append({"id": id, "solo": true, "friend": false})
	var marks := Completion.chapters(earned)
	_check(HardMode.unlocked(marks, V2) and HardMode.unlocked(marks, V1), "A chapter finished in @1 unlocks hard in both versions")
	var entries: Array[Dictionary] = [ChapterPicker.entry(V2)]
	var cards := HardMode.picker_entries(entries, marks)
	_check(cards.size() == 1 and not cards[0].locked, "Play Solo with Hard on shows the @2 card open")
	var marks_path := "user://tide-versions-hard-%d.json" % Time.get_ticks_usec()
	paths.append(marks_path)
	var file := FileAccess.open(marks_path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"schema_version": HardMode.VERSION, "marks": {V1: {"solo": true, "together": false}}}))
	file.close()
	var store := HardMode.new(marks_path)
	_check(store.completed(V2, HardMode.SOLO) and store.completed(V1, HardMode.SOLO) and not store.completed(V2, HardMode.TOGETHER), "A hard mark kept under @1 counts for @2")
	var states := store.states(marks)
	_check(states.get(V2, {}).get(HardMode.SOLO) == HardMode.DONE and states.get(V1, {}).get(HardMode.SOLO) == HardMode.DONE and states.get(V2, {}).get(HardMode.TOGETHER) == HardMode.OPEN, "The hard marks read the same under either key")
	_check(store.record(V1, HardMode.TOGETHER) and HardMode.new(marks_path).completed(V2, HardMode.TOGETHER), "A hard room finished at @1 marks @2")
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(marks_path))
	_check(saved is Dictionary and saved.marks.keys() == [V2], "Marks are kept under the offered version only: " + str(saved))

func _hosting() -> void:
	var none := func(_key: String) -> bool: return false
	var only_v1 := func(key: String) -> bool: return key == V1
	var both := func(key: String) -> bool: return key in [V1, V2]
	var offered := Registry.offered_key(V1)
	_check(Registry.hosting_key(offered, only_v1) == V1, "A server without @2 hosts @1")
	_check(Registry.hosting_key(offered, both) == V2, "A server with @2 hosts @2")
	_check(Registry.hosting_key(offered, none) == V2, "A server with neither keeps @2, shown as unavailable")

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
