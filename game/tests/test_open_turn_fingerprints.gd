extends SceneTree
## Open turns fingerprints (services/open_turn_store.gd; the wire is
## claude-20261011/open-turns-fingerprints/WIRE.md, private): the server keeps
## only a stage's newest turn and a closing turn in full, earlier turns as
## fingerprints and checkpoints flat, and each phone plays, checks and replays
## from its own copies.
## - two real phones (coordinators) play Turn of the Tide@3 through, many turns
##   a stage, against a server double that stubs turns as WIRE.md says; each
##   phone checks the partner's new turn by replaying that turn alone, and the
##   earlier stage by hash, so a check costs the same at every turn and stage;
## - the finished room's checkpoint nests again from the phone's copies, checks
##   from scratch, and is the run a phone posts;
## - a reinstalled phone gets every turn back from its partner's phone (want,
##   send-back on the partner's poll, ack) and takes the room again;
## - a four stage room of many turns on a counting engine: each stage replays
##   only its own turns, and nesting the last checkpoint reads every stage;
## - core: a flat checkpoint passes only once proved here, and only on open turns rules.
const Coordinator = preload("res://services/relay_room_coordinator.gd")
const Registry = preload("res://services/chapter_registry.gd")
const OpenTurns = preload("res://core/physical/open_turns.gd")
const OpenTurnStore = preload("res://services/open_turn_store.gd")
const KnownCheckpoints = preload("res://core/physical/known_checkpoints.gd")
const MemoryTrace = preload("res://core/physical/memory_trace.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const BlobCodec = preload("res://services/blob_codec.gd")
const Witness = preload("res://tests/chapter_witness.gd")
const Server = preload("res://tests/open_turns_server.gd")
const TIDE := "turn-of-the-tide@3"
const HOST := "HHHHHHHHHHHHHHHHHHHHHH"
const GUEST := "GGGGGGGGGGGGGGGGGGGGGG"
const ROOM := "RRRRRRRRRRRRRRRRRRRRRR"
const ROOT := "user://open-turn-fingerprints-test"
## Repeats of each stage's first two routes before its closing route: 3 gives seven turns a stage.
const ROUNDS := 3
var checks := 0
var failures := 0

class Phone:
	extends RefCounted
	var player := ""
	var disk: Dictionary = {}
	var keys := 0
	var coordinator: RefCounted
	func _init(player_id: String, server: RefCounted, root: String) -> void:
		player = player_id
		coordinator = Coordinator.new(Callable(server, "transport"), load_store, save_store, identity, key)
		coordinator.turn_store_root = root
	func identity() -> Dictionary:
		return {"ready": true, "player_id": player, "epoch": 1}
	func load_store(scope: String) -> Dictionary:
		return {"ok": true, "found": disk.has(scope), "value": disk.get(scope, {}).duplicate(true)}
	func save_store(scope: String, value: Dictionary) -> Dictionary:
		disk[scope] = JSON.parse_string(JSON.stringify(value))
		return {"ok": true}
	func key() -> String:
		keys += 1
		return "%s-operation-%04d" % [player.left(4), keys]
	func store() -> RefCounted:
		return OpenTurnStore.new(player, ROOM, ROOT)

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	_wipe()
	_core_flat_checkpoints()
	var played := await _room_plays_through()
	if not played.is_empty(): await _reinstall_recovers(played)
	_four_stages()
	_wipe()
	print("OPEN TURN FINGERPRINTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + label)

func _wipe() -> void:
	OpenTurnStore.erase_owner(HOST, ROOT)
	OpenTurnStore.erase_owner(GUEST, ROOT)
	OpenTurnStore.erase_owner("FFFFFFFFFFFFFFFFFFFFFF", ROOT)

## Each stage's routes with its first two repeated ROUNDS times before the closing one.
static func _stage_steps(stage_id: String) -> Array:
	var turns: Array = Witness.routes(TIDE)[stage_id].turns
	var steps: Array = []
	for _round in range(ROUNDS): steps.append_array([turns[0], turns[1]])
	steps.append(turns[2])
	return steps

## One turn on `phone`'s live engine, as the room screen plays it; {} when it cannot.
func _play_turn(phone: Phone, steps: Array, last: bool) -> Dictionary:
	var sim: RefCounted = phone.coordinator.create_live_simulation()
	if sim == null: return {}
	Witness._play(sim, steps)
	var limit: int = int(sim.duration_limit())
	if int(sim.turn_number) == 1: return JSON.parse_string(JSON.stringify(sim.export_recording())) if sim.can_commit() else {}
	for _tick in range(limit):
		if sim.finished or (not last and sim.can_pass()): break
		sim.step({})
	if not last:
		if not sim.can_pass(): return {}
		sim.pass_turn()
	elif not sim.complete: return {}
	return JSON.parse_string(JSON.stringify(sim.export_recording()))

func _room_plays_through() -> Dictionary:
	MemoryTrace.clear()
	KnownCheckpoints.clear()
	var server := Server.new(TIDE, ROOM, HOST, GUEST)
	var phones := {HOST: Phone.new(HOST, server, ROOT), GUEST: Phone.new(GUEST, server, ROOT)}
	for phone: Phone in phones.values():
		_check(phone.coordinator.bind_room(ROOM) and await phone.coordinator.refresh(), "Each phone opens the room (%s)" % phone.coordinator.last_code)
	var level := Registry.definition(TIDE)
	var check_costs: Array = []
	var played_turns := 0
	for stage: Dictionary in level.stages:
		var steps := _stage_steps(str(stage.id))
		for index in range(steps.size()):
			var last := index == steps.size() - 1
			var mover: Phone = phones[server._player_of(index + 1)]
			var other: Phone = phones[GUEST if mover.player == HOST else HOST]
			var recording := _play_turn(mover, steps[index], last)
			if recording.is_empty():
				_check(false, "Turn %d of %s plays on the live engine" % [index + 1, stage.id])
				return {}
			if not await mover.coordinator.commit(recording):
				_check(false, "Turn %d of %s is accepted (%s)" % [index + 1, stage.id, mover.coordinator.last_code])
				return {}
			# The other phone checks the new turn: only that turn is simulated, at every turn and stage.
			var before := MemoryTrace.simulated
			if not await other.coordinator.refresh():
				_check(false, "The partner takes turn %d of %s (%s)" % [index + 1, stage.id, other.coordinator.last_code])
				return {}
			check_costs.append(MemoryTrace.simulated - before)
			played_turns += 1
	_check(played_turns == 2 * (2 * ROUNDS + 1), "Both stages play %d turns each with fingerprints from the server" % (2 * ROUNDS + 1))
	_check(check_costs.all(func(cost: int) -> bool: return cost <= 1), "Each phone checks the partner's turn by simulating that turn alone, at every turn of both stages: %s" % str(check_costs))
	_check(server.full_after_turn.all(func(count: int) -> bool: return count <= 2), "The server holds at most the newest and a closing turn in full: %s" % str(server.full_after_turn))
	var done: bool = phones[HOST].coordinator.chapter_complete() and phones[GUEST].coordinator.chapter_complete()
	_check(done, "The room finishes on both phones")
	# A poll after the end acknowledges the final turn: the server keeps no turn in full.
	for phone: Phone in phones.values(): await phone.coordinator.refresh()
	_check(server.rows.values().all(func(row: Dictionary) -> bool: return OpenTurnStore.fingerprint(row)), "Once both phones have the final turn the server holds only fingerprints")
	_check(phones[HOST].store().held().size() == played_turns and phones[GUEST].store().held().size() == played_turns, "Each phone keeps every turn of the room")
	var flat: Dictionary = phones[GUEST].coordinator.checkpoint()
	var whole: Dictionary = phones[GUEST].coordinator.full_checkpoint()
	_check(not flat.has("proof") and whole.get("proof") is Dictionary and whole.proof.checkpoint.get("proof") is Dictionary, "The final checkpoint is flat on the server and nests both stages from the phone's copies")
	_check(OpenTurns.proof_turns(whole.proof).size() == 2 * ROUNDS + 1, "The nested stage holds every turn, passes included")
	MemoryTrace.clear()
	KnownCheckpoints.clear()
	_check(Registry.simulation_script(TIDE).verify_checkpoint(level, whole).valid, "The rebuilt run checks from scratch, as the board's replay job checks it")
	var run: Dictionary = phones[HOST].store().run_blob(TIDE)
	var bytes := BlobCodec.verified(Marshalls.base64_to_raw(str(run.get("body", ""))), int(run.get("byte_length", 0)), str(run.get("digest", "")), 4 * 1024 * 1024)
	_check(not bytes.is_empty() and Canonical.same(JSON.parse_string(bytes.get_string_from_utf8()), whole), "The posted run is the phone's nested copy in the blob format")
	return {"server": server, "phones": phones, "turns": played_turns}

func _reinstall_recovers(played: Dictionary) -> void:
	var server: RefCounted = played.server
	var host: Phone = played.phones[HOST]
	# A reinstall: no journal, no turn copies, nothing proved in memory.
	OpenTurnStore.erase_owner(GUEST, ROOT)
	KnownCheckpoints.clear()
	MemoryTrace.clear()
	var guest := Phone.new(GUEST, server, ROOT)
	_check(guest.coordinator.bind_room(ROOM), "The reinstalled phone binds the room")
	_check(not await guest.coordinator.refresh() and guest.coordinator.last_code == "turns_missing" and guest.coordinator.missing_turns().size() == played.turns, "It asks for every turn it lost (%s, %d)" % [guest.coordinator.last_code, guest.coordinator.missing_turns().size()])
	_check(server.wanted.get(GUEST, []).size() == played.turns, "The server keeps the want, not the turns")
	# The partner's next poll sends them back from its own copies.
	_check(await host.coordinator.refresh(), "The partner's poll still reads the room")
	_check(server.copies.size() == played.turns, "The partner's phone sent back every wanted turn")
	_check(await guest.coordinator.refresh() and guest.coordinator.chapter_complete(), "The reinstalled phone takes the finished room again (%s)" % guest.coordinator.last_code)
	_check(guest.store().held().size() == played.turns and server.copies.is_empty() and server.wanted.get(GUEST, []).is_empty(), "Its copies are back and the server let go of the sent-back turns")
	_check(guest.coordinator.full_checkpoint().get("proof") is Dictionary, "Its replays nest again from its own copies")

## A counting engine for a four stage room: a turn is simulated the first time
## it is checked, a checkpoint derives only over a previous one proved here.
class Counting:
	extends RefCounted
	var simulated := 0
	var seen: Dictionary = {}
	func check(turn: Dictionary) -> void:
		if seen.has(turn.recording_hash): return
		seen[turn.recording_hash] = true
		simulated += 1
	func derive_checkpoint(_definition: Dictionary, previous: Dictionary, first: Dictionary, second: Dictionary, passes: Array = []) -> Dictionary:
		if int(previous.stage_index) > 0 and not previous.has("proof") and not KnownCheckpoints.known(str(previous.checkpoint_hash)): return {"valid": false}
		var turns: Array = [first] + passes + [second]
		for turn: Dictionary in turns: check(turn)
		var value := {"schema_version": 8, "stage_index": int(previous.stage_index) + 1, "previous_checkpoint_hash": previous.checkpoint_hash, "turn_hashes": turns.map(func(turn: Dictionary) -> String: return turn.recording_hash)}
		value["checkpoint_hash"] = Canonical.digest(value)
		KnownCheckpoints.keep(value.checkpoint_hash)
		value["proof"] = {"checkpoint": previous, "turns": turns}
		return {"valid": true, "checkpoint": value}

static func _turn(stage: int, number: int) -> Dictionary:
	var record := {"stage": stage, "number": number, "packed": "AQID".repeat(number), "role": "a" if number == 1 else "b"}
	record["recording_hash"] = Canonical.digest(record)
	return record

func _four_stages() -> void:
	KnownCheckpoints.clear()
	var engine := Counting.new()
	var player := "FFFFFFFFFFFFFFFFFFFFFF"
	var copies := OpenTurnStore.new(player, ROOM, ROOT)
	var level := Registry.definition(TIDE)
	var checkpoint := Registry.initial_checkpoint(TIDE)
	var per_stage: Array = []
	var turns_a_stage := 12
	for stage in range(4):
		var before := engine.simulated
		var turns: Array = []
		for number in range(1, turns_a_stage + 1):
			var turn := _turn(stage, number)
			# The room view carries the newest turn in full and the rest by hash.
			var view := {"stage_index": stage, "recording_a": OpenTurnStore.strip(turns[0] if not turns.is_empty() else turn), "open_turns": {"turn_hashes": turns.map(func(item: Dictionary) -> String: return item.recording_hash) + [turn.recording_hash], "newest": turn}}
			var found: Dictionary = copies.stage_turns(view)
			if found.turns.size() != number:
				_check(false, "Stage %d turn %d plays over this phone's copies (%s)" % [stage + 1, number, str(found.missing)])
				return
			engine.check(turn)
			copies.keep_turn(stage, turn)
			turns.append(turn)
		# The closing turn's checkpoint arrives flat; this phone proves it from its copies.
		var flat: Dictionary = KnownCheckpoints.flat(engine.derive_checkpoint(level, checkpoint, turns[0], turns[-1], turns.slice(1, turns.size() - 1)).checkpoint)
		KnownCheckpoints.clear()
		if stage > 0: copies.trust_all()
		var learned: Dictionary = copies.learn(engine, level, TIDE, flat, turns[-1])
		_check(learned.valid, "Stage %d's flat checkpoint is proved from this phone's copies, the stage before by hash" % (stage + 1))
		per_stage.append(engine.simulated - before)
		checkpoint = flat
	_check(per_stage.all(func(count: int) -> bool: return count == turns_a_stage), "Each of four stages simulates only its own %d turns, however many stages came before: %s" % [turns_a_stage, str(per_stage)])
	var whole: Dictionary = copies.nested(TIDE, checkpoint)
	var depth := 0
	var current := whole
	while current.get("proof") is Dictionary and not current.proof.is_empty():
		_check(current.proof.turns.size() == turns_a_stage, "Nested stage %d holds every turn" % (4 - depth))
		depth += 1
		current = current.proof.checkpoint
	_check(depth == 4 and Canonical.same(current, Registry.initial_checkpoint(TIDE)), "Nesting the last checkpoint reads all four stages back to the start")
	OpenTurnStore.erase_owner(player, ROOT)
	_check(copies.nested(TIDE, checkpoint).is_empty() and not DirAccess.dir_exists_absolute(ROOT.path_join(player)), "An erased identity's copies are gone")

func _core_flat_checkpoints() -> void:
	KnownCheckpoints.clear()
	var level := Registry.definition(TIDE)
	var engine: Script = Registry.simulation_script(TIDE)
	var nested: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/journey/turn-of-the-tide-v3-set-the-tide-checkpoint.json"))
	var flat := KnownCheckpoints.flat(nested)
	_check(not engine.verify_checkpoint(level, flat).valid, "A flat checkpoint this phone never proved is refused")
	_check(engine.verify_checkpoint(level, nested).valid and engine.verify_checkpoint(level, flat).valid, "Once its nested form checks, the flat one passes by hash")
	var forged := flat.duplicate(true)
	forged.players.p0.x = int(forged.players.p0.x) + 1
	_check(not engine.verify_checkpoint(level, forged).valid, "A flat checkpoint that does not hash to itself is refused")
	# Published rules never take a flat checkpoint.
	var published: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/journey/turn-of-the-tide-v2-final-checkpoint.json"))
	var chapter := Registry.resolve(published)
	var script: Script = Registry.simulation_script(chapter)
	var definition := Registry.definition(chapter)
	_check(script.verify_checkpoint(definition, published).valid and not script.verify_checkpoint(definition, KnownCheckpoints.flat(published)).valid, "Rules before open turns still need the nested proof (%s)" % chapter)
