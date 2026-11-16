extends RefCounted
## Emphasis in player copy: *word* is written leaning, with a hand-drawn wavy
## line under it. The one place that reads the markup: plain() strips it for
## every surface that shows plain text (the registry, logs), and words() splits
## it for presentation/letter/letter_text.gd, the one place that draws it. The
## lean is a slanted FontVariation of the text's own font (no italic file).

## How far the lean goes: x moves this much per unit of height.
const SLANT := 0.2
## The wavy line: how far it swings up and down, and how long one wave is.
const WAVE_HEIGHT := 0.07
const WAVE_LENGTH := 0.55

## *word*: at least one character, no asterisk or line break inside.
const PATTERN := "\\*([^*\\n]+)\\*"
static var _marked := RegEx.create_from_string(PATTERN)

## The text with its markup removed: "They *knew*" reads "They knew".
static func plain(text: String) -> String:
	return _marked.sub(text, "$1", true)

## The text as pieces to lay out: [{"text", "emphasis", "space"}], where a
## piece ends at a space or where emphasis starts or stops, and "space" is true
## when a space comes before it (a line may break there). "*knew*," gives
## "knew" (emphasis) then "," glued to it.
static func words(text: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var at := 0
	for found: RegExMatch in _marked.search_all(text):
		_add_pieces(result, text.substr(at, found.get_start() - at), false)
		_add_pieces(result, found.get_string(1), true, found.get_start() > 0 and text[found.get_start() - 1] == " ")
		at = found.get_end()
	_add_pieces(result, text.substr(at), false)
	return result

## The slanted twin of a font. Made per use: a static cache of fonts would
## outlive the renderer at exit.
static func italic(base: Font) -> FontVariation:
	var slanted := FontVariation.new()
	if base is FontVariation:
		slanted.base_font = base.base_font
		slanted.variation_opentype = base.variation_opentype
		slanted.variation_embolden = base.variation_embolden
	else:
		slanted.base_font = base
	slanted.variation_transform = Transform2D(Vector2(1.0, SLANT), Vector2(0.0, 1.0), Vector2.ZERO)
	return slanted

## The wavy line under emphasis from x to x + width at height y, for a font
## this size: a gentle wave, the same for the same words every time.
static func underline(x: float, y: float, width: float, font_size: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var step := maxf(2.0, font_size * 0.08)
	var swing := font_size * WAVE_HEIGHT
	var wave := font_size * WAVE_LENGTH
	var along := 0.0
	while along < width:
		points.append(Vector2(x + along, y + sin(along / wave * TAU) * swing))
		along += step
	points.append(Vector2(x + width, y + sin(width / wave * TAU) * swing))
	return points

static func _add_pieces(into: Array[Dictionary], text: String, emphasis: bool, first_spaced: bool = false) -> void:
	if text.is_empty(): return
	var parts := text.split(" ")
	for i in range(parts.size()):
		if parts[i].is_empty(): continue
		# split(" ") leaves "" before a leading space, so a piece after one has i > 0.
		var spaced := i > 0 or first_spaced
		into.append({"text": parts[i], "emphasis": emphasis, "space": spaced and not into.is_empty()})
