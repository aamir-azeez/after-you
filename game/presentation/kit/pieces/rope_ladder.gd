extends "res://presentation/kit/pieces/piece.gd"
## World kit: a pull-up rope ladder (rules 16's rope_ladder block: a stair
## with "one_way": "up"), in one of its styles (content/dressing/
## prop_styles.gd "ladder"; piece_styles.gd picks which, by the stair's id).
##
##   "rope": two side ropes and timber rungs along the stair's slope, from
##       its foot up to two iron hooks on its head. While no pip is near its
##       foot it is pulled up: rolled into a bundle on the hooks at the head,
##       so a pip at the top sees it cannot come down that way.
##
## Hung or rolled is presentation only (set_pulled), shown from where the
## pips stand; the rule itself (no step down it) is the simulation's.
const STYLES := ["rope"]
const ROPE := Color("c9b48a")
const RUNG := Color("9b7653")
const RUNGS := 8

var _hung: Node3D
var _rolled: Node3D

## A ladder in `style` on `stair` (its plan rect in metres as a Rect2, its
## foot and head heights in metres, along x when `along_x`, rising toward +
## when `rising`) under `parent`, hung.
static func build(ladder_style: String, rect: Rect2, foot: float, head: float, along_x: bool, rising: bool, parent: Node3D) -> RefCounted:
	var piece: RefCounted = load("res://presentation/kit/pieces/rope_ladder.gd").new()
	piece._make(ladder_style if ladder_style in STYLES else "rope", rect, foot, head, along_x, rising, parent)
	return piece

## Pulled up (rolled at the head) or let down (hung along the stair).
func set_pulled(pulled: bool, _immediate: bool = false) -> void:
	_hung.visible = not pulled
	_rolled.visible = pulled

func moving_parts() -> Array[Node3D]:
	return [_hung, _rolled]

func _make(ladder_style: String, rect: Rect2, foot: float, head: float, along_x: bool, rising: bool, parent: Node3D) -> void:
	style = ladder_style
	var center := Vector3(rect.get_center().x, foot, rect.get_center().y)
	_root("RopeLadder_" + ladder_style, center, parent)
	anchor = root
	var run := rect.size.x if along_x else rect.size.y
	var across := rect.size.y if along_x else rect.size.x
	var sign := 1.0 if rising else -1.0
	var bottom := Vector3(-sign * run * 0.5, 0.02, 0) if along_x else Vector3(0, 0.02, -sign * run * 0.5)
	var top := Vector3(sign * run * 0.5, head - foot + 0.02, 0) if along_x else Vector3(0, head - foot + 0.02, sign * run * 0.5)
	var side := Vector3(0, 0, across * 0.32) if along_x else Vector3(across * 0.32, 0, 0)
	_hung = Node3D.new()
	_hung.name = "Hung"
	root.add_child(_hung)
	for edge: float in [-1.0, 1.0]: _bar(bottom + side * edge, top + side * edge, 0.022, ROPE, _hung)
	for index in range(RUNGS):
		var at := bottom.lerp(top, (float(index) + 0.5) / float(RUNGS))
		_bar(at - side * 1.1, at + side * 1.1, 0.03, RUNG, _hung)
	for edge: float in [-1.0, 1.0]: Parts.box(Vector3(0.04, 0.08, 0.04), Parts.IRON, top + side * edge + Vector3(0, 0.03, 0), root)
	_rolled = Node3D.new()
	_rolled.name = "Rolled"
	_rolled.visible = false
	root.add_child(_rolled)
	var roll := Parts.rod(0.09, across * 0.8, RUNG, top + Vector3(0, 0.1, 0), _rolled)
	if along_x: roll.rotation = Vector3(PI / 2.0, 0, 0)
	for edge: float in [-1.0, 1.0]: Parts.torus(0.095, 0.015, ROPE, top + Vector3(0, 0.1, 0) + side * edge * 0.8, _rolled).rotation = Vector3(PI / 2.0, 0, 0) if along_x else Vector3(0, 0, PI / 2.0)

## A box from `from` to `to`, `thick` square.
static func _bar(from: Vector3, to: Vector3, thick: float, color: Color, parent: Node3D) -> void:
	var line := to - from
	var bar := Parts.box(Vector3(thick, thick, line.length()), color, (from + to) * 0.5, parent)
	if line.length() > 0.001: bar.basis = Basis.looking_at(line.normalized(), Vector3.UP if absf(line.normalized().y) < 0.99 else Vector3.RIGHT)
