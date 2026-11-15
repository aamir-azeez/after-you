extends "res://presentation/kit/pieces/piece.gd"
## World kit: a lift, in one of its styles (content/dressing/prop_styles.gd
## "lift"; content/dressing/piece_styles.gd picks which).
##
##   "plain": First Steps' first lift: a pale plate between four guide poles.
##   "rope_tower": a cosy timber lift. A plank cage hangs from a hook block on
##       four corner ropes; one rope runs up to a pulley wheel atop a four-post
##       timber tower, over a second wheel at the tower's back corner and down
##       in one taut line to a hand winch beside the power spot. While
##       the cage rises the wheels and the winch drum turn and the hook rope
##       shortens, so the ride is visibly pulled from the winch.
##
## The deck (`root`) is the simulation's walking surface; every part of the
## structure stays outside the walkable rectangle, under the deck or high over
## the floor (the winch's line), and the
## cage's rails are low (RAIL) so a rider's face stays in view. Every moving
## part follows the shown height alone (set_height).
const STYLES := ["plain", "rope_tower"]
const RAIL := 0.32
## The hook block over the deck, and the tower top over the upper floor (m).
const HOOK_OVER := 1.15
const TOWER_OVER := 1.55
const WHEEL := 0.32
## The tower's top beams (m across), thicker than its posts.
const BEAM := 0.07
const DRUM := 0.13
const ROPE := Color("c9b48a")
## Rope thickness (m): thick enough to read at phone size.
const ROPE_WIDTH := 0.04
## The winch's line up to the tower, the one the eye follows.
const DRIVE_ROPE := 0.06
## The winch's size, and how far from the power spot's centre it stands,
## towards the tower: beside the pip on the spot, on the camera's side of its
## rope, never behind the pip.
const WINCH_SIZE := 1.35
const WINCH_OFFSET := 0.66

var _bottom := 0.0
var _top := 1.0
var _rope: Node3D
var _wheels: Array[Node3D] = []
var _drum: Node3D
var _parts: Array[Node3D] = []

## A lift in `style` over `rect` (metres, x and z in parent space), riding
## from `bottom` to `top`. `options`: "drive" (Vector3, the power spot a
## rope_tower's winch stands beside).
static func build(lift_style: String, rect: Rect2, bottom: float, top: float, parent: Node3D, options: Dictionary = {}) -> RefCounted:
	var piece: RefCounted = load("res://presentation/kit/pieces/lift.gd").new()
	piece._make(lift_style if lift_style in STYLES else "plain", rect, bottom, top, parent, options)
	return piece

## Shows the deck at `height` (m, parent space).
func set_height(height: float) -> void:
	root.position.y = height
	if style != "rope_tower": return
	var hook := height + HOOK_OVER
	var wheel_y := _top + TOWER_OVER - WHEEL
	var length := maxf(wheel_y - hook, 0.05)
	_rope.position.y = hook + length / 2.0
	_rope.scale = Vector3(1, length, 1)
	var turn := (height - _bottom) / WHEEL
	for wheel: Node3D in _wheels: wheel.rotation.z = -turn
	if _drum != null: _drum.rotation.x = (height - _bottom) / DRUM

func moving_parts() -> Array[Node3D]:
	return _parts

func _make(lift_style: String, rect: Rect2, bottom: float, top: float, parent: Node3D, options: Dictionary) -> void:
	style = lift_style
	_bottom = bottom
	_top = top
	var center := Vector3(rect.get_center().x, bottom, rect.get_center().y)
	_root("Lift_" + lift_style, center, parent)
	anchor = root
	_parts.append(root)
	if lift_style == "rope_tower": _rope_tower(rect, parent, options)
	else: _plain(rect, parent)

func _plain(rect: Rect2, parent: Node3D) -> void:
	var width := rect.size.x
	var depth := rect.size.y
	Parts.box(Vector3(width, 0.18, depth), Color("b8aa8c"), Vector3(0, -0.09, 0), root)
	Parts.box(Vector3(width - 0.06, 0.018, depth - 0.06), Color("e0d4ac"), Vector3(0, 0.009, 0), root)
	Parts.ring(0.40, Parts.GOLD, Vector3(0, 0.035, 0), root)
	var height := _top - _bottom
	var center := Vector3(rect.get_center().x, _bottom, rect.get_center().y)
	for side in [-1, 1]:
		for edge in [-1, 1]:
			Parts.cylinder(0.045, height + 0.40, Color("809d91"), center + Vector3(edge * (width / 2.0 - 0.16), height / 2.0, side * (depth / 2.0 + 0.10)), parent)
		Parts.box(Vector3(width, 0.05, 0.045), Parts.CREAM, Vector3(0, 0.33, side * (depth / 2.0 + 0.04)), root)

