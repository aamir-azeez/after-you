extends SceneTree

const Schedule = preload("res://services/refresh_schedule.gd")
const Backoff = preload("res://services/poll_backoff.gd")
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
	_test_idle_backoff()
	_test_idle_backoff_resets()
	_test_live_hint_and_pace()
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


## Completes one due read at `now` and returns the wait it set.
func _poll(clock: RefCounted, now: int, changed: bool, success: bool = true) -> int:
	var token: Dictionary = clock.begin_if_due(now, true, false)
	_check(not token.is_empty(), "A read is due at %d" % now)
	clock.complete(token, now, success, 0, false, changed)
	return clock.next_due_ms() - now


## Idle reads from `now` until the schedule waits `wait` ms; returns the time of
## the read that set it.
func _idle_until(clock: RefCounted, now: int, wait: int) -> int:
	for read in 40:
		var got := _poll(clock, now, false)
		if got == wait: return now
		now += got
	_check(false, "The schedule reached a %d ms wait" % wait)
	return now


func _test_idle_backoff() -> void:
	var helper := Backoff.new()
	var waits: Array = []
	for read in 24: waits.append(helper.next_ms(false))
	var steady: Array = []
	steady.resize(20)
	steady.fill(3000)
	_check(waits == steady + [4500, 6750, 10125, 15000], "The helper waits 3 s for the first minute, then half as long again each idle read, capped at 15 s: %s" % [waits])
	_check(helper.next_ms(false) == 15000, "The wait stays at the 15 s cap")
	_check(helper.next_ms(true) == 3000, "A change brings the helper back to 3 s at once")
	waits.clear()
	for read in 21: waits.append(helper.next_ms(false))
	_check(waits.slice(0, 19).all(func(wait: int) -> bool: return wait == 3000) and waits[19] == 4500, "A change starts another steady minute: %s" % [waits])
	helper.reset()
	_check(helper.next_ms(false) == 3000, "After a reset the next idle read waits only 3 s")
	var quick := Backoff.new(3000, 15000, 3000)
	waits.clear()
	for read in 6: waits.append(quick.next_ms(false))
	_check(waits == [3000, 4500, 6750, 10125, 15000, 15000], "Without a steady minute the growth starts at once: %s" % [waits])
	_check(helper.observe({"revision": 1}) and not helper.observe({"revision": 1}) and helper.observe({"revision": 2}), "observe() reports only a reply that differs from the last one")
	var clock := Schedule.new()
	clock.bind("room", 0)
	var now := 3000
	var seen: Array = []
	for read in 24:
		var wait := _poll(clock, now, false)
		seen.append(wait)
		_check(clock.begin_if_due(now + wait - 1, true, false).is_empty(), "An idle room never reads before its wait (read %d)" % read)
		now += wait
	_check(seen == steady + [4500, 6750, 10125, 15000], "Idle reads keep 3 s for a minute, then wait longer each time, up to 15 s: %s" % [seen])
	_check(clock.idle_extra_ms() == 12000, "The schedule says how much the backoff added to the base")
	_check(_poll(clock, now, true) == 3000 and clock.idle_extra_ms() == 0, "A change found by a read brings the next one back to 3 s, so no poll is skipped")
	now += 3000
	_check(_poll(clock, now, false) == 3000, "A change starts another steady minute")
	now += 3000
	var legacy := Schedule.new()
	legacy.bind("room", 0)
	var token: Dictionary = legacy.begin_if_due(3000, true, false)
	legacy.complete(token, 3000, true)
	token = legacy.begin_if_due(6000, true, false)
	legacy.complete(token, 6000, true)
	_check(legacy.next_due_ms() == 9000, "A caller with no change signal keeps the 3 s cadence")
	# Failures keep their own delays and neither grow nor reset the idle step.
	now = _idle_until(clock, now, 15000) + 15000
	_check(_poll(clock, now, false, false) == 5000 and clock.idle_extra_ms() == 0, "A failed read waits the ordinary five-second failure delay")
	now += 5000
	_check(_poll(clock, now, false) == 15000, "A failure between idle reads leaves the idle step where it was")


