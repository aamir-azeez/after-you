extends "res://tests/test_relay_online.gd"
## The room hub lists earlier-island and chapter rooms side by side and opens
## either. Blocking the other player from an earlier-island room lands on the
## hub, and that room is neither the current room, the saved room nor listed
## any more, even while the hub can only show its saved list. That room's
## unsent turn is kept as a held turn, so online play opens again. When the
## other player blocks first, checking an unsent turn holds it instead of
## leaving it pending for good. A turn the server refuses on submit opens its
## held screen, and when the player left before the answer, their next online
## tap does. A timeout or server error leaves the turn unsent and retryable.
## Another identity's unsent turn is never opened.

const Safety = preload("res://services/safety_client.gd")
const SafetyStore = preload("res://services/safety_store.gd")
const LEGACY := "LLLLLLLLLLLLLLLLLLLLLL"
const LEGACY_PENDING := "MMMMMMMMMMMMMMMMMMMMMM"
const LEGACY_PARTNER := "QQQQQQQQQQQQQQQQQQQQQQ"
const LEGACY_OTHER := "OOOOOOOOOOOOOOOOOOOOOO"
const LEGACY_DRAFT := "DDDDDDDDDDDDDDDDDDDDDD"
const LEGACY_BACK := "KKKKKKKKKKKKKKKKKKKKKK"
const LEGACY_SUBMIT := "SSSSSSSSSSSSSSSSSSSSSS"
const LEGACY_AWAY := "WWWWWWWWWWWWWWWWWWWWWW"
const LEGACY_RETRY := "TTTTTTTTTTTTTTTTTTTTTT"
const LEGACY_CHECK := "CCCCCCCCCCCCCCCCCCCCCC"
const LEGACY_EARLIER := "EEEEEEEEEEEEEEEEEEEEEE"
const NEXT_IDENTITY := "NNNNNNNNNNNNNNNNNNNNNN"
const Copy = preload("res://presentation/player_copy.gd")
const PEER := "PPPPPPPPPPPPPPPPPPPPPP"
const BLOCKED_ERROR := "Synthetic blocked room."
var blocked: Dictionary = {}
var inbox_offline := false
var block_target := ""
var safety_dir := ""
## The next answers to a turn submitted in a room: "blocked", "timeout" or
## "unavailable"; with none left the turn is accepted.
var turn_replies: Dictionary = {}
## A finished first turn on the first island.
var played: Dictionary

func _run() -> void:
	for name: String in ["relay-a","relay-b","garden-a","garden-b","initial-checkpoint","relay-checkpoint","final-checkpoint"]:
		fixtures[name]=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/v2/"+name+".json"))
	var viewport := SubViewport.new()
	viewport.size=Vector2i(1280,720)
	root.add_child(viewport)
	var suffix := Crypto.new().generate_random_bytes(8).hex_encode()
	var path := "user://room-hub-block-"+suffix+".json"
	cleanup_paths.append(path)
	safety_dir="user://room-hub-block-safety-"+suffix
	var app := Main.new()
	app.saves=Save.new(path)
	app.saves.data.settings.sound=false
	app.saves.data.settings.haptics=false
	_check(app.saves.flush(),"Prepare isolated muted profile")
	viewport.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	app.api.queue_free()
	var api := _api()
	# Its own server address keeps this run's saved hub list apart from other runs.
	api.base_url="https://room-hub-block-"+suffix+".invalid"
	root.remove_child(api)
	app.add_child(api)
	app.api=api
	api.exists=true
	api.joined=true
	app.identity_read_state=Main.IdentityReadState.LOADED
	app.identity_data={"player_id":HOST,"device_token":"synthetic-device-token"}
	app.relay_session=Session.new(api,app._relay_identity,MemoryStore.new())
	var saved := FileAccess.get_file_as_string(path)
	app._return_to_room_hub()
	await _frames(4)
	var hub: Node=app.room_hub_flow.screen
	_check(is_instance_valid(hub) and app.mode=="rooms","The hub opens")
	_check(is_instance_valid(hub) and hub.room_action(LEGACY)!=null and hub.room_action(ROOM)!=null,"The hub lists an earlier-island room and a chapter room together")
	_check(FileAccess.get_file_as_string(path)==saved,"Listing both room families never changes the gameplay save")
	await _block_saved_room(app,api)
	await _block_with_other_pending_turn(app,api)
	await _block_with_pending_turn(app,api)
	await _block_with_room_draft(app,api)
	await _partner_blocked_keep(app,api)
	await _partner_blocked_back(app,api)
	played=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/first-light-a.json"))
	await _refused_on_submit(app,api)
	await _refused_after_leaving(app,api)
	await _unanswered_submit(app,api)
	await _refused_while_checking(app,api)
	await _previous_identity_turn(app,api)
	_finish(viewport)

