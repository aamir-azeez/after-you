extends "res://presentation/kit/pieces/piece.gd"
## World kit: a pressure pad, in one of its styles (content/dressing/
## prop_styles.gd "pad"; content/dressing/piece_styles.gd picks which).
##
##   "board": the one pad look (every level and version): a flat timber
##       board of four planks, its rim the ring the world lights, in the
##       owner's colour. Held, it sinks a little into the floor.
##   "crank_board": the board with a windlass beside it (a crank board that
##       keeps a rope bridge tight): its drum turns over while held.
##   "pan": a weight lift's pan (rules 20's weight_lift block): a wide brass
##       dish on a timber cradle, nothing over it (a pip stands in it). Held
##       (something heavy in it), it sinks down its cradle.
##
## Pressed, the part that sinks (a board or a dish) dips DIP further and
## springs back to its held place (Motion.arrival), unless the call was
## immediate (a seek, a retry, reduced motion). A board's top stays above the
## floor at the bottom of its dip, so a pad never vanishes under a pip.
##
## A ball pad (heavy) is a gold board with a cream ring at its centre: no
## spirit stands on it. The world lights the pad's `rim` while it is held
## (the snapshot's hold_pads, the simulation's own rule).
##
## Cost: the board's planks fold into one batch under the part that sinks
## (kit/static_batch.gd), so a board draws its planks and its rim.
const StaticBatch = preload("res://presentation/kit/static_batch.gd")
const STYLES := ["board", "crank_board", "pan"]
const DEFAULT_STYLE := "board"
## Board: its planks' top over the floor, and how far it sinks while held.
const BOARD_TOP := 0.06
const BOARD_SINK := 0.025
## Board: its rim ring's height on the board.
const BOARD_RIM := 0.07
## Pan: how far the dish sinks while held (m).
const PAN_SINK := 0.06
const PAN_RIM := 0.1
## How much further a pressed pad dips before it springs back (m).
const DIP := 0.01
## Pan: its dish's middle over the floor and its thickness (m). An item set
## down on a pad rests on its dish or its board's planks (top()).
const DISH_Y := 0.075
const DISH_THICK := 0.035

## The ring the world lights while the pad is held.
var rim: MeshInstance3D
## The pad's floor point (parent space) and radius (m): where it counts a pip.
var at := Vector3.ZERO
var radius := 0.0
## A pan's dish or a board's top, which sinks while held; a crank board's drum.
var _dish: Node3D
var _drum: Node3D
var _held := false
## The dipping part's held height, which its dip springs back to.
var _dip_rest := 0.0
## The rim's height over the floor while the pad is free.
var _rim_rest := 0.0

## How far from its centre a pad in `pad_style`, `radius_m` across, is drawn
## on its floor (metres): a board's corners, a crank board's windlass frame.
static func drawn_radius(pad_style: String, radius_m: float) -> float:
	var half := radius_m * 0.8
	match pad_style:
		"board": return half * sqrt(2.0)
		"crank_board": return maxf(half * sqrt(2.0), Vector2(0.205, half + 0.125).length())
	return radius_m

## A pad in `style` on the spot `at` (parent space) under `parent`, `radius_m`
## across. `options`: "owner" ("p0"/"p1"), "heavy" (a ball pad), "id",
## "shadow": false for no contact shadow (a pad on a goal's disc); a board
## never casts one.
static func build(pad_style: String, at: Vector3, radius_m: float, parent: Node3D, options: Dictionary = {}) -> RefCounted:
	var piece: RefCounted = load("res://presentation/kit/pieces/pad.gd").new()
	var heavy := bool(options.get("heavy", false))
	piece._make(DEFAULT_STYLE if heavy or pad_style not in STYLES else pad_style, at, radius_m, parent, options, heavy)
	return piece

func set_held(on: bool, immediate: bool = false) -> void:
	if on == _held and not immediate: return
	var pressed := on and not _held
	_held = on
	if _arriving(): _dip(0.0)
	_stop_arrival()
	_dish.position.y = -(PAN_SINK if style == "pan" else BOARD_SINK) if on else 0.0
	if _drum != null: _drum.rotation.x = PI * 0.5 if on else 0.0
	_dip_rest = _dish.position.y
	if pressed and not immediate: _arrive(-DIP)

