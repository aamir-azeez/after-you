extends RefCounted
## Trails a pip can wear (the Trail slot, Pollen trails board 2026-11-12):
## small flat marks left on the floor behind a walking pip. An art script
## (presentation/pip_wear/) wears one with a recipe:
##     TrailKit.wear(look, {"id": "leaves", "shape": &"leaf", ...})
## A recipe is a Dictionary of DEFAULTS' fields; "shape" is a name in
## kit/flat_shapes.gd (the falling effect's shape library), sizes and drift are
## in pip widths (the head's width) as the board gives them.
##
## The rules the board sets, all here:
## - Marks come only while the pip moves and stop the moment it stands; each
##   fades to nothing over its own life (0.8 s at most), so the floor is clear
##   soon after. No ribbon: one mark at a time, alternating under each foot.
## - At most MAX_MARKS live per pip (twelve for a pair); a new mark takes the
##   oldest one's place.
## - At most OPACITY strong, unlit, flat on the floor just above it (LIFT),
##   writing no depth and drawn before the pair tags (RENDER_PRIORITY), so pads,
##   floor letters, stand spots and tags stay on top of it.
## - Reduce motion: no trail at all.
## - The same walk makes the same marks: a mark is dropped each time the pip
##   has walked one spacing (the recipe's interval at the game's walking
##   speed), at the exact point along its path, whatever the frame rate, and
##   its look (side, turn, drift, colour) comes from an integer hash of its
##   number and the pip's slot. So the friend's memory and every replay of a
##   turn draw the trail the turn drew. A placement (a replay seek, a reset)
##   starts the count again.
## - Nothing runs while the pip stands with no mark left: the step returns at
##   once and the node is hidden.
## In a picture of a pip (any place but the world: Wardrobe cards, room and
## result pages, name chips) there is no walk, so a few still marks stand
## beside it instead (SAMPLE), the way the board's cards draw it.
##
## One node per pip: a MultiMeshInstance3D of MAX_MARKS instances of the
## recipe's shape (its mesh baked once per recipe) with the one shared trail
## material (kit/trail.gdshader); per pip values are instance uniforms, per
## mark values the instance's transform and custom data, written only when a
## mark is dropped. Cached meshes and the material are released at session end
## (kit/pip_wear_kit.gd).
const Kit = preload("res://presentation/kit/pip_wear_kit.gd")
const FlatShapes = preload("res://presentation/kit/flat_shapes.gd")
const FallEffect = preload("res://presentation/kit/fall_effect.gd")
const Look = preload("res://presentation/spirit_look.gd")
const Simulation = preload("res://core/simulation.gd")
const PipOutfit = preload("res://presentation/pip_outfit.gd")
const SHADER = preload("res://presentation/kit/trail.gdshader")

const NODE_NAME := "Trail"
## The node's meta holding its recipe (resolved), so tests find every trail,
## and the one holding its Walk (a walking pip's: tests read its marks there,
## since a GPU-less run keeps no instance data).
const RECIPE_META := &"trail_recipe"
const WALK_META := &"trail_walk"
## The node's meta naming the instance uniform that fades it (race_ghost_view.gd).
const VEIL_META := &"veil_uniform"
const VEIL := &"veil"
const CLOCK := &"trail_clock"
## A pip width (the head's width), metres: the board's unit.
const PIP_WIDTH := Look.HEAD_HALF.x * 2.0
const MAX_MARKS := 6
const OPACITY := 0.38
## Metres above the floor the pip stands on: over the floor's lines (6 mm),
## under the pair tags (9.5 mm), stand spots and pads.
const LIFT := 0.0085
## Drawn before the pair tags (render priority -1).
const RENDER_PRIORITY := -2
## The game's walking speed, metres a second (core/simulation.gd: centimetres
## a tick at its tick rate), which turns a recipe's interval into a spacing.
const WALK_SPEED := Simulation.MOVE_PER_TICK * Simulation.TICK_RATE / 100.0
## Each mark sits this far to one side of the path, alternating (half the
## feet's spread, spirit_look.gd FOOT_SPREAD).
const SIDE := Look.FOOT_SPREAD * 0.5
## After a placement, the first mark comes once the pip has walked this share
## of a spacing.
const FIRST_AT := 0.25
## A step longer than this (metres) is a placement, not a walk: no marks
## along it.
const JUMP := 1.2
## A margin round the live marks for culling (metres).
const MARGIN := 0.2

## Every field of a recipe (the Leaves trail's values as defaults).
const DEFAULTS := {
	## Names the recipe's shared mesh.
	"id": "",
	## A name in kit/flat_shapes.gd NAMES, and its width (pip widths).
	"shape": &"leaf",
	"width": 0.1,
	## The two colours a mark picks between.
	"colors": [Color("af895a"), Color("d3a66c")],
	## Seconds between marks at walking speed, and a mark's life (seconds).
	"interval": 0.4,
	"life": 0.8,
	## How far a mark drifts over the floor (pip widths a second) and turns
	## (degrees a second).
	"drift": 0.06,
	"spin": 20.0,
	## How far (radians) a mark's first turn strays either way from upright
	## (the shape's top away from the camera): TAU for any way.
	"turn": PI,
}

