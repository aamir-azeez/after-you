extends Control
## Fixed touch joystick, mouse usable in desktop development builds.
var value := Vector2.ZERO
var touch_id := -1
var dragging := false
var left_handed := false

func _ready() -> void:
	custom_minimum_size=Vector2(152,152)
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
	value=((pos-size/2.0)/48.0).limit_length()
	if value.length()<0.12:
		value=Vector2.ZERO
	queue_redraw()

func release() -> void:
	value=Vector2.ZERO
	touch_id=-1
	dragging=false
	queue_redraw()

func _draw() -> void:
	var center := size/2
	draw_circle(center,66,Color(0.75,0.89,0.82,0.10))
	draw_arc(center,65,0,TAU,64,Color(0.82,0.92,0.86,0.3),1.5,true)
	for angle in [0,PI/2,PI,PI*1.5]:
		var direction := Vector2(cos(angle),sin(angle))
		draw_line(center+direction*52,center+direction*58,Color(0.83,0.93,0.84,0.5),2,true)
	draw_circle(center+value*43,25,Color("dce8cb"))
	draw_circle(center+value*43,19,Color("b5cdb0"))
