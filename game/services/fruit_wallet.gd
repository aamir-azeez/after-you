extends RefCounted
## Fruits on this phone: a copy of what the server last said (the `fruits` part
## of GET /v1/pollen while FRUITS is on; backend/src/pollen/). The server holds
## the only real Fruit balance; nothing here counts, pays or prices Fruits.
## It sits beside the Pollen wallet (services/pollen_wallet.gd) the way the
## monthly grant does (services/pollen_grant.gd): every wallet read feeds it
## through services/wallet_reply.gd, every turn or clear receipt through
## pollen_wallet.gd note_receipt, every spend receipt through wallet_reply.gd
## note_spend and every pack claim through services/bundle_claims.gd.
##
## Kept per server and player (a scope), in one small file written whole with
## AtomicFile:
## - enabled: the server said Fruits are on (capabilities pollen_fruits_version);
## - packs: the server said Fruit packs sell in this phone's store too
##   (pollen_fruit_packs_version, or pollen_app_store_fruit_packs_version on iOS);
## - part: the last `fruits` part, as kept by checked_part ({} until read):
##   balance (below 0 after a refund: Fruit spending is blocked then), earned,
##   sunshine {left, turns, price}, convert {pollen_per_fruit, step},
##   first_pack_gift and first_pack_percent, achievements (each with `paid`), the
##   Full Journey Fruits (grant) and the Fruit ladder everyone is shown (ladder:
##   {first, step, every, top, welcome}). A sub part off the contract is left out, so
##   the screen hides only what it needs (Sunshine, converting, the grant line);
## - paid: every achievement id this phone knows was paid (reads and receipts);
## - unlocks: achievements paid since this phone last knew, each {id, fruits},
##   oldest first, until a screen shows its toast (mark_unlock_shown). The first
##   read of a scope only learns what was paid before, so a new install or a
##   second phone never opens with a row of old toasts; a receipt's `paid` list
##   is always news. A late read never takes back a paid achievement.
##
## Replies may land out of order; the newest one noted stands, as for Pollen.
## Every value read from the file or a server reply is checked; anything that
## fails is dropped, and a file that cannot be read reads as empty (the client
## then reads the wallet again: needs_read).
const AtomicFile = preload("res://services/atomic_file.gd")
const Typed = preload("res://services/typed_values.gd")

const PATH := "user://fruit_wallet.json"
const VERSION := 1
const ID_PATTERN := "^[a-z0-9_]{1,40}$"
const LEVEL_PATTERN := "^[a-z0-9-]{1,64}$"
## Rows an achievements list may hold: well past the server's 15.
const MAX_ACHIEVEMENTS := 32
## Paid ids remembered, and toasts kept waiting.
const MAX_PAID := 64
const MAX_UNLOCKS := 16
const MAX_TIME := 8640000000000000
const MAX_AMOUNT := 1000000

## The kept Fruits of a scope changed (a read, a receipt, a spend, a claim).
signal changed(server: String, owner: String)
## An achievement unlock now waits to be shown (unlocks()).
signal unlocked(server: String, owner: String)

static var _shared: RefCounted = null
static var _id := RegEx.create_from_string(ID_PATTERN)
static var _level := RegEx.create_from_string(LEVEL_PATTERN)

var path := PATH
var _scopes: Dictionary = {}
## Scope keys whose answered read had no Fruits part this build could keep (memory
## only): needs_read asks no more this launch, so a server that sends none costs one read.
var _unkept: Dictionary = {}

static func shared() -> RefCounted:
	if _shared == null: _shared = load("res://services/fruit_wallet.gd").new()
	return _shared

## Installs a store as the shared one (tests), or clears it with null.
static func use_shared(store: RefCounted) -> void:
	_shared = store

func _init(storage_path: String = PATH) -> void:
	path = storage_path
	_load()

# --- Checks ----------------------------------------------------------------

static func _count(value: Variant, top: int = MAX_AMOUNT) -> bool:
	return Typed.whole_number(value) and float(value) >= 0.0 and float(value) <= float(top)

static func _balance(value: Variant) -> bool:
	return Typed.whole_number(value) and absf(float(value)) <= 9007199254740991.0

static func valid_id(value: Variant) -> bool:
	return value is String and _id.search(value) != null

