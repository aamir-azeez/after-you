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
##   "lantern": the fog lantern pump (rules 16's fog_lantern block). A lantern
##       hangs from the arm of a timber post over a squat iron pump; pulled,
##       the pump handle comes down and the lantern glows, let go it goes dark.
##       The world clears the fog round a lit one (kit/fog.gd).
##   "crank": the winch built squat and low, its drum bare of chain let go and
##       wound fat with it pulled, so the drum says which at a glance.
##   "rope": a mooring rope on a tall post. Let go, it hangs slack down the
##       post into a big coil at its foot; pulled, it runs taut and straight
##       from the post's head across to an iron cleat, the coil drawn small.
##   "water_gate": a timber gate in a little stone channel, lifted by a wheel
##       on its frame. Let go, the gate is down and the water behind it lies
##       still; pulled, the wheel turns, the gate rises and water runs out under it.
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
const MACHINES := ["winch", "bolt", "lantern", "crank", "rope", "water_gate"]
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
const TOPS := {"winch": 0.63, "bolt": 0.63, "lantern": 0.90, "crank": 0.45, "rope": 0.84, "water_gate": 0.71}
const KNOB_REACH := 0.49
## Winch and crank: the drum's height, its frame posts' height, its flanges'
## radius, its coil's radius let go and pulled, and whether the drum shows
## bare (no coil) let go; turns of the crank. A coil stays 0.05 or more
## across, so its bands stand 3 mm off it (the dressing lint's coplanar rule).
const WINCHES := {
	"winch": {"drum_y": 0.50, "posts": 0.60, "flange": 0.085, "coil": [0.052, 0.078]},
	"crank": {"drum_y": 0.30, "posts": 0.42, "flange": 0.11, "coil": [0.05, 0.10], "bare": true},
}
const DRUM_X := -0.03
const CRANK_TURNS := 1.5
const LINKS := 7
## Bolt: its centre drawn back and slid home (x, m).
const BOLT_BACK := 0.02
const BOLT_HOME := -0.10
## Lantern: its glass, how bright it burns lit, and the pump handle's tilt
## (radians about z) let go and pulled.
const LANTERN_GLASS := Color("f6d488")
const LANTERN_DARK := Color("6b6252")
const LANTERN_GLOW := 1.4
const PUMP_UP := 0.55
const PUMP_DOWN := -0.25
## Rope: its colour and thickness, the post's spot and height, where the rope
## leaves the post's head, the cleat across from the post (north and east, so
## the taut rope runs well off upright on screen), and the coil at the foot.
const ROPE := Color("ead7a4")
const ROPE_RADIUS := 0.025
const ROPE_SEGMENTS := 12
const ROPE_POST := Vector3(-0.22, 0, 0.10)
const ROPE_POST_HEIGHT := 0.80
const ROPE_HEAD := Vector3(-0.165, 0.70, 0.10)
const CLEAT := Vector3(0.10, 0, -0.10)
const COIL_AT := Vector3(-0.06, 0, 0.15)
const COIL_RADIUS := 0.075
## Gate: the channel's walls and the piers in them (x of each middle), the
## gate's line across the channel (south of the middle, so the pool it holds
## back shows past the beam and wheel from the game camera), its stone and
## bed, the gate's travel, the wheel's height and radius, and its water still
## and running.
const GATE_WALLS := [-0.21, 0.09]
const GATE_PIERS := [-0.205, 0.085]
const GATE_X := -0.06
const GATE_Z := 0.10
const GATE_STONE := Color("b9a585")
const GATE_BED := Color("6b5e4e")
const GATE_DOWN := 0.035
const GATE_LIFT := 0.13
const GATE_WHEEL_Y := 0.58
const GATE_WHEEL_R := 0.11
const GATE_WHEEL_TURNS := 1.25
const STILL_WATER := Color("4f8fb5")
const RUNNING_WATER := Color("7cc4d6")
const FOAM := Color("eef6f4")

