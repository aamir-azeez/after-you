extends RefCounted
## World kit: the marsh fog round fog lanterns (rules 16's fog_lantern block,
## a lever in the "lantern" style), in one of its styles (content/dressing/
## prop_styles.gd "fog", the dressing's pick; "none" builds nothing).
##
##   "mist": soft banks lying low on the floors, drifting a little: long flat
##       blots of haze (kit/soft_mist.gd) that overlap into banks, in two
##       layers, one draw for the whole stage (a MultiMesh). A lit lantern
##       clears every blot within CLEAR of it.
##
## Fog is only drawing. It lies on floors alone, never on a crossing, a stair
## or water: every blot's whole card, wherever its drift takes it, stays on its
## floor and KEEP clear of every crossing's and stair's rectangle and of every
## control, pad and goal, so no gate, gap, stair or water is ever hidden. It
## stays under a pip's knees (TOP). Built once per stage; present() rewrites
## the blots only when a lantern changes, drift() moves them a little.
const SoftMist = preload("res://presentation/kit/soft_mist.gd")
const STYLES := ["mist"]
const COLOR := Color(0.96, 0.97, 0.96, 0.68)
## Blots this far apart along x and z (m), this long (x) and deep (z) at
## most, the two layers' heights over their floor, and the highest.
const STEP := 0.62
const ROW := 0.46
const LENGTH := 1.5
const DEPTH := 0.82
const LAYERS := [0.07, 0.15]
const TOP := 0.22
## The sizes a blot may shrink to (shares of its full card) to fit.
const SHARES := [1.0, 0.7, 0.5]
## How far a blot drifts each way (m), and how slowly (radians a second).
const DRIFT := 0.12
const DRIFT_RATE := 0.16
## Where the fog lies: a slow wave over the marsh (bank()) above BANK_EDGE,
## so it gathers in banks with clear gaps between; GAPS of the blots in a
## bank are left out so its edge is ragged.
const BANK_EDGE := -0.35
const GAPS := 0.08
## Room kept clear round crossings, stairs and spots (m), and the lit
## lantern's clear radius.
const KEEP := 0.45
const CLEAR := 2.6

var node: MultiMeshInstance3D
var _puffs: Array[Transform3D] = []
var _lanterns: Dictionary = {}
var _lit: Dictionary = {}
## Per blot, whether a lit lantern clears it (what the MultiMesh shows).
var _cleared: Array[bool] = []

## Fog in `style` over `view`'s floors (a stage plan in cm, as the worlds
## read it) under `parent`, round `lanterns` {lever id: position (m)}; null
## for "none" or no lantern.
static func build(fog_style: String, view: Dictionary, lanterns: Dictionary, parent: Node3D) -> RefCounted:
	if fog_style not in STYLES or lanterns.is_empty(): return null
	var fog: RefCounted = load("res://presentation/kit/fog.gd").new()
	fog._make(view, lanterns, parent)
	return fog

## Clears the blots round the lanterns `levers` (the snapshot's) shows lit.
func present(levers: Dictionary) -> void:
	var lit: Dictionary = {}
	for id: String in _lanterns: lit[id] = bool(levers.get(id, false))
	if lit == _lit: return
	_lit = lit
	for index in range(_puffs.size()):
		var at := _puffs[index].origin
		var cleared := false
		for id: String in _lanterns:
			if lit[id] and Vector2(at.x, at.z).distance_to(Vector2(_lanterns[id].x, _lanterns[id].z)) < CLEAR: cleared = true
		_cleared[index] = cleared
		node.multimesh.set_instance_transform(index, _puffs[index] if not cleared else Transform3D(Basis().scaled(Vector3.ZERO), at))

## The banks' slow drift at `seconds` on the world's clock: each blot sways
## within DRIFT of its rest, which every keep-clear rule already allows for.
func drift(seconds: float) -> void:
	for index in range(_puffs.size()):
		if _cleared[index]: continue
		var rest := _puffs[index]
		var phase := float(index) * 1.7
		var offset := Vector3(sin(seconds * DRIFT_RATE + phase) * DRIFT, 0, cos(seconds * DRIFT_RATE * 0.7 + phase) * DRIFT * 0.4)
		node.multimesh.set_instance_transform(index, Transform3D(rest.basis, rest.origin + offset))

## The blots' rest places (m), for tests.
func puffs() -> Array[Transform3D]:
	return _puffs

