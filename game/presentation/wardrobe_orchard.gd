extends PanelContainer
## The Wardrobe's Orchard (Fruits board 4a), the right panel while the Orchard
## chip is picked (presentation/wardrobe_page.gd shows it in place of the
## cream shop panel): the plum Orchard (kit/orchard_surface.gd) with a branch,
## leaves and Fruits overhead; "The Orchard" and "Every item stays in the shop"
## beside the slot chips (Hat, Body, Leaf) with the Orchard chip picked; the
## Orchard items on cream plinths, each on a still pip wearing it
## (kit/pip_avatar.gd), with its name, its tier's tag and its Fruit price (or
## Yours and Wearing); the sprigs as leaf tiles under "Sprigs · 20 each"; and
## each Orchard set's card with its pieces, the full price struck and the set
## price. The picked card or tile has the ripe ring.
##
## A view only: render(model, line) redraws from the Wardrobe's model
## (presentation/wardrobe_flow.gd); a tap asks through the signals. Cards are
## made again only when what they show changes; a new pick only moves the ring.
## The branch draws once per resize, never per frame.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const ShopKit = preload("res://presentation/kit/shop_kit.gd")
const OrchardSurface = preload("res://presentation/kit/orchard_surface.gd")
const CurrencyMark = preload("res://presentation/kit/currency_mark.gd")
const FruitMark = preload("res://presentation/kit/fruit_mark.gd")
const PipAvatar = preload("res://presentation/kit/pip_avatar.gd")
const PipOutfit = preload("res://presentation/pip_outfit.gd")
const ThemeRules = preload("res://presentation/control_theme.gd")
const SpiritLook = preload("res://presentation/spirit_look.gd")
const Outfit = preload("res://services/outfit.gd")
const PollenMoney = preload("res://services/pollen_money.gd")
const Sprig = preload("res://presentation/pip_wear/sprig.gd")

const FRUITS := "fruits"
## The plinth's cream, the ring of the picked card, and the branch.
const PLINTH := Color("f3efdf")
const RIPE := OrchardSurface.PEACH
const BRANCH := Color("2a1226")
const LEAF_DARK := Color("7da05e")
const LEAF_LIGHT := Color("93b874")
## The selector's and the set card's dark glass on plum, and the set card's rim.
const GLASS := Color(0.078, 0.031, 0.086, 0.45)
const SET_RIM := Color(0.949, 0.718, 0.612, 0.35)
const CARD_SIZE := Vector2(240, 175)
## The narrowest an item card and the set card get on a 16:9 phone (a safe
## area 1280 units wide); wider screens give them up to CARD_SIZE and SET_SIZE.
## An item card is never narrower than its full name and tag need (CARD_NAME_GAP
## between them); where the cards don't all fit, their row scrolls sideways.
const CARD_NARROW := 168.0
const CARD_NAME_GAP := 10.0
## Where the row scrolls, the cards widen (up to CARD_SIZE.x) so whole cards
## fill the view with this much of the next one peeking in at its edge.
const CARD_PEEK := 0.45
## How far the cards' scroll view reaches past the cards on every side, so the
## picked card's ring (6 out from its plinth) is never clipped.
const RING_ROOM := 8
const SET_SIZE := Vector2(515, 103)
const SET_NARROW := 400.0
const CARD_PIP := Vector2(140, 168)
const TILE := 77.0
const RADIUS := 22

signal item_chosen(id: String)
signal kind_chosen(kind: String)

var _status: Label
var _seg: HBoxContainer
var _cards: ShareRow
var _card_scroll: ScrollContainer
var _scrolled_to := ""
var _card_floor := CARD_NARROW
var _sprigs: HBoxContainer
var _each: Label
var _sets: VBoxContainer
var _model: Dictionary = {}
var _key := ""
## The player's Reduce motion setting: with it off, a card whose item moves
## on its own shows it moving (kit/pip_avatar.gd animate_moving).
var reduced := false

