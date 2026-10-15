extends Range
## The small bar beside "Waiting for Sam": how much of the friend's memory is
## still to play, emptying toward the end. It draws with the turn timer's own
## track and fill (SeedTimerBar), so the two read as one family, and like it
## redraws only when its value or size changes; nothing runs per frame.
const SeedTimerBar = preload("res://presentation/seed_timer_bar.gd")
const HEIGHT := 8.0
const MIN_SIZE := Vector2(96.0, HEIGHT)

func _init() -> void:
	min_value = 0.0
	max_value = 1.0
	step = 0.001
	value = 1.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = MIN_SIZE
	set_process(false)
	changed.connect(queue_redraw)
	value_changed.connect(func(_value: float) -> void: queue_redraw())

func _draw() -> void:
	var track := Rect2(0.0, (size.y - HEIGHT) * 0.5, size.x, HEIGHT)
	draw_style_box(SeedTimerBar._style("track"), track)
	var ratio := clampf(value, 0.0, 1.0)
	if ratio * size.x >= 1.0:
		draw_style_box(SeedTimerBar._style("fill"), Rect2(track.position, Vector2(maxf(HEIGHT, track.size.x * ratio), HEIGHT)))
