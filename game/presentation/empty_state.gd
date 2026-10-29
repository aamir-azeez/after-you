extends Container
## An empty list's placeholder: faint dashed copies of the list's own cards
## with small scenes in their pictures, and a title and line under them. On the
## wide Replays page the rows keep the left and the text (with a preview card
## or the screen's own button) takes the right. It draws in _draw only, which
## Godot reruns on a resize or a content change: no per-frame work and no
## motion. Screens add it with ControlTheme.empty_state() and rebuild their
## list as usual, which frees it when the first item arrives.
const Art = preload("res://presentation/empty_state_art.gd")
const HEADING_FONT = preload("res://assets/fonts/fredoka.ttf")
const UiTokens = preload("res://presentation/ui_tokens.gd")
const CREAM := UiTokens.CREAM
const MUTED := UiTokens.SOFT
const SIDE_GAP := 18.0
const ROW_GAP := 10.0
const TEXT_GAP := 6.0
const TEXT_TOP := 22.0
const TEXT_MAX := 520.0
## In the wide preview card: the smallest picture, and the room under the
## picture besides the text (gap above the text, gap and button below it).
const PICTURE_MIN := 80.0
const PREVIEW_BELOW := 14.0 + 16.0 + 50.0
const FADES := [1.0, 0.6, 0.35, 0.18]
## Ghost rows above the text at most, so the text stays close to the art.
const STACKED_ROWS := 3
## Each spot: its list's card, the scene in each row's picture, an optional
## scene for the wide preview card, and links the kit draws between two rows'
## pictures as [from row, to row, kind]. Adding a spot is one row here.
const SPOTS := {
	"rooms": {"card": "room", "rows": ["invite"]},
	"rooms_completed": {"card": "room", "rows": ["finished"]},
	"friends": {"card": "friend", "rows": ["friend", "friend_next"], "links": [[1, 0, "plane"]]},
	"replays_solo": {"card": "replay", "preview": "footprints"},
	"replays_together": {"card": "replay", "rows": ["polaroid"]},
	# The empty Duels lobby: three versions for the owner to pick from (duels_screen.gd EMPTY_ART).
	"duels_a": {"card": "room", "rows": ["duel_start", "duel_other"]},
	"duels_b": {"card": "room", "rows": ["duel_rivals", "duel_snooze"]},
	"duels_c": {"card": "room", "rows": ["duel_trail", "duel_letter"], "links": [[1, 0, "plane"]]},
}
static var _heading: FontVariation
var art := "rooms"
## Draw passes so far; tests read it to prove idle frames draw nothing.
var draw_count := 0
var title: Label
var line: Label
## A control of the screen's own (Together's Refresh) placed under the text.
var extra: Control
## The screen is in its wide layout (Replays' split): a list with a preview card
## then keeps its rows on the left and the text column on the right.
var wide := false

func setup(art_id: String, title_text: String, text: String, below: Control = null, wide_layout: bool = false) -> void:
	assert(SPOTS.has(art_id), "Unknown empty-state art: " + art_id)
	art = art_id
	wide = wide_layout
	name = "EmptyState"
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	if _heading == null:
		_heading = FontVariation.new()
		_heading.base_font = HEADING_FONT
		_heading.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 600.0}
	title = _label(title_text, 24, CREAM, _heading)
	line = _label(text, 18, MUTED, null)
	extra = below
	if extra != null:
		if extra.get_parent() != null: extra.get_parent().remove_child(extra)
		add_child(extra)

func _label(value: String, font_size: int, color: Color, font: Font) -> Label:
	var label := Label.new()
	label.text = value
	label.visible = not value.is_empty()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", font_size)
	if font != null: label.add_theme_font_override("font", font)
	add_child(label)
	return label

## Title, line and extra heights when the text is this wide.
func _block(width: float) -> Vector3:
	var heights := Vector3.ZERO
	for index: int in range(2):
		var label: Label = [title, line][index]
		if not label.visible: continue
		var font := label.get_theme_font("font")
		var font_size := label.get_theme_font_size("font_size")
		var height := font.get_multiline_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, width, font_size).y
		# A Label also spaces its wrapped lines apart.
		var lines := maxi(1, roundi(height / font.get_height(font_size)))
		heights[index] = height + (lines - 1) * label.get_theme_constant("line_spacing")
	if extra != null: heights.z = extra.get_combined_minimum_size().y
	return heights

static func _total(heights: Vector3) -> float:
	return heights.x + heights.y + (TEXT_GAP if heights.x > 0 else 0.0) + (TEXT_GAP * 2.0 + heights.z if heights.z > 0 else 0.0)

