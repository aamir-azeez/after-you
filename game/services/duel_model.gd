extends RefCounted
## What the duel pages say about a duel (services/duels_client.gd valid_view),
## worked out in one place so the lobby tiles, the duel page and the result
## page always agree. Pure: no nodes, no files, no requests. Names come from a
## callable the page passes (the friends list and this player's partner), so a
## player the server did not name shows as "Sam's partner", never as an id.
##
## A public duel (its view has `public`) names its seats from their own facts:
## an open seat is "Open", this player is "You", a friend or partner by name,
## and a stranger by the name they chose to show, else "A player". A pair of
## two unnamed strangers is "A pair", the leaderboard's own words
## (presentation/leaderboard_rows.gd pair_title). A stranger's id never reaches
## this phone, so nothing here can name one by id.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const LeaderboardRows = preload("res://presentation/leaderboard_rows.gd")
const Breakdown = preload("res://presentation/pollen_breakdown.gd")
const Runs = preload("res://services/leaderboard_runs.gd")
const TICK_RATE := Runs.TICK_RATE
const HOUR_MS := 3_600_000
const DAY_MS := 24 * HOUR_MS
const WEEK_MS := 7 * DAY_MS
## Whether a stranger's pip wears the look the server sent (the leaderboard rows do);
## false draws every stranger plain. The one place that decides it (stranger_look).
const STRANGER_LOOKS := true

## A time in ticks, as the Fastest pair board shows it (m:ss.t), so a ghost reads the same here and there.
static func time_text(ticks: int) -> String:
	return Runs.time_text(ticks)

## The gap between two times: whole seconds, or hundredths under a tenth of a second.
static func margin_text(ticks: int) -> String:
	if ticks <= 0: return ""
	if ticks * 10 < TICK_RATE: return PlayerCopy.DUEL_MARGIN_HUNDREDTHS % (float(ticks) / TICK_RATE)
	var seconds := maxi(1, roundi(float(ticks) / TICK_RATE))
	return PlayerCopy.DUEL_MARGIN_ONE if seconds == 1 else PlayerCopy.DUEL_MARGIN_SECONDS % seconds

## The pair's two names for the side at `index`: "You + Maya", "Finn + Noor",
## "Sam + Sam's partner", "Their pair" or "Recorded run". `name_of(id)` answers
## a name or "".
static func pair_title(view: Dictionary, index: int, name_of: Callable) -> String:
	if index == 1 and view.kind == "ghost": return PlayerCopy.DUEL_GHOST_PAIR
	if is_public(view): return _public_pair_title(view, index, name_of)
	var side: Dictionary = view.sides[index]
	var names: Array[String] = []
	for id: Variant in side.members:
		names.append(_name(id, side.you, name_of))
	if names[0].is_empty() and names[1].is_empty(): return PlayerCopy.DUEL_THEIR_PAIR
	for slot in range(2):
		if names[slot].is_empty(): names[slot] = PlayerCopy.DUEL_PARTNER_OF % names[1 - slot]
	# Your own side always reads "You + partner".
	if side.you and names[1] == PlayerCopy.DUEL_YOU: names.reverse()
	return PlayerCopy.DUEL_PAIR % [names[0], names[1]]

## A member's name from the page's callable, or "" (no id, or nobody this phone can name).
static func _name(id: Variant, _own_side: bool, name_of: Callable) -> String:
	if id == null or not name_of.is_valid(): return ""
	return str(name_of.call(id))

## Whose turn a side shows: "Your turn", "Maya's turn", "Waiting for Noor", "Finished", "Gave up", or "".
## A public duel's side with open seats says "Nobody yet" or "Waiting for a partner" instead.
static func turn_line(view: Dictionary, index: int, name_of: Callable) -> String:
	if index == 1 and view.kind == "ghost": return PlayerCopy.DUEL_RECORDED
	var side: Dictionary = view.sides[index]
	if side.left: return PlayerCopy.DUEL_GAVE_UP
	if side.finished: return PlayerCopy.DUEL_FINISHED
	if view.status != "running": return ""
	if is_public(view):
		var open := open_seats(view, index)
		if open == 2: return PlayerCopy.PUBLIC_NOBODY_YET
		if side.turn >= 0 and bool(seat(view, index, side.turn).get("open", false)): return PlayerCopy.PUBLIC_WAITING_PARTNER
		if side.turn < 0: return PlayerCopy.DUEL_YOUR_TURN if side.you else PlayerCopy.PUBLIC_WAITING_PARTNER if open == 1 else PlayerCopy.DUEL_NOT_STARTED
		if not side.you and seat_stranger(view, index, side.turn) and str(seat(view, index, side.turn).get("label", "")).is_empty(): return PlayerCopy.PUBLIC_WAITING_THEM
	if side.turn < 0: return PlayerCopy.DUEL_NOT_STARTED
	var id: Variant = side.members[side.turn]
	var shown := _name(id, side.you, name_of) if not is_public(view) else _seat_shown(view, index, side.turn, name_of)
	if shown.is_empty(): shown = _partner_word(view)
	if side.you: return PlayerCopy.DUEL_YOUR_TURN if shown == PlayerCopy.DUEL_YOU else PlayerCopy.DUEL_THEIR_TURN % shown
	return PlayerCopy.DUEL_WAITING_FOR % shown

