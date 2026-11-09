extends PanelContainer
## The Wardrobe's Orchard (Fruits board 4a), the right panel while the Orchard
## chip is picked (presentation/wardrobe_page.gd shows it in place of the
## cream shop panel): the plum Orchard (kit/orchard_surface.gd) with a branch,
## leaves and Fruits overhead; "The Orchard" and "Every item stays in the shop"
## beside the slot chips (Hat, Body, Leaf) with the Orchard chip picked; the
## Orchard items on cream plinths, each on a still pip wearing it
## (kit/pip_avatar.gd), with its name, its tier's tag and its Fruit price (or
## Yours and Wearing); the sprigs as leaf tiles under "Sprigs · 10 each"; and
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
const CARD_PIP := Vector2(140, 168)
const TILE := 77.0
const RADIUS := 22

signal item_chosen(id: String)
signal kind_chosen(kind: String)

var _status: Label
var _seg: HBoxContainer
var _cards: HBoxContainer
var _sprigs: HBoxContainer
var _each: Label
var _sets: VBoxContainer
var _model: Dictionary = {}
var _key := ""

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
	titles.add_child(ShopKit.text(PlayerCopy.ORCHARD_TITLE, 32, OrchardSurface.TEXT, ShopKit.heading_font()))
	var stays := ShopKit.text(PlayerCopy.WARDROBE_STAYS, 17, OrchardSurface.TEXT_SOFT)
	stays.name = "OrchardStays"
	titles.add_child(stays)
	header.add_child(titles)
	var seg_panel := PanelContainer.new()
	seg_panel.name = "OrchardChips"
	seg_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	seg_panel.add_theme_stylebox_override("panel", ThemeRules.padded(ThemeRules.rounded(GLASS, 15), 4, 4))
	header.add_child(seg_panel)
	_seg = HBoxContainer.new()
	_seg.add_theme_constant_override("separation", 4)
	seg_panel.add_child(_seg)
	_status = ShopKit.text("", 16, OrchardSurface.TEXT_SOFT)
	_status.name = "OrchardStatus"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)
	_cards = HBoxContainer.new()
	_cards.name = "OrchardItems"
	_cards.add_theme_constant_override("separation", 24)
	column.add_child(_cards)
	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(filler)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 24)
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
	bottom.add_child(_sets)

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
		_fill(_sprigs, sprigs.map(_tile))
		_fill(_sets, sets.map(_set_card))
		_each.text = _each_line(sprigs)
		(_sprigs.get_parent() as Control).visible = not sprigs.is_empty()
	_restyle()

## "· 10 each" while every sprig sells at one price, else nothing.
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
	var card := _pickable(str(entry.id), str(entry.name), Vector2(CARD_SIZE.x, 0))
	card.name = "OrchardCard_" + str(entry.id)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 4)
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.add_child(column)
	var plinth := _plinth(CARD_SIZE, 17)
	column.add_child(plinth)
	var pip := PipAvatar.new(true, SpiritLook.PEACH, CARD_PIP, true)
	pip.outfit = Outfit.of(str(entry.id))
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
	var card := _pickable(str(entry.id), str(entry.name), Vector2(515, 103))
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

## "Apple leaf, Fruit cap and Orchard skin".
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

## The ring on the picked card, tile or set; the rest without it.
func _restyle() -> void:
	var picked := str(_model.get("selected", ""))
	for box: Container in [_cards, _sprigs, _sets]:
		for node: Node in box.get_children():
			if not node is Button: continue
			var on := str(node.get_meta("item_id", "")) == picked
			(node as Button).set_pressed_no_signal(on)
			var ring: Node = node.find_child("OrchardRing", true, false)
			if ring != null: (ring as Control).visible = on

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
## leaves and three Fruits (kit/fruit_mark.gd's render). Once per resize.
class Branch extends Control:
	const FRAME_WIDTH := 1715.0
	const BOUGH := [[Vector2(-20, 70), Vector2(260, 30), Vector2(520, 120), Vector2(820, 80)], [Vector2(820, 80), Vector2(1120, 40), Vector2(1380, 30), Vector2(1740, 96)]]
	const TWIGS := [[Vector2(380, 82), Vector2(420, 120), Vector2(470, 130), Vector2(520, 128)], [Vector2(1180, 64), Vector2(1220, 30), Vector2(1270, 20), Vector2(1320, 26)], [Vector2(960, 70), Vector2(990, 110), Vector2(1010, 140), Vector2(1000, 170)]]
	## [centre, side, degrees, light] in the board's frame.
	const LEAVES := [[Vector2(155, 57), 70.0, -30.0, false], [Vector2(670, 100), 60.0, 150.0, true], [Vector2(1272, 36), 64.0, 10.0, false], [Vector2(1588, 98), 56.0, 120.0, true]]
	## [centre, side] in the board's frame.
	const FRUIT_SPOTS := [[Vector2(555, 105), 70.0], [Vector2(1070, 126), 60.0], [Vector2(1336, 46), 72.0]]
	var _render: Texture2D

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		# The bough runs off both edges; the panel's own rounded edge ends it.
		clip_contents = true
		_render = FruitMark.render()
		resized.connect(queue_redraw)

	func _draw() -> void:
		if size.x <= 0.0: return
		var zoom := size.x / FRAME_WIDTH
		for curve: Array in BOUGH: draw_polyline(_bezier(curve, zoom), BRANCH, 16.0 * zoom, true)
		for curve: Array in TWIGS: draw_polyline(_bezier(curve, zoom), BRANCH, 8.0 * zoom, true)
		for leaf: Array in LEAVES: LeafArt.draw(self, leaf[0] * zoom, leaf[1] * zoom, leaf[2], LEAF_LIGHT if leaf[3] else LEAF_DARK)
		for spot: Array in FRUIT_SPOTS:
			var side: float = spot[1] * zoom
			FruitMark.draw_render(self, _render, Rect2(spot[0] * zoom - Vector2(side, side) * 0.5, Vector2(side, side)))

	static func _bezier(curve: Array, zoom: float) -> PackedVector2Array:
		var points := PackedVector2Array()
		for step in range(25):
			var t := step / 24.0
			var u := 1.0 - t
			points.append((curve[0] * u * u * u + curve[1] * 3.0 * u * u * t + curve[2] * 3.0 * u * t * t + curve[3] * t * t * t) * zoom)
		return points
