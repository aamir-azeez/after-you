extends RefCounted
## Export this run (the owner's own phone only: services/tester_switches.gd
## run_export, which every capabilities read notes). A whole attempt leaves as
## one file in the stored and sent blob format (services/blob_codec.gd: an
## encoding byte, then deflate; its SHA-256 is of the canonical bytes inside):
## - Together: the room attempt this phone keeps (services/history_store.gd),
##   byte for byte as the server sent it.
## - Solo: no blob is kept for a solo run, so its every part (the accepted
##   pairs, first stage first) is put in canonical JSON under FORMAT and encoded
##   the same way. A solo run names no player and no room.
## Nothing here is sent anywhere; services/file_share.gd hands the file over.
const BlobCodec = preload("res://services/blob_codec.gd")
const HistoryStore = preload("res://services/history_store.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Typed = preload("res://services/typed_values.gd")

const FORMAT := "after-you.solo-attempt"
const FORMAT_VERSION := 1
const EXTENSION := ".afteryou"
const MAX_SLUG := 48

## "relay-isles-attempt-1.afteryou" for the chapter key "relay-isles@2" and
## attempt 1: the chapter's id, lowercase and hyphenated, then the attempt.
static func file_name(chapter_key: String, attempt: int) -> String:
	var slug := RegEx.create_from_string("[^a-z0-9]+").sub(chapter_key.get_slice("@", 0).to_lower(), "-", true).lstrip("-").rstrip("-")
	slug = slug.left(MAX_SLUG).rstrip("-")
	return "%s-attempt-%d%s" % ["run" if slug.is_empty() else slug, maxi(attempt, 1), EXTENSION]

## A solo attempt's file, from every part's row (SoloReplayCollection rows,
## hidden parts too): empty when a part is missing or out of order.
static func solo_blob(chapter_key: String, rows: Array) -> PackedByteArray:
	if chapter_key.is_empty() or rows.is_empty(): return PackedByteArray()
	var ordered := rows.duplicate()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("stage_index", 0)) < int(b.get("stage_index", 0)))
	var pairs: Array = []
	for index in range(ordered.size()):
		var row: Variant = ordered[index]
		if not row is Dictionary or not Typed.equal(row.get("stage_index"), index) or not Typed.equal(row.get("chapter_key"), chapter_key) or not row.get("pair") is Dictionary: return PackedByteArray()
		pairs.append(row.pair)
	var document := {"format": FORMAT, "format_version": FORMAT_VERSION, "chapter_key": chapter_key, "pairs": pairs}
	var canonical := JSON.stringify(Canonical.normalized(document), "", true, true).to_utf8_buffer()
	if canonical.size() > HistoryStore.MAX_ATTEMPT_BYTES: return PackedByteArray()
	return BlobCodec.encode(canonical)
