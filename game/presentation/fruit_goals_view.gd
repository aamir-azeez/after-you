extends RefCounted
## The Fruits for playing together card on the Fruits page (Fruits board 6a):
## each goal in the server's order. A paid one has the round plum badge with
## the Fruit, its place (the chapter it was paid on) and "✓ +10"; one still to
## reach has its Fruits in a dashed circle and, when its goal is above 1, a dot
## per step with the steps done filled. A goal the server does not count yet
## (`live` false: the two keepsake goals) shows greyed, with no dots. The card
## lists the first FEW until the player opens them all with the link under it
## ("All 15 goals, 260 Fruits in all", the server's count and sum), which then
## closes them again.
## Pure drawing: presentation/fruits_page.gd gives it the card's column (already
## empty) and the data; it keeps nothing. Its only input is the link.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const ControlTheme = preload("res://presentation/control_theme.gd")
const ShopKit = preload("res://presentation/kit/shop_kit.gd")
const CurrencyMark = preload("res://presentation/kit/currency_mark.gd")
const Orchard = preload("res://presentation/kit/orchard_surface.gd")
const DashedBox = preload("res://presentation/kit/dashed_box.gd")
const PollenMoney = preload("res://services/pollen_money.gd")
const PollenHistory = preload("res://services/pollen_history.gd")
const CHECK := preload("res://assets/ui/settings/check.svg")
const CHEVRON := preload("res://assets/ui/social/chevron-right.svg")

const INK := ShopKit.INK
const SOFT_INK := Color("4e6660")
const PLUM_INK := Color("7a3a64")
const DOT_EMPTY := Color("dcd3c0")
const RING := Color("b8ad95")
const BADGE := 50.0
## Goals listed before the link opens them all.
const FEW := 6
const ROW_SIZE := 18
const NOTE_SIZE := 14
## A goal the server does not count yet.
const GREYED := 0.42

## Fills `column` from {achievements (services/fruit_wallet.gd part), all (every
## goal shows)}; `toggle` runs on the link.
static func fill(column: VBoxContainer, model: Dictionary, title_font: Font, toggle: Callable) -> void:
	var title := ShopKit.text(PlayerCopy.FRUIT_GOALS_TITLE, 26, INK, title_font if title_font != null else ShopKit.heading_font())
	title.name = "FruitGoalsTitle"
	column.add_child(title)
	var goals: Array = model.get("achievements", [])
	var every := bool(model.get("all", false)) or goals.size() <= FEW
	var shown := goals if every else goals.slice(0, FEW)
	for index in range(shown.size()):
		if index > 0: column.add_child(_rule())
		column.add_child(row(shown[index]))
	if goals.size() <= FEW: return
	var spare := Control.new()
	spare.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spare.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(spare)
	column.add_child(_link(goals, bool(model.get("all", false)), toggle))

## One goal's row.
static func row(goal: Dictionary) -> Control:
	var line := HBoxContainer.new()
	line.name = "FruitGoal_" + str(goal.id)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", 16)
	var paid := bool(goal.get("paid", false))
	var live := bool(goal.get("live", true))
	line.add_child(_paid_badge() if paid else _amount_badge(int(goal.fruits)))
	var words := VBoxContainer.new()
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	words.add_theme_constant_override("separation", 2)
	line.add_child(words)
	var named := ShopKit.text(str(PlayerCopy.FRUIT_GOALS.get(str(goal.id), "")), ROW_SIZE, INK)
	named.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.add_child(named)
	var place := PollenHistory.chapter_title(str(goal.get("level_id", "")))
	if paid and not place.is_empty():
		var detail := ShopKit.text(place, NOTE_SIZE, SOFT_INK)
		detail.name = "FruitGoalPlace"
		words.add_child(detail)
	elif not paid and live and int(goal.get("goal", 1)) > 1:
		words.add_child(Steps.new(int(goal.goal), int(goal.get("progress", 0))))
	if paid: line.add_child(_paid_amount(int(goal.fruits)))
	if not live and not paid: line.modulate.a = GREYED
	return line

