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
##   soft round quad instead (contact_shadow.gdshader), all of them in one
##   MultiMesh; a pip draws its own quad in the same look. A foot past the
##   edge of the floor its thing stands on (a jetty over the water) gets none.
##
## Who gets one, with no per-level code:
## - every piece: kit/pieces/piece.gd `_root()` marks its root (a kit that is
##   ground itself, a crossing or a float, passes `shadow = false`);
## - every dressing prop: kit/props.gd `build()` asks prop() (PROP_NONE lists
##   the kinds that get none, and a prop set below its floor stands in water,
##   as does one the water world finds out in the water, which sets it off);
## - Home's earned keepsakes, garden planters and relay nests mark their own
##   roots (an unearned keepsake's outline gets none); a carried item marks
##   its root `live`.
## A marked root is a plain Node3D container. Its feet are the bottoms of the
## meshes that reach down to its lowest point (a tree stands on its trunk, not
## its crown; a model by the outline of its lowest vertices), each foot its
## own shape, turned with its part (a slight lean keeps its base's outline; a
## rounded underside, too few vertices to outline, rests on a round spot).
## Dressing that grows (PROP_SOFT) gets a soft round shade under each base
## and wears no grass; dressing lower than TINY_HEIGHT gets one faint round
## one, smaller than its base, and casts no sun shadow (never a box from a
## clump's bounds). Parts the static fold keeps whole because
## they move (a lever's handle, a pad's plate, a bell) never count:
## kit/static_batch.gd start() measures every marked root under what it folds
## before any leaf is folded away (FEET_META); a root measured later (a world
## that never folds) is measured on the layer's next gather, past the same
## parts (its world's _static_keep()), so feet never depend on which came first.
## A part that changes as its thing plays (changes(): a keepsake's arm, door
## or bucket) is measured then too, on its own (MOVER_META). At rest it is
## baked where it stands; while its thing plays (set_playing()) it leaves the
## bake and draws a live soft shadow in the same MultiMesh, shaped from its
## footprint, following it each frame and fading as it shows or hides; where
## it ends is baked again. Moving parts bake into their floor's second
## texture (ground_shade.gdshader keeps the darker of the two), only round
## what changed (patch()), so a play bakes its own few parts and never the
## scenery round them; nothing runs a frame for them once their thing is still.
##
## A bake is the same on every machine and in any order: its inputs are
## snapped to a fixed grid (SNAP) and it uses no trigonometry (a foot's turn is
## its across axis), overlapping feet keep the darkest, floors bake in a fixed
## order, BAKE_STAMPS a frame (work, never time), and each floor's overlay is
## made with the floor (ground()), so baking adds and removes no nodes.
##
## The layer (one per world, island_world._ready) gathers the marked roots
## and grounds under its world whenever one comes or goes, shows or hides, or
## calls touch(), and bakes again only the floors whose feet changed, a few
## floors a frame, each only where its stamps changed when that is a small
## part of it (PATCH_SHARE). Between gathers it looks at a few roots a
## frame: a still root that moved on its floor is baked where it settles; one
## that keeps moving becomes live. A live item lifted off its rest fades its
## shadow out; a carried or floating item sets_off() its own (the pip's
## shadow and the water's rings show those). Low keeps every shadow, a little
## lighter, without the grass detail or the sun's shadows, so a playing part's
## live shadow is a blob under it alone (services/graphics_policy.gd).
const SHADER = preload("res://presentation/kit/contact_shadow.gdshader")
const SHADE_SHADER = preload("res://presentation/kit/ground_shade.gdshader")
const SessionRelease = preload("res://presentation/kit/session_release.gd")
const GraphicsPolicy = preload("res://services/graphics_policy.gd")
const Cutaway = preload("res://presentation/kit/cutaway.gd")
const NODE_NAME := "ContactShadows"
const GROUP := &"contact_shadow"
## Floor tops a still thing can be baked into (ground()).
const GROUND_GROUP := &"contact_ground"
## On a ground: its bounds in its own space (x, z), the rectangles of them
## its floor is drawn as (shade lies only over these) and whether it is grass
## that wears round a base.
const GROUND_RECT_META := &"contact_ground_rect"
const GROUND_PIECES_META := &"contact_ground_pieces"
const GROUND_WORN_META := &"contact_ground_worn"
## On a marked root: its feet, [[centre Vector2, half Vector2, y, round,
## across Vector2 (unit), strength 0..1, wears grass]] in its own space; []
## for none.
const FEET_META := &"contact_shadow_feet"
## On a marked root: what casts the sun's shadow, [[centre Vector2, half
## Vector2, low, high]] in its own space.
const CASTERS_META := &"contact_shadow_casters"
## On a marked root: no shadow for now (a carried or floating item).
const OFF_META := &"contact_shadow_off"
## On a marked root: it moves, so it gets a quad instead of being baked.
const LIVE_META := &"contact_shadow_live"
## On a part under a marked root that moves, shows or hides as it plays (a
## keepsake's spinning arm, a lamp that lights): it is no foot of its root
## (changes()), but a mover of its own.
const CHANGES_META := &"contact_shadow_changes"
## On a marked root: its changing parts and the level they stand on in its
## space, {"movers": [Node3D], "ground": y}, measured with its feet.
const MOVERS_META := &"contact_shadow_movers"
## On a changing part: its solid meshes in its own space, measured with its
## root's feet (before any fold), {"parts": [[box, mesh, transform]], "box":
## all of them}.
const MOVER_META := &"contact_shadow_mover"
## On a marked root: its thing plays now (set_playing()).
const PLAYING_META := &"contact_shadow_playing"
## On a marked root at rest: its changing parts' [feet, casters] in its space
## where they stand now, measured once until it plays again.
const SETTLED_META := &"contact_shadow_settled"
## A playing part's live shadow eases in or out over this long (seconds) as
## the part shows or hides.
const PART_FADE := 0.2
## A raised playing part's live shadow, cast along the sun, is as dark beside
## a resting one as a floor's sun shadow beside its contact shade
## (ground_shade.gdshader cast_strength over contact_strength).
const PART_CAST := 0.30 / 0.62
## A floor's two baked textures: what stands still, and its resting
## changing parts (ground_shade.gdshader's shade and moving).
const KINDS: Array[String] = ["still", "moving"]
## A floor whose changed stamps cover at most this share of it bakes again
## only there (patch()); more, and it bakes whole.
const PATCH_SHARE := 0.5
## On a dressing root (prop()): "soft" for a kind in PROP_SOFT, else "firm".
const LOOK_META := &"contact_shadow_look"
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
## A part leaning less than this (the sine of its lean) still stands on its
## own base's outline; one leaning more falls back to its box.
const LEAN := 0.2
## A model whose lowest vertices are too few to outline (a rounded underside,
## a leafy ball) rests on the outline of its vertices this share of its
## height up, round.
const ROUNDED_BAND := 0.25
## Dressing lower than this (metres over its ground) is tiny: one faint round
## shade, TINY_SHARE of its base across and TINY_STRENGTH as dark, no worn
## grass and no sun shadow.
const TINY_HEIGHT := 0.2
const TINY_SHARE := 0.6
const TINY_STRENGTH := 0.5
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
## Stamps (feet and sun shadows) baked a frame, once a frame has baked a
## floor: about 2 ms on a desktop, so the busiest chapter bakes in about 25
## frames.
const BAKE_STAMPS := 16
## A bake's inputs snap to 1/SNAP metres (a power of two, so exact), so the
## last bit of a transform never changes a texel between platforms.
const SNAP := 4096.0
## On a ground: its overlay, made with it (overlay_of()).
const OVERLAY_META := &"contact_ground_overlay"
## The render layers an overlay draws on once it holds shade (none before).
const SHADE_LAYERS := 1
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
## Dressing kinds that grow rather than stand, with why: every foot a soft
## round shade under its base, wearing no grass.
const PROP_SOFT := {
	"bush": "leafy balls sit on the grass",
	"flowers": "a clump of leaves and stems",
	"hedge": "leafy balls in a row",
}

