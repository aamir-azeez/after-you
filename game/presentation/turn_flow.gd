extends Node
## Submitting an earlier-island (v1) room turn and handling its outcome: the
## unsent turn saved before its request goes out, the check and exact resend of
## a turn whose answer was lost, a turn the server refuses, and the held screen
## that keeps its rehearsal.
##
## Main hosts it as a child and keeps the room write lock (submission_in_flight,
## _one_room_write, shared with fork, advance and reactions) and active_room;
## the room page is LegacyRoomFlow's. The flow keeps no state of its own: the unsent
## turn lives in saves ("pending_turn", "held_turns"). It asks Main to show the
## room hub through rooms_requested, and reads Main only through this host
## contract (read at call time, so Main or a test can swap a service):
## - services: api, saves, _ensure_identity
## - screen: mode, running, review_recording, _toast, _report
## - room flow: active_room, submission_in_flight, _one_room_write,
##   _return_to_room_hub, legacy_room_flow (accept_room, show_room)
## - card kit: _card, _label, _paragraph, _button, _back_button
## Main calls commit_online() from review, reconcile_pending() from the room
## page's Check saved submission, show_unsent_turn() when an unsent turn holds
## online play, pending_owned() for the foreground refresh, and reject_pending()
## with keep_held_turn() when a block ends the room.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const TurnState = preload("res://services/turn_state.gd")
const RoomsApi = preload("res://services/rooms_api.gd")
const LocalSave = preload("res://services/local_save.gd")
const Typed = preload("res://services/typed_values.gd")
const Levels = preload("res://core/levels.gd")
const CREAM := Color("eceddb")
## Main's mode while a held turn is shown.
const MODE_HELD := "held"

signal rooms_requested

var host: Node

func _init(main: Node = null) -> void:
	host = main

func commit_online() -> void:
	if host.submission_in_flight:
		return
	var pending: Dictionary=host.saves.data.get("pending_turn",{})
	if not pending.is_empty():
		await reconcile_pending()
		return
	if not TurnState.my_turn(host.active_room,host.api.player_id):
		host._toast(PlayerCopy.MAIN_2FB9511D4AA8)
		return
	pending={"room_id":host.active_room.room_id,"owner_player_id":host.api.player_id,"base_revision":host.active_room.revision,"idempotency_key":RoomsApi.new_key(),"recording":host.review_recording.duplicate(true)}
	if not host.saves.update_values({"pending_turn":pending}):
		host._toast(PlayerCopy.MAIN_9F721149F702)
		return
	await _send_pending(pending)

func _send_pending(pending: Dictionary) -> void:
	var screen: String = host.mode
	host.submission_in_flight=true
	var response: Dictionary=await host.api.request_json(HTTPClient.METHOD_POST,"/v1/rooms/"+str(pending.room_id)+"/turns",{"base_revision":pending.base_revision,"idempotency_key":pending.idempotency_key,"recording":pending.recording})
	host.submission_in_flight=false
	if response.ok:
		# The exact idempotency key returning success is the receipt, even if the
		# room has advanced and the API returns its latest snapshot.
		if not host.saves.update_values({},["pending_turn","room_draft"]):
			host._toast(PlayerCopy.MAIN_B701225FD961)
		host.legacy_room_flow.accept_room(response)
	elif int(response.status)>=400 and int(response.status)<500 and int(response.status) not in [408,429]:
		# A player who moved on meanwhile is not pulled back; their next online
		# tap opens the held turn (Main's _relay_available).
		_save_refused_turn(pending,response)
		if host.mode==screen: show_held_turn(pending)
	else:
		# A timeout or server error leaves the turn unsent, to check and send again.
		host._toast(response.error+PlayerCopy.MAIN_F7B46601CBC3)

func reconcile_pending() -> void:
	if host.submission_in_flight or not await host._ensure_identity():
		return
	var pending: Dictionary=host.saves.data.get("pending_turn",{})
	if pending.is_empty():
		return
	if not pending_owned(pending):
		host._toast(PlayerCopy.MAIN_ECBD713D8F0C)
		return
	var screen: String = host.mode
	var response: Dictionary=await host._one_room_write(host.api.request_json.bind(HTTPClient.METHOD_GET,"/v1/rooms/"+str(pending.room_id)))
	# A player who moved on meanwhile is not pulled back: only a refusal is
	# saved, and their next online tap opens it (Main's _relay_available).
	var current: bool = host.mode==screen
	if not response.ok:
		if _room_refused(response):
			_save_refused_turn(pending,response)
			if current: show_held_turn(pending)
			return
		host._toast(response.error+PlayerCopy.MAIN_602A7BD28B67)
		return
	if not current: return
	var room: Dictionary=response.data.get("room",response.data)
	var status := TurnState.pending_status(pending,room)
	if status=="accepted":
		host.legacy_room_flow.accept_room(response)
		host._toast(PlayerCopy.MAIN_A917FC21E486)
		return
	host.active_room=room.duplicate(true)
	if bool(pending.get("rejected",false)):
		show_held_turn(pending)
		return
	# Retry once with exactly the same saved body/key. The server deduplicates
	# before revision checks, so an earlier success cannot become a second turn.
	await _send_pending(pending)

