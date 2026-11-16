extends Control
## About this chapter as a letter (owner-approved envelope board, 16 Nov): the
## chapter's title on the card, and an envelope with the level's stamp,
## postmark and address. A tap turns it over, the seal pops, the flap opens and
## the letter slides out, tilted as if set down by hand, with Back as a coral
## tag taped over its corner. A long letter scrolls under the title while the
## tag stays put. Reduced motion shows the letter at once.
## The words come from Registry.letter (services/chapter_registry.gd).
const Emphasis = preload("res://presentation/emphasis.gd")
const LetterText = preload("res://presentation/letter/letter_text.gd")
const StampArt = preload("res://presentation/letter/stamp_art.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const PEN = preload("res://assets/fonts/pen-date.ttf")
const NUNITO = preload("res://assets/fonts/nunito.ttf")

const CREAM := Color("eceddb")
const PAPER := Color("f7f3e6")
const PAPER_EDGE := Color("e2dac6")
const RULE := Color(0.82, 0.78, 0.69, 0.55)
const ENVELOPE := Color("f0e9d8")
const ENVELOPE_INSIDE := Color("e4dbc6")
const ENVELOPE_FOLD := Color("d6cbb4")
const FLAP := Color("e8dfca")
const INK := Color("343a38")
const SOFT_INK := Color("6e746c")
const POSTMARK := Color(0.24, 0.32, 0.38, 0.62)
const SEAL := Color("91d6c6")
const SEAL_RING := Color("6fb8a6")
const SEAL_LEAF := Color("3a6b5f")
const TAPE := Color(0.98, 0.96, 0.87, 0.72)
## Sizes in canvas units (the 1280 x 720 design). The letter's words are big
## enough to read on a 6-inch phone and the Duo's outer screen.
const TITLE_SIZE := 34
const GREETING_SIZE := 44
const BODY_SIZE := 38
const ADDRESS_SIZE := 40
const MARGIN := 22.0
const ENVELOPE_TILT := -2.0
const PAPER_TILT := 1.2
const TAG_TILT := -4.0
## The share of the envelope left showing as the pocket under the open letter.
const POCKET := 0.24

var envelope: Envelope
var pocket: Pocket
var scroll: ScrollContainer
var paper: PanelContainer
var body: LetterText
var back_button: Button
var opened := false

var _panel: PanelContainer
var _stage: Control
var _paper_holder: MarginContainer
## A plain box the paper sits in: a container would undo the paper's tilt.
var _paper_frame: Control
var _fitting := false
var _letter: Dictionary = {}
var _reduced_motion := false
var _tween: Tween

## title: the chapter's name; letter: Registry.letter; back: the room's shared
## Back button, which this view wears as the tag.
func configure(title: String, letter: Dictionary, title_font: Font, reduced_motion: bool, back: Button) -> void:
	_letter = letter
	_reduced_motion = reduced_motion
	name = "ChapterLetter"
	mouse_filter = Control.MOUSE_FILTER_STOP
	_panel = PanelContainer.new()
	_panel.name = "LetterCard"
	_panel.add_theme_stylebox_override("panel", _card_style())
	add_child(_panel)
	var margin := MarginContainer.new()
	for edge: String in ["left", "top", "right", "bottom"]: margin.add_theme_constant_override("margin_" + edge, int(MARGIN))
	_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	var heading := Label.new()
	heading.text = title
	heading.add_theme_font_override("font", title_font)
	heading.add_theme_font_size_override("font_size", TITLE_SIZE)
	heading.add_theme_color_override("font_color", CREAM)
	column.add_child(heading)
	_stage = Control.new()
	_stage.name = "LetterStage"
	_stage.clip_contents = true
	_stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stage.resized.connect(_place)
	column.add_child(_stage)
	envelope = Envelope.new()
	envelope.letter = letter
	envelope.paper_colour = ENVELOPE
	envelope.stamp = StampArt.texture(str(letter.get("stamp", "teacup")), 1.6, ENVELOPE)
	envelope.pressed.connect(open)
	_stage.add_child(envelope)
	scroll = ScrollContainer.new()
	scroll.name = "LetterScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.visible = false
	_stage.add_child(scroll)
	_paper_holder = MarginContainer.new()
	_paper_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_paper_holder)
	_paper_frame = Control.new()
	_paper_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_paper_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_paper_holder.add_child(_paper_frame)
	paper = _build_paper(letter)
	_paper_frame.add_child(paper)
	_paper_frame.resized.connect(_fit_paper)
	paper.minimum_size_changed.connect(_fit_paper)
	pocket = Pocket.new()
	pocket.visible = false
	_stage.add_child(pocket)
	back_button = back
	_wear_tag(back_button)
	back_button.visible = false
	_stage.add_child(back_button)
	_layout()
	if _reduced_motion: _show_open()

