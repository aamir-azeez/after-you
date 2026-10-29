extends RefCounted
## Pollen on this phone: a copy of what the server last confirmed. The server
## holds the only real wallet (backend/src/pollen/wallet.ts); nothing here
## counts Pollen.
##
## Kept per server and player (a scope), in one small file written whole with
## AtomicFile:
## - enabled: the server said Pollen earning is on (its capabilities);
## - item_blooms: the server said item blooms drop (its capabilities), so Help
##   publishes their odds;
## - wallet: the last confirmed balance, lifetime earned and bank, or {};
## - claims: accepted turns whose credit did not come back confirmed, to send
##   to POST /v1/pollen/turn-claims (services/pollen_client.gd). The server
##   pays each turn once, so sending one twice is harmless;
## - results: the newest confirmed turn receipts, for the results line, each
##   marked once its line was shown (presentation/pollen_result_line.gd once);
##   one kept by a build from before the mark reads as shown, so it never shows again;
##   a room's first clear that the room's finish paid this player is kept among
##   them too, under ROOM_CLEAR, from its clear claim's answer;
## - clears: first clears waiting to be claimed (POST /v1/pollen/clear-claims):
##   "room:<room_id>" for a room this player saw finished together, and
##   "level:<level_id>" for a chapter finished solo. Each is sent until the
##   server confirms it, then remembered in `cleared` so it is never sent again.
##
## Every value read from the file or a server reply is checked; anything that
## fails is dropped. A file that cannot be read reads as empty, and the client
## then asks the server for the wallet again, so nothing is lost.
const AtomicFile = preload("res://services/atomic_file.gd")
const Typed = preload("res://services/typed_values.gd")

const PATH := "user://pollen_wallet.json"
const VERSION := 1
## The request header that asks the server for Pollen (capabilities, turns).
const HEADER := "X-AfterYou-Pollen: 1"
## Turns kept waiting to be claimed; older ones go first.
const MAX_CLAIMS := 32
## The server refuses a claim for a turn older than this (rates.json turn_claim_days).
const CLAIM_DAYS := 28
const MAX_RESULTS := 8
## First clears waiting, and first clears already settled (remembered so they are not sent again).
const MAX_CLEARS := 32
const MAX_CLEARED := 256
const LEVEL_PATTERN := "^[a-z0-9-]{1,64}$"
const BONUSES := ["first_try", "gold_pace", "silver_pace", "hard"]
## Item bloom tiers (backend rates.json item_blooms); an earned item never drops.
const BLOOM_TIERS := ["common", "uncommon", "rare", "epic", "special"]
const ITEM_PATTERN := "^[a-z0-9_]{1,40}$"
const ROOM_PATTERN := "^[A-Za-z0-9_-]{22}$"
const HASH_PATTERN := "^[a-f0-9]{64}$"
## Where a room's first clear is kept among the results, in place of a turn's recording hash.
const ROOM_CLEAR := "room-clear"

## A result was kept for one of this player's turns, or for a room's first clear
## (`recording_hash` ROOM_CLEAR): a screen still up for it may show its line now.
signal result_noted(server: String, owner: String, room_id: String, recording_hash: String)

## A confirmed receipt brought an item bloom's item: it is owned now (Main
## connects it to services/wardrobe.gd note_drop, so the wardrobe shows it at once).
signal item_dropped(server: String, owner: String, item_id: String)

static var _shared: RefCounted = null
static var _room := RegEx.create_from_string(ROOM_PATTERN)
static var _hash := RegEx.create_from_string(HASH_PATTERN)
static var _level := RegEx.create_from_string(LEVEL_PATTERN)
static var _item := RegEx.create_from_string(ITEM_PATTERN)

var path := PATH
var _scopes: Dictionary = {}

static func shared() -> RefCounted:
	if _shared == null: _shared = load("res://services/pollen_wallet.gd").new()
	return _shared

## Installs a store as the shared one (tests), or clears it with null.
static func use_shared(store: RefCounted) -> void:
	_shared = store

