extends SceneTree
## The chapter unlock gate (services/chapter_unlocks.gd): one chain in the
## Chapters page order, advanced by a finish in any mode, with existing
## players keeping every chapter they have been in, and the join line a room
## checks. Pure: marks, played chapters and Full Journey access go in as data.
const Unlocks = preload("res://services/chapter_unlocks.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Picker = preload("res://presentation/chapter_picker.gd")
const Catalog = preload("res://services/home_keepsake_catalog.gd")
const Completion = preload("res://presentation/chapter_completion.gd")
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

## The chain is the Chapters page's order, from the registry: First Steps
## first, free chapters before the Full Journey, the Lighthouse leading it.
## Every chapter in it can be finished, or the chain would stop there.
func _order() -> void:
	var entries: Array[Dictionary] = []
	for key: String in Registry.offered_keys():
		if not Registry.solo_scene(key).is_empty(): entries.append(Picker.entry(key))
	var shown: Array[String] = []
	for item: Dictionary in Picker.shown_order(entries): shown.append(str(item.key))
	_check(chain == shown, "The chain is the Chapters page order: %s vs %s" % [chain, shown])
	_check(chain.size() >= 8 and chain[0] == Registry.FIRST_STEPS, "First Steps leads the chain")
	var first_paid := -1
	for index in chain.size():
		var paid: bool = Registry.descriptor(chain[index]).premium
		_check(paid or first_paid < 0, "No free chapter follows a Full Journey one: %s" % chain[index])
		if paid and first_paid < 0: first_paid = index
		_check(not Catalog.chapter_places(chain[index]).is_empty(), "%s has places, so it can be finished and the chain goes on" % chain[index])
	_check(first_paid > 0 and chain[first_paid] == Registry.LIGHTHOUSE_V2, "The Sleeping Lighthouse leads the Full Journey part of the chain")
	_check(Unlocks.chain_key("") == "" and Unlocks.reached("", Unlocks.progress({})) and Unlocks.reached("no-such@1", Unlocks.progress({})), "Keys outside the chain, such as the earlier islands, are never gated")

## A new player has First Steps alone, and every other chapter says which
## chapter opens it.
func _new_player() -> void:
	var fresh := Unlocks.progress({}, {}, true)
	_check(_reached(fresh) == [Registry.FIRST_STEPS], "A new player has First Steps alone: %s" % [_reached(fresh)])
	_check(Unlocks.open(Registry.FIRST_STEPS, fresh) and Unlocks.reason(Registry.FIRST_STEPS, fresh).is_empty(), "First Steps is always open")
	_check(Unlocks.reason(chain[1], fresh) == PlayerCopy.CHAPTER_LOCKED % Unlocks.title(chain[0]), "The second chapter says to finish First Steps")
	_check(Unlocks.reason(chain[3], fresh, true) == PlayerCopy.CHAPTER_LOCKED_NOTE % Unlocks.title(chain[2]), "A locked card's note names the chapter just before it")
	var solo := Unlocks.progress(Fixture.finished_through(chain[0]), {}, true)
	_check(_reached(solo) == chain.slice(0, 2), "Finishing First Steps opens the next chapter and no further: %s" % [_reached(solo)])

## Solo, together and duel finishes all move the chain; solo, together and
## duel play all ask the same open().
func _any_mode() -> void:
	var together := Unlocks.progress(Fixture.finished_through(chain[2], "friend"), {}, true)
	_check(_reached(together) == chain.slice(0, 4), "A chain advanced only by finishes with a friend: %s" % [_reached(together)])
	var duel := Unlocks.progress(Fixture.finished_through(chain[1], "duel"), {}, true)
	_check(_reached(duel) == chain.slice(0, 3), "A duel finish advances the chain: %s" % [_reached(duel)])
	var mixed := {chain[0]: {"solo": true}, chain[1]: {"friend": true}, chain[2]: {"duel": true}}
	_check(_reached(Unlocks.progress(mixed, {}, true)) == chain.slice(0, 4), "Finishes in different modes chain on")
	var unfinished := {chain[0]: {"solo": false, "friend": false}}
	_check(_reached(Unlocks.progress(unfinished, {}, true)) == [chain[0]], "A mark with nothing finished opens nothing")
	# The marks ChapterCompletion gives a player who earned every First Steps place with a friend.
	var earned: Array[Dictionary] = []
	for item: Dictionary in Catalog.all():
		if item.chapter_key == chain[0]: earned.append({"id": item.id, "solo": false, "friend": true})
	_check(Unlocks.reached(chain[1], Unlocks.progress(Completion.chapters(earned), {}, true)), "Every First Steps place earned with a friend opens the next chapter")

## Existing players never lose a chapter: a finish further along opens every
## chapter before it, and a chapter already played or in a room stays open
## without opening the one after it.
func _existing_players() -> void:
	var later := Unlocks.progress({chain[5]: {"solo": true}}, {}, true)
	_check(_reached(later) == chain.slice(0, 7), "A later finish opens every earlier chapter and the next one: %s" % [_reached(later)])
	var played := Unlocks.progress({}, {chain[4]: true}, true)
	_check(Unlocks.reached(chain[4], played) and not Unlocks.reached(chain[5], played) and not Unlocks.reached(chain[3], played), "A chapter already played stays open and opens nothing else")
	var earned: Array[Dictionary] = []
	for item: Dictionary in Catalog.all():
		if item.chapter_key == chain[3]:
			earned.append({"id": item.id, "chapter_key": item.chapter_key, "solo": true, "friend": false})
			break
	var partly := Unlocks.progress(Completion.chapters(earned), Unlocks.touched(earned, [chain[6]]), true)
	_check(Unlocks.reached(chain[3], partly), "One place earned in a chapter keeps it open")
	_check(Unlocks.reached(chain[6], partly) and not Unlocks.reached(chain[7], partly), "A room for a chapter keeps it open")
	var veteran := Fixture.all_played()
	_check(_reached(veteran) == chain, "A player who has been in every chapter keeps them all")

## A Full Journey chapter needs the chain and Full Journey; screens that keep
## their own Full Journey lock ask reached() and get the chain's reason first.
func _full_journey() -> void:
	var paid := Registry.LIGHTHOUSE_V2
	var index := chain.find(paid)
	var marks := Fixture.finished_through(chain[index - 1])
	var without := Unlocks.progress(marks, {}, false)
	_check(Unlocks.reached(paid, without) and not Unlocks.open(paid, without), "A reached Full Journey chapter is not open without Full Journey")
	_check(Unlocks.reason(paid, without) == PlayerCopy.CHAPTER_LOCKED_FULL_JOURNEY, "Its reason is the Full Journey")
	_check(Unlocks.open(paid, Unlocks.progress(marks, {}, true)), "With Full Journey it is open")
	var early := Unlocks.progress({}, {}, true)
	_check(not Unlocks.open(paid, early) and Unlocks.reason(paid, early) == PlayerCopy.CHAPTER_LOCKED % Unlocks.title(chain[index - 1]), "Full Journey alone does not open a chapter the chain has not reached")

## Every version of a chapter counts for the one offered: marks and rooms under
## an older key, and a room hosted at an older version, answer as the offered key.
func _versions() -> void:
	for key: String in Registry.keys():
		var offered := Registry.offered_key(key)
		if offered == key or not offered in chain: continue
		var index := chain.find(offered)
		var marks := Fixture.finished_through(chain[index - 1])
		var state := Unlocks.progress(marks, {}, true)
		_check(Unlocks.reached(key, state) == Unlocks.reached(offered, state) and Unlocks.reached(key, state), "%s answers as %s" % [key, offered])
		_check(Unlocks.reached(chain[index + 1] if index + 1 < chain.size() else offered, Unlocks.progress({key: {"solo": true}}, {}, true)), "A finish marked under %s counts for %s" % [key, offered])
		_check(Unlocks.reached(offered, Unlocks.progress({}, {key: true}, true)), "A room at %s keeps %s open" % [key, offered])
	var lighthouse := Unlocks.progress({Catalog.LIGHTHOUSE: {"solo": true}}, {}, true)
	_check(Unlocks.reached(chain[chain.find(Registry.LIGHTHOUSE_V2) + 1], lighthouse), "A Lighthouse finish kept under its first version counts")
	var places: Array[Dictionary] = [{"id": "x", "chapter_key": Catalog.LIGHTHOUSE, "solo": true}]
	_check(Unlocks.touched(places).has(Registry.LIGHTHOUSE_V2), "A Lighthouse place kept under its first version keeps it open")

## A chapter's journal on this phone keeps it open, under any of its versions.
func _journals() -> void:
	var key := chain[4]
	var path := str(Registry.descriptor(key).local_path)
	if not _check(not FileAccess.file_exists(path), "The isolated run has no journal for %s yet" % key): return
	_check(not Unlocks.touched([]).has(key), "No journal, no played chapter")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{}")
	file.close()
	_check(Unlocks.touched([]).has(key), "A journal on this phone keeps %s open" % key)
	DirAccess.remove_absolute(path)

## A join carries the level ids the joiner has reached; a room refuses one
## that leaves out its chapter. A new player and a veteran both start at First
## Steps and move along together.
func _joining() -> void:
	var newcomer := Unlocks.progress({}, {}, false)
	var veteran := Unlocks.progress(Fixture.finished_through(chain[-1]), {}, true)
	var line := Unlocks.join_header(newcomer)
	_check(line.begins_with(Unlocks.JOIN_HEADER + ": "), "The join line is the header the room reads")
	var levels := line.get_slice(": ", 1).split(",")
	_check(Array(levels) == [Registry.FIRST_STEPS.get_slice("@", 0)], "A new player's join names First Steps alone: %s" % line)
	_check(Unlocks.open(Registry.FIRST_STEPS, newcomer) and Unlocks.open(Registry.FIRST_STEPS, veteran), "A new player and a veteran can both play First Steps together")
	_check(Unlocks.open(chain[2], veteran) and not Unlocks.open(chain[2], newcomer), "Only the veteran has the third chapter")
	_check(not chain[2].get_slice("@", 0) in levels and chain[2].get_slice("@", 0) in Unlocks.join_header(veteran), "So a room for it refuses the new player and takes the veteran")
	_check(Unlocks.join_refusal(newcomer) == PlayerCopy.CHAPTER_JOIN_NOT_REACHED % Unlocks.title(Registry.FIRST_STEPS), "The refused new player is told to ask for First Steps")
	var after_first := Unlocks.progress(Fixture.finished_through(chain[0], "friend"), {}, false)
	_check(Unlocks.join_refusal(after_first) == PlayerCopy.CHAPTER_JOIN_NOT_REACHED % Unlocks.title(chain[1]), "After First Steps together, the next chapter is the one to ask for")
	_check(chain[1].get_slice("@", 0) in Unlocks.join_header(after_first), "And a room for it now takes the new player")
	for key: String in Registry.keys():
		var level := key.get_slice("@", 0)
		_check(level in Unlocks.join_header(veteran), "A veteran's join names %s" % level)