static var _touches := 0
## Bumped when a thing starts or stops playing (set_playing()): each layer
## redoes only its playing things' changing parts, never a whole gather.
static var _plays := 0
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

## Marks `part` as one that moves, shows or hides as its thing plays: no foot
## of its root, but baked on its own where it rests and drawn live while its
## thing plays (set_playing()).
static func changes(part: Node) -> void:
	part.set_meta(CHANGES_META, true)

## Whether root's thing is playing: while it plays its changing parts draw
## live shadows that follow them; once it stops they are baked where they
## stand, the floor again only round them.
static func set_playing(root: Node3D, on: bool) -> void:
	if not is_instance_valid(root) or root.has_meta(PLAYING_META) == on: return
	if on: root.set_meta(PLAYING_META, true)
	else: root.remove_meta(PLAYING_META)
	root.remove_meta(SETTLED_META)
	if not (root.get_meta(MOVERS_META, {}).get("movers", []) as Array).is_empty(): _plays += 1

## Marks a dressing prop of `spec`, unless its kind gets none or it stands
## below its floor (in water or mud).
static func prop(root: Node3D, spec: Dictionary) -> void:
	var kind := str(spec.get("kind", ""))
	if PROP_NONE.has(kind) or bool(spec.get("wall", false)) or float(spec.get("y", 0)) < 0.0: return
	root.set_meta(LOOK_META, "soft" if PROP_SOFT.has(kind) else "firm")
	mark(root)

## Registers a floor top under `parent`: `rect` (x, z in parent space) at
## height `top`, its whole drawn top (past the walkable edge where it is drawn
## wider, kit/walk_reach.gd); `worn` for grass, which wears round a base. A
## floor drawn as several rectangles that meet edge to edge (cut round its
## neighbours) names them as `pieces`, inside `rect`: one ground, so a foot by
## a seam is baked whole, with shade drawn only over them. A shared floor
## builder calls it once per floor it lays; the layer bakes what stands on it.
static func ground(parent: Node3D, rect: Rect2, top: float, worn: bool, pieces: Array[Rect2] = []) -> Node3D:
	var node := Node3D.new()
	node.name = "Ground"
	node.position = Vector3(0, top, 0)
	node.set_meta(GROUND_RECT_META, rect)
	var drawn: Array[Rect2] = pieces.duplicate()
	if drawn.is_empty(): drawn.append(rect)
	node.set_meta(GROUND_PIECES_META, drawn)
	node.set_meta(GROUND_WORN_META, worn)
	node.add_to_group(GROUND_GROUP)
	parent.add_child(node)
	# Its overlay comes with it, whole from the start: the floor's quad in the
	# floor's look, drawn on no layer until the layer bakes shade into it.
	var overlay := MeshInstance3D.new()
	overlay.name = "Shade"
	overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	overlay.set_meta(Cutaway.HIDE, true)
	var look := ShaderMaterial.new()
	look.shader = SHADE_SHADER
	look.set_shader_parameter("dark_tint", Vector3(TINT.r, TINT.g, TINT.b))
	overlay.material_override = look
	node.set_meta(OVERLAY_META, overlay)
	_empty_overlay(node)
	node.add_child(overlay)
	return node

## ground() for a floor drawn as `pieces_cm` ([x0, z0, x1, z1] cm in parent
## space, meeting edge to edge: WalkReach.pieces), over their bounds.
static func ground_cm(parent: Node3D, pieces_cm: Array, top: float, worn: bool) -> Node3D:
	var pieces: Array[Rect2] = []
	var bounds := Rect2()
	for piece: Array in pieces_cm:
		var rect := Rect2(Vector2(float(piece[0]), float(piece[1])) / 100.0, Vector2(float(piece[2] - piece[0]), float(piece[3] - piece[1])) / 100.0)
		bounds = rect if pieces.is_empty() else bounds.merge(rect)
		pieces.append(rect)
	return ground(parent, bounds, top, worn, pieces)

## Whether a ground's drawn top holds `at` (its own x, z), `grow` metres past
## its pieces' sides.
static func holds(ground: Node3D, at: Vector2, grow: float = 0.0) -> bool:
	for piece: Rect2 in ground.get_meta(GROUND_PIECES_META):
		if piece.grow(grow).has_point(at): return true
	return false

## A ground's overlay (null for a node that is not one).
static func overlay_of(ground: Node3D) -> MeshInstance3D:
	var overlay: Variant = ground.get_meta(OVERLAY_META, null)
	return overlay if is_instance_valid(overlay) else null

## A ground's overlay holding no shade: the floor's quads (its pieces), on
## no render layer, so it is a whole mesh that costs no draw.
static func _empty_overlay(ground: Node3D) -> void:
	var overlay: MeshInstance3D = ground.get_meta(OVERLAY_META)
	var pieces: Array[Rect2] = []
	pieces.assign(ground.get_meta(GROUND_PIECES_META))
	overlay.mesh = overlay_mesh(ground.get_meta(GROUND_RECT_META), pieces)
	overlay.layers = 0

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
	var movers: Array[Node3D] = []
	_parts(root, Transform3D.IDENTITY, kept, parts, movers)
	var measured := [[], []]
	# A post sunk into the floor meets it at the root's own level.
	var ground_y := 0.0
	if not parts.is_empty():
		var lowest := INF
		for part: Array in parts: lowest = minf(lowest, (part[0] as AABB).position.y)
		ground_y = maxf(lowest, 0.0)
		if lowest <= GROUND_REACH: measured = _measure(parts, ground_y, str(root.get_meta(LOOK_META, "")))
		else: movers.clear()
	root.set_meta(CASTERS_META, measured[1])
	root.set_meta(FEET_META, measured[0])
	# Each changing part on its own, in its own space, nested ones too.
	var found: Array[Node3D] = []
	var index := 0
	while index < movers.size():
		var mover := movers[index]
		index += 1
		var own: Array = []
		if mover is MeshInstance3D and _solid(mover as MeshInstance3D): own.append([(mover as MeshInstance3D).mesh.get_aabb(), (mover as MeshInstance3D).mesh, Transform3D.IDENTITY])
		_parts(mover, Transform3D.IDENTITY, kept, own, movers)
		if own.is_empty(): continue
		var box: AABB = own[0][0]
		for part: Array in own: box = box.merge(part[0])
		mover.set_meta(MOVER_META, {"parts": own, "box": box})
		found.append(mover)
	root.set_meta(MOVERS_META, {"movers": found, "ground": ground_y})
	return measured[0]