## The `fruits` part of a wallet answer as kept, or {} when it is missing or its
## balance or earned is not the contract's. Each other sub part off the contract
## is left out on its own (an achievement row by itself).
static func checked_part(value: Variant) -> Dictionary:
	if not value is Dictionary or not Typed.equal(value.get("schema_version"), 1): return {}
	if not _balance(value.get("balance")) or not _count(value.get("earned"), 9007199254740991): return {}
	var kept := {"balance": Typed.as_int(value.balance), "earned": Typed.as_int(value.earned), "first_pack_gift": false, "first_pack_percent": 0, "achievements": []}
	var sunshine: Variant = value.get("sunshine")
	if sunshine is Dictionary and _count(sunshine.get("left")) and _count(sunshine.get("turns")) and _count(sunshine.get("price")) and int(sunshine.turns) > 0 and int(sunshine.price) > 0 and int(sunshine.left) <= int(sunshine.turns):
		kept["sunshine"] = {"left": Typed.as_int(sunshine.left), "turns": Typed.as_int(sunshine.turns), "price": Typed.as_int(sunshine.price)}
	var convert: Variant = value.get("convert")
	if convert is Dictionary and _count(convert.get("pollen_per_fruit")) and _count(convert.get("step")) and int(convert.pollen_per_fruit) > 0 and int(convert.step) > 0:
		kept["convert"] = {"pollen_per_fruit": Typed.as_int(convert.pollen_per_fruit), "step": Typed.as_int(convert.step)}
	if value.get("first_pack_gift") is bool and _count(value.get("first_pack_percent"), 1000):
		kept.first_pack_percent = Typed.as_int(value.first_pack_percent)
		kept.first_pack_gift = value.first_pack_gift and kept.first_pack_percent > 0
	var rows: Variant = value.get("achievements")
	if rows is Array and rows.size() <= MAX_ACHIEVEMENTS:
		var seen := {}
		for row: Variant in rows:
			var achievement := checked_achievement(row)
			if achievement.is_empty() or seen.has(achievement.id): continue
			seen[achievement.id] = true
			kept.achievements.append(achievement)
	var grant := checked_grant(value.get("grant"))
	if not grant.is_empty(): kept["grant"] = grant
	var ladder := checked_ladder(value.get("ladder"))
	if not ladder.is_empty(): kept["ladder"] = ladder
	return kept

## The Full Journey Fruit ladder as kept ({first, step, every, top, welcome}), or {}:
## month n pays min(first + step * floor((n - 1) / every), top), and the welcome basket once.
static func checked_ladder(value: Variant) -> Dictionary:
	if not value is Dictionary: return {}
	for field: String in ["first", "step", "every", "top", "welcome"]:
		if not _count(value.get(field)): return {}
	if int(value.first) <= 0 or int(value.every) <= 0 or int(value.top) < int(value.first): return {}
	return {"first": Typed.as_int(value.first), "step": Typed.as_int(value.step), "every": Typed.as_int(value.every), "top": Typed.as_int(value.top), "welcome": Typed.as_int(value.welcome)}

## One achievement row as kept, or {}: {id, fruits, goal, progress, live, paid,
## paid_at?, level_id?, room_id?}. `paid` is true once its Fruits were paid.
static func checked_achievement(row: Variant) -> Dictionary:
	if not row is Dictionary or not valid_id(row.get("id")) or not _count(row.get("fruits")) or not _count(row.get("goal")) or not _count(row.get("progress")) or not row.get("live") is bool: return {}
	var kept := {"id": row.id, "fruits": Typed.as_int(row.fruits), "goal": Typed.as_int(row.goal), "progress": mini(Typed.as_int(row.progress), Typed.as_int(row.goal)), "live": row.live, "paid": false}
	if row.has("paid_at"):
		if not _count(row.paid_at, MAX_TIME): return {}
		kept["paid_at"] = Typed.as_int(row.paid_at)
		kept.paid = true
	if row.has("level_id"):
		if not row.level_id is String or _level.search(row.level_id) == null: return {}
		kept["level_id"] = row.level_id
	if row.has("room_id"):
		if not Typed.valid_id(row.room_id): return {}
		kept["room_id"] = row.room_id
	return kept

## The Full Journey Fruits as kept: {next, top, welcome, welcome_paid, latest?
## {amount, welcome, at}}, or {}.
static func checked_grant(value: Variant) -> Dictionary:
	if not value is Dictionary or not _count(value.get("next")) or not _count(value.get("top")) or not _count(value.get("welcome")) or not value.get("welcome_paid") is bool: return {}
	var kept := {"next": Typed.as_int(value.next), "top": Typed.as_int(value.top), "welcome": Typed.as_int(value.welcome), "welcome_paid": value.welcome_paid}
	if value.has("latest"):
		var latest: Variant = value.latest
		if not latest is Dictionary or not _count(latest.get("amount")) or not _count(latest.get("welcome")) or not _count(latest.get("at"), MAX_TIME): return {}
		kept["latest"] = {"amount": Typed.as_int(latest.amount), "welcome": Typed.as_int(latest.welcome), "at": Typed.as_int(latest.at)}
	return kept

