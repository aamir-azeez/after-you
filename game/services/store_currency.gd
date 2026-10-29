extends RefCounted
## The currency the player's store sells in ("USD", "GBP"), as the last offerings
## read named it (services/purchases.gd get_offerings, any offering's package),
## kept on the phone so it is known after a restart, before the store opens again.
## "" until a read has named one. The Purchases card (presentation/pollen_purchases_view.gd)
## shows money only while this is "USD": the server keeps Google Play's US figure,
## so a player who pays in another currency would see a price they never paid.
const AtomicFile = preload("res://services/atomic_file.gd")

const PATH := "user://store_currency.json"
const VERSION := 1
const PATTERN := "^[A-Z]{3}$"

## Where it is kept (tests point it elsewhere with use_path).
static var path := PATH
static var _code := ""
static var _loaded := false
static var _valid := RegEx.create_from_string(PATTERN)

## The store's currency code, or "" while unknown.
static func code() -> String:
	if not _loaded: _load()
	return _code

## Whether money the server kept in US dollars reads true for this player.
static func usd() -> bool:
	return code() == "USD"

## Keeps the currency an offerings payload names: the first package with a
## well-formed code. A payload that names none changes nothing.
static func note(payload: Dictionary) -> void:
	var found := ""
	for entry: Variant in payload.get("offerings", []):
		if not entry is Dictionary or not entry.get("packages") is Array: continue
		for item: Variant in entry.packages:
			if item is Dictionary and _valid.search(str(item.get("currency", ""))) != null:
				found = str(item.currency)
				break
		if not found.is_empty(): break
	if found.is_empty() or found == code(): return
	_code = found
	AtomicFile.write_text(path, JSON.stringify({"schema_version": VERSION, "currency": _code}))

## Points the store at another file and forgets what it read (tests).
static func use_path(storage_path: String) -> void:
	path = storage_path
	_code = ""
	_loaded = false

static func _load() -> void:
	_loaded = true
	_code = ""
	var parsed: Variant = JSON.parse_string(AtomicFile.read_text(path))
	if parsed is Dictionary and int(parsed.get("schema_version", 0)) == VERSION and _valid.search(str(parsed.get("currency", ""))) != null:
		_code = str(parsed.currency)
