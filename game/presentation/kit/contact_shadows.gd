extends Node3D
## World kit: grounding, so things look set on the floor rather than pasted
## on it. Phones draw no shadow pass and no screen-space occlusion; this costs
## about one texture read where it shows.
##
## Two looks, one warm dark (they multiply the floor, so it keeps its colour):
## - What stands still is baked into its floor once a world is built: each
##   floor top has a ground (ground(), registered by the shared floor builders:
##   kit/surfaces.gd, island_world's shell and the worlds' own shores), and the
##   layer rasterizes the feet standing on it into one small texture
##   (ground_shade.gdshader): a soft footprint-shaped darkening where a model
##   meets the floor (the darkest of overlapping feet, never their sum), a
##   wider worn patch round each base on grass (browner, with flattened grass
##   and grit on Balanced and High), and the sun's soft shadow of the taller
##   scenery. One overlay per floor that has any, drawn only over the tiles
##   that hold some.
## - What moves (an item set down, a thing standing on no floor top) gets a
##   soft quad instead (contact_shadow.gdshader), all of them in one
##   MultiMesh; a pip draws its own quad in the same look.
##
## Who gets one, with no per-level code:
## - every piece: kit/pieces/piece.gd `_root()` marks its root (a kit that is
##   ground itself, a crossing or a float, passes `shadow = false`);
## - every dressing prop: kit/props.gd `build()` asks prop() (PROP_NONE lists
##   the kinds that get none, and a prop set below its floor stands in water);
## - Home keepsakes, garden planters, relay nests and the classic island
##   trees mark their own roots; a carried item marks its root `live`.
## A marked root is a plain Node3D container. Its feet are the bottoms of the
## meshes that reach down to its lowest point (a tree stands on its trunk, not
## its crown; a model by the outline of its lowest vertices), each foot its
## own shape, turned with its part. Parts the static fold keeps whole because
## they move (a lever's handle, a pad's plate, a bell) never count:
## kit/static_batch.gd start() measures every marked root under what it folds
## before any leaf is folded away (FEET_META); a root measured later (a world
## that never folds) is measured on the layer's next gather.
##
## The layer (one per world, island_world._ready) gathers the marked roots
## and grounds under its world whenever one comes or goes, shows or hides, or
## calls touch(), and bakes again only the floors whose feet changed, a few
## milliseconds a frame at most. Between gathers it looks at a few roots a
## frame: a still root that moved on its floor is baked where it settles; one
## that keeps moving becomes live. A live item lifted off its rest fades its
## shadow out; a carried or floating item sets_off() its own (the pip's
## shadow and the water's rings show those). Low keeps every shadow, a little
## lighter, without the grass detail (services/graphics_policy.gd).
const SHADER = preload("res://presentation/kit/contact_shadow.gdshader")
const SHADE_SHADER = preload("res://presentation/kit/ground_shade.gdshader")
const SessionRelease = preload("res://presentation/kit/session_release.gd")
const GraphicsPolicy = preload("res://services/graphics_policy.gd")
const Cutaway = preload("res://presentation/kit/cutaway.gd")
const NODE_NAME := "ContactShadows"
const GROUP := &"contact_shadow"
## Floor tops a still thing can be baked into (ground()).
const GROUND_GROUP := &"contact_ground"
## On a ground: its walkable rect in its own space (x, z) and whether it is
## grass that wears round a base.
const GROUND_RECT_META := &"contact_ground_rect"
const GROUND_WORN_META := &"contact_ground_worn"
## On a marked root: its feet, [[centre Vector2, half Vector2, y, round,
## turn]] in its own space; [] for none.
const FEET_META := &"contact_shadow_feet"
## On a marked root: what casts the sun's shadow, [[centre Vector2, half
## Vector2, low, high]] in its own space.
const CASTERS_META := &"contact_shadow_casters"
## On a marked root: no shadow for now (a carried or floating item).
const OFF_META := &"contact_shadow_off"
## On a marked root: it moves, so it gets a quad instead of being baked.
const LIVE_META := &"contact_shadow_live"
## On a still root: how often it moved on its floor and settled.
const MOVES_META := &"contact_shadow_moves"
## The look, shared with the pip's shadow and the baked floors.
const TINT := Color(0.50, 0.47, 0.40)
## Metres over the walking height where every shadow lies: a pip's shadow
## (SpiritVisual.SHADOW_TOP), the live quads and the floors' overlays; the
## dressing lint keeps every face clear of it where a pip stands.
const SHADE_TOP := 0.02425
## A mesh whose bottom is this close to the lowest point counts as a foot.
const BAND := 0.04
## A root whose lowest point is higher than this over its origin hangs (a
## bell, a sign): no shadow.
const GROUND_REACH := 0.08
## How far a shadow fades out past its footprint: a share of its smaller
## half size, at least the first and at most the second (metres).
const FADE_SHARE := 0.55
const FADE_RANGE := Vector2(0.05, 0.14)
## How far grass wears round a base: a share of its smaller half size plus
## the first, at most the second (metres).
const WORN_SHARE := 0.6
const WORN_RANGE := Vector2(0.10, 0.26)
## Only parts at least this tall cast the sun's shadow, the CASTS_MOST
## biggest of a root; the shadow reaches at most SUN_REACH metres along the
## floor per metre of height and softens with height.
const CAST_HEIGHT := 0.22
const CASTS_MOST := 6
const SUN_REACH := 0.8
const CAST_SOFT := Vector2(0.06, 0.16)
## A baked floor's texel and the tiles its overlay is drawn in (metres).
const TEXEL := 0.05
const TILE := 0.5
## Milliseconds of baking a frame, once a frame has started one.
const BAKE_BUDGET_USEC := 4000
## A root lifted this far over where it rested has no shadow left.
const LIFT_FADE := 0.35
## Roots looked at per frame for moves, frames a moved one stays watched,
## and moves a still root may make before it is drawn live.
const POLL_PER_FRAME := 12
const HOT_FRAMES := 30
const STILL_MOVES := 2
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
## A model mesh's bottom outline, by instance id: [Rect2 (x, z), round].
static var _bottoms: Dictionary = {}

