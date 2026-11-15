extends RefCounted
## A developer run (content/dev_ghosts.json) played again packed
## (core/v2/recording_codec.gd), shared by test_recording_codec.gd and
## test_recording_codec_runs.gd. A turn replays from the packed run's own chain
## and each stage's checkpoint is derived from its packed turns, which verifies
## both turns; turn b, the one that depends on the packed turn a, walks the JSON
## run's positions. Without `full` only the first stage plays (each chapter's
## round trip, kept fast). `full` plays every stage and adds the slower checks
## one board needs: the JSON turn plays back exactly, packed exports repeat, each
## turn verifies on its own, turn a's positions, a bad check gives no ghost, the
## whole run reads back from its blob and the whole chain verifies again.
const Codec = preload("res://core/v2/recording_codec.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Track = preload("res://services/race_ghost_track.gd")
const TheirRun = preload("res://services/duel_their_run.gd")
const BlobCodec = preload("res://services/blob_codec.gd")
const Coordinator = preload("res://services/relay_room_coordinator.gd")

## False when the board's family never records packed. `check` is (okay: bool, message: String).
static func run(row: Dictionary, check: Callable, full: bool) -> bool:
	var key := str(row.board)
	var engine: Script = Registry.simulation_script(key)
	if not "packed_recordings" in engine.new(): return false
	var parts := TheirRun.parts({"digest": row.proof_hash, "byte_length": int(row.byte_length), "body": row.body}, key)
	check.call(not parts.is_empty(), "%s decodes" % key)
	if parts.is_empty(): return true
	var level := Registry.definition(key)
	var before := 0
	var after := 0
	# Each stage starts from the checkpoint its packed turns made.
	var chained := Registry.previous_checkpoint(key, parts[0].pair.checkpoint)
	for part: Dictionary in (parts if full else parts.slice(0, 1)):
		var pair: Dictionary = part.pair
		var where := "%s stage %d" % [key, int(pair.stage_index)]
		var start := chained
		var a := play(key, level, pair.a, start, {}, true)
		var b := play(key, level, pair.b, start, a, true)
		check.call(Codec.is_packed(a) and Codec.is_packed(b) and not a.has("actions") and not b.has("replay_checks"), "%s: both turns export packed" % where)
		check.call(Canonical.same(Codec.actions(a), pair.a.actions) and Canonical.same(Codec.actions(b), pair.b.actions), "%s: the same runs" % where)
		var derived: Dictionary = engine.derive_checkpoint(level, start, a, b)
		check.call(derived.get("valid", false), "%s: the packed turns verify and make the stage's checkpoint" % where)
		if not derived.get("valid", false): return true
		chained = derived.checkpoint
		if int(pair.stage_index) == 0:
			# The first set-up is the JSON run's own, so the state hashes are too (they name the set-up's checkpoint).
			check.call(a.final_state_hash == pair.a.final_state_hash, "%s: turn a ends on the same state" % where)
			var listed: Dictionary = {}
			for item: Dictionary in pair.a.replay_checks: listed[int(item.tick)] = str(item.state_hash)
			var prefixes := true
			for item: Dictionary in Codec.checks(a): prefixes = prefixes and Codec.check_matches(item.state_hash, str(listed.get(int(item.tick), "")))
			check.call(prefixes, "%s: turn a's checks are the first bytes of the same state hashes" % where)
		var packed_pair := {"stage_index": pair.stage_index, "a": a, "b": b, "checkpoint": chained}
		var roles := ["a", "b"] if full else ["b"]
		for role: String in roles:
			var track := Track.build(key, packed_pair, role)
			check.call(not track.is_empty() and track.points == Track.build(key, pair, role).points, "%s turn %s: the same positions every tick" % [where, role])
		if full:
			var json_start := Registry.previous_checkpoint(key, pair.checkpoint)
			check.call(Canonical.same(play(key, level, pair.a, json_start, {}, false), pair.a), "%s: the JSON turn a plays back exactly" % where)
			check.call(Canonical.same(play(key, level, pair.a, start, {}, true), a), "%s: a packed export is the same every time" % where)
			check.call(engine.verify_recording(level, a, start).valid and engine.verify_recording(level, b, start, a).valid, "%s: each packed turn verifies on its own" % where)
			if Codec.checks(a).size() > 1:
				var off := packed_pair.duplicate(true)
				var bytes := Marshalls.base64_to_raw(off.a.packed)
				bytes[bytes.size() - 1] ^= 1
				off.a.packed = Marshalls.raw_to_base64(bytes)
				check.call(Track.build(key, off, "a").is_empty(), "%s: a check that does not match gives no ghost" % where)
		for record: Dictionary in [pair.a, pair.b]: before += deflated(record)
		for record: Dictionary in [a, b]: after += deflated(record)
	print("%s: %d turns, deflated %d bytes as JSON, %d packed" % [key, (parts.size() if full else 1) * 2, before, after])
	if not full: return true
	# The whole packed run as a board replay, a duel's run or a race ghost reads it: the blob, its parts and the room bound.
	var run_bytes := JSON.stringify(Canonical.normalized(chained)).to_utf8_buffer()
	var kept := {"digest": BlobCodec.digest(run_bytes), "byte_length": run_bytes.size(), "body": Marshalls.raw_to_base64(BlobCodec.encode(run_bytes))}
	var read := TheirRun.parts(kept, key)
	check.call(read.size() == parts.size() and Coordinator._bounded(chained) and Canonical.same(read[-1].pair.checkpoint, chained), "%s: the packed run reads back whole from its blob" % key)
	check.call(engine.verify_checkpoint(level, chained).valid, "%s: the whole packed run verifies" % key)
	var json_bytes := JSON.stringify(Canonical.normalized(parts[-1].pair.checkpoint)).to_utf8_buffer()
	print("%s whole run: %d raw / %d deflated as JSON, %d / %d packed" % [key, json_bytes.size(), json_bytes.compress(FileAccess.COMPRESSION_DEFLATE).size(), run_bytes.size(), run_bytes.compress(FileAccess.COMPRESSION_DEFLATE).size()])
	return true

static func play(key: String, level: Dictionary, record: Dictionary, start: Dictionary, prior: Dictionary, packed: bool) -> Dictionary:
	var sim: RefCounted = Registry.simulation_script(key).new()
	if not Registry.reset_simulation(sim, key, level, str(record.stage_id), start, prior, str(record.role), record): return {}
	sim.packed_recordings = packed
	sim.catch_assistance = bool(record.get("catch_assistance", false))
	for input: Dictionary in Registry.simulation_script(key).expand_recording_inputs(record):
		if bool(sim.get("finished")): break
		sim.step(input)
	return sim.export_recording()

static func deflated(record: Dictionary) -> int:
	return JSON.stringify(Canonical.normalized(record)).to_utf8_buffer().compress(FileAccess.COMPRESSION_DEFLATE).size()
