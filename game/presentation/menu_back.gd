extends RefCounted
## The one back history the menu screens share: Home or Settings at the bottom,
## then the Wardrobe (with its Orchard), the store, the Fruits page and the
## Pollen page in the order the player opened them. Each screen says when it
## opened (opened) and asks it to go Back (back). A screen already in the
## history opens in its own place, the screens above it dropped, so Back always
## walks out the way the player came and ends where they started, never round
## in a loop. Each screen keeps its own look for reopening (the store its tab,
## the Wardrobe its Orchard and pick); the history keeps only names.
##
## Main owns the one instance and sets `routes`: screen -> () -> bool that opens
## that screen again, true once it is up (read at call time, so a test can swap
## a flow). A screen that cannot open now is passed over to the one below it.
## Every screen it tracks gets the Home square beside its Back
## (kit/home_square.gd) while Back would not already go Home.
const HomeSquare = preload("res://presentation/kit/home_square.gd")

const HOME := "home"
const SETTINGS := "settings"
const WARDROBE := "wardrobe"
const STORE := "store"
const FRUITS := "fruits"
const POLLEN := "pollen"
## Where a history starts: opening a screen from one of these starts it again.
const ROOTS := [HOME, SETTINGS]
const SCREENS := [HOME, SETTINGS, WARDROBE, STORE, FRUITS, POLLEN]

var routes: Dictionary = {}
var _entries: Array[String] = []

## The history, bottom first (tests).
func entries() -> Array[String]:
	return _entries.duplicate()

## The screen up now, as the history has it ("" before any).
func top() -> String:
	return "" if _entries.is_empty() else _entries.back()

## `screen` opened over `from` (the screen it was asked from; "" when Back
## opened it again). `back` is its Back button, which gets the Home square.
func opened(screen: String, from: String, back: Button = null) -> void:
	if from in ROOTS:
		_entries.assign([from, screen])
	elif _entries.has(screen):
		_entries.resize(_entries.find(screen) + 1)
	else:
		var below := _entries.find(from)
		if below >= 0: _entries.resize(below + 1)
		else:
			_entries.assign([HOME])
			if from in SCREENS: _entries.append(from)
		_entries.append(screen)
	if back != null and is_instance_valid(back): HomeSquare.attach(back, home_shown(), home)

## Whether the Home square shows: Back from the screen up now would not go Home.
func home_shown() -> bool:
	return _entries.size() >= 2 and _entries[_entries.size() - 2] != HOME

## Back from `screen`: the screen under it opens again, or the next one that
## can. Only the screen on top goes Back, so a second tap, or a page that closes
## itself after Back already left it, changes nothing.
func back(screen: String) -> void:
	if top() != screen: return
	_entries.pop_back()
	while not _entries.is_empty():
		var route: Callable = routes.get(_entries.back(), Callable())
		if route.is_valid() and bool(route.call()): return
		_entries.pop_back()
	home()

## Straight Home, the history cleared.
func home() -> void:
	_entries.clear()
	var route: Callable = routes.get(HOME, Callable())
	if route.is_valid(): route.call()
