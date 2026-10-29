extends RefCounted
## "Your monthly Pollen arrived": the card Home shows once for each Full Journey
## instalment the server paid (services/pollen_grant.gd pending()), drawn as
## pollen-concepts board 3 has it: the Pollen bag beside the title, which month
## of the ladder arrived and what next month pays, the big "+4,500" with the
## grain, then Open the Wardrobe and Done. It sits right of the island over a
## light dim, so both pips show behind it making their joy face until it closes.
## Plain and quiet: no countdown, no "don't lose" wording, nothing to buy, and
## never on a build that names no Full Journey (services/pollen_surfaces.gd
## full_journey_visible, asked by Main).
##
## It is an InGameModal, so Android Back, the focus order and Main's "a card is
## up" checks treat it as every other card. The board has no X: Done and Back
## close it.
const InGameModal = preload("res://presentation/in_game_modal.gd")
const ControlTheme = preload("res://presentation/control_theme.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const PollenMoney = preload("res://services/pollen_money.gd")
const FullJourneyArt = preload("res://presentation/full_journey_art.gd")
const SpiritLook = preload("res://presentation/spirit_look.gd")
const UiTokens = preload("res://presentation/ui_tokens.gd")
const HANGER = preload("res://assets/ui/hanger.svg")

const LIFETIME_KEY := "grant:lifetime"
const WIDTH := 540.0
## The dim behind the card: light enough that the island and the pips read.
const DIM := 0.26
## The card sits this far from the screen's right edge, right of the island
## and its pips, as drawn. A screen too narrow for that centres it.
const RIGHT_MARGIN := 28.0
const AMOUNT := Color("f8d77a")
const AMOUNT_SIZE := 56
const TITLE_SIZE := 34
const BAG := 74.0
## The pips keep their joy face while the card is up: a timed reaction this
## long, which a doze never takes over, cleared as the card goes.
const JOY_SECONDS := 3600.0

## The line under the title: "From Full Journey, month 1 of your ladder.\nNext month: 4,750."
static func month_line(card: Dictionary) -> String:
	if str(card.get("key", "")) == LIFETIME_KEY or int(card.get("months", 0)) < 1: return PlayerCopy.POLLEN_GRANT_LIFETIME
	return PlayerCopy.POLLEN_GRANT_MONTH % [PollenMoney.grouped(int(card.months)), PollenMoney.grouped(int(card.get("next", 0)))]

## "+4,500".
static func amount_text(amount: int) -> String:
	return "+" + PollenMoney.grouped(amount)

## Opens the card for `card` ({key, amount, next, top, months}) over `parent`.
## `spirits`: Home's pips, which make their joy face until it closes.
## `wardrobe`: opens the Wardrobe; without one the card offers Done alone.
static func open(parent: Control, card: Dictionary, spirits: Array = [], wardrobe: Callable = Callable(), opener: Control = null) -> Control:
	var modal := InGameModal.open(parent, "PollenGrantCard", PlayerCopy.POLLEN_GRANT_TITLE, month_line(card), opener) as InGameModal
	modal.widen(WIDTH)
	_restyle(modal)
	var amount := HBoxContainer.new()
	amount.name = "PollenGrantAmount"
	amount.add_theme_constant_override("separation", 14)
	amount.add_child(FullJourneyArt.grain(AMOUNT_SIZE * 0.82))
	var figure := modal.label(amount_text(int(card.get("amount", 0))), AMOUNT_SIZE, amount)
	figure.name = "PollenGrantFigure"
	figure.autowrap_mode = TextServer.AUTOWRAP_OFF
	figure.add_theme_font_override("font", modal.heading_font)
	figure.add_theme_color_override("font_color", AMOUNT)
	modal.content.add_child(amount)
	_add_actions(modal, wardrobe)
	_cheer(modal, spirits)
	return modal

## The board's header: the bag before the titles, a bigger title that wraps,
## no X; the dim lightened and the card moved right of the island.
static func _restyle(modal: InGameModal) -> void:
	var bag := FullJourneyArt.bag(BAG)
	bag.name = "PollenGrantBag"
	modal.header.add_child(bag)
	modal.header.move_child(bag, 0)
	modal.header.add_theme_constant_override("separation", 18)
	modal.title_label.add_theme_font_size_override("font_size", TITLE_SIZE)
	modal.title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if modal.subtitle_label != null: modal.subtitle_label.add_theme_font_size_override("font_size", 18)
	var close := modal.header.find_child("ModalClose", false, false) as Control
	if close != null: close.visible = false
	for child: Node in modal.get_children():
		if child is ColorRect: (child as ColorRect).color.a = DIM
	_place(modal)
	modal.resized.connect(_place.bind(modal))

## Against the right edge, clear of the island, when the screen has room for
## the island beside it; else centred.
static func _place(modal: InGameModal) -> void:
	var centre := modal.find_child("ModalCenter", false, false) as Control
	if centre == null: return
	var width := modal.size.x if modal.size.x > 0.0 else modal.get_viewport_rect().size.x
	if width <= 0.0: return
	# The centre container centres the card, so its left anchor sits as far
	# left of the card's middle as the right edge is right of it.
	var middle := width - RIGHT_MARGIN - WIDTH * 0.5
	centre.anchor_left = clampf((2.0 * middle - width) / width, 0.0, 1.0) if width >= WIDTH * 2.0 else 0.0

static func _add_actions(modal: InGameModal, wardrobe: Callable) -> void:
	var gap := Control.new()
	gap.custom_minimum_size.y = 4
	modal.content.add_child(gap)
	var row := HBoxContainer.new()
	row.name = "PollenGrantActions"
	row.add_theme_constant_override("separation", 14)
	modal.content.add_child(row)
	if wardrobe.is_valid():
		var open := Button.new()
		open.name = "PollenGrantWardrobe"
		open.text = PlayerCopy.POLLEN_GRANT_WARDROBE
		open.custom_minimum_size.y = 54
		open.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		open.icon = HANGER
		# The icon follows the text: cream on teal, ink on a hovered or pressed cream fill.
		for state: String in ["normal", "focus"]: open.add_theme_color_override("icon_%s_color" % state, UiTokens.CREAM)
		for state: String in ["hover", "pressed", "hover_pressed"]: open.add_theme_color_override("icon_%s_color" % state, UiTokens.INK)
		ControlTheme.secondary(open)
		ControlTheme.center_icon_label(open)
		open.pressed.connect(func() -> void:
			modal.close(false)
			wardrobe.call())
		row.add_child(open)
	var done := Button.new()
	done.name = "PollenGrantDone"
	done.text = PlayerCopy.POLLEN_GRANT_DONE
	done.custom_minimum_size.y = 54
	done.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	done.pressed.connect(func() -> void: modal.close())
	row.add_child(done)
	modal.refresh_focus_order()

## Home's pips make their joy face while the card is up, and stop when it goes,
## however it goes (Done, Back, Open the Wardrobe or the page leaving).
static func _cheer(modal: InGameModal, spirits: Array) -> void:
	var cheered: Array = []
	for spirit: Variant in spirits:
		if spirit is Node3D and is_instance_valid(spirit) and (spirit as Node3D).visible and spirit.has_method("show_expression"):
			spirit.show_expression(SpiritLook.JOY, JOY_SECONDS)
			cheered.append(spirit)
	if cheered.is_empty(): return
	modal.tree_exiting.connect(func() -> void:
		for spirit: Variant in cheered:
			if is_instance_valid(spirit) and spirit.expression_target() == SpiritLook.JOY: spirit.show_expression(SpiritLook.NORMAL, 0.0))