## Still marks beside a pictured pip (its own space, metres): where, how
## faded (1 full), and its first turn. A row behind it on the view's left at
## foot height, fading as it goes, as the board's cards draw it; a narrow
## view shows the nearest few, a wide card the whole row.
const SAMPLE := [
	[Vector3(-0.36, 0.05, 0.05), 1.0, 0.3],
	[Vector3(-0.53, 0.13, 0.03), 0.85, -0.4],
	[Vector3(-0.70, 0.05, 0.01), 0.7, 0.6],
	[Vector3(-0.87, 0.13, -0.01), 0.55, -0.2],
	[Vector3(-1.04, 0.05, -0.03), 0.4, 0.4],
]
## Sample marks are drawn this much bigger than walking ones, so a card's
## small pip shows them as the board does.
const SAMPLE_SCALE := 1.5

## Puts the trail `overrides` names (a recipe) on the pip `look` dresses.
## Returns its node.
static func wear(look: RefCounted, overrides: Dictionary) -> MultiMeshInstance3D:
	var made := recipe(overrides)
	var node := MultiMeshInstance3D.new()
	node.name = NODE_NAME
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.material_override = material()
	var marks := MultiMesh.new()
	marks.transform_format = MultiMesh.TRANSFORM_3D
	marks.use_custom_data = true
	marks.mesh = mesh(made)
	marks.instance_count = MAX_MARKS
	node.multimesh = marks
	node.set_meta(RECIPE_META, made)
	node.set_meta(VEIL_META, VEIL)
	var colors: Array = made.colors
	node.set_instance_shader_parameter(&"trail_life", float(made.life))
	node.set_instance_shader_parameter(&"trail_drift", float(made.drift) * PIP_WIDTH)
	node.set_instance_shader_parameter(&"trail_spin", deg_to_rad(float(made.spin)))
	node.set_instance_shader_parameter(&"trail_color_a", _raw(colors[0]))
	node.set_instance_shader_parameter(&"trail_color_b", _raw(colors[1]))
	look.attach(look.root(), node)
	if look.place() != PipOutfit.WORLD:
		_sample(node, made)
		return node
	node.top_level = true
	node.global_transform = Transform3D.IDENTITY
	node.visible = false
	var walk := Walk.new(node, made)
	node.set_meta(WALK_META, walk)
	look.travel(func(worn: RefCounted, at: Vector3, delta: float, reduced: bool) -> void: walk.step(at, delta, reduced, worn.slot_seed()))
	look.on_reset(func(_worn: RefCounted) -> void: walk.clear())
	return node

## DEFAULTS with `overrides` over them. An unknown field, an unknown shape or
## no id is an error (the defaults stand in).
static func recipe(overrides: Dictionary) -> Dictionary:
	var made := DEFAULTS.duplicate()
	for field: String in overrides:
		if DEFAULTS.has(field): made[field] = overrides[field]
		else: push_error("Trail recipe field '%s' is not one of DEFAULTS" % field)
	if not FlatShapes.NAMES.has(StringName(made.shape)):
		push_error("Trail recipe shape '%s' is not a flat shape" % made.shape)
		made.shape = DEFAULTS.shape
	if str(made.id).is_empty(): push_error("A trail recipe needs an id")
	return made

## Metres the pip walks between marks.
static func spacing(made: Dictionary) -> float:
	return float(made.interval) * WALK_SPEED

## The recipe's shared mesh: one mark, its width across.
static func mesh(made: Dictionary) -> Mesh:
	return Kit.cached_mesh("trail:%s:%d" % [made.id, made.hash()], func() -> Mesh:
		var half := float(made.width) * PIP_WIDTH * 0.5
		var one := FlatShapes.shape(made.shape, Vector3(half, 0.0, half))
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = one.vertices
		arrays[Mesh.ARRAY_NORMAL] = one.normals
		arrays[Mesh.ARRAY_INDEX] = one.indices
		var made_mesh := ArrayMesh.new()
		made_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return made_mesh)

## The one material every trail draws with.
static func material() -> Material:
	return Kit.cached_material("trail", func() -> Material:
		var shading := ShaderMaterial.new()
		shading.shader = SHADER
		shading.set_shader_parameter(&"opacity", OPACITY)
		shading.render_priority = RENDER_PRIORITY
		return shading)

## Mark `number`'s look for a pip of `pip_seed`: {"side" (metres, alternating),
## "turn" (its first turn), "heading" (its drift's), "tint" (0 or 1: which
## colour)}, from an integer hash (kit/fall_effect.gd fall_draws, the same in
## every run).
static func mark_look(made: Dictionary, number: int, pip_seed: int) -> Dictionary:
	return Walk.mark_look(made, number, pip_seed)

