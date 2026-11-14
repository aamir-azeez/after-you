extends "res://presentation/kit/pieces/piece.gd"
## World kit: a stage's goal, in one of its styles (content/dressing/
## prop_styles.gd "goal"; content/dressing/piece_styles.gd picks which). Each
## keeps the goal's exact centre and radius: a low disc under a ring the size
## of the goal, and the ornament above it.
##
##   "bell": a bell hung between two stone posts under a beam.
##   "harbour_lantern": a tall harbour lantern on a mole stone well north of
##       the standing point, so a spirit lighting it never hides its head
##       from the follow camera.
##   "crest": a low lit garden crest, a round lamp in the ring; nothing tall
##       stands where the completion garden grows round it.
##   "window": an openable window in a timber frame north of the ring
##       (presentation/house_window.gd); lit, its shutters swing open.
##   "walled_window": the window set in a short plaster wall, so it never
##       stands free inside a room.
##
## The handles the world lights (lighthouse_world present): `bell` (the
## lantern, the lamp or the window pane), `ring`, and `light`, an omni light
## the world brightens, stood in the parent's space beside the goal. A window
## style also keeps `window` for house_window.gd present.
const WindowVisual = preload("res://presentation/house_window.gd")
const Look = preload("res://presentation/kit/look.gd")
## A lit goal's light, before the look's lamp scale (kit/look.gd lamp_energy).
const LIGHT_ENERGY := 1.2
const STYLES := ["bell", "harbour_lantern", "crest", "window", "walled_window"]
## Styles whose cradle carries its owner's mark (kit/owner_mark.gd): the ones a
## spirit lights from in front, where the mark stands clear of the ornament.
const MARKED := ["harbour_lantern", "window", "walled_window"]
## Root node names, one per style.
const NAMES := {"bell": "CourtBell", "harbour_lantern": "HarbourLanternGoal", "crest": "GardenLightCrest", "window": "ArrivalWindowGoal", "walled_window": "ArrivalWindowGoal"}
const BELL_LIGHT := Color("ffd9a2")
const SLATE := Color("6b8984")
## The plaster wall's plane, just behind the window's frame.
const WALL_Z := -0.49

var bell: MeshInstance3D
var ring: MeshInstance3D
var light: OmniLight3D
var window: Dictionary = {}

## A goal in `style` at `at` (parent space, on its floor) under `parent`,
## `radius_m` across.
static func build(goal_style: String, at: Vector3, radius_m: float, parent: Node3D) -> RefCounted:
	var piece: RefCounted = load("res://presentation/kit/pieces/goal.gd").new()
	piece._make(goal_style if goal_style in STYLES else "bell", at, radius_m, parent)
	return piece

## Lights the goal once the stage's objective is done (the snapshot's
## objective_done), or puts it out: its ring and ornament glow and its light
## comes up; a window glows gold and swings its shutters open.
func set_lit(on: bool) -> void:
	Parts.glow(ring, Parts.LIGHT, 1.0 if on else 0.0)
	if window.is_empty(): Parts.glow(bell, Parts.LIGHT, 0.65 if on else 0.0)
	else: WindowVisual.present(window, on, Parts.GOLD)
	light.light_energy = Look.lamp_energy(LIGHT_ENERGY) if on else 0.0
	bell.set_meta("lit", on)

func moving_parts() -> Array[Node3D]:
	var parts: Array[Node3D] = [bell, ring]
	for shutter: Node3D in window.get("shutters", []): parts.append(shutter)
	return parts

func _make(goal_style: String, at: Vector3, radius_m: float, parent: Node3D) -> void:
	style = goal_style
	_root(NAMES[goal_style], at, parent)
	anchor = root
	match goal_style:
		"harbour_lantern": _make_lantern(radius_m)
		"crest": _make_crest(radius_m)
		"window", "walled_window": _make_window(radius_m)
		_: _make_bell(radius_m)
	parent.add_child(light)

## The goal's light, off, at `offset` from the goal in the parent's space.
func _light(color: Color, reach: float, offset: Vector3) -> void:
	light = OmniLight3D.new()
	light.light_color = color
	light.light_energy = 0.0
	light.omni_range = reach
	light.position = root.position + offset

