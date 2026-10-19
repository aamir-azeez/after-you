extends RefCounted
## One chapter screen's hard run (services/hard_mode.gd): a solo run on its
## own journal, or a friend's hard room. The screen holds one (or none outside
## hard mode) and asks it, at a few seams, what it offers, whether a start or
## a finished turn ends the run, and hands it the failure and the finish.
##
## Solo: a failure keeps the run (HardMode.keep_run), clears the journal and
## the run's open try counts, so the next start is stage 1, try 1.
## Together: a failure keeps the run and queues the room's reset
## (services/hard_room_client.gd) first; only once the reset is kept does the
## turn's draft go. The turn's open try count stays open until the room has
## taken the reset, so a reset that never lands can never give a free retry:
## a second start of that turn is still a slip. The room moves both phones
## back to stage 1; the friend's phone shows the same failure card once and
## reads the slip for Replays.
const HardMode = preload("res://services/hard_mode.gd")
const HardRoomClient = preload("res://services/hard_room_client.gd")
const TurnTries = preload("res://services/turn_tries.gd")
const Typed = preload("res://services/typed_values.gd")

var chapter_key := ""
var together := false
var store: RefCounted
var session: RefCounted
## The run the last failure kept.
var last_run: Dictionary = {}
## A failed read of the friend's slips: not tried again on this screen.
var read_failed := false
## The slip whose reset this phone owes the room ({reason, slip}), so a reset
## the room refused as stale can be queued again from the room as it is now.
var _owed: Dictionary = {}

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
	return not together or hard_view() is Dictionary

## The room's hard field (HardRoomClient.valid_view), or null; never copies the room.
func hard_view() -> Variant:
	if session == null or session.coordinator == null: return null
	return session.coordinator.hard_view()

func room() -> Dictionary:
	if session == null or session.coordinator == null: return {}
	return session.coordinator.snapshot()

## A hard room whose last reset found no space for another run.
func over() -> bool:
	var hard: Variant = hard_view()
	return together and hard is Dictionary and hard.get("over") is bool and hard.over

## How many slips the room has counted (0 solo).
func failures() -> int:
	var hard: Variant = hard_view()
	return int(hard.failures) if hard is Dictionary else 0

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
	HardMode.keep_run(last_run)
	return restart_solo(journey, tries, screen_key)

## Starts the solo run again from stage 1: the journal empties and every open
## try count of the run goes. The counts go only once the journal is empty,
## so a journal that could not be emptied keeps refusing a second start.
func restart_solo(journey: RefCounted, tries: RefCounted, screen_key: String) -> bool:
	if not HardMode.clear_journal(journey): return false
	tries.restart_solo(tries_key(screen_key))
	return true

## Whether the solo run is still the one that failed (its journal could not
## be emptied yet).
static func solo_left_over(journey: RefCounted) -> bool:
	return not journey.pairs().is_empty() or not journey.prior_recording().is_empty() or journey.has_draft()

## A finished solo run: its mark and the run kept for Replays.
func complete_solo(journey: RefCounted) -> void:
	store.record(chapter_key, HardMode.SOLO)
	var pairs: Array = journey.pairs()
	HardMode.keep_run(HardMode.run_record(chapter_key, HardMode.SOLO, HardMode.COMPLETE, "", "", pairs.size(), "", pairs, {}))


# Together --------------------------------------------------------------------

func client() -> RefCounted:
	if session == null or not session.has_method("hard_client"): return null
	var room_client: RefCounted = session.hard_client()
	var room_id := str(room().get("room_id", ""))
	if room_client == null or room_id.is_empty() or not room_client.bind(room_id): return null
	return room_client

## A slip in a hard room: kept here and its reset queued, then the turn's
## draft dropped. `partner` is the friend's name now. False when the reset
## could not be kept: nothing else changed, so the turn's open count still
## makes its next start a slip, and Start again queues it again (requeue).
func fail_together(reason: String, slip: Dictionary, partner: String) -> bool:
	var current := room()
	if current.is_empty(): return false
	var prior: Variant = current.get("recording_a")
	var kept: Dictionary = {} if slip.is_empty() else {"recording": slip.duplicate(true), "checkpoint": Typed.as_dict(current.get("checkpoint")), "prior": prior.duplicate(true) if prior is Dictionary and str(current.get("active_role")) == "b" else {}}
	last_run = HardMode.run_record(key(), HardMode.TOGETHER, HardMode.FAILED, reason, "you", int(current.get("stage_index", 0)), str(current.get("active_role", "a")), [], kept, partner, str(current.get("room_id", "")))
	HardMode.keep_run(last_run)
	_owed = {"reason": reason, "slip": slip.duplicate(true)}
	return requeue()

