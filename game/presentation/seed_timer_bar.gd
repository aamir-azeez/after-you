extends Range
## The one turn timer every chapter HUD shows: the remaining seconds above a
## rounded track, where the icon's seed rides the edge of the gold fill toward
## a small sprout at the end of the turn. `value` is the elapsed time and
## `max_value` the turn length, both in seconds, as on the old ProgressBar.
##
## Cheap by design: the seed is one cached 2D texture from assets/ui/seed.svg,
## the styles are built once, nothing runs per frame, and the bar redraws only
## when its value, range or size changes.
const SEED_TEXTURE: Texture2D = preload("res://assets/ui/seed.svg")
const TITLE_FONT: Font = preload("res://assets/fonts/fredoka.ttf")
const CREAM := Color("eceddb")
const TRACK := Color("35584f")
const TRACK_EDGE := Color("54766a")
const GOLD := Color("f1c48a")
const GOLD_LIGHT := Color("ffe1a0")
const LEAF := Color("a2bd81")
const PATH_DOT := Color(0.81, 0.80, 0.78, 0.38)
const SHADOW := Color(0.04, 0.09, 0.13, 0.42)
const LABEL_HEIGHT := 40.0
const TRACK_HEIGHT := 12.0
const TRACK_CENTRE := 52.0
const SEED_SIZE := Vector2(25.5, 30.0)
## Where the seed body's centre sits inside seed.svg, as a fraction of its size.
const SEED_BODY := Vector2(0.42, 0.615)
const SEED_BODY_HALF_WIDTH := 0.4
const DOT_SPACING := 13.0
const ROCKS_PER_TURN := 6.0
const ROCK_ANGLE := 0.12
const MIN_SIZE := Vector2(160.0, 66.0)

static var _styles: Dictionary = {}
static var _number_font: FontVariation

## The remaining seconds, readable over any world.
var label: Label
## Reduced motion keeps the seed upright instead of rocking as it rolls.
var reduced_motion := false:
	set(value):
		if reduced_motion == value: return
		reduced_motion = value
		queue_redraw()
## Counts real redraws, so tests can prove unchanged values cost nothing.
var draw_count := 0

func _init() -> void:
	step = 0.01
	max_value = 20.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = MIN_SIZE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	set_process(false)
	label = Label.new()
	label.name = "Remaining"
	label.text = "20.0"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", _font())
	label.add_theme_font_size_override("font_size", 25)
	label.add_theme_color_override("font_color", CREAM)
	# A dark outline and halo keep the number readable over pale walls and grass.
	label.add_theme_color_override("font_outline_color", Color("101f31"))
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_color_override("font_shadow_color", Color(0.04, 0.09, 0.13, 0.62))
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.add_theme_constant_override("shadow_outline_size", 12)
	add_child(label)
	label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	label.offset_bottom = LABEL_HEIGHT
	changed.connect(queue_redraw)
	value_changed.connect(_value_redraw)

## Shows a turn of `duration` seconds with `remaining` seconds left.
func set_remaining(remaining: float, duration: float) -> void:
	max_value = duration
	value = clampf(duration - remaining, 0.0, duration)
	var text := "%.1f" % maxf(0.0, remaining)
	if label.text != text: label.text = text

func ratio_elapsed() -> float:
	var span := max_value - min_value
	return clampf((value - min_value) / span, 0.0, 1.0) if span > 0.0 else 0.0

func _value_redraw(_value: float) -> void:
	queue_redraw()

func _draw() -> void:
	draw_count += 1
	var track := Rect2(0.0, TRACK_CENTRE - TRACK_HEIGHT * 0.5, size.x, TRACK_HEIGHT)
	# The body is narrower than the texture; keep it, not the leaf, on the track.
	var seed_half := SEED_SIZE.x * SEED_BODY_HALF_WIDTH
	var low := track.position.x + seed_half
	var high := track.end.x - seed_half
	var edge := lerpf(low, maxf(low, high), ratio_elapsed())
	draw_style_box(_style("track"), track)
	# The road still ahead is the icon's dotted throw path.
	var dot_x := high
	while dot_x > edge + seed_half + 4.0:
		draw_circle(Vector2(dot_x, TRACK_CENTRE), 1.6, PATH_DOT, true, -1.0, true)
		dot_x -= DOT_SPACING
	_draw_sprout(Vector2(track.end.x - 8.0, track.position.y + 1.0))
	# Before the first tick the seed alone marks the start; no gold peeks behind it.
	if edge > low + 0.5:
		draw_style_box(_style("fill"), Rect2(track.position, Vector2(maxf(TRACK_HEIGHT, edge - track.position.x), TRACK_HEIGHT)))
	if edge - track.position.x > 10.0 and edge > low + 0.5:
		draw_style_box(_style("shine"), Rect2(track.position.x + 4.0, track.position.y + 2.0, edge - track.position.x - 6.0, 3.0))
	var angle := 0.0 if reduced_motion else sin(ratio_elapsed() * TAU * ROCKS_PER_TURN) * ROCK_ANGLE
	var body := Rect2(-SEED_SIZE * SEED_BODY, SEED_SIZE)
	draw_set_transform(Vector2(edge, TRACK_CENTRE + 2.0), angle)
	draw_texture_rect(SEED_TEXTURE, body, false, SHADOW)
	draw_set_transform(Vector2(edge, TRACK_CENTRE), angle)
	draw_texture_rect(SEED_TEXTURE, body, false)
	draw_set_transform(Vector2.ZERO)

## A two-leaf sprout standing on the end of the track, where the turn ends.
func _draw_sprout(base: Vector2) -> void:
	draw_line(base, base + Vector2(0.0, -6.0), LEAF, 1.6, true)
	for side: float in [-1.0, 1.0]:
		# Each leaf opens up and out from the stem tip, like the icon's sprouts.
		draw_set_transform(base + Vector2(side * 3.2, -8.2), -side * 0.62, Vector2(1.0, 0.52))
		draw_circle(Vector2.ZERO, 3.8, LEAF, true, -1.0, true)
	draw_set_transform(Vector2.ZERO)

static func _font() -> Font:
	if _number_font == null:
		_number_font = FontVariation.new()
		_number_font.base_font = TITLE_FONT
		_number_font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 600.0}
		# Even-width figures keep the number from shifting as it counts down.
		_number_font.opentype_features = {TextServerManager.get_primary_interface().name_to_tag("tnum"): 1}
	return _number_font

static func _style(key: String) -> StyleBoxFlat:
	if _styles.is_empty():
		var track := StyleBoxFlat.new()
		track.bg_color = TRACK
		track.set_corner_radius_all(int(TRACK_HEIGHT * 0.5))
		track.set_border_width_all(1)
		track.border_color = TRACK_EDGE
		track.shadow_color = SHADOW
		track.shadow_size = 3
		track.shadow_offset = Vector2(0.0, 1.0)
		track.anti_aliasing = true
		var fill := StyleBoxFlat.new()
		fill.bg_color = GOLD
		fill.set_corner_radius_all(int(TRACK_HEIGHT * 0.5))
		fill.anti_aliasing = true
		var shine := StyleBoxFlat.new()
		shine.bg_color = Color(GOLD_LIGHT, 0.7)
		shine.set_corner_radius_all(2)
		shine.anti_aliasing = true
		_styles = {"track": track, "fill": fill, "shine": shine}
	return _styles[key]