## The feet and casters of `parts` ([box, mesh, transform] in a root's space)
## standing on `ground_y`, for a root of `look`: [feet, casters].
static func _measure(parts: Array, ground_y: float, look: String) -> Array:
	var result: Array = []
	var casters: Array = []
	var top := ground_y
	for part: Array in parts: top = maxf(top, (part[0] as AABB).end.y)
	var tiny := not look.is_empty() and top - ground_y < TINY_HEIGHT
	var soft := look == "soft"
	for part: Array in parts:
		var box: AABB = part[0]
		if box.end.y - ground_y >= CAST_HEIGHT and not tiny: casters.append([Vector2(box.get_center().x, box.get_center().z), Vector2(box.size.x, box.size.z) * 0.5, maxf(box.position.y, ground_y), box.end.y])
		if box.position.y > ground_y + BAND or box.end.y < ground_y: continue
		var foot := _foot(part[1], part[2])
		if (foot[1] as Vector2).x < 0.0025 or (foot[1] as Vector2).y < 0.0025: continue
		result.append([foot[0], foot[1], ground_y, 1.0 if soft else foot[2], foot[3], 1.0, not soft])
	if tiny and not result.is_empty(): result = [_tiny_foot(result, ground_y)]
	# The biggest shadow first (a tall post before a low wide plinth, so an
	# arch's shadow keeps its legs); equal ones by where they stand, so the
	# same few win whatever order the parts were found in.
	casters.sort_custom(func(a: Array, b: Array) -> bool: return _before([-_q(_cast_size(a)), _q((a[0] as Vector2).x), _q((a[0] as Vector2).y), _q(float(a[3]))], [-_q(_cast_size(b)), _q((b[0] as Vector2).x), _q((b[0] as Vector2).y), _q(float(b[3]))]))
	return [result, casters.slice(0, CASTS_MOST)]

## root's changing parts where they stand now, at rest: [feet, casters] in its
## space, measured once until it plays again (set_playing()). A hidden part
## has none, and none wears the grass.
static func _settled(root: Node3D) -> Array:
	if root.has_meta(SETTLED_META): return root.get_meta(SETTLED_META)
	var movers: Dictionary = root.get_meta(MOVERS_META, {})
	var parts: Array = []
	var from_root := root.global_transform.affine_inverse()
	for mover: Variant in movers.get("movers", []):
		if not is_instance_valid(mover) or not (mover as Node3D).is_visible_in_tree(): continue
		var to_root := from_root * (mover as Node3D).global_transform
		for part: Array in (mover as Node3D).get_meta(MOVER_META).parts:
			var xform := to_root * (part[2] as Transform3D)
			parts.append([xform * (part[1] as Mesh).get_aabb(), part[1], xform])
	var settled := [[], []] if parts.is_empty() else _measure(parts, float(movers.get("ground", 0.0)), str(root.get_meta(LOOK_META, "")))
	# A part that comes and goes wears no grass.
	for foot: Array in settled[0]: foot[6] = false
	root.set_meta(SETTLED_META, settled)
	return settled

## How big a caster's sun shadow is: its longer side by its height.
static func _cast_size(caster: Array) -> float:
	return maxf((caster[1] as Vector2).x, (caster[1] as Vector2).y) * (float(caster[3]) - float(caster[2]))

## Tiny dressing's one faint round foot: under the middle of its feet,
## TINY_SHARE of their outline across, wearing no grass.
static func _tiny_foot(feet_list: Array, ground_y: float) -> Array:
	var outline := Rect2()
	for index in range(feet_list.size()):
		var foot: Array = feet_list[index]
		var across: Vector2 = foot[4]
		var half: Vector2 = foot[1]
		var spread := Vector2(absf(across.x) * half.x + absf(across.y) * half.y, absf(across.y) * half.x + absf(across.x) * half.y)
		var rect := Rect2((foot[0] as Vector2) - spread, spread * 2.0)
		outline = rect if index == 0 else outline.merge(rect)
	return [outline.get_center(), outline.size * 0.5 * TINY_SHARE, ground_y, 1.0, Vector2.RIGHT, TINY_STRENGTH, false]

## The solid meshes under node, past any kept, changing or hidden part or
## another marked root, each as [box in root's space, mesh, transform in root's
## space]; the changing parts met on the way (shown or not) go in `movers`.
static func _parts(node: Node, to_root: Transform3D, kept: Dictionary, parts: Array, movers: Array[Node3D] = []) -> void:
	for child: Node in node.get_children():
		if not child is Node3D or kept.has(child.get_instance_id()) or child.is_in_group(GROUP) or child.is_in_group(GROUND_GROUP): continue
		if child.has_meta(CHANGES_META):
			movers.append(child as Node3D)
			continue
		if not (child as Node3D).visible: continue
		var xform := to_root * (child as Node3D).transform
		if child is MeshInstance3D and _solid(child as MeshInstance3D):
			var mesh := (child as MeshInstance3D).mesh
			parts.append([xform * mesh.get_aabb(), mesh, xform])
		_parts(child, xform, kept, parts, movers)

## A mesh's foot in root space: [centre, half, round, across (unit)]. Its
## bottom's outline (bottom()) turned with it; a tilted part keeps its box's.
static func _foot(mesh: Mesh, xform: Transform3D) -> Array:
	var bottom := bottom(mesh)
	var rect: Rect2 = bottom[0]
	var across := Vector3(xform.basis.x.x, 0, xform.basis.x.z)
	var deep := Vector3(xform.basis.z.x, 0, xform.basis.z.z)
	var upright := absf(xform.basis.x.y) < LEAN * xform.basis.x.length() and absf(xform.basis.z.y) < LEAN * xform.basis.z.length()
	if not upright:
		var box := xform * mesh.get_aabb()
		return [Vector2(box.get_center().x, box.get_center().z), Vector2(box.size.x, box.size.z) * 0.5, minf(float(bottom[1]), 0.5), Vector2.RIGHT]
	var centre := xform * Vector3(rect.get_center().x, mesh.get_aabb().position.y, rect.get_center().y)
	return [Vector2(centre.x, centre.z), rect.size * 0.5 * Vector2(across.length(), deep.length()), bottom[1], _unit(Vector2(across.x, across.z))]

## v made unit, or the x axis for none.
static func _unit(v: Vector2) -> Vector2:
	return v / v.length() if v.length() > 0.000001 else Vector2.RIGHT

## A length in whole 1/SNAP metres.
static func _q(value: float) -> int:
	return roundi(value * SNAP)

static func _snapped(value: float) -> float:
	return roundi(value * SNAP) / SNAP

static func _snapped2(value: Vector2) -> Vector2:
	return Vector2(_snapped(value.x), _snapped(value.y))

## Whether key a (whole numbers) sorts before key b.
static func _before(a: Array, b: Array) -> bool:
	for index in range(a.size()):
		if a[index] != b[index]: return a[index] < b[index]
	return false

