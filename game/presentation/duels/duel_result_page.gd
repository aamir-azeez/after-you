extends "res://presentation/duels/duel_page_base.gd"
## A duel's result (duels-concepts OWNER-CHOSEN-result, without its Full
## Journey note): the title, both pairs' cards with their whole times and
## dots (Winner on the winning pair), the gap, and Pollen earned from this
## duel's real pay: the turns' own pay, the duel bonus and the room boost as
## the wallet credited them, and the win bonus (services/duel_model.gd
## pay_lines). The card hides while Pollen is off or nothing was paid. While
## the runs are still checked, the cards show the times under "Checking both
## runs". Watch replay opens the pair's room, which plays its finished run.
const DuelModel = preload("res://services/duel_model.gd")
const Registry = preload("res://services/chapter_registry.gd")
const RoomChapterTitle = preload("res://services/room_chapter_title.gd")
const PollenMark = preload("res://presentation/kit/pollen_mark.gd")
const PLAY_ICON = preload("res://assets/ui/play-circle.svg")
const PollenMoney = preload("res://services/pollen_money.gd")
const Backdrop = preload("res://presentation/duels/duel_result_backdrop.gd")
const Runs = preload("res://services/leaderboard_runs.gd")

signal watch_requested(view: Dictionary, control: Control)

var me := ""
var name_of: Callable
var view: Dictionary = {}
## services/duels_client.gd duel(): the pay and win bonus, {} when none.
var pay: Dictionary = {}
var win_bonus: Dictionary = {}
## Whether this build names Full Journey (services/pollen_surfaces.gd), and shows Pollen at all.
var show_boost := true
var show_pollen := true
var _column: VBoxContainer
var _backdrop: Control

func page_name() -> String: return "DuelResult"

func backdrop() -> Control:
	_backdrop = Backdrop.new()
	return _backdrop

func show_result(next: Dictionary, paid: Dictionary = {}, bonus: Dictionary = {}) -> void:
	view = next
	pay = paid
	win_bonus = bonus
	if is_instance_valid(_column): _render()

func _build() -> void:
	_column = VBoxContainer.new()
	_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_column.alignment = BoxContainer.ALIGNMENT_CENTER
	_column.add_theme_constant_override("separation", 10)
	body.add_child(_column)
	_render()

func _render() -> void:
	Kit.clear(_column)
	if view.is_empty(): return
	var key := str(view.chapter)
	set_title("", "")
	if is_instance_valid(_backdrop): _backdrop.show_chapter(_picture_key())
	var title := Kit.text(DuelModel.result_title(view, name_of), 50 if not compact else 42, UiTokens.CREAM, true)
	title.name = "DuelResultHeadline"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_column.add_child(title)
	var chapter := Kit.text(RoomChapterTitle.title(key, str(Registry.descriptor(key).get("title", key))), 24, UiTokens.SOFT, true)
	chapter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_column.add_child(chapter)
	var cards := HBoxContainer.new()
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	cards.add_theme_constant_override("separation", 18)
	var result: Variant = view.result
	for index: int in [view.mine, 1 - view.mine]:
		var won: bool = result is Dictionary and ((result.outcome == "won" and index == view.mine) or (result.outcome == "lost" and index != view.mine))
		cards.add_child(_card(index, won))
	_column.add_child(cards)
	var line := DuelModel.result_line(view)
	if not line.is_empty():
		var gap := Kit.text(line, 22, UiTokens.SOFT, true)
		gap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_column.add_child(gap)
	var paid := DuelModel.pay_lines(pay, win_bonus, show_boost)
	if show_pollen and not paid.lines.is_empty(): _column.add_child(_pollen(paid))
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 22)
	if str(view.sides[view.mine].get("room_id", "")) != "":
		var watch := Kit.button(PlayerCopy.DUEL_WATCH, Callable(), false, 56)
		watch.name = "DuelWatch"
		Kit.icon_on(watch, PLAY_ICON, true, 34)
		watch.custom_minimum_size.x = 400
		watch.pressed.connect(func(): watch_requested.emit(view, watch))
		buttons.add_child(watch)
	var back := Kit.button(PlayerCopy.DUEL_BACK_TO_DUELS, close, true, 56)
	back.name = "DuelBackToDuels"
	back.custom_minimum_size.x = 400
	back.add_theme_font_size_override("font_size", 24)
	buttons.add_child(back)
	_column.add_child(buttons)

## The bundled chapter whose picture shows behind the result: the board's own version, as duels_flow.gd opens it.
func _picture_key() -> String:
	var key := Runs.chapter_of(str(view.get("board", "")))
	return key if not key.is_empty() else str(view.chapter)

func _card(index: int, won: bool) -> Control:
	var card := Kit.panel("ResultSide%d" % index, Kit.PANEL_FILL, Kit.HIGHLIGHT_EDGE if won else Kit.PANEL_EDGE, 20, 16.0)
	card.custom_minimum_size.x = 400 if not compact else 340
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	card.add_child(column)
	var head := HBoxContainer.new()
	if won: head.add_child(Kit.pill(PlayerCopy.DUEL_WINNER, true, 20))
	var who := Kit.text(DuelModel.pair_title(view, index, name_of), 26, UiTokens.CREAM, true)
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	who.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.add_child(who)
	column.add_child(head)
	var middle := HBoxContainer.new()
	middle.add_theme_constant_override("separation", 14)
	var pips := Kit.pips(Vector2(62, 74), index == view.mine)
	if index == 1 and view.kind == "ghost": pips.modulate = Color(1, 1, 1, 0.55)
	middle.add_child(pips)
	var time := Kit.text(DuelModel.time_text(DuelModel.ticks(view, index)), 54 if not compact else 46, UiTokens.CREAM, true)
	time.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	time.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	middle.add_child(time)
	column.add_child(middle)
	var steps := DuelModel.steps(view, index)
	column.add_child(Kit.dots_within(steps.x, steps.y, 340.0, 22.0))
	return card

## The cream Pollen earned card: each line and the total.
func _pollen(paid: Dictionary) -> Control:
	var card := Kit.panel("DuelPollen", UiTokens.CREAM, Color.TRANSPARENT, 22, 18.0)
	card.custom_minimum_size.x = 560
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	card.add_child(column)
	column.add_child(Kit.text(PlayerCopy.DUEL_POLLEN_EARNED, 26, UiTokens.INK, true))
	for item: Array in paid.lines:
		column.add_child(_line(str(item[0]), ("+" if column.get_child_count() > 1 else "") + PollenMoney.grouped(int(item[1])), 19, false))
	var rule := ColorRect.new()
	rule.color = Color(UiTokens.INK, 0.35)
	rule.custom_minimum_size.y = 1
	column.add_child(rule)
	# A little air under the rule, so the total's row sits clear of it.
	var air := Control.new()
	air.custom_minimum_size.y = 6
	column.add_child(air)
	column.add_child(_line(PlayerCopy.DUEL_PAY_TOTAL, PollenMoney.grouped(int(paid.total)), 26, true))
	return card

func _line(label: String, amount: String, font_size: int, total: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var name_label := Kit.text(label, font_size, UiTokens.INK, total)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	if total: row.add_child(PollenMark.beside(font_size))
	row.add_child(Kit.text(amount, font_size, UiTokens.INK, true))
	return row
