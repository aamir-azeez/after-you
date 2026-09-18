extends SceneTree

const Lighthouse = preload("res://core/lighthouse/borrowed_light.gd")
const Lift = preload("res://core/first_steps/simulation.gd")
const LiftCatalog = preload("res://core/first_steps/stage_catalog.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Registry = preload("res://services/chapter_registry.gd")
const LighthouseJourney = preload("res://services/lighthouse_journey.gd")
const Coordinator = preload("res://services/relay_room_coordinator.gd")
const RelayJourney = preload("res://services/relay_journey.gd")
var checks := 0
var failures := 0
var new_lift_a: Dictionary = {}
var new_lift_b: Dictionary = {}
var new_lift_checkpoint: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_legacy_proofs()
	_lighthouse_pause()
	_ordered_pause()
	_finale_pause()
	_all_stage_receivers()
	_lift_pause()
	_capacity_boundaries()
	_journal_versions()
	_capabilities()
	_room_pins()
	if failures == 0 and "--write-fixtures" in OS.get_cmdline_user_args():
		for key: String in ["a", "b", "checkpoint"]:
			var path := "res://tests/fixtures/first_steps/cumulative-lift-" + key + ".json"
			_check(not FileAccess.file_exists(path), "New cumulative fixture must not overwrite frozen evidence")
			if not FileAccess.file_exists(path):
				var file := FileAccess.open(path, FileAccess.WRITE)
				file.store_string(JSON.stringify(new_lift_a if key == "a" else new_lift_b if key == "b" else new_lift_checkpoint, "\t") + "\n")
	print("AFTER YOU CUMULATIVE HOLDS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _legacy_proofs() -> void:
	var frozen := _fixture("lighthouse/complete-six-v3.json")
	var prefix: Array = []
	for pair: Dictionary in frozen.pairs:
		for role: String in ["a", "b"]:
			var prior: Dictionary = pair.a if role == "b" else {}
			var replay := Lighthouse.new()
			_check(replay.resume_recording(pair[role], prior, prefix), "Historical Lighthouse record still verifies")
			_check(Canonical.same(replay.export_recording(), pair[role]), "Historical Lighthouse bytes and every state hash stay exact")
		prefix.append(pair)
	_check(Lighthouse.checkpoint_from_pairs(prefix).valid, "All six historical Lighthouse checkpoint proofs remain valid")
	var definition := LiftCatalog.definition()
	var previous := LiftCatalog.initial_checkpoint()
	for stage: String in ["a-little-lift", "a-place-to-grow"]:
		var a := _fixture("first_steps/" + stage + "-a.json")
		var b := _fixture("first_steps/" + stage + "-b.json")
		_check(Lift.verify_recording(definition, a, previous).valid, "Historical First Steps source verifies")
		var derived := Lift.derive_checkpoint(definition, previous, a, b)
		_check(derived.valid, "Historical First Steps receiver and checkpoint verify")
		if derived.valid: previous = derived.checkpoint
	_check(previous.next_stage_id == "", "Historical First Steps chapter stays complete")

func _lighthouse_pause() -> void:
	for version: int in [3, 5]:
		var a := Lighthouse.new()
		a.reset("a", {}, [], version)
		_walk(a, [-700, -100])
		while a.snapshot().hold_ticks < 20: a.step({})
		_walk(a, [-760, -100])
		var saved: int = a.snapshot().hold_ticks
		for _i in range(12): a.step({})
		_check(a.snapshot().hold_ticks == saved and not a.snapshot().emitter_powered, "Stepping away pauses the counter and turns the light off")
		_check(not a.can_commit(), "An unpowered endpoint cannot be saved as an active source")
		_walk(a, [-700, -100])
		for _i in range(15): a.step({})
		_check(a.snapshot().hold_ticks > saved and a.can_commit() == (version == 5), "Returning resumes credit only under explicitly recorded cumulative rules")
		var record := a.export_recording()
		_check(record.simulation_version == version and Lighthouse.verify_recording(record).valid, "Each ruleset binds its own replay and hash")
		if version == 3: continue
		var b := Lighthouse.new()
		_check(b.reset("b", record), "A resumed light is a viable receiver source")
		# Wait for this short interruption to pass, then execute the ordinary route.
		while b.tick < a.tick: b.step({})
		_walk(b, [-560, 80]); _walk(b, [-560, -100])
		b.step({"interact": true}); b.step({})
		_walk(b, [-560, 0]); _walk(b, [-160, 0]); b.step({"interact": true})
		_check(b.complete and Lighthouse.verify_recording(b.export_recording(), record).valid, "Actual receiver controls complete after a resumed source")
		var changed := record.duplicate(true)
		changed.simulation_version = 3
		changed.recording_hash = Lighthouse.recording_hash(changed)
		_check(not Lighthouse.verify_recording(changed).valid, "Changing only the rules version cannot reuse cumulative state hashes")
		var resumed := Lighthouse.new()
		_check(resumed.resume_recording(record) and resumed.state_hash() == a.state_hash(), "Resuming a cumulative source restores its exact credit")

func _ordered_pause() -> void:
	var prefix: Array = _fixture("lighthouse/first-three-v3.json").pairs
	var legacy_source: Dictionary = _fixture("lighthouse/first-four-v3.json").pairs[3].a
	var a := Lighthouse.new()
	_check(a.reset("a", {}, prefix, 5), "New ordered source accepts the exact historical prefix")
	# Replay only the ordinary approach and its first selector activation.
	for frame: Dictionary in Lighthouse.expand_recording_inputs(legacy_source):
		a.step(frame)
		if a.snapshot().sequence.phase == "first": break
	var budget := a.sequence_budget_ticks()
	while a.snapshot().sequence.first_ticks < 10: a.step({})
	# Cycle through second and off, then return to the first path.
	a.step({"interact": true}); a.step({})
	a.step({"interact": true}); a.step({})
	var kept := int(a.snapshot().sequence.first_ticks)
	for _i in range(8): a.step({})
	_check(a.snapshot().sequence.phase == "off" and a.snapshot().sequence.first_ticks == kept and not a.can_commit(), "An off selector pauses saved first-path credit and cannot finish")
	a.step({"interact": true})
	while a.snapshot().sequence.first_ticks < budget[0]: a.step({})
	a.step({"interact": true})
	while a.snapshot().sequence.second_ticks < budget[1]: a.step({})
	_check(a.can_commit() and not a.snapshot().sequence.broken, "A repaired selector schedule retains cumulative credit without a poison flag")
	var record := a.export_recording()
	_check(Lighthouse.verify_recording(record, {}, prefix).valid, "Interrupted ordered source replay verifies")
	var b := Lighthouse.new()
	_check(b.reset("b", record, prefix), "Receiver admits the repaired ordered schedule")
	var player: Dictionary = b.snapshot().players.p0
	_walk(b, [-48, int(player.z)]); _walk(b, [-48, 0])
	_walk(b, [288, 0]); _walk(b, [552, 0]); b.step({"interact": true})
	while not b.finished: b.step({})
	_check(b.complete and Lighthouse.verify_recording(b.export_recording(), record, prefix).valid, "A real receiver crosses both repaired light windows and rings the tower bell")
	_check(Lighthouse.checkpoint_from_pairs(prefix + [{"a": record, "b": b.export_recording()}]).valid, "Mixed old-prefix/new-turn chapter proof remains valid")

func _finale_pause() -> void:
	var frozen := _fixture("lighthouse/complete-six-v3.json")
	var prefix: Array = frozen.pairs.slice(0, 5)
	var a := Lighthouse.new()
	a.reset("a", {}, prefix, 5)
	for frame: Dictionary in Lighthouse.expand_recording_inputs(frozen.pairs[5].a): a.step(frame)
	_walk(a, [680, -144])
	var saved := int(a.snapshot().hold_ticks)
	for _i in range(7): a.step({})
	_check(not a.snapshot().hold_pads["beacon-hold"] and not a.snapshot().beacon.signals["beacon-upper"] and a.snapshot().hold_ticks == saved, "Finale pad absence really extinguishes the beam while preserving accumulated credit")
	_walk(a, [680, -80])
	_check(a.can_commit() and a.snapshot().beacon.signals["beacon-upper"], "Returning to the finale pad can restore a viable contribution")

func _lift_pause() -> void:
	var definition := LiftCatalog.definition()
	var initial := LiftCatalog.initial_checkpoint()
	var a := Lift.new()
	a.reset(definition, "a-little-lift", initial, {}, "a", 5)
	_walk(a, [-300, -130])
	while a.tick < 100: a.step({})
	_walk(a, [-430, -130])
	var saved: int = a._power_ticks
	while a.tick < 140: a.step({})
	_check(a._power_ticks == saved and not a.snapshot().controls["lift-power"] and not a.can_commit(), "Lift credit pauses away from the pad without treating absent power as active")
	_walk(a, [-300, -130])
	_check(a.can_commit() and a._power_ticks > saved, "First Steps source can recover after leaving and re-entering")
	new_lift_a = a.export_recording()
	var b := Lift.new()
	_check(b.reset(definition, "a-little-lift", initial, new_lift_a, "b"), "New receiver uses the source's cumulative rules")
	while b.tick < 70: b.step({})
	_walk(b, [-20, 0])
	while b.tick < 118: b.step({})
	var lift: Dictionary = b.snapshot().mechanisms.lift.duplicate(true)
	_check(lift.phase == "rising" and not b.snapshot().controls["lift-power"], "Source interruption can occur during a real lift ride")
	for _i in range(15): b.step({})
	_check(Canonical.same(lift, b.snapshot().mechanisms.lift), "The unpowered lift holds its actual height and does not advance")
	var paused := b.export_recording()
	_check(Lift.verify_recording(definition, paused, initial, new_lift_a).valid, "A mid-air paused receiver draft verifies")
	while b.snapshot().mechanisms.lift.phase != "upper" and not b.finished: b.step({})
	_walk(b, [230, 0]); b.step({"interact": true})
	new_lift_b = b.export_recording()
	_check(b.complete and b.snapshot().mechanisms.lift.progress_ticks == 60, "Lift resumes and reaches its exact required powered duration")
	var derived := Lift.derive_checkpoint(definition, initial, new_lift_a, new_lift_b)
	_check(derived.valid, "Real interrupted lift pair produces a verified checkpoint")
	if derived.valid: new_lift_checkpoint = derived.checkpoint
	for batch: int in [1, 7, 19]:
		var replay := Lift.new()
		replay.reset(definition, "a-little-lift", initial, new_lift_a, "b")
		var frames := Lift.expand_recording_inputs(new_lift_b)
		for i in range(frames.size()):
			replay.step(frames[i])
			if i % batch == 0: replay.snapshot()
		_check(Canonical.same(replay.export_recording(), new_lift_b), "Render observation frequency cannot change cumulative outcomes")
	var bad := new_lift_a.duplicate(true)
	bad.simulation_version = 4; bad.recording_hash = Lift.recording_hash(bad)
	_check(not Lift.verify_recording(definition, bad, initial).valid, "A v5 source cannot masquerade as a historical v4 source")

func _all_stage_receivers() -> void:
	var frozen := _fixture("lighthouse/complete-six-v3.json")
	var prefix: Array = []
	for index in range(frozen.pairs.size()):
		var pair: Dictionary = frozen.pairs[index]
		if index == 3:
			# The interrupted ordered route is exercised with physical controls above.
			prefix.append(pair)
			continue
		var a := Lighthouse.new()
		a.reset("a", {}, prefix, 5)
		for frame: Dictionary in Lighthouse.expand_recording_inputs(pair.a): a.step(frame)
		if index in [1, 2]:
			var saved := int(a.snapshot().hold_ticks)
			a.step({}); a.step({"interact": true})
			_check(not a.snapshot().emitter_powered, "Mirror rotation really interrupts the source in " + str(pair.a.stage_id))
			for _i in range(9): a.step({})
			_check(a.snapshot().hold_ticks == saved + 1, "Mirror-off time does not count as hold time")
			a.step({"interact": true}); a.step({})
		elif index in [0, 5]:
			var player: Dictionary = a.snapshot().players[a.snapshot().active_slot]
			var target := [player.x, player.z]
			_walk(a, [int(player.x), int(player.z) - 64])
			for _i in range(9): a.step({})
			_walk(a, target)
		else:
			# The portable-lens stage has no hold objective to accumulate.
			for _i in range(9): a.step({})
		_check(a.can_commit(), "Current source can finish after recoverable interruption: " + str(pair.a.stage_id))
		var record := a.export_recording()
		var b := Lighthouse.new()
		_check(b.reset("b", record, prefix), "Each stage starts a receiver from actual v5 source evidence")
		while b.tick < a.tick: b.step({})
		for frame: Dictionary in Lighthouse.expand_recording_inputs(pair.b): b.step(frame)
		_check(b.complete and Lighthouse.verify_recording(b.export_recording(), record, prefix).valid, "Actual receiver controls complete under current rules: " + str(pair.a.stage_id))
		_check(Lighthouse.checkpoint_from_pairs(prefix + [{"a": record, "b": b.export_recording()}]).valid, "Each current pair derives a valid checkpoint without changing the historical prefix")
		prefix.append(pair)

func _capacity_boundaries() -> void:
	# Enough progress alone is insufficient if the interruptions used all of B's time.
	var a := Lighthouse.new()
	a.reset("a", {}, [], 5)
	_walk(a, [-700, -100])
	while a.snapshot().hold_ticks < 20: a.step({})
	_walk(a, [-760, -100])
	while a.tick < 590: a.step({})
	_walk(a, [-700, -100])
	while not a.finished: a.step({})
	_check(a.snapshot().hold_ticks >= 15 and a.snapshot().emitter_powered and not a.can_commit(), "Late re-entry retains progress but cannot invent enough receiver time")
	_check(not Lighthouse.new().reset("b", a.export_recording()), "An impossible interrupted source never opens receiver play")
	var power := Lift.new()
	power.reset(LiftCatalog.definition(), "a-little-lift", LiftCatalog.initial_checkpoint(), {}, "a", 5)
	_walk(power, [-300, -130]); _walk(power, [-430, -130])
	while power.tick < 580: power.step({})
	_walk(power, [-300, -130])
	while not power.finished: power.step({})
	_check(power.snapshot().outcome.supplied_power and not power.can_commit(), "Cumulative lift credit cannot excuse an impossible remaining ride")

func _journal_versions() -> void:
	var directory := "user://cumulative-holds-" + str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(directory)
	var lighthouse := LighthouseJourney.new(directory.path_join("lighthouse.json"))
	lighthouse.load_data()
	_check(lighthouse.create_live_simulation().simulation_version == 5, "Fresh Lighthouse rehearsal starts current rules")
	var old := Lighthouse.new(); old.reset(); old.step({})
	_check(lighthouse.save_draft(old.export_recording()), "Historical draft remains saveable")
	_check(lighthouse.create_live_simulation(true).simulation_version == 3, "Resume retains the historical Lighthouse draft rules")
	_check(lighthouse.create_live_simulation().simulation_version == 5, "Retry chooses new rules without rewriting the old draft")
	var steps := RelayJourney.new(directory.path_join("steps.json"), null, Registry.FIRST_STEPS)
	steps.load_data()
	_check(steps.create_live_simulation().simulation_version == 5, "Fresh First Steps rehearsal starts current rules")
	_check(steps.save_draft(_fixture("first_steps/a-little-lift-a.json")), "Historical lift draft remains saveable")
	_check(steps.create_live_simulation(true).simulation_version == 4, "Resume retains historical lift rules")
	_check(steps.create_live_simulation().simulation_version == 5, "Retry upgrades lift rules explicitly")

func _capabilities() -> void:
	var entry := Registry.descriptor(Registry.FIRST_STEPS)
	entry.simulation_version = 4
	var value := {"api_version": 2, "recording_version": 2, "simulation_version": 2, "mutations_enabled": true, "validation": "structural_client_replay_required", "chapters": [entry]}
	var old := Registry.supported_capabilities(value)
	_check(old.valid and old.chapters[0].simulation_version == 4, "An older server negotiates legacy rules rather than receiving unsupported new turns")
	entry.supported_simulation_versions = [4, 5]
	var current := Registry.supported_capabilities(JSON.parse_string(JSON.stringify(value)))
	_check(current.valid and current.chapters[0].simulation_version == 5, "An upgraded server explicitly negotiates cumulative rules")
	entry.supported_simulation_versions = [4, 5, 5]
	_check(not Registry.supported_capabilities(value).valid, "Ambiguous capability arrays fail closed")

func _room_pins() -> void:
	var host := "H".repeat(22)
	var guest := "G".repeat(22)
	var room_id := "R".repeat(22)
	var identity := {"ready": true, "player_id": host, "epoch": 1}
	var coordinator := Coordinator.new(func(_request): return {}, func(_scope): return {}, func(_scope, _value): return {"ok": true}, func(): return identity)
	coordinator._owner = host; coordinator._epoch = 1; coordinator._room = room_id
	coordinator._chapter_key = Registry.FIRST_STEPS
	coordinator._level = LiftCatalog.definition(); coordinator._simulation = Lift
	coordinator._state = coordinator._empty_state()
	coordinator.supported_simulation_versions = {Registry.FIRST_STEPS: 5}
	var descriptor := Registry.descriptor(Registry.FIRST_STEPS)
	var room := {"schema_version": 2, "api_version": 2, "room_id": room_id, "revision": 1,
		"branch": 0, "stage_index": 0, "level_id": descriptor.level_id, "level_version": descriptor.level_version,
		"definition_hash": descriptor.definition_hash, "host_id": host, "guest_id": guest,
		"checkpoint": LiftCatalog.initial_checkpoint(), "a_turn_id": null, "completed_pair_ids": [],
		"invite_expires_at": "2026-09-25T12:00:00Z", "created_at": "2026-09-18T12:00:00Z", "updated_at": "2026-09-18T12:00:00Z",
		"active_role": "a", "first_player_id": host, "active_player_id": host, "player_slot": "p0",
		"stage_id": "a-little-lift", "recording_a": null, "invite_code": "A1".repeat(10),
		"validation": "structural_client_replay_required"}
	_check(coordinator._valid_snapshot(room), "Legacy unpinned room remains a valid room after server upgrade")
	coordinator._state.snapshot = room
	_check(coordinator.create_live_simulation().simulation_version == 4, "Advertised new rules never upgrade an existing unpinned room")
	_check(not coordinator._verify_recording(new_lift_a, room).valid, "Cumulative record cannot enter a legacy room")
	var legacy_room := room.duplicate(true)
	room.simulation_version = 5
	_check(not coordinator._same_context(legacy_room, room), "Changing rules retires the previous live rehearsal context")
	_check(coordinator._valid_snapshot(JSON.parse_string(JSON.stringify(room))), "Pinned new room validates through actual JSON numeric types")
	coordinator._state.snapshot = room
	_check(coordinator.create_live_simulation().simulation_version == 5, "A new pinned room starts cumulative rules")
	_check(coordinator._verify_recording(new_lift_a, room).valid, "Cumulative source is valid in the explicitly pinned room")
	_check(not coordinator._verify_recording(_fixture("first_steps/a-little-lift-a.json"), room).valid, "Historical draft cannot silently change a pinned room's rules")
	room.recording_a = new_lift_a; room.a_turn_id = "t0-0-a"; room.active_role = "b"; room.active_player_id = guest
	room.player_slot = "p1"; room.erase("invite_code")
	room = JSON.parse_string(JSON.stringify(room))
	identity.player_id = guest; coordinator._owner = guest; coordinator._state.snapshot = room
	_check(coordinator._valid_snapshot(room) and coordinator.create_live_simulation().simulation_version == 5, "Receiver inherits the room and source rules")
	_check(coordinator._verify_recording(new_lift_b, room).valid, "The interrupted source/receiver pair is valid in the new room")
	room.simulation_version = 4
	_check(not coordinator._valid_snapshot(room), "A source recording cannot disagree with the room pin")
	room.simulation_version = 99
	_check(not coordinator._valid_snapshot(room), "Unknown room rules fail closed")

func _fixture(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/" + path))

func _walk(sim: RefCounted, destination: Array) -> void:
	for _i in range(400):
		if sim.finished: return
		var state: Dictionary = sim.snapshot()
		var player: Dictionary = state.players[state.active_slot]
		var dx := int(destination[0]) - int(player.x)
		var dz := int(destination[1]) - int(player.z)
		if absi(dx) <= 4 and absi(dz) <= 4: return
		sim.step({"move_x": signi(dx) if absi(dx) > 4 else 0, "move_z": 0 if absi(dx) > 4 else signi(dz)})

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