## Whether the pad shows held.
func held() -> bool:
	return _held

## The rim's centre while the pad is free, in global space: what lays out
## around the pad holds still while a pip steps on and off.
func rest_rim() -> Vector3:
	return root.to_global(Vector3(0, _rim_rest, 0))

## How high over its floor an item set down on the pad rests now (m): on top
## of its board or dish, sunk with it while held, so it never sinks into the
## pad.
func top() -> float:
	return _dish.position.y + (DISH_Y + DISH_THICK / 2.0 if style == "pan" else BOARD_TOP)

func moving() -> bool:
	return _arriving()

func advance(delta: float) -> void:
	_dip(_arrival_step(delta))

func _dip(offset: float) -> void:
	_dish.position.y = _dip_rest + offset

func moving_parts() -> Array[Node3D]:
	var parts: Array[Node3D] = [rim, _dish]
	if _drum != null: parts.append(_drum)
	return parts

func _make(pad_style: String, at_point: Vector3, radius_m: float, parent: Node3D, options: Dictionary, heavy: bool) -> void:
	style = pad_style
	at = at_point
	radius = radius_m
	var color := Parts.GOLD if heavy else Parts.owner_color(str(options.get("owner", "p0")))
	# A board lies flat on the floor and sinks into it: no contact shadow.
	if pad_style != "board" and bool(options.get("shadow", true)): _root("Pad_" + pad_style, at_point, parent)
	else: _root("Pad_" + pad_style, at_point, parent, false)
	anchor = root
	if pad_style == "pan": _make_pan(radius_m, color)
	else: _make_board(radius_m, color, heavy)
	_rim_rest = rim.position.y
	# The planks (or the dish) draw as one batch under the part that sinks.
	StaticBatch.fold(_dish, [self])

## The pan: a timber cradle ring on the floor, the dish in it (its rim the
## ring the world lights). Every part stays within the pad's radius and under
## a step, so a spirit standing in it stands in the dish.
func _make_pan(radius_m: float, color: Color) -> void:
	Parts.disc(radius_m, 0.05, Parts.TIMBER, Vector3(0, 0.025, 0), root)
	_dish = Node3D.new()
	root.add_child(_dish)
	Parts.disc(radius_m * 0.9, DISH_THICK, Parts.BRASS, Vector3(0, DISH_Y, 0), _dish, radius_m * 0.96)
	rim = Parts.ring(radius_m, color, Vector3(0, PAN_RIM, 0), _dish)

## A square timber board the pad's size, four thick planks standing on the
## floor that sink into it as one while held, its rim ring lit while
## held (a ball pad's with a cream ring at its centre); a crank board adds a
## windlass on a frame at its north edge.
func _make_board(radius_m: float, color: Color, heavy: bool) -> void:
	var side := radius_m * 1.6
	_dish = Node3D.new()
	root.add_child(_dish)
	for index in range(4):
		Parts.box(Vector3(side, BOARD_TOP, side / 4.0 - 0.012), Parts.TIMBER_LIGHT.darkened(0.06 * float(index % 2)), Vector3(0, BOARD_TOP * 0.5, -side * 0.5 + (float(index) + 0.5) * side / 4.0), _dish)
	rim = Parts.ring(radius_m, color, Vector3(0, BOARD_RIM, 0), _dish)
	if heavy: Parts.ring(0.16, Parts.CREAM, Vector3(0, BOARD_RIM - 0.005, 0), _dish)
	if style != "crank_board": return
	var frame_z := -side * 0.5 - 0.1
	for x: float in [-0.18, 0.18]: Parts.box(Vector3(0.05, 0.42, 0.05), Parts.TIMBER_DARK, Vector3(x, 0.21, frame_z), root)
	_drum = Node3D.new()
	_drum.position = Vector3(0, 0.36, frame_z)
	root.add_child(_drum)
	Parts.rod(0.07, 0.30, Parts.TIMBER, Vector3.ZERO, _drum)
	Parts.box(Vector3(0.32, 0.02, 0.15), Color("c9b48a"), Vector3.ZERO, _drum)
