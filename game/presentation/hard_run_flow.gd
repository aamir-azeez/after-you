extends RefCounted
## A chapter screen's hard run, as the screen shows it (services/hard_mode.gd
## for the rules and the keeping, services/hard_run.gd for one run). The
## screen (relay_preview.gd) holds its run in `hard` and calls in here only at
## its seams: _ready (claim), _begin (start), the first tick (draft), a resume
## that fails, _show_review (verdict and body), _show_ready and the waiting
## panel (held turns, the room's own states), _show_completed (finish), the
## HUD (label) and its card buttons (offers). Everything hard mode draws on
## the screen lives here: the failure card, the room full card and the
## finished card.
const HardMode = preload("res://services/hard_mode.gd")
const HardRun = preload("res://services/hard_run.gd")
const HardModeView = preload("res://presentation/hard_mode_view.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const RoomActions = preload("res://presentation/room_actions.gd")
const Typed = preload("res://services/typed_values.gd")
const FAILED_MODE := "hard_failed"
const FULL_MODE := "hard_full"

var host: Node
## The failure card's end card slot, filled once the server's slip number is
## known (the slipper's reset answered), and its run.
var _extras: VBoxContainer
var _extras_run: Dictionary = {}
var _read_note_shown := false

func _init(screen: Node) -> void:
	host = screen

func run() -> RefCounted:
	return host.hard

## Whether hard rules apply on the screen now.
func on() -> bool:
	return host.hard != null and host.hard.active()


# Seams ------------------------------------------------------------------------

## _ready: a solo hard open (Main's HardMode.hand_over) or a kept run to watch;
## a room screen's run is a hard run while its room is a hard room. A watch
## starts at its last part, the slip, with the parts before it after it in
## Replays' part chips.
func claim() -> void:
	# Claimed once: the premium screen claims before its access check.
	if host.hard != null: return
	if host.online_session != null:
		host.hard = HardRun.for_room(host.online_session)
		return
	var request: Dictionary = HardMode.claim(host.chapter_key)
	match str(request.get("kind", "")):
		"play":
			if not host._solo_replay_only and not host._solo_replay_context_error: host.hard = HardRun.solo(host.chapter_key)
		"watch":
			if host._solo_replay_only or host._solo_replay_context_error: return
			var kept: Dictionary = request.get("run", {}) if request.get("run") is Dictionary else HardMode.kept_run(host.chapter_key, str(request.get("id", "")))
			var pairs: Array = HardMode.watch_pairs(kept)
			if pairs.is_empty():
				host._solo_replay_context_error = true
				return
			host._solo_replay_only = true
			host._replay_collection = pairs
			host.replay_pair_index = clampi(int(request.get("part", pairs.size() - 1)), 0, pairs.size() - 1)

## Whether a card offers the action (action_buttons.gd or RoomActions id).
func offers(action_id: String) -> bool:
	return not on() or host.hard.offers(action_id)

## The chapter a turn's try count is kept under.
func tries_chapter(chapter_key: String) -> String:
	return host.hard.tries_key(chapter_key) if on() else chapter_key

## _begin: a second start of a turn ends the run. True when it did.
func slipped_on_start(tries: int) -> bool:
	if not on() or not host.hard.slipped(tries): return false
	fail("retry", {})
	return true

## The first tick of a hard turn is saved at once (as every 30th is), so an
## app closed in a turn's first second offers Resume rather than counting the
## next start as a retry. A recording holds at least one tick, so tick 1 is
## the first that can be saved.
func saves_tick(tick: int) -> bool:
	return tick == 1 and on()

## A saved hard draft that cannot be resumed: the only way on would be to
## start the turn again, so the run ends there. True when it did.
func resume_failed() -> bool:
	if not on(): return false
	fail("failed_turn", {})
	return true

## _show_review: a turn the run cannot keep ends it. True when it did.
func verdict(verified: Dictionary, review: Dictionary) -> bool:
	if not on(): return false
	var reason: String = host.hard.failure(verified)
	if reason.is_empty(): return false
	fail(reason, review)
	return true

## The review card's line above Save turn.
func review_body(ordinary: String) -> String:
	return PlayerCopy.HARD_REVIEW_BODY if on() else ordinary

## The ready card's extra line.
func ready_note() -> String:
	return "\n\n" + PlayerCopy.HARD_READY_NOTE if on() else ""

## The ready card's or room panel's heading, tagged in a hard run.
func heading(title: String) -> String:
	return PlayerCopy.HARD_ROOM_TAG + " · " + title if on() else title

## In play, the pill under the stage line: "Hard · Stage 2 of 4", or "".
func hud_label(stage_index: int, stages: int) -> String:
	return PlayerCopy.HARD_IN_PLAY % [stage_index + 1, stages] if on() else ""

## _show_ready, before its pending check: a turn the room refused after it
## started again goes quietly (RelayRoomCoordinator.drop_stale_hard_turn).
func settle_held() -> void:
	if host.online_session != null and on(): host.journey.drop_stale_hard_turn()

## A hard room's own states before any turn: its reset still to send, no
## space left for another run, or a friend's slip not shown yet. True when
## the screen shows one of them.
func holds() -> bool:
	if host.online_session == null or not on(): return false
	if host.hard.reset_pending():
		show_failed(true)
		send_reset()
		return true
	if host.hard.over():
		show_room_full()
		return true
	var slip: Dictionary = host.hard.friend_slip(host._waiting_partner_name(host.journey.snapshot()))
	if slip.is_empty(): return false
	show_friend_failed(slip)
	return true

## _show_completed: a finished hard run's card. True when it showed.
func complete() -> bool:
	if not on(): return false
	if host.hard.together: host.hard.complete_together()
	else: host.hard.complete_solo(host.journey)
	var card := bare_card()
	var extras := HardModeView.add_band(card, PlayerCopy.HARD_COMPLETE_TITLE, PlayerCopy.HARD_COMPLETE_BODY % str(host.chapter.title), {}, host.title_font, host.hard.mode())
	HardModeView.fill_extras(extras, context(HardMode.COMPLETE, {}, host.hard.failures()))
	host._set_room_state("complete")
	host._add_room_actions(card, "complete", "turn", host._room_facts())
	return true


# The failure ----------------------------------------------------------------

## The turn can never be kept, or was started a second time: the run ends.
## `slip` is the slipped turn's recording, or {}.
func fail(reason: String, slip: Dictionary) -> void:
	host.running = false
	host.action_pressed = false
	host.review = {}
	host._drop_prefetch()
	if host.hard.together:
		var kept: bool = host.hard.fail_together(reason, slip, host._waiting_partner_name(host.journey.snapshot()))
		show_failed(kept)
		if kept: send_reset()
	else:
		show_failed(host.hard.fail_solo(host.journey, host.turn_tries, reason, slip, host.chapter_key))

## A card with no title or body line of its own; the hard band heads it.
func bare_card() -> VBoxContainer:
	var card: VBoxContainer = host._card("", "")
	for line: Node in card.get_children():
		if line is Label and (line as Label).text.is_empty(): (line as Label).visible = false
	return card

## The end card hook's context (presentation/hard_mode_view.gd). `number` is
## the room's count of slips with this one (both phones read the same), 0 solo.
func context(kind: String, kept: Dictionary, number: int) -> Dictionary:
	return {"kind": kind, "chapter_key": host.chapter_key, "together": host.hard.together, "room_id": str(host.journey.snapshot().get("room_id", "")) if host.online_session != null else "",
		"run": kept, "number": number}

## This phone's failed run's card: who slipped and where, then Watch the
## slip (solo), Start again and Back. `ready`: the run could start again
## (solo), or its reset is kept (together).
func show_failed(ready: bool) -> void:
	var kept: Dictionary = host.hard.last_run if not host.hard.last_run.is_empty() else host.hard.pending_run()
	var card := _failed_card(kept)
	var status: Label = host._label("" if ready else PlayerCopy.HARD_RESTART_STUCK, 17)
	status.name = "HardResetStatus"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(status)
	# Watching plays from the slip; the chapter screen plays a room's slip in Replays.
	if not host.hard.together and HardMode.watchable(kept):
		card.add_child(host._button(PlayerCopy.HARD_WATCH_SLIP, _watch.bind(kept), false))
	var again: Button = host._button(PlayerCopy.HARD_START_AGAIN, start_again)
	again.name = "HardStartAgain"
	card.add_child(again)
	card.add_child(host._action_button("back", host._leave))
	_extras_run = kept
	# Solo, and a room's slip once the room has counted it, fill the hook now.
	if not host.hard.together: _fill(0)
	if host.hard.together and host.hard.reset_pending():
		again.disabled = true
		status.text = PlayerCopy.HARD_RESET_SENDING

## The friend's slip, on this phone: the same card, once per slip, while the
## slip itself is read for Replays.
func show_friend_failed(slip: Dictionary) -> void:
	var card := _failed_card(slip)
	var again: Button = host._button(PlayerCopy.HARD_START_AGAIN, host._show_ready)
	again.name = "HardStartAgain"
	card.add_child(again)
	card.add_child(host._action_button("back", host._leave))
	_extras_run = slip
	_fill(int(slip.number))
	host.hard.mark_shown(int(slip.number))
	_take_in(str(slip.friend))

func _failed_card(kept: Dictionary) -> VBoxContainer:
	host.mode = FAILED_MODE
	var card := bare_card()
	_extras = HardModeView.add_band(card, PlayerCopy.HARD_FAILED_TITLE, HardModeView.failure_line(kept), HardModeView.failure_badge(kept), host.title_font, host.hard.mode())
	var body: Label = host._label(failed_body(host.hard.together, kept), 18)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(body)
	return card

## The failure card's line: back to stage 1 (for both, together), and whether
## the slip is kept to watch.
static func failed_body(together: bool, kept: Dictionary) -> String:
	var watch := HardMode.watchable(kept) or (together and str(kept.get("by", "")) == "friend")
	if together: return PlayerCopy.HARD_FAILED_TOGETHER + (" " + PlayerCopy.HARD_FAILED_KEPT_TOGETHER if watch else "")
	return PlayerCopy.HARD_FAILED_SOLO + (" " + PlayerCopy.HARD_FAILED_KEPT_SOLO if watch else "")

func _fill(number: int) -> void:
	if not is_instance_valid(_extras) or _extras.has_meta("filled"): return
	_extras.set_meta("filled", true)
	HardModeView.fill_extras(_extras, context(HardMode.FAILED, _extras_run, number))

func _watch(kept: Dictionary) -> void:
	if host.mode != FAILED_MODE or host.backgrounded: return
	var pairs := HardMode.watch_pairs(kept)
	if pairs.is_empty(): return
	host._replay_collection = pairs
	host.replay_pair_index = pairs.size() - 1
	host._play_collection_pair()

## Start again: solo, the run's journal empties if it has not yet; together,
## a reset that could not be kept is queued again, and a waiting one is sent.
func start_again() -> void:
	if host.mode != FAILED_MODE or host.backgrounded: return
	if host.hard.together:
		if host.hard.reset_pending() or host.hard.requeue(host.turn_tries):
			send_reset()
			return
		host._show_ready()
		return
	# A journal that could not be emptied is emptied now, or stays refused.
	if HardRun.solo_left_over(host.journey) and not host.hard.restart_solo(host.journey, host.turn_tries, host.chapter_key):
		host._show_error(host.journey.last_error if not host.journey.last_error.is_empty() else PlayerCopy.HARD_RESTART_STUCK)
		return
	host._show_ready()

## Sends a hard room's waiting reset and redraws the failed card's status.
func send_reset() -> void:
	var generation: int = host.online_request_generation
	var answer: Dictionary = await host.hard.send_reset(host.turn_tries)
	if not host.is_inside_tree() or generation != host.online_request_generation or host.mode != FAILED_MODE: return
	var card: Node = host.controls.modal_stack if is_instance_valid(host.controls) else null
	var again: Button = card.find_child("HardStartAgain", true, false) if is_instance_valid(card) else null
	var status: Label = card.find_child("HardResetStatus", true, false) if is_instance_valid(card) else null
	if not is_instance_valid(again) or not is_instance_valid(status): return
	var done: bool = answer.get("ok", false) or answer.get("settled", false)
	again.disabled = false
	status.text = "" if done else PlayerCopy.HARD_RESET_WAITING
	if answer.get("ok", false): _fill(int(answer.get("number", 0)))
	if done: host.refresh_schedule.note_activity(Time.get_ticks_msec())

## Reads the friend's slip for Replays. One quiet note when it cannot be read;
## it is not tried again on this screen, and no turn waits on it.
func _take_in(partner: String) -> void:
	await host.hard.take_in_failures(partner)
	if host.hard.read_failed and not _read_note_shown and host.is_inside_tree():
		_read_note_shown = true
		host.notification_deferred(PlayerCopy.HARD_READ_FAILED)

## A hard room with no space for another run. Its host can open a new one;
## the friend waits for them.
func show_room_full() -> void:
	host.mode = FULL_MODE
	if host.hard.hosting():
		var card: VBoxContainer = host._card(PlayerCopy.HARD_ROOM_FULL_TITLE, PlayerCopy.HARD_ROOM_FULL_BODY)
		card.add_child(host._button(PlayerCopy.HARD_NEW_ROOM, host._create_another_room))
		card.add_child(host._action_button("back", host._leave))
		return
	var waiting: VBoxContainer = host._card(PlayerCopy.HARD_ROOM_FULL_TITLE, PlayerCopy.HARD_ROOM_FULL_GUEST % _host_name())
	waiting.add_child(host._action_button("back", host._leave))

func _host_name() -> String:
	var name: String = host._waiting_partner_name(host.journey.snapshot())
	return name if not name.is_empty() else PlayerCopy.HARD_FRIEND_FALLBACK

## Play Hard again, from a finished solo run.
func again() -> void:
	if host.mode != "complete" or host.online_session != null or not on(): return
	if not host.hard.restart_solo(host.journey, host.turn_tries, host.chapter_key):
		host._note_refusal(host.journey.last_error)
		return
	host._show_ready()
