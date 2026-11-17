extends RefCounted
## Chapter unlocks: one chain, in the Chapters page order, that every way to
## play a chapter asks: solo, hosting or joining a room with a friend, and
## duels. Nothing here is saved: progress is worked out from what the player
## already has, so a rebuilt keepsake ledger or a new phone gives the same answer.
##
## - The chain: every offered chapter with its own solo screen, in the order
##   the pickers show them (Registry.picker_rank): free chapters first, then
##   the Full Journey with the Sleeping Lighthouse leading.
## - First Steps is always open. A chapter opens once the chapter before it
##   is cleared. A clear is what earns the chapter's keepsake on Home, read
##   through the same view (services/home_keepsake_states.gd "base"): every
##   stage solo or every stage with a friend, or either Hard mark. A finished
##   room the keepsake ledger has not taken yet, and a duel's clear, count too
##   (progress() `finished_elsewhere`). A clear further along opens every
##   chapter before it, so the rule is one comparison against the furthest
##   cleared chapter (the frontier).
## - A chapter the player has already been in stays open: its keepsake started
##   (a stage mark), its journal on this phone, or a room for it (touched()).
##   Being in one does not open the next.
## - reached() is the chain alone. Play Solo and Host a room ask it and keep
##   their own Full Journey lock, store and tester code routing. A join asks
##   it too: the host's Full Journey covers the guest, as it always has.
## - open() adds Full Journey: what a duel, which has no host to cover it, asks.
## - A chapter with a Fruit price (descriptor "unlock": {"fruits": n}) is
##   open to a free player once they paid it (the server's record, kept by
##   services/fruit_wallet.gd opened_levels) and always with Full Journey
##   (fruit_locked). While the server does not sell levels (`fruit_levels.on`
##   false) it stays a Full Journey chapter: its card says so and nothing is
##   offered. Play Solo and Host a room offer the spend (fruit_offered);
##   a join is covered by the host, as Full Journey is.
## - Keys outside the chain and replays are never gated.
## - While the keepsake ledger is held (unreadable) or still being rebuilt from
##   the journals, its marks may be missing: the caller asks unsettled(), so
##   nothing is locked and a join carries no header, as an older build's.
##
## Callers build progress() once per draw and ask it per card; nothing here
## reads a file except touched(), which checks a few journal paths.
const Registry = preload("res://services/chapter_registry.gd")
const Index = preload("res://content/chapters/index.gd")
const Catalog = preload("res://services/home_keepsake_catalog.gd")
const KeepsakeStates = preload("res://services/home_keepsake_states.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const PollenMoney = preload("res://services/pollen_money.gd")
## The request header a join carries: the level ids open to the joiner. The
## room refuses a guest whose list leaves out its chapter (backend v2 room
## join, chapter_not_open). A server without the check ignores it.
const JOIN_HEADER := "X-AfterYou-Open-Chapters"
const JOIN_REFUSAL := "chapter_not_open"

## Worked out on first ask, then only read.
static var _chain: Array[String] = []
static var _premium: Dictionary = {}
## Chain key -> every key whose journals count for it.
static var _sources: Dictionary = {}
## Level id (a key before "@", how keepsakes join a chapter) -> chain key.
static var _by_level: Dictionary = {}
## {level id: Fruits} in place of the descriptors' prices; tests set their own
## (no registered chapter has a price yet).
static var prices_override: Dictionary = {}

## The chain in order. A copy.
static func chain() -> Array[String]:
	_build()
	return _chain.duplicate()

## The chain key `key` counts for: the offered version of its chapter, joined
## by level id as keepsakes join them, so every version (older, superseded or
## not yet released) answers as the offered one; "" when outside the chain.
static func chain_key(key: String) -> String:
	_build()
	return str(_by_level.get(key.get_slice("@", 0), ""))

## What the gate answers from, built once per draw. `earned` and `hard` are
## the marks Home's keepsakes read (HomeKeepsakes.earned_descriptors() and
## HardMode.marks()); `touched_keys` is touched(...) (chapters the player has
## already been in); `full_journey` whether the player has the Full Journey;
## `finished_elsewhere` chapter keys cleared where the keepsake marks do not
## show it yet: a finished room whose places this phone has not taken (a
## partner's last turn), and a duel's clear.
## `fruit_levels`: {"on": the server sells levels for Fruits, "open": the level
## ids this player paid for} (services/fruit_wallet.gd).
static func progress(earned: Array, hard: Dictionary = {}, touched_keys: Dictionary = {}, full_journey: bool = false, finished_elsewhere: Array = [], fruit_levels: Dictionary = {}) -> Dictionary:
	_build()
	var frontier := -1
	var opened := {}
	var states: Dictionary = KeepsakeStates.states(KeepsakeStates.entries(false), earned, hard, true)
	for item: Dictionary in states.items:
		var counted := str(_by_level.get(item.id, ""))
		if counted.is_empty(): continue
		if item.base: frontier = maxi(frontier, _chain.find(counted))
		if item.base or item.look == "started": opened[counted] = true
	for key: Variant in finished_elsewhere:
		frontier = maxi(frontier, _chain.find(chain_key(str(key))))
	for key: Variant in touched_keys:
		var counted := chain_key(str(key))
		if not counted.is_empty(): opened[counted] = true
	return {"frontier": frontier, "touched": opened, "full_journey": full_journey, "fruit_levels": fruit_levels}

## Progress while the keepsake marks cannot be trusted yet: every chapter
## reached, Full Journey as given, and no join header.
static func unsettled(full_journey: bool = false, fruit_levels: Dictionary = {}) -> Dictionary:
	_build()
	return {"frontier": _chain.size(), "touched": {}, "full_journey": full_journey, "unsettled": true, "fruit_levels": fruit_levels}

## Whether the chain has reached the chapter for this player. Full Journey is
## not asked here.
static func reached(key: String, state: Dictionary) -> bool:
	var counted := chain_key(key)
	if counted.is_empty(): return true
	return _chain.find(counted) <= int(state.get("frontier", -1)) + 1 or state.get("touched", {}).has(counted)

## Whether the player can play the chapter now, in any mode: solo, with a
## friend or in a duel.
static func open(key: String, state: Dictionary) -> bool:
	return reached(key, state) and (not _premium.get(chain_key(key), false) or bool(state.get("full_journey", false))) and not fruit_locked(key, state)

## The Fruits a free player pays once to open the chapter (its offered
## version's descriptor "unlock"), or 0 when it has no price.
static func price(key: String) -> int:
	if prices_override.has(key.get_slice("@", 0)): return int(prices_override[key.get_slice("@", 0)])
	var counted := chain_key(key)
	var unlock: Variant = Index.data(counted if not counted.is_empty() else key).get("unlock", {})
	return int(unlock.get("fruits", 0)) if unlock is Dictionary else 0

## Whether the chapter's Fruit price still stands between the player and it:
## it has one, they have no Full Journey and have not paid it.
static func fruit_locked(key: String, state: Dictionary) -> bool:
	if price(key) <= 0 or bool(state.get("full_journey", false)): return false
	var paid: Variant = (state.get("fruit_levels", {}) as Dictionary).get("open", [])
	return not (paid is Array and key.get_slice("@", 0) in paid)

## Whether a tap on the chapter offers its Fruit price: it is reached, locked
## by its price, and the server sells levels now.
static func fruit_offered(key: String, state: Dictionary) -> bool:
	return reached(key, state) and fruit_locked(key, state) and bool((state.get("fruit_levels", {}) as Dictionary).get("on", false))

## Why the chapter is not open, as a sentence; "" when it is. `note` gives the
## short form a chapter card shows.
static func reason(key: String, state: Dictionary, note: bool = false) -> String:
	if not reached(key, state):
		return (PlayerCopy.CHAPTER_LOCKED_NOTE if note else PlayerCopy.CHAPTER_LOCKED) % title(opens_after(key))
	if open(key, state): return ""
	if fruit_offered(key, state): return PlayerCopy.LEVEL_UNLOCK_NOTE % PollenMoney.grouped(price(key))
	return PlayerCopy.CHAPTER_LOCKED_FULL_JOURNEY

## Locks a picker entry (ChapterPicker.entry) the chain has not reached: its
## card shows the lock and the short reason, and "unlock_reason" carries the
## sentence for a tap. True when it locked it.
## A chapter reached but locked by its Fruit price is locked the same way, its
## note the price while the server sells levels.
static func lock_entry(item: Dictionary, state: Dictionary) -> bool:
	var key := str(item.get("key", ""))
	if reached(key, state) and not fruit_locked(key, state): return false
	item.locked = true
	item.note = reason(key, state, true)
	item.unlock_reason = reason(key, state)
	return true

## The chapter whose finish opens `key`: the one before it in the chain, or
## "" for First Steps and keys outside the chain.
static func opens_after(key: String) -> String:
	_build()
	var index := _chain.find(chain_key(key))
	return _chain[index - 1] if index > 0 else ""

static func title(key: String) -> String:
	return str(Registry.descriptor(key).get("title", key))

## Chapters the player has already been in, outside the keepsake marks
## (progress() reads those), keyed by chain key: a room for it
## (`room_chapters`, chapter keys) or, with `journals`, its journal on this phone.
static func touched(room_chapters: Array = [], journals: bool = true) -> Dictionary:
	_build()
	var result := {}
	for key: Variant in room_chapters: result[chain_key(str(key))] = true
	for key: String in (_chain if journals else []):
		if result.has(key): continue
		for source: String in _sources[key]:
			var path := _journal(source)
			if not path.is_empty() and FileAccess.file_exists(path):
				result[key] = true
				break
	result.erase("")
	return result

## A join's header line: every registered chapter's level id the player has
## reached, so the room can refuse a chapter past them. "" while unsettled:
## the join then carries none and is never refused for a chapter.
static func join_header(state: Dictionary) -> String:
	if state.get("unsettled", false): return ""
	var levels: Array[String] = []
	for key: String in Index.keys():
		var level := key.get_slice("@", 0)
		if not level in levels and reached(key, state): levels.append(level)
	return JOIN_HEADER + ": " + ",".join(levels)

## The line a refused join shows: the chapter the player can play next, which
## the friend can host for them.
static func join_refusal(state: Dictionary) -> String:
	_build()
	var next := _chain[clampi(int(state.get("frontier", -1)) + 1, 0, _chain.size() - 1)]
	return PlayerCopy.CHAPTER_JOIN_NOT_REACHED % title(next)

static func _journal(key: String) -> String:
	if key in Index.keys(): return str(Index.data(key).local_path)
	return Catalog.local_path(key)

static func _build() -> void:
	if not _chain.is_empty(): return
	var offered: Array[String] = []
	var premium := {}
	for key: String in Registry.offered_keys():
		if Registry.solo_scene(key).is_empty(): continue
		offered.append(key)
		premium[key] = bool(Registry.descriptor(key).get("premium", false))
	var ordered: Array[String] = []
	ordered.assign(Registry.picker_order(offered, func(key: String) -> int: return Registry.picker_rank(key, premium[key])))
	var sources := {}
	var by_level := {}
	for key: String in ordered:
		sources[key] = []
		by_level[key.get_slice("@", 0)] = key
	for key: String in Index.keys() + Catalog.OTHER_CHAPTERS.keys():
		var counted := str(by_level.get(key.get_slice("@", 0), ""))
		if not counted.is_empty() and not key in sources[counted]: sources[counted].append(key)
	_premium = premium
	_sources = sources
	_by_level = by_level
	_chain = ordered
