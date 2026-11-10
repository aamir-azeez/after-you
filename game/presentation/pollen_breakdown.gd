extends RefCounted
## What a confirmed Pollen receipt says, as the results card's rows (pollen
## concepts board 7b): the base, each skill bonus and the Full Journey room
## boost (each with its percent and the Pollen it added), "This turn" with its
## total, a lucky bloom with the bloomed total, an item bloom, the first clears,
## and why an after-bank turn paid a little. The rows above "This turn" always
## add up to it. Pure data: presentation/pollen_breakdown_view.gd draws the rows.
##
## Rows are dictionaries: {kind, label, value, grain, plus} and, for an item
## bloom, item_id and tier. `value` is "" for a row that is all words. `grain`
## puts the Pollen mark before the value; `plus` a "+" before that, on the rows
## that add to Base (ADDED: "First try (25%)  +[grain] 22"). Kinds:
## base, bonus, boost, duel, sunshine, total, bloom, item, item_pollen, clear,
## reason, earned, fruit. A Sunshine turn (Fruits board 7) adds its Sunshine
## row ("Sunshine ×2  +[grain] 89"), the plain amount paid again; the server
## puts it in the turn's total and not in its amount. Each achievement the
## credit paid (Fruits board 6b, the receipt's `fruits.paid`) is a fruit row
## under everything else, its value in Fruits (`currency` "fruits").
##
## A receipt from a server that sends no base or bonus percents (older ones,
## and receipts kept before they came) has no rows: the plain lines show then.
## So does a bank turn whose own numbers would show a row below zero.
## Pace shows here only, after the turn, never during it (POLLEN-RULES.md).
const PlayerCopy = preload("res://presentation/player_copy.gd")
const PollenMoney = preload("res://services/pollen_money.gd")
const Catalog = preload("res://services/cosmetic_catalog.gd")

## What each Full Journey player in a room adds (backend rates.json boost_percent_per_subscriber).
const BOOST_PERCENT_EACH := 10
## The rows that add to Base: each shows "+" before its mark.
const ADDED := ["bonus", "boost", "duel", "sunshine", "fruit"]
const FRUITS := "fruits"
const BONUS_NAMES := {"first_try": PlayerCopy.POLLEN_ROW_FIRST_TRY, "gold_pace": PlayerCopy.POLLEN_ROW_GOLD_PACE, "silver_pace": PlayerCopy.POLLEN_ROW_SILVER_PACE, "hard": PlayerCopy.POLLEN_ROW_HARD}

## Whether a receipt carries what the rows need.
static func detailed(receipt: Dictionary) -> bool:
	if receipt.is_empty(): return false
	var turn: Dictionary = receipt.get("turn", {})
	if turn.is_empty() or turn.get("kind") == "after_bank": return true
	if not (turn.has("base") and turn.has("bonus_percents")): return false
	# A malformed bank turn (an amount below its base, or bonuses its amount cannot pay) never shows a row below zero.
	var added := int(turn.amount) - int(turn.base)
	return added >= 0 and bonus_amounts(int(turn.base), added, turn.bonus_percents).all(func(share: int) -> bool: return share >= 0)

