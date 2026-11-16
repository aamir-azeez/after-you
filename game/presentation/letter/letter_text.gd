extends Control
## A letter's words, wrapped to this control's width in one font, with
## *emphasis* leaning and underlined by a hand-drawn wave
## (presentation/emphasis.gd), and a faint ruled line under each line of
## writing. Its height follows its width, so it sits in a container like a
## wrapping Label.
const Emphasis = preload("res://presentation/emphasis.gd")

var font: Font
var font_size := 34
var color := Color.BLACK
var rule_color := Color(0, 0, 0, 0)
## Line height as a share of the font size.
var spacing := 1.42

var _pieces: Array[Dictionary] = []
var _italic: Font
## [{"text", "emphasis", "at": Vector2 (baseline start), "width"}], for the width last laid out.
var _placed: Array[Dictionary] = []
var _lines := 0
var _laid_width := -1.0

func configure(text: String, text_font: Font, size: int, ink: Color, rules: Color) -> void:
	font = text_font
	font_size = size
	color = ink
	rule_color = rules
	_italic = Emphasis.italic(text_font)
	_pieces = Emphasis.words(text)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_laid_width = -1.0
	_layout()

## Lines of writing at the current width.
func line_count() -> int:
	return _lines

## The words as drawn, in order: [{"text", "emphasis", "at", "width"}].
func placed() -> Array[Dictionary]:
	return _placed

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and not is_equal_approx(size.x, _laid_width): _layout()

func _get_minimum_size() -> Vector2:
	return Vector2(0, _lines * _line_height())

func _line_height() -> float:
	return roundf(font_size * spacing)

func _layout() -> void:
	if font == null: return
	var width := size.x if size.x > 0.0 else 600.0
	_laid_width = size.x
	_placed.clear()
	var space := font.get_string_size(" ", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var x := 0.0
	var line := 0
	var ascent := font.get_ascent(font_size)
	var top_gap := (_line_height() - font.get_height(font_size)) * 0.5
	# Pieces glued to the one before (no space) move to a new line with it.
	var groups: Array = []
	for piece: Dictionary in _pieces:
		if piece.space or groups.is_empty(): groups.append([])
		groups[-1].append(piece)
	for group: Array in groups:
		var group_width := 0.0
		for piece: Dictionary in group: group_width += _width(piece)
		var lead := space if x > 0.0 else 0.0
		if x > 0.0 and x + lead + group_width > width:
			line += 1
			x = 0.0
			lead = 0.0
		x += lead
		for piece: Dictionary in group:
			var w := _width(piece)
			_placed.append({"text": piece.text, "emphasis": piece.emphasis, "at": Vector2(x, line * _line_height() + top_gap + ascent), "width": w})
			x += w
	_lines = line + 1 if not _placed.is_empty() else 0
	update_minimum_size()
	queue_redraw()

func _width(piece: Dictionary) -> float:
	var used: Font = _italic if piece.emphasis else font
	var w := used.get_string_size(piece.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	# The lean pushes a word's top to the right: leave room so the next word clears it.
	return w + (font_size * Emphasis.SLANT * 0.5 if piece.emphasis else 0.0)

func _draw() -> void:
	if font == null: return
	if rule_color.a > 0.0:
		for line in range(_lines):
			var y := (line + 1) * _line_height() - font_size * 0.12
			draw_line(Vector2(0, y), Vector2(size.x, y), rule_color, maxf(1.0, font_size * 0.04))
	for item: Dictionary in _placed:
		var used: Font = _italic if item.emphasis else font
		used.draw_string(get_canvas_item(), item.at, item.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
		if item.emphasis:
			var wave := Emphasis.underline(item.at.x, item.at.y + font_size * 0.16, item.width - font_size * Emphasis.SLANT * 0.5, font_size)
			draw_polyline(wave, color, maxf(1.5, font_size * 0.055), true)
