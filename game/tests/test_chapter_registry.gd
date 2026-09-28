extends SceneTree
const Registry = preload("res://services/chapter_registry.gd")
const Coordinator = preload("res://services/relay_room_coordinator.gd")
const Session = preload("res://services/relay_online_session.gd")
const Journey = preload("res://services/relay_journey.gd")
const Photo = preload("res://services/turn_photo_controller.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const OldCoordinatorTests = preload("res://tests/test_relay_room_coordinator.gd")
const OldOnlineTests = preload("res://tests/test_relay_online.gd")
const HOST := "HHHHHHHHHHHHHHHHHHHHHH"
const GUEST := "GGGGGGGGGGGGGGGGGGGGGG"
const ROOM := "RRRRRRRRRRRRRRRRRRRRRR"
const OTHER := "SSSSSSSSSSSSSSSSSSSSSS"
var checks := 0
var failures := 0
var fixtures: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _fixture(key: String, index: int) -> Dictionary:
	var folder := "first_steps" if key == Registry.FIRST_STEPS else "v2"
	var names := ["initial-checkpoint", "lift-checkpoint", "final-checkpoint"] if key == Registry.FIRST_STEPS else ["initial-checkpoint", "relay-checkpoint", "final-checkpoint"]
	return JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/" + folder + "/" + names[index] + ".json"))

func _record(stage_index: int, role: String = "a") -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/first_steps/" + ["a-little-lift", "a-place-to-grow"][stage_index] + "-" + role + ".json"))

func _room(key: String, room_id: String = ROOM, index: int = 0, has_a: bool = false, revision: int = 1) -> Dictionary:
	var level := Registry.definition(key)
	var first: Variant = HOST if index == 0 else GUEST
	var second: Variant = GUEST if index == 0 else HOST
	return {"schema_version":2,"api_version":2,"room_id":room_id,"revision":revision,"branch":0,
		"stage_index":index,"level_id":level.id,"level_version":level.version,"definition_hash":Canonical.digest(level),
		"host_id":HOST,"guest_id":GUEST,"checkpoint":_fixture(key,index),"a_turn_id":"t0-%d-a"%index if has_a else null,
		"completed_pair_ids":["p0-0","p0-1"].slice(0,index),"invite_code":"A1".repeat(10),
		"invite_expires_at":"2026-09-21T12:00:00Z","created_at":"2026-09-14T12:00:00Z","updated_at":"2026-09-14T12:00:00Z",
		"active_role":"complete" if index==2 else "b" if has_a else "a","first_player_id":null if index==2 else first,
		"active_player_id":null if index==2 else second if has_a else first,"player_slot":"p0",
		"stage_id":"" if index==2 else level.stages[index].id,"recording_a":_record(index) if has_a else null,
		"validation":"structural_client_replay_required"}

func _ok(data: Dictionary) -> Dictionary:
	return {"ok":true,"status":200,"data":data}

func _caps() -> Dictionary:
	var chapters: Array = []
	for key: String in Registry.keys():
		var d := Registry.descriptor(key)
		chapters.append({"level_id":d.level_id,"level_version":d.level_version,"definition_hash":d.definition_hash,
			"premium":d.premium,"recording_version":d.recording_version,"simulation_version":4 if key == Registry.FIRST_STEPS else d.simulation_version})
		if key == Registry.FIRST_STEPS: chapters[-1]["supported_simulation_versions"] = [4, 5]
	return {"api_version":2,"recording_version":2,"simulation_version":2,"mutations_enabled":true,
		"validation":"structural_client_replay_required","chapters":chapters}

func _run() -> void:
	_resolution_compatibility()
	_check(Registry.keys() == [Registry.FIRST_STEPS, Registry.RELAY, Registry.HIGH_AND_LOW, Registry.ROLLING_HOME, Registry.HOUSE, Registry.CONSERVATORY, Registry.LONG_WAY_HOME], "Published chapter order remains stable before appended journey chapters")
	for key: String in Registry.keys():
		var d := Registry.descriptor(key)
		_check(Registry.resolve(d) == key, "Only the exact bundled descriptor resolves")
		var tampered := d.duplicate(true)
		tampered.definition_hash = "f".repeat(64)
		_check(Registry.resolve(tampered).is_empty(), "Unrecognized hash does not fall back to a named chapter")
		_check(not Registry.initial_checkpoint(key).is_empty(), "Each trusted chapter has its own initial checkpoint")
	_check(Registry.world_script(Registry.FIRST_STEPS) != Registry.world_script(Registry.RELAY), "New lift mechanics use a distinct world")
	_check(Registry.descriptor(Registry.FIRST_STEPS).local_path != Registry.descriptor(Registry.RELAY).local_path, "Local chapters use separate files")
	var caps := _caps()
	_check(Registry.supported_capabilities(caps).chapters.size() == 7, "Per-chapter supported versions enable all exact bundled choices")
	for key: String in [Registry.CONSERVATORY,Registry.LONG_WAY_HOME]:
		_check(Registry.descriptor(key).premium and Registry.descriptor(key).simulation_version == 8 and Registry.supported_rules(key) == [7,8], "Fresh Journey chapters prefer8 while exact retained7 remains supported")
		_check(Registry.simulation_script(key) != Registry.simulation_script(Registry.HOUSE), "New rules never replace the retained version-six engine")
	_check(Registry.descriptor(Registry.HOUSE).premium and Registry.world_script(Registry.HOUSE) != Registry.world_script(Registry.ROLLING_HOME), "House reuses paid-host policy with its own cutaway presentation")
	_check(Registry.simulation_script(Registry.HOUSE) == Registry.simulation_script(Registry.ROLLING_HOME) and Registry.descriptor(Registry.HOUSE).local_path != Registry.descriptor(Registry.ROLLING_HOME).local_path, "House reuses the physical engine while keeping a separate journal")
	_check(not Registry.descriptor(Registry.HIGH_AND_LOW).premium and Registry.descriptor(Registry.ROLLING_HOME).premium, "The free and Full Journey chapter policies are explicit")
	_check(Registry.descriptor(Registry.HIGH_AND_LOW).local_path != Registry.descriptor(Registry.ROLLING_HOME).local_path, "New chapter journals have separate durable paths")
	var legacy_caps := caps.duplicate(true)
	legacy_caps.chapters = [legacy_caps.chapters[1]]
	legacy_caps.chapters[0].erase("simulation_version")
	legacy_caps.chapters[0].erase("recording_version")
	var legacy := Registry.supported_capabilities(legacy_caps)
	_check(legacy.valid and legacy.chapters[0].key == Registry.RELAY and legacy.chapters[0].simulation_version == 2, "Existing capability response retains Relay's original rules")
	_capability_default_compatibility(legacy_caps)
	var wrong := caps.duplicate(true)
	wrong.chapters[0].simulation_version = 2
	_check(not Registry.supported_capabilities(wrong).valid, "First Steps cannot borrow top-level Relay version")
	wrong = caps.duplicate(true)
	wrong.chapters.append(wrong.chapters[0])
	_check(not Registry.supported_capabilities(wrong).valid, "Conflicting duplicate chapter advertisement rejected")
	wrong = caps.duplicate(true)
	wrong.chapters[0].premium = true
	_check(not Registry.supported_capabilities(wrong).valid, "No invented premium policy")
	wrong = caps.duplicate(true)
	wrong.chapters[3].premium = false
	_check(not Registry.supported_capabilities(wrong).valid, "The service cannot silently remove the bundled paid-host policy")
	wrong = caps.duplicate(true)
	wrong.chapters[2].simulation_version = 5
	_check(not Registry.supported_capabilities(wrong).valid, "New physical chapters cannot borrow an older engine version")
	var blank := caps.duplicate(true)
	blank.chapters = []
	_check(Registry.supported_capabilities(blank).valid and Registry.supported_capabilities(blank).chapters.is_empty(), "Creation-disabled service can still permit retained room reads")
	await _switching()
	await _pending_and_photos()
	await _session_intent()
	_local_storage()
	print("Trusted chapter client: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _capability_default_compatibility(legacy_caps: Dictionary) -> void:
	for field: String in ["simulation_version", "recording_version"]:
		var partial := legacy_caps.duplicate(true)
		partial.chapters[0][field] = 2
		_check(not Registry.supported_capabilities(partial).valid, "Partial legacy metadata cannot use the missing-field fallback")
	var modern := legacy_caps.duplicate(true)
	modern.chapters[0].simulation_version = 2.0
	modern.chapters[0].recording_version = 2
	var supplied := Registry.supported_capabilities(modern)
	_check(supplied.valid and supplied.chapters[0].simulation_version is float and supplied.chapters[0].simulation_version == 2.0, "Explicit integral versions retain their supplied numeric type")
	for invalid: Variant in [null, true, "2", 2.5, INF, -INF, NAN, 6]:
		var wrong := modern.duplicate(true)
		wrong.chapters[0].simulation_version = invalid
		_check(not Registry.supported_capabilities(wrong).valid, "Invalid supplied versions cannot fall back to legacy rules")
	var negotiated := legacy_caps.duplicate(true)
	negotiated.chapters[0].supported_simulation_versions = [2, 8]
	_check(Registry.supported_capabilities(negotiated).chapters[0].simulation_version == 8, "Legacy Relay negotiates newer rules only through the advertised version list")

func _resolution_compatibility() -> void:
	for key: String in Registry.keys():
		var descriptor := Registry.descriptor(key)
		_check(key.get_slice("@", 0) == descriptor.level_id, "Bundled key prefix matches its canonical level ID")
		var wire: Dictionary = JSON.parse_string(JSON.stringify(descriptor))
		wire.level_version = float(wire.level_version)
		var before := Canonical.digest(wire)
		_check(Registry.resolve(wire) == key, "Integral JSON versions resolve to the exact bundled chapter")
		_check(Canonical.digest(wire) == before, "Resolution leaves the supplied descriptor unchanged")
		for rules: int in Registry.supported_rules(key):
			var retained := wire.duplicate(true)
			retained.simulation_version = rules
			_check(Registry.resolve(retained) == key, "Retained simulation versions do not change chapter identity")
	var exact := Registry.descriptor(Registry.RELAY)
	for version: Variant in [null, true, "2", 2.5, INF, -INF, NAN, 3, 3.0]:
		var wrong := exact.duplicate(true)
		wrong.level_version = version
		_check(Registry.resolve(wrong).is_empty(), "Malformed or mismatched versions never resolve by ID alone")
	for level_id: Variant in [null, 2, "", "relay-isles-other", Registry.RELAY, "RELAY-ISLES"]:
		var wrong := exact.duplicate(true)
		wrong.level_id = level_id
		_check(Registry.resolve(wrong).is_empty(), "Only an exact string level ID can select a bundled chapter")
	for invalid: Variant in [null, [], "relay-isles", {}, {"level_id":"relay-isles", "level_version":2, "definition_hash":null}]:
		_check(Registry.resolve(invalid).is_empty(), "Malformed descriptor shapes are rejected")
	var caps := _caps()
	var expected := Registry.supported_capabilities(caps)
	caps.chapters.reverse()
	_check(Canonical.same(Registry.supported_capabilities(caps), expected), "Capability input order cannot change bundled chapter order or negotiation")

func _switching() -> void:
	var boundary := OldCoordinatorTests.Boundary.new()
	var c := Coordinator.new(boundary.transport,boundary.load_store,boundary.save_store,boundary.owner,boundary.key)
	_check(c.bind_room(ROOM) and c.chapter_key().is_empty(), "Empty room bind has no leftover default engine")
	boundary.responses.append(_ok(_room(Registry.FIRST_STEPS)))
	_check(await c.refresh() and c.chapter_key()==Registry.FIRST_STEPS, "First Steps descriptor committed after actual replay validation")
	var live: RefCounted = c.create_live_simulation()
	_check(live != null and live.get_script()==Registry.simulation_script(Registry.FIRST_STEPS), "Authorized live producer uses exact First Steps engine")
	live.step({"move_x":1.0})
	_check(c.save_live_draft(live), "Actual active First Steps tick uses bounded live autosave")
	var first_state: Dictionary = c.snapshot()
	var different := _room(Registry.RELAY)
	different.revision = 2
	boundary.responses.append(_ok(different))
	_check(not await c.refresh() and Canonical.same(c.snapshot(),first_state), "Same room cannot change chapter under a newer revision")
	_check(c.bind_room(OTHER) and c.chapter_key().is_empty(), "New empty room clears First Steps dispatch before reading")
	boundary.responses.append(_ok(_room(Registry.RELAY,OTHER)))
	_check(await c.refresh() and c.chapter_key()==Registry.RELAY, "First Steps to Relay selects exact old engine")
	_check(c.bind_room(ROOM) and c.chapter_key()==Registry.FIRST_STEPS, "Relay to stored First Steps restores descriptor without migrating scope")
	_check(c.draft().recording_hash == live.export_recording().recording_hash, "Chapter switch preserves the actual First Steps draft")
	_check(c.bind_room(OTHER) and c.chapter_key()==Registry.RELAY, "Returning to saved Relay does not retain First Steps context")
	var scope := "relay-room-v2:"+HOST+":"+OTHER
	var preserved: Dictionary = boundary.disk[scope].duplicate(true)
	boundary.disk[scope].snapshot.definition_hash = "f".repeat(64)
	var before := Canonical.digest(boundary.disk[scope])
	_check(not c.bind_room(OTHER) and c.read_only and c.chapter_key().is_empty(), "Unsupported stored snapshot holds without stale engine")
	_check(Canonical.digest(boundary.disk[scope])==before, "Unsupported bytes are not overwritten")
	boundary.disk[scope] = preserved
	_check(c.bind_room(OTHER), "Restoring test fixture allows a normal verified rebind")
	c.invalidate_identity()
	_check(c.chapter_key().is_empty() and c.snapshot().is_empty(), "Identity invalidation clears selected engine and room")

func _pending_and_photos() -> void:
	var b := OldCoordinatorTests.Boundary.new()
	var c := Coordinator.new(b.transport,b.load_store,b.save_store,b.owner,b.key)
	c.bind_room(ROOM)
	b.responses.append(_ok(_room(Registry.FIRST_STEPS)))
	_check(await c.refresh(), "New intro opens for durable submission test")
	_check(not await c.commit(_record(0)), "Lost response keeps an actual First Steps A request pending")
	var saved := Canonical.digest(c.pending())
	_check(not c.bind_room(OTHER) and Canonical.digest(c.pending())==saved, "Pending First Steps cannot be moved to another chapter")
	var restarted := Coordinator.new(b.transport,b.load_store,b.save_store,b.owner,b.key)
	_check(restarted.bind_room(ROOM) and Canonical.digest(restarted.pending())==saved, "Pending new chapter request survives restart byte-for-byte logically")
	var req: Dictionary = restarted.pending()
	var response := _accepted(req.body, _room(Registry.FIRST_STEPS,ROOM,0,true,2))
	b.responses.append(_ok(response))
	_check(await restarted.reconcile() and restarted.pending().is_empty(), "Exact saved new chapter receipt reconciles")
	var photo := Photo.new(Callable(),Callable(),Callable(),b.owner,Callable())
	photo._owner = HOST
	var target: Dictionary = photo._accepted_target(response,ROOM,req.body.idempotency_key)
	_check(target.get("stage_id")=="a-little-lift" and target.get("recording_hash")==_record(0).recording_hash, "Photo target is grounded in accepted no-seed stage receipt")
	var bad := response.duplicate(true)
	bad.receipt.stage_id = "relay"
	_check(photo._accepted_target(bad,ROOM,req.body.idempotency_key).is_empty(), "Old chapter stage cannot be substituted into new photo receipt")
	bad = response.duplicate(true)
	bad.room.definition_hash = "f".repeat(64)
	_check(photo._accepted_target(bad,ROOM,req.body.idempotency_key).is_empty(), "Unknown photo chapter does not inherit permissions")
	photo._owner = GUEST
	_check(photo._accepted_target(response,ROOM,req.body.idempotency_key).is_empty(), "Partner cannot edit the owner's new chapter photo")
	var complete := _room(Registry.FIRST_STEPS,ROOM,2,false,5)
	b.responses.append(_ok(complete))
	_check(await restarted.refresh(), "Full new checkpoint proof verifies after original receipt")
	var pair := {"pair_id":"p0-1","branch":0,"stage_index":1,"a":_record(1),"b":_record(1,"b"),"checkpoint":_fixture(Registry.FIRST_STEPS,2)}
	b.responses.append(_ok(pair))
	_check(not (await restarted.fetch_pair("p0-1")).is_empty(), "New proof checkpoint key dispatches exact pair replay")

func _accepted(body: Dictionary, room: Dictionary) -> Dictionary:
	var request := body.duplicate(true)
	request.operation = "turns"
	return {"room":room,"receipt":{"schema_version":2,"room_id":ROOM,"idempotency_key":body.idempotency_key,
		"request_hash":Canonical.digest(request),"operation":"turns","accepted_revision":body.base_revision+1,
		"branch":0,"stage_index":0,"stage_id":"a-little-lift","turn_id":"t0-0-a","recording_hash":body.recording.recording_hash,
		"pair_id":null,"checkpoint_hash":body.recording.checkpoint_hash}}

func _session_intent() -> void:
	var api := OldOnlineTests.FakeApi.new()
	var disk := OldOnlineTests.MemoryStore.new()
	var identity := OldOnlineTests.Identity.new()
	var wrong_creation := [true]
	api.responder = func(call: Dictionary) -> Dictionary:
		if call.path=="/v2/capabilities": return _ok(_caps())
		if call.path=="/v2/rooms" and call.method==HTTPClient.METHOD_GET: return _ok({"rooms":[]})
		if call.path=="/v2/rooms" and call.method==HTTPClient.METHOD_POST:
			if wrong_creation[0]: return _ok(_room(Registry.RELAY))
		var created := _room(Registry.FIRST_STEPS)
		created["simulation_version"] = 5
		return _ok(created)
	root.add_child(api)
	var session := Session.new(api,identity.get_value,disk)
	_check(await session.load_lobby() and session.supports_creation(Registry.FIRST_STEPS), "Chooser uses verified per-chapter service capability")
	_check((await session.create_room(Registry.FIRST_STEPS)).is_empty(), "Mismatched create response is not accepted as new intro")
	var pending: Dictionary = session.pending_lobby()
	_check(Registry.resolve(pending.body)==Registry.FIRST_STEPS and pending.body.get("simulation_version") == 5, "Durable create intent includes exact definition identity and negotiated cumulative rules")
	var digest := Canonical.digest(pending)
	_check((await session.create_room(Registry.RELAY)).is_empty() and Canonical.digest(session.pending_lobby())==digest, "Changing chooser cannot rewrite pending new chapter intent")
	wrong_creation[0] = false
	_check(await session.retry_lobby()==ROOM and session.chapter_key()==Registry.FIRST_STEPS, "Exact create retry opens the originally chosen chapter")
	_check(session.pending_lobby().is_empty(), "Confirmed exact create clears pending once")
	api.queue_free()
	await process_frame

func _local_storage() -> void:
	var path := "user://first-steps-registry-test-" + Crypto.new().generate_random_bytes(8).hex_encode() + ".json"
	var journal := Journey.new(path,null,Registry.FIRST_STEPS)
	journal.load_data()
	_check(not journal.read_only and journal.stage_id()=="a-little-lift", "New local file starts its independently versioned engine")
	_check(journal.accept_recording(_record(0)), "Local First Steps accepts real no-seed source")
	var reopened := Journey.new(path,null,Registry.FIRST_STEPS)
	reopened.load_data()
	_check(not reopened.read_only and Canonical.same(reopened.prior_recording(),_record(0)), "Restart keeps accepted First Steps source exactly")
	var digest := FileAccess.get_sha256(path)
	var wrong := Journey.new(path,null,Registry.RELAY)
	wrong.load_data()
	_check(wrong.read_only and FileAccess.get_sha256(path)==digest, "Opening a First Steps file with Relay fails without changing bytes")
	var collision := Journey.new(Journey.PATH,null,Registry.FIRST_STEPS)
	collision.load_data()
	_check(collision.read_only, "First Steps refuses the legacy Relay default path before reading it")
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	raw.relay.schema_version = 5
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(raw))
	file.close()
	digest = FileAccess.get_sha256(path)
	var future := Journey.new(path,null,Registry.FIRST_STEPS)
	future.load_data()
	_check(future.read_only and FileAccess.get_sha256(path)==digest, "Future First Steps journal is preserved even with readable older backup")
	for suffix: String in ["", ".tmp", ".backup"]:
		if FileAccess.file_exists(path+suffix): DirAccess.remove_absolute(path+suffix)
