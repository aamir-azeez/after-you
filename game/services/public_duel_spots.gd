extends RefCounted
## Public duel spots: which seat a join takes and why a row is greyed. Pure, no
## nodes or requests. spot_for() mirrors the server's own rule (backend
## src/duels/public.ts spotFor), and both are held to one table of cases,
## tests/fixtures/public_duels/spots.json, so a greyed reason on the list always
## matches what the server would answer.
##
## Seats are numbered 0 to 3: 0 and 1 are the first pair, 2 and 3 the second.
## `open` is four flags in seat order, true while that seat is free.
const ALONE := "alone"
const PARTY := "party"

## The greyed reasons, in the order a row checks them: the first that applies is
## the one it shows. Geometry reasons (seat_taken, full, one_left, split) come
## from spot_for; the rest from what the phone knows of the player.
const MINE := "mine"
const CHAPTER := "chapter"
const PARTNER_OFF := "partner_off"
const PARTNER_RULES := "partner_rules"
const LIMIT := "limit"
const SEAT_TAKEN := "seat_taken"
const FULL := "full"
const ONE_LEFT := "one_left"
const SPLIT := "split"

## {seat} or {reason}. `wanted`: a tapped seat, or -1 for the game's pick.
static func spot_for(open: Array, joining: String, wanted: int = -1) -> Dictionary:
	if open.size() != 4: return {"reason": FULL}
	var free := func(seat: int) -> bool: return bool(open[seat])
	if joining == PARTY:
		if wanted >= 0:
			var first := wanted - wanted % 2
			if free.call(first) and free.call(first + 1): return {"seat": first}
			return {"reason": SPLIT if free.call(wanted) else SEAT_TAKEN}
		for first: int in [0, 2]:
			if free.call(first) and free.call(first + 1): return {"seat": first}
		var count := open.count(true)
		return {"reason": FULL if count == 0 else ONE_LEFT if count == 1 else SPLIT}
	if wanted >= 0: return {"seat": wanted} if free.call(wanted) else {"reason": SEAT_TAKEN}
	# Beside a player first: their pair is complete sooner.
	for seat in range(4):
		if free.call(seat) and not free.call(seat ^ 1): return {"seat": seat}
	for first: int in [0, 2]:
		if free.call(first) and free.call(first + 1): return {"seat": first}
	return {"reason": FULL}

## The four open flags of a list row or a public duel view's sides ([{seats: [{open}, {open}]}, ...]).
static func open_flags(sides: Array) -> Array:
	var flags := []
	for index in range(2):
		var side: Variant = sides[index] if index < sides.size() else null
		var seats: Array = side.get("seats", []) if side is Dictionary else []
		for slot in range(2):
			var seat: Variant = seats[slot] if slot < seats.size() else null
			flags.append(seat is Dictionary and seat.get("open") == true)
	return flags

## Why a list row is greyed for this player, or "" when it can be joined.
## `known`: {chapter_open: bool, partner_on: bool, partner_rules: bool or null,
## at_limit: bool}; a party join also needs the partner (partner_reason).
static func greyed(row: Dictionary, joining: String, known: Dictionary) -> String:
	if row.get("mine", false): return MINE
	if not known.get("chapter_open", true): return CHAPTER
	if joining == PARTY and not partner_reason(known).is_empty(): return partner_reason(known)
	if known.get("at_limit", false): return LIMIT
	var spot := spot_for(open_flags(row.get("sides", [])), joining)
	return str(spot.get("reason", ""))

## Why your partner can't post or join with you, or "": their switch is off, or
## the lobby said they have not accepted the community rules in force (only a
## clear false greys; unknown leaves it to the server's partner_rules_required).
static func partner_reason(known: Dictionary) -> String:
	if not known.get("partner_on", false): return PARTNER_OFF
	var rules: Variant = known.get("partner_rules")
	if rules is bool and not rules: return PARTNER_RULES
	return ""