func _init(storage_path: String = PATH) -> void:
	path = storage_path
	_load()

# --- Checks ----------------------------------------------------------------

static func _count(value: Variant, top: int = 9007199254740991) -> bool:
	return Typed.whole_number(value) and float(value) >= 0.0 and float(value) <= float(top)

## A balance: a whole number, below zero only after a refund took back what it paid.
static func _balance(value: Variant) -> bool:
	return Typed.whole_number(value) and absf(float(value)) <= 9007199254740991.0

static func valid_room(value: Variant) -> bool:
	return value is String and _room.search(value) != null

static func valid_hash(value: Variant) -> bool:
	return value is String and _hash.search(value) != null

## A wallet answer (GET /v1/pollen) as kept: whole numbers only.
static func checked_wallet(value: Variant) -> Dictionary:
	if not value is Dictionary or not Typed.equal(value.get("schema_version"), 1): return {}
	if not _balance(value.get("balance")): return {}
	for field: String in ["earned", "bank"]:
		if not _count(value.get(field)): return {}
	return {"balance": Typed.as_int(value.balance), "earned": Typed.as_int(value.earned), "bank": Typed.as_int(value.bank)}

## A turn credit's receipt (the turn reply's `pollen`, or a claim's) as kept,
## or {} when any part of it is not the contract's.
static func checked_receipt(value: Variant) -> Dictionary:
	if not value is Dictionary or not Typed.equal(value.get("schema_version"), 1) or not _count(value.get("earned")) or not _balance(value.get("balance")): return {}
	var clears: Variant = _checked_clears(value.get("clears"))
	if clears == null: return {}
	var kept := {"earned": Typed.as_int(value.earned), "balance": Typed.as_int(value.balance), "clears": clears}
	# A room clear claim's answer: the first clears the room's finish paid already.
	if value.has("paid_clears"):
		var paid: Variant = _checked_clears(value.paid_clears)
		if paid == null: return {}
		kept["paid_clears"] = paid
	if value.has("turn"):
		var turn: Variant = value.turn
		if not turn is Dictionary or not turn.get("kind") in ["bank", "after_bank"]: return {}
		for field: String in ["amount", "total", "bonus_percent", "boost", "bloom_extra"]:
			if not _count(turn.get(field)): return {}
		if not _count(turn.get("boost_percent"), 100) or not Typed.as_int(turn.get("bloom"), 0) in [1, 2, 3]: return {}
		var bonuses: Variant = turn.get("bonuses")
		if not bonuses is Array or bonuses.size() > BONUSES.size() or bonuses.any(func(bonus: Variant) -> bool: return not bonus in BONUSES): return {}
		var reason: Variant = turn.get("reason", "")
		if not reason in ["", "repeat", "bank_empty", "late"]: return {}
		var from: Variant = turn.get("boost_from", [])
		if not from is Array or from.size() > 2 or from.any(func(who: Variant) -> bool: return not who in ["you", "partner"]): return {}
		kept["turn"] = {"kind": turn.kind, "amount": Typed.as_int(turn.amount), "total": Typed.as_int(turn.total), "bonuses": bonuses.duplicate(),
			"bonus_percent": Typed.as_int(turn.bonus_percent), "bloom": Typed.as_int(turn.bloom), "bloom_extra": Typed.as_int(turn.bloom_extra),
			"boost_percent": Typed.as_int(turn.boost_percent), "boost": Typed.as_int(turn.boost), "reason": reason, "boost_from": from.duplicate()}
	if value.has("item_bloom"):
		var bloom := checked_item_bloom(value.item_bloom)
		if bloom.is_empty(): return {}
		kept["item_bloom"] = bloom
	return kept

## First clear lines as kept, or null when any is not the contract's.
static func _checked_clears(value: Variant) -> Variant:
	if not value is Array or value.size() > 4: return null
	var kept := []
	for clear: Variant in value:
		if not clear is Dictionary or not clear.get("kind") in ["clear", "hardclear"] or not _count(clear.get("total")) or not _count(clear.get("boost_percent"), 100): return null
		kept.append({"kind": clear.kind, "total": Typed.as_int(clear.total), "boost_percent": Typed.as_int(clear.boost_percent)})
	return kept

