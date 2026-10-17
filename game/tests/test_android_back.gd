extends SceneTree
## Android Back on a Main screen with no rule of its own goes where the
## screen's own way back goes, and closes a card open over the screen first.
const Main = preload("res://main.gd")
const Storage = preload("res://services/local_save.gd")
const InGameModal = preload("res://presentation/in_game_modal.gd")
var checks := 0
var failures := 0
var app: Node
var path := ""

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	path = "user://android-back-" + Crypto.new().generate_random_bytes(8).hex_encode() + ".json"
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1560, 720)
	root.add_child(viewport)
	app = Main.new()
	app.saves = Storage.new(path)
	viewport.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	await process_frame
	var screens := {
		"settings": app.settings_flow.show_settings,
		"notifications": app.notification_flow.show_settings,
		"account": app.account_flow.show_account,
		"delete identity confirm": app.account_flow.confirm_delete_identity,
		"recovery form": app.account_flow.show_recovery_form,
		"play solo": app._show_journey,
		"earlier islands": app._show_earlier_islands,
		"replays": app.replays_flow.show_collection,
		"graphics": app.settings_flow.show_graphics_settings,
	}
	for name: String in screens:
		await _same_as_on_screen(name, screens[name])
	await _unmarked_cancel()
	await _modal_first()
	await _home_stays()
	viewport.queue_free()
	await process_frame
	for suffix: String in ["", ".tmp", ".backup"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	print("Android Back: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _open(screen: Callable) -> String:
	app._show_home()
	await process_frame
	await screen.call()
	await process_frame
	return _screen()

## The screen on show: its mode and its buttons.
func _screen() -> String:
	var texts: Array = []
	for node: Node in app.overlay.find_children("*", "Button", true, false):
		if (node as Button).is_visible_in_tree() and not node.is_queued_for_deletion(): texts.append((node as Button).text)
	return str(app.mode) + " " + str(texts)

func _same_as_on_screen(name: String, screen: Callable) -> void:
	var opened := await _open(screen)
	var back: Button = null
	for node: Node in app.overlay.find_children("*", "Button", true, false):
		if node.has_meta(Main.SCREEN_BACK) and (node as Button).is_visible_in_tree(): back = node
	_check(back != null, "%s has a marked way back" % name)
	if back == null: return
	var label := back.text
	back.pressed.emit()
	await process_frame
	var by_button := _screen()
	await _open(screen)
	app.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await process_frame
	_check(by_button != opened and _screen() == by_button, "Android Back on %s goes where '%s' goes (%s, went to %s)" % [name, label, by_button, _screen()])

## A Cancel that is not the screen's marked way back (one that cancels a request,
## say) is never pressed by Android Back.
func _unmarked_cancel() -> void:
	await _open(func(): pass)
	app.mode = "unmarked_cancel_test"
	var card: VBoxContainer = app._card()
	var pressed := [0]
	card.add_child(app._button("Cancel", func(): pressed[0] += 1))
	card.add_child(app._button("Back", func(): pressed[0] += 10))
	await process_frame
	app.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await process_frame
	_check(pressed[0] == 0, "Android Back presses only a control marked as the way back, never one by its label")

func _modal_first() -> void:
	await _open(app.settings_flow.show_settings)
	var modal := InGameModal.open(app.ui, "BackTestModal", "A card")
	app.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await process_frame
	_check(not is_instance_valid(modal) or modal.is_queued_for_deletion(), "Android Back closes a card open over the screen")
	_check(app.mode == "settings", "and leaves the screen under it as it was")

func _home_stays() -> void:
	await _open(func(): pass)
	app.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await process_frame
	_check(app.mode == "home", "Android Back on Home stays on Home")

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
