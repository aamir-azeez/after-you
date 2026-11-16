extends RefCounted
## Saved Games slots for the replays only phones keep in full: kept room history attempts, shared
## replay files and friend duel runs (the server keeps their hashes once both phones have them).
## Read and written by cloud_save_sync.gd like the progress slot; cloud_replay_sources.gd is the
## phone's side.
##
## Items are keyed by what they are ("room/<owner>/<server>/<room>/<place>-<link>",
## "shared/<file>", "duel/<owner>/<file>"), and each key always goes to the same slot
## (slot_of), so a slot changes only when its own items do. A slot is one JSON bundle in the
## replay blob format (an SHA-256 of the canonical bytes, then BlobCodec's deflate body).
##
## merge(a, b) is a union by key: the same key keeps the later revision (shared replay files
## are rewritten; attempts and duel runs never change). Space: newest first. A slot keeps the
## newest items whose JSON fits BUDGET and leaves the rest out (fit), the same way on every phone,
## so merge(x, x) == x and a left-out item never comes back to push a newer one out.
const BlobCodec = preload("res://services/blob_codec.gd")
const Typed = preload("res://services/typed_values.gd")

const SCHEMA_VERSION := 1
const MAGIC := "AYR1"
const SLOT_PREFIX := "after-you-history-"
## Six slots of at most 2.9 MB each: about 17 MB of replays, well within the player's own
## Google Drive or iCloud space (Saved Games has no per-game total beyond that).
const SLOTS := 6
## Saved Games allows 3 MiB a slot (Play Games' guaranteed minimum).
const MAX_BYTES := 2_900_000
## The JSON kept per slot. Deflate never grows it by more than a few bytes per 16 KB, so the slot
## with its 40-byte header always stays under MAX_BYTES.
const BUDGET := 2_800_000
## Room for an item's fields beside its data.
const ITEM_OVERHEAD := 512
const MAX_ITEMS := 4096
const ITEM_KEYS := ["kind", "owner", "rev", "at", "digest", "data", "meta"]
const KINDS := ["room", "shared", "duel"]
const KEY := "^(room|shared|duel)(/[A-Za-z0-9_-][A-Za-z0-9_.-]{0,79}){1,5}$"
const DIGEST := "^[a-f0-9]{64}$"
static var _patterns: Dictionary = {}

## Compiles every pattern once on the calling (main) thread, so worker threads only read the cache.
static func warm() -> void:
	for pattern: String in [KEY, DIGEST]: _matches("", pattern)

static func slot_name(index: int) -> String:
	return SLOT_PREFIX + str(index + 1)

## The slot an item key always goes to.
static func slot_of(key: String) -> int:
	return key.sha256_text().left(8).hex_to_int() % SLOTS

static func empty() -> Dictionary:
	return {"schema_version": SCHEMA_VERSION, "items": {}}

static func cost(item: Dictionary) -> int:
	return str(item.get("data", "")).length() + ITEM_OVERHEAD

## {"items": the newest items that fit BUDGET, "left_out": how many did not}. Newest by `at`, then key.
static func fit(items: Dictionary) -> Dictionary:
	var order: Array = items.keys()
	order.sort_custom(func(x: String, y: String) -> bool:
		var ax := int(items[x].at)
		var ay := int(items[y].at)
		return ax > ay or (ax == ay and x < y))
	var kept := {}
	var total := 0
	var left_out := 0
	for key: String in order:
		var size := cost(items[key])
		if total + size > BUDGET or kept.size() >= MAX_ITEMS:
			left_out += 1
			continue
		kept[key] = items[key]
		total += size
	return {"items": kept, "left_out": left_out}

## For one key: the later revision, then the larger digest, then the earlier time (any fixed rule
## does; this one is the same on every phone).
static func _wins(a: Dictionary, b: Dictionary) -> bool:
	if int(a.rev) != int(b.rev): return int(a.rev) > int(b.rev)
	if a.digest != b.digest: return str(a.digest) > str(b.digest)
	return int(a.at) <= int(b.at)

static func merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var items := {}
	for source: Dictionary in [a, b]:
		var held: Dictionary = source.get("items", {})
		for key: String in held:
			if not items.has(key) or _wins(held[key], items[key]) and held[key] != items[key]: items[key] = held[key]
	var out := empty()
	out.items = fit(items).items
	return out

