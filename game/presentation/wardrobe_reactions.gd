extends VBoxContainer
## The Wardrobe's Reactions chip (faces board 4, mocks 1 to 3): the slot row,
## "Your reactions", in its tinted panel with the heart at its end, over every
## face the player has or can buy, each in its tier frame with its price, or
## In a slot, Yours or Free. A face that moves has a small play mark. While a
## face is being put in a slot (`swapping`) the row lifts in its mint panel,
## each open place dashed, and the other cards step back. A place past the open
## ones shows a lock: tapping it picks the next reaction slot to buy.
## A view only: presentation/wardrobe_flow.gd builds the state and answers the
## signals. Faces are drawn flat with the game's own shapes (end_reactions.gd
## FaceIcon), drawn once each, so the list costs nothing on idle frames; the big
## pip beside it shows the picked face moving.
const EndReactions = preload("res://presentation/end_reactions.gd")
const ShopKit = preload("res://presentation/kit/shop_kit.gd")
const TierFrame = preload("res://presentation/kit/tier_frame.gd")
const ThemeRules = preload("res://presentation/control_theme.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const CurrencyMark = preload("res://presentation/kit/currency_mark.gd")

const INK := ShopKit.INK
const INK_SOFT := ShopKit.INK_SOFT
const ROW := Color("e4eee0")
const ROW_EDGE := Color("d3e2d0")
const LIFTED := Color("dcefe6")
const LIFTED_EDGE := Color("4f9d89")
const SLOT_FILL := Color("efe8d4")
const HEART_FILL := Color("fbe1dc")
const SLOT_SIZE := Vector2(96, 96)
const CARD_SIZE := Vector2(112, 132)
const FACE := 56.0
## A face in a reaction slot.
const SLOT_FACE := 76.0
## The other cards while a face is being put in a slot.
const STEPPED_BACK := 0.45

signal face_chosen(id: String)
signal slot_chosen(index: int)

var _row_panel: PanelContainer
var _row: HBoxContainer
var _grid: HFlowContainer
var _key := ""

func _init() -> void:
	name = "WardrobeReactions"
	add_theme_constant_override("separation", 12)
	_row_panel = PanelContainer.new()
	_row_panel.name = "ReactionSlotRow"
	add_child(_row_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	_row_panel.add_child(column)
	column.add_child(ShopKit.text(PlayerCopy.WARDROBE_YOUR_REACTIONS, 17, INK, ShopKit.bold_font()))
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 10)
	column.add_child(_row)
	_grid = HFlowContainer.new()
	_grid.name = "ReactionFaces"
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	add_child(_grid)

## Draws `state`: {slots (SLOT_COUNT ids, "" empty), open (places open),
## unlock (the next reaction slot entry, or {}), faces (services/reaction_slots.gd
## faces), selected, swapping, shop, color ("peach" or "mint")}. Made again only
## when what it shows changes.
func render(state: Dictionary) -> void:
	var key := var_to_str(state)
	if key == _key: return
	_key = key
	var swapping := bool(state.get("swapping", false))
	_row_panel.add_theme_stylebox_override("panel", ThemeRules.padded(ThemeRules.rounded(LIFTED if swapping else ROW, 16, LIFTED_EDGE if swapping else ROW_EDGE), 12, 10))
	for child: Node in _row.get_children() + _grid.get_children():
		child.get_parent().remove_child(child)
		child.queue_free()
	var slots: Array = state.get("slots", [])
	var color := str(state.get("color", "peach"))
	for index: int in slots.size():
		_row.add_child(_slot(index, str(slots[index]), index < int(state.get("open", 4)), swapping, state.get("unlock", {}), bool(state.get("shop", false)), color))
	# A thin line keeps the heart apart from the slots (board 4).
	var line := VSeparator.new()
	line.add_theme_constant_override("separation", 16)
	_row.add_child(line)
	_row.add_child(_heart())
	var picked := str(state.get("selected", ""))
	for entry: Dictionary in state.get("faces", []):
		var card := _card(entry, entry.id == picked, bool(state.get("shop", false)), color)
		if swapping and entry.id != picked: card.modulate.a = STEPPED_BACK
		_grid.add_child(card)

func _slot(index: int, face: String, open: bool, swapping: bool, unlock: Dictionary, shop: bool, color: String) -> Button:
	var button := Button.new()
	button.name = "ReactionSlot_%d" % index
	button.custom_minimum_size = SLOT_SIZE
	button.focus_mode = Control.FOCUS_ALL
	button.accessibility_name = EndReactions.FaceArt.face_name(face) if not face.is_empty() else PlayerCopy.WARDROBE_EMPTY_SLOT
	var look := ThemeRules.rounded(SLOT_FILL if open else Color(SLOT_FILL, 0.5), 14, LIFTED_EDGE if swapping and open else Color("d6ceb4"))
	look.set_border_width_all(2 if swapping and open else 1)
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]: button.add_theme_stylebox_override(state, look)
	button.pressed.connect(func() -> void: slot_chosen.emit(index))
	if swapping and open: button.add_child(Dashes.new())
	if open and not face.is_empty():
		var icon := EndReactions.FaceIcon.new(face, color, SLOT_FACE)
		icon.position = (SLOT_SIZE - icon.size) * 0.5
		button.add_child(icon)
	elif not open:
		# A locked place: the lock, and the next slot's price while it sells.
		var column := VBoxContainer.new()
		column.alignment = BoxContainer.ALIGNMENT_CENTER
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var lock := Lock.new()
		lock.custom_minimum_size = Vector2(22, 24)
		lock.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		column.add_child(lock)
		if shop and bool(unlock.get("sold", false)):
			var price := ShopKit.amount(int(unlock.price), 12, INK, "", "", "pollen")
			price.alignment = BoxContainer.ALIGNMENT_CENTER
			column.add_child(price)
		button.add_child(column)
		button.accessibility_name = PlayerCopy.WARDROBE_LOCKED_SLOT
	return button

