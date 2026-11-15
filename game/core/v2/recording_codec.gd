extends RefCounted
## Packed recordings: the one place a physical turn's inputs and replay checks
## are read or written (backend src/v2/recording-codec.ts writes the same bytes).
##
## A packed record keeps every header field of the JSON record and swaps
## `actions` and `replay_checks` for one `packed` string, the standard base64 of:
## FORMAT (one byte); the run count as a varint, then each run as
## varint(ticks * 2 + action), stick x and stick z (one signed byte each, the
## same integers as the JSON runs); then the replay checks, whose ticks are
## implied (every CHECK_EVERY ticks before the end, then the end): each the first
## SHORT_HASH_BYTES of its state hash, or all FULL_HASH_BYTES where the tick is a
## multiple of FULL_CHECK_EVERY. The end's check is final_state_hash, not repeated.
## One byte string means each turn (minimal varints, adjacent runs differ,
## nothing trails, canonical base64), and recording_hash stays the digest of the
## record's canonical JSON, so it covers the packed bytes.
##
## The engines record packed only in a room that says `packed_recordings`
## (services/rooms_api.gd); every reader takes both forms through here, and a
## replay exports in the form of the record it replays, so live, memory, retry
## and replay stay byte for byte the same within a form.

const PACKED_KEY := "packed"
## The longest `packed` string any turn needs, with room to spare (the server's MAX_PACKED_CHARS).
const MAX_PACKED_CHARS := 128 * 1024
const FORMAT := 1
const CHECK_EVERY := 30
const FULL_CHECK_EVERY := 150
const SHORT_HASH_BYTES := 8
const FULL_HASH_BYTES := 32

static func is_packed(record: Variant) -> bool:
	return record is Dictionary and record.has(PACKED_KEY)

## A family's JSON record keys for the packed form.
static func packed_keys(keys: Array) -> Array:
	var result: Array = []
	for key: String in keys:
		if key != "actions" and key != "replay_checks": result.append(key)
	result.append(PACKED_KEY)
	return result

## The keys `record` must have exactly: the family's keys in its form.
static func keys_for(record: Dictionary, keys: Array) -> Array:
	return packed_keys(keys) if is_packed(record) else keys

static func check_ticks(duration: int) -> Array:
	var ticks: Array = []
	var tick := CHECK_EVERY
	while tick < duration:
		ticks.append(tick)
		tick += CHECK_EVERY
	ticks.append(duration)
	return ticks

## How many bytes of the state hash the check at `tick` keeps (none at the end).
static func check_bytes(tick: int, duration: int) -> int:
	if tick == duration: return 0
	return FULL_HASH_BYTES if tick % FULL_CHECK_EVERY == 0 else SHORT_HASH_BYTES

## The packed form of a JSON record (recording_hash left out: the caller hashes
## it), or {} when its checks are not on the implied ticks.
static func packed_form(record: Dictionary) -> Dictionary:
	var text := pack(record.get("actions", []), record.get("replay_checks", []), int(record.get("duration_ticks", 0)))
	if text.is_empty(): return {}
	var result := record.duplicate(true)
	result.erase("actions")
	result.erase("replay_checks")
	result.erase("recording_hash")
	result[PACKED_KEY] = text
	return result

## The `packed` string for runs and checks (full or already short hashes), or "".
static func pack(actions: Array, checks: Array, duration: int) -> String:
	var out := PackedByteArray([FORMAT])
	_varint(out, actions.size())
	for run: Dictionary in actions:
		_varint(out, int(run.ticks) * 2 + (1 if bool(run.action) else 0))
		out.append(int(run.x) & 0xff)
		out.append(int(run.z) & 0xff)
	var ticks := check_ticks(duration)
	if checks.size() != ticks.size(): return ""
	for index in range(ticks.size()):
		var check: Dictionary = checks[index]
		if int(check.get("tick", -1)) != int(ticks[index]): return ""
		var size := check_bytes(int(ticks[index]), duration)
		if size == 0: continue
		var hex := str(check.get("state_hash", ""))
		if hex.length() < size * 2 or not _lower_hex(hex.substr(0, size * 2)): return ""
		out.append_array(hex.substr(0, size * 2).hex_decode())
	return Marshalls.raw_to_base64(out)

