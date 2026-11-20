extends Node3D
## World kit: soft contact shadows where things meet the ground (levers, pads,
## goals, lamps, keepsakes, dressing props, items set down). Phones draw no
## shadow pass and no screen-space occlusion, so without these a lever on a
## boardwalk looks pasted on.
##
## One look for everything (contact_shadow.gdshader, the pip's own shadow
## too): a flat quad a few millimetres over the ground, darkest over the
## footprint and fading out past its edge. A world draws all of its shadows in
## one MultiMesh, so they cost one draw call however many there are.
##
## Who gets one, with no per-level code:
## - every piece: kit/pieces/piece.gd `_root()` marks its root (a kit that is
##   ground itself, a crossing or a float, passes `shadow = false`);
## - every dressing prop: kit/props.gd `build()` asks prop() (PROP_NONE lists
##   the kinds that get none, and a prop set below its floor stands in water);
## - Home keepsakes, garden planters and relay nests mark their own roots.
## A marked root is a plain Node3D container. Its footprint is the union of
## the boxes of its meshes that reach down to its lowest point (a tree stands
## on its trunk, not its crown), each separate foot its own shadow (a goal's
## two posts). Parts the static fold keeps whole because they move (a lever's
## handle, a pad's plate, a bell) never count: kit/static_batch.gd start()
## measures every marked root under what it folds, before any leaf is folded
## away, and caches the feet on the root (FEET_META). A root measured later
## (a world that never folds) is measured on the layer's next refresh.
##
## The layer (one per world, island_world._ready) gathers the marked roots
## under its world whenever one comes or goes, shows or hides, or calls
## touch(); between refreshes it looks at a few roots a frame and follows any
## that moved (a deck rising with the water) every frame until it settles. An
## item lifted off its rest fades its shadow out; a carried or floating item
## sets_off() its own (the pip's shadow and the water's rings show those).
## Low graphics quality keeps pieces, keepsakes and items and drops the
## dressing's, a little lighter (services/graphics_policy.gd).
const SHADER = preload("res://presentation/kit/contact_shadow.gdshader")
const SessionRelease = preload("res://presentation/kit/session_release.gd")
const GraphicsPolicy = preload("res://services/graphics_policy.gd")
const NODE_NAME := "ContactShadows"
const GROUP := &"contact_shadow"
## On a marked root: its feet, [[centre Vector2, half Vector2, y, round]], in
## its own space; [] for none.
const FEET_META := &"contact_shadow_feet"
## On a marked root: no shadow for now (a carried or floating item).
const OFF_META := &"contact_shadow_off"
## The look, shared with the pip's shadow.
const TINT := Color(0.12, 0.23, 0.21)
## Metres over the ground (under the pip's shadow, SpiritVisual.SHADOW_TOP).
const LIFT := 0.006
## A mesh whose bottom is this close to the lowest point counts as a foot.
const BAND := 0.04
## A root whose lowest point is higher than this over its origin hangs (a
## bell, a sign): no shadow.
const GROUND_REACH := 0.08
## Feet closer than this merge into one shadow.
const MERGE := 0.04
## More separate feet than this (a fence's posts) make one shadow round them.
const MOST_FEET := 8
## How far a shadow fades out past its footprint: a share of its smaller
## half size, at least the first and at most the second (metres).
const FADE_SHARE := 0.7
const FADE_RANGE := Vector2(0.04, 0.15)
## A root lifted this far over where it rested has no shadow left.
const LIFT_FADE := 0.35
## Roots looked at per frame for moves, and frames a moved one stays watched.
const POLL_PER_FRAME := 12
const HOT_FRAMES := 30
## Dressing kinds (kit/props.gd) that get no shadow, with why.
const PROP_NONE := {
	"rug": "lies flat on the floor",
	"path": "lies flat on the floor",
	"bank": "is ground itself",
	"tuft": "a few millimetres tall",
	"shells": "a few millimetres tall",
	"ivy": "hangs on a wall",
	"shelf": "hangs on a wall",
	"frame": "hangs on a wall",
	"basket": "hangs on a wall",
	"light_pool": "a pool of light, no body",
	"waterfall": "water",
	"boat": "rides the water",
	"reeds": "stand in the water",
	"reed_bed": "stands in the water",
	"sunken_boat": "lies in the water",
	"stilt_hut": "stands in the water on stilts",
	"mill_wheel": "turns in the water",
}

static var _touches := 0
static var _material: ShaderMaterial
static var _singles: Dictionary = {}
static var _quads: Dictionary = {}

