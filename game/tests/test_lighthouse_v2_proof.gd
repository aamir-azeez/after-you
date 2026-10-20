extends SceneTree
## sleeping-lighthouse@2: the six Lighthouse stages as one shared-format
## chapter. Replays the frozen six-stage solo inputs through the facade, checks
## the shared record and checkpoint shape, rebuilds the committed v2 fixture,
## refuses tampering at every depth, and checks the verified-checkpoint memo.
## AFTER_YOU_WRITE_LIGHTHOUSE_V2=<absolute path> rewrites the fixture.
const Native = preload("res://core/lighthouse/borrowed_light.gd")
const LightCatalog = preload("res://core/lighthouse/stage_catalog.gd")
const Catalog = preload("res://core/lighthouse/room_catalog.gd")
const Room = preload("res://core/lighthouse/room_simulation.gd")
const RoomProof = preload("res://core/lighthouse/room_proof.gd")
const Proof = preload("res://core/physical/two_pair_proof.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Controls = preload("res://core/first_steps/simulation.gd")
const FIXTURE := "res://tests/fixtures/lighthouse/v2-chain.json"
## Solo @1 stays byte-identical: LF-normalized md5 of the engine and catalog.
## Editing either also needs RoomProof.VERIFIER_VERSION bumped.
const ENGINE_MD5 := "d9c36f858582a39f1c06ced43647a559"
const NATIVE_CATALOG_MD5 := "0a04ea684908e0cd7174558d3328856e"
## Backend LIGHTHOUSE_LIMITS (protocol-lighthouse.ts) and published bounds.
const LIMIT_CHECKPOINT_BYTES := 393216
const LIMIT_CHECKPOINT_VALUES := 40000
const LIMIT_BODY_BYTES := 425984
const LIMIT_BODY_VALUES := 44000
const MAX_DEPTH := 16
const PUBLISHED_BODY_BYTES := 327680
const INDEX_PATH := "user://lighthouse-v2-verified-test.json"
var checks := 0
var failures := 0
var fixture: Dictionary = {}
var level: Dictionary = {}
var chain: Array = []
var checkpoints: Array = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	fixture = _json("res://tests/fixtures/lighthouse/complete-six-v3.json")
	_check(not fixture.is_empty(), "solo six-stage fixture parses")
	_check(_md5("res://core/lighthouse/borrowed_light.gd") == ENGINE_MD5, "borrowed_light.gd is unchanged")
	_check(_md5("res://core/lighthouse/stage_catalog.gd") == NATIVE_CATALOG_MD5, "native stage_catalog.gd is unchanged")
	_check(Native.checkpoint_from_pairs(fixture.pairs).valid, "the solo six-stage v3 chain still verifies natively")
	level = Catalog.definition()
	_definition_checks()
	RoomProof.clear_memo()
	var started := Time.get_ticks_msec()
	_play_chain()
	print("LIGHTHOUSE_V2 phase _play_chain: %d ms" % [Time.get_ticks_msec() - started])
	if checkpoints.size() == 7:
		for phase: Callable in [_fixture_checks, _final_checks, _negative, _memo_checks, _index_checks, _sizes]:
			var begun := Time.get_ticks_msec()
			phase.call()
			print("LIGHTHOUSE_V2 phase %s: %d ms" % [phase.get_method(), Time.get_ticks_msec() - begun])
	_finish()

func _definition_checks() -> void:
	_check(level.stages.size() == 6, "one chapter with six stages")
	_check(int(level.schema_version) == 8 and int(level.simulation_version) == 11 and int(level.version) == 2 and level.premium == true, "schema 8, rules 11, version 2, premium")
	_check(Catalog.known(level), "the catalog knows its own definition")
	var roundtrip: Variant = JSON.parse_string(JSON.stringify(level))
	_check(roundtrip is Dictionary and Catalog.known(roundtrip), "the definition is still known after a JSON round trip")
	for stage: Dictionary in level.stages:
		_check(Canonical.same(stage.native, LightCatalog.definition(stage.id)), "embedded %s equals the native catalog stage" % stage.id)
	var slots: Array = []
	for stage: Dictionary in level.stages: slots.append(stage.first_player_slot)
	_check(slots == ["p0", "p1", "p0", "p1", "p0", "p1"], "first player alternates host / friend per stage: %s" % [slots])
	var initial := Catalog.initial_checkpoint(level)
	_check(Room.verify_checkpoint(level, initial).valid, "the initial checkpoint verifies")
	var other := level.duplicate(true)
	other.title = "Other"
	_check(not Room.verify_checkpoint(other, initial).valid, "an edited definition is unknown")
	print("LIGHTHOUSE_V2 definition hash ", Canonical.digest(level), " bytes ", _bytes(level))

func _play_chain() -> void:
	var checkpoint := Catalog.initial_checkpoint(level)
	checkpoints.append(checkpoint)
	for index in 6:
		var pair: Dictionary = fixture.pairs[index]
		var stage_id: String = level.stages[index].id
		var a := Room.new()
		var ok_a := a.reset(level, stage_id, checkpoint, {}, "a")
		_check(ok_a, "stage %d %s: A resets on the room checkpoint (%s)" % [index + 1, stage_id, a.error])
		if not ok_a: return
		for input: Dictionary in Native.expand_recording_inputs(pair.a): a.step(input)
		var a_state := a.snapshot()
		_check(a_state.can_commit, "stage %d: A can commit" % [index + 1])
		var a_record := a.export_recording()
		_check(_keys_match(a_record, Controls.RECORD_KEYS), "stage %d: A record has exactly the shared 20 keys" % [index + 1])
		_check(a_record.outcome == {"source_ready": true, "objective_complete": false} and a_record.catch_assistance == false and int(a_record.schema_version) == 8 and int(a_record.simulation_version) == 11,
			"stage %d: A outcome, catch_assistance, schema and rules are the shared shape" % [index + 1])
		_check(_scaled(a_record), "stage %d: A actions are on the shared +-100 scale" % [index + 1])
		_check(a_record.definition_hash == Canonical.digest(level) and a_record.checkpoint_hash == checkpoint.checkpoint_hash, "stage %d: A names the chapter hash and the room checkpoint" % [index + 1])
		var a_check: Dictionary = Room.verify_recording(level, a_record, checkpoint)
		_check(a_check.valid and a_check.snapshot.can_commit, "stage %d: A record verifies (%s)" % [index + 1, a_check.get("error", "")])
		_check(Room.recording_error(level, a_record, checkpoint).is_empty(), "stage %d: A passes the coordinator's structural check" % [index + 1])
		var b := Room.new()
		var ok_b := b.reset(level, stage_id, checkpoint, a_record, "b")
		_check(ok_b, "stage %d: B resets on the A ghost (%s)" % [index + 1, b.error])
		if not ok_b: return
		for input: Dictionary in Native.expand_recording_inputs(pair.b):
			if b.finished: break
			b.step(input)
		_check(b.snapshot().complete, "stage %d: B completes" % [index + 1])
		var b_record := b.export_recording()
		_check(b_record.outcome == {"source_ready": true, "objective_complete": true} and b_record.completed == true and b_record.source_recording_hash == a_record.recording_hash,
			"stage %d: B outcome is the shared shape and names A" % [index + 1])
		var derived: Dictionary = Room.derive_checkpoint(level, checkpoint, a_record, b_record)
		_check(derived.valid, "stage %d: the pair derives checkpoint %d (%s)" % [index + 1, index + 1, derived.get("error", "")])
		if not derived.valid: return
		var raw: Dictionary = Room._verify_raw(level, b_record, checkpoint, a_record)
		_check(raw.valid and Canonical.same(Room._build_checkpoint(level, checkpoint, a_record, b_record, raw.snapshot), derived.checkpoint), "stage %d: the journal surface builds the same checkpoint" % [index + 1])
		chain.append({"checkpoint": checkpoint, "a": a_record, "b": b_record})
		checkpoint = derived.checkpoint
		checkpoints.append(checkpoint)
		_check(_nesting(checkpoint) == index + 1, "checkpoint %d nests exactly %d proofs" % [index + 1, index + 1])
		print("LIGHTHOUSE_V2 stage %d %s A=%d B=%d ticks; record bytes A=%d B=%d; checkpoint bytes=%d values=%d depth=%d" % [index + 1, stage_id,
			int(a_record.duration_ticks), int(b_record.duration_ticks), _bytes(a_record), _bytes(b_record), _bytes(checkpoint), _values(checkpoint), _depth(checkpoint)])

func _fixture_checks() -> void:
	var data := {"definition": level, "initial": checkpoints[0], "pairs": [], "checkpoints": checkpoints}
	for item: Dictionary in chain: data.pairs.append({"a": item.a, "b": item.b})
	var out := OS.get_environment("AFTER_YOU_WRITE_LIGHTHOUSE_V2")
	if not out.is_empty():
		var file := FileAccess.open(out, FileAccess.WRITE)
		_check(file != null, "fixture export opens " + out)
		if file:
			file.store_string(JSON.stringify(Canonical.normalized(data)))
			file.close()
	var committed := _json(FIXTURE)
	_check(Canonical.same(committed, data), "the committed v2 fixture equals the rebuilt chain")
	_check(not committed.is_empty() and Canonical.digest(committed.get("definition", {})) == Canonical.digest(level), "the committed definition has the chapter hash")

func _final_checks() -> void:
	var final: Dictionary = checkpoints[6]
	_check(final.next_stage_id == "" and int(final.stage_index) == 6, "the final checkpoint has no next stage")
	var native: Dictionary = fixture.checkpoints[6]
	for slot: String in ["p0", "p1"]:
		_check(int(final.players[slot].x) == int(native.players[slot].x) and int(final.players[slot].z) == int(native.players[slot].z) and final.players[slot].surface_id == native.players[slot].surface_id,
			"final %s position equals the solo v3 chain" % slot)
	for key: String in ["latched_bridges", "mirrors", "props", "flags"]:
		_check(Canonical.same(final.mechanisms[key], native.mechanisms[key]), "final mechanisms.%s equal the solo v3 chain" % key)
	RoomProof.clear_memo()
	var t0 := Time.get_ticks_msec()
	var roundtrip: Variant = JSON.parse_string(JSON.stringify(final))
	_check(roundtrip is Dictionary and Room.verify_checkpoint(level, roundtrip).valid, "the final checkpoint verifies cold after a JSON round trip")
	print("LIGHTHOUSE_V2 cold full verify of checkpoint 6: %d ms, %d pair replays" % [Time.get_ticks_msec() - t0, RoomProof.Memo.pair_replays])
	for index in range(1, 7):
		var room_cp: Dictionary = checkpoints[index]
		var solo_cp: Dictionary = fixture.checkpoints[index]
		var same := Canonical.same(room_cp.mechanisms.latched_bridges, solo_cp.mechanisms.latched_bridges) and Canonical.same(room_cp.mechanisms.props, solo_cp.mechanisms.props) and Canonical.same(room_cp.mechanisms.flags, solo_cp.mechanisms.get("flags", {}))
		_check(same, "checkpoint %d mechanisms equal solo checkpoint %d" % [index, index])

## Every case a memo could change, as [label, checkpoint].
func _cases() -> Array:
	var final: Dictionary = checkpoints[6]
	var cases: Array = []
	for index in 7: cases.append(["checkpoint %d" % index, checkpoints[index]])
	for depth in range(0, 6):
		var forged := final.duplicate(true)
		var node: Dictionary = forged
		for i in depth: node = node.proof.checkpoint
		node.proof.b.actions[0].ticks = int(node.proof.b.actions[0].ticks) + 1
		node.proof.b.recording_hash = Controls.recording_hash(node.proof.b)
		cases.append(["a re-hashed B record tampered %d levels deep" % depth, forged])
	var too_deep := final.duplicate(true)
	too_deep.stage_index = 7
	cases.append(["a checkpoint past the last stage", too_deep])
	var skipped := final.duplicate(true)
	skipped.proof.checkpoint = checkpoints[4].duplicate(true)
	cases.append(["a chain that skips a stage", skipped])
	var shell := final.duplicate(true)
	shell.mechanisms.flags.erase("beacon-lit")
	shell.checkpoint_hash = Catalog.checkpoint_hash(shell)
	cases.append(["a re-hashed final checkpoint with a dropped flag", shell])
	var swapped: Dictionary = checkpoints[3].duplicate(true)
	swapped.proof.a = chain[1].a.duplicate(true)
	cases.append(["checkpoint 3 with stage 2's A record", swapped])
	return cases

func _negative() -> void:
	for item: Array in _cases().slice(7):
		_check(not Room.verify_checkpoint(level, item[1]).valid, "%s is refused" % item[0])
	var wrong_stage: Dictionary = chain[2].a.duplicate(true)
	_check(not Room.verify_recording(level, wrong_stage, checkpoints[3]).valid, "a stage-3 record is refused at the stage-4 checkpoint")
	var analog: Dictionary = chain[0].a.duplicate(true)
	analog.actions[0].x = 50
	analog.recording_hash = Controls.recording_hash(analog)
	_check(not Room.verify_recording(level, analog, checkpoints[0]).valid, "an off-grid (analog) action does not replay to the same record")
	_check(not Room.verify_recording(level, fixture.pairs[0].a, checkpoints[0]).valid, "a native schema-3 record is refused by the @2 chapter")
	var downgraded: Dictionary = chain[0].a.duplicate(true)
	downgraded.simulation_version = 9
	downgraded.recording_hash = Controls.recording_hash(downgraded)
	_check(not Room.verify_recording(level, downgraded, checkpoints[0]).valid, "a record claiming rules 9 is refused (pinned to 11)")
	var long: Dictionary = chain[0].a.duplicate(true)
	long.actions.append({"ticks": 600, "x": 0, "z": 0, "action": false})
	long.duration_ticks = int(long.duration_ticks) + 600
	long.replay_checks.append({"tick": int(long.duration_ticks), "state_hash": long.final_state_hash})
	long.recording_hash = Controls.recording_hash(long)
	_check(not Room.verify_recording(level, long, checkpoints[0]).valid, "a record past the 600-tick turn is refused")
	var wrong_slot: Dictionary = chain[1].a.duplicate(true)
	wrong_slot.player_slot = "p0"
	wrong_slot.recording_hash = Controls.recording_hash(wrong_slot)
	_check(not Room.recording_error(level, wrong_slot, checkpoints[1]).is_empty(), "stage 2's A is the friend (p1)")
	var b := Room.new()
	_check(not b.reset(level, level.stages[0].id, checkpoints[0], {}, "b"), "B cannot reset without a ready A")
	var two := level.duplicate(true)
	two.stages = two.stages.slice(0, 2)
	_check(not Proof.new(Catalog, Room, 11, 8).verify_checkpoint(two, checkpoints[3]).valid, "a two-stage view of the definition cannot verify checkpoint 3")

func _memo_checks() -> void:
	var cases := _cases()
	# Cold results for every refusal and both ends of the valid chain (the
	# middle checkpoints are checked cold through checkpoint 6's recursion).
	var cold: Array = []
	for i in cases.size():
		if i in [1, 2, 3, 4, 5]:
			cold.append({"valid": true, "error": ""})
			continue
		RoomProof.clear_memo()
		cold.append(Room.verify_checkpoint(level, cases[i][1]))
	RoomProof.clear_memo()
	for index in 7: _check(Room.verify_checkpoint(level, checkpoints[index]).valid, "warming checkpoint %d" % index)
	_check(RoomProof.memo_size() == 7, "the warmed memo holds the seven chain checkpoints (%d)" % RoomProof.memo_size())
	for i in cases.size():
		var warm: Dictionary = Room.verify_checkpoint(level, cases[i][1])
		_check(Canonical.same(warm, cold[i]), "memo equivalence: %s gives the same result cold and warm (%s)" % [cases[i][0], warm.error])
	for i in range(7, cases.size()):
		_check(not _memo_has(cases[i][1]), "a refusal is never remembered: %s" % cases[i][0])
	RoomProof.clear_memo()
	_check(Room.verify_checkpoint(level, checkpoints[6]).valid and RoomProof.Memo.pair_replays == 6, "a cold stage-6 check replays six pairs (%d)" % RoomProof.Memo.pair_replays)
	var before: int = RoomProof.Memo.pair_replays
	_check(Room.verify_checkpoint(level, checkpoints[6]).valid and RoomProof.Memo.pair_replays == before, "a repeated check replays nothing")
	RoomProof.clear_memo()
	_check(Room.verify_checkpoint(level, checkpoints[5]).valid, "checkpoint 5 verifies")
	before = RoomProof.Memo.pair_replays
	_check(Room.verify_checkpoint(level, checkpoints[6]).valid and RoomProof.Memo.pair_replays - before == 1, "after checkpoint 5, checkpoint 6 costs one pair (%d)" % [RoomProof.Memo.pair_replays - before])
	var roundtrip: Variant = JSON.parse_string(JSON.stringify(checkpoints[6]))
	before = RoomProof.Memo.pair_replays
	_check(Room.verify_checkpoint(level, roundtrip).valid and RoomProof.Memo.pair_replays == before, "a JSON round trip of a verified checkpoint is a memo hit")
	before = RoomProof.Memo.pair_replays
	var receiver := Room.new()
	_check(receiver.reset(level, level.stages[5].id, checkpoints[5], chain[5].a, "b") and RoomProof.Memo.pair_replays == before, "B's reset on a verified stage-6 checkpoint replays no pair")
	var mutated: Dictionary = checkpoints[6].duplicate(true)
	mutated.proof.checkpoint.proof.a.actions[0].action = not bool(mutated.proof.checkpoint.proof.a.actions[0].action)
	_check(not Room.verify_checkpoint(level, mutated).valid, "a changed byte inside a remembered ancestor is checked again and refused")
	var plain := Proof.new(Catalog, Room, Catalog.RULES, Catalog.SCHEMA)
	_check(plain.verify_checkpoint(level, checkpoints[6]).valid and not plain.verify_checkpoint(level, mutated).valid, "the shared proof without the memo agrees")

func _index_checks() -> void:
	RoomProof.clear_memo()
	for index in 7: Room.verify_checkpoint(level, checkpoints[index])
	var exported := RoomProof.export_memo()
	_check(exported.keys.size() == 7 and exported.stamp == RoomProof.stamp(), "the memo exports its keys under the current stamp")
	RoomProof.clear_memo()
	_check(RoomProof.import_memo(exported) == 7 and RoomProof.memo_size() == 7, "an export imports back")
	_check(Room.verify_checkpoint(level, checkpoints[6]).valid and RoomProof.Memo.pair_replays == 0, "imported keys spare every pair replay")
	RoomProof.clear_memo()
	var stale := exported.duplicate(true)
	stale.stamp = "sleeping-lighthouse@2|11|0|old"
	_check(RoomProof.import_memo(stale) == 0, "another stamp is ignored")
	var malformed := exported.duplicate(true)
	malformed.keys.append("not-a-digest")
	_check(RoomProof.import_memo(malformed) == 0 and RoomProof.memo_size() == 0, "a malformed key list is ignored whole")
	var extra := exported.duplicate(true)
	extra["more"] = true
	_check(RoomProof.import_memo(extra) == 0, "unknown fields are ignored whole")
	RoomProof.import_memo(exported)
	_check(RoomProof.save_index(INDEX_PATH), "the index saves")
	RoomProof.clear_memo()
	_check(RoomProof.load_index(INDEX_PATH) == 7, "the saved index loads back after a restart")
	_check(not FileAccess.file_exists(INDEX_PATH + ".tmp") and not FileAccess.file_exists(INDEX_PATH + ".backup"), "no temporary or backup file is left")
	RoomProof.clear_memo()
	var big := FileAccess.open(INDEX_PATH, FileAccess.WRITE)
	big.store_string(" ".repeat(RoomProof.INDEX_MAX_BYTES + 1))
	big.close()
	_check(RoomProof.load_index(INDEX_PATH) == 0, "an oversized index is ignored")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(INDEX_PATH))
	_check(RoomProof.load_index("user://missing-lighthouse-index.json") == 0, "a missing index loads nothing")

