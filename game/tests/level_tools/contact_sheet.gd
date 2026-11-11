extends Control
## A contact sheet: a title, then groups of captioned frames in a grid, on the
## map plan's paper. Set `title`, `note` and `groups` ([{heading, frames:
## [{image, caption}]}]), then canvas_size() before rendering it
## (render_kit.gd render). Frames keep their aspect at `frame_width` across.
const HEADING := preload("res://assets/fonts/fredoka.ttf")
const BODY := preload("res://assets/fonts/nunito.ttf")
const INK := Color("2b3634")
const SOFT_INK := Color("5d6a66")
const PAPER := Color("eef3ee")
const MARGIN := 32.0
const GAP := 14.0
const CAPTION := 20.0
const HEAD := 40.0

var title := ""
var note := ""
var groups: Array = []
var columns := 4
var frame_width := 400.0
var _textures: Dictionary = {}

func _frame_height() -> float:
	for group: Dictionary in groups:
		for frame: Dictionary in group.frames:
			var image: Image = frame.image
			return frame_width * float(image.get_height()) / float(maxi(image.get_width(), 1))
	return frame_width * 0.45

func canvas_size() -> Vector2i:
	var rows := 0
	for group: Dictionary in groups: rows += ceili(float(group.frames.size()) / float(columns))
	var width := MARGIN * 2.0 + columns * frame_width + (columns - 1) * GAP
	var height := MARGIN * 2.0 + 64.0 + groups.size() * HEAD + rows * (_frame_height() + CAPTION + GAP)
	return Vector2i(ceili(width), ceili(height))

func _draw() -> void:
	var size := Vector2(canvas_size())
	draw_rect(Rect2(Vector2.ZERO, size), PAPER)
	draw_string(HEADING, Vector2(MARGIN, MARGIN + 26), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, INK)
	draw_string(BODY, Vector2(MARGIN, MARGIN + 50), note, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, SOFT_INK)
	var y := MARGIN + 64.0
	var height := _frame_height()
	for group: Dictionary in groups:
		draw_string(HEADING, Vector2(MARGIN, y + 28), str(group.heading), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, INK)
		y += HEAD
		for index in range(group.frames.size()):
			var frame: Dictionary = group.frames[index]
			var column := index % columns
			if column == 0 and index > 0: y += height + CAPTION + GAP
			var at := Vector2(MARGIN + column * (frame_width + GAP), y)
			draw_texture_rect(_texture(frame.image), Rect2(at, Vector2(frame_width, height)), false)
			draw_rect(Rect2(at, Vector2(frame_width, height)), Color(INK, 0.25), false, 1.0)
			draw_string(BODY, at + Vector2(2, height + 15), str(frame.caption), HORIZONTAL_ALIGNMENT_LEFT, frame_width - 4, 13, INK)
		if not group.frames.is_empty(): y += height + CAPTION + GAP

func _texture(image: Image) -> Texture2D:
	var id := image.get_instance_id()
	if not _textures.has(id): _textures[id] = ImageTexture.create_from_image(image)
	return _textures[id]
