extends Control
## A row of step dots: one per turn of the run, filled for the turns played.
## While a lane's time covers fewer turns than it played (services/duel_model.gd
## lane), the turns its time covers are filled bright and the rest it played soft.
## Joined (a result's stages), a line runs behind the dots and on past the
## last one by `tail`, to meet whatever sits after the row (the chapter badge).
## Drawn once per change, never per frame.
const UiTokens = preload("res://presentation/ui_tokens.gd")
const EMPTY := Color("54766a")
## A played turn the shown time leaves out.
const PLAYED := Color(UiTokens.MINT, 0.38)

var done := 0
var counted := 0
var total := 0
var dot := 16.0
var joined := false
var tail := 0.0

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER

func setup(played: int, steps: int, diameter: float = 16.0, line_to: float = -1.0, covered: int = -1) -> void:
	done = clampi(played, 0, steps)
	total = maxi(steps, 0)
	counted = done if covered < 0 else clampi(covered, 0, done)
	dot = diameter
	joined = line_to >= 0.0
	tail = maxf(line_to, 0.0)
	var gap := diameter * (1.0 if joined else 0.45)
	custom_minimum_size = Vector2(maxf(0.0, total * diameter + (total - 1) * gap) + tail, diameter + 2.0)
	queue_redraw()

func _draw() -> void:
	var gap := dot * (1.0 if joined else 0.45)
	var radius := dot * 0.5
	if joined and total > 0: draw_line(Vector2(radius, size.y * 0.5), Vector2(size.x, size.y * 0.5), EMPTY, 3.0, true)
	for index in range(total):
		var centre := Vector2(radius + index * (dot + gap), size.y * 0.5)
		if index < counted: draw_circle(centre, radius, UiTokens.MINT, true, -1.0, true)
		elif index < done: draw_circle(centre, radius, PLAYED, true, -1.0, true)
		else: draw_arc(centre, radius - 1.0, 0.0, TAU, 24, EMPTY, 2.0, true)
