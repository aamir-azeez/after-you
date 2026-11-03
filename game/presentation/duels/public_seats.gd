extends RefCounted
## A public duel's seats as every surface draws them (boards 2 to 6): a taken
## seat is a still pip (duel_kit.gd pip, so it wears its player's look: your
## own through OwnLook, anyone else's as sent, a stranger's through
## services/duel_model.gd stranger_look) with its name under it; an open seat
## is a dashed ring with a plus, lit (solid mint) where a join would sit you. A
## pair's two seats sit together on a small dark chip, and two chips make a
## duel with "vs" between them. The list rows, the join sheets, Start a duel's
## preview, the lobby tiles and the duel page all build from here, so a seat
## looks the same everywhere. Everything is still: nothing draws per frame.
const Kit = preload("res://presentation/duels/duel_kit.gd")
const UiTokens = preload("res://presentation/ui_tokens.gd")
const ThemeRules = preload("res://presentation/control_theme.gd")
const DuelModel = preload("res://services/duel_model.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const CHIP_FILL := Color("123531")

## An open seat: a dashed ring and a plus, or a solid mint ring when lit.
class Ring extends Control:
	var lit := false
	var dashes := 18

	func _init(edge: float, is_lit: bool) -> void:
		custom_minimum_size = Vector2(edge, edge)
		lit = is_lit
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var middle := size * 0.5
		var radius := minf(size.x, size.y) * 0.5 - 2.0
		var ink := UiTokens.MINT if lit else Color(UiTokens.CREAM, 0.75)
		var width := maxf(1.5, radius * 0.08)
		if lit:
			draw_circle(middle, radius, Color(UiTokens.MINT, 0.18))
			draw_arc(middle, radius, 0.0, TAU, 48, ink, width, true)
		else:
			# A dashed ring: every other arc of `dashes` pairs.
			for index in range(dashes):
				var start := TAU * index / dashes
				draw_arc(middle, radius, start, start + TAU / dashes * 0.55, 6, ink, width, true)
		var arm := radius * 0.32
		var cross := maxf(2.0, radius * 0.12)
		draw_line(middle - Vector2(arm, 0), middle + Vector2(arm, 0), ink, cross, true)
		draw_line(middle - Vector2(0, arm), middle + Vector2(0, arm), ink, cross, true)

## One seat: {open, you, label, look} plus `name` (the words under it). A taken
## seat that is this player's is their own pip. `slot` picks the pip colour.
## With `tap`, the seat is a flat button that calls tap() (a ring to join there).
static func seat(held: Dictionary, slot: int, edge: float, lit: bool = false, tap: Callable = Callable(), font_size: int = 13) -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if held.get("open", false):
		var ring := Ring.new(edge * 0.82, lit)
		ring.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		column.add_child(ring)
	else:
		column.add_child(Kit.pip(Vector2(edge * 0.86, edge), Kit.FIRST_PIP if slot % 2 == 0 else Kit.SECOND_PIP, held.get("you", false), held.get("look", {})))
	var words := Kit.text(str(held.get("name", "")), font_size, UiTokens.CREAM if not held.get("open", false) else UiTokens.SOFT)
	words.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Kit.fitted(words, edge, edge + 26.0)
	column.add_child(words)
	if not tap.is_valid(): return column
	var button := Button.new()
	button.flat = true
	button.focus_mode = Control.FOCUS_ALL
	button.custom_minimum_size = column.get_combined_minimum_size() + Vector2(4, 4)
	button.accessibility_name = str(held.get("name", ""))
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		button.add_theme_stylebox_override(state, ThemeRules.rounded(Color(1, 1, 1, 0.06) if state.begins_with("hover") else Color.TRANSPARENT, 10))
	button.add_theme_stylebox_override("focus", ThemeRules.rounded(Color.TRANSPARENT, 10, UiTokens.CREAM))
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	button.add_child(column)
	button.pressed.connect(tap)
	return button

## A pair's two seats on their dark chip. `seats`: two seat dictionaries as seat() takes them.
## `lit`: the slots (0, 1) a join would take. `tap(slot)`: makes each open seat a button.
static func pair(seats: Array, edge: float, lit: Array = [], tap: Callable = Callable(), font_size: int = 13) -> PanelContainer:
	var chip := PanelContainer.new()
	var style := ThemeRules.rounded(CHIP_FILL, 12, Kit.PANEL_EDGE)
	ThemeRules.padded(style, 6.0, 4.0)
	chip.add_theme_stylebox_override("panel", style)
	chip.mouse_filter = Control.MOUSE_FILTER_PASS
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	line.alignment = BoxContainer.ALIGNMENT_CENTER
	chip.add_child(line)
	for slot in range(2):
		var held: Dictionary = seats[slot] if slot < seats.size() else {"open": true}
		var on_tap := tap.bind(slot) if tap.is_valid() and held.get("open", false) else Callable()
		line.add_child(seat(held, slot, edge, slot in lit, on_tap, font_size))
	return chip

## Two pairs with "vs" between them, `first` side drawn first. `lit_seats`: the seats (0 to 3,
## server order) a join would take. `tap(seat)` with the server's seat number.
static func duel(sides: Array, first: int, edge: float, lit_seats: Array = [], tap: Callable = Callable(), font_size: int = 13) -> HBoxContainer:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	line.alignment = BoxContainer.ALIGNMENT_CENTER
	line.mouse_filter = Control.MOUSE_FILTER_PASS
	for index: int in [first, 1 - first]:
		if index != first:
			var versus := Kit.text(PlayerCopy.PUBLIC_VS, font_size, UiTokens.SOFT)
			versus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			line.add_child(versus)
		var side: Dictionary = sides[index]
		var lit: Array = []
		for taken: int in lit_seats:
			if taken / 2 == index: lit.append(taken % 2)
		var on_tap := func(slot: int) -> void: tap.call(index * 2 + slot)
		line.add_child(pair(side.get("seats", []), edge, lit, on_tap if tap.is_valid() else Callable(), font_size))
	return line

## The small gold PUBLIC tag beside a public duel's title (boards 3 to 5).
static func tag(font_size: int = 14) -> PanelContainer:
	var box := PanelContainer.new()
	box.name = "PublicTag"
	var style := ThemeRules.rounded(UiTokens.SOLO, 8)
	ThemeRules.padded(style, 9.0, 1.0)
	box.add_theme_stylebox_override("panel", style)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(Kit.text(PlayerCopy.PUBLIC_TAG, font_size, UiTokens.INK, true))
	return box

## A list row's seats as seat() draws them: each with its name ("You", a shown name,
## "A player" or "Open") and a stranger's look as DuelModel.stranger_look allows.
static func row_seats(row: Dictionary) -> Array:
	var sides: Array = []
	for side: Dictionary in row.get("sides", []):
		var seats: Array = []
		for held: Dictionary in side.get("seats", []):
			var named := PlayerCopy.PUBLIC_OPEN if held.open else PlayerCopy.DUEL_YOU if held.get("you", false) else str(held.label) if not str(held.get("label", "")).is_empty() else PlayerCopy.PUBLIC_A_PLAYER
			seats.append({"open": held.open, "you": held.get("you", false), "name": named, "look": {} if held.open or held.get("you", false) else DuelModel.stranger_look(held.get("look", {}))})
		sides.append({"seats": seats})
	return sides

## A public duel view's side as seat() draws it: names from services/duel_model.gd seat_name, looks from its looks().
static func view_seats(view: Dictionary, index: int, me: String, name_of: Callable) -> Array:
	var looks := DuelModel.looks(view, index)
	var seats: Array = []
	for slot in range(2):
		var held := DuelModel.seat(view, index, slot)
		var own: bool = held.get("you", false) or view.sides[index].members[slot] == me
		seats.append({"open": held.get("open", false), "you": own, "name": DuelModel.seat_name(view, index, slot, name_of), "look": looks[slot]})
	return seats
