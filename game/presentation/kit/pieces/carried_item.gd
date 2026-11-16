extends "res://presentation/kit/pieces/piece.gd"
## World kit: a carried item or a float (rules 16, core/physical/carried_items.gd)
## in one of its styles (content/dressing/prop_styles.gd "carried_item";
## content/dressing/piece_styles.gd picks which, a pin by the item's id first).
##
##   "parcel": a brown paper parcel tied with cream twine (the default).
##   "pipsport": a navy booklet with a gold crest on its cover.
##   "raft": a few lashed planks, for a float nobody carries.
##
## The world shows each snapshot's item state (journey_world _present_items):
## on a spirit's back (carry: the root rides under the spirit, so it follows
## every step), resting at its place (rest), or bobbing on the water (rest with
## `floating`, advance() each frame while motion is not reduced). The root is
## the only part that changes, so it is the one moving part.
const STYLES := ["parcel", "pipsport", "raft"]
## Where an item sits on a spirit's back, in the spirit's own space.
const BACK := Vector3(0.0, 0.62, -0.2)
## How far a float bobs, and how fast.
const BOB_M := 0.025
const BOB_RATE := 2.2
const NAVY := Color("2f3e66")
const PAPER := Color("b98d5f")

var _rest_at := Vector3.ZERO
var _floating := false
var _clock := 0.0

## An item in `item_style` under `parent`, at `at` until the first present.
static func build(item_style: String, at: Vector3, parent: Node3D, options: Dictionary = {}) -> RefCounted:
	var piece: RefCounted = load("res://presentation/kit/pieces/carried_item.gd").new()
	piece._make(item_style if item_style in STYLES else "parcel", at, parent, options)
	return piece

func _make(item_style: String, at: Vector3, parent: Node3D, options: Dictionary) -> void:
	style = item_style
	_root("CarriedItem_" + str(options.get("id", "")), at, parent)
	anchor = root
	_rest_at = at
	match item_style:
		"pipsport":
			Parts.box(Vector3(0.16, 0.035, 0.22), NAVY, Vector3(0, 0.02, 0), root)
			Parts.box(Vector3(0.012, 0.047, 0.232), NAVY.lightened(0.25), Vector3(-0.078, 0.02, 0), root)
			Parts.disc(0.035, 0.008, Parts.GOLD, Vector3(0.01, 0.045, -0.02), root)
		"raft":
			for index in range(4):
				Parts.box(Vector3(0.18, 0.06, 0.72), Parts.TIMBER if index % 2 == 0 else Parts.TIMBER_LIGHT, Vector3(-0.285 + 0.19 * index, 0.03, 0), root)
			for z: float in [-0.25, 0.25]:
				Parts.box(Vector3(0.8, 0.03, 0.06), Parts.TIMBER_DARK, Vector3(0, 0.075, z), root)
		_:
			Parts.box(Vector3(0.22, 0.14, 0.18), PAPER, Vector3(0, 0.07, 0), root)
			Parts.box(Vector3(0.232, 0.152, 0.025), Parts.CREAM, Vector3(0, 0.07, 0), root)
			Parts.box(Vector3(0.025, 0.164, 0.192), Parts.CREAM, Vector3(0, 0.07, 0), root)

## On `actor`'s back: it rides under the spirit from now on.
func carry(actor: Node3D) -> void:
	_floating = false
	if root.get_parent() != actor: root.reparent(actor, false)
	root.position = BACK
	root.rotation = Vector3(-PI / 2.0 if style == "pipsport" else 0.0, 0.0, 0.0)

## Resting at `at` under `parent` (the terrain), bobbing when `floating`.
func rest(at: Vector3, parent: Node3D, floating: bool) -> void:
	if root.get_parent() != parent: root.reparent(parent, false)
	_rest_at = at
	_floating = floating
	root.rotation = Vector3.ZERO
	root.position = at

func moving() -> bool:
	return _floating

## A float's bob, on the world's clock.
func advance(delta: float) -> void:
	_clock += delta
	root.position = _rest_at + Vector3(0, sin(_clock * BOB_RATE) * BOB_M, 0)

func moving_parts() -> Array[Node3D]:
	return [root]