## Opens the earlier-island room from the hub card; false when it did not open.
func _open_from_hub(app: Node, api: FakeApi, room_id: String) -> bool:
	var hub: Node=app.room_hub_flow.screen
	var before: int=api.calls.size()
	if is_instance_valid(hub) and hub.room_action(room_id)!=null: hub.room_action(room_id).pressed.emit()
	await _frames(4)
	_check(app.mode=="room" and app.active_room.get("room_id")==room_id,"An earlier-island card opens that room: "+room_id)
	var opened: Array=api.calls.slice(before)
	_check(opened.filter(func(call: Dictionary) -> bool: return call.method==HTTPClient.METHOD_GET and call.path=="/v1/rooms/"+room_id).size()==1,"Opening it reads the room once: "+room_id)
	_check(not opened.any(func(call: Dictionary) -> bool: return call.method!=HTTPClient.METHOD_GET),"Opening it sends no join or other change: "+room_id)
	_check(app.friend_share_target=={"api_version":1,"room_id":room_id},"The opened room is the one Friends would share: "+room_id)
	return app.mode=="room"

## Blocks the open room's other player through the safety screen's own Block.
func _block_open_room(app: Node, room_id: String) -> bool:
	block_target=room_id
	app._room_safety()
	await _frames(2)
	var screen: Node=app.safety_screen
	_check(is_instance_valid(screen) and app.mode=="safety","Report or block opens the safety screen for this room: "+room_id)
	if not is_instance_valid(screen): return false
	# A safety store of its own, so the block is never saved where other runs read.
	screen.client=Safety.new(app.api,app._relay_identity,SafetyStore.new(safety_dir))
	await screen._block()
	return true

## Main runs normally here, so a foreground refresh of a room left saved would
## read the blocked room and show its refusal on the hub.
func _block_saved_room(app: Node, api: FakeApi) -> void:
	if not await _open_from_hub(app,api,LEGACY): return
	app.set_process(true)
	var start: int=api.calls.size()
	if not await _block_open_room(app,LEGACY): return
	var notices: Array[String] = await _notices(app,6)
	# As a resume would: ask for the foreground refresh straight away.
	app.queue_foreground_refresh()
	notices.append_array(await _notices(app,10))
	app.set_process(false)
	_check(blocked.has(LEGACY) and not is_instance_valid(app.safety_screen),"The block is confirmed and the safety screen closes")
	_check(app.mode=="rooms" and app.room_hub_flow.is_open() and app.ui.visible==false,"Blocking from safety lands on the room hub")
	_check(app.active_room.is_empty(),"The blocked room is no longer the current room")
	_check(app.saves.data.get("room",{}).is_empty(),"The blocked room is no longer the saved room")
	_check(app.friend_share_target.get("room_id")!=LEGACY,"Friends no longer offers the blocked room")
	_check(not api.calls.slice(start).any(func(call: Dictionary) -> bool: return call.path=="/v1/rooms/"+LEGACY),"Nothing reads the blocked room after the block")
	_check(not notices.any(func(text: String) -> bool: return text.contains(BLOCKED_ERROR)),"No refusal for the blocked room shows on the hub: %s" % [notices])
	var hub: Node=app.room_hub_flow.screen
	_check(is_instance_valid(hub) and hub.room_action(LEGACY)==null,"The hub's saved list leaves the blocked room out while the server cannot be reached")
	_check(is_instance_valid(hub) and hub.room_action(ROOM)!=null,"Other rooms stay on the hub")
	inbox_offline=false
	if is_instance_valid(hub): await app.room_hub_flow.refresh()
	await _frames(2)
	hub=app.room_hub_flow.screen
	_check(is_instance_valid(hub) and hub.room_action(LEGACY)==null and hub.room_action(ROOM)!=null,"Once the server list arrives the blocked room stays off the hub")
	_check(not app.room_hub_flow.inbox.view().rooms.any(func(room: Dictionary) -> bool: return room.room_id==LEGACY),"The hub's list holds no blocked room")

