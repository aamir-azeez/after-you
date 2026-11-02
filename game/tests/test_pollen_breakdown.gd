extends SceneTree
## The Pollen results card's rows (presentation/pollen_breakdown.gd) and the
## Pollen from play page's data (services/pollen_history.gd), from receipts and
## history as the server sends them (JSON numbers arrive as floats):
## - a bank turn: base, each bonus and the room boost with its percent and the
##   Pollen it added ("Full Journey (2 × 10%)", no one named; left out on a build
##   that names no Full Journey, whose Base then carries it), a friend duel's
##   premium, This turn, and a lucky bloom with the bloomed total; the rows
##   above This turn always add up to it;
## - an after-bank turn: This turn and why it paid a little (repeat, bank empty, late);
## - an item bloom, a fully owned tier's Pollen, first clears and what it all came to;
## - a receipt without the base or the bonus percents has no rows (the plain line shows);
## - history: turns of chapters this build knows, free chapters' first clears, the bank.
const Breakdown = preload("res://presentation/pollen_breakdown.gd")
const PollenWallet = preload("res://services/pollen_wallet.gd")
const PollenHistory = preload("res://services/pollen_history.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	_bank_turn()
	_after_bank()
	_blooms_and_clears()
	_older_server()
	_shares_add_up()
	_history()
	print("AFTER YOU POLLEN BREAKDOWN: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

static func _turn(extra: Dictionary = {}) -> Dictionary:
	var turn := {"kind": "bank", "base": 166.0, "bonuses": ["first_try", "silver_pace"], "bonus_percents": [25.0, 5.0], "bonus_percent": 30.0, "amount": 216.0,
		"bloom": 1.0, "bloom_extra": 0.0, "boost_percent": 10.0, "boost": 22.0, "total": 238.0, "boost_from": ["partner"]}
	turn.merge(extra, true)
	return turn

static func _receipt(turn: Dictionary, extra: Dictionary = {}) -> Dictionary:
	var value := {"schema_version": 1.0, "earned": turn.get("total", 0.0), "balance": 1000.0, "turn": turn, "clears": []}
	value.merge(extra, true)
	return PollenWallet.checked_receipt(value)

static func _labels(rows: Array) -> Array:
	return rows.map(func(row: Dictionary) -> String: return row.label + ("" if row.value.is_empty() else " = " + row.value))

## Whether the rows above This turn add up to it (the amounts as shown, commas and all).
static func _adds_up(rows: Array) -> bool:
	var sum := 0
	for row: Dictionary in rows:
		if row.kind == "total": return sum == int(str(row.value).replace(",", ""))
		if row.kind in ["base", "bonus", "boost", "duel"]: sum += int(str(row.value).replace(",", ""))
	return false

func _bank_turn() -> void:
	var rows := Breakdown.rows(_receipt(_turn()))
	_check(_labels(rows) == ["Base = 166", "First try (25%) = 42", "Silver pace (5%) = 8", "Full Journey (10%) = 22", "This turn = 238"], "The board's paid chapter turn: " + str(_labels(rows)))
	_check(rows.all(func(row: Dictionary) -> bool: return row.grain), "Every amount has its grain, as Base does")
	_check(rows.map(func(row: Dictionary) -> bool: return row.plus) == [false, true, true, true, false], "The rows that add to Base lead with a plus; Base and This turn do not")
	_check(_adds_up(rows), "The rows add up to This turn")
	var both := Breakdown.rows(_receipt(_turn({"boost_percent": 20.0, "boost": 43.0, "total": 259.0, "boost_from": ["you", "partner"]})))
	_check(_labels(both)[3] == "Full Journey (2 × 10%) = 43" and both[4].value == "259" and _adds_up(both), "Two Full Journey players, each adding 10%: " + str(_labels(both)))
	_check(_labels(Breakdown.rows(_receipt(_turn({"boost_from": ["you"]}))))[3] == "Full Journey (10%) = 22", "Your own Full Journey reads the same, with no name")
	_check(not _labels(both).any(func(label: String) -> bool: return label.contains("has Full Journey") or label.contains("have Full Journey")), "No row says whose Full Journey it was")
	# The owner's card: base 89, first try, both with Full Journey: 111 + 22 = 133.
	var owner := Breakdown.rows(_receipt(_turn({"base": 89.0, "bonuses": ["first_try"], "bonus_percents": [25.0], "bonus_percent": 25.0, "amount": 111.0, "boost_percent": 20.0, "boost": 22.0, "total": 133.0, "boost_from": ["you", "partner"]})))
	_check(_labels(owner) == ["Base = 89", "First try (25%) = 22", "Full Journey (2 × 10%) = 22", "This turn = 133"] and _adds_up(owner), "The owner's Turn saved card: " + str(_labels(owner)))
	_check(Breakdown.boost_label(10) == "Full Journey (10%)" and Breakdown.boost_label(20) == "Full Journey (2 × 10%)" and Breakdown.boost_label(20, 1) == "Full Journey (20%)" and Breakdown.boost_label(15) == "Full Journey (15%)", "The boost words: how many from the receipt, or from the percent where no one is named")
	# A friend duel's turn: 216 at 10% boost and the 50% premium, one rounding: 130 - 22 = 108.
	var duel := Breakdown.rows(_receipt(_turn({"duel_percent": 50.0, "duel": 108.0, "total": 346.0})))
	_check(_labels(duel).slice(-3) == ["Full Journey (10%) = 22", (PlayerCopy.DUEL_PAY_PREMIUM % 50) + " = 108", "This turn = 346"] and duel[-2].grain and _adds_up(duel), "A duel turn names its premium so the rows add up: " + str(_labels(duel)))
	_check(PlayerCopy.DUEL_PAY_PREMIUM % 50 == "Duel bonus (50%)", "The duel premium shows its percent as the other rows do")
	_check(not _receipt(_turn()).turn.has("duel") and not _labels(rows).any(func(label: String) -> bool: return label.begins_with(PlayerCopy.DUEL_PAY_PREMIUM % 50)), "Any other turn has no duel row")
	_check(PollenWallet.checked_receipt({"schema_version": 1.0, "earned": 1.0, "balance": 1.0, "clears": [], "turn": _turn({"duel": -1.0, "duel_percent": 50.0})}).is_empty(), "A duel premium below zero refuses the receipt")
	_check(PollenWallet.checked_receipt({"schema_version": 1.0, "earned": 1.0, "balance": 1.0, "clears": [], "turn": _turn({"duel": 108.0})}).is_empty(), "So does a premium without its percent")
	var rate := Breakdown.rows(_receipt(_turn({"duel_percent": 40.0, "duel": 86.0, "total": 324.0})))
	_check(rate[-2].label == PlayerCopy.DUEL_PAY_PREMIUM % 40, "The row names the server's rate, not a fixed one: " + str(_labels(rate)))
	var phone := Breakdown.rows(_receipt(_turn()), false)
	_check(_labels(phone) == ["Base = 188", "First try (25%) = 42", "Silver pace (5%) = 8", "This turn = 238"] and _adds_up(phone), "A build that names no Full Journey leaves out the boost row and counts it in Base, so the rows add up: " + str(_labels(phone)))
	var phone_duel := Breakdown.rows(_receipt(_turn({"duel_percent": 50.0, "duel": 108.0, "total": 346.0})), false)
	_check(_adds_up(phone_duel) and phone_duel.size() == 5, "So does a duel turn there: " + str(_labels(phone_duel)))
	var plain := Breakdown.rows(_receipt(_turn({"bonuses": [], "bonus_percents": [], "bonus_percent": 0.0, "amount": 89.0, "base": 89.0, "boost_percent": 0.0, "boost": 0.0, "total": 89.0, "boost_from": []})))
	_check(_labels(plain) == ["Base = 89", "This turn = 89"], "A turn with no bonus or boost")
	var big := Breakdown.rows(_receipt(_turn({"base": 1200.0, "bonuses": [], "bonus_percents": [], "amount": 1200.0, "boost_percent": 0.0, "boost": 0.0, "total": 1200.0})))
	_check(big[0].value == "1,200", "Amounts are written with thousands commas")

func _after_bank() -> void:
	var tail := _turn({"kind": "after_bank", "base": 0.0, "bonuses": [], "bonus_percents": [], "bonus_percent": 0.0, "amount": 10.0, "boost_percent": 0.0, "boost": 0.0, "total": 10.0, "boost_from": [], "reason": "repeat"})
	_check(_labels(Breakdown.rows(_receipt(tail))) == ["This turn = 10", PlayerCopy.POLLEN_REPEAT], "A repeated part says why it pays a little")
	tail.reason = "bank_empty"
	_check(_labels(Breakdown.rows(_receipt(tail))) == ["This turn = 10", PlayerCopy.POLLEN_BANK_EMPTY], "So does an empty bank")
	tail.reason = "late"
	_check(Breakdown.rows(_receipt(tail))[1].label == PlayerCopy.POLLEN_LATE, "And a turn from an earlier week")
	tail.erase("base")
	tail.erase("bonus_percents")
	_check(Breakdown.detailed(_receipt(tail)), "An after-bank turn needs no base to show its rows")

func _blooms_and_clears() -> void:
	var bloomed := Breakdown.rows(_receipt(_turn({"base": 89.0, "bonuses": ["first_try", "gold_pace"], "bonus_percents": [25.0, 15.0], "bonus_percent": 40.0, "amount": 125.0, "bloom": 2.0, "bloom_extra": 125.0, "boost_percent": 0.0, "boost": 0.0, "total": 250.0, "boost_from": []})))
	_check(_labels(bloomed) == ["Base = 89", "First try (25%) = 22", "Gold pace (15%) = 14", "This turn = 125", "A lucky bloom: ×2 = 250"] and _adds_up(bloomed), "The board's double bloom, its bonuses sharing the one rounding (36, not 22 + 13): " + str(_labels(bloomed)))
	var boosted := Breakdown.rows(_receipt(_turn({"base": 100.0, "bonuses": [], "bonus_percents": [], "bonus_percent": 0.0, "amount": 125.0, "bloom": 2.0, "bloom_extra": 125.0, "boost": 13.0, "total": 263.0})))
	_check(boosted[-2].value == "138" and boosted[-1].value == "263", "A bloom's extra is never boosted: this turn 125 + 13, bloomed 263: " + str(_labels(boosted)))
	var item := Breakdown.rows(_receipt(_turn({"base": 89.0, "bonuses": ["first_try"], "bonus_percents": [25.0], "bonus_percent": 25.0, "amount": 111.0, "boost_percent": 0.0, "boost": 0.0, "total": 111.0, "boost_from": []}), {"item_bloom": {"tier": "common", "item_id": "daisy"}}))
	_check(item[-1].kind == "item" and item[-1].item_id == "daisy" and item[-1].tier == "common" and item[-1].label == "A lucky bloom: a new Daisy!" and Breakdown.tier_name(item[-1].tier) == "Common", "An item bloom names the new item and its tier")
	var owned := Breakdown.rows(_receipt(_turn({"boost_percent": 0.0, "boost": 0.0, "total": 216.0, "boost_from": []}), {"earned": 1216.0, "item_bloom": {"tier": "common", "pollen": 1000.0}}))
	_check(_labels(owned).slice(-3) == ["This turn = 216", "A lucky bloom: +1,000 Pollen", "Pollen earned = 1,216"], "A fully owned tier pays its price, and the card says what it all came to: " + str(_labels(owned)))
	var finish := _receipt(_turn({"boost_percent": 0.0, "boost": 0.0, "total": 216.0, "boost_from": []}), {"earned": 1416.0, "clears": [{"kind": "clear", "level_id": "conservatory", "amount": 1200.0, "boost_percent": 0.0, "boost": 0.0, "total": 1200.0}]})
	_check(_labels(Breakdown.rows(finish)).slice(-3) == ["This turn = 216", "First clear = 1,200", "Pollen earned = 1,416"], "The finishing turn and its first clear: " + str(_labels(Breakdown.rows(finish))))
	var friend := PollenWallet.checked_receipt({"schema_version": 1.0, "earned": 1320.0, "balance": 1320.0, "clears": [{"kind": "clear", "total": 1320.0, "boost_percent": 10.0}, {"kind": "hardclear", "total": 1320.0, "boost_percent": 10.0}]})
	_check(_labels(Breakdown.rows(friend)) == ["First clear = 1,320", "First Hard clear = 1,320", "Pollen earned = 1,320"], "A friend's first clears from the room's finish: " + str(_labels(Breakdown.rows(friend))))

func _older_server() -> void:
	var old := _turn()
	old.erase("base")
	old.erase("bonus_percents")
	_check(not Breakdown.detailed(_receipt(old)) and Breakdown.rows(_receipt(old)).is_empty(), "A receipt from a server without the base and percents has no rows")
	_check(PollenWallet.checked_receipt({"schema_version": 1.0, "earned": 1.0, "balance": 1.0, "clears": [], "turn": _turn({"bonus_percents": [25.0]})}).is_empty(), "Percents that do not match the bonuses refuse the receipt")
	_check(PollenWallet.checked_receipt({"schema_version": 1.0, "earned": 1.0, "balance": 1.0, "clears": [], "turn": _turn({"base": -1.0})}).is_empty(), "So does a base below zero")
	_check(Breakdown.rows({}).is_empty(), "No receipt, no rows")
	# A malformed bank turn never shows a row below zero: it shows the plain line instead.
	var below := _receipt(_turn({"base": 89.0, "bonuses": [], "bonus_percents": [], "bonus_percent": 0.0, "amount": 80.0, "boost_percent": 0.0, "boost": 0.0, "total": 80.0, "boost_from": []}))
	_check(not below.is_empty() and not Breakdown.detailed(below) and Breakdown.rows(below).is_empty(), "An amount below its base has no rows")
	var short := _receipt(_turn({"base": 89.0, "bonuses": ["first_try", "gold_pace"], "bonus_percents": [25.0, 15.0], "bonus_percent": 40.0, "amount": 99.0, "boost_percent": 0.0, "boost": 0.0, "total": 99.0, "boost_from": []}))
	_check(not short.is_empty() and Breakdown.rows(short).is_empty(), "Nor do bonuses their amount cannot pay")

## Each bonus's share of the Pollen the bonuses added, over every base and pair
## of the server's bonus percents: the shares always add up to the turn's amount,
## each is within one of its exact share, and Hard alone takes all of it.
func _shares_add_up() -> void:
	var sets := [[25], [15], [5], [50], [25, 15], [25, 5], [25, 50], [15, 50], [25, 15, 50], [25, 5, 50]]
	var exact := true
	var near := true
	for base in range(1, 400):
		for percents: Array in sets:
			var total := 0
			for percent: int in percents: total += percent
			# The server's one rounding: base x (100 + percents) / 100, half up.
			var added := floori((2 * base * (100 + total) + 100) / 200.0) - base
			var shares := Breakdown.bonus_amounts(base, added, percents)
			var sum := 0
			for index in range(shares.size()):
				sum += shares[index]
				near = near and absf(shares[index] - base * percents[index] / 100.0) < 1.0
			exact = exact and sum == added
	_check(exact, "The bonus rows always add up to what the server added for them")
	_check(near, "Each bonus row is within one of its exact share")
	_check(Breakdown.bonus_amounts(166, 50, [25, 5]) == [42, 8] and Breakdown.bonus_amounts(89, 36, [25, 15]) == [22, 14], "The board's turns")
	_check(Breakdown.bonus_amounts(89, 45, [50]) == [45], "Hard alone takes all it added")
	_check(Breakdown.bonus_amounts(89, 0, []).is_empty(), "No bonuses, no shares")
	var hard := Breakdown.rows(_receipt(_turn({"base": 207.0, "bonuses": ["first_try", "gold_pace", "hard"], "bonus_percents": [25.0, 15.0, 50.0], "bonus_percent": 90.0, "amount": 393.0, "boost_percent": 10.0, "boost": 39.0, "total": 432.0, "boost_from": ["you"]})))
	_check(_labels(hard).slice(1, 4) == ["First try (25%) = 52", "Gold pace (15%) = 31", "Hard (50%) = 103"] and _adds_up(hard), "A Hard turn's rows add up: " + str(_labels(hard)))

func _history() -> void:
	var value := {"schema_version": 1.0, "entries": [
		{"kind": "turn", "amount": 250.0, "at": 3.0, "level_id": "the-wishing-well", "stage_id": "", "role": "a", "bonuses": ["first_try", "gold_pace"], "bloom": 2.0},
		{"kind": "turn", "amount": 10.0, "at": 2.0, "level_id": "relay-isles", "stage_id": "garden", "role": "b", "reason": "repeat"},
		{"kind": "turn", "amount": 9.0, "at": 2.0, "level_id": "a-chapter-from-later", "stage_id": "x", "role": "a"},
		{"kind": "clear", "amount": 1200.0, "at": 1.0, "level_id": "first-steps"},
		{"kind": "grant", "amount": 4500.0, "at": 1.0},
		{"kind": "turn", "amount": 9.0, "at": 2.0, "level_id": "relay-isles", "stage_id": "garden", "role": "a", "bonuses": ["luck"]}],
		"first_clears": [{"level_id": "first-steps", "price": 1200.0, "paid": 1200.0}, {"level_id": "high-and-low", "price": 1200.0}, {"level_id": "conservatory", "price": 2000.0}, {"level_id": "a-chapter-from-later", "price": 1.0}],
		"bank": {"left": 15.0, "refill": 12.0, "cap": 36.0, "tail": [{"pay": 10.0, "turns": 36.0}, {"pay": 1.0, "turns": 64.0}]}}
	var history := PollenHistory.checked(value)
	_check(history.turns.size() == 2 and history.turns[0].bloom == 2 and history.turns[0].bonuses == ["first_try", "gold_pace"] and history.turns[1].reason == "repeat", "Turns of known chapters show, with their bonuses, bloom and reason; others are left out")
	_check(history.first_clears == [{"level_id": "first-steps", "price": 1200, "paid": 1200}, {"level_id": "high-and-low", "price": 1200, "paid": -1}], "Free chapters' first clears, paid or not; paid and unknown chapters are left out: " + str(history.first_clears))
	_check(history.bank == {"left": 15, "refill": 12, "cap": 36, "tail": [{"pay": 10, "turns": 36}, {"pay": 1, "turns": 64}]}, "The bank and its rules come from the server")
	var older := value.duplicate(true)
	older.erase("bank")
	older.erase("first_clears")
	_check(PollenHistory.checked(older).bank.is_empty() and PollenHistory.checked(older).first_clears.is_empty(), "A server before them sends no bank or clears")
	_check(PollenHistory.checked({"schema_version": 2.0, "entries": []}).is_empty() and PollenHistory.checked(null).is_empty(), "A history that is not the contract's reads as empty")
	_check(PollenHistory.chapter_title("relay-isles") == "The Relay Isles" and PollenHistory.stage_number("relay-isles", "garden") == 2 and PollenHistory.stage_number("relay-isles", "nowhere") == 0, "Chapter titles and stage numbers come from this build")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