func _init() -> void:
	name = "WardrobeOrchard"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_stylebox_override("panel", ThemeRules.padded(StyleBoxEmpty.new(), 0, 0))
	draw.connect(func() -> void: OrchardSurface.paint(self, RADIUS, false))
	resized.connect(queue_redraw)
	var decor := Branch.new()
	decor.name = "OrchardBranch"
	add_child(decor)
	var margin := MarginContainer.new()
	for side: Array in [["left", 30], ["right", 26], ["top", 64], ["bottom", 20]]: margin.add_theme_constant_override("margin_" + side[0], side[1])
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	column.add_child(header)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", 0)
	var title := ShopKit.text(PlayerCopy.ORCHARD_TITLE, 32, OrchardSurface.TEXT, ShopKit.heading_font())
	titles.add_child(title)
	var stays := ShopKit.text(PlayerCopy.WARDROBE_STAYS, 17, OrchardSurface.TEXT_SOFT)
	stays.name = "OrchardStays"
	titles.add_child(stays)
	header.add_child(titles)
	var seg_panel := PanelContainer.new()
	seg_panel.name = "OrchardChips"
	seg_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	seg_panel.add_theme_stylebox_override("panel", ThemeRules.padded(ThemeRules.rounded(GLASS, 15), 4, 4))
	header.add_child(seg_panel)
	var lines: Array[Label] = [title, stays]
	decor.keep_between(lines, seg_panel)
	_seg = HBoxContainer.new()
	_seg.add_theme_constant_override("separation", 4)
	seg_panel.add_child(_seg)
	_status = ShopKit.text("", 16, OrchardSurface.TEXT_SOFT)
	_status.name = "OrchardStatus"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)
	_cards = ShareRow.new(24)
	_cards.name = "OrchardItems"
	_cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_scrolling(_cards))
	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(filler)
	var bottom := ShareRow.new(24)
	column.add_child(bottom)
	var sprig_column := VBoxContainer.new()
	sprig_column.name = "OrchardSprigs"
	sprig_column.add_theme_constant_override("separation", 10)
	sprig_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sprig_column.size_flags_vertical = Control.SIZE_SHRINK_END
	bottom.add_child(sprig_column)
	var sprig_title := HBoxContainer.new()
	sprig_title.add_theme_constant_override("separation", 6)
	sprig_title.add_child(ShopKit.text(PlayerCopy.ORCHARD_SPRIGS, 20, OrchardSurface.TEXT, ShopKit.bold_font()))
	_each = ShopKit.text("", 20, OrchardSurface.TEXT_SOFT)
	_each.name = "OrchardSprigsEach"
	sprig_title.add_child(_each)
	sprig_column.add_child(sprig_title)
	_sprigs = HBoxContainer.new()
	_sprigs.name = "OrchardSprigTiles"
	_sprigs.add_theme_constant_override("separation", 15)
	sprig_column.add_child(_sprigs)
	_sets = VBoxContainer.new()
	_sets.name = "OrchardSets"
	_sets.size_flags_vertical = Control.SIZE_SHRINK_END
	_sets.add_theme_constant_override("separation", 10)
	_sets.set_meta(ShareRow.CAP, SET_SIZE.x)
	bottom.add_child(_sets)

## The cards' row in a sideways scroll. Where every card fits the row fills
## the width exactly as without it; where they don't, the cards keep their
## size and the row scrolls (a drag or the wheel, no bar), the next card
## peeking in at the edge. A drag scrolls and never picks; a tap still picks
## (ThemeRules.touch_scroll). The view reaches RING_ROOM past the cards and the
## cards sit back in by as much, so they stand where they would without it.
func _scrolling(row: Control) -> Control:
	var reach := MarginContainer.new()
	reach.name = "OrchardItemsReach"
	reach.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_scroll = ScrollContainer.new()
	_card_scroll.name = "OrchardItemsScroll"
	_card_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_card_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	reach.add_child(_card_scroll)
	var inset := MarginContainer.new()
	inset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side: String in ["left", "right", "top", "bottom"]:
		reach.add_theme_constant_override("margin_" + side, -RING_ROOM)
		inset.add_theme_constant_override("margin_" + side, RING_ROOM)
	_card_scroll.add_child(inset)
	inset.add_child(row)
	ThemeRules.touch_scroll(_card_scroll)
	_card_scroll.resized.connect(_size_cards)
	return reach

## Whether the cards' row is wider than its view (it scrolls).
func cards_scroll() -> bool:
	return _card_scroll.get_h_scroll_bar().max_value > _card_scroll.size.x + 0.5

## Whether an entry is drawn as a sprig tile (else an item card).
static func is_sprig(entry: Dictionary) -> bool:
	return str(entry.get("tier", "")) == "sprig"

## The tier's word ("Hat"), the card's tag in capitals and the big pip's line.
static func tier_word(tier: String) -> String:
	return str(PlayerCopy.ORCHARD_TIERS.get(tier, ""))

