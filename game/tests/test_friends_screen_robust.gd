extends "res://tests/test_friends_client.gd"
## Friends moments that lost a tap or repeated a request: a Join tapped while a
## hosting push's inbox read is out, Android Back with a pop-up open, and a
## friend's hosting event acknowledged again on every redraw.
const Screen = preload("res://presentation/friends_screen.gd")
const EventsClient = preload("res://services/friend_room_events_client.gd")
const HOSTING_EVENT := {"event_id":PEER+"_3","category":"room_available","player_id":PEER,"request_id":REQUEST,"publication_epoch":3,"room":{"api_version":2,"room_id":OWNER},"published_at":1780000000000}

## An events client whose inbox read waits until let_go.
class HeldInbox extends RefCounted:
	signal let_go
	var busy := false
	var reads := 0
	func inbox() -> Dictionary:
		reads += 1
		busy = true
		await let_go
		busy = false
		return {"ok":true,"data":{"events":[],"preferences":[]}}
	func set_hosting_alert(_peer: Dictionary, _enabled: bool) -> bool: return true

var event_calls: Array = []
func events_request(_method: int, path: String, body: Dictionary) -> Dictionary:
	event_calls.append({"path":path,"action":str(body.get("action",""))})
	if path == "/v1/social/inbox": return {"ok":true,"data":JSON.parse_string(JSON.stringify({"schema_version":1,"available":true,"events":[HOSTING_EVENT],"preferences":[]}))}
	return {"ok":true,"data":{"schema_version":1,"acknowledged":true,"request_id":str(body.get("request_id",""))}}

func _run() -> void:
	api = Transport.new()
	root.add_child(api)
	client = Client.new(api,identity,request)
	client.clock_ms = func(): return now
	response = {"ok":true,"data":page()}
	await client.refresh()
	await _join_during_hosting_read()
	await _back_closes_pop_up_first()
	await _hosting_event_acknowledged_once()
	print("Friends screen robust: %d failures" % failures)
	quit(1 if failures else 0)

func _open(events: Variant) -> CanvasLayer:
	var screen: CanvasLayer = Screen.new()
	screen.client = client
	if events != null: screen.event_client = events
	root.add_child(screen)
	for i in 4: await process_frame
	return screen

func _join_during_hosting_read() -> void:
	var events := HeldInbox.new()
	var screen := await _open(events)
	var joins := [0]
	screen.join_requested.connect(func(_value: Dictionary): joins[0] += 1)
	screen.hosting_hint()
	await process_frame
	check(events.reads == 1,"A hosting push reads the inbox")
	var code := "0123456789ABCDEF0123"
	response = {"ok":true,"data":{"schema_version":1,"api_version":2,"room_id":("v2:"+code).sha256_text().substr(0,22),"invite_code":code}}
	var before := calls.size()
	screen._act("join",client.view().friends[0])
	for i in 2: await process_frame
	events.let_go.emit()
	for i in 6: await process_frame
	var joined := calls.slice(before).any(func(call: Dictionary) -> bool: return str(call.path).ends_with("/join"))
	check(joined and joins[0] == 1,"A Join tapped while the hosting push's read is out joins once that read lands")
	if is_instance_valid(screen): screen.close()
	await process_frame
	now += Client.JOIN_COOLDOWN_MS
	response = {"ok":true,"data":page()}

func _back_closes_pop_up_first() -> void:
	var screen := await _open(null)
	var closes := [0]
	screen.closed.connect(func(): closes[0] += 1)
	screen._edit_nickname(client.view().friends[0])
	await process_frame
	check(is_instance_valid(screen._modal),"The nickname pop-up is open")
	screen.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	for i in 2: await process_frame
	check(closes[0] == 0 and is_instance_valid(screen) and screen.is_inside_tree(),"Android Back with a pop-up open leaves Friends open")
	if not is_instance_valid(screen): return
	check(not is_instance_valid(screen._modal) or screen._modal.is_queued_for_deletion(),"Android Back closes the pop-up")
	screen.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await process_frame
	check(closes[0] == 1,"Android Back with no pop-up closes Friends")
	await process_frame

func _hosting_event_acknowledged_once() -> void:
	now += 120000
	response = {"ok":true,"data":page()}
	var screen := await _open(EventsClient.new(api,identity,events_request))
	for i in 6: await process_frame
	var acks := func() -> int: return event_calls.filter(func(call: Dictionary) -> bool: return call.action == "ack").size()
	check(event_calls.any(func(call: Dictionary) -> bool: return call.path == "/v1/social/inbox") and acks.call() == 1,"The shown hosting event is acknowledged once (%d)" % acks.call())
	for i in 3:
		screen._render()
		for frame in 4: await process_frame
	check(acks.call() == 1,"Redrawing Friends sends no further acknowledgement (%d)" % acks.call())
	screen.close()
	await process_frame