## Marks root for a contact shadow (its world's layer measures it).
static func mark(root: Node3D) -> void:
	if root is GeometryInstance3D:
		push_error("A contact shadow root is a plain container: %s" % root.name)
		return
	root.add_to_group(GROUP)

## Marks a dressing prop of `spec`, unless its kind gets none or it stands
## below its floor (in water or mud).
static func prop(root: Node3D, spec: Dictionary) -> void:
	if PROP_NONE.has(str(spec.get("kind", ""))) or bool(spec.get("wall", false)) or float(spec.get("y", 0)) < 0.0: return
	mark(root)

## Whether root has its shadow switched off (or its kind none).
static func set_off(root: Node3D, off: bool) -> void:
	if not is_instance_valid(root) or bool(root.get_meta(OFF_META, false)) == off: return
	if off: root.set_meta(OFF_META, true)
	else: root.remove_meta(OFF_META)
	touch()

## Asks every layer to gather again (something marked moved on purpose).
static func touch() -> void:
	_touches += 1

## Measures every marked root under `root` that has not been measured yet,
## leaving out what `kept` (instance ids of nodes the fold keeps whole) holds.
static func measure_under(root: Node, kept: Dictionary = {}) -> void:
	if not is_instance_valid(root) or not root.is_inside_tree(): return
	for found: Node in root.get_tree().get_nodes_in_group(GROUP):
		if (found == root or root.is_ancestor_of(found)) and not found.has_meta(FEET_META): feet(found as Node3D, kept)

## root's feet (see FEET_META), measured once.
static func feet(root: Node3D, kept: Dictionary = {}) -> Array:
	if root.has_meta(FEET_META): return root.get_meta(FEET_META)
	var boxes: Array[AABB] = []
	var rounds: Array[bool] = []
	_boxes(root, Transform3D.IDENTITY, root, kept, boxes, rounds)
	var result: Array = []
	if not boxes.is_empty():
		var lowest := INF
		for box: AABB in boxes: lowest = minf(lowest, box.position.y)
		if lowest <= GROUND_REACH:
			# A post sunk into the floor meets it at the root's own level.
			var ground := maxf(lowest, 0.0)
			var rects: Array[Rect2] = []
			var round: Array[bool] = []
			for index in range(boxes.size()):
				var box := boxes[index]
				if box.position.y > ground + BAND or box.end.y < ground: continue
				rects.append(Rect2(box.position.x, box.position.z, box.size.x, box.size.z))
				round.append(rounds[index])
			_merge(rects, round)
			if rects.size() > MOST_FEET:
				var whole := rects[0]
				for rect: Rect2 in rects: whole = whole.merge(rect)
				rects = [whole]
				round = [false]
			for index in range(rects.size()):
				var rect := rects[index]
				if rect.size.x < 0.005 or rect.size.y < 0.005: continue
				result.append([rect.get_center(), rect.size * 0.5, ground, 1.0 if round[index] else 0.35])
	root.set_meta(FEET_META, result)
	return result

## The boxes (in root's space) of the solid meshes under node, past any kept
## part or another marked root, and whether each is round.
static func _boxes(node: Node, to_root: Transform3D, root: Node3D, kept: Dictionary, boxes: Array[AABB], rounds: Array[bool]) -> void:
	for child: Node in node.get_children():
		if not child is Node3D or kept.has(child.get_instance_id()) or child.is_in_group(GROUP): continue
		var xform := to_root * (child as Node3D).transform
		if child is MeshInstance3D and _solid(child as MeshInstance3D):
			var mesh := (child as MeshInstance3D).mesh
			boxes.append(xform * mesh.get_aabb())
			rounds.append(mesh is CylinderMesh or mesh is SphereMesh or mesh is TorusMesh or mesh is CapsuleMesh)
		_boxes(child, xform, root, kept, boxes, rounds)

## A mesh that stands on the ground: opaque, not a glow or a pool of light.
static func _solid(mesh: MeshInstance3D) -> bool:
	if mesh.mesh == null or mesh.transparency > 0.0: return false
	var look := mesh.material_override
	if look == null: return true
	if not look is BaseMaterial3D: return false
	var base := look as BaseMaterial3D
	return base.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and not (base.emission_enabled and base.emission_energy_multiplier > 1.5)

## Merges rects that touch or nearly touch, until none do.
static func _merge(rects: Array[Rect2], round: Array[bool]) -> void:
	var merged := true
	while merged:
		merged = false
		for i in range(rects.size()):
			for j in range(i + 1, rects.size()):
				if not rects[i].grow(MERGE * 0.5).intersects(rects[j].grow(MERGE * 0.5)): continue
				var one := rects[i].merge(rects[j])
				# The bigger part decides how round they are.
				round[i] = round[i] if rects[i].get_area() >= rects[j].get_area() else round[j]
				rects[i] = one
				rects.remove_at(j)
				round.remove_at(j)
				merged = true
				break
			if merged: break

