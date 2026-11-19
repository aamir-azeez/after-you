extends "res://presentation/kit/pieces/piece.gd"
## World kit: a pressure pad, in one of its styles (content/dressing/
## prop_styles.gd "pad"; content/dressing/piece_styles.gd picks which).
##
##   "plain": a low disc in the owner's colour, darkened, under a ring in it.
##   "stand_spot": a bright disc exactly the pad's radius under a firmer rim,
##       the owner's mark at its centre (kit/stand_spot.gd): the spot is just
##       where the pad counts a spirit. Held, it lights and sinks a little.
##   "board": a board that needs a pip standing on it (a water gate board, a
##       winding board, a door step): a flat timber board on two bearers, its
##       rim the ring the world lights. Held, it sinks a little.
##   "crank_board": the board with a windlass beside it (a crank board that
##       keeps a rope bridge tight): its drum turns over while held.
##   "pan": a weight lift's pan (rules 16's weight_lift block): a wide brass
##       dish on a timber cradle, three chains rising from its rim to a hook
##       over it. Held (something heavy in it), it sinks down its cradle.
##
## Pressed, the part that sinks (a plain pad's ring, a stand spot, a board or
## a dish) dips DIP further and springs back to its held place (Motion.arrival),
## unless the call was immediate (a seek, a retry, reduced motion).
##
## A ball pad (heavy) is always plain, gold, with a cream ring at its centre:
## no spirit stands on it. The world lights the pad's `rim` while it is held
## (the snapshot's hold_pads, the simulation's own rule).
const StandSpotKit = preload("res://presentation/kit/stand_spot.gd")
const STYLES := ["plain", "stand_spot", "pan", "board", "crank_board"]
## Board: how far it sinks while held.
const BOARD_SINK := 0.025
## Pan: how far the dish sinks while held, and the hook's height over it (m).
const PAN_SINK := 0.06
const PAN_HOOK := 0.95
## How much further a pressed pad dips before it springs back (m).
const DIP := 0.01

## The ring the world lights while the pad is held.
var rim: MeshInstance3D
## The stand spot of a "stand_spot" pad, else null.
var spot: StandSpotKit
## A pan's dish or a board's top, which sinks while held; a crank board's drum.
var _dish: Node3D
var _drum: Node3D
var _held := false
## The dipping part's held height, which its dip springs back to.
var _dip_rest := 0.0

## A pad in `style` on the spot `at` (parent space) under `parent`, `radius_m`
## across. `options`: "owner" ("p0"/"p1"), "heavy" (a ball pad), "id" (names
## a stand spot "StandSpot_<id>").
static func build(pad_style: String, at: Vector3, radius_m: float, parent: Node3D, options: Dictionary = {}) -> RefCounted:
	var piece: RefCounted = load("res://presentation/kit/pieces/pad.gd").new()
	var heavy := bool(options.get("heavy", false))
	piece._make("plain" if heavy or pad_style not in STYLES else pad_style, at, radius_m, parent, options, heavy)
	return piece

func set_held(on: bool, immediate: bool = false) -> void:
	if on == _held and not immediate: return
	var pressed := on and not _held
	_held = on
	if _arriving(): _dip(0.0)
	_stop_arrival()
	if spot != null: spot.set_held(on)
	if _dish != null: _dish.position.y = -(PAN_SINK if style == "pan" else BOARD_SINK) if on else 0.0
	if _drum != null: _drum.rotation.x = PI * 0.5 if on else 0.0
	_dip_rest = _dipping().position.y
	if pressed and not immediate: _arrive(-DIP)

func moving() -> bool:
	return _arriving()

func advance(delta: float) -> void:
	_dip(_arrival_step(delta))

## The part a press dips: a board or dish, a stand spot, else the ring.
func _dipping() -> Node3D:
	if _dish != null: return _dish
	return spot if spot != null else rim

func _dip(offset: float) -> void:
	_dipping().position.y = _dip_rest + offset

func moving_parts() -> Array[Node3D]:
	var parts: Array[Node3D] = [rim]
	if spot != null: parts.append(spot)
	if _dish != null: parts.append(_dish)
	if _drum != null: parts.append(_drum)
	return parts

