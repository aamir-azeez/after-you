extends SceneTree

const Schedule = preload("res://services/refresh_schedule.gd")
var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)


func _run() -> void:
	_test_room_and_lobby()
	_test_coalescing_and_guards()
	_test_context_change()
	_test_backoff_and_cooldown()
	_test_terminal_and_clock()
	print("REFRESH SCHEDULE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _test_room_and_lobby() -> void:
	var clock := Schedule.new()
	_check(clock.stopped() and clock.begin_if_due(0, true, false).is_empty(), "An unbound clock never starts polling")
	clock.bind("identity-1/epoch-1/room-a", 1000)
	_check(clock.next_due_ms() == 4000, "An active room checks within three seconds of binding")
	clock.bind("identity-1/epoch-1/room-a", 3000)
	_check(clock.next_due_ms() == 4000, "Repeated context observation does not postpone polling")
	_check(clock.begin_if_due(3999, true, false).is_empty(), "A room does not poll before its due time")
	var token: Dictionary = clock.begin_if_due(4000, true, false)
	_check(not token.is_empty() and clock.busy(), "A due eligible room reserves one request")
	_check(clock.complete(token, 4500, true), "The matching completion is accepted")
	_check(not clock.busy() and clock.next_due_ms() == 7500, "Successful polling schedules from completion, without catch-up bursts")
	clock.bind("identity-1/epoch-1/lobby", 20000, Schedule.LOBBY_INTERVAL_MS)
	_check(clock.next_due_ms() == 30000, "A lobby uses the ten-second cadence")
	clock.bind("", 21000)
	_check(clock.stopped() and not clock.request_now(21000), "Unbinding stops both timed and manual scheduling")


func _test_coalescing_and_guards() -> void:
	var clock := Schedule.new()
	clock.bind("room", 0)
	clock.request_now(5)
	clock.request_now(5)
	_check(clock.begin_if_due(5, false, false).is_empty(), "Background or unsafe recording/review modes defer a queued read")
	_check(clock.begin_if_due(500, true, true).is_empty(), "A different transport request keeps the queued refresh deferred")
	var token: Dictionary = clock.begin_if_due(501, true, false)
	_check(not token.is_empty(), "The single queued refresh starts when both guards clear")
	_check(not clock.request_now(502) and not clock.request_now(503), "Duplicate manual and resume signals share the active read")
	_check(clock.begin_if_due(99999, true, false).is_empty(), "A long request cannot overlap another timer tick")
	var changed := token.duplicate()
	changed.serial += 1
	_check(not clock.complete(changed, 100000, true) and clock.busy(), "An unrelated completion cannot release the request slot")
	_check(clock.complete(token, 100001, true), "The actual delayed completion releases its slot")
	_check(clock.begin_if_due(100001, true, false).is_empty(), "Coalesced clicks do not produce a second read after success")
	_check(not clock.complete(token, 100002, false), "Duplicate callbacks cannot change the successful schedule")
	_check(clock.next_due_ms() == 103001, "No burst is accumulated during a long request")


func _test_context_change() -> void:
	var clock := Schedule.new()
	clock.bind("identity-1/epoch-1/room-a", 0)
	clock.request_now(0)
	var old: Dictionary = clock.begin_if_due(0, true, false)
	clock.bind("identity-1/epoch-1/room-b", 10)
	clock.request_now(10)
	_check(clock.busy() and clock.begin_if_due(10, true, false).is_empty(), "Room changes do not pretend the old HTTP request has stopped")
	_check(not clock.complete(old, 20, true), "Old-room response cannot validate or reschedule the new room")
	var current: Dictionary = clock.begin_if_due(20, true, false)
	_check(not current.is_empty() and current != old, "A queued new-room read follows the old transport completion")
	clock.bind("identity-1/epoch-2/room-b", 21)
	_check(not clock.complete(current, 22, false), "Recovery epoch change invalidates even a same-room result")
	_check(clock.next_due_ms() == 3021, "An old identity failure does not apply its backoff to the new identity")
	clock.bind("identity-1/epoch-1/room-a", 23)
	_check(not clock.complete(old, 24, true), "Returning to an old context key cannot resurrect an old request token")
	clock.request_now(25)
	var next: Dictionary = clock.begin_if_due(25, true, false)
	clock.bind("", 26)
	_check(not clock.complete(next, 27, true) and clock.stopped(), "Leaving online screens drains an outstanding request without restarting polling")


func _test_backoff_and_cooldown() -> void:
	var clock := Schedule.new()
	clock.bind("room", 0)
	clock.request_now(0)
	var token: Dictionary = clock.begin_if_due(0, true, false)
	clock.complete(token, 100, false)
	_check(clock.next_due_ms() == 5100, "A transient failed read can recover after five seconds")
	token = clock.begin_if_due(30100, true, false)
	clock.complete(token, 30200, false)
	_check(clock.next_due_ms() == 45200, "Second failed read backs off fifteen seconds")
	token = clock.begin_if_due(90200, true, false)
	clock.complete(token, 90300, false)
	_check(clock.next_due_ms() == 120300, "Third failed read backs off thirty seconds")
	token = clock.begin_if_due(210300, true, false)
	clock.complete(token, 210400, false)
	_check(clock.next_due_ms() == 240400, "Repeated failures stay at the bounded delay")
	clock.request_now(210401)
	token = clock.begin_if_due(210401, true, false)
	_check(not token.is_empty(), "An explicit manual request may retry ordinary connectivity backoff")
	clock.complete(token, 210500, true)
	_check(clock.next_due_ms() == 213500, "Successful recovery restores the ordinary cadence")
	token = clock.begin_if_due(225500, true, false)
	clock.complete(token, 225600, false)
	_check(clock.next_due_ms() == 230600, "A new failure after success restarts at the first backoff")
	clock.request_now(225601)
	token = clock.begin_if_due(225601, true, false)
	clock.complete(token, 225602, false, 179998)
	_check(clock.next_due_ms() == 405600, "Provider Retry-After can require a longer wait than the local backoff")
	clock.request_now(225603)
	_check(clock.begin_if_due(405599, true, false).is_empty(), "Manual refresh cannot bypass the provider's cooldown")
	token = clock.begin_if_due(405600, true, false)
	_check(not token.is_empty(), "The coalesced manual refresh starts at cooldown expiry")
	clock.bind("another-room", 405601)
	clock.request_now(405601)
	_check(not clock.complete(token, 405602, false, 45000), "Stale room result is rejected while its provider cooldown remains meaningful")
	_check(clock.next_due_ms() == 450602 and clock.begin_if_due(405603, true, false).is_empty(), "Switching rooms does not evade a provider cooldown")


func _test_terminal_and_clock() -> void:
	var clock := Schedule.new()
	clock.bind("identity/epoch-1/room", 100)
	clock.request_now(100)
	var token: Dictionary = clock.begin_if_due(100, true, false)
	clock.complete(token, 200, false, 0, true)
	_check(clock.stopped() and not clock.request_now(100000), "A terminal authentication/deletion result cannot become a retry storm")
	clock.bind("identity/epoch-2/room", 100001)
	_check(not clock.stopped(), "An explicitly changed identity context can resume polling")
	clock.request_now(100002)
	token = clock.begin_if_due(100002, true, false)
	clock.complete(token, 100003, true)
	clock.request_now(1)
	_check(clock.next_due_ms() == 100003, "A backwards clock sample cannot schedule a request before the last observed time")
	_check(clock.begin_if_due(2, false, false).is_empty(), "A backwards sample does not bypass the safe-mode guard")
