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
