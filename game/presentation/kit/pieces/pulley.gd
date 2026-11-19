extends "res://presentation/kit/pieces/piece.gd"
## World kit: the pulley post by a missing crossing, in one of its styles
## (content/dressing/prop_styles.gd "pulley"; content/dressing/piece_styles.gd
## picks which). Each style names the weight hung on its rope:
##
##   "lantern_hook": a timber crook post with leaves climbing it and a little
##       wheel under its hook; a leafy lantern hangs from it and glows while
##       the crossing is laid.
##   "theme_hanger": a white post with red bands and a curled arm with a brass
##       wheel; an anchor hangs from it, and a rope coil lies beside its foot,
##       away from the crossing, where the floor has room for it.
##   "little_roof": a timber post on a stone foot under a little pitched roof,
##       its wheel under the eaves; a flour sack hangs from it.
##
## The weight hangs ROPE_X out from the post at REST_Y, the crossing gone. Its
## world drops it 0.7 m while the crossing is laid (cooperative_world's
## _weights), then calls set_laid(), which runs the rope down to the weight
## and lights a lantern. Every part keeps a few millimetres off its
## neighbours' faces, and their widths are odd millimetres, so no face lands on
## a wall or floor edge laid on whole centimetres: nothing z-fights at any zoom.
const Primitives = preload("res://presentation/kit/primitives.gd")
const Styles = preload("res://content/dressing/prop_styles.gd")
const Models = preload("res://presentation/kit/models.gd")
## The weights, modelled in Blender (tools/blender/models/pulley_weights.py).
const WEIGHTS := "res://assets/models/pulley_weights.glb"
const STYLES := ["lantern_hook", "theme_hanger", "little_roof"]
## The weight's centre: out from the post and over its foot (m).
const ROPE_X := 0.14
const REST_Y := 0.45
const ROPE_WIDTH := 0.022
## A lantern's glow while its crossing is laid.
const GLOW := 0.9
const GLOW_COLOR := Color("ffc66b")
const TIMBER := Color("8a6b4e")
const TIMBER_LIGHT := Color("b08a62")
const STONE := Color("a3906f")
const ROOF := Color("b5654a")
const ROPE := Color("d1b98c")
const LAMP := Color("ffd894")
const LAMP_OFF := Color("cdbf9a")
const PLASTER := Color("efe2c4")
const LEAF := Color("7fa36a")
const LEAF_DARK := Color("5f8a5a")
const PINK := Color("f2a7b0")
const BRASS := Color("e2b25e")
const IRON := Color("4d4a52")
const NAVY := Color("46607a")
const RED := Color("c8644c")
const SACK := Color("d9c08f")
## A hanger's rope coil: the spot it lies nearest to, beside the post's foot,
## off the crossing and toward the camera (post space x, z), its rings' radii
## and the rope's.
const COIL_AT := Vector2(-0.235, 0.15)
const COIL_RINGS := [0.07, 0.05, 0.03]
const COIL_ROPE := 0.015
## The coil keeps this far inside its floor's edges, clear of the parapets,
## copings and crossing walls that stand along them (m).
const COIL_EDGE := 0.10
## How far the coil may slide from COIL_AT to fit and still sit by its post (m).
const COIL_SLIDE := 0.2

## The weight, a held container its world moves (set its rest_y there).
var weight: Node3D
## The rope from the wheel down to the weight, stretched by set_laid().
var _rope: MeshInstance3D
## A lantern's glass, lit while laid; null for other weights.
var _glass: MeshInstance3D
## Where the rope leaves the wheel (post space) and meets the weight (its space).
var _rope_top := 1.0
var _hang := 0.1

## A pulley post in `pulley_style` on the spot `at` (parent space) under
## `parent`; an unknown style builds the first. `ground` holds the floors at
## its foot's height (post space x, z); what lies at the foot is laid only
## wholly on one of them.
static func build(pulley_style: String, at: Vector3, parent: Node3D, ground: Array[Rect2] = []) -> RefCounted:
	var piece: RefCounted = load("res://presentation/kit/pieces/pulley.gd").new()
	piece._make(pulley_style if pulley_style in STYLES else STYLES[0], at, parent, ground)
	return piece

