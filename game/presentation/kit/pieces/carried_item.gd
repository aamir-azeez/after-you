extends "res://presentation/kit/pieces/piece.gd"
## World kit: a carried item or a float (rules 16, core/physical/carried_items.gd)
## in one of its styles (content/dressing/prop_styles.gd "carried_item";
## content/dressing/piece_styles.gd picks which, a pin by the item's id first).
##
##   "parcel": a brown paper parcel tied with cream twine (the default).
##   "pipsport": a navy booklet with a gold crest on its cover.
##   "raft": a few lashed planks, for a float nobody carries.
##   "seed": the seed every world draws (presentation/seed_visual.gd), First
##       Steps' golden one.
##
## The world shows each snapshot's item state (journey_world _present_items):
## on a spirit's back (carry: the root rides under the spirit's facing pivot,
## so it follows every step and turn), resting at its place (rest), or bobbing
## on the water (rest with `floating`, advance() each frame while motion is not
## reduced). A float sits by the float rule (kit/floats.gd, its style's kind,
## else a raft's): its keel under the water's surface by its draft, its deck
## clear of it all through its bob. The root is the only part that changes, so
## it is the one moving part.
const Floats = preload("res://presentation/kit/floats.gd")
const Models = preload("res://presentation/kit/models.gd")
const Look = preload("res://presentation/spirit_look.gd")
const STYLES := ["parcel", "pipsport", "raft", "seed"]
## How far behind the back of a spirit's head a carried item's near face hangs
## (room for the head's hop and lean, which the item does not share).
const BACK_GAP := 0.03
const NAVY := Color("2f3e66")
const PAPER := Color("b98d5f")
## The seed's half height and colour (island_world.gd's seed).
const SEED_RADIUS := 0.13
const SEED_GOLD := Color("ffda83")
const SeedVisual = preload("res://presentation/seed_visual.gd")

## Where this item hangs on a spirit's back, in its facing pivot's space (the
## pip faces +Z there), turned `turn` (euler): see _back_from().
var back := Vector3.ZERO
var turn := Vector3.ZERO
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
	# It is picked up and set down: a live shadow, never baked.
	ContactShadows.mark(root, true)
	anchor = root
	_rest_at = at
	match item_style:
		"pipsport":
			Parts.box(Vector3(0.16, 0.035, 0.22), NAVY, Vector3(0, 0.02, 0), root)
			Parts.box(Vector3(0.012, 0.047, 0.232), NAVY.lightened(0.25), Vector3(-0.078, 0.02, 0), root)
			Parts.disc(0.035, 0.008, Parts.GOLD, Vector3(0.01, 0.045, -0.02), root)
		"seed":
			# The seed's builder asks the world for its meshes: the terrain's parent.
			SeedVisual.create(options.get("world", parent.get_parent()), SEED_RADIUS, SEED_GOLD, Vector3(0, SEED_RADIUS, 0), root)
		"raft":
			# The log raft model at the float's 0.8 by 0.72 m, resting on its spot.
			var raft := Models.moving("res://assets/models/raft.glb", "raft", {"log_a": Parts.TIMBER, "log_b": Parts.TIMBER_LIGHT, "lashing": Color("c9b48a"), "bearer": Parts.TIMBER_DARK}, root)
			raft.transform = Transform3D(Basis.from_scale(Vector3(0.8, 1.0, 0.9)), Vector3(0, 0.169, 0))
		_:
			Parts.box(Vector3(0.22, 0.14, 0.18), PAPER, Vector3(0, 0.07, 0), root)
			Parts.box(Vector3(0.232, 0.152, 0.025), Parts.CREAM, Vector3(0, 0.07, 0), root)
			Parts.box(Vector3(0.025, 0.164, 0.192), Parts.CREAM, Vector3(0, 0.07, 0), root)
	# A pipsport is worn flat against the back, its cover facing out.
	turn = Vector3(-PI / 2.0 if item_style == "pipsport" else 0.0, 0.0, 0.0)
	back = _back_from(turn)

## Where the item, turned `turn`, hangs on a spirit's back: its middle level
## with the middle of the head and in line with it, and its near face BACK_GAP
## behind the back of the head (spirit_look.gd HEAD_HALF), so every style shows
## outside the head, whatever its size.
func _back_from(item_turn: Vector3) -> Vector3:
	var turned := Transform3D(Basis.from_euler(item_turn), Vector3.ZERO)
	var box := AABB()
	var first := true
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var to_root := mesh.transform
		var parent := mesh.get_parent()
		while parent != root:
			to_root = (parent as Node3D).transform * to_root
			parent = parent.get_parent()
		var part: AABB = turned * to_root * mesh.get_aabb()
		box = part if first else box.merge(part)
		first = false
	var middle := box.get_center()
	return Vector3(-middle.x, Look.HEAD_CENTER.y - middle.y, -(Look.HEAD_HALF.z + BACK_GAP) - box.end.z)

## On `actor`'s back: it rides under the spirit from now on, behind it
## whichever way it faces.
func carry(actor: Node3D) -> void:
	_floating = false
	# The pip's own shadow shows it now.
	ContactShadows.set_off(root, true)
	# A pip hangs it under its facing pivot and sways it with its stride and its
	# stop (spirit_visual.gd hang_on_back).
	if actor.has_method("hang_on_back"): actor.hang_on_back(root, back, turn)
	else:
		if root.get_parent() != actor: root.reparent(actor, false)
		root.position = back
		root.rotation = turn

## Resting at `at` under `parent` (the terrain), or, when `floating`, on the
## water whose surface `at` is, bobbing.
func rest(at: Vector3, parent: Node3D, floating: bool) -> void:
	if root.get_parent() != parent: root.reparent(parent, false)
	_rest_at = at
	_floating = floating
	root.rotation = Vector3.ZERO
	root.position = Vector3(at.x, Floats.keel(style, at.y), at.z) if floating else at
	# Set down it has its shadow again, where it now rests; afloat, the water's
	# rings show it.
	ContactShadows.set_off(root, floating)
	ContactShadows.touch()

func moving() -> bool:
	return _floating

## A float's bob, on the world's clock.
func advance(delta: float) -> void:
	_clock += delta
	root.position = Vector3(_rest_at.x, Floats.keel(style, _rest_at.y, _clock, 0.0, false), _rest_at.z)

func moving_parts() -> Array[Node3D]:
	return [root]