## An item bloom as kept: {tier, item_id} for a dropped item, or {tier, pollen}
## when the player owned every item of that tier; {} when it is not the contract's.
static func checked_item_bloom(value: Variant) -> Dictionary:
	if not value is Dictionary or not value.get("tier") in BLOOM_TIERS: return {}
	var item: Variant = value.get("item_id")
	if item is String and _item.search(item) != null and not value.has("pollen"): return {"tier": value.tier, "item_id": item}
	if not value.has("item_id") and _count(value.get("pollen")) and int(value.pollen) > 0: return {"tier": value.tier, "pollen": Typed.as_int(value.pollen)}
	return {}

# --- Scopes ----------------------------------------------------------------

static func scope_key(server: String, owner: String) -> String:
	return server.strip_edges().trim_suffix("/") + "|" + owner

func _scope(server: String, owner: String, create: bool = false) -> Dictionary:
	if owner.is_empty() or server.strip_edges().is_empty(): return {}
	var key := scope_key(server, owner)
	if not _scopes.has(key):
		if not create: return {}
		_scopes[key] = {"enabled": false, "item_blooms": false, "wallet": {}, "claims": [], "results": [], "clears": [], "cleared": []}
	return _scopes[key]

## Whether the server said Pollen earning is on for this player.
func enabled(server: String, owner: String) -> bool:
	return bool(_scope(server, owner).get("enabled", false))

func set_enabled(server: String, owner: String, on: bool) -> void:
	var scope := _scope(server, owner, on)
	if scope.is_empty() or bool(scope.enabled) == on: return
	scope.enabled = on
	_save()

## Whether the server said item blooms drop for this player (Help shows their odds then).
func item_blooms(server: String, owner: String) -> bool:
	var scope := _scope(server, owner)
	return not scope.is_empty() and bool(scope.enabled) and bool(scope.get("item_blooms", false))

func set_item_blooms(server: String, owner: String, on: bool) -> void:
	var scope := _scope(server, owner, on)
	if scope.is_empty() or bool(scope.get("item_blooms", false)) == on: return
	scope.item_blooms = on
	_save()

## The last confirmed wallet ({} until the server has said).
func wallet(server: String, owner: String) -> Dictionary:
	var scope := _scope(server, owner)
	return (scope.wallet as Dictionary).duplicate() if not scope.is_empty() else {}

func note_wallet(server: String, owner: String, value: Variant) -> bool:
	var kept := checked_wallet(value)
	var scope := _scope(server, owner, not kept.is_empty())
	if kept.is_empty() or scope.is_empty(): return false
	if scope.wallet != kept:
		scope.wallet = kept
		_save()
	return true

## A balance the server confirmed after a spend (services/wardrobe_client.gd).
## Earned and bank are only ever taken from a wallet answer.
func note_balance(server: String, owner: String, balance: Variant) -> bool:
	var scope := _scope(server, owner)
	if scope.is_empty() or (scope.wallet as Dictionary).is_empty() or not _balance(balance): return false
	if int(scope.wallet.balance) != Typed.as_int(balance):
		scope.wallet.balance = Typed.as_int(balance)
		_save()
	return true

## A confirmed receipt for one turn: kept for its results line, its claim goes,
## and the balance follows it.
func note_receipt(server: String, owner: String, room_id: String, recording_hash: String, value: Variant) -> bool:
	var kept := checked_receipt(value)
	var scope := _scope(server, owner, not kept.is_empty())
	if kept.is_empty() or scope.is_empty() or not valid_room(room_id) or not valid_hash(recording_hash): return false
	_drop_claim(scope, room_id, recording_hash)
	_keep_result(scope, room_id, recording_hash, kept)
	# The receipt's balance is the server's newest; earned and bank are only ever
	# taken from a wallet answer, so a phone that has none asks for one.
	if not (scope.wallet as Dictionary).is_empty(): scope.wallet.balance = kept.balance
	_save()
	result_noted.emit(server, owner, room_id, recording_hash)
	# An item bloom's item is owned now: the wardrobe shows it without asking again.
	if kept.has("item_bloom") and kept.item_bloom.has("item_id"): item_dropped.emit(server, owner, str(kept.item_bloom.item_id))
	return true

