extends RefCounted
## The cloud copy of local progress, as one bundle, and the one rule that joins two copies.
##
## Every field merges so that nothing is lost and an older copy never wins over a newer one:
## - completed: the union of finished earlier islands;
## - replays: an earlier island's finished recording is kept from whichever copy has it
##   (this phone's first), unless either copy removed it;
## - removed_replays: the union of replays a player removed (by their pair digest), so a replay
##   removed on one phone never comes back from another;
## - keepsakes: per place, solo and friend each stay earned once either copy earned them;
## - hard: per chapter, its solo and together Hard marks, merged like keepsakes (a mark only
##   ever turns on). A copy from before this field reads as one with no Hard marks,
##   and a copy with none is written without it, so older builds still read it;
## - journals: per chapter, the copy with more finished stages; this phone's on a tie;
## - settings: the copy changed last, by its change stamp (never a device's clock order alone:
##   a copy with no recorded change has stamp 0 and loses to any real change).
## merge(a, b) is commutative in content except where it prefers `a` on an exact tie, and
## merge(x, x) == x, so applying the same cloud copy twice changes nothing.
##
## No credentials, ids, rooms or friends are ever in a bundle: only solo progress,
## keepsakes, Hard marks and a few device-neutral settings (SYNCED_SETTINGS).
const Typed = preload("res://services/typed_values.gd")
const Canonical = preload("res://core/v2/canonical.gd")

const SCHEMA_VERSION := 1
const MAGIC := "AYC1"
## Saved Games allows 3 MiB a slot; this leaves room for the header and Google's own limit checks.
const MAX_BYTES := 2_900_000
## Larger than any real bundle; a decompressed size above this is refused.
const MAX_JSON_BYTES := 24_000_000
## Settings that follow a player between phones. Graphics, frame rate and notification
## switches belong to the device (and to its system permission), so they stay local.
## Every key a copy may hold: older builds wrote "assistance" too, so a copy with it still reads.
const SETTINGS_KEYS := ["sound", "haptics", "reduced_motion", "assistance", "left_handed", "photo_prompts", "skip_waits", "share_online_status"]
## The settings this build writes and takes. Forgiving catches stays on each
## phone: a choice on one phone never turns it on or off on another.
const SYNCED_SETTINGS := ["sound", "haptics", "reduced_motion", "left_handed", "photo_prompts", "skip_waits", "share_online_status"]
const LEVEL_ID := "^[a-z0-9][a-z0-9_-]{0,63}$"
const JOURNAL_NAME := "^[a-z0-9-]{1,64}-journey-v[0-9]{1,3}\\.json$"
## Keepsake places are "<chapter>/<stage>"; the catalog checks them when they are applied.
const KEEPSAKE_ID := "^[A-Za-z0-9@/_.:-]{1,96}$"
const DIGEST := "^[a-f0-9]{64}$"
## Hard marks are kept per chapter key, "<level id>@<version>"; HardMode checks them when applied.
const CHAPTER_KEY := "^[a-z0-9][a-z0-9-]{0,63}@[0-9]{1,4}$"
static var _patterns: Dictionary = {}

## Compiles every pattern once on the calling (main) thread, so worker threads only read the cache.
static func warm() -> void:
	for pattern: String in [LEVEL_ID, JOURNAL_NAME, KEEPSAKE_ID, DIGEST, CHAPTER_KEY]: _matches("", pattern)

static func empty() -> Dictionary:
	return {"schema_version": SCHEMA_VERSION, "settings": {"values": {}, "stamp": 0}, "completed": {}, "replays": {}, "removed_replays": {}, "keepsakes": {}, "journals": {}, "hard": {}}

## A bundle from local data. `journals` maps a journal file name to its LocalSave envelope;
## `hard` is HardMode.marks().
static func collect(save_data: Dictionary, settings_stamp: int, keepsakes: Dictionary, journals: Dictionary, hard: Dictionary = {}) -> Dictionary:
	var bundle := empty()
	var settings: Variant = save_data.get("settings")
	if settings is Dictionary:
		for key: String in SYNCED_SETTINGS:
			if settings.get(key) is bool: bundle.settings.values[key] = settings[key]
	bundle.settings.stamp = maxi(0, settings_stamp)
	var completed: Variant = save_data.get("completed")
	if completed is Dictionary:
		for id: Variant in completed:
			if id is String and _matches(id, LEVEL_ID) and completed[id] == true: bundle.completed[id] = true
	var removed: Variant = save_data.get("removed_replays")
	if removed is Dictionary:
		for id: Variant in removed:
			if not id is String or not _matches(id, LEVEL_ID) or not removed[id] is Dictionary: continue
			for digest: Variant in removed[id]:
				if digest is String and _matches(digest, DIGEST) and removed[id][digest] == true:
					if not bundle.removed_replays.has(id): bundle.removed_replays[id] = {}
					bundle.removed_replays[id][digest] = true
	var replays: Variant = save_data.get("replays")
	if replays is Dictionary:
		for id: Variant in replays:
			if id is String and _matches(id, LEVEL_ID) and replays[id] is Dictionary and not replays[id].is_empty() and not _removed(bundle.removed_replays, id, replays[id]):
				bundle.replays[id] = replays[id].duplicate(true)
	for id: Variant in keepsakes:
		var mark: Variant = keepsakes[id]
		if id is String and _matches(id, KEEPSAKE_ID) and mark is Dictionary and (mark.get("solo") == true or mark.get("friend") == true):
			bundle.keepsakes[id] = {"solo": mark.get("solo") == true, "friend": mark.get("friend") == true}
	for key: Variant in hard:
		var mark: Variant = hard[key]
		if key is String and _matches(key, CHAPTER_KEY) and mark is Dictionary and (mark.get("solo") == true or mark.get("together") == true):
			bundle.hard[key] = {"solo": mark.get("solo") == true, "together": mark.get("together") == true}
	for name: Variant in journals:
		var stages := journal_stages(journals[name])
		if name is String and _matches(name, JOURNAL_NAME) and stages > 0:
			bundle.journals[name] = {"stages": stages, "envelope": journals[name].duplicate(true)}
	return bundle

