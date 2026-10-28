extends SceneTree
## The chapter unlock gate (services/chapter_unlocks.gd): one chain in the
## Chapters page order, advanced by a clear in any mode, with existing players
## keeping every chapter they have been in, and the join line a room checks.
## A clear is what earns the chapter's keepsake on Home
## (services/home_keepsake_states.gd), read from the same marks. Pure: marks,
## played chapters and Full Journey access go in as data.
const Unlocks = preload("res://services/chapter_unlocks.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Picker = preload("res://presentation/chapter_picker.gd")
const Catalog = preload("res://services/home_keepsake_catalog.gd")
const KeepsakeStates = preload("res://services/home_keepsake_states.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const Fixture = preload("res://tests/unlock_fixture.gd")

var checks := 0
var failures := 0
var chain: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> bool:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
	return value

func _run() -> void:
	chain = Unlocks.chain()
	_order()
	_new_player()
	_any_mode()
	_same_clear_as_keepsakes()
	_existing_players()
	_full_journey()
	_versions()
	_journals()
	_joining()
	print("CHAPTER UNLOCKS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## Reached keys in chain order, for messages.
func _reached(state: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for key: String in chain:
		if Unlocks.reached(key, state): result.append(key)
	return result

## Progress from keepsake marks alone.
static func _from(earned: Array, hard: Dictionary = {}, full_journey: bool = true) -> Dictionary:
	return Unlocks.progress(earned, hard, {}, full_journey)

## Every chain chapter in the given order of the Chapters page, each with a
## keepsake on Home and ledger places, so it can be cleared and the chain goes
## on. A chapter scaffolded by scripts/new_chapter.py meets the same checks.
func _order() -> void:
	var entries: Array[Dictionary] = []
	for key: String in Registry.offered_keys():
		if not Registry.solo_scene(key).is_empty(): entries.append(Picker.entry(key))
	var shown: Array[String] = []
	for item: Dictionary in Picker.shown_order(entries): shown.append(str(item.key))
	_check(chain == shown, "The chain is the Chapters page order: %s vs %s" % [chain, shown])
	_check(chain.size() >= 8 and chain[0] == Registry.FIRST_STEPS, "First Steps leads the chain")
	var keepsakes := {}
	for entry: Dictionary in KeepsakeStates.entries(false): keepsakes[entry.id] = entry
	var first_paid := -1
	for index in chain.size():
		var paid: bool = Registry.descriptor(chain[index]).premium
		_check(paid or first_paid < 0, "No free chapter follows a Full Journey one: %s" % chain[index])
		if paid and first_paid < 0: first_paid = index
		var level := chain[index].get_slice("@", 0)
		_check(keepsakes.has(level) and not keepsakes[level].places.is_empty(), "%s has a keepsake with places, so it can be cleared and the chain goes on" % chain[index])
		var earned := Fixture.cleared(chain[index])
		_check(Unlocks.reached(chain[index + 1] if index + 1 < chain.size() else chain[index], _from(earned)), "Clearing %s opens the chapter after it" % chain[index])
	_check(first_paid > 0 and chain[first_paid] == Registry.LIGHTHOUSE_V2, "The Sleeping Lighthouse leads the Full Journey part of the chain")
	var fresh := _from([])
	_check(Unlocks.chain_key("") == "" and Unlocks.reached("", fresh) and Unlocks.reached("no-such@1", fresh), "Keys outside the chain, such as the earlier islands, are never gated")

## A new player has First Steps alone, and every other chapter says which
## chapter opens it.
func _new_player() -> void:
	var fresh := _from([])
	_check(_reached(fresh) == [Registry.FIRST_STEPS], "A new player has First Steps alone: %s" % [_reached(fresh)])
	_check(Unlocks.open(Registry.FIRST_STEPS, fresh) and Unlocks.reason(Registry.FIRST_STEPS, fresh).is_empty(), "First Steps is always open")
	_check(Unlocks.reason(chain[1], fresh) == PlayerCopy.CHAPTER_LOCKED % Unlocks.title(chain[0]), "The second chapter says to finish First Steps")
	_check(Unlocks.reason(chain[3], fresh, true) == PlayerCopy.CHAPTER_LOCKED_NOTE % Unlocks.title(chain[2]), "A locked card's note names the chapter just before it")
	var solo := _from(Fixture.cleared_through(chain[0]))
	_check(_reached(solo) == chain.slice(0, 2), "Clearing First Steps opens the next chapter and no further: %s" % [_reached(solo)])

## Solo, together and duel clears all move the chain; solo, together and duel
## play all ask the same gate.
func _any_mode() -> void:
	var together := _from(Fixture.cleared_through(chain[2], "friend"))
	_check(_reached(together) == chain.slice(0, 4), "A chain advanced only by clears with a friend: %s" % [_reached(together)])
	var duel := Unlocks.progress([], {}, {}, true, chain.slice(0, 2))
	_check(_reached(duel) == chain.slice(0, 3), "A duel clear advances the chain: %s" % [_reached(duel)])
	var mixed: Array = Fixture.cleared(chain[0], "solo") + Fixture.cleared(chain[1], "friend")
	_check(_reached(Unlocks.progress(mixed, {}, {}, true, [chain[2]])) == chain.slice(0, 4), "Clears in different modes chain on")
	var hard := _from([], {chain[3]: {"solo": true, "together": false}})
	_check(_reached(hard).has(chain[4]) and not Unlocks.reached(chain[5], hard), "A Hard mark is a clear, as it earns the keepsake")
	var mixed_stages: Array = []
	var places := Catalog.chapter_places(chain[0])
	for index in places.size(): mixed_stages.append({"id": places[index], "solo": index % 2 == 0, "friend": index % 2 == 1})
	_check(_reached(_from(mixed_stages)) == [chain[0]], "Stages split between solo and a friend are not a clear, as on the keepsake")

## The gate's clear is the keepsake's base, for every chapter and mark kind:
## there is no second idea of a finish.
func _same_clear_as_keepsakes() -> void:
	var entries := KeepsakeStates.entries(false)
	for key: String in chain:
		var level := key.get_slice("@", 0)
		var index := chain.find(key)
		var after := chain[index + 1] if index + 1 < chain.size() else ""
		for marks: Array in [[Fixture.cleared(key, "solo"), {}], [Fixture.cleared(key, "friend"), {}], [[], {key: {"solo": true, "together": false}}], [Fixture.cleared(key).slice(0, 1), {}]]:
			var states: Dictionary = KeepsakeStates.states(entries, marks[0], marks[1], true)
			var base := false
			for item: Dictionary in states.items:
				if item.id == level: base = item.base
			if after.is_empty(): continue
			_check(Unlocks.reached(after, _from(marks[0], marks[1])) == base, "%s opens the next chapter exactly when its keepsake shows (%s)" % [key, marks])

## Existing players never lose a chapter: a clear further along opens every
## chapter before it, and a chapter already played or in a room stays open
## without opening the one after it.
func _existing_players() -> void:
	var later := _from(Fixture.cleared(chain[5]))
	_check(_reached(later) == chain.slice(0, 7), "A later clear opens every earlier chapter and the next one: %s" % [_reached(later)])
	var played := Unlocks.progress([], {}, {chain[4]: true}, true)
	_check(Unlocks.reached(chain[4], played) and not Unlocks.reached(chain[5], played) and not Unlocks.reached(chain[3], played), "A chapter already played stays open and opens nothing else")
	var partly := Unlocks.progress(Fixture.cleared(chain[3]).slice(0, 1), {}, Unlocks.touched([chain[6]]), true)
	_check(Unlocks.reached(chain[3], partly) and not Unlocks.reached(chain[4], partly), "A started keepsake keeps its chapter open")
	_check(Unlocks.reached(chain[6], partly) and not Unlocks.reached(chain[7], partly), "A room for a chapter keeps it open")
	_check(_reached(Fixture.all_played()) == chain, "A player who has been in every chapter keeps them all")
	_check(Unlocks.opens_after(chain[0]).is_empty() and Unlocks.opens_after(chain[3]) == chain[2] and Unlocks.opens_after("no-such@1").is_empty(), "Each chapter is opened by the one before it")
	var item := {"key": chain[3], "locked": false}
	var fresh := _from([])
	_check(Unlocks.lock_entry(item, fresh) and item.locked and item.note == Unlocks.reason(chain[3], fresh, true) and item.unlock_reason == Unlocks.reason(chain[3], fresh), "A card the chain has not reached is locked with its reason")
	var first := {"key": chain[0], "locked": false}
	_check(not Unlocks.lock_entry(first, fresh) and not first.locked and not first.has("note"), "A reached card is left as it was")

## A Full Journey chapter needs the chain and Full Journey; screens that keep
## their own Full Journey lock ask reached() and get the chain's reason first.
func _full_journey() -> void:
	var paid := Registry.LIGHTHOUSE_V2
	var index := chain.find(paid)
	var earned := Fixture.cleared_through(chain[index - 1])
	var without := _from(earned, {}, false)
	_check(Unlocks.reached(paid, without) and not Unlocks.open(paid, without), "A reached Full Journey chapter is not open without Full Journey")
	_check(Unlocks.reason(paid, without) == PlayerCopy.CHAPTER_LOCKED_FULL_JOURNEY, "Its reason is the Full Journey")
	_check(Unlocks.open(paid, _from(earned)), "With Full Journey it is open")
	var early := _from([])
	_check(not Unlocks.open(paid, early) and Unlocks.reason(paid, early) == PlayerCopy.CHAPTER_LOCKED % Unlocks.title(chain[index - 1]), "Full Journey alone does not open a chapter the chain has not reached")

## Every version of a chapter counts for the one offered: Hard marks and rooms
## under an older key, a room hosted at an older version, and the Lighthouse's
## places kept under its first version.
func _versions() -> void:
	for key: String in Registry.keys():
		var offered := Registry.offered_key(key)
		if offered == key or not offered in chain: continue
		var index := chain.find(offered)
		var state := _from(Fixture.cleared_through(chain[index - 1]))
		_check(Unlocks.reached(key, state) == Unlocks.reached(offered, state) and Unlocks.reached(key, state), "%s answers as %s" % [key, offered])
		var next := chain[index + 1] if index + 1 < chain.size() else offered
		_check(Unlocks.reached(next, _from([], {key: {"solo": true, "together": false}})), "A Hard mark under %s counts for %s" % [key, offered])
		_check(Unlocks.reached(offered, Unlocks.progress([], {}, Unlocks.touched([key]), true)), "A room at %s keeps %s open" % [key, offered])
	var lighthouse := chain.find(Registry.LIGHTHOUSE_V2)
	var places: Array = []
	for id: String in Catalog.chapter_places(Catalog.LIGHTHOUSE): places.append({"id": id, "solo": true, "friend": false})
	_check(not places.is_empty() and Unlocks.reached(chain[lighthouse + 1], _from(places)), "A Lighthouse clear kept under its first version counts")
	_check(Unlocks.reached(Registry.LIGHTHOUSE_V2, _from(places.slice(0, 1))), "A Lighthouse place kept under its first version keeps it open")

## A chapter's journal on this phone keeps it open, under any of its versions.
func _journals() -> void:
	var key := chain[4]
	var path := str(Registry.descriptor(key).local_path)
	if not _check(not FileAccess.file_exists(path), "The isolated run has no journal for %s yet" % key): return
	_check(not Unlocks.touched().has(key), "No journal, no played chapter")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{}")
	file.close()
	_check(Unlocks.touched().has(key), "A journal on this phone keeps %s open" % key)
	DirAccess.remove_absolute(path)

## A join carries the level ids the joiner has reached; a room refuses one
## that leaves out its chapter. A new player and a veteran both start at First
## Steps and move along together.
func _joining() -> void:
	var newcomer := _from([], {}, false)
	var veteran := _from(Fixture.cleared_through(chain[-1]))
	var line := Unlocks.join_header(newcomer)
	_check(line.begins_with(Unlocks.JOIN_HEADER + ": "), "The join line is the header the room reads")
	var levels := _levels(newcomer)
	_check(levels == [Registry.FIRST_STEPS.get_slice("@", 0)], "A new player's join names First Steps alone: %s" % line)
	_check(Unlocks.open(Registry.FIRST_STEPS, newcomer) and Unlocks.open(Registry.FIRST_STEPS, veteran), "A new player and a veteran can both play First Steps together")
	_check(Unlocks.open(chain[2], veteran) and not Unlocks.open(chain[2], newcomer), "Only the veteran has the third chapter")
	_check(not chain[2].get_slice("@", 0) in levels and chain[2].get_slice("@", 0) in _levels(veteran), "So a room for it refuses the new player and takes the veteran")
	_check(Unlocks.join_refusal(newcomer) == PlayerCopy.CHAPTER_JOIN_NOT_REACHED % Unlocks.title(Registry.FIRST_STEPS), "The refused new player is told to ask for First Steps")
	var after_first := _from(Fixture.cleared(chain[0], "friend"), {}, false)
	_check(Unlocks.join_refusal(after_first) == PlayerCopy.CHAPTER_JOIN_NOT_REACHED % Unlocks.title(chain[1]), "After First Steps together, the next chapter is the one to ask for")
	_check(chain[1].get_slice("@", 0) in _levels(after_first), "And a room for it now takes the new player")
	var finished_room := Unlocks.progress([], {}, {}, false, [chain[0]])
	_check(Unlocks.reached(chain[1], finished_room) and not Unlocks.reached(chain[2], finished_room), "A finished room counts as a clear before its places reach this phone")
	var named := RegEx.create_from_string("^[a-z0-9-]{1,64}$")
	var all := _levels(veteran)
	_check(all.size() <= 64, "A join names at most the 64 levels the room reads")
	for key: String in Registry.keys():
		var level := key.get_slice("@", 0)
		_check(level in all, "A veteran's join names %s" % level)
		_check(named.search(level) != null, "Level id %s fits the room's header pattern, or every join would be refused" % level)

static func _levels(state: Dictionary) -> Array:
	return Array(Unlocks.join_header(state).get_slice(": ", 1).split(","))
