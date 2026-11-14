extends "res://presentation/kit/pieces/piece.gd"
## World kit: a selector, in one of its styles (content/dressing/prop_styles.gd
## "selector"; content/dressing/piece_styles.gd picks which).
##
##   "plain", "brass": the lever of the same style (lever.gd), its handle
##       over at the first value and back at any other.
##   "valve": a valve wheel. A flat wheel on a tall cast-iron pedestal, over a
##       spirit's head so one standing at it never hides it, above a dial plate
##       whose marks (outside the rim) name its values; the wheel's arrow turns
##       to the value chosen. A post behind it holds a sign plate the world
##       fills (sign_point), higher still.
##   "lamp_post": the plain lever with a lamp post beside it whose glass globe
##       shows the value's colour (LAMP_COLORS; any other value is dark).
##   "gate_arch": the plain lever with an open timber arch over the walk east
##       of it, a lantern under its beam showing the value's colour.
##   "shutter": the plain lever with a shutter board in a frame beside it,
##       slid down for the value "down" and up for any other.
##
## Every style stands on its control's own spot. A valve's arrow turns at
## VALVE_RATE and snaps on its first value; the rest snap. The world passes
## "values" (the selector's values in order) and, for a valve, "marks": per
## value, how many bands mark it on the dial (0: a bar).
const Lever = preload("res://presentation/kit/pieces/lever.gd")
const LEVER_STYLES := ["plain", "brass"]
## Styles that stand a prop beside a plain lever.
const PROPS := ["lamp_post", "gate_arch", "shutter"]
const REACH := Lever.REACH
## Valve: where a bubble's tail lands (its top, m over its spot); its wheel's
## height; the sweep of its marks either side of straight back (radians, the
## first value west); how fast its arrow turns (radians a second); the sign
## plate's centre (behind the wheel, just in front of its post).
const VALVE_TOP := 0.97
const VALVE_Y := 0.94
const VALVE_SWEEP := 0.95
const VALVE_RATE := 3.0
const SIGN_AT := Vector3(0.10, 1.16, -0.19)
## A lamp's glass for each value it shows; any other value is dark ("off").
const LAMP_DARK := Color("4a4038")
const LAMP_COLORS := {"off": LAMP_DARK, "shut": LAMP_DARK, "rose": Color("e8607e"), "moss": Color("6fae3c")}
const LAMP_GLOW := 0.9
## The arch's climbing green.
const LEAF := Color("8fb57a")
## Lamp post: its foot east and north of the spot, and its height.
const LAMP_BASE := Vector3(0.42, 0, -0.14)
const LAMP_HEIGHT := 1.05
## Gate arch: east of the spot, its two posts north and south of it.
const ARCH_X := 0.62
const ARCH_POSTS := [-0.60, 0.28]
## Shutter: its frame east and north of the spot; the board's centre over the
## spot's floor, down and up.
const SHUTTER_AT := Vector3(0.40, 0, -0.42)
const SHUTTER_DOWN := 0.30
const SHUTTER_UP := 0.86

var _lever: RefCounted
var _values: Array = []
var _shown := 0.0
var _target := 0.0
var _count := 1
var _placed := false
var _wheel: Node3D
var _lamp: MeshInstance3D
var _shutter: Node3D

## A selector in `style` on the spot `at` (parent space) under `parent`.
## `options`: "owner" ("p0"/"p1"), "values" (its values in order), "marks"
## (a valve's bands per value), "id" (names a lamp "Lamp_<id>").
static func build(selector_style: String, at: Vector3, parent: Node3D, options: Dictionary = {}) -> RefCounted:
	var piece: RefCounted = load("res://presentation/kit/pieces/selector.gd").new()
	piece._make(selector_style if selector_style in LEVER_STYLES + PROPS + ["valve"] else "plain", at, parent, options)
	return piece

## Shows value `index` (of its values): a valve's arrow eased there from where
## it points, or at once; every other style at once.
func set_value(index: int, immediate: bool = false) -> void:
	if _lever != null: _lever.set_value(index, immediate)
	if index < 0: return
	var value := str(_values[index]) if index < _values.size() else ""
	match style:
		"valve":
			_target = value_angle(index, _count)
			if immediate or not _placed:
				_placed = true
				_shown = _target
				_pose()
		"lamp_post", "gate_arch": light_lamp(_lamp, value)
		"shutter":
			_shutter.position.y = SHUTTER_DOWN if value == "down" else SHUTTER_UP
			_shutter.set_meta("down", value == "down")

## The arrow's turn (radians about up) for value `index` of `count`: from
## VALVE_SWEEP (the first, west) to -VALVE_SWEEP (the last, east).
static func value_angle(index: int, count: int) -> float:
	return lerpf(VALVE_SWEEP, -VALVE_SWEEP, float(index) / float(maxi(count - 1, 1)))

