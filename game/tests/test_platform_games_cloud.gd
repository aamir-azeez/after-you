extends SceneTree
## Cloud save sync with a fake Saved Games slot and fake sources: debounce to quiet moments,
## offline and signed-out runs stay due, conflicts resolve to the join of every copy, a copy this
## build cannot read is never overwritten, nothing is written when the cloud already has it all,
## and nothing runs when nothing changed. Then the real sources: what applies, and what never does.
const Sync = preload("res://services/platform_games/cloud_save_sync.gd")
const Bundle = preload("res://services/platform_games/cloud_save_bundle.gd")
const State = preload("res://services/platform_games/platform_games_state.gd")
const Sources = preload("res://services/platform_games/cloud_save_sources.gd")
const LocalSave = preload("res://services/local_save.gd")
const HomeKeepsakes = preload("res://services/home_keepsakes.gd")
const Catalog = preload("res://services/home_keepsake_catalog.gd")
const Levels = preload("res://core/levels.gd")
const Registry = preload("res://services/chapter_registry.gd")
const RelayJourney = preload("res://services/relay_journey.gd")
const Retained = preload("res://tests/retained_chapter_fixture.gd")

class Slot extends "res://services/platform_games/games_provider.gd":
	var data := PackedByteArray()
	var conflicts: Array = []
	var offline := false
	var failure := ""
	## Called while the slot is open, as if the player finished something during the network wait.
	var during_open: Callable
	var opens := 0
	var commits := 0
	var discards := 0
	var resolves := 0
	func open_answer() -> Dictionary:
		var answer := {"ok": true, "handle": "0".repeat(32), "data": data}
		if not conflicts.is_empty(): answer.conflict = {"data": conflicts.pop_front()}
		return answer
	func snapshot_open(_name: String) -> Dictionary:
		opens += 1
		if offline: return {"ok": false, "code": "offline"}
		if not failure.is_empty(): return {"ok": false, "code": failure}
		if during_open.is_valid(): during_open.call()
		return open_answer()
	func snapshot_resolve(_handle: String, bytes: PackedByteArray) -> Dictionary:
		resolves += 1
		data = bytes
		return open_answer()
	func snapshot_commit(_handle: String, bytes: PackedByteArray, _description: String) -> Dictionary:
		commits += 1
		data = bytes
		return {"ok": true}
	func snapshot_discard(_handle: String) -> Dictionary:
		discards += 1
		return {"ok": true}

class FakeSources extends RefCounted:
	var bundle: Dictionary
	var applied: Array = []
	var is_ready := true
	var home := true
	var stamp_value := "s1"
	func ready() -> bool: return is_ready
	func at_home() -> bool: return home
	func stamp() -> String: return stamp_value
	func collect() -> Dictionary: return bundle.duplicate(true)
	func apply(merged: Dictionary) -> bool:
		applied.append(merged.duplicate(true))
		bundle = Bundle.merge(bundle, merged)
		return true

var checks := 0
var failures := 0
var now := 1000

func _initialize() -> void: _run.call_deferred()

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _bundle(completed: Array, keepsakes: Dictionary = {}, stamp: int = 0, sound: bool = true) -> Dictionary:
	var marks := {}
	for id: String in completed: marks[id] = true
	return Bundle.collect({"settings": {"sound": sound}, "completed": marks, "replays": {}}, stamp, keepsakes, {})

func _sync(slot: RefCounted, sources: RefCounted, state: RefCounted) -> RefCounted:
	var sync: RefCounted = Sync.new(slot, sources, state)
	sync.clock_ms = func() -> int: return now
	return sync

