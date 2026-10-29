extends Node
## Opens Pollen from play (presentation/pollen_play_page.gd, pollen board 7b)
## from Home's Pollen chip, from Settings or from the Pollen store's "Earn
## Pollen free by playing", and reads its data once each time it opens
## (services/pollen_client.gd history), never on a timer. Back returns to where
## it opened: `return_to` names it ("home", "settings" or "store"); the host
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
## While the shop sells, the chip's plus shows and a tap goes to `store_route`
## when one is set; otherwise every tap opens this page, and no purchase route
## shows. Main leaves it unset: the Pollen store (presentation/pollen_store_flow.gd)
## opens only while bundles sell, which shop() does not check, so a plus could
## show that opens nothing.
## On a build that sells bundles, the page also lists purchases (pollen board 1,
## "Pollen and purchases") while the server sells them or the history holds one;
## Settings names its row from purchases_shown(). iPhone never lists them.
const Page = preload("res://presentation/pollen_play_page.gd")
const PollenChip = preload("res://presentation/kit/pollen_chip.gd")
const PollenWallet = preload("res://services/pollen_wallet.gd")
const PollenSurfaces = preload("res://services/pollen_surfaces.gd")
const Wardrobe = preload("res://services/wardrobe.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const StoreCurrency = preload("res://services/store_currency.gd")

const MODE := "pollen_play"

signal back_requested

var host: Node
## What this build shows (services/pollen_surfaces.gd); tests set their own.
var surfaces: RefCounted
## A purchase route for the chip; a tap opens it while the shop sells (unset in Main, see above).
var store_route: Callable
## Scope key -> the balance a chip last showed.
static var _shown: Dictionary = {}
var _page: Page
## The page's chip, made once per opening so its gain shows through the redraws.
var _page_chip: Button
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

## Whether the shop sells: the build sells and the server has the shop on.
func shop() -> bool:
	var scope := _scope()
	return _surfaces().shop_visible() and not scope.is_empty() and Wardrobe.shared().shop(str(scope.server), str(scope.owner))

## Whether the page lists purchases: a Google Play build that sells bundles, while the
## server sells them to this player or `history` (once read) holds a purchase.
func purchases_shown(history: Dictionary = {}) -> bool:
	if not _surfaces().bundles_visible() or not available(): return false
	var scope := _scope()
	return Wardrobe.shared().bundles(str(scope.server), str(scope.owner)) or not (history.get("purchases", []) as Array).is_empty()

## The money spent on bundles in US cents: the history's figure, else (a server
## from before the history listed purchases) the wallet read's, else -1 (no total shows).
func spent_usd_cents(history: Dictionary) -> int:
	var spent := int(history.get("spent_usd_cents", -1))
	if spent >= 0 or not available(): return spent
	var scope := _scope()
	var part: Dictionary = Wardrobe.shared().view(str(scope.server), str(scope.owner)).get("bundles", {})
	return int(part.get("spent_usd_cents", -1)) if not part.is_empty() else -1

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
	_open("home")

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
	_page.render({"chip": _page_chip, "full_journey": _surfaces().full_journey_visible(), "status": _status, "retry": retry, "history": _history,
		"purchases": purchases_shown(_history), "spent_usd_cents": spent_usd_cents(_history), "money": money_shown()})

## Whether the Purchases card shows money: only while the store sells in US
## dollars (services/store_currency.gd), since the server keeps Google Play's US
## figure. Anyone else sees each bundle, its Pollen, its date and its order, and no total.
func money_shown() -> bool:
	return StoreCurrency.usd()