## Where a hanger's coil lies (post space x, z): the spot nearest COIL_AT, at
## most COIL_SLIDE from it, where it stays COIL_EDGE inside one of the floors
## `ground` and clear of the post; Vector2.INF when none has room.
static func coil_spot(ground: Array[Rect2]) -> Vector2:
	var reach: float = COIL_RINGS[0] + COIL_ROPE
	var best := Vector2.INF
	for area: Rect2 in ground:
		var room := area.grow(-(reach + COIL_EDGE))
		if room.size.x < 0.0 or room.size.y < 0.0: continue
		var spot := COIL_AT.clamp(room.position, room.end)
		var slide := spot.distance_to(COIL_AT)
		if slide <= COIL_SLIDE and spot.length() >= reach + 0.08 and slide < best.distance_to(COIL_AT): best = spot
	return best

## The rope runs down to wherever the weight hangs now; a lantern glows only
## while its crossing is laid.
func set_laid(laid: bool) -> void:
	var low := weight.position.y + _hang
	_rope.scale.y = maxf(_rope_top - low, 0.01)
	_rope.position.y = (_rope_top + low) * 0.5
	if _glass != null: _glass.material_override = Primitives.shared_material(LAMP, 0.9, GLOW_COLOR, GLOW) if laid else Primitives.shared_material(LAMP_OFF)

## The rope and a lantern's glass change after the build; the weight is held
## by its world, so its other parts fold under it.
func moving_parts() -> Array[Node3D]:
	var parts: Array[Node3D] = [_rope]
	if _glass != null: parts.append(_glass)
	return parts

func anchor_lift() -> float:
	return _rope_top

func _make(pulley_style: String, at: Vector3, parent: Node3D, ground: Array[Rect2]) -> void:
	style = pulley_style
	_root("Pulley_" + pulley_style, at, parent)
	anchor = root
	weight = Node3D.new()
	weight.name = "Weight"
	weight.position = Vector3(ROPE_X, REST_Y, 0)
	root.add_child(weight)
	match pulley_style:
		"theme_hanger": _make_hanger(ground)
		"little_roof": _make_roof()
		_: _make_hook()
	match str(Styles.style("pulley", pulley_style).get("weight", "")):
		"anchor": _anchor()
		"sack": _sack()
		_: _lantern(LEAF_DARK)
	_rope = Parts.box(Vector3(ROPE_WIDTH, 1.0, ROPE_WIDTH), ROPE, Vector3(ROPE_X, 0, 0), root)
	set_laid(false)

# --- Posts (post space: its foot's centre at the origin) ---

## A timber crook on a stone foot, leaves climbing it, a wheel under its hook.
func _make_hook() -> void:
	var top := 1.12
	Parts.box(Vector3(0.176, 0.08, 0.176), STONE, Vector3(0, 0.035, 0), root)
	Parts.box(Vector3(0.094, top, 0.094), TIMBER, Vector3(0, top * 0.5 + 0.04, 0), root)
	Parts.box(Vector3(0.254, 0.06, 0.06), TIMBER, Vector3(0.083, top + 0.05, 0), root)
	_arc(Vector2(0.20, top + 0.11), 0.06, -PI * 0.5, PI * 0.9, 0.05, 0.055, TIMBER, 5)
	var heights := [0.25, 0.45, 0.65, 0.85]
	for k in range(heights.size()):
		Parts.ball(0.045, LEAF if k % 2 else LEAF_DARK, Vector3(0.05 * (-1.0 if k % 2 else 1.0), heights[k], 0.05), root)
	Parts.ball(0.03, PINK, Vector3(0.06, 0.55, 0.07), root)
	_wheel(Vector3(ROPE_X, top - 0.02, 0), 0.045)
	_rope_top = top - 0.02

## A white post with red bands, a curled arm and a rope coil beside its foot.
func _make_hanger(ground: Array[Rect2]) -> void:
	var top := 1.10
	var coil := coil_spot(ground)
	if coil.is_finite():
		for k in range(COIL_RINGS.size()):
			var ring := Parts.torus(COIL_RINGS[k], COIL_ROPE, ROPE.darkened(0.1 - 0.05 * k), Vector3(coil.x, 0.03 + 0.02 * k, coil.y), root, 20 - 4 * k, 6)
			ring.name = "Coil"
	Parts.box(Vector3(0.096, top, 0.096), PLASTER, Vector3(0, top * 0.5 - 0.005, 0), root)
	for y: float in [0.25, 0.75]: Parts.box(Vector3(0.122, 0.07, 0.122), RED, Vector3(0, y, 0), root)
	_arc(Vector2(0.07, top - 0.02), 0.08, 0.0, PI, 0.05, 0.05, PLASTER, 5)
	var cap := Parts.ball(0.06, NAVY, Vector3(0, top + 0.02, 0), root)
	cap.scale.y = 0.8
	_wheel(Vector3(ROPE_X, top, 0), 0.045)
	_rope_top = top