## Marks root for a contact shadow (its world's layer measures it). A `live`
## root moves (a carried item): it gets a quad, never a bake.
static func mark(root: Node3D, live: bool = false) -> void:
	if root is GeometryInstance3D:
		push_error("A contact shadow root is a plain container: %s" % root.name)
		return
	if live: root.set_meta(LIVE_META, true)
	root.add_to_group(GROUP)

## Marks a dressing prop of `spec`, unless its kind gets none or it stands
## below its floor (in water or mud).
static func prop(root: Node3D, spec: Dictionary) -> void:
	if PROP_NONE.has(str(spec.get("kind", ""))) or bool(spec.get("wall", false)) or float(spec.get("y", 0)) < 0.0: return
	mark(root)

## Registers a floor top under `parent`: `rect` (x, z in parent space) walked
## at height `top`; `worn` for grass, which wears round a base. A shared floor
## builder calls it once per floor it lays; the layer bakes what stands on it.
static func ground(parent: Node3D, rect: Rect2, top: float, worn: bool) -> Node3D:
	var node := Node3D.new()
	node.name = "Ground"
	node.position = Vector3(0, top, 0)
	node.set_meta(GROUND_RECT_META, rect)
	node.set_meta(GROUND_WORN_META, worn)
	node.add_to_group(GROUND_GROUP)
	parent.add_child(node)
	return node

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

## root's feet (see FEET_META), measured once with its casters.
static func feet(root: Node3D, kept: Dictionary = {}) -> Array:
	if root.has_meta(FEET_META): return root.get_meta(FEET_META)
	var parts: Array = []
	_parts(root, Transform3D.IDENTITY, kept, parts)
	var result: Array = []
	var casters: Array = []
	if not parts.is_empty():
		var lowest := INF
		for part: Array in parts: lowest = minf(lowest, (part[0] as AABB).position.y)
		if lowest <= GROUND_REACH:
			# A post sunk into the floor meets it at the root's own level.
			var ground_y := maxf(lowest, 0.0)
			for part: Array in parts:
				var box: AABB = part[0]
				if box.end.y - ground_y >= CAST_HEIGHT: casters.append([Vector2(box.get_center().x, box.get_center().z), Vector2(box.size.x, box.size.z) * 0.5, maxf(box.position.y, ground_y), box.end.y])
				if box.position.y > ground_y + BAND or box.end.y < ground_y: continue
				var foot := _foot(part[1], part[2])
				if (foot[1] as Vector2).x < 0.0025 or (foot[1] as Vector2).y < 0.0025: continue
				result.append([foot[0], foot[1], ground_y, foot[2], foot[3]])
	casters.sort_custom(func(a: Array, b: Array) -> bool: return (a[1] as Vector2).x * (a[1] as Vector2).y > (b[1] as Vector2).x * (b[1] as Vector2).y)
	root.set_meta(CASTERS_META, casters.slice(0, CASTS_MOST))
	root.set_meta(FEET_META, result)
	return result