## The instance ids of what root's world keeps whole because it moves (its
## _static_keep(), as its fold leaves out), for measuring feet without a fold.
static func _kept_by(world: Node) -> Dictionary:
	var ids: Dictionary = {}
	if world == null or not world.has_method("_static_keep"): return ids
	for node: Variant in world.call("_static_keep"):
		if is_instance_valid(node) and node is Node: ids[(node as Node).get_instance_id()] = true
	return ids

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
	var low := _low_points(mesh, box.position.y + maxf(box.size.y * 0.05, 0.01))
	var found := [whole, 0.3]
	if low.size() < 3:
		# A rounded underside: it rests on a round spot, the outline a little
		# way up it (ROUNDED_BAND), never its whole box.
		low = _low_points(mesh, box.position.y + box.size.y * ROUNDED_BAND)
		if low.size() >= 3:
			var spot := Rect2(low[0], Vector2.ZERO)
			for point: Vector2 in low: spot = spot.expand(point)
			found = [spot, 1.0]
	else:
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

## A mesh's vertices no higher than `band`, flat (x, z).
static func _low_points(mesh: Mesh, band: float) -> Array[Vector2]:
	var low: Array[Vector2] = []
	for surface in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surface)
		for point: Vector3 in arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array:
			if point.y <= band: low.append(Vector2(point.x, point.z))
	return low

## A mesh that stands on the ground, drawn solid: every look it draws with
## opaque, not a glow, a pool of light, a see-through veil (an unearned
## keepsake's outline) or a part drawn with no shadow of its own. A mesh the
## cutaway fades for now (kit/cutaway.gd) is still there: it counts.
static func _solid(mesh: MeshInstance3D) -> bool:
	if mesh.mesh == null: return false
	if mesh.get_meta("cutaway", false): return true
	if mesh.transparency > 0.0 or mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF: return false
	if mesh.material_override != null: return _opaque(mesh.material_override)
	for surface in range(mesh.mesh.get_surface_count()):
		var look := mesh.get_surface_override_material(surface)
		if look == null: look = mesh.mesh.surface_get_material(surface)
		if look != null and not _opaque(look): return false
	return true

## A look drawn solid: an opaque base material that does not glow.
static func _opaque(look: Material) -> bool:
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

## Bakes `feet` ([[centre, half, round, across (unit), strength, wears grass]]
## in the ground's space; the last two default to 1 and true)
## and `casts` ([[centre, along (unit), half, soft]]) into an RGB image over
## `rect` (see ground_shade.gdshader). Returns {image, tiles: [Rect2]} or {}
## when nothing shows. Every input is snapped first (SNAP), and the stamps
## keep the darkest, so the image is the same on any platform, in any order.
## `pieces`: the rectangles of rect the floor is drawn as (all of it when
## empty); its tiles are drawn only over them.
static func bake(rect: Rect2, feet_list: Array, casts: Array, worn: bool, pieces: Array = []) -> Dictionary:
	var size := _texels(rect)
	var data := PackedByteArray()
	data.resize(size.x * size.y * 3)
	var records := _records(feet_list, casts, worn)
	var boxes: Array[Rect2i] = []
	for record: Array in records: boxes.append(_stamp(data, size, rect, record))
	return _baked_image(rect, pieces, size, data, records, boxes)

## bake() again from `before` (a bake() or patch() of the same floor with what
## stood on it then): only the texels round the stamps that came or went are
## cleared and stamped again, by every stamp that reaches them, so every
## texel and tile is what bake() would make, for a few stamps' work. With
## nothing baked before, or more than PATCH_SHARE of the floor changed, it
## bakes whole. The result also gives "stamped": the stamps it drew.
static func patch(rect: Rect2, before: Dictionary, feet_list: Array, casts: Array, worn: bool, pieces: Array = []) -> Dictionary:
	var size := _texels(rect)
	var records := _records(feet_list, casts, worn)
	if not before.has("image") or (before.image as Image).get_size() != size: return _whole(rect, feet_list, casts, worn, pieces, records.size())
	# The stamps that came or went, by value (snapped, so exact).
	var left: Dictionary = {}
	for record: Array in before.records: left[record] = int(left.get(record, 0)) + 1
	var changed: Array = []
	for record: Array in records:
		if int(left.get(record, 0)) > 0: left[record] = int(left[record]) - 1
		else: changed.append(record)
	for record: Array in left:
		for count in range(int(left[record])): changed.append(record)
	if changed.is_empty(): return before.merged({"records": records, "stamped": 0}, true)
	var region := Rect2i(0, 0, -1, -1)
	for record: Array in changed:
		var box := _stamp_box(size, rect, record)
		if box.size.x >= 0: region = box if region.size.x < 0 else region.merge(box)
	if region.size.x >= 0 and (region.size.x + 1) * (region.size.y + 1) > size.x * size.y * PATCH_SHARE: return _whole(rect, feet_list, casts, worn, pieces, records.size())
	var cleared := (before.image as Image).duplicate() as Image
	if region.size.x >= 0: cleared.fill_rect(Rect2i(region.position, region.size + Vector2i.ONE), Color.BLACK)
	var data := cleared.get_data()
	var boxes: Array[Rect2i] = []
	var stamped := 0
	for record: Array in records: boxes.append(_stamp_box(size, rect, record))
	if region.size.x >= 0:
		for index in range(records.size()):
			if _meets(boxes[index], region):
				_stamp(data, size, rect, records[index], region)
				stamped += 1
	var baked := _baked_image(rect, pieces, size, data, records, boxes)
	return baked if baked.is_empty() else baked.merged({"stamped": stamped})

## bake(), saying it drew `stamps`; {} when nothing shows.
static func _whole(rect: Rect2, feet_list: Array, casts: Array, worn: bool, pieces: Array, stamps: int) -> Dictionary:
	var baked := bake(rect, feet_list, casts, worn, pieces)
	return baked if baked.is_empty() else baked.merged({"stamped": stamps})

## A floor's size in texels.
static func _texels(rect: Rect2) -> Vector2i:
	return Vector2i(maxi(1, ceili(rect.size.x / TEXEL)), maxi(1, ceili(rect.size.y / TEXEL)))

## The stamps `feet_list` and `casts` make on a floor, every input snapped
## (SNAP): [centre, across (unit), half, corner, fade, reach, worn, strength]
## for _stamp().
static func _records(feet_list: Array, casts: Array, worn: bool) -> Array:
	var records: Array = []
	for foot: Array in feet_list:
		var half := _snapped2(foot[1])
		var fade := fade_for(half)
		var wears := worn and (bool(foot[5]) if foot.size() > 5 else true)
		records.append([_snapped2(foot[0]), _snapped2(foot[3]), half, _snapped(float(foot[2])) * minf(half.x, half.y), fade, worn_for(half) if wears else fade, 0 if wears else -1, _strength(foot, 4)])
	for cast: Array in casts:
		var cast_half := _snapped2(cast[2])
		var soft := _snapped(float(cast[3]))
		records.append([_snapped2(cast[0]), _snapped2(cast[1]), cast_half, minf(cast_half.x, cast_half.y), soft, soft, -2, 1.0])
	return records

