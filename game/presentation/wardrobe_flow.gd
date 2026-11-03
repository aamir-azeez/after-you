extends Node
## The Wardrobe (POLLEN-RULES.md "The shop", boards 5b and 10): the page, its
## confirm and short-of-Pollen cards, buying and wearing. The server decides
## what is sold and holds what is owned and worn (services/wardrobe_client.gd);
## this flow only shows the last confirmed answer and sends what the player asks.
##
## Main hosts it as a child and reads Main only through this host contract
## (read at call time, so Main or a test can swap a service):
## - services: api, _names_scope, saves (reduced motion)
## - screen: mode, running, overlay (the page's parent), ui (the cards' parent),
##   _clear_overlay, _toast, and _mark_screen_back when Main has it (Android Back)
## - soundscape when Main has it (play_fixed_cue): worn, taken off and bought.
##   wear_item() stays quiet: its caller (a room's Wear it) sounds it on its own.
## - pollen_store_flow when Main has it: its `purchase` engine, through which
##   the short card buys the bundle it suggests.
## It asks Main to leave through back_requested. Settings opens it with
## show_wardrobe() when available(), and the display name flow calls refresh()
## after a saved change.
##
## What the build shows comes from services/pollen_surfaces.gd, and what the
## server has on from its capabilities (services/wardrobe.gd): the Wardrobe
## needs POLLEN_WARDROBE, the shop POLLEN_SHOP too. Without the shop (a build
## that sells nothing, as iOS without a store, or a server with the shop off)
## the Wardrobe only wears what the player owns, earned items and item bloom
## drops, with the balance: no shelf of the week, no price and no Buy. Its All
## items tab shows only while an earned item the player does not own is
## offered, and it opens on Owned once the player owns something.
## Until the player picks a tab, the page opens on All items with the shop,
## and on any build while the player owns nothing yet (owner, 2026-11-03), so
## an empty Owned is never the first thing shown; Owned stays one tap away
## (_start_tab, read on every draw until the player touches the page, so an
## answer that comes after opening, such as the first read or the shop's
## switch, still decides it; _keep_tab).
## Earned items (catalogue tier "earned") show in All items once the server
## offers them, owned or not, so players know they exist: never sold, never on
## the shelf, never counted as something to buy (Get more, the short card).
## Picking one the player does not own puts it on the big pip and says how it
## is earned (services/cosmetic_catalog.gd earn).
## While bundles sell too (the server's POLLEN_BUNDLES and a build that sells
## them, services/pollen_surfaces.gd bundles_visible), the balance chip's + asks
## the host to open the Pollen store (store_requested), and the short card
## buys the bundle it suggests in place, at the store's price: once that Pollen
## arrives the item's confirm card opens on the new balance, so the item still
## takes its own Buy tap.
## The chip's balance asks for the Pollen page (pollen_requested).
## Hooks for later phases: reaction packs (owned `packs`, the server's
## `offered_packs`) and sets (`sets`) are kept by services/wardrobe.gd and
## priced by the server. The page lists items only: the Faces tab is still to
## build (its hooks are services/face_packs.gd faces_tab_visible and pack_rows),
## and no set exists yet.
##
## Offline (services/connectivity.gd) the Wardrobe still opens once this
## player has a wardrobe saved from an earlier read: what they own, what they
## wear and the catalogue as last saved. Wear and Take off work at once
## (services/wardrobe_client.gd sync sends them when the app is next online;
## friends see the new look after that). Buying needs the server: All items
## stays browsable with its last prices, and Buy greys with a line saying so.
## A player with nothing saved sees no Wardrobe offline (available).
##
## The main button goes through a BusyTapGate (presentation/busy_tap_gate.gd):
## a tap while the wardrobe is still being read waits for that read instead of
## being dropped, so the first tap always registers.
## `return_to` names where Back goes ("settings" or "home"); the host reads it.
const Wardrobe = preload("res://services/wardrobe.gd")
const WardrobeClient = preload("res://services/wardrobe_client.gd")
const PollenWallet = preload("res://services/pollen_wallet.gd")
const Catalog = preload("res://services/cosmetic_catalog.gd")
## Its confirmations sound on the host's soundscape (play_on).
const Soundscape = preload("res://services/soundscape.gd")
const Outfit = preload("res://services/outfit.gd")
const FeaturedShelf = preload("res://services/featured_shelf.gd")
const ChapterRegistry = preload("res://services/chapter_registry.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const Page = preload("res://presentation/wardrobe_page.gd")
const Sheets = preload("res://presentation/wardrobe_sheets.gd")
const PollenSurfaces = preload("res://services/pollen_surfaces.gd")
const BusyTapGate = preload("res://presentation/busy_tap_gate.gd")
const OfflineHold = preload("res://presentation/offline_hold.gd")

const MODE_WARDROBE := "wardrobe"

signal back_requested
## The balance chip's +: open the Pollen store.
signal store_requested
## The balance chip's balance: open the Pollen page.
signal pollen_requested

var host: Node
var client: RefCounted
## What this build shows (services/pollen_surfaces.gd); tests set their own.
var surfaces: RefCounted
var _page: Page
var _sheet: WeakRef = null
## The tab the player picked; empty until they pick one (_start_tab decides it).
var _tab := ""
var _selected := ""
var _kind := ""
var _view_mode := "you"
var _gate: BusyTapGate
## Where Back returns: "settings" (the default) or "home".
var return_to := "settings"
var _status := ""
## A look whose send got no answer while online goes again after these
## (RefreshSchedule's failure pace); tests set shorter ones.
var sync_retry_ms: Array = preload("res://services/refresh_schedule.gd").FAILURE_DELAYS_MS
## Sends of a pending look that got no answer while online, in a row (sync_retry_ms).
var _sync_misses := 0
var _retry := false
## Tests: the week the shelf shows (-1: this week on the phone's clock).
var week := -1

func _init(main: Node = null) -> void:
	host = main

func _client() -> RefCounted:
	if client == null: client = WardrobeClient.new(host.api, host._names_scope)
	if not client.changed.is_connected(_redraw): client.changed.connect(_redraw)
	return client

func _surfaces() -> RefCounted:
	if surfaces == null: surfaces = PollenSurfaces.shared()
	return surfaces

## Whether Settings and Home may offer the Wardrobe: the server has the
## wardrobe on for this player and the build shows the Wardrobe; offline, only
## while a wardrobe from an earlier read is saved (there is something to show).
func available() -> bool:
	if host == null or not _surfaces().wardrobe_visible(): return false
	if _client().scope().is_empty(): return false
	return _client().online() or not _view().is_empty()

func is_open() -> bool:
	return is_instance_valid(_page) and _page.is_inside_tree() and not _page.is_queued_for_deletion()

func show_wardrobe(from: String = "settings") -> void:
	if not available(): return
	return_to = from
	host.running = false
	host.mode = MODE_WARDROBE
	host._clear_overlay()
	var reduced: bool = bool(host.saves.data.settings.get("reduced_motion", false)) if host.get("saves") != null else false
	_page = Page.new(reduced)
	_page.back_pressed.connect(func() -> void: back_requested.emit())
	_page.tab_chosen.connect(set_tab)
	_page.kind_chosen.connect(set_kind)
	_page.view_chosen.connect(set_view)
	_page.item_chosen.connect(select)
	_page.more_chosen.connect(show_more)
	_page.action_pressed.connect(tap_action)
	_page.retry_pressed.connect(refresh)
	_page.plus_pressed.connect(func() -> void: if bundles(): store_requested.emit())
	_page.pollen_pressed.connect(func() -> void: pollen_requested.emit())
	host.overlay.add_child(_page)
	_gate = BusyTapGate.new(_page)
	if host.has_method("_mark_screen_back"): host._mark_screen_back(_page.back_button)
	_tab = ""
	_selected = ""
	_kind = ""
	_view_mode = "you"
	_status = PlayerCopy.WARDROBE_LOADING if _view().is_empty() else ""
	_retry = false
	_redraw()
	# Offline the saved wardrobe shows as it is; the read comes once the phone is back online (connectivity_changed).
	if _client().online(): refresh()

## The phone went offline or came back (Main follows services/connectivity.gd):
## a look put on offline is sent, and an open page reads again and redraws (Buy).
func connectivity_changed(online: bool) -> void:
	if host == null or _client().scope().is_empty(): return
	# A card left open (confirm, short of Pollen) would buy offline: it closes.
	if not online: _close_sheet()
	_redraw()
	if not online: return
	_sync_misses = 0
	await sync_pending()
	if is_open(): refresh()

## Sends a look put on and not confirmed yet (Main, after a Pollen flush and
## once the identity is read). Nothing while there is none.
func sync_pending() -> void:
	if host == null or _client().scope().is_empty(): return
	_after_sync(await _client().sync())

## A send that got no answer while the phone still reads as online (a server
## error, one timeout) goes again soon, a few times, instead of waiting for the
## next resume; offline, the connection coming back sends it.
func _after_sync(answer: Dictionary) -> void:
	if not answer.get("pending", false) or not _client().online() or _client().busy():
		if not answer.get("pending", false): _sync_misses = 0
		return
	if _sync_misses >= sync_retry_ms.size() or not is_inside_tree(): return
	var wait := float(sync_retry_ms[_sync_misses]) / 1000.0
	_sync_misses += 1
	get_tree().create_timer(wait).timeout.connect(sync_pending)

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
	_tab = _allowed_tab(tab if tab in ["all", "owned"] else "all", bool(model().all_items))
	_kind = ""
	_redraw()

## The Owned tab's Get more card: All items on slot `kind`, in one step, or on
## the first slot with something to buy when this one has nothing more (the
## earned leaves).
func show_more(kind: String) -> void:
	if not shop(): return
	var buyable := _buyable_slots(model().items)
	_tab = "all"
	_kind = kind if kind in buyable or buyable.is_empty() else str(buyable[0])
	if not _kind in Catalog.slots(): _kind = ""
	_redraw()

## The slots, in shop order, with something on sale the player does not own.
static func _buyable_slots(items: Array) -> Array:
	return Catalog.slots().filter(func(slot: String) -> bool: return items.any(func(entry: Dictionary) -> bool: return bool(entry.sold) and not bool(entry.owned) and entry.slot == slot))

## A slot chip: Hat, Body or Leaf.
func set_kind(kind: String) -> void:
	_keep_tab()
	_kind = kind if kind in Catalog.slots() else ""
	_redraw()

## The pip switch: "you", or "friend" (your pip in a friend's room: mint).
func set_view(view: String) -> void:
	_view_mode = view if view in ["you", "friend"] else "you"
	_redraw()

## The main button's tap: it waits for a wardrobe read or a purchase in flight
## (the gate), then acts on the item that was picked when it was tapped.
func tap_action(id: String) -> void:
	if not is_open() or _gate == null: return
	_gate.tap(_page.action_button, "", func() -> bool: return not _client().busy(), func() -> void: await act(id), func() -> bool: return is_open() and (_selected == id or _selected.is_empty()))

## The tab shown for the one asked for: Owned while All items does not show
## (`all_items`: the shop, or an earned item listed and not owned).
static func _allowed_tab(tab: String, all_items: bool) -> String:
	return "all" if tab == "all" and all_items else "owned"

## The player touched the page: the tab on screen stays, so a late answer never
## moves them off it (first taps register).
func _keep_tab() -> void:
	if _tab.is_empty(): _tab = str(model().tab)

## The tab shown before the player picks one: All items while the shop sells
## (`selling`) or the player owns nothing yet (`owns_any`), else Owned.
static func _start_tab(selling: bool, owns_any: bool) -> String:
	return "all" if selling or not owns_any else "owned"

func select(id: String) -> void:
	_keep_tab()
	_selected = id if Catalog.has(id) else ""
	_redraw()

## The picked item's button: buy it, or wear it or take it off when owned.
func act(id: String) -> void:
	var entry := _entry(id)
	if entry.is_empty() or _client().busy(): return
	if bool(entry.owned):
		await _wear(entry)
		return
	if not bool(entry.sold) or bool(entry.locked) or not shop(): return
	if not _client().online():
		_offline_reason()
		return
	# A balance the server has not said yet is read first; no card shows a guess.
	if not _balance_known():
		await refresh()
		if not _balance_known() or not is_open(): return
	var balance := _balance()
	_close_sheet()
	var parent: Control = host.ui
	var opener: Control = _page.action_button if is_open() else null
	if balance < int(entry.price):
		# The card suggests the smallest bundle that covers the gap and buys it in place.
		var card: Control = Sheets.short(parent, str(entry.name), str(entry.tier), int(entry.price), balance, _buyer(), _after_bundle.bind(id), opener, true, _view().get("bundles", {}))
		card.set_meta(&"short_for", id)
		_sheet = weakref(card)
	else: _sheet = weakref(Sheets.confirm(parent, id, str(entry.name), int(entry.price), balance, func() -> void: confirm_buy(id, int(entry.price)), opener))

## The Pollen store's purchase engine (presentation/bundle_purchase.gd) while bundles sell, else null.
func _buyer() -> Node:
	var store: Variant = host.get("pollen_store_flow") if host != null else null
	if not bundles() or not store is Object or not is_instance_valid(store) or not store.available(): return null
	return store.get("purchase")

## A bundle bought on item `id`'s short card arrived: while that card is still
## up, it closes and the item's card opens on the new balance (the confirm
## card, or the short card again when the bundle only got closer). Nothing is spent here.
func _after_bundle(id: String) -> void:
	var open: Variant = _sheet.get_ref() if _sheet != null else null
	if not open is Control or not is_instance_valid(open) or (open as Control).is_queued_for_deletion() or str((open as Control).get_meta(&"short_for", "")) != id: return
	_close_sheet()
	if not is_open(): return
	_redraw()
	await act(id)

## The confirm card's Buy: sends the purchase at the cost the card showed.
func confirm_buy(id: String, cost: int) -> void:
	_close_sheet()
	if not shop(): return
	if not _client().online():
		_offline_reason()
		_redraw()
		return
	var answer: Dictionary = await _client().buy("item", id, cost)
	if answer.get("ok", false):
		Soundscape.play_on(host, "ui_bought")
		_toast(PlayerCopy.WARDROBE_BOUGHT % Catalog.display_name(id))
	else: _toast(_error_line(str(answer.get("code", ""))))
	_redraw()

func _wear(entry: Dictionary) -> void:
	var look := _look()
	if bool(entry.worn): look.erase(str(entry.slot))
	else: look[str(entry.slot)] = str(entry.id)
	var answer: Dictionary = await _client().wear(look)
	if not answer.get("ok", false): _toast(_error_line(str(answer.get("code", ""))))
	else: Soundscape.play_on(host, "ui_taken_off" if bool(entry.worn) else "ui_worn")
	_after_sync(answer)
	_redraw()

## Wears one owned item in its slot, over the rest of the look: the results
## card's Wear it after an item bloom brought it. True once it is worn here
## (the server confirms it with the next sync when not at once).
func wear_item(id: String) -> bool:
	if not available() or Catalog.slot(id).is_empty(): return false
	var look := _look()
	look[Catalog.slot(id)] = id
	var answer: Dictionary = await _client().wear(look)
	_after_sync(answer)
	_redraw()
	return bool(answer.get("ok", false))

## Whether bundles sell: the build sells them and the server has them on.
func bundles() -> bool:
	return _surfaces().store_sells(_client().store, _client().scope())

## Whether the shop shows: the build sells and the server has the shop on.
func shop() -> bool:
	if not _surfaces().shop_visible(): return false
	var scope: Dictionary = _client().scope()
	return not scope.is_empty() and _client().store.shop(str(scope.server), str(scope.owner))

## The page's model (presentation/wardrobe_page.gd), from the kept wardrobe and wallet.
## Without the shop it lists only what the player owns, with no price.
func model() -> Dictionary:
	var selling := shop()
	var view := _view()
	var owned: Array = view.get("items", [])
	var look := _look()
	var unlocked: Array = view.get("unlocked", [])
	var prices: Dictionary = view.get("prices", {})
	var offered: Array = view.get("offered", [])
	var items: Array = []
	var by_tier := {}
	for id: String in Catalog.ids():
		var mine := id in owned
		# The server's catalogue decides what shows: what it sells, anything owned, and every earned item it offers.
		var sold: bool = selling and Catalog.sold(id) and id in offered
		var earned: bool = Catalog.tier(id) == Catalog.EARNED and id in offered
		if not mine and not sold and not earned: continue
		if Catalog.slot(id).is_empty(): continue
		var unlock := Catalog.unlock(id)
		var entry := {"id": id, "name": Catalog.display_name(id), "tier": Catalog.tier(id), "slot": Catalog.slot(id), "price": int(prices.get(id, Catalog.price(id))) if selling else 0,
			"owned": mine, "worn": look.get(Catalog.slot(id)) == id, "sold": sold, "locked": not mine and not unlock.is_empty() and not id in unlocked,
			"unlock_name": _chapter_name(unlock), "earn": Catalog.earn(id)}
		items.append(entry)
		if sold: (by_tier.get_or_add(entry.tier, []) as Array).append(id)
	var featured: Array = FeaturedShelf.shelf(week if week >= 0 else FeaturedShelf.this_week(), by_tier).map(func(slot: Dictionary) -> String: return slot.id) if selling else []
	# All items shows with the shop, and without it while an earned item is listed and not owned.
	var all_items: bool = selling or items.any(func(entry: Dictionary) -> bool: return entry.tier == Catalog.EARNED and not bool(entry.owned))
	var owns_any: bool = items.any(func(entry: Dictionary) -> bool: return bool(entry.owned))
	var tab := _allowed_tab(_tab if not _tab.is_empty() else _start_tab(selling, owns_any), all_items)
	# The slot chips list only slots with something in this tab; a chip with nothing left falls back to the first.
	var kinds: Array = []
	for slot: String in Catalog.slots():
		if items.any(func(entry: Dictionary) -> bool: return entry.slot == slot and (tab == "all" or bool(entry.owned))): kinds.append(slot)
	var listed: Array = items.filter(func(entry: Dictionary) -> bool: return tab == "all" or bool(entry.owned))
	var selected := _selected if not _entry_in(listed, _selected).is_empty() else _default_pick(listed, look, featured if tab == "all" else [])
	var picked := _entry_in(items, selected)
	# With no chip picked, the chip of the picked item's slot, so its card is on screen.
	var kind: String = _kind if _kind in kinds else (str(picked.slot) if not picked.is_empty() and picked.slot in kinds else (str(kinds[0]) if not kinds.is_empty() else ""))
	var preview := Outfit.from(look)
	if not picked.is_empty() and not bool(picked.worn): preview[str(picked.slot)] = str(picked.id)
	# Owned ends with Get more on every slot while the shop has anything the player does not own (show_more picks where it leads).
	var more := selling and tab == "owned" and not _buyable_slots(items).is_empty()
	var offline: bool = not _client().online()
	return {"balance": _balance() if _surfaces().wallet_visible() else -1, "balance_known": _surfaces().wallet_visible() and _balance_known(), "status": _status, "retry": _retry, "shop": selling, "all_items": all_items, "bundles": bundles() and not offline, "tab": tab, "kind": kind, "kinds": kinds,
		"buy_offline": selling and offline, "note": PlayerCopy.WARDROBE_OFFLINE_NOTE if offline and not view.is_empty() else "",
		"more": more, "selected": selected, "view": _view_mode, "preview": Outfit.from(preview), "featured": featured, "items": items}

## The item picked while the player has picked none: what they wear, else the
## shelf's top slot, else the first item the tab lists (`items`).
static func _default_pick(items: Array, look: Dictionary, featured: Array) -> String:
	for slot: String in Catalog.slots():
		if look.has(slot) and not _entry_in(items, str(look[slot])).is_empty(): return str(look[slot])
	if not featured.is_empty(): return str(featured.back())
	return str(items[0].id) if not items.is_empty() else ""


func _redraw() -> void:
	if is_open(): _page.render(model())

func _view() -> Dictionary:
	var scope: Dictionary = _client().scope()
	return {} if scope.is_empty() else _client().store.view(str(scope.server), str(scope.owner))

## What the player wears on this phone: a look put on and not confirmed yet, else the server's.
func _look() -> Dictionary:
	var scope: Dictionary = _client().scope()
	return {} if scope.is_empty() else _client().store.effective_look(str(scope.server), str(scope.owner))

## Why buying waits: the phone is offline. Asks the server once, so a connection that came back shows at once.
func _offline_reason() -> void:
	OfflineHold.refuse(_toast)

func _balance() -> int:
	var scope: Dictionary = _client().scope()
	if scope.is_empty(): return -1
	var wallet: Dictionary = _client().wallet.wallet(str(scope.server), str(scope.owner))
	return int(wallet.get("balance", -1)) if not wallet.is_empty() else -1

## Whether the server has said the balance (a refund may leave it below zero, even at -1).
func _balance_known() -> bool:
	var scope: Dictionary = _client().scope()
	return not scope.is_empty() and not _client().wallet.wallet(str(scope.server), str(scope.owner)).is_empty()

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

## A refusal's words. Without the shop, the ones that name buying or a price read plainly.
func _error_line(code: String) -> String:
	if not shop() and code in ["not_owned", "pollen_short", "pollen_price_changed"]: return PlayerCopy.WARDROBE_ERROR
	return str(PlayerCopy.WARDROBE_ERRORS.get(code, PlayerCopy.WARDROBE_ERROR))

func _close_sheet() -> void:
	var open: Variant = _sheet.get_ref() if _sheet != null else null
	if open is Control and is_instance_valid(open) and open.has_method("close"): open.close(false)
	_sheet = null

func _toast(text: String) -> void:
	if host != null and host.has_method("_toast"): host._toast(text)