func _make(pad_style: String, at: Vector3, radius_m: float, parent: Node3D, options: Dictionary, heavy: bool) -> void:
	style = pad_style
	var owner := str(options.get("owner", "p0"))
	var color := Parts.GOLD if heavy else Parts.owner_color(owner)
	if pad_style == "stand_spot":
		spot = StandSpotKit.new()
		parent.add_child(spot)
		spot.build(at, radius_m, owner, color, Parts.LIGHT)
		spot.name = "StandSpot_" + str(options.get("id", ""))
		root = spot
		anchor = spot
		rim = spot.rim
		return
	if pad_style == "pan":
		_make_pan(at, radius_m, parent, color)
		return
	if pad_style in ["board", "crank_board"]:
		_make_board(at, radius_m, parent, color)
		return
	_root("Pad_plain", at, parent)
	anchor = root
	Parts.cylinder(radius_m, 0.055, color.darkened(0.25), Vector3(0, 0.025, 0), root)
	rim = Parts.ring(radius_m, color, Vector3(0, 0.065, 0), root)
	if heavy: Parts.ring(0.16, Parts.CREAM, Vector3(0, 0.06, 0), root)

## The pan: a timber cradle ring on the floor, the dish in it (its rim the
## ring the world lights), chains up to the hook over it. Every part stays
## within the pad's radius, so a spirit standing in it stands in the dish.
func _make_pan(at: Vector3, radius_m: float, parent: Node3D, color: Color) -> void:
	_root("Pad_pan", at, parent)
	anchor = root
	Parts.disc(radius_m, 0.05, Parts.TIMBER, Vector3(0, 0.025, 0), root)
	_dish = Node3D.new()
	root.add_child(_dish)
	Parts.disc(radius_m * 0.9, 0.035, Parts.BRASS, Vector3(0, 0.075, 0), _dish, radius_m * 0.96)
	rim = Parts.ring(radius_m, color, Vector3(0, 0.1, 0), _dish)
	for turn in range(3):
		var side := Vector3.FORWARD.rotated(Vector3.UP, TAU * float(turn) / 3.0) * radius_m * 0.82
		var chain := Parts.box(Vector3(0.012, PAN_HOOK, 0.012), Parts.IRON, side * 0.5 + Vector3(0, 0.1 + PAN_HOOK * 0.5, 0), _dish)
		# Leaning in from the rim to the hook over the middle.
		chain.basis = Basis(Vector3(side.z, 0, -side.x).normalized(), -atan2(radius_m * 0.82, PAN_HOOK))
	Parts.ring(0.04, Parts.IRON, Vector3(0, 0.1 + PAN_HOOK, 0), _dish)

## A square timber board the pad's size on two bearers, its rim ring lit while
## held; a crank board adds a windlass on a frame at its north edge.
func _make_board(at: Vector3, radius_m: float, parent: Node3D, color: Color) -> void:
	_root("Pad_" + style, at, parent)
	anchor = root
	var side := radius_m * 1.6
	for x: float in [-0.35, 0.35]: Parts.box(Vector3(0.06, 0.03, side), Parts.TIMBER_DARK, Vector3(x * side, 0.015, 0), root)
	_dish = Node3D.new()
	root.add_child(_dish)
	for index in range(4):
		Parts.box(Vector3(side, 0.03, side / 4.0 - 0.012), Parts.TIMBER_LIGHT.darkened(0.06 * float(index % 2)), Vector3(0, 0.045, -side * 0.5 + (float(index) + 0.5) * side / 4.0), _dish)
	rim = Parts.ring(radius_m, color, Vector3(0, 0.07, 0), _dish)
	if style != "crank_board": return
	var frame_z := -side * 0.5 - 0.1
	for x: float in [-0.18, 0.18]: Parts.box(Vector3(0.05, 0.42, 0.05), Parts.TIMBER_DARK, Vector3(x, 0.21, frame_z), root)
	_drum = Node3D.new()
	_drum.position = Vector3(0, 0.36, frame_z)
	root.add_child(_drum)
	Parts.rod(0.07, 0.30, Parts.TIMBER, Vector3.ZERO, _drum)
	Parts.box(Vector3(0.32, 0.02, 0.15), Color("c9b48a"), Vector3.ZERO, _drum)
