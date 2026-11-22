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
##   "winch_handle": an iron crank with a wooden grip
##       (tools/blender/models/winch_handle.py). It lies on its side on the
##       ground and in a pip's hands; fitted (resting at a solid spot: a winch,
##       socket.gd winch()) it stands with its stub in the socket (fit()).
##
## The world shows each snapshot's item state (journey_world _present_items):
## over a spirit's head (carry: held the one way a seed or a lens is, its
## middle on the spirit's carry point, spirit_visual.gd hold_overhead, turned
## the way the pip faces), resting at its place (rest), or bobbing on the
## water (rest with `floating`). advance() each frame while moving(): a carried
## item follows its carrier, a float bobs unless motion is reduced, and a
## pick-up or a set-down eases between the ground and the head for HANDOFF
## seconds (an immediate call or Reduce motion snaps; a catch snaps, as the
## seed's does). A float sits by the float rule (kit/floats.gd, its style's
## kind, else a raft's): its keel under the water's surface by its draft, its
## deck clear of it all through its bob. The root is the only part that
## changes, so it is the one moving part.
const Floats = preload("res://presentation/kit/floats.gd")
const Models = preload("res://presentation/kit/models.gd")
const SpiritVisual = preload("res://presentation/spirit_visual.gd")
const STYLES := ["parcel", "pipsport", "raft", "seed", "winch_handle"]
const HANDLE := "res://assets/models/winch_handle.glb"
## The handle lying on its side: turned onto its grip's flat, its 5 cm iron
## half over the floor, the middle of its length over its spot.
const HANDLE_LIE := Transform3D(Basis(Vector3.BACK, PI / 2.0), Vector3(0.12, 0.026, 0))
## How long a pick-up or a set-down takes between the ground and the head (s).
const HANDOFF := 0.2
const NAVY := Color("2f3e66")
const PAPER := Color("b98d5f")
## The seed's half height and colour (island_world.gd's seed).
const SEED_RADIUS := 0.13
const SEED_GOLD := Color("ffda83")
const SeedVisual = preload("res://presentation/seed_visual.gd")

## Its middle and half its widest side at its own size, from its built parts:
## the head carry holds it by these.
var middle := Vector3.ZERO
var radius := 0.0
## The spirit carrying it, or null while it rests.
var holder: SpiritVisual = null
var _rest_at := Vector3.ZERO
var _floating := false
var _flying := false
var _clock := 0.0
## Where it is drawn now, a handoff aside, and where a handoff set off from.
var _place := Vector3.ZERO
var _from := Vector3.ZERO
var _handoff_age := HANDOFF
## Whether it has been drawn yet: the first showing never eases from the build spot.
var _shown := false
## A handle's pose (fit()): lying, or standing in its socket. Null for other styles.
var _pose: Node3D = null

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
	_place = at
	match item_style:
		"pipsport":
			Parts.box(Vector3(0.16, 0.035, 0.22), NAVY, Vector3(0, 0.02, 0), root)
			Parts.box(Vector3(0.012, 0.047, 0.232), NAVY.lightened(0.25), Vector3(-0.078, 0.02, 0), root)
			Parts.disc(0.035, 0.008, Parts.GOLD, Vector3(0.01, 0.045, -0.02), root)
		"seed":
			# The seed's builder asks the world for its meshes: the terrain's parent.
			SeedVisual.create(options.get("world", parent.get_parent()), SEED_RADIUS, SEED_GOLD, Vector3(0, SEED_RADIUS, 0), root)
		"winch_handle":
			_pose = Node3D.new()
			_pose.name = "HandlePose"
			_pose.transform = HANDLE_LIE
			root.add_child(_pose)
			Models.moving(HANDLE, "winch_handle", {"metal": Parts.IRON, "grip": Color("b08a62")}, _pose)
		"raft":
			# The log raft model at the float's 0.8 by 0.72 m, resting on its spot.
			var raft := Models.moving("res://assets/models/raft.glb", "raft", {"log_a": Parts.TIMBER, "log_b": Parts.TIMBER_LIGHT, "lashing": Color("c9b48a"), "bearer": Parts.TIMBER_DARK}, root)
			raft.transform = Transform3D(Basis.from_scale(Vector3(0.8, 1.0, 0.9)), Vector3(0, 0.169, 0))
		_:
			Parts.box(Vector3(0.22, 0.14, 0.18), PAPER, Vector3(0, 0.07, 0), root)
			Parts.box(Vector3(0.232, 0.152, 0.025), Parts.CREAM, Vector3(0, 0.07, 0), root)
			Parts.box(Vector3(0.025, 0.164, 0.192), Parts.CREAM, Vector3(0, 0.07, 0), root)
	_measure()

