extends RefCounted
## Whole runs in the shared blob format, as a board replay, a duel's run or a
## race ghost carries one: {board, ticks, proof_hash, byte_length, body}, where
## `board` is the run's chapter key. The runs older apps shipped as Our run
## (fixtures/whole_runs.json, now only the chapters that have not changed since)
## and, for each chapter whose hand controls went solid, the current
## definition's whole run the chapter's own fixtures keep (the same runs the
## backend's developer-bests.ts times). Shared by test_race_ghost.gd,
## test_recording_codec.gd and test_recording_codec_runs.gd.
const BlobCodec = preload("res://services/blob_codec.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Runs = preload("res://services/leaderboard_runs.gd")
const SHIPPED := "res://tests/fixtures/whole_runs.json"
## chapter key -> [fixture, path to its final checkpoint inside it].
const CURRENT := {
	"high-and-low@1": ["cooperative/high-and-low-final-checkpoint.json", []],
	"rolling-home@1": ["comfort8/recordings.json", ["rolling-home", "checkpoints", -1]],
	"a-house-for-two@1": ["cooperative/a-house-for-two-final-checkpoint.json", []],
	"conservatory@1": ["journey/conservatory-final-checkpoint.json", []],
	"long-way-home@1": ["journey/long-way-home-final-checkpoint.json", []],
	"the-wishing-well@1": ["cooperative/the-wishing-well-final-checkpoint.json", []],
	"long-way-home@2": ["journey/long-way-home-v2-final-checkpoint.json", []],
	"turn-of-the-tide@1": ["journey/slack-water-high-punt-checkpoint.json", []],
	"turn-of-the-tide@2": ["journey/turn-of-the-tide-v2-final-checkpoint.json", []],
}

static func rows() -> Array:
	var found: Array = JSON.parse_string(FileAccess.get_file_as_string(SHIPPED)).ghosts
	for key: String in CURRENT:
		var value: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/" + CURRENT[key][0]))
		for step: Variant in CURRENT[key][1]: value = value[step]
		var bytes := JSON.stringify(Canonical.normalized(value)).to_utf8_buffer()
		found.append({"board": key, "ticks": int(Runs.run_time(key, value).get("ticks", -1)), "proof_hash": BlobCodec.digest(bytes), "byte_length": bytes.size(), "body": Marshalls.raw_to_base64(BlobCodec.encode(bytes))})
	return found

## The row for chapter `key`, or {}.
static func row(key: String) -> Dictionary:
	for item: Dictionary in rows():
		if item.board == key: return item
	return {}
