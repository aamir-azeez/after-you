extends "res://presentation/kit/pieces/piece.gd"
## World kit: a crossing that rises into place as it opens and sinks out of
## reach as it shuts (Relay Isles' bridges between its islands): seven planks
## across the crossing's rectangle, each with a post at both sides, under a
## root at the crossing's middle named by its id. Open, it lies at its floor's
## height; shut, SUNK metres under it. Built from the definition's crossing
## alone (island_world _build_crossings), fed the snapshot's bridges.
##   var piece := Bridge.build(bridge, parent)
##   piece.set_open(state.bridges[id], immediate)   # each snapshot
##   if piece.moving(): piece.advance(delta)       # each frame
## An immediate call snaps, so live play, the memory and a replay show the same.
## A crossing that reaches its height thuds there: it runs OVER past it and
## settles back (Motion.arrival), then rests exactly at that height.

const PLANK := Color("c4b090")
const POST := Color("8b7964")
const PLANKS := 7
## How far under its floor a shut crossing lies, and a new one starts (metres).
const SUNK := -0.65
const BUILT := -0.6
## How fast a moving crossing closes on its pose: this share of the way a
## second, at most all of it in one frame.
const RATE := 12.0
## How near its height (m) a moving crossing counts as there, and how far it
## overshoots it as it lands.
const LANDED := 0.005
const OVER := 0.025

## The floor height the crossing lies at when open (metres).
var _rest := 0.0
var _target := 0.0
## The height the crossing is on its way through, without its overshoot
## (kept here at full precision: the root's own float would never equal it).
var _y := 0.0

## The crossing `bridge` ({id, rect_cm, height_cm?}) under `parent`.
static func build(bridge: Dictionary, parent: Node3D) -> RefCounted:
	var piece: RefCounted = load("res://presentation/kit/pieces/bridge.gd").new()
	piece._make(bridge, parent)
	return piece

## Opens or shuts the crossing; immediate puts it there at once.
func set_open(on: bool, immediate: bool = false) -> void:
	var target := _rest + (0.0 if on else SUNK)
	if target != _target or immediate: _stop_arrival()
	_target = target
	if immediate:
		_y = _target
		root.position.y = _y

## Whether the crossing is open or opening.
func is_open() -> bool:
	return is_equal_approx(_target, _rest)

func moving() -> bool:
	return _arriving() or _y != _target

func advance(delta: float) -> void:
	if not moving(): return
	if _arriving():
		root.position.y = _target + _arrival_step(delta)
		return
	var was := _y
	_y = lerpf(was, _target, minf(delta * RATE, 1.0))
	if absf(_y - _target) < LANDED:
		_y = _target
		_arrive(OVER * signf(_target - was))
	root.position.y = _y

## Nothing under the root changes: the root rises and sinks whole. The world
## holds it (its sound anchor), so the static fold batches the planks under it
## and they move with it.
func moving_parts() -> Array[Node3D]:
	return []

func _make(bridge: Dictionary, parent: Node3D) -> void:
	style = "planks"
	var rect: Array = bridge.rect_cm
	var width := float(rect[2] - rect[0]) / 100.0
	var depth := float(rect[3] - rect[1]) / 100.0
	_rest = float(bridge.get("height_cm", 0)) / 100.0
	_target = _rest + SUNK
	_root(str(bridge.id), Vector3(float(rect[0] + rect[2]) / 200.0, _rest + BUILT, float(rect[1] + rect[3]) / 200.0), parent)
	anchor = root
	_y = root.position.y
	for index in range(PLANKS):
		var x := -width / 2.0 + (float(index) + 0.5) * width / PLANKS
		var plank := Parts.box(Vector3(width / PLANKS - 0.012, 0.10, depth), PLANK, Vector3(x, -0.06, 0), root)
		for side in [-1, 1]:
			Parts.cylinder(0.035, 0.3, POST, Vector3(0, 0.19, side * (depth / 2.0 - 0.06)), plank)
