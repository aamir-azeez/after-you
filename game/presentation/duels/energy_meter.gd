extends PanelContainer
## The duel energy meter, the one component every energy surface shows it
## through (boards 10, ENERGY-PLAN.md "Colours for the build"):
## - pill(): the Duels lobby header's pill beside the title: the sprouts (full
##   ones lit, empty ones outlined), "Energy 3 of 5" and under it, only while
##   below the max, "Next in 6 min";
## - card(): the out-of-energy card's big empty meter and "Your next energy
##   comes in 6 min." under it.
## Both read services/duel_energy.gd for one player (a scope) and draw again
## when it changes. Nothing ticks: the minutes line is drawn again by one
## timer set to the next moment what it shows changes (at most once a minute,
## never seconds), only while the meter shows. A meter with nothing kept (or
## energy off) hides itself. No red, no sound, no hurry words.
const DuelEnergy = preload("res://services/duel_energy.gd")
const SproutMark = preload("res://presentation/kit/sprout_mark.gd")
const DashedBox = preload("res://presentation/kit/dashed_box.gd")
const SettingsKit = preload("res://presentation/settings_kit.gd")
const UiTokens = preload("res://presentation/ui_tokens.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")

const PILL := "pill"
const CARD := "card"
## The pill's fill and ring, its words and its quiet line.
const PILL_FILL := Color("18433e")
const PILL_RING := Color("2f6359")
const RING_WIDTH := 1.5
const LABEL := UiTokens.CREAM
const LINE := Color("afc6be")
const PILL_RADIUS := 18.0
## Sprout sizes and gaps as the boards draw them.
const PILL_SPROUT := 30.0
const PILL_GAP := 2.0
const CARD_SPROUT := 66.0
const CARD_GAP := 14.0
## A moment past each change, so the redraw lands after it.
const LATE_S := 0.05

var store: RefCounted
var scope: Dictionary = {}
var style := PILL
var _sprouts: Control
var _label: Label
var _line: Control
var _timer: Timer

## The lobby header's pill for the player of `scope` ({server, owner}).
static func pill(energy: RefCounted, player: Dictionary) -> PanelContainer:
	return _made(energy, player, PILL)

## The out-of-energy card's meter for the player of `scope`.
static func card(energy: RefCounted, player: Dictionary) -> PanelContainer:
	return _made(energy, player, CARD)

static func _made(energy: RefCounted, player: Dictionary, kind: String) -> PanelContainer:
	var meter: PanelContainer = load("res://presentation/duels/energy_meter.gd").new()
	meter.name = "EnergyMeter" if kind == PILL else "EnergyMeterCard"
	meter.store = energy
	meter.scope = player
	meter.style = kind
	meter._build()
	return meter

func _build() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(refresh)
	add_child(_timer, false, Node.INTERNAL_MODE_BACK)
	if style == PILL:
		add_theme_stylebox_override("panel", _pad(StyleBoxEmpty.new(), 16.0, 6.0))
		custom_minimum_size.y = 56.0
		draw.connect(_paint)
		resized.connect(queue_redraw)
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 12)
		add_child(row)
		_sprouts = SproutMark.row(0, 0, PILL_SPROUT, PILL_GAP, true)
		row.add_child(_sprouts)
		var words := VBoxContainer.new()
		words.mouse_filter = Control.MOUSE_FILTER_IGNORE
		words.alignment = BoxContainer.ALIGNMENT_CENTER
		words.add_theme_constant_override("separation", -2)
		row.add_child(words)
		_label = _text(18, LABEL, 800)
		_label.name = "EnergyLabel"
		words.add_child(_label)
		var next := _text(14, LINE, 600)
		next.name = "EnergyNext"
		words.add_child(next)
		_line = next
	else:
		add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		var column := VBoxContainer.new()
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_theme_constant_override("separation", 22)
		add_child(column)
		_sprouts = SproutMark.row(0, 0, CARD_SPROUT, CARD_GAP, true)
		column.add_child(_sprouts)
		var next := RichTextLabel.new()
		next.name = "EnergyNext"
		next.bbcode_enabled = true
		next.fit_content = true
		next.scroll_active = false
		next.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		next.mouse_filter = Control.MOUSE_FILTER_IGNORE
		next.get_v_scroll_bar().mouse_filter = Control.MOUSE_FILTER_IGNORE
		next.add_theme_font_override("normal_font", SettingsKit.font(600))
		next.add_theme_font_override("bold_font", SettingsKit.font(800))
		next.add_theme_font_size_override("normal_font_size", 22)
		next.add_theme_font_size_override("bold_font_size", 22)
		next.add_theme_color_override("default_color", LABEL)
		column.add_child(next)
		_line = next
	refresh()

