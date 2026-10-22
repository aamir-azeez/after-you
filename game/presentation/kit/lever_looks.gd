extends RefCounted
## World kit: a lever prop's look. A chapter descriptor's "lever_looks" names
## one for a lever id; a lever without one keeps the plain handle and knob.
##
##   "winch": a hand winch. A crank on a timber frame turns an iron drum; the
##       chain runs off the drum down through a hawse ring in the sill. Pulled,
##       the crank turns over, the drum fills with chain and the chain comes up
##       taut; let go, it pays out into a slack loop.
##   "bolt": a sliding bolt. A round iron bolt with a knob lies in two staples
##       on a timber block. Pulled, it slides home into the iron catch; let go,
##       it draws back.
##
##   var look := LeverLooks.build("winch", at, knob_color, terrain)
##   look.anchor                        # the point a bubble's tail follows
##   look.set_pulled(on, immediate)     # each snapshot
##   if look.moving(): look.advance(delta)   # each frame
##
## A look stands on the lever's own spot, inside its reach (REACH of its
## centre every way, inside the lever's 28 cm interaction radius) and on its
## east side no further than the plain lever's housing (EAST_SIDE), so a lamp
## or mark a world stands beside a lever stays clear. It only shows the
## snapshot's lever state: pulled or not. The pose eases toward it over
## PULL_SECONDS (an immediate call, for a seek, a retry or reduced motion,
## snaps), and every part's place follows from that one value, so live play,
## the memory and a replay show the same thing. Shapes and colours come from
## the kit's shared caches (Primitives, released through SessionRelease);
## nothing here keeps a static of its own, and no frame allocates.
const Primitives = preload("res://presentation/kit/primitives.gd")
const KINDS := ["winch", "bolt"]
## How far a look reaches from its spot (m), every way, and east (+x).
const REACH := 0.26
const EAST_SIDE := 0.16
## How long a pull or a release takes (s).
const PULL_SECONDS := 0.45
## The anchor stands this high: anchor + (0, 0.4, 0) is the plain lever's
## knob centre, and a bubble's tail lands KNOB_RADIUS (0.09) above that, on
## the look's top (0.63).
const ANCHOR_Y := 0.14
const TIMBER := Color("7a5d45")
const TIMBER_DARK := Color("5f4a38")
const TIMBER_LIGHT := Color("9b7653")
const IRON := Color("4f5458")
const IRON_LIGHT := Color("7b8287")
const BRASS := Color("b8914f")
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

var kind := ""
var root: Node3D
var anchor: Node3D
var _shown := 0.0
var _target := 0.0
var _crank: Node3D
var _drum: Node3D
var _coil: Node3D
var _links: Array[MeshInstance3D] = []
var _bolt: Node3D

## The look `kind` (one of KINDS) on the spot `at` (terrain space) under
## `parent`, its knob in `knob` (the owner's colour). Shown let go.
static func build(look_kind: String, at: Vector3, knob: Color, parent: Node3D) -> RefCounted:
	var look: RefCounted = load("res://presentation/kit/lever_looks.gd").new()
	look._make(look_kind, at, knob, parent)
	return look

func moving() -> bool:
	return _shown != _target

## Shows the lever pulled or let go: eased from here, or at once.
func set_pulled(pulled: bool, immediate: bool = false) -> void:
	_target = 1.0 if pulled else 0.0
	if immediate:
		_shown = _target
		_pose()

func advance(delta: float) -> void:
	if not moving(): return
	_shown = move_toward(_shown, _target, maxf(delta, 0.0) / PULL_SECONDS)
	_pose()

## The parts a pull moves, for a world's list of nodes its static fold keeps
## whole; the frame, sill and block fold with the scenery around them.
func moving_parts() -> Array[Node3D]:
	var parts: Array[Node3D] = []
	if kind == "winch":
		parts.append_array([_drum, _crank])
		for link: MeshInstance3D in _links: parts.append(link)
	else: parts.append(_bolt)
	return parts

## How far the shown pose is from let go (0) to pulled (1), for tests.
func shown() -> float:
	return _shown

func _make(look_kind: String, at: Vector3, knob: Color, parent: Node3D) -> void:
	kind = look_kind
	root = Node3D.new()
	root.name = "LeverLook_" + look_kind
	root.position = at
	parent.add_child(root)
	anchor = Node3D.new()
	anchor.name = "LeverAnchor"
	anchor.position = at + Vector3(0, ANCHOR_Y, 0)
	parent.add_child(anchor)
	match look_kind:
		"winch": _make_winch(knob)
		_: _make_bolt(knob)
	_pose()

static func _box(size: Vector3, color: Color, at: Vector3, parent: Node3D) -> MeshInstance3D:
	return Primitives.mesh_node(Primitives.shared_mesh("box", size.x, size.y, size.z), Primitives.shared_material(color), at, parent)

