extends "res://presentation/kit/pieces/piece.gd"
## World kit: a lever, in one of its styles (content/dressing/prop_styles.gd
## "lever"; content/dressing/piece_styles.gd picks which).
##
##   "plain": a grey stone housing and a cream handle whose knob is the owner's
##       colour; the handle tilts over when pulled.
##   "brass": the plain lever in a warm brass housing under a timber collar.
##   "winch": a hand winch. A crank on a timber frame turns an iron drum; the
##       chain runs off the drum down through a hawse ring in the sill. Pulled,
##       the crank turns over, the drum fills with chain and the chain comes up
##       taut; let go, it pays out into a slack loop.
##   "bolt": a sliding bolt. A round iron bolt with a knob lies in two staples
##       on a timber block. Pulled, it slides home into the iron catch; let go,
##       it draws back.
##
## A handle style's anchor is its tilting pivot (the knob at journey_world
## KNOB); a machine's is a fixed point anchor_lift() over its spot. A machine
## stands inside its control's reach (REACH every way, the 28 cm interaction
## radius) and keeps its east side no further than the plain housing
## (EAST_SIDE), so a lamp or mark a world stands beside a lever stays clear.
## A machine eases over PULL_SECONDS; a handle snaps. Every part's place
## follows from the shown value alone, and no frame allocates.

## Styles that tilt a handle, and machines that move their own parts.
const HANDLES := ["plain", "brass"]
const MACHINES := ["winch", "bolt"]
const REACH := 0.28
const EAST_SIDE := 0.16
const PULL_SECONDS := 0.45
## A handle's tilt (radians about z): pulled, and let go.
const TILT := 0.6
## The plain housing's stone.
const HOUSING := Color("728788")
## Where a bubble's tail lands on each machine (its top on its axis, m over
## its spot), and how far over its anchor that is: journey_world's knob point
## (KNOB 0.4 over the anchor) plus KNOB_RADIUS (0.09).
const TOPS := {"winch": 0.63, "bolt": 0.63}
const KNOB_REACH := 0.49
## Winch: drum height and its coil's radius, slack and wound; turns of the crank.
const DRUM_Y := 0.50
const DRUM_X := -0.03
const COIL_SLACK := 0.052
const COIL_WOUND := 0.078
const CRANK_TURNS := 1.5
const LINKS := 7
## Bolt: its centre drawn back and slid home (x, m).
const BOLT_BACK := 0.02
const BOLT_HOME := -0.10

var _shown := 0.0
var _target := 0.0
var _crank: Node3D
var _drum: Node3D
var _coil: Node3D
var _links: Array[MeshInstance3D] = []
var _bolt: Node3D

## A lever in `style` on the spot `at` (parent space) under `parent`, shown let
## go. `options`: "owner" ("p0"/"p1") colours its knob. An unknown style is plain.
static func build(lever_style: String, at: Vector3, parent: Node3D, options: Dictionary = {}) -> RefCounted:
	var piece: RefCounted = load("res://presentation/kit/pieces/lever.gd").new()
	piece._make(lever_style if lever_style in HANDLES + MACHINES else "plain", at, parent, Parts.owner_color(str(options.get("owner", "p0"))))
	return piece

## Shows the lever pulled or let go: eased from here, or at once.
func set_pulled(pulled: bool, immediate: bool = false) -> void:
	_target = 1.0 if pulled else 0.0
	if immediate or style in HANDLES:
		_shown = _target
		_pose()

## A handle shown as a selector's switch: over to the pulled side at the
## first value, back for any other (or none).
func set_value(index: int, _immediate: bool = false) -> void:
	if style in HANDLES: set_pulled(index == 0, true)

func moving() -> bool:
	return _shown != _target

func advance(delta: float) -> void:
	if not moving(): return
	_shown = move_toward(_shown, _target, maxf(delta, 0.0) / PULL_SECONDS)
	_pose()

## How high a machine's anchor stands over its spot (a handle's pivot: 0.2).
func anchor_lift() -> float:
	return float(TOPS[style]) - KNOB_REACH if TOPS.has(style) else 0.2

func moving_parts() -> Array[Node3D]:
	var parts: Array[Node3D] = []
	match style:
		"winch":
			parts.append_array([_drum, _crank])
			for link: MeshInstance3D in _links: parts.append(link)
		"bolt": parts.append(_bolt)
		_: parts.append(anchor)
	return parts

## How far the shown pose is from let go (0) to pulled (1), for tests.
func shown() -> float:
	return _shown

func _make(lever_style: String, at: Vector3, parent: Node3D, knob: Color) -> void:
	style = lever_style
	_root("Lever_" + lever_style, at, parent)
	# The anchor stands in the parent's own space, so its transform is where
	# the knob is for a bubble laid out there.
	anchor = Node3D.new()
	anchor.name = "LeverAnchor"
	anchor.position = at + Vector3(0, anchor_lift(), 0)
	parent.add_child(anchor)
	match lever_style:
		"winch": _make_winch(knob)
		"bolt": _make_bolt(knob)
		_: _make_handle(knob)
	_pose()

func _make_handle(knob: Color) -> void:
	Parts.cylinder(0.18, 0.2, Parts.BRASS if style == "brass" else HOUSING, Vector3(0, 0.1, 0), root)
	if style == "brass": Parts.cylinder(0.19, 0.04, Parts.TIMBER, Vector3(0, 0.19, 0), root)
	Parts.box(Vector3(0.055, 0.40, 0.055), Parts.CREAM, Vector3(0, 0.2, 0), anchor)
	Parts.sphere(0.09, knob, Vector3(0, 0.4, 0), anchor)