## A turn saved for another room is not this block's to change.
func _block_with_other_pending_turn(app: Node, api: FakeApi) -> void:
	if not await _open_from_hub(app,api,LEGACY_OTHER): return
	var other := {"room_id":"RRRRRRRRRRRRRRRRRRRRRR","owner_player_id":HOST,"base_revision":1,"idempotency_key":"synthetic-other-key","recording":{}}
	_check(app.saves.update_values({"pending_turn":other}),"Save an unsent turn for a different room")
	var held_before: Array=app.saves.data.get("held_turns",[]).duplicate(true)
	if not await _block_open_room(app,LEGACY_OTHER): return
	await _frames(4)
	_check(blocked.has(LEGACY_OTHER) and app.mode=="rooms" and app.room_hub_flow.is_open(),"Blocking with another room's unsent turn lands on the room hub")
	_check(app.saves.data.get("pending_turn",{})==other and app.saves.data.get("held_turns",[])==held_before,"Another room's unsent turn is left exactly as it was")
	_check(app.active_room.is_empty(),"The blocked room is not the current room")
	# Clear the unrelated turn so the next pass starts with online play open.
	_check(app.saves.update_values({"room":{}},["pending_turn"]),"Clear the unrelated unsent turn")

## The server confirmed the block, so this room's unsent turn can never be
## sent: its rehearsal is kept as a held turn and online play opens again.
func _block_with_pending_turn(app: Node, api: FakeApi) -> void:
	if not await _open_from_hub(app,api,LEGACY_PENDING): return
	var pending := {"room_id":LEGACY_PENDING,"owner_player_id":HOST,"base_revision":1,"idempotency_key":"synthetic-pending-key","recording":{}}
	_check(app.saves.update_values({"pending_turn":pending}),"Save an unsent turn for the room")
	_check(not app._relay_available(),"An unsent turn holds online play before the block")
	if not await _block_open_room(app,LEGACY_PENDING): return
	await _frames(4)
	_check(blocked.has(LEGACY_PENDING) and app.mode=="rooms" and app.room_hub_flow.is_open(),"Blocking with an unsent turn lands on the room hub")
	var held: Array=app.saves.data.get("held_turns",[]).filter(func(turn: Dictionary) -> bool: return turn.get("room_id")==LEGACY_PENDING)
	_check(held.size()==1 and held[0].get("idempotency_key")=="synthetic-pending-key" and held[0].get("rejected",false) and held[0].get("error")==Copy.MAIN_52480E5314F5,"The unsent turn's rehearsal is kept as a held turn: %s" % [held])
	_check(app.saves.data.get("pending_turn",{}).is_empty() and app.saves.data.get("room",{}).is_empty(),"The unsent turn and the blocked saved room are cleared")
	_check(app._relay_available(),"Online play is open again after the block")
	_check(app.active_room.is_empty() and app.friend_share_target.get("room_id")!=LEGACY_PENDING,"The blocked room is not the current room")
	var hub: Node=app.room_hub_flow.screen
	_check(is_instance_valid(hub) and hub.room_action(LEGACY_PENDING)==null,"The hub leaves out the blocked room")

## A turn started and left part way keeps a draft. After a block it can never
## be sent, so it goes too: invite links open again and the hub shows no
## refusal for the room.
func _block_with_room_draft(app: Node, api: FakeApi) -> void:
	inbox_offline=false
	if app.room_hub_flow.is_open(): await app.room_hub_flow.refresh()
	await _frames(2)
	if not await _open_from_hub(app,api,LEGACY_DRAFT): return
	var play: Button=_button_named(app,"Play your turn")
	_check(play!=null,"The room offers Play your turn")
	if play==null: return
	play.pressed.emit()
	await _frames(2)
	# The ready card's Begin, then a moment of play.
	app._begin_turn()
	for _tick in range(4): app._physics_process(1.0/60.0)
	# Back pauses the turn, which saves its draft; the pause card's back goes Home.
	app.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await _frames(2)
	_check(app.mode=="paused" and app.saves.data.get("room_draft",{}).get("room_id")==LEGACY_DRAFT,"Leaving the turn part way saves its draft: %s" % app.mode)
	app._show_home()
	app.room_hub_flow.show_rooms()
	await _frames(4)
	if not await _open_from_hub(app,api,LEGACY_DRAFT): return
	_check(app._invite_link_occupied(),"The draft holds invite links before the block")
	app.set_process(true)
	var start: int=api.calls.size()
	if not await _block_open_room(app,LEGACY_DRAFT): return
	var notices: Array[String] = await _notices(app,6)
	app.queue_foreground_refresh()
	notices.append_array(await _notices(app,10))
	app.set_process(false)
	_check(blocked.has(LEGACY_DRAFT) and app.mode=="rooms" and app.room_hub_flow.is_open(),"Blocking with a draft lands on the room hub")
	_check(app.saves.data.get("room_draft",{}).is_empty() and app.saves.data.get("room",{}).is_empty(),"The blocked room's draft and saved room are gone")
	_check(not app._invite_link_occupied(),"Invite links open again after the block")
	_check(not api.calls.slice(start).any(func(call: Dictionary) -> bool: return call.path=="/v1/rooms/"+LEGACY_DRAFT),"Nothing reads the blocked room after the block")
	_check(not notices.any(func(text: String) -> bool: return text.contains(BLOCKED_ERROR)),"No refusal for the blocked room shows on the hub: %s" % [notices])

