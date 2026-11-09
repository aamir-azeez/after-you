extends PanelContainer
## The Sunshine card at the foot of the Turns with friends card on the Pollen
## page (Fruits board 7): the warm sun, its title and what it does, a dot for
## each of its turns (the used ones pale, the ones left golden), "21 of 24
## turns left", and the price button (the Fruit mark and the price), only
## while a new one can be bought: none left and Fruit spending not blocked.
## A tap on it is `buy_pressed`; presentation/fruit_spend_flow.gd decides
## between the confirm card and the short card. The button needs the server,
## so it greys offline (presentation/offline_hold.gd).
##
## Every number is the server's (services/fruit_wallet.gd sunshine). Pure
## drawing: no timer, no motion; the dots draw once per resize.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const ControlTheme = preload("res://presentation/control_theme.gd")
const ShopKit = preload("res://presentation/kit/shop_kit.gd")
const SunMark = preload("res://presentation/kit/sun_mark.gd")
const CurrencyMark = preload("res://presentation/kit/currency_mark.gd")
const OfflineHold = preload("res://presentation/offline_hold.gd")
const PollenMoney = preload("res://services/pollen_money.gd")
const Orchard = preload("res://presentation/kit/orchard_surface.gd")

const FILL := Color("f8cf88")
const EDGE := Color("efbd6c")
const INK := Color("3b2a14")
const SOFT_INK := Color("6b5330")
## The big sun, set into the card's top left corner so the card cuts it as drawn.
const SUN := 196.0
const SUN_AT := Vector2(-44, -40)
## Room kept left of the words for the sun.
const SUN_ROOM := 150

signal buy_pressed(button: Button)

var buy_button: Button = null
var dots: Dots

## A card for `sunshine` ({left, turns, price}); `buyable`: the price button shows.
static func make(sunshine: Dictionary, buyable: bool, title_font: Font = null, say: Callable = Callable()) -> Control:
	var card: PanelContainer = load("res://presentation/sunshine_card.gd").new()
	card._build(sunshine, buyable, title_font, say)
	return card

func _build(sunshine: Dictionary, buyable: bool, title_font: Font, say: Callable) -> void:
	name = "SunshineCard"
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", ControlTheme.padded(ControlTheme.rounded(FILL, 18, EDGE), 20.0, 14.0))
	var art := Control.new()
	art.name = "SunshineArt"
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(art)
	var sun := SunMark.make(SUN, SunMark.ART)
	sun.position = SUN_AT
	sun.size = Vector2(SUN, SUN)
	art.add_child(sun)
	var inset := MarginContainer.new()
	inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inset.add_theme_constant_override("margin_left", SUN_ROOM)
	add_child(inset)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 6)
	inset.add_child(column)
	var title := ShopKit.text(PlayerCopy.SUNSHINE_TITLE, 28, INK, title_font if title_font != null else ShopKit.heading_font())
	title.name = "SunshineTitle"
	column.add_child(title)
	var note := ShopKit.text(PlayerCopy.SUNSHINE_NOTE, 16, SOFT_INK)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(note)
	var turns := int(sunshine.get("turns", 0))
	var left := clampi(int(sunshine.get("left", 0)), 0, turns)
	dots = Dots.new(turns, left)
	column.add_child(dots)
	var foot := HBoxContainer.new()
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot.add_theme_constant_override("separation", 12)
	column.add_child(foot)
	var count := ShopKit.text(PlayerCopy.SUNSHINE_LEFT % [left, turns], 20, INK, ShopKit.bold_font())
	count.name = "SunshineLeft"
	count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(count)
	if not buyable: return
	var price := int(sunshine.get("price", 0))
	var content := HBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	content.add_child(CurrencyMark.beside(CurrencyMark.FRUITS, 22))
	content.add_child(ShopKit.text(PollenMoney.grouped(price), 22, Orchard.TEXT, ShopKit.bold_font()))
	buy_button = ShopKit.content_button(content, 52.0)
	buy_button.name = "SunshineBuy"
	buy_button.accessibility_name = PlayerCopy.SUNSHINE_BUY % PollenMoney.grouped(price)
	buy_button.tooltip_text = buy_button.accessibility_name
	buy_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	Orchard.plum_button(buy_button)
	buy_button.pressed.connect(func() -> void: buy_pressed.emit(buy_button))
	OfflineHold.hold(buy_button, say)
	foot.add_child(buy_button)

## The turns as two rows of dots: the used ones first, pale, then the ones left, golden.
class Dots extends Control:
	const SIDE := 24.0
	const GAP := 7.0
	const PER_ROW := 12
	const GOLD := Color("f2be58")
	const GOLD_LIGHT := Color("fde7a8")
	const GOLD_EDGE := Color("d8973f")
	const PALE := Color("fbeccc")
	const PALE_EDGE := Color("e2c389")
	var turns := 0
	var left := 0

	func _init(count: int, remaining: int) -> void:
		name = "SunshineDots"
		turns = maxi(count, 0)
		left = clampi(remaining, 0, turns)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var rows := ceili(turns / float(PER_ROW))
		custom_minimum_size = Vector2(mini(turns, PER_ROW) * (SIDE + GAP) - GAP, rows * (SIDE + GAP) - GAP) if turns > 0 else Vector2.ZERO
		resized.connect(queue_redraw)

	## How many dots show a turn left (tests).
	func golden() -> int:
		return left

	func _draw() -> void:
		var used := turns - left
		for index in range(turns):
			var centre := Vector2((index % PER_ROW) * (SIDE + GAP), floori(index / float(PER_ROW)) * (SIDE + GAP)) + Vector2.ONE * SIDE * 0.5
			var radius := SIDE * 0.5
			if index < used:
				draw_circle(centre, radius, PALE, true, -1.0, true)
				draw_arc(centre, radius - 1.0, 0.0, TAU, 24, PALE_EDGE, 1.5, true)
				continue
			draw_circle(centre, radius, GOLD_EDGE, true, -1.0, true)
			draw_circle(centre + Vector2(0, -1), radius - 1.5, GOLD, true, -1.0, true)
			draw_circle(centre + Vector2(-radius, -radius) * 0.28, radius * 0.38, Color(GOLD_LIGHT, 0.8), true, -1.0, true)
