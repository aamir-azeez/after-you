extends SceneTree
## Pollen board 3 as built, through the real Main at the phone's 1600x738:
## - the Full Journey card's two cream panels (the room boost, then the monthly
##   Pollen with its explainer and ladder) in each state the server can be in,
##   after the chapter lines, taking no input, and the whole card on screen;
## - the ladder line for a new, a returning and a top step subscriber;
## - "Your monthly Pollen arrived" over Home with both pips in their joy face
##   while it is up (a doze never takes it over), and back to their own face
##   once it goes;
## - its first taps land: Done closes it at once, Open the Wardrobe closes it
##   and opens the Wardrobe;
## - an instalment the Wardrobe's own wallet read paid (the owner's 0.7.7 case)
##   shows once back on Home, and one paid while the store card is up waits for Home;
## - a build that names no Full Journey (iPhone without a store) shows neither
##   the panels nor the card;
## - with Fruits on (Fruits boards 5a and 5b): the monthly gifts as two tiles in
##   the same place, the Pollen tile and the plum Fruit tile with the server's
##   Fruits a month, the step they grow to and the welcome basket until it is
##   paid, the whole card on screen at 1600x738 and 1600x720; the monthly card
##   as "Your monthly gifts arrived" with both amounts and next month's two,
##   today's Pollen card whenever Fruits are off or the instalment brought none.
const Main = preload("res://tests/unlocked_main.gd")
const PlatformSupport = preload("res://services/platform_support.gd")
const Purchases = preload("res://services/purchases.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const Storage = preload("res://services/local_save.gd")
const Keepsakes = preload("res://services/home_keepsakes.gd")
const PollenWallet = preload("res://services/pollen_wallet.gd")
const PollenGrant = preload("res://services/pollen_grant.gd")
const PollenSurfaces = preload("res://services/pollen_surfaces.gd")
const Benefits = preload("res://presentation/full_journey_benefits.gd")
const GrantCard = preload("res://presentation/pollen_grant_card.gd")
const SpiritLook = preload("res://presentation/spirit_look.gd")
const Wardrobe = preload("res://services/wardrobe.gd")
const WardrobeClient = preload("res://services/wardrobe_client.gd")
const FruitWallet = preload("res://services/fruit_wallet.gd")

const SIZE := Vector2i(1600, 738)
const TESTER_ONLY := {"purchase_mode": "tester_only", "entitlement_id": "full_journey", "revenuecat_public_key": ""}
const GOOGLE_PLAY := {"purchase_mode": "google_play", "entitlement_id": "full_journey_play", "revenuecat_public_key": "goog_synthetic_key"}
const OFFER := {"offering_id": "default", "packages": [{"id": "monthly", "offering_id": "default", "period": "month", "price": "$0.99"}, {"id": "yearly", "offering_id": "default", "period": "year", "price": "$9.99"}]}
# Synthetic ids only.
const PLAYER := "PPPPPPPPPPPPPPPPPPPPPP"

var checks := 0
var failures := 0
var paths: Array[String] = []

## The Wardrobe's server, offline: nothing leaves the test.
class Offline extends RefCounted:
	func call_it(_method: int, _path: String, _body: Dictionary) -> Dictionary:
		return {"ok": false, "status": 0, "code": "connection_interrupted"}

## The Wardrobe's server, online, answering every wallet read with `data`.
class Paid extends RefCounted:
	var tree: SceneTree
	var data: Dictionary
	var reads := 0
	func call_it(method: int, _path: String, _body: Dictionary) -> Dictionary:
		await tree.process_frame
		if method != HTTPClient.METHOD_GET: return {"ok": false, "status": 0, "code": "connection_interrupted"}
		reads += 1
		return {"ok": true, "status": 200, "data": data.duplicate(true)}

class Online extends RefCounted:
	func online() -> bool: return true

class FakeStore extends Purchases:
	func _connect_native() -> bool: return true
	func is_available() -> bool: return true
	func has_entitlement(_entitlement_id: String = "") -> bool: return false
	func has_subscription() -> bool: return false

## Main with no tester code, no purchase and a ready identity.
class App extends Main:
	func _tester_checks_enabled() -> bool: return false
	func _tester_active() -> bool: return false
	func _relay_identity() -> Dictionary: return {"ready": true, "player_id": "PPPPPPPPPPPPPPPPPPPPPP", "epoch": 1}

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	_ladder()
	var storage := Storage.new(_path("fj-board-save"))
	storage.data.settings.sound = false
	storage.data.settings.haptics = false
	storage.data.settings.reduced_motion = false
	_check(storage.flush(), "Use an isolated muted save")
	# Fruits stay off until a step turns them on; Main follows this store from its start.
	var fruits := FruitWallet.new(_path("fj-board-fruits"))
	FruitWallet.use_shared(fruits)
	var viewport := SubViewport.new()
	viewport.size = SIZE
	viewport.handle_input_locally = true
	root.add_child(viewport)
	var app := App.new()
	app.saves = storage
	app.home_keepsakes = Keepsakes.new(_path("fj-board-keepsakes"))
	viewport.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	app.world.set_process(false)
	app.home_keepsakes.cancel_backfill()
	app.purchases.queue_free()
	var store := FakeStore.new()
	app.purchases = store
	app.add_child(store)
	app.api.player_id = PLAYER
	app.api.base_url = "https://board.example.test"
	var wallet := PollenWallet.new(_path("fj-board-wallet"))
	var grant := PollenGrant.new(_path("fj-board-grant"))
	PollenWallet.use_shared(wallet)
	PollenGrant.use_shared(grant)
	PollenSurfaces.set_shared_for_tests(true)
	PlatformSupport.override_platform = PlatformSupport.ANDROID
	app.config.merge(GOOGLE_PLAY, true)
	var scope: Dictionary = app._names_scope()
	_check(not scope.is_empty(), "The test player is signed in")

	await _card_states(app, wallet, grant, scope, viewport)
	await _fruit_tiles(app, fruits, scope, viewport)
	await _grant_over_home(app, grant, scope, viewport)
	await _wardrobe_paid(app, grant, scope)
	await _fruit_grant_card(app, grant, fruits, scope, viewport)
	await _iphone(app, grant, scope)

	PlatformSupport.override_platform = ""
	PollenSurfaces.set_shared_for_tests(null)
	PollenWallet.use_shared(null)
	PollenGrant.use_shared(null)
	FruitWallet.use_shared(null)
	viewport.queue_free()
	await process_frame
	for path: String in paths:
		for suffix: String in ["", ".tmp", ".backup"]:
			if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	print("AFTER YOU FULL JOURNEY BOARD: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _ladder() -> void:
	_check(Benefits.ladder_line() == "Next month: 4,750 · By month 12: 7,250 · Top step: 12,000", "A new subscriber's ladder, as drawn: " + Benefits.ladder_line())
	_check(Benefits.ladder_line({"months": 5, "next": 5750, "top": 12000}) == "Next month: 6,000 · By month 12: 7,250 · Top step: 12,000", "A returning subscriber's ladder starts at their step")
	_check(Benefits.ladder_line({"months": 10, "next": 7000, "top": 12000}) == "Next month: 7,250 · Top step: 12,000", "Month 12 is not named once it is next or past")
	_check(Benefits.ladder_line({"months": 29, "next": 11750, "top": 12000}) == "Next month: 12,000 · Top step: 12,000", "Next month never passes the top step")
	_check(Benefits.ladder_line({"months": 40, "next": 12000, "top": 12000}) == "Top step: 12,000", "At the top step only the top step")
	var model := Benefits.content(true, true, {}, false)
	_check(model.panels.is_empty() and model.intro.size() == 2, "A build that names no Full Journey Pollen keeps the chapter lines and shows no panel")

## The Full Journey card as each state draws it, with the subscribe buttons from a store offer.
func _card_states(app: Node, wallet: RefCounted, grant: RefCounted, scope: Dictionary, viewport: SubViewport) -> void:
	var server := str(scope.server)
	var owner := str(scope.owner)
	for state: Array in [[false, false, []], [true, false, ["FullJourneyBoost"]], [true, true, ["FullJourneyBoost", "FullJourneyGrant"]]]:
		wallet.set_enabled(server, owner, state[0])
		grant.set_enabled(server, owner, state[1])
		var seen := await _open_card(app)
		_check(seen.panels == state[2], "Earning %s, grant %s: panels %s, got %s" % [state[0], state[1], state[2], seen.panels])
		_check(seen.after_intro, "The panels follow the chapter lines")
		_check(seen.on_screen, "The whole card stays on the 1600x738 screen with nothing to scroll: %s" % seen.rect)
		_check(seen.subscribe == 2, "Both subscribe buttons show")
	await _open_card(app)
	var panel: Control = app.overlay.find_child("FullJourneyGrant", true, false)
	var texts: Array = panel.find_children("*", "Label", true, false).map(func(label: Label) -> String: return label.text) if panel != null else []
	_check(texts == ["4,500 Pollen a month, growing every month you stay", "250 more each month, up to 12,000. Paid on each monthly anniversary on both plans. It never expires.", "Next month: 4,750 · By month 12: 7,250 · Top step: 12,000"], "The monthly Pollen panel says the board's words: " + str(texts))
	var boost: Control = app.overlay.find_child("FullJourneyBoost", true, false)
	var boost_texts: Array = boost.find_children("*", "Label", true, false).map(func(label: Label) -> String: return label.text) if boost != null else []
	_check(boost_texts == [PlayerCopy.FULL_JOURNEY_ROOM_BOOST, PlayerCopy.FULL_JOURNEY_ROOM_BOOST_NOTE], "The room boost panel: " + str(boost_texts))
	var takes_input := false
	for name: String in ["FullJourneyBoost", "FullJourneyGrant"]:
		var node: Control = app.overlay.find_child(name, true, false)
		if node == null: continue
		var controls: Array = node.find_children("*", "Control", true, false)
		controls.append(node)
		for control: Control in controls:
			if control.mouse_filter == Control.MOUSE_FILTER_STOP: takes_input = true
	_check(not takes_input, "The panels take no input, so a drag on them still scrolls")
	_check(Benefits.content(true, true, {"months": 40, "next": 12000, "top": 12000}).panels[1].title == "12,000 Pollen a month, the top step", "At the top step the panel stops saying it grows")
	# A returning subscriber sees the step the server says.
	grant.note_view(server, owner, {"grant": {"months": 6.0, "next": 6000.0, "top": 12000.0}})
	await _open_card(app)
	panel = app.overlay.find_child("FullJourneyGrant", true, false)
	texts = panel.find_children("*", "Label", true, false).map(func(label: Label) -> String: return label.text) if panel != null else []
	_check(texts.size() == 3 and texts[0] == "6,000 Pollen a month, growing every month you stay" and texts[2] == "Next month: 6,250 · By month 12: 7,250 · Top step: 12,000", "A returning subscriber's panel: " + str(texts))
	# A short screen scrolls the column instead of running the card off it.
	viewport.size = Vector2i(1600, 560)
	await process_frame
	await _open_card(app)
	var short_scroll: ScrollContainer = app.overlay.find_child("FullJourneyDetailsScroll", true, false)
	var short_card := _card_of(short_scroll) if short_scroll != null else null
	_check(short_card != null and short_card.get_global_rect().end.y <= 561.0 and short_scroll.get_v_scroll_bar().max_value > short_scroll.size.y, "A 560 tall screen keeps the card on it and scrolls the column: %s" % (short_card.get_global_rect() if short_card != null else Rect2()))
	viewport.size = SIZE
	await process_frame
	await _open_card(app)
	# A subscribe button takes its first tap.
	var bought := {"package": ""}
	var subscribe: Button = app.overlay.find_child("Subscribe_month", true, false)
	if subscribe != null:
		for connection: Dictionary in subscribe.pressed.get_connections(): subscribe.pressed.disconnect(connection.callable)
		subscribe.pressed.connect(func() -> void: bought.package = "month")
		await _tap(viewport, subscribe)
	_check(bought.package == "month", "Subscribe takes the first tap under the panels")

func _open_card(app: Node) -> Dictionary:
	app.store_flow.purchase_offer = OFFER.duplicate(true)
	app.store_flow._show_store_offer()
	for i in range(4): await process_frame
	var details: Control = app.overlay.find_child("FullJourneyDetails", true, false)
	var names: Array = []
	var after_intro := true
	var intro_seen := 0
	if details != null:
		for child: Node in details.get_children():
			if str(child.name).begins_with("FullJourney"):
				names.append(str(child.name))
				if intro_seen < 2: after_intro = false
			elif child is Label and (child as Label).text in [PlayerCopy.SUBSCRIPTION_PURPOSE, PlayerCopy.COOPERATIVE_HOST_ACCESS]:
				intro_seen += 1
	var card: Control = _card_of(details) if details != null else null
	var rect: Rect2 = card.get_global_rect() if card != null else Rect2()
	var screen := Rect2(Vector2.ZERO, Vector2(SIZE))
	var scroll: ScrollContainer = app.overlay.find_child("FullJourneyDetailsScroll", true, false)
	var fits := scroll != null and scroll.get_v_scroll_bar().max_value <= scroll.size.y + 1.0
	return {"panels": names, "after_intro": after_intro and intro_seen == 2, "on_screen": card != null and screen.encloses(rect) and fits, "rect": rect,
		"subscribe": app.overlay.find_children("Subscribe_*", "Button", true, false).size()}

## Board 5a: with Fruits on, the monthly Pollen panel becomes the Pollen and Fruit tiles, in the same place.
func _fruit_tiles(app: Node, fruits: RefCounted, scope: Dictionary, viewport: SubViewport) -> void:
	var server := str(scope.server)
	var owner := str(scope.owner)
	fruits.set_enabled(server, owner, true)
	var seen := await _open_card(app)
	_check(seen.panels == ["FullJourneyBoost", "FullJourneyGrant"], "Fruits on but no read with the Fruit ladder yet: today's Pollen panel, no Fruit numbers of the app's own")
	fruits.note_view(server, owner, {"fruits": {"schema_version": 1.0, "balance": 0.0, "earned": 0.0, "achievements": [], "ladder": {"first": 15.0, "step": 1.0, "every": 2.0, "top": 30.0, "welcome": 25.0}}})
	seen = await _open_card(app)
	_check(seen.panels == ["FullJourneyBoost", "FullJourneyGifts"] and seen.after_intro and seen.on_screen and seen.subscribe == 2, "Fruits on: the chapters, the room boost, then the monthly gifts row, all on screen: %s %s" % [seen.panels, seen.rect])
	var pollen: Control = app.overlay.find_child("FullJourneyGrant", true, false)
	var fruit: Control = app.overlay.find_child("FullJourneyFruits", true, false)
	_check(pollen != null and fruit != null and pollen.get_parent() == fruit.get_parent() and pollen.get_global_rect().end.x <= fruit.get_global_rect().position.x and absf(pollen.get_global_rect().position.y - fruit.get_global_rect().position.y) <= 0.5, "The Pollen tile and then the Fruit tile, side by side")
	_check(_words(pollen) == ["6,000 Pollen a month", "Grows by 250 every month you stay, up to 12,000."] and pollen.find_child("PollenMark", true, false) != null, "The Pollen tile as drawn, at this player's step: " + str(_words(pollen)))
	_check(_words(fruit) == ["15 Fruits a month", "Grows to 30 as you stay, plus a 25 Fruit welcome basket with your next month."] and fruit.find_child("FruitMark", true, false) != null, "Before the server sent a Fruit grant: month 1's Fruits, and for this player already on the ladder the basket with the next month: " + str(_words(fruit)))
	var fruit_ladder := {"first": 15, "step": 1, "every": 2, "top": 30, "welcome": 25}
	_check(Benefits.fruit_tile({}, fruit_ladder).body == "Grows to 30 as you stay, plus a [b]25 Fruit welcome basket[/b] in month 1.", "A player who never subscribed gets the basket in month 1, as drawn")
	_check(Benefits.fruit_tile({}, {}).is_empty(), "No Fruit tile without the server's ladder")
	var takes_input: Array = []
	for control: Control in fruit.find_children("*", "Control", true, false) + [fruit]:
		if control.mouse_filter == Control.MOUSE_FILTER_STOP: takes_input.append(str(control.name))
	_check(takes_input.is_empty(), "The Fruit tile takes no input either: %s" % [takes_input])
	fruits.note_view(server, owner, {"fruits": {"schema_version": 1.0, "balance": 40.0, "earned": 40.0, "achievements": [], "ladder": {"first": 15.0, "step": 1.0, "every": 2.0, "top": 30.0, "welcome": 25.0}, "grant": {"next": 16.0, "top": 30.0, "welcome": 25.0, "welcome_paid": true}}})
	await _open_card(app)
	fruit = app.overlay.find_child("FullJourneyFruits", true, false)
	_check(_words(fruit) == ["16 Fruits a month", "Grows to 30 as you stay."], "The server's numbers win, and a paid welcome basket is no longer named: " + str(_words(fruit)))
	_check(Benefits.fruit_tile({"next": 30, "top": 30, "welcome": 25, "welcome_paid": true}, fruit_ladder).title == "30 Fruits a month, the top step", "At the top step the tile stops saying it grows")
	viewport.size = Vector2i(1600, 720)
	await process_frame
	await _open_card(app)
	var card := _card_of(app.overlay.find_child("FullJourneyDetailsScroll", true, false))
	var gifts: Control = app.overlay.find_child("FullJourneyGifts", true, false)
	_check(card != null and Rect2(Vector2.ZERO, Vector2(1600, 720)).encloses(card.get_global_rect()) and gifts != null and card.get_global_rect().encloses(gifts.get_global_rect()), "At 1600x720 (an 800x360 phone) the card and both tiles stay on screen")
	viewport.size = SIZE
	await process_frame
	fruits.set_enabled(server, owner, false)
	seen = await _open_card(app)
	_check(seen.panels == ["FullJourneyBoost", "FullJourneyGrant"] and app.overlay.find_child("FullJourneyFruits", true, false) == null, "Fruits off: today's Pollen panel and no Fruit tile")

## Board 5b: the monthly card with both gifts while Fruits show, today's card otherwise.
func _fruit_grant_card(app: Node, kept_grant: RefCounted, fruits: RefCounted, scope: Dictionary, viewport: SubViewport) -> void:
	var server := str(scope.server)
	var owner := str(scope.owner)
	# A store of its own, so the instalments here never touch the steps after.
	var grant := PollenGrant.new(_path("fj-board-fruit-grant"))
	PollenGrant.use_shared(grant)
	grant.set_enabled(server, owner, true)
	var at := _now()
	grant.note_view(server, owner, {"grant": {"months": 3.0, "next": 5250.0, "top": 12000.0, "latest": {"key": "grant:1790000000000:3", "amount": 5000.0, "at": float(at)}}})
	fruits.set_enabled(server, owner, true)
	fruits.note_view(server, owner, {"fruits": {"schema_version": 1.0, "balance": 56.0, "earned": 56.0, "achievements": [], "grant": {"next": 16.0, "top": 30.0, "welcome": 25.0, "welcome_paid": true, "latest": {"amount": 16.0, "welcome": 0.0, "at": float(at)}}}})
	app._show_home()
	for i in range(4): await process_frame
	app.grant_card_check = true
	app._service_grant_card()
	await process_frame
	var card: Control = app.ui.find_child("PollenGrantCard", false, false)
	var texts: Array = card.find_children("*", "Label", true, false).map(func(label: Label) -> String: return label.text) if card != null else []
	_check(card != null and PlayerCopy.FRUIT_GRANT_TITLE in texts and "+5,000" in texts and "+16" in texts and "From Full Journey, month 3 of your ladder.\nNext month: 5,250 Pollen and 16 Fruits." in texts, "Your monthly gifts arrived, both amounts and next month's two: " + str(texts))
	if card != null:
		var tile: Control = card.find_child("PollenGrantFruits", true, false)
		var pollen: Control = card.find_child("PollenGrantFigure", true, false)
		var panel: Control = card.find_child("ModalPanel", true, false)
		_check(tile != null and tile.find_child("FruitMark", true, false) != null and card.find_child("PollenGrantAmount", true, false).find_child("PollenMark", true, false) != null, "The Fruits on their plum tile with the Fruit mark, the Pollen with its grain")
		_check(tile != null and pollen.get_global_rect().end.x < tile.get_global_rect().position.x and panel.get_global_rect().encloses(tile.get_global_rect()), "The tile sits right of the Pollen, inside the card")
		await _tap(viewport, card.find_child("PollenGrantDone", true, false))
	# A first month with the welcome basket names the Fruits with the basket.
	var welcome: Control = GrantCard.open(app.ui, {"key": "grant:1790000000000:1", "amount": 4500, "next": 4750, "top": 12000, "months": 1}, [], Callable(), null, {"amount": 15, "welcome": 25, "next": 15, "top": 30})
	var welcome_texts: Array = welcome.find_children("*", "Label", true, false).map(func(label: Label) -> String: return label.text)
	_check("+40" in welcome_texts and "From Full Journey, month 1 of your ladder.\nNext month: 4,750 Pollen and 15 Fruits." in welcome_texts, "Month 1 names its Fruits with the welcome basket: " + str(welcome_texts))
	welcome.close(false)
	for i in range(3): await process_frame
	_check(GrantCard.fruit_total({"amount": 16, "welcome": 0, "top": 30}) == 16 and GrantCard.fruit_total({"amount": 15, "welcome": 25}) == 40, "The card names what the server paid with the newest instalment and its welcome basket, never a guess for months paid together")
	_check(Benefits.fruit_tile({}, {"first": 15, "step": 1, "every": 2, "top": 30, "welcome": 25}, 6).body == "Grows to 30 as you stay, plus a [b]25 Fruit welcome basket[/b] with your next month.", "A subscriber already on the ladder gets the basket with their next month")
	# An instalment that brought no Fruits (paid before Fruits were on) keeps today's card.
	grant.note_view(server, owner, {"grant": {"months": 4.0, "next": 5500.0, "top": 12000.0, "latest": {"key": "grant:1790000000000:4", "amount": 5250.0, "at": float(at + 1000)}}})
	app.grant_card_check = true
	app._service_grant_card()
	await process_frame
	card = app.ui.find_child("PollenGrantCard", false, false)
	texts = card.find_children("*", "Label", true, false).map(func(label: Label) -> String: return label.text) if card != null else []
	_check(card != null and PlayerCopy.POLLEN_GRANT_TITLE in texts and "From Full Journey, month 4 of your ladder.\nNext month: 5,500." in texts and card.find_child("PollenGrantFruits", true, false) == null, "An instalment with no Fruits: today's card: " + str(texts))
	if card != null: app._close_top_modal()
	await process_frame
	# Fruits off: today's card, unchanged.
	fruits.note_view(server, owner, {"fruits": {"schema_version": 1.0, "balance": 72.0, "earned": 72.0, "achievements": [], "grant": {"next": 17.0, "top": 30.0, "welcome": 25.0, "welcome_paid": true, "latest": {"amount": 17.0, "welcome": 0.0, "at": float(at + 2000)}}}})
	fruits.set_enabled(server, owner, false)
	grant.note_view(server, owner, {"grant": {"months": 5.0, "next": 5750.0, "top": 12000.0, "latest": {"key": "grant:1790000000000:5", "amount": 5500.0, "at": float(at + 2000)}}})
	app.grant_card_check = true
	app._service_grant_card()
	await process_frame
	card = app.ui.find_child("PollenGrantCard", false, false)
	texts = card.find_children("*", "Label", true, false).map(func(label: Label) -> String: return label.text) if card != null else []
	_check(card != null and PlayerCopy.POLLEN_GRANT_TITLE in texts and not "+17" in texts and card.find_child("FruitMark", true, false) == null, "Fruits off: today's Pollen card: " + str(texts))
	if card != null: app._close_top_modal()
	await process_frame
	PollenGrant.use_shared(kept_grant)

## Every word a panel shows, labels and rich text alike, in order.
static func _words(node: Node) -> Array:
	var out: Array = []
	if node == null: return out
	if node is Label: out.append((node as Label).text)
	elif node is RichTextLabel: out.append((node as RichTextLabel).get_parsed_text())
	for child: Node in node.get_children(): out.append_array(_words(child))
	return out

## The grant card over Home, its pips, its first taps, and once only.
func _grant_over_home(app: Node, grant: RefCounted, scope: Dictionary, viewport: SubViewport) -> void:
	var server := str(scope.server)
	var owner := str(scope.owner)
	grant.set_enabled(server, owner, true)
	grant.note_view(server, owner, {"grant": {"months": 1.0, "next": 4750.0, "top": 12000.0, "latest": {"key": "grant:1790000000000:1", "amount": 4500.0, "at": float(_now())}}})
	app._show_home()
	for i in range(4): await process_frame
	var spirits: Array = app.world.actors.values().filter(func(actor: Node3D) -> bool: return actor.visible)
	_check(spirits.size() == 2, "Home shows both pips: %d" % spirits.size())
	app.grant_card_check = true
	app._service_grant_card()
	await process_frame
	var card: Control = app.ui.find_child("PollenGrantCard", false, false)
	_check(card != null and app._top_modal() == card, "The card opens over Home as Home's top card")
	if card == null: return
	var texts: Array = card.find_children("*", "Label", true, false).map(func(label: Label) -> String: return label.text)
	_check(PlayerCopy.POLLEN_GRANT_TITLE in texts and "+4,500" in texts and "From Full Journey, month 1 of your ladder.\nNext month: 4,750." in texts, "It says what arrived, the month and next month: " + str(texts))
	_check(card.find_child("PollenGrantBag", true, false) != null and card.find_child("PollenMark", true, false) != null, "The bag and the grain beside the amount")
	var close: Control = card.find_child("ModalClose", true, false)
	_check(close != null and not close.visible, "No X: Done and Back close it")
	_check(spirits.all(func(actor: Node3D) -> bool: return actor.expression_target() == SpiritLook.JOY), "Both pips make their joy face behind it")
	for i in range(6):
		for actor: Node3D in spirits: actor.advance_motion(Vector3.ZERO, 10.0, false)
	_check(spirits.all(func(actor: Node3D) -> bool: return actor.expression_target() == SpiritLook.JOY), "A minute later they still do (no doze takes it)")
	var panel: Control = card.find_child("ModalPanel", true, false)
	_check(panel != null and panel.get_global_rect().get_center().x > SIZE.x * 0.6, "It sits right of the island, as drawn: %s" % (panel.get_global_rect() if panel != null else Rect2()))
	var wardrobe_shown: bool = card.find_child("PollenGrantWardrobe", true, false) != null
	_check(wardrobe_shown == app.wardrobe_flow.available(), "Open the Wardrobe shows only when the Wardrobe can open")
	await _tap(viewport, card.find_child("PollenGrantDone", true, false))
	_check(not is_instance_valid(card) or card.is_queued_for_deletion() or not card.is_inside_tree(), "Done closes it on the first tap")
	await process_frame
	_check(spirits.all(func(actor: Node3D) -> bool: return actor.expression_target() != SpiritLook.JOY), "The pips go back to their own face")
	app.grant_card_check = true
	app._service_grant_card()
	await process_frame
	_check(app.ui.find_child("PollenGrantCard", false, false) == null, "Each instalment's card shows once")

	# Open the Wardrobe: one tap closes the card and opens it.
	var opened := {"count": 0}
	var direct: Control = GrantCard.open(app.ui, {"key": "grant:1790000000000:2", "amount": 4750, "next": 5000, "top": 12000, "months": 2}, spirits, func() -> void: opened.count += 1)
	await process_frame
	await process_frame
	var open_button: Button = direct.find_child("PollenGrantWardrobe", true, false)
	_check(open_button != null and open_button.icon != null, "Open the Wardrobe has the hanger")
	await _tap(viewport, open_button)
	_check(opened.count == 1, "Open the Wardrobe opens it on the first tap")
	_check(not is_instance_valid(direct) or direct.is_queued_for_deletion(), "and the card goes")
	await process_frame
	_check(spirits.all(func(actor: Node3D) -> bool: return actor.expression_target() != SpiritLook.JOY), "The pips stop cheering when it goes")
	# Android Back closes it too, faces and all.
	var backed: Control = GrantCard.open(app.ui, {"key": "grant:1790000000000:3", "amount": 5000, "next": 5250, "top": 12000, "months": 3}, spirits)
	await process_frame
	_check(app._close_top_modal(), "Back closes the card")
	await process_frame
	_check(not is_instance_valid(backed) and spirits.all(func(actor: Node3D) -> bool: return actor.expression_target() != SpiritLook.JOY), "and the pips stop cheering")

	# With the server's Wardrobe on, Home's card opens it, and its Back comes home.
	var wardrobe := Wardrobe.new(_path("fj-board-wardrobe"))
	wardrobe.set_enabled(server, owner, true, false)
	var offline := Offline.new()
	app.wardrobe_flow.client = WardrobeClient.new(null, app._names_scope, offline.call_it, wardrobe, PollenWallet.shared())
	grant.note_view(server, owner, {"grant": {"months": 2.0, "next": 5000.0, "top": 12000.0, "latest": {"key": "grant:1790000000000:2", "amount": 4750.0, "at": float(_now())}}})
	app._show_home()
	for i in range(4): await process_frame
	app.grant_card_check = true
	app._service_grant_card()
	await process_frame
	var with_wardrobe: Control = app.ui.find_child("PollenGrantCard", false, false)
	_check(with_wardrobe != null and with_wardrobe.find_child("PollenGrantWardrobe", true, false) != null, "With the Wardrobe on, the card offers it")
	if with_wardrobe != null: await _tap(viewport, with_wardrobe.find_child("PollenGrantWardrobe", true, false))
	_check(app.wardrobe_flow.is_open(), "One tap opens the Wardrobe")
	app.wardrobe_flow.back_requested.emit()
	await process_frame
	_check(app.mode == "home", "Its Back comes home, where it opened: " + str(app.mode))
	app.settings_flow.show_settings()
	await process_frame
	app.wardrobe_flow.show_wardrobe()
	await process_frame
	app.wardrobe_flow.back_requested.emit()
	await process_frame
	_check(app.mode != "home" and not app.wardrobe_flow.is_open(), "Opened from Settings later, its Back goes to Settings: " + str(app.mode))
	app.wardrobe_flow.client = null

## The owner's 0.7.7 case: the Wardrobe's own wallet read is the one that pays.
## No card over the Wardrobe; back on Home it shows once with nothing set by
## hand, and never again, a restart included. A payment kept while the store
## card is up waits for Home the same way.
func _wardrobe_paid(app: Node, grant: RefCounted, scope: Dictionary) -> void:
	var server := str(scope.server)
	var owner := str(scope.owner)
	var wardrobe := Wardrobe.new(_path("fj-board-wardrobe-paid"))
	wardrobe.set_enabled(server, owner, true, false)
	var paid := Paid.new()
	paid.tree = self
	paid.data = {"schema_version": 1.0, "balance": 9500.0, "earned": 9500.0, "bank": 12.0,
		"wardrobe": {"items": [], "packs": [], "look": {}, "look_revision": 1.0, "offered": ["daisy", "seashell"], "offered_packs": [], "sets": {}, "unlocked": []},
		"grant": {"months": 3.0, "next": 5250.0, "top": 12000.0, "latest": {"key": "grant:1790000000000:3", "amount": 5000.0, "at": float(_now())}}}
	var client: RefCounted = WardrobeClient.new(null, app._names_scope, paid.call_it, wardrobe, PollenWallet.shared())
	client.connectivity = Online.new()
	app.wardrobe_flow.client = client
	app._show_home()
	for i in range(4): await process_frame
	app._service_grant_card()
	app.wardrobe_flow.show_wardrobe("home")
	for i in range(6): await process_frame
	_check(paid.reads == 1, "Opening the Wardrobe reads the wallet: %d" % paid.reads)
	app._service_grant_card()
	await process_frame
	_check(app.ui.find_child("PollenGrantCard", false, false) == null, "No card over the Wardrobe")
	_check(not grant.pending(server, owner).is_empty(), "but the instalment its read paid is kept")
	app.wardrobe_flow.back_requested.emit()
	for i in range(4): await process_frame
	_check(app.mode == "home", "Back on Home: " + str(app.mode))
	app._service_grant_card()
	await process_frame
	var card: Control = app.ui.find_child("PollenGrantCard", false, false)
	var texts: Array = card.find_children("*", "Label", true, false).map(func(label: Label) -> String: return label.text) if card != null else []
	_check(card != null and "+5,000" in texts, "The card shows on Home for the Wardrobe's payment: " + str(texts))
	if card != null: app._close_top_modal()
	await process_frame
	app._service_grant_card()
	await process_frame
	_check(app.ui.find_child("PollenGrantCard", false, false) == null, "once")
	_check(PollenGrant.new(grant.path).pending(server, owner).is_empty(), "and not after a restart either")
	# Paid while the store card is up (as a purchase's own read can be): the card waits for Home to be free.
	app.mode = app.store_flow.MODE_PAYWALL
	app.store_flow.purchase_offer = OFFER.duplicate(true)
	app.store_flow._show_store_offer()
	for i in range(4): await process_frame
	grant.note_view(server, owner, {"grant": {"months": 4.0, "next": 5500.0, "top": 12000.0, "latest": {"key": "grant:1790000000000:4", "amount": 5250.0, "at": float(_now())}}})
	app._service_grant_card()
	await process_frame
	_check(app.ui.find_child("PollenGrantCard", false, false) == null, "No card over the store card")
	app._show_home()
	for i in range(4): await process_frame
	app._service_grant_card()
	await process_frame
	var bought: Control = app.ui.find_child("PollenGrantCard", false, false)
	_check(bought != null, "Back on Home it shows")
	if bought != null: app._close_top_modal()
	await process_frame
	app.wardrobe_flow.client = null

## A build that names no Full Journey: no card, and the store card keeps no panel.
func _iphone(app: Node, grant: RefCounted, scope: Dictionary) -> void:
	var server := str(scope.server)
	var owner := str(scope.owner)
	grant.note_view(server, owner, {"grant": {"months": 5.0, "next": 5750.0, "top": 12000.0, "latest": {"key": "grant:1790000000000:5", "amount": 5500.0, "at": float(_now())}}})
	PlatformSupport.override_platform = PlatformSupport.IOS
	for key: String in ["purchase_mode", "entitlement_id", "revenuecat_public_key"]: app.config.erase(key)
	app.config.merge(TESTER_ONLY, true)
	app._show_home()
	for i in range(4): await process_frame
	_check(app._home_free_for_card() and not app._grant_card_allowed(), "Home is free for a card, but the build names no Full Journey")
	app.grant_card_check = true
	app._service_grant_card()
	await process_frame
	_check(app.ui.find_child("PollenGrantCard", false, false) == null, "iPhone without a store never shows the card")
	_check(not grant.pending(server, owner).is_empty(), "and keeps it unshown")
	PollenSurfaces.set_shared_for_tests(false)
	app.store_flow._full_journey_card()
	await process_frame
	_check(app.overlay.find_child("FullJourneyBoost", true, false) == null and app.overlay.find_child("FullJourneyGrant", true, false) == null, "and its store card shows no Pollen panel")
	PollenSurfaces.set_shared_for_tests(true)

## A real press and release at the middle of `control`.
func _tap(viewport: SubViewport, control: Control) -> void:
	if control == null:
		_check(false, "Nothing to tap")
		return
	var at := control.get_global_rect().get_center()
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = at
		event.global_position = at
		viewport.push_input(event)
		await process_frame

static func _now() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)

func _path(label: String) -> String:
	var result := "user://test-%s-%d.json" % [label, Time.get_ticks_usec()]
	paths.append(result)
	return result

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

## The card's panel round `details`.
static func _card_of(details: Control) -> Control:
	var node: Node = details
	while node != null and not node is PanelContainer: node = node.get_parent()
	return node as Control
