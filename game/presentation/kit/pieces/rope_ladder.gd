extends "res://presentation/kit/pieces/piece.gd"
## World kit: a pull-up rope ladder (rules 20's rope_ladder block: a stair
## with "one_way": "up"), in one of its styles (content/dressing/
## prop_styles.gd "ladder"; piece_styles.gd picks which, by the stair's id).
##
##   "rope": two side ropes and timber rungs along the stair's slope, from
##       its foot up to two iron hooks on its head. While no pip is near its
##       foot it is pulled up: rolled into a bundle on the hooks at the head,
##       so a pip at the top sees it cannot come down that way.
##   "wheel": the wheel ride (rules 20's wheel_ride): a big mill wheel beside
##       the stair, its paddles the holds a pip rides up on. It turns while the
##       stair is open (set_turning) and stands still otherwise; it only ever
##       turns upward, so nobody rides it down.
##
## Hung or rolled is presentation only (set_pulled), shown from where the
## pips stand; the rule itself (no step down it) is the simulation's.
const STYLES := ["rope", "wheel"]
## The wheel turns this fast (radians a second) while open.
const TURN_RATE := 0.8
const PADDLES := 10
const ROPE := Color("c9b48a")
const RUNG := Color("9b7653")
const RUNGS := 8
## The posts the head's beam hangs from stand this high over the upper floor (m).
const POST_HEIGHT := 0.55

var _hung: Node3D
var _rolled: Node3D
var _wheel: Node3D
var _turning := false

## A ladder in `style` on `stair` (its plan rect in metres as a Rect2, its
## foot and head heights in metres, along x when `along_x`, rising toward +
## when `rising`) under `parent`, hung.
static func build(ladder_style: String, rect: Rect2, foot: float, head: float, along_x: bool, rising: bool, parent: Node3D) -> RefCounted:
	var piece: RefCounted = load("res://presentation/kit/pieces/rope_ladder.gd").new()
	piece._make(ladder_style if ladder_style in STYLES else "rope", rect, foot, head, along_x, rising, parent)
	return piece

## Pulled up (rolled at the head) or let down (hung along the stair).
func set_pulled(pulled: bool, _immediate: bool = false) -> void:
	if _wheel != null: return
	_hung.visible = not pulled
	_rolled.visible = pulled

## A wheel ride turns while its stair is open.
func set_turning(on: bool) -> void:
	_turning = on and _wheel != null

func moving() -> bool:
	return _turning

func advance(delta: float) -> void:
	if _turning: _wheel.rotate_object_local(Vector3.FORWARD, maxf(delta, 0.0) * TURN_RATE)

func moving_parts() -> Array[Node3D]:
	return [_wheel] if _wheel != null else [_hung, _rolled]

