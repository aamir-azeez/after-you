extends RefCounted
## Orchard skin (body): soft pink blossom petals resting on the pip, as the
## Orchard board draws it (Fruits board 4a), and petals falling round it like
## leaves from a tree. The pip keeps its own colour.
##
## The resting petals lie on the head's and the torso's surfaces (kit
## on_head, lie_on), clear of the eyes, and move with those parts.
##
## The falling petals are one mesh on the upper body, placed entirely by
## orchard_fall.gdshader. Each fades in above the head, flutters down round
## the pip (in front of the face or behind the head, then anywhere round the
## body) and fades out by the feet, then waits a moment and falls again. Every
## fall draws its own start, speed, sway, tumble, size, pink and wait from an
## integer hash of the petal, the fall's number and the pip's seed, so no two
## falls match and two pips never fall alike. Each petal falls a whole number
## of times per FALL_LOOP (30 s) and the fall's number wraps there, so the
## whole fall loops perfectly, too long a loop to notice.
##
## The shader reads the pip's own clock (one instance uniform set at the idle
## card rate, like every moving item), not the engine's running time: that
## would make calm screens redraw every frame, and this way a replay, a still
## and a live preview agree. The petals show only while that clock runs: a
## still pip, a pip under Reduce motion and a hidden one show the resting
## petals alone. fall_petal() is the shader's path in GDScript for the tests.
##
## Meshes and the falling petals' material are baked once and shared; a pip's
## clock, seed and see-through strength (the race ghost) are instance
## uniforms. Draw calls: head petals, torso petals, the falling petals.
const Kit = preload("res://presentation/kit/pip_wear_kit.gd")
const Meshes = preload("res://presentation/spirit_meshes.gd")
const Look = preload("res://presentation/spirit_look.gd")
const FALL_SHADER = preload("res://presentation/pip_wear/orchard_fall.gdshader")

const PETAL := Color("f5b8c9")
const PETAL_DEEP := Color("ee9fb6")
## A resting petal's half sizes: long, thick, wide. Big enough to read as a
## petal on a shop card.
const PETAL_SIZE := Vector3(0.072, 0.009, 0.046)
const PETAL_SEGMENTS := 8
const GAP := 0.003
## Resting petals: [direction from the part's centre, turn (radians) of the
## petal's long side]. On the head they keep away from the eyes and the top,
## where a carried seed rests.
const HEAD_PETALS := [
	[Vector3(-0.3, -0.2, 0.22), 0.5],
	[Vector3(0.2, 0.2, 0.24), -0.3],
	[Vector3(0.33, -0.1, 0.05), 1.2],
	[Vector3(-0.15, 0.2, -0.2), 0.2],
]
const TORSO_PETALS := [
	[Vector3(0.35, -0.12, 0.9), -0.4],
	[Vector3(-0.45, -0.35, 0.85), 0.9],
	[Vector3(0.75, -0.35, 0.45), 0.3],
	[Vector3(-0.8, -0.15, -0.2), -0.6],
]