## A baked floor's image and the tiles its stamps' boxes touch: {image, tiles,
## records}, or {} when nothing shows.
static func _baked_image(rect: Rect2, pieces: Array, size: Vector2i, data: PackedByteArray, records: Array, boxes: Array[Rect2i]) -> Dictionary:
	var per_tile := maxi(1, roundi(TILE / TEXEL))
	var tiles_across := ceili(float(size.x) / per_tile)
	var marked: Dictionary = {}
	for box: Rect2i in boxes: _mark_tiles(box, per_tile, tiles_across, marked)
	if marked.is_empty(): return {}
	var tiles: Array[Rect2] = []
	for key: int in marked:
		var tile := Rect2(rect.position + Vector2(key % tiles_across, key / tiles_across) * per_tile * TEXEL, Vector2.ONE * per_tile * TEXEL)
		for piece: Rect2 in (pieces if not pieces.is_empty() else [rect]):
			var part := tile.intersection(piece.intersection(rect))
			if part.has_area(): tiles.append(part)
	if tiles.is_empty(): return {}
	tiles.sort_custom(func(a: Rect2, b: Rect2) -> bool: return a.position.y < b.position.y or (a.position.y == b.position.y and a.position.x < b.position.x))
	return {"image": Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGB8, data), "tiles": tiles, "records": records}

## Whether two texel boxes (their end texels inside them) share a texel.
static func _meets(a: Rect2i, b: Rect2i) -> bool:
	return a.size.x >= 0 and b.size.x >= 0 and a.position.x <= b.end.x and b.position.x <= a.end.x and a.position.y <= b.end.y and b.position.y <= a.end.y

## The texels a stamp (_records()) reaches on a floor of `size` over `rect`,
## its last texel at its end (a negative size when it lies off the floor).
static func _stamp_box(size: Vector2i, rect: Rect2, record: Array) -> Rect2i:
	var centre: Vector2 = record[0]
	var across: Vector2 = record[1]
	var half: Vector2 = record[2]
	var deep := Vector2(-across.y, across.x)
	var outer := half + Vector2.ONE * maxf(float(record[4]), float(record[5]))
	var spread := Vector2(absf(across.x) * outer.x + absf(deep.x) * outer.y, absf(across.y) * outer.x + absf(deep.y) * outer.y)
	var from := Vector2i(floori((centre.x - spread.x - rect.position.x) / TEXEL), floori((centre.y - spread.y - rect.position.y) / TEXEL))
	var to := Vector2i(ceili((centre.x + spread.x - rect.position.x) / TEXEL), ceili((centre.y + spread.y - rect.position.y) / TEXEL))
	if to.x < 0 or to.y < 0 or from.x >= size.x or from.y >= size.y: return Rect2i(0, 0, -1, -1)
	from = from.clamp(Vector2i.ZERO, size - Vector2i.ONE)
	to = to.clamp(Vector2i.ZERO, size - Vector2i.ONE)
	return Rect2i(from, to - from)

## Stamps one soft rounded box (a _records() stamp: centre, its across axis
## (unit), half size, corner radius, how far its own channel fades out past it
## and how far the worn channel does, worn, strength) into data, keeping the
## darker of what is there and what it adds, only inside `clip` when it has
## one. `worn`: 0 also writes the worn channel, -1 only the contact channel,
## -2 the sun's (b) channel alone. `strength` scales how dark its own channel
## gets. Returns the texel box it reaches (_stamp_box()).
static func _stamp(data: PackedByteArray, size: Vector2i, rect: Rect2, record: Array, clip: Rect2i = Rect2i(0, 0, -1, -1)) -> Rect2i:
	var box := _stamp_box(size, rect, record)
	if box.size.x < 0 or (clip.size.x >= 0 and not _meets(box, clip)): return box
	var centre: Vector2 = record[0]
	var across: Vector2 = record[1]
	var half: Vector2 = record[2]
	var corner: float = record[3]
	var fade: float = record[4]
	var reach: float = record[5]
	var worn: int = record[6]
	var strength: float = record[7]
	var width := size.x
	var deep := Vector2(-across.y, across.x)
	var from := box.position
	var to := box.end
	if clip.size.x >= 0:
		from = from.max(clip.position)
		to = to.min(clip.end)
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
				var level := int(shade * shade * (3.0 - 2.0 * shade) * 255.0 * strength)
				if level > data[at + channel]: data[at + channel] = level
			if worn == 0:
				var wear := clampf(1.0 - outside / reach, 0.0, 1.0)
				var level := int(wear * wear * (3.0 - 2.0 * wear) * 255.0)
				if level > data[at + 1]: data[at + 1] = level
	return box

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
## Per playing part drawn live (after the live shadows in the MultiMesh):
## {part, box (its MOVER_META box), ground (its floor's height in the layer's
## space), sun (the floor offset per metre of height, x and z in the layer's
## space; zero without the sun's shadows), seen, strength (its fade), drawn:
## {transform, strength, half}}.
var _movers: Array[Dictionary] = []
## Per still root with changing parts, in the gather's order (_mover_entry()).
var _mover_roots: Array[Dictionary] = []
## The visible floors in their fixed order, and the sun's floor offset, as
## the last gather found them.
var _grounds: Array[Node3D] = []
var _sun := Vector3.ZERO
var _played := -1
## Per ground node: {key (what the floor is), tiles (drawn now), "still" and
## "moving" (its two textures, KINDS): {signature, bake (what bake() or
## patch() gave, to patch next time)}}.
var _baked: Dictionary = {}
## Grounds waiting to bake, in a fixed order: [ground, feet, casts, signature].
var _to_bake: Array = []
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
		for ground: Variant in _baked:
			for kind: String in KINDS:
				if (_baked[ground] as Dictionary).has(kind): _baked[ground][kind].signature = 0
		_dirty = true
	if _draw == null: return
	_draw.set_instance_shader_parameter("shadow_strength", GraphicsPolicy.contact_shadow_strength(_quality))
	for ground: Variant in _baked:
		if is_instance_valid(ground): _shade_quality(ground as Node3D)

## A floor's overlay in this quality's look, whether or not it holds shade.
func _shade_quality(ground: Node3D) -> void:
	var overlay := overlay_of(ground)
	if overlay == null: return
	var look := overlay.material_override as ShaderMaterial
	var detail := GraphicsPolicy.ground_detail(_quality)
	var strength := 0.62 * GraphicsPolicy.contact_shadow_strength(_quality) / GraphicsPolicy.contact_shadow_strength("balanced")
	if look.get_shader_parameter("detail") != detail: look.set_shader_parameter("detail", detail)
	if look.get_shader_parameter("contact_strength") != strength: look.set_shader_parameter("contact_strength", strength)

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

## The playing parts' live shadows as drawn: [{part, transform (in the
## layer's space), strength, half}].
func part_shadows() -> Array:
	var found: Array = []
	for mover: Dictionary in _movers: found.append((mover.drawn as Dictionary).merged({"part": mover.part}))
	return found

## The roots baked into a floor, each with its ground: [[root, ground]].
func baked_roots() -> Array:
	var found: Array = []
	for still: Array in _still: found.append([still[0], still[1]])
	return found

## The floors drawn with an overlay now, each {ground, overlay, image (what
## stands still, or null), moving (changing parts at rest, or null)}.
func overlays() -> Array:
	var found: Array = []
	for ground: Variant in _baked:
		if not is_instance_valid(ground): continue
		var images := {}
		for kind: String in KINDS: images[kind] = _baked[ground].get(kind, {}).get("bake", {}).get("image")
		if images.still != null or images.moving != null: found.append({"ground": ground, "overlay": overlay_of(ground as Node3D), "image": images.still, "moving": images.moving})
	return found

## Whether every floor waiting to bake has baked.
func settled() -> bool:
	return not _dirty and _to_bake.is_empty()

