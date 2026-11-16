extends RefCounted
## World kit: the marsh fog round fog lanterns (rules 16's fog_lantern block,
## a lever in the "lantern" style), in one of its styles (content/dressing/
## prop_styles.gd "fog", the dressing's pick; "none" builds nothing).
##
##   "mist": low soft puffs lying on the floors, one draw for the whole stage
##       (a MultiMesh). A lit lantern clears every puff within CLEAR of it.
##
## Fog is only drawing. It lies on floors alone, never on a crossing, a stair
## or water, and keeps KEEP clear of every crossing's and stair's rectangle
## and of every control, pad and goal, so no gate, gap, stair or water is ever
## hidden. It stays under a pip's knees (TOP). Built once per stage; present()
## rewrites the puffs only when a lantern changes.
const STYLES := ["mist"]
const COLOR := Color(0.93, 0.95, 0.94, 0.42)
## Puffs this far apart (m), this wide, this high over their floor.
const STEP := 0.85
const WIDTH := 0.95
const TOP := 0.22
## Room kept clear round crossings, stairs and spots (m), and the lit
## lantern's clear radius.
const KEEP := 0.45
const CLEAR := 2.6

var node: MultiMeshInstance3D
var _puffs: Array[Transform3D] = []
var _lanterns: Dictionary = {}
var _lit: Dictionary = {}
## Per puff, whether a lit lantern clears it (what the MultiMesh shows).
var _cleared: Array[bool] = []

## Fog in `style` over `view`'s floors (a stage plan in cm, as the worlds
## read it) under `parent`, round `lanterns` {lever id: position (m)}; null
## for "none" or no lantern.
static func build(fog_style: String, view: Dictionary, lanterns: Dictionary, parent: Node3D) -> RefCounted:
	if fog_style not in STYLES or lanterns.is_empty(): return null
	var fog: RefCounted = load("res://presentation/kit/fog.gd").new()
	fog._make(view, lanterns, parent)
	return fog

## Clears the puffs round the lanterns `levers` (the snapshot's) shows lit.
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

## The puffs' places (m), for tests.
func puffs() -> Array[Transform3D]:
	return _puffs

## Where the puffs a lit lantern has not cleared stand (m), for tests.
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
	for island: Dictionary in view.get("islands", []):
		var floor := _rect(island.rect_cm).grow(-0.3)
		var y := float(island.get("height_cm", 0)) / 100.0
		var x := floor.position.x
		var row := 0
		while x <= floor.end.x:
			var z := floor.position.y + (STEP * 0.5 if row % 2 else 0.0)
			while z <= floor.end.y:
				var at := Vector2(x, z)
				if not keep.any(func(rect: Rect2) -> bool: return rect.has_point(at)) and not spots.any(func(spot: Dictionary) -> bool: return at.distance_to(Vector2(float(spot.position_cm[0]), float(spot.position_cm[1])) / 100.0) < float(spot.get("radius_cm", 28)) / 100.0 + KEEP):
					var size := WIDTH * (0.8 + 0.4 * fposmod(sin(x * 12.9898 + z * 78.233) * 43758.5453, 1.0))
					_puffs.append(Transform3D(Basis().scaled(Vector3(size, TOP, size)), Vector3(x, y + TOP * 0.45, z)))
				z += STEP
			x += STEP * 0.87
			row += 1
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	var puff := SphereMesh.new()
	puff.radius = 0.5
	puff.height = 1.0
	puff.radial_segments = 10
	puff.rings = 5
	var material := StandardMaterial3D.new()
	material.albedo_color = COLOR
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_BACK
	puff.material = material
	multimesh.mesh = puff
	multimesh.instance_count = _puffs.size()
	_cleared.resize(_puffs.size())
	_cleared.fill(false)
	for index in range(_puffs.size()): multimesh.set_instance_transform(index, _puffs[index])
	node = MultiMeshInstance3D.new()
	node.name = "MarshFog"
	node.multimesh = multimesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)

static func _rect(cm: Array) -> Rect2:
	return Rect2(float(cm[0]) / 100.0, float(cm[1]) / 100.0, float(int(cm[2]) - int(cm[0])) / 100.0, float(int(cm[3]) - int(cm[1])) / 100.0)