## The other player blocked this one while a turn was saved but unsent: the
## server refuses the room, and Check saved submission shows the turn held.
## False when the held turn did not show.
func _held_by_partner_block(app: Node, api: FakeApi, room_id: String) -> bool:
	inbox_offline=false
	if app.room_hub_flow.is_open(): await app.room_hub_flow.refresh()
	await _frames(2)
	if not await _open_from_hub(app,api,room_id): return false
	var pending := {"room_id":room_id,"owner_player_id":HOST,"base_revision":1,"idempotency_key":"synthetic-key-"+room_id,"recording":{}}
	_check(app.saves.update_values({"pending_turn":pending}),"Save an unsent turn for the room")
	var refresh: Button=_button_named(app,"Refresh")
	if refresh!=null: refresh.pressed.emit()
	await _frames(4)
	var check: Button=_button_named(app,"Check saved submission")
	_check(app.mode=="room" and check!=null,"The room offers Check saved submission: "+room_id)
	if check==null: return false
	blocked[room_id]=true
	check.pressed.emit()
	await _frames(4)
	var held: Dictionary=app.saves.data.get("pending_turn",{})
	_check(app.mode=="held" and held.get("rejected",false) and held.get("error")==Copy.MAIN_52480E5314F5,"Checking a turn the server refuses after a block holds it: %s %s" % [app.mode,held])
	_check(app.active_room.is_empty(),"The refused room is no longer the current room")
	return app.mode=="held"

## Straight after a block with an unsent turn, the hub opens another room;
## Keep rehearsal & return then clears the held turn and online play opens.
func _partner_blocked_keep(app: Node, api: FakeApi) -> void:
	if not await _held_by_partner_block(app,api,LEGACY_PARTNER): return
	var keep: Button=_button_named(app,"Keep rehearsal & return")
	_check(keep!=null,"The held turn offers Keep rehearsal & return")
	if keep==null: return
	keep.pressed.emit()
	await _frames(4)
	_check(app.saves.data.get("pending_turn",{}).is_empty() and app.saves.data.get("room",{}).is_empty(),"Keeping the rehearsal clears the unsent turn and the refused room")
	_check(app.saves.data.get("held_turns",[]).any(func(turn: Dictionary) -> bool: return turn.get("room_id")==LEGACY_PARTNER),"The rehearsal is kept on this phone")
	_check(app._relay_available(),"Online play is open again")
	_check(app.mode=="rooms" and app.room_hub_flow.is_open(),"Keeping the rehearsal returns to the room hub")

## Back on the held turn keeps the rehearsal too, so no refused turn is left
## unsent to hold online play for good.
func _partner_blocked_back(app: Node, api: FakeApi) -> void:
	if not await _held_by_partner_block(app,api,LEGACY_BACK): return
	app.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await _frames(4)
	_check(app.mode=="rooms" and app.room_hub_flow.is_open(),"Back from the held turn opens the room hub: "+app.mode)
	_check(app.saves.data.get("pending_turn",{}).is_empty() and app.saves.data.get("held_turns",[]).any(func(turn: Dictionary) -> bool: return turn.get("room_id")==LEGACY_BACK),"Back keeps the rehearsal and clears the unsent turn")
	_check(app._relay_available(),"Online play is open again after Back")

## Opens the room from the hub and plays this player's turn up to its review:
## the turn was played to its end and left there, so Play your turn offers
## Resume. Returns the review's Save turn, or null.
func _review_turn(app: Node, api: FakeApi, room_id: String) -> Button:
	inbox_offline=false
	if app.room_hub_flow.is_open(): await app.room_hub_flow.refresh()
	await _frames(2)
	if not await _open_from_hub(app,api,room_id): return null
	_check(app.saves.update_values({"room_draft":{"room_id":room_id,"revision":1,"attempt":{"a":{},"b":{},"draft":played.duplicate(true)}}}),"Save the played turn's draft: "+room_id)
	var play: Button=_button_named(app,"Play your turn")
	_check(play!=null,"The room offers Play your turn: "+room_id)
	if play==null: return null
	play.pressed.emit()
	await _frames(2)
	var resume: Button=_button_named(app,"Resume")
	_check(app.mode=="ready" and resume!=null,"The ready card offers Resume for the played turn: "+app.mode)
	if resume==null: return null
	resume.pressed.emit()
	await _frames(2)
	var save: Button=_button_named(app,"Save turn")
	_check(app.mode=="review" and save!=null,"The played turn reaches its review with Save turn: "+app.mode)
	return save

