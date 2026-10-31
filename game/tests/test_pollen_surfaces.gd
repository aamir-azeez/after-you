extends SceneTree
## Which Pollen parts each build shows (services/pollen_surfaces.gd):
## - Android, desktop and iOS with a store show every part;
## - iOS that sells nothing (Purchases.paid_content_hidden) shows earning, the
##   balance and the Wardrobe, and hides the shop, every price and Full Journey;
## - the name change on both builds: the selling build says the price and its
##   money figure; the build that sells nothing names no price and never sends
##   a change that costs, while a free change and going anonymous still save;
## - pollen board 6's Save states on the selling build: "Save · free this
##   time" only for the last free change (the server's next price, or the
##   phone's own reading without it), Save with the grain and "about $X" inside,
##   "N more needed" with Save held back and a Get Pollen link that opens the
##   short card, the price line under the field and the balance line under the
##   choices, all inside the card at 1280x720 and 1600x738.
## The Wardrobe, the line after a turn and the odds note are covered on both
## builds in test_wardrobe_flow, test_pollen_wallet and test_pollen_item_bloom.
const PollenSurfaces = preload("res://services/pollen_surfaces.gd")
const PlatformSupport = preload("res://services/platform_support.gd")
const Purchases = preload("res://services/purchases.gd")
const DisplayNames = preload("res://services/display_names.gd")
const Prompt = preload("res://presentation/display_name_prompt.gd")
const Flow = preload("res://presentation/display_name_flow.gd")
const Wardrobe = preload("res://services/wardrobe.gd")
const PollenWallet = preload("res://services/pollen_wallet.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const StoreSupport = preload("res://services/store_support.gd")

# Synthetic ids only.
const ME := "aaaaaaaaaaaaaaaaaaaaaa"
const SERVER := "https://pollen-surfaces.example.test"

const TESTER_ONLY := {"purchase_mode": "tester_only", "entitlement_id": "full_journey", "revenuecat_public_key": ""}
const APP_STORE := {"purchase_mode": "app_store", "entitlement_id": "full_journey_play", "revenuecat_public_key": "appl_synthetic_key"}
const APP_STORE_NO_KEY := {"purchase_mode": "app_store", "entitlement_id": "full_journey_play", "revenuecat_public_key": ""}
const TEST_STORE := {"purchase_mode": "test_store", "entitlement_id": "full_journey", "revenuecat_public_key": "test_synthetic_key"}
const GOOGLE_PLAY := {"purchase_mode": "google_play", "entitlement_id": "full_journey_play", "revenuecat_public_key": "goog_synthetic_key"}

var checks := 0
var failures := 0
var page: Control
var _paths: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_rule()
	page = Control.new()
	page.size = Vector2(1280, 720)
	root.add_child(page)
	await _name_price()
	await _name_prompt(true)
	await _name_prompt(false)
	_free_this_time()
	for size: Vector2i in [Vector2i(1280, 720), Vector2i(1561, 720)]:
		await _board_six(size)
	await _short_card()
	page.queue_free()
	PlatformSupport.override_platform = ""
	PollenSurfaces.set_shared_for_tests(null)
	Wardrobe.use_shared(null)
	PollenWallet.use_shared(null)
	await process_frame
	for path: String in _paths:
		for suffix: String in ["", ".tmp", ".backup", ".bak"]:
			if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	print("AFTER YOU POLLEN SURFACES: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

## The words inside a button's content (Save with the grain), in order.
static func _words(button: Button) -> Array:
	var holder := button.get_node_or_null("ButtonContent") as Control
	if holder == null or not holder.visible: return []
	return holder.find_children("*", "Label", true, false).map(func(label: Label) -> String: return label.text)

## "Save · free this time" only for the last free change: from the server's next
## price, or, from a server that sends none, when the player holds a name now.
func _free_this_time() -> void:
	var named := {"choice": "typed", "name": "Robin"}
	var fresh := {"choice": "", "name": ""}
	var anon := {"choice": "anonymous", "name": ""}
	var cases := [
		[{"price": 0, "next": 1000}, named, "typed", "Sky", true, "the free change after a first name"],
		[{"price": 0, "next": 1000}, anon, "typed", "Sky", true, "naming again after going anonymous, the free change"],
		[{"price": 0, "next": 0}, fresh, "typed", "Sky", false, "a first name (the change after it is free too)"],
		[{"price": 0, "next": 0}, anon, "typed", "Sky", false, "a first name after starting anonymous"],
		[{"price": 1000, "next": 1000}, named, "typed", "Sky", false, "a paid change"],
		[{"price": 0, "next": 1000}, named, "typed", "Robin", false, "keeping the name"],
		[{"price": 0, "next": 1000}, named, "anonymous", "", false, "going anonymous"],
		[{"price": 0, "next": -1}, named, "typed", "Sky", true, "an older server, a player who holds a name"],
		[{"price": 0, "next": -1}, anon, "typed", "Sky", false, "an older server, an anonymous player"],
		[{}, named, "typed", "Sky", false, "the shop off"]]
	for case: Array in cases:
		_check(Prompt.free_this_time(case[0], case[1], case[2], case[3]) == case[4], "Free this time for %s: %s" % [case[5], case[4]])

## Board 6's three Save states, the lines and the link, at `size`.
func _board_six(size: Vector2i) -> void:
	PollenSurfaces.set_shared_for_tests(true)
	var holder := Control.new()
	holder.size = Vector2(size)
	root.add_child(holder)
	var own := {"choice": "typed", "name": "Robin", "revision": 1, "state": "synced", "code": "", "asked": true, "confirmed": "Robin"}
	var opened: Array = []
	var sent: Array = []
	var price := {"price": 0, "balance": 600, "shown": true, "next": 1000}
	var context := {"own": own, "anonymous": "Kite 41", "platform": "", "edit": true, "price": price,
		"get_pollen": func(link: Control) -> void: opened.append(link),
		"save": func(choice: String, name: String) -> Dictionary: sent.append([choice, name]); return {"closed": false, "code": "busy"}}
	var modal: Control = Prompt.open(holder, context)
	for i in range(3): await process_frame
	var prompt: Node = modal.find_child("DisplayNamePrompt", true, false)
	prompt.field.text = "Robin Sky"
	prompt.field.text_changed.emit("Robin Sky")
	await process_frame
	_check(prompt.save_button.text == PlayerCopy.DISPLAY_NAME_SAVE_FREE and not prompt.save_button.disabled and not prompt._price_note.visible and not prompt._have_line.visible and not prompt.get_pollen_link.visible, "Free this time: Save says so, with no price lines at %s" % size)
	# A paid change the balance covers.
	price.price = 1000
	price.balance = 24000
	prompt._show()
	await process_frame
	_check(_words(prompt.save_button) == [PlayerCopy.DISPLAY_NAME_SAVE_DOT, "1,000", PlayerCopy.WARDROBE_ABOUT % "$0.20"] and prompt.save_button.find_child("PollenMark", true, false) != null and not prompt.save_button.disabled, "Save · [grain] 1,000 about $0.20 at %s" % size)
	_check(prompt._have_line.visible and prompt._have_label.text == PlayerCopy.DISPLAY_NAME_PRICE_HAVE % "24,000" and prompt._have_line.find_child("PollenMark", true, false) != null, "The balance line with its grain under the choices")
	_check(prompt._price_note.get_parent() == prompt._counter.get_parent() and prompt._price_note.visible and not prompt.get_pollen_link.visible, "The price line sits under the field beside the counter, and no link while the balance covers it")
	_fits(modal, prompt, size, "priced")
	# Short of Pollen: Save waits and says what is needed; the link opens the short card.
	price.balance = 600
	prompt._show()
	await process_frame
	_check(_words(prompt.save_button) == [PlayerCopy.DISPLAY_NAME_SAVE_DOT, "1,000" + PlayerCopy.DISPLAY_NAME_SAVE_NEEDED % "400"] and prompt.save_button.disabled
		and prompt.save_button.accessibility_name == PlayerCopy.DISPLAY_NAME_SAVE_SHORT % ["1,000", "400"], "Save · [grain] 1,000 · 400 more needed, held back at %s: %s" % [size, str(_words(prompt.save_button))])
	_check(prompt.get_pollen_link.is_visible_in_tree() and prompt.get_pollen_link.text == PlayerCopy.WARDROBE_GET_POLLEN, "Get Pollen shows under Save")
	var link_rect: Rect2 = prompt.get_pollen_link.get_global_rect()
	var save_rect: Rect2 = prompt.save_button.get_global_rect()
	_check(link_rect.position.y >= save_rect.end.y and absf(link_rect.position.x - save_rect.position.x) <= 2.0, "under Save, at its left edge: %s %s" % [link_rect, save_rect])
	_fits(modal, prompt, size, "short")
	prompt.get_pollen_link.pressed.emit()
	_check(opened == [prompt.get_pollen_link], "Get Pollen asks the flow for the short card")
	prompt.field.text_submitted.emit("Robin Sky")
	await process_frame
	_check(sent.is_empty() and prompt.save_button.disabled and _words(prompt.save_button).size() == 2, "Enter never sends a change the balance cannot pay: " + str(sent))
	# Going anonymous is free: plain Save, no price lines or link.
	prompt.anonymous_row.pressed.emit()
	await process_frame
	_check(prompt.save_button.text == PlayerCopy.DISPLAY_NAME_SAVE and _words(prompt.save_button).is_empty() and not prompt.save_button.disabled and not prompt.get_pollen_link.visible and not prompt._have_line.visible, "Going anonymous is a plain free Save")
	# An error takes the price line's place under the field.
	prompt.field.text = "<<>>"
	prompt.field.text_changed.emit("<<>>")
	price.balance = 24000
	prompt._save()
	await process_frame
	_check(prompt._error.visible and not prompt._price_note.visible, "An error takes the price line's place")
	modal.queue_free()
	holder.queue_free()
	await process_frame

## Stands in for Main's Pollen store flow: whether it can open, and where from.
class StoreStub extends Node:
	var on := true
	var opened: Array = []
	func available() -> bool: return on
	func show_store(from: String = "wardrobe") -> void: opened.append(from)

class FlowHost extends Node:
	var pollen_store_flow: Node

## Get Pollen's short card (board 5b's, for a name change): the cost and the
## balance, no "It stays in the shop.", and its own link to the store only while
## the store can open, which closes the prompt and opens the store with Back to Friends.
func _short_card() -> void:
	var holder := Control.new()
	holder.size = Vector2(1280, 720)
	root.add_child(holder)
	var host := FlowHost.new()
	host.pollen_store_flow = StoreStub.new()
	host.add_child(host.pollen_store_flow)
	root.add_child(host)
	var flow := Flow.new(host)
	host.add_child(flow)
	var prompt_card := Prompt.open(holder, {"own": {}, "anonymous": "Kite 41", "platform": "", "edit": true})
	flow._prompt = weakref(prompt_card)
	flow._prompt_price = {"price": 1000, "balance": 600, "shown": true, "next": 1000}
	flow._open_short(holder, null)
	flow._open_short(holder, null)
	await process_frame
	var cards := holder.find_children("WardrobeShort", "", true, false)
	_check(cards.size() == 1, "A second tap opens no second card")
	var card: Control = cards[0] if not cards.is_empty() else null
	var words: Array = card.find_children("*", "Label", true, false).map(func(label: Label) -> String: return label.text) if card != null else []
	_check(words.has(PlayerCopy.WARDROBE_SHORT_NOTE % [PlayerCopy.DISPLAY_NAME_SHORT_ITEM, "1,000", "600"]) and words.has("400" + PlayerCopy.WARDROBE_SHORT_MORE) and not words.has(PlayerCopy.WARDROBE_SHORT_STAYS), "The short card names the change and what is needed, and nothing about the shop: " + str(words))
	var link := card.find_child("WardrobeGetPollen", true, false) as LinkButton if card != null else null
	_check(link != null, "Its own Get Pollen shows while the store can open")
	if link != null: link.pressed.emit()
	await process_frame
	_check(host.pollen_store_flow.opened == ["friends"] and (not is_instance_valid(prompt_card) or prompt_card.is_queued_for_deletion()), "It closes the prompt and opens the store with Back to Friends")
	host.pollen_store_flow.on = false
	flow._open_short(holder, null)
	await process_frame
	var shut := holder.find_children("WardrobeShort", "", true, false).filter(func(node: Node) -> bool: return not node.is_queued_for_deletion())
	_check(shut.size() == 1 and shut[0].find_child("WardrobeGetPollen", true, false) == null, "With the store shut the card has no link")
	shut[0].close()
	flow._prompt_price = {"price": 1000, "balance": 600, "shown": false, "next": 1000}
	flow._open_short(holder, null)
	await process_frame
	_check(holder.find_children("WardrobeShort", "", true, false).filter(func(node: Node) -> bool: return not node.is_queued_for_deletion()).is_empty(), "A build that shows no price never opens it")
	holder.queue_free()
	host.queue_free()
	await process_frame

## Everything in the card stays inside it and inside the screen; Save's content fits its button.
func _fits(modal: Control, prompt: Node, size: Vector2i, context: String) -> void:
	var panel := modal.find_child("ModalPanel", true, false) as Control
	var screen := Rect2(Vector2.ZERO, Vector2(size))
	_check(screen.encloses(panel.get_global_rect()), "The card stays on screen (%s, %s): %s" % [context, size, panel.get_global_rect()])
	var content := prompt.save_button.get_node("ButtonContent").get_child(0) as Control
	_check(prompt.save_button.get_global_rect().grow(0.5).encloses(content.get_global_rect()), "Save's content fits its button (%s, %s): %s in %s" % [context, size, content.get_global_rect(), prompt.save_button.get_global_rect()])

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
		print("FAIL: " + message)

func _path(stem: String) -> String:
	var path := "user://test-pollen-surfaces-%s-%s.json" % [stem, Crypto.new().generate_random_bytes(6).hex_encode()]
	_paths.append(path)
	return path

static func _parts(surfaces: RefCounted) -> Dictionary:
	return {"earning": surfaces.earning_visible(), "wallet": surfaces.wallet_visible(), "wardrobe": surfaces.wardrobe_visible(),
		"shop": surfaces.shop_visible(), "full_journey": surfaces.full_journey_visible()}

const EVERY_PART := {"earning": true, "wallet": true, "wardrobe": true, "shop": true, "full_journey": true}
const EARN_AND_WEAR := {"earning": true, "wallet": true, "wardrobe": true, "shop": false, "full_journey": false}

## The rule: the same answer as Purchases.paid_content_hidden, split by surface.
func _rule() -> void:
	for platform: String in ["", PlatformSupport.ANDROID]:
		PlatformSupport.override_platform = platform
		for config: Dictionary in [TESTER_ONLY, APP_STORE, APP_STORE_NO_KEY, TEST_STORE, GOOGLE_PLAY, {}]:
			_check(_parts(PollenSurfaces.for_configuration(config)) == EVERY_PART, "%s shows every Pollen part (%s)" % [platform if not platform.is_empty() else "desktop", config.get("purchase_mode", "no config")])
	PlatformSupport.override_platform = PlatformSupport.IOS
	for config: Dictionary in [TESTER_ONLY, GOOGLE_PLAY, APP_STORE_NO_KEY, {}]:
		_check(Purchases.paid_content_hidden(config), "iOS hides paid content with %s" % config.get("purchase_mode", "no config"))
		_check(_parts(PollenSurfaces.for_configuration(config)) == EARN_AND_WEAR, "iOS selling nothing (%s) earns, keeps the balance and the Wardrobe, and hides the shop and Full Journey" % config.get("purchase_mode", "no config"))
	for config: Dictionary in [APP_STORE, TEST_STORE]:
		_check(_parts(PollenSurfaces.for_configuration(config)) == EVERY_PART, "iOS with a store (%s) shows every part" % config.purchase_mode)
	# Bundles: a Google Play or App Store build with its key, never the Test Store or a build without a key.
	_check(PollenSurfaces.for_configuration(APP_STORE).bundles_visible(), "The App Store build sells bundles")
	for config: Dictionary in [TEST_STORE, APP_STORE_NO_KEY, TESTER_ONLY]:
		_check(not PollenSurfaces.for_configuration(config).bundles_visible(), "iOS %s sells no bundles" % config.get("purchase_mode"))
	# The server's answer for the signed-in player (services/store_support.gd): unknown and on show, off holds every paid part.
	var support: RefCounted = StoreSupport.new(_path("store-support"))
	StoreSupport.use_shared(support)
	support.scope_source = func() -> Dictionary: return {"server": SERVER, "owner": ME}
	var selling: RefCounted = PollenSurfaces.for_configuration(APP_STORE)
	_check(support.state(SERVER, ME) == StoreSupport.UNKNOWN and _parts(selling) == EVERY_PART and selling.bundles_visible(), "No answer yet: the iPhone build decides")
	support.note(SERVER, ME, false)
	_check(_parts(selling) == EARN_AND_WEAR and not selling.bundles_visible(), "The server takes no App Store purchases: the shop, bundles and Full Journey hide, earning and the Wardrobe stay")
	_check(support.hides_paid() and not support.confirmed(SERVER, ME) and not support.may_buy() and support.read_now(), "and nothing may be bought on that answer")
	support.note(SERVER, ME, true)
	_check(_parts(selling) == EVERY_PART and selling.bundles_visible() and support.may_buy(), "It does: every part shows, and money may move on this run's answer")
	var again: RefCounted = StoreSupport.new(support.path)
	again.scope_source = support.scope_source
	_check(again.state(SERVER, ME) == StoreSupport.ON and not again.read_this_session(SERVER, ME) and not again.may_buy() and not again.read_now(), "A restart keeps the answer for what shows, but money waits for a new read")
	again.note(SERVER, ME, false)
	_check(StoreSupport.new(support.path).state(SERVER, ME) == StoreSupport.OFF, "An off answer is kept on disk")
	PlatformSupport.override_platform = PlatformSupport.ANDROID
	_check(not again.hides_paid() and again.may_buy() and again.read_now(), "Android never waits on the App Store answer")
	PlatformSupport.override_platform = PlatformSupport.IOS
	StoreSupport.use_shared(null)
	PlatformSupport.override_platform = ""
	PollenSurfaces.set_shared_for_tests(false)
	_check(_parts(PollenSurfaces.shared()) == EARN_AND_WEAR, "Tests can pick the build that sells nothing")
	PollenSurfaces.set_shared_for_tests(true)
	_check(_parts(PollenSurfaces.shared()) == EVERY_PART, "and the one that sells")
	PollenSurfaces.set_shared_for_tests(null)
	_check(PollenSurfaces.shared() == PollenSurfaces.shared(), "The shared answer is read once")

## The flow hands the prompt the price with whether this build may show it.
func _name_price() -> void:
	var store_path := _path("wardrobe")
	var store: RefCounted = Wardrobe.new(store_path)
	var wallet: RefCounted = PollenWallet.new(_path("wallet"))
	Wardrobe.use_shared(store)
	PollenWallet.use_shared(wallet)
	var current := {"server": SERVER, "owner": ME}
	_check(Flow.name_price(current).is_empty(), "No price before the server said one")
	store.set_enabled(SERVER, ME, true)
	wallet.set_enabled(SERVER, ME, true)
	var answer := {"schema_version": 1.0, "balance": 5000.0, "earned": 5000.0, "bank": 12.0, "name_price": 1000.0,
		"wardrobe": {"items": [], "packs": [], "look": {}, "look_revision": 0.0, "offered": [], "offered_packs": [], "sets": {}, "unlocked": []}}
	store.note_view(SERVER, ME, answer)
	wallet.note_wallet(SERVER, ME, answer)
	PollenSurfaces.set_shared_for_tests(true)
	_check(Flow.name_price(current) == {"price": 1000, "balance": 5000, "shown": true, "next": -1}, "Selling: the price, the balance and that it shows, with no next price from an older server: " + str(Flow.name_price(current)))
	PollenSurfaces.set_shared_for_tests(false)
	_check(Flow.name_price(current) == {"price": 1000, "balance": 5000, "shown": false, "next": -1}, "Selling nothing: the same price, marked not shown")
	answer.name_price = 0.0
	answer.name_price_next = 1000.0
	store.note_view(SERVER, ME, answer)
	_check(Flow.name_price(current).get("next") == 1000 and Flow.name_price(current).get("price") == 0, "The server's price after the free change comes through")
	var reread: RefCounted = Wardrobe.new(store_path)
	reread.set_enabled(SERVER, ME, true)
	_check(reread.name_price_next(SERVER, ME) == 1000 and reread.name_price(SERVER, ME) == 0, "and is kept on the phone through a restart")
	answer.name_price_next = -5.0
	store.note_view(SERVER, ME, answer)
	_check(Flow.name_price(current).get("next") == -1 and Flow.name_price(current).get("price") == 0, "A next price off the contract reads as none, and the view stays")
	answer.erase("name_price_next")
	answer.name_price = 1000.0
	store.note_view(SERVER, ME, answer)
	for code: String in ["pollen_short", "name_change_price"]:
		var line := str(PlayerCopy.DISPLAY_NAME_ERRORS.get(Flow.refusal_code(code), ""))
		_check(line == PlayerCopy.DISPLAY_NAME_PRICE_HIDDEN, "Selling nothing: the %s refusal names no price: %s" % [code, line])
	_check(Flow.refusal_code("display_name_refused") == "display_name_refused", "Selling nothing: other refusals keep their words")
	PollenSurfaces.set_shared_for_tests(true)
	_check(Flow.refusal_code("pollen_short") == "pollen_short" and Flow.refusal_code("name_change_price") == "name_change_price", "Selling: price refusals keep their words")
	PollenSurfaces.set_shared_for_tests(null)
	Wardrobe.use_shared(null)
	PollenWallet.use_shared(null)
	await process_frame

## The prompt on each build, with a change that costs 1,000 and a balance of 5,000.
func _name_prompt(sells: bool) -> void:
	var label := "Selling" if sells else "Selling nothing"
	var saved: Array = []
	var own: Dictionary = DisplayNames.new(_path("own")).own(SERVER, ME)
	own.name = "Robin"
	own.choice = "typed"
	var modal: Control = Prompt.open(page, {"own": own, "anonymous": "Kite 41", "platform": "", "edit": true,
		"price": {"price": 1000, "balance": 5000, "shown": sells},
		"save": func(choice: String, name: String) -> Dictionary: saved.append([choice, name]); return {"closed": false, "code": "busy"}})
	for i in range(3): await process_frame
	var prompt: Node = modal.find_child("DisplayNamePrompt", true, false)
	_check(prompt != null, "%s: the prompt opens" % label)
	if prompt == null: return
	prompt.field.text = "Robin Sky"
	prompt.field.text_changed.emit("Robin Sky")
	await process_frame
	var note: RichTextLabel = prompt._price_note
	if sells:
		_check(not prompt.save_button.disabled and prompt.save_button.accessibility_name == PlayerCopy.DISPLAY_NAME_SAVE_PRICED % "1,000" and _words(prompt.save_button) == [PlayerCopy.DISPLAY_NAME_SAVE_DOT, "1,000", PlayerCopy.WARDROBE_ABOUT % "$0.20"], "Selling: Save says the price with the grain and its money figure: " + str(_words(prompt.save_button)))
		_check(note.visible and note.text == PlayerCopy.DISPLAY_NAME_PRICE_NOTE % ["1,000", "$0.20"] and note.get_parsed_text().contains("1,000 Pollen"), "Selling: the note says the price and its money figure: " + note.text)
		prompt.field.text_submitted.emit("Robin Sky")
		for i in range(3): await process_frame
		_check(saved == [["typed", "Robin Sky"]], "Selling: Enter saves the priced change")
	else:
		_check(prompt.save_button.disabled and prompt.save_button.text == PlayerCopy.DISPLAY_NAME_SAVE and _words(prompt.save_button).is_empty(), "Selling nothing: Save waits and names no price")
		_check(note.visible and note.text == PlayerCopy.DISPLAY_NAME_PRICE_HIDDEN, "Selling nothing: the note says the free change is used: " + note.text)
		_check(not note.text.contains("$") and not note.text.contains("1,000") and not prompt.save_button.text.contains("Pollen") and not prompt._have_line.visible and prompt.find_child("PollenMark", true, false) == null, "Selling nothing: no price, grain or money figure")
		prompt.field.text_submitted.emit("Robin Sky")
		for i in range(3): await process_frame
		_check(saved.is_empty(), "Selling nothing: Enter never sends a change that costs")
		prompt.field.text = "Robin"
		prompt.field.text_changed.emit("Robin")
		await process_frame
		_check(not prompt.save_button.disabled and not note.visible, "Selling nothing: keeping the name is free and saves")
		prompt.anonymous_row.pressed.emit()
		await process_frame
		_check(not prompt.save_button.disabled and not note.visible and prompt.choice() == "anonymous", "Selling nothing: going anonymous is free and saves")
		prompt.field.text_submitted.emit("")
		for i in range(3): await process_frame
		_check(saved.size() == 1 and saved[0][0] == "anonymous", "Selling nothing: the free choice is sent: " + str(saved))
	if is_instance_valid(modal): modal.queue_free()
	for i in range(2): await process_frame