## Shows `value`'s colour in a lamp's globe, lit, or dark for a value it has
## no colour for. A world's own lantern that follows a selector uses it too.
static func light_lamp(globe: MeshInstance3D, value: String) -> void:
	var color: Color = LAMP_COLORS.get(value, LAMP_COLORS.off)
	Parts.Primitives.own_material(globe).albedo_color = color
	Parts.glow(globe, color, LAMP_GLOW if value in LAMP_COLORS and color != LAMP_COLORS.off else 0.0)
	globe.set_meta("value", value)

func moving() -> bool:
	return _shown != _target

func advance(delta: float) -> void:
	if not moving(): return
	_shown = move_toward(_shown, _target, maxf(delta, 0.0) * VALVE_RATE)
	_pose()

## How high the anchor stands over the spot.
func anchor_lift() -> float:
	return VALVE_TOP - Lever.KNOB_REACH if style == "valve" else _lever.anchor_lift()

## Where a valve's sign plate goes (parent space), for the world to fill.
func sign_point() -> Vector3:
	return root.position + SIGN_AT

## The node a valve turns (its wheel and arrow), else null.
func wheel() -> Node3D:
	return _wheel

## A selector's lamp globe, else null.
func lamp() -> MeshInstance3D:
	return _lamp

func shown() -> float:
	return _shown

func moving_parts() -> Array[Node3D]:
	var parts: Array[Node3D] = []
	if _lever != null: parts.append_array(_lever.moving_parts())
	if is_instance_valid(_wheel): parts.append(_wheel)
	if is_instance_valid(_lamp): parts.append(_lamp)
	if is_instance_valid(_shutter): parts.append(_shutter)
	return parts

func _make(selector_style: String, at: Vector3, parent: Node3D, options: Dictionary) -> void:
	style = selector_style
	_values = Array(options.get("values", []))
	if style == "valve":
		_root("Selector_valve", at, parent)
		anchor = Node3D.new()
		anchor.name = "LeverAnchor"
		anchor.position = at + Vector3(0, anchor_lift(), 0)
		parent.add_child(anchor)
		_make_valve(Parts.owner_color(str(options.get("owner", "p0"))), Array(options.get("marks", [])))
		_pose()
		return
	_lever = Lever.build("brass" if style == "brass" else "plain", at, parent, options)
	root = _lever.root
	root.name = "Selector_" + style
	anchor = _lever.anchor
	match style:
		"lamp_post": _make_lamp_post(str(options.get("id", "")))
		"gate_arch": _make_gate_arch(str(options.get("id", "")))
		"shutter": _make_shutter()

## A post with a glass globe.
func _make_lamp_post(id: String) -> void:
	var base := LAMP_BASE
	Parts.cylinder(0.11, 0.06, Parts.POST, base + Vector3(0, 0.03, 0), root)
	Parts.cylinder(0.035, LAMP_HEIGHT, Parts.POST, base + Vector3(0, LAMP_HEIGHT * 0.5, 0), root)
	Parts.box(Vector3(0.26, 0.04, 0.26), Parts.POST, base + Vector3(0, LAMP_HEIGHT + 0.02, 0), root)
	_lamp = Parts.sphere(0.20, LAMP_COLORS.off, base + Vector3(0, LAMP_HEIGHT + 0.24, 0), root)
	_lamp.name = "Lamp_" + id
	Parts.box(Vector3(0.22, 0.035, 0.22), Parts.POST, base + Vector3(0, LAMP_HEIGHT + 0.46, 0), root)

## An open timber arch over the walk; its lantern hangs under the beam.
func _make_gate_arch(id: String) -> void:
	var middle := (float(ARCH_POSTS[0]) + float(ARCH_POSTS[1])) * 0.5
	for z: float in ARCH_POSTS: Parts.box(Vector3(0.09, 1.30, 0.09), Parts.POST, Vector3(ARCH_X, 0.65, z), root)
	Parts.box(Vector3(0.12, 0.08, 1.06), Parts.POST, Vector3(ARCH_X, 1.32, middle), root)
	for side: int in [-1, 1]:
		var arc := Parts.box(Vector3(0.08, 0.06, 0.30), LEAF, Vector3(ARCH_X, 1.40, middle + float(side) * 0.34), root)
		arc.rotation.x = -0.35 * float(side)
	_lamp = Parts.sphere(0.12, LAMP_COLORS.shut, Vector3(ARCH_X, 1.12, middle), root)
	_lamp.name = "Lamp_" + id

