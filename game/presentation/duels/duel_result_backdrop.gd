extends Control
## What sits behind a duel's result: the chapter's own picture
## (services/chapter_thumbnail_catalog.gd) across the whole screen, drawn
## faint over the page's deep green so the cards and lines read as they do on
## the plain page.
##
## The picture loads off the main thread through the chapter picture shelf
## (chapter_thumbnail_shelf.gd), which keeps it and lets it go with the rest.
## Nothing here runs per frame: the picture is set once per chapter.
const ThumbnailShelf = preload("res://presentation/chapter_thumbnail_shelf.gd")
const Thumbnails = preload("res://services/chapter_thumbnail_catalog.gd")
const SafeArea = preload("res://presentation/safe_area.gd")

## How much of the page's green shows through the picture: enough that the
## soft lines on the page keep their contrast over the bright islands. The
## picture is drawn faint over the green: one layer, no scrim.
const DIM := 0.8

var _key := ""
var _picture: TextureRect

func _init() -> void:
	name = "DuelResultBackdrop"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	SafeArea.bleed(self)
	_picture = TextureRect.new()
	_picture.name = "ResultPicture"
	_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# self_modulate, as the shelf's fade in tweens modulate.
	_picture.self_modulate = Color(1, 1, 1, 1.0 - DIM)
	add_child(_picture)

## Shows `key`'s chapter. The picture is asked for once per chapter.
func show_chapter(key: String) -> void:
	if key == _key: return
	_key = key
	# A chapter with no picture must not take the last one's late arrival.
	_picture.texture = null
	_picture.remove_meta(ThumbnailShelf.PATH_META)
	ThumbnailShelf.fill(_picture, Thumbnails.path(key))
