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
## `floating`, advance() each frame while motion is not reduced). A float sits
## by the float rule (kit/floats.gd, its style's kind, else a raft's): its
## keel under the water's surface by its draft, its deck clear of it all
## through its bob. The root is the only part that changes, so it is the one
## moving part.
const STYLES := ["parcel", "pipsport", "raft"]
const Floats = preload("res://presentation/kit/floats.gd")
const Models = preload("res://presentation/kit/models.gd")
## Where an item sits on a spirit's back, in the spirit's own space.
const BACK := Vector3(0.0, 0.62, -0.2)
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
			# The log raft model at the float's 0.8 by 0.72 m, resting on its spot.
			var raft := Models.moving("res://assets/models/raft.glb", "raft", {"log_a": Parts.TIMBER, "log_b": Parts.TIMBER_LIGHT, "lashing": Color("c9b48a"), "bearer": Parts.TIMBER_DARK}, root)
			raft.transform = Transform3D(Basis.from_scale(Vector3(0.8, 1.0, 0.9)), Vector3(0, 0.169, 0))
		_:
			Parts.box(Vector3(0.22, 0.14, 0.18), PAPER, Vector3(0, 0.07, 0), root)
			Parts.box(Vector3(0.232, 0.152, 0.025), Parts.CREAM, Vector3(0, 0.07, 0), root)
			Parts.box(Vector3(0.025, 0.164, 0.192), Parts.CREAM, Vector3(0, 0.07, 0), root)

## On `actor`'s back: it rides under the spirit from now on.
func carry(actor: Node3D) -> void:
	_floating = false
	if root.get_parent() != actor: root.reparent(actor, false)
	var turn := Vector3(-PI / 2.0 if style == "pipsport" else 0.0, 0.0, 0.0)
	# A pip sways it with its stride and its stop (spirit_visual.gd hang_on_back).
	if actor.has_method("hang_on_back"): actor.hang_on_back(root, BACK, turn)
	else:
		root.position = BACK
		root.rotation = turn

## Resting at `at` under `parent` (the terrain), or, when `floating`, on the
## water whose surface `at` is, bobbing.
func rest(at: Vector3, parent: Node3D, floating: bool) -> void:
	if root.get_parent() != parent: root.reparent(parent, false)
	_rest_at = at
	_floating = floating
	root.rotation = Vector3.ZERO
	root.position = Vector3(at.x, Floats.keel(style, at.y), at.z) if floating else at

func moving() -> bool:
	return _floating

## A float's bob, on the world's clock.
func advance(delta: float) -> void:
	_clock += delta
	root.position = Vector3(_rest_at.x, Floats.keel(style, _rest_at.y, _clock, 0.0, false), _rest_at.z)

func moving_parts() -> Array[Node3D]:
	return [root]