## A timber post on a stone foot under a little pitched roof with a plaster
## gable, its wheel under the eaves.
func _make_roof() -> void:
	var top := 1.10
	var shade := TIMBER_LIGHT.darkened(0.1)
	Parts.box(Vector3(0.216, 0.08, 0.216), STONE, Vector3(0, 0.035, 0), root)
	Parts.box(Vector3(0.104, top, 0.104), TIMBER_LIGHT, Vector3(0, top * 0.5 + 0.04, 0), root)
	Parts.box(Vector3(0.294, 0.06, 0.08), shade, Vector3(0.091, top + 0.06, 0), root)
	Parts.box(Vector3(0.06, 0.08, 0.06), shade, Vector3(0, top + 0.10, 0), root)
	# The gable: a plaster prism inside two roof boards meeting at a ridge.
	var eave := top + 0.10
	var rise := 0.22
	var half := 0.20
	var centre := 0.07
	Primitives.mesh_node(Primitives.shared_mesh("prism", half * 2.0 - 0.05, rise - 0.03, 0.28), Primitives.shared_material(PLASTER), Vector3(centre, eave + (rise - 0.03) * 0.5, 0), root)
	var slope := atan2(rise, half)
	var length := Vector2(half, rise).length() + 0.03
	for side: float in [-1.0, 1.0]:
		var normal := Vector2(side * rise, half).normalized()
		var middle := Vector2(centre + side * half * 0.5, eave + rise * 0.5) + normal * 0.015
		var board := Parts.box(Vector3(length, 0.03, 0.30), ROOF, Vector3(middle.x, middle.y, 0), root)
		board.rotation.z = -side * slope
	Parts.box(Vector3(0.035, 0.035, 0.32), ROOF.darkened(0.3), Vector3(centre, eave + rise + 0.02, 0), root)
	_wheel(Vector3(ROPE_X - 0.06, top - 0.02, 0), 0.06)
	_rope_top = top - 0.02

## A wheel turning on z, its iron hub through it.
func _wheel(at: Vector3, radius: float) -> void:
	var rim := Parts.disc(radius, 0.04, BRASS.darkened(0.15), at, root, -1.0, 16)
	rim.rotation.x = PI * 0.5
	var hub := Parts.disc(radius * 0.3, 0.06, IRON, at, root, -1.0, 8)
	hub.rotation.x = PI * 0.5

## A bent bar in the xy plane round `centre` (x, y) from angle `from` to `to`
## (radians, counter-clockwise from +x): `count` straight pieces `thick`
## across and `deep` along z, each a little long so the joints close.
func _arc(centre: Vector2, radius: float, from: float, to: float, thick: float, deep: float, color: Color, count: int, parent: Node3D = null) -> void:
	var holder := parent if parent != null else root
	var step := (to - from) / float(count)
	for index in range(count):
		var a := from + step * float(index)
		var b := a + step
		var p := centre + Vector2(cos(a), sin(a)) * radius
		var q := centre + Vector2(cos(b), sin(b)) * radius
		var piece := Parts.box(Vector3(p.distance_to(q) + thick * 0.5, thick, deep), color, Vector3((p.x + q.x) * 0.5, (p.y + q.y) * 0.5, 0), holder)
		piece.rotation.z = (q - p).angle()

# --- Weights (weight space: its centre at the origin) ---

## A lantern: a base, corner posts, a cone roof and a hanging ring, with its
## glass apart so it can glow while laid.
func _lantern(cap: Color) -> void:
	Models.still(WEIGHTS, "weight_lantern", {"cap": cap, "post": cap.darkened(0.2), "iron": IRON}, weight)
	_glass = Models.moving(WEIGHTS, "weight_lantern_glass", {"glass": LAMP_OFF}, weight)
	_hang = 0.15

## An anchor: a brass ring, a stock, a shank, curved arms and two flukes.
func _anchor() -> void:
	Models.still(WEIGHTS, "weight_anchor", {"brass": BRASS, "navy": NAVY}, weight)
	_hang = 0.17

## A flour sack: a soft round body, a neck tied with red, a knot and a patch.
func _sack() -> void:
	Models.still(WEIGHTS, "weight_sack", {"sack": SACK, "tie": RED, "patch": SACK.darkened(0.2)}, weight)
	_hang = 0.08