func _turns_sent(api: FakeApi, room_id: String) -> Array:
	return api.calls.filter(func(call: Dictionary) -> bool: return call.method==HTTPClient.METHOD_POST and call.path=="/v1/rooms/"+room_id+"/turns")

## The other player blocked during this player's turn: Save turn gets 403
## player_blocked, and the held screen opens straight away.
func _refused_on_submit(app: Node, api: FakeApi) -> void:
	var save := await _review_turn(app,api,LEGACY_SUBMIT)
	if save==null: return
	var held_before: int=app.saves.data.get("held_turns",[]).size()
	turn_replies[LEGACY_SUBMIT]=["blocked"]
	save.pressed.emit()
	await _frames(4)
	_check(_turns_sent(api,LEGACY_SUBMIT).size()==1,"Save turn submits the turn once")
	var pending: Dictionary=app.saves.data.get("pending_turn",{})
	_check(app.mode=="held" and _button_named(app,"Keep rehearsal & return")!=null,"A turn refused on submit opens the held screen: "+app.mode)
	_check(pending.get("rejected",false) and pending.get("error")==Copy.MAIN_52480E5314F5,"The refused turn is saved as refused, with the held screen's reason: %s" % [pending])
	_check(app.saves.data.get("room",{}).is_empty() and app.saves.data.get("room_draft",{}).is_empty() and app.active_room.is_empty(),"The blocked room and the draft played there are cleared")
	var keep: Button=_button_named(app,"Keep rehearsal & return")
	if keep==null: return
	keep.pressed.emit()
	await _frames(4)
	var held: Array=app.saves.data.get("held_turns",[])
	_check(held.size()==held_before+1 and held[-1].get("room_id")==LEGACY_SUBMIT and Canonical.same(held[-1].get("recording"),played),"Keep keeps the played turn's rehearsal on this phone")
	_check(app.saves.data.get("pending_turn",{}).is_empty() and app._relay_available(),"Keep clears the unsent turn and online play opens")
	_check(app.mode=="rooms" and app.room_hub_flow.is_open(),"Keep returns to the room hub: "+app.mode)
	_check(not app._invite_link_occupied(),"Nothing saved for the blocked room holds invite links")

## The player goes Home while the turn is still being sent, and the partner's
## block refuses it meanwhile. Home stays put; Friends and Play with your friend
## then open the held turn, and Back keeps it.
func _refused_after_leaving(app: Node, api: FakeApi) -> void:
	var save := await _review_turn(app,api,LEGACY_AWAY)
	if save==null: return
	var held_before: int=app.saves.data.get("held_turns",[]).size()
	turn_replies[LEGACY_AWAY]=["blocked"]
	api.hold_next=true
	save.pressed.emit()
	await _frames(2)
	_check(app.submission_in_flight,"The turn is being sent")
	_escape(app)
	await _frames(2)
	_check(app.mode=="home","Escape goes Home while the turn is being sent: "+app.mode)
	var waiting: Button=_button_named(app,"Play with your friend")
	if waiting!=null: waiting.pressed.emit()
	await _frames(2)
	_check(app.mode=="home" and app.toast_label.visible and app.toast_label.text==Copy.MAIN_8184DEB41266,"While the turn is being sent, Play with your friend says to wait: "+app.toast_label.text)
	api.release.emit()
	await _frames(4)
	var pending: Dictionary=app.saves.data.get("pending_turn",{})
	_check(app.mode=="home" and pending.get("rejected",false) and not app.submission_in_flight,"The refusal lands while the player is Home and leaves them there: "+app.mode)
	var friends: Button=_button_named(app,"Friends")
	_check(friends!=null,"Home offers Friends")
	if friends==null: return
	friends.pressed.emit()
	await _frames(4)
	_check(app.mode=="held" and _button_named(app,"Keep rehearsal & return")!=null and not app.friends_flow.is_open(),"Friends from Home opens the held turn: "+app.mode)
	# Escape on the held screen goes Home and leaves the turn as it was.
	_escape(app)
	await _frames(2)
	var rooms: Button=_button_named(app,"Play with your friend")
	_check(app.mode=="home" and rooms!=null and app.saves.data.get("pending_turn",{}).get("rejected",false),"Back Home the refused turn is still unsent")
	if rooms==null: return
	rooms.pressed.emit()
	await _frames(4)
	_check(app.mode=="held" and _button_named(app,"Keep rehearsal & return")!=null and not app.room_hub_flow.is_open(),"Play with your friend opens the held turn: "+app.mode)
	app.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await _frames(4)
	var held: Array=app.saves.data.get("held_turns",[])
	_check(held.size()==held_before+1 and held[-1].get("room_id")==LEGACY_AWAY,"Back keeps the rehearsal on this phone")
	_check(app.saves.data.get("pending_turn",{}).is_empty() and app._relay_available(),"Back clears the unsent turn and online play opens")
	_check(app.mode=="rooms" and app.room_hub_flow.is_open(),"Back returns to the room hub: "+app.mode)
	_check(app.saves.data.get("room",{}).is_empty() and app.saves.data.get("room_draft",{}).is_empty(),"Nothing saved names the blocked room")