## A receipt's `fruits` part (a turn or claim credit: board 6b) as kept, or {}:
## {balance, paid: [{id, amount}]}. A paid line off the contract is left out.
static func checked_credit(value: Variant) -> Dictionary:
	if not value is Dictionary or not _balance(value.get("balance")) or not value.get("paid") is Array or value.paid.size() > MAX_ACHIEVEMENTS: return {}
	var paid: Array = []
	for line: Variant in value.paid:
		if line is Dictionary and valid_id(line.get("id")) and _count(line.get("amount")) and not paid.any(func(kept: Dictionary) -> bool: return kept.id == line.id):
			paid.append({"id": line.id, "amount": Typed.as_int(line.amount)})
	return {"balance": Typed.as_int(value.balance), "paid": paid}

# --- Scopes ----------------------------------------------------------------

static func scope_key(server: String, owner: String) -> String:
	return server.strip_edges().trim_suffix("/") + "|" + owner

func _scope(server: String, owner: String, create: bool = false) -> Dictionary:
	if owner.is_empty() or server.strip_edges().is_empty(): return {}
	var key := scope_key(server, owner)
	if not _scopes.has(key):
		if not create: return {}
		_scopes[key] = {"enabled": false, "packs": false, "part": {}, "paid": [], "unlocks": [], "baseline": false}
	return _scopes[key]

## Whether the server said Fruits are on for this player.
func enabled(server: String, owner: String) -> bool:
	return bool(_scope(server, owner).get("enabled", false))

## Whether the server said Fruit packs sell in this phone's store (never without Fruits).
func packs(server: String, owner: String) -> bool:
	var scope := _scope(server, owner)
	return bool(scope.get("enabled", false)) and bool(scope.get("packs", false))

## The server's answer (services/relay_online_session.gd): Fruits `on`, and packs with them.
func set_enabled(server: String, owner: String, on: bool, packs_on: bool = false) -> void:
	var scope := _scope(server, owner, on)
	var selling := on and packs_on
	if scope.is_empty() or bool(scope.enabled) == on and bool(scope.packs) == selling: return
	scope.enabled = on
	scope.packs = selling
	_save()
	changed.emit(server, owner)

## Whether the wallet should be read for Fruits: they are on and no part is kept yet.
func needs_read(server: String, owner: String) -> bool:
	var scope := _scope(server, owner)
	return bool(scope.get("enabled", false)) and (scope.part as Dictionary).is_empty() and not _unkept.has(scope_key(server, owner))

## A wallet answer (services/wallet_reply.gd only): keeps its `fruits` part when it has one.
func note_view(server: String, owner: String, value: Variant) -> bool:
	if not value is Dictionary: return false
	var kept := checked_part(value.get("fruits"))
	var scope := _scope(server, owner, not kept.is_empty())
	if kept.is_empty() and enabled(server, owner): _unkept[scope_key(server, owner)] = true
	if kept.is_empty() or scope.is_empty(): return false
	_unkept.erase(scope_key(server, owner))
	var news := false
	var first: bool = not bool(scope.baseline)
	var learned := first
	for row: Dictionary in kept.achievements:
		if not row.paid or row.id in scope.paid: continue
		_remember_paid(scope, row.id)
		learned = true
		# The first read learns what was paid before; after it, a newly paid one is news.
		if not first: news = _add_unlock(scope, row.id, int(row.fruits)) or news
	scope.baseline = true
	if scope.part == kept and not learned: return true
	scope.part = kept
	_save()
	changed.emit(server, owner)
	if news: unlocked.emit(server, owner)
	return true

## The last `fruits` part ({} until the server has said), each achievement's
## `paid` true too when a receipt paid it since that read.
func part(server: String, owner: String) -> Dictionary:
	var scope := _scope(server, owner)
	if scope.is_empty(): return {}
	var kept: Dictionary = (scope.part as Dictionary).duplicate(true)
	for row: Dictionary in kept.get("achievements", []):
		if row.id in scope.paid: row.paid = true
	return kept

## The kept part itself, read only (the getters below; screens take part()'s copy).
func _kept(server: String, owner: String) -> Dictionary:
	return _scope(server, owner).get("part", {})

## The Fruit balance, or 0 while unknown (part() is empty then).
func balance(server: String, owner: String) -> int:
	return int(_kept(server, owner).get("balance", 0))