var _shown := 0.0
var _target := 0.0
var _crank: Node3D
var _drum: Node3D
var _coil: Node3D
var _links: Array[MeshInstance3D] = []
var _bolt: Node3D
var _glass: MeshInstance3D
var _pump: Node3D
var _rope: Array[MeshInstance3D] = []
var _rope_coil: Node3D
var _gate: Node3D
var _wheel: Node3D
var _flow: Node3D

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
		"winch", "crank":
			parts.append_array([_drum, _crank])
			for link: MeshInstance3D in _links: parts.append(link)
		"rope":
			parts.append(_rope_coil)
			for piece: MeshInstance3D in _rope: parts.append(piece)
		"water_gate": parts.append_array([_gate, _wheel, _flow])
		"bolt": parts.append(_bolt)
		"lantern": parts.append_array([_glass, _pump])
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
		"winch", "crank": _make_winch(knob)
		"rope": _make_rope()
		"water_gate": _make_water_gate(knob)
		"bolt": _make_bolt(knob)
		"lantern": _make_lantern(knob)
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
	var drum_y: float = WINCHES[style].drum_y
	var posts: float = WINCHES[style].posts
	Parts.box(Vector3(0.36, 0.05, 0.22), Parts.TIMBER, Vector3(DRUM_X, 0.025, 0), root)
	for x: float in [-0.14, 0.11]:
		Parts.box(Vector3(0.05, posts, 0.07), Parts.TIMBER_DARK, Vector3(x, posts * 0.5, 0), root)
		Parts.box(Vector3(0.07, 0.03, 0.09), Parts.BRASS, Vector3(x, posts + 0.015, 0), root)
	# Every face stands a centimetre or more off its neighbours' (the dressing
	# lint's coplanar rule): the axle ends inside the east post and the crank.
	Parts.rod(0.016, 0.30, Parts.IRON, Vector3(DRUM_X - 0.005, drum_y, 0), root)
	_drum = Node3D.new()
	_drum.position = Vector3(DRUM_X, drum_y, 0)
	root.add_child(_drum)
	for x: float in [-0.07, 0.07]: Parts.rod(float(WINCHES[style].flange), 0.018, Parts.IRON, Vector3(x, 0, 0), _drum)
	# A brass stud on the east flange shows the drum turning.
	Parts.box(Vector3(0.024, 0.026, 0.026), Parts.BRASS, Vector3(0.095, 0.06, 0), _drum)
	# The chain wound on the drum: a coil of unit radius, scaled across the
	# axle (never along it) as it fills, banded where the turns lie.
	_coil = Node3D.new()
	_drum.add_child(_coil)
	Parts.rod(1.0, 0.11, Parts.IRON_LIGHT, Vector3.ZERO, _coil)
	for index in range(4): Parts.rod(1.07, 0.012, Parts.IRON, Vector3(-0.04 + float(index) * 0.0267, 0, 0), _coil)
	_crank = Node3D.new()
	_crank.position = Vector3(-0.18, drum_y, 0)
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

func _make_lantern(knob: Color) -> void:
	Parts.disc(0.15, 0.07, Parts.STONE, Vector3(0, 0.035, 0), root)
	# The pump: a squat iron barrel on the base, its handle on a pivot.
	Parts.disc(0.07, 0.22, Parts.IRON, Vector3(0.04, 0.18, 0), root)
	Parts.disc(0.085, 0.03, Parts.IRON_LIGHT, Vector3(0.04, 0.305, 0), root)
	_pump = Node3D.new()
	_pump.position = Vector3(0.04, 0.33, 0)
	root.add_child(_pump)
	Parts.box(Vector3(0.20, 0.025, 0.025), Parts.IRON, Vector3(-0.10, 0, 0), _pump)
	Parts.ball(0.03, knob, Vector3(-0.20, 0, 0), _pump)
	# The post and its arm, the lantern hanging east of the post.
	Parts.box(Vector3(0.05, 0.86, 0.05), Parts.TIMBER_DARK, Vector3(-0.09, 0.47, -0.06), root)
	Parts.box(Vector3(0.24, 0.04, 0.04), Parts.TIMBER, Vector3(0.01, 0.88, -0.06), root)
	Parts.box(Vector3(0.012, 0.08, 0.012), Parts.IRON, Vector3(0.09, 0.82, -0.06), root)
	Parts.disc(0.06, 0.03, Parts.BRASS, Vector3(0.09, 0.765, -0.06), root, 0.035)
	_glass = Parts.box(Vector3(0.085, 0.12, 0.085), LANTERN_DARK, Vector3(0.09, 0.69, -0.06), root)
	Parts.box(Vector3(0.10, 0.02, 0.10), Parts.BRASS, Vector3(0.09, 0.62, -0.06), root)

