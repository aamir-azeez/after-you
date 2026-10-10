extends SceneTree
## Locked hosting page and the host entitlement split between the GitHub Test
## Store build (solo purchase only; hosting needs a tester code) and a Google
## Play build (a purchase grants solo and cooperative hosting).

const Main = preload("res://main.gd")
const Purchases = preload("res://services/purchases.gd")
const Storage = preload("res://services/local_save.gd")
const Registry = preload("res://services/chapter_registry.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")

var checks := 0
var failures := 0
var paths: Array[String] = []

class FakeStore extends Purchases:
	var entitled := false
	var available := true
	func _connect_native() -> bool: return true
	func is_available() -> bool: return available
	func has_entitlement(_entitlement_id: String = "") -> bool: return entitled

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var premium := ""
	for key: String in Registry.keys():
		if Registry.descriptor(key).get("premium", false):
			premium = key
			break
	_check(not premium.is_empty(), "A premium cooperative chapter exists to gate hosting")
	var scene := Main.new()
	scene.saves = Storage.new(_path("hosting"))
	root.add_child(scene)
	scene.set_process(false)
	scene.set_physics_process(false)
	scene.world.set_process(false)
	scene.purchases.queue_free()
	var store := FakeStore.new()
	scene.purchases = store
	scene.add_child(store)
	scene.purchase_package = {"price": "$4.99", "offering_id": "offer", "id": "package"}

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
	scene._show_hosting_locked(premium)
	await process_frame
	await process_frame
	_check(scene.mode == "paywall" and _find(scene, "HostingLocked") != null, "Hosting a locked chapter opens the locked hosting page")
	var unlock := _find(scene, "HostingLockedUnlock") as Button
	_check(unlock != null and "$4.99" in unlock.text, "Google Play locked hosting shows Unlock with the real store price")
	_check(_button(scene, "Restore purchases") != null, "Google Play locked hosting offers Restore purchases")
	_check(_find(scene, "HostingLockedTester") == null, "Google Play locked hosting does not route to a tester code")
	_check(_hero(scene) != null, "Locked hosting shows the selected chapter artwork")
	_check(_button(scene, "Back") != null, "Locked hosting keeps a Back control")
	_check(_text(scene, "Host a room") and _text(scene, "One-time purchase"), "Google Play locked hosting is titled Host a room and names the one-time purchase")
	if _hero(scene) != null and unlock != null:
		_check(_hero(scene).get_global_rect().get_center().x < unlock.get_global_rect().position.x, "The chapter picture sits left of the purchase details")
	var back := _button(scene, "Back")
	if back != null and unlock != null:
		_check(back.get_global_rect().end.y <= _hero(scene).get_global_rect().position.y and back.get_global_rect().end.y <= unlock.get_global_rect().position.y, "Back stays in the header above the picture and details")
		back.pressed.emit()
		await process_frame
		_check(scene.mode != "paywall" and _find(scene, "HostingLocked") == null, "Locked hosting Back leaves for the rooms screen")
		scene._show_hosting_locked(premium)
		await process_frame
		await process_frame
	# A short safe area (cutouts plus a tall system bar) keeps Back fixed and
	# scrolls the details so every action is still reachable.
	var full := scene.get_viewport().get_visible_rect()
	var tight := Rect2(full.position + Vector2(96, 40), full.size - Vector2(144, 340))
	scene._apply_safe_area(tight)
	scene._show_hosting_locked(premium)
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
	var short_unlock := _find(scene, "HostingLockedUnlock") as Button
	if short_unlock != null:
		_scroll_of(short_unlock).ensure_control_visible(short_unlock)
		await process_frame
		await process_frame
		_check(tight.grow(0.5).encloses(short_unlock.get_global_rect()) and short_unlock.size.y >= 48, "Unlock keeps a full touch target in a short safe area")
	scene._apply_safe_area(full)
	await process_frame

	# A Google Play build without a store price must not fabricate one.
	store.available = false
	scene._show_hosting_locked(premium)
	await process_frame
	var plain := _find(scene, "HostingLockedUnlock") as Button
	_check(plain != null and not ("$" in plain.text), "No price is shown until the store provides one")

	# --- Test Store locked page -------------------------------------------
	scene.config.purchase_mode = "test_store"
	scene.config.entitlement_id = "full_journey"
	store.entitled = true
	scene._show_hosting_locked(premium)
	await process_frame
	await process_frame
	_check(_find(scene, "HostingLockedTester") != null, "Test Store locked hosting offers tester code access")
	_check(_find(scene, "HostingLockedUnlock") == null, "Test Store locked hosting hides a purchase that would not unlock hosting")
	_check(_text(scene, PlayerCopy.MAIN_FAD34E850ED9), "Test Store locked hosting explains tester-code hosting")
	_check(not _text(scene, "One-time purchase"), "Test Store locked hosting names no purchase it cannot offer")

	root.remove_child(scene)
	scene.queue_free()
	await process_frame
	for path: String in paths:
		for suffix: String in ["", ".tmp", ".backup"]:
			if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	print("HOSTING LOCKED: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

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
