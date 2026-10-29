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
const Kit = preload("res://presentation/duels/duel_kit.gd")

const STYLES := ["level", "snapshots", "cheer"]
## How much of the page's green shows through the whole picture ("level"):
## enough that the soft lines on the page keep their contrast over the bright
## islands. The picture is drawn faint over the green: one layer, no scrim.
const LEVEL_DIM := 0.8
## The width the result's cards and buttons take in the middle, and the least
## margin beside them a snapshot or a drawn scene needs.
const CONTENT := 840.0
const MARGIN_MIN := 150.0
## Each margin's piece: its middle as a share of the screen's height, and its tilt.
const SIDES := [[0.36, -0.09], [0.62, 0.07]]
## A snapshot's paper, and how much it is darkened (opaque, so nothing shows through it).
const PAPER := Color("eceddb")
const SNAPSHOT_DIM := 0.25
## The drawn look's sparkles and hearts: a share of the margin across, of the
## screen down, and a size at 720 high; and how strongly the look shows, as
## the page's green laid over the finished drawing so no piece shows through another.
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
			# self_modulate, as the shelf's fade in tweens modulate.
			var picture := _picture(self)
			picture.self_modulate = Color(1, 1, 1, 1.0 - LEVEL_DIM)
			_pictures.append(picture)
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
				paper.modulate = Color(1, 1, 1).darkened(SNAPSHOT_DIM)
				var frame := Control.new()
				frame.clip_contents = true
				frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
				paper.add_child(frame)
				_pictures.append(_picture(frame))
				add_child(paper)
				_snapshots.append(paper)
	# A half turn moves a camera cutout without a resize; the watcher catches it.
	if style != "level":
		resized.connect(_relayout)
		SafeArea.watch(self, _relayout)

## Shows `key`'s chapter, and whether the player's pair won. The picture is asked for once per chapter.
func show_chapter(key: String, won: bool) -> void:
	if won != _won and style == "cheer": queue_redraw()
	_won = won
	if key == _key: return
	_key = key
	for picture: TextureRect in _pictures:
		# A chapter with no picture must not take the last one's late arrival.
		picture.texture = null
		picture.remove_meta(ThumbnailShelf.PATH_META)
		ThumbnailShelf.fill(picture, Thumbnails.path(key))

func _relayout() -> void:
	if style == "snapshots": _place_snapshots()
	else: queue_redraw()

## The room beside the result's cards, the same on each side, 0 when there is none to use.
## The cards sit in the middle of the safe area, so a camera cutout on one side moves them.
func margin() -> float:
	var middle := _middle()
	var room := minf(middle - CONTENT * 0.5, size.x - middle - CONTENT * 0.5)
	return room if room >= MARGIN_MIN else 0.0

## The middle of the safe area across, in this control's own space.
func _middle() -> float:
	if not is_inside_tree(): return size.x * 0.5
	return (get_global_transform().affine_inverse() * SafeArea.rect(get_viewport()).get_center()).x

## Where each margin piece is centred across: left of the cards, then right of them.
func _side_x(side: int, room: float) -> float:
	var middle := _middle()
	return middle - CONTENT * 0.5 - room * 0.5 if side == 0 else middle + CONTENT * 0.5 + room * 0.5

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
		paper.position = Vector2(_side_x(side, room), size.y * SIDES[side][0]) - paper.size * 0.5

func _draw() -> void:
	if style != "cheer": return
	var room := margin()
	if room <= 0.0: return
	var unit := size.y / 720.0
	for side: int in SIDES.size():
		var left := _side_x(side, room) - room * 0.5
		var slot := Rect2(left + room * 0.08, size.y * SIDES[side][0] - room * 0.4, room * 0.84, room * 0.6)
		Art.scene(self, ("result_cheer_" if _won else "result_calm_") + ("left" if side == 0 else "right"), slot)
		if _won:
			for spark: Array in CHEER_SPARKS:
				var at: Vector2 = spark[0]
				Art.sparkle(self, Transform2D.IDENTITY, Vector2(left + at.x * room, at.y * size.y + side * size.y * 0.06), spark[1] * unit)
			for heart: Array in CHEER_HEARTS:
				var at: Vector2 = heart[0]
				Art.heart(self, Transform2D.IDENTITY, Vector2(left + (at.x if side == 0 else 1.0 - at.x) * room, at.y * size.y + side * size.y * 0.5), heart[1] * unit)
		draw_rect(Rect2(left, 0.0, room, size.y), Color(Kit.BACKGROUND, 1.0 - CHEER_ALPHA))