func _rope_tower(rect: Rect2, parent: Node3D, options: Dictionary) -> void:
	var width := rect.size.x
	var depth := rect.size.y
	var center := Vector3(rect.get_center().x, _bottom, rect.get_center().y)
	# The cage: a plank deck on edge beams, low rails on its two closed sides,
	# corner posts, and four ropes up to the hook block.
	Parts.box(Vector3(width, 0.12, depth), Parts.TIMBER_DARK, Vector3(0, -0.07, 0), root)
	var planks := [Color("bda27e"), Color("c9af8a"), Color("c2a481"), Color("b99b77")]
	for i in range(7):
		var z := -depth / 2.0 + (float(i) + 0.5) * depth / 7.0
		Parts.box(Vector3(width - 0.08, 0.02, depth / 7.0 - 0.02), planks[i % planks.size()], Vector3(0, 0.0, z), root)
	var hook := Vector3(0, HOOK_OVER, 0)
	for side in [-1, 1]:
		for edge in [-1, 1]:
			var corner := Vector3(edge * (width / 2.0 - 0.06), 0, side * (depth / 2.0 - 0.04))
			Parts.box(Vector3(0.07, RAIL + 0.06, 0.07), Parts.TIMBER, corner + Vector3(0, (RAIL + 0.06) / 2.0, 0), root)
			_bar(corner + Vector3(0, RAIL + 0.06, 0), hook, ROPE_WIDTH * 0.5, ROPE, root)
		Parts.box(Vector3(width - 0.08, 0.05, 0.05), Parts.TIMBER_LIGHT, Vector3(0, RAIL, side * (depth / 2.0 - 0.04)), root)
		Parts.box(Vector3(width - 0.08, 0.04, 0.04), Parts.TIMBER, Vector3(0, RAIL * 0.5, side * (depth / 2.0 - 0.04)), root)
	Parts.box(Vector3(0.16, 0.12, 0.12), Parts.IRON, hook, root)
	Parts.ball(0.035, Parts.BRASS, hook + Vector3(0, 0.08, 0), root)
	# The tower: four posts outside the deck's closed sides, from below the
	# lower floor to over the upper one, braced, with a top frame.
	var top_y := _top + TOWER_OVER
	var post_z := depth / 2.0 + 0.12
	var post_x := width / 2.0 - 0.10
	for side in [-1, 1]:
		for edge in [-1, 1]:
			var foot := center + Vector3(edge * post_x, -1.2, side * post_z)
			_bar(foot, Vector3(foot.x, top_y + 0.06, foot.z), 0.05, Parts.TIMBER, parent)
		# Top beams are thicker than the posts and sit at different heights
		# from the end beams, so no two faces lie together (they would flicker).
		_bar(center + Vector3(-post_x, top_y, side * post_z), center + Vector3(post_x, top_y, side * post_z), BEAM, Parts.TIMBER_DARK, parent)
		# A cross brace on each closed side, low enough to stay under the upper floor's edge.
		_bar(center + Vector3(-post_x, _bottom - center.y - 1.0, side * post_z), center + Vector3(post_x, _bottom - center.y - 0.15, side * post_z), 0.03, Parts.TIMBER_DARK, parent)
	for edge in [-1, 1]:
		_bar(center + Vector3(edge * post_x, top_y - 0.10, -post_z), center + Vector3(edge * post_x, top_y - 0.10, post_z), BEAM, Parts.TIMBER_DARK, parent)
	# A small ridge roof high over the head beam, short enough that the wheel
	# under it stays in view from the play camera.
	for side in [-1, 1]:
		var slope := Parts.box(Vector3(0.62, 0.04, 0.42), Color("b5643f"), center + Vector3(0, top_y + 0.62, side * 0.17), parent)
		slope.rotation.x = side * 0.5
	for side in [-1, 1]:
		Parts.box(Vector3(0.05, 0.62, 0.05), Parts.TIMBER_DARK, center + Vector3(side * 0.26, top_y + 0.3, 0), parent)
	# The head beam across the middle carries the main wheel; the hook rope hangs from it.
	_bar(center + Vector3(0, top_y + 0.065, -post_z), center + Vector3(0, top_y + 0.065, post_z), 0.06, Parts.TIMBER, parent)
	var wheel_y := top_y - WHEEL
	_wheels.append(_wheel(center + Vector3(0, wheel_y, 0), parent))
	_rope = Node3D.new()
	_rope.name = "HookRope"
	parent.add_child(_rope)
	_rope.position = center + Vector3(0, wheel_y, 0)
	Parts.cylinder(ROPE_WIDTH * 0.6, 1.0, ROPE, Vector3.ZERO, _rope)
	_parts.append(_rope)
	# Over the top to a second wheel at the back corner on the drive's side,
	# down that post and along the floor to the winch.
	var drive: Vector3 = options.get("drive", center + Vector3(-width, 0, -depth))
	var corner_x := -post_x if drive.x < center.x else post_x
	var corner := center + Vector3(corner_x, wheel_y, -post_z)
	_wheels.append(_wheel(corner, parent))
	_bar(center + Vector3(0, top_y + 0.12, 0), corner + Vector3(0, WHEEL + 0.02, 0), ROPE_WIDTH, ROPE, parent)
	for part: Node3D in _wheels: _parts.append(part)
	_winch(drive, corner + Vector3(signf(corner_x) * WHEEL, 0, 0), parent)