## Redraws from the Wardrobe's model; `line` is the status or offline note ("" for none).
func render(model: Dictionary, line: String) -> void:
	_model = model
	_status.text = line
	_status.visible = not line.is_empty()
	var entries: Array = (model.get("items", []) as Array).filter(func(entry: Dictionary) -> bool: return entry.get("currency") == FRUITS)
	var cards: Array = entries.filter(func(entry: Dictionary) -> bool: return not is_sprig(entry))
	var sprigs: Array = entries.filter(is_sprig)
	var sets: Array = model.get("sets", [])
	var key := var_to_str([cards, sprigs, sets, model.get("kinds", [])])
	if key != _key:
		_key = key
		_fill_seg(model.get("kinds", []))
		_fill(_cards, cards.map(_card))
		_even_cards()
		_fill(_sprigs, sprigs.map(_tile))
		_fill(_sets, sets.map(_set_card))
		_each.text = _each_line(sprigs)
		(_sprigs.get_parent() as Control).visible = not sprigs.is_empty()
	_restyle()

## "· 20 each" while every sprig sells at one price, else nothing.
static func _each_line(sprigs: Array) -> String:
	var prices := {}
	for entry: Dictionary in sprigs:
		if bool(entry.sold) and not bool(entry.owned): prices[int(entry.price)] = true
	return PlayerCopy.ORCHARD_EACH % PollenMoney.grouped(int(prices.keys()[0])) if prices.size() == 1 else ""

static func _fill(box: Container, made: Array) -> void:
	for child: Node in box.get_children():
		box.remove_child(child)
		child.queue_free()
	for node: Control in made: box.add_child(node)

## The slot chips on plum, then the Orchard chip, picked.
func _fill_seg(kinds: Array) -> void:
	_fill(_seg, [])
	for kind: Variant in kinds:
		var chip := Button.new()
		chip.name = "OrchardKind_" + str(kind)
		chip.text = str(PlayerCopy.WARDROBE_SLOTS.get(kind, kind))
		chip.custom_minimum_size = Vector2(0, 40)
		chip.add_theme_font_size_override("font_size", 18)
		_chip_style(chip, false)
		chip.pressed.connect(func() -> void: kind_chosen.emit(str(kind)))
		_seg.add_child(chip)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(CurrencyMark.beside(FRUITS, 20))
	row.add_child(ShopKit.text(PlayerCopy.ORCHARD_TAB, 18, OrchardSurface.PEACH_INK, ShopKit.bold_font()))
	var on := ShopKit.content_button(row, 40)
	on.name = "OrchardKind_orchard"
	on.accessibility_name = PlayerCopy.ORCHARD_TAB
	_chip_style(on, true)
	_seg.add_child(on)

static func _chip_style(chip: Button, picked: bool) -> void:
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		var fill := RIPE if picked else (Color.TRANSPARENT if state in ["normal", "focus"] else Color(OrchardSurface.PLUM_LIGHT, 0.6))
		chip.add_theme_stylebox_override(state, ThemeRules.padded(ThemeRules.rounded(fill, 11), 16, 4))
		chip.add_theme_color_override("font_color" if state == "normal" else "font_%s_color" % state, OrchardSurface.PEACH_INK if picked else OrchardSurface.TEXT_SOFT)

## A transparent button that shows the ring (its child "OrchardRing") while picked.
func _pickable(id: String, accessible: String, minimum: Vector2) -> Button:
	var button := Button.new()
	button.custom_minimum_size = minimum
	button.toggle_mode = true
	button.accessibility_name = accessible
	button.set_meta("item_id", id)
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	button.pressed.connect(func() -> void: item_chosen.emit(id))
	return button

## The picked ring around `around` (a plinth or tile), shown by _restyle.
static func _ring(around: Control, radius: int) -> void:
	var ring := Panel.new()
	ring.name = "OrchardRing"
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var style := ThemeRules.rounded(Color.TRANSPARENT, radius + 6, RIPE)
	style.draw_center = false
	style.set_border_width_all(3)
	style.set_expand_margin_all(6)
	ring.add_theme_stylebox_override("panel", style)
	ring.visible = false
	around.add_child(ring)

static func _plinth(minimum: Vector2, radius: int) -> PanelContainer:
	var plinth := PanelContainer.new()
	plinth.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plinth.custom_minimum_size = minimum
	plinth.add_theme_stylebox_override("panel", ThemeRules.rounded(PLINTH, radius))
	return plinth

