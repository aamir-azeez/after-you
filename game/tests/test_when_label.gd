extends SceneTree
## Shared replay rooms show when they last changed, in the player's local time.
const WhenLabel = preload("res://presentation/when_label.gd")
var failures := 0

func _initialize() -> void:
	# Tuesday 2026-10-13 22:30 in New York (UTC-4).
	var now := int(Time.get_unix_time_from_datetime_string("2026-10-14T02:30:00"))
	var bias := -240
	var at := func(iso: String) -> int: return int(Time.get_unix_time_from_datetime_string(iso))
	_check(WhenLabel.compact(at.call("2026-10-14T01:42:00"), now, bias), "Today, 9:42 PM")
	_check(WhenLabel.compact(at.call("2026-10-13T03:05:00"), now, bias), "Yesterday, 11:05 PM")
	_check(WhenLabel.compact(at.call("2026-10-13T16:00:00"), now, bias), "Today, 12:00 PM")
	_check(WhenLabel.compact(at.call("2026-10-13T04:00:00"), now, bias), "Today, 12:00 AM")
	_check(WhenLabel.compact(at.call("2026-10-10T14:15:00"), now, bias), "Sat, 10:15 AM")
	_check(WhenLabel.compact(at.call("2026-10-03T14:15:00"), now, bias), "Oct 3, 10:15 AM")
	_check(WhenLabel.compact(at.call("2025-12-31T23:00:00"), now, bias), "Dec 31, 2025")
	_check(WhenLabel.compact(at.call("2026-10-14T01:42:00"), now, 330), "Today, 7:12 AM")
	_check(WhenLabel.compact(0, now, bias), "")
	_check(WhenLabel.text(0), "")
	if failures == 0: print("WHEN_LABEL_TESTS_PASSED")
	quit(1 if failures else 0)

func _check(actual: String, expected: String) -> void:
	if actual != expected:
		failures += 1
		push_error("expected %s, got %s" % [expected, actual])