## Whether it is this player's own move in the duel now.
static func your_turn(view: Dictionary, me: String) -> bool:
	var side: Dictionary = view.sides[view.mine]
	if view.status != "running" or side.finished or side.left: return false
	if side.turn >= 0: return side.members[side.turn] == me
	# No turn yet: the first room has not been made, and either of you may open it.
	return true

## Whether `view` is a public duel (backend duels public routes): its seats fill from the list.
static func is_public(view: Dictionary) -> bool:
	return view.has("public")

## A public duel's seat at `slot` of side `index`: {open, you, label}, or {} for any other duel.
static func seat(view: Dictionary, index: int, slot: int) -> Dictionary:
	if not is_public(view) or index < 0 or index >= view.sides.size() or not view.sides[index] is Dictionary: return {}
	var seats: Array = view.sides[index].get("seats", [])
	return seats[slot] if slot >= 0 and slot < seats.size() else {}

## How many seats of side `index` are still open (0 for any duel that is not public).
static func open_seats(view: Dictionary, index: int) -> int:
	var count := 0
	for slot in range(2):
		if bool(seat(view, index, slot).get("open", false)): count += 1
	return count

## Whether the seat holds a player this phone has no id for: a stranger.
static func seat_stranger(view: Dictionary, index: int, slot: int) -> bool:
	var held := seat(view, index, slot)
	return not held.is_empty() and not held.open and not held.you and view.sides[index].members[slot] == null

## The name under a public seat: "Open", "You", a friend's name, a stranger's shown name or "A player".
static func seat_name(view: Dictionary, index: int, slot: int, name_of: Callable) -> String:
	var held := seat(view, index, slot)
	if held.is_empty(): return _name(view.sides[index].members[slot], true, name_of)
	if held.open: return PlayerCopy.PUBLIC_OPEN
	if held.you: return PlayerCopy.DUEL_YOU
	var shown := _seat_shown(view, index, slot, name_of)
	return shown if not shown.is_empty() else PlayerCopy.PUBLIC_A_PLAYER

## A taken seat's name when this phone has one (a friend by id, a stranger's shown name), else "".
static func _seat_shown(view: Dictionary, index: int, slot: int, name_of: Callable) -> String:
	var id: Variant = view.sides[index].members[slot]
	if id != null: return _name(id, true, name_of)
	return str(seat(view, index, slot).get("label", ""))

## A public side's title: "Open pair", "Kite + open spot", "You + Kite", "Juniper + A player" or "A pair".
static func _public_pair_title(view: Dictionary, index: int, name_of: Callable) -> String:
	var names: Array[String] = [seat_name(view, index, 0, name_of), seat_name(view, index, 1, name_of)]
	var open: Array[bool] = [bool(seat(view, index, 0).get("open", false)), bool(seat(view, index, 1).get("open", false))]
	if open[0] and open[1]: return PlayerCopy.PUBLIC_OPEN_PAIR
	if open[0] or open[1]: return PlayerCopy.PUBLIC_OPEN_SPOT % names[1 if open[0] else 0]
	if names[0] == PlayerCopy.PUBLIC_A_PLAYER and names[1] == PlayerCopy.PUBLIC_A_PLAYER: return LeaderboardRows.pair_title({})
	if names[1] == PlayerCopy.DUEL_YOU: names.reverse()
	return PlayerCopy.DUEL_PAIR % [names[0], names[1]]

