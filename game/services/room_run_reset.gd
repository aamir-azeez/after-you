extends RefCounted
## The one path for a room whose run started over (backend v2/room.ts wipeRun):
## the server removed every turn of the old run, and this phone drops its
## copies the same way. The room's redo client notices it from the server's
## run marker (services/redo_client.gd take_run_reset), whether or not this
## phone was open when the friend agreed; the session then drops its own
## stores (relay_online_session.gd forget_room_run) and announces it here, so
## every other store of that room's run (services/shared_replay_collection.gd)
## drops its copies too.

signal room_reset(owner: String, room_id: String)

static var _shared: RefCounted

static func shared() -> RefCounted:
	if _shared == null: _shared = load("res://services/room_run_reset.gd").new()
	return _shared

func announce(owner: String, room_id: String) -> void:
	room_reset.emit(owner, room_id)
