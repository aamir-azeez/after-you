extends RefCounted
## Duel energy on this phone: a copy of what the server last said (the `energy`
## part of GET /v1/pollen, of each duel start or join reply, and of the refill
## receipt, while the server has ENERGY on; backend/src/pollen/energy.ts). The
## server holds the only real meter; nothing here spends, refunds or refills.
## Every part arrives through services/wallet_reply.gd (note, note_spend,
## note_duel), so a read, a duel reply and a refill feed it the same way.
##
## The server keeps one time per player, `full_at`, when the meter is full:
## energy at a time t is max - ceil(max(0, full_at - t) / step_ms), from 0 to max.
## Each part carries the server's `now`, so the phone works t out on the
## server's clock (its own clock plus the offset seen when the part arrived).
## The energy the server named is a floor until the next part: only a spend
## lowers it, and every spend comes back with a part, so a phone clock turned
## back never empties the meter. Nothing ticks here; a screen asks meter() when
## it draws.
##
## Kept per server and player (a scope), in memory only: the duels lobby reads
## the wallet when it opens with nothing kept (needs_read), so a new launch
## costs one read. Replies may land out of order: the part with the newest
## server `now` stands, so a read sent before a start never undoes the start.
## A start refused as energy_empty says the meter is 0 without a part: it reads
## 0, with no time for the next one, until the read that follows (note_empty).
const Typed = preload("res://services/typed_values.gd")
const PATH := "res://services/duel_energy.gd"
const MAX_TIME := 8640000000000000
## Bounds a part must keep: a meter of at most MAX_TOP, a step of at most a day.
const MAX_TOP := 64
const MAX_STEP_MS := 86400000
const MAX_PRICE := 1000000
## A kept meter older than this is read again when Duels opens: a partner's
## start, or a start on another phone, spends from it unseen.
const FRESH_MS := 5 * 60 * 1000
## The Full Journey card's perk line ("Duel energy: 7 instead of 5"): the
## server's ENERGY.full_journey_max and ENERGY.max (backend/src/pollen/energy.ts).
## The wallet part carries only this player's own max, so a player without Full
## Journey never hears the 7; these stand in until the server sends both.
const PLAIN_MAX := 5
const FULL_JOURNEY_MAX := 7

## The kept meter of a scope changed (a part, a refusal, the switch).
signal changed(server: String, owner: String)

static var _shared: RefCounted = null

## () -> int: this phone's clock in Unix ms; tests set their own.
var clock: Callable
var _scopes: Dictionary = {}

static func shared() -> RefCounted:
	if _shared == null: _shared = load(PATH).new()
	return _shared

## Installs a store as the shared one (tests), or clears it with null.
static func use_shared(store: RefCounted) -> void:
	_shared = store

func now_ms() -> int:
	return int(clock.call()) if clock.is_valid() else int(Time.get_unix_time_from_system() * 1000.0)

static func scope_key(server: String, owner: String) -> String:
	return server.strip_edges().trim_suffix("/") + "|" + owner

func _scope(server: String, owner: String, create: bool = false) -> Dictionary:
	if owner.is_empty() or server.strip_edges().is_empty(): return {}
	var key := scope_key(server, owner)
	if not _scopes.has(key):
		if not create: return {}
		_scopes[key] = {"enabled": false, "part": {}, "offset": 0, "noted_at": 0, "stale": false, "empty": false, "unkept": false}
	return _scopes[key]

# --- Checks ----------------------------------------------------------------

static func _count(value: Variant, top: int) -> bool:
	return Typed.whole_number(value) and float(value) >= 0.0 and float(value) <= float(top)

## An `energy` part as kept ({energy, max, full_at, step_ms, now, refill_fruits}), or {} when it is not the contract's.
static func checked(value: Variant) -> Dictionary:
	if not value is Dictionary or not Typed.equal(value.get("schema_version"), 1): return {}
	if not _count(value.get("max"), MAX_TOP) or int(value.max) < 1 or not _count(value.get("energy"), int(value.max)): return {}
	if not _count(value.get("step_ms"), MAX_STEP_MS) or int(value.step_ms) < 1: return {}
	if not _count(value.get("full_at"), MAX_TIME) or not _count(value.get("now"), MAX_TIME) or not _count(value.get("refill_fruits"), MAX_PRICE): return {}
	return {"energy": Typed.as_int(value.energy), "max": Typed.as_int(value.max), "full_at": Typed.as_int(value.full_at), "step_ms": Typed.as_int(value.step_ms),
		"now": Typed.as_int(value.now), "refill_fruits": Typed.as_int(value.refill_fruits)}

# --- Switch ----------------------------------------------------------------

## The server's answer (services/relay_online_session.gd duels_energy_supported).
func set_enabled(server: String, owner: String, on: bool) -> void:
	var scope := _scope(server, owner, on)
	if scope.is_empty() or bool(scope.enabled) == on: return
	scope.enabled = on
	if not on:
		scope.part = {}
		scope.stale = false
		scope.empty = false
	changed.emit(server, owner)

## Whether the server said duel energy is on for this player: every energy surface hides otherwise.
func enabled(server: String, owner: String) -> bool:
	return bool(_scope(server, owner).get("enabled", false))

## Whether the wallet should be read for the meter: energy is on and nothing is
## kept, or what is kept is stale. A read that brought no part asks no more this launch.
func needs_read(server: String, owner: String) -> bool:
	var scope := _scope(server, owner)
	if not bool(scope.get("enabled", false)) or bool(scope.unkept): return false
	return (scope.part as Dictionary).is_empty() or bool(scope.stale)

