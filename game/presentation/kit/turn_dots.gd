extends Control
## An open turns stage's turns as a row of dots (core/physical/open_turns.gd),
## the one drawing the turn HUD, the room page and the room list share: each
## turn played in its pip's colour (the host's slot is peach, the guest's mint,
## spirit_look.gd), the turn being played a larger dot, the turns left hollow.
## The stage's last turn wears a coral ring; while it is played the track's
## edge turns coral too. Its view comes from view() (a room's open_turns) or
## from the room list (room_inbox_client.gd); show_turns() changes nothing for
## an unchanged view, so a caller may pass it every tick.
## Presentation only. Nothing is cached outside the node.
const ControlTheme = preload("res://presentation/control_theme.gd")
const Look = preload("res://presentation/spirit_look.gd")
const OpenTurns = preload("res://core/physical/open_turns.gd")
## The track behind the dots: the goal card's dark green, so they hold over grass and rails.
const TRACK := Color("193f3a")
## A hollow dot's ring, and the dark gap inside the last turn's ring.
const HOLLOW := Color(0.92, 0.93, 0.86, 0.85)
const GAP := Color(0.06, 0.16, 0.17)
const SHADOW := Color(0.04, 0.09, 0.13, 0.42)
const PAD := Vector2(10.0, 4.0)

## The widest step between dots; a narrower row shrinks the step to fit the cap.
var max_step := 28.0
## Whether the dark track is drawn behind the dots.
var track := true
## Whether the dots sit at the row's centre (the HUD) or its start (the room page and list).
var centered := false
var _view: Dictionary = {}

func _init(step: float = 28.0, with_track: bool = true) -> void:
	name = "TurnDots"
	max_step = step
	track = with_track
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0.0, 30.0)
	resized.connect(queue_redraw)

## The dots for a room's open_turns view ({turn, cap, must_finish}) on a stage
## whose first turn is `first_slot`'s: {turn, cap, first_slot, last, edge}.
## `last` is the turn that wears the ring: this one when it must finish (at the
## cap, or early when the stage's bytes run out), else the cap's once it is
## next; 0 for none. `edge` is true while that turn is the one being played.
static func view(open: Dictionary, first_slot: String) -> Dictionary:
	var turn := int(open.get("turn", 0))
	var cap := int(open.get("cap", 0))
	if turn < 1 or cap < 2 or first_slot not in ["p0", "p1"]: return {}
	var must := bool(open.get("must_finish", false))
	var last := turn if must else (cap if turn >= cap - 1 else 0)
	return {"turn": turn, "cap": cap, "first_slot": first_slot, "last": last, "edge": last == turn}

## Shows `value` (view()); an empty view hides the row. Returns whether anything changed.
func show_turns(value: Dictionary) -> bool:
	var changed := value != _view
	if changed:
		_view = value.duplicate()
		visible = not value.is_empty()
		queue_redraw()
	return changed

## The width the row takes at its widest step: what a caller anchors.
func natural_width() -> float:
	return max_step * float(maxi(int(_view.get("cap", 0)), 1)) + PAD.x * 2.0

func _draw() -> void:
	if _view.is_empty(): return
	var cap := int(_view.cap)
	var turn := int(_view.turn)
	var step := minf(max_step, (size.x - PAD.x * 2.0) / float(cap))
	if step <= 0.0: return
	var width := step * float(cap) + PAD.x * 2.0
	var left := (size.x - width) * 0.5 if centered else 0.0
	var y := size.y * 0.5
	if track:
		var look := ControlTheme.rounded(TRACK, int(size.y * 0.5), ControlTheme.CORAL if _view.edge else Color.TRANSPARENT)
		look.set_border_width_all(2 if _view.edge else 0)
		draw_style_box(look, Rect2(left, 0.0, width, size.y))
	var r := clampf(step * 0.34, 3.0, 7.0)
	var ring := Vector2.ZERO
	for i in range(cap):
		var number := i + 1
		var at := Vector2(left + PAD.x + step * (float(i) + 0.5), y)
		var color: Color = Look.PEACH if OpenTurns.slot(str(_view.first_slot), number) == "p0" else Look.MINT
		var big := r
		if number < turn: draw_circle(at, r, color, true, -1.0, true)
		elif number == turn:
			big = r + clampf(r * 0.4, 1.5, 2.5)
			draw_circle(at, big + 1.0, SHADOW, true, -1.0, true)
			draw_circle(at, big, color, true, -1.0, true)
		else: draw_arc(at, r - 0.5, 0.0, TAU, 48, HOLLOW, maxf(1.4, r * 0.3), true)
		if number == int(_view.last): ring = Vector2(at.x, big)
	# Last, so the ring sits over its neighbours on a tight row.
	if int(_view.last) > 0:
		var at := Vector2(ring.x, y)
		var gap := maxf(1.5, r * 0.3)
		draw_arc(at, ring.y + gap * 0.5 + 0.5, 0.0, TAU, 48, GAP, gap, true)
		draw_arc(at, ring.y + gap + maxf(1.5, r * 0.25), 0.0, TAU, 48, ControlTheme.CORAL, maxf(2.0, r * 0.5), true)