## The partner this player shares a side with, as the duel page names them: a name, a stranger's shown name,
## "your partner", or "" while their seat is open.
static func partner_name(view: Dictionary, me: String, name_of: Callable) -> String:
	var side: Dictionary = view.sides[view.mine]
	for slot in range(2):
		if is_public(view):
			var held := seat(view, view.mine, slot)
			if held.get("you", false): continue
			if held.get("open", false): return ""
			var shown := _seat_shown(view, view.mine, slot, name_of)
			return shown if not shown.is_empty() else PlayerCopy.PUBLIC_DUEL_PARTNER
		var id: Variant = side.members[slot]
		if id != null and id != me and name_of.is_valid(): return str(name_of.call(id))
	return PlayerCopy.DUEL_PARTNER

## A stranger's look as a pip shows it: as sent while STRANGER_LOOKS, else plain.
static func stranger_look(look: Variant) -> Dictionary:
	return (look as Dictionary) if STRANGER_LOOKS and look is Dictionary else {}

## A side's members in slot order; a ghost's are nobody.
static func members(view: Dictionary, index: int) -> Array:
	if index == 1 and view.kind == "ghost": return [null, null]
	return view.sides[index].members

## What a side's members wear, in `members` order (services/duels_client.gd
## `looks`); a ghost wears its board row's. [{}, {}] when the server sent none.
static func looks(view: Dictionary, index: int) -> Array:
	var source: Variant = view.get("ghost") if index == 1 and view.kind == "ghost" else view.sides[index]
	var held: Variant = source.get("looks") if source is Dictionary else null
	var kept: Array = held if held is Array and held.size() == 2 else [{}, {}]
	if not is_public(view): return kept
	# A public duel: an open seat wears nothing, a stranger what stranger_look allows.
	var shown: Array = []
	for slot in range(2):
		var seat_now := seat(view, index, slot)
		shown.append({} if seat_now.get("open", false) else stranger_look(kept[slot]) if seat_stranger(view, index, slot) else kept[slot])
	return shown

## What a side's lane shows, the one path every duel surface takes for its time and dots (tests/test_shared_paths.gd):
## {ticks, counted, played, total, compared}. While the duel runs and one side has played more turns than the other,
## which has played some, the side ahead shows its time after the same number of turns as the side behind (owner,
## 2026-11-08), from the splits the server sends (services/duels_client.gd `splits`): `counted` is how many turns that
## time covers, `played` how many the side has played, `total` the run's. Without splits (an older server, a race made
## before them), and once the duel is over, each side shows its whole time so far, as before.
static func lane(view: Dictionary, index: int) -> Dictionary:
	var own := steps(view, index)
	var shown := {"ticks": ticks(view, index), "counted": own.x, "played": own.x, "total": own.y, "compared": false}
	var level := compared_steps(view)
	if level <= 0 or level >= own.x: return shown
	var held: Variant = view.ghost if index == 1 and view.kind == "ghost" else view.sides[index]
	var splits: Variant = held.get("splits") if held is Dictionary else null
	if not splits is Array or splits.size() != own.x: return shown
	shown.ticks = int(splits[level - 1])
	shown.counted = level
	shown.compared = true
	return shown

## The turns both sides have played while the duel runs and one is ahead, or 0: nothing to set side by side
## (level, over, a side that has not played yet, whose whole time 0:00.0 says nothing, or a pair that left,
## which plays no further, so the pair still playing keeps its whole time).
static func compared_steps(view: Dictionary) -> int:
	if view.status != "running" or view.sides.size() < 2 or (view.sides[1] == null and view.kind != "ghost"): return 0
	for side: Variant in view.sides:
		if side is Dictionary and side.left: return 0
	var a := steps(view, 0).x
	var b := steps(view, 1).x
	return 0 if a == b else mini(a, b)

## The steps a side has played and the whole run's (lane() shows them).
static func steps(view: Dictionary, index: int) -> Vector2i:
	if index == 1 and view.kind == "ghost": return Vector2i(view.steps, view.steps)
	return Vector2i(view.sides[index].steps, view.steps)

## A side's time so far (the ghost's whole time); lane() shows it.
static func ticks(view: Dictionary, index: int) -> int:
	if index == 1 and view.kind == "ghost": return int(view.ghost.ticks)
	return int(view.sides[index].ticks)

## What a lobby tile offers: "accept" (a challenge to you), "waiting" (yours,
## not answered), "play", "open" or "result".
static func action(view: Dictionary, me: String) -> String:
	match view.status:
		"challenged": return "accept" if view.mine == 1 else "waiting"
		"running": return "play" if your_turn(view, me) else "open"
		_: return "result"

