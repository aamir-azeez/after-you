extends "res://tests/test_room_inbox_client.gd"
## Hide on a finished room's menu acts on the room as the list now has it. The
## menu keeps the room as its card drew it; a list read while the menu was open
## can bring newer activity, and hiding with the card's older count let that
## activity show the room again at once.

func _run() -> void:
	var api := FakeApi.new()
	api.base_url += str(Time.get_ticks_usec())
	root.add_child(api)
	client = Client.new(api,identity,transport)
	var finished := server_room("cccccccccccccccccccccc",2,"completed")
	response = {"ok":true,"data":{"schema_version":1,"rooms":[finished]}}
	check(await client.refresh(),"The finished room is listed")
	var drawn: Dictionary = client.view().rooms[0].duplicate(true)
	# The menu is open; the friend replays and the list is read again.
	finished.remote_activity_sequence = 4
	response = {"ok":true,"data":{"schema_version":1,"rooms":[finished]}}
	check(await client.refresh(),"The list is read again while the menu is open")
	client.hide(drawn)
	var listed: bool = client.view().rooms.any(func(row: Dictionary) -> bool: return row.room_id == finished.room_id)
	check(not listed,"Hide takes the room off the list even though the list moved on since its card was drawn")
	check(client.hidden_rooms().size() == 1,"The room is under Hidden rooms")
	# New activity after the hide still brings it back.
	finished.remote_activity_sequence = 5
	response = {"ok":true,"data":{"schema_version":1,"rooms":[finished]}}
	check(await client.refresh(),"The list is read again later")
	check(client.view().rooms.any(func(row: Dictionary) -> bool: return row.room_id == finished.room_id),"Activity after the hide shows the room again")
	print("Room hide current: %d failures" % failures)
	quit(1 if failures else 0)