## A cylinder lying along x.
static func _rod(radius: float, length: float, color: Color, at: Vector3, parent: Node3D) -> MeshInstance3D:
	var node := Primitives.mesh_node(Primitives.shared_mesh("cylinder", radius, length, radius), Primitives.shared_material(color), at, parent)
	node.rotation.z = PI / 2.0
	return node

static func _ball(radius: float, color: Color, at: Vector3, parent: Node3D) -> MeshInstance3D:
	return Primitives.mesh_node(Primitives.shared_mesh("sphere", radius), Primitives.shared_material(color), at, parent)

## One chain link (a flattened ring), cached by the kit like every shape.
static func _link(color: Color, parent: Node3D) -> MeshInstance3D:
	var ring := TorusMesh.new()
	ring.inner_radius = 0.011
	ring.outer_radius = 0.024
	ring.rings = 8
	ring.ring_segments = 5
	return Primitives.mesh_node(Primitives.cached_shape(ring), Primitives.shared_material(color), Vector3.ZERO, parent)

func _make_winch(knob: Color) -> void:
	_box(Vector3(0.36, 0.05, 0.22), TIMBER, Vector3(DRUM_X, 0.025, 0), root)
	for x: float in [-0.14, 0.11]:
		_box(Vector3(0.05, 0.60, 0.07), TIMBER_DARK, Vector3(x, 0.30, 0), root)
		_box(Vector3(0.07, 0.03, 0.09), BRASS, Vector3(x, 0.615, 0), root)
	_rod(0.016, 0.33, IRON, Vector3(DRUM_X, DRUM_Y, 0), root)
	_drum = Node3D.new()
	_drum.position = Vector3(DRUM_X, DRUM_Y, 0)
	root.add_child(_drum)
	for x: float in [-0.09, 0.09]:
		_rod(0.085, 0.018, IRON, Vector3(x, 0, 0), _drum)
		# A brass stud on each flange shows the drum turning.
		_box(Vector3(0.024, 0.026, 0.026), BRASS, Vector3(x * 1.12, 0.06, 0), _drum)
	# The chain wound on the drum: a coil of unit radius, scaled across the
	# axle (never along it) as it fills, banded where the turns lie.
	_coil = Node3D.new()
	_drum.add_child(_coil)
	_rod(1.0, 0.16, IRON_LIGHT, Vector3.ZERO, _coil)
	for index in range(4): _rod(1.07, 0.014, IRON, Vector3(-0.06 + float(index) * 0.04, 0, 0), _coil)
	_crank = Node3D.new()
	_crank.position = Vector3(-0.18, DRUM_Y, 0)
	root.add_child(_crank)
	_box(Vector3(0.025, 0.12, 0.03), IRON, Vector3(0, 0.05, 0), _crank)
	_rod(0.016, 0.04, IRON, Vector3(-0.02, 0.11, 0), _crank)
	_ball(0.032, knob, Vector3(-0.04, 0.11, 0), _crank)
	# The hawse the chain runs down through, in the sill's front.
	var hawse := _link(IRON, root)
	hawse.position = Vector3(DRUM_X, 0.055, 0.075)
	hawse.scale = Vector3(1.8, 1.0, 1.8)
	for index in range(LINKS): _links.append(_link(IRON, root))

func _make_bolt(knob: Color) -> void:
	_box(Vector3(0.36, 0.44, 0.18), TIMBER, Vector3(-0.04, 0.22, 0), root)
	_box(Vector3(0.40, 0.03, 0.22), TIMBER_LIGHT, Vector3(-0.04, 0.455, 0), root)
	for x: float in [-0.18, 0.10]: _box(Vector3(0.03, 0.40, 0.012), IRON, Vector3(x, 0.22, 0.094), root)
	# Two staples the bolt lies in, west of where its knob travels.
	for x: float in [-0.14, -0.05]:
		for z: float in [-0.045, 0.045]: _box(Vector3(0.025, 0.08, 0.02), IRON, Vector3(x, 0.50, z), root)
		_box(Vector3(0.025, 0.02, 0.11), IRON, Vector3(x, 0.545, 0), root)
	_box(Vector3(0.06, 0.10, 0.11), IRON, Vector3(-0.21, 0.52, 0), root)
	_bolt = Node3D.new()
	_bolt.position = Vector3(BOLT_BACK, 0.51, 0)
	root.add_child(_bolt)
	_rod(0.026, 0.26, IRON_LIGHT, Vector3.ZERO, _bolt)
	_box(Vector3(0.02, 0.07, 0.02), IRON, Vector3(0.09, 0.04, 0), _bolt)
	_ball(0.036, knob, Vector3(0.09, 0.085, 0), _bolt)

## Places every moving part for the shown pose.
func _pose() -> void:
	var t := smoothstep(0.0, 1.0, _shown)
	if kind == "winch":
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