## The rows for one receipt, top to bottom; [] when it is not detailed.
## Without `full_journey` (a build that names no Full Journey) the boost row
## is left out and its Pollen counts in Base, so the rows still add up.
## Without `fruits` (Fruits hidden: services/pollen_surfaces.gd fruits_visible)
## the Sunshine row is left out the same way and no fruit row shows.
static func rows(receipt: Dictionary, full_journey: bool = true, fruits: bool = true) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not detailed(receipt): return out
	var turn: Dictionary = receipt.get("turn", {})
	if not turn.is_empty():
		if turn.kind == "bank":
			var boost := int(turn.boost)
			var boost_row := int(turn.boost_percent) > 0 and full_journey
			var sunshine := int(turn.get("sunshine", 0))
			var sunshine_row := sunshine > 0 and fruits
			out.append(_row("base", PlayerCopy.POLLEN_ROW_BASE, PollenMoney.grouped(int(turn.base) + (0 if boost_row else boost) + (0 if sunshine_row else sunshine)), true))
			var percents: Array = turn.bonus_percents
			var added := bonus_amounts(int(turn.base), int(turn.amount) - int(turn.base), percents)
			for index in range(turn.bonuses.size()):
				out.append(_row("bonus", PlayerCopy.POLLEN_ROW_PERCENT % [BONUS_NAMES[turn.bonuses[index]], int(percents[index])], PollenMoney.grouped(added[index]), true))
			if boost_row: out.append(_row("boost", boost_label(int(turn.boost_percent), (turn.get("boost_from", []) as Array).size()), PollenMoney.grouped(boost), true))
			# A friend duel's turn: its premium, as the duel result page names it (duel_model.gd pay_lines).
			if int(turn.get("duel", 0)) > 0: out.append(_row("duel", PlayerCopy.DUEL_PAY_PREMIUM % int(turn.duel_percent), PollenMoney.grouped(int(turn.duel)), true))
			if sunshine_row: out.append(_row("sunshine", PlayerCopy.FRUIT_SUNSHINE_ROW, PollenMoney.grouped(sunshine), true))
		# This turn: everything but a bloom's extra, which the bloom row adds.
		out.append(_row("total", PlayerCopy.POLLEN_ROW_THIS_TURN, PollenMoney.grouped(int(turn.total) - int(turn.bloom_extra)), true))
		if int(turn.bloom) > 1: out.append(_row("bloom", PlayerCopy.POLLEN_BLOOM % int(turn.bloom), PollenMoney.grouped(int(turn.total)), true))
		# A public duel turn's duel extra, held outside the total until the duel ends.
		if int(turn.get("duel_held", 0)) > 0: out.append(_row("reason", PlayerCopy.POLLEN_ROW_DUEL_HELD % PollenMoney.grouped(int(turn.duel_held))))
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
	if fruits: out.append_array(fruit_rows(receipt))
	return out

## A fruit row for each achievement the receipt paid (`fruits.paid`, oldest
## first as the server lists them): its name and "5 Fruits". [] for none, or
## for an id this build has no name for.
static func fruit_rows(receipt: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var credit: Variant = receipt.get("fruits")
	if not credit is Dictionary: return out
	for line: Variant in (credit as Dictionary).get("paid", []):
		if not line is Dictionary: continue
		var named := str(PlayerCopy.FRUIT_GOALS.get(str(line.get("id", "")), ""))
		if named.is_empty() or int(line.get("amount", 0)) <= 0: continue
		var row := _row("fruit", named, PlayerCopy.FRUIT_AMOUNT % PollenMoney.grouped(int(line.amount)), true)
		row["currency"] = FRUITS
		row["id"] = str(line.id)
		out.append(row)
	return out

## The Full Journey row's words, on every surface that shows the room boost:
## "Full Journey (10%)" for one Full Journey player, "Full Journey (2 × 10%)"
## for two. `players` is how many had it; 0 works it out from the percent (a
## duel's pay names no one).
static func boost_label(percent: int, players: int = 0) -> String:
	if players <= 0 and percent % BOOST_PERCENT_EACH == 0: players = percent / BOOST_PERCENT_EACH
	if players > 1 and percent % players == 0: return PlayerCopy.POLLEN_ROW_BOOST_EACH % [players, percent / players]
	return PlayerCopy.POLLEN_ROW_BOOST % percent

## The Pollen each bonus added: `added` (the turn's amount less its base, which
## the server rounds once for all the bonuses) shared out by each bonus's
## percent of `base`. Each share is rounded down, then what is left goes one at
## a time to the largest remainders (the earlier bonus on a tie), so the shares
## always add up to `added`.
static func bonus_amounts(base: int, added: int, percents: Array) -> Array[int]:
	var out: Array[int] = []
	var remainders: Array[int] = []
	var left := added
	for percent: Variant in percents:
		var exact := base * int(percent)
		out.append(floori(exact / 100.0))
		remainders.append(exact - out[-1] * 100)
		left -= out[-1]
	if out.is_empty(): return out
	var order: Array = range(out.size())
	order.sort_custom(func(first: int, second: int) -> bool: return remainders[first] > remainders[second] or (remainders[first] == remainders[second] and first < second))
	for step in range(mini(maxi(left, 0), out.size())):
		out[order[step]] += 1
		left -= 1
	# A server amount these percents cannot explain: the rest goes on the last bonus, so the rows still add up.
	out[-1] += left
	return out

static func _row(kind: String, label: String, value: String = "", grain: bool = false) -> Dictionary:
	return {"kind": kind, "label": label, "value": value, "grain": grain, "plus": kind in ADDED}

## The tier's name for an item bloom's "Added to your Wardrobe" line.
static func tier_name(tier: String) -> String:
	return str(PlayerCopy.WARDROBE_TIERS.get(tier, ""))
