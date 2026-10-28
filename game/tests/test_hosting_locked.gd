extends SceneTree
## Locked hosting page and the host entitlement split between the GitHub Test
## Store build (solo purchase only; hosting needs a tester code) and a Google
## Play build (a purchase grants solo and cooperative hosting). In the Test Store
## build a player who owns Full Journey without a code is told a tester code is
## what hosting needs, and the card or host button opens the Tester code screen.

const Main = preload("res://tests/unlocked_main.gd")
const Purchases = preload("res://services/purchases.gd")
const Storage = preload("res://services/local_save.gd")
const Registry = preload("res://services/chapter_registry.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const Hub = preload("res://presentation/room_hub_screen.gd")
const Unlocks = preload("res://services/chapter_unlocks.gd")
const UnlockFixture = preload("res://tests/unlock_fixture.gd")
const TEST_STORE := {"purchase_mode": "test_store", "entitlement_id": "full_journey"}
const GOOGLE_PLAY := {"purchase_mode": "google_play", "entitlement_id": "full_journey_play"}

var checks := 0
var failures := 0
var paths: Array[String] = []

class FakeStore extends Purchases:
	var entitled := false
	var available := true
	func _connect_native() -> bool: return true
	func is_available() -> bool: return available
	func has_entitlement(_entitlement_id: String = "") -> bool: return entitled

## Main with the accepted tester code and account readiness set by the test.
class App extends Main:
	var tester := false
	func _tester_active() -> bool: return tester
	func _relay_identity() -> Dictionary: return {"ready": true, "player_id": "P".repeat(22), "epoch": 1}

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var premium := ""
	for key: String in Registry.keys():
		if Registry.descriptor(key).get("premium", false):
			premium = key
			break
	_check(not premium.is_empty(), "A premium cooperative chapter exists to gate hosting")
	_rule()
	var scene := App.new()
	scene.saves = Storage.new(_path("hosting"))
	root.add_child(scene)
	scene.set_process(false)
	scene.set_physics_process(false)
	scene.world.set_process(false)
	scene.purchases.queue_free()
	var store := FakeStore.new()
	scene.purchases = store
	scene.add_child(store)
	scene.store_flow.purchase_offer = {"offering_id": "offer", "packages": [
		{"price": "$0.99", "offering_id": "offer", "id": "$rc_monthly", "type": "MONTHLY", "period": "month"},
		{"price": "$9.99", "offering_id": "offer", "id": "$rc_annual", "type": "ANNUAL", "period": "year"}]}

	# --- Entitlement split -------------------------------------------------
	scene.config.purchase_mode = "test_store"
	scene.config.entitlement_id = "full_journey"
	store.entitled = false
	_check(not scene._hosting_entitled(), "No purchase and no tester code cannot host in the Test Store build")
	store.entitled = true
	_check(not scene._hosting_entitled(), "A Test Store purchase unlocks solo only and still cannot host")
	scene.config.purchase_mode = "google_play"
	scene.config.entitlement_id = "full_journey_play"
	scene.config.revenuecat_public_key = "goog_synthetic"
	store.entitled = false
	_check(not scene._hosting_entitled(), "Without a purchase a Google Play build cannot host either")
	store.entitled = true
	_check(scene._hosting_entitled(), "A Google Play purchase grants cooperative hosting")

	# --- Google Play locked page ------------------------------------------
	store.entitled = false
	store.available = true
	scene.store_flow.show_hosting_locked(premium)
	await process_frame
	await process_frame
	_check(scene.mode == "paywall" and _find(scene, "HostingLocked") != null, "Hosting a locked chapter opens the locked hosting page")
	var unlock := _find(scene, "Subscribe_month") as Button
	var yearly := _find(scene, "Subscribe_year") as Button
	_check(unlock != null and unlock.text == "Subscribe · $0.99 a month" and yearly != null and yearly.text == "Subscribe · $9.99 a year", "Google Play locked hosting shows both subscriptions with the real store price per period")
	_check(_find(scene, "HostingLockedUnlock") == null and _text(scene, PlayerCopy.SUBSCRIPTION_TERMS_PLAY), "Locked hosting offers the subscriptions directly with their renewal terms")
	_check(_text(scene, PlayerCopy.COOPERATIVE_HOST_ACCESS), "Locked hosting says only the host needs Full Journey and a friend joins free")
	_check(_button(scene, "Restore purchases") != null, "Google Play locked hosting offers Restore purchases")
	_check(_find(scene, "HostingLockedTester") == null, "Google Play locked hosting does not route to a tester code")
	_check(_hero(scene) != null, "Locked hosting shows the selected chapter artwork")
	_check(_button(scene, "Back") != null, "Locked hosting keeps a Back control")
	_check(_text(scene, "Host a room") and _text(scene, PlayerCopy.SUBSCRIPTION_PURPOSE) and not _text(scene, "One-time purchase"), "Google Play locked hosting is titled Host a room and names the subscription and what it pays for")
	if _hero(scene) != null and unlock != null:
		_check(_hero(scene).get_global_rect().get_center().x < unlock.get_global_rect().position.x, "The chapter picture sits left of the purchase details")
	var back := _button(scene, "Back")
	if back != null and unlock != null:
		_check(back.get_global_rect().end.y <= _hero(scene).get_global_rect().position.y and back.get_global_rect().end.y <= unlock.get_global_rect().position.y, "Back stays in the header above the picture and details")
		back.pressed.emit()
		await process_frame
		_check(scene.mode != "paywall" and _find(scene, "HostingLocked") == null, "Locked hosting Back leaves for the rooms screen")
		scene.store_flow.show_hosting_locked(premium)
		await process_frame
		await process_frame
	# A short safe area (cutouts plus a tall system bar) keeps Back fixed and
	# scrolls the details so every action is still reachable.
	var full := scene.get_viewport().get_visible_rect()
	var tight := Rect2(full.position + Vector2(96, 40), full.size - Vector2(144, 340))
	scene._apply_safe_area(tight)
	scene.store_flow.show_hosting_locked(premium)
	for i in range(4): await process_frame
	var short_back := _button(scene, "Back")
	_check(short_back != null and tight.grow(0.5).encloses(short_back.get_global_rect()) and _scroll_of(short_back) == null, "Back stays fixed inside a short safe area")
	var scrolled := false
	for label: String in ["Restore purchases"]:
		var action := _button(scene, label)
		var scroll: ScrollContainer = _scroll_of(action) if action != null else null
		_check(action != null and scroll != null, "Locked hosting details scroll internally: " + label)
		if scroll == null: continue
		scrolled = scrolled or scroll.get_v_scroll_bar().max_value > scroll.get_v_scroll_bar().page
		scroll.ensure_control_visible(action)
		await process_frame
		await process_frame
		_check(tight.grow(0.5).encloses(action.get_global_rect()) and scroll.get_global_rect().grow(0.5).encloses(action.get_global_rect()), "Locked hosting action is reachable in a short safe area: " + label)
	_check(scrolled, "The short safe area genuinely needs the details scroll")
	var short_unlock := _find(scene, "Subscribe_year") as Button
	if short_unlock != null:
		_scroll_of(short_unlock).ensure_control_visible(short_unlock)
		await process_frame
		await process_frame
		_check(tight.grow(0.5).encloses(short_unlock.get_global_rect()) and short_unlock.size.y >= 48, "Unlock keeps a full touch target in a short safe area")
	scene._apply_safe_area(full)
	await process_frame

	# A Google Play build without a store price must not fabricate one.
	store.available = false
	scene.store_flow.show_hosting_locked(premium)
	await process_frame
	var plain := _find(scene, "HostingLockedUnlock") as Button
	_check(plain != null and not ("$" in plain.text), "No price is shown until the store provides one")

	# --- Test Store locked page -------------------------------------------
	scene.config.purchase_mode = "test_store"
	scene.config.entitlement_id = "full_journey"
	store.entitled = true
	scene.store_flow.show_hosting_locked(premium)
	await process_frame
	await process_frame
	_check(_find(scene, "HostingLockedTester") != null, "Test Store locked hosting offers tester code access")
	_check(_text(scene, PlayerCopy.HOSTING_NEEDS_TESTER_CODE) and not _text(scene, PlayerCopy.MAIN_FAD34E850ED9), "Owning Full Journey through the Test Store, locked hosting says a tester code is what is missing")
	_check(_find(scene, "HostingLockedUnlock") == null, "Test Store locked hosting hides a purchase that would not unlock hosting")
	_check(not _text(scene, PlayerCopy.SUBSCRIPTION_PURPOSE) and _find(scene, "Subscribe_month") == null, "Test Store locked hosting names no purchase it cannot offer")
	store.entitled = false
	scene.store_flow.show_hosting_locked(premium)
	await process_frame
	_check(_text(scene, PlayerCopy.MAIN_FAD34E850ED9) and not _text(scene, PlayerCopy.HOSTING_NEEDS_TESTER_CODE) and _find(scene, "HostingLockedTester") != null, "Without a Test Store purchase locked hosting keeps the earlier text")

	await _together(scene, store, premium)
	await _chain(scene, store)

	root.remove_child(scene)
	scene.queue_free()
	await process_frame
	for path: String in paths:
		for suffix: String in ["", ".tmp", ".backup"]:
			if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	print("HOSTING LOCKED: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## The shared lock rule across build mode, ownership and an accepted tester code.
func _rule() -> void:
	var disabled := {}
	for build: Array in [["Test Store", TEST_STORE], ["Google Play", GOOGLE_PLAY], ["store off", disabled]]:
		var configuration: Dictionary = build[1]
		for owned: bool in [false, true]:
			for tester: bool in [false, true]:
				var expected := ""
				if tester: expected = ""
				elif configuration == TEST_STORE: expected = Purchases.HOSTING_NEEDS_TESTER_CODE if owned else Purchases.HOSTING_NEEDS_FULL_JOURNEY
				elif not owned: expected = Purchases.HOSTING_NEEDS_FULL_JOURNEY
				var actual := Purchases.hosting_lock_reason(configuration, owned, tester)
				_check(actual == expected, "Hosting lock for %s, owned %s, tester code %s: %s (got %s)" % [build[0], owned, tester, expected, actual])
	_check(Purchases.HOSTING_NEEDS_TESTER_CODE != Purchases.HOSTING_NEEDS_FULL_JOURNEY and not Purchases.HOSTING_NEEDS_TESTER_CODE.is_empty(), "The two lock reasons are distinct and non-empty")

## Play with a friend: the card text, the tap and the host button for each state.
func _together(scene: App, store: FakeStore, premium: String) -> void:
	for state: Array in [["test_store", true, false, true], ["test_store", false, false, false], ["test_store", true, true, false], ["google_play", false, false, false], ["google_play", true, false, false]]:
		var label := "%s, owned %s, tester code %s" % state.slice(0, 3)
		scene.config.merge(TEST_STORE if state[0] == "test_store" else GOOGLE_PLAY, true)
		store.entitled = state[1]
		scene.tester = state[2]
		var hint: bool = state[3]
		var open_to_host: bool = scene._hosting_entitled()
		_check(open_to_host == (scene._hosting_lock_reason() == ""), "Hosting access follows the shared lock reason: " + label)
		var item := {}
		for entry: Dictionary in scene.room_hub_flow.together_chapters():
			if entry.key == premium: item = entry
		_check(item.get("locked", false) == (not open_to_host), "Paid card lock follows hosting access: " + label)
		_check((item.get("note", "") == PlayerCopy.HOSTING_NEEDS_TESTER_CODE) == hint, "The tester code line shows only when owned through the Test Store without a code: " + label)
		scene._show_home()
		scene.room_hub_flow.open_hub("", false)
		var hub: Hub = scene.room_hub_flow.screen
		for i in range(2): await process_frame
		_check(hub != null and hub.tester_code_requested.is_connected(scene.room_hub_flow._open_tester_code), "The room hub routes tester code requests to its flow: " + label)
		if hub == null: continue
		hub.open_chapter_picker()
		await process_frame
		var card: Control = hub._picker.card_for(premium)
		var access := card.find_child("ChapterAccess", true, false) as Label if card != null else null
		var open := card.find_child("ChapterOpen", true, false) as Button if card != null else null
		if hint:
			_check(access != null and access.text == PlayerCopy.HOSTING_NEEDS_TESTER_CODE and access.autowrap_mode != TextServer.AUTOWRAP_OFF and access.get_theme_color("font_color") == hub._picker.GOLD, "The paid card says hosting needs a tester code, wrapped in the locked gold")
			_check(open != null and open.locked and PlayerCopy.HOSTING_NEEDS_TESTER_CODE in str(open.accessibility_name), "The card stays locked and its button names the reason")
			# Host button with the paid chapter selected: the note and a Tester code button.
			hub._selected_key = premium
			hub._update_hero()
			var note := hub.find_child("HostLockNote", true, false) as Label
			var host := hub.find_child("HostRoom", true, false) as Button
			_check(note != null and note.visible and note.text == PlayerCopy.HOSTING_NEEDS_TESTER_CODE and host != null and host.text == "Tester code", "The host panel says why and offers the Tester code button")
			host.pressed.emit()
			await process_frame
			_check(scene.mode == "tester_access" and not is_instance_valid(scene.room_hub_flow.screen) and scene.ui.visible, "The host button goes straight to the Tester code screen")
			await process_frame
			scene._show_home()
			scene.room_hub_flow.open_hub("", false)
			hub = scene.room_hub_flow.screen
			await process_frame
			hub.open_chapter_picker()
			await process_frame
			open = hub._picker.card_for(premium).find_child("ChapterOpen", true, false) as Button
			open.pressed.emit()
			await process_frame
			_check(scene.mode == "tester_access" and not is_instance_valid(scene.room_hub_flow.screen), "Tapping the card goes straight to the Tester code screen")
			await process_frame
		else:
			_check(access != null and access.text == "Full Journey", "The paid card keeps its Full Journey marker: " + label)
			_check(open != null and open.locked == (not open_to_host), "The card lock is unchanged: " + label)
			hub._selected_key = premium
			hub._update_hero()
			var note := hub.find_child("HostLockNote", true, false) as Label
			var host := hub.find_child("HostRoom", true, false) as Button
			_check(note != null and not note.visible and host != null and host.text == "Host a room", "The host button stays Host a room: " + label)
			if not open_to_host:
				open.pressed.emit()
				await process_frame
				_check(hub.selected_key() == premium and not hub._picker_page.visible and is_instance_valid(scene.room_hub_flow.screen), "A locked card is still chosen as before: " + label)
				host.pressed.emit()
				await process_frame
				_check(scene.mode == "paywall" and _find(scene, "HostingLocked") != null and not is_instance_valid(scene.room_hub_flow.screen), "Host a room opens the locked hosting page as before: " + label)
				await process_frame
			else:
				hub.queue_free()
				scene.room_hub_flow.screen = null
				await process_frame
	scene.tester = false

## Play with a friend for a new player: First Steps alone is open to host; a
## later chapter's card shows its lock and reason, is never chosen, and
## hosting it is refused with the reason. A remembered locked choice falls
## back to First Steps. Joins carry the same progress.
func _chain(scene: App, store: FakeStore) -> void:
	var chain := Unlocks.chain()
	scene.config.merge(GOOGLE_PLAY, true)
	scene.unlocks = Unlocks.progress([], {}, {}, false)
	var reason := Unlocks.reason(chain[1], scene.unlocks)
	var entries := {}
	for entry: Dictionary in scene.room_hub_flow.together_chapters(): entries[entry.key] = entry
	_check(not entries[chain[0]].get("locked", false) and str(entries[chain[0]].get("unlock_reason", "")).is_empty(), "A new player can host First Steps")
	_check(entries[chain[1]].locked and entries[chain[1]].unlock_reason == reason and entries[chain[1]].note == Unlocks.reason(chain[1], scene.unlocks, true), "The next chapter is locked with its reason")
	scene.room_hub_flow.selected_chapter = chain[2]
	scene._show_home()
	scene.room_hub_flow.open_hub("", false)
	var hub: Hub = scene.room_hub_flow.screen
	for i in range(2): await process_frame
	_check(hub.selected_key() == chain[0], "A remembered chapter that is not open falls back to First Steps")
	hub.open_chapter_picker()
	await process_frame
	var card: Control = hub._picker.card_for(chain[1])
	var open := card.find_child("ChapterOpen", true, false) as Button
	var access := card.find_child("ChapterAccess", true, false) as Label
	_check(open.locked and access.text == entries[chain[1]].note and access.get_theme_color("font_color") == hub._picker.GOLD, "The host picker's card shows the lock and the reason")
	open.pressed.emit()
	await process_frame
	_check(hub.selected_key() == chain[0] and not hub._picker_page.visible and hub._message == reason, "Choosing it keeps First Steps and the hub says why")
	scene.room_hub_flow._host_room(chain[1], "friends")
	await process_frame
	_check(is_instance_valid(scene.room_hub_flow.screen) and scene.mode == "rooms" and hub._message == reason, "Hosting it is refused on the hub with the reason")
	scene.ensure_relay_session()
	_check(scene.relay_session.join_unlocks.is_valid() and scene.relay_session.join_unlocks.call() == scene.unlocks, "Joins carry this player's unlock progress")
	_check(not chain[1].get_slice("@", 0) in _levels(scene.relay_session.join_unlocks.call()), "So a room past First Steps refuses this player")
	hub.queue_free()
	scene.room_hub_flow.screen = null
	await process_frame
	# Main's own progress: a finished room with a friend counts before this
	# phone takes its places, and a room in play keeps its chapter open.
	scene.unlocks = null
	scene.real = true
	var before := scene.shared_replays
	scene.shared_replays = Replays.new([{"family": "chapter", "chapter_key": chain[0]}])
	var progress: Dictionary = scene._chapter_unlocks()
	_check(Unlocks.reached(chain[1], progress) and not Unlocks.reached(chain[2], progress), "A finished First Steps room opens the next chapter")
	_check(chain[1].get_slice("@", 0) in _levels(progress), "And a room for it then takes this player")
	scene.shared_replays = before
	# Bought Full Journey before reaching it: the card says what opens the
	# Lighthouse and leads to the chapters, never to a refused open.
	store.entitled = true
	scene.store_flow._show_full_journey_unlocked()
	await process_frame
	var lighthouse := Registry.LIGHTHOUSE_V2
	var line := PlayerCopy.FULL_JOURNEY_NOT_REACHED % [Unlocks.title(Unlocks.opens_after(lighthouse)), Unlocks.title(lighthouse)]
	_check(_text_in(scene, line) and _button(scene, "Enter the Lighthouse") == null, "Full Journey unlocked says which chapter leads to the Lighthouse")
	var go := _button(scene, PlayerCopy.FULL_JOURNEY_TO_CHAPTERS)
	_check(go != null, "And offers the way to the chapters")
	if go != null:
		go.pressed.emit()
		await process_frame
		_check(scene.mode == "journey", "Which opens the Chapters page")
	scene.real = false
	scene.unlocks = Unlocks.progress(UnlockFixture.cleared_through(Unlocks.opens_after(lighthouse)), {}, {}, true)
	scene.store_flow._show_full_journey_unlocked()
	await process_frame
	_check(_button(scene, "Enter the Lighthouse") != null, "Once the Lighthouse is reached the card enters it")
	scene.unlocks = null
	store.entitled = false

## The level ids a join for `state` names.
static func _levels(state: Dictionary) -> Array:
	return Array(Unlocks.join_header(state).get_slice(": ", 1).split(","))

## Finished rooms with a saved replay, as SharedReplayCollection.rooms() lists them.
class Replays extends RefCounted:
	var listed: Array
	func _init(rooms: Array) -> void: listed = rooms
	func rooms() -> Array: return listed

func _text_in(node: Node, value: String) -> bool:
	if (node is Label or node is RichTextLabel) and value in str(node.text): return true
	for child: Node in node.get_children():
		if _text_in(child, value): return true
	return false

func _path(label: String) -> String:
	var result := "user://test-%s-%d.json" % [label, Time.get_ticks_usec()]
	paths.append(result)
	return result

func _find(node: Node, name: String) -> Node:
	if node.name == name: return node
	for child: Node in node.get_children():
		var found := _find(child, name)
		if found != null: return found
	return null

func _hero(node: Node) -> TextureRect:
	var found := _find(node, "HostingLockedHero")
	return found as TextureRect if found is TextureRect and (found as TextureRect).texture != null else null

func _scroll_of(control: Node) -> ScrollContainer:
	var node := control.get_parent()
	while node != null and not node is ScrollContainer: node = node.get_parent()
	return node as ScrollContainer

func _button(node: Node, value: String) -> Button:
	if node is Button and node.text == value: return node
	for child: Node in node.get_children():
		var found := _button(child, value)
		if found != null: return found
	return null

func _text(node: Node, value: String) -> bool:
	if node is Label and node.text == value: return true
	for child: Node in node.get_children():
		if _text(child, value): return true
	return false

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