## The node the falling petals are drawn by.
const FALL_NAME := "Fall"
## The node's meta naming the instance uniform that fades it (race_ghost_view.gd
## VEIL_UNIFORM): a plain see-through material can't place the petals.
const VEIL_META := &"veil_uniform"
## A falling petal's half sizes at its largest: long, cupped, wide. Smaller
## than a resting one, so it stays inside the narrowest pip view.
const FALL_SIZE := Vector3(0.06, 0.006, 0.04)
const FALL_POINTS := 8
## How many petals fall at once at most (the shader takes this many).
const FALL_PETALS := 10
## Seconds the whole fall takes to come round again: long enough that nobody
## sees it repeat. Each petal gets FALL_SLOTS.x or .y turns in it (alternate
## petals), one fall per turn.
const FALL_LOOP := 30.0
const FALL_SLOTS := Vector2i(5, 6)
## Seconds one fall takes; the rest of its turn it waits, the wait split
## before and after it at random.
const FALL_TIME := Vector2(3.4, 4.6)
## The share of falls that start in front of the head (the rest behind it),
## and how far (radians) a start turns from straight toward or away from the
## camera: that keeps it in the view beside the head.
const FALL_FRONT := 0.6
const FALL_SECTOR := 0.35
## How far round the body (radians) it drifts once below the chin, either way.
const FALL_DRIFT := 2.2
## Its sway (radians), sways per fall, turns per fall either way, rock and tip
## (radians), size (share of FALL_SIZE) and start height (metres up).
const FALL_SWAY := Vector2(0.15, 0.22)
const FALL_SWAYS := Vector2(1.0, 2.0)
const FALL_SPIN := 0.6
const FALL_ROCK := Vector2(0.3, 0.6)
const FALL_TIP := Vector2(0.2, 0.5)
const FALL_SCALE := Vector2(0.8, 1.0)
const FALL_TOP := Vector2(0.92, 0.97)
## Where it ends (metres up); the share of a fall it fades in over, and the
## height it starts fading out.
const FALL_BOTTOM := 0.1
const FALL_FADE_IN := 0.12
const FALL_FADE_OUT := 0.22
## Slower at the top and the bottom, quicker past the head.
const FALL_EASE := -0.7
## Nearest a petal's middle comes to the upright axis, and to the head and torso.
const FALL_REACH := 0.3
const FALL_CLEAR := 0.065
## How far the head may sink onto the body (a dozing pip: spirit_idle.gd
## DOZE_HEAD_SINK and its breath): the path clears the head anywhere in it.
const FALL_HEAD_SINK := 0.05
## Between these heights it drifts round the body.
const FALL_OPEN_FROM := 0.28
const FALL_OPEN_TO := 0.15
## Its dip at each sway; how far it leans up from flat, so it shows its face
## rather than its edge; its size while faded; and how much of its colour
## shows unlit, so a small petal stays bright.
const FALL_BOB := 0.01
const FALL_LEAN := 1.1
const FALL_SHRINK := 0.3
const FALL_GLOW := 0.4
## Everywhere a falling petal can be, for culling (the mesh holds only petal shapes).
const FALL_BOUNDS := AABB(Vector3(-0.5, 0.0, -0.5), Vector3(1.0, 1.12, 1.0))
## How many random values one fall draws (fall_draws).
const FALL_DRAWS := 14
## The hash's 32 bit words (the shader's uint).
const WORD := 0xFFFFFFFF

## Pips dressed so far: each gets its own seed.
static var _dressed := 0

static func wear(look: RefCounted) -> void:
	look.mesh(look.head(), Kit.cached_mesh("orchard_skin:head", _head), Kit.vertex_material())
	look.mesh(look.torso(), Kit.cached_mesh("orchard_skin:torso", _torso), Kit.vertex_material())
	var fall: MeshInstance3D = look.mesh(look.upper_body(), Kit.cached_mesh("orchard_skin:fall", _fall), Kit.cached_material("orchard_skin:fall", _fall_material))
	fall.name = FALL_NAME
	fall.custom_aabb = FALL_BOUNDS
	fall.visible = false
	fall.set_meta(VEIL_META, &"veil")
	_dressed += 1
	fall.set_instance_shader_parameter(&"fall_seed", float(pip_seed(_dressed)))
	# Shown once the pip's clock runs: never on a still, under Reduce motion
	# (its clock holds at 0) or on a hidden pip (never advanced).
	look.animate(func(_worn: RefCounted, seconds: float) -> void:
		var falling := seconds > 0.0
		if fall.visible != falling: fall.visible = falling
		if falling: fall.set_instance_shader_parameter(&"fall_clock", seconds))

## The seed the `count`th dressed pip falls with (a whole number below 65536,
## exact in the shader's float).
static func pip_seed(count: int) -> int:
	return _mix(count) & 0xFFFF

## Where falling petal `index` is at `seconds` of the pip's clock, for a pip
## of seed `pip_key` (pip_seed), seen from `camera` (upper body space), as the
## shader places it: {"frame": its transform (upper body space), "alpha": how
## faded in it is (0 while it waits)}. The same every FALL_LOOP seconds.
static func fall_petal(index: int, seconds: float, pip_key: int, camera: Vector3) -> Dictionary:
	var turns := FALL_SLOTS.x if index % 2 == 0 else FALL_SLOTS.y
	var turn_time := FALL_LOOP / turns
	var at := fposmod(seconds + turn_time * index / FALL_PETALS, FALL_LOOP)
	var fall := mini(floori(at / turn_time), turns - 1)
	var draws := fall_draws(index, fall, pip_key)
	var time := lerpf(FALL_TIME.x, minf(FALL_TIME.y, turn_time), draws[1])
	var u := (at - fall * turn_time - draws[0] * (turn_time - time)) / time
	return fall_place(draws, u, camera)

