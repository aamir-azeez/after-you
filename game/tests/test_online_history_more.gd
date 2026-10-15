extends "res://tests/test_online_history.gd"
## The rest of the room history scenarios.

func scenarios() -> Array[Callable]:
	return [_new_phone_asks_friend, _older_build_keeps_rooms, _offload_off]

func suite_name() -> String:
	return "Online history (more)"
