extends SceneTree
## Pollen from play and Home's Pollen chip (pollen boards 7b and 1):
## - Home's chip (kit/pollen_chip.gd, tested in test_pollen_chip.gd): the gain
##   after earning, worked out from what a chip last showed (never after a spend,
##   none on the first chip), and no plus while the shop is off;
## - the page: loading, offline with Try again, the bank with its rules, an
##   empty bank's tail in the server's numbers, recent turns with their bonuses,
##   a bloom or why one paid a little, first clears paid or not, and the Full
##   Journey sentence left out on a build that names no Full Journey; it lays
##   out inside the screen at 1280x720, 1600x738 and 800x360;
## - the flow: opens from Home, Settings or the Pollen store and goes back there, reads once per
##   opening, and the chip opens the page while the shop is off;
## - purchases (pollen boards 1 and 2, Batch D): the history's purchases checked
##   (and read from older servers' entries), the Purchases card with the money
##   spent, each bundle and refund with its receipt line, its empty and loading
##   states inside the screen at every size, and the page lists them only on a
##   build that sells bundles (never iPhone or a build without bundles).
const Page = preload("res://presentation/pollen_play_page.gd")
const Flow = preload("res://presentation/pollen_play_flow.gd")
const PollenChip = preload("res://presentation/kit/pollen_chip.gd")
const PollenHistory = preload("res://services/pollen_history.gd")
const PollenSurfaces = preload("res://services/pollen_surfaces.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const HomeMenu = preload("res://presentation/home_menu.gd")
const HomeStage = preload("res://presentation/home_stage.gd")
const Wardrobe = preload("res://services/wardrobe.gd")
const PurchasesView = preload("res://presentation/pollen_purchases_view.gd")

const SIZES := [Vector2i(1280, 720), Vector2i(1561, 720), Vector2i(1600, 720)]

class FakeWallet:
	extends RefCounted
	var balance := 24000
	func wallet(_server: String, _owner: String) -> Dictionary:
		return {"balance": balance, "earned": balance, "bank": 15}

class FakeClient:
	extends RefCounted
	var wallet := FakeWallet.new()
	var on := true
	var answer: Dictionary = {}
	var reads := 0
	func scope() -> Dictionary:
		return {"server": "https://synthetic.invalid", "owner": "OOOOOOOOOOOOOOOOOOOOOO"} if on else {}
	func history() -> Dictionary:
		reads += 1
		await Engine.get_main_loop().process_frame
		return answer.duplicate(true)

class FakeWardrobe:
	extends RefCounted
	var selling := false
	func shop(_server: String, _owner: String) -> bool: return selling
	func bundles(_server: String, _owner: String) -> bool: return selling

class Host:
	extends Node
	var pollen_client := FakeClient.new()
	var mode := "home"
	var running := false
	var overlay := Control.new()
	var title_font: Font = null
	func _init() -> void:
		overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(overlay)
	func _clear_overlay() -> void:
		for child: Node in overlay.get_children():
			overlay.remove_child(child)
			child.queue_free()

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await _page_states()
	await _flow()
	await _home_slot()
	_purchase_history()
	await _purchase_card()
	await _purchase_flow()
	print("AFTER YOU POLLEN PLAY: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

static func _history(left: int = 15) -> Dictionary:
	return PollenHistory.checked({"schema_version": 1.0, "entries": [
		{"kind": "turn", "amount": 250.0, "at": 3.0, "level_id": "relay-isles", "stage_id": "relay", "role": "a", "bonuses": ["first_try", "gold_pace"], "bloom": 2.0},
		{"kind": "turn", "amount": 185.0, "at": 2.0, "level_id": "relay-isles", "stage_id": "garden", "role": "b", "bonuses": ["first_try"]},
		{"kind": "turn", "amount": 10.0, "at": 1.0, "level_id": "relay-isles", "stage_id": "garden", "role": "b", "reason": "repeat"}],
		"first_clears": [{"level_id": "first-steps", "price": 1200.0, "paid": 1200.0}, {"level_id": "relay-isles", "price": 1200.0}, {"level_id": "conservatory", "price": 2000.0}],
		"bank": {"left": float(left), "refill": 12.0, "cap": 36.0, "tail": [{"pay": 10.0, "turns": 36.0}, {"pay": 1.0, "turns": 64.0}]}})

func _viewport(size: Vector2i) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = size
	root.add_child(viewport)
	return viewport

func _page_states() -> void:
	for size: Vector2i in SIZES:
		var viewport := _viewport(size)
		var page := Page.new()
		viewport.add_child(page)
		page.render({"chip": PollenChip.make(24000, false), "full_journey": true, "status": PlayerCopy.POLLEN_PLAY_LOADING, "retry": false, "history": {}})
		await _settle()
		_check(_texts(page).has(PlayerCopy.POLLEN_PLAY_LOADING) and page.find_child("PollenPlayRetry", true, false) == null, "Loading says so, with no Try again")
		page.render({"chip": PollenChip.make(24000, false), "full_journey": true, "status": PlayerCopy.POLLEN_PLAY_OFFLINE, "retry": true, "history": {}})
		await _settle()
		_check(page.find_child("PollenPlayRetry", true, false) != null, "Offline offers Try again")
		page.render({"chip": PollenChip.make(24000, false), "full_journey": true, "status": "", "retry": false, "history": _history()})
		await _settle()
		var texts := _texts(page)
		_check((page.find_child("PollenBankLeft", true, false) as Label).text == "15" and texts.has("+12 every Monday") and texts.has("holds up to 36") and is_equal_approx((page.find_child("PollenBankBar", true, false) as ProgressBar).value, 15.0), "The bank: turns left, the Monday refill and the cap, from the server: " + str(texts))
		_check(texts.has("The Relay Isles, stage 1") and texts.has("First try · gold pace") and texts.has("The Relay Isles, stage 2") and texts.has(PlayerCopy.POLLEN_TURN_REPEAT), "Recent turns name the place, their bonuses, and why one paid a little")
		_check(page.find_children("PollenBloomTag", "", true, false).size() == 1, "A bloomed turn carries its small flower tag")
		_check(texts.has("+1,200 earned") and page.find_children("*PollenClearRow*", "", true, false).size() == 2 and texts.has(PlayerCopy.POLLEN_CLEARS_FULL_JOURNEY + " " + PlayerCopy.POLLEN_CLEARS_HARD), "First clears: paid and not, free chapters only, with the Full Journey sentence: " + str(texts))
		_check(page.find_child("PollenBankTail", true, false) == null, "A bank with turns left needs no tail line")
		_layout(page, size, "the full page")
		page.render({"chip": PollenChip.make(24000, false), "full_journey": false, "status": "", "retry": false, "history": _history(0)})
		await _settle()
		texts = _texts(page)
		var tail := page.find_child("PollenBankTail", true, false) as Label
		_check(texts.has(PlayerCopy.POLLEN_BANK_EMPTY_LINE) and tail != null and tail.text == "After the bank runs out, each turn earns 10 for the next 36 turns, then 1 for the next 64, then nothing until Monday, when the bank gains 12 more turns.", "An empty bank says what turns still earn, in the server's numbers: " + (tail.text if tail != null else "none"))
		_check(texts.has(PlayerCopy.POLLEN_CLEARS_HARD) and not texts.any(func(text: String) -> bool: return text.contains("Full Journey")), "A build that names no Full Journey leaves its sentence out")
		_layout(page, size, "the page with an empty bank")
		viewport.queue_free()
		await _settle()

## Every label inside the screen, and a short one on one row.
func _layout(page: Control, size: Vector2i, context: String) -> void:
	var screen := Rect2(Vector2.ZERO, Vector2(size))
	for label: Label in page.find_children("*", "Label", true, false):
		if not label.is_visible_in_tree(): continue
		var rect := label.get_global_rect()
		var inside := screen.grow(0.5).encloses(rect)
		var scroll := label.get_parent()
		while scroll != null and not scroll is ScrollContainer: scroll = scroll.get_parent()
		if scroll != null: inside = inside or not (scroll as ScrollContainer).get_global_rect().intersects(rect)
		_check(inside, "'%s' stays inside the screen in %s at %s" % [label.text, context, size])
		if label.autowrap_mode == TextServer.AUTOWRAP_OFF: continue
		_check(label.get_line_count() <= 4 and label.size.x >= 120.0, "'%s' wraps by words, %d wide, in %s at %s" % [label.text, label.size.x, context, size])

func _flow() -> void:
	PollenSurfaces.set_shared_for_tests(true)
	var viewport := _viewport(SIZES[1])
	var host := Host.new()
	viewport.add_child(host)
	var flow := Flow.new(host)
	host.add_child(flow)
	host.pollen_client.answer = _history()
	Flow.forget_shown()
	var back: Array = []
	flow.back_requested.connect(func() -> void: back.append(flow.return_to))
	flow.open_from_home()
	_check(host.mode == Flow.MODE and _texts(host.overlay).has(PlayerCopy.POLLEN_PLAY_LOADING), "Opening shows the page at once, loading")
	await _settle()
	_check(host.pollen_client.reads == 1 and _texts(host.overlay).has("+12 every Monday"), "It reads the history once and draws it")
	(host.overlay.find_child("PollenPlayBack", true, false) as Button).pressed.emit()
	flow.open_from_settings()
	await _settle()
	(host.overlay.find_child("PollenPlayBack", true, false) as Button).pressed.emit()
	flow.open_from_store()
	await _settle()
	(host.overlay.find_child("PollenPlayBack", true, false) as Button).pressed.emit()
	_check(back == ["home", "settings", "store"] and host.pollen_client.reads == 3, "Back goes where it opened from; each opening reads once: " + str(back))
	host.pollen_client.answer = {}
	flow.open_from_home()
	await _settle()
	_check(_texts(host.overlay).has(PlayerCopy.POLLEN_PLAY_OFFLINE) and host.overlay.find_child("PollenPlayRetry", true, false) != null, "A read that fails offers Try again")
	host.pollen_client.answer = _history()
	(host.overlay.find_child("PollenPlayRetry", true, false) as Button).pressed.emit()
	await _settle()
	_check(_texts(host.overlay).has("+12 every Monday"), "Try again reads again")
	_check(host.overlay.find_child("PollenChip", true, false) != null, "The page's header shows the chip")
	# Home's chip: the gain after earning, from what a chip last showed.
	var gains: Array = []
	for balance: int in [24000, 24125, 23000, 23000]:
		host.pollen_client.wallet.balance = balance
		var made := flow.chip()
		gains.append(made.gain_label.text if made.gain_label.visible else "")
		made.free()
	_check(gains == ["", "+125", "", ""], "The gain shows just after earning, never after a spend or on the first chip: " + str(gains))
	# While the shop is off it opens this page, and no plus shows.
	PollenSurfaces.set_shared_for_tests(false)
	host._clear_overlay()
	host.mode = "home"
	await _settle()
	var chip := flow.chip()
	_check(chip != null and chip.plus_icon == null, "A build that sells nothing shows the chip without its plus")
	chip.pressed.emit()
	_check(host.mode == Flow.MODE, "The chip opens Pollen from play")
	chip.free()
	host.pollen_client.on = false
	_check(flow.chip() == null and not flow.available(), "No chip and no page while the server has Pollen off")
	PollenSurfaces.set_shared_for_tests(null)
	viewport.queue_free()
	await _settle()

## Home's chip sits left of Full Journey, or in its place while it is hidden.
func _home_slot() -> void:
	for size: Vector2i in SIZES:
		var viewport := _viewport(size)
		var holder := Control.new()
		holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		viewport.add_child(holder)
		var menu := HomeMenu.new()
		holder.add_child(menu)
		var noop := func() -> void: pass
		menu.build({"play": func(_button: Button) -> void: pass, "solo": noop, "friends": noop, "replays": noop, "invite": noop, "whats_new": noop, "settings": noop, "full_journey": noop}, HomeStage.heading_font())
		menu.set_pollen_chip(PollenChip.make(24000, true))
		await _settle()
		var chip := menu.pollen_slot.get_child(0) as Control
		var journey := menu.journey_offer.get_global_rect()
		_check(chip.get_global_rect().end.x <= journey.position.x - 8.0 and absf(chip.get_global_rect().get_center().y - journey.get_center().y) <= 1.0 and Rect2(Vector2.ZERO, Vector2(size)).encloses(chip.get_global_rect()), "The chip sits left of Full Journey, level with it, at %s: %s %s" % [size, chip.get_global_rect(), journey])
		menu.journey_offer.visible = false
		await _settle()
		_check(absf(chip.get_global_rect().end.x - (size.x - HomeMenu.RIGHT)) <= 1.0, "With Full Journey hidden the chip takes its place at %s" % size)
		viewport.queue_free()
		await _settle()

const PURCHASES := [
	{"kind": "bundlerefund", "amount": -21000.0, "at": 1.80e12 + 3000.0, "bundle": "pouch", "order": "GPA.1234-5678-9012-34567", "usd_cents": 399.0},
	{"kind": "bundle", "amount": 115000.0, "at": 1.80e12 + 2000.0, "bundle": "basket", "order": "GPA.2222-3333-4444-55555", "usd_cents": 1999.0},
	{"kind": "bundle", "amount": 21000.0, "at": 1.80e12 + 1000.0, "bundle": "pouch", "order": "GPA.1234-5678-9012-34567", "usd_cents": 399.0},
	{"kind": "bundle", "amount": 5000.0, "at": 1.80e12, "bundle": "pinch"}]

static func _with_purchases(lines: Array = PURCHASES, spent: Variant = 1999.0) -> Dictionary:
	var value := {"schema_version": 1.0, "entries": [], "first_clears": [], "purchases": lines}
	if spent != null: value.spent_usd_cents = spent
	return value

func _purchase_history() -> void:
	var kept := PollenHistory.checked(_with_purchases())
	_check(kept.purchases.size() == 4 and kept.spent_usd_cents == 1999 and kept.purchases[0].kind == "bundlerefund" and kept.purchases[0].amount == -21000 and kept.purchases[3].usd_cents == -1 and kept.purchases[3].order == "",
		"Purchases keep their order, a refund's negative Pollen and an unknown price as -1: " + str(kept.purchases))
	var bad := [{"kind": "bundle", "amount": 5000.0, "at": 1.0, "bundle": "chest"}, {"kind": "bundle", "amount": -5000.0, "at": 1.0, "bundle": "pinch"},
		{"kind": "bundlerefund", "amount": 5000.0, "at": 1.0, "bundle": "pinch"}, {"kind": "bundle", "amount": 5000.0, "at": 1.0, "bundle": "pinch", "order": "<b>x</b>"},
		{"kind": "turn", "amount": 5000.0, "at": 1.0, "bundle": "pinch"}, {"kind": "bundle", "amount": 5000.5, "at": 1.0, "bundle": "pinch"}, "pinch"]
	_check(PollenHistory.checked(_with_purchases(bad)).purchases.is_empty(), "A line off the contract is left out")
	# 1999 + 399 - 399, and the Pinch with no price adds nothing.
	_check(PollenHistory.checked(_with_purchases(PURCHASES, null)).spent_usd_cents == 1999, "Without the server's figure the money spent is the lines' sum, refunds taken off")
	_check(PollenHistory.checked(_with_purchases(range(101).map(func(_i: int) -> Dictionary: return PURCHASES[3]))).is_empty(), "A list longer than the server sends is refused")
	var older := PollenHistory.checked({"schema_version": 1.0, "entries": [{"kind": "turn", "amount": 250.0, "at": 3.0, "level_id": "relay-isles", "stage_id": "relay", "role": "a"}, PURCHASES[2]]})
	_check(older.turns.size() == 1 and older.purchases.size() == 1 and older.purchases[0].bundle == "pouch" and older.spent_usd_cents == 399, "An older server's history: its bundle entries are the purchases, its turns stay turns")
	_check(PollenHistory.checked({"schema_version": 1.0, "entries": []}).purchases.is_empty(), "No purchases reads as none")
	_check(PurchasesView.receipt_line({"usd_cents": 399, "order": "GPA.1"}) == PlayerCopy.POLLEN_STORE_ORDER % ["$3.99", "GPA.1"] and PurchasesView.receipt_line({"usd_cents": -1, "order": "GPA.1"}) == PlayerCopy.POLLEN_STORE_ORDER_ONLY % "GPA.1"
		and PurchasesView.receipt_line({"usd_cents": 99, "order": ""}) == "$0.99", "The receipt line is the store receipt's Paid line, from what the server kept")

func _purchase_card() -> void:
	for size: Vector2i in SIZES + [Vector2i(1600, 738)]:
		var viewport := _viewport(size)
		var page := Page.new()
		viewport.add_child(page)
		var history := _history()
		var bought := PollenHistory.checked(_with_purchases())
		history.purchases = bought.purchases
		history.spent_usd_cents = bought.spent_usd_cents
		page.render({"chip": PollenChip.make(24000, true), "full_journey": true, "status": "", "retry": false, "history": history, "purchases": true})
		await _settle()
		var texts := _texts(page)
		var card := page.find_child("PollenPurchasesCard", true, false) as Control
		_check(card.visible and (page.find_child("PollenPlayTitle", true, false) as Label).text == PlayerCopy.SETTINGS_POLLEN_PURCHASES, "The page is Pollen and purchases, with its Purchases card first at %s" % size)
		_check((page.find_child("PollenPurchasesSpent", true, false) as Label).text == "$19.99" and texts.has(PlayerCopy.POLLEN_PURCHASES_SPENT) and texts.has(PlayerCopy.POLLEN_PURCHASES_USD), "The money spent, in US dollars")
		_check(page.find_children("PollenPurchaseRow*", "", true, false).size() == 4 and texts.has(PlayerCopy.POLLEN_PURCHASE_REFUNDED % "Pouch") and texts.has("Basket") and texts.has("Pinch")
			and texts.has(PlayerCopy.POLLEN_STORE_ORDER % ["$19.99", "GPA.2222-3333-4444-55555"]), "Each bundle and refund with its receipt line: " + str(texts))
		_check(page.find_child("PollenPurchaseRow0", true, false).find_children("BundleArt", "", true, false).size() == 1, "A purchase row has its bundle's art")
		_layout(page, size, "the page with purchases")
		page.render({"chip": PollenChip.make(0, true), "full_journey": true, "status": "", "retry": false, "history": PollenHistory.checked({"schema_version": 1.0, "entries": []}), "purchases": true})
		await _settle()
		_check(page.find_child("PollenPurchasesNone", true, false) != null and page.find_child("PollenPurchasesTotal", true, false) == null, "No purchases yet, and no total")
		page.render({"chip": null, "full_journey": true, "status": PlayerCopy.POLLEN_PLAY_LOADING, "retry": false, "history": {}, "purchases": true})
		await _settle()
		_check(card.visible and _texts(card).has(PlayerCopy.POLLEN_PURCHASES_TITLE) and page.find_child("PollenPurchasesNone", true, false) == null, "Loading: the card keeps its title and shows nothing it does not know")
		page.render({"chip": null, "full_journey": true, "status": "", "retry": false, "history": _history(), "purchases": false})
		await _settle()
		_check(not card.visible and (page.find_child("PollenPlayTitle", true, false) as Label).text == PlayerCopy.POLLEN_PLAY_TITLE, "Without purchases it is Pollen from play, as before")
		viewport.queue_free()
		await _settle()

func _purchase_flow() -> void:
	var store := FakeWardrobe.new()
	Wardrobe.use_shared(store)
	var viewport := _viewport(SIZES[1])
	var host := Host.new()
	viewport.add_child(host)
	var flow := Flow.new(host)
	host.add_child(flow)
	host.pollen_client.answer = PollenHistory.checked(_with_purchases())
	for build: Array in [[true, true, true, "a Google Play build while bundles sell"], [false, false, false, "iPhone"], [true, false, false, "a build without bundles"]]:
		PollenSurfaces.set_shared_for_tests(build[0], build[1])
		flow.surfaces = null
		store.selling = true
		_check(flow.purchases_shown() == build[2], "The row and page list purchases on %s: %s" % [build[3], build[2]])
		flow.open_from_settings()
		await _settle()
		var card := host.overlay.find_child("PollenPurchasesCard", true, false) as Control
		_check(card != null and card.visible == build[2], "The Purchases card on %s: %s" % [build[3], build[2]])
		var money := _texts(host.overlay).any(func(text: String) -> bool: return text.contains("$") or text.contains("Google Play"))
		_check(money == build[2], "%s: money shows only with purchases" % build[3])
	# Bundles off later: a player who bought still sees them once the history says so.
	PollenSurfaces.set_shared_for_tests(true, true)
	flow.surfaces = null
	store.selling = false
	_check(not flow.purchases_shown(), "With bundles off the Settings row is Pollen")
	flow.open_from_settings()
	await _settle()
	_check((host.overlay.find_child("PollenPurchasesCard", true, false) as Control).visible, "but a history with purchases still lists them")
	host.pollen_client.answer = {}
	flow.open_from_settings()
	await _settle()
	_check(not (host.overlay.find_child("PollenPurchasesCard", true, false) as Control).visible and _texts(host.overlay).has(PlayerCopy.POLLEN_PLAY_OFFLINE), "Offline with bundles off: no card, the page says so")
	store.selling = true
	flow.open_from_settings()
	await _settle()
	var offline := host.overlay.find_child("PollenPurchasesCard", true, false) as Control
	_check(offline.visible and host.overlay.find_child("PollenPurchasesNone", true, false) == null and host.overlay.find_child("PollenPlayRetry", true, false) != null, "Offline while bundles sell: the card's title, no guess, and Try again")
	PollenSurfaces.set_shared_for_tests(null)
	Wardrobe.use_shared(null)
	viewport.queue_free()
	await _settle()

static func _texts(node: Node) -> Array:
	return node.find_children("*", "Label", true, false).filter(func(label: Label) -> bool: return label.is_visible_in_tree()).map(func(label: Label) -> String: return label.text)

func _settle() -> void:
	for frame in range(4): await process_frame

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
