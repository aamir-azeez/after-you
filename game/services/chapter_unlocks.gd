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
##   is finished in any mode (FINISH_MODES, or a finished room for it). A
##   finish further along opens
##   every chapter before it too, so the rule is one comparison against the
##   furthest finished chapter (the frontier).
## - A chapter the player has already been in stays open: a place earned there,
##   its journal on this phone, or a room for it (touched()). Being in one does
##   not open the next.
## - reached() is the chain alone. Play Solo and Host a room ask it and keep
##   their own Full Journey lock, store and tester code routing. A join asks
##   it too: the host's Full Journey covers the guest, as it always has.
## - open() adds Full Journey: what a duel, which has no host to cover it, asks.
## - Earlier islands, keys outside the chain and replays are never gated.
##
## Callers build progress() once per draw and ask it per card; nothing here
## reads a file except touched(), which checks a few journal paths.
const Registry = preload("res://services/chapter_registry.gd")
const Index = preload("res://content/chapters/index.gd")
const Catalog = preload("res://services/home_keepsake_catalog.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
## The completion marks whose finish advances the chain: ChapterCompletion's
## "solo" and "friend", and a duel's own mark once duels keep one.
const FINISH_MODES := ["solo", "friend", "duel"]
## The request header a join carries: the level ids open to the joiner. The
## room refuses a guest whose list leaves out its chapter (backend v2 room
## join, chapter_not_open). A server without the check ignores it.
const JOIN_HEADER := "X-AfterYou-Open-Chapters"
const JOIN_REFUSAL := "chapter_not_open"

## Worked out on first ask, then only read.
static var _chain: Array[String] = []
static var _premium: Dictionary = {}
## Any registered or older key -> the chain key it counts for.
static var _counts_for: Dictionary = {}
## Chain key -> every key whose marks and journals count for it.
static var _sources: Dictionary = {}

## The chain in order. A copy.
static func chain() -> Array[String]:
	_build()
	return _chain.duplicate()

## The chain key `key` counts for: itself, the newer version offered in its
## place, or the version whose places it earns; "" when outside the chain.
static func chain_key(key: String) -> String:
	_build()
	return str(_counts_for.get(key, ""))

## What the gate answers from. `marks` is ChapterCompletion.chapters(...),
## `touched` is touched(...) (chapters the player has already been in),
## `full_journey` whether the player has the Full Journey and `finished_rooms`
## the chapter keys of finished rooms the player was in, which count before
## this phone has taken the room's places (a partner's last turn).
static func progress(marks: Dictionary, touched_keys: Dictionary = {}, full_journey: bool = false, finished_rooms: Array = []) -> Dictionary:
	_build()
	var frontier := -1
	for index in _chain.size():
		if finished(marks, _chain[index]): frontier = index
	for key: Variant in finished_rooms:
		frontier = maxi(frontier, _chain.find(chain_key(str(key))))
	var opened := {}
	for key: Variant in touched_keys:
		var counted := chain_key(str(key))
		if not counted.is_empty(): opened[counted] = true
	return {"frontier": frontier, "touched": opened, "full_journey": full_journey}

## Whether the chapter is finished in any mode, under any key that counts for it.
static func finished(marks: Dictionary, key: String) -> bool:
	_build()
	for source: String in _sources.get(chain_key(key), [key]):
		var mark: Variant = marks.get(source)
		if not mark is Dictionary: continue
		for mode: String in FINISH_MODES:
			if mark.get(mode) is bool and mark[mode]: return true
	return false

## Whether the chain has reached the chapter for this player. Full Journey is
## not asked here.
static func reached(key: String, state: Dictionary) -> bool:
	var counted := chain_key(key)
	if counted.is_empty(): return true
	return _chain.find(counted) <= int(state.get("frontier", -1)) + 1 or state.get("touched", {}).has(counted)

## Whether the player can play the chapter now, in any mode: solo, with a
## friend or in a duel.
static func open(key: String, state: Dictionary) -> bool:
	return reached(key, state) and (not _premium.get(chain_key(key), false) or bool(state.get("full_journey", false)))

## Why the chapter is not open, as a sentence; "" when it is. `note` gives the
## short form a chapter card shows.
static func reason(key: String, state: Dictionary, note: bool = false) -> String:
	if not reached(key, state):
		return (PlayerCopy.CHAPTER_LOCKED_NOTE if note else PlayerCopy.CHAPTER_LOCKED) % title(opens_after(key))
	return "" if open(key, state) else PlayerCopy.CHAPTER_LOCKED_FULL_JOURNEY

## Locks a picker entry (ChapterPicker.entry) the chain has not reached: its
## card shows the lock and the short reason, and "unlock_reason" carries the
## sentence for a tap. True when it locked it.
static func lock_entry(item: Dictionary, state: Dictionary) -> bool:
	var key := str(item.get("key", ""))
	if reached(key, state): return false
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

## Chapters the player has already been in, keyed by chain key: a place earned
## there in any mode (`earned`, HomeKeepsakes.earned_descriptors()), a room for
## it (`room_chapters`, chapter keys) or its journal on this phone.
static func touched(earned: Array, room_chapters: Array = []) -> Dictionary:
	_build()
	var result := {}
	for item: Variant in earned:
		if item is Dictionary: result[chain_key(str(item.get("chapter_key", "")))] = true
	for key: Variant in room_chapters: result[chain_key(str(key))] = true
	for key: String in _chain:
		if result.has(key): continue
		for source: String in _sources[key]:
			var path := _journal(source)
			if not path.is_empty() and FileAccess.file_exists(path):
				result[key] = true
				break
	result.erase("")
	return result

## A join's header line: every registered chapter's level id the player has
## reached, so the room can refuse a chapter past them.
static func join_header(state: Dictionary) -> String:
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
	var counts := {}
	var sources := {}
	for key: String in ordered:
		counts[key] = key
		sources[key] = [key]
	for key: String in Index.keys():
		var counted := Registry.offered_key(key)
		if not sources.has(counted): continue
		for source: String in [key, str(Index.data(key).version_of)]:
			if source.is_empty() or counts.has(source): continue
			counts[source] = counted
			sources[counted].append(source)
	_premium = premium
	_counts_for = counts
	_sources = sources
	_chain = ordered