func _process(delta: float) -> void:
	refresh(delta)

## Gathers again when something marked came, went, showed, hid or was
## touched, then bakes what changed; otherwise follows whatever moved, and
## every playing part `step` seconds on.
func refresh(step: float = 0.0) -> void:
	if _draw == null or not is_inside_tree(): return
	var members := get_tree().get_node_count_in_group(GROUP)
	var grounds := get_tree().get_node_count_in_group(GROUND_GROUP)
	if _dirty or members != _members or grounds != _grounds_seen or _touches != _touched:
		_gather(members, grounds)
	else:
		if _plays != _played: _replay()
		_follow()
	if not _movers.is_empty(): _follow_parts(step)
	if not _to_bake.is_empty(): _bake_some()

func _on_member_shown() -> void:
	_dirty = true

func _gather(members: int, grounds_count: int) -> void:
	_dirty = false
	_members = members
	_grounds_seen = grounds_count
	_touched = _touches
	_played = _plays
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
	# In a fixed order (where each floor lies), never the order they were made.
	var ground_keys: Dictionary = {}
	for ground: Node3D in grounds:
		var rect: Rect2 = ground.get_meta(GROUND_RECT_META)
		var at := ground.global_position
		ground_keys[ground] = [_q(at.y), _q(at.x + rect.position.x), _q(at.z + rect.position.y), _q(rect.size.x), _q(rect.size.y)]
	grounds.sort_custom(func(a: Node3D, b: Node3D) -> bool: return _before(ground_keys[a], ground_keys[b]))
	# Feet not measured yet are measured past what the world keeps whole, as
	# its fold measures them (static_batch.gd start()).
	var kept: Variant = null
	var on_ground: Dictionary = {}
	# Per floor: what stands still on it (feet, casts, what each is).
	for ground: Node3D in grounds: on_ground[ground] = [[], [], []]
	var live: Array = []
	var still: Array = []
	var sun := _sun_offset()
	_grounds = grounds
	_sun = sun
	_mover_roots.clear()
	for found: Node in get_tree().get_nodes_in_group(GROUP):
		if not world.is_ancestor_of(found): continue
		var root := found as Node3D
		if not root.visibility_changed.is_connected(_on_member_shown): root.visibility_changed.connect(_on_member_shown)
		if not root.is_visible_in_tree() or root.has_meta(OFF_META): continue
		if not root.has_meta(FEET_META) and kept == null: kept = _kept_by(world)
		var its_feet := feet(root, kept if kept != null else {})
		if root.has_meta(LIVE_META):
			for foot: Array in its_feet: live.append([root, foot, (foot[1] as Vector2).x * (foot[1] as Vector2).y])
			continue
		var stood: Node3D = null
		var off: Array = []
		for foot: Array in its_feet:
			var ground := _ground_for(root, foot, grounds)
			if ground == null:
				off.append([root, foot, (foot[1] as Vector2).x * (foot[1] as Vector2).y])
				continue
			var to_ground := ground.global_transform.affine_inverse() * root.global_transform
			(on_ground[ground][0] as Array).append(_ground_foot(foot, to_ground))
			(on_ground[ground][2] as Array).append([root.get_instance_id(), to_ground, foot])
			if stood == null: stood = ground
		# Standing on no floor top at all (a ledge no builder registers), it
		# gets quads; feet past the edge of the floor it stands on (a jetty
		# over the water) get nothing.
		if stood == null:
			live.append_array(off)
			continue
		var to_stood := stood.global_transform.affine_inverse() * root.global_transform
		if not (root.get_meta(MOVERS_META, {}).get("movers", []) as Array).is_empty(): _mover_roots.append(_mover_entry(root, stood))
		for caster: Array in root.get_meta(CASTERS_META, []):
			var cast := _cast(caster, to_stood, (stood.global_transform.basis.inverse() * sun))
			if not cast.is_empty(): (on_ground[stood][1] as Array).append(cast)
		still.append([root, stood, to_stood])
	_still = still
	# Bake only the floors whose feet changed; a floor that went or hid is
	# emptied (its overlay stays with it, holding nothing).
	for ground: Variant in _baked.keys():
		if not on_ground.has(ground):
			if is_instance_valid(ground): _clear(ground as Node3D)
			_baked.erase(ground)
	_to_bake.clear()
	for ground: Node3D in grounds:
		_shade_quality(ground)
		var entry: Array = on_ground[ground]
		_queue(ground, "still", entry[0], entry[1], entry[2])
		_queue_moving(ground)
	_place_live(live)

## Queues one of a floor's textures (KINDS) to bake when what it holds
## (`made_of`: what each stamp is) changed since it was last baked; a moving
## texture that never held anything and holds nothing now has nothing to bake.
func _queue(ground: Node3D, kind: String, feet_list: Array, casts: Array, made_of: Array) -> void:
	var signature := hash([made_of, casts, ground.get_meta(GROUND_RECT_META), ground.get_meta(GROUND_PIECES_META), ground.get_meta(GROUND_WORN_META)])
	var last: Dictionary = _baked.get(ground, {}).get(kind, {})
	if last.has("signature") and int(last.signature) == signature: return
	if kind == "moving" and feet_list.is_empty() and casts.is_empty() and (last.get("bake", {}) as Dictionary).is_empty(): return
	_to_bake = _to_bake.filter(func(job: Array) -> bool: return job[0] != ground or job[4] != kind)
	_to_bake.append([ground, feet_list, casts, signature, kind])

## Queues a floor's moving texture from the resting changing parts standing on it.
func _queue_moving(ground: Node3D) -> void:
	var feet_list: Array = []
	var casts: Array = []
	var made_of: Array = []
	for entry: Dictionary in _mover_roots:
		for foot: Array in entry.feet:
			if foot[0] != ground: continue
			feet_list.append(foot[1])
			made_of.append(foot[2])
		if entry.stood == ground:
			casts.append_array(entry.casts)
			made_of.append_array(entry.casts)
	_queue(ground, "moving", feet_list, casts, made_of)

## A still root's changing parts: {root, stood (its floor), playing, feet:
## [[ground, foot in its space, what it is]], casts (on stood)}, none while it
## plays (they are drawn live then).
func _mover_entry(root: Node3D, stood: Node3D) -> Dictionary:
	var entry := {"root": root, "stood": stood, "playing": root.has_meta(PLAYING_META), "feet": [], "casts": []}
	if entry.playing: return entry
	var settled := _settled(root)
	for foot: Array in settled[0]:
		var ground := _ground_for(root, foot, _grounds)
		if ground == null: continue
		var to_ground := ground.global_transform.affine_inverse() * root.global_transform
		(entry.feet as Array).append([ground, _ground_foot(foot, to_ground), [root.get_instance_id(), to_ground, foot]])
	var to_stood := stood.global_transform.affine_inverse() * root.global_transform
	for caster: Array in settled[1]:
		var cast := _cast(caster, to_stood, (stood.global_transform.basis.inverse() * _sun))
		if not cast.is_empty(): (entry.casts as Array).append(cast)
	return entry

