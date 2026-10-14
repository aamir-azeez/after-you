extends "res://tests/test_online_scenarios.gd"
## The second half of the scripted Play with a friend scenarios.

func scenarios() -> Array[Callable]:
	return [_close_while_partner_mid_turn, _lost_replies, _double_taps, _force_quit_everywhere, _reinstall_with_old_rooms, _skip_and_early_replays]

func suite_name() -> String:
	return "Online scenarios (more)"
