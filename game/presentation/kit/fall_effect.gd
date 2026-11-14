extends RefCounted
## A falling effect a pip can wear: small shapes (petals, leaves, snow, stars,
## drops, seed fluff) that fade in above the head, flutter down round the pip
## (in front of the face or behind the head, then anywhere round the body) and
## fade out by the feet, then wait a moment and fall again. Every fall draws
## its own start, speed, sway, tumble, size, colour and wait from an integer
## hash of the shape, the fall's number and the pip's seed, so no two falls
## match and two pips never fall alike. Each shape falls a whole number of
## times per loop and the fall's number wraps there, so the whole fall loops
## perfectly, too long a loop to notice.
##
## An art script (presentation/pip_wear/) wears one with a recipe:
##     FallEffect.wear(look, {"id": "orchard_skin", "shape": &"petal", ...})
## A recipe is a Dictionary of the fields in DEFAULTS; a field left out takes
## its default (the Orchard skin's petal fall). "id" names the recipe: its
## mesh and material are baked once under it and its values and shared by
## every pip wearing it (pip_wear_kit.gd cached_mesh and cached_material,
## released at session end). "shape" is a name in SHAPES, "size" its half sizes (long, thick,
## wide), "colors" the two colours a fall picks between; the rest are the
## shader's path values (fall_effect.gdshader, the same names).
##
## The shader places every shape from the pip's own clock (one instance
## uniform set at the idle card rate, like every moving item), not the
## engine's running time: that would make calm screens redraw every frame,
## and this way a replay, a still and a live preview agree. The shapes show
## only while that clock runs: a still pip, a pip under Reduce motion and a
## hidden one show none. fall_shape() is the shader's path in GDScript for the
## tests, and test_fall_effect.gd checks the two agree.
##
## One node, one mesh, one draw call per pip; its clock, seed and see-through
## strength (the race ghost) are instance uniforms.
const Kit = preload("res://presentation/kit/pip_wear_kit.gd")
const Look = preload("res://presentation/spirit_look.gd")
const SHADER = preload("res://presentation/kit/fall_effect.gdshader")
const FlatShapes = preload("res://presentation/kit/flat_shapes.gd")

## The node the falling shapes are drawn by.
const NODE_NAME := "Fall"
## The node's meta holding its recipe (resolved), so tests find every fall.
const RECIPE_META := &"fall_recipe"
## The node's meta naming the instance uniform that fades it (race_ghost_view.gd
## VEIL_UNIFORM): a plain see-through material can't place the shapes.
const VEIL_META := &"veil_uniform"
## The shader's instance uniforms: the pip's clock, its seed, its strength.
const CLOCK := &"fall_clock"
const SEED := &"fall_seed"
const VEIL := &"veil"

## Every field of a recipe, with the Orchard skin's petal fall as defaults.
const DEFAULTS := {
	## Names the recipe's shared mesh and material.
	"id": "",
	## A name in SHAPES, its half sizes at its largest (long, thick, wide):
	## small enough to stay inside the narrowest pip view.
	"shape": &"petal",
	"size": Vector3(0.06, 0.006, 0.04),
	## The two colours a fall picks between.
	"colors": [Color("f5b8c9"), Color("ee9fb6")],
	## How many shapes fall at once at most (the mesh holds this many).
	"count": 10,
	## Seconds the whole fall takes to come round again. Each shape gets
	## slots.x or .y turns in it (alternate shapes), one fall per turn.
	"loop": 30.0,
	"slots": Vector2i(5, 6),
	## Seconds one fall takes; the rest of its turn it waits, the wait split
	## before and after it at random.
	"fall_time": Vector2(3.4, 4.6),
	## The share of falls that start in front of the head (the rest behind
	## it), and how far (radians) a start turns from straight toward or away
	## from the camera: that keeps it in the view beside the head.
	"front": 0.6,
	"sector": 0.35,
	## How far round the body (radians) it drifts once below the chin, either way.
	"drift": 2.2,
	## Its sway (radians), sways per fall, turns per fall either way, rock and
	## tip (radians), size (share of "size") and start height (metres up).
	"sway_size": Vector2(0.15, 0.22),
	"sways": Vector2(1.0, 2.0),
	"spin": 0.6,
	"rock": Vector2(0.3, 0.6),
	"tip": Vector2(0.2, 0.5),
	"scale": Vector2(0.8, 1.0),
	"top": Vector2(0.92, 0.97),
	## Where it ends (metres up); the share of a fall it fades in over, and
	## the height it starts fading out.
	"bottom": 0.1,
	"fade_in": 0.12,
	"fade_out": 0.22,
	## Slower at the top and the bottom, quicker past the head.
	"ease": -0.7,
	## Nearest a shape's middle comes to the upright axis, and to the head and torso.
	"least_reach": 0.3,
	"clear": 0.065,
	## How far the head may sink onto the body (a dozing pip: spirit_idle.gd
	## DOZE_HEAD_SINK and its breath): the path clears the head anywhere in it.
	"head_sink": 0.05,
	## Between these heights it drifts round the body.
	"open_from": 0.28,
	"open_to": 0.15,
	## Its dip at each sway; how far it leans up from flat, so it shows its
	## face rather than its edge; its size while faded; and how much of its
	## colour shows unlit, so a small shape stays bright.
	"bob": 0.01,
	"lean": 1.1,
	"shrink": 0.3,
	"glow": 0.4,
	## Everywhere a falling shape can be, for culling.
	"bounds": AABB(Vector3(-0.5, 0.0, -0.5), Vector3(1.0, 1.12, 1.0)),
}
## The recipe fields the shader takes under the same name (uniforms() adds
## the colours and the head and torso the path keeps clear of).
const PATH_FIELDS := ["loop", "slots", "count", "fall_time", "front", "sector", "drift", "sway_size", "sways", "spin", "rock", "tip", "scale", "top", "bottom", "fade_in", "fade_out", "ease", "least_reach", "open_from", "open_to", "bob", "lean", "shrink", "glow"]