## A timeout, then a server error: the turn stays unsent and not refused.
## Leaving the review opens its room, where Check saved submission sends the
## same turn again.
func _unanswered_submit(app: Node, api: FakeApi) -> void:
	var save := await _review_turn(app,api,LEGACY_RETRY)
	if save==null: return
	var held_before: Array=app.saves.data.get("held_turns",[]).duplicate(true)
	turn_replies[LEGACY_RETRY]=["timeout","unavailable"]
	save.pressed.emit()
	await _frames(4)
	var pending: Dictionary=app.saves.data.get("pending_turn",{})
	_check(app.mode=="review" and not pending.is_empty() and not pending.get("rejected",false),"A timeout leaves the turn unsent and not refused: %s %s" % [app.mode,pending])
	save=_button_named(app,"Save turn")
	if save!=null: save.pressed.emit()
	await _frames(6)
	pending=app.saves.data.get("pending_turn",{})
	_check(_turns_sent(api,LEGACY_RETRY).size()==2 and not pending.is_empty() and not pending.get("rejected",false),"A server error on the resend leaves it unsent and not refused: %s" % [pending])
	_check(app.saves.data.get("held_turns",[])==held_before and app.mode!="held","Neither answer holds the turn")
	var back: Button=_button_named(app,"Back")
	_check(back!=null,"The review offers Back")
	if back==null: return
	back.pressed.emit()
	await _frames(4)
	var check: Button=_button_named(app,"Check saved submission")
	_check(app.mode=="room" and app.active_room.get("room_id")==LEGACY_RETRY and check!=null,"Leaving the review with an unsent turn opens its room with Check saved submission: "+app.mode)
	if check==null: return
	check.pressed.emit()
	await _frames(6)
	var sent: Array=_turns_sent(api,LEGACY_RETRY)
	_check(sent.size()==3 and sent[0].body==sent[2].body,"Check saved submission sends the same turn with the same key")
	_check(app.saves.data.get("pending_turn",{}).is_empty() and app._relay_available() and app.active_room.get("active_role")=="b","The accepted turn clears the unsent turn and online play opens")

## Home, then Play with your friend, from wherever the last pass ended.
func _to_hub(app: Node) -> void:
	if app.room_hub_flow.is_open(): return
	var home: Button=_button_named(app,"Home")
	if home!=null: home.pressed.emit()
	await _frames(2)
	var rooms: Button=_button_named(app,"Play with your friend")
	if rooms!=null: rooms.pressed.emit()
	await _frames(4)
	_check(app.mode=="rooms" and app.room_hub_flow.is_open(),"Home's Play with your friend opens the hub: "+app.mode)