## A thing started or stopped playing (set_playing()): only the changing
## parts of those that did are measured again, their floors' moving textures
## baked round them and the live shadows drawn again.
func _replay() -> void:
	_played = _plays
	var floors := {}
	var changed := false
	for index in range(_mover_roots.size()):
		var entry: Dictionary = _mover_roots[index]
		var root: Variant = entry.root
		if not is_instance_valid(root) or not (root as Node3D).is_inside_tree() or not is_instance_valid(entry.stood):
			_dirty = true
			return
		var playing := (root as Node3D).has_meta(PLAYING_META)
		if playing == entry.playing and (playing or (root as Node3D).has_meta(SETTLED_META)): continue
		var now := _mover_entry(root as Node3D, entry.stood)
		for foot: Array in (entry.feet as Array) + (now.feet as Array): floors[foot[0]] = true
		floors[entry.stood] = true
		_mover_roots[index] = now
		changed = true
	if not changed: return
	for ground: Node3D in _grounds:
		if floors.has(ground): _queue_moving(ground)
	_place_parts()

## The floor top a foot of root stands on: the one whose rect holds its
## centre at its height, the nearest under it; null for none.
func _ground_for(root: Node3D, foot: Array, grounds: Array[Node3D]) -> Node3D:
	var at := root.global_transform * Vector3((foot[0] as Vector2).x, float(foot[2]), (foot[0] as Vector2).y)
	var best: Node3D = null
	var best_gap := INF
	for ground: Node3D in grounds:
		var local := ground.global_transform.affine_inverse() * at
		if local.y < -0.06 or local.y > 0.12 or not holds(ground, Vector2(local.x, local.z), 0.02): continue
		if absf(local.y) < best_gap:
			best_gap = absf(local.y)
			best = ground
	return best

## A foot of a root in its ground's space: [centre, half, round, across,
## strength, wears grass].
static func _ground_foot(foot: Array, to_ground: Transform3D) -> Array:
	var turn: Vector2 = foot[4]
	var centre := to_ground * Vector3((foot[0] as Vector2).x, float(foot[2]), (foot[0] as Vector2).y)
	var across := to_ground.basis * Vector3(turn.x, 0, turn.y)
	var deep := to_ground.basis * Vector3(-turn.y, 0, turn.x)
	var flat_across := Vector2(across.x, across.z)
	var half := (foot[1] as Vector2) * Vector2(flat_across.length(), Vector2(deep.x, deep.z).length())
	return [Vector2(centre.x, centre.z), half, foot[3], _unit(flat_across), _strength(foot, 5), bool(foot[6]) if foot.size() > 6 else true]

## A foot's strength (0..1) at `index` of its array, 1 when it gives none.
static func _strength(foot: Array, index: int) -> float:
	return clampf(float(foot[index]), 0.0, 1.0) if foot.size() > index else 1.0

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
	# The caster's own box as it lies on the floor, measured along the sun and
	# across it: a long thin beam casts a long thin band, never a blob as wide
	# as the beam is long. A squarish part (most, round) keeps its round
	# shadow its longer side across, whichever way it is turned.
	var half: Vector2 = caster[1]
	var side_x := Vector2(to_ground.basis.x.x, to_ground.basis.x.z) * half.x
	var side_z := Vector2(to_ground.basis.z.x, to_ground.basis.z.z) * half.y
	var longest := maxf(side_x.length(), side_z.length())
	var across := Vector2(-along.y, along.x)
	var deep := minf(absf(side_x.dot(along)) + absf(side_z.dot(along)), longest) * 0.8
	var wide := minf(absf(side_x.dot(across)) + absf(side_z.dot(across)), longest) * 0.8
	var soft := lerpf(CAST_SOFT.x, CAST_SOFT.y, clampf(high.y - ground_y, 0.0, 2.0) * 0.5)
	return [(near + far) * 0.5, along, Vector2(near.distance_to(far) * 0.5 + deep * 0.5, wide), soft]

## How far along the floor a point's shadow falls per metre of height, in
## world space (0 with no sun).
func _sun_offset() -> Vector3:
	var sun: Variant = get_parent().get("sun")
	if not sun is DirectionalLight3D or not is_instance_valid(sun): return Vector3.ZERO
	var ray := -(sun as DirectionalLight3D).global_transform.basis.z.normalized()
	if ray.y > -0.1: return Vector3.ZERO
	var offset := Vector3(ray.x, 0, ray.z) / -ray.y
	return offset.limit_length(SUN_REACH)

## Bakes waiting floors in their order: whole floors, until BAKE_STAMPS
## stamps have baked this frame (at least one floor). Work, never time, so
## every machine bakes the same floors in the same frames.
func _bake_some() -> void:
	var started := Time.get_ticks_usec()
	var stamps := 0
	while not _to_bake.is_empty() and stamps < BAKE_STAMPS:
		var job: Array = _to_bake.pop_front()
		if not is_instance_valid(job[0]): continue
		stamps += maxi(1, _bake_ground(job[0] as Node3D, job[1], job[2], int(job[3]), str(job[4])))
	bake_usec += Time.get_ticks_usec() - started

## Bakes one of a floor's textures (KINDS), only where its stamps changed
## when it was baked before as it is now (patch()). Returns the stamps it
## took: a whole floor counts its feet and casts.
func _bake_ground(ground: Node3D, feet_list: Array, casts: Array, signature: int, kind: String) -> int:
	var rect: Rect2 = ground.get_meta(GROUND_RECT_META)
	var key := [rect, ground.get_meta(GROUND_PIECES_META), ground.get_meta(GROUND_WORN_META)]
	var entry: Dictionary = _baked.get(ground, {})
	if entry.get("key") != key: entry = {"key": key}
	var before: Dictionary = entry.get(kind, {}).get("bake", {})
	var baked := patch(rect, before, feet_list, casts if GraphicsPolicy.cast_shadows(_quality) else [], bool(key[2]), key[1])
	var stamps: int = baked.get("stamped", feet_list.size() + casts.size()) if not before.is_empty() else feet_list.size() + casts.size()
	entry[kind] = {"signature": signature, "bake": baked}
	_baked[ground] = entry
	var overlay := overlay_of(ground)
	if overlay == null: return stamps
	var still: Dictionary = entry.get("still", {}).get("bake", {})
	var moving: Dictionary = entry.get("moving", {}).get("bake", {})
	if still.is_empty() and moving.is_empty():
		_clear(ground)
		entry.erase("tiles")
		return stamps
	var look := overlay.material_override as ShaderMaterial
	var param := "shade" if kind == "still" else "moving"
	var shade: Variant = look.get_shader_parameter(param)
	if baked.is_empty(): look.set_shader_parameter(param, null)
	elif shade is ImageTexture and (shade as ImageTexture).get_size() == Vector2((baked.image as Image).get_size()):
		if baked.image != before.get("image"): (shade as ImageTexture).update(baked.image)
	else: look.set_shader_parameter(param, ImageTexture.create_from_image(baked.image))
	if (look.get_shader_parameter("has_moving") == true) == moving.is_empty(): look.set_shader_parameter("has_moving", not moving.is_empty())
	# Drawn over the tiles either texture shades, each once.
	var tiles: Array[Rect2] = []
	var seen := {}
	for tile: Rect2 in (still.get("tiles", []) as Array) + (moving.get("tiles", []) as Array):
		if seen.has(tile): continue
		seen[tile] = true
		tiles.append(tile)
	tiles.sort_custom(func(a: Rect2, b: Rect2) -> bool: return a.position.y < b.position.y or (a.position.y == b.position.y and a.position.x < b.position.x))
	if entry.get("tiles") != tiles or overlay.layers == 0:
		overlay.mesh = overlay_mesh(rect, tiles)
		entry.tiles = tiles
	overlay.layers = SHADE_LAYERS
	return stamps

