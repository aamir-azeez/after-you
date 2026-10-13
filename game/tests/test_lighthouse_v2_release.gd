extends SceneTree
## sleeping-lighthouse@2 taking over the Lighthouse card: a solo @1 journey is
## carried over on first open (or kept in @1 when it cannot be), @2 progress
## earns the same six keepsake places, and the together keepsakes, the paid
## gallery's "Together" and the picture's solo-only mark follow the chapter's
## release. Recordings are the frozen @1 fixtures (rules 3).
const Registry = preload("res://services/chapter_registry.gd")
const Migration = preload("res://services/lighthouse_migration.gd")
const V1Journey = preload("res://services/lighthouse_journey.gd")
const Journey = preload("res://services/relay_journey.gd")
const KeepsakeCatalog = preload("res://services/home_keepsake_catalog.gd")
const Thumbnails = preload("res://services/chapter_thumbnail_catalog.gd")
const PaidCatalog = preload("res://services/paid_level_catalog.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Main = preload("res://main.gd")
const KEY := Registry.LIGHTHOUSE_V2
var checks := 0
var failures := 0
var frozen: Dictionary
var stamp := ""

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	frozen = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/lighthouse/complete-six-v3.json"))
	stamp = Crypto.new().generate_random_bytes(6).hex_encode()
	_keepsakes_and_flags()
	_conversion()
	_plans()
	await _screen()
	await _fallback_screen()
	print("LIGHTHOUSE V2 RELEASE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _keepsakes_and_flags() -> void:
	var places := KeepsakeCatalog.chapter_places(KEY)
	_check(places.size() == 6 and places == KeepsakeCatalog.chapter_places(KeepsakeCatalog.LIGHTHOUSE), "@2 progress earns the six Lighthouse places")
	var released: bool = KEY in Registry.offered_keys()
	var lighthouse_rows := KeepsakeCatalog.all().filter(func(item: Dictionary) -> bool: return item.chapter_key == KeepsakeCatalog.LIGHTHOUSE)
	_check(lighthouse_rows.size() == 6 and lighthouse_rows.all(func(item: Dictionary) -> bool: return item.friend_available == released), "The Lighthouse's together keepsakes follow its release (%s)" % released)
	_check(KeepsakeCatalog.variant_total() == (64 if released else 58), "Keepsake variants: %d" % KeepsakeCatalog.variant_total())
	_check(Thumbnails.entry(Thumbnails.SLEEPING_LIGHTHOUSE).solo_only == not released and PaidCatalog.entry("sleeping-lighthouse").together == released, "The gallery says Together exactly when it can be played together")

## Writes an @1 journal of the first `pairs` frozen stages and, optionally, the next A.
func _v1(path: String, pairs: int, with_a: bool) -> void:
	_remove(path)
	var journal := V1Journey.new(path)
	journal.load_data()
	var ok := not journal.read_only
	for index in range(pairs):
		ok = ok and journal.accept_recording(frozen.pairs[index].a) and journal.accept_recording(frozen.pairs[index].b)
	if with_a: ok = ok and journal.accept_recording(frozen.pairs[pairs].a)
	_check(ok, "An @1 journal holds %d stages%s" % [pairs, " and an A turn" if with_a else ""])

func _conversion() -> void:
	var v1 := "user://lighthouse-v1-%s.json" % stamp
	var v2 := "user://lighthouse-v2-%s.json" % stamp
	_v1(v1, 6, false)
	var before := Migration._digest(v1)
	var converted := Migration.convert_v1(v1)
	_check(converted.get("status") == "converted" and converted.pairs.size() == 6 and converted.complete, "All six frozen @1 stages convert: " + str(converted.get("status")))
	var journey := Journey.new(v2, null, KEY)
	journey.load_data()
	_check(Migration.adopt(journey, converted) and journey.chapter_complete(), "The converted journey is saved complete in @2")
	var cold := Journey.new(v2, null, KEY)
	cold.load_data()
	_check(not cold.read_only and cold.chapter_complete() and cold.pairs().size() == 6, "...and loads complete from a cold start")
	_check(Migration._digest(v1) == before, "The @1 save is not changed")
	_check(not Migration.adopt(cold, converted), "A journal that already has turns is never overwritten")
	_v1(v1, 3, true)
	var partial := Migration.convert_v1(v1)
	_check(partial.get("status") == "converted" and partial.pairs.size() == 3 and not partial.a.is_empty() and not partial.complete, "Three stages and a waiting A turn convert")
	_remove(v2)
	var resumed := Journey.new(v2, null, KEY)
	resumed.load_data()
	_check(Migration.adopt(resumed, partial) and resumed.pairs().size() == 3 and resumed.role() == "b" and resumed.stage_id() == Registry.definition(KEY).stages[3].id, "@2 resumes at stage 4, B's turn")
	_remove(v1)
	_check(Migration.convert_v1(v1).get("status") == "empty", "No @1 journey, nothing to carry over")
	_remove(v2)

func _plans() -> void:
	var v1 := "user://lighthouse-plan-v1-%s.json" % stamp
	var v2 := "user://lighthouse-plan-v2-%s.json" % stamp
	var marker := "user://lighthouse-plan-marker-%s.json" % stamp
	_check(Migration.plan(v1, v2, marker) == "v2", "No saves: open @2")
	_v1(v1, 2, false)
	_check(Migration.plan(v1, v2, marker) == "migrate", "An @1 journey and no @2 save: carry it over")
	_check(Migration.remember("fallback", v1, marker) and Migration.plan(v1, v2, marker) == "v1", "An unfinished journey that did not convert stays in @1")
	var journal := V1Journey.new(v1)
	journal.load_data()
	journal.accept_recording(frozen.pairs[2].a)
	_check(Migration.plan(v1, v2, marker) == "migrate", "...until that @1 save changes")
	Migration.remember("fresh", v1, marker)
	_check(Migration.plan(v1, v2, marker) == "v2", "A finished journey that did not convert starts @2 fresh")
	var fresh := Journey.new(v2, null, KEY)
	fresh.load_data()
	fresh.accept_recording(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/lighthouse/v2-chain.json")).pairs[0].a)
	_check(Migration.plan(v1, v2, marker) == "v2", "Once @2 has a save it is always opened")
	for path: String in [v1, v2, marker]: _remove(path)

func _open() -> Node:
	var scene: Node = load(Registry.solo_scene(KEY)).instantiate()
	scene.settings = {"sound": false, "haptics": false, "reduced_motion": true, "assistance": true, "photo_prompts": false}
	root.add_child(scene)
	return scene

func _wait_mode(scene: Node, modes: Array, seconds: float = 60.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while is_instance_valid(scene) and scene.mode not in modes and Time.get_ticks_msec() < deadline: await process_frame
	return is_instance_valid(scene) and scene.mode in modes

## The real first open: the @1 save in its own place, no @2 save yet.
func _screen() -> void:
	var v2 := str(Registry.descriptor(KEY).local_path)
	_remove(v2)
	_remove(Migration.MARKER_PATH)
	_v1(Migration.V1_PATH, 3, true)
	_check(Migration.plan() == "migrate", "The first open plans a carry-over")
	var scene := _open()
	_check(scene.mode == "loading", "The carry-over runs on the journal worker")
	_check(await _wait_mode(scene, ["ready"]), "The screen opens at the carried-over turn")
	_check(scene.journey.pairs().size() == 3 and scene.journey.role() == "b", "Three stages and the waiting A are in @2")
	_check(Migration.plan() == "v2", "Later opens go straight to @2")
	_check(Main.lighthouse_scene() == (Registry.solo_scene(KEY) if KEY in Registry.offered_keys() else Migration.V1_SCENE), "The Solo Lighthouse card opens @2 once it is offered")
	scene.queue_free()
	await process_frame
	_remove(v2)

func _fallback_screen() -> void:
	var v2 := str(Registry.descriptor(KEY).local_path)
	for path: String in [Migration.V1_PATH, v2, Migration.MARKER_PATH]: _remove(path)
	var scene := _open()
	_check(await _wait_mode(scene, ["ready"]), "An @2 screen is open")
	# As if this open had found an unfinished @1 journey that did not convert.
	_v1(Migration.V1_PATH, 3, false)
	_check(not scene._adopt_migration({"status": "fallback", "complete": false}) and scene.mode == "leaving", "A journey that does not convert hands over to the @1 screen")
	_check(Migration.plan() == "v1", "...and the @1 screen is what the card opens next")
	_check(Main.lighthouse_scene() == Migration.V1_SCENE, "The Solo card opens the @1 screen for it")
	for i in range(4): await process_frame
	_check(current_scene != null and current_scene.scene_file_path == Migration.V1_SCENE, "The @1 screen is now showing")
	if current_scene != null:
		current_scene.queue_free()
		await process_frame
	scene.queue_free()
	await process_frame
	for path: String in [Migration.V1_PATH, v2, Migration.MARKER_PATH]: _remove(path)

func _remove(path: String) -> void:
	for suffix: String in ["", ".tmp", ".backup"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