## Whether `merged` holds anything `held` lacks.
static func adds_to(merged: Dictionary, held: Dictionary) -> bool:
	return fingerprint(merge(held, merged)) != fingerprint(held)

## A digest of what a bundle holds: each item's key, revision, time and digest (the digest
## stands for its data).
static func fingerprint(bundle: Dictionary) -> String:
	var held: Dictionary = bundle.get("items", {})
	var keys: Array = held.keys()
	keys.sort()
	var lines := PackedStringArray()
	for key: String in keys: lines.append("%s %d %d %s" % [key, int(held[key].rev), int(held[key].at), held[key].digest])
	return "\n".join(lines).sha256_text()

## Slot bytes: magic, the canonical JSON's length and SHA-256, then its tagged deflate body.
static func encode(bundle: Dictionary) -> PackedByteArray:
	var kept: Dictionary = fit(bundle.get("items", {})).items
	while true:
		var raw := JSON.stringify({"schema_version": SCHEMA_VERSION, "items": kept}, "", true).to_utf8_buffer()
		var out := MAGIC.to_ascii_buffer()
		var size := PackedByteArray()
		size.resize(4)
		size.encode_u32(0, raw.size())
		out.append_array(size)
		out.append_array(BlobCodec.digest(raw).hex_decode())
		out.append_array(BlobCodec.encode(raw))
		if out.size() <= MAX_BYTES or kept.is_empty(): return out
		# Never expected (fit leaves room): drop the oldest rather than write an oversized slot.
		var order: Array = kept.keys()
		order.sort_custom(func(x: String, y: String) -> bool: return int(kept[x].at) < int(kept[y].at) or (int(kept[x].at) == int(kept[y].at) and x > y))
		kept.erase(order[0])
	return PackedByteArray()

## A bundle from slot bytes: empty bytes are a new slot (empty()); anything malformed, damaged or
## from a newer build is {} and is never written over.
static func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.is_empty(): return empty()
	if bytes.size() < 41 or bytes.size() > MAX_BYTES + 65536 or bytes.slice(0, 4).get_string_from_ascii() != MAGIC: return {}
	var raw_size := bytes.decode_u32(4)
	if raw_size < 2 or raw_size > BUDGET + 65536: return {}
	var raw := BlobCodec.verified(bytes.slice(40), raw_size, bytes.slice(8, 40).hex_encode(), BUDGET + 65536)
	if raw.is_empty(): return {}
	var json := JSON.new()
	if json.parse(raw.get_string_from_utf8()) != OK: return {}
	return validated(json.data)

## Only the shapes this version knows. Each item's data is checked again by its owner on restore.
static func validated(value: Variant) -> Dictionary:
	if not value is Dictionary or value.size() != 2 or not Typed.equal(value.get("schema_version"), SCHEMA_VERSION) or not value.get("items") is Dictionary or value.items.size() > MAX_ITEMS: return {}
	var out := empty()
	for key: Variant in value.items:
		var item: Variant = value.items[key]
		if not key is String or not _matches(key, KEY) or key.contains("..") or not item is Dictionary or item.size() != ITEM_KEYS.size(): return {}
		if ITEM_KEYS.any(func(field: String) -> bool: return not item.has(field)): return {}
		if item.kind != key.get_slice("/", 0) or not Typed.valid_id(item.owner) or not Typed.whole_number(item.rev) or not Typed.whole_number(item.at) or int(item.rev) < 0 or int(item.at) < 0: return {}
		if not item.digest is String or not _matches(item.digest, DIGEST) or not item.data is String or not item.meta is Dictionary or item.meta.size() > 8: return {}
		out.items[key] = {"kind": item.kind, "owner": item.owner, "rev": int(item.rev), "at": int(item.at), "digest": item.digest, "data": item.data, "meta": item.meta}
	return out

static func _matches(text: String, pattern: String) -> bool:
	if not _patterns.has(pattern): _patterns[pattern] = RegEx.create_from_string(pattern)
	return (_patterns[pattern] as RegEx).search(text) != null
