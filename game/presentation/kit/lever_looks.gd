extends RefCounted
## World kit: a lever or selector prop's look. A chapter descriptor's
## "lever_looks" names one for a lever or selector id; a control without one
## keeps the plain handle and knob.
##
##   "winch": a hand winch. A crank on a timber frame turns an iron drum; the
##       chain runs off the drum down through a hawse ring in the sill. Pulled,
##       the crank turns over, the drum fills with chain and the chain comes up
##       taut; let go, it pays out into a slack loop.
##   "bolt": a sliding bolt. A round iron bolt with a knob lies in two staples
##       on a timber block. Pulled, it slides home into the iron catch; let go,
##       it draws back.
##   "valve": a valve wheel for a selector. A flat wheel on a tall cast-iron
##       pedestal, over a spirit's head so one standing at it never hides it,
##       above a dial plate whose marks (outside the rim) name its values; the
##       wheel's arrow turns to the value chosen (set_value). A post behind it
##       holds a sign plate the world fills (sign_point), higher still.
##
##   var look := LeverLooks.build("winch", at, knob_color, terrain)
##   look.anchor                        # the point a bubble's tail follows
##   look.set_pulled(on, immediate)     # each snapshot (a winch or bolt)
##   look.set_value(index, immediate)   # each snapshot (a valve)
##   if look.moving(): look.advance(delta)   # each frame
##
## A look stands on its control's own spot, inside its reach (REACH of its
## centre every way, the 28 cm interaction radius); a lever's look keeps
## its east side no further than the plain lever's housing (EAST_SIDE), so a
## lamp or mark a world stands beside a lever stays clear. It only shows the
## snapshot's state: a lever pulled or not, eased over PULL_SECONDS; a
## selector's value, its arrow turning at VALVE_RATE. An immediate call (a
## seek, a retry, reduced motion) snaps, and so does a valve's first value,
## and every part's place follows from that one value, so live play, the
## memory and a replay show the same thing. The accents (a knob, a valve's
## rim, hub and arrow head) take the colour the world passes, its owner's.
## Shapes and colours come from the kit's shared caches (Primitives, released
## through SessionRelease); nothing here keeps a static of its own, and no
## frame allocates.
const Primitives = preload("res://presentation/kit/primitives.gd")
## Looks a lever takes, and looks a selector takes.
const LEVER_KINDS := ["winch", "bolt"]
const SELECTOR_KINDS := ["valve"]
## How far a look reaches from its spot (m), every way (the 28 cm interaction
## radius), and a lever's look east (+x), where a world may stand a lamp
## beside it.
const REACH := 0.28
const EAST_SIDE := 0.16
## How long a pull or a release takes (s).
const PULL_SECONDS := 0.45
## Where a bubble's tail lands on each look (its top on its axis, m over its
## spot), and how far over its anchor that is: journey_world's knob point
## (KNOB 0.4 over the anchor) plus KNOB_RADIUS (0.09). anchor_lift() stands
## the anchor that far under the top.
const TOPS := {"winch": 0.63, "bolt": 0.63, "valve": 0.97}
const KNOB_REACH := 0.49
const TIMBER := Color("7a5d45")
const TIMBER_DARK := Color("5f4a38")
const TIMBER_LIGHT := Color("9b7653")
const IRON := Color("4f5458")
const IRON_LIGHT := Color("7b8287")
const BRASS := Color("b8914f")
const CREAM := Color("f3e6c8")
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
## Valve: its wheel's height (over a spirit's head, about 0.85, so one
## standing at the valve never hides it), the sweep of its marks either side
## of straight back (radians, the first value west), how fast its arrow turns
## (radians a second) and the sign plate's centre (behind the wheel, just in
## front of its post).
const VALVE_Y := 0.94
const VALVE_SWEEP := 0.95
const VALVE_RATE := 3.0
const SIGN_AT := Vector3(0.10, 1.16, -0.19)

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
var _wheel: Node3D
var _count := 1
## Whether a valve has shown a value yet: its first snaps, never sweeping in
## from a value it never had.
var _placed := false

## The look `kind` (LEVER_KINDS or SELECTOR_KINDS) on the spot `at` (terrain space) under
## `parent`, its knob in `knob` (the owner's colour). Shown let go.
## A valve takes `marks`: per value, how many bands mark it on the dial (0: a
## bar), first value west.
static func build(look_kind: String, at: Vector3, knob: Color, parent: Node3D, marks: Array = []) -> RefCounted:
	var look: RefCounted = load("res://presentation/kit/lever_looks.gd").new()
	look._make(look_kind, at, knob, parent, marks)
	return look

