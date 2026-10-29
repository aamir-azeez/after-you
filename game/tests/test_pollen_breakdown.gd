extends SceneTree
## The Pollen results card's rows (presentation/pollen_breakdown.gd) and the
## Pollen from play page's data (services/pollen_history.gd), from receipts and
## history as the server sends them (JSON numbers arrive as floats):
## - a bank turn: base, each bonus with its own percent, the room boost and whose
##   it was (left out on a build that names no Full Journey), This turn, and a
##   lucky bloom with the bloomed total;
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

func _bank_turn() -> void:
	var rows := Breakdown.rows(_receipt(_turn()), "Maya")
	_check(_labels(rows) == ["Base = 166", "First try = +25%", "Silver pace = +5%", "Full Journey room +10%: +22 · Maya has Full Journey", "This turn = 238"], "The board's paid chapter turn: " + str(_labels(rows)))
	_check(rows.map(func(row: Dictionary) -> bool: return row.grain) == [true, false, false, false, true], "The grain sits beside the base and the total only")
	var both := Breakdown.rows(_receipt(_turn({"boost_percent": 20.0, "boost": 43.0, "total": 259.0, "boost_from": ["you", "partner"]})), "Maya")
	_check(both[3].label == "Full Journey room +20%: +43 · You and Maya have Full Journey" and both[4].value == "259", "Two subscribers: " + str(_labels(both)))
	_check(Breakdown.rows(_receipt(_turn({"boost_from": ["you"]})), "Maya")[3].label.ends_with("· You have Full Journey"), "Your own Full Journey")
	_check(Breakdown.rows(_receipt(_turn()), "a friend")[3].label.ends_with("· Your friend has Full Journey"), "A friend with no name")
	var phone := Breakdown.rows(_receipt(_turn()), "Maya", false)
	_check(_labels(phone) == ["Base = 166", "First try = +25%", "Silver pace = +5%", "This turn = 238"], "A build that names no Full Journey leaves out the boost row, not the amount: " + str(_labels(phone)))
	var plain := Breakdown.rows(_receipt(_turn({"bonuses": [], "bonus_percents": [], "bonus_percent": 0.0, "amount": 89.0, "base": 89.0, "boost_percent": 0.0, "boost": 0.0, "total": 89.0, "boost_from": []})), "")
	_check(_labels(plain) == ["Base = 89", "This turn = 89"], "A turn with no bonus or boost")
	var big := Breakdown.rows(_receipt(_turn({"base": 1200.0, "bonuses": [], "bonus_percents": [], "amount": 1200.0, "boost_percent": 0.0, "boost": 0.0, "total": 1200.0})), "")
	_check(big[0].value == "1,200", "Amounts are written with thousands commas")

func _after_bank() -> void:
	var tail := _turn({"kind": "after_bank", "base": 0.0, "bonuses": [], "bonus_percents": [], "bonus_percent": 0.0, "amount": 10.0, "boost_percent": 0.0, "boost": 0.0, "total": 10.0, "boost_from": [], "reason": "repeat"})
	_check(_labels(Breakdown.rows(_receipt(tail), "")) == ["This turn = 10", PlayerCopy.POLLEN_REPEAT], "A repeated part says why it pays a little")
	tail.reason = "bank_empty"
	_check(_labels(Breakdown.rows(_receipt(tail), "")) == ["This turn = 10", PlayerCopy.POLLEN_BANK_EMPTY], "So does an empty bank")
	tail.reason = "late"
	_check(Breakdown.rows(_receipt(tail), "")[1].label == PlayerCopy.POLLEN_LATE, "And a turn from an earlier week")
	tail.erase("base")
	tail.erase("bonus_percents")
	_check(Breakdown.detailed(_receipt(tail)), "An after-bank turn needs no base to show its rows")