func _sizes() -> void:
	var final: Dictionary = checkpoints[6]
	var last: Dictionary = chain[5]
	var body := {"base_revision": 11, "idempotency_key": "lighthouse-v2-000000000000000", "branch": 0, "recording": last.b, "checkpoint": final}
	print("LIGHTHOUSE_V2 real final checkpoint bytes=%d values=%d depth=%d; B turn body bytes=%d values=%d depth=%d" % [_bytes(final), _values(final), _depth(final), _bytes(body), _values(body), _depth(body)])
	_check(_bytes(body) < PUBLISHED_BODY_BYTES and _depth(body) == MAX_DEPTH, "a real stage-6 receiver body fits the published body bound at depth 16")
	# Structural worst case: every record widened to 600 one-tick entries.
	var widest := _widen(final)
	var wide_body := {"base_revision": 11, "idempotency_key": "lighthouse-v2-000000000000000", "branch": 0, "recording": _wide_record(last.b), "checkpoint": widest}
	print("LIGHTHOUSE_V2 dense checkpoint bytes=%d values=%d depth=%d; body bytes=%d values=%d depth=%d" % [_bytes(widest), _values(widest), _depth(widest), _bytes(wide_body), _values(wide_body), _depth(wide_body)])
	_check(_bytes(widest) <= LIMIT_CHECKPOINT_BYTES and _values(widest) <= LIMIT_CHECKPOINT_VALUES, "a dense 600-tick stage-6 checkpoint fits the chapter checkpoint limits")
	_check(_bytes(wide_body) <= LIMIT_BODY_BYTES and _values(wide_body) <= LIMIT_BODY_VALUES and _depth(wide_body) <= MAX_DEPTH, "a dense 600-tick stage-6 receiver body fits the chapter body limits and depth 16")
	_check(_bytes(wide_body) > PUBLISHED_BODY_BYTES, "the dense body needs the chapter's own body bound")