## Places every moving part for the shown pose.
func _pose() -> void:
	if style in HANDLES:
		anchor.rotation.z = -TILT if _shown >= 0.5 else TILT
		return
	var t := smoothstep(0.0, 1.0, _shown)
	if WINCHES.has(style):
		var turn := -t * CRANK_TURNS * TAU
		_crank.rotation.x = turn
		_drum.rotation.x = turn
		var coil := lerpf(WINCHES[style].coil[0], WINCHES[style].coil[1], t)
		_coil.scale = Vector3(1.0, coil, coil)
		if WINCHES[style].has("bare"): _coil.visible = t > 0.0
		# Off the drum's front, down to the hawse: a slack loop let go, taut pulled.
		var from := Vector3(DRUM_X, float(WINCHES[style].drum_y) - coil * 0.3, coil)
		var to := Vector3(DRUM_X, 0.07, 0.075)
		var bend := (from + to) * 0.5 + Vector3(0, -0.06, 0.13).lerp(Vector3.ZERO, t)
		for index in range(LINKS):
			var s := (float(index) + 0.5) / float(LINKS)
			var at := from.lerp(bend, s).lerp(bend.lerp(to, s), s)
			var along := (bend - from).lerp(to - bend, s).normalized()
			var across := Vector3(1, 0, 0) if index % 2 == 0 else along.cross(Vector3(1, 0, 0)).normalized()
			_links[index].basis = Basis(along * 1.5, across, along.cross(across).normalized())
			_links[index].position = at
	elif style == "rope":
		# From the post's head to the cleat: hanging down the post into the
		# coil let go, a straight line pulled.
		var to := (COIL_AT + Vector3(-0.05, 0.09, 0)).lerp(CLEAT + Vector3(0, 0.07, 0), t)
		var bend := Vector3(-0.15, 0.02, 0.12).lerp((ROPE_HEAD + to) * 0.5, t)
		_lay(_rope, ROPE_HEAD, bend, to, 1.15)
		var wound := lerpf(1.0, 0.45, t)
		_rope_coil.scale = Vector3(wound, 1.0, wound)
	elif style == "water_gate":
		_gate.position.y = GATE_DOWN + GATE_LIFT * t
		_wheel.rotation.z = -t * GATE_WHEEL_TURNS * TAU
		# Let go, the water is hidden at its full height, so no face of it lies
		# on the bed; as the gate rises it swells up from a third.
		_flow.visible = t > 0.0
		_flow.scale = Vector3(1.0, lerpf(0.3, 1.0, t) if t > 0.0 else 1.0, 1.0)
	elif style == "lantern":
		_pump.rotation.z = lerpf(PUMP_UP, PUMP_DOWN, t)
		var lit := t >= 0.5
		Parts.Primitives.own_material(_glass).albedo_color = LANTERN_GLASS if lit else LANTERN_DARK
		Parts.glow(_glass, LANTERN_GLASS, LANTERN_GLOW * t if lit else 0.0)
	elif is_instance_valid(_bolt):
		_bolt.position.x = lerpf(BOLT_BACK, BOLT_HOME, t)

## Lays `pieces` end to end along the curve from `from` over `bend` to `to`,
## each `overlap` times its share so the joints close.
func _lay(pieces: Array[MeshInstance3D], from: Vector3, bend: Vector3, to: Vector3, overlap: float) -> void:
	var count := pieces.size()
	var last := from
	for index in range(count):
		var s := float(index + 1) / float(count)
		var next := from.lerp(bend, s).lerp(bend.lerp(to, s), s)
		var along := next - last
		var length := maxf(along.length(), 0.001)
		var up := along / length
		var side := Vector3(0, 0, 1) if absf(up.z) < 0.9 else Vector3(1, 0, 0)
		side = (side - up * up.dot(side)).normalized()
		pieces[index].basis = Basis(side, up * length * overlap, side.cross(up))
		pieces[index].position = (last + next) * 0.5
		last = next

## A tall post with the rope lashed at its head, an iron cleat on the floor
## across from it and the rope's coil at the post's foot; the rope's pieces
## are laid by _pose.
func _make_rope() -> void:
	Parts.box(Vector3(0.09, ROPE_POST_HEIGHT, 0.09), Parts.TIMBER_DARK, ROPE_POST + Vector3(0, ROPE_POST_HEIGHT * 0.5, 0), root)
	Parts.box(Vector3(0.11, 0.04, 0.11), Parts.TIMBER_LIGHT, ROPE_POST + Vector3(0, ROPE_POST_HEIGHT + 0.02, 0), root)
	Parts.box(Vector3(0.10, 0.05, 0.10), ROPE, ROPE_POST + Vector3(0, ROPE_HEAD.y, 0), root)
	Parts.box(Vector3(0.04, 0.04, 0.05), Parts.IRON, CLEAT + Vector3(0, 0.02, 0), root)
	Parts.box(Vector3(0.10, 0.025, 0.035), Parts.IRON, CLEAT + Vector3(0, 0.0525, 0), root)
	_rope_coil = Node3D.new()
	_rope_coil.position = COIL_AT
	root.add_child(_rope_coil)
	for turn in range(3): Parts.torus(COIL_RADIUS - 0.012 * float(turn), ROPE_RADIUS, ROPE, Vector3(0, ROPE_RADIUS + 0.03 * float(turn), 0), _rope_coil, 14, 6)
	for index in range(ROPE_SEGMENTS): _rope.append(Parts.disc(ROPE_RADIUS, 1.0, ROPE, Vector3.ZERO, root, -1.0, 6))

