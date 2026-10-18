extends RefCounted
## A friend's redo request is easy to miss as a button label, so it is also
## shown once per request in the shared pop-up. Not now leaves the request
## waiting. The online room screen and the earlier islands' room page each keep
## one notice, which remembers the requests it has shown.
const InGameModal = preload("res://presentation/in_game_modal.gd")
const RoomActions = preload("res://presentation/room_actions.gd")
const BODY := "Your friend requested to redo your turn. Check the request to accept or reject it."

## The open pop-up, or null.
var modal: Control
var _shown: Dictionary = {}

## Shows `client`'s pending request over `parent` unless a pop-up is open, the
## request can't be answered, or it was shown before. Review request closes
## the pop-up and calls `review`.
func announce(parent: Control, client: RefCounted, room_id: String, review: Callable) -> void:
	if is_instance_valid(modal) or not client.can_accept(): return
	var request: Variant = client.view().get("request")
	if not request is Dictionary: return
	var key := room_id + ":" + str(request.get("request_id",JSON.stringify(request)))
	if _shown.has(key): return
	_shown[key] = true
	modal = InGameModal.open(parent,"RedoRequestModal",RoomActions.REDO_REQUESTED)
	modal.label(BODY)
	var open: Button = modal.add_actions("Review request",func():
		if is_instance_valid(modal): modal.close(false)
		modal = null
		review.call(),"Not now")
	open.grab_focus()