func moving() -> bool:
	return _shown != _target

## Shows the lever pulled or let go: eased from here, or at once. A valve
## ignores it.
func set_pulled(pulled: bool, immediate: bool = false) -> void:
	if kind == "valve": return
	_target = 1.0 if pulled else 0.0
	if immediate:
		_shown = _target
		_pose()

## Turns a valve's arrow to value `index` (of its marks): eased from where it
## points, or at once. Any other look ignores it.
func set_value(index: int, immediate: bool = false) -> void:
	if kind != "valve" or index < 0: return
	_target = value_angle(index, _count)
	if immediate or not _placed:
		_placed = true
		_shown = _target
		_pose()

## The arrow's turn (radians about up) for value `index` of `count`: from
## VALVE_SWEEP (the first, west) to -VALVE_SWEEP (the last, east).
static func value_angle(index: int, count: int) -> float:
	return lerpf(VALVE_SWEEP, -VALVE_SWEEP, float(index) / float(maxi(count - 1, 1)))

func advance(delta: float) -> void:
	if not moving(): return
	var rate := VALVE_RATE if kind == "valve" else 1.0 / PULL_SECONDS
	_shown = move_toward(_shown, _target, maxf(delta, 0.0) * rate)
	_pose()

## Where a valve's sign plate goes (terrain space), for the world to fill.
func sign_point() -> Vector3:
	return root.position + SIGN_AT

## The node a valve turns (its wheel and arrow), else null.
func wheel() -> Node3D:
	return _wheel

## How high the anchor stands over the look's spot.
func anchor_lift() -> float:
	return float(TOPS[kind]) - KNOB_REACH

## The parts a pull moves, for a world's list of nodes its static fold keeps
## whole; the frame, sill and block fold with the scenery around them.
func moving_parts() -> Array[Node3D]:
	var parts: Array[Node3D] = []
	if kind == "winch":
		parts.append_array([_drum, _crank])
		for link: MeshInstance3D in _links: parts.append(link)
	elif kind == "valve": parts.append(_wheel)
	else: parts.append(_bolt)
	return parts

## How far the shown pose is from let go (0) to pulled (1), for tests.
func shown() -> float:
	return _shown

func _make(look_kind: String, at: Vector3, knob: Color, parent: Node3D, marks: Array) -> void:
	kind = look_kind
	root = Node3D.new()
	root.name = "LeverLook_" + look_kind
	root.position = at
	parent.add_child(root)
	anchor = Node3D.new()
	anchor.name = "LeverAnchor"
	anchor.position = at + Vector3(0, anchor_lift(), 0)
	parent.add_child(anchor)
	match look_kind:
		"winch": _make_winch(knob)
		"valve": _make_valve(knob, marks)
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
	# Every face stands a centimetre or more off its neighbours' (the dressing
	# lint's coplanar rule): the axle ends inside the east post and the crank.
	_rod(0.016, 0.30, IRON, Vector3(DRUM_X - 0.005, DRUM_Y, 0), root)
	_drum = Node3D.new()
	_drum.position = Vector3(DRUM_X, DRUM_Y, 0)
	root.add_child(_drum)
	for x: float in [-0.07, 0.07]: _rod(0.085, 0.018, IRON, Vector3(x, 0, 0), _drum)
	# A brass stud on the east flange shows the drum turning.
	_box(Vector3(0.024, 0.026, 0.026), BRASS, Vector3(0.095, 0.06, 0), _drum)
	# The chain wound on the drum: a coil of unit radius, scaled across the
	# axle (never along it) as it fills, banded where the turns lie.
	_coil = Node3D.new()
	_drum.add_child(_coil)
	_rod(1.0, 0.11, IRON_LIGHT, Vector3.ZERO, _coil)
	for index in range(4): _rod(1.07, 0.012, IRON, Vector3(-0.04 + float(index) * 0.0267, 0, 0), _coil)
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
	for x: float in [-0.14, 0.08]: _box(Vector3(0.03, 0.40, 0.012), IRON, Vector3(x, 0.22, 0.094), root)
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

