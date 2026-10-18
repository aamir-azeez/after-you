extends Node
## One phone in the online scenario harness: a whole Main in its own
## SubViewport with its own save file, identity and DeviceApi. Lifecycle
## events go to this phone only. Room journals, replay caches and inbox caches
## use the app's own owner-scoped stores under the suite's isolated user://.
const Main = preload("res://main.gd")
const Save = preload("res://services/local_save.gd")
const DeviceApi = preload("res://tests/online_harness/device_api.gd")
const DeletedCaches = preload("res://services/deleted_identity_cache_cleanup.gd")

var label := ""
var server: RefCounted
var player_id := ""
var device_token := ""
var save_path := ""
var viewport: SubViewport
var app: Node
var api: Node
var legacy_060 := false
var latency_frames := 1
## Every toast and error card seen since the last clear, with the step's fault flag.
## Friend news in the pop-up (it carries the friends icon) is kept apart in `news`.
var toasts: Array[String] = []
var news: Array[String] = []
var error_cards: Array[String] = []
var _last_toast := ""

func _init(name_label: String, fake_server: RefCounted, size: Vector2i = Vector2i(1280, 720)) -> void:
	label = name_label
	name = "Device_" + name_label
	server = fake_server
	viewport = SubViewport.new()
	viewport.size = size
	viewport.name = "Viewport"
	save_path = "user://online-harness-" + name_label + "-" + Crypto.new().generate_random_bytes(6).hex_encode() + ".json"

func _ready() -> void:
	add_child(viewport)

## A fresh install: a new identity from the server and an empty save.
func install() -> void:
	var identity: Dictionary = server.new_identity()
	player_id = identity.player_id
	device_token = identity.device_token
	save_path = "user://online-harness-" + label + "-" + Crypto.new().generate_random_bytes(6).hex_encode() + ".json"
	boot()

## The same identity recovered on a new phone: nothing of it is saved locally
## (room journals, replay caches and kept room attempts are gone).
func new_phone() -> void:
	force_quit()
	DeletedCaches.new().erase_owner(player_id)
	save_path = "user://online-harness-" + label + "-" + Crypto.new().generate_random_bytes(6).hex_encode() + ".json"
	boot()

## Starts the app on this phone's saved state and identity.
func boot() -> void:
	app = Main.new()
	app.saves = Save.new(save_path)
	app.saves.data.settings.sound = false
	viewport.add_child(app)
	app.api.queue_free()
	api = DeviceApi.new()
	api.server = server
	api.device = label
	api.legacy_060 = legacy_060
	api.latency_frames = latency_frames
	api.player_id = player_id
	api.device_token = device_token
	app.add_child(api)
	app.api = api
	# The app's quiet retries wait seconds; a test phone waits moments.
	app.replays_flow.replay_save_retry_s.assign([0.05, 0.05, 0.05])
	app.room_sharing.retry_delays_s.assign([0.05, 0.05, 0.05])
	# The live socket goes to the same server (it opens only when the server offers it).
	app.live_connection.socket_factory = server.live_socket
	# Main configured its notification service with the api it built in _ready.
	app.turn_notifications._api = api
	app.identity_read_state = Main.IdentityReadState.LOADED
	app.identity_data = {"player_id": player_id, "device_token": device_token}
	_last_toast = ""

## Kills the app with whatever it was doing in flight; nothing is saved first.
func force_quit() -> void:
	if is_instance_valid(app):
		viewport.remove_child(app)
		app.free()
	app = null
	api = null

func running() -> bool:
	return is_instance_valid(app)

func background() -> void:
	viewport.propagate_notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	viewport.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)

func foreground() -> void:
	viewport.propagate_notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	viewport.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)

## Android Back, delivered the way the engine delivers it: Window's
## _propagate_window_notification notifies each node, then walks its children
## by index (no child lock, unlike propagate_notification, so the handlers may
## add and remove screens).
func system_back() -> void:
	_window_notification(viewport, Node.NOTIFICATION_WM_GO_BACK_REQUEST)

