extends Node
## Opens Pollen from play (presentation/pollen_play_page.gd, pollen board 7b)
## from Home's Pollen chip or from Settings, and reads its data once each time
## it opens (services/pollen_client.gd history), never on a timer. Back returns
## to where it opened. It also makes the chips (kit/pollen_chip.gd) for Home and
## the page, and remembers for the app's run the balance a chip last showed the
## player, so a chip shows the gain just after earning: increases only, never
## after a spend, and none on the first chip after a launch.
##
## Main hosts it as a child and reads Main only through this host contract
## (read at call time, so Main or a test can swap a service):
## - services: pollen_client, saves (reduced motion), title_font
## - screen: mode, running, overlay (the page's parent), _clear_overlay, and
##   _mark_screen_back when Main has it (Android Back)
## While the shop sells, the chip's plus shows and a tap goes to `store_route`
## (the Pollen store, built elsewhere) when one is set; otherwise every tap
## opens this page, and no purchase route shows.
const Page = preload("res://presentation/pollen_play_page.gd")
const PollenChip = preload("res://presentation/kit/pollen_chip.gd")
const PollenWallet = preload("res://services/pollen_wallet.gd")
const PollenSurfaces = preload("res://services/pollen_surfaces.gd")
const Wardrobe = preload("res://services/wardrobe.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")

const MODE := "pollen_play"

signal back_requested(to_settings: bool)

var host: Node
## What this build shows (services/pollen_surfaces.gd); tests set their own.
var surfaces: RefCounted
## The Pollen store, once it exists; a tap on the chip opens it while the shop sells.
var store_route: Callable
## Scope key -> the balance a chip last showed.
static var _shown: Dictionary = {}
var _page: Page
## The page's chip, made once per opening so its gain shows through the redraws.
var _page_chip: Button
var _history: Dictionary = {}
var _status := ""
var _from_settings := false
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

## Whether the shop sells: the build sells and the server has the shop on.
func shop() -> bool:
	var scope := _scope()
	return _surfaces().shop_visible() and not scope.is_empty() and Wardrobe.shared().shop(str(scope.server), str(scope.owner))

func _reduced() -> bool:
	return bool(host.saves.data.settings.get("reduced_motion", false)) if host.get("saves") != null else false

## A chip for Home or the page, or null while Pollen does not show or no balance is known yet.
func chip() -> Button:
	if not available() or balance() < 0: return null
	var scope := _scope()
	var key := PollenWallet.scope_key(str(scope.server), str(scope.owner))
	var now := balance()
	# The plus only where a tap reaches the store.
	var made := PollenChip.make(now, shop() and store_route.is_valid())
	var before: Variant = _shown.get(key)
	_shown[key] = now
	if before is int and now > before: made.show_gain(now - before, _reduced())
	made.pressed.connect(_chip_pressed)
	return made

## Forgets what chips showed (tests).
static func forget_shown() -> void:
	_shown.clear()

## On Home the chip opens the store while the shop sells (once one is set), else this
## page; on this page it opens the store, or does nothing.
func _chip_pressed() -> void:
	if shop() and store_route.is_valid(): store_route.call()
	elif not is_open(): open_from_home()

func open_from_home() -> void:
	_from_settings = false
	_open()

func open_from_settings() -> void:
	_from_settings = true
	_open()

func is_open() -> bool:
	return is_instance_valid(_page) and _page.is_inside_tree() and not _page.is_queued_for_deletion()

func _open() -> void:
	if not available(): return
	host.running = false
	host.mode = MODE
	host._clear_overlay()
	_page = Page.new(host.get("title_font"))
	_page.back_pressed.connect(func() -> void: back_requested.emit(_from_settings))
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