## The digest LocalSave.remove_replay records for a replay: its a and b recordings.
static func replay_digest(value: Dictionary) -> String:
	return Canonical.digest({"a": value.get("a", {}), "b": value.get("b", {})})

static func _removed(removed: Dictionary, id: String, replay: Variant) -> bool:
	return removed.has(id) and replay is Dictionary and removed[id].has(replay_digest(replay))

## Finished stages in a journal envelope (its relay state's pairs), or 0.
static func journal_stages(envelope: Variant) -> int:
	if not envelope is Dictionary: return 0
	var state: Variant = envelope.get("relay")
	if not state is Dictionary or not state.get("pairs") is Array: return 0
	return state.pairs.size()

## The join of two bundles. Either may be empty() or a decoded cloud copy.
static func merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := empty()
	var a_settings: Dictionary = a.get("settings", {"values": {}, "stamp": 0})
	var b_settings: Dictionary = b.get("settings", {"values": {}, "stamp": 0})
	var newer: Dictionary = b_settings if int(b_settings.get("stamp", 0)) > int(a_settings.get("stamp", 0)) else a_settings
	out.settings = {"values": newer.get("values", {}).duplicate(true), "stamp": int(newer.get("stamp", 0))}
	for source: Dictionary in [a, b]:
		for id: String in source.get("removed_replays", {}):
			if not out.removed_replays.has(id): out.removed_replays[id] = {}
			for digest: String in source.removed_replays[id]: out.removed_replays[id][digest] = true
	for source: Dictionary in [a, b]:
		for id: String in source.get("completed", {}): out.completed[id] = true
		for id: String in source.get("replays", {}):
			if not out.replays.has(id) and not _removed(out.removed_replays, id, source.replays[id]): out.replays[id] = source.replays[id].duplicate(true)
		for id: String in source.get("keepsakes", {}):
			var mark: Dictionary = out.keepsakes.get(id, {"solo": false, "friend": false})
			var other: Dictionary = source.keepsakes[id]
			out.keepsakes[id] = {"solo": mark.solo or other.get("solo", false), "friend": mark.friend or other.get("friend", false)}
		for key: String in source.get("hard", {}):
			var mark: Dictionary = out.hard.get(key, {"solo": false, "together": false})
			var other: Dictionary = source.hard[key]
			out.hard[key] = {"solo": mark.solo or other.get("solo", false), "together": mark.together or other.get("together", false)}
		for name: String in source.get("journals", {}):
			var entry: Dictionary = source.journals[name]
			if not out.journals.has(name) or int(entry.stages) > int(out.journals[name].stages): out.journals[name] = entry.duplicate(true)
	return out

## Whether `merged` holds anything `held` lacks: the test for a cloud write or a local apply.
static func adds_to(merged: Dictionary, held: Dictionary) -> bool:
	return fingerprint(merge(held, merged)) != fingerprint(held)

## A stable digest of a bundle's content, for "changed since the last sync".
static func fingerprint(bundle: Dictionary) -> String:
	return JSON.stringify(_sorted(bundle)).sha256_text()

## Bytes for a Saved Games slot: magic, raw length, then zstd JSON. Journals are dropped,
## fewest stages first, until the bundle fits; completions, keepsakes and settings always fit.
static func encode(bundle: Dictionary) -> PackedByteArray:
	var working := bundle.duplicate(true)
	# A copy with no Hard marks keeps the seven fields older builds read.
	if working.get("hard", {}).is_empty(): working.erase("hard")
	var order: Array = working.journals.keys()
	order.sort_custom(func(x: String, y: String) -> bool:
		var sx := int(working.journals[x].stages)
		var sy := int(working.journals[y].stages)
		return sx < sy or (sx == sy and x < y))
	while true:
		var raw := JSON.stringify(_sorted(working)).to_utf8_buffer()
		var packed := raw.compress(FileAccess.COMPRESSION_ZSTD)
		var out := MAGIC.to_ascii_buffer()
		var size := PackedByteArray()
		size.resize(4)
		size.encode_u32(0, raw.size())
		out.append_array(size)
		out.append_array(packed)
		if out.size() <= MAX_BYTES or order.is_empty(): return out
		working.journals.erase(order.pop_front())
	return PackedByteArray()

