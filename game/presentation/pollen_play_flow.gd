extends Node
## Opens the Pollen page (presentation/pollen_play_page.gd, pollen board 7b)
## from the balance on any Pollen chip (Home, the Wardrobe, the Pollen store),
## from Settings or from the Pollen store's "Earn Pollen free by playing", and
## reads its data once each time it opens (services/pollen_client.gd history),
## never on a timer. Back goes through Main's back history (menu_opened, when
## Main has it: presentation/menu_back.gd), told which screen it opened over
## ("home", "settings", "wardrobe", "store" or "fruits"). It also makes the chips (kit/pollen_chip.gd) for Home and
## the page, and remembers for the app's run the balance a chip last showed the
## player, so a chip shows the gain just after earning: increases only, never
## after a spend, and none on the first chip after a launch.
##
## Main hosts it as a child and reads Main only through this host contract
## (read at call time, so Main or a test can swap a service):
## - services: pollen_client, saves (reduced motion), title_font
## - screen: mode, running, overlay (the page's parent), _clear_overlay, and
##   _mark_screen_back when Main has it (Android Back)
## The chip is one pill split in two (kit/pollen_chip.gd): its balance opens
## this page, and its plus, shown only while the Pollen store can open
## (`store_sells`), opens the store through `store_route`. Main sets both from
## the Pollen store (presentation/pollen_store_flow.gd available, show_store);
## left unset, no plus shows. While Fruits show, its Fruit half opens the Fruits
## page through `fruits_route` (Main sets it to the Fruits page's opener; left
## unset, the Fruit half still shows and its tap does nothing). A screen already
## under this one in the history opens in its own place there, so screens never
## stack into a loop.
const Page = preload("res://presentation/pollen_play_page.gd")
const PollenChip = preload("res://presentation/kit/pollen_chip.gd")
const PollenWallet = preload("res://services/pollen_wallet.gd")
const PollenSurfaces = preload("res://services/pollen_surfaces.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")

const MODE := "pollen_play"
## Its name in Main's back history (presentation/menu_back.gd).
const MENU_SCREEN := "pollen"
## Where Back goes when the Fruits page's Sunshine opened this page.
const FROM_FRUITS := "fruits"

signal back_requested

var host: Node
## What this build shows (services/pollen_surfaces.gd); tests set their own.
var surfaces: RefCounted
## (from: String) -> void: opens the Pollen store, its Back going to `from` ("home" or "pollen").
var store_route: Callable
## () -> bool: whether the Pollen store can open now (bundles on for this store).
var store_sells: Callable
## (from: String) -> void: opens the Fruits page, its Back going to `from` ("home" or "pollen").
var fruits_route: Callable
## The Fruits kept on this phone (services/fruit_wallet.gd); tests set their own.
var fruits: RefCounted
## The Fruit spends (presentation/fruit_spend_flow.gd): the Sunshine card's
## data, whether its price button shows, and its confirm and short cards. Main
## sets it; left unset, no Sunshine card shows.
var fruit_spends: Node
## Scope key -> the balance a chip last showed.
static var _shown: Dictionary = {}
var _page: Page
## The page's chip, made once per opening so its gain shows through the redraws.
var _page_chip: Control
var _history: Dictionary = {}
var _status := ""
var _reads := 0

func _init(main: Node = null) -> void:
	host = main

func _surfaces() -> RefCounted:
	if surfaces == null: surfaces = PollenSurfaces.shared()
	return surfaces

func _scope() -> Dictionary:
	var client: Variant = host.get("pollen_client") if host != null else null
	return client.scope() if client != null else {}

## Whether Pollen shows: the server has earning on for this player and the build shows the balance.
func available() -> bool:
	return _surfaces().wallet_visible() and not _scope().is_empty()

## The kept balance, or -1 before the server has said.
func balance() -> int:
	var scope := _scope()
	if scope.is_empty(): return -1
	var wallet: Dictionary = host.pollen_client.wallet.wallet(str(scope.server), str(scope.owner))
	return int(wallet.get("balance", -1)) if not wallet.is_empty() else -1

## Whether the chip's plus shows: the Pollen store can open now.
func store_open() -> bool:
	return store_route.is_valid() and store_sells.is_valid() and bool(store_sells.call())

func _reduced() -> bool:
	return bool(host.saves.data.settings.get("reduced_motion", false)) if host.get("saves") != null else false

## What a chip shows now: [balance, whether its plus reaches the store, the
## Fruit half (kit/pollen_chip.gd fruits_for: [] while Fruits do not show)], or
## [] while Pollen does not show or no balance is known yet. Home makes a new
## chip only when this changes, so a refresh never replaces one under a finger.
func chip_state() -> Array:
	if not available() or balance() < 0: return []
	return [balance(), store_open(), PollenChip.fruits_for(_scope(), _surfaces(), fruits)]

