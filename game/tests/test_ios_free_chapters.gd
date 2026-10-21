extends SceneTree
## An iOS build that sells nothing (no App Store or Test Store configuration) lists only
## the free chapters: no paid or locked cards in Play Solo or Play with your friend, only
## the free earlier islands, no Full Journey offer on Home, no Check hosting access row
## and no Next island into a paid island. Android, desktop and iOS with a store show
## exactly what they showed before. Joining a friend's paid room keeps its card details.

const Main = preload("res://main.gd")
const PlatformSupport = preload("res://services/platform_support.gd")
const Purchases = preload("res://services/purchases.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Storage = preload("res://services/local_save.gd")
const Keepsakes = preload("res://services/home_keepsakes.gd")
const Hub = preload("res://presentation/room_hub_screen.gd")
const SettingsRows = preload("res://presentation/settings_rows.gd")

const TESTER_ONLY := {"purchase_mode": "tester_only", "entitlement_id": "full_journey", "revenuecat_public_key": ""}
const APP_STORE := {"purchase_mode": "app_store", "entitlement_id": "full_journey_play", "revenuecat_public_key": "appl_synthetic_key"}
const APP_STORE_NO_KEY := {"purchase_mode": "app_store", "entitlement_id": "full_journey_play", "revenuecat_public_key": ""}
const TEST_STORE := {"purchase_mode": "test_store", "entitlement_id": "full_journey", "revenuecat_public_key": "test_synthetic_key"}
const GOOGLE_PLAY := {"purchase_mode": "google_play", "entitlement_id": "full_journey_play", "revenuecat_public_key": "goog_synthetic_key"}

var checks := 0
var failures := 0
var paths: Array[String] = []

class FakeStore extends Purchases:
	func _connect_native() -> bool: return true
	func is_available() -> bool: return true
	func has_entitlement(_entitlement_id: String = "") -> bool: return false
	func has_subscription() -> bool: return false

## Main with no tester code, no purchase and a ready identity.
class App extends Main:
	func _tester_checks_enabled() -> bool: return false
	func _tester_active() -> bool: return false
	func _relay_identity() -> Dictionary: return {"ready": true, "player_id": "P".repeat(22), "epoch": 1}

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	_rule()
	var path := _path("ios-free")
	var storage := Storage.new(path)
	storage.data.settings.sound = false
	storage.data.settings.haptics = false
	_check(storage.flush(), "Use an isolated muted save")
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.handle_input_locally = true
	root.add_child(viewport)
	var app := App.new()
	app.saves = storage
	app.home_keepsakes = Keepsakes.new(_path("ios-free-keepsakes"))
	viewport.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	app.world.set_process(false)
	app.home_keepsakes.cancel_backfill()
	app.purchases.queue_free()
	var store := FakeStore.new()
	app.purchases = store
	app.add_child(store)

	# The reference: what desktop development builds show today.
	var baseline: Dictionary = await _surfaces(app, "", TESTER_ONLY)
	var paid_cards := 0
	for key: String in Registry.offered_keys():
		if Registry.descriptor(key).premium and not Registry.is_lighthouse(key): paid_cards += 1
	_check(baseline.paid_cards == paid_cards + 1 and baseline.locked_cards == baseline.paid_cards, "Play Solo lists every paid chapter, and the Lighthouse, locked")
	_check(baseline.free_cards > 0 and baseline.islands == 8 and baseline.home_offer and baseline.hosting_row and baseline.next_island, "Earlier islands, the Full Journey offer, hosting access and Next island are all there")
	_check(baseline.together_paid > 0 and baseline.together_locked == baseline.together_paid, "Play with your friend lists the paid chapters locked")
	_check(baseline.summary == PlayerCopy.SETTINGS_ACCOUNT_SUMMARY, "Account keeps its purchases summary")

	# Android and iOS with a store show exactly the same.
	for case: Array in [[PlatformSupport.ANDROID, TESTER_ONLY], [PlatformSupport.ANDROID, GOOGLE_PLAY], [PlatformSupport.IOS, APP_STORE], [PlatformSupport.IOS, TEST_STORE]]:
		var seen: Dictionary = await _surfaces(app, case[0], case[1])
		_check(seen == baseline, "%s with %s shows what it showed before: %s" % [case[0], case[1].purchase_mode, _differences(seen, baseline)])
	PlatformSupport.override_platform = PlatformSupport.ANDROID
	app.config.merge(TESTER_ONLY, true)
	_check(await _store_text(app) == "Google Play", "Android without a store keeps its store message")
	PlatformSupport.override_platform = ""

	# iOS with purchases off: the free chapters alone.
	for config: Dictionary in [TESTER_ONLY, APP_STORE_NO_KEY]:
		var free: Dictionary = await _surfaces(app, PlatformSupport.IOS, config)
		var label := " (%s%s)" % [config.purchase_mode, "" if not str(config.revenuecat_public_key).is_empty() else ", no key"]
		_check(free.paid_cards == 0 and free.locked_cards == 0, "Play Solo shows no paid and no locked chapter" + label)
		_check(free.free_cards == baseline.free_cards, "Play Solo still shows every free chapter" + label)
		_check(free.columns == baseline.columns and free.hidden_cards == 0, "The free cards fill the same grid with no hidden card leaving a hole" + label)
		_check(free.together_paid == 0 and free.together_locked == 0 and free.together_free == baseline.together_free, "Play with your friend lists only the free chapters, none locked" + label)
		_check(free.islands == 3 and not free.island_scroll, "Earlier islands lists the three free islands with no empty scroll space" + label)
		_check(not free.home_offer, "Home has no Full Journey button" + label)
		_check(not free.hosting_row, "Settings has no Check hosting access row" + label)
		_check(free.summary == PlayerCopy.SETTINGS_ACCOUNT_SUMMARY_FREE, "Account's summary drops purchases" + label)
		_check(not free.next_island and free.next_island_free, "Finishing island 3 offers no Next island into a paid one; earlier islands still lead on" + label)
		_check(await _store_text(app) == PlayerCopy.PURCHASES_49387E2DE82E_IOS, "A store request explains itself without the old free-chapter list" + label)

	# A friend's paid room joined from a free-only build keeps its part count.
	PlatformSupport.override_platform = PlatformSupport.IOS
	app.config.merge(TESTER_ONLY, true)
	var premium := ""
	for key: String in Registry.offered_keys():
		if Registry.descriptor(key).premium and int(Registry.descriptor(key).get("stage_count", 1)) > 1:
			premium = key
			break
	var hub := Hub.new()
	hub.set_chapters(app.room_hub_flow.together_chapters())
	_check(not premium.is_empty() and hub._part_line({"chapter_key": premium, "part": 1}) == "Part 1 / %d" % int(Registry.descriptor(premium).stage_count), "A joined paid room still shows its part count")
	hub.free()

	PlatformSupport.override_platform = ""
	PlatformSupport.override_release = false
	viewport.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.15).timeout
	for item: String in paths:
		for suffix: String in ["", ".tmp", ".bak", ".backup"]:
			if FileAccess.file_exists(item + suffix): DirAccess.remove_absolute(item + suffix)
	print("AFTER YOU iOS FREE CHAPTERS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## The rule on its own: iOS without a store, or without a store key, hides paid content.
func _rule() -> void:
	for platform: String in ["", PlatformSupport.ANDROID]:
		PlatformSupport.override_platform = platform
		for config: Dictionary in [TESTER_ONLY, APP_STORE, APP_STORE_NO_KEY, TEST_STORE, GOOGLE_PLAY, {}]:
			_check(not Purchases.paid_content_hidden(config), "%s never hides paid content (%s)" % [platform if not platform.is_empty() else "desktop", config.get("purchase_mode", "no config")])
	PlatformSupport.override_platform = PlatformSupport.IOS
	_check(Purchases.paid_content_hidden(TESTER_ONLY) and Purchases.paid_content_hidden(GOOGLE_PLAY) and Purchases.paid_content_hidden({}), "iOS without a store it can use hides paid content")
	_check(Purchases.paid_content_hidden(APP_STORE_NO_KEY), "iOS with an App Store mode but no key hides paid content")
	_check(not Purchases.paid_content_hidden(APP_STORE) and not Purchases.paid_content_hidden(TEST_STORE), "iOS that sells through the App Store or the Test Store shows paid content")
	PlatformSupport.override_platform = ""

## What every paid surface shows on `platform` with `config`.
func _surfaces(app: Node, platform: String, config: Dictionary) -> Dictionary:
	PlatformSupport.override_platform = platform
	PlatformSupport.override_release = true
	for key: String in ["purchase_mode", "entitlement_id", "revenuecat_public_key"]: app.config.erase(key)
	app.config.merge(config, true)
	app.api.player_id = ""
	var seen := {}
	app._journey_hard = false
	app._show_journey()
	await _settle()
	var grid: GridContainer = app.overlay.find_child("JourneyChapters", true, false) as GridContainer
	var cards: Array = grid.get_children() if grid != null else []
	seen.paid_cards = cards.filter(func(card: Node) -> bool: return str(card.name).begins_with("PaidLevel_")).size()
	seen.free_cards = cards.filter(func(card: Node) -> bool: return str(card.name).begins_with("FreeChapter_")).size()
	seen.locked_cards = cards.filter(func(card: Node) -> bool: return bool(card.get_meta("full_journey_locked", false))).size()
	seen.columns = grid.columns if grid != null else 0
	# A grid reflows over its visible cards; a card left in but hidden would leave a hole.
	seen.hidden_cards = cards.filter(func(card: Node) -> bool: return not (card as Control).visible).size()
	var together: Array[Dictionary] = app.room_hub_flow.together_chapters()
	seen.together_paid = together.filter(func(item: Dictionary) -> bool: return item.premium).size()
	seen.together_free = together.size() - seen.together_paid
	seen.together_locked = together.filter(func(item: Dictionary) -> bool: return item.locked).size()
	app._show_earlier_islands()
	await _settle()
	seen.islands = _buttons_starting(app.overlay, ["01  ", "02  ", "03  ", "04  ", "05  ", "06  ", "07  ", "08  "])
	seen.island_scroll = _island_row(app.overlay) != null and _scroll_of(_island_row(app.overlay)) != null
	app._show_home()
	await _settle()
	var offer: Control = app.overlay.find_child("HomeFullJourney", true, false) as Control
	seen.home_offer = offer != null and offer.visible
	app.api.player_id = "P".repeat(22)
	app.settings_flow.show_settings(SettingsRows.ACCOUNT)
	await _settle()
	var hosting: Control = app.overlay.find_child("hosting_access", true, false) as Control
	seen.hosting_row = hosting != null and hosting.is_visible_in_tree()
	var category: Node = app.overlay.find_child("category_" + SettingsRows.ACCOUNT, true, false)
	var summary: Label = category.find_child("Summary", true, false) as Label if category != null else null
	seen.summary = summary.text if summary != null else ""
	app.api.player_id = ""
	seen.next_island = await _offers_next_island(app, 2)
	seen.next_island_free = await _offers_next_island(app, 1)
	app._show_home()
	await _settle()
	PlatformSupport.override_release = false
	return seen

## The message a store request gets in this build, as a player would read it.
func _store_text(app: Node) -> String:
	var errors: Array = []
	var probe := Purchases.new()
	probe._configuration = app.config.duplicate()
	app.add_child(probe)
	probe.failed.connect(func(_id, _operation, _code, text, _cancelled): errors.append(text))
	probe.purchase("default", "$rc_monthly")
	await process_frame
	await process_frame
	probe.queue_free()
	return str(errors[0]) if not errors.is_empty() else ""

## Whether the solo celebration after earlier island `index` offers Next island.
func _offers_next_island(app: Node, index: int) -> bool:
	app.room_play = false
	app.level_index = index
	app.current_level = app.levels[index]
	app._show_celebration()
	await _settle()
	return _button(app.overlay, "Next island") != null

func _buttons_starting(node: Node, prefixes: Array) -> int:
	var count := 0
	for button: Button in node.find_children("*", "Button", true, false):
		if not button.is_visible_in_tree() or button.is_queued_for_deletion(): continue
		for prefix: String in prefixes:
			if button.text.begins_with(prefix): count += 1
	return count

func _island_row(node: Node) -> Button:
	for button: Button in node.find_children("*", "Button", true, false):
		if button.text.begins_with("01  ") and not button.is_queued_for_deletion(): return button
	return null

func _scroll_of(control: Control) -> ScrollContainer:
	var parent: Node = control.get_parent()
	while parent != null and not parent is ScrollContainer: parent = parent.get_parent()
	return parent as ScrollContainer

func _button(node: Node, value: String) -> Button:
	if node is Button and node.text == value and node.is_visible_in_tree() and not node.is_queued_for_deletion(): return node
	for child: Node in node.get_children():
		var found := _button(child, value)
		if found != null: return found
	return null

func _differences(seen: Dictionary, expected: Dictionary) -> String:
	var result: Array[String] = []
	for key: String in expected:
		if seen.get(key) != expected[key]: result.append("%s %s != %s" % [key, seen.get(key), expected[key]])
	for key: String in seen:
		if not expected.has(key): result.append("extra " + key)
	return "same" if result.is_empty() else ", ".join(result)

func _settle() -> void:
	await process_frame
	await process_frame

func _path(label: String) -> String:
	var result := "user://test-%s-%d.json" % [label, Time.get_ticks_usec()]
	paths.append(result)
	return result

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