## {"actions", "replay_checks"} from a `packed` string for a turn of `duration`
## ticks ending on `final_hash` with at most `max_runs` runs, or {} for anything
## but the one canonical encoding. Short checks come back as 16 hex.
static func unpack(packed: Variant, duration: int, final_hash: String, max_runs: int) -> Dictionary:
	if not packed is String or duration < 1 or max_runs < 1: return {}
	var bytes := Marshalls.base64_to_raw(packed)
	if bytes.is_empty() or Marshalls.raw_to_base64(bytes) != packed or bytes[0] != FORMAT: return {}
	var cursor := [1]
	var count := _read_varint(bytes, cursor)
	if count < 1 or count > max_runs: return {}
	var actions: Array = []
	var total := 0
	for _index in range(count):
		var head := _read_varint(bytes, cursor)
		if head < 0 or cursor[0] + 2 > bytes.size(): return {}
		var x := _signed(bytes[cursor[0]])
		var z := _signed(bytes[cursor[0] + 1])
		cursor[0] += 2
		var run := {"ticks": head / 2, "x": x, "z": z, "action": head % 2 == 1}
		if run.ticks < 1 or absi(x) > 100 or absi(z) > 100: return {}
		if not actions.is_empty() and actions[-1].x == x and actions[-1].z == z and actions[-1].action == run.action: return {}
		total += int(run.ticks)
		if total > duration: return {}
		actions.append(run)
	if total != duration: return {}
	var checks: Array = []
	for tick: int in check_ticks(duration):
		var size := check_bytes(tick, duration)
		if size == 0:
			checks.append({"tick": tick, "state_hash": final_hash})
			continue
		if cursor[0] + size > bytes.size(): return {}
		checks.append({"tick": tick, "state_hash": bytes.slice(cursor[0], cursor[0] + size).hex_encode()})
		cursor[0] += size
	if cursor[0] != bytes.size(): return {}
	return {"actions": actions, "replay_checks": checks}

## A record's runs, from either form ([] when a packed one does not read).
static func actions(record: Dictionary) -> Array:
	if not is_packed(record):
		var listed: Variant = record.get("actions", [])
		return listed if listed is Array else []
	return _unpacked(record).get("actions", [])

## A record's replay checks, from either form ([] when a packed one does not read).
static func checks(record: Dictionary) -> Array:
	if not is_packed(record):
		var listed: Variant = record.get("replay_checks", [])
		return listed if listed is Array else []
	return _unpacked(record).get("replay_checks", [])

## Whether a listed check's hash (short or full) is `state_hash`.
static func check_matches(listed: Variant, state_hash: String) -> bool:
	return listed is String and (listed.length() == SHORT_HASH_BYTES * 2 or listed.length() == FULL_HASH_BYTES * 2) and state_hash.begins_with(listed)

static func _unpacked(record: Dictionary) -> Dictionary:
	var duration: Variant = record.get("duration_ticks")
	if not (duration is int or duration is float) or int(duration) < 1: return {}
	return unpack(record.get(PACKED_KEY), int(duration), str(record.get("final_state_hash", "")), int(duration))

static func _varint(out: PackedByteArray, value: int) -> void:
	while value >= 0x80:
		out.append((value & 0x7f) | 0x80)
		value >>= 7
	out.append(value)

## The next varint, or -1 when it is cut short, too long or not minimal.
static func _read_varint(bytes: PackedByteArray, cursor: Array) -> int:
	var value := 0
	var shift := 0
	for length in range(5):
		if cursor[0] >= bytes.size(): return -1
		var byte: int = bytes[cursor[0]]
		cursor[0] += 1
		value |= (byte & 0x7f) << shift
		if byte < 0x80: return -1 if length > 0 and byte == 0 else value
		shift += 7
	return -1

static func _lower_hex(text: String) -> bool:
	for character in text:
		if not character in "0123456789abcdef": return false
	return true

static func _signed(byte: int) -> int:
	return byte - 256 if byte > 127 else byte