func _test_idle_backoff_resets() -> void:
	var clock := Schedule.new()
	clock.bind("room-a", 0)
	var now := _idle_until(clock, 3000, 15000) + 15000
	# A tap or a resume (both request_now) reads at once and resets the wait.
	var tapped := now - 14000
	_check(clock.request_now(tapped) and not clock.begin_if_due(tapped, true, false).is_empty(), "A tap reads at once, however far the backoff had grown")
	var token: Dictionary = clock._active.duplicate()
	clock.complete(token, tapped, true, 0, false, false)
	_check(clock.next_due_ms() == tapped + 3000, "The read a tap asked for is followed 3 s later even when nothing changed")
	now = _idle_until(clock, tapped + 3000, 15000) + 15000
	_check(now - tapped >= 60000 + 3000, "A tap starts another steady minute")
	# A tap during a read already out is served by that read, and still resets.
	token = clock.begin_if_due(now, true, false)
	_check(not clock.request_now(now + 1), "A tap during a read shares that read")
	clock.complete(token, now + 2, true, 0, false, false)
	_check(clock.next_due_ms() == now + 2 + 3000, "A tap that shared a read still brings the next one to 3 s")
	now = _idle_until(clock, now + 3002, 15000) + 15000
	# The player's own action: no read now, the next within 3 s, a steady minute again.
	var acted := now - 15000 + 1000
	clock.note_activity(acted)
	_check(clock.next_due_ms() == acted + 3000 and not clock.busy(), "An own action brings the next read within 3 s without sending one")
	_check(_poll(clock, acted + 3000, false) == 3000, "The read after an own action is followed 3 s later")
	clock.note_activity(acted + 3001)
	_check(clock.next_due_ms() == acted + 6000, "An own action never pushes a nearer read later")
	# Entering another room starts at the base; observing the same room again does not reset.
	now = _idle_until(clock, acted + 6000, 15000) + 15000
	clock.bind("room-a", now - 1)
	_check(clock.idle_extra_ms() == 12000, "Re-binding the same room each frame keeps its backoff")
	clock.bind("room-b", now)
	_check(clock.next_due_ms() == now + 3000 and _poll(clock, now + 3000, false) == 3000, "Entering a room starts at 3 s")
	_check(clock.changed({"revision": 1}) and not clock.changed({"revision": 1}), "The schedule's change check sees only new replies")
	clock.bind("room-c", now + 3001)
	_check(clock.changed({"revision": 1}), "A new room forgets the last reply it saw")
	# A provider Retry-After still applies to every read, taps included.
	var busy := Schedule.new()
	busy.bind("room", 0)
	token = busy.begin_if_due(3000, true, false)
	busy.complete(token, 3000, false, 60000)
	busy.request_now(3001)
	_check(busy.begin_if_due(62999, true, false).is_empty() and not busy.begin_if_due(63000, true, false).is_empty(), "A tap resets the backoff but never the provider cooldown")
## A live hint makes a read due now, or one more after the read already out
## (it may have been answered before the change). A changed pace (the socket
## came or went) re-times the next read without resetting failure or terminal state.
func _test_live_hint_and_pace() -> void:
	var clock := Schedule.new()
	_check(not clock.hint(0), "A hint with no room bound asks for nothing")
	clock.bind("room", 0, 60000)
	_check(clock.next_due_ms() == 60000, "A healthy socket paces the room at its safety interval")
	_check(clock.hint(10) and clock.next_due_ms() == 10, "A hint makes the read due now")
	var token: Dictionary = clock.begin_if_due(10, true, false)
	_check(clock.hint(20), "A hint during a read is kept")
	clock.complete(token, 30, true)
	_check(clock.next_due_ms() == 30, "The read after a mid-read hint runs at once")
	token = clock.begin_if_due(30, true, false)
	clock.complete(token, 40, true)
	_check(clock.next_due_ms() == 60040, "Only one extra read follows a hint")
	clock.bind("room", 50)
	_check(clock.next_due_ms() == 50 + Schedule.ROOM_INTERVAL_MS, "Losing the socket brings the next read within one normal interval")
	clock.bind("room", 60, 60000)
	_check(clock.next_due_ms() == 50 + Schedule.ROOM_INTERVAL_MS, "Regaining it never pushes a due read later")
	token = clock.begin_if_due(50 + Schedule.ROOM_INTERVAL_MS, true, false)
	clock.complete(token, 4000, false, 0, true)
	clock.bind("room", 4001)
	_check(clock.stopped() and not clock.hint(4002), "A pace change never restarts a room that answered 401/403/404/410")
	# The idle backoff runs only while the socket is down, and a hint starts it over.
	var idle := Schedule.new()
	idle.bind("room", 0, 60000)
	var now := 60000
	for read in 25: now += _poll(idle, now, false)
	_check(_poll(idle, now, false) == 60000, "A healthy socket keeps the safety pace, with no idle growth on top")
	now += 60000
	idle.bind("room", now, Schedule.ROOM_INTERVAL_MS)
	var quiet := _idle_until(idle, now + Schedule.ROOM_INTERVAL_MS, 15000)
	_check(quiet - now >= 60000, "With the socket down, idle reads keep 3 s for a minute and then back off to 15 s")
	_check(idle.hint(quiet + 1) and _poll(idle, quiet + 1, false) == Schedule.ROOM_INTERVAL_MS, "A hint reads at once and the next read is back at 3 s")

