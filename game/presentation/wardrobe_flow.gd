extends Node
## The Wardrobe (POLLEN-RULES.md "The shop", boards 5b and 10): the page, its
## confirm and short-of-Pollen cards, buying and wearing. The server decides
## what is sold and holds what is owned and worn (services/wardrobe_client.gd);
## this flow only shows the last confirmed answer and sends what the player asks.
##
## Main hosts it as a child and reads Main only through this host contract
## (read at call time, so Main or a test can swap a service):
## - services: api, _names_scope, saves (reduced motion), _paid_content_hidden
## - screen: mode, running, overlay (the page's parent), ui (the cards' parent),
##   _clear_overlay, _toast, and _mark_screen_back when Main has it (Android Back)
## It asks Main to leave through back_requested. Settings opens it with
## show_wardrobe() when available(), and the display name flow calls refresh()
## after a saved change.
##
## Never shown on a build that hides paid content (Purchases.paid_content_hidden):
## that build still earns, and its balance waits on the server.
## Hooks for later phases: reaction packs (owned `packs`, the server's
## `offered_packs`) and sets (`sets`) are kept by services/wardrobe.gd and
## priced by the server, but no pack or set exists yet, so the page lists
## items only. "Get Pollen" joins the short card with bundles (Phase 6).
const Wardrobe = preload("res://services/wardrobe.gd")
const WardrobeClient = preload("res://services/wardrobe_client.gd")
const PollenWallet = preload("res://services/pollen_wallet.gd")
const Catalog = preload("res://services/cosmetic_catalog.gd")
const Outfit = preload("res://services/outfit.gd")
const FeaturedShelf = preload("res://services/featured_shelf.gd")
const ChapterRegistry = preload("res://services/chapter_registry.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const Page = preload("res://presentation/wardrobe_page.gd")
const Sheets = preload("res://presentation/wardrobe_sheets.gd")

const MODE_WARDROBE := "wardrobe"

signal back_requested

var host: Node
var client: RefCounted
var _page: Page
var _sheet: WeakRef = null
var _tab := "all"
var _selected := ""
var _status := ""
var _retry := false
## Tests: the week the shelf shows (-1: this week on the phone's clock).
var week := -1

func _init(main: Node = null) -> void:
	host = main

func _client() -> RefCounted:
	if client == null:
		client = WardrobeClient.new(host.api, host._names_scope)
		client.changed.connect(_redraw)
	return client

## Whether Settings may offer the Wardrobe: the server has the shop on for this
## player and the build shows paid content.
func available() -> bool:
	if host == null or (host.has_method("_paid_content_hidden") and host._paid_content_hidden()): return false
	return not _client().scope().is_empty()

func is_open() -> bool:
	return is_instance_valid(_page) and _page.is_inside_tree() and not _page.is_queued_for_deletion()

func show_wardrobe() -> void:
	if not available(): return
	host.running = false
	host.mode = MODE_WARDROBE
	host._clear_overlay()
	var reduced: bool = bool(host.saves.data.settings.get("reduced_motion", false)) if host.get("saves") != null else false
	_page = Page.new(reduced)
	_page.back_pressed.connect(func() -> void: back_requested.emit())
	_page.tab_chosen.connect(set_tab)
	_page.item_chosen.connect(select)
	_page.action_pressed.connect(act)
	_page.retry_pressed.connect(refresh)
	host.overlay.add_child(_page)
	if host.has_method("_mark_screen_back"): host._mark_screen_back(_page.back_button)
	_tab = "all"
	_selected = ""
	_status = PlayerCopy.WARDROBE_LOADING if _view().is_empty() else ""
	_retry = false
	_redraw()
	refresh()

## Reads the wardrobe again; the page redraws with the answer.
func refresh() -> void:
	if _client().scope().is_empty(): return
	var answer: Dictionary = await _client().refresh()
	if answer.get("code", "") == "busy": return
	var nothing := _view().is_empty()
	_status = PlayerCopy.WARDROBE_OFFLINE if not answer.get("ok", false) and nothing else ""
	_retry = not _status.is_empty()
	_redraw()

func set_tab(tab: String) -> void:
	_tab = tab if tab in ["all", "owned"] else "all"
	_redraw()

func select(id: String) -> void:
	_selected = id if Catalog.has(id) else ""
	_redraw()

## The picked item's button: buy it, or wear it or take it off when owned.
func act(id: String) -> void:
	var entry := _entry(id)
	if entry.is_empty() or _client().busy(): return
	if bool(entry.owned):
		await _wear(entry)
		return
	if not bool(entry.sold) or bool(entry.locked): return
	var balance := _balance()
	_close_sheet()
	var parent: Control = host.ui
	var opener: Control = _page.action_button if is_open() else null
	if balance < int(entry.price): _sheet = weakref(Sheets.short(parent, str(entry.name), int(entry.price), balance, opener))
	else: _sheet = weakref(Sheets.confirm(parent, str(entry.name), int(entry.price), balance, func() -> void: confirm_buy(id, int(entry.price)), opener))

## The confirm card's Buy: sends the purchase at the cost the card showed.
func confirm_buy(id: String, cost: int) -> void:
	_close_sheet()
	var answer: Dictionary = await _client().buy("item", id, cost)
	if answer.get("ok", false): _toast(PlayerCopy.WARDROBE_BOUGHT % Catalog.display_name(id))
	else: _toast(str(PlayerCopy.WARDROBE_ERRORS.get(str(answer.get("code", "")), PlayerCopy.WARDROBE_ERROR)))
	_redraw()

func _wear(entry: Dictionary) -> void:
	var look: Dictionary = _view().get("look", {}).duplicate()
	if bool(entry.worn): look.erase(str(entry.slot))
	else: look[str(entry.slot)] = str(entry.id)
	var answer: Dictionary = await _client().wear(look)
	if not answer.get("ok", false): _toast(str(PlayerCopy.WARDROBE_ERRORS.get(str(answer.get("code", "")), PlayerCopy.WARDROBE_ERROR)))
	_redraw()

## The page's model (presentation/wardrobe_page.gd), from the kept wardrobe and wallet.
func model() -> Dictionary:
	var view := _view()
	var owned: Array = view.get("items", [])
	var look: Dictionary = view.get("look", {})
	var unlocked: Array = view.get("unlocked", [])
	var items: Array = []
	var by_tier := {}
	for id: String in Catalog.ids():
		var mine := id in owned
		# The server's catalogue decides what shows: offered items, and earned ones once owned.
		if not mine and not id in view.get("offered", []): continue
		if Catalog.slot(id).is_empty(): continue
		var sold := Catalog.sold(id) and id in view.get("offered", [])
		var unlock := Catalog.unlock(id)
		var entry := {"id": id, "name": Catalog.display_name(id), "tier": Catalog.tier(id), "slot": Catalog.slot(id), "price": Catalog.price(id),
			"owned": mine, "worn": look.get(Catalog.slot(id)) == id, "sold": sold, "locked": not mine and not unlock.is_empty() and not id in unlocked,
			"unlock_name": _chapter_name(unlock)}
		items.append(entry)
		if sold: (by_tier.get_or_add(entry.tier, []) as Array).append(id)
	var preview := Outfit.from(look)
	var picked := _entry_in(items, _selected)
	if not picked.is_empty() and not bool(picked.worn): preview[str(picked.slot)] = str(picked.id)
	return {"balance": _balance(), "status": _status, "retry": _retry, "tab": _tab, "selected": _selected, "preview": Outfit.from(preview),
		"featured": FeaturedShelf.shelf(week if week >= 0 else FeaturedShelf.this_week(), by_tier).map(func(slot: Dictionary) -> String: return slot.id), "items": items}

func _redraw() -> void:
	if is_open(): _page.render(model())

func _view() -> Dictionary:
	var scope: Dictionary = _client().scope()
	return {} if scope.is_empty() else _client().store.view(str(scope.server), str(scope.owner))

func _balance() -> int:
	var scope: Dictionary = _client().scope()
	if scope.is_empty(): return -1
	var wallet: Dictionary = _client().wallet.wallet(str(scope.server), str(scope.owner))
	return int(wallet.get("balance", -1)) if not wallet.is_empty() else -1

func _entry(id: String) -> Dictionary:
	return _entry_in(model().items, id)

static func _entry_in(items: Array, id: String) -> Dictionary:
	for entry: Dictionary in items:
		if entry.id == id: return entry
	return {}

## Chapter titles by level id, worked out once (a descriptor reads its definition).
static var _chapter_names: Dictionary = {}

## A chapter's title by its level id (any version), for a Special's unlock line.
static func _chapter_name(level_id: String) -> String:
	if level_id.is_empty(): return ""
	if not _chapter_names.has(level_id):
		_chapter_names[level_id] = level_id
		for key: String in ChapterRegistry.keys():
			var descriptor: Dictionary = ChapterRegistry.descriptor(key)
			if str(descriptor.get("level_id", "")) == level_id:
				_chapter_names[level_id] = str(descriptor.get("title", level_id))
				break
	return str(_chapter_names[level_id])

func _close_sheet() -> void:
	var open: Variant = _sheet.get_ref() if _sheet != null else null
	if open is Control and is_instance_valid(open) and open.has_method("close"): open.close(false)
	_sheet = null

func _toast(text: String) -> void:
	if host != null and host.has_method("_toast"): host._toast(text)