## The still marks of a pictured pip (SAMPLE), standing up to face the view.
static func _sample(node: MultiMeshInstance3D, made: Dictionary) -> void:
	var marks := node.multimesh
	marks.visible_instance_count = SAMPLE.size()
	var upright := Basis(Vector3.RIGHT, PI * 0.5).scaled(Vector3.ONE * SAMPLE_SCALE)
	var life := float(made.life)
	for index in range(SAMPLE.size()):
		var spot: Array = SAMPLE[index]
		marks.set_instance_transform(index, Transform3D(upright, spot[0]))
		# Its birth puts it `faded` of the way through its fade at clock 0.
		marks.set_instance_custom_data(index, Color(-(1.0 - float(spot[1])) * life, float(spot[2]), TAU * index / SAMPLE.size(), float(index % 2)))
	node.set_instance_shader_parameter(&"trail_drift", 0.0)

## A palette colour as the shader takes it (as baked vertex colours are).
static func _raw(color: Color) -> Vector3:
	return Vector3(color.r, color.g, color.b)


## One pip's walking trail: where it last was, how far it has walked since its
## last mark, its own clock and its marks.
class Walk:
	extends RefCounted
	var node: MultiMeshInstance3D
	var made: Dictionary
	var pip_key := 0
	var gap := 1.0
	var placed := false
	var last := Vector3.ZERO
	var walked := 0.0
	var clock := 0.0
	var number := 0
	## When the last mark fades, by the clock; marks live while clock < this.
	var live_until := -1.0
	## What each instance was last given (its place and custom data), kept
	## here too for the bounds and the tests.
	var spots := PackedVector3Array()
	var customs := PackedColorArray()

	func _init(trail: MultiMeshInstance3D, wanted: Dictionary) -> void:
		node = trail
		made = wanted
		gap = maxf(0.05, float(wanted.interval) * WALK_SPEED)
		clear()

	static func mark_look(wanted: Dictionary, count: int, pip_seed: int) -> Dictionary:
		var draws := FallEffect.fall_draws(count, 0, pip_seed)
		return {
			"side": -SIDE if count % 2 == 0 else SIDE,
			"turn": lerpf(-float(wanted.turn), float(wanted.turn), draws[0]),
			"heading": draws[1] * TAU,
			"tint": 0.0 if draws[2] < 0.5 else 1.0,
		}

	## Whether a mark still shows.
	func live() -> bool:
		return clock < live_until

	## The marks showing now, oldest first: [place, custom data] each.
	func live_marks() -> Array:
		var found: Array = []
		for index in range(spots.size()):
			var age := clock - customs[index].r
			if age >= 0.0 and age <= float(made.life): found.append([spots[index], customs[index]])
		found.sort_custom(func(a: Array, b: Array) -> bool: return a[1].r < b[1].r)
		return found

	## One frame: the pip's feet are `at` (global), `delta` seconds on;
	## `pip_seed` its slot's (PipOutfit slot_seed).
	func step(at: Vector3, delta: float, reduced: bool, pip_seed: int = 0) -> void:
		pip_key = pip_seed
		if reduced:
			if placed or live(): clear()
			return
		if not placed:
			placed = true
			last = at
			walked = gap * (1.0 - FIRST_AT)
			return
		var moved := Vector2(at.x - last.x, at.z - last.z)
		var distance := moved.length()
		if distance == 0.0 and not live(): return
		clock += maxf(delta, 0.0)
		if distance > JUMP:
			last = at
			walked = gap * (1.0 - FIRST_AT)
		elif distance > 0.0:
			var heading := moved / distance
			var from := last
			var done := 0.0
			while walked + (distance - done) >= gap:
				done += gap - walked
				walked = 0.0
				var t := done / distance
				_drop(from.lerp(at, t), heading, clock - delta * (1.0 - t))
			walked += distance - done
			last = at
		if live(): node.set_instance_shader_parameter(CLOCK, clock)
		elif node.visible: node.visible = false

	## A placement: every mark goes and the count starts again.
	func clear() -> void:
		placed = false
		walked = 0.0
		number = 0
		live_until = -1.0
		spots.clear()
		customs.clear()
		for index in range(MAX_MARKS): node.multimesh.set_instance_custom_data(index, Color(-1000.0, 0, 0, 0))
		node.visible = false

	func _drop(point: Vector3, heading: Vector2, birth: float) -> void:
		var look := mark_look(made, number, pip_key)
		var across := Vector2(-heading.y, heading.x) * float(look.side)
		var spot := Vector3(point.x + across.x, point.y + LIFT, point.z + across.y)
		var index := number % MAX_MARKS
		var custom := Color(birth, float(look.turn), float(look.heading), float(look.tint))
		node.multimesh.set_instance_transform(index, Transform3D(Basis.IDENTITY, spot))
		node.multimesh.set_instance_custom_data(index, custom)
		if spots.size() < MAX_MARKS:
			spots.append(spot)
			customs.append(custom)
		else:
			spots[index] = spot
			customs[index] = custom
		number += 1
		live_until = maxf(live_until, birth + float(made.life))
		var bounds := AABB(spots[0], Vector3.ZERO)
		for each: Vector3 in spots: bounds = bounds.expand(each)
		node.custom_aabb = bounds.grow(MARGIN)
		node.set_instance_shader_parameter(CLOCK, clock)
		if not node.visible: node.visible = true