## The solid meshes under node, past any kept part or another marked root,
## each as [box in root's space, mesh, transform in root's space].
static func _parts(node: Node, to_root: Transform3D, kept: Dictionary, parts: Array) -> void:
	for child: Node in node.get_children():
		if not child is Node3D or kept.has(child.get_instance_id()) or child.is_in_group(GROUP) or child.is_in_group(GROUND_GROUP): continue
		var xform := to_root * (child as Node3D).transform
		if child is MeshInstance3D and _solid(child as MeshInstance3D):
			var mesh := (child as MeshInstance3D).mesh
			parts.append([xform * mesh.get_aabb(), mesh, xform])
		_parts(child, xform, kept, parts)

## A mesh's foot in root space: [centre, half, round, turn]. Its bottom's
## outline (bottom()) turned with it; a tilted part keeps its box's.
static func _foot(mesh: Mesh, xform: Transform3D) -> Array:
	var bottom := bottom(mesh)
	var rect: Rect2 = bottom[0]
	var across := Vector3(xform.basis.x.x, 0, xform.basis.x.z)
	var deep := Vector3(xform.basis.z.x, 0, xform.basis.z.z)
	var upright := absf(xform.basis.x.y) < 0.02 and absf(xform.basis.z.y) < 0.02
	if not upright:
		var box := xform * mesh.get_aabb()
		return [Vector2(box.get_center().x, box.get_center().z), Vector2(box.size.x, box.size.z) * 0.5, minf(float(bottom[1]), 0.5), 0.0]
	var centre := xform * Vector3(rect.get_center().x, mesh.get_aabb().position.y, rect.get_center().y)
	return [Vector2(centre.x, centre.z), rect.size * 0.5 * Vector2(across.length(), deep.length()), bottom[1], atan2(across.z, across.x)]

## A mesh's bottom outline in its own space: [Rect2 (x, z), round 0..1].
## Primitives by their shape; a model by its vertices near its lowest point
## (round when they keep off the corners of their box), read once.
static func bottom(mesh: Mesh) -> Array:
	var box := mesh.get_aabb()
	var whole := Rect2(box.position.x, box.position.z, box.size.x, box.size.z)
	if mesh is CylinderMesh:
		var radius := maxf((mesh as CylinderMesh).bottom_radius, 0.01)
		return [Rect2(-radius, -radius, radius * 2.0, radius * 2.0), 1.0]
	if mesh is SphereMesh or mesh is CapsuleMesh: return [whole.grow_individual(-whole.size.x * 0.2, -whole.size.y * 0.2, -whole.size.x * 0.2, -whole.size.y * 0.2), 1.0]
	if mesh is TorusMesh: return [whole, 1.0]
	if mesh is PrimitiveMesh: return [whole, 0.3]
	var id := mesh.get_instance_id()
	if _bottoms.has(id): return _bottoms[id]
	if _bottoms.is_empty(): SessionRelease.on_exit(_release)
	var band := box.position.y + maxf(box.size.y * 0.05, 0.01)
	var low: Array[Vector2] = []
	for surface in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surface)
		for point: Vector3 in arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array:
			if point.y <= band: low.append(Vector2(point.x, point.z))
	var found := [whole, 0.3]
	if low.size() >= 3:
		var rect := Rect2(low[0], Vector2.ZERO)
		for point: Vector2 in low: rect = rect.expand(point)
		var half := rect.size * 0.5
		# A square's lowest vertices reach its corners; a round base's keep
		# about 0.71 of the way off them.
		var cornered := 0.0
		if half.x > 0.001 and half.y > 0.001:
			for point: Vector2 in low:
				var off := (point - rect.get_center()).abs() / half
				cornered = maxf(cornered, minf(off.x, off.y))
		found = [rect, clampf((1.0 - cornered) / 0.29, 0.0, 1.0)]
	_bottoms[id] = found
	return found

## A mesh that stands on the ground: opaque, not a glow or a pool of light.
static func _solid(mesh: MeshInstance3D) -> bool:
	if mesh.mesh == null or mesh.transparency > 0.0: return false
	var look := mesh.material_override
	if look == null: return true
	if not look is BaseMaterial3D: return false
	var base := look as BaseMaterial3D
	return base.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and not (base.emission_enabled and base.emission_energy_multiplier > 1.5)

## The one live shadow material, shared by every world.
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
	_bottoms.clear()

## How far a footprint of `half` fades out past its edge.
static func fade_for(half: Vector2) -> float:
	return clampf(minf(half.x, half.y) * FADE_SHARE, FADE_RANGE.x, FADE_RANGE.y)

