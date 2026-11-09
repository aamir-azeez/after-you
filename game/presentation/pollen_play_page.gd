extends Control
## The Pollen page (pollen board 7b, titled "Pollen"): what play has earned and
## what it still can. A header with the coral back square, the title and the
## balance chip (its plus opens the Pollen store);
## then two cards, each drawn by its own view:
## - Turns with friends (presentation/pollen_turns_view.gd): the turn bank and
##   the newest turns;
## - First chapter clears (presentation/pollen_clears_view.gd): what first
##   clears still pay, and each free chapter, paid or not.
## While Fruits show and the server sent Sunshine, the Turns card ends with the
## Sunshine card (presentation/sunshine_card.gd, Fruits board 7), held below
## its scrolling list so a long list never hides it.
## Receipts live behind the Pollen store's Previous purchases, not here.
## presentation/pollen_play_flow.gd reads the data and calls render(); this
## script only draws it. Each card scrolls on its own. No timers, no countdown.
## The frame (shade, header, chip slot, scrolling cards) is the kit's
## (kit/page_frame.gd), shared with the Fruits page.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const Frame = preload("res://presentation/kit/page_frame.gd")
const Parts = preload("res://presentation/pollen_play_parts.gd")
const TurnsView = preload("res://presentation/pollen_turns_view.gd")
const ClearsView = preload("res://presentation/pollen_clears_view.gd")
const SunshineCard = preload("res://presentation/sunshine_card.gd")

const CARD := Frame.CARD
## Room kept for a card's scroll bar while it shows, so a long list's amounts stay clear of it.
const GUTTER := Frame.GUTTER

signal back_pressed
signal retry_pressed
## The Sunshine card's price button (its button, for the card that opens over it).
signal sunshine_buy_pressed(button: Button)

var back_button: Button
var title_font: Font
var _chip_slot: HBoxContainer
var _title_label: Label
var _turns: VBoxContainer
var _clears: VBoxContainer
## Under the Turns card's list: the Sunshine card, or nothing.
var _turns_foot: VBoxContainer

func _init(heading_font: Font = null) -> void:
	title_font = heading_font
	name = "PollenPlayPage"
	var frame := Frame.build(self, {"back_name": "PollenPlayBack", "back_words": PlayerCopy.POLLEN_PLAY_BACK, "title": PlayerCopy.POLLEN_PLAY_TITLE,
		"title_name": "PollenPlayTitle", "subtitle": PlayerCopy.POLLEN_PLAY_SUBTITLE}, title_font, func() -> void: back_pressed.emit())
	back_button = frame.back
	_chip_slot = frame.chip_slot
	_title_label = frame.title
	# The Turns card holds the Sunshine card under its list (_turns_foot).
	var turns := VBoxContainer.new()
	turns.add_theme_constant_override("separation", 12)
	Frame.cream_card(frame.body, "PollenTurnsCard").add_child(turns)
	_turns = Frame.scrolling(turns)
	_turns_foot = VBoxContainer.new()
	_turns_foot.name = "PollenTurnsCardFoot"
	turns.add_child(_turns_foot)
	_clears = Frame.scrolling(Frame.cream_card(frame.body, "PollenClearsCard"))

## Draws `model` from the flow: {chip (kit/pollen_chip.gd, or null before a
## balance is known), full_journey, status ("" when the history is in), retry,
## history (services/pollen_history.gd), fruits (Fruits show), sunshine ({}
## or services/fruit_wallet.gd sunshine), sunshine_buyable}.
func render(model: Dictionary) -> void:
	Frame.show_chip(_chip_slot, model.get("chip"))
	Frame.clear([_turns, _clears, _turns_foot])
	var status := str(model.get("status", ""))
	var history: Dictionary = model.get("history", {})
	if not status.is_empty():
		Parts.heading(_turns, PlayerCopy.POLLEN_TURNS_TITLE, PlayerCopy.POLLEN_TURNS_NOTE, title_font)
		Parts.heading(_clears, PlayerCopy.POLLEN_CLEARS_TITLE, PlayerCopy.POLLEN_CLEARS_NOTE, title_font)
		Frame.status(_turns, status, Parts.SOFT_INK, "PollenPlay", PlayerCopy.POLLEN_PLAY_RETRY, (func() -> void: retry_pressed.emit()) if bool(model.get("retry", false)) else Callable())
		return
	var fruits := bool(model.get("fruits", false))
	var cards := {"history": history, "full_journey": bool(model.get("full_journey", true)), "fruits": fruits}
	TurnsView.fill(_turns, cards, title_font)
	ClearsView.fill(_clears, cards, title_font)
	var sunshine: Dictionary = model.get("sunshine", {})
	if fruits and not sunshine.is_empty():
		var card := SunshineCard.make(sunshine, bool(model.get("sunshine_buyable", false)), title_font)
		card.buy_pressed.connect(func(button: Button) -> void: sunshine_buy_pressed.emit(button))
		_turns_foot.add_child(card)