## Where a duel belongs on the lobby: "challenge" (Open duels, waiting for an answer), "going" (the
## Going tab's tiles), "finished" (the Finished tab's result tiles: won, lost, a draw or no result) or
## "not_played" (the Finished tab's challenges that never started: said not now, no answer in a week,
## taken back, a pair split up).
static func section(view: Dictionary) -> String:
	match view.status:
		"challenged": return "challenge"
		"running": return "going"
		"decided", "unfinished": return "finished"
	return "not_played"

## Why a challenge never started, under its card on the Finished tab.
static func not_played_line(view: Dictionary) -> String:
	match view.status:
		"declined": return PlayerCopy.DUELS_NOT_PLAYED_YOU_SAID if int(view.mine) == 1 else PlayerCopy.DUELS_NOT_PLAYED_SAID
		"expired": return PlayerCopy.DUELS_NOT_PLAYED_NO_ANSWER
		"withdrawn": return PlayerCopy.DUELS_NOT_PLAYED_YOU_TOOK if int(view.mine) == 0 else PlayerCopy.DUELS_NOT_PLAYED_TAKEN
	return PlayerCopy.DUELS_NOT_PLAYED_SPLIT

## How long until an open duel ends by itself (services/duels_client.gd `ends_at`) at `now` (ticks): ms, or -1 for none.
static func time_left_ms(view: Dictionary, now: int) -> int:
	var ends_at := int(view.get("ends_at", -1))
	return -1 if ends_at < 0 or not view.status in ["challenged", "running"] else maxi(0, ends_at - now)

## A time left as its tag says it, always rounded down: weeks from 7 days, then days, then hours under a day, never under 1 hour.
static func time_left_text(ms: int) -> String:
	if ms >= WEEK_MS:
		var weeks := ms / WEEK_MS
		return PlayerCopy.DUEL_TIME_LEFT_WEEK if weeks == 1 else PlayerCopy.DUEL_TIME_LEFT_WEEKS % weeks
	if ms >= DAY_MS:
		var days := ms / DAY_MS
		return PlayerCopy.DUEL_TIME_LEFT_DAY if days == 1 else PlayerCopy.DUEL_TIME_LEFT_DAYS % days
	var hours := maxi(1, ms / HOUR_MS)
	return PlayerCopy.DUEL_TIME_LEFT_HOUR if hours == 1 else PlayerCopy.DUEL_TIME_LEFT_HOURS % hours

## Whether a time left shows coral: under a day.
static func time_left_urgent(ms: int) -> bool:
	return ms < DAY_MS

## What Give up shows on this player's own side (backend duels/model.ts giveUp), at `now` (ticks):
## {mode "ask" | "leave", asked "" | "you" | "friend", asked_at, again_ms (-1 while under the cap)},
## or {} when there is none to show (over, finished, a public seat with nobody beside, or a server
## without Give up).
static func give_up(view: Dictionary, me: String, now: int) -> Dictionary:
	var own: Variant = view.sides[view.mine]
	if view.status != "running" or not own is Dictionary or not own.has("give_up") or own.give_up.mode == "none" or own.finished or own.left: return {}
	var held: Dictionary = own.give_up
	var asked := ""
	if int(held.asked) >= 0: asked = "you" if own.members[int(held.asked)] == me or bool(seat(view, view.mine, int(held.asked)).get("you", false)) else "friend"
	# A ghost race never counts toward the cap.
	var again := -1 if view.kind == "ghost" or int(held.again_at) < 0 else int(held.again_at) - now
	return {"mode": held.mode, "asked": asked, "asked_at": int(held.asked_at), "again_ms": again if again > 0 else -1}

## Give up greyed at the cap: "Give up again in 2 days", rounded up, so it is never too soon.
static func give_up_again_text(ms: int) -> String:
	var days := maxi(1, ceili(float(ms) / DAY_MS))
	return PlayerCopy.GIVE_UP_AGAIN_DAY if days == 1 else PlayerCopy.GIVE_UP_AGAIN_DAYS % days

## The friend beside you who answers a give up: their name, a stranger's shown name, or "" for a
## stranger who shows none.
static func give_up_friend(view: Dictionary, me: String, name_of: Callable) -> String:
	if not is_public(view): return partner_name(view, me, name_of)
	for slot in range(2):
		var held := seat(view, view.mine, slot)
		if held.get("you", false) or held.get("open", false): continue
		return _seat_shown(view, view.mine, slot, name_of)
	return ""