## Queues the owed reset again from the room as it is now, when the turn that
## slipped is still open (`tries` counts it) and no reset waits. True when a
## reset waits afterwards.
func requeue(tries: RefCounted = null) -> bool:
	var room_client := client()
	if room_client == null: return false
	if not room_client.pending().is_empty(): return true
	if _owed.is_empty() or (tries != null and tries.count(TurnTries.slot_for(session.coordinator, key(), true)) == 0): return false
	if not room_client.queue_reset(room(), str(_owed.reason), _owed.slip): return false
	# Never held: a held draft per slip would fill the room's four and stop it.
	session.coordinator.save_draft({})
	return true

## A reset still waiting for the server: no turn starts until it lands.
func reset_pending() -> bool:
	var room_client := client()
	return room_client != null and not room_client.pending().is_empty()

## What the card shows for a reset kept from before this screen (the app
## closed before it was sent).
func pending_run() -> Dictionary:
	var room_client := client()
	var body: Dictionary = room_client.pending() if room_client != null else {}
	return {"reason": str(body.get("reason", "failed_turn")), "stage_index": int(body.get("stage_index", 0)), "role": str(body.get("role", "a")), "by": "you", "friend": "", "pairs": [], "slip": {}}

## Sends the waiting reset; on success the room's new snapshot is the
## coordinator's and the slipped turn's count closes. A reset the room
## refused as stale while the slipped turn is still open (a friend joined in
## between) is queued again from the room read afresh and sent once more.
## {"ok", "number"} or {"ok": false, "settled"} as HardRoomClient.send().
func send_reset(tries: RefCounted, again: bool = true) -> Dictionary:
	var room_client := client()
	if room_client == null: return {"ok": false, "code": "hard_storage_unavailable"}
	var slot := TurnTries.slot_for(session.coordinator, key(), true)
	var answer: Dictionary = await room_client.send()
	if answer.get("ok", false):
		session.coordinator.adopt_snapshot(answer.room)
		tries.close(slot)
		_owed = {}
	elif answer.get("settled", false) and answer.get("code") == "stale_revision" and again and not _owed.is_empty() and tries.count(slot) > 0:
		if await session.coordinator.refresh() and TurnTries.slot_for(session.coordinator, key(), true) == slot and session.coordinator.my_turn() and requeue(tries):
			return await send_reset(tries, false)
	return answer

## The friend's slip this phone has not shown a card for, as a run for the
## card ({} when none). `partner` is the friend's name now. This phone's own
## slips are counted as shown.
func friend_slip(partner: String) -> Dictionary:
	var hard: Variant = hard_view()
	var room_client := client()
	if not hard is Dictionary or not hard.get("last") is Dictionary or room_client == null or int(hard.failures) <= room_client.shown(): return {}
	if Typed.equal(hard.last.by, _me(room())):
		room_client.mark_shown(int(hard.failures))
		return {}
	return {"reason": str(hard.last.reason), "stage_index": int(hard.last.stage_index), "role": str(hard.last.role), "by": "friend", "friend": partner, "pairs": [], "slip": {}, "number": int(hard.failures)}

## The friend's slip card was shown.
func mark_shown(number: int) -> void:
	var room_client := client()
	if room_client != null: room_client.mark_shown(number)

## Reads the room's slips this phone has not seen and keeps the friend's as
## runs here. One request, only after a new slip, and none again on this
## screen once a read failed. The kept runs (newest last); [] when none.
func take_in_failures(partner: String) -> Array:
	var current := room()
	var room_client := client()
	if read_failed or room_client == null or not current.get("hard") is Dictionary or int(current.hard.failures) <= room_client.seen(): return []
	var read: Dictionary = await room_client.read_failures(current)
	if not read.get("ok", false):
		read_failed = true
		return []
	var me := _me(current)
	var kept: Array = []
	for item: Dictionary in read.list:
		if Typed.equal(item.by, me): continue
		var slip: Variant = item.get("slip")
		var shown: Dictionary = {} if not slip is Dictionary else {"recording": slip.recording, "checkpoint": slip.checkpoint, "prior": slip.prior if slip.get("prior") is Dictionary else {}}
		var record := HardMode.run_record(key(), HardMode.TOGETHER, HardMode.FAILED, str(item.reason), "friend", int(item.stage_index), str(item.role), [], shown, partner, str(current.get("room_id", "")))
		record.at = int(Time.get_unix_time_from_datetime_string(str(item.at)))
		HardMode.keep_run(record)
		record.number = int(item.number)
		kept.append(record)
	return kept

## A finished hard room: its mark.
func complete_together() -> void:
	store.record(key(), HardMode.TOGETHER)

## Whether this phone made the room (its host).
func hosting() -> bool:
	var current := room()
	return current.get("player_slot") == "p0"

static func _me(current: Dictionary) -> String:
	return str(current.get("host_id", "")) if current.get("player_slot") == "p0" else str(current.get("guest_id", ""))