## The heart (Love), always at the row's end, outside the slots.
func _heart() -> Control:
	var chip := PanelContainer.new()
	chip.name = "ReactionSlotHeart"
	chip.custom_minimum_size = SLOT_SIZE
	chip.add_theme_stylebox_override("panel", ThemeRules.rounded(HEART_FILL, 14, Color("efc3bb")))
	var icon := EndReactions.FaceIcon.new("heart", "peach", SLOT_FACE * 0.8)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.add_child(icon)
	return chip

func _card(entry: Dictionary, picked: bool, shop: bool, color: String) -> Button:
	var card := Button.new()
	card.name = "ReactionCard_" + str(entry.id)
	card.custom_minimum_size = CARD_SIZE
	card.toggle_mode = true
	card.set_pressed_no_signal(picked)
	card.focus_mode = Control.FOCUS_ALL
	card.accessibility_name = str(entry.name)
	var tier := str(entry.tier)
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		card.add_theme_stylebox_override(state, TierFrame.style(tier, 14, picked or state in ["pressed", "hover_pressed"]))
	card.pressed.connect(func() -> void: face_chosen.emit(str(entry.id)))
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 7)
	card.add_child(margin)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 1)
	margin.add_child(column)
	var picture := PanelContainer.new()
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.add_theme_stylebox_override("panel", ThemeRules.rounded(SLOT_FILL, 10))
	picture.custom_minimum_size.y = 64
	column.add_child(picture)
	var icon := EndReactions.FaceIcon.new(str(entry.id), color, FACE)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	picture.add_child(icon)
	if bool(entry.get("moving", false)):
		var play := Play.new()
		play.custom_minimum_size = Vector2(16, 16)
		play.size_flags_horizontal = Control.SIZE_SHRINK_END
		play.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		picture.add_child(play)
	var title := ShopKit.text(str(entry.name), 13, INK, ShopKit.bold_font())
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(title)
	var bottom := HBoxContainer.new()
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_theme_constant_override("separation", 4)
	column.add_child(bottom)
	var word := PlayerCopy.FACE_PACK_FREE_TAB.to_upper() if tier == "free" else TierFrame.word(tier)
	var tier_word := ShopKit.text(word, 9, TierFrame.ink(tier), ShopKit.bold_font())
	tier_word.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tier_word.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bottom.add_child(tier_word)
	if int(entry.get("in_slot", -1)) >= 0: bottom.add_child(_tag(PlayerCopy.WARDROBE_IN_SLOT, true))
	elif bool(entry.owned) and tier != "free": bottom.add_child(_tag(PlayerCopy.WARDROBE_OWNED_TAG, false))
	elif bool(entry.sold) and shop: bottom.add_child(ShopKit.amount(int(entry.price), 12, INK, "", "", "pollen"))
	return card

## In a slot (ink) or Yours (mint), a small pill.
func _tag(text: String, ink: bool) -> Control:
	var pill := PanelContainer.new()
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_theme_stylebox_override("panel", ThemeRules.padded(ThemeRules.rounded(INK if ink else Color("d6eadf"), 8), 5, 1))
	pill.add_child(ShopKit.text(text, 10, ShopKit.CREAM if ink else Color("2e5d4f"), ShopKit.bold_font()))
	return pill

## The dashed edge of an open place while a face is being put in.
class Dashes extends Control:
	func _init() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var rect := Rect2(Vector2(3, 3), size - Vector2(6, 6))
		var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
		for side: int in 4:
			var a: Vector2 = corners[side]
			var b: Vector2 = corners[(side + 1) % 4]
			var steps := int(a.distance_to(b) / 8.0)
			for step: int in steps:
				if step % 2 == 0: draw_line(a.lerp(b, float(step) / steps), a.lerp(b, float(step + 1) / steps), LIFTED_EDGE, 2.0, true)

## A small padlock.
class Lock extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var w := size.x
		draw_arc(Vector2(w * 0.5, size.y * 0.42), w * 0.28, PI, TAU, 16, INK_SOFT, 2.5, true)
		draw_rect(Rect2(Vector2(w * 0.12, size.y * 0.42), Vector2(w * 0.76, size.y * 0.55)), INK_SOFT)

## The play mark on a face that moves.
class Play extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var r := minf(size.x, size.y) * 0.5
		draw_circle(size * 0.5, r, Color("223b36"), true, -1.0, true)
		draw_colored_polygon(PackedVector2Array([size * 0.5 + Vector2(-r * 0.3, -r * 0.45), size * 0.5 + Vector2(r * 0.5, 0), size * 0.5 + Vector2(-r * 0.3, r * 0.45)]), Color("f4f1e2"))
