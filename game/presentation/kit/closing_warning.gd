extends RefCounted
## World kit: the one closing warning (presentation/cooperative_world.gd hosts
## one for every chapter world; never a copy). While a crossing closes (the
## snapshot's route_progress.closing: route id -> ticks left before it shuts,
## core/physical/runtime.gd CLOSING_GRACE_TICKS), a thin rim along its edges
## flashes the warning colour, on and off with the ticks left, so live play,
## the friend's replay, a memory and a replay all flash alike; Reduce motion
## holds it at a steady glow instead. Any crossing kind: a bridge's rim lies
## flat at its height, a stair's runs up its slope. Held, crank and rope
## bridges and stones all close this way, so every one warns the same.
## Presentation only.
const Primitives = preload("res://presentation/kit/primitives.gd")
## The warning colour and its glow while lit, dim and steady.
const COLOR := Color("f08a5d")
const LIT := 1.6
const DIM := 0.5
const STEADY := 1.1
## Ticks a flash stays lit, then dark: three flashes a second at 30 ticks.
const BLINK := 5
## The rim's thickness and how far over the deck it lies (m).
const WIDTH := 0.035
const LIFT := 0.02

var _world: Node3D
## Route id -> [its rim (a Node3D of bars), its own material], built on the
## route's first warning in a stage.
var _rims: Dictionary = {}

func _init(world: Node3D) -> void:
	_world = world

## A new stage: its terrain is built again, so the rims are forgotten.
func forget() -> void:
	_rims.clear()

## Each snapshot: its closing crossings (route id -> ticks left; {} for none).
func show(closing: Dictionary) -> void:
	for id: String in _rims:
		var rim: Node3D = _rims[id][0]
		if is_instance_valid(rim): rim.visible = closing.has(id)
	for id: Variant in closing:
		var entry: Array = _rim(str(id))
		if entry.is_empty(): continue
		var material: StandardMaterial3D = entry[1]
		var lit: bool = int(closing[id]) % (BLINK * 2) < BLINK
		material.emission_energy_multiplier = STEADY if _world.reduced_motion else (LIT if lit else DIM)

## The rims shown, which come and go, so the static fold keeps them whole.
func moving_nodes() -> Array:
	var nodes: Array = []
	for entry: Array in _rims.values():
		if is_instance_valid(entry[0]): nodes.append(entry[0])
	return nodes

## Route `id`'s rim, built on first use: [node, material], or [] for no such crossing.
func _rim(id: String) -> Array:
	if _rims.has(id) and is_instance_valid(_rims[id][0]): return _rims[id]
	var route := _route(id)
	if route.is_empty(): return []
	var material := Primitives.fresh_material(COLOR, 0.6)
	material.emission_enabled = true
	material.emission = COLOR
	material.emission_energy_multiplier = LIT
	var rim := Node3D.new()
	rim.name = "ClosingWarning_" + id
	_world.terrain.add_child(rim)
	var corners := _corners(route)
	for index in range(4):
		var from: Vector3 = corners[index]
		var to: Vector3 = corners[(index + 1) % 4]
		Primitives.bar_between(from, to, WIDTH, material, rim)
	_rims[id] = [rim, material]
	return _rims[id]

## The crossing's four corners in metres, round its rect, each at the height a
## walker stands there plus LIFT (a stair's rise along its axis).
static func _corners(route: Dictionary) -> Array:
	var rect: Array = route.rect_cm
	var points := [[rect[0], rect[1]], [rect[2], rect[1]], [rect[2], rect[3]], [rect[0], rect[3]]]
	var corners: Array = []
	for point: Array in points:
		var height := float(route.get("height_cm", 0))
		if route.has("axis"):
			var low := int(point[0]) == int(rect[0]) if route.axis == "x" else int(point[1]) == int(rect[1])
			height = float(route.from_height_cm if low else route.to_height_cm)
		corners.append(Vector3(float(point[0]) / 100.0, height / 100.0 + LIFT, float(point[1]) / 100.0))
	return corners

func _route(id: String) -> Dictionary:
	var definition: Dictionary = _world.chapter_definition
	for route: Dictionary in definition.get("bridges", []) + definition.get("stairs", []):
		if str(route.id) == id: return route
	return {}