## The one shadow material, shared by every world and pip.
static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
		_material.set_shader_parameter("tint", Vector3(TINT.r, TINT.g, TINT.b))
		SessionRelease.on_exit(_release)
	return _material

## A single shadow's look in metres (a pip's): half sizes, fade, roundness;
## one material per shape, shared.
static func single_material(half: Vector2, fade: float, round: float) -> ShaderMaterial:
	var key := Vector4(half.x, half.y, fade, round)
	if not _singles.has(key):
		var look := ShaderMaterial.new()
		look.shader = SHADER
		look.set_shader_parameter("tint", Vector3(TINT.r, TINT.g, TINT.b))
		look.set_shader_parameter("from_instance", false)
		look.set_shader_parameter("shape", key)
		_singles[key] = look
		SessionRelease.on_exit(_release)
	return _singles[key]

## A flat quad `radius` metres from its middle to each side, shared.
static func pip_quad(radius: float) -> PlaneMesh:
	if not _quads.has(radius):
		var quad := PlaneMesh.new()
		quad.size = Vector2.ONE * radius * 2.0
		_quads[radius] = quad
		SessionRelease.on_exit(_release)
	return _quads[radius]

static func _unit_quad() -> PlaneMesh:
	return pip_quad(1.0)

static func _release() -> void:
	_material = null
	_singles.clear()
	_quads.clear()

## How far a footprint of `half` fades out past its edge.
static func fade_for(half: Vector2) -> float:
	return clampf(minf(half.x, half.y) * FADE_SHARE, FADE_RANGE.x, FADE_RANGE.y)

# --- The layer -----------------------------------------------------------------

var _draw: MultiMeshInstance3D
var _quality := GraphicsPolicy.DEFAULT_QUALITY
var _members := -1
var _touched := -1
var _dirty := true
## Per shadow (its instance index): [root, foot, root transform seen in the
## layer's space, the ground it rests on, what was drawn: {transform,
## strength, half}].
var _shown: Array = []
## Of those, the first this many are pieces', keepsakes' and items' (Low).
var _shown_pieces := 0
var _poll := 0
## Shadow index -> frames left watching it every frame.
var _hot: Dictionary = {}

func _init() -> void:
	name = NODE_NAME

func _ready() -> void:
	_draw = MultiMeshInstance3D.new()
	_draw.name = "Shadows"
	_draw.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_draw.material_override = material()
	var many := MultiMesh.new()
	many.transform_format = MultiMesh.TRANSFORM_3D
	many.use_custom_data = true
	many.use_colors = true
	many.mesh = _unit_quad()
	_draw.multimesh = many
	add_child(_draw)
	set_quality(_quality)

## Shows every shadow (Balanced, High) or the pieces' only (Low).
func set_quality(quality: String) -> void:
	_quality = GraphicsPolicy.normalize(quality)
	if _draw == null: return
	_draw.set_instance_shader_parameter("shadow_strength", GraphicsPolicy.contact_shadow_strength(_quality))
	_show_count()

## How many shadows the layer draws now.
func shown() -> int:
	return _draw.multimesh.visible_instance_count if _draw != null and _draw.multimesh.visible_instance_count >= 0 else _shown.size()

## Shadow `index` as drawn: {root, transform (in the layer's space), strength
## (1 resting, fading as it is lifted), half (its footprint's half size)}.
func shadow(index: int) -> Dictionary:
	return (_shown[index][4] as Dictionary).merged({"root": _shown[index][0]})

## The shadows drawn under root, by index.
func shadows_of(root: Node3D) -> Array[int]:
	var found: Array[int] = []
	for index in range(_shown.size()):
		if _shown[index][0] == root: found.append(index)
	return found

func _process(_delta: float) -> void:
	refresh()

## Gathers again when something marked came, went, showed, hid or was
## touched; otherwise follows whatever moved.
func refresh() -> void:
	if _draw == null or not is_inside_tree(): return
	var members := get_tree().get_node_count_in_group(GROUP)
	if _dirty or members != _members or _touches != _touched:
		_gather(members)
		return
	_follow()

func _on_member_shown() -> void:
	_dirty = true