func _make_bell(radius_m: float) -> void:
	Parts.cylinder(0.34, 0.065, Color("697b8e"), Vector3(0, 0.033, 0), root)
	ring = Parts.ring(radius_m, Color("a2b3c0"), Vector3(0, 0.07, 0), root)
	for side: int in [-1, 1]: Parts.box(Vector3(0.10, 1.52, 0.13), Color("9e9180"), Vector3(float(side) * 0.43, 0.76, -0.12), root)
	Parts.box(Vector3(0.98, 0.12, 0.18), Color("b4a381"), Vector3(0, 1.52, -0.12), root)
	var shape := CylinderMesh.new()
	shape.top_radius = 0.11
	shape.bottom_radius = 0.27
	shape.height = 0.42
	shape.radial_segments = 20
	bell = Parts.Primitives.mesh_node(shape, Parts.Primitives.shared_material(Color("b29868")), Vector3(0, 1.18, 0), root)
	Parts.ring(0.27, Color("c4ad7a"), Vector3(0, 0.97, 0), root)
	Parts.sphere(0.055, Color("dfc58c"), Vector3(0, 0.97, 0), root)
	_light(BELL_LIGHT, 4.0, Vector3(0, 1.6, 0))

func _make_lantern(radius_m: float) -> void:
	Parts.cylinder(radius_m, 0.05, SLATE, Vector3(0, 0.025, 0), root)
	ring = Parts.ring(radius_m, Parts.CREAM, Vector3(0, 0.06, 0), root)
	var base := Vector3(0, 0, -0.85)
	var frame := Parts.TIMBER.darkened(0.25)
	Parts.box(Vector3(0.50, 0.22, 0.40), Parts.STONE, base + Vector3(0, 0.11, 0), root)
	Parts.cylinder(0.05, 1.40, Parts.TIMBER.darkened(0.2), base + Vector3(0, 0.92, 0), root)
	var head := base + Vector3(0, 1.78, 0)
	Parts.box(Vector3(0.40, 0.05, 0.40), frame, head + Vector3(0, -0.24, 0), root)
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		Parts.box(Vector3(0.035, 0.46, 0.035), frame, head + Vector3(corner.x * 0.16, 0, corner.y * 0.16), root)
	for side: Vector3 in [Vector3(0, 0, 0.16), Vector3(0, 0, -0.16), Vector3(0.16, 0, 0), Vector3(-0.16, 0, 0)]:
		var pane := Parts.box(Vector3(0.012 if side.x != 0.0 else 0.30, 0.40, 0.012 if side.z != 0.0 else 0.30), Color(1.0, 0.92, 0.72, 0.42), head + side, root)
		pane.name = "LanternPane"
		pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bell = Parts.sphere(0.10, Color("e6c98a"), head, root)
	bell.name = "HarbourLantern"
	Parts.box(Vector3(0.46, 0.06, 0.46), frame, head + Vector3(0, 0.25, 0), root)
	Parts.box(Vector3(0.28, 0.08, 0.28), frame, head + Vector3(0, 0.31, 0), root)
	Parts.sphere(0.05, Parts.BRASS, head + Vector3(0, 0.38, 0), root)
	_light(Parts.LIGHT, 4.5, head + Vector3(0, 0, 0.2))

## Low enough to stay clear of the completion bed's discs around it; a round
## lamp, since a gold diamond would read as the first spirit's mark.
func _make_crest(radius_m: float) -> void:
	Parts.cylinder(radius_m, 0.044, SLATE, Vector3(0, 0.022, 0), root)
	ring = Parts.ring(radius_m, Parts.CREAM, Vector3(0, 0.06, 0), root)
	bell = Parts.cylinder(0.075, 0.022, Parts.LIGHT, Vector3(0, 0.07, 0), root)
	_light(Parts.GOLD, 4.0, Vector3(0, 0.8, 0))

func _make_window(radius_m: float) -> void:
	Parts.cylinder(radius_m, 0.045, Color("748e87"), Vector3(0, 0.025, 0), root)
	ring = Parts.ring(radius_m, Parts.CREAM, Vector3(0, 0.06, 0), root)
	window = WindowVisual.build(root, Vector3(0, 0, -0.44), 0.80, Parts.HOME_FRAME, Parts.GLASS, Parts.CREAM)
	bell = window.pane
	bell.name = "SecondWindow"
	for side: int in [-1, 1]: Parts.box(Vector3(0.08, 0.42, 0.08), Parts.HOME_FRAME, Vector3(float(side) * 0.42, 0.21, -0.44), root)
	if style == "walled_window":
		for side: int in [-1, 1]: Parts.box(Vector3(0.46, 1.36, 0.07), Parts.HOME_PLASTER, Vector3(float(side) * 0.68, 0.68, WALL_Z), root)
		# Just under the sill and the posts, never level with either.
		Parts.box(Vector3(0.90, 0.415, 0.07), Parts.HOME_PLASTER, Vector3(0, 0.2075, WALL_Z), root)
		Parts.box(Vector3(0.90, 0.18, 0.07), Parts.HOME_PLASTER, Vector3(0, 1.27, WALL_Z), root)
		Parts.box(Vector3(1.86, 0.07, 0.12), Parts.HOME_FRAME, Vector3(0, 1.39, WALL_Z), root)
	_light(Parts.GOLD, 4.0, Vector3(0, 1.0, -0.20))
