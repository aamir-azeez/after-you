extends "res://presentation/kit/pieces/piece.gd"
## World kit: a pressure pad, in one of its styles (content/dressing/
## prop_styles.gd "pad"; content/dressing/piece_styles.gd picks which).
##
##   "plain": a low disc in the owner's colour, darkened, under a ring in it.
##   "stand_spot": a bright disc exactly the pad's radius under a firmer rim,
##       the owner's mark at its centre (kit/stand_spot.gd): the spot is just
##       where the pad counts a spirit. Held, it lights and sinks a little.
##   "pan": a weight lift's pan (rules 16's weight_lift block): a wide brass
##       dish on a timber cradle, three chains rising from its rim to a hook
##       over it. Held (something heavy in it), it sinks down its cradle.
##
## A ball pad (heavy) is always plain, gold, with a cream ring at its centre:
## no spirit stands on it. The world lights the pad's `rim` while it is held
## (the snapshot's hold_pads, the simulation's own rule).
const StandSpotKit = preload("res://presentation/kit/stand_spot.gd")
const STYLES := ["plain", "stand_spot", "pan"]
## Pan: how far the dish sinks while held, and the hook's height over it (m).
const PAN_SINK := 0.06
const PAN_HOOK := 0.95

## The ring the world lights while the pad is held.
var rim: MeshInstance3D
## The stand spot of a "stand_spot" pad, else null.
var spot: StandSpotKit
## A pan's dish, which sinks while held.
var _dish: Node3D

## A pad in `style` on the spot `at` (parent space) under `parent`, `radius_m`
## across. `options`: "owner" ("p0"/"p1"), "heavy" (a ball pad), "id" (names
## a stand spot "StandSpot_<id>").
static func build(pad_style: String, at: Vector3, radius_m: float, parent: Node3D, options: Dictionary = {}) -> RefCounted:
	var piece: RefCounted = load("res://presentation/kit/pieces/pad.gd").new()
	var heavy := bool(options.get("heavy", false))
	piece._make("plain" if heavy or pad_style not in STYLES else pad_style, at, radius_m, parent, options, heavy)
	return piece

func set_held(on: bool) -> void:
	if spot != null: spot.set_held(on)
	if _dish != null: _dish.position.y = -PAN_SINK if on else 0.0

func moving_parts() -> Array[Node3D]:
	var parts: Array[Node3D] = [rim]
	if spot != null: parts.append(spot)
	if _dish != null: parts.append(_dish)
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