## The shapes a recipe can fall with (kit/flat_shapes.gd), each a few
## triangles, flat or a little cupped (the shader draws both sides).
const SHAPES: Array[StringName] = [&"petal", &"leaf", &"snowflake", &"star", &"raindrop", &"seed_fluff"]

## How many random values one fall draws (fall_draws): [wait share, time,
## front, start, drift, sway, sways, sway phase, spin, rock, tip, size, top,
## colour].
const DRAWS := 14
## The hash (lowbias32) and the fall key's multipliers, as the shader has them.
const HASH := [2146121005, 2221713035]
const KEY := [2654435769, 2246822507]
## The hash's 32 bit words (the shader's uint).
const WORD := 0xFFFFFFFF

## Pips dressed so far: each gets its own seed.
static var _dressed := 0

## Puts the fall `overrides` names (a recipe: DEFAULTS' fields) on the pip
## `look` dresses, round its upper body. Returns its node.
static func wear(look: RefCounted, overrides: Dictionary) -> MeshInstance3D:
	var made := recipe(overrides)
	var fall: MeshInstance3D = look.mesh(look.upper_body(), mesh(made), material(made))
	fall.name = NODE_NAME
	fall.custom_aabb = made.bounds
	fall.visible = false
	fall.set_meta(VEIL_META, VEIL)
	fall.set_meta(RECIPE_META, made)
	_dressed += 1
	fall.set_instance_shader_parameter(SEED, float(pip_seed(_dressed)))
	# Shown once the pip's clock runs: never on a still, under Reduce motion
	# (its clock holds at 0) or on a hidden pip (never advanced).
	look.animate(func(_worn: RefCounted, seconds: float) -> void:
		var falling := seconds > 0.0
		if fall.visible != falling: fall.visible = falling
		if falling: fall.set_instance_shader_parameter(CLOCK, seconds))
	return fall

## DEFAULTS with `overrides` over them. An unknown field, an unknown shape or
## no id is an error (the defaults stand in).
static func recipe(overrides: Dictionary) -> Dictionary:
	var made := DEFAULTS.duplicate()
	for field: String in overrides:
		if DEFAULTS.has(field): made[field] = overrides[field]
		else: push_error("Fall recipe field '%s' is not one of DEFAULTS" % field)
	if not SHAPES.has(StringName(made.shape)):
		push_error("Fall recipe shape '%s' is not one of SHAPES" % made.shape)
		made.shape = DEFAULTS.shape
	if str(made.id).is_empty(): push_error("A fall recipe needs an id")
	return made

## The recipe's shared mesh: `count` copies of its shape, UV.x holding each
## copy's index (its colour and path are drawn per fall in the shader).
static func mesh(made: Dictionary) -> Mesh:
	return Kit.cached_mesh(_key(made), func() -> Mesh: return _bake(made))

## The recipe's shared material.
static func material(made: Dictionary) -> Material:
	return Kit.cached_material(_key(made), func() -> Material:
		var shading := ShaderMaterial.new()
		shading.shader = SHADER
		var values := uniforms(made)
		for key: StringName in values: shading.set_shader_parameter(key, values[key])
		return shading)