## A bundle from slot bytes. Empty bytes are a new slot (empty()). Anything malformed is {}.
static func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.is_empty(): return empty()
	if bytes.size() < 8 or bytes.size() > MAX_BYTES + 65536 or bytes.slice(0, 4).get_string_from_ascii() != MAGIC: return {}
	var raw_size := bytes.decode_u32(4)
	if raw_size < 2 or raw_size > MAX_JSON_BYTES: return {}
	var raw := bytes.slice(8).decompress(raw_size, FileAccess.COMPRESSION_ZSTD)
	if raw.size() != raw_size: return {}
	var json := JSON.new()
	if json.parse(raw.get_string_from_utf8()) != OK: return {}
	return validated(json.data)

## Only the fields and shapes this version knows; anything else makes the copy unusable ({}),
## so a newer app's bundle is never half-read. A copy written before Hard marks joined (no
## "hard" field) reads as one with none. Unknown keepsake places, levels and chapters pass
## here; the owners (HomeKeepsakes, LocalSave, HardMode) check them when applying.
static func validated(value: Variant) -> Dictionary:
	if not value is Dictionary or value.size() != 7 + int(value.has("hard")) or not Typed.equal(value.get("schema_version"), SCHEMA_VERSION): return {}
	var settings: Variant = value.get("settings")
	if not settings is Dictionary or settings.size() != 2 or not settings.get("values") is Dictionary or not Typed.whole_number(settings.get("stamp")) or int(settings.stamp) < 0: return {}
	var out := empty()
	for key: Variant in settings.values:
		if not key is String or key not in SETTINGS_KEYS or not settings.values[key] is bool: return {}
		out.settings.values[key] = settings.values[key]
	out.settings.stamp = int(settings.stamp)
	for field: String in ["completed", "replays", "removed_replays", "keepsakes", "journals"]:
		if not value.get(field) is Dictionary or value[field].size() > 256: return {}
	for id: Variant in value.removed_replays:
		var marks: Variant = value.removed_replays[id]
		if not id is String or not _matches(id, LEVEL_ID) or not marks is Dictionary or marks.size() > 256: return {}
		out.removed_replays[id] = {}
		for digest: Variant in marks:
			if not digest is String or not _matches(digest, DIGEST) or marks[digest] != true: return {}
			out.removed_replays[id][digest] = true
	for id: Variant in value.completed:
		if not id is String or not _matches(id, LEVEL_ID) or value.completed[id] != true: return {}
		out.completed[id] = true
	for id: Variant in value.replays:
		if not id is String or not _matches(id, LEVEL_ID) or not value.replays[id] is Dictionary or value.replays[id].is_empty(): return {}
		out.replays[id] = value.replays[id]
	for id: Variant in value.keepsakes:
		var mark: Variant = value.keepsakes[id]
		if not id is String or not _matches(id, KEEPSAKE_ID) or not mark is Dictionary or mark.size() != 2 or not mark.get("solo") is bool or not mark.get("friend") is bool: return {}
		out.keepsakes[id] = {"solo": mark.solo, "friend": mark.friend}
	var hard: Variant = value.get("hard", {})
	if not hard is Dictionary or hard.size() > 64: return {}
	for key: Variant in hard:
		var mark: Variant = hard[key]
		if not key is String or not _matches(key, CHAPTER_KEY) or not mark is Dictionary or mark.size() != 2 or not mark.get("solo") is bool or not mark.get("together") is bool: return {}
		out.hard[key] = {"solo": mark.solo, "together": mark.together}
	for name: Variant in value.journals:
		var entry: Variant = value.journals[name]
		if not name is String or not _matches(name, JOURNAL_NAME) or not entry is Dictionary or entry.size() != 2 or not Typed.whole_number(entry.get("stages")) or not entry.get("envelope") is Dictionary: return {}
		if int(entry.stages) < 1 or journal_stages(entry.envelope) != int(entry.stages): return {}
		out.journals[name] = {"stages": int(entry.stages), "envelope": entry.envelope}
	return out

static func _matches(text: String, pattern: String) -> bool:
	if not _patterns.has(pattern): _patterns[pattern] = RegEx.create_from_string(pattern)
	return (_patterns[pattern] as RegEx).search(text) != null

## Keys sorted at every level and whole floats as ints (JSON reads every number back as a
## float), so equal content always prints the same JSON.
static func _sorted(value: Variant) -> Variant:
	if value is float and is_finite(value) and value == floorf(value) and absf(value) <= 9007199254740991.0:
		return int(value)
	if value is Dictionary:
		var keys: Array = value.keys()
		keys.sort()
		var out := {}
		for key: Variant in keys: out[key] = _sorted(value[key])
		return out
	if value is Array:
		return value.map(func(item: Variant) -> Variant: return _sorted(item))
	return value
