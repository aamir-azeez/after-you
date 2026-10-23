extends SceneTree
## An iOS build that sells nothing (no App Store or Test Store configuration) lists only
## the free chapters: no paid or locked cards in Play Solo or Play with your friend, only
## the free earlier islands, no Full Journey offer on Home, no Check hosting access row
## and no Next island into a paid island. Android, desktop and iOS with a store show
## exactly what they showed before. Joining a friend's paid room keeps its card details.
## Home's keepsake and Hard totals, the keepsakes standing on Home, and What's new
## count and show the free chapters alone there, and nothing else changes elsewhere.

const Main = preload("res://main.gd")
const PlatformSupport = preload("res://services/platform_support.gd")
const Purchases = preload("res://services/purchases.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Storage = preload("res://services/local_save.gd")
const Keepsakes = preload("res://services/home_keepsakes.gd")
const Hub = preload("res://presentation/room_hub_screen.gd")
const SettingsRows = preload("res://presentation/settings_rows.gd")
const Catalog = preload("res://services/home_keepsake_catalog.gd")
const HardMode = preload("res://services/hard_mode.gd")
const Changelog = preload("res://services/changelog.gd")
## Earned places: a free chapter finished solo, so its hard plays open and Home shows
## the Hard count, and a paid place earned in a friend's room.
const EARNED := {"first-steps/a-little-lift": {"solo": true}, "first-steps/a-place-to-grow": {"solo": true},
	"rolling-home/weight-of-a-friend": {"solo": true, "friend": true}}

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
	_paid_places()
	_paid_lines()
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
	_check(app.home_keepsakes.adopt_earned(EARNED), "Seed the isolated keepsakes")

	# The reference: what desktop development builds show today.
	var baseline: Dictionary = await _surfaces(app, "", TESTER_ONLY)
	var paid_cards := 0
	for key: String in Registry.offered_keys():
		if Registry.descriptor(key).premium and not Registry.is_lighthouse(key): paid_cards += 1
	_check(baseline.paid_cards == paid_cards + 1 and baseline.locked_cards == baseline.paid_cards, "Play Solo lists every paid chapter, and the Lighthouse, locked")
	_check(baseline.free_cards > 0 and baseline.islands == 8 and baseline.home_offer and baseline.hosting_row and baseline.next_island, "Earlier islands, the Full Journey offer, hosting access and Next island are all there")
	_check(baseline.together_paid > 0 and baseline.together_locked == baseline.together_paid, "Play with your friend lists the paid chapters locked")
	_check(baseline.summary == PlayerCopy.SETTINGS_ACCOUNT_SUMMARY, "Account keeps its purchases summary")
	_check(baseline.store_rows == [false, false], "A desktop build without a store has no Full Journey or Restore row")
	baseline.erase("store_rows")
	var together_modes := 2 if app.hard_together() else 1
	_check(baseline.keepsakes == "Keepsakes · 4 / %d · " % Catalog.variant_total() + PlayerCopy.HARD_COUNT % [0, HardMode.eligible_keys().size() * together_modes] and Catalog.variant_total() == 64,
		"Home counts every keepsake and every hard play: " + baseline.keepsakes)
	_check(baseline.keepsake_places == _ids(Catalog.all()), "Every keepsake place has its slot on Home")
	var lines := _changelog_lines(false)
	_check(baseline.whats_new.opened and baseline.whats_new.card == lines.card and baseline.whats_new.earlier == lines.earlier and baseline.whats_new.versions == lines.versions, "What's new shows every highlight in the files")

	# Android and iOS with a store show exactly the same; their store rows show.
	for case: Array in [[PlatformSupport.ANDROID, TESTER_ONLY], [PlatformSupport.ANDROID, GOOGLE_PLAY], [PlatformSupport.IOS, APP_STORE], [PlatformSupport.IOS, TEST_STORE]]:
		var seen: Dictionary = await _surfaces(app, case[0], case[1])
		var with_store: bool = Purchases.store_enabled(case[1])
		_check(seen.store_rows == [with_store, with_store], "%s with %s shows Full Journey and Restore only with a store" % [case[0], case[1].purchase_mode])
		seen.erase("store_rows")
		_check(seen == baseline, "%s with %s shows what it showed before: %s" % [case[0], case[1].purchase_mode, _differences(seen, baseline)])
	PlatformSupport.override_platform = PlatformSupport.ANDROID
	app.config.merge(TESTER_ONLY, true)
	_check(await _store_reply(app) == ["store_disabled", "Google Play"], "Android without a store keeps its store message")
	app.config.merge({"purchase_mode": "google_play", "entitlement_id": "full_journey_play", "revenuecat_public_key": ""}, true)
	_check(await _paywall_says(app, PlayerCopy.MAIN_FC1F8BAE026C), "Android's store card without a key keeps its text")
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
		_check(not free.hosting_row and free.store_rows == [false, false], "Settings has no Check hosting access, Full Journey or Restore purchases row" + label)
		_check(free.summary == PlayerCopy.SETTINGS_ACCOUNT_SUMMARY_FREE, "Account's summary drops purchases" + label)
		_check(not free.next_island and free.next_island_free, "Finishing island 3 offers no Next island into a paid one; earlier islands still lead on" + label)
		# Free places: the earlier islands Earlier islands lists and the chapters Play Solo lists.
		var free_places: Array = Catalog.all().filter(func(item: Dictionary) -> bool:
			if item.family == "earlier": return Catalog.EARLIER_ROWS.slice(0, free.islands).any(func(row: Array) -> bool: return row[1] == item.stage_id)
			return "FreeChapter_" + str(item.family).replace("-", "_") in free.free_card_names)
		var free_total: int = free_places.reduce(func(total: int, item: Dictionary) -> int: return total + (2 if item.friend_available else 1), 0)
		var free_hard: int = HardMode.eligible_keys().filter(func(key: String) -> bool: return "FreeChapter_" + key.get_slice("@", 0).replace("-", "_") in free.free_card_names).size() * together_modes
		_check(free_total == 26 and free_hard == 5 * together_modes, "The free chapters hold 26 keepsakes and 5 hard chapters" + label)
		_check(free.keepsakes == "Keepsakes · 2 / %d · " % free_total + PlayerCopy.HARD_COUNT % [0, free_hard], "Home counts only the free keepsakes and hard plays, leaving out a paid place earned with a friend: " + free.keepsakes + label)
		_check(free.keepsake_places == _ids(free_places), "Only the free places stand on Home, so no paid outline is browsed" + label)
		var free_lines := _changelog_lines(true)
		_check(free.whats_new.opened and free.whats_new.card == free_lines.card and free.whats_new.earlier == free_lines.earlier and free.whats_new.versions == free_lines.versions, "What's new still opens, without a paid highlight or a version left with none" + label)
		_check(free.whats_new.versions < baseline.whats_new.versions and free.whats_new.earlier.size() < baseline.whats_new.earlier.size(), "What's new leaves the paid highlights out" + label)
		var reply: Array = await _store_reply(app)
		_check(reply == [("store_disabled" if not Purchases.store_enabled(config) else "android_required"), PlayerCopy.PURCHASES_49387E2DE82E_IOS], "A store request explains itself without the old free-chapter list" + label)
		# Only a store mode without a key reaches the card's own unavailable line.
		var card_text: bool = await _paywall_says(app, PlayerCopy.PURCHASES_49387E2DE82E_IOS)
		var old_text: bool = await _paywall_says(app, PlayerCopy.MAIN_FC1F8BAE026C)
		_check(card_text == Purchases.store_enabled(config) and not old_text, "The store card, if ever reached, drops the old free-chapter list too" + label)
		app.journey_flow.hard = true
		app.journey_flow.show_journey()
		await _settle()
		var hard_grid: GridContainer = app.overlay.find_child("JourneyChapters", true, false) as GridContainer
		_check(hard_grid != null and hard_grid.get_children().all(func(card: Node) -> bool: return not str(card.name).begins_with("PaidLevel_")), "Hard in Play Solo lists no paid chapter either" + label)
		app.journey_flow.hard = false


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

## Which places are paid, decided once from the level data.
func _paid_places() -> void:
	_check(Catalog.paid(Catalog.by_id("sleeping-lighthouse/borrowed-light")), "The Lighthouse's places are paid, through the chapter that earns them")
	_check(Catalog.paid(Catalog.by_id("rolling-home/weight-of-a-friend")) and not Catalog.paid(Catalog.by_id("first-steps/a-little-lift")), "A premium chapter's places are paid and a free chapter's are not")
	_check(not Catalog.paid(Catalog.by_id("earlier/long-way-home")) and Catalog.paid(Catalog.by_id("earlier/rising-together")), "The three first earlier islands are free, the rest paid")
	var earned: Array = [{"id": "rolling-home/weight-of-a-friend", "solo": true, "friend": true}, {"id": "first-steps/a-little-lift", "solo": true}]
	_check(Catalog.variant_count(earned) == 3 and Catalog.variant_count(earned, true) == 1, "A paid place earned with a friend counts only where paid content shows")
	_check(Catalog.variant_total(true) < Catalog.variant_total(), "The free total leaves out the paid places")
	_check(HardMode.new().count(false, true)[1] < HardMode.new().count(false)[1], "The free Hard total leaves out the paid chapters")

## The files flag paid lines, and only a build that hides paid content drops them.
func _paid_lines() -> void:
	var entries := Changelog.load_file()
	var archive := Changelog.load_archive()
	var paid_highlights: Array[String] = []
	var paid_paragraphs: Array[String] = []
	for entry: Dictionary in entries:
		for line: Dictionary in entry.highlights:
			if line.get("paid", false): paid_highlights.append(line.text)
		for paragraph: Dictionary in entry.paragraphs:
			if paragraph.get("paid", false): paid_paragraphs.append(paragraph.text)
	# The archive's paid highlights are checked on Earlier versions, in _surfaces().
	_check(not archive.filter(func(entry: Dictionary) -> bool: return entry.highlights.any(func(line: Dictionary) -> bool: return line.get("paid", false))).is_empty(), "The archive loads with paid highlights flagged")
	_check(paid_highlights.size() > 0 and paid_paragraphs.size() > 0, "The file loads with paid lines flagged")
	for channel: String in Changelog.CHANNELS:
		for platform: String in ["", PlatformSupport.ANDROID, PlatformSupport.IOS]:
			PlatformSupport.override_platform = platform
			var label := " (%s, %s)" % [channel, platform if not platform.is_empty() else "desktop"]
			_check(Changelog.load_entries(channel) == Changelog.for_channel(entries, channel), "Without the rule every line stays" + label)
			var free := Changelog.load_entries(channel, Changelog.PATH, true)
			var shown: Array = []
			for entry: Dictionary in free:
				shown.append_array(entry.highlights.map(func(line: Dictionary) -> String: return line.text))
				shown.append_array(entry.paragraphs)
			_check(paid_highlights.all(func(text: String) -> bool: return text not in shown), "The rule drops every paid highlight" + label)
			_check(paid_paragraphs.all(func(text: String) -> bool: return text not in shown), "The rule drops every paid paragraph" + label)
			_check(not free.is_empty() and free[0].version == entries[0].version, "This version's notes stay" + label)
	PlatformSupport.override_platform = PlatformSupport.ANDROID
	var play: Array = []
	for entry: Dictionary in Changelog.load_entries(Changelog.PLAY): play.append_array(entry.paragraphs)
	_check(paid_paragraphs.all(func(text: String) -> bool: return text in play), "Android keeps its paid paragraphs")
	PlatformSupport.override_platform = ""

## What What's new should show from the files: this version's highlights, and every
## earlier version's highlights and how many versions list; `paid_hidden` leaves out
## paid ones and a version left with none.
func _changelog_lines(paid_hidden: bool) -> Dictionary:
	var keep := func(line: Dictionary) -> bool: return not (paid_hidden and line.get("paid", false))
	var entries := Changelog.load_file()
	var result := {"card": entries[0].highlights.filter(keep).map(func(line: Dictionary) -> String: return line.text), "earlier": [], "versions": 0}
	for entry: Dictionary in entries.slice(1) + Changelog.load_archive():
		var lines: Array = entry.highlights.filter(keep).map(func(line: Dictionary) -> String: return line.text)
		if lines.is_empty(): continue
		result.versions += 1
		result.earlier.append_array(lines)
	return result

## What's new as opened from Home: its card's highlights, then Earlier versions with
## every version opened.
func _whats_new(app: Node) -> Dictionary:
	app._open_whats_new_card()
	await _settle()
	var card: Control = app._whats_new_card
	var result := {"opened": is_instance_valid(card), "card": [], "earlier": [], "versions": 0}
	if not result.opened: return result
	result.card = _highlight_texts(card)
	var earlier: Button = card.find_child("WhatsNewEarlier", true, false) as Button
	if earlier != null: earlier.pressed.emit()
	await _settle()
	var versions: Node = card.find_child("WhatsNewVersions", true, false)
	if versions != null:
		for holder: Node in versions.get_children():
			var row := holder.get_child(0) as Button if holder.get_child_count() > 0 else null
			if row == null: continue
			result.versions += 1
			row.pressed.emit()
		await _settle()
		result.earlier = _highlight_texts(versions)
	card.close(false)
	await _settle()
	return result

func _highlight_texts(node: Node) -> Array:
	var result: Array = []
	for list: Node in node.find_children("WhatsNewHighlights", "", true, false):
		for label: Label in list.find_children("*", "Label", true, false): result.append(label.text)
	return result

func _ids(items: Array) -> Array[String]:
	var result: Array[String] = []
	for item: Dictionary in items: result.append(item.id)
	result.sort()
	return result

## What every paid surface shows on `platform` with `config`.
func _surfaces(app: Node, platform: String, config: Dictionary) -> Dictionary:
	PlatformSupport.override_platform = platform
	PlatformSupport.override_release = true
	for key: String in ["purchase_mode", "entitlement_id", "revenuecat_public_key"]: app.config.erase(key)
	app.config.merge(config, true)
	app.api.player_id = ""
	var seen := {}
	app.journey_flow.hard = false
	app.journey_flow.show_journey()
	await _settle()
	var grid: GridContainer = app.overlay.find_child("JourneyChapters", true, false) as GridContainer
	var cards: Array = grid.get_children() if grid != null else []
	seen.paid_cards = cards.filter(func(card: Node) -> bool: return str(card.name).begins_with("PaidLevel_")).size()
	seen.free_card_names = cards.map(func(card: Node) -> String: return str(card.name)).filter(func(card_name: String) -> bool: return card_name.begins_with("FreeChapter_"))
	seen.free_cards = seen.free_card_names.size()
	seen.locked_cards = cards.filter(func(card: Node) -> bool: return bool(card.get_meta("full_journey_locked", false))).size()
	seen.columns = grid.columns if grid != null else 0
	# A grid reflows over its visible cards; a card left in but hidden would leave a hole.
	seen.hidden_cards = cards.filter(func(card: Node) -> bool: return not (card as Control).visible).size()
	var together: Array[Dictionary] = app.room_hub_flow.together_chapters()
	seen.together_paid = together.filter(func(item: Dictionary) -> bool: return item.premium).size()
	seen.together_free = together.size() - seen.together_paid
	seen.together_locked = together.filter(func(item: Dictionary) -> bool: return item.locked).size()
	app.journey_flow.show_earlier_islands()
	await _settle()
	seen.islands = _buttons_starting(app.overlay, ["01  ", "02  ", "03  ", "04  ", "05  ", "06  ", "07  ", "08  "])
	seen.island_scroll = _island_row(app.overlay) != null and _scroll_of(_island_row(app.overlay)) != null
	app._show_home()
	await _settle()
	var offer: Control = app.overlay.find_child("HomeFullJourney", true, false) as Control
	seen.home_offer = offer != null and offer.visible
	var stage: Node = app.home_stage_view
	var count: Label = stage.find_child("KeepsakeCount", true, false) as Label
	seen.keepsakes = count.text if count != null else ""
	var places: Array[String] = stage._keepsake_display.slot_ids() if is_instance_valid(stage._keepsake_display) else []
	places.sort()
	seen.keepsake_places = places
	seen.whats_new = await _whats_new(app)
	app.api.player_id = "P".repeat(22)
	app.settings_flow.show_settings(SettingsRows.ACCOUNT)
	await _settle()
	var hosting: Control = app.overlay.find_child("hosting_access", true, false) as Control
	seen.hosting_row = hosting != null and hosting.is_visible_in_tree()
	var category: Node = app.overlay.find_child("category_" + SettingsRows.ACCOUNT, true, false)
	var summary: Label = category.find_child("Summary", true, false) as Label if category != null else null
	seen.summary = summary.text if summary != null else ""
	# Full Journey and Restore purchases follow the store; _store_rows() says when they show.
	var store_rows: Array[bool] = []
	for id: String in ["full_journey", "restore_purchases"]:
		var row: Control = app.overlay.find_child(id, true, false) as Control
		store_rows.append(row != null and row.is_visible_in_tree())
	seen.store_rows = store_rows
	app.api.player_id = ""
	seen.next_island = await _offers_next_island(app, 2)
	seen.next_island_free = await _offers_next_island(app, 1)
	app._show_home()
	await _settle()
	PlatformSupport.override_release = false
	return seen

## The error code and message a store request gets in this build.
func _store_reply(app: Node) -> Array:
	var errors: Array = []
	var probe := Purchases.new()
	probe._configuration = app.config.duplicate()
	app.add_child(probe)
	probe.failed.connect(func(_id, _operation, code, text, _cancelled): errors.append([code, text]))
	probe.purchase("default", "$rc_monthly")
	await process_frame
	await process_frame
	probe.queue_free()
	return errors[0] if not errors.is_empty() else []

## Whether the Full Journey store card shows `text`, as when a guest's replay reaches it.
func _paywall_says(app: Node, text: String) -> bool:
	app.store_flow.show_paywall()
	await _settle()
	var found := false
	for label: Label in app.overlay.find_children("*", "Label", true, false):
		if label.text == text and not label.is_queued_for_deletion(): found = true
	app._show_home()
	await _settle()
	return found

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