## A hand winch on a timber frame just behind `spot` (towards the tower's
## back), its rope laid along the floor to `to`.
func _winch(spot: Vector3, to: Vector3, parent: Node3D) -> void:
	var toward := Vector3(to.x - spot.x, 0, to.z - spot.z).normalized()
	var at := spot + toward * WINCH_OFFSET
	var frame := Node3D.new()
	frame.name = "LiftWinch"
	frame.position = at
	# The drum lies across the rope, which leaves it towards the tower.
	frame.rotation.y = atan2(toward.x, toward.z)
	frame.scale = Vector3.ONE * WINCH_SIZE
	parent.add_child(frame)
	for side in [-1, 1]:
		Parts.box(Vector3(0.06, 0.62, 0.08), Parts.TIMBER, Vector3(side * 0.24, 0.31, 0), frame)
		Parts.box(Vector3(0.10, 0.06, 0.34), Parts.TIMBER_DARK, Vector3(side * 0.24, 0.03, 0), frame)
	_drum = Node3D.new()
	_drum.name = "WinchDrum"
	_drum.position = Vector3(0, 0.46, 0)
	frame.add_child(_drum)
	var barrel := Parts.rod(DRUM, 0.42, Parts.TIMBER_LIGHT, Vector3.ZERO, _drum)
	barrel.name = "Barrel"
	Parts.rod(DRUM + 0.012, 0.30, ROPE, Vector3.ZERO, _drum)
	# The crank handle turns with the drum.
	Parts.box(Vector3(0.03, 0.22, 0.03), Parts.IRON, Vector3(0.29, 0.10, 0), _drum)
	Parts.rod(0.025, 0.12, Parts.BRASS, Vector3(0.34, 0.2, 0), _drum)
	_parts.append(_drum)
	# Off the top of the drum, one taut line up over the tower's corner wheel,
	# high over the floor: the pull reads from the winch to the wheels.
	_bar(at + Vector3(0, (0.46 + DRUM) * WINCH_SIZE, 0), to, DRIVE_ROPE, ROPE, parent)

func _wheel(at: Vector3, parent: Node3D) -> Node3D:
	var wheel := Node3D.new()
	wheel.name = "LiftWheel"
	wheel.position = at
	parent.add_child(wheel)
	var rim := Parts.cylinder(WHEEL, 0.06, Parts.BRASS, Vector3.ZERO, wheel)
	rim.rotation.x = PI / 2.0
	var hub := Parts.cylinder(WHEEL * 0.72, 0.075, Parts.TIMBER_LIGHT, Vector3.ZERO, wheel)
	hub.rotation.x = PI / 2.0
	for spoke in range(3):
		var bar := Parts.box(Vector3(WHEEL * 1.7, 0.035, 0.085), Parts.TIMBER_DARK, Vector3.ZERO, wheel)
		bar.rotation.z = float(spoke) * PI / 3.0
	Parts.ball(0.04, Parts.BRASS, Vector3(0, 0, 0.05), wheel)
	return wheel

## A round bar from `a` to `b` (parent space).
func _bar(a: Vector3, b: Vector3, radius: float, color: Color, parent: Node3D) -> MeshInstance3D:
	# Basis.looking_at cannot face straight up: a vertical bar is a standing box.
	if absf((b - a).normalized().y) > 0.99:
		return Parts.box(Vector3(radius, a.distance_to(b), radius), color, (a + b) / 2.0, parent)
	return Parts.Primitives.bar_between(a, b, radius, Parts.Primitives.shared_material(color), parent)
