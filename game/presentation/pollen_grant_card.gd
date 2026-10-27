extends RefCounted
## "Your monthly Pollen arrived": the card Home shows once for each Full Journey
## instalment the server paid (services/pollen_grant.gd pending()). It says what
## arrived and the loyalty ladder: what next month pays and the top step. Plain
## and quiet: no countdown, no "don't lose" wording, nothing to buy, and never
## on a build that hides paid content.
const InGameModal = preload("res://presentation/in_game_modal.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const PollenMoney = preload("res://services/pollen_money.gd")

## "+4,750 Pollen from Full Journey".
static func amount_line(amount: int) -> String:
	return PlayerCopy.POLLEN_GRANT_AMOUNT % PollenMoney.grouped(amount)

## "Next month: 5,000 · Top step: 12,000".
static func ladder_line(next: int, top: int) -> String:
	return PlayerCopy.POLLEN_GRANT_LADDER % [PollenMoney.grouped(next), PollenMoney.grouped(top)]

## Opens the card for `card` ({amount, next, top}) over `parent`; Got it closes it.
static func open(parent: Control, card: Dictionary, opener: Control = null) -> Control:
	var modal := InGameModal.open(parent, "PollenGrantCard", PlayerCopy.POLLEN_GRANT_TITLE, amount_line(int(card.get("amount", 0))), opener) as InGameModal
	var ladder := modal.label(ladder_line(int(card.get("next", 0)), int(card.get("top", 0))))
	ladder.name = "PollenGrantLadder"
	var got_it := Button.new()
	got_it.name = "PollenGrantGotIt"
	got_it.text = PlayerCopy.POLLEN_GRANT_OK
	got_it.custom_minimum_size.y = 54
	got_it.pressed.connect(func() -> void: modal.close())
	modal.content.add_child(got_it)
	modal.refresh_focus_order()
	return modal
