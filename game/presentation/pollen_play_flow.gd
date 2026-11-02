extends Node
## Opens the Pollen page (presentation/pollen_play_page.gd, pollen board 7b)
## from the balance on any Pollen chip (Home, the Wardrobe, the Pollen store),
## from Settings or from the Pollen store's "Earn Pollen free by playing", and
## reads its data once each time it opens (services/pollen_client.gd history),
## never on a timer. Back returns to where it opened: `return_to` names it
## ("home", "settings", "wardrobe" or "store"); the host
## reads it. It also makes the chips (kit/pollen_chip.gd) for Home and
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
## left unset, no plus shows. A tap that would open the screen Back already
## leads to goes Back instead, so the two screens never stack into a loop.
const Page = preload("res://presentation/pollen_play_page.gd")
const PollenChip = preload("res://presentation/kit/pollen_chip.gd")
const PollenWallet = preload("res://services/pollen_wallet.gd")
const PollenSurfaces = preload("res://services/pollen_surfaces.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")

const MODE := "pollen_play"

signal back_requested

var host: Node
## What this build shows (services/pollen_surfaces.gd); tests set their own.
var surfaces: RefCounted
## (from: String) -> void: opens the Pollen store, its Back going to `from` ("home" or "pollen").
var store_route: Callable
## () -> bool: whether the Pollen store can open now (bundles on for this store).
var store_sells: Callable
## Scope key -> the balance a chip last showed.
static var _shown: Dictionary = {}
var _page: Page
## The page's chip, made once per opening so its gain shows through the redraws.
var _page_chip: Control
var _history: Dictionary = {}
var _status := ""
var return_to := "home"
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

## What a chip shows now: [balance, whether its plus reaches the store], or []
## while Pollen does not show or no balance is known yet. Home makes a new chip
## only when this changes, so a refresh never replaces one under a finger.
func chip_state() -> Array:
	if not available() or balance() < 0: return []
	return [balance(), store_open()]

## A chip for Home or the page, or null while Pollen does not show or no balance is known yet.
func chip() -> Control:
	var state := chip_state()
	if state.is_empty(): return null
	var scope := _scope()
	var key := PollenWallet.scope_key(str(scope.server), str(scope.owner))
	var now: int = state[0]
	var made := PollenChip.make(now, state[1])
	var before: Variant = _shown.get(key)
	_shown[key] = now
	if before is int and now > before: made.show_gain(now - before, _reduced())
	made.amount_pressed.connect(_amount_pressed)
	made.plus_pressed.connect(_plus_pressed)
	return made

## Forgets what chips showed (tests).
static func forget_shown() -> void:
	_shown.clear()

## The balance: this page (nothing while it is open).
func _amount_pressed() -> void:
	if not is_open(): open_from_home()

## The plus: the Pollen store, whose Back comes to where the chip was. On this
## page opened from the store, the store is where Back leads, so it goes Back.
func _plus_pressed() -> void:
	if not store_open(): return
	if not is_open(): store_route.call("home")
	elif return_to == "store": back_requested.emit()
	else: store_route.call("pollen")

func open_from_home() -> void:
	_open("home")

func open_from_wardrobe() -> void:
	_open("wardrobe")

## Opens the page again with the Back it had (when the Pollen store it opened goes Back).
func reopen() -> void:
	_open(return_to)

func open_from_settings() -> void:
	_open("settings")

func open_from_store() -> void:
	_open("store")

func is_open() -> bool:
	return is_instance_valid(_page) and _page.is_inside_tree() and not _page.is_queued_for_deletion()

func _open(from: String) -> void:
	if not available(): return
	return_to = from
	host.running = false
	host.mode = MODE
	host._clear_overlay()
	_page = Page.new(host.get("title_font"))
	_page.back_pressed.connect(func() -> void: back_requested.emit())
	_page.retry_pressed.connect(refresh)
	host.overlay.add_child(_page)
	if host.has_method("_mark_screen_back"): host._mark_screen_back(_page.back_button)
	_history = {}
	_page_chip = chip()
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
	_page.render({"chip": _page_chip, "full_journey": _surfaces().full_journey_visible(), "status": _status, "retry": retry, "history": _history})