## The round plum badge with the Fruit in it.
static func _paid_badge() -> Control:
	var badge := PanelContainer.new()
	badge.name = "FruitGoalPaid"
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.custom_minimum_size = Vector2(BADGE, BADGE)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var disc := Orchard.flat(int(BADGE / 2.0), Orchard.PLUM_DARK, Orchard.PLUM_LIGHT)
	disc.shadow_color = Color(0, 0, 0, 0.18)
	disc.shadow_size = 4
	disc.shadow_offset = Vector2(0, 2)
	badge.add_theme_stylebox_override("panel", disc)
	var centre := CenterContainer.new()
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(centre)
	centre.add_child(CurrencyMark.make(CurrencyMark.FRUITS, 30.0))
	return badge

## The Fruits a goal pays, in a dashed circle.
static func _amount_badge(fruits: int) -> Control:
	var badge := PanelContainer.new()
	badge.name = "FruitGoalAmount"
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.custom_minimum_size = Vector2(BADGE, BADGE)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var ring: StyleBox = DashedBox.new()
	ring.radius = BADGE / 2.0
	ring.color = RING
	ring.dash = 4.0
	ring.gap = 3.0
	badge.add_theme_stylebox_override("panel", ring)
	var amount := ShopKit.text(PollenMoney.grouped(fruits), 17, SOFT_INK, ShopKit.bold_font())
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	amount.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_child(amount)
	return badge

## "✓ +10" in plum.
static func _paid_amount(fruits: int) -> Control:
	var paid := HBoxContainer.new()
	paid.name = "FruitGoalPaidAmount"
	paid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	paid.add_theme_constant_override("separation", 6)
	var tick := TextureRect.new()
	tick.texture = CHECK
	tick.modulate = PLUM_INK
	tick.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tick.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tick.custom_minimum_size = Vector2(16, 16)
	tick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paid.add_child(tick)
	paid.add_child(ShopKit.text(PlayerCopy.FRUIT_GOAL_PAID % PollenMoney.grouped(fruits), 16, PLUM_INK, ShopKit.bold_font()))
	return paid

## "All 15 goals, 260 Fruits in all ›", or "Fewer goals" while all show.
static func _link(goals: Array, every: bool, toggle: Callable) -> Button:
	var total := 0
	for goal: Dictionary in goals: total += int(goal.fruits)
	var words := PlayerCopy.FRUIT_GOALS_FEWER if every else PlayerCopy.FRUIT_GOALS_ALL % [goals.size(), PollenMoney.grouped(total)]
	var content := HBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	content.add_child(ShopKit.text(words, 18, INK, ShopKit.bold_font()))
	var chevron := TextureRect.new()
	chevron.texture = CHEVRON
	chevron.modulate = INK
	chevron.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	chevron.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	chevron.custom_minimum_size = Vector2(16, 16)
	chevron.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chevron.rotation_degrees = -90.0 if every else 0.0
	chevron.pivot_offset = Vector2(8, 8)
	content.add_child(chevron)
	var link := ShopKit.content_button(content, 44.0)
	link.name = "FruitGoalsAll"
	link.accessibility_name = words
	link.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	for state: String in ["normal", "hover", "pressed", "hover_pressed"]:
		link.add_theme_stylebox_override(state, ControlTheme.rounded(Color(INK, 0.06 if state == "hover" else 0.1 if state.contains("pressed") else 0.0), 10))
	link.add_theme_stylebox_override("focus", ControlTheme.rounded(Color.TRANSPARENT, 10, INK))
	link.pressed.connect(func() -> void: if toggle.is_valid(): toggle.call())
	return link

static func _rule() -> ColorRect:
	var line := ColorRect.new()
	line.color = Color(0, 0, 0, 0.08)
	line.custom_minimum_size.y = 1
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line

## A goal's steps: a dot each, the steps done in plum.
class Steps extends Control:
	const SIDE := 10.0
	const GAP := 4.0
	var goal := 0
	var done := 0

	func _init(count: int, progress: int) -> void:
		name = "FruitGoalSteps"
		goal = clampi(count, 0, 32)
		done = clampi(progress, 0, goal)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		custom_minimum_size = Vector2(goal * (SIDE + GAP) - GAP, SIDE + 4.0)
		resized.connect(queue_redraw)

	func filled() -> int:
		return done

	func _draw() -> void:
		for index in range(goal):
			draw_circle(Vector2(index * (SIDE + GAP) + SIDE * 0.5, size.y * 0.5), SIDE * 0.5, PLUM_INK if index < done else DOT_EMPTY, true, -1.0, true)