## The kept receipt for one of this player's turns, or {}.
func result_for(server: String, owner: String, room_id: String, recording_hash: String) -> Dictionary:
	var scope := _scope(server, owner)
	if scope.is_empty(): return {}
	for entry: Dictionary in scope.results:
		if entry.room_id == room_id and entry.recording_hash == recording_hash: return (entry.receipt as Dictionary).duplicate(true)
	return {}

## Whether the line for one of this player's turns was shown already.
func result_shown(server: String, owner: String, room_id: String, recording_hash: String) -> bool:
	return _result_shown(_scope(server, owner), room_id, recording_hash)

## The line for one of this player's turns was shown: it is never shown again.
func mark_shown(server: String, owner: String, room_id: String, recording_hash: String) -> void:
	var scope := _scope(server, owner)
	if scope.is_empty(): return
	for entry: Dictionary in scope.results:
		if entry.room_id == room_id and entry.recording_hash == recording_hash and not entry.shown:
			entry.shown = true
			_save()
			return

## Keeps one result, newest last. The same credit noted again (a retried reply, a
## settled claim) keeps whether its line was shown.
static func _keep_result(scope: Dictionary, room_id: String, recording_hash: String, kept: Dictionary) -> void:
	var shown := _result_shown(scope, room_id, recording_hash)
	var results: Array = scope.results.filter(func(entry: Dictionary) -> bool: return entry.recording_hash != recording_hash or entry.room_id != room_id)
	results.append({"room_id": room_id, "recording_hash": recording_hash, "receipt": kept, "shown": shown})
	scope.results = results.slice(maxi(0, results.size() - MAX_RESULTS))

static func _result_shown(scope: Dictionary, room_id: String, recording_hash: String) -> bool:
	for entry: Dictionary in scope.get("results", []):
		if entry.room_id == room_id and entry.recording_hash == recording_hash: return bool(entry.shown)
	return false

## An accepted turn whose credit did not come back confirmed: kept to claim.
## `now_ms` is this phone's clock, used only to let old claims go.
func queue_claim(server: String, owner: String, room_id: String, recording_hash: String, now_ms: int = -1) -> bool:
	var scope := _scope(server, owner, true)
	if scope.is_empty() or not valid_room(room_id) or not valid_hash(recording_hash): return false
	if not result_for(server, owner, room_id, recording_hash).is_empty(): return false
	var now := now_ms if now_ms >= 0 else int(Time.get_unix_time_from_system() * 1000.0)
	var claims: Array = scope.claims.filter(func(entry: Dictionary) -> bool: return entry.room_id != room_id or entry.recording_hash != recording_hash)
	claims.append({"room_id": room_id, "recording_hash": recording_hash, "at": now})
	scope.claims = _fresh(claims, now)
	_save()
	return true

## Up to `limit` claims to send, oldest first, as the claims route takes them.
func claims(server: String, owner: String, limit: int = MAX_CLAIMS, now_ms: int = -1) -> Array:
	var scope := _scope(server, owner)
	if scope.is_empty(): return []
	var now := now_ms if now_ms >= 0 else int(Time.get_unix_time_from_system() * 1000.0)
	var kept := _fresh(scope.claims, now)
	if kept.size() != scope.claims.size():
		scope.claims = kept
		_save()
	return kept.slice(0, limit).map(func(entry: Dictionary) -> Dictionary: return {"room_id": entry.room_id, "recording_hash": entry.recording_hash})

