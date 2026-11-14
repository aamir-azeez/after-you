extends SceneTree
## The menu screens' one back history (presentation/menu_back.gd) through a real
## Main and its real flows, only their gates open and their server reads
## stilled: from Home and from Settings, every chain of the cross-links each
## screen offers (Home's and Settings' rows and chips, the Wardrobe's chip and
## Get Fruits, the store's Fruits, Earn and receipt, the Fruits page's buttons
## and chip, the Pollen page's chip, and the short card's Get Fruits and a goal's
## toast from anywhere), a few steps deep. After each step the history's top is
## the screen up; then Back, pressed as Android Back presses it, walks out to
## the starting screen in finite presses, never showing a screen twice. The
## Home square shows exactly where Back would not already go Home, and takes
## the player straight Home. A second Back tap on a page already left changes
## nothing.
const Main = preload("res://main.gd")
const Storage = preload("res://services/local_save.gd")
const MenuBack = preload("res://presentation/menu_back.gd")
const WardrobeFlow = preload("res://presentation/wardrobe_flow.gd")
const PollenStoreFlow = preload("res://presentation/pollen_store_flow.gd")
const PollenPlayFlow = preload("res://presentation/pollen_play_flow.gd")
const FruitsPageFlow = preload("res://presentation/fruits_page_flow.gd")
const WalletView = preload("res://presentation/fruit_wallet_view.gd")
const HomeSquare = preload("res://presentation/kit/home_square.gd")
const Connectivity = preload("res://services/connectivity.gd")

## Links followed after the starting screen.
const DEPTH := 3
## The screen each mode is, as the history names it.
const SCREEN_OF := {"home": MenuBack.HOME, "settings": MenuBack.SETTINGS, WardrobeFlow.MODE_WARDROBE: MenuBack.WARDROBE,
	PollenStoreFlow.MODE_POLLEN_STORE: MenuBack.STORE, FruitsPageFlow.MODE: MenuBack.FRUITS, PollenPlayFlow.MODE: MenuBack.POLLEN}

class OpenWardrobe extends WardrobeFlow:
	func available() -> bool: return true
	func refresh() -> void: pass

class OpenStore extends PollenStoreFlow:
	func available() -> bool: return true
	func load_store() -> void: pass

class OpenPlay extends PollenPlayFlow:
	func available() -> bool: return true
	func refresh() -> void: pass

class OpenFruits extends FruitsPageFlow:
	func available() -> bool: return true
	func refresh() -> void: pass

class OpenMain extends Main:
	func _new_wardrobe_flow() -> WardrobeFlow: return OpenWardrobe.new(self)
	func _new_pollen_store_flow() -> PollenStoreFlow: return OpenStore.new(self)
	func _new_pollen_play_flow() -> PollenPlayFlow: return OpenPlay.new(self)
	func _new_fruits_page_flow() -> FruitsPageFlow: return OpenFruits.new(self)

var checks := 0
var failures := 0
var app: Node
var paths := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	Connectivity.shared().note_reached()
	var path := "user://menu-back-" + Crypto.new().generate_random_bytes(8).hex_encode() + ".json"
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1560, 720)
	root.add_child(viewport)
	app = OpenMain.new()
	app.saves = Storage.new(path)
	app.saves.data.settings.sound = false
	app.saves.data.settings.haptics = false
	app.saves.flush()
	viewport.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	await process_frame
	await _owner_chain()
	await _second_tap()
	await _stale_history()
	for start: String in [MenuBack.HOME, MenuBack.SETTINGS]:
		await _walk(start, [])
	_check(paths > 100, "Every chain was walked: %d" % paths)
	viewport.free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("AFTER YOU MENU BACK: %d checks, %d failures, %d chains" % [checks, failures, paths])
	quit(1 if failures > 0 else 0)

## The cross-links on `screen`: name -> what the player taps.
func _links(screen: String) -> Dictionary:
	var play: Node = app.pollen_play_flow
	var store: Node = app.pollen_store_flow
	var wardrobe: Node = app.wardrobe_flow
	var fruits: Node = app.fruits_page_flow
	var links := {}
	match screen:
		MenuBack.HOME:
			links["wardrobe row"] = app._open_wardrobe_from_home
			links["chip balance"] = play._amount_pressed.bind("")
			links["chip plus"] = play._plus_pressed.bind("")
			links["chip fruits"] = play._fruits_pressed.bind("")
		MenuBack.SETTINGS:
			links["wardrobe row"] = func() -> void: wardrobe.show_wardrobe()
			links["pollen row"] = play.open_from_settings
		MenuBack.WARDROBE:
			links["chip plus"] = wardrobe.store_requested.emit
			links["chip balance"] = wardrobe.pollen_requested.emit
			links["chip fruits"] = wardrobe.fruits_requested.emit
			links["orchard get fruits"] = wardrobe.fruits_store_requested.emit
		MenuBack.STORE:
			links["fruits"] = store.show_fruits
			links["earn"] = store.show_earning
			links["receipt wardrobe"] = store.wardrobe_requested.emit
		MenuBack.FRUITS:
			links["get fruits"] = fruits._pressed.bind(WalletView.GET, null)
			links["orchard"] = fruits._pressed.bind(WalletView.ORCHARD, null)
			links["sunshine"] = fruits._pressed.bind(WalletView.SUNSHINE, null)
			links["chip balance"] = play._amount_pressed.bind(PollenPlayFlow.FROM_FRUITS)
			links["chip plus"] = play._plus_pressed.bind(PollenPlayFlow.FROM_FRUITS)
		MenuBack.POLLEN:
			links["chip plus"] = play._plus_pressed.bind("")
			links["chip fruits"] = play._fruits_pressed.bind("")
	links["short card get fruits"] = app.fruit_spend_flow.get_fruits
	links["goal toast"] = app.fruit_unlock_toasts.open_page.bind("")
	return links

