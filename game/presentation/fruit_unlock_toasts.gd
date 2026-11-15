extends Node
## Says each newly paid Fruit goal once, through the app's one pop-up
## (presentation/toast.gd): "First friend duel win: +10 Fruits" with the Fruit
## mark and View, which opens the Fruits page. A line outlives the screen it
## was posted on (it may still be up as a room opens), so View runs through the
## pop-up's when_free with `open_ready`: inside a room or a replay it waits and
## opens the page once the player is back on a screen it opens over. The goals wait in services/fruit_wallet.gd
## unlocks (from a turn's receipt or a wallet read) until one is shown, and each
## is marked shown as it posts, so it never says one twice, on this launch or
## the next.
##
## One at a time and never over play: Main's loop calls service(), which posts
## only while no line shows (a posted line replaces the one showing), nothing is
## being played (Main.in_play: a room, whose turn's result card says its goals
## in its own plum line, presentation/pollen_result_line.gd, which marks them
## shown; a replay; a chapter on its way in), the app is in front and the
## screen up is one its View opens the page over (open_ready). Nothing runs while no goal waits or Fruits do not
## show: the Fruit store's `unlocked` and `changed` signals wake it.
##
## Main hosts it and reads Main only through: toast, in_play,
## application_backgrounded and _names_scope.
const FruitWallet = preload("res://services/fruit_wallet.gd")
const PollenSurfaces = preload("res://services/pollen_surfaces.gd")
const PollenMoney = preload("res://services/pollen_money.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const CurrencyMark = preload("res://presentation/kit/currency_mark.gd")

var host: Node
## The Fruits kept on this phone; tests set their own.
var fruits: RefCounted
## What this build shows (services/pollen_surfaces.gd); tests set their own.
var surfaces: RefCounted
## (from: String) -> void: opens the Fruits page (the toast's View).
var open_page: Callable
## () -> bool: whether View may open the page now (Main.fruits_view_ready); View waits for it.
var open_ready: Callable
## A goal may wait: set at launch and by `unlocked` or `changed`, cleared once
## none waits or Fruits do not show (a sign in or Fruits turning on is a change).
var _waiting := true

func _init(main: Node = null) -> void:
	host = main

func _store() -> RefCounted:
	if fruits == null: fruits = FruitWallet.shared()
	if not fruits.unlocked.is_connected(_on_unlocked): fruits.unlocked.connect(_on_unlocked)
	if not fruits.changed.is_connected(_on_unlocked): fruits.changed.connect(_on_unlocked)
	return fruits

func _surfaces() -> RefCounted:
	if surfaces == null: surfaces = PollenSurfaces.shared()
	return surfaces

func _on_unlocked(_server: String, _owner: String) -> void:
	_waiting = true

## Posts the oldest goal waiting, when the screen is free for it. Returns the line posted, or "".
func service() -> String:
	var store := _store()
	if not _waiting or host == null: return ""
	if host.in_play() or bool(host.get("application_backgrounded")): return ""
	# Only where its View opens the page at once (Friends, Journey or a lobby wait).
	if open_ready.is_valid() and open_ready.call() != true: return ""
	var toast: Variant = host.get("toast")
	if toast == null or toast.showing(): return ""
	var scope: Dictionary = host._names_scope()
	# No player yet: looked at again once there is one.
	if scope.is_empty(): return ""
	if not _surfaces().fruits_visible(store, scope):
		_waiting = false
		return ""
	var waiting: Array = store.unlocks(str(scope.server), str(scope.owner))
	if waiting.is_empty():
		_waiting = false
		return ""
	var goal: Dictionary = waiting[0]
	# Marked before it posts, so it never shows twice.
	store.mark_unlock_shown(str(scope.server), str(scope.owner), str(goal.id))
	var named := str(PlayerCopy.FRUIT_GOALS.get(str(goal.id), ""))
	if named.is_empty(): return ""
	var line := PlayerCopy.FRUIT_UNLOCK_TOAST % [named, PollenMoney.grouped(int(goal.fruits))]
	if open_page.is_valid(): toast.post(line, CurrencyMark.FRUITS, PlayerCopy.FRUIT_UNLOCK_VIEW, open_page.bind("home"), open_ready)
	else: toast.post(line, CurrencyMark.FRUITS)
	return line