## Duels opened: a meter older than FRESH_MS (or none) is read again. Whether a read is wanted now.
func ask_fresh(server: String, owner: String) -> bool:
	var scope := _scope(server, owner)
	if not bool(scope.get("enabled", false)) or bool(scope.unkept): return false
	if not (scope.part as Dictionary).is_empty() and now_ms() - int(scope.noted_at) >= FRESH_MS: scope.stale = true
	return needs_read(server, owner)

# --- Parts (services/wallet_reply.gd only) ----------------------------------

## A wallet answer: keeps its `energy` part when it has one.
func note_view(server: String, owner: String, data: Variant) -> bool:
	if not data is Dictionary: return false
	var noted := _note(server, owner, data.get("energy"))
	var scope := _scope(server, owner)
	# An answered read with no part this build can keep: no more reads for it this launch.
	if not noted and not scope.is_empty() and bool(scope.enabled) and checked(data.get("energy")).is_empty():
		scope.unkept = true
		scope.stale = false
	return noted

## A spend receipt (the refill's): its `energy` part.
func note_spend(server: String, owner: String, receipt: Variant) -> bool:
	return _note(server, owner, receipt.get("energy")) if receipt is Dictionary else false

## A duel start or join reply: the requesting player's meter after the spend.
func note_duel(server: String, owner: String, data: Variant) -> bool:
	return _note(server, owner, data.get("energy")) if data is Dictionary else false

func _note(server: String, owner: String, value: Variant) -> bool:
	var kept := checked(value)
	var scope := _scope(server, owner, not kept.is_empty())
	if kept.is_empty() or scope.is_empty(): return false
	var held: Dictionary = scope.part
	# An older answer than the kept one (a read sent before a start) changes nothing. Two from the
	# same server moment (a read and a spend in one millisecond): the later full_at, the spend, stands.
	if not held.is_empty() and (int(held.now) > int(kept.now) or (int(held.now) == int(kept.now) and int(held.full_at) > int(kept.full_at))): return false
	var phone := now_ms()
	scope.part = kept
	scope.offset = int(kept.now) - phone
	scope.noted_at = phone
	scope.stale = false
	scope.empty = false
	scope.unkept = false
	changed.emit(server, owner)
	return true

## The server refused a start or join as energy_empty: the meter reads 0, with
## no time for the next one, until the next part; the next flush reads it.
func note_empty(server: String, owner: String) -> void:
	var scope := _scope(server, owner)
	if scope.is_empty() or not bool(scope.enabled): return
	scope.empty = true
	scope.stale = true
	scope.unkept = false
	changed.emit(server, owner)

# --- Reads -----------------------------------------------------------------

## The meter now: {energy, max, next_ms, refill_fruits}, or {} while energy is
## off or nothing is kept. `next_ms`: until the next one comes, 0 when full,
## -1 while unknown (a refusal said empty and the read is still out).
func meter(server: String, owner: String) -> Dictionary:
	var scope := _scope(server, owner)
	if scope.is_empty() or not bool(scope.enabled) or (scope.part as Dictionary).is_empty(): return {}
	var part: Dictionary = scope.part
	var top := int(part.max)
	if bool(scope.empty): return {"energy": 0, "max": top, "next_ms": -1, "refill_fruits": int(part.refill_fruits)}
	var at := now_ms() + int(scope.offset)
	return meter_at(part, at)

## The meter of a kept `part` at server time `at` (pure: the tests' arithmetic).
static func meter_at(part: Dictionary, at: int) -> Dictionary:
	var top := int(part.max)
	var step := int(part.step_ms)
	var left := maxi(0, int(part.full_at) - at)
	var energy := clampi(top - ceili(float(left) / float(step)), 0, top)
	# The server's own count is a floor until the next part: a clock turned back never lowers it.
	if energy < int(part.energy):
		energy = int(part.energy)
		left = mini(left, (top - energy) * step)
	var next := 0 if energy >= top else mini((left - 1) % step + 1, step)
	return {"energy": energy, "max": top, "next_ms": next, "refill_fruits": int(part.refill_fruits)}

## Whole minutes until the next one, as the "Next in" line says it (never 0 while one is coming).
static func minutes(next_ms: int) -> int:
	return maxi(1, ceili(float(next_ms) / 60000.0))

## Milliseconds until what the meter shows changes (the count or the minute), or -1 for never (full, or unknown).
static func next_change_ms(next_ms: int) -> int:
	if next_ms <= 0: return -1
	return (next_ms - 1) % 60000 + 1

## Whether a refill is offered now: the meter is known, below its max, and has a price.
func refill_offered(server: String, owner: String) -> bool:
	var now := meter(server, owner)
	return not now.is_empty() and int(now.energy) < int(now.max) and int(now.refill_fruits) > 0

## Whether the kept meter says nothing is left: a spend tap opens the out-of-energy card without a
## request. Never while the meter is unknown after a refusal (no minutes yet): the server decides
## then, so a read that failed never stops every start on this phone.
func empty_now(server: String, owner: String) -> bool:
	var now := meter(server, owner)
	return not now.is_empty() and int(now.energy) <= 0 and int(now.next_ms) >= 0

## The Full Journey perk for its card: {full_journey, plain} (see FULL_JOURNEY_MAX).
static func perk() -> Dictionary:
	return {"full_journey": FULL_JOURNEY_MAX, "plain": PLAIN_MAX}