## Opens the envelope: turned over, the seal pops, the flap lifts and the
## letter slides out. Instant with reduced motion (or `instant`).
func open(instant: bool = false) -> void:
	if opened: return
	opened = true
	envelope.disabled = true
	if instant or _reduced_motion:
		_show_open()
		return
	if _tween != null: _tween.kill()
	_tween = create_tween()
	_tween.tween_property(envelope, "scale:x", 0.0, 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_tween.tween_callback(func() -> void: envelope.side_back = true)
	_tween.tween_property(envelope, "scale:x", 1.0, 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_property(envelope, "seal", 1.25, 0.08)
	_tween.tween_property(envelope, "seal", 0.0, 0.1)
	_tween.tween_property(envelope, "flap", 1.0, 0.24).set_trans(Tween.TRANS_SINE)
	_tween.tween_callback(_start_slide)
	_tween.tween_interval(0.0)

func _start_slide() -> void:
	# The envelope drops to its pocket place while the letter rises out of it.
	envelope.front_flaps = false
	pocket.visible = true
	scroll.visible = true
	var rest := _pocket_position()
	var slide := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	slide.tween_property(envelope, "position", rest, 0.3)
	slide.tween_property(pocket, "position", rest, 0.3)
	paper.position.y = _stage.size.y * 0.55
	slide.tween_property(paper, "position:y", 0.0, 0.4).set_delay(0.08)
	slide.chain().tween_callback(_show_open)

## The letter out and the tag on, with no motion.
func _show_open() -> void:
	opened = true
	envelope.disabled = true
	envelope.side_back = true
	envelope.seal = 0.0
	envelope.flap = 1.0
	envelope.front_flaps = false
	envelope.scale = Vector2.ONE
	envelope.position = _pocket_position()
	pocket.position = envelope.position
	pocket.visible = true
	scroll.visible = true
	paper.position.y = 0.0
	back_button.visible = true
	envelope.queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED: _layout()

## The card: as wide as reads well, as tall as the screen allows.
func _layout() -> void:
	if _panel == null: return
	var card := Vector2(minf(size.x - 48.0, 1000.0), size.y - 28.0)
	_panel.size = card
	_panel.position = (size - card) * 0.5

func _place() -> void:
	var stage := _stage.size
	if stage.x <= 0.0: return
	var width := minf(stage.x * 0.84, 780.0)
	var envelope_size := Vector2(width, roundf(width * 0.58))
	for item: Control in [envelope, pocket]:
		item.size = envelope_size
		item.pivot_offset = envelope_size * 0.5
		item.rotation_degrees = ENVELOPE_TILT
	envelope.position = _pocket_position() if opened else (stage - envelope_size) * 0.5
	pocket.position = envelope.position
	scroll.position = Vector2.ZERO
	scroll.size = stage
	var side := maxf(16.0, (stage.x - width * 1.04) * 0.5)
	for edge: String in ["left", "right"]: _paper_holder.add_theme_constant_override("margin_" + edge, int(side))
	_paper_holder.add_theme_constant_override("margin_top", 8)
	# The letter's end can be scrolled up past the pocket.
	_paper_holder.add_theme_constant_override("margin_bottom", int(envelope_size.y * POCKET + 12.0))
	back_button.position = Vector2(4.0, stage.y - back_button.get_combined_minimum_size().y - 10.0)

## The paper as wide as its frame and as tall as its words, the frame as tall
## as the paper, so the scroll knows the letter's length.
func _fit_paper() -> void:
	if _fitting: return
	_fitting = true
	paper.size = Vector2(_paper_frame.size.x, 0.0)
	paper.size = Vector2(_paper_frame.size.x, paper.get_combined_minimum_size().y)
	paper.pivot_offset = paper.size * 0.5
	_paper_frame.custom_minimum_size.y = paper.size.y
	_fitting = false

func _pocket_position() -> Vector2:
	var envelope_size := envelope.size
	return Vector2((_stage.size.x - envelope_size.x) * 0.5, _stage.size.y - envelope_size.y * POCKET)

func _build_paper(letter: Dictionary) -> PanelContainer:
	var sheet := PanelContainer.new()
	sheet.name = "LetterPaper"
	var look := StyleBoxFlat.new()
	look.bg_color = PAPER
	look.border_color = PAPER_EDGE
	look.set_border_width_all(2)
	look.shadow_color = Color(0, 0, 0, 0.28)
	look.shadow_size = 12
	look.shadow_offset = Vector2(4, 8)
	look.content_margin_left = 40
	look.content_margin_right = 40
	look.content_margin_top = 30
	look.content_margin_bottom = 34
	sheet.add_theme_stylebox_override("panel", look)
	sheet.rotation_degrees = PAPER_TILT
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 12)
	sheet.add_child(lines)
	lines.add_child(_pen_label(str(letter.get("greeting", "")), GREETING_SIZE, HORIZONTAL_ALIGNMENT_LEFT))
	body = LetterText.new()
	body.name = "LetterBody"
	body.configure(str(letter.get("body", "")), PEN, BODY_SIZE, INK, RULE)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lines.add_child(body)
	lines.add_child(_pen_label(str(letter.get("signoff", "")), GREETING_SIZE, HORIZONTAL_ALIGNMENT_RIGHT))
	return sheet

func _pen_label(text: String, size: int, align: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = align
	label.add_theme_font_override("font", PEN)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", INK)
	return label

## The shared Back button as a coral paper tag in the pen hand, taped on.
func _wear_tag(button: Button) -> void:
	button.add_theme_font_override("font", PEN)
	button.add_theme_font_size_override("font_size", 40)
	button.custom_minimum_size = Vector2(170, 66)
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.rotation_degrees = TAG_TILT
	button.resized.connect(func() -> void: button.pivot_offset = button.size * 0.5)
	var tape := ColorRect.new()
	tape.name = "Tape"
	tape.color = TAPE
	tape.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tape.size = Vector2(70, 22)
	tape.position = Vector2(50, -12)
	button.add_child(tape)

func _card_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("163c36")
	style.set_corner_radius_all(16)
	style.set_border_width_all(1)
	style.border_color = Color("54766a")
	return style

## The envelope: its front (stamp, postmark, address) until it turns over,
## then its back (flap, seal), the flap opening as `flap` goes from 0 to 1.
## With front_flaps off, the side and bottom flaps are left to the Pocket,
## which draws them over the letter.
class Envelope extends Button:
	var letter: Dictionary = {}
	var stamp: Texture2D
	var paper_colour := ENVELOPE
	var side_back := false:
		set(value):
			side_back = value
			queue_redraw()
	var seal := 1.0:
		set(value):
			seal = value
			queue_redraw()
	var flap := 0.0:
		set(value):
			flap = value
			queue_redraw()
	var front_flaps := true:
		set(value):
			front_flaps = value
			queue_redraw()

	func _init() -> void:
		name = "Envelope"
		flat = true
		focus_mode = Control.FOCUS_ALL
		accessibility_name = PlayerCopy.LETTER_OPEN
		tooltip_text = PlayerCopy.LETTER_OPEN
		for state: String in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
			add_theme_stylebox_override(state, StyleBoxEmpty.new())

	func _draw() -> void:
		var box := Rect2(Vector2.ZERO, size)
		if not side_back:
			_draw_front(box)
			return
		draw_rect(box, ENVELOPE_INSIDE)
		var top := Vector2(size.x * 0.5, lerpf(size.y * 0.6, -size.y * 0.55, flap))
		var flap_points := PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), top])
		if flap > 0.5: draw_colored_polygon(flap_points, FLAP)
		if front_flaps: Pocket.draw_flaps(self, size)
		if flap <= 0.5:
			draw_colored_polygon(flap_points, FLAP)
			draw_polyline(PackedVector2Array([Vector2.ZERO, top, Vector2(size.x, 0)]), ENVELOPE_FOLD, 2.0, true)
		if seal > 0.0:
			var at := top - Vector2(0, size.y * 0.02)
			var r := size.y * 0.075 * seal
			draw_circle(at, r, SEAL)
			draw_arc(at, r, 0, TAU, 32, SEAL_RING, maxf(1.0, r * 0.12), true)
			draw_colored_polygon(PackedVector2Array([at + Vector2(0, -r * 0.55), at + Vector2(r * 0.4, 0), at + Vector2(0, r * 0.55), at + Vector2(-r * 0.4, 0)]), SEAL_LEAF)
		draw_rect(box, ENVELOPE_FOLD, false, 2.0)

	func _draw_front(box: Rect2) -> void:
		draw_rect(box, paper_colour)
		draw_rect(box, ENVELOPE_FOLD, false, 2.0)
		var stamp_size := stamp.get_size() * minf(1.0, size.y * 0.3 / stamp.get_size().y)
		var stamp_at := Vector2(size.x - stamp_size.x - size.x * 0.045, size.y * 0.07)
		draw_texture_rect(stamp, Rect2(stamp_at, stamp_size), false)
		# The ring overlaps the stamp's left edge; its name sits on the paper.
		var radius := stamp_size.y * 0.42
		_draw_postmark(stamp_at + Vector2(-radius * 0.55, stamp_size.y * 0.5), radius)
		var x := size.x * 0.3
		var y := size.y * 0.58
		var line := ADDRESS_SIZE * 1.25
		var address: Array = letter.get("address", [])
		PEN.draw_string(get_canvas_item(), Vector2(x, y), PlayerCopy.LETTER_TO, HORIZONTAL_ALIGNMENT_LEFT, -1, ADDRESS_SIZE, INK)
		if address.size() > 0: PEN.draw_string(get_canvas_item(), Vector2(x + 24, y + line), str(address[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, int(ADDRESS_SIZE * 0.92), INK)
		if address.size() > 1: PEN.draw_string(get_canvas_item(), Vector2(x + 24, y + line * 1.85), str(address[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, int(ADDRESS_SIZE * 0.78), SOFT_INK)

	## A ring over the stamp's left edge with the post office's name in it,
	## and wavy cancel lines running left onto the paper.
	func _draw_postmark(centre: Vector2, radius: float) -> void:
		var width := maxf(1.5, radius * 0.06)
		draw_arc(centre, radius, 0, TAU, 48, POSTMARK, width, true)
		draw_arc(centre, radius * 0.84, 0, TAU, 48, POSTMARK, width * 0.6, true)
		var words := str(letter.get("postmark", "")).to_upper().split(" ", false)
		var font_size := int(radius * 0.26)
		for i in range(words.size()):
			var word: String = words[i]
			var w := NUNITO.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			NUNITO.draw_string(get_canvas_item(), centre + Vector2(-w * 0.5, (i - (words.size() - 1) * 0.5) * font_size * 1.15 + font_size * 0.35), word, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, POSTMARK)
		for i in range(4):
			var y := centre.y + (i - 1.5) * radius * 0.38
			var points := PackedVector2Array()
			var along := 0.0
			while along <= radius * 2.6:
				points.append(Vector2(centre.x - radius - 4.0 - along, y + sin(along / (radius * 0.32)) * radius * 0.08))
				along += 4.0
			draw_polyline(points, POSTMARK, width, true)

## The envelope's side and bottom flaps over the letter's foot, where it sits
## in the open envelope.
class Pocket extends Control:
	func _init() -> void:
		name = "Pocket"
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		Pocket.draw_flaps(self, size)

	static func draw_flaps(canvas: CanvasItem, area: Vector2) -> void:
		var middle := Vector2(area.x * 0.5, area.y * 0.56)
		canvas.draw_colored_polygon(PackedVector2Array([Vector2.ZERO, middle, Vector2(0, area.y)]), ENVELOPE)
		canvas.draw_colored_polygon(PackedVector2Array([Vector2(area.x, 0), middle, Vector2(area.x, area.y)]), ENVELOPE)
		canvas.draw_colored_polygon(PackedVector2Array([Vector2(0, area.y), Vector2(area.x * 0.5, area.y * 0.46), Vector2(area.x, area.y)]), ENVELOPE.darkened(0.03))
		canvas.draw_polyline(PackedVector2Array([Vector2.ZERO, middle, Vector2(area.x, 0)]), ENVELOPE_FOLD, 2.0, true)
		canvas.draw_polyline(PackedVector2Array([Vector2(0, area.y), Vector2(area.x * 0.5, area.y * 0.46), Vector2(area.x, area.y)]), ENVELOPE_FOLD, 2.0, true)
		canvas.draw_rect(Rect2(Vector2.ZERO, area), ENVELOPE_FOLD, false, 2.0)