func _gather(members: int) -> void:
	_dirty = false
	_members = members
	_touched = _touches
	_hot.clear()
	_poll = 0
	var world := get_parent()
	var entries: Array = []
	for found: Node in get_tree().get_nodes_in_group(GROUP):
		if not world.is_ancestor_of(found): continue
		var root := found as Node3D
		if not root.visibility_changed.is_connected(_on_member_shown): root.visibility_changed.connect(_on_member_shown)
		if not root.is_visible_in_tree() or root.has_meta(OFF_META): continue
		var dressing := root.has_meta("dressing_kind")
		for foot: Array in feet(root):
			entries.append([root, foot, dressing, (foot[1] as Vector2).x * (foot[1] as Vector2).y])
	# The pieces' first (Low keeps only those), then the biggest.
	entries.sort_custom(func(a: Array, b: Array) -> bool: return a[3] > b[3] if a[2] == b[2] else not a[2])
	var many := _draw.multimesh
	many.instance_count = 0
	many.instance_count = entries.size()
	_shown = []
	_shown_pieces = 0
	var to_layer := global_transform.affine_inverse()
	for index in range(entries.size()):
		var entry: Array = entries[index]
		var root: Node3D = entry[0]
		var seen := to_layer * root.global_transform
		var foot: Array = entry[1]
		# Where it rests now: its feet's ground in the layer's space.
		_shown.append([root, foot, seen, (seen * Vector3((foot[0] as Vector2).x, float(foot[2]), (foot[0] as Vector2).y)).y, {}])
		_place(index, seen)
		if not entry[2]: _shown_pieces += 1
	_show_count()

## Draws shadow `index` where its root stands now (`seen`, in the layer's
## space): flat, turned with the root, at its feet. Lifted off its rest it
## stays on the ground it left and fades; set down lower, it rests there.
func _place(index: int, seen: Transform3D) -> void:
	var shown_one: Array = _shown[index]
	shown_one[2] = seen
	var foot: Array = shown_one[1]
	var scale := Vector2(Vector2(seen.basis.x.x, seen.basis.x.z).length(), Vector2(seen.basis.z.x, seen.basis.z.z).length())
	var half: Vector2 = (foot[1] as Vector2) * scale
	var fade := fade_for(half)
	var across := Vector2(seen.basis.x.x, seen.basis.x.z)
	var turn := atan2(-across.y, across.x) if across.length_squared() > 0.000001 else 0.0
	var centre := seen * Vector3((foot[0] as Vector2).x, float(foot[2]), (foot[0] as Vector2).y)
	if centre.y < float(shown_one[3]): shown_one[3] = centre.y
	var ground: float = shown_one[3]
	var outer := half + Vector2.ONE * fade
	var placed := Transform3D(Basis(Vector3.UP, turn).scaled(Vector3(outer.x, 1.0, outer.y)), Vector3(centre.x, ground + LIFT, centre.z))
	var strength := clampf(1.0 - (centre.y - ground) / LIFT_FADE, 0.0, 1.0)
	shown_one[4] = {"transform": placed, "strength": strength, "half": half}
	var many := _draw.multimesh
	many.set_instance_transform(index, placed)
	many.set_instance_custom_data(index, Color(half.x, half.y, fade, float(foot[3])))
	many.set_instance_color(index, Color(1, 1, 1, strength))

## Looks at a few roots for a move, and every frame at those that just moved.
func _follow() -> void:
	if _shown.is_empty(): return
	var to_layer := global_transform.affine_inverse()
	for index: int in _hot.keys():
		if _moved(index, to_layer): _hot[index] = HOT_FRAMES
		else:
			_hot[index] -= 1
			if _hot[index] > 0: continue
			_hot.erase(index)
			# Settled higher up (a deck that rose): it rests there now.
			_shown[index][3] = INF
			_place(index, _shown[index][2])
	for step in range(mini(POLL_PER_FRAME, _shown.size())):
		_poll = (_poll + 1) % _shown.size()
		if not _hot.has(_poll) and _moved(_poll, to_layer): _hot[_poll] = HOT_FRAMES

func _moved(index: int, to_layer: Transform3D) -> bool:
	var root: Variant = _shown[index][0]
	# Gone, or taken out of the world (a stage rebuilt with as many marked
	# roots): gather again next frame.
	if not is_instance_valid(root) or not (root as Node3D).is_inside_tree():
		_dirty = true
		return false
	var now := to_layer * (root as Node3D).global_transform
	if now.is_equal_approx(_shown[index][2]): return false
	_place(index, now)
	return true

func _show_count() -> void:
	if _draw == null: return
	_draw.multimesh.visible_instance_count = -1 if GraphicsPolicy.dressing_contact_shadows(_quality) else _shown_pieces