## Check saved submission, then the player goes Home and on to Play Solo while
## the check is out; the room then answers that the block ended it. The turn
## is saved as refused without pulling them back, and their next online tap
## opens it.
func _refused_while_checking(app: Node, api: FakeApi) -> void:
	await _to_hub(app)
	inbox_offline=false
	if app.room_hub_flow.is_open(): await app.room_hub_flow.refresh()
	await _frames(2)
	if not await _open_from_hub(app,api,LEGACY_CHECK): return
	var pending := {"room_id":LEGACY_CHECK,"owner_player_id":HOST,"base_revision":1,"idempotency_key":"synthetic-key-check","recording":{}}
	_check(app.saves.update_values({"pending_turn":pending}),"Save an unsent turn for the room")
	var refresh: Button=_button_named(app,"Refresh")
	if refresh!=null: refresh.pressed.emit()
	await _frames(4)
	var check: Button=_button_named(app,"Check saved submission")
	_check(app.mode=="room" and check!=null,"The room offers Check saved submission")
	if check==null: return
	blocked[LEGACY_CHECK]=true
	api.hold_next=true
	check.pressed.emit()
	await _frames(2)
	var home: Button=_button_named(app,"Home")
	if home!=null: home.pressed.emit()
	await _frames(2)
	var solo: Button=_button_named(app,"Play Solo")
	if solo!=null: solo.pressed.emit()
	await _frames(2)
	_check(app.mode=="journey" and app.submission_in_flight,"The player is in Play Solo while the check is out: "+app.mode)
	api.release.emit()
	await _frames(4)
	var saved: Dictionary=app.saves.data.get("pending_turn",{})
	_check(app.mode=="journey","The refusal leaves the player in Play Solo: "+app.mode)
	_check(saved.get("idempotency_key")=="synthetic-key-check" and saved.get("rejected",false) and saved.get("error")==Copy.MAIN_52480E5314F5,"The turn is saved as refused: %s" % [saved])
	_check(app.saves.data.get("room",{}).is_empty(),"The refused room is no longer the saved room")
	app.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await _frames(2)
	var rooms: Button=_button_named(app,"Play with your friend")
	_check(app.mode=="home" and rooms!=null,"Back from Play Solo goes Home: "+app.mode)
	if rooms==null: return
	rooms.pressed.emit()
	await _frames(4)
	var keep: Button=_button_named(app,"Keep rehearsal & return")
	_check(app.mode=="held" and keep!=null,"The next online tap opens the held turn: "+app.mode)
	if keep==null: return
	keep.pressed.emit()
	await _frames(4)
	_check(app.saves.data.get("pending_turn",{}).is_empty() and app.saves.data.get("held_turns",[]).any(func(turn: Dictionary) -> bool: return turn.get("room_id")==LEGACY_CHECK) and app._relay_available(),"Keep keeps the rehearsal and online play opens")

## The phone switched to another identity while a turn was unsent. That turn
## is never opened, held or sent for the new identity: an online tap shows why
## and the screen stays.
func _previous_identity_turn(app: Node, api: FakeApi) -> void:
	await _to_hub(app)
	inbox_offline=false
	if app.room_hub_flow.is_open(): await app.room_hub_flow.refresh()
	await _frames(2)
	if not await _open_from_hub(app,api,LEGACY_EARLIER): return
	var pending := {"room_id":LEGACY_EARLIER,"owner_player_id":HOST,"base_revision":1,"idempotency_key":"synthetic-key-earlier","recording":{}}
	_check(app.saves.update_values({"pending_turn":pending}),"Save an unsent turn for the room")
	var home: Button=_button_named(app,"Home")
	if home!=null: home.pressed.emit()
	await _frames(2)
	api.player_id=NEXT_IDENTITY
	app.identity_data={"player_id":NEXT_IDENTITY,"device_token":"synthetic-device-token"}
	var held_before: Array=app.saves.data.get("held_turns",[]).duplicate(true)
	var saved_room: Dictionary=app.saves.data.get("room",{}).duplicate(true)
	var before: int=api.calls.size()
	for label: String in ["Play with your friend","Friends"]:
		app.toast_label.visible=false
		var tap: Button=_button_named(app,label)
		_check(app.mode=="home" and tap!=null,"Home offers "+label)
		if tap==null: continue
		tap.pressed.emit()
		await _frames(4)
		_check(app.mode=="home" and not app.room_hub_flow.is_open() and not app.friends_flow.is_open(),label+" with another identity's turn keeps Home: "+app.mode)
		_check(app.toast_label.visible and app.toast_label.text==Copy.MAIN_ECBD713D8F0C,label+" says the turn is from the previous identity: "+app.toast_label.text)
	_check(app.saves.data.get("pending_turn",{})==pending and app.saves.data.get("held_turns",[])==held_before and app.saves.data.get("room",{})==saved_room,"The previous identity's turn, held turns and saved room are untouched")
	_check(api.calls.size()==before,"Nothing is sent for the previous identity's turn")
	api.player_id=HOST
	app.identity_data={"player_id":HOST,"device_token":"synthetic-device-token"}
	_check(app.saves.update_values({},["pending_turn"]),"Clear the previous identity's turn")

## Escape, as a keyboard player leaves a screen.
func _escape(app: Node) -> void:
	var key := InputEventKey.new()
	key.physical_keycode=KEY_ESCAPE
	key.pressed=true
	app._unhandled_key_input(key)

