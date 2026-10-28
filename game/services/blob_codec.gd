extends RefCounted
## The one format for a recording, checkpoint or replay body the server stores
## or sends (backend src/blob-codec.ts): an encoding byte (0 raw, 1 deflate in
## zlib framing) and the payload. Its record names the canonical byte length
## and the SHA-256 of the canonical bytes. Room history (history_store.gd) and
## leaderboard replays (leaderboard_replay.gd) both read it here.

const ENCODING_RAW := 0
const ENCODING_DEFLATE := 1

## The canonical bytes inside a tagged body, or empty when they are not exactly
## `byte_length` long. Inflating stops at that length, so a bomb costs nothing.
static func decode(tagged: PackedByteArray, byte_length: int, max_bytes: int) -> PackedByteArray:
	if tagged.is_empty() or byte_length < 1 or byte_length > max_bytes or tagged.size() > max_bytes + 1: return PackedByteArray()
	var payload := tagged.slice(1)
	var bytes := PackedByteArray()
	if tagged[0] == ENCODING_RAW: bytes = payload
	elif tagged[0] == ENCODING_DEFLATE and not payload.is_empty(): bytes = payload.decompress(byte_length, FileAccess.COMPRESSION_DEFLATE)
	return bytes if bytes.size() == byte_length else PackedByteArray()

static func digest(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()

## The canonical bytes when `tagged` decodes to exactly `byte_length` bytes whose SHA-256 is `expected_digest`, else empty.
static func verified(tagged: PackedByteArray, byte_length: int, expected_digest: String, max_bytes: int) -> PackedByteArray:
	var bytes := decode(tagged, byte_length, max_bytes)
	return bytes if not bytes.is_empty() and digest(bytes) == expected_digest else PackedByteArray()
