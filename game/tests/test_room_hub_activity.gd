extends SceneTree
## The hub footer counts every unread room, and each tab
## with unread rooms carries the yellow dot, so a completed room in the count
## always has a visible place to find it.

const Hub = preload("res://presentation/room_hub_screen.gd")
const Registry = preload("res://services/chapter_registry.gd")

class Inbox extends RefCounted:
	var rooms: Array = []
	var unread_ids: Array = []
	func view() -> Dictionary: return {"rooms": rooms, "stale": false, "error": ""}
	func unread(room: Dictionary) -> bool: return unread_ids.has(room.get("room_id"))
	func confirm_room_rendered(_version: int, _id: String) -> bool: return false
	func refresh() -> bool: return true

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var key: String = Registry.keys()[0]
	var inbox := Inbox.new()
	for spec: Array in [["a", "waiting_for_their_turn"], ["b", "your_turn"], ["c", "completed"]]:
		inbox.rooms.append({"api_version": 2, "room_id": spec[0], "chapter_key": key, "chapter_title": str(Registry.descriptor(key).title), "member_ids": ["me", "friend"], "status": spec[1], "part": 1, "stage_count": 2})
	inbox.unread_ids = ["a", "b", "c"]
	var chapters: Array[Dictionary] = [{"key": key, "title": str(Registry.descriptor(key).title), "stage_count": 2}]
	var hub := Hub.new()
	hub.client = inbox
	hub.set_chapters(chapters)
	hub.display_name = func(_member: String) -> String: return "Sam"
	root.add_child(hub)
	for i in range(3): await process_frame
	_check(hub._footer.visible and hub._footer.text == "3 rooms have new activity", "Footer counts every unread room, completed included: " + hub._footer.text)
	_check(_dot(hub, "Your rooms") and _dot(hub, "Completed") and not _dot(hub, "Friends"), "Tabs with unread rooms show the dot; Friends has none")
	inbox.unread_ids = ["c"]
	hub._render()
	await process_frame
	_check(hub._footer.visible and hub._footer.text == "1 room has new activity" and not _dot(hub, "Your rooms") and _dot(hub, "Completed"), "Only a completed room unread: footer counts it, dot on Completed only")
	inbox.unread_ids = []
	hub._render()
	await process_frame
	_check(not _dot(hub, "Your rooms") and not _dot(hub, "Completed"), "Dots clear once everything is read")
	var dot: Control = hub._tab_buttons["Completed"].get_node("UnreadDot")
	_check(dot.mouse_filter == Control.MOUSE_FILTER_IGNORE, "The tab dot never steals taps")
	hub.queue_free()
	print("AFTER YOU ROOM HUB ACTIVITY: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _dot(hub: Node, tab: String) -> bool:
	var dot := (hub._tab_buttons[tab] as Node).get_node_or_null("UnreadDot") as Control
	return dot != null and dot.visible

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + label)