func _run() -> void:
	var dir := "user://platform-games-cloud-test-%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(dir)
	var state: RefCounted = State.new(dir.path_join("state.json"))

	# The server's answer: "off" is asked again within a quarter of an hour, "on" after a day.
	var t0 := 1_800_000_000_000
	state.remember_capability({"play_games": false, "game_center": false}, t0)
	_check(not state.capability(t0 + 60_000).is_empty(), "An off answer holds for a minute")
	_check(state.capability(t0 + State.OFF_CAPABILITY_TTL_MS + 1).is_empty(), "An off answer is asked again after a quarter of an hour, so a switch turned on reaches the next launch")
	state.remember_capability({"play_games": true, "web_client_id": "665737720520-abcdefgh.apps.googleusercontent.com"}, t0)
	_check(not state.capability(t0 + State.OFF_CAPABILITY_TTL_MS + 1).is_empty(), "An on answer holds past a quarter of an hour")
	_check(state.capability(t0 + State.CAPABILITY_TTL_MS + 1).is_empty(), "An on answer is asked again after a day")
	state.forget_capability()

	# Debounce: a note waits for a quiet moment; flush runs at once.
	var slot := Slot.new()
	var sources := FakeSources.new()
	sources.bundle = _bundle(["first-light"])
	var sync := _sync(slot, sources, state)
	sync.note()
	_check(not sync.due(), "A progress note does not sync at once")
	now += Sync.DEBOUNCE_MS - 1
	_check(not sync.due(), "Nor just before the quiet moment ends")
	now += 1
	_check(sync.due(), "It is due once things settle")
	sync.note()
	_check(not sync.due(), "Another note moves the moment on, so a burst of taps is one sync")
	sync.flush()
	_check(sync.due(), "Flush runs at once")
	var first: Dictionary = await sync.run()
	_check(first.ok and first.wrote and slot.commits == 1 and Bundle.decode(slot.data).completed.has("first-light"), "The first run writes this phone's progress to an empty slot")
	# Nothing changed: no slot is even opened.
	var opens := slot.opens
	sync.flush()
	var idle: Dictionary = await sync.run()
	_check(idle.ok and not idle.wrote and slot.opens == opens, "No change since the last sync: no work at all")
	# A pull still reads the slot when asked (another phone may have played).
	sync.flush(true)
	var pulled: Dictionary = await sync.run()
	_check(pulled.ok and slot.opens == opens + 1 and not pulled.wrote and slot.discards == 1, "A pull reads, finds nothing new and writes nothing")

	# Another phone's progress arrives: applied here, and the cloud keeps the union.
	slot.data = Bundle.encode(Bundle.merge(Bundle.decode(slot.data), _bundle(["long-way-home"], {"relay/x": {"solo": true, "friend": false}})))
	sync.flush(true)
	var joined: Dictionary = await sync.run()
	_check(joined.ok and joined.applied and sources.bundle.completed.has("long-way-home") and sources.bundle.keepsakes.has("relay/x"), "Cloud progress is applied to this phone")
	_check(not joined.wrote, "Nothing is written back when the cloud already holds everything")

	# Offline: the run fails and stays due, with the pull kept.
	slot.offline = true
	sources.stamp_value = "s2"
	sync.flush(true)
	var offline: Dictionary = await sync.run()
	_check(not offline.ok and offline.code == "offline" and not sync.due(), "Offline fails quietly and backs off")
	now += Sync.DEBOUNCE_MS * 3
	_check(sync.due(), "and tries again later")
	slot.offline = false
	sources.bundle = Bundle.merge(sources.bundle, _bundle(["rising-together"]))
	var back: Dictionary = await sync.run()
	_check(back.ok and back.wrote and Bundle.decode(slot.data).completed.has("rising-together"), "Back online, the queued progress is written")

	# Not ready (a chapter is open, or a save is held): nothing is read or written, and it stays due.
	sources.is_ready = false
	sync.flush()
	opens = slot.opens
	var held: Dictionary = await sync.run()
	_check(not held.ok and slot.opens == opens, "Held sources stop the run before the slot")
	now += Sync.DEBOUNCE_MS
	_check(sync.due(), "and the run is due again later")
	sources.is_ready = true
	# Away from Home (a chapter open in Main's place, or a room): no run at all.
	sources.home = false
	sync.flush(true)
	opens = slot.opens
	var away: Dictionary = await sync.run()
	_check(not away.ok and slot.opens == opens, "Nothing runs away from Home")
	sources.home = true
	now += Sync.DEBOUNCE_MS
	await sync.run()
	# Progress made while the slot was open is not marked synced: the run is due again.
	sources.bundle = Bundle.merge(sources.bundle, _bundle(["two-beats"]))
	sources.stamp_value = "s3"
	slot.during_open = func() -> void: sources.stamp_value = "s4"
	sync.flush()
	var moving: Dictionary = await sync.run()
	_check(not moving.ok and moving.code == "changed" and state.cloud("dirty") == true and Bundle.decode(slot.data).completed.has("two-beats"), "A change during the run keeps it due, and what was collected is still written")
	slot.during_open = Callable()
	now += Sync.DEBOUNCE_MS
	_check(sync.due(), "so it runs again after a quiet moment")
	var caught_up: Dictionary = await sync.run()
	_check(caught_up.ok and state.cloud("dirty") == false, "and then settles")
	# Saved Games off in the console (or no iCloud): no retry loop until the next sign-in.
	slot.failure = "not_configured"
	sync.flush(true)
	var off: Dictionary = await sync.run()
	now += Sync.BACKOFF_CAP_MS
	_check(not off.ok and not sync.due(), "A setup problem waits for the next sign-in")
	slot.failure = ""
	sync.flush(true)
	_check(sync.due(), "and a sign-in tries again")
	await sync.run()
	# Repeated failures back off, capped.
	slot.offline = true
	var waits: Array = []
	for attempt in range(8):
		sources.stamp_value = "backoff-%d" % attempt
		sync.flush()
		var before_ms := now
		await sync.run()
		var wait := 0
		while not sync.due() and wait < Sync.BACKOFF_CAP_MS * 2:
			now += 1000
			wait += 1000
		waits.append(now - before_ms)
	slot.offline = false
	_check(waits[1] > waits[0] and waits[-1] <= Sync.BACKOFF_CAP_MS + 1000, "Failures back off and the wait is capped")
	sync.flush(true)
	await sync.run()

	# A conflict: this phone, the cloud and the other copy all join; nothing is lost.
	var slot2 := Slot.new()
	slot2.data = Bundle.encode(_bundle(["first-light"], {}, 10, false))
	slot2.conflicts = [Bundle.encode(_bundle(["patient-garden"], {"relay/y": {"solo": false, "friend": true}}, 20, true))]
	var sources2 := FakeSources.new()
	sources2.bundle = _bundle(["across-the-blue"], {}, 5, true)
	var state2: RefCounted = State.new(dir.path_join("state2.json"))
	var sync2 := _sync(slot2, sources2, state2)
	sync2.flush()
	var resolved: Dictionary = await sync2.run()
	var cloud := Bundle.decode(slot2.data)
	_check(resolved.ok and slot2.resolves == 1 and slot2.commits == 1, "A conflict is resolved, then the join is committed")
	_check(cloud.completed.keys().size() == 3 and cloud.keepsakes.has("relay/y"), "The resolved copy keeps every copy's progress")
	_check(cloud.settings.stamp == 20 and cloud.settings.values.sound == true, "The newest settings win the conflict")
	_check(sources2.bundle.completed.has("first-light") and sources2.bundle.completed.has("patient-garden"), "This phone gets the other copies' progress")
	# A conflict that keeps coming back is given up, not looped.
	var slot3 := Slot.new()
	slot3.data = Bundle.encode(_bundle(["first-light"]))
	for index in range(Sync.MAX_RESOLVE_ROUNDS + 2): slot3.conflicts.append(Bundle.encode(_bundle(["first-light"])))
	var sync3 := _sync(slot3, sources2, State.new(dir.path_join("state3.json")))
	var looping: Dictionary = await sync3.run()
	_check(not looping.ok and looping.code == "conflict_unresolved" and slot3.discards == 1, "Endless conflicts stop after a few rounds")

	# A copy this build cannot read (a newer app) is never overwritten.
	var slot4 := Slot.new()
	var future := _bundle(["first-light"])
	future.schema_version = 2
	slot4.data = Bundle.encode(future)
	var before := slot4.data.duplicate()
	var sync4 := _sync(slot4, sources2, State.new(dir.path_join("state4.json")))
	var unreadable: Dictionary = await sync4.run()
	_check(not unreadable.ok and unreadable.code == "cloud_unreadable" and slot4.data == before and slot4.commits == 0, "An unreadable cloud copy is left exactly as it was")
	var slot5 := Slot.new()
	slot5.data = Bundle.encode(_bundle(["first-light"]))
	slot5.conflicts = ["junk".to_utf8_buffer()]
	var sync5 := _sync(slot5, sources2, State.new(dir.path_join("state5.json")))
	var junk: Dictionary = await sync5.run()
	_check(not junk.ok and slot5.resolves == 0 and slot5.commits == 0, "Never resolve a conflict over a copy this build cannot read")

	await _sources_apply(dir)

	for name: String in DirAccess.get_files_at(dir): DirAccess.remove_absolute(dir.path_join(name))
	DirAccess.remove_absolute(dir)
	print("PLATFORM GAMES CLOUD: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _fixture(folder: String, name: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(("res://tests/fixtures/" + folder).path_join(name + ".json")))

class FakeMain extends Node:
	var saves: RefCounted
	var home_keepsakes: RefCounted
	var mode := "home"
	var applied_settings := 0
	func _apply_settings() -> void: applied_settings += 1

## The real sources against temp files: what applies through the owners, and what never does.
func _sources_apply(dir: String) -> void:
	var host := FakeMain.new()
	root.add_child(host)
	host.saves = LocalSave.new(dir.path_join("journey.json"))
	host.saves.load_data()
	host.saves.update_values({"completed": {Levels.IDS[0]: true}})
	host.home_keepsakes = HomeKeepsakes.new(dir.path_join("keepsakes.json"))
	host.home_keepsakes.load_data()
	var state: RefCounted = State.new(dir.path_join("sources-state.json"))
	var sources: RefCounted = Sources.new(host, state)
	sources.journal_paths = {}
	sources.staging = dir.path_join("staging")
	var local: Dictionary = await sources.collect()
	_check(local.completed.has(Levels.IDS[0]) and local.settings.stamp == 0, "Untouched default settings collect with stamp 0")
	var place: String = Catalog.all()[0].id
	var remote := Bundle.empty()
	remote.completed = {Levels.IDS[1]: true, "not-a-level": true}
	remote.replays = {Levels.IDS[1]: {"a": {"x": 1}, "b": {}, "draft": {}}}
	remote.keepsakes = {place: {"solo": true, "friend": false}, "nowhere/at-all": {"solo": true, "friend": false}}
	remote.settings = {"values": {"sound": false, "haptics": false}, "stamp": 50}
	var merged := Bundle.merge(local, remote)
	host.mode = "play"
	_check(not await sources.apply(merged), "Nothing applies away from Home")
	host.mode = "home"
	_check(await sources.apply(merged), "At Home the merged copy applies")
	_check(host.saves.data.completed.has(Levels.IDS[1]) and not host.saves.data.completed.has("not-a-level"), "Only known levels are marked finished")
	_check(host.saves.data.replays.has(Levels.IDS[1]) and host.saves.data.replays[Levels.IDS[1]].keys().size() == 3, "A finished island's replay arrives in the save's own shape")
	_check(host.saves.data.settings.sound == false and host.applied_settings == 1, "Newer settings apply and take effect")
	_check(host.saves.data.settings.graphics_quality == LocalSave.defaults().settings.graphics_quality, "Device settings are untouched")
	_check(host.home_keepsakes.earned_marks().has(place) and not host.home_keepsakes.earned_marks().has("nowhere/at-all"), "Keepsakes go through the catalog")
	var again: Dictionary = await sources.collect()
	_check(again.settings.stamp == 50, "Applied settings keep the cloud's stamp, so they do not look new")
	# Older settings never replace newer ones.
	var older := merged.duplicate(true)
	older.settings = {"values": {"sound": true}, "stamp": 10}
	await sources.apply(older)
	_check(host.saves.data.settings.sound == false, "An older settings copy does not apply")
	# A held save is never touched.
	host.saves.read_only = true
	_check(not sources.ready() and (await sources.collect()).is_empty() and not await sources.apply(merged), "A held save is neither read nor written")
	host.saves.read_only = false
	# Journals: a real cloud journal for a chapter never started here is adopted and loads clean.
	var source_path := dir.path_join("source-house.json")
	_check(Retained.seed(source_path, Registry.HOUSE), "A house journal at its retained rules")
	var source := RelayJourney.new(source_path, null, Registry.HOUSE)
	source.load_data()
	_check(source.accept_recording(_fixture("cooperative", "open-the-house-a")) and source.accept_recording(_fixture("cooperative", "open-the-house-b")), "A real house journal with one finished stage")
	var house_name := str(Registry.descriptor(Registry.HOUSE).local_path).get_file()
	var envelope: Variant = JSON.parse_string(FileAccess.get_file_as_string(source_path))
	var cloud_copy := Bundle.decode(Bundle.encode(Bundle.collect({"settings": {}}, 0, {}, {house_name: envelope})))
	_check(cloud_copy.journals.has(house_name) and int(cloud_copy.journals[house_name].stages) == 1, "The journal survives the slot's encoding")
	var house_target := dir.path_join("adopted").path_join(house_name)
	DirAccess.make_dir_recursive_absolute(dir.path_join("adopted"))
	sources.journal_paths = {house_name: {"chapter": Registry.HOUSE, "path": house_target}}
	var started := Time.get_ticks_usec()
	_check(await sources.apply(Bundle.merge(await sources.collect(), cloud_copy)), "Applying the cloud journal finishes in one run")
	var elapsed_ms := (Time.get_ticks_usec() - started) / 1000
	print("PLATFORM GAMES CLOUD: adopting a one-stage house journal took %d ms" % elapsed_ms)
	var adopted := RelayJourney.new(house_target, null, Registry.HOUSE)
	adopted.load_data()
	_check(FileAccess.file_exists(house_target) and not adopted.read_only and adopted.pairs().size() == 1, "The adopted journal loads with its finished stage")
	adopted = null
	source = null
	for folder: String in [dir.path_join("adopted")]:
		for name: String in DirAccess.get_files_at(folder): DirAccess.remove_absolute(folder.path_join(name))
		DirAccess.remove_absolute(folder)
	# Journals: a bad cloud journal never reaches the chapter, and local progress is never replaced.
	var journal_path := dir.path_join("relay-journey-v2.json")
	sources.journal_paths = {"relay-journey-v2.json": {"chapter": Registry.RELAY, "path": journal_path}}
	var bad := Bundle.empty()
	bad.journals = {"relay-journey-v2.json": {"stages": 1, "envelope": {"version": 1, "generation": 1, "relay": {"pairs": [{"a": {}, "b": {}}], "a": {}, "draft": {}}}}}
	await sources.apply(bad)
	_check(not FileAccess.file_exists(journal_path), "A journal that does not load cleanly is never written")
	_check(DirAccess.get_files_at(dir.path_join("staging")).is_empty(), "Its staging copy is removed")
	_check(state.cloud("rejected_journals", []).size() == 1, "and it is remembered, so it is not checked again")
	FileAccess.open(journal_path, FileAccess.WRITE).store_string("{\"local\":true}")
	await sources.apply(bad)
	_check(FileAccess.get_file_as_string(journal_path) == "{\"local\":true}", "A chapter started here is never replaced from the cloud")
	DirAccess.remove_absolute(journal_path)
	for name: String in DirAccess.get_files_at(dir.path_join("staging")): DirAccess.remove_absolute(dir.path_join("staging").path_join(name))
	DirAccess.remove_absolute(dir.path_join("staging"))
	host.queue_free()