## The values one fall draws, each in [0, 1): an integer hash of the petal,
## the fall's number in the loop and the pip's seed, the same in the shader.
## [wait share, time, front, start, drift, sway, sways, sway phase, spin,
## rock, tip, size, top, pink].
static func fall_draws(index: int, fall: int, pip_key: int) -> PackedFloat32Array:
	var key := _mix(((_times(index, 2654435769) + _times(fall, 2246822507)) & WORD) ^ pip_key)
	var draws := PackedFloat32Array()
	for at in range(FALL_DRAWS): draws.append(float(_mix((key + at) & WORD) >> 8) / 16777216.0)
	return draws

## Where a fall with these draws is `u` of the way down (outside 0 to 1 it
## waits: no size, no alpha).
static func fall_place(draws: PackedFloat32Array, u: float, camera: Vector3) -> Dictionary:
	var waiting := u < 0.0 or u >= 1.0
	u = clampf(u, 0.0, 1.0)
	var w := u + FALL_EASE * sin(TAU * u) / TAU
	var sway := TAU * lerpf(FALL_SWAYS.x, FALL_SWAYS.y, draws[6]) * u + TAU * draws[7]
	var y := lerpf(lerpf(FALL_TOP.x, FALL_TOP.y, draws[12]), FALL_BOTTOM, w) + FALL_BOB * sin(2.0 * sway)
	var open := 1.0 - _smooth(FALL_OPEN_TO, FALL_OPEN_FROM, y)
	var toward := Vector2(camera.x, camera.z) if Vector2(camera.x, camera.z).length() > 0.0001 else Vector2(0, 1)
	var start := (0.0 if draws[2] < FALL_FRONT else PI) + lerpf(-FALL_SECTOR, FALL_SECTOR, draws[3])
	var angle := atan2(toward.x, toward.y) + start + lerpf(-FALL_DRIFT, FALL_DRIFT, draws[4]) * open + lerpf(FALL_SWAY.x, FALL_SWAY.y, draws[5]) * sin(sway)
	var d := Vector2(sin(angle), cos(angle))
	var head := _reach(y, d, _head_center(), _head_half(), Look.HEAD_POWER)
	var torso := _reach(y, d, Look.TORSO_CENTER, _torso_half(), Look.TORSO_POWER)
	var out := maxf(FALL_REACH, maxf(head, torso))
	var alpha := 0.0 if waiting else _smooth(0.0, FALL_FADE_IN, u) * _smooth(FALL_BOTTOM, FALL_FADE_OUT, y)
	var size := 0.0 if waiting else lerpf(FALL_SCALE.x, FALL_SCALE.y, draws[11]) * lerpf(FALL_SHRINK, 1.0, alpha)
	var spin := lerpf(-FALL_SPIN, FALL_SPIN, draws[8])
	var pose := _turn_y(angle + spin * TAU * u) * _turn_x(FALL_LEAN + lerpf(FALL_ROCK.x, FALL_ROCK.y, draws[9]) * cos(sway)) * _turn_z(lerpf(FALL_TIP.x, FALL_TIP.y, draws[10]) * sin(sway + 1.0))
	return {"frame": Transform3D(pose.scaled_local(Vector3.ONE * size), Vector3(d.x * out, y, d.y * out)), "alpha": alpha, "pink": draws[13]}

## The shader's hash of one 32 bit word (lowbias32).
static func _mix(x: int) -> int:
	x &= WORD
	x ^= x >> 16
	x = _times(x, 2146121005)
	x ^= x >> 15
	x = _times(x, 2221713035)
	x ^= x >> 16
	return x

## a times b, kept to 32 bits as the shader's uint does (in parts, so no
## 64 bit product overflows).
static func _times(a: int, b: int) -> int:
	a &= WORD
	return (a * (b & 0xFFFF) + (((a * (b >> 16)) & 0xFFFF) << 16)) & WORD

## The head the path keeps clear of, at rest or sunk, grown by FALL_CLEAR.
static func _head_center() -> Vector3:
	return Look.HEAD_CENTER - Vector3(0, FALL_HEAD_SINK * 0.5, 0)

