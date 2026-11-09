extends Node
## The two Fruit spends that are not Orchard items: Sunshine (Fruits board 7)
## and Turn Fruits into Pollen (board 8), from every place that offers them
## (the Pollen page's Sunshine card, the Fruits page, the store's Fruits tab).
## One path each, so the card, the refusals and the offline hold are the same
## wherever the player starts:
## - sunshine(): the shared Fruit confirm card (presentation/wardrobe_sheets.gd
##   confirm, with the sun in the pip's place: You have, Sunshine, You'll have
##   left) when the balance covers the price, else the shared short-of-Fruits
##   card (short_of); Buy sends services/wardrobe_client.gd buy_sunshine();
## - convert(): the convert card (presentation/fruit_convert_sheet.gd) when the
##   balance covers one step, else the short card for one step; its button sends
##   convert(n).
## A refusal reads as a plain line in the toast (error_line); a short answer
## opens the short card with the balance the server gave. Offline, nothing is
## sent and the reason shows (presentation/offline_hold.gd). Nothing here
## counts Fruits: the server answers, services/wallet_reply.gd keeps it, and
## the pages redraw from services/fruit_wallet.gd changed.
##
## Main hosts it as a child and reads Main only through: wardrobe_client() (the
## one client it shares with the Wardrobe; else api and _names_scope for its
## own), _toast, and get_fruits (the store on its Fruits tab).
const WardrobeClient = preload("res://services/wardrobe_client.gd")
const PollenSurfaces = preload("res://services/pollen_surfaces.gd")
const Soundscape = preload("res://services/soundscape.gd")
const PollenMoney = preload("res://services/pollen_money.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const Sheets = preload("res://presentation/wardrobe_sheets.gd")
const ConvertSheet = preload("res://presentation/fruit_convert_sheet.gd")
const SunMark = preload("res://presentation/kit/sun_mark.gd")
const OfflineHold = preload("res://presentation/offline_hold.gd")

const FRUITS := "fruits"
const SUNSHINE_ID := "sunshine"
const SUNSHINE_ART := 108.0

## A Fruit spend went through (the pages redraw from the Fruit store as well).
signal spent(kind: String)

var host: Node
## services/wardrobe_client.gd; made from the host on first use, tests set their own.
var client: RefCounted
## What this build shows (services/pollen_surfaces.gd); tests set their own.
var surfaces: RefCounted
## () -> void: opens the store on its Fruits tab (Main sets it), for the short card's Get Fruits.
var get_fruits: Callable
var _sheet: WeakRef = null

func _init(main: Node = null) -> void:
	host = main

func _client() -> RefCounted:
	# Main's one client, shared with the Wardrobe so one request at a time holds across Orchard buys, converting and Sunshine.
	if client == null: client = host.wardrobe_client() if host.has_method("wardrobe_client") else WardrobeClient.new(host.api, host._names_scope)
	return client

func _surfaces() -> RefCounted:
	if surfaces == null: surfaces = PollenSurfaces.shared()
	return surfaces

func _scope() -> Dictionary:
	return _client().scope()

## {server, owner} of the signed-in player while the wardrobe routes are on, else {}.
func scope() -> Dictionary:
	return _scope()

## The Fruits kept on this phone (services/fruit_wallet.gd) that every spend here feeds.
func fruits() -> RefCounted:
	return _client().fruits

## Reads the wallet (its Fruits part with it, through services/wallet_reply.gd). {ok, code}.
func refresh_wallet() -> Dictionary:
	return await _client().refresh()

## Whether Fruits show for the signed-in player.
func visible() -> bool:
	return _surfaces().fruits_visible(_client().fruits, _scope())

## Whether a new Sunshine is offered (the card's price button): Fruits show,
## none is left, the price is known and Fruit spending is not blocked. The
## balance is not asked: a short balance opens the short card.
func sunshine_offered() -> bool:
	if not visible(): return false
	var scope := _scope()
	var kept: Dictionary = _client().fruits.sunshine(str(scope.server), str(scope.owner))
	return not kept.is_empty() and int(kept.left) == 0 and int(kept.price) > 0 and not _client().fruits.blocked(str(scope.server), str(scope.owner))

## Sunshine bought from `parent` (the page the card opens over), from `opener`.
func sunshine(parent: Control, opener: Control = null) -> void:
	if not visible() or OfflineHold.refuse(_say_callable()): return
	var scope := _scope()
	var fruits: RefCounted = _client().fruits
	var kept: Dictionary = fruits.sunshine(str(scope.server), str(scope.owner))
	if kept.is_empty(): return
	if int(kept.left) > 0:
		_say(error_line("sunshine_active"))
		return
	if fruits.blocked(str(scope.server), str(scope.owner)):
		_say(error_line("fruits_blocked"))
		return
	var price := int(kept.price)
	var balance: int = fruits.balance(str(scope.server), str(scope.owner))
	_close_sheet()
	if balance < price:
		_short(parent, price, balance, opener)
		return
	var art := SunMark.make(SUNSHINE_ART, SunMark.ART)
	art.name = "SunshineConfirmArt"
	var modal: Control = Sheets.confirm(parent, SUNSHINE_ID, PlayerCopy.SUNSHINE_TITLE, price, balance, func() -> void: _buy_sunshine(parent, opener), opener, FRUITS, {}, art, PlayerCopy.SUNSHINE_NOTE)
	_sheet = weakref(modal)

func _buy_sunshine(parent: Control, opener: Control) -> void:
	_close_sheet()
	if _client().busy():
		_say(error_line("busy"))
		return
	var answer: Dictionary = await _client().buy_sunshine()
	var code := str(answer.get("code", ""))
	if answer.get("ok", false):
		Soundscape.play_on(host, "ui_bought")
		_say(PlayerCopy.SUNSHINE_BOUGHT % int(answer.receipt.get("sunshine_left", 0)))
		spent.emit(SUNSHINE_ID)
	elif code == "fruits_short" and is_instance_valid(parent) and parent.is_inside_tree():
		var scope := _scope()
		var kept: Dictionary = _client().fruits.sunshine(str(scope.server), str(scope.owner))
		_short(parent, int(kept.get("price", 0)), _client().fruits.balance(str(scope.server), str(scope.owner)), opener)
	else: _say(error_line(code))

## Turn Fruits into Pollen from `parent`, from `opener`.
func convert(parent: Control, opener: Control = null) -> void:
	if not visible() or OfflineHold.refuse(_say_callable()): return
	var scope := _scope()
	var fruits: RefCounted = _client().fruits
	var rules: Dictionary = fruits.convert_rules(str(scope.server), str(scope.owner))
	if rules.is_empty(): return
	if fruits.blocked(str(scope.server), str(scope.owner)):
		_say(error_line("fruits_blocked"))
		return
	var balance: int = fruits.balance(str(scope.server), str(scope.owner))
	_close_sheet()
	if balance < int(rules.step):
		_short(parent, int(rules.step), balance, opener)
		return
	var pollen := int(_client().wallet.wallet(str(scope.server), str(scope.owner)).get("balance", 0))
	var sheet: RefCounted = ConvertSheet.open(parent, rules, balance, pollen, func(count: int) -> void: _convert(parent, opener, count), opener, _say_callable())
	_sheet = weakref(sheet.modal)

func _convert(parent: Control, opener: Control, count: int) -> void:
	_close_sheet()
	if _client().busy():
		_say(error_line("busy"))
		return
	var answer: Dictionary = await _client().convert(count)
	var code := str(answer.get("code", ""))
	if answer.get("ok", false):
		Soundscape.play_on(host, "ui_bought")
		_say(PlayerCopy.FRUIT_CONVERT_DONE % [PollenMoney.grouped(count), PollenMoney.grouped(int(answer.receipt.get("pollen", 0)))])
		spent.emit(WardrobeClient.CONVERT)
	elif code == "fruits_short" and is_instance_valid(parent) and parent.is_inside_tree():
		var scope := _scope()
		_short(parent, count, _client().fruits.balance(str(scope.server), str(scope.owner)), opener)
	else: _say(error_line(code))

## The shared short-of-Fruits card for `cost` against `balance`, with Get Fruits while packs sell.
func _short(parent: Control, cost: int, balance: int, opener: Control) -> void:
	var scope := _scope()
	var fruits: RefCounted = _client().fruits
	var spec := {"currency": FRUITS, "cost": cost, "balance": balance, "offer": fruits.offer(str(scope.server), str(scope.owner)), "opener": opener}
	if get_fruits.is_valid() and _surfaces().fruit_packs_visible(fruits, scope): spec["get_fruits"] = get_fruits
	_sheet = weakref(Sheets.short_of(parent, spec))

## The plain line for a refusal code.
static func error_line(code: String) -> String:
	if PlayerCopy.FRUIT_SPEND_ERRORS.has(code): return str(PlayerCopy.FRUIT_SPEND_ERRORS[code])
	if PlayerCopy.ORCHARD_ERRORS.has(code): return str(PlayerCopy.ORCHARD_ERRORS[code])
	return str(PlayerCopy.WARDROBE_ERRORS.get(code, PlayerCopy.WARDROBE_ERROR))

## The card open now, or null (tests).
func sheet() -> Control:
	var open: Variant = _sheet.get_ref() if _sheet != null else null
	return open if open is Control and is_instance_valid(open) and open.is_inside_tree() else null

func _close_sheet() -> void:
	var open := sheet()
	if open != null and open.has_method("close"): open.close(false)
	_sheet = null

func _say_callable() -> Callable:
	return Callable(self, "_say")

func _say(text: String) -> void:
	if host != null and host.has_method("_toast"): host._toast(text)