static func _window_notification(node: Node, what: int) -> void:
	node.notification(what)
	var index := 0
	while index < node.get_child_count():
		var item := node.get_child(index)
		if not item is Window: _window_notification(item, what)
		index += 1

## Records any new toast text (called by the harness every frame).
func observe() -> void:
	if not running(): return
	var toast: Variant = app.toast
	if is_instance_valid(toast) and toast.visible and toast.text != _last_toast:
		_last_toast = toast.text
		if toast._current.get("icon") != null: news.append(toast.text)
		else: toasts.append(toast.text)
	elif is_instance_valid(toast) and not toast.visible:
		_last_toast = ""
	var child: Node = app.relay_child
	if is_instance_valid(child) and child.mode == "error":
		var text := _card_text(child)
		if error_cards.is_empty() or error_cards.back() != text: error_cards.append(text)

func _card_text(child: Node) -> String:
	var parts: Array[String] = []
	for node: Node in child.find_children("*", "Label", true, false):
		var item := node as Label
		if item.is_visible_in_tree() and not item.text.is_empty(): parts.append(item.text)
	return " | ".join(parts)

## Every visible control text on this phone, for the raw-id and <null> checks.
func visible_texts() -> Array[String]:
	var result: Array[String] = []
	if not running(): return result
	for node: Node in viewport.find_children("*", "Control", true, false):
		var control := node as Control
		if not control.is_visible_in_tree(): continue
		var text := ""
		if control is Label: text = (control as Label).text
		elif control is Button: text = (control as Button).text
		elif control is LineEdit: text = (control as LineEdit).text
		elif control is RichTextLabel: text = (control as RichTextLabel).get_parsed_text()
		if not text.is_empty(): result.append(text)
	return result

## Visible, enabled buttons on the top screen.
func buttons() -> Array[Button]:
	var result: Array[Button] = []
	if not running(): return result
	for node: Node in viewport.find_children("*", "Button", true, false):
		var button := node as Button
		if button.is_visible_in_tree() and not button.disabled and not button.is_queued_for_deletion(): result.append(button)
	return result

func button(text_or_action: String) -> Button:
	for item: Button in buttons():
		if item.text == text_or_action or item.name == text_or_action or str(item.get_meta("action_id", "")) == text_or_action: return item
	return null

func hub() -> Node:
	return app.room_hub_flow.screen if running() and is_instance_valid(app.room_hub_flow.screen) and not app.room_hub_flow.screen.is_queued_for_deletion() else null

func child() -> Node:
	return app.relay_child if running() and is_instance_valid(app.relay_child) and not app.relay_child.is_queued_for_deletion() else null

## A short description for step logs.
func recent_requests(count: int = 8) -> String:
	if not running(): return ""
	var lines: Array[String] = []
	for entry: Dictionary in api.requests.slice(maxi(0, api.requests.size() - count)):
		lines.append("%s %s %d %s%s" % [["GET","HEAD","POST","PUT","DELETE"][entry.method] if entry.method < 5 else str(entry.method), entry.path, entry.status, entry.code, (" !" + entry.fault) if not str(entry.fault).is_empty() else ""])
	return "; ".join(lines)

func where() -> String:
	if not running(): return "closed"
	var parts := [str(app.mode)]
	if child() != null: parts.append("room:" + str(child().mode))
	if hub() != null:
		var rooms: Array = app.room_hub_flow.inbox.view().rooms if app.room_hub_flow.inbox != null else []
		parts.append("hub[%s](%s)" % [hub()._message, ",".join(rooms.map(func(room: Dictionary) -> String: return str(room.room_id).left(4) + ":" + str(room.status)))])
	if is_instance_valid(app.shared_replay_child): parts.append("replay")
	if app.friends_flow.is_open(): parts.append("friends")
	return "/".join(parts)