## Whether an unsent turn is this identity's: a turn saved before turns named
## their owner counts as this identity's.
func pending_owned(pending: Dictionary) -> bool:
	return not pending.has("owner_player_id") or Typed.equal(pending.owner_player_id,host.api.player_id)

## The room is gone for this player: deleted, not found, or a block between
## the two players.
static func _room_refused(response: Dictionary) -> bool:
	var status := int(response.get("status",0))
	return status in [404,410] or (status==403 and str(response.get("code",""))=="player_blocked")

## The server refused an unsent turn for good: it is saved as rejected, for
## its held screen. A room that is gone goes with it, and so does the draft
## played there, so neither holds anything later.
func _save_refused_turn(pending: Dictionary, response: Dictionary) -> void:
	var changes := {"pending_turn":pending}
	var erased: Array = []
	if _room_refused(response):
		reject_pending(pending)
		host.active_room={}
		if Typed.equal(Typed.as_dict(host.saves.data.get("room")).get("room_id"),pending.get("room_id")): changes["room"]={}
		if Typed.equal(Typed.as_dict(host.saves.data.get("room_draft")).get("room_id"),pending.get("room_id")): erased.append("room_draft")
	else:
		reject_pending(pending,response.error)
	if not host.saves.update_values(changes,erased): host._toast(host.saves.last_error)

## An unsent turn holds online play. A turn the server refused opens its held
## screen, whose Keep and Back both keep the rehearsal. One still unanswered
## opens its saved room, where Check saved submission sends it again; with no
## saved room to show, it is held too. Another identity's turn is never opened
## here: the reason shows (report) and the screen stays.
func show_unsent_turn(report: Callable = Callable()) -> void:
	var pending: Dictionary = host.saves.data.get("pending_turn",{})
	if not pending_owned(pending):
		host._report(report,PlayerCopy.MAIN_ECBD713D8F0C)
		return
	var saved: Dictionary = Typed.as_dict(host.saves.data.get("room"))
	host.active_room = saved.duplicate(true) if Typed.equal(saved.get("room_id"),pending.get("room_id")) else {}
	if bool(pending.get("rejected",false)) or host.active_room.is_empty(): show_held_turn(pending)
	else: host.legacy_room_flow.show_room()

func show_held_turn(pending: Dictionary) -> void:
	host.running=false
	host.mode=MODE_HELD
	var card: VBoxContainer = host._card()
	card.add_child(host._label(PlayerCopy.MAIN_2A20737AA436,32,CREAM,true))
	card.add_child(host._paragraph(str(pending.get("error",PlayerCopy.MAIN_6D127185ABF4))))
	card.add_child(host._paragraph(PlayerCopy.MAIN_BCD95F847CF2))
	card.add_child(host._button("Keep rehearsal & return",func(): _archive_held_turn(pending)))
	# Back keeps the rehearsal too, then goes to the hub: a refused turn left
	# unsent would hold online play for good.
	card.add_child(host._back_button("Back",func(): if keep_held_turn(pending,host.active_room): host._return_to_room_hub(),false))

## Marks an unsent turn as refused for good, with the reason its held turn shows.
func reject_pending(pending: Dictionary, error: String = PlayerCopy.MAIN_52480E5314F5) -> Dictionary:
	pending["rejected"]=true
	pending["error"]=error
	return pending

func _archive_held_turn(pending: Dictionary) -> void:
	if not keep_held_turn(pending,host.active_room): return
	if host.active_room.is_empty(): rooms_requested.emit()
	else: host.legacy_room_flow.show_room()

## Keeps a held turn's rehearsal in held_turns and clears the unsent turn, as
## Keep rehearsal & return does; room becomes the saved room ({} for none).
## False, with the reason shown, if not saved.
func keep_held_turn(pending: Dictionary, room: Dictionary) -> bool:
	var held: Array=host.saves.data.get("held_turns",[]).duplicate(true)
	held.append(pending.duplicate(true))
	var changes := {"held_turns":held,"room":room.duplicate(true)}
	if TurnState.my_turn(room,host.api.player_id) and Typed.equal(Typed.as_dict(pending.get("recording")).get("level_id"),room.get("level_id")):
		var current_attempt := LocalSave.normalize_attempt(room.get("recordings",{}))
		if TurnState.review(Levels.get_level(room.level_id),pending.recording,current_attempt,TurnState.simulation_version({},str(pending.recording.get("role","")),room)).valid:
			current_attempt.draft=pending.recording.duplicate(true)
			changes["room_draft"]={"room_id":room.room_id,"revision":room.revision,"attempt":current_attempt}
	if not host.saves.update_values(changes,["pending_turn"]):
		host._toast(host.saves.last_error)
		return false
	return true