func _blooms_and_clears() -> void:
	var bloomed := Breakdown.rows(_receipt(_turn({"base": 89.0, "bonuses": ["first_try", "gold_pace"], "bonus_percents": [25.0, 15.0], "bonus_percent": 40.0, "amount": 125.0, "bloom": 2.0, "bloom_extra": 125.0, "boost_percent": 0.0, "boost": 0.0, "total": 250.0, "boost_from": []})), "Sam")
	_check(_labels(bloomed) == ["Base = 89", "First try = +25%", "Gold pace = +15%", "This turn = 125", "A lucky bloom: ×2 = 250"], "The board's double bloom: " + str(_labels(bloomed)))
	var boosted := Breakdown.rows(_receipt(_turn({"base": 100.0, "bonuses": [], "bonus_percents": [], "bonus_percent": 0.0, "amount": 125.0, "bloom": 2.0, "bloom_extra": 125.0, "boost": 13.0, "total": 263.0})), "Maya")
	_check(boosted[-2].value == "138" and boosted[-1].value == "263", "A bloom's extra is never boosted: this turn 125 + 13, bloomed 263: " + str(_labels(boosted)))
	var item := Breakdown.rows(_receipt(_turn({"base": 89.0, "bonuses": ["first_try"], "bonus_percents": [25.0], "bonus_percent": 25.0, "amount": 111.0, "boost_percent": 0.0, "boost": 0.0, "total": 111.0, "boost_from": []}), {"item_bloom": {"tier": "common", "item_id": "daisy"}}), "")
	_check(item[-1].kind == "item" and item[-1].item_id == "daisy" and item[-1].tier == "common" and item[-1].label == "A lucky bloom: a new Daisy!" and Breakdown.tier_name(item[-1].tier) == "Common", "An item bloom names the new item and its tier")
	var owned := Breakdown.rows(_receipt(_turn({"boost_percent": 0.0, "boost": 0.0, "total": 216.0, "boost_from": []}), {"earned": 1216.0, "item_bloom": {"tier": "common", "pollen": 1000.0}}), "")
	_check(_labels(owned).slice(-3) == ["This turn = 216", "A lucky bloom: +1,000 Pollen", "Pollen earned = 1,216"], "A fully owned tier pays its price, and the card says what it all came to: " + str(_labels(owned)))
	var finish := _receipt(_turn({"boost_percent": 0.0, "boost": 0.0, "total": 216.0, "boost_from": []}), {"earned": 1416.0, "clears": [{"kind": "clear", "level_id": "conservatory", "amount": 1200.0, "boost_percent": 0.0, "boost": 0.0, "total": 1200.0}]})
	_check(_labels(Breakdown.rows(finish, "")).slice(-3) == ["This turn = 216", "First clear = 1,200", "Pollen earned = 1,416"], "The finishing turn and its first clear: " + str(_labels(Breakdown.rows(finish, ""))))
	var friend := PollenWallet.checked_receipt({"schema_version": 1.0, "earned": 1320.0, "balance": 1320.0, "clears": [{"kind": "clear", "total": 1320.0, "boost_percent": 10.0}, {"kind": "hardclear", "total": 1320.0, "boost_percent": 10.0}]})
	_check(_labels(Breakdown.rows(friend, "")) == ["First clear = 1,320", "First Hard clear = 1,320", "Pollen earned = 1,320"], "A friend's first clears from the room's finish: " + str(_labels(Breakdown.rows(friend, ""))))

func _older_server() -> void:
	var old := _turn()
	old.erase("base")
	old.erase("bonus_percents")
	_check(not Breakdown.detailed(_receipt(old)) and Breakdown.rows(_receipt(old), "Maya").is_empty(), "A receipt from a server without the base and percents has no rows")
	_check(PollenWallet.checked_receipt({"schema_version": 1.0, "earned": 1.0, "balance": 1.0, "clears": [], "turn": _turn({"bonus_percents": [25.0]})}).is_empty(), "Percents that do not match the bonuses refuse the receipt")
	_check(PollenWallet.checked_receipt({"schema_version": 1.0, "earned": 1.0, "balance": 1.0, "clears": [], "turn": _turn({"base": -1.0})}).is_empty(), "So does a base below zero")
	_check(Breakdown.rows({}, "").is_empty(), "No receipt, no rows")

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
