extends RefCounted
## One chapter screen's hard run (services/hard_mode.gd): a solo run on its
## own journal, or a friend's hard room. The screen holds one (or none outside
## hard mode) and asks it, at a few seams, what it offers, whether a start or
## a finished turn ends the run, and hands it the failure and the finish.
##
## Solo: a failure keeps the run (HardMode.save_run), clears the journal and
## the run's open try counts, so the next start is stage 1, try 1.
## Together: a failure keeps the run, drops the room's draft (a slip is never
## kept as a held draft), closes the turn's try count and queues the room's
## reset (services/hard_room_client.gd), which the screen sends. The room
## moves both phones back to stage 1; the friend's phone reads who slipped.
const HardMode = preload("res://services/hard_mode.gd")
const HardRoomClient = preload("res://services/hard_room_client.gd")
const Typed = preload("res://services/typed_values.gd")

var chapter_key := ""
var together := false
var store: RefCounted
var session: RefCounted
## The run the last failure kept.
var last_run: Dictionary = {}

static func solo(key: String, marks_path: String = HardMode.MARKS_PATH) -> RefCounted:
	var run: RefCounted = load("res://services/hard_run.gd").new()
	run.chapter_key = key
	run.store = HardMode.new(marks_path)
	return run

## A room screen's run: active() only while its room is a hard room.
static func for_room(online: RefCounted, marks_path: String = HardMode.MARKS_PATH) -> RefCounted:
	var run: RefCounted = load("res://services/hard_run.gd").new()
	run.together = true
	run.session = online
	run.store = HardMode.new(marks_path)
	return run

## Whether hard rules apply now: always solo, in a hard room together.
func active() -> bool:
	return not together or room().get("hard") is Dictionary

func room() -> Dictionary:
	if session == null or session.coordinator == null: return {}
	return session.coordinator.snapshot()

## A hard room whose last reset found no space for another run.
func over() -> bool:
	var hard: Variant = room().get("hard")
	return together and hard is Dictionary and hard.get("over") is bool and hard.over

func mode() -> String:
	return HardMode.TOGETHER if together else HardMode.SOLO

func key() -> String:
	return chapter_key if not together else str(session.coordinator.chapter_key()) if session != null and session.coordinator != null else ""

## The chapter its try counts are kept under (TurnTries.slot_for).
func tries_key(screen_key: String) -> String:
	return screen_key if together else HardMode.tries_key(screen_key)

func offers(action_id: String) -> bool: return HardMode.offers(action_id)
func slipped(tries: int) -> bool: return HardMode.slipped(tries)
func failure(verified: Dictionary) -> String: return HardMode.failure(verified)


# Solo ------------------------------------------------------------------------

## A solo slip: keeps the run up to the slip, then starts the run again.
## `slip` is the slipped turn's recording ({} when it never got one). False
## when the journal could not be started again; restart_solo tries again.
func fail_solo(journey: RefCounted, tries: RefCounted, reason: String, slip: Dictionary, screen_key: String) -> bool:
	var recording: Dictionary = slip if not slip.is_empty() else (journey.draft() if journey.has_draft() else {})
	var kept: Dictionary = {} if recording.is_empty() else {"recording": recording.duplicate(true), "checkpoint": journey.checkpoint(), "prior": journey.prior_recording()}
	last_run = HardMode.run_record(chapter_key, HardMode.SOLO, HardMode.FAILED, reason, "you", int(journey.checkpoint().get("stage_index", 0)), str(journey.role()), journey.pairs(), kept)
	# Keeping the slip is for laughs; the restart never waits on it.
	HardMode.save_run(last_run)
	return restart_solo(journey, tries, screen_key)

## Starts the solo run again from stage 1: the journal empties and every open
## try count of the run goes. The counts go only once the journal is empty,
## so a journal that could not be emptied keeps refusing a second start.
func restart_solo(journey: RefCounted, tries: RefCounted, screen_key: String) -> bool:
	if not HardMode.clear_journal(journey): return false
	tries.restart_solo(tries_key(screen_key))
	return true

## A finished solo run: its mark and the run kept for Replays.
func complete_solo(journey: RefCounted) -> void:
	store.record(chapter_key, HardMode.SOLO)
	var pairs: Array = journey.pairs()
	HardMode.save_run(HardMode.run_record(chapter_key, HardMode.SOLO, HardMode.COMPLETE, "", "", pairs.size(), "", pairs, {}))