## How far grass wears round a footprint of `half`.
static func worn_for(half: Vector2) -> float:
	return minf(WORN_RANGE.x + minf(half.x, half.y) * WORN_SHARE, WORN_RANGE.y)

# --- Baking a floor -------------------------------------------------------------

## Bakes `feet` ([[centre, half, round, turn]] in the ground's space) and
## `casts` ([[centre, along (unit), half, soft]]) into an RGB image over
## `rect` (see ground_shade.gdshader). Returns {image, tiles: [Rect2]} or {}
## when nothing shows.
static func bake(rect: Rect2, feet_list: Array, casts: Array, worn: bool) -> Dictionary:
	var width := maxi(1, ceili(rect.size.x / TEXEL))
	var height := maxi(1, ceili(rect.size.y / TEXEL))
	var data := PackedByteArray()
	data.resize(width * height * 3)
	var per_tile := maxi(1, roundi(TILE / TEXEL))
	var tiles_across := ceili(float(width) / per_tile)
	var marked: Dictionary = {}
	for foot: Array in feet_list:
		var half: Vector2 = foot[1]
		var turn: float = foot[3]
		var fade := fade_for(half)
		var reach := worn_for(half) if worn else fade
		var box := _stamp(data, width, height, rect, foot[0], Vector2(cos(turn), sin(turn)), half, float(foot[2]) * minf(half.x, half.y), fade, reach, 0 if worn else -1)
		_mark_tiles(box, per_tile, tiles_across, marked)
	for cast: Array in casts:
		_mark_tiles(_stamp(data, width, height, rect, cast[0], cast[1], cast[2], minf((cast[2] as Vector2).x, (cast[2] as Vector2).y), cast[3], cast[3], -2), per_tile, tiles_across, marked)
	if marked.is_empty(): return {}
	var tiles: Array[Rect2] = []
	for key: int in marked:
		var tile := Rect2(rect.position + Vector2(key % tiles_across, key / tiles_across) * per_tile * TEXEL, Vector2.ONE * per_tile * TEXEL)
		tiles.append(tile.intersection(rect))
	tiles.sort_custom(func(a: Rect2, b: Rect2) -> bool: return a.position.y < b.position.y or (a.position.y == b.position.y and a.position.x < b.position.x))
	return {"image": Image.create_from_data(width, height, false, Image.FORMAT_RGB8, data), "tiles": tiles}

## Stamps one soft rounded box into data, keeping the darker of what is there
## and what it adds: centre, its across axis (unit), half size, corner radius,
## how far its own channel fades out past it and how far the worn channel
## does. `worn`: 0 also writes the worn channel, -1 only the contact channel,
## -2 the sun's (b) channel alone. Returns the texel box it touched (a
## negative size when it lies off the floor).
static func _stamp(data: PackedByteArray, width: int, height: int, rect: Rect2, centre: Vector2, across: Vector2, half: Vector2, corner: float, fade: float, reach: float, worn: int) -> Rect2i:
	var deep := Vector2(-across.y, across.x)
	var outer := half + Vector2.ONE * maxf(fade, reach)
	var spread := Vector2(absf(across.x) * outer.x + absf(deep.x) * outer.y, absf(across.y) * outer.x + absf(deep.y) * outer.y)
	var from := Vector2i(floori((centre.x - spread.x - rect.position.x) / TEXEL), floori((centre.y - spread.y - rect.position.y) / TEXEL))
	var to := Vector2i(ceili((centre.x + spread.x - rect.position.x) / TEXEL), ceili((centre.y + spread.y - rect.position.y) / TEXEL))
	if to.x < 0 or to.y < 0 or from.x >= width or from.y >= height: return Rect2i(0, 0, -1, -1)
	from = from.clamp(Vector2i.ZERO, Vector2i(width - 1, height - 1))
	to = to.clamp(Vector2i.ZERO, Vector2i(width - 1, height - 1))
	corner = minf(corner, minf(half.x, half.y))
	var inner := (half - Vector2.ONE * corner).max(Vector2.ZERO)
	var channel := 2 if worn == -2 else 0
	for j in range(from.y, to.y + 1):
		var z := rect.position.y + (j + 0.5) * TEXEL - centre.y
		var row := j * width
		for i in range(from.x, to.x + 1):
			var x := rect.position.x + (i + 0.5) * TEXEL - centre.x
			var u := absf(x * across.x + z * across.y) - inner.x
			var v := absf(x * deep.x + z * deep.y) - inner.y
			var outside := Vector2(maxf(u, 0.0), maxf(v, 0.0)).length() + minf(maxf(u, v), 0.0) - corner
			if outside >= reach and outside >= fade: continue
			var at := (row + i) * 3
			var shade := clampf(1.0 - outside / fade, 0.0, 1.0)
			if shade > 0.0:
				var level := int(shade * shade * (3.0 - 2.0 * shade) * 255.0)
				if level > data[at + channel]: data[at + channel] = level
			if worn == 0:
				var wear := clampf(1.0 - outside / reach, 0.0, 1.0)
				var level := int(wear * wear * (3.0 - 2.0 * wear) * 255.0)
				if level > data[at + 1]: data[at + 1] = level
	return Rect2i(from, to - from)

