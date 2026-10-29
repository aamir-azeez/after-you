extends SceneTree
## tests/leaderboard_replay_check.gd: the offline replay check the leaderboard
## job runs on waiting runs. A real Lighthouse run (catch assistance is always
## off there) passes and is measured; a changed claim, a changed recording, an
## unfinished run, an assisted run and an unknown chapter fail.
const Check = preload("res://tests/leaderboard_replay_check.gd")
const Registry = preload("res://services/chapter_registry.gd")
const BlobCodec = preload("res://services/blob_codec.gd")

var checks := 0
var failures := 0
func _initialize() -> void: _run.call_deferred()
func _check(okay: bool, message: String) -> void:
	checks += 1
	if not okay: failures += 1; push_error(message)

func _entry(key: String, checkpoint: Dictionary, ticks: int) -> Dictionary:
	var descriptor := Registry.descriptor(key)
	return {"board": "%s@%d" % [descriptor.level_id, descriptor.level_version], "entry_id": "e".repeat(32), "proof_hash": "f".repeat(64), "ticks": ticks,
		"chapter": {"level_id": descriptor.level_id, "level_version": descriptor.level_version, "definition_hash": descriptor.definition_hash}, "checkpoint": checkpoint}

## The JSON round trip the job's input takes, so numbers arrive as the job reads them.
func _as_received(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value))

func _run() -> void:
	var chain: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/lighthouse/v2-chain.json"))
	var final: Dictionary = chain.checkpoints[-1]
	var ticks := 0
	for pair: Dictionary in chain.pairs: ticks += int(pair.a.duration_ticks) + int(pair.b.duration_ticks)
	var lighthouse := Registry.LIGHTHOUSE_V2

	var passed := Check.check(_as_received(_entry(lighthouse, final, ticks)))
	_check(passed.valid and passed.measured_ticks == ticks and passed.reason == "", "a real whole run passes and is measured: %s" % passed)

	var claimed := Check.check(_as_received(_entry(lighthouse, final, ticks - 1)))
	_check(not claimed.valid and claimed.reason == "time_mismatch" and claimed.measured_ticks == ticks, "a claimed time other than the measured one fails: %s" % claimed)

	var changed: Dictionary = final.duplicate(true)
	changed.proof.b.actions[0].x = 100 if int(changed.proof.b.actions[0].x) != 100 else -100
	var replay := Check.check(_as_received(_entry(lighthouse, changed, ticks)))
	_check(not replay.valid and replay.reason == "replay_failed", "a changed recording fails the replay: %s" % replay)

	var partial := Check.check(_as_received(_entry(lighthouse, chain.checkpoints[-2], ticks)))
	_check(not partial.valid and partial.reason == "unfinished_run", "a run short of the last stage fails: %s" % partial)

	var relay_final: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/v2/final-checkpoint.json"))
	var assisted := Check.check(_as_received(_entry(Registry.RELAY, relay_final, 588)))
	_check(not assisted.valid and assisted.reason == "assisted_run", "a run with catch assistance on never ranks: %s" % assisted)
	var duel_entry := _entry(Registry.RELAY, relay_final, 588)
	duel_entry["duel"] = true
	# A duel run's checkpoint arrives as a blob body, as the server stores and sends it.
	var bytes := JSON.stringify(relay_final).to_utf8_buffer()
	var body := PackedByteArray([BlobCodec.ENCODING_DEFLATE]) + bytes.compress(FileAccess.COMPRESSION_DEFLATE)
	duel_entry.erase("checkpoint")
	duel_entry.merge({"body": Marshalls.raw_to_base64(body), "byte_length": bytes.size(), "proof_hash": BlobCodec.digest(bytes)}, true)
	var wrong_hash := duel_entry.duplicate()
	wrong_hash.proof_hash = "0".repeat(64)
	_check(Check.check(_as_received(wrong_hash)).reason == "replay_error", "a duel body that does not match its hash goes to a person, never fails the run")
	var duel := Check.check(_as_received(duel_entry))
	_check(duel.valid and duel.measured_ticks == 588, "a duel's run may have assisted turns and is still replayed and measured: %s" % duel)
	_check(Check.verdict(_as_received(duel_entry)).keys().size() == 6, "a duel's verdict has the same six keys")

	var unknown := _entry(lighthouse, final, ticks)
	unknown.chapter.definition_hash = "0".repeat(64)
	_check(Check.check(_as_received(unknown)).reason == "unknown_chapter", "a chapter this build does not bundle fails")

	var verdict := Check.verdict(_as_received(_entry(lighthouse, final, ticks)))
	_check(verdict.keys().size() == 6 and verdict.valid and verdict.board == "sleeping-lighthouse@2" and verdict.proof_hash == "f".repeat(64), "a verdict carries exactly what the verdicts route takes: %s" % verdict)

	var job: Variant = load("res://tests/leaderboard_replay_job.gd")
	_check(job is GDScript and job.can_instantiate(), "the job's entry script compiles")

	print("Leaderboard replay check: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