# Together --------------------------------------------------------------------

func client() -> RefCounted:
	if session == null or not session.has_method("hard_client"): return null
	var room_client: RefCounted = session.hard_client()
	var room_id := str(room().get("room_id", ""))
	if room_client == null or room_id.is_empty() or not room_client.bind(room_id): return null
	return room_client

## A slip in a hard room: kept here, the turn's draft and try count dropped,
## the reset queued. `partner` is the friend's name now. False when the reset
## could not be kept (the screen says so and offers it again).
func fail_together(reason: String, slip: Dictionary, tries: RefCounted, slot: String, partner: String) -> bool:
	var current := room()
	var room_client := client()
	if current.is_empty() or room_client == null: return false
	var prior: Variant = current.get("recording_a")
	var kept: Dictionary = {} if slip.is_empty() else {"recording": slip.duplicate(true), "checkpoint": Typed.as_dict(current.get("checkpoint")), "prior": prior.duplicate(true) if prior is Dictionary and str(current.get("active_role")) == "b" else {}}
	last_run = HardMode.run_record(key(), HardMode.TOGETHER, HardMode.FAILED, reason, "you", int(current.get("stage_index", 0)), str(current.get("active_role", "a")), [], kept, partner, str(current.get("room_id", "")))
	HardMode.save_run(last_run)
	# Never held: a held draft per slip would fill the room's four and stop it.
	session.coordinator.save_draft({})
	tries.close(slot)
	if not room_client.pending().is_empty(): return true
	return room_client.queue_reset(current, reason, slip)

## A reset still waiting for the server: no turn starts until it lands.
func reset_pending() -> bool:
	var room_client := client()
	return room_client != null and not room_client.pending().is_empty()

## What the card shows for a reset kept from before this screen (the app
## closed before it was sent).
func pending_run() -> Dictionary:
	var room_client := client()
	var body: Dictionary = room_client.pending() if room_client != null else {}
	return {"reason": str(body.get("reason", "failed_turn")), "stage_index": int(body.get("stage_index", 0)), "by": "you", "friend": ""}

## Sends the waiting reset; on success the room's new snapshot is the
## coordinator's. {"ok"} or {"ok": false, "settled"} as HardRoomClient.send().
func send_reset() -> Dictionary:
	var room_client := client()
	if room_client == null: return {"ok": false, "code": "hard_storage_unavailable"}
	var answer: Dictionary = await room_client.send()
	if answer.get("ok", false) and session != null and session.coordinator != null: session.coordinator.adopt_snapshot(answer.room)
	return answer

## The note for a friend's slip this phone has not taken in yet, or "".
## `partner` is the friend's name now.
func notice(partner: String) -> String:
	var current := room()
	var hard: Variant = current.get("hard")
	var room_client := client()
	if not hard is Dictionary or not hard.get("last") is Dictionary or room_client == null or int(hard.failures) <= room_client.seen(): return ""
	if Typed.equal(hard.last.by, _me(current)): return ""
	return HardMode.notice_text(partner, int(hard.last.stage_index))

## Reads the room's failures this phone has not seen and keeps the friend's
## as runs here. Costs one request, only after a new failure.
func take_in_failures(partner: String) -> int:
	var current := room()
	var room_client := client()
	if room_client == null or not current.get("hard") is Dictionary or int(current.hard.failures) <= room_client.seen(): return 0
	var fresh: Array = await room_client.read_failures(current)
	var me := _me(current)
	var kept := 0
	for item: Dictionary in fresh:
		if Typed.equal(item.by, me): continue
		var slip: Variant = item.get("slip")
		var shown: Dictionary = {} if not slip is Dictionary else {"recording": slip.recording, "checkpoint": slip.checkpoint, "prior": slip.prior if slip.get("prior") is Dictionary else {}}
		var record := HardMode.run_record(key(), HardMode.TOGETHER, HardMode.FAILED, str(item.reason), "friend", int(item.stage_index), str(item.role), [], shown, partner, str(current.get("room_id", "")))
		record.at = int(Time.get_unix_time_from_datetime_string(str(item.at)))
		if HardMode.save_run(record): kept += 1
	return kept

## A finished hard room: its mark.
func complete_together() -> void:
	store.record(key(), HardMode.TOGETHER)

static func _me(current: Dictionary) -> String:
	return str(current.get("host_id", "")) if current.get("player_slot") == "p0" else str(current.get("guest_id", ""))
