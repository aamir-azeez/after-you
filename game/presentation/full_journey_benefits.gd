extends RefCounted
## What the Full Journey card says the subscription brings, in the order the
## rules set (POLLEN-RULES.md "Card order"): the chapters first, then the room
## boost, and only then the monthly Pollen. The Pollen lines show only while the
## server pays them; the store card (presentation/store_flow.gd) draws these.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const PollenMoney = preload("res://services/pollen_money.gd")

## Month 1 of the monthly grant (backend/src/pollen/rates.json grant.first).
const GRANT_FIRST := 4500

## The card's lines, top to bottom. `boost`: Pollen earning is on (the room
## boost pays). `grant`: the monthly grant is on. `step`: what this player's
## next month pays when the server has said (a returning subscriber), else 0.
static func lines(boost: bool, grant: bool, step: int = 0) -> PackedStringArray:
	var out := PackedStringArray([PlayerCopy.SUBSCRIPTION_PURPOSE, PlayerCopy.COOPERATIVE_HOST_ACCESS])
	if boost: out.append(PlayerCopy.FULL_JOURNEY_ROOM_BOOST)
	if boost and grant: out.append(PlayerCopy.FULL_JOURNEY_GRANT % PollenMoney.grouped(step if step > 0 else GRANT_FIRST))
	return out
