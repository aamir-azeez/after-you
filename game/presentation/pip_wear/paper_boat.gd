extends RefCounted
## Paper boat (hat): a folded paper boat on the head's top, tilted up away from
## the leaf, as the hats board draws it: a cream hull with pointed ends and a
## terracotta fold along its front edge, a cream sail folded down its middle,
## and the dark inside of the hull between them. Every face is flat, so the
## folds read as paper. It sits clear beside the leaf ("pokes_through"). One
## baked mesh, one draw call.
const Kit = preload("res://presentation/kit/pip_wear_kit.gd")

const PAPER := Color("eee9d4")
const FOLD := Color("cb8967")
const INK := Color("193d39")
## Where the keel's middle sits on the head and the boat's turn (head space):
## its right end raised, turned a little to show its side, and its size.
const AT := Vector3(0.24, 0.255, -0.015)
const TURN := Vector3(0.0, -0.22, 0.24)
const SCALE := 1.2
## The boat's own space: x along it, y up, z across. The keel's half length,
## the rim's tips (half length, height), the rim's sides (half length,
## height, half width), and where the terracotta fold starts up the side.
const KEEL := 0.12
const TIP := Vector2(0.255, 0.115)
const SIDE := Vector3(0.115, 0.085, 0.105)
const FOLD_FROM := 0.62
## The sail: its base's half length and half width, its peak, and how far its
## middle fold stands out.
const SAIL_BASE := Vector2(0.115, 0.048)
const SAIL_PEAK := Vector3(0.012, 0.24, 0.0)
const SAIL_FOLD := 0.018

## Metres a carried seed or lens sits higher while it is worn, just clear of
## the hat itself (a leaf may touch it; pip_outfit.gd lift_seed).
const SEED_LIFT := 0.075

static func wear(look: RefCounted) -> void:
	look.mesh(look.head(), Kit.cached_mesh("paper_boat", _build), Kit.vertex_material())
	look.lift_seed(SEED_LIFT)

static func _build() -> Mesh:
	var parts := Kit.Parts.new()
	parts.push(Kit.Parts.place(AT, TURN, Vector3.ONE * SCALE))
	var inside := Vector3(0.0, 0.04, 0.0)
	var keel := [Vector3(-KEEL, 0.0, 0.0), Vector3(KEEL, 0.0, 0.0)]
	var tips := [Vector3(-TIP.x, TIP.y, 0.0), Vector3(TIP.x, TIP.y, 0.0)]
	for side: float in [1.0, -1.0]:
		var rim := [Vector3(-SIDE.x, SIDE.y, SIDE.z * side), Vector3(SIDE.x, SIDE.y, SIDE.z * side)]
		var fold := [keel[0].lerp(rim[0], FOLD_FROM), keel[1].lerp(rim[1], FOLD_FROM)]
		# The side below the fold, the fold band up to the rim, and the pointed end flaps.
		parts.facets(PAPER, PackedVector3Array([keel[0], keel[1], fold[1], keel[0], fold[1], fold[0]]), inside)
		parts.facets(FOLD if side > 0.0 else PAPER, PackedVector3Array([fold[0], fold[1], rim[1], fold[0], rim[1], rim[0]]), inside)
		parts.facets(PAPER, PackedVector3Array([keel[0], rim[0], tips[0], keel[1], tips[1], rim[1]]), inside)
	# The hull's dark inside, just under the rim.
	var inner := SIDE.y - 0.012
	var front := [Vector3(-SIDE.x, inner, SIDE.z * 0.92), Vector3(SIDE.x, inner, SIDE.z * 0.92)]
	var back := [Vector3(-SIDE.x, inner, -SIDE.z * 0.92), Vector3(SIDE.x, inner, -SIDE.z * 0.92)]
	var ends := [Vector3(-TIP.x * 0.9, inner, 0.0), Vector3(TIP.x * 0.9, inner, 0.0)]
	parts.facets(INK, PackedVector3Array([front[0], front[1], back[1], front[0], back[1], back[0], ends[0], front[0], back[0], ends[1], back[1], front[1]]), Vector3(0.0, -1.0, 0.0))
	# The sail, folded down its middle on both faces.
	var peak := SAIL_PEAK
	for side: float in [1.0, -1.0]:
		var base := [Vector3(-SAIL_BASE.x, SIDE.y - 0.01, SAIL_BASE.y * side), Vector3(SAIL_BASE.x, SIDE.y - 0.01, SAIL_BASE.y * side)]
		var middle := Vector3(peak.x * 0.5, SIDE.y - 0.01, (SAIL_BASE.y + SAIL_FOLD) * side)
		var sail_inside := Vector3(peak.x * 0.5, SIDE.y + 0.04, 0.0)
		parts.facets(PAPER, PackedVector3Array([base[0], middle, peak, middle, base[1], peak]), sail_inside)
	# Its two narrow ends.
	var low := SIDE.y - 0.01
	parts.facets(PAPER, PackedVector3Array([Vector3(-SAIL_BASE.x, low, SAIL_BASE.y), Vector3(-SAIL_BASE.x, low, -SAIL_BASE.y), peak, Vector3(SAIL_BASE.x, low, SAIL_BASE.y), Vector3(SAIL_BASE.x, low, -SAIL_BASE.y), peak]), Vector3(peak.x * 0.5, SIDE.y + 0.04, 0.0))
	parts.pop()
	return parts.commit()