func _widen(checkpoint: Dictionary) -> Dictionary:
	var result := checkpoint.duplicate(true)
	var node: Dictionary = result
	while node.get("proof") is Dictionary and not node.proof.is_empty():
		node.proof.a = _wide_record(node.proof.a)
		node.proof.b = _wide_record(node.proof.b)
		node = node.proof.checkpoint
	return result

func _wide_record(record: Dictionary) -> Dictionary:
	var result := record.duplicate(true)
	var actions: Array = []
	for i in 600: actions.append({"ticks": 1, "x": -100, "z": -100 if i % 2 == 0 else 100, "action": false})
	result.actions = actions
	result.duration_ticks = 600
	var checks_list: Array = []
	for i in range(1, 21): checks_list.append({"tick": i * 30, "state_hash": record.final_state_hash})
	result.replay_checks = checks_list
	return result

func _memo_has(checkpoint: Dictionary) -> bool:
	return RoomProof.export_memo().keys.has(Canonical.digest(checkpoint))

func _md5(path: String) -> String:
	return FileAccess.get_file_as_string(path).replace("\r\n", "\n").md5_text()

func _json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

func _keys_match(value: Dictionary, keys: Array) -> bool:
	if value.size() != keys.size(): return false
	for key: String in keys:
		if not value.has(key): return false
	return true