## A little stone channel across the spot, a timber gate between two piers,
## a beam over them with the wheel's housing, the wheel facing the camera,
## still water behind the gate and running water before it.
func _make_water_gate(knob: Color) -> void:
	# Faces of different looks stand a centimetre or more apart (the dressing
	# lint's coplanar rule).
	Parts.box(Vector3(0.24, 0.03, 0.51), GATE_BED, Vector3(GATE_X, 0.015, 0.0), root)
	Parts.box(Vector3(0.38, 0.17, 0.04), GATE_STONE, Vector3(GATE_X, 0.085, -0.255), root)
	for x: float in GATE_WALLS: Parts.box(Vector3(0.08, 0.18, 0.50), GATE_STONE, Vector3(x, 0.09, 0.0), root)
	for x: float in GATE_PIERS: Parts.box(Vector3(0.11, 0.40, 0.12), GATE_STONE.darkened(0.08), Vector3(x, 0.20, GATE_Z), root)
	Parts.box(Vector3(0.42, 0.06, 0.10), Parts.TIMBER, Vector3(GATE_X, 0.41, GATE_Z), root)
	Parts.box(Vector3(0.09, 0.12, 0.09), Parts.IRON, Vector3(GATE_X, 0.49, GATE_Z), root)
	# The pool the gate holds back, lying still below the walls' tops from the
	# back wall to the gate.
	Parts.box(Vector3(0.20, 0.12, 0.215 + GATE_Z), STILL_WATER, Vector3(GATE_X, 0.09, (GATE_Z - 0.245) * 0.5), root)
	_gate = Node3D.new()
	_gate.position = Vector3(GATE_X, GATE_DOWN, GATE_Z)
	root.add_child(_gate)
	Parts.box(Vector3(0.17, 0.18, 0.04), Parts.TIMBER, Vector3(0, 0.09, 0), _gate)
	for y: float in [0.045, 0.135]: Parts.box(Vector3(0.16, 0.025, 0.012), Parts.IRON, Vector3(0, y, 0.026), _gate)
	# Running water: a sheet out from under the gate, foam where it leaves.
	_flow = Node3D.new()
	_flow.position = Vector3(GATE_X, 0.03, GATE_Z)
	root.add_child(_flow)
	var run := 0.225 - GATE_Z
	Parts.box(Vector3(0.20, 0.05, run), RUNNING_WATER, Vector3(0, 0.025, 0.025 + run * 0.5), _flow)
	Parts.box(Vector3(0.15, 0.05, 0.03), FOAM, Vector3(0, 0.035, 0.05), _flow)
	for x: float in [-0.06, 0.0, 0.06]: Parts.box(Vector3(0.016, 0.04, run - 0.055), FOAM, Vector3(x, 0.035, 0.07 + (run - 0.055) * 0.5), _flow)
	_wheel = Node3D.new()
	_wheel.position = Vector3(GATE_X, GATE_WHEEL_Y, GATE_Z + 0.075)
	root.add_child(_wheel)
	var rim := Parts.torus(GATE_WHEEL_R, 0.018, Parts.IRON, Vector3.ZERO, _wheel)
	rim.rotation.x = PI / 2.0
	for spoke in range(2):
		var bar := Parts.box(Vector3(0.022, GATE_WHEEL_R * 2.0, 0.02), Parts.IRON_LIGHT, Vector3.ZERO, _wheel)
		bar.rotation.z = float(spoke) * PI / 2.0
	var hub := Parts.disc(0.03, 0.04, Parts.BRASS, Vector3.ZERO, _wheel)
	hub.rotation.x = PI / 2.0
	Parts.ball(0.03, knob, Vector3(GATE_WHEEL_R, 0, 0.025), _wheel)