## The other pair as a give up names them: "Finn and Noor", or "" when the duel names nobody there.
static func other_pair_names(view: Dictionary, name_of: Callable) -> String:
	var title := pair_title(view, 1 - int(view.mine), name_of)
	if title == PlayerCopy.DUEL_THEIR_PAIR or title == LeaderboardRows.pair_title({}) or title.contains(PlayerCopy.PUBLIC_A_PLAYER): return ""
	return title.replace(" + ", " and ")

## Whether the other pair's run can be watched (backend duels/routes.ts their-run): a friend
## duel whose other pair finished, once it is over for this pair (their own run finished or
## they left, or the duel is settled).
static func their_run_ready(view: Dictionary) -> bool:
	if view.get("kind") != "friend" or view.sides.size() < 2 or view.sides[1 - int(view.mine)].is_empty(): return false
	var own: Dictionary = view.sides[view.mine]
	return bool(view.sides[1 - int(view.mine)].get("finished", false)) and (view.status != "running" or own.get("finished", false) or own.get("left", false))

## The result page's title: "You and Maya won", "Finn and Noor won", "A draw", or "No result".
static func result_title(view: Dictionary, name_of: Callable) -> String:
	var result: Variant = view.result
	if not result is Dictionary: return PlayerCopy.DUEL_CHECKING_RUN_TITLE if view.kind == "ghost" else PlayerCopy.DUEL_CHECKING_TITLE
	match result.outcome:
		"won":
			if view.kind == "ghost": return PlayerCopy.DUEL_BEAT_GHOST
			return PlayerCopy.DUEL_WON % _partner_name(view, name_of)
		"lost":
			# A ghost race is lost only on time; a run that failed its check has no result.
			if view.kind == "ghost": return PlayerCopy.DUEL_GHOST_FASTER if result.reason == "faster" else PlayerCopy.DUEL_NO_RESULT
			return PlayerCopy.DUEL_THEY_WON % pair_title(view, 1 - view.mine, name_of).replace(" + ", " and ")
		"draw": return PlayerCopy.DUEL_DRAW
	return PlayerCopy.DUEL_NO_RESULT

## The fixed cue (services/sound_cues.gd) the result page sounds as it shows
## a decided duel: the leaderboard's first place bell for a win, else none.
## It rings once per duel (services/duels_client.gd bell_due).
static func result_cue(view: Dictionary) -> String:
	var result: Variant = view.get("result")
	return "ui_first" if result is Dictionary and result.get("outcome") == "won" else ""

## The line under the result's cards. `name_of` names the pair that gave up for the winners.
static func result_line(view: Dictionary, name_of: Callable = Callable()) -> String:
	var result: Variant = view.result
	if not result is Dictionary: return checking_line(view)
	match result.reason:
		"faster":
			var margin := margin_text(int(result.margin_ticks))
			return PlayerCopy.DUEL_FASTER % margin if result.outcome == "won" else PlayerCopy.DUEL_SLOWER % margin
		"draw": return PlayerCopy.DUEL_SAME_TIME
		"left":
			# A side ends this way when its pips gave up (backend duels/model.ts giveUp): a race is your own pair's.
			if view.kind == "ghost": return PlayerCopy.DUEL_RESULT_GAVE_UP_RACE
			if result.outcome == "lost": return PlayerCopy.DUEL_RESULT_GAVE_UP
			var names := other_pair_names(view, name_of)
			return PlayerCopy.DUEL_RESULT_OTHER_GAVE_UP if names.is_empty() else PlayerCopy.DUEL_RESULT_THEY_GAVE_UP % names
		"failed_check": return PlayerCopy.DUEL_RESULT_CHECK
		"stalled": return PlayerCopy.DUEL_RESULT_STALLED
		"nobody_joined": return PlayerCopy.PUBLIC_RESULT_NOBODY
	return PlayerCopy.DUEL_RESULT_NONE