## An Orchard item: the pip wearing it on its plinth, the name and tag, the price.
func _card(entry: Dictionary) -> Control:
	var card := _pickable(str(entry.id), str(entry.name), Vector2(CARD_NARROW, 0))
	card.name = "OrchardCard_" + str(entry.id)
	card.set_meta(ShareRow.CAP, CARD_SIZE.x)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 4)
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.add_child(column)
	var plinth := _plinth(Vector2(0, CARD_SIZE.y), 17)
	column.add_child(plinth)
	var pip := PipAvatar.new(reduced, SpiritLook.PEACH, CARD_PIP, true)
	pip.place = PipOutfit.WARDROBE
	pip.outfit = Outfit.of(str(entry.id))
	pip.animate_moving = true
	pip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	plinth.add_child(pip)
	_ring(plinth, 17)
	var title := HBoxContainer.new()
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(title)
	var label := ShopKit.text(str(entry.name), 19, OrchardSurface.TEXT, ShopKit.bold_font())
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.name = "OrchardName"
	title.add_child(label)
	var tag := ShopKit.text(tier_word(str(entry.tier)).to_upper(), 13, OrchardSurface.TEXT_SOFT, ShopKit.bold_font())
	tag.name = "OrchardTag"
	title.add_child(tag)
	column.add_child(_price(entry, 20))
	card.custom_minimum_size.y = CARD_SIZE.y + 64
	return card

## The price in Fruits, or Yours and Wearing once owned.
static func _price(entry: Dictionary, font_size: int) -> Control:
	if bool(entry.owned):
		var owned := ShopKit.text(PlayerCopy.WARDROBE_WEARING if bool(entry.worn) else PlayerCopy.WARDROBE_OWNED_TAG, font_size - 2, RIPE, ShopKit.bold_font())
		owned.name = "OrchardOwned"
		return owned
	var price := ShopKit.amount(int(entry.price), font_size, RIPE, "", "", FRUITS)
	price.name = "OrchardPrice"
	return price

## A sprig: its leaf, in its own colour, on a small cream tile.
func _tile(entry: Dictionary) -> Control:
	var tile := _pickable(str(entry.id), str(entry.name), Vector2(TILE, TILE))
	tile.name = "OrchardSprig_" + str(entry.id)
	var plinth := _plinth(Vector2(TILE, TILE), 16)
	plinth.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tile.add_child(plinth)
	var leaf := Leaf.new()
	leaf.colour = Sprig.COLOURS.get(str(entry.id), LEAF_LIGHT)
	plinth.add_child(leaf)
	_ring(plinth, 16)
	if bool(entry.owned):
		var mark := ShopKit.text(PlayerCopy.WARDROBE_OWNED_TAG, 11, OrchardSurface.PEACH_INK, ShopKit.bold_font())
		mark.name = "OrchardOwned"
		mark.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
		mark.grow_horizontal = Control.GROW_DIRECTION_BOTH
		mark.grow_vertical = Control.GROW_DIRECTION_BEGIN
		mark.offset_bottom = -3
		tile.add_child(mark)
	return tile

## An Orchard set: its name and pieces, the full price struck and the set price.
func _set_card(entry: Dictionary) -> Control:
	var card := _pickable(str(entry.id), str(entry.name), Vector2(SET_NARROW, SET_SIZE.y))
	card.name = "OrchardSet_" + str(entry.id)
	var back := Panel.new()
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var style := ThemeRules.rounded(GLASS, 17, SET_RIM)
	style.set_border_width_all(2)
	back.add_theme_stylebox_override("panel", style)
	card.add_child(back)
	_ring(back, 17)
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: Array in [["left", 19], ["right", 19], ["top", 14], ["bottom", 14]]: margin.add_theme_constant_override("margin_" + side[0], side[1])
	card.add_child(margin)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)
	var words := VBoxContainer.new()
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	words.add_theme_constant_override("separation", 2)
	row.add_child(words)
	words.add_child(ShopKit.text(str(entry.name), 20, OrchardSurface.TEXT, ShopKit.bold_font()))
	var pieces := ShopKit.text(PlayerCopy.ORCHARD_SET_PIECES % _listed(entry.get("pieces", [])), 16, OrchardSurface.TEXT_SOFT)
	pieces.name = "OrchardSetPieces"
	pieces.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.add_child(pieces)
	var price := HBoxContainer.new()
	price.mouse_filter = Control.MOUSE_FILTER_IGNORE
	price.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	price.add_theme_constant_override("separation", 10)
	row.add_child(price)
	if not bool(entry.owned) and int(entry.full) > int(entry.price):
		price.add_child(_struck(PollenMoney.grouped(int(entry.full)), 17))
	price.add_child(_price(entry, 27))
	return card

