extends Control
## Fixed touch joystick, mouse usable in desktop development builds.
const HIT_SIZE := 192.0
const ART_RADIUS := 72.0
const MAX_TRAVEL := 48.0
## While watching (watch()), the stick's spot shows the room camera inside a
## ring that fills toward the hand-off, and takes no movement.
const CAMERA: Texture2D = preload("res://assets/ui/room/camera.svg")
const CAMERA_SIZE := 34.0
const KNOB := Color("dce8cb")
## The ring's fill moves in steps this fine, so a tick that changes nothing
## visible redraws nothing.
const WATCH_STEPS := 128.0
## The pop back into a stick at the hand-off: its starting scale and length.
const POP_FROM := 0.84
const POP_SECONDS := 0.28
var value := Vector2.ZERO
var touch_id := -1
var dragging := false
var left_handed := false
var watching := false
## How far toward the hand-off the watch is (0 to 1), as drawn.
var watch_progress := 0.0
## Where the finger last was, so a finger held through the hand-off steers at once.
var _last_pos := Vector2.ZERO
var _pop: Tween

func _ready() -> void:
	custom_minimum_size=Vector2(HIT_SIZE,HIT_SIZE)
	mouse_filter=Control.MOUSE_FILTER_STOP

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and touch_id<0:
			touch_id=event.index
			_update_value(event.position)
		elif not event.pressed and event.index==touch_id:
			release()
	if event is InputEventScreenDrag and event.index==touch_id:
		_update_value(event.position)
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		dragging=event.pressed
		if dragging:
			_update_value(event.position)
		else:
			release()
	if event is InputEventMouseMotion and dragging:
		_update_value(event.position)
	accept_event()

func _update_value(pos: Vector2) -> void:
	_last_pos=pos
	if watching:
		value=Vector2.ZERO
		return
	value=((pos-size/2.0)/MAX_TRAVEL).limit_length()
	if value.length()<0.12:
		value=Vector2.ZERO
	queue_redraw()

func release() -> void:
	value=Vector2.ZERO
	touch_id=-1
	dragging=false
	queue_redraw()

## Shows the watch, `progress` of the way to the hand-off (0 to 1). Cheap to
## call every tick: it redraws only when the ring visibly moves.
func watch(progress: float) -> void:
	var stepped := snappedf(clampf(progress, 0.0, 1.0), 1.0 / WATCH_STEPS)
	if watching and is_equal_approx(stepped, watch_progress): return
	if not watching:
		watching = true
		value = Vector2.ZERO
		if _pop != null: _pop.kill()
		scale = Vector2.ONE
	watch_progress = stepped
	queue_redraw()

## The hand-off: back to the stick with a short pop (none with Reduce motion).
func end_watch(reduced_motion: bool) -> void:
	if not watching: return
	watching = false
	watch_progress = 0.0
	queue_redraw()
	if touch_id >= 0 or dragging: _update_value(_last_pos)
	if reduced_motion or not is_inside_tree(): return
	pivot_offset = size / 2.0
	scale = Vector2.ONE * POP_FROM
	_pop = create_tween()
	_pop.tween_property(self, "scale", Vector2.ONE, POP_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _draw() -> void:
	var center := size/2
	if watching:
		_draw_watch(center)
		return
	draw_circle(center,ART_RADIUS,Color(0.75,0.89,0.82,0.10))
	draw_arc(center,ART_RADIUS-1.0,0,TAU,64,Color(0.82,0.92,0.86,0.3),1.5,true)
	for angle in [0,PI/2,PI,PI*1.5]:
		var direction := Vector2(cos(angle),sin(angle))
		draw_line(center+direction*58,center+direction*64,Color(0.83,0.93,0.84,0.5),2,true)
	draw_circle(center+value*43,28,KNOB)
	draw_circle(center+value*43,21,Color("b5cdb0"))

## The dimmed ring filling clockwise from the top, the camera where the knob rests.
func _draw_watch(center: Vector2) -> void:
	draw_circle(center,ART_RADIUS,Color(0.75,0.89,0.82,0.05))
	draw_arc(center,ART_RADIUS-1.0,0,TAU,64,Color(0.82,0.92,0.86,0.16),1.5,true)
	if watch_progress > 0.0:
		draw_arc(center,ART_RADIUS-1.0,-PI/2,-PI/2+TAU*watch_progress,maxi(4,int(64*watch_progress)),Color(KNOB,0.85),4.0,true)
	draw_circle(center,28,Color(0.06,0.14,0.15,0.5))
	draw_circle(center,28,Color(KNOB,0.35),false,1.5,true)
	draw_texture_rect(CAMERA,Rect2(center-Vector2.ONE*CAMERA_SIZE*0.5,Vector2.ONE*CAMERA_SIZE),false,Color(KNOB,0.85))