func _scaled(record: Dictionary) -> bool:
	for run: Dictionary in record.actions:
		if absi(int(run.x)) not in [0, 100] or absi(int(run.z)) not in [0, 100]: return false
	return true

func _nesting(checkpoint: Dictionary) -> int:
	var count := 0
	var node: Dictionary = checkpoint
	while node.get("proof") is Dictionary and not node.proof.is_empty():
		count += 1
		node = node.proof.checkpoint
	return count

func _bytes(value: Dictionary) -> int:
	return JSON.stringify(Canonical.normalized(value)).to_utf8_buffer().size()

func _values(value: Variant) -> int:
	var count := 1
	if value is Dictionary:
		for key: Variant in value: count += _values(value[key])
	elif value is Array:
		for item: Variant in value: count += _values(item)
	return count

## Depth as the backend's iterative preflight counts it (root = 0; every child +1).
func _depth(value: Variant, at: int = 0) -> int:
	var deepest := at
	if value is Dictionary:
		for key: Variant in value: deepest = maxi(deepest, _depth(value[key], at + 1))
	elif value is Array:
		for item: Variant in value: deepest = maxi(deepest, _depth(item, at + 1))
	return deepest

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)
		print("FAIL: ", label)
	else:
		print("ok: ", label)

func _finish() -> void:
	print("LIGHTHOUSE_V2: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