## Where the blots a lit lantern has not cleared rest (m), for tests.
func shown() -> Array[Vector3]:
	var found: Array[Vector3] = []
	for index in range(_puffs.size()):
		if not _cleared[index]: found.append(_puffs[index].origin)
	return found

func _make(view: Dictionary, lanterns: Dictionary, parent: Node3D) -> void:
	_lanterns = lanterns
	var keep: Array[Rect2] = []
	for route: Dictionary in view.get("bridges", []) + view.get("stairs", []): keep.append(_rect(route.rect_cm).grow(KEEP))
	var spots: Array = []
	for field: String in ["levers", "controls", "pressure_pads"]:
		for spot: Dictionary in view.get(field, []): spots.append(spot)
	if view.has("goal"): spots.append(view.goal)
	var tints: Array[Color] = []
	for island: Dictionary in view.get("islands", []):
		var whole := _rect(island.rect_cm)
		var y := float(island.get("height_cm", 0)) / 100.0
		var x := whole.position.x + 0.3
		var column := 0
		while x <= whole.end.x - 0.3:
			var z := whole.position.y + 0.25 + (ROW * 0.5 if column % 2 else 0.0)
			var row := 0
			while z <= whole.end.y - 0.25:
				var at := Vector2(x, z)
				var noise := fposmod(sin(x * 12.9898 + z * 78.233) * 43758.5453, 1.0)
				var full := Vector2(LENGTH * (0.75 + 0.25 * noise), DEPTH * (0.8 + 0.2 * fposmod(noise * 7.31, 1.0)))
				# Fog always gathers round an unlit lantern, so lighting one shows.
				var wave := bank(at) + (1.5 if lanterns.values().any(func(lamp: Vector3) -> bool: return at.distance_to(Vector2(lamp.x, lamp.z)) < CLEAR) else 0.0)
				var clear := false
				var size := full
				# The whole card, wherever it drifts, stays on its floor and
				# KEEP clear of every crossing, stair and spot; where a long
				# card does not fit (a small floor, a crowded corner) a
				# shorter one may.
				for share: float in SHARES:
					if clear or wave <= BANK_EDGE or noise < GAPS: break
					size = full * share
					var card := Rect2(at - size * 0.5, size).grow_individual(DRIFT, DRIFT * 0.4, DRIFT, DRIFT * 0.4)
					clear = whole.encloses(card)
					clear = clear and not keep.any(func(rect: Rect2) -> bool: return rect.intersects(card))
					clear = clear and not spots.any(func(spot: Dictionary) -> bool: return _distance(card, Vector2(float(spot.position_cm[0]), float(spot.position_cm[1])) / 100.0) < float(spot.get("radius_cm", 28)) / 100.0 + KEEP)
				if clear:
					var layer: float = LAYERS[(column + row) % LAYERS.size()]
					_puffs.append(Transform3D(Basis().scaled(Vector3(size.x, 1.0, size.y)), Vector3(x, y + layer, z)))
					tints.append(Color(1, 1, 1, clampf((wave - BANK_EDGE) / 1.1, 0.35, 1.0) * (0.75 + 0.25 * fposmod(noise * 3.17, 1.0))))
				z += ROW
				row += 1
			x += STEP
			column += 1
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	var card := PlaneMesh.new()
	card.size = Vector2.ONE
	multimesh.mesh = card
	multimesh.instance_count = _puffs.size()
	_cleared.resize(_puffs.size())
	_cleared.fill(false)
	for index in range(_puffs.size()):
		multimesh.set_instance_transform(index, _puffs[index])
		multimesh.set_instance_color(index, tints[index])
	node = MultiMeshInstance3D.new()
	node.name = "MarshFog"
	node.multimesh = multimesh
	node.material_override = SoftMist.look(COLOR, true)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)

## The fog's wave at a point (m): above BANK_EDGE the fog lies there.
static func bank(at: Vector2) -> float:
	return sin(at.x * 0.85 + 0.6) + sin(at.y * 1.3 + at.x * 0.35 + 1.1)

## How far `point` lies from `rect` (0 inside).
static func _distance(rect: Rect2, point: Vector2) -> float:
	return point.distance_to(Vector2(clampf(point.x, rect.position.x, rect.end.x), clampf(point.y, rect.position.y, rect.end.y)))

static func _rect(cm: Array) -> Rect2:
	return Rect2(float(cm[0]) / 100.0, float(cm[1]) / 100.0, float(int(cm[2]) - int(cm[0])) / 100.0, float(int(cm[3]) - int(cm[1])) / 100.0)