## A chip for Home, this page or the Fruits page (`where` "fruits"), or null
## while Pollen does not show or no balance is known yet. Each half goes where
## the chip is: on the Fruits page its Fruit half does nothing, and the Pollen
## page and the store it opens come back to the Fruits page.
func chip(where: String = "") -> Control:
	var state := chip_state()
	if state.is_empty(): return null
	var scope := _scope()
	var key := PollenWallet.scope_key(str(scope.server), str(scope.owner))
	var now: int = state[0]
	var made := PollenChip.make(now, state[1], state[2])
	var before: Variant = _shown.get(key)
	_shown[key] = now
	if before is int and now > before: made.show_gain(now - before, _reduced())
	made.amount_pressed.connect(_amount_pressed.bind(where))
	made.plus_pressed.connect(_plus_pressed.bind(where))
	made.fruits_pressed.connect(_fruits_pressed.bind(where))
	return made

## Forgets what chips showed (tests).
static func forget_shown() -> void:
	_shown.clear()

## The balance: this page (nothing while it is open).
func _amount_pressed(where: String = "") -> void:
	if where != FROM_FRUITS:
		if not is_open(): open_from_home()
	else: open_from_fruits()

## The plus: the Pollen store, whose Back comes to where the chip was.
func _plus_pressed(where: String = "") -> void:
	if not store_open(): return
	if where == FROM_FRUITS: store_route.call(FROM_FRUITS)
	elif not is_open(): store_route.call("home")
	else: store_route.call(MENU_SCREEN)

## The Fruit half: the Fruits page, whose Back comes to where the chip was
## (nothing on the Fruits page itself).
func _fruits_pressed(where: String = "") -> void:
	if where != FROM_FRUITS and fruits_route.is_valid(): fruits_route.call("pollen" if is_open() else "home")

func open_from_home() -> void:
	_open("home")

func open_from_wardrobe() -> void:
	_open("wardrobe")

## Opens the page again (Back from a screen it opened).
func reopen() -> void:
	_open("")

func open_from_settings() -> void:
	_open("settings")

func open_from_store() -> void:
	_open("store")

## From the Fruits page's Sunshine: its Back goes to the Fruits page.
func open_from_fruits() -> void:
	_open(FROM_FRUITS)

func is_open() -> bool:
	return is_instance_valid(_page) and _page.is_inside_tree() and not _page.is_queued_for_deletion()

func _open(from: String) -> void:
	if not available(): return
	host.running = false
	host.mode = MODE
	host._clear_overlay()
	_page = Page.new(host.get("title_font"))
	_page.back_pressed.connect(func() -> void: back_requested.emit())
	_page.retry_pressed.connect(refresh)
	_page.sunshine_buy_pressed.connect(_sunshine_pressed)
	host.overlay.add_child(_page)
	if host.has_method("_mark_screen_back"): host._mark_screen_back(_page.back_button)
	if host.has_method("menu_opened"): host.menu_opened(MENU_SCREEN, from, _page.back_button)
	# The Sunshine card follows the kept Fruits (a purchase, a turn that used one).
	if fruit_spends != null and not fruit_spends.fruits().changed.is_connected(_on_fruits_changed): fruit_spends.fruits().changed.connect(_on_fruits_changed)
	_history = {}
	_page_chip = chip()
	_fruits_shown = var_to_str([_sunshine(), chip_state()])
	_status = PlayerCopy.POLLEN_PLAY_LOADING
	_redraw(false)
	refresh()

## Reads the history again; the page redraws with the answer.
func refresh() -> void:
	if not is_open(): return
	_reads += 1
	var read := _reads
	if not _history.is_empty() or _status != PlayerCopy.POLLEN_PLAY_LOADING:
		_status = PlayerCopy.POLLEN_PLAY_LOADING
		_redraw(false)
	var answer: Dictionary = await host.pollen_client.history()
	# A newer read, or the page closed meanwhile: this answer is not shown.
	if read != _reads or not is_open(): return
	_history = answer
	_status = PlayerCopy.POLLEN_PLAY_OFFLINE if answer.is_empty() else ""
	_redraw(answer.is_empty())

func _redraw(retry: bool) -> void:
	if not is_open(): return
	var model := {"chip": _page_chip, "full_journey": _surfaces().full_journey_visible(), "status": _status, "retry": retry, "history": _history}
	model.merge(_sunshine())
	_page.render(model)

## The Sunshine card's part of the page: {fruits, sunshine, sunshine_buyable}.
func _sunshine() -> Dictionary:
	if fruit_spends == null or not fruit_spends.visible(): return {"fruits": false}
	var scope: Dictionary = fruit_spends.scope()
	return {"fruits": true, "sunshine": fruit_spends.fruits().sunshine(str(scope.server), str(scope.owner)), "sunshine_buyable": fruit_spends.sunshine_offered()}

func _sunshine_pressed(button: Button) -> void:
	if fruit_spends != null and is_open(): fruit_spends.sunshine(_page, button)

## The kept Fruits changed: the page draws again only when its Sunshine card or
## its chip would show something else (a new chip then), so a read that changes
## neither never rebuilds a button under a finger.
func _on_fruits_changed(_server: String, _owner: String) -> void:
	if not is_open(): return
	var shown := var_to_str([_sunshine(), chip_state()])
	if shown == _fruits_shown: return
	_fruits_shown = shown
	_page_chip = chip()
	_redraw(_status == PlayerCopy.POLLEN_PLAY_OFFLINE)

## What the Sunshine card and the chip last showed (_on_fruits_changed).
var _fruits_shown := ""