## A tall cast-iron pedestal on a round foot, brass at its foot and its neck,
## four brass bolt heads on the foot; a dial plate with cream marks for the
## values round its edge, outside the rim; a five-spoked wheel with a rim,
## hub, knob and arrow head in the owner's colour and spokes in a touch lighter
## shade of it, clear against the dark dial; and behind it a timber post with
## a brass bracket for the sign.
func _make_valve(knob: Color, marks: Array) -> void:
	_count = maxi(marks.size(), 1)
	_disc(0.17, 0.05, IRON, Vector3(0, 0.025, 0), root)
	_disc(0.115, 0.024, BRASS, Vector3(0, 0.061, 0), root)
	for index in range(4):
		var turn := PI / 4.0 + float(index) * PI / 2.0
		_box(Vector3(0.026, 0.016, 0.026), BRASS, Vector3(sin(turn), 0, cos(turn)) * 0.142 + Vector3(0, 0.057, 0), root)
	_disc(0.05, 0.776, IRON, Vector3(0, 0.462, 0), root, 0.04)
	_disc(0.066, 0.026, BRASS, Vector3(0, 0.86, 0), root)
	# The dial: a dark iron plate with a cream mark per value round its back
	# edge, outside the wheel's rim so the rim never hides one.
	_disc(0.275, 0.018, IRON, Vector3(0, 0.88, 0), root, -1.0, 16)
	for index in range(_count):
		var turn := value_angle(index, _count)
		var bands := int(marks[index]) if index < marks.size() else 1
		var along := Vector3(-sin(turn), 0, -cos(turn))
		var across := Vector3(-along.z, 0, along.x)
		var at := along * 0.235 + Vector3(0, 0.895, 0)
		if bands <= 0:
			var bar := _box(Vector3(0.07, 0.014, 0.02), CREAM, at, root)
			bar.rotation.y = turn
		for band in range(bands):
			var tick := _box(Vector3(0.016, 0.014, 0.032), CREAM, at + across * (float(band) - float(bands - 1) * 0.5) * 0.03, root)
			tick.rotation.y = turn
	_wheel = Node3D.new()
	_wheel.name = "ValveWheel"
	_wheel.position = Vector3(0, VALVE_Y, 0)
	root.add_child(_wheel)
	var rim := Primitives.mesh_node(Primitives.cached_shape(_ring_mesh(0.19, 0.021)), Primitives.shared_material(knob), Vector3.ZERO, _wheel)
	rim.name = "ValveRim"
	for spoke in range(5):
		var turn := float(spoke) * TAU / 5.0 + PI / 5.0
		var bar := _box(Vector3(0.028, 0.02, 0.17), knob.lightened(0.1), Vector3(sin(turn), 0, cos(turn)) * 0.095, _wheel)
		bar.rotation.y = turn
		bar.name = "ValveSpoke"
	_disc(0.042, 0.04, knob.darkened(0.15), Vector3.ZERO, _wheel)
	# The arrow from the hub out past the rim, toward the value; its head in
	# the owner's colour, and a handle knob on the rim to turn it by.
	# It runs out past the rim onto the dark dial, where it reads against the
	# light spokes and touches the mark it points at.
	var arrow := _box(Vector3(0.044, 0.016, 0.21), CREAM, Vector3(0, 0.024, -0.105), _wheel)
	arrow.name = "WheelPointer"
	var head := _box(Vector3(0.05, 0.018, 0.05), knob, Vector3(0, 0.028, -0.212), _wheel)
	head.rotation.y = PI / 4.0
	_ball(0.03, knob.lightened(0.15), Vector3(0.19, 0.03, 0.0), _wheel)
	# The sign's post and bracket, behind and east of the wheel.
	_box(Vector3(0.04, 1.12, 0.04), TIMBER_DARK, Vector3(SIGN_AT.x, 0.56, SIGN_AT.z - 0.035), root)
	_box(Vector3(0.05, 0.03, 0.06), BRASS, Vector3(SIGN_AT.x, 1.133, SIGN_AT.z - 0.035), root)

## A cylinder standing up (top radius `top` when given).
static func _disc(radius: float, height: float, color: Color, at: Vector3, parent: Node3D, top: float = -1.0, sides: int = 12) -> MeshInstance3D:
	var mesh := Primitives.cylinder_mesh(radius, height, top, sides)
	return Primitives.mesh_node(Primitives.cached_shape(mesh), Primitives.shared_material(color), at, parent)

static func _ring_mesh(radius: float, tube: float) -> TorusMesh:
	var ring := TorusMesh.new()
	ring.inner_radius = radius - tube
	ring.outer_radius = radius + tube
	ring.rings = 18
	ring.ring_segments = 6
	return ring

## Places every moving part for the shown pose.
func _pose() -> void:
	if kind == "valve":
		if is_instance_valid(_wheel): _wheel.rotation.y = _shown
		return
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
