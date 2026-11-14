extends "res://presentation/kit/pieces/piece.gd"
## World kit: a pressure pad, in one of its styles (content/dressing/
## prop_styles.gd "pad"; content/dressing/piece_styles.gd picks which).
##
##   "plain": a low disc in the owner's colour, darkened, under a ring in it.
##   "stand_spot": a bright disc exactly the pad's radius under a firmer rim,
##       the owner's mark at its centre (kit/stand_spot.gd): the spot is just
##       where the pad counts a spirit. Held, it lights and sinks a little.
##
## A ball pad (heavy) is always plain, gold, with a cream ring at its centre:
## no spirit stands on it. The world lights the pad's `rim` while it is held
## (the snapshot's hold_pads, the simulation's own rule).
const StandSpotKit = preload("res://presentation/kit/stand_spot.gd")
const STYLES := ["plain", "stand_spot"]

## The ring the world lights while the pad is held.
var rim: MeshInstance3D
## The stand spot of a "stand_spot" pad, else null.
var spot: StandSpotKit

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

func moving_parts() -> Array[Node3D]:
	var parts: Array[Node3D] = [rim]
	if spot != null: parts.append(spot)
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
	_root("Pad_plain", at, parent)
	anchor = root
	Parts.cylinder(radius_m, 0.055, color.darkened(0.25), Vector3(0, 0.025, 0), root)
	rim = Parts.ring(radius_m, color, Vector3(0, 0.065, 0), root)
	if heavy: Parts.ring(0.16, Parts.CREAM, Vector3(0, 0.06, 0), root)