## Empties a floor's overlay: it draws nothing until it bakes again.
func _clear(ground: Node3D) -> void:
	var overlay := overlay_of(ground)
	if overlay == null or overlay.layers == 0: return
	_empty_overlay(ground)
	var look := overlay.material_override as ShaderMaterial
	look.set_shader_parameter("shade", null)
	if look.get_shader_parameter("has_moving") == true:
		look.set_shader_parameter("moving", null)
		look.set_shader_parameter("has_moving", false)

## Draws the live shadows: the biggest first, equal ones by where they stand
## (never by the order they were found); then the playing parts'.
func _place_live(entries: Array) -> void:
	var to_layer := global_transform.affine_inverse()
	for entry: Array in entries:
		var foot: Array = entry[1]
		var at := to_layer * (entry[0] as Node3D).global_transform * Vector3((foot[0] as Vector2).x, float(foot[2]), (foot[0] as Vector2).y)
		entry.append([-_q(float(entry[2])), _q(at.x), _q(at.z), _q(at.y)])
	entries.sort_custom(func(a: Array, b: Array) -> bool: return _before(a[3], b[3]))
	_shown = []
	for index in range(entries.size()):
		var entry: Array = entries[index]
		var root: Node3D = entry[0]
		var seen := to_layer * root.global_transform
		var foot: Array = entry[1]
		# Where it rests now: its feet's ground in the layer's space.
		_shown.append([root, foot, seen, (seen * Vector3((foot[0] as Vector2).x, float(foot[2]), (foot[0] as Vector2).y)).y, {}])
	_place_parts()

## Sizes the MultiMesh for the live shadows and the playing things' changing
## parts after them, and draws them all.
func _place_parts() -> void:
	var to_layer := global_transform.affine_inverse()
	var playing: Array = []
	for entry: Dictionary in _mover_roots:
		if not entry.playing: continue
		for mover: Variant in (entry.root as Node3D).get_meta(MOVERS_META).movers:
			if is_instance_valid(mover): playing.append([mover, entry.stood])
	var many := _draw.multimesh
	many.instance_count = 0
	many.instance_count = _shown.size() + playing.size()
	for index in range(_shown.size()): _place(index, _shown[index][2])
	# A playing part's shadow falls along the sun as it rises (none on Low).
	var sun := to_layer.basis * _sun if GraphicsPolicy.cast_shadows(_quality) else Vector3.ZERO
	var was := {}
	for mover: Dictionary in _movers: was[mover.part] = mover.strength
	_movers.clear()
	for entry: Array in playing:
		var part: Node3D = entry[0]
		_movers.append({"part": part, "box": part.get_meta(MOVER_META).box, "ground": (to_layer * (entry[1] as Node3D).global_transform).origin.y, "sun": Vector2(sun.x, sun.z),
			"seen": to_layer * part.global_transform, "strength": was.get(part, 1.0 if part.is_visible_in_tree() else 0.0), "drawn": {}})
		_place_part(_movers.size() - 1)

## Follows every playing part (refresh()): where it stands, and its shadow
## easing in or out over PART_FADE as it shows or hides; one that stands still
## and shown as it was costs one look.
func _follow_parts(step: float) -> void:
	var to_layer := global_transform.affine_inverse()
	for index in range(_movers.size()):
		var mover: Dictionary = _movers[index]
		var part: Variant = mover.part
		# Gone with its set: gather again next frame.
		if not is_instance_valid(part) or not (part as Node3D).is_inside_tree():
			_dirty = true
			continue
		var seen := to_layer * (part as Node3D).global_transform
		var strength := move_toward(float(mover.strength), 1.0 if (part as Node3D).is_visible_in_tree() else 0.0, step / PART_FADE)
		if seen == mover.seen and strength == mover.strength: continue
		mover.seen = seen
		mover.strength = strength
		_place_part(index)

## Draws playing part `index`'s live shadow where it stands now: its
## footprint turned with it on its root's floor, as dark as it is near it
## (none once it sinks below it).
## Raised, it slides along the sun as far as it is high and softens, as dark
## as the floor's sun shadows (PART_CAST) while it is tall enough to cast one
## (CAST_HEIGHT).
func _place_part(index: int) -> void:
	var mover: Dictionary = _movers[index]
	var seen: Transform3D = mover.seen
	var box: AABB = mover.box
	var middle := box.get_center()
	var flat := _ground_foot([Vector2(middle.x, middle.z), Vector2(box.size.x, box.size.z) * 0.5, middle.y, 1.0, Vector2.RIGHT], seen)
	var half: Vector2 = flat[1]
	var reach := seen * box
	var ground: float = mover.ground
	var raised := maxf(reach.get_center().y - ground, 0.0)
	# Sunk below its floor (a bucket down a well), it has none.
	var contact := clampf(1.0 - maxf(reach.position.y - ground, 0.0) / LIFT_FADE, 0.0, 1.0) if reach.end.y >= ground else 0.0
	var cast := PART_CAST if mover.sun != Vector2.ZERO and reach.end.y - ground >= CAST_HEIGHT else 0.0
	var centre: Vector2 = (flat[0] as Vector2) + (mover.sun as Vector2) * raised * (1.0 - contact)
	var fade := lerpf(fade_for(half), lerpf(CAST_SOFT.x, CAST_SOFT.y, clampf(raised, 0.0, 2.0) * 0.5), 1.0 - contact)
	var strength := maxf(contact, cast) * float(mover.strength)
	var outer := half + Vector2.ONE * fade
	var across: Vector2 = flat[3]
	var placed := Transform3D(Basis(Vector3(across.x, 0, across.y), Vector3.UP, Vector3(-across.y, 0, across.x)) * Basis.from_scale(Vector3(outer.x, 1.0, outer.y)), Vector3(centre.x, ground + SHADE_TOP, centre.y))
	mover.drawn = {"transform": placed, "strength": strength, "half": half}
	var at := _shown.size() + index
	var many := _draw.multimesh
	many.set_instance_transform(at, placed)
	many.set_instance_custom_data(at, Color(half.x, half.y, fade, 1.0))
	many.set_instance_color(at, Color(1, 1, 1, strength))

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
	var across: Vector2 = ground_foot[3]
	var turned := Basis(Vector3(across.x, 0, across.y), Vector3.UP, Vector3(-across.y, 0, across.x))
	var placed := Transform3D(turned * Basis.from_scale(Vector3(outer.x, 1.0, outer.y)), Vector3(centre.x, ground + SHADE_TOP, centre.z))
	var strength := clampf(1.0 - (centre.y - ground) / LIFT_FADE, 0.0, 1.0)
	shown_one[4] = {"transform": placed, "strength": strength, "half": half}
	var many := _draw.multimesh
	many.set_instance_transform(index, placed)
	# A live shadow is always round: a soft blob, never a box.
	many.set_instance_custom_data(index, Color(half.x, half.y, fade, 1.0))
	many.set_instance_color(index, Color(1, 1, 1, strength * float(ground_foot[4])))

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