static func _mark_tiles(box: Rect2i, per_tile: int, across: int, marked: Dictionary) -> void:
	if box.size.x < 0: return
	for tz in range(box.position.y / per_tile, box.end.y / per_tile + 1):
		for tx in range(box.position.x / per_tile, box.end.x / per_tile + 1):
			if tx < across: marked[tz * across + tx] = true

## The flat overlay over a baked floor's `tiles` (in the ground's space,
## SHADE_TOP over it), its UVs over `rect`.
static func overlay_mesh(rect: Rect2, tiles: Array[Rect2]) -> ArrayMesh:
	var points := PackedVector3Array()
	var uvs := PackedVector2Array()
	for tile: Rect2 in tiles:
		var corners := [tile.position, Vector2(tile.end.x, tile.position.y), tile.end, Vector2(tile.position.x, tile.end.y)]
		for index: int in [0, 1, 2, 0, 2, 3]:
			var at: Vector2 = corners[index]
			points.append(Vector3(at.x, SHADE_TOP, at.y))
			uvs.append((at - rect.position) / (Vector2(ceili(rect.size.x / TEXEL), ceili(rect.size.y / TEXEL)) * TEXEL))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

# --- The layer -----------------------------------------------------------------

## Microseconds the last bake of this world took, all floors (for the probe).
var bake_usec := 0
var _draw: MultiMeshInstance3D
var _quality := GraphicsPolicy.DEFAULT_QUALITY
var _members := -1
var _grounds_seen := -1
var _touched := -1
var _dirty := true
## Per live shadow (its instance index): [root, foot, root transform seen in
## the layer's space, the ground it rests on, what was drawn: {transform,
## strength, half}].
var _shown: Array = []
## Per still root baked: [root, its ground, its transform in the ground's
## space last seen].
var _still: Array = []
## Per ground node: {signature, overlay (MeshInstance3D or null)}.
var _baked: Dictionary = {}
## Grounds waiting to bake: ground -> [feet, casts].
var _to_bake: Dictionary = {}
var _poll := 0
## Live shadow index -> frames left watching it every frame.
var _hot: Dictionary = {}
## Still index -> frames left watching it.
var _hot_still: Dictionary = {}

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

## Every shadow on every quality; Low a little lighter, without grass detail
## or the sun's shadows (baked again when that changes).
func set_quality(quality: String) -> void:
	var casts := GraphicsPolicy.cast_shadows(_quality)
	_quality = GraphicsPolicy.normalize(quality)
	if casts != GraphicsPolicy.cast_shadows(_quality):
		for ground: Variant in _baked: _baked[ground].signature = 0
		_dirty = true
	if _draw == null: return
	_draw.set_instance_shader_parameter("shadow_strength", GraphicsPolicy.contact_shadow_strength(_quality))
	for ground: Variant in _baked:
		var overlay: Variant = _baked[ground].overlay
		if is_instance_valid(overlay): _shade_quality((overlay as MeshInstance3D).material_override as ShaderMaterial)

func _shade_quality(look: ShaderMaterial) -> void:
	look.set_shader_parameter("detail", GraphicsPolicy.ground_detail(_quality))
	look.set_shader_parameter("contact_strength", 0.62 * GraphicsPolicy.contact_shadow_strength(_quality) / GraphicsPolicy.contact_shadow_strength("balanced"))

## How many live shadows the layer draws now.
func shown() -> int:
	return _shown.size()

## Live shadow `index` as drawn: {root, transform (in the layer's space),
## strength (1 resting, fading as it is lifted), half (its footprint's half
## size)}.
func shadow(index: int) -> Dictionary:
	return (_shown[index][4] as Dictionary).merged({"root": _shown[index][0]})

## The live shadows drawn under root, by index.
func shadows_of(root: Node3D) -> Array[int]:
	var found: Array[int] = []
	for index in range(_shown.size()):
		if _shown[index][0] == root: found.append(index)
	return found