func _screen() -> String:
	return str(SCREEN_OF.get(app.mode, app.mode))

func _start(start: String) -> void:
	if start == MenuBack.HOME: app._show_home()
	else: app.settings_flow.show_settings()
	await process_frame

## Follows `steps` from `start`, checking the history after each; the screens shown.
func _follow(start: String, steps: Array) -> Array:
	await _start(start)
	var shown := [start]
	for step: String in steps:
		var link: Callable = _links(_screen()).get(step, Callable())
		link.call()
		shown.append(_screen())
		_check(app.menu_back.top() == _screen(), "%s %s: the history's top is the screen up (%s, %s)" % [start, steps, app.menu_back.entries(), _screen()])
	return shown

## Every chain from `start` up to DEPTH links deep, each walked out with Back.
func _walk(start: String, steps: Array) -> void:
	if steps.size() >= DEPTH: return
	var shown := await _follow(start, steps)
	for name: String in _links(shown.back()).keys():
		var next := steps + [name]
		await _back_out(start, next)
		await _walk(start, next)

## Follows `steps`, checks the Home square, then presses Back to the start.
func _back_out(start: String, steps: Array) -> void:
	paths += 1
	await _follow(start, steps)
	var entries: Array[String] = app.menu_back.entries()
	var square := app.overlay.find_child(HomeSquare.NAME, true, false) as Button
	var tracked := _screen() not in MenuBack.ROOTS
	var wanted := tracked and entries.size() >= 2 and entries[entries.size() - 2] != MenuBack.HOME
	_check(not tracked or (square != null and square.visible == wanted), "%s %s: the Home square shows only where Back would not go Home (%s)" % [start, steps, entries])
	var seen := [_screen()]
	var presses := 0
	while _screen() != start and presses <= MenuBack.SCREENS.size():
		app._back_on_screen()
		presses += 1
		await process_frame
		_check(_screen() not in seen, "%s %s: Back never shows a screen twice (%s after %s)" % [start, steps, _screen(), seen])
		seen.append(_screen())
	_check(_screen() == start and presses <= steps.size(), "%s %s: Back walks out to %s in %d presses: %s" % [start, steps, start, presses, seen])
	if wanted and steps.size() == 2:
		await _follow(start, steps)
		(app.overlay.find_child(HomeSquare.NAME, true, false) as Button).pressed.emit()
		await process_frame
		_check(app.mode == "home" and app.menu_back.entries().is_empty(), "%s %s: the Home square goes straight Home and clears the history" % [start, steps])

## The owner's chain: the store, its Fruits, Get Fruits, Pollen and more; Back
## then goes store, Home (it went round store, Fruits page, Pollen page forever).
func _owner_chain() -> void:
	var shown := await _follow(MenuBack.HOME, ["chip plus", "fruits", "get fruits", "earn"])
	_check(shown == [MenuBack.HOME, MenuBack.STORE, MenuBack.FRUITS, MenuBack.STORE, MenuBack.POLLEN] and app.menu_back.entries() == [MenuBack.HOME, MenuBack.STORE, MenuBack.POLLEN], "The store, its Fruits, Get Fruits and Earn: %s %s" % [shown, app.menu_back.entries()])
	app.pollen_store_flow.set_tab("fruits")
	app._back_on_screen()
	await process_frame
	_check(_screen() == MenuBack.STORE, "Back from the Pollen page goes to the store")
	app._back_on_screen()
	await process_frame
	_check(app.mode == "home", "and Back from the store goes Home")

## A second tap on a Back already pressed changes nothing: one step back only.
func _second_tap() -> void:
	await _follow(MenuBack.HOME, ["wardrobe row", "chip plus", "fruits"])
	var back: Button = app.fruits_page_flow._page.back_button
	back.pressed.emit()
	back.pressed.emit()
	await process_frame
	_check(_screen() == MenuBack.STORE and app.menu_back.entries() == [MenuBack.HOME, MenuBack.WARDROBE, MenuBack.STORE], "A double tap on Back goes back one screen: %s" % [app.menu_back.entries()])

## A history left behind (the player went Home another way) never sends a new visit's Back there.
func _stale_history() -> void:
	await _follow(MenuBack.SETTINGS, ["wardrobe row", "chip plus"])
	await _follow(MenuBack.HOME, ["chip plus"])
	_check(app.menu_back.entries() == [MenuBack.HOME, MenuBack.STORE], "The store from Home's chip starts its own history: %s" % [app.menu_back.entries()])
	app._back_on_screen()
	await process_frame
	_check(app.mode == "home", "and its Back goes Home")
