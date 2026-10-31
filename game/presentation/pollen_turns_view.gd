extends RefCounted
## The Turns with friends card on Pollen from play (pollen board 7b): the turn
## bank (turns left, how full it is, the Monday refill and the cap; when empty,
## what turns still earn, in the server's numbers), then the newest turns, each
## with its chapter's picture, its bonuses or why it paid a little, a lucky
## bloom, its Pollen and when it was played. With few turns or none, the room
## left under them shows the player's own pip at rest among a few grains
## (presentation/pollen_play_spare.gd), only while that room is really spare.
## Pure drawing: presentation/pollen_play_page.gd gives it the card's column
## (already empty) and the data; it keeps nothing and takes no input.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const Parts = preload("res://presentation/pollen_play_parts.gd")
const Spare = preload("res://presentation/pollen_play_spare.gd")
const ShopKit = preload("res://presentation/kit/shop_kit.gd")
const PollenHistory = preload("res://services/pollen_history.gd")
const PollenResultLine = preload("res://presentation/pollen_result_line.gd")
const BreakdownView = preload("res://presentation/pollen_breakdown_view.gd")
const Breakdown = preload("res://presentation/pollen_breakdown.gd")
const WhenLabel = preload("res://presentation/when_label.gd")

const ROW_SIZE := Parts.ROW_SIZE

## Fills `column` from {history (services/pollen_history.gd), pictures (bool:
## rows show their chapter's picture; off where the card is narrow)}.
static func fill(column: VBoxContainer, model: Dictionary, title_font: Font) -> void:
	Parts.heading(column, PlayerCopy.POLLEN_TURNS_TITLE, PlayerCopy.POLLEN_TURNS_NOTE, title_font)
	var history: Dictionary = model.get("history", {})
	_bank(column, history.get("bank", {}), title_font)
	var turns: Array = history.get("turns", [])
	if turns.is_empty():
		var none := Parts.wrapped(PlayerCopy.POLLEN_TURNS_NONE, ROW_SIZE, Parts.SOFT_INK)
		none.name = "PollenTurnsNone"
		column.add_child(none)
	var pictures := bool(model.get("pictures", true))
	for index in range(turns.size()):
		if index > 0: column.add_child(Parts.rule())
		column.add_child(_row(turns[index], index, pictures))
	column.add_child(Spare.new())

## The turn bank: how many full rate turns are left, how full it is, and its rules.
static func _bank(column: VBoxContainer, bank: Dictionary, title_font: Font) -> void:
	if bank.is_empty(): return
	var left := int(bank.left)
	var number := Parts.big(str(left), title_font)
	number.name = "PollenBankLeft"
	var words := PlayerCopy.POLLEN_BANK_COUNT_ONE if left == 1 else PlayerCopy.POLLEN_BANK_COUNT
	var refill := PlayerCopy.POLLEN_BANK_EMPTY_LINE if left == 0 else PlayerCopy.POLLEN_BANK_REFILL % int(bank.refill)
	column.add_child(Parts.summary("PollenBank", number, words, left, int(bank.cap), refill, PlayerCopy.POLLEN_BANK_CAP % int(bank.cap)))
	if left == 0 and not (bank.tail as Array).is_empty():
		var tail := Parts.wrapped(tail_line(bank), 15, Parts.SOFT_INK)
		tail.name = "PollenBankTail"
		column.add_child(tail)

## What turns earn once the bank is empty, in the server's numbers.
static func tail_line(bank: Dictionary) -> String:
	var steps := PackedStringArray()
	for step: Dictionary in bank.get("tail", []):
		steps.append((PlayerCopy.POLLEN_TAIL_FIRST if steps.is_empty() else PlayerCopy.POLLEN_TAIL_STEP) % [int(step.pay), int(step.turns)])
	return PlayerCopy.POLLEN_TAIL % [PlayerCopy.POLLEN_TAIL_THEN.join(steps), int(bank.get("refill", 0))]

## One turn: its chapter's picture, where, what added to it, its Pollen and when.
static func _row(turn: Dictionary, index: int, pictures: bool) -> Control:
	var row := HBoxContainer.new()
	row.name = "PollenTurnRow%d" % index
	row.add_theme_constant_override("separation", 12)
	var art := Parts.picture(str(turn.level_id)) if pictures else null
	if art != null: row.add_child(art)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	words.add_theme_constant_override("separation", 0)
	row.add_child(words)
	words.add_child(Parts.wrapped(place(turn), ROW_SIZE, Parts.INK))
	var note := turn_note(turn)
	if not note.is_empty(): words.add_child(Parts.wrapped(note, Parts.NOTE_SIZE, Parts.SOFT_INK))
	# The Pollen with a bloom's tag after it, and when the turn was played under it.
	var paid := VBoxContainer.new()
	paid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	paid.add_theme_constant_override("separation", 0)
	row.add_child(paid)
	var line := HBoxContainer.new()
	line.alignment = BoxContainer.ALIGNMENT_END
	line.add_theme_constant_override("separation", 8)
	paid.add_child(line)
	line.add_child(ShopKit.amount(int(turn.amount), ROW_SIZE, Parts.INK))
	if int(turn.get("bloom", 1)) > 1:
		line.add_child(BreakdownView.tag(PlayerCopy.POLLEN_BLOOM_SHORT % int(turn.bloom), func() -> Control: return PollenResultLine.Flower.new()))
	var when := WhenLabel.text(floori(int(turn.get("at", 0)) / 1000.0))
	if not when.is_empty():
		var said := Parts.text(when, Parts.NOTE_SIZE, Parts.SOFT_INK)
		said.name = "PollenTurnWhen"
		said.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		paid.add_child(said)
	return row

## "The Wishing Well, stage 1".
static func place(turn: Dictionary) -> String:
	var title := PollenHistory.chapter_title(str(turn.level_id))
	var stage := PollenHistory.stage_number(str(turn.level_id), str(turn.stage_id))
	return PlayerCopy.POLLEN_TURN_PLACE % [title, stage] if stage > 0 else title

## A turn's small line: its bonuses ("First try · gold pace"), or why it paid a little.
static func turn_note(turn: Dictionary) -> String:
	match str(turn.get("reason", "")):
		"repeat": return PlayerCopy.POLLEN_TURN_REPEAT
		"bank_empty": return PlayerCopy.POLLEN_TURN_BANK_EMPTY
		"late": return PlayerCopy.POLLEN_TURN_LATE
	var names := PackedStringArray()
	for bonus: String in turn.get("bonuses", []):
		var named: String = Breakdown.BONUS_NAMES[bonus]
		names.append(named if names.is_empty() else named.to_lower())
	return PlayerCopy.POLLEN_TURN_BONUS_JOIN.join(names)