## "Ahead by 0:12 after stage 2" once both pairs have finished the same stage, else "".
static func ahead_line(view: Dictionary) -> String:
	if view.kind != "friend" or view.status != "running": return ""
	var a: Dictionary = view.sides[0]
	var b: Dictionary = view.sides[1]
	if a.steps != b.steps or a.steps == 0 or a.steps % 2 != 0 or a.ticks == b.ticks: return ""
	var mine: Dictionary = view.sides[view.mine]
	var other: Dictionary = view.sides[1 - view.mine]
	var stage: int = a.steps / 2
	if mine.ticks < other.ticks: return PlayerCopy.DUEL_AHEAD % [time_text(other.ticks - mine.ticks), stage]
	return PlayerCopy.DUEL_BEHIND % [time_text(mine.ticks - other.ticks), stage]

static func _partner_name(view: Dictionary, name_of: Callable) -> String:
	var side: Dictionary = view.sides[view.mine]
	for id: Variant in side.members:
		var shown := _name(id, true, name_of)
		if shown != PlayerCopy.DUEL_YOU and not shown.is_empty(): return shown
	return _partner_word(view)

## "your friend", or "your partner" for the player beside you in a public duel.
static func _partner_word(view: Dictionary) -> String:
	return PlayerCopy.PUBLIC_DUEL_PARTNER if is_public(view) else PlayerCopy.DUEL_PARTNER

## The note while your finished run waits for the replay check: while the server checks duel runs
## (backend DUEL_RUN_CHECKS), every friend run, and a ghost race run faster than Our run (its first
## win there pays a bonus); "" otherwise. A run no check waits on ("none") counts as it finishes.
static func checking_line(view: Dictionary) -> String:
	var own: Dictionary = view.sides[view.mine]
	if not own.finished: return ""
	if view.kind == "friend": return PlayerCopy.DUEL_CHECKING_LINE if own.check != "none" else ""
	return PlayerCopy.DUEL_CHECKING_RUN_LINE if own.check == "waiting" else ""

## The result card's Pollen lines from the duel's pay and bonus: [[label, amount]], and the total.
## `bonus`: a friend duel's win bonus, or a ghost race's first win over Our run (`ghost`), which the
## server sends only on the race that paid it.
## `with_boost`: false where this build names no Full Journey (services/pollen_surfaces.gd); the boost then folds into the turns' line.
## `held`: a public duel's held duel extra (services/duels_client.gd): paid, it is one more line in the
## total; not paid, it comes back as `note` with its amount, outside the total.
static func pay_lines(pay: Dictionary, bonus: Dictionary, with_boost: bool = true, ghost: bool = false, held: Dictionary = {}) -> Dictionary:
	var lines: Array = []
	var note := ""
	if not pay.is_empty() and int(pay.turns) > 0:
		var boosted := with_boost and int(pay.boost) > 0
		lines.append([PlayerCopy.DUEL_PAY_TURNS, int(pay.plain) + int(pay.blooms) + (0 if boosted else int(pay.boost))])
		if int(pay.duel) > 0: lines.append([PlayerCopy.DUEL_PAY_PREMIUM % int(pay.duel_percent), int(pay.duel)])
		if boosted: lines.append([Breakdown.boost_label(int(pay.boost_percent)), int(pay.boost)])
	if not bonus.is_empty():
		lines.append([PlayerCopy.DUEL_PAY_GHOST_FIRST if ghost else PlayerCopy.DUEL_PAY_WIN if bonus.counted else _bonus_note(str(bonus.reason)), int(bonus.amount)])
	if int(held.get("amount", 0)) > 0:
		if held.get("state") == "paid": lines.append([PlayerCopy.PUBLIC_HELD_PAID, int(held.amount)])
		elif held.get("state") == "forfeit": note = held_note(str(held.get("reason", "")))
	var total := 0
	for line: Array in lines: total += int(line[1])
	return {"lines": lines, "total": total, "note": note, "note_amount": int(held.get("amount", 0)) if not note.is_empty() else 0}

## Why a public duel's held extra was not paid.
static func held_note(reason: String) -> String:
	match reason:
		"left": return PlayerCopy.PUBLIC_HELD_LEFT
		"stopped": return PlayerCopy.PUBLIC_HELD_STOPPED
		"nobody_joined": return PlayerCopy.PUBLIC_HELD_NOBODY
	return PlayerCopy.PUBLIC_HELD_NOT_PAID

static func _bonus_note(reason: String) -> String:
	return PlayerCopy.DUEL_PAY_WIN_CAP if reason == "weekly_cap" else PlayerCopy.DUEL_PAY_WIN_SAME if reason == "same_pair" else PlayerCopy.DUEL_PAY_WIN