## The roots baked into a floor, each with its ground: [[root, ground]].
func baked_roots() -> Array:
	var found: Array = []
	for still: Array in _still: found.append([still[0], still[1]])
	return found

## The floors drawn with an overlay now, each {ground, overlay, image}.
func overlays() -> Array:
	var found: Array = []
	for ground: Variant in _baked:
		if is_instance_valid(ground) and is_instance_valid(_baked[ground].overlay): found.append({"ground": ground, "overlay": _baked[ground].overlay, "image": _baked[ground].image})
	return found

## Whether every floor waiting to bake has baked.
func settled() -> bool:
	return not _dirty and _to_bake.is_empty()

func _process(_delta: float) -> void:
	refresh()

## Gathers again when something marked came, went, showed, hid or was
## touched, then bakes what changed; otherwise follows whatever moved.
func refresh() -> void:
	if _draw == null or not is_inside_tree(): return
	var members := get_tree().get_node_count_in_group(GROUP)
	var grounds := get_tree().get_node_count_in_group(GROUND_GROUP)
	if _dirty or members != _members or grounds != _grounds_seen or _touches != _touched:
		_gather(members, grounds)
	else: _follow()
	if not _to_bake.is_empty(): _bake_some()

func _on_member_shown() -> void:
	_dirty = true

func _gather(members: int, grounds_count: int) -> void:
	_dirty = false
	_members = members
	_grounds_seen = grounds_count
	_touched = _touches
	_hot.clear()
	_hot_still.clear()
	_poll = 0
	var world := get_parent()
	var grounds: Array[Node3D] = []
	for found: Node in get_tree().get_nodes_in_group(GROUND_GROUP):
		if world.is_ancestor_of(found):
			var ground := found as Node3D
			if not ground.visibility_changed.is_connected(_on_member_shown): ground.visibility_changed.connect(_on_member_shown)
			if ground.is_visible_in_tree(): grounds.append(ground)
	var on_ground: Dictionary = {}
	for ground: Node3D in grounds: on_ground[ground] = [[], [], []]
	var live: Array = []
	var still: Array = []
	var sun := _sun_offset()
	for found: Node in get_tree().get_nodes_in_group(GROUP):
		if not world.is_ancestor_of(found): continue
		var root := found as Node3D
		if not root.visibility_changed.is_connected(_on_member_shown): root.visibility_changed.connect(_on_member_shown)
		if not root.is_visible_in_tree() or root.has_meta(OFF_META): continue
		var its_feet := feet(root)
		if root.has_meta(LIVE_META):
			for foot: Array in its_feet: live.append([root, foot, (foot[1] as Vector2).x * (foot[1] as Vector2).y])
			continue
		var stood: Node3D = null
		for foot: Array in its_feet:
			var ground := _ground_for(root, foot, grounds)
			if ground == null:
				live.append([root, foot, (foot[1] as Vector2).x * (foot[1] as Vector2).y])
				continue
			var to_ground := ground.global_transform.affine_inverse() * root.global_transform
			(on_ground[ground][0] as Array).append(_ground_foot(foot, to_ground))
			(on_ground[ground][2] as Array).append([root.get_instance_id(), to_ground, foot])
			if stood == null: stood = ground
		if stood == null: continue
		var to_stood := stood.global_transform.affine_inverse() * root.global_transform
		for caster: Array in root.get_meta(CASTERS_META, []):
			var cast := _cast(caster, to_stood, (stood.global_transform.basis.inverse() * sun))
			if not cast.is_empty(): (on_ground[stood][1] as Array).append(cast)
		still.append([root, stood, to_stood])
	_still = still
	# Bake only the floors whose feet changed; forget floors that went.
	for ground: Variant in _baked.keys():
		if not on_ground.has(ground):
			if is_instance_valid(_baked[ground].overlay): (_baked[ground].overlay as Node).queue_free()
			_baked.erase(ground)
	_to_bake.clear()
	for ground: Node3D in on_ground:
		var entry: Array = on_ground[ground]
		var signature := hash([entry[2], entry[1], ground.get_meta(GROUND_RECT_META), ground.get_meta(GROUND_WORN_META)])
		if _baked.has(ground) and int(_baked[ground].signature) == signature: continue
		_to_bake[ground] = [entry[0], entry[1], signature]
	_place_live(live)