## A shutter board between two posts under a head rail.
func _make_shutter() -> void:
	for side: int in [-1, 1]: Parts.box(Vector3(0.06, 1.10, 0.06), Parts.POST, SHUTTER_AT + Vector3(float(side) * 0.22, 0.55, 0), root)
	Parts.box(Vector3(0.50, 0.05, 0.08), Parts.POST, SHUTTER_AT + Vector3(0, 1.12, 0), root)
	_shutter = Node3D.new()
	_shutter.name = "PorchShutterBoard"
	_shutter.position = SHUTTER_AT + Vector3(0, SHUTTER_UP, 0)
	root.add_child(_shutter)
	Parts.box(Vector3(0.38, 0.40, 0.04), Parts.BOARD, Vector3.ZERO, _shutter)
	for y: float in [-0.10, 0.10]: Parts.box(Vector3(0.32, 0.035, 0.02), Parts.CREAM, Vector3(0, y, 0.025), _shutter)

## A tall cast-iron pedestal on a round foot, brass at its foot and its neck,
## four brass bolt heads on the foot; a dial plate with marks for the values
## round its edge, outside the rim; a five-spoked wheel with a rim, hub, knob
## and arrow head in the owner's colour and spokes a touch lighter, clear
## against the dark dial; and behind it a timber post with a brass bracket for
## the sign.
func _make_valve(knob: Color, marks: Array) -> void:
	_count = maxi(marks.size(), 1)
	Parts.disc(0.17, 0.05, Parts.IRON, Vector3(0, 0.025, 0), root)
	Parts.disc(0.115, 0.024, Parts.BRASS, Vector3(0, 0.061, 0), root)
	for index in range(4):
		var turn := PI / 4.0 + float(index) * PI / 2.0
		Parts.box(Vector3(0.026, 0.016, 0.026), Parts.BRASS, Vector3(sin(turn), 0, cos(turn)) * 0.142 + Vector3(0, 0.057, 0), root)
	Parts.disc(0.05, 0.776, Parts.IRON, Vector3(0, 0.462, 0), root, 0.04)
	Parts.disc(0.066, 0.026, Parts.BRASS, Vector3(0, 0.86, 0), root)
	# The dial: a dark iron plate with a mark per value round its back edge,
	# outside the wheel's rim so the rim never hides one.
	Parts.disc(0.275, 0.018, Parts.IRON, Vector3(0, 0.88, 0), root, -1.0, 16)
	for index in range(_count):
		var turn := value_angle(index, _count)
		var bands := int(marks[index]) if index < marks.size() else 1
		var along := Vector3(-sin(turn), 0, -cos(turn))
		var across := Vector3(-along.z, 0, along.x)
		var at := along * 0.235 + Vector3(0, 0.895, 0)
		if bands <= 0:
			Parts.box(Vector3(0.07, 0.014, 0.02), Parts.MARK, at, root).rotation.y = turn
		for band in range(bands):
			Parts.box(Vector3(0.016, 0.014, 0.032), Parts.MARK, at + across * (float(band) - float(bands - 1) * 0.5) * 0.03, root).rotation.y = turn
	_wheel = Node3D.new()
	_wheel.name = "ValveWheel"
	_wheel.position = Vector3(0, VALVE_Y, 0)
	root.add_child(_wheel)
	Parts.torus(0.19, 0.021, knob, Vector3.ZERO, _wheel).name = "ValveRim"
	for spoke in range(5):
		var turn := float(spoke) * TAU / 5.0 + PI / 5.0
		var bar := Parts.box(Vector3(0.028, 0.02, 0.17), knob.lightened(0.1), Vector3(sin(turn), 0, cos(turn)) * 0.095, _wheel)
		bar.rotation.y = turn
		bar.name = "ValveSpoke"
	Parts.disc(0.042, 0.04, knob.darkened(0.15), Vector3.ZERO, _wheel)
	# The arrow from the hub out past the rim onto the dark dial, where it reads
	# against the light spokes and touches the mark it points at; its head in
	# the owner's colour, and a handle knob on the rim to turn it by.
	Parts.box(Vector3(0.044, 0.016, 0.21), Parts.MARK, Vector3(0, 0.024, -0.105), _wheel).name = "WheelPointer"
	Parts.box(Vector3(0.05, 0.018, 0.05), knob, Vector3(0, 0.028, -0.212), _wheel).rotation.y = PI / 4.0
	Parts.ball(0.03, knob.lightened(0.15), Vector3(0.19, 0.03, 0.0), _wheel)
	# The sign's post and bracket, behind and east of the wheel.
	Parts.box(Vector3(0.04, 1.12, 0.04), Parts.TIMBER_DARK, Vector3(SIGN_AT.x, 0.56, SIGN_AT.z - 0.035), root)
	Parts.box(Vector3(0.05, 0.03, 0.06), Parts.BRASS, Vector3(SIGN_AT.x, 1.133, SIGN_AT.z - 0.035), root)

func _pose() -> void:
	if is_instance_valid(_wheel): _wheel.rotation.y = _shown
