extends RefCounted
## The server's public switches that decide which of Home's rows show (Duels,
## the leaderboard surfaces, together Hard): the same for every player, so they are kept
## per server only, never per player, on this phone (AtomicFile), and a launch
## shows the rows the last answer said at once.
##
## Two answers write them, and the newest wins:
## - GET /v1/app-status, which the app already asks at launch and on a resume
##   six hours on (services/app_status.gd): it carries `switches` when asked
##   with SWITCHES_HEADER (backend src/app-status.ts). No identity, no Durable
##   Object, no extra request.
## - every authorized capabilities read (services/relay_online_session.gd
##   load_capabilities), whose duels and leaderboards fields say the same.
## Anything else (offline, a timeout, a 429 from the public limiter, a server
## that does not send them, a malformed answer) changes nothing kept.
##
## A row shown from here still opens through the authorized capabilities read,
## made when the player taps it (Main._show_duels), so nothing is ever used on
## this answer alone.
const AtomicFile = preload("res://services/atomic_file.gd")
const Typed = preload("res://services/typed_values.gd")

## Asked with app-status; the value is the switch set this build reads.
const SWITCHES_HEADER := "X-AfterYou-Switches: 1"
## hard_mode, leaderboards_platform (posts need platform accounts, backend
## leaderboards/platform-rule.ts) and public_duels (Settings' Public duels switch)
## come only from capabilities reads, kept so a launch knows them.
const NAMES: Array[String] = ["duels", "leaderboards", "hard_mode", "leaderboards_platform", "public_duels"]
const PATH := "user://server_switches.json"
const VERSION := 1
## Servers kept; more than this keeps the newest.
const MAX_SERVERS := 8

## A switch changed for some server.
signal changed

static var _shared: RefCounted = null

var path := PATH
var _servers: Dictionary = {}

static func shared() -> RefCounted:
	if _shared == null: _shared = load("res://services/server_switches.gd").new()
	return _shared

## Installs a store as the shared one (tests), or clears it with null.
static func use_shared(store: RefCounted) -> void:
	_shared = store

func _init(storage_path: String = PATH) -> void:
	path = storage_path
	_load()

static func server_key(server: String) -> String:
	return server.strip_edges().trim_suffix("/")

## The well formed part of an answer's `switches`: each known name with a bool
## value. {} for anything that is not an object or names none of them.
static func parse(value: Variant) -> Dictionary:
	if not value is Dictionary: return {}
	var known := {}
	for name: String in NAMES:
		if value.get(name) is bool: known[name] = value[name]
	return known

## What the server last said for `name`; false before any answer.
func on(server: String, name: String) -> bool:
	return bool(_servers.get(server_key(server), {}).get(name, false))

## What the server `api` talks to (RoomsApi base_url) last said for `name`.
func on_for(api: Object, name: String) -> bool:
	var server: Variant = api.get("base_url") if api != null else null
	return server is String and on(server, name)

## An answer for a server: only its well formed switches change, the rest stay.
func note(server: String, values: Dictionary) -> void:
	var key := server_key(server)
	var known := parse(values)
	if key.is_empty() or known.is_empty(): return
	var kept: Dictionary = _servers.get(key, {}).duplicate()
	var before := kept.duplicate()
	kept.merge(known, true)
	if kept == before: return
	_servers.erase(key)
	_servers[key] = kept
	while _servers.size() > MAX_SERVERS: _servers.erase(_servers.keys()[0])
	_save()
	changed.emit()

func _load() -> void:
	_servers = {}
	var parsed: Variant = AtomicFile.read_json(path, func(value: Variant) -> bool:
		return value is Dictionary and Typed.equal(value.get("schema_version"), VERSION) and value.get("servers") is Dictionary)
	if not parsed is Dictionary: return
	for key: Variant in parsed.servers:
		var known := parse(parsed.servers[key])
		if key is String and not key.is_empty() and not known.is_empty(): _servers[key] = known
	while _servers.size() > MAX_SERVERS: _servers.erase(_servers.keys()[0])

func _save() -> bool:
	return AtomicFile.write_text(path, JSON.stringify({"schema_version": VERSION, "servers": _servers}))
