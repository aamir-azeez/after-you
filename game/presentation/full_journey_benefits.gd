extends RefCounted
## What the Full Journey card says the subscription brings, in the order the
## rules set (POLLEN-RULES.md "Card order"): the chapters first, then the room
## boost, and only then the monthly Pollen. The chapters are two plain lines;
## the boost and the monthly Pollen are the two cream panels of pollen-concepts
## board 3, each with its explainer, and the Pollen panel ends with the ladder.
## The panels show only while the server pays them, and never on a build that
## names no Full Journey Pollen (services/pollen_surfaces.gd, asked by the
## caller). The store card (presentation/store_flow.gd) draws this with
## presentation/kit/benefit_panel.gd.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const PollenMoney = preload("res://services/pollen_money.gd")

## The monthly grant's ladder, as backend/src/pollen/rates.json "grant" sets it:
## month 1 pays FIRST, each month after pays STEP more, up to TOP.
const GRANT_FIRST := 4500
const GRANT_STEP := 250
const GRANT_TOP := 12000
## The ladder line names what this month pays.
const LADDER_MONTH := 12
const SEPARATOR := " · "

## The card's content. `boost`: Pollen earning is on (the room boost pays).
## `grant`: the monthly grant is on. `ladder`: what the server last said for
## this player ({months, next, top}, services/pollen_grant.gd ladder), {} for a
## player who never subscribed. `shown`: the build names Full Journey Pollen.
## Returns {intro: the chapter lines, panels: [{name, icon, title, body, ladder?}]}.
static func content(boost: bool, grant: bool, ladder: Dictionary = {}, shown: bool = true) -> Dictionary:
	var panels: Array[Dictionary] = []
	if boost and shown:
		panels.append({"name": "FullJourneyBoost", "icon": "room", "title": PlayerCopy.FULL_JOURNEY_ROOM_BOOST, "body": PlayerCopy.FULL_JOURNEY_ROOM_BOOST_NOTE})
	if boost and grant and shown:
		var top := _top(ladder)
		var first := _first_month(ladder)
		panels.append({"name": "FullJourneyGrant", "icon": "pollen", "title": (PlayerCopy.FULL_JOURNEY_GRANT_TOP if first >= top else PlayerCopy.FULL_JOURNEY_GRANT) % PollenMoney.grouped(first),
			"body": PlayerCopy.FULL_JOURNEY_GRANT_NOTE % [PollenMoney.grouped(GRANT_STEP), PollenMoney.grouped(top)], "ladder": ladder_line(ladder)})
	return {"intro": PackedStringArray([PlayerCopy.SUBSCRIPTION_PURPOSE, PlayerCopy.COOPERATIVE_HOST_ACCESS]), "panels": panels}

## "Next month: 4,750 · By month 12: 7,250 · Top step: 12,000": what the month
## after the first pays, month 12 while it is still ahead, and the top step.
## A returning subscriber picks up at their own step (the server's next).
static func ladder_line(ladder: Dictionary = {}) -> String:
	var top := _top(ladder)
	var first := _first_month(ladder)
	var month := int(ladder.get("months", 0)) + 1
	var parts := PackedStringArray()
	if first < top: parts.append(PlayerCopy.FULL_JOURNEY_LADDER_NEXT % PollenMoney.grouped(mini(first + GRANT_STEP, top)))
	if month + 1 < LADDER_MONTH: parts.append(PlayerCopy.FULL_JOURNEY_LADDER_BY % [LADDER_MONTH, PollenMoney.grouped(mini(GRANT_FIRST + GRANT_STEP * (LADDER_MONTH - 1), top))])
	parts.append(PlayerCopy.FULL_JOURNEY_LADDER_TOP % PollenMoney.grouped(top))
	return SEPARATOR.join(parts)

## What the player's first month back pays: the server's step, else month 1.
static func _first_month(ladder: Dictionary) -> int:
	var next := int(ladder.get("next", 0))
	return mini(next, _top(ladder)) if next > 0 else GRANT_FIRST

static func _top(ladder: Dictionary) -> int:
	var top := int(ladder.get("top", 0))
	return top if top > 0 else GRANT_TOP
