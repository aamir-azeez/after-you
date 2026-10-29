extends Control
## What sits behind a duel's result, in one of three looks (duel_result_page.gd
## RESULT_BG is the owner's pick):
##
## - "level": the chapter's own picture (services/chapter_thumbnail_catalog.gd)
##   across the whole screen, under the page's deep green so the cards and
##   lines read as they do on the plain page.
## - "snapshots": the same picture as two tilted snapshots in the side
##   margins, like photos of the race pinned beside the result.
## - "cheer": no picture; a pair on a little island in each side margin with a
##   few sparkles and hearts, drawn with the empty lists' own pieces
##   (empty_state_art.gd). After a loss the pairs sit calmly and the sparkles go.
##
## The margin looks use only the space beside the result's cards (CONTENT
## wide in the middle) and stay away when that space is too narrow, so they
## never sit under a card or a line. The picture loads off the main thread
## through the chapter picture shelf (chapter_thumbnail_shelf.gd), which keeps
## it and lets it go with the rest. Nothing here runs per frame: the picture is
## set once, and the margins lay out and draw again only when the size changes.
const ThumbnailShelf = preload("res://presentation/chapter_thumbnail_shelf.gd")
const Thumbnails = preload("res://services/chapter_thumbnail_catalog.gd")
const SafeArea = preload("res://presentation/safe_area.gd")
const Art = preload("res://presentation/empty_state_art.gd")

const STYLES := ["level", "snapshots", "cheer"]
## The page's own green (duel_kit.gd BACKGROUND), laid over the picture.
const PAGE := Color("123936")
## How much of the page's green covers the whole picture ("level"): enough
## that the soft lines on the page keep their contrast over the bright islands.
const LEVEL_DIM := 0.8
## The width the result's cards and buttons take in the middle, and the least
## margin beside them a snapshot or a drawn scene needs.
const CONTENT := 840.0
const MARGIN_MIN := 150.0
## Each margin's piece: its middle as a share of the screen's height, and its tilt.
const SIDES := [[0.36, -0.09], [0.62, 0.07]]
## A snapshot's paper and how much of the page's green softens it.
const PAPER := Color("eceddb")
const SNAPSHOT_DIM := 0.25
## The drawn look's sparkles and hearts: a share of the margin across, of the
## screen down, and a size at 720 high; and how strongly the look shows.
const CHEER_SPARKS := [[Vector2(0.3, 0.2), 9.0], [Vector2(0.75, 0.12), 6.0], [Vector2(0.2, 0.9), 7.0]]
const CHEER_HEARTS := [[Vector2(0.65, 0.24), 11.0]]
const CHEER_ALPHA := 0.6

var style := "level"
var _key := ""
var _won := false
var _pictures: Array[TextureRect] = []
var _snapshots: Array[Control] = []

func _init(look: String = "level") -> void:
	style = look if look in STYLES else "level"
	name = "DuelResultBackdrop"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	SafeArea.bleed(self)
	match style:
		"level":
			_pictures.append(_picture(self))
			var dim := ColorRect.new()
			dim.name = "ResultPictureDim"
			dim.color = Color(PAGE, LEVEL_DIM)
			dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
			dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			add_child(dim)
			SafeArea.bleed(dim)
		"snapshots":
			for side: int in SIDES.size():
				var paper := PanelContainer.new()
				paper.name = "ResultSnapshot%d" % side
				paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
				var style_box := StyleBoxFlat.new()
				style_box.bg_color = PAPER
				style_box.set_corner_radius_all(4)
				style_box.content_margin_left = 7
				style_box.content_margin_right = 7
				style_box.content_margin_top = 7
				style_box.content_margin_bottom = 22
				style_box.shadow_color = Color(0, 0, 0, 0.25)
				style_box.shadow_size = 8
				style_box.shadow_offset = Vector2(0, 4)
				paper.add_theme_stylebox_override("panel", style_box)
				paper.modulate = Color(1, 1, 1, 1.0 - SNAPSHOT_DIM)
				var frame := Control.new()
				frame.clip_contents = true
				frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
				paper.add_child(frame)
				_pictures.append(_picture(frame))
				add_child(paper)
				_snapshots.append(paper)
			resized.connect(_place_snapshots)
		"cheer":
			modulate = Color(1, 1, 1, CHEER_ALPHA)
			resized.connect(queue_redraw)

## Shows `key`'s chapter, and whether the player's pair won. The picture is asked for once per chapter.
func show_chapter(key: String, won: bool) -> void:
	if won != _won and style == "cheer": queue_redraw()
	_won = won
	if key == _key: return
	_key = key
	for picture: TextureRect in _pictures:
		picture.texture = null
		ThumbnailShelf.fill(picture, Thumbnails.path(key))

## The room beside the result's cards on each side, 0 when there is none to use.
func margin() -> float:
	var room := (size.x - CONTENT) * 0.5
	return room if room >= MARGIN_MIN else 0.0

func _picture(holder: Control) -> TextureRect:
	var picture := TextureRect.new()
	picture.name = "ResultPicture"
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(picture)
	return picture

func _place_snapshots() -> void:
	var room := margin()
	for side: int in _snapshots.size():
		var paper := _snapshots[side]
		paper.visible = room > 0.0
		if room <= 0.0: continue
		var width := minf(room - 36.0, 300.0)
		var picture := Vector2(width - 14.0, (width - 14.0) * 0.5625)
		paper.size = picture + Vector2(14, 29)
		paper.pivot_offset = paper.size * 0.5
		paper.rotation = SIDES[side][1]
		var middle_x := room * 0.5 if side == 0 else size.x - room * 0.5
		paper.position = Vector2(middle_x, size.y * SIDES[side][0]) - paper.size * 0.5

func _draw() -> void:
	if style != "cheer": return
	var room := margin()
	if room <= 0.0: return
	var unit := size.y / 720.0
	for side: int in SIDES.size():
		var left := 0.0 if side == 0 else size.x - room
		var slot := Rect2(left + room * 0.08, size.y * SIDES[side][0] - room * 0.4, room * 0.84, room * 0.6)
		Art.scene(self, ("result_cheer_" if _won else "result_calm_") + ("left" if side == 0 else "right"), slot)
		if not _won: continue
		for spark: Array in CHEER_SPARKS:
			var at: Vector2 = spark[0]
			Art.sparkle(self, Transform2D.IDENTITY, Vector2(left + at.x * room, at.y * size.y + side * size.y * 0.06), spark[1] * unit)
		for heart: Array in CHEER_HEARTS:
			var at: Vector2 = heart[0]
			Art.heart(self, Transform2D.IDENTITY, Vector2(left + (at.x if side == 0 else 1.0 - at.x) * room, at.y * size.y + side * size.y * 0.5), heart[1] * unit)
