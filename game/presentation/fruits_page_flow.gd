extends Node
## Opens the Fruits page (presentation/fruits_page.gd, Fruits board 6a) and
## reads its data once each time it opens, never on a timer: the Fruit lines
## from the history (services/pollen_client.gd history, fruit_entries) and, when
## this phone has no Fruits part yet (services/fruit_wallet.gd needs_read), the
## wallet. The goals and the balance are the kept Fruits part; the page draws
## again when it changes (a spend, a read, a receipt), and only then.
##
## open(from) is its one opener: the chip's Fruit half (Home, the Pollen page,
## the Wardrobe, the store), the store's "Fruits for playing together" and a
## goal's toast. Back returns to `from` (`return_to`; the host reads it); reopen()
## opens it again with that Back, after a screen it opened goes Back. Its
## buttons go through routes Main sets, so the page never reaches into another
## screen: Get Fruits (`store_route`, the store on its Fruits tab), Open the
## Orchard (`orchard_route`), Sunshine (`pollen_route`, the Pollen page with its
## Sunshine card) and Turn into Pollen (presentation/fruit_spend_flow.gd).
## Everything hides while Fruits do not show (services/pollen_surfaces.gd fruits_visible).
##
## Main hosts it as a child and reads Main only through: pollen_client,
## title_font, mode, running, overlay, _clear_overlay, and _mark_screen_back
## when Main has it (Android Back).
const Page = preload("res://presentation/fruits_page.gd")
const WalletView = preload("res://presentation/fruit_wallet_view.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const PollenSurfaces = preload("res://services/pollen_surfaces.gd")

const MODE := "fruits_page"
## Fruit lines the page lists (the history keeps up to 50).
const LINES := 20

signal back_requested

var host: Node
## presentation/fruit_spend_flow.gd: the Fruit spends, the client and the kept Fruits.
var spend: Node
## What this build shows (services/pollen_surfaces.gd); tests set their own.
var surfaces: RefCounted
## () -> Control: the money chip for the header (presentation/pollen_play_flow.gd chip), or null.
var chip_source: Callable
## () -> Array: what that chip shows (presentation/pollen_play_flow.gd chip_state); a new chip only when it changes.
var chip_state: Callable
## (from: String) -> void: the store on its Fruits tab, its Back coming here.
var store_route: Callable
## (from: String) -> void: the Wardrobe on its Orchard tab, its Back coming here.
var orchard_route: Callable
## (from: String) -> void: the Pollen page (its Sunshine card), its Back coming here.
var pollen_route: Callable
## () -> bool: whether the Wardrobe and the Pollen page can open now; their buttons show only then.
var orchard_ready: Callable
var pollen_ready: Callable
var return_to := "home"
var _page: Page
var _chip: Control
var _history: Dictionary = {}
var _reading := false
var _failed := false
var _all := false
var _reads := 0
var _drawn := ""

func _init(main: Node = null) -> void:
	host = main

func _surfaces() -> RefCounted:
	if surfaces == null: surfaces = PollenSurfaces.shared()
	return surfaces

## Whether the page can open: Fruits show for the signed-in player.
func available() -> bool:
	return spend != null and spend.visible()

func is_open() -> bool:
	return is_instance_valid(_page) and _page.is_inside_tree() and not _page.is_queued_for_deletion()

## Opens the page, its Back going to `from`; nothing while it is open already or Fruits do not show.
func open(from: String = "home") -> void:
	if is_open() or not available(): return
	return_to = from
	host.running = false
	host.mode = MODE
	host._clear_overlay()
	_page = Page.new(host.get("title_font"))
	_page.back_pressed.connect(func() -> void: back_requested.emit())
	_page.retry_pressed.connect(refresh)
	_page.goals_toggled.connect(_toggle_goals)
	_page.button_pressed.connect(_pressed)
	host.overlay.add_child(_page)
	if host.has_method("_mark_screen_back"): host._mark_screen_back(_page.back_button)
	var store: RefCounted = spend.fruits()
	if not store.changed.is_connected(_on_fruits_changed): store.changed.connect(_on_fruits_changed)
	_history = {}
	_failed = false
	_all = false
	_drawn = ""
	_chip_shown = chip_state.call() if chip_state.is_valid() else []
	_chip = _make_chip()
	_redraw()
	refresh()

## Opens the page again with the Back it had.
func reopen() -> void:
	open(return_to)

## Reads the history, and the wallet first when no Fruits part is kept; the page draws with the answers.
func refresh() -> void:
	if not is_open() or _reading: return
	_reads += 1
	var read := _reads
	_reading = true
	_failed = false
	_redraw()
	var scope: Dictionary = spend.scope()
	var store: RefCounted = spend.fruits()
	if not scope.is_empty() and store.needs_read(str(scope.server), str(scope.owner)): await spend.refresh_wallet()
	var answer: Dictionary = await host.pollen_client.history()
	_reading = false
	if read != _reads or not is_open(): return
	if not answer.is_empty(): _history = answer
	_failed = _part().is_empty()
	_redraw()

func _part() -> Dictionary:
	var scope: Dictionary = spend.scope()
	return {} if scope.is_empty() else spend.fruits().part(str(scope.server), str(scope.owner))

func _make_chip() -> Control:
	return chip_source.call() if chip_source.is_valid() else null

## The kept Fruits changed: a new chip only when what it shows changed, and the
## page drawn again only when what it shows changed (_redraw), so a read that
## changes neither never rebuilds a button under a finger.
func _on_fruits_changed(_server: String, _owner: String) -> void:
	if not is_open(): return
	if not available():
		back_requested.emit()
		return
	var state: Array = chip_state.call() if chip_state.is_valid() else []
	if state != _chip_shown:
		_chip_shown = state
		_chip = _make_chip()
		_page.show_chip(_chip)
	_redraw()

## What the chip in the header shows (chip_state), as it was made.
var _chip_shown: Array = []

func _toggle_goals() -> void:
	_all = not _all
	_redraw()

## The page's data now: the kept Fruits part, the newest Fruit lines and the buttons that show.
func model() -> Dictionary:
	var part := _part()
	if part.is_empty():
		return {"status": PlayerCopy.FRUITS_PAGE_OFFLINE if _failed and not _reading else PlayerCopy.FRUITS_PAGE_LOADING, "retry": _failed and not _reading}
	var buttons: Array[String] = []
	var scope: Dictionary = spend.scope()
	if store_route.is_valid() and _surfaces().fruit_packs_visible(spend.fruits(), scope): buttons.append(WalletView.GET)
	if orchard_route.is_valid() and (not orchard_ready.is_valid() or orchard_ready.call()): buttons.append(WalletView.ORCHARD)
	if pollen_route.is_valid() and part.has("sunshine") and (not pollen_ready.is_valid() or pollen_ready.call()): buttons.append(WalletView.SUNSHINE)
	if part.has("convert"): buttons.append(WalletView.CONVERT)
	var entries: Array = (_history.get("fruit_entries", []) as Array).slice(0, LINES)
	return {"status": "", "achievements": part.get("achievements", []), "all": _all, "balance": int(part.balance), "entries": entries, "buttons": buttons}

func _redraw() -> void:
	if not is_open(): return
	var shown := model()
	# Drawn again only when what it shows changed, so a late answer never rebuilds a button under a finger.
	var key := var_to_str(shown)
	if key == _drawn: return
	_drawn = key
	shown["chip"] = _chip
	_page.render(shown)

## A button: its screen, opened from here ("fruits"; Main keeps the opener's own
## Back when that screen opened this page, so two screens never loop).
func _pressed(which: String, button: Button) -> void:
	var routes := {WalletView.GET: store_route, WalletView.ORCHARD: orchard_route, WalletView.SUNSHINE: pollen_route}
	if which == WalletView.CONVERT:
		spend.convert(_page, button)
		return
	var route: Callable = routes.get(which, Callable())
	if route.is_valid(): route.call("fruits")
