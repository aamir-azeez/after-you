extends RefCounted
## What the duel pages say about a duel (services/duels_client.gd valid_view),
## worked out in one place so the lobby tiles, the duel page and the result
## page always agree. Pure: no nodes, no files, no requests. Names come from a
## callable the page passes (the friends list and this player's partner), so a
## player the server did not name shows as "Sam's partner", never as an id.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const TICK_RATE := 30

## m:ss for a time in ticks.
static func time_text(ticks: int) -> String:
	var seconds := maxi(ticks, 0) / TICK_RATE
	return "%d:%02d" % [seconds / 60, seconds % 60]

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

## Whose turn a side shows: "Your turn", "Maya's turn", "Waiting for Noor", "Finished", "Left", or "".
static func turn_line(view: Dictionary, index: int, name_of: Callable) -> String:
	if index == 1 and view.kind == "ghost": return PlayerCopy.DUEL_RECORDED
	var side: Dictionary = view.sides[index]
	if side.left: return PlayerCopy.DUEL_LEFT
	if side.finished: return PlayerCopy.DUEL_FINISHED
	if view.status != "running": return ""
	if side.turn < 0: return PlayerCopy.DUEL_NOT_STARTED
	var id: Variant = side.members[side.turn]
	var shown := _name(id, side.you, name_of)
	if side.you: return PlayerCopy.DUEL_YOUR_TURN if shown == PlayerCopy.DUEL_YOU else PlayerCopy.DUEL_THEIR_TURN % (shown if not shown.is_empty() else PlayerCopy.DUEL_PARTNER)
	return PlayerCopy.DUEL_WAITING_FOR % (shown if not shown.is_empty() else PlayerCopy.DUEL_PARTNER)

## Whether it is this player's own move in the duel now.
static func your_turn(view: Dictionary, me: String) -> bool:
	var side: Dictionary = view.sides[view.mine]
	if view.status != "running" or side.finished or side.left: return false
	if side.turn >= 0: return side.members[side.turn] == me
	# No turn yet: the first room has not been made, and either of you may open it.
	return true

## The steps a side has played and the whole run's, for its dots.
static func steps(view: Dictionary, index: int) -> Vector2i:
	if index == 1 and view.kind == "ghost": return Vector2i(view.steps, view.steps)
	return Vector2i(view.sides[index].steps, view.steps)

## A side's time so far (the ghost's whole time).
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

## Where a duel belongs on the lobby: "challenge" (waiting for an answer), "duel" (running or over).
static func section(view: Dictionary) -> String:
	return "challenge" if view.status == "challenged" else "duel"

## Shown on the lobby: open challenges and duels, and results. Declined, withdrawn,
## expired and dissolved challenges fade without a word.
static func shown(view: Dictionary) -> bool:
	return not view.status in ["declined", "withdrawn", "expired", "pair_gone"]

## The result page's title: "You and Maya won", "Finn and Noor won", "A draw", or "No result".
static func result_title(view: Dictionary, name_of: Callable) -> String:
	var result: Variant = view.result
	if not result is Dictionary: return PlayerCopy.DUEL_CHECKING_TITLE
	match result.outcome:
		"won":
			if view.kind == "ghost": return PlayerCopy.DUEL_BEAT_GHOST
			return PlayerCopy.DUEL_WON % _partner_name(view, name_of)
		"lost":
			if view.kind == "ghost": return PlayerCopy.DUEL_GHOST_FASTER
			return PlayerCopy.DUEL_THEY_WON % pair_title(view, 1 - view.mine, name_of).replace(" + ", " and ")
		"draw": return PlayerCopy.DUEL_DRAW
	return PlayerCopy.DUEL_NO_RESULT

## The line under the result's cards.
static func result_line(view: Dictionary) -> String:
	var result: Variant = view.result
	if not result is Dictionary:
		var own: Dictionary = view.sides[view.mine]
		return PlayerCopy.DUEL_CHECKING_LINE if own.finished else ""
	match result.reason:
		"faster":
			var margin := margin_text(int(result.margin_ticks))
			return PlayerCopy.DUEL_FASTER % margin if result.outcome == "won" else PlayerCopy.DUEL_SLOWER % margin
		"draw": return PlayerCopy.DUEL_SAME_TIME
		"left": return PlayerCopy.DUEL_RESULT_LEFT
		"failed_check": return PlayerCopy.DUEL_RESULT_CHECK
		"stalled": return PlayerCopy.DUEL_RESULT_STALLED
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
	return PlayerCopy.DUEL_PARTNER

## The result card's Pollen lines from the duel's pay and win bonus: [[label, amount]], and the total.
## `with_boost`: false where this build names no Full Journey (services/pollen_surfaces.gd); the boost then folds into the turns' line.
static func pay_lines(pay: Dictionary, bonus: Dictionary, with_boost: bool = true) -> Dictionary:
	var lines: Array = []
	if not pay.is_empty() and int(pay.turns) > 0:
		var boosted := with_boost and int(pay.boost) > 0
		lines.append([PlayerCopy.DUEL_PAY_TURNS, int(pay.plain) + int(pay.blooms) + (0 if boosted else int(pay.boost))])
		if int(pay.duel) > 0: lines.append([PlayerCopy.DUEL_PAY_PREMIUM, int(pay.duel)])
		if boosted: lines.append([PlayerCopy.DUEL_PAY_BOOST % int(pay.boost_percent), int(pay.boost)])
	if not bonus.is_empty():
		lines.append([PlayerCopy.DUEL_PAY_WIN if bonus.counted else _bonus_note(str(bonus.reason)), int(bonus.amount)])
	var total := 0
	for line: Array in lines: total += int(line[1])
	return {"lines": lines, "total": total}

static func _bonus_note(reason: String) -> String:
	return PlayerCopy.DUEL_PAY_WIN_CAP if reason == "weekly_cap" else PlayerCopy.DUEL_PAY_WIN_SAME if reason == "same_pair" else PlayerCopy.DUEL_PAY_WIN
