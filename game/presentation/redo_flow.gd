extends RefCounted
## A Together room's redo request, as the room screen shows it (concept boards
## claude-20261011/redo-concepts, BOARD-1): the friend on their second turn
## asks from the turn itself (the chip beside the try count in play, and the
## turn card's row), is nudged once a turn after 8 tries or 5 minutes, and
## then sees "Asked Sam" or "Sam kept their turn" in place of the button; the
## first player sees the request lead their room page and plays their turn
## again in one tap ("Your turn again"), or keeps it.
##
## The state is the room's redo client (services/redo_client.gd), read from
## the room poll (X-AfterYou-Poll-Redo) or, once on opening a second turn,
## from GET /redo. Taps wait for any read or write still out on this screen
## (BusyTapGate) and then run, so a first tap always registers.
##
## Host contract (relay_preview.gd): online_session, journey, controls, mode,
## running, backgrounded, _leaving, _room_context_lost; calls _hard_on(),
## _ordinary_redo_available(), _waiting_partner_name(), _partner_id(),
## _show_ready(), _online_refresh(), _begin() and offer_redo_alerts.
const RedoClient = preload("res://services/redo_client.gd")
const RedoPrompts = preload("res://services/redo_prompts.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const InGameModal = preload("res://presentation/in_game_modal.gd")
const ControlTheme = preload("res://presentation/control_theme.gd")
const FriendPip = preload("res://presentation/kit/friend_pip.gd")
const FriendNicknames = preload("res://services/friend_nicknames.gd")
const BusyTapGate = preload("res://presentation/busy_tap_gate.gd")
const OfflineHold = preload("res://presentation/offline_hold.gd")
const PEOPLE := preload("res://assets/ui/whats_new/people.svg")
const CHECK := preload("res://assets/ui/check.svg")
## How long "Your turn again" stays over the turn.
const NOTE_SECONDS := 4.0

var host: Node
var _gate: BusyTapGate
## The room the first read of a second turn was made for (ensure_read).
var _read_for := ""
## A friend's request answered with Play my turn again: the turn starts as soon as the room shows it.
var _play_after_accept := false
var _nudge: Control
## The redo alerts question waits for the turn to stop playing (offer_owed_alerts).
var _alerts_owed := false
## Home's Play my turn again opened this room (accept_on_open), until this time.
var _accept_room := ""
var _accept_until := 0
## How long Home's tap waits for the room to show its request.
const ACCEPT_ON_OPEN_MS := 30000

func _init(screen: Node) -> void:
	host = screen

func client() -> RefCounted:
	return host.online_session.redo_client()

## An ordinary Together room (never a hard one) with a redo client.
func available() -> bool:
	return host._ordinary_redo_available() and not host._hard_on()

## The friend's name as the room shows it ("A friend" when unknown).
func partner() -> String:
	return FriendNicknames.sentence_start(host._waiting_partner_name(host.journey.snapshot()))

## The second player may ask now: their turn, and no request yet.
func can_ask() -> bool:
	return available() and host.journey.my_turn() and host.online_session.mutations_enabled() and client().can_request()

## What became of this player's own request on this turn: "pending",
## "declined", or "" when there is none to show.
func answer() -> String:
	if not available() or not host.journey.my_turn(): return ""
	var request: Variant = client().view().get("request")
	return str(request.get("status", "")) if request is Dictionary and request.get("status") in ["pending", "declined"] else ""

## Its line: "Asked Sam" or "Sam kept their turn".
func answer_line() -> String:
	match answer():
		"pending": return PlayerCopy.REDO_ASKED % partner()
		"declined": return PlayerCopy.REDO_KEPT % partner()
	return ""

## A request or answer whose reply never came: its recovery screen offers Retry.
func unsettled() -> bool:
	return host._ordinary_redo_available() and not client().pending().is_empty()

## The first read of a second turn's redo state when nothing has read it yet
## (later polls carry it). Redraws the screen when it changes what shows.
func ensure_read() -> void:
	if not available() or not host.journey.my_turn() or not host.journey.pending().is_empty(): return
	var room: Dictionary = host.journey.snapshot()
	var key := "%s:%s:%s" % [room.get("room_id", ""), room.get("revision", ""), room.get("branch", "")]
	if key == _read_for or RedoClient.source_for("relay", room).is_empty(): return
	var redo := client()
	if redo.busy or not redo.bind_room("relay", room) or not redo.view().is_empty(): return
	_read_for = key
	if not await redo.refresh() or not _same_room(room): return
	if host.mode == "ready": host._show_ready()
	elif host.mode == "play": update_hud()

func _same_room(room: Dictionary) -> bool:
	return is_instance_valid(host) and host.is_inside_tree() and not host._leaving and not host._room_context_lost and host.online_session != null and host.journey.snapshot().get("room_id") == room.get("room_id") and host.journey.snapshot().get("revision") == room.get("revision")

# --- the turn: the chip in play ---------------------------------------------------

## The chip beside the try count: Ask while it may, then what became of it.
func update_hud() -> void:
	if not is_instance_valid(host.controls) or not host.controls.has_method("show_redo_chip"): return
	if host.mode != "play" or not available():
		host.controls.show_redo_chip("")
		return
	if can_ask():
		host.controls.show_redo_chip(PlayerCopy.REDO_ASK, PEOPLE)
		hold(host.controls.redo_chip)
		return
	host.controls.show_redo_chip(answer_line(), CHECK if answer() == "pending" else null, false)

## A live hint while the turn plays: the friend may have kept their turn. Play
## never polls, so a request still waiting is read once here.
func live_hint() -> void:
	if not host.running or not available() or client().busy: return
	var request: Variant = client().view().get("request")
	if not request is Dictionary or request.get("status") != "pending" or not host.journey.my_turn(): return
	var room: Dictionary = host.journey.snapshot()
	if await client().refresh() and _same_room(room): update_hud()

# --- asking ----------------------------------------------------------------------

## Every redo button needs the server: greyed while offline, back on its own.
static func hold(button: BaseButton) -> void:
	if is_instance_valid(button): OfflineHold.hold(button)

## Ask for a redo, from the chip, the turn card or the nudge.
func ask(control: Control = null) -> void:
	await _tap(control, func() -> void:
		if not can_ask(): return
		var room: Dictionary = host.journey.snapshot()
		var asked: bool = await client().request_redo()
		if not _same_room(room): return
		if host.mode == "play": update_hud()
		elif host.mode == "ready": host._show_ready()
		if asked: _offer_alerts())
	# The tap path gives the chip its old words back when it ends: draw what is true now.
	if is_instance_valid(host) and host.mode == "play": update_hud()

## Before a try starts (`start`): the nudge, once a turn, after
## RedoPrompts.NUDGE_TRIES tries or NUDGE_SECONDS on it, while the player may
## still ask. It opens between tries, so it never takes a tap from the turn.
## True when it opened; `start` then runs when it closes.
func nudge_before(tries: int, slot: String, start: Callable) -> bool:
	if is_instance_valid(_nudge) or not can_ask(): return false
	var prompts: RefCounted = RedoPrompts.shared()
	var key := RedoPrompts.turn_key(slot)
	if not prompts.nudge_due(key, tries, int(Time.get_unix_time_from_system())): return false
	prompts.mark_nudged(key)
	var room: Dictionary = host.journey.snapshot()
	var friend_hosts: bool = room.get("player_slot") != "p0"
	_nudge = InGameModal.open(host.controls.ui, "RedoNudge", PlayerCopy.REDO_NUDGE_TITLE, PlayerCopy.REDO_NUDGE_TRIES % tries if tries > 1 else PlayerCopy.REDO_NUDGE_MINUTES)
	_nudge.widen(500.0)
	var pip := FriendPip.make(host._partner_id(room), friend_hosts, 60.0)
	_nudge.header.add_child(pip)
	_nudge.header.move_child(pip, 0)
	_nudge.header.add_theme_constant_override("separation", 16)
	_nudge.label(PlayerCopy.REDO_NUDGE_LINE % partner())
	var asking := [false]
	var ask_button: Button = _nudge.add_actions(PlayerCopy.REDO_ASK, func() -> void:
		asking[0] = true
		if is_instance_valid(_nudge): _nudge.close(false), PlayerCopy.REDO_KEEP_TRYING)
	ask_button.icon = PEOPLE
	ask_button.add_theme_constant_override("icon_max_width", 24)
	for state: String in ["normal", "focus", "hover", "pressed", "hover_pressed"]: ask_button.add_theme_color_override("icon_%s_color" % state, ControlTheme.INK)
	ControlTheme.center_icon_label(ask_button)
	# Keep trying, Close and Back all start the try; Ask also sends the request.
	_nudge.closed.connect(func() -> void:
		_nudge = null
		if not _same_room(room): return
		start.call()
		if asking[0]: ask())
	return true

# --- answering a friend's request ---------------------------------------------------

## Play my turn again: accept the request (a fork), read the room, then start
## the turn at once with "Your turn again".
func play_again(control: Control = null) -> void:
	await _tap(control, func() -> void:
		if not available() or not client().can_accept(): return
		var room: Dictionary = host.journey.snapshot()
		var accepted: bool = await client().accept()
		if not _same_room(room): return
		if not accepted:
			host._show_ready()
			return
		_play_after_accept = true
		await host._online_refresh()
		start_if_accepted())

## Keep it as it is: decline; the friend sees "Sam kept their turn".
func keep(control: Control = null) -> void:
	await _tap(control, func() -> void:
		if not available() or not client().can_accept(): return
		var room: Dictionary = host.journey.snapshot()
		await client().decline()
		if _same_room(room): host._show_ready())

## After an accepted request the room shows this player's turn again: it starts
## at once, with the note over it. Called when the room is drawn ready.
func start_if_accepted() -> void:
	if not _play_after_accept or not is_instance_valid(host) or host.mode != "ready" or not host.journey.my_turn() or host.online_session.busy(): return
	_play_after_accept = false
	host._begin()
	if host.mode == "play": _show_note()

func _show_note() -> void:
	var room: Dictionary = host.journey.snapshot()
	var panel := PanelContainer.new()
	panel.name = "RedoAgainNote"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", ControlTheme.padded(ControlTheme.rounded(Color("173f39"), 18, Color("3f6b61")), 18.0, 8.0))
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	row.add_child(FriendPip.make(host._partner_id(room), room.get("player_slot") != "p0", 40.0))
	var label := Label.new()
	label.text = PlayerCopy.REDO_AGAIN_NOTE
	label.add_theme_font_size_override("font_size", 20)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	host.controls.hud.add_child(panel)
	panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	panel.size = panel.get_combined_minimum_size()
	panel.position = Vector2((host.controls.hud.size.x - panel.size.x) * 0.5, 104.0)
	host.get_tree().create_timer(NOTE_SECONDS).timeout.connect(func() -> void: if is_instance_valid(panel): panel.queue_free())

## Home's Play my turn again opened `room_id`: once its request shows, it plays.
func accept_on_open(room_id: String) -> void:
	_accept_room = room_id
	_accept_until = Time.get_ticks_msec() + ACCEPT_ON_OPEN_MS

## The request's Play my turn again was drawn: Home's tap plays it now, or the
## player sees the request in the app (the redo alerts question, once).
func request_drawn(button: Button) -> void:
	var room_id := str(host.journey.snapshot().get("room_id", "")) if available() else ""
	if not _accept_room.is_empty() and _accept_room == room_id and Time.get_ticks_msec() < _accept_until:
		_accept_room = ""
		await play_again(button)
		return
	noticed_request()

## Seeing a friend's request in the app for the first time asks about redo alerts once.
func noticed_request() -> void:
	if available() and client().can_accept(): _offer_alerts()

func _offer_alerts() -> void:
	# Never over a turn that is playing: it waits for the next card.
	if host.running:
		_alerts_owed = true
		return
	_alerts_owed = false
	if host.offer_redo_alerts.is_valid(): host.offer_redo_alerts.call(host.controls.ui)

## A question owed from a request sent during play, once the turn stops.
func offer_owed_alerts() -> void:
	if _alerts_owed and is_instance_valid(host) and not host.running and host.is_inside_tree(): _offer_alerts()

## One tap path for every redo button: it waits for a read or write still out
## (the room poll, an earlier redo tap), then runs on the same room.
func _tap(control: Control, run: Callable) -> void:
	if _gate == null: _gate = BusyTapGate.new(host.controls)
	var room_id := str(host.journey.snapshot().get("room_id", ""))
	await _gate.tap(control, PlayerCopy.ROOM_CHECKING,
		func() -> bool: return host.online_session == null or (not host.online_session.busy() and not client().busy),
		run,
		func() -> bool: return is_instance_valid(host) and not host._leaving and not host.backgrounded and host.online_session != null and str(host.journey.snapshot().get("room_id", "")) == room_id)