## Whether Fruit spending is blocked: a refund took the balance below 0.
func blocked(server: String, owner: String) -> bool:
	return balance(server, owner) < 0

## The first Fruit pack's gift as an offer, in the Pollen bundles' shape, for
## services/pollen_bundles.gd adds, cover and gift_percent.
func offer(server: String, owner: String) -> Dictionary:
	var kept := _kept(server, owner)
	return {"first_gift": bool(kept.get("first_pack_gift", false)), "first_gift_percent": int(kept.get("first_pack_percent", 0))}

## Sunshine as kept ({left, turns, price}), or {} while unknown.
func sunshine(server: String, owner: String) -> Dictionary:
	return (_kept(server, owner).get("sunshine", {}) as Dictionary).duplicate()

## Whether Sunshine can be bought now: none active, the price known and covered, and nothing blocked.
func sunshine_buyable(server: String, owner: String) -> bool:
	var kept := sunshine(server, owner)
	return not kept.is_empty() and int(kept.left) == 0 and balance(server, owner) >= int(kept.price) and not blocked(server, owner)

## The Full Journey Fruit ladder as kept ({first, step, every, top, welcome}), or {} while unknown.
func ladder(server: String, owner: String) -> Dictionary:
	return (_kept(server, owner).get("ladder", {}) as Dictionary).duplicate()

## The convert rules as kept ({pollen_per_fruit, step}), or {} while unknown.
func convert_rules(server: String, owner: String) -> Dictionary:
	return (_kept(server, owner).get("convert", {}) as Dictionary).duplicate()

## Whether `fruits` is a count the server converts: at least one step, a whole number of steps.
func convert_valid(server: String, owner: String, fruits: int) -> bool:
	var rules := convert_rules(server, owner)
	return not rules.is_empty() and fruits >= int(rules.step) and fruits % int(rules.step) == 0

## The Pollen `fruits` Fruits make, or 0 while the rules are unknown.
func convert_pollen(server: String, owner: String, fruits: int) -> int:
	var rules := convert_rules(server, owner)
	return maxi(fruits, 0) * int(rules.get("pollen_per_fruit", 0))

## The Fruits a monthly instalment paid at `at` (services/pollen_grant.gd pending's
## instalment) brought, {amount, welcome}, or {} when the kept grant names another.
func grant_paid(server: String, owner: String, at: int) -> Dictionary:
	var latest: Variant = (_kept(server, owner).get("grant", {}) as Dictionary).get("latest")
	return {"amount": int(latest.amount), "welcome": int(latest.welcome)} if latest is Dictionary and int(latest.at) == at else {}

# --- Receipts --------------------------------------------------------------

## A confirmed turn or clear receipt (services/pollen_wallet.gd checked_receipt):
## its `fruits` balance and paid achievements, and the Sunshine turns left.
func note_receipt(server: String, owner: String, receipt: Dictionary) -> bool:
	var scope := _scope(server, owner)
	if scope.is_empty() or not bool(scope.enabled): return false
	var credit: Dictionary = receipt.get("fruits", {})
	var news := false
	if not credit.is_empty():
		_set_balance(scope, int(credit.balance))
		for line: Dictionary in credit.paid:
			if line.id in scope.paid: continue
			_remember_paid(scope, line.id)
			news = _add_unlock(scope, line.id, int(line.amount)) or news
	if receipt.has("sunshine_left"): _set_sunshine(scope, int(receipt.sunshine_left))
	if credit.is_empty() and not receipt.has("sunshine_left"): return false
	_save()
	changed.emit(server, owner)
	if news: unlocked.emit(server, owner)
	return true

## A Fruit balance the server confirmed (a spend's `fruit_balance`, a claim's `fruit_balance`).
func note_balance(server: String, owner: String, value: Variant) -> bool:
	var scope := _scope(server, owner)
	if scope.is_empty() or (scope.part as Dictionary).is_empty() or not _balance(value): return false
	if int(scope.part.balance) == Typed.as_int(value): return true
	_set_balance(scope, Typed.as_int(value))
	_save()
	changed.emit(server, owner)
	return true

## A spend receipt (POST /v1/pollen/spend, services/wallet_reply.gd note_spend):
## its `fruit_balance` and `sunshine_left`, when it has them.
func note_spend(server: String, owner: String, receipt: Variant) -> bool:
	var scope := _scope(server, owner)
	if scope.is_empty() or not receipt is Dictionary: return false
	var noted := false
	if _balance(receipt.get("fruit_balance")) and not (scope.part as Dictionary).is_empty():
		_set_balance(scope, Typed.as_int(receipt.fruit_balance))
		noted = true
	if _count(receipt.get("sunshine_left")): noted = _set_sunshine(scope, Typed.as_int(receipt.sunshine_left)) or noted
	if noted:
		_save()
		changed.emit(server, owner)
	return noted