## The cache key: the id and the recipe's own values, so two recipes under
## one id never share a mesh or material.
static func _key(made: Dictionary) -> String:
	return "fall:%s:%d" % [made.id, made.hash()]

## Every uniform the material sets for the recipe, by its shader name.
static func uniforms(made: Dictionary) -> Dictionary:
	var values := {}
	for field: String in PATH_FIELDS:
		var value: Variant = made[field]
		if value is Vector2i: value = Vector2(value)
		elif value is int: value = float(value)
		values[StringName(field)] = value
	var colors: Array = made.colors
	values[&"color_a"] = Vector3(colors[0].r, colors[0].g, colors[0].b)
	values[&"color_b"] = Vector3(colors[1].r, colors[1].g, colors[1].b)
	values[&"head_center"] = head_center(made)
	values[&"head_half"] = head_half(made)
	values[&"head_power"] = Look.HEAD_POWER
	values[&"torso_center"] = Look.TORSO_CENTER
	values[&"torso_half"] = torso_half(made)
	values[&"torso_power"] = Look.TORSO_POWER
	return values

## The seed the `count`th dressed pip falls with (a whole number below 65536,
## exact in the shader's float).
static func pip_seed(count: int) -> int:
	return _mix(count) & 0xFFFF

# --- The shader's path in GDScript (tests) ----------------------------------

## Where falling shape `index` is at `seconds` of the pip's clock, for a pip
## of seed `pip_key` (pip_seed), seen from `camera` (upper body space), as the
## shader places it: {"frame": its transform (upper body space), "alpha": how
## faded in it is (0 while it waits), "tint": its colour}. The same every
## loop seconds.
static func fall_shape(made: Dictionary, index: int, seconds: float, pip_key: int, camera: Vector3) -> Dictionary:
	var slots: Vector2i = made.slots
	var loop: float = made.loop
	var turns := slots.x if index % 2 == 0 else slots.y
	var turn_time := loop / turns
	var at := fposmod(seconds + turn_time * index / float(made.count), loop)
	var fall := mini(floori(at / turn_time), turns - 1)
	var draws := fall_draws(index, fall, pip_key)
	var fall_time: Vector2 = made.fall_time
	var time := lerpf(fall_time.x, minf(fall_time.y, turn_time), draws[1])
	var u := (at - fall * turn_time - draws[0] * (turn_time - time)) / time
	return fall_place(made, draws, u, camera)

## The values one fall draws, each in [0, 1): an integer hash of the shape,
## the fall's number in the loop and the pip's seed, the same in the shader.
static func fall_draws(index: int, fall: int, pip_key: int) -> PackedFloat32Array:
	var key := _mix(((_times(index, KEY[0]) + _times(fall, KEY[1])) & WORD) ^ pip_key)
	var draws := PackedFloat32Array()
	for at in range(DRAWS): draws.append(float(_mix((key + at) & WORD) >> 8) / 16777216.0)
	return draws

## Where a fall with these draws is `u` of the way down (outside 0 to 1 it
## waits: no size, no alpha).
static func fall_place(made: Dictionary, draws: PackedFloat32Array, u: float, camera: Vector3) -> Dictionary:
	var waiting := u < 0.0 or u >= 1.0
	u = clampf(u, 0.0, 1.0)
	var w := u + float(made.ease) * sin(TAU * u) / TAU
	var sways: Vector2 = made.sways
	var top: Vector2 = made.top
	var bottom: float = made.bottom
	var sway := TAU * lerpf(sways.x, sways.y, draws[6]) * u + TAU * draws[7]
	var y := lerpf(lerpf(top.x, top.y, draws[12]), bottom, w) + float(made.bob) * sin(2.0 * sway)
	var open := 1.0 - _smooth(made.open_to, made.open_from, y)
	var toward := Vector2(camera.x, camera.z) if Vector2(camera.x, camera.z).length() > 0.0001 else Vector2(0, 1)
	var sector: float = made.sector
	var drift: float = made.drift
	var sway_size: Vector2 = made.sway_size
	var start := (0.0 if draws[2] < float(made.front) else PI) + lerpf(-sector, sector, draws[3])
	var angle := atan2(toward.x, toward.y) + start + lerpf(-drift, drift, draws[4]) * open + lerpf(sway_size.x, sway_size.y, draws[5]) * sin(sway)
	var d := Vector2(sin(angle), cos(angle))
	var head_power := Look.HEAD_POWER
	var torso_center := Look.TORSO_CENTER
	var torso_power := Look.TORSO_POWER
	var out_to := maxf(made.least_reach, maxf(_reach(y, d, head_center(made), head_half(made), head_power), _reach(y, d, torso_center, torso_half(made), torso_power)))
	var fade := 0.0 if waiting else _smooth(0.0, made.fade_in, u) * _smooth(bottom, made.fade_out, y)
	var scale: Vector2 = made.scale
	var size := 0.0 if waiting else lerpf(scale.x, scale.y, draws[11]) * lerpf(made.shrink, 1.0, fade)
	var spin: float = made.spin
	var rock: Vector2 = made.rock
	var tip: Vector2 = made.tip
	var turning := lerpf(-spin, spin, draws[8])
	var pose := _turn_y(angle + turning * TAU * u) * _turn_x(float(made.lean) + lerpf(rock.x, rock.y, draws[9]) * cos(sway)) * _turn_z(lerpf(tip.x, tip.y, draws[10]) * sin(sway + 1.0))
	var tint: Color = (made.colors[0] as Color).lerp(made.colors[1], draws[13])
	return {"frame": Transform3D(pose.scaled_local(Vector3.ONE * size), Vector3(d.x * out_to, y, d.y * out_to)), "alpha": fade, "tint": tint}

