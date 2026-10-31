extends RefCounted
## Whether the server takes App Store purchases for this player: Full Journey
## through the App Store (GET /v2/capabilities' app_store_full_journey_version,
## sent only to an App Store build while the server admits App Store
## subscribers, backend src/entitlement.ts storeCapability).
##
## Kept per server and player (a scope), on this phone, so a restart knows it:
## - unknown (no read for this scope yet): the build decides, as it always has.
##   A new install has no identity, so App Review sees the store from the start.
## - off (a read without the field): the iPhone hides every paid surface, as a
##   build that sells nothing does (Main._paid_content_hidden, PollenSurfaces).
## - on: the build decides.
## A failed read changes nothing. A change shows on the next screen drawn.
##
## Money moves only on this session's answer: confirmed() is true only after a
## read in this run of the app said on, whatever the kept state says, so a
## purchase sheet never opens on an answer from an earlier session
## (presentation/store_flow.gd, presentation/pollen_store_flow.gd).
const AtomicFile = preload("res://services/atomic_file.gd")
const Typed = preload("res://services/typed_values.gd")
const PlatformSupport = preload("res://services/platform_support.gd")

const PATH := "user://store_support.json"
const VERSION := 1
const UNKNOWN := -1
const OFF := 0
const ON := 1
## Scopes kept; more than this keeps the newest.
const MAX_SCOPES := 16

static var _shared: RefCounted = null

var path := PATH
## () -> {server, owner} for the signed-in player, or {} (Main._names_scope). Tests set their own.
var scope_source: Callable
var _scopes: Dictionary = {}
var _session: Dictionary = {}

static func shared() -> RefCounted:
	if _shared == null: _shared = load("res://services/store_support.gd").new()
	return _shared

## Installs a store as the shared one (tests), or clears it with null.
static func use_shared(store: RefCounted) -> void:
	_shared = store

func _init(storage_path: String = PATH) -> void:
	path = storage_path
	_load()

static func scope_key(server: String, owner: String) -> String:
	return server.strip_edges().trim_suffix("/") + "|" + owner

## UNKNOWN, OFF or ON for a scope, as last read (this session or an earlier one).
func state(server: String, owner: String) -> int:
	if owner.is_empty() or server.strip_edges().is_empty(): return UNKNOWN
	var key := scope_key(server, owner)
	return UNKNOWN if not _scopes.has(key) else (ON if bool(_scopes[key]) else OFF)

## A capabilities read for a scope: whether it carried the App Store field.
func note(server: String, owner: String, on: bool) -> void:
	if owner.is_empty() or server.strip_edges().is_empty(): return
	var key := scope_key(server, owner)
	_session[key] = on
	if _scopes.has(key) and bool(_scopes[key]) == on: return
	_scopes.erase(key)
	_scopes[key] = on
	while _scopes.size() > MAX_SCOPES: _scopes.erase(_scopes.keys()[0])
	_save()

## Whether a read for this scope was made in this run of the app.
func read_this_session(server: String, owner: String) -> bool:
	return _session.has(scope_key(server, owner))

## Whether this run's read for the scope said the server takes App Store purchases.
func confirmed(server: String, owner: String) -> bool:
	return bool(_session.get(scope_key(server, owner), false))

## The signed-in scope ({} without one).
func current() -> Dictionary:
	var value: Variant = scope_source.call() if scope_source.is_valid() else {}
	return value if value is Dictionary and not value.is_empty() else {}

## True on iOS while the server said, for the signed-in player, that it takes no
## App Store purchases: every paid surface is hidden then.
func hides_paid() -> bool:
	if not PlatformSupport.is_ios(): return false
	var scope := current()
	return not scope.is_empty() and state(str(scope.server), str(scope.owner)) == OFF

## Whether money may move now: anywhere but iOS, or on iOS after this run's read said on.
func may_buy() -> bool:
	if not PlatformSupport.is_ios(): return true
	var scope := current()
	return not scope.is_empty() and confirmed(str(scope.server), str(scope.owner))

## Whether this run has read the server's answer for the signed-in player: anywhere but iOS,
## always. The Pollen store sells on that read's bundles capability (Wardrobe.bundles).
func read_now() -> bool:
	if not PlatformSupport.is_ios(): return true
	var scope := current()
	return not scope.is_empty() and read_this_session(str(scope.server), str(scope.owner))

func _load() -> void:
	_scopes = {}
	var text := AtomicFile.read_text(path)
	var json := JSON.new()
	if text.is_empty() or json.parse(text) != OK: return
	var parsed: Variant = json.data
	if not parsed is Dictionary or not Typed.equal(parsed.get("schema_version"), VERSION) or not parsed.get("scopes") is Dictionary: return
	for key: Variant in parsed.scopes:
		var value: Variant = parsed.scopes[key]
		if key is String and key.contains("|") and value is bool: _scopes[key] = value
	while _scopes.size() > MAX_SCOPES: _scopes.erase(_scopes.keys()[0])

func _save() -> bool:
	return AtomicFile.write_text(path, JSON.stringify({"schema_version": VERSION, "scopes": _scopes}))