## The server's answer to one claim: credited keeps the receipt, refused lets
## the claim go for good, anything else keeps it for the next send, behind the
## others, so one the server cannot pay yet never holds up newer ones.
func settle_claim(server: String, owner: String, room_id: String, recording_hash: String, answer: Variant) -> void:
	var scope := _scope(server, owner)
	if scope.is_empty() or not answer is Dictionary: return
	if answer.get("status") == "credited" and note_receipt(server, owner, room_id, recording_hash, answer.get("receipt")): return
	if answer.get("status") == "refused" or answer.get("status") == "credited":
		_drop_claim(scope, room_id, recording_hash)
	else:
		var waiting: Array = scope.claims.filter(func(entry: Dictionary) -> bool: return entry.room_id == room_id and entry.recording_hash == recording_hash)
		_drop_claim(scope, room_id, recording_hash)
		scope.claims.append_array(waiting)
	_save()

# --- First clears ------------------------------------------------------------

## A first clear's key: "room:<room_id>" (finished together) or "level:<level_id>" (finished solo).
static func valid_clear(key: Variant) -> bool:
	if not key is String: return false
	if key.begins_with("room:"): return valid_room(key.substr(5))
	return key.begins_with("level:") and _level.search(key.substr(6)) != null

## Queues a first clear to claim, unless it waits already or the server settled it.
func queue_clear(server: String, owner: String, key: String) -> bool:
	if not valid_clear(key): return false
	var scope := _scope(server, owner, true)
	if scope.is_empty() or key in scope.cleared or key in scope.clears: return false
	scope.clears.append(key)
	scope.clears = scope.clears.slice(maxi(0, scope.clears.size() - MAX_CLEARS))
	_save()
	return true

## A first clear this player's own turn claim already carries (the turn that finished the
## chapter pays its clears with it): never sent as a clear claim of its own.
func mark_cleared(server: String, owner: String, key: String) -> void:
	if not valid_clear(key): return
	var scope := _scope(server, owner, true)
	if scope.is_empty() or key in scope.cleared: return
	scope.clears.erase(key)
	_remember_cleared(scope, key)
	_save()

## Up to `limit` waiting first clears, as {key, claim} with the claim as the route takes it.
func clear_claims(server: String, owner: String, limit: int = MAX_CLEARS) -> Array:
	var scope := _scope(server, owner)
	if scope.is_empty(): return []
	return scope.clears.slice(0, limit).map(func(key: String) -> Dictionary:
		return {"key": key, "claim": {"room_id": key.substr(5)} if key.begins_with("room:") else {"level_id": key.substr(6)}})

## The server's answer to one first clear: credited or refused settles it for good (a refusal
## is final: no facts for the room, an unknown chapter, or no Full Journey for a paid one);
## anything else keeps it for the next send, behind the others.
func settle_clear(server: String, owner: String, key: String, answer: Variant) -> void:
	var scope := _scope(server, owner)
	if scope.is_empty() or not answer is Dictionary or not key in scope.clears: return
	scope.clears.erase(key)
	var room := ""
	if answer.get("status") in ["credited", "refused"]:
		_remember_cleared(scope, key)
		var receipt := checked_receipt(answer.get("receipt"))
		if not receipt.is_empty() and not (scope.wallet as Dictionary).is_empty(): scope.wallet.balance = receipt.balance
		# A room's first clear, for its end card: what this claim paid, or else what the
		# room's finish paid already (a server from before `paid_clears` says nothing).
		var lines: Array = receipt.get("clears", []) if not receipt.get("clears", []).is_empty() else receipt.get("paid_clears", [])
		if key.begins_with("room:") and not lines.is_empty():
			room = key.substr(5)
			var earned: int = lines.reduce(func(sum: int, line: Dictionary) -> int: return sum + int(line.total), 0)
			_keep_result(scope, room, ROOM_CLEAR, {"earned": earned, "balance": receipt.balance, "clears": lines})
	else:
		scope.clears.append(key)
	_save()
	if not room.is_empty(): result_noted.emit(server, owner, room, ROOM_CLEAR)

