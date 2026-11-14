extends SceneTree
## A tester's own test codes on the phone (services/tester_switches.gd): each code's action, the
## same code again, per player, kept across a restart, and that no gameplay record is written.
const Switches = preload("res://services/tester_switches.gd")
const Catalog = preload("res://services/home_keepsake_catalog.gd")
const HardMode = preload("res://services/hard_mode.gd")
const HomeKeepsakes = preload("res://services/home_keepsakes.gd")
const ChapterUnlocks = preload("res://services/chapter_unlocks.gd")
const KeepsakeStates = preload("res://services/home_keepsake_states.gd")
const ChapterAccess = preload("res://services/chapter_access.gd")
const Tester = preload("res://services/tester_access.gd")
const AtomicFile = preload("res://services/atomic_file.gd")
const SERVER := "https://switches.test"
## Synthetic ids only.
const OWNER := "SSSSSSSSSSSSSSSSSSSSSS"
const OTHER := "TTTTTTTTTTTTTTTTTTTTTT"

var checks := 0
var failures := 0
var directory := ""
var signed_in := OWNER

func _initialize() -> void: _run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)

func _run() -> void:
	directory = "user://tester-switches-test-" + Crypto.new().generate_random_bytes(8).hex_encode()
	DirAccess.make_dir_recursive_absolute(directory)
	_keepsake_codes()
	_fresh_view_hears_play()
	_full_journey_switch()
	_run_export_switch()
	_kept_and_scoped()
	_damaged_file()
	_observers()
	_scope_outlives_main()
	_hard_picker_view()
	await _chapter_access_holds()
	_tester_replies()
	_restore()
	print("AFTER YOU TESTER SWITCHES: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _store(label: String) -> RefCounted:
	var store: RefCounted = Switches.new(directory.path_join(label + ".json"))
	store.scope_source = func() -> Dictionary: return {"server": SERVER, "owner": signed_in} if not signed_in.is_empty() else {}
	return store

## Real marks a player might have: First Steps' first place solo, and First Steps' solo Hard mark.
func _real_earned() -> Array[Dictionary]:
	var item: Dictionary = Catalog.all()[0]
	item.solo = true
	item.friend = false
	return [item]

func _keepsake_codes() -> void:
	var store := _store("codes")
	var real := _real_earned()
	var real_hard := {"first-steps@1": {"solo": true, "together": false}}
	check(store.earned(real) == real and store.hard(real_hard) == real_hard, "With no switch the real marks show")
	var before: int = store.generation
	check(store.apply("grant_keepsakes") == {"ok": true, "state": "all"}, "The grant code shows every keepsake")
	check(store.generation > before, "and moves the generation on, so Home builds again")
	var all: Array[Dictionary] = store.earned(real)
	check(all.size() == Catalog.all().size(), "Every keepsake place is earned: %d of %d" % [all.size(), Catalog.all().size()])
	check(all.all(func(item: Dictionary) -> bool: return item.solo and item.friend == bool(item.get("friend_available", true))), "solo, and with a friend wherever a place has a friend variant")
	var hard: Dictionary = store.hard(real_hard)
	check(hard.size() == HardMode.eligible_keys().size() and hard.values().all(func(mark: Dictionary) -> bool: return mark.solo and mark.together), "Both Hard marks of every chapter that has them")
	var states: Dictionary = KeepsakeStates.states(KeepsakeStates.entries(false), all, hard, true)
	check(states.keepsakes[0] == states.keepsakes[1] and states.upgrades[0] == states.upgrades[1] and states.hard[0] == states.hard[1], "Home counts every keepsake, upgrade and Hard mark: %s" % [states])
	var unlocks: Dictionary = ChapterUnlocks.progress(all, hard, {}, true, [])
	check(ChapterUnlocks.chain().all(func(key: String) -> bool: return ChapterUnlocks.reached(key, unlocks)), "and every chapter in the chain is open")
	check(store.apply("grant_keepsakes") == {"ok": true, "state": "real"}, "The same code again goes back to the real marks")
	check(store.earned(real) == real and store.hard(real_hard) == real_hard, "which show unchanged")
	check(store.apply("reset_keepsakes") == {"ok": true, "state": "fresh"}, "The reset code shows a fresh Home")
	check(store.earned(real).is_empty() and store.hard(real_hard).is_empty(), "with no keepsake and no Hard mark")
	var fresh: Dictionary = ChapterUnlocks.progress(store.earned(real), store.hard(real_hard), {}, true, [])
	check(ChapterUnlocks.reached(ChapterUnlocks.chain()[0], fresh) and not ChapterUnlocks.reached(ChapterUnlocks.chain()[1], fresh), "and only the first chapter open")
	var in_room: String = ChapterUnlocks.chain()[2]
	var touched: Dictionary = ChapterUnlocks.touched([in_room], false)
	check(touched == {in_room: true}, "A fresh view keeps the chapter of a room the player is in, and reads no journal: %s" % [touched])
	var with_room: Dictionary = ChapterUnlocks.progress(store.earned(real), store.hard(real_hard), touched, true, [])
	check(ChapterUnlocks.reached(in_room, with_room) and not ChapterUnlocks.reached(ChapterUnlocks.chain()[1], with_room), "so a friend waiting there is never locked out, and nothing else opens")
	check(store.apply("grant_keepsakes").state == "all", "The other code switches straight over")
	check(store.apply("reset_keepsakes").state == "fresh" and store.earned(real).is_empty(), "and back, fresh again")
	check(store.apply("reset_keepsakes").state == "real" and store.earned(real) == real, "The reset code again shows the real marks: nothing was lost")
	check(store.apply("something_else") == {"ok": false, "state": ""}, "An unknown action changes nothing")
	signed_in = ""
	check(not store.apply("grant_keepsakes").ok and store.earned(real) == real, "Without a signed-in player nothing switches")
	signed_in = OWNER

func _fresh_view_hears_play() -> void:
	var store := _store("fresh")
	var none: Array[Dictionary] = []
	var places := Catalog.chapter_places(Catalog.CHAPTERS[0])
	store.note_award(places.slice(0, 1), "solo")
	check(store.earned(none).is_empty(), "Play is not kept while the view is real")
	store.apply("reset_keepsakes")
	store.note_award(places.slice(0, 1), "solo")
	store.note_award(["not-a-place", 7], "solo")
	store.note_award(places.slice(0, 1), "elsewhere")
	var shown: Array[Dictionary] = store.earned(none)
	check(shown.size() == 1 and shown[0].id == places[0] and shown[0].solo and not shown[0].friend, "A fresh view shows a place play records from then on, and nothing unknown: %s" % [shown])
	store.note_hard(HardMode.eligible_keys()[0], HardMode.SOLO)
	store.note_hard(HardMode.eligible_keys()[0], "sideways")
	check(store.hard({}) == {HardMode.eligible_keys()[0]: {"solo": true, "together": false}}, "and a Hard play finished from then on")
	store.apply("reset_keepsakes")
	store.apply("reset_keepsakes")
	check(store.earned(none).is_empty() and store.hard({}).is_empty(), "A fresh view switched on again starts empty")

func _full_journey_switch() -> void:
	var store := _store("journey")
	check(not store.full_journey_off(), "Full Journey is on by default")
	check(store.apply("full_journey_off") == {"ok": true, "state": "off"} and store.full_journey_off(), "The server's off answer switches it off")
	check(store.apply("full_journey_on") == {"ok": true, "state": "on"} and not store.full_journey_off(), "and its on answer back on")
	store.note_full_journey(SERVER, OWNER, true)
	check(store.full_journey_off(), "A capabilities read saying off switches it off")
	var generation: int = store.generation
	store.note_full_journey(SERVER, OWNER, true)
	check(store.generation == generation, "An unchanged read writes nothing")
	store.note_full_journey(SERVER, OWNER, false)
	check(not store.full_journey_off(), "A read without it switches it back on")
	store.note_full_journey(SERVER, OTHER, true)
	check(not store.full_journey_off(), "Another player's read changes nothing for this one")

## Export this run follows each capabilities read for its own player, beside the other switches.
func _run_export_switch() -> void:
	var store := _store("export")
	check(not store.run_export(), "Nobody may export runs by default")
	store.note_run_export(SERVER, OWNER, true)
	check(store.run_export() and _store("export").run_export(), "A read that allows it is kept across a restart")
	var generation: int = store.generation
	store.note_run_export(SERVER, OWNER, true)
	check(store.generation == generation, "An unchanged read writes nothing")
	store.note_full_journey(SERVER, OWNER, true)
	check(store.run_export() and store.full_journey_off(), "It sits beside the Full Journey switch")
	store.note_run_export(SERVER, OTHER, true)
	signed_in = OTHER
	check(store.run_export() and not store.full_journey_off(), "Each player has their own")
	signed_in = OWNER
	store.note_run_export(SERVER, OWNER, false)
	check(not store.run_export() and store.full_journey_off(), "A read without it takes only it away")

func _kept_and_scoped() -> void:
	var store := _store("kept")
	store.apply("grant_keepsakes")
	store.apply("full_journey_off")
	var again := _store("kept")
	check(again.keepsakes() == Switches.ALL and again.full_journey_off(), "A restart keeps both switches")
	signed_in = OTHER
	check(again.keepsakes().is_empty() and not again.full_journey_off() and again.earned(_real_earned()) == _real_earned(), "Another player on the phone sees their own marks and Full Journey")
	signed_in = OWNER
	check(again.clear_owner(OWNER) and again.keepsakes().is_empty() and not again.full_journey_off(), "Account deletion forgets the switches")
	check(_store("kept").keepsakes().is_empty(), "on disk too")

func _damaged_file() -> void:
	var path := directory.path_join("damaged.json")
	for bad: Variant in ["{not json", {"schema_version": 2, "scopes": {}}, {"schema_version": 1, "scopes": {SERVER + "|" + OWNER: {"keepsakes": "everything"}}},
			{"schema_version": 1, "scopes": {SERVER + "|" + OWNER: {"keepsakes": "all", "earned": {}}}}, {"schema_version": 1, "scopes": {SERVER + "|" + OWNER: {"full_journey_off": "yes"}}}, {"schema_version": 1, "scopes": {SERVER + "|" + OWNER: {"run_export": "yes"}}}]:
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(bad if bad is String else JSON.stringify(bad))
		file.close()
		var store := _store("damaged")
		check(store.keepsakes().is_empty() and not store.full_journey_off() and not store.run_export(), "A damaged or unexpected file shows the real marks: %s" % [bad])
		AtomicFile.remove(path)
		AtomicFile.remove_unreadable(path)

func _observers() -> void:
	var heard: Array = []
	HomeKeepsakes.award_observer = func(ids: Array, variant: String) -> void: heard.append([ids, variant])
	var places := Catalog.chapter_places(Catalog.CHAPTERS[0])
	HomeKeepsakes.record_solo_prefix(Catalog.CHAPTERS[0], 1)
	HomeKeepsakes.record_solo_prefix(Catalog.CHAPTERS[0], 0)
	check(heard == [[[places[0]], "solo"]], "The keepsake observer hears each award gameplay records, and no empty one: %s" % [heard])
	HomeKeepsakes.award_observer = Callable()
	HomeKeepsakes._unclaimed.clear()
	var hard_heard: Array = []
	HardMode.record_observer = func(key: String, mode: String) -> void: hard_heard.append([key, mode])
	var marks := HardMode.new(directory.path_join("hard-marks.json"))
	marks.record(HardMode.eligible_keys()[0], HardMode.SOLO)
	check(hard_heard.is_empty(), "Only the phone's own marks file is heard")
	HardMode.record_observer = Callable()

## A chapter screen replaces Main, whose scope_source then goes invalid: awards recorded there
## still count for the player Main last had signed in.
func _scope_outlives_main() -> void:
	var store: RefCounted = Switches.new(directory.path_join("outlive.json"))
	store.scope_source = func() -> Dictionary: return {"server": SERVER, "owner": OWNER}
	store.apply("reset_keepsakes")
	var gone := Node.new()
	store.scope_source = Callable(gone, "get_name")
	gone.free()
	check(not store.scope_source.is_valid(), "The scope source is gone, as Main's is while a chapter shows")
	var places := Catalog.chapter_places(Catalog.CHAPTERS[0])
	store.note_award(places.slice(0, 2), "solo")
	var none: Array[Dictionary] = []
	check(store.earned(none).size() == 2, "An award recorded meanwhile counts for the player last signed in")

## The Hard menus read the switched marks, as Home does (Main.hard_states).
func _hard_picker_view() -> void:
	var path := directory.path_join("hard-picker.json")
	var real := HardMode.new(path)
	real.record(HardMode.eligible_keys()[0], HardMode.SOLO)
	var key: String = HardMode.eligible_keys()[0]
	var shown: RefCounted = HardMode.new(path).showing({})
	check(shown.states({key: {"solo": true, "friend": false}})[key][HardMode.SOLO] == HardMode.OPEN, "A fresh view shows a real Hard clear as not done")
	check(not shown.record(key, HardMode.TOGETHER), "and a view records nothing")
	check(not HardMode.new(path).completed(key, HardMode.TOGETHER), "so the file is unchanged")
	var all: RefCounted = HardMode.new(path).showing({key: {"solo": true, "together": true}})
	check(all.states({})[key][HardMode.TOGETHER] == HardMode.DONE, "and the all view shows every Hard play done")
	check(HardMode.new(path).completed(key, HardMode.SOLO), "while the real mark stays on disk")

func _chapter_access_holds() -> void:
	var store := _store("access")
	Switches.use_shared(store)
	store.apply("full_journey_off")
	var access: Node = ChapterAccess.new()
	access.tester_access_factory = func() -> Node:
		check(false, "A switched-off tester never reaches the tester receipt")
		return Node.new()
	root.add_child(access)
	access.check_access()
	check(access.state == "hold" and access.reason == "purchase_required", "A paid scene holds a switched-off tester as it holds a free player: %s %s" % [access.state, access.reason])
	access.queue_free()
	await process_frame
	Switches.use_shared(null)

func _tester_replies() -> void:
	for action: String in Switches.ACTIONS:
		check(Tester._test_action({"schema_version": 1, "player_id": OWNER, "test_action": action}, OWNER), "The tester code service takes the %s answer" % action)
	for bad: Dictionary in [{"schema_version": 1, "player_id": OTHER, "test_action": "grant_keepsakes"}, {"schema_version": 1, "player_id": OWNER, "test_action": "grant_everything"},
			{"schema_version": 2, "player_id": OWNER, "test_action": "grant_keepsakes"}, {"schema_version": 1, "player_id": OWNER, "test_action": "grant_keepsakes", "extra": true}]:
		check(not Tester._test_action(bad, OWNER), "and refuses an answer for someone else, unknown or malformed: %s" % [bad])

func _restore() -> void:
	HomeKeepsakes.award_observer = Callable()
	HardMode.record_observer = Callable()
	Switches.use_shared(null)
	for name: String in DirAccess.get_files_at(directory): DirAccess.remove_absolute(ProjectSettings.globalize_path(directory.path_join(name)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(directory))