## Where everything goes at the current size: the ghost rows, the text block
## (title, line, extra) and, on wide Replays with a preview scene, that card.
func _layout() -> Dictionary:
	var spot: Dictionary = SPOTS[art]
	var card: Dictionary = Art.CARDS[spot.card]
	var side: bool = card.get("preview", false) and wide
	var width := (size.x - SIDE_GAP) * 1.15 / 2.15 if side else size.x
	var geo := {"spot": spot, "card": card, "side": side}
	var text: Rect2
	var rows: int
	if side:
		var column := Rect2(width + SIDE_GAP, 0, size.x - width - SIDE_GAP, size.y)
		# Round up: the last row is cut by the clip, which reads as the fade-out.
		rows = clampi(ceili((size.y + ROW_GAP) / (card.height + ROW_GAP)), 1, FADES.size())
		if spot.has("preview"):
			var panel := Rect2(column.position, Vector2(column.size.x, minf(size.y, 400.0)))
			var inner := panel.grow(-16.0)
			text.size.x = inner.size.x
			var heights := _block(text.size.x)
			var picture := Rect2(inner.position, Vector2(inner.size.x, clampf(inner.size.y - _total(heights) - PREVIEW_BELOW, PICTURE_MIN, 230.0)))
			text.position = Vector2(inner.position.x, picture.end.y + 14.0)
			geo.merge({"panel": panel, "picture": picture, "heights": heights})
		else:
			text.size.x = minf(column.size.x, TEXT_MAX)
			geo.heights = _block(text.size.x)
			var rows_end: float = rows * (card.height + ROW_GAP) - ROW_GAP
			text.position = Vector2(column.position.x, maxf(0.0, (minf(rows_end, size.y) - _total(geo.heights)) * 0.5))
	else:
		text.size.x = minf(size.x, TEXT_MAX)
		geo.heights = _block(text.size.x)
		var room := size.y - TEXT_TOP - _total(geo.heights) + ROW_GAP
		rows = clampi(int(room / (card.height + ROW_GAP)), spot.get("rows", []).size(), STACKED_ROWS)
		text.position = Vector2((size.x - text.size.x) * 0.5, rows * (card.height + ROW_GAP) - ROW_GAP + TEXT_TOP)
	text.size.y = _total(geo.heights)
	var cards: Array[Rect2] = []
	for index: int in range(maxi(rows, 1)): cards.append(Rect2(0, index * (card.height + ROW_GAP), width, card.height))
	geo.cards = cards
	geo.text = text
	return geo

func _get_minimum_size() -> Vector2:
	var geo := _layout()
	var rows: int = maxi(1, geo.spot.get("rows", []).size())
	var art_height: float = rows * (geo.card.height + ROW_GAP) - ROW_GAP
	if not geo.side: return Vector2(0, art_height + TEXT_TOP + geo.text.size.y)
	# The text column must fit whole: in the preview card, under its picture.
	var column: float = geo.text.size.y + (32.0 + PICTURE_MIN + PREVIEW_BELOW if geo.has("panel") else 0.0)
	return Vector2(0, maxf(art_height, column))

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		update_minimum_size()
	elif what == NOTIFICATION_SORT_CHILDREN:
		var geo := _layout()
		var text: Rect2 = geo.text
		var heights: Vector3 = geo.heights
		var align := HORIZONTAL_ALIGNMENT_LEFT if geo.side else HORIZONTAL_ALIGNMENT_CENTER
		var y := text.position.y
		for index: int in range(2):
			var label: Label = [title, line][index]
			label.horizontal_alignment = align
			fit_child_in_rect(label, Rect2(text.position.x, y, text.size.x, heights[index]))
			if heights[index] > 0: y += heights[index] + TEXT_GAP
		if extra != null: fit_child_in_rect(extra, Rect2(text.position.x, y + TEXT_GAP, text.size.x, heights.z))

func _draw() -> void:
	draw_count += 1
	var geo := _layout()
	var spot: Dictionary = geo.spot
	var rows: Array = spot.get("rows", [])
	if spot.has("preview") and not geo.has("panel"): rows = [spot.preview]
	var slots := {}
	for index: int in range(geo.cards.size() - 1, -1, -1):
		var parts := Art.ghost_card(self, geo.card, geo.cards[index], FADES[index], true)
		if parts.has("slot"):
			slots[index] = parts.slot
			if index < rows.size(): Art.scene(self, rows[index], parts.slot)
	for link: Array in spot.get("links", []):
		if slots.has(link[0]) and slots.has(link[1]): Art.link(self, link[2], slots[link[0]], slots[link[1]])
	if geo.has("panel"):
		Art.ghost_preview(self, geo.panel, geo.picture)
		Art.scene(self, spot.preview, geo.picture)
