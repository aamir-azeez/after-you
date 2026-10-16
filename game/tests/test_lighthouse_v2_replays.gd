extends SceneTree
## sleeping-lighthouse@2 replays: a six-stage room's replay transfer, its
## shared replay cache, the combined "watch all parts" sequence and the part
## labels all take their stage count from the chapter. The archive is the
## C2 six-stage chain as one branch of a complete room.
const Transfer = preload("res://services/replay_transfer.gd")
const Collection = preload("res://services/shared_replay_collection.gd")
const View = preload("res://presentation/shared_replay_view.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Fixture = preload("res://tests/replay_transfer_fixture.gd")
const TransferTests = preload("res://tests/test_replay_transfer.gd")
const SharedTests = preload("res://tests/test_shared_replays.gd")
const Main = preload("res://main.gd")
const ReplaysFlow = preload("res://presentation/replays_flow.gd")
const HOST := Fixture.HOST
const GUEST := Fixture.GUEST
const ROOM := Fixture.ROOM
const KEY := Registry.LIGHTHOUSE_V2
var checks := 0
var failures := 0
var chain: Dictionary

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	chain = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/lighthouse/v2-chain.json"))
	var archive := Fixture.archive(KEY, chain.checkpoints[6])
	var manifest := Fixture.manifest(archive)
	_check(archive.pairs.size() == 6 and archive.turns.size() == 12 and archive.room.stage_index == 6, "The six-stage archive has 6 pairs and 12 turns")
	_check(Transfer._manifest_valid(manifest, HOST, ROOM) and Transfer._manifest_valid(manifest, GUEST, ROOM), "A complete six-stage manifest is valid for both members")
	var checked := Transfer.verify_archive(archive, manifest, HOST, ROOM)
	_check(checked.get("ok", false) and checked.get("entries", []).size() == 6, "The six-stage archive verifies natively: " + str(checked.get("code", "ok")))
	_manifest_refusals(archive, manifest)
	_archive_refusals(archive)
	_two_stage_unchanged()
	await _download(archive, manifest)
	await _shared_cache(checked.get("entries", []), manifest)
	_labels()
	print("LIGHTHOUSE V2 REPLAYS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _manifest_refusals(archive: Dictionary, manifest: Dictionary) -> void:
	var cases := {}
	var two := manifest.duplicate(true)
	two.room.stage_index = 2
	cases["a room claiming completion at stage index 2"] = two
	var seven := manifest.duplicate(true)
	seven.room.stage_index = 7
	cases["stage index 7"] = seven
	var short := manifest.duplicate(true)
	short.room.completed_pair_ids = ["p0-0", "p0-1"]
	cases["two completed pairs"] = short
	var fewer := manifest.duplicate(true)
	fewer.pairs.pop_back()
	fewer.turns.pop_back()
	fewer.turns.pop_back()
	cases["fewer pairs than stages"] = fewer
	var digit := manifest.duplicate(true)
	digit.turns[11].turn_id = "t0-6-b"
	cases["a turn past the last stage"] = digit
	var pair := manifest.duplicate(true)
	pair.pairs[5].stage_index = 6
	pair.pairs[5].pair_id = "p0-6"
	cases["a pair past the last stage"] = pair
	var order := manifest.duplicate(true)
	order.room.completed_pair_ids = ["p0-0", "p0-1", "p0-3", "p0-2", "p0-4", "p0-5"]
	cases["completed pairs out of stage order"] = order
	var player := manifest.duplicate(true)
	player.turns[6].player_id = HOST if player.turns[6].player_id == GUEST else GUEST
	cases["a stage-4 turn by the wrong player"] = player
	for name: String in cases:
		_check(not Transfer._manifest_valid(cases[name], HOST, ROOM), "A manifest is refused for " + name)

func _archive_refusals(archive: Dictionary) -> void:
	# Swap two middle pairs' records: every hash still matches its manifest,
	# but the nested proofs no longer chain.
	var swapped := archive.duplicate(true)
	var third: Dictionary = swapped.pairs[2].duplicate(true)
	swapped.pairs[2].checkpoint = swapped.pairs[3].checkpoint.duplicate(true)
	swapped.pairs[3].checkpoint = third.checkpoint
	_check(not Transfer.verify_archive(swapped, Fixture.manifest(swapped), HOST, ROOM).get("ok", false), "Pairs whose checkpoints do not nest are refused")
	var stale := archive.duplicate(true)
	stale.room.checkpoint = chain.checkpoints[5].duplicate(true)
	_check(not Transfer.verify_archive(stale, Fixture.manifest(stale), HOST, ROOM).get("ok", false), "A final checkpoint one stage short is refused")

func _two_stage_unchanged() -> void:
	var relay := Fixture.archive(Registry.RELAY, Fixture.fixture("v2/final-checkpoint"))
	_check(relay.room.revision == 5 and relay.room.stage_index == 2 and relay.room.completed_pair_ids == ["p0-0", "p0-1"] and relay.turns.size() == 4, "The two-stage fixture archive keeps its exact shape")
	var manifest := Fixture.manifest(relay)
	_check(Transfer.verify_archive(relay, manifest, HOST, ROOM).get("ok", false), "A two-stage archive still verifies")
	var six := manifest.duplicate(true)
	six.room.stage_index = 6
	_check(not Transfer._manifest_valid(six, HOST, ROOM), "A two-stage room cannot claim six stages")

## The durable helper downloads, verifies and saves the six-stage archive.
func _download(archive: Dictionary, manifest: Dictionary) -> void:
	var boundary := TransferTests.Boundary.new()
	var store := Fixture.Memory.new()
	var helper: RefCounted = Transfer.new(boundary.transport, boundary.owner, boundary.eligible, store)
	var reply := {"schema_version": 1, "manifest": manifest.duplicate(true), "acked_player_ids": [], "transferred": false, "archive": archive.duplicate(true)}
	boundary.replies.append({"ok": true, "status": 200, "data": reply})
	var result: Dictionary = await helper.download(ROOM)
	_check(result.get("ok", false) and store.writes == 1, "The six-stage transfer downloads and saves: " + str(result.get("code", "ok")))
	var local: Dictionary = await helper.local_archive(ROOM, manifest)
	_check(local.get("ok", false), "...and the saved archive verifies again from storage")

func _shared_cache(entries: Array, manifest: Dictionary) -> void:
	var owner := SharedTests.Boundary.new()
	var api := SharedTests.Api.new()
	root.add_child(api)
	var collection: RefCounted = Collection.new(api, owner.identity, SharedTests.Memory.new(), SharedTests.OnlineMemory.new())
	_check(collection.cache_transferred_entries(ROOM, entries, manifest), "The shared cache adopts all six pairs")
	var key := "chapter:" + ROOM
	var sequence: Array = collection.local_sequence(key)
	var ordered := sequence.size() == 6
	for index in range(sequence.size()): ordered = ordered and int(sequence[index].pair.stage_index) == index
	_check(ordered, "Watch all parts plays six parts in stage order")
	_check(View.valid_sequence(sequence, HOST), "The viewer accepts the six-part chain")
	var reversed := sequence.duplicate()
	reversed.reverse()
	_check(not View.valid_sequence(reversed, HOST), "...but not in reverse")
	var gap := sequence.duplicate()
	gap.remove_at(3)
	_check(not View.valid_sequence(gap, HOST), "...or with a stage missing")
	_check(View.valid_sequence(sequence.slice(0, 3), HOST) and not View.valid_sequence(sequence.slice(1, 4), HOST), "A prefix from the first stage is a sequence; one starting later is not")
	var rows: Array = collection.memories(key)
	var titles := rows.size() == 6
	for index in range(rows.size()):
		titles = titles and str(rows[index].title) == "%d · %s" % [index + 1, chain.definition.stages[index].native.title]
	_check(titles, "Each cached part is titled by its stage")
	_check(Collection._pair_id("p0-5") and Collection._pair_id("p31-7") and not Collection._pair_id("p0-8"), "Pair ids carry any stage digit below 8")
	# A transfer with fewer pairs than stages is refused.
	var partial: Array = entries.duplicate(true)
	partial.remove_at(2)
	var partial_manifest := manifest.duplicate(true)
	partial_manifest.pairs.remove_at(2)
	var other: RefCounted = Collection.new(api, owner.identity, SharedTests.Memory.new(), SharedTests.OnlineMemory.new())
	_check(not other.cache_transferred_entries(ROOM, partial, partial_manifest), "A transfer with fewer pairs than stages is not adopted")
	# A cache missing the stage-3 pair has no complete sequence.
	collection._memories[key].erase("p0-2")
	_check(collection.local_sequence(key).is_empty(), "A missing middle stage leaves no combined sequence")
	api.queue_free()

func _labels() -> void:
	_check(ReplaysFlow._shared_part({"stage_index": 4}, 0) == 5 and ReplaysFlow._shared_part({"stage_index": 0.0}, 3) == 1 and ReplaysFlow._shared_part({"title": "Earlier"}, 2) == 3, "A shared memory's part is its stage, or its place for earlier islands")

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