static func _set_balance(scope: Dictionary, value: int) -> void:
	if not (scope.part as Dictionary).is_empty(): scope.part.balance = value

static func _set_sunshine(scope: Dictionary, left: int) -> bool:
	if (scope.part as Dictionary).is_empty() or not scope.part.has("sunshine"): return false
	scope.part.sunshine.left = clampi(left, 0, int(scope.part.sunshine.turns))
	return true

# --- Unlocks ---------------------------------------------------------------

## Achievements paid and not shown yet, oldest first: [{id, fruits}].
func unlocks(server: String, owner: String) -> Array:
	var scope := _scope(server, owner)
	return (scope.get("unlocks", []) as Array).duplicate(true)

## The toast for achievement `id` was shown: it never shows again.
func mark_unlock_shown(server: String, owner: String, id: String) -> void:
	var scope := _scope(server, owner)
	if scope.is_empty(): return
	var left: Array = scope.unlocks.filter(func(entry: Dictionary) -> bool: return entry.id != id)
	if left.size() == scope.unlocks.size(): return
	scope.unlocks = left
	_save()

static func _remember_paid(scope: Dictionary, id: String) -> void:
	scope.paid.append(id)
	scope.paid = scope.paid.slice(maxi(0, scope.paid.size() - MAX_PAID))

static func _add_unlock(scope: Dictionary, id: String, fruits: int) -> bool:
	if scope.unlocks.any(func(entry: Dictionary) -> bool: return entry.id == id): return false
	scope.unlocks.append({"id": id, "fruits": fruits})
	scope.unlocks = scope.unlocks.slice(maxi(0, scope.unlocks.size() - MAX_UNLOCKS))
	return true

# --- File ------------------------------------------------------------------

## Forgets everything kept for a player on every server (account deletion).
## False when the file, or a damaged copy of it kept aside, could not be changed (services/deleted_identity_stores.gd tries again).
func clear_owner(owner: String) -> bool:
	for key: String in _scopes.keys():
		if key.get_slice("|", 1) == owner: _scopes.erase(key)
	# Written even when nothing changed: a damaged file read as empty, and the
	# copy of it kept aside (AtomicFile.read_json), hold every player's Fruits here.
	var saved := _save()
	return AtomicFile.remove_unreadable(path) and saved

func _load() -> void:
	_scopes = {}
	var parsed: Variant = AtomicFile.read_json(path, func(value: Variant) -> bool:
		return value is Dictionary and Typed.equal(value.get("schema_version"), VERSION) and value.get("scopes") is Dictionary)
	if not parsed is Dictionary or not parsed.get("scopes") is Dictionary: return
	for key: Variant in parsed.scopes:
		var value: Variant = parsed.scopes[key]
		if not key is String or not key.contains("|") or not value is Dictionary: continue
		var on: bool = value.get("enabled") == true
		var scope := {"enabled": on, "packs": on and value.get("packs") == true, "part": {}, "paid": [], "unlocks": [], "baseline": value.get("baseline") == true}
		var saved: Variant = value.get("part")
		if saved is Dictionary and not saved.is_empty(): scope.part = checked_part(saved.merged({"schema_version": 1}))
		# A saved row keeps its derived `paid`; checked_achievement reads only paid_at, so it is set again from the list.
		if value.get("paid") is Array:
			for id: Variant in value.paid:
				if valid_id(id) and not id in scope.paid: scope.paid.append(id)
			scope.paid = scope.paid.slice(maxi(0, scope.paid.size() - MAX_PAID))
		if value.get("unlocks") is Array:
			for entry: Variant in value.unlocks:
				if entry is Dictionary and valid_id(entry.get("id")) and _count(entry.get("fruits")) and not scope.unlocks.any(func(kept: Dictionary) -> bool: return kept.id == entry.id):
					scope.unlocks.append({"id": entry.id, "fruits": Typed.as_int(entry.fruits)})
			scope.unlocks = scope.unlocks.slice(maxi(0, scope.unlocks.size() - MAX_UNLOCKS))
		_scopes[key] = scope

func _save() -> bool:
	return AtomicFile.write_text(path, JSON.stringify({"schema_version": VERSION, "scopes": _scopes}))
