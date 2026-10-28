extends SceneTree
## Which Pollen parts each build shows (services/pollen_surfaces.gd):
## - Android, desktop and iOS with a store show every part;
## - iOS that sells nothing (Purchases.paid_content_hidden) shows earning, the
##   balance and the Wardrobe, and hides the shop, every price and Full Journey;
## - the name change on both builds: the selling build says the price and its
##   money figure; the build that sells nothing names no price and never sends
##   a change that costs, while a free change and going anonymous still save.
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
	PlatformSupport.override_platform = ""
	PollenSurfaces.set_shared_for_tests(false)
	_check(_parts(PollenSurfaces.shared()) == EARN_AND_WEAR, "Tests can pick the build that sells nothing")
	PollenSurfaces.set_shared_for_tests(true)
	_check(_parts(PollenSurfaces.shared()) == EVERY_PART, "and the one that sells")
	PollenSurfaces.set_shared_for_tests(null)
	_check(PollenSurfaces.shared() == PollenSurfaces.shared(), "The shared answer is read once")

## The flow hands the prompt the price with whether this build may show it.
func _name_price() -> void:
	var store: RefCounted = Wardrobe.new(_path("wardrobe"))
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
	_check(Flow.name_price(current) == {"price": 1000, "balance": 5000, "shown": true}, "Selling: the price, the balance and that it shows: " + str(Flow.name_price(current)))
	PollenSurfaces.set_shared_for_tests(false)
	_check(Flow.name_price(current) == {"price": 1000, "balance": 5000, "shown": false}, "Selling nothing: the same price, marked not shown")
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
	var note: Label = prompt._price_note
	if sells:
		_check(not prompt.save_button.disabled and prompt.save_button.text == PlayerCopy.DISPLAY_NAME_SAVE_PRICED % "1,000", "Selling: Save says the price")
		_check(note.visible and note.text == PlayerCopy.DISPLAY_NAME_PRICE_NOTE % ["1,000", "$0.20"], "Selling: the note says the price and its money figure: " + note.text)
		prompt.field.text_submitted.emit("Robin Sky")
		for i in range(3): await process_frame
		_check(saved == [["typed", "Robin Sky"]], "Selling: Enter saves the priced change")
	else:
		_check(prompt.save_button.disabled and prompt.save_button.text == PlayerCopy.DISPLAY_NAME_SAVE, "Selling nothing: Save waits and names no price")
		_check(note.visible and note.text == PlayerCopy.DISPLAY_NAME_PRICE_HIDDEN, "Selling nothing: the note says the free change is used: " + note.text)
		_check(not note.text.contains("$") and not note.text.contains("1,000") and not prompt.save_button.text.contains("Pollen"), "Selling nothing: no price or money figure")
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