func _enter_tree() -> void:
	if store != null and not store.changed.is_connected(_changed): store.changed.connect(_changed)
	# Once its timer has entered the tree with it.
	refresh.call_deferred()

func _exit_tree() -> void:
	if store != null and store.changed.is_connected(_changed): store.changed.disconnect(_changed)
	if is_instance_valid(_timer): _timer.stop()

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_inside_tree():
		if is_visible_in_tree(): refresh()
		elif is_instance_valid(_timer): _timer.stop()

func _changed(server: String, owner: String) -> void:
	if DuelEnergy.scope_key(server, owner) == DuelEnergy.scope_key(str(scope.get("server", "")), str(scope.get("owner", ""))): refresh()

## What the meter shows now ({} while nothing is kept).
func reading() -> Dictionary:
	if store == null or scope.is_empty(): return {}
	return store.meter(str(scope.server), str(scope.owner))

## Draws what the kept meter says now, and sets the one timer for its next change.
func refresh() -> void:
	if not is_instance_valid(_sprouts): return
	var now := reading()
	# The pill shows only with a meter to show; the card keeps its place (an empty meter until the read lands).
	if style == PILL: visible = not now.is_empty()
	# The card opened on a refusal before any read draws the usual max, empty, until the read lands.
	var top := int(now.get("max", 0 if style == PILL else DuelEnergy.PLAIN_MAX))
	var have := int(now.get("energy", 0))
	var next := int(now.get("next_ms", 0))
	_sprouts.show_count(have, top)
	if style == PILL:
		_label.text = PlayerCopy.ENERGY_METER % [have, top]
		(_line as Label).text = PlayerCopy.ENERGY_NEXT % DuelEnergy.minutes(next) if next > 0 else ""
		_line.visible = next > 0
	else:
		(_line as RichTextLabel).text = PlayerCopy.ENERGY_OUT_NEXT % ("[b]%s[/b]" % (PlayerCopy.ENERGY_MINUTES % DuelEnergy.minutes(next))) if next > 0 else ""
		_line.visible = next > 0
	var wait := DuelEnergy.next_change_ms(next)
	if wait > 0 and _timer.is_inside_tree() and is_visible_in_tree(): _timer.start(wait / 1000.0 + LATE_S)
	elif is_instance_valid(_timer) and _timer.is_inside_tree(): _timer.stop()

## The pill's fill and its ring, inside its own edge.
func _paint() -> void:
	var box := Rect2(Vector2.ZERO, size)
	if box.size.x <= 2.0 or box.size.y <= 2.0: return
	draw_colored_polygon(DashedBox.outline(box, PILL_RADIUS), PILL_FILL)
	var inset := RING_WIDTH * 0.5
	var ring := DashedBox.outline(box.grow(-inset), PILL_RADIUS - inset)
	ring.append(ring[0])
	draw_polyline(ring, PILL_RING, RING_WIDTH, true)

static func _text(font_size: int, colour: Color, weight: int) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", SettingsKit.font(weight))
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	return label

static func _pad(style_box: StyleBox, horizontal: float, vertical: float) -> StyleBox:
	style_box.content_margin_left = horizontal
	style_box.content_margin_right = horizontal
	style_box.content_margin_top = vertical
	style_box.content_margin_bottom = vertical
	return style_box
