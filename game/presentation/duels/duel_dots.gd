extends Control
## A row of step dots: one per turn of the run, filled for the turns played.
## Drawn once per change, never per frame.
const UiTokens = preload("res://presentation/ui_tokens.gd")
const EMPTY := Color("54766a")

var done := 0
var total := 0
var dot := 16.0

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER

func setup(played: int, steps: int, diameter: float = 16.0) -> void:
	done = clampi(played, 0, steps)
	total = maxi(steps, 0)
	dot = diameter
	var gap := diameter * 0.45
	custom_minimum_size = Vector2(maxf(0.0, total * diameter + (total - 1) * gap), diameter + 2.0)
	queue_redraw()

func _draw() -> void:
	var gap := dot * 0.45
	var radius := dot * 0.5
	for index in range(total):
		var centre := Vector2(radius + index * (dot + gap), size.y * 0.5)
		if index < done: draw_circle(centre, radius, UiTokens.MINT, true, -1.0, true)
		else: draw_arc(centre, radius - 1.0, 0.0, TAU, 24, EMPTY, 2.0, true)