## The head the path keeps clear of, at rest or sunk, grown by the clearance.
static func head_center(made: Dictionary) -> Vector3:
	return Look.HEAD_CENTER - Vector3(0, float(made.head_sink) * 0.5, 0)

static func head_half(made: Dictionary) -> Vector3:
	return Look.HEAD_HALF + Vector3(0, float(made.head_sink) * 0.5, 0) + Vector3.ONE * float(made.clear)

static func torso_half(made: Dictionary) -> Vector3:
	return Look.TORSO_HALF + Vector3.ONE * float(made.clear)

## The shader's hash of one 32 bit word (lowbias32).
static func _mix(x: int) -> int:
	x &= WORD
	x ^= x >> 16
	x = _times(x, HASH[0])
	x ^= x >> 15
	x = _times(x, HASH[1])
	x ^= x >> 16
	return x

## a times b, kept to 32 bits as the shader's uint does (in parts, so no
## 64 bit product overflows).
static func _times(a: int, b: int) -> int:
	a &= WORD
	return (a * (b & 0xFFFF) + (((a * (b >> 16)) & 0xFFFF) << 16)) & WORD

## GLSL's smoothstep (edges in order).
static func _smooth(from: float, to: float, x: float) -> float:
	var t := clampf((x - from) / (to - from), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

## The shader's reach(): how far out from the upright axis the rounded box
## reaches at height y in direction d, 0 above or below it.
static func _reach(y: float, d: Vector2, center: Vector3, half: Vector3, power: float) -> float:
	var k := 1.0 - pow(absf((y - center.y) / half.y), power)
	if k <= 0.0: return 0.0
	return pow(k, 1.0 / power) / pow(pow(absf(d.x / half.x), power) + pow(absf(d.y / half.z), power), 1.0 / power)

static func _turn_y(a: float) -> Basis:
	return Basis(Vector3(cos(a), 0, -sin(a)), Vector3(0, 1, 0), Vector3(sin(a), 0, cos(a)))

static func _turn_x(a: float) -> Basis:
	return Basis(Vector3(1, 0, 0), Vector3(0, cos(a), sin(a)), Vector3(0, -sin(a), cos(a)))

static func _turn_z(a: float) -> Basis:
	return Basis(Vector3(cos(a), sin(a), 0), Vector3(-sin(a), cos(a), 0), Vector3(0, 0, 1))

# --- Shapes -----------------------------------------------------------------

## One shape round its own middle, lying flat (face up): the shared flat shape
## kit's (kit/flat_shapes.gd), which the trails draw with too.
static func shape(name: StringName, size: Vector3) -> Dictionary:
	return FlatShapes.shape(name, size)

static func _bake(made: Dictionary) -> Mesh:
	var one := shape(made.shape, made.size)
	var single: PackedVector3Array = one.vertices
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for index in range(int(made.count)):
		var first := vertices.size()
		vertices.append_array(single)
		normals.append_array(one.normals)
		for point in range(single.size()): uvs.append(Vector2(index, 0))
		for corner: int in one.indices: indices.append(first + corner)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var made_mesh := ArrayMesh.new()
	made_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return made_mesh