## Whether a first clear is settled (tests and the client's queueing).
func cleared(server: String, owner: String, key: String) -> bool:
	return key in _scope(server, owner).get("cleared", [])

func _remember_cleared(scope: Dictionary, key: String) -> void:
	scope.cleared.append(key)
	scope.cleared = scope.cleared.slice(maxi(0, scope.cleared.size() - MAX_CLEARED))

func _drop_claim(scope: Dictionary, room_id: String, recording_hash: String) -> void:
	scope.claims = scope.claims.filter(func(entry: Dictionary) -> bool: return entry.room_id != room_id or entry.recording_hash != recording_hash)

static func _fresh(claims: Array, now: int) -> Array:
	var oldest := now - CLAIM_DAYS * 86400000
	var kept := claims.filter(func(entry: Dictionary) -> bool: return int(entry.at) >= oldest and int(entry.at) <= now + 86400000)
	return kept.slice(maxi(0, kept.size() - MAX_CLAIMS))

# --- File ------------------------------------------------------------------

func _load() -> void:
	_scopes = {}
	var parsed: Variant = _parsed(AtomicFile.read_text(path, func(text: String) -> bool:
		var value: Variant = _parsed(text)
		return value is Dictionary and Typed.equal(value.get("schema_version"), VERSION) and value.get("scopes") is Dictionary))
	if not parsed is Dictionary or not parsed.get("scopes") is Dictionary: return
	for key: Variant in parsed.scopes:
		var value: Variant = parsed.scopes[key]
		if not key is String or not key.contains("|") or not value is Dictionary: continue
		var scope := {"enabled": value.get("enabled") == true, "item_blooms": value.get("item_blooms") == true, "wallet": {}, "claims": [], "results": [], "clears": [], "cleared": []}
		for list: String in ["clears", "cleared"]:
			if value.get(list) is Array:
				for entry: Variant in value[list]:
					if valid_clear(entry) and not entry in scope[list]: scope[list].append(entry)
		scope.clears = scope.clears.slice(maxi(0, scope.clears.size() - MAX_CLEARS))
		scope.cleared = scope.cleared.slice(maxi(0, scope.cleared.size() - MAX_CLEARED))
		var kept_wallet: Variant = value.get("wallet")
		if kept_wallet is Dictionary and not kept_wallet.is_empty(): scope.wallet = checked_wallet(kept_wallet.merged({"schema_version": 1}))
		if value.get("claims") is Array:
			for entry: Variant in value.claims:
				if entry is Dictionary and valid_room(entry.get("room_id")) and valid_hash(entry.get("recording_hash")) and _count(entry.get("at")):
					scope.claims.append({"room_id": entry.room_id, "recording_hash": entry.recording_hash, "at": Typed.as_int(entry.at)})
			scope.claims = scope.claims.slice(maxi(0, scope.claims.size() - MAX_CLAIMS))
		if value.get("results") is Array:
			for entry: Variant in value.results:
				if not entry is Dictionary or not valid_room(entry.get("room_id")) or not (valid_hash(entry.get("recording_hash")) or entry.get("recording_hash") == ROOM_CLEAR): continue
				var receipt := checked_receipt(Typed.as_dict(entry.get("receipt")).merged({"schema_version": 1}))
				if not receipt.is_empty(): scope.results.append({"room_id": entry.room_id, "recording_hash": entry.recording_hash, "receipt": receipt, "shown": entry.get("shown") != false})
			scope.results = scope.results.slice(maxi(0, scope.results.size() - MAX_RESULTS))
		_scopes[key] = scope

## JSON text as a value, or null, without logging an error for a missing or damaged file.
static func _parsed(text: String) -> Variant:
	var json := JSON.new()
	return json.data if not text.is_empty() and json.parse(text) == OK else null

func _save() -> bool:
	return AtomicFile.write_text(path, JSON.stringify({"schema_version": VERSION, "scopes": _scopes}))