## The floor top a foot of root stands on: the one whose rect holds its
## centre at its height, the nearest under it; null for none.
func _ground_for(root: Node3D, foot: Array, grounds: Array[Node3D]) -> Node3D:
	var at := root.global_transform * Vector3((foot[0] as Vector2).x, float(foot[2]), (foot[0] as Vector2).y)
	var best: Node3D = null
	var best_gap := INF
	for ground: Node3D in grounds:
		var local := ground.global_transform.affine_inverse() * at
		var rect: Rect2 = ground.get_meta(GROUND_RECT_META)
		if local.y < -0.06 or local.y > 0.12 or not rect.grow(0.02).has_point(Vector2(local.x, local.z)): continue
		if absf(local.y) < best_gap:
			best_gap = absf(local.y)
			best = ground
	return best

## A foot of a root in its ground's space: [centre, half, round, turn].
static func _ground_foot(foot: Array, to_ground: Transform3D) -> Array:
	var turn: float = foot[4]
	var centre := to_ground * Vector3((foot[0] as Vector2).x, float(foot[2]), (foot[0] as Vector2).y)
	var across := to_ground.basis * Vector3(cos(turn), 0, sin(turn))
	var deep := to_ground.basis * Vector3(-sin(turn), 0, cos(turn))
	var flat_across := Vector2(across.x, across.z)
	var half := (foot[1] as Vector2) * Vector2(flat_across.length(), Vector2(deep.x, deep.z).length())
	return [Vector2(centre.x, centre.z), half, foot[3], atan2(flat_across.y, flat_across.x)]

## A caster's soft shadow on its ground, cast along `sun` (the floor offset
## per metre of height, in the ground's space): [centre, along, half, soft].
static func _cast(caster: Array, to_ground: Transform3D, sun: Vector3) -> Array:
	var offset := Vector2(sun.x, sun.z)
	if offset.length() < 0.02: return []
	var low := to_ground * Vector3((caster[0] as Vector2).x, float(caster[2]), (caster[0] as Vector2).y)
	var high := to_ground * Vector3((caster[0] as Vector2).x, float(caster[3]), (caster[0] as Vector2).y)
	var ground_y := (to_ground * Vector3((caster[0] as Vector2).x, 0, (caster[0] as Vector2).y)).y
	var near := Vector2(low.x, low.z) + offset * (low.y - ground_y)
	var far := Vector2(high.x, high.z) + offset * (high.y - ground_y)
	var along := (far - near).normalized() if far.distance_to(near) > 0.001 else offset.normalized()
	var size := (caster[1] as Vector2) * Vector2(to_ground.basis.x.length(), to_ground.basis.z.length())
	var width := maxf(size.x, size.y) * 0.8
	var soft := lerpf(CAST_SOFT.x, CAST_SOFT.y, clampf(high.y - ground_y, 0.0, 2.0) * 0.5)
	return [(near + far) * 0.5, along, Vector2(near.distance_to(far) * 0.5 + width * 0.5, width), soft]

## How far along the floor a point's shadow falls per metre of height, in
## world space (0 with no sun).
func _sun_offset() -> Vector3:
	var sun: Variant = get_parent().get("sun")
	if not sun is DirectionalLight3D or not is_instance_valid(sun): return Vector3.ZERO
	var ray := -(sun as DirectionalLight3D).global_transform.basis.z.normalized()
	if ray.y > -0.1: return Vector3.ZERO
	var offset := Vector3(ray.x, 0, ray.z) / -ray.y
	return offset.limit_length(SUN_REACH)

## Bakes waiting floors, at most BAKE_BUDGET_USEC a frame once one has begun.
func _bake_some() -> void:
	var started := Time.get_ticks_usec()
	for ground: Variant in _to_bake.keys():
		if Time.get_ticks_usec() - started > BAKE_BUDGET_USEC: return
		var job: Array = _to_bake[ground]
		_to_bake.erase(ground)
		if not is_instance_valid(ground): continue
		_bake_ground(ground as Node3D, job[0], job[1], int(job[2]))
	bake_usec += Time.get_ticks_usec() - started

func _bake_ground(ground: Node3D, feet_list: Array, casts: Array, signature: int) -> void:
	var rect: Rect2 = ground.get_meta(GROUND_RECT_META)
	var baked := bake(rect, feet_list, casts if GraphicsPolicy.cast_shadows(_quality) else [], bool(ground.get_meta(GROUND_WORN_META)))
	var entry: Dictionary = _baked.get(ground, {"overlay": null, "image": null})
	entry.signature = signature
	_baked[ground] = entry
	if baked.is_empty():
		if is_instance_valid(entry.overlay): (entry.overlay as Node).queue_free()
		entry.overlay = null
		entry.image = null
		return
	var overlay: MeshInstance3D = entry.overlay if is_instance_valid(entry.overlay) else null
	if overlay == null:
		overlay = MeshInstance3D.new()
		overlay.name = "Shade"
		overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		overlay.set_meta(Cutaway.HIDE, true)
		var look := ShaderMaterial.new()
		look.shader = SHADE_SHADER
		look.set_shader_parameter("dark_tint", Vector3(TINT.r, TINT.g, TINT.b))
		overlay.material_override = look
		_shade_quality(look)
		ground.add_child(overlay)
		entry.overlay = overlay
	overlay.mesh = overlay_mesh(rect, baked.tiles)
	(overlay.material_override as ShaderMaterial).set_shader_parameter("shade", ImageTexture.create_from_image(baked.image))
	entry.image = baked.image

