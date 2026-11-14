extends RefCounted
## Home's redo request card (concept board 1, frame 4): a friend asked this
## player to play their turn again. The friend's pip, "Maya asked for a redo",
## the chapter, stage and turn, then Not now and Play my turn again. No dim, so
## Home stays readable behind it.
##
## It reads the room list (services/room_inbox_client.gd, the hub's own
## client), whose rooms in play carry their current request (redo, sent to
## clients that send X-AfterYou-Room-Redo). Home shows the list it already
## holds at once and reads it again only when something may have changed: the
## first Home of a session, a live room hint while Home shows, and the app
## coming back, never closer than READ_GAP_MS. Not now puts that request's card
## away on this phone (services/redo_prompts.gd); the request still leads the
## room page. Play my turn again opens the room, which plays the turn again at
## once (presentation/redo_flow.gd accept_on_open).
##
## Host contract (main.gd): mode, ui, application_backgrounded, room_hub_flow,
## relay_lobby_flow, legacy_room_flow, relay_child, notification_flow,
## _relay_identity(), _top_modal(), _friend_display_name().
const InGameModal = preload("res://presentation/in_game_modal.gd")
const ControlTheme = preload("res://presentation/control_theme.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const FriendPip = preload("res://presentation/kit/friend_pip.gd")
const FriendNicknames = preload("res://services/friend_nicknames.gd")
const RedoPrompts = preload("res://services/redo_prompts.gd")
const ChapterRegistry = preload("res://services/chapter_registry.gd")
const OfflineHold = preload("res://presentation/offline_hold.gd")
const PLAY := preload("res://assets/ui/play.svg")
## The closest two of Home's own reads of the room list may be.
const READ_GAP_MS := 60000
## Only the right half of a wide Home holds the card, beside the menu.
const SIDE_MIN_WIDTH := 1040.0

var host: Node
var card: Control
var _shown_key := ""
var _last_read_ms := -READ_GAP_MS
var _read_once := false
var _opening := false

func _init(main: Node) -> void:
	host = main

func _on_home() -> bool:
	return is_instance_valid(host) and host.mode == "home" and not host.application_backgrounded and host._relay_identity().ready

## Home was drawn: the card from the list already held, and the session's first read.
func home_shown() -> void:
	show_card()
	if not _read_once: read_soon()

## A live room hint, or the app came back: read the list again while Home shows.
func read_soon() -> void:
	if not _on_home(): return
	var now := Time.get_ticks_msec()
	if now - _last_read_ms < READ_GAP_MS: return
	var client: RefCounted = host.room_hub_flow.rooms_client()
	if client.busy: return
	_last_read_ms = now
	_read_once = true
	await client.refresh()
	show_card()

## The first request a friend made of this player that Home has not put away.
func _request() -> Dictionary:
	var client: RefCounted = host.room_hub_flow.rooms_client()
	for room: Dictionary in client.view().get("rooms", []):
		var redo: Variant = room.get("redo")
		if redo is Dictionary and redo.get("state") == "asked_you" and int(room.get("api_version", 0)) in [1, 2] and not RedoPrompts.shared().dismissed(_key(room)): return room
	return {}

static func _key(room: Dictionary) -> String:
	return RedoPrompts.request_key(str(room.get("room_id", "")), int(room.get("revision", 0)), int(room.get("redo", {}).get("stage_index", 0)))

func show_card() -> void:
	if not _on_home(): return
	var room := _request()
	if room.is_empty():
		_close()
		return
	if is_instance_valid(card) and _shown_key == _key(room): return
	if host._top_modal() != null and not is_instance_valid(card): return
	open_card(room)

## The card for `room`, a room-list entry whose redo is asked_you.
func open_card(room: Dictionary) -> void:
	_close()
	_shown_key = _key(room)
	var friend := _friend(room)
	card = InGameModal.open(host.ui, "RedoAskCard", PlayerCopy.REDO_ASKED_FOR % FriendNicknames.sentence_start(host._friend_display_name(friend)), _line(room))
	card.widen(520.0)
	var pip := FriendPip.make(friend, room.get("member_ids", []).find(friend) == 0, 64.0)
	card.header.add_child(pip)
	card.header.move_child(pip, 0)
	card.header.add_theme_constant_override("separation", 16)
	var close := card.header.find_child("ModalClose", false, false) as Control
	if close != null: close.visible = false
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	card.content.add_child(row)
	var later := Button.new()
	later.text = PlayerCopy.REDO_NOT_NOW
	later.custom_minimum_size.y = 54
	later.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	later.size_flags_stretch_ratio = 0.55
	ControlTheme.secondary(later)
	later.pressed.connect(func() -> void:
		RedoPrompts.shared().dismiss(_key(room))
		_close()
		# Seeing a friend's request in the app for the first time asks about redo alerts once.
		if _on_home(): host.notification_flow.offer_redo_alerts(host.ui))
	row.add_child(later)
	var play := Button.new()
	play.name = "RedoPlayAgain"
	play.text = PlayerCopy.REDO_PLAY_AGAIN
	play.icon = PLAY
	play.custom_minimum_size.y = 54
	play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	play.add_theme_constant_override("icon_max_width", 24)
	for state: String in ["normal", "focus", "hover", "pressed", "hover_pressed"]: play.add_theme_color_override("icon_%s_color" % state, ControlTheme.INK)
	play.pressed.connect(_play.bind(room))
	row.add_child(play)
	ControlTheme.center_icon_label(play)
	# Playing again needs the server: greyed while offline, back on its own.
	OfflineHold.hold(play)
	card.refresh_focus_order()
	_side(card)

## "The Relay Isles · 1 / 2 · Your first turn".
func _line(room: Dictionary) -> String:
	var parts: PackedStringArray = [str(room.get("chapter_title", ""))]
	var stages: Variant = ChapterRegistry.definition(str(room.get("chapter_key", ""))).get("stages") if int(room.get("api_version", 0)) == 2 else null
	if stages is Array and not stages.is_empty(): parts.append("%d / %d" % [int(room.redo.stage_index) + 1, stages.size()])
	parts.append(PlayerCopy.REDO_FIRST_TURN)
	return " · ".join(parts)

func _friend(room: Dictionary) -> String:
	for member: Variant in room.get("member_ids", []):
		if str(member) != str(host.api.player_id): return str(member)
	return ""

## No dim, and on a wide Home the card sits over the island, beside the menu.
func _side(modal: Control) -> void:
	for child: Node in modal.get_children():
		if child is ColorRect: (child as ColorRect).color.a = 0.0
	var centre := modal.find_child("ModalCenter", false, false) as Control
	var width: float = modal.get_viewport_rect().size.x
	if centre != null and width >= SIDE_MIN_WIDTH:
		var middle := width - 28.0 - 260.0
		centre.anchor_left = clampf((2.0 * middle - width) / width, 0.0, 1.0)

## Play my turn again: open the room; the room plays the turn again at once.
func _play(room: Dictionary) -> void:
	if _opening or not _on_home(): return
	_opening = true
	_close()
	var room_id := str(room.get("room_id", ""))
	if int(room.get("api_version", 0)) == 2:
		await host.relay_lobby_flow.lobby_action("open", room_id)
		if is_instance_valid(host.relay_child) and host.relay_child.has_method("accept_redo_on_open"): host.relay_child.accept_redo_on_open(room_id)
	else:
		await host.legacy_room_flow.open_room(room_id)
	_opening = false

func _close() -> void:
	if is_instance_valid(card): card.close(false)
	card = null
	_shown_key = ""