## "Apple hood, Apple leaf and Orchard skin".
static func _listed(names: Array) -> String:
	if names.size() <= 1: return "" if names.is_empty() else str(names[0])
	return PlayerCopy.ORCHARD_AND % [", ".join(PackedStringArray(names.slice(0, names.size() - 1))), str(names.back())]

## The full price, struck through.
static func _struck(text: String, font_size: int) -> Control:
	var label := ShopKit.text(text, font_size, OrchardSurface.TEXT_SOFT)
	label.name = "OrchardSetFull"
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var line := ColorRect.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.color = OrchardSurface.TEXT_SOFT
	line.anchor_left = 0.0
	line.anchor_right = 1.0
	line.anchor_top = 0.5
	line.anchor_bottom = 0.5
	line.offset_top = 0.0
	line.offset_bottom = 2.0
	label.add_child(line)
	return label

## Every item card as wide as the widest full name and tag need (at least
## CARD_NARROW), so the cards match and no name is cut short.
func _even_cards() -> void:
	var least := CARD_NARROW
	for card: Node in _cards.get_children():
		var label: Label = card.find_child("OrchardName", true, false)
		var tag: Label = card.find_child("OrchardTag", true, false)
		var name_width := label.get_theme_font("font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x
		least = maxf(least, ceilf(name_width + tag.get_combined_minimum_size().x + CARD_NAME_GAP))
	_card_floor = least
	_size_cards()

## Every card at the floor where the row fits (the row then shares out the
## rest as it always has); where it scrolls, as wide as fills the view with
## whole cards and CARD_PEEK of the next. The view's width never depends on
## the cards', so this settles in one pass.
func _size_cards() -> void:
	var cards := _cards.get_children()
	if cards.is_empty(): return
	var view := _card_scroll.size.x - RING_ROOM * 2.0
	var width := _card_floor
	if cards.size() * (_card_floor + _cards.gap) - _cards.gap > view and view > 0.0:
		var whole := maxi(floori((view - CARD_PEEK * _card_floor) / (_card_floor + _cards.gap)), 1)
		width = clampf((view - whole * _cards.gap) / (whole + CARD_PEEK), _card_floor, CARD_SIZE.x)
	for card: Node in cards: (card as Control).custom_minimum_size.x = width

## The ring on the picked card, tile or set; the rest without it. A newly
## picked card scrolls into view.
func _restyle() -> void:
	var picked := str(_model.get("selected", ""))
	for box: Container in [_cards, _sprigs, _sets]:
		for node: Node in box.get_children():
			if not node is Button: continue
			var on := str(node.get_meta("item_id", "")) == picked
			(node as Button).set_pressed_no_signal(on)
			var ring: Node = node.find_child("OrchardRing", true, false)
			if ring != null: (ring as Control).visible = on
			if on and box == _cards and picked != _scrolled_to:
				_scrolled_to = picked
				_show_card.call_deferred(node)

## Scrolls the cards' row so `card` and its ring show whole, once the row is
## laid out (a frame on).
func _show_card(card: Control) -> void:
	if not is_inside_tree(): return
	await get_tree().process_frame
	if not is_instance_valid(card) or not card.is_inside_tree(): return
	var scroll := _card_scroll.get_h_scroll_bar()
	# In the view's own frame the cards sit RING_ROOM in, the ring 6 out from each.
	var left := card.position.x
	var right := card.position.x + card.size.x + RING_ROOM * 2
	if left < scroll.value: scroll.value = left
	elif right > scroll.value + _card_scroll.size.x: scroll.value = right - _card_scroll.size.x

## A leaf (the boards' leaf: a pointed oval with its midrib and a soft shine),
## in a unit frame built once and only moved and scaled when drawn.
class LeafArt extends RefCounted:
	static var outline: PackedVector2Array = _outline()

	static func _outline() -> PackedVector2Array:
		var points := PackedVector2Array()
		var curves := [[Vector2(-0.7, 0.7), Vector2(-0.8, -0.2), Vector2(0, -0.85), Vector2(0.8, -0.8)], [Vector2(0.8, -0.8), Vector2(0.75, 0), Vector2(0.2, 0.75), Vector2(-0.7, 0.7)]]
		for curve: Array in curves:
			for step in range(12):
				var t := step / 12.0
				var u := 1.0 - t
				points.append(curve[0] * u * u * u + curve[1] * 3.0 * u * u * t + curve[2] * 3.0 * u * t * t + curve[3] * t * t * t)
		return points

	## Draws a leaf `side` pixels across round `centre`, turned `degrees`, into `canvas`.
	static func draw(canvas: CanvasItem, centre: Vector2, side: float, degrees: float, colour: Color) -> void:
		var at := Transform2D(deg_to_rad(degrees), Vector2(side, side) * 0.5, 0.0, centre)
		canvas.draw_colored_polygon(at * outline, colour)
		canvas.draw_line(at * Vector2(-0.6, 0.6), at * Vector2(0.7, -0.7), Color(0.16, 0.24, 0.12, 0.45), maxf(1.0, side * 0.03), true)
		canvas.draw_set_transform(at * Vector2(-0.1, -0.3), deg_to_rad(degrees - 40.0), Vector2(side * 0.11, side * 0.04))
		canvas.draw_circle(Vector2.ZERO, 1.0, Color(1, 1, 1, 0.4))
		canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## A sprig tile's leaf: drawn once per resize.
class Leaf extends Control:
	var colour := Color.WHITE
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	func _draw() -> void:
		LeafArt.draw(self, size * 0.5, minf(size.x, size.y) * 0.64, 0.0, colour)

## The branch over the Orchard (board 4a), drawn in the board's own frame
## (1715 wide) scaled to the panel's width: the bough and three twigs, four
## leaves and three Fruits (kit/fruit_mark.gd's render). Every part is placed
## from a point on the bough or a twig (layout()): each Fruit hangs from a
## green stalk that runs into its own stem, each leaf joins on a short stalk
## of its own green, and each twig starts on the bough, so nothing floats.
## What hangs below the bough spreads across the gap between the title and
## the chips (span()), so a 16:9 phone's narrower panel keeps it clear of
## them too; test_wardrobe_flow.gd checks it at the phones' widths. Once per
## resize, and again when the title or the chips move.
class Branch extends Control:
	const FRAME_WIDTH := 1715.0
	## [cubic curve, width]: the bough's two halves (x only grows along them),
	## then the twig that rises from the bough on the right.
	const CURVES := [
		[[Vector2(-20, 70), Vector2(260, 30), Vector2(520, 120), Vector2(820, 80)], 16.0],
		[[Vector2(820, 80), Vector2(1120, 40), Vector2(1380, 30), Vector2(1740, 96)], 16.0],
		[[Vector2(1169, 49), Vector2(1200, 30), Vector2(1250, 18), Vector2(1300, 22)], 8.0]]
	const TWIG := 8.0
	## A twig a Fruit hangs from, seen from its end: its start on the bough,
	## then its two middle points from its start and from its end.
	const TWIG_LEFT := [Vector2(-115, -24), Vector2(32, 18), Vector2(-43, 1)]
	const TWIG_RIGHT := [Vector2(-108, -30), Vector2(28, 16), Vector2(-35, -2)]
	## The gap between the title and the chips on the 1600x738 board, in frame
	## units, for while the header is not laid out; and how far inside the
	## gap's ends what hangs keeps.
	const SPAN := Vector2(401, 1171)
	const SPAN_INSET := 30.0
	## Below the bough, across the gap: [how far across, twig ([] hangs from
	## the bough), the stalk down to the Fruit's stem, side]. The stalk is long
	## enough to show past the twig and above the Fruit's own leaf.
	const HUNG := [[0.165, TWIG_LEFT, Vector2(0, 24), 64.0], [0.51, [], Vector2(0, 27), 66.0], [0.886, TWIG_RIGHT, Vector2(0, 24), 64.0]]
	## A leaf hanging off the bough in the gap: [how far across, stalk length,
	## the way it points in degrees (0 right, 90 down), side, light].
	const HUNG_LEAVES := [[0.31, 16.0, 70.0, 60.0, true]]
	## Leaves above the bough: [curve, how far along it, stalk length, degrees, side, light].
	const LEAVES := [[0, 0.2, 16.0, -140.0, 56.0, false], [2, 1.0, 10.0, 10.0, 56.0, false], [1, 0.8, 16.0, -35.0, 54.0, true]]
	const FRUIT_STALK := 4.5
	const LEAF_STALK := 4.0
	## How far a stalk runs on into the Fruit's stem, and into the leaf's thin
	## base, per side.
	const TUCK := 0.03
	const LEAF_TUCK := 0.12
	var _render: Texture2D
	## The title's lines and the chips, which the gap lies between.
	var _titles: Array[Label] = []
	var _chips: Control

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		# The bough runs off both edges; the panel's own rounded edge ends it.
		clip_contents = true
		_render = FruitMark.render()
		resized.connect(queue_redraw)

	## Hangs the Fruits between the end of `titles` and the start of `chips`.
	func keep_between(titles: Array[Label], chips: Control) -> void:
		_titles = titles
		_chips = chips
		for each: Control in titles: each.item_rect_changed.connect(queue_redraw)
		chips.item_rect_changed.connect(queue_redraw)

	## The gap between the title and the chips in frame units at this size,
	## inset by SPAN_INSET; SPAN while they are not laid out.
	func span() -> Vector2:
		var zoom := size.x / FRAME_WIDTH
		if zoom <= 0.0 or _chips == null or not _chips.is_visible_in_tree() or _chips.size.x <= 0.0: return SPAN + Vector2(SPAN_INSET, -SPAN_INSET)
		var to_here := get_global_transform().affine_inverse()
		var left := 0.0
		for label: Label in _titles:
			var wide := label.get_theme_font("font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x
			left = maxf(left, (to_here * label.global_position).x + wide)
		return Vector2(left / zoom + SPAN_INSET, (to_here * _chips.global_position).x / zoom - SPAN_INSET)

	func _draw() -> void:
		if size.x <= 0.0 or _render == null: return
		var parts := layout(size.x / FRAME_WIDTH, _render.get_size(), span())
		# Stalks first, so they grow out from under the bough and the Fruits.
		for stalk: Array in parts.stalks: draw_line(stalk[0], stalk[1], stalk[3], stalk[2], true)
		for curve: Array in parts.curves: draw_polyline(curve[0], BRANCH, curve[1], true)
		for leaf: Array in parts.leaves: LeafArt.draw(self, leaf[0], leaf[1], leaf[2], LEAF_LIGHT if leaf[3] else LEAF_DARK)
		for box: Rect2 in parts.fruits: FruitMark.draw_render(self, _render, box)

	## The branch at `zoom` (panel pixels per frame unit), the Fruit's render
	## being `picture_size`, what hangs spread across `gap` (frame units):
	## curves [points, width], stalks [from, to, width, colour] (from on a
	## curve), leaves [centre, side, degrees, light] for LeafArt.draw, and the
	## Fruits' draw_render boxes.
	static func layout(zoom: float, picture_size: Vector2, gap: Vector2) -> Dictionary:
		var parts := {"curves": [], "stalks": [], "leaves": [], "fruits": []}
		for curve: Array in CURVES: parts.curves.append([_bezier(curve[0], zoom), curve[1] * zoom])
		for fruit: Array in HUNG:
			var x := lerpf(gap.x, gap.y, fruit[0])
			var twig: Array = fruit[1]
			var from := bough_at(x)
			if not twig.is_empty():
				var start := bough_at(x + twig[0].x)
				from = Vector2(x, start.y - twig[0].y)
				parts.curves.append([_bezier([start, start + twig[1], from + twig[2], from], zoom), TWIG * zoom])
			var stem: Vector2 = (from + fruit[2]) * zoom
			var side: float = fruit[3] * zoom
			parts.stalks.append([from * zoom, stem + (fruit[2] as Vector2).normalized() * side * TUCK, FRUIT_STALK * zoom, FruitMark.GREEN])
			parts.fruits.append(FruitMark.hung_box(picture_size, stem, side))
		for leaf: Array in HUNG_LEAVES: _leaf(parts, bough_at(lerpf(gap.x, gap.y, leaf[0])), leaf.slice(1), zoom)
		for leaf: Array in LEAVES: _leaf(parts, _point(CURVES[leaf[0]][0], leaf[1]), leaf.slice(2), zoom)
		return parts

	## A leaf on a stalk from `from` (frame units): [stalk length, degrees, side, light].
	static func _leaf(parts: Dictionary, from: Vector2, leaf: Array, zoom: float) -> void:
		var way := Vector2.from_angle(deg_to_rad(leaf[1]))
		var base: Vector2 = (from + way * leaf[0]) * zoom
		var side: float = leaf[2] * zoom
		# LeafArt's base is its unit frame's (-0.7, 0.7) corner and it points
		# along (1, -1): turned 45 degrees past the way it points.
		var degrees: float = leaf[1] + 45.0
		parts.stalks.append([from * zoom, base + way * side * LEAF_TUCK, LEAF_STALK * zoom, LEAF_LIGHT if leaf[3] else LEAF_DARK])
		parts.leaves.append([base - Vector2(-0.35, 0.35).rotated(deg_to_rad(degrees)) * side, side, degrees, leaf[3]])

	## The point on the bough's centre line at `x` (frame units).
	static func bough_at(x: float) -> Vector2:
		var curve: Array = CURVES[0][0] if x <= (CURVES[0][0][3] as Vector2).x else CURVES[1][0]
		var low := 0.0
		var high := 1.0
		for step in range(24):
			var mid := (low + high) * 0.5
			if _point(curve, mid).x < x: low = mid
			else: high = mid
		return _point(curve, (low + high) * 0.5)

	static func _point(curve: Array, t: float) -> Vector2:
		var u := 1.0 - t
		return curve[0] * u * u * u + curve[1] * 3.0 * u * u * t + curve[2] * 3.0 * u * t * t + curve[3] * t * t * t

	static func _bezier(curve: Array, zoom: float) -> PackedVector2Array:
		var points := PackedVector2Array()
		for step in range(25): points.append(_point(curve, step / 24.0) * zoom)
		return points

## A row that gives each child its least width, then shares what is left
## equally up to each child's cap (its ShareRow.CAP meta, or no cap for one
## that expands, else its least width); the rest stays empty at the end. So
## the Orchard's cards keep their board size on a wide screen and narrow
## together on a 16:9 phone. A child that shrinks to the end or centre
## vertically keeps its own height; the others fill the row's height.
class ShareRow extends Container:
	const CAP := &"share_cap"
	var gap := 0.0

	func _init(separation: float) -> void:
		gap = separation

	func _shown() -> Array[Control]:
		var shown: Array[Control] = []
		for child: Node in get_children():
			if child is Control and (child as Control).visible and not (child as Control).top_level: shown.append(child)
		return shown

	func _get_minimum_size() -> Vector2:
		var least := Vector2.ZERO
		var shown := _shown()
		for child: Control in shown:
			var each := child.get_combined_minimum_size()
			least = Vector2(least.x + each.x, maxf(least.y, each.y))
		return least + Vector2(gap * maxi(shown.size() - 1, 0), 0)

	## Each child's width when the row is `room` wide.
	static func widths(floors: Array, caps: Array, room: float) -> Array:
		var given := floors.duplicate()
		var spare := room
		for width: float in floors: spare -= width
		while spare > 0.01:
			var open := range(given.size()).filter(func(index: int) -> bool: return given[index] < caps[index] - 0.01)
			if open.is_empty(): break
			var share := spare / open.size()
			for index: int in open:
				var add := minf(share, caps[index] - given[index])
				given[index] += add
				spare -= add
		return given

	func _notification(what: int) -> void:
		if what != NOTIFICATION_SORT_CHILDREN: return
		var shown := _shown()
		var floors := shown.map(func(child: Control) -> float: return child.get_combined_minimum_size().x)
		var caps := shown.map(func(child: Control) -> float: return maxf(float(child.get_meta(CAP)), child.get_combined_minimum_size().x) if child.has_meta(CAP) else (INF if child.size_flags_horizontal & Control.SIZE_EXPAND else child.get_combined_minimum_size().x))
		var given := widths(floors, caps, size.x - gap * maxi(shown.size() - 1, 0))
		var x := 0.0
		for index in range(shown.size()):
			var child := shown[index]
			var tall := child.get_combined_minimum_size().y
			var y := 0.0
			if child.size_flags_vertical & Control.SIZE_SHRINK_END: y = size.y - tall
			elif child.size_flags_vertical & Control.SIZE_SHRINK_CENTER: y = (size.y - tall) * 0.5
			else: tall = size.y
			fit_child_in_rect(child, Rect2(x, y, given[index], tall))
			x += given[index] + gap