## Draws the live shadows: the biggest first.
func _place_live(entries: Array) -> void:
	entries.sort_custom(func(a: Array, b: Array) -> bool: return a[2] > b[2])
	var many := _draw.multimesh
	many.instance_count = 0
	many.instance_count = entries.size()
	_shown = []
	var to_layer := global_transform.affine_inverse()
	for index in range(entries.size()):
		var entry: Array = entries[index]
		var root: Node3D = entry[0]
		var seen := to_layer * root.global_transform
		var foot: Array = entry[1]
		# Where it rests now: its feet's ground in the layer's space.
		_shown.append([root, foot, seen, (seen * Vector3((foot[0] as Vector2).x, float(foot[2]), (foot[0] as Vector2).y)).y, {}])
		_place(index, seen)

## Draws live shadow `index` where its root stands now (`seen`, in the
## layer's space): flat, turned with its foot, at its feet. Lifted off its
## rest it stays on the ground it left and fades; set down lower, it rests
## there.
func _place(index: int, seen: Transform3D) -> void:
	var shown_one: Array = _shown[index]
	shown_one[2] = seen
	var foot: Array = shown_one[1]
	var ground_foot := _ground_foot(foot, seen)
	var half: Vector2 = ground_foot[1]
	var fade := fade_for(half)
	var centre := seen * Vector3((foot[0] as Vector2).x, float(foot[2]), (foot[0] as Vector2).y)
	if centre.y < float(shown_one[3]): shown_one[3] = centre.y
	var ground: float = shown_one[3]
	var outer := half + Vector2.ONE * fade
	var placed := Transform3D(Basis(Vector3.UP, -float(ground_foot[3])) * Basis.from_scale(Vector3(outer.x, 1.0, outer.y)), Vector3(centre.x, ground + SHADE_TOP, centre.z))
	var strength := clampf(1.0 - (centre.y - ground) / LIFT_FADE, 0.0, 1.0)
	shown_one[4] = {"transform": placed, "strength": strength, "half": half}
	var many := _draw.multimesh
	many.set_instance_transform(index, placed)
	many.set_instance_custom_data(index, Color(half.x, half.y, fade, float(foot[3])))
	many.set_instance_color(index, Color(1, 1, 1, strength))

## Looks at a few roots for a move, and every frame at those that just moved:
## a live one is followed; a still one is baked again where it settles, and
## drawn live once it has moved STILL_MOVES times.
func _follow() -> void:
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
	for index: int in _hot_still.keys():
		if _still_moved(index): _hot_still[index] = HOT_FRAMES
		else:
			_hot_still[index] -= 1
			if _hot_still[index] > 0: continue
			_hot_still.erase(index)
			var root: Node3D = _still[index][0]
			root.set_meta(MOVES_META, int(root.get_meta(MOVES_META, 0)) + 1)
			if int(root.get_meta(MOVES_META)) >= STILL_MOVES: root.set_meta(LIVE_META, true)
			_dirty = true
	var total := _shown.size() + _still.size()
	for step in range(mini(POLL_PER_FRAME, total)):
		_poll = (_poll + 1) % total
		if _poll < _shown.size():
			if not _hot.has(_poll) and _moved(_poll, to_layer): _hot[_poll] = HOT_FRAMES
		else:
			var index := _poll - _shown.size()
			if not _hot_still.has(index) and _still_moved(index): _hot_still[index] = HOT_FRAMES

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

## Whether still root `index` moved on its floor since it was last seen.
func _still_moved(index: int) -> bool:
	var still: Array = _still[index]
	if not is_instance_valid(still[0]) or not (still[0] as Node3D).is_inside_tree() or not is_instance_valid(still[1]):
		_dirty = true
		return false
	var now := (still[1] as Node3D).global_transform.affine_inverse() * (still[0] as Node3D).global_transform
	if now.is_equal_approx(still[2]): return false
	still[2] = now
	return true
