extends RefCounted
## The developers' ghost runs a duel's ghost race times (backend
## duels/developer-ghosts.ts), recorded with Forgiving catches off at the rules
## a new room plays (ChapterRegistry.preferred_rules). Kept apart from the
## developers' best times (backend leaderboards/developer-bests.ts), which stay
## as they are.
##
## Each ghost replays the real inputs of the whole run its earlier, assisted
## ghost time came from (SOURCES: the fixture developer-bests.ts names, or the
## same route already recorded at today's rules in comfort8/), turn by
## turn through the chapter's own engine with catch assistance off at today's
## rules, and derives every checkpoint from the new recordings. Where a
## source turn leaned on Forgiving catches, the receiver presses on the first
## tick the engine offers the catch: the press a player makes without
## assistance. Nothing else in a route changes; a run that no longer finishes
## is an error, never patched.
##
## A ghost is stored as the run's final checkpoint in the shared blob format
## (services/blob_codec.gd): the canonical bytes deflated, their length and
## SHA-256, the shape the leaderboard replay check takes
## (tests/leaderboard_replay_check.gd). tests/test_dev_ghosts.gd checks the
## stored ghosts and, with AFTERYOU_WRITE_DEV_GHOSTS=1, writes them again.
const Registry = preload("res://services/chapter_registry.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const BlobCodec = preload("res://services/blob_codec.gd")

const MANIFEST := "res://tests/fixtures/dev_ghosts.json"
## Board key -> [fixture under tests/fixtures/, where its run is]: "final" for a
## final checkpoint file, "chain" for a {"checkpoints"} file's last one, else the
## entry of a recordings file that holds {"pairs"}.
const SOURCES := {
	"relay-isles@2": ["v2/final-checkpoint.json", "final"],
	"first-steps@1": ["first_steps/final-checkpoint.json", "final"],
	"high-and-low@1": ["comfort8/recordings.json", "high-and-low"],
	"rolling-home@1": ["comfort8/recordings.json", "rolling-home"],
	"a-house-for-two@1": ["comfort8/recordings.json", "a-house-for-two"],
	"conservatory@1": ["comfort8/recordings.json", "conservatory"],
	"long-way-home@1": ["comfort8/recordings.json", "long-way-home"],
	"the-wishing-well@1": ["cooperative/the-wishing-well-final-checkpoint.json", "final"],
	"long-way-home@2": ["journey/long-way-home-v2-final-checkpoint.json", "final"],
	"turn-of-the-tide@1": ["journey/slack-water-high-punt-checkpoint.json", "final"],
	"sleeping-lighthouse@2": ["lighthouse/v2-chain.json", "chain"],
	"turn-of-the-tide@2": ["journey/turn-of-the-tide-v2-final-checkpoint.json", "final"],
}

## {"checkpoint", "ticks", "rules", "presses", "error"} for one board's ghost.
static func record(key: String) -> Dictionary:
	var result := {"checkpoint": {}, "ticks": 0, "rules": Registry.preferred_rules(key), "presses": 0, "error": ""}
	var level := Registry.definition(key)
	var engine: Script = Registry.simulation_script(key)
	var pairs := source_pairs(key)
	if level.is_empty() or engine == null or pairs.size() != level.stages.size():
		result.error = "%s: %d source pairs for %d stages" % [key, pairs.size(), level.get("stages", []).size()]
		return result
	var rules := {"simulation_version": result.rules}
	var checkpoint := Registry.initial_checkpoint(key)
	for index in range(pairs.size()):
		var stage_id: String = level.stages[index].id
		var a: RefCounted = engine.new()
		a.catch_assistance = false
		if not Registry.reset_simulation(a, key, level, stage_id, checkpoint, {}, "a", rules):
			result.error = "%s %s: source could not start: %s" % [key, stage_id, a.error]
			return result
		_replay(a, engine.expand_recording_inputs(pairs[index].a), result)
		if not a.error.is_empty() or not _ends(a, false):
			result.error = "%s %s: source turn failed: %s %s" % [key, stage_id, a.error, a.snapshot().get("commit_reason", "")]
			return result
		var first: Dictionary = a.export_recording()
		var b: RefCounted = engine.new()
		b.catch_assistance = false
		if not Registry.reset_simulation(b, key, level, stage_id, checkpoint, first, "b", rules):
			result.error = "%s %s: receiver could not start: %s" % [key, stage_id, b.error]
			return result
		_replay(b, engine.expand_recording_inputs(pairs[index].b), result)
		# The receiver may finish before the recorded source does; real ticks run it out.
		while not b.finished and b.error.is_empty() and b.snapshot().get("objective_done", false): b.step({})
		if not b.error.is_empty() or not _ends(b, true):
			result.error = "%s %s: receiver turn failed without Forgiving catches: %s %s" % [key, stage_id, b.error, b.snapshot().get("commit_reason", "")]
			return result
		var second: Dictionary = b.export_recording()
		var derived: Dictionary = engine.derive_checkpoint(level, checkpoint, first, second)
		if not derived.valid:
			result.error = "%s %s: checkpoint failed: %s" % [key, stage_id, derived.get("error", "")]
			return result
		result.ticks += int(first.duration_ticks) + int(second.duration_ticks)
		checkpoint = derived.checkpoint
	result.checkpoint = checkpoint
	return result

## Whether the turn can be committed (and, for the receiver, closed the stage), read from the snapshot every engine gives.
static func _ends(sim: RefCounted, receiver: bool) -> bool:
	var state: Dictionary = sim.snapshot()
	return bool(state.get("can_commit", false)) and (not receiver or bool(state.get("complete", false)))

## Steps `frames` until the turn finishes. A catch the engine offers is pressed
## for on the next tick unless that frame already presses.
static func _replay(sim: RefCounted, frames: Array, result: Dictionary) -> void:
	var held := false
	for frame: Dictionary in frames:
		if sim.finished or not sim.error.is_empty(): return
		var input := frame.duplicate()
		var offered: Dictionary = sim.context_action()
		if not held and not bool(input.get("interact", false)) and offered.get("id") == "catch" and bool(offered.get("enabled", false)):
			input.interact = true
			result.presses += 1
		held = bool(input.get("interact", false))
		sim.step(input)

## The source run's recorded pairs, first stage first.
static func source_pairs(key: String) -> Array:
	var source: Array = SOURCES.get(key, [])
	if source.is_empty(): return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/" + str(source[0])))
	if not parsed is Dictionary: return []
	match str(source[1]):
		"final": return _chain_pairs(key, parsed)
		"chain": return _chain_pairs(key, parsed.get("checkpoints", [{}])[-1])
	var entry: Variant = parsed.get(str(source[1]))
	return entry.get("pairs", []) if entry is Dictionary else []

static func _chain_pairs(key: String, final: Dictionary) -> Array:
	var pairs: Array = []
	var current := final
	while int(current.get("stage_index", 0)) > 0 and current.get("proof") is Dictionary:
		pairs.push_front({"a": current.proof.a, "b": current.proof.b})
		current = Registry.previous_checkpoint(key, current)
	return pairs

## The canonical bytes of a ghost's final checkpoint, as the blob carries them.
static func canonical_bytes(checkpoint: Dictionary) -> PackedByteArray:
	return JSON.stringify(Canonical.normalized(checkpoint)).to_utf8_buffer()

## One manifest row: the board, its chapter, the rules and time, and the run in the blob format.
static func manifest_row(key: String, recorded: Dictionary) -> Dictionary:
	var descriptor := Registry.descriptor(key)
	var bytes := canonical_bytes(recorded.checkpoint)
	return {"board": key, "chapter": {"level_id": descriptor.level_id, "level_version": descriptor.level_version, "definition_hash": descriptor.definition_hash},
		"simulation_version": recorded.rules, "ticks": recorded.ticks, "catch_assistance": false,
		"byte_length": bytes.size(), "proof_hash": BlobCodec.digest(bytes), "body": Marshalls.raw_to_base64(BlobCodec.encode(bytes))}