func _make(ladder_style: String, rect: Rect2, foot: float, head: float, along_x: bool, rising: bool, parent: Node3D) -> void:
	style = ladder_style
	var center := Vector3(rect.get_center().x, foot, rect.get_center().y)
	_root("RopeLadder_" + ladder_style, center, parent, false)
	anchor = root
	var run := rect.size.x if along_x else rect.size.y
	var across := rect.size.y if along_x else rect.size.x
	var sign := 1.0 if rising else -1.0
	var bottom := Vector3(-sign * run * 0.5, 0.02, 0) if along_x else Vector3(0, 0.02, -sign * run * 0.5)
	var top := Vector3(sign * run * 0.5, head - foot + 0.02, 0) if along_x else Vector3(0, head - foot + 0.02, sign * run * 0.5)
	var side := Vector3(0, 0, across * 0.32) if along_x else Vector3(across * 0.32, 0, 0)
	if ladder_style == "wheel":
		_make_wheel(bottom, top, side, along_x)
		return
	_hung = Node3D.new()
	_hung.name = "Hung"
	root.add_child(_hung)
	for edge: float in [-1.0, 1.0]: _bar(bottom + side * edge, top + side * edge, 0.022, ROPE, _hung)
	for index in range(RUNGS):
		var at := bottom.lerp(top, (float(index) + 0.5) / float(RUNGS))
		_bar(at - side * 1.1, at + side * 1.1, 0.03, RUNG, _hung)
	for edge: float in [-1.0, 1.0]: Parts.box(Vector3(0.04, 0.08, 0.04), Parts.IRON, top + side * edge + Vector3(0, 0.03, 0), root)
	# It hangs from the higher floor's edge: two short posts on that floor and a
	# beam across them, a rope from the beam to each side rope's hook.
	var onward := Vector3(sign, 0, 0) if along_x else Vector3(0, 0, sign)
	var beam_at := top + onward * 0.12 + Vector3(0, POST_HEIGHT, 0)
	for edge: float in [-1.0, 1.0]:
		var post := top + onward * 0.12 + side * edge * 1.35
		Parts.box(Vector3(0.06, POST_HEIGHT, 0.06), Parts.TIMBER, post + Vector3(0, POST_HEIGHT * 0.5 - 0.02, 0), root)
		_bar(top + side * edge + Vector3(0, 0.06, 0), beam_at + side * edge, 0.02, ROPE, root)
	_bar(beam_at - side * 1.4, beam_at + side * 1.4, 0.05, Parts.TIMBER_DARK, root)
	_rolled = Node3D.new()
	_rolled.name = "Rolled"
	_rolled.visible = false
	root.add_child(_rolled)
	var roll := Parts.rod(0.09, across * 0.8, RUNG, top + Vector3(0, 0.1, 0), _rolled)
	if along_x: roll.rotation = Vector3(PI / 2.0, 0, 0)
	for edge: float in [-1.0, 1.0]: Parts.torus(0.095, 0.015, ROPE, top + Vector3(0, 0.1, 0) + side * edge * 0.8, _rolled).rotation = Vector3(PI / 2.0, 0, 0) if along_x else Vector3(0, 0, PI / 2.0)

## A mill wheel standing beside the stair's far side, its hub over the
## stair's middle, big enough that its rim runs from the foot to the head.
func _make_wheel(bottom: Vector3, top: Vector3, side: Vector3, along_x: bool) -> void:
	var hub := (bottom + top) * 0.5 + side * 1.9
	var radius := maxf((top - bottom).length() * 0.5, 0.4)
	Parts.box(Vector3(0.1, hub.y + 0.1, 0.1), Parts.TIMBER_DARK, Vector3(hub.x, (hub.y + 0.1) * 0.5 - 0.1, hub.z) + side * 0.4, root)
	_wheel = Node3D.new()
	_wheel.name = "RideWheel"
	_wheel.position = hub
	if not along_x: _wheel.rotation.y = PI / 2.0
	root.add_child(_wheel)
	var rim := Parts.torus(radius, 0.035, Parts.TIMBER, Vector3.ZERO, _wheel, 24, 6)
	rim.rotation.x = PI / 2.0
	for index in range(PADDLES):
		var turn := TAU * float(index) / float(PADDLES)
		var spoke := Parts.box(Vector3(0.04, radius * 2.0, 0.04), Parts.TIMBER_DARK, Vector3.ZERO, _wheel)
		spoke.rotation.z = turn
		var paddle := Parts.box(Vector3(0.05, 0.2, 0.36), Parts.TIMBER_LIGHT, Vector3(cos(turn), sin(turn), 0) * radius, _wheel)
		paddle.rotation.z = turn
	_hung = _wheel
	_rolled = _wheel

## A box from `from` to `to`, `thick` square.
static func _bar(from: Vector3, to: Vector3, thick: float, color: Color, parent: Node3D) -> void:
	var line := to - from
	var bar := Parts.box(Vector3(thick, thick, line.length()), color, (from + to) * 0.5, parent)
	if line.length() > 0.001: bar.basis = Basis.looking_at(line.normalized(), Vector3.UP if absf(line.normalized().y) < 0.99 else Vector3.RIGHT)
