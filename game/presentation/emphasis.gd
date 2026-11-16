extends RefCounted
## Emphasis in player copy: *word* shows the word in italics. The one place
## that reads the markup: plain() strips it for every surface that shows
## plain text (the registry, logs), and rich_label() draws it, in a synthetic
## italic of the label's own font (a slanted FontVariation of Nunito, no
## italic font file).

## How far the italic leans: x moves this much per unit of height.
const SLANT := 0.2

## *word*: at least one character, no asterisk or line break inside.
const PATTERN := "\\*([^*\\n]+)\\*"
static var _marked := RegEx.create_from_string(PATTERN)

## True when the text has a *word* to emphasise.
static func has_markup(text: String) -> bool:
	return _marked.search(text) != null

## The text with its markup removed: "They *knew*" reads "They knew".
static func plain(text: String) -> String:
	return _marked.sub(text, "$1", true)

## The text as BBCode: emphasis in [i], any other bracket shown as written.
static func bbcode(text: String) -> String:
	return _marked.sub(text.replace("[", "[lb]"), "[i]$1[/i]", true)

## A wrapping label for the text, the size of a plain Label with the same
## words: base is the font the text would otherwise show in.
static func rich_label(text: String, base: Font, size: int, color: Color) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("normal_font", base)
	label.add_theme_font_override("italics_font", italic(base))
	for item: String in ["normal_font_size", "italics_font_size"]:
		label.add_theme_font_size_override(item, size)
	label.add_theme_color_override("default_color", color)
	label.text = bbcode(text)
	return label

## The slanted twin of a font. Made per label: a static cache of fonts would
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

