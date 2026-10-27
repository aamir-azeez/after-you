extends RefCounted
## The Full Journey monthly Pollen on this phone: a copy of what the server last
## said (the `grant` part of GET /v1/pollen while the grant is on;
## backend/src/pollen/grant-settle.ts). The server pays every instalment; this
## only remembers what to show.
##
## Kept per server and player (a scope), in one small file written whole with
## AtomicFile:
## - enabled: the server said the monthly grant is on (its capabilities);
## - ladder: {months, next, top}: instalments paid so far, what the next pays,
##   and the top step;
## - latest: {key, amount, at}: the newest instalment the server paid, and when;
## - shown: the key of the newest instalment whose card this phone showed, so
##   each instalment's "Your monthly Pollen arrived" card shows once.
##
## Every value read from the file or a server reply is checked; anything that
## fails is dropped, and a file that cannot be read reads as empty.
const AtomicFile = preload("res://services/atomic_file.gd")
const Typed = preload("res://services/typed_values.gd")

const PATH := "user://pollen_grant.json"
const VERSION := 1
const KEY_PATTERN := "^grant:([0-9]{1,16}:[0-9]{1,6}|lifetime)$"
const MAX_AMOUNT := 1000000
const MAX_TIME := 8640000000000000
## An instalment older than this on the phone's clock is not news: a new install
## or a long absence never opens with an old month's card.
const CARD_DAYS := 35

static var _shared: RefCounted = null
static var _key := RegEx.create_from_string(KEY_PATTERN)

var path := PATH
var _scopes: Dictionary = {}

static func shared() -> RefCounted:
	if _shared == null: _shared = load("res://services/pollen_grant.gd").new()
	return _shared

## Installs a store as the shared one (tests), or clears it with null.
static func use_shared(store: RefCounted) -> void:
	_shared = store

func _init(storage_path: String = PATH) -> void:
	path = storage_path
	_load()

static func _count(value: Variant, top: int = MAX_AMOUNT) -> bool:
	return Typed.whole_number(value) and float(value) >= 0.0 and float(value) <= float(top)

## The `grant` part of a wallet answer as kept: {months, next, top, latest?}, or
## {} when it is missing or any part is not the contract's.
static func checked_grant(value: Variant) -> Dictionary:
	if not value is Dictionary: return {}
	if not _count(value.get("months"), 100000) or not _count(value.get("next")) or not _count(value.get("top")) or int(value.next) < 1 or int(value.top) < int(value.next): return {}
	var kept := {"months": Typed.as_int(value.months), "next": Typed.as_int(value.next), "top": Typed.as_int(value.top)}
	if value.has("latest"):
		var latest: Variant = value.latest
		if not latest is Dictionary or not latest.get("key") is String or _key.search(latest.key) == null or not _count(latest.get("amount")) or int(latest.amount) < 1 or not _count(latest.get("at"), MAX_TIME): return {}
		kept["latest"] = {"key": latest.key, "amount": Typed.as_int(latest.amount), "at": Typed.as_int(latest.at)}
	return kept

static func scope_key(server: String, owner: String) -> String:
	return server.strip_edges().trim_suffix("/") + "|" + owner

func _scope(server: String, owner: String, create: bool = false) -> Dictionary:
	if owner.is_empty() or server.strip_edges().is_empty(): return {}
	var key := scope_key(server, owner)
	if not _scopes.has(key):
		if not create: return {}
		_scopes[key] = {"enabled": false, "ladder": {}, "shown": ""}
	return _scopes[key]

## Whether the server said the monthly grant is on for this player.
func enabled(server: String, owner: String) -> bool:
	return bool(_scope(server, owner).get("enabled", false))

func set_enabled(server: String, owner: String, on: bool) -> void:
	var scope := _scope(server, owner, on)
	if scope.is_empty() or bool(scope.enabled) == on: return
	scope.enabled = on
	_save()

## A wallet answer: keeps its grant part when it has one.
func note_view(server: String, owner: String, value: Variant) -> bool:
	if not value is Dictionary or not value.has("grant"): return false
	var kept := checked_grant(value.grant)
	var scope := _scope(server, owner, not kept.is_empty())
	if kept.is_empty() or scope.is_empty(): return false
	if scope.ladder != kept:
		scope.ladder = kept
		_save()
	return true

## The last ladder the server sent ({} until it has).
func ladder(server: String, owner: String) -> Dictionary:
	var scope := _scope(server, owner)
	return (scope.ladder as Dictionary).duplicate(true) if not scope.is_empty() else {}

## The card to show: {key, amount, next, top} for an instalment this phone has
## not shown yet and that is recent, or {} when there is none (or the grant is
## off). `now_ms` is this phone's clock.
func pending(server: String, owner: String, now_ms: int = -1) -> Dictionary:
	var scope := _scope(server, owner)
	if scope.is_empty() or not bool(scope.enabled): return {}
	var kept: Dictionary = scope.ladder
	if not kept.has("latest") or kept.latest.key == scope.shown: return {}
	var now := now_ms if now_ms >= 0 else int(Time.get_unix_time_from_system() * 1000.0)
	if int(kept.latest.at) < now - CARD_DAYS * 86400000: return {}
	return {"key": kept.latest.key, "amount": kept.latest.amount, "next": kept.next, "top": kept.top}

## The card for `key` was shown: it never shows again.
func mark_shown(server: String, owner: String, key: String) -> void:
	var scope := _scope(server, owner)
	if scope.is_empty() or scope.shown == key: return
	scope.shown = key
	_save()

func _load() -> void:
	_scopes = {}
	var parsed: Variant = _parsed(AtomicFile.read_text(path, func(text: String) -> bool:
		var value: Variant = _parsed(text)
		return value is Dictionary and Typed.equal(value.get("schema_version"), VERSION) and value.get("scopes") is Dictionary))
	if not parsed is Dictionary or not parsed.get("scopes") is Dictionary: return
	for key: Variant in parsed.scopes:
		var value: Variant = parsed.scopes[key]
		if not key is String or not key.contains("|") or not value is Dictionary: continue
		var shown: Variant = value.get("shown", "")
		_scopes[key] = {"enabled": value.get("enabled") == true, "ladder": checked_grant(value.get("ladder")),
			"shown": shown if shown is String and (shown.is_empty() or _key.search(shown) != null) else ""}

static func _parsed(text: String) -> Variant:
	var json := JSON.new()
	return json.data if not text.is_empty() and json.parse(text) == OK else null

func _save() -> bool:
	return AtomicFile.write_text(path, JSON.stringify({"schema_version": VERSION, "scopes": _scopes}))