static func _head_half() -> Vector3:
	return Look.HEAD_HALF + Vector3(0, FALL_HEAD_SINK * 0.5, 0) + Vector3.ONE * FALL_CLEAR

static func _torso_half() -> Vector3:
	return Look.TORSO_HALF + Vector3.ONE * FALL_CLEAR

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

static func _fall_material() -> Material:
	var material := ShaderMaterial.new()
	material.shader = FALL_SHADER
	var values := {
		&"loop": FALL_LOOP, &"slots": Vector2(FALL_SLOTS), &"petals": float(FALL_PETALS), &"fall_time": FALL_TIME,
		&"front": FALL_FRONT, &"sector": FALL_SECTOR, &"drift": FALL_DRIFT, &"sway_size": FALL_SWAY, &"sways": FALL_SWAYS,
		&"spin": FALL_SPIN, &"rock": FALL_ROCK, &"tip": FALL_TIP, &"scale": FALL_SCALE, &"top": FALL_TOP,
		&"bottom": FALL_BOTTOM, &"fade_in": FALL_FADE_IN, &"fade_out": FALL_FADE_OUT, &"ease": FALL_EASE,
		&"least_reach": FALL_REACH, &"open_from": FALL_OPEN_FROM, &"open_to": FALL_OPEN_TO, &"bob": FALL_BOB,
		&"lean": FALL_LEAN, &"shrink": FALL_SHRINK, &"glow": FALL_GLOW,
		&"pink": Vector3(PETAL.r, PETAL.g, PETAL.b), &"pink_deep": Vector3(PETAL_DEEP.r, PETAL_DEEP.g, PETAL_DEEP.b),
		&"head_center": _head_center(), &"head_half": _head_half(), &"head_power": Look.HEAD_POWER,
		&"torso_center": Look.TORSO_CENTER, &"torso_half": _torso_half(), &"torso_power": Look.TORSO_POWER,
	}
	for key: StringName in values: material.set_shader_parameter(key, values[key])
	return material

## The falling petals' shapes, each round its own middle, flat and a little
## cupped, narrowing to its tip; UV.x holds the petal's index (its pink is
## drawn per fall in the shader).
static func _fall() -> Mesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for index in range(FALL_PETALS):
		var first := vertices.size()
		vertices.append(Vector3(0, FALL_SIZE.y, 0))
		normals.append(Vector3.UP)
		for point in range(FALL_POINTS):
			var angle := TAU * point / FALL_POINTS
			vertices.append(Vector3(cos(angle) * FALL_SIZE.x, 0, sin(angle) * FALL_SIZE.z * (1.0 - 0.25 * cos(angle))))
			normals.append(Vector3(cos(angle) * 0.2, 1.0, sin(angle) * 0.2).normalized())
		for point in range(FALL_POINTS + 1): uvs.append(Vector2(index, 0))
		for point in range(FALL_POINTS):
			# Clockwise seen from above: the front face.
			indices.append_array(PackedInt32Array([first, first + 1 + point, first + 1 + (point + 1) % FALL_POINTS]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var made := ArrayMesh.new()
	made.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return made

static func _head() -> Mesh:
	var parts := Kit.Parts.new()
	for index in range(HEAD_PETALS.size()):
		var petal: Array = HEAD_PETALS[index]
		parts.blob_at(_colour(index), Kit.on_head(petal[0], _toward(petal[1]), PETAL_SIZE, GAP), PETAL_SEGMENTS, 2)
	return parts.commit()

static func _torso() -> Mesh:
	var parts := Kit.Parts.new()
	for index in range(TORSO_PETALS.size()):
		var petal: Array = TORSO_PETALS[index]
		parts.blob_at(_colour(index + 1), Kit.lie_on(Meshes.torso_surface(petal[0]), _toward(petal[1]), PETAL_SIZE, GAP), PETAL_SEGMENTS, 2)
	return parts.commit()

static func _colour(index: int) -> Color:
	return PETAL if index % 2 == 0 else PETAL_DEEP

## The petal's long side, turned `turn` from level, before it is laid on the surface.
static func _toward(turn: float) -> Vector3:
	return Vector3(cos(turn), sin(turn), 0.0)