## Every toast shown over the next frames.
func _notices(app: Node, count: int) -> Array[String]:
	var seen: Array[String] = []
	for _frame in range(count):
		await process_frame
		if app.toast_label.visible and not app.toast_label.text in seen: seen.append(app.toast_label.text)
	return seen

func _finish(viewport: SubViewport) -> void:
	viewport.queue_free()
	await process_frame
	await create_timer(0.2).timeout
	for path: String in cleanup_paths:
		for suffix: String in ["",".tmp",".backup"]:
			if FileAccess.file_exists(path+suffix): DirAccess.remove_absolute(path+suffix)
	var file := safety_dir.path_join(HOST.sha256_text()+".json")
	for suffix: String in ["",".tmp",".backup"]:
		if FileAccess.file_exists(file+suffix): DirAccess.remove_absolute(file+suffix)
	if DirAccess.dir_exists_absolute(safety_dir): DirAccess.remove_absolute(safety_dir)
	print("ROOM HUB BLOCK: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)

func _peer(room_id: String) -> String:
	return GUEST if room_id==LEGACY else PEER

const LEGACY_ROOMS := [LEGACY,LEGACY_OTHER,LEGACY_PENDING,LEGACY_DRAFT,LEGACY_PARTNER,LEGACY_BACK,LEGACY_SUBMIT,LEGACY_AWAY,LEGACY_RETRY,LEGACY_CHECK,LEGACY_EARLIER]

func _legacy_room(room_id: String) -> Dictionary:
	return {"room_id":room_id,"revision":1,"host_id":HOST,"guest_id":_peer(room_id),"level_index":0,"level_id":"first-light","active_role":"a","first_player_id":HOST,"recordings":{},"attempt":0}

func _inbox_room(room_id: String, family: String, chapter: Dictionary, guest: String) -> Dictionary:
	return {"room_id":room_id,"family":family,"api_version":1 if family=="legacy" else 2,"chapter":chapter,"membership":{"host_id":HOST,"guest_id":guest,"you_are_host":true},"status":"waiting_for_their_turn","revision":1,"remote_activity_sequence":1,"activity_at":"2026-10-09T13:00:00.000Z"}

func _server(request: Dictionary, api: FakeApi) -> Dictionary:
	if request.path=="/v1/room-inbox":
		if inbox_offline: return {"ok":false,"status":0,"code":"connection_interrupted","error":"Synthetic offline response."}
		var rooms: Array=[_inbox_room(ROOM,"relay",{"id":"relay-isles","version":2},GUEST)]
		# The server leaves out a room whose members have blocked each other.
		for room_id: String in LEGACY_ROOMS:
			if not blocked.has(room_id): rooms.append(_inbox_room(room_id,"legacy",{"id":"first-light","version":1},_peer(room_id)))
		return _ok({"schema_version":1,"rooms":rooms})
	for room_id: String in LEGACY_ROOMS:
		if request.path=="/v1/rooms/"+room_id+"/turns" and request.method==HTTPClient.METHOD_POST:
			return _turn_reply(room_id,request)
		if request.path=="/v1/rooms/"+room_id and request.method==HTTPClient.METHOD_GET:
			if blocked.has(room_id): return {"ok":false,"status":403,"code":"player_blocked","error":BLOCKED_ERROR}
			return _ok(_legacy_room(room_id))
	if request.path=="/v1/safety/block" and request.method==HTTPClient.METHOD_POST:
		_check(request.body=={"schema_version":1,"room_family":"legacy","room_id":block_target},"The block names the earlier-island room: "+block_target)
		blocked[block_target]=true
		# The hub that opens next can only show what this phone saved.
		inbox_offline=true
		return _ok({"schema_version":1,"blocked":true,"player_id":_peer(block_target)})
	return super._server(request,api)

func _turn_reply(room_id: String, request: Dictionary) -> Dictionary:
	var queue: Array=turn_replies.get(room_id,[])
	var reply: String=str(queue.pop_front()) if not queue.is_empty() else ""
	match reply:
		"blocked":
			blocked[room_id]=true
			return {"ok":false,"status":403,"code":"player_blocked","error":BLOCKED_ERROR}
		"timeout": return {"ok":false,"status":0,"code":"connection_interrupted","error":"Synthetic interrupted response."}
		"unavailable": return {"ok":false,"status":503,"code":"service_unavailable","error":"Synthetic unavailable response."}
	var room := _legacy_room(room_id)
	room.revision=2
	room.active_role="b"
	room.recordings={"a":request.body.recording}
	return _ok(room)

func _frames(count: int) -> void:
	for _frame in range(count): await process_frame