## Its middle and half its widest side, from the boxes of its built meshes.
func _measure() -> void:
	var box := AABB()
	var first := true
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var to_root := mesh.transform
		var parent := mesh.get_parent()
		while parent != root:
			to_root = (parent as Node3D).transform * to_root
			parent = parent.get_parent()
		var part: AABB = to_root * mesh.get_aabb()
		box = part if first else box.merge(part)
		first = false
	middle = box.get_center()
	radius = box.size[box.get_longest_axis_index()] / 2.0

## Over `actor`'s head (a spirit), from now on until it rests: it follows the
## spirit's carry point each advance(). Picked up from where it rested, it
## rises there over HANDOFF unless `immediate`.
func carry(actor: SpiritVisual, immediate: bool = true) -> void:
	if actor != holder: _hand_off(immediate or _flying)
	holder = actor
	_floating = false
	_flying = false
	if root.get_parent() != actor.get_parent(): root.reparent(actor.get_parent(), false)
	# The pip's own shadow shows it now.
	ContactShadows.set_off(root, true)
	root.scale = Vector3.ONE * actor.hold_overhead(radius)
	_follow()
	_draw()

## A pick-up or a set-down starts from where it is drawn now, or snaps.
func _hand_off(snap: bool) -> void:
	_from = root.position
	_handoff_age = HANDOFF if snap or reduced_motion or not _shown else 0.0

## On its carrier's carry point, its middle there, turned the way it faces.
func _follow() -> void:
	if not is_instance_valid(holder):
		holder = null
		return
	var yaw := Basis(Vector3.UP, holder.facing.rotation.y)
	root.basis = yaw.scaled(root.scale)
	_place = holder.carry_point() - yaw * (middle * root.scale)

func _draw() -> void:
	_shown = true
	root.position = _place if _handoff_age >= HANDOFF else _from.lerp(_place, smoothstep(0.0, 1.0, _handoff_age / HANDOFF))

## Resting at `at` under `parent` (the terrain), or, when `floating`, on the
## water whose surface `at` is, bobbing; `flying` while a throw's arc has it.
## Set down from a head, it eases there over HANDOFF unless `immediate`.
func rest(at: Vector3, parent: Node3D, floating: bool, flying: bool = false, immediate: bool = true) -> void:
	if holder != null: _hand_off(immediate)
	holder = null
	if root.get_parent() != parent: root.reparent(parent, false)
	_rest_at = at
	_floating = floating
	_flying = flying
	root.rotation = Vector3.ZERO
	root.scale = Vector3.ONE
	place(Vector3(at.x, Floats.keel(style, at.y), at.z) if floating else at)
	# Set down it has its shadow again, where it now rests; afloat, the water's
	# rings show it.
	ContactShadows.set_off(root, floating)
	ContactShadows.touch()

## Where it rests now (a deck it rests on moves it), a handoff aside.
func place(at: Vector3) -> void:
	_place = at
	_draw()

func moving() -> bool:
	return holder != null or _floating or _handoff_age < HANDOFF

## A frame on the world's clock: it follows its carrier, a float bobs unless
## motion is reduced, and a handoff eases on.
func advance(delta: float) -> void:
	_handoff_age = minf(_handoff_age + delta, HANDOFF)
	if holder != null: _follow()
	elif _floating and not reduced_motion:
		_clock += delta
		_place = Vector3(_rest_at.x, Floats.keel(style, _rest_at.y, _clock, 0.0, false), _rest_at.z)
	_draw()

func moving_parts() -> Array[Node3D]:
	# A handle's pose turns under its root, which the fold already keeps whole.
	return [root]

## Whether the item rests fitted in a socket (a solid spot): a handle then
## stands with its stub in it, else lies on its side. Other styles keep one pose.
func fit(fitted: bool) -> void:
	if _pose != null: _pose.transform = Transform3D.IDENTITY if fitted else HANDLE_LIE
