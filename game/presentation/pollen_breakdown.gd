extends RefCounted
## What a confirmed Pollen receipt says, as the results card's rows (pollen
## concepts board 7b): the base, each skill bonus, the Full Journey room boost
## and whose it was, "This turn" with its total, a lucky bloom with the bloomed
## total, an item bloom, the first clears, and why an after-bank turn paid a
## little. Pure data: presentation/pollen_result_line.gd draws the rows.
##
## Rows are dictionaries: {kind, label, value, grain} and, for an item bloom,
## item_id and tier. `value` is "" for a row that is all words. `grain` puts
## the Pollen mark before the value. Kinds:
## base, bonus, boost, total, bloom, item, item_pollen, clear, reason, earned.
##
## A receipt from a server that sends no base or bonus percents (older ones,
## and receipts kept before they came) has no rows: the plain lines show then.
## Pace shows here only, after the turn, never during it (POLLEN-RULES.md).
const PlayerCopy = preload("res://presentation/player_copy.gd")
const PollenMoney = preload("res://services/pollen_money.gd")
const FriendNicknames = preload("res://services/friend_nicknames.gd")
const Catalog = preload("res://services/cosmetic_catalog.gd")

const BONUS_NAMES := {"first_try": PlayerCopy.POLLEN_ROW_FIRST_TRY, "gold_pace": PlayerCopy.POLLEN_ROW_GOLD_PACE, "silver_pace": PlayerCopy.POLLEN_ROW_SILVER_PACE, "hard": PlayerCopy.POLLEN_ROW_HARD}

## Whether a receipt carries what the rows need.
static func detailed(receipt: Dictionary) -> bool:
	if receipt.is_empty(): return false
	var turn: Dictionary = receipt.get("turn", {})
	return turn.is_empty() or (turn.has("base") and turn.has("bonus_percents")) or turn.get("kind") == "after_bank"

## The rows for one receipt, top to bottom; [] when it is not detailed.
## `partner` is the friend's name as the room shows it ("" when unknown).
## Without `full_journey` (a build that names no Full Journey) the boost row
## is left out; the totals still count the boost.
static func rows(receipt: Dictionary, partner: String, full_journey: bool = true) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not detailed(receipt): return out
	var turn: Dictionary = receipt.get("turn", {})
	if not turn.is_empty():
		if turn.kind == "bank":
			out.append(_row("base", PlayerCopy.POLLEN_ROW_BASE, PollenMoney.grouped(int(turn.base)), true))
			var percents: Array = turn.bonus_percents
			for index in range(turn.bonuses.size()):
				out.append(_row("bonus", BONUS_NAMES[turn.bonuses[index]], PlayerCopy.POLLEN_ROW_PERCENT % int(percents[index])))
			if int(turn.boost_percent) > 0 and full_journey:
				out.append(_row("boost", PlayerCopy.POLLEN_ROW_BOOST % [int(turn.boost_percent), PollenMoney.grouped(int(turn.boost)), _boost_whose(turn.get("boost_from", []), partner)]))
		# This turn: everything but a bloom's extra, which the bloom row adds.
		out.append(_row("total", PlayerCopy.POLLEN_ROW_THIS_TURN, PollenMoney.grouped(int(turn.total) - int(turn.bloom_extra)), true))
		if int(turn.bloom) > 1: out.append(_row("bloom", PlayerCopy.POLLEN_BLOOM % int(turn.bloom), PollenMoney.grouped(int(turn.total)), true))
		match str(turn.get("reason", "")):
			"repeat": out.append(_row("reason", PlayerCopy.POLLEN_REPEAT))
			"bank_empty": out.append(_row("reason", PlayerCopy.POLLEN_BANK_EMPTY))
			"late": out.append(_row("reason", PlayerCopy.POLLEN_LATE))
	var item: Dictionary = receipt.get("item_bloom", {})
	if item.has("item_id"):
		var named := Catalog.display_name(str(item.item_id))
		var row := _row("item", PlayerCopy.POLLEN_ITEM_BLOOM % (named if not named.is_empty() else PlayerCopy.POLLEN_ITEM_BLOOM_UNKNOWN))
		row["item_id"] = str(item.item_id)
		row["tier"] = str(item.get("tier", ""))
		out.append(row)
	elif item.has("pollen"):
		out.append(_row("item_pollen", PlayerCopy.POLLEN_ITEM_BLOOM_POLLEN % PollenMoney.grouped(int(item.pollen))))
	var clears: Array = receipt.get("clears", [])
	for clear: Dictionary in clears:
		out.append(_row("clear", PlayerCopy.POLLEN_ROW_FIRST_HARD_CLEAR if clear.get("kind") == "hardclear" else PlayerCopy.POLLEN_ROW_FIRST_CLEAR, PollenMoney.grouped(int(clear.get("total", 0))), true))
	# More than one part (a turn and its clears, or a bloom's Pollen): what it all came to.
	var parts := int(not turn.is_empty()) + clears.size() + int(item.has("pollen"))
	if parts > 1: out.append(_row("earned", PlayerCopy.POLLEN_ROW_EARNED, PollenMoney.grouped(int(receipt.get("earned", 0))), true))
	return out

## Whose Full Journey boosted the room, from the viewer's side.
static func _boost_whose(from: Array, partner: String) -> String:
	# A friend with no name the room knows reads "Your friend" first and "your friend" after "You and".
	var named := not partner.is_empty() and partner != FriendNicknames.FALLBACK
	if "you" in from and "partner" in from: return PlayerCopy.POLLEN_ROW_BOOST_BOTH % (partner if named else PlayerCopy.POLLEN_BOOST_FRIEND.to_lower())
	if "you" in from: return PlayerCopy.POLLEN_ROW_BOOST_YOU
	return PlayerCopy.POLLEN_ROW_BOOST_PARTNER % (partner if named else PlayerCopy.POLLEN_BOOST_FRIEND)

static func _row(kind: String, label: String, value: String = "", grain: bool = false) -> Dictionary:
	return {"kind": kind, "label": label, "value": value, "grain": grain}

## The tier's name for an item bloom's "Added to your Wardrobe" line.
static func tier_name(tier: String) -> String:
	return str(PlayerCopy.WARDROBE_TIERS.get(tier, ""))