## One chain link (a flattened ring), cached by the kit like every shape.
static func _link(parent: Node3D) -> MeshInstance3D:
	return Parts.torus(0.0175, 0.0065, Parts.IRON, Vector3.ZERO, parent, 8, 5)

func _make_winch(knob: Color) -> void:
	Parts.box(Vector3(0.36, 0.05, 0.22), Parts.TIMBER, Vector3(DRUM_X, 0.025, 0), root)
	for x: float in [-0.14, 0.11]:
		Parts.box(Vector3(0.05, 0.60, 0.07), Parts.TIMBER_DARK, Vector3(x, 0.30, 0), root)
		Parts.box(Vector3(0.07, 0.03, 0.09), Parts.BRASS, Vector3(x, 0.615, 0), root)
	# Every face stands a centimetre or more off its neighbours' (the dressing
	# lint's coplanar rule): the axle ends inside the east post and the crank.
	Parts.rod(0.016, 0.30, Parts.IRON, Vector3(DRUM_X - 0.005, DRUM_Y, 0), root)
	_drum = Node3D.new()
	_drum.position = Vector3(DRUM_X, DRUM_Y, 0)
	root.add_child(_drum)
	for x: float in [-0.07, 0.07]: Parts.rod(0.085, 0.018, Parts.IRON, Vector3(x, 0, 0), _drum)
	# A brass stud on the east flange shows the drum turning.
	Parts.box(Vector3(0.024, 0.026, 0.026), Parts.BRASS, Vector3(0.095, 0.06, 0), _drum)
	# The chain wound on the drum: a coil of unit radius, scaled across the
	# axle (never along it) as it fills, banded where the turns lie.
	_coil = Node3D.new()
	_drum.add_child(_coil)
	Parts.rod(1.0, 0.11, Parts.IRON_LIGHT, Vector3.ZERO, _coil)
	for index in range(4): Parts.rod(1.07, 0.012, Parts.IRON, Vector3(-0.04 + float(index) * 0.0267, 0, 0), _coil)
	_crank = Node3D.new()
	_crank.position = Vector3(-0.18, DRUM_Y, 0)
	root.add_child(_crank)
	Parts.box(Vector3(0.025, 0.12, 0.03), Parts.IRON, Vector3(0, 0.05, 0), _crank)
	Parts.rod(0.016, 0.04, Parts.IRON, Vector3(-0.02, 0.11, 0), _crank)
	Parts.ball(0.032, knob, Vector3(-0.04, 0.11, 0), _crank)
	# The hawse the chain runs down through, in the sill's front.
	var hawse := _link(root)
	hawse.position = Vector3(DRUM_X, 0.055, 0.075)
	hawse.scale = Vector3(1.8, 1.0, 1.8)
	for index in range(LINKS): _links.append(_link(root))

func _make_bolt(knob: Color) -> void:
	Parts.box(Vector3(0.36, 0.44, 0.18), Parts.TIMBER, Vector3(-0.04, 0.22, 0), root)
	Parts.box(Vector3(0.40, 0.03, 0.22), Parts.TIMBER_LIGHT, Vector3(-0.04, 0.455, 0), root)
	for x: float in [-0.14, 0.08]: Parts.box(Vector3(0.03, 0.40, 0.012), Parts.IRON, Vector3(x, 0.22, 0.094), root)
	# Two staples the bolt lies in, west of where its knob travels.
	for x: float in [-0.14, -0.05]:
		for z: float in [-0.045, 0.045]: Parts.box(Vector3(0.025, 0.08, 0.02), Parts.IRON, Vector3(x, 0.50, z), root)
		Parts.box(Vector3(0.025, 0.02, 0.11), Parts.IRON, Vector3(x, 0.545, 0), root)
	Parts.box(Vector3(0.06, 0.10, 0.11), Parts.IRON, Vector3(-0.21, 0.52, 0), root)
	_bolt = Node3D.new()
	_bolt.position = Vector3(BOLT_BACK, 0.51, 0)
	root.add_child(_bolt)
	Parts.rod(0.026, 0.26, Parts.IRON_LIGHT, Vector3.ZERO, _bolt)
	Parts.box(Vector3(0.02, 0.07, 0.02), Parts.IRON, Vector3(0.09, 0.04, 0), _bolt)
	Parts.ball(0.036, knob, Vector3(0.09, 0.085, 0), _bolt)

## Places every moving part for the shown pose.
func _pose() -> void:
	if style in HANDLES:
		anchor.rotation.z = -TILT if _shown >= 0.5 else TILT
		return
	var t := smoothstep(0.0, 1.0, _shown)
	if style == "winch":
		var turn := -t * CRANK_TURNS * TAU
		_crank.rotation.x = turn
		_drum.rotation.x = turn
		var coil := lerpf(COIL_SLACK, COIL_WOUND, t)
		_coil.scale = Vector3(1.0, coil, coil)
		# Off the drum's front, down to the hawse: a slack loop let go, taut pulled.
		var from := Vector3(DRUM_X, DRUM_Y - coil * 0.3, coil)
		var to := Vector3(DRUM_X, 0.07, 0.075)
		var bend := (from + to) * 0.5 + Vector3(0, -0.06, 0.13).lerp(Vector3.ZERO, t)
		for index in range(LINKS):
			var s := (float(index) + 0.5) / float(LINKS)
			var at := from.lerp(bend, s).lerp(bend.lerp(to, s), s)
			var along := (bend - from).lerp(to - bend, s).normalized()
			var across := Vector3(1, 0, 0) if index % 2 == 0 else along.cross(Vector3(1, 0, 0)).normalized()
			_links[index].basis = Basis(along * 1.5, across, along.cross(across).normalized())
			_links[index].position = at
	elif is_instance_valid(_bolt):
		_bolt.position.x = lerpf(BOLT_BACK, BOLT_HOME, t)
