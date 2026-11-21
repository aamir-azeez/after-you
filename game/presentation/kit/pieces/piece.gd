extends RefCounted
## World kit: what every built piece answers, whatever its style. A piece kit
## (lever.gd, selector.gd, pad.gd, goal.gd) builds one style of its piece and
## returns one of these; the world keeps it and feeds it the snapshot:
##
##   var piece := Lever.build(style, at, parent, {"owner": "p0"})
##   piece.anchor                         # the point a bubble's tail follows
##   piece.set_pulled(on, immediate)      # a lever, each snapshot
##   piece.set_value(index, immediate)    # a selector, each snapshot
##   piece.set_held(on, immediate)        # a pad, each snapshot
##   piece.set_lit(on, immediate)         # a goal, each snapshot
##   if piece.moving(): piece.advance(delta)   # each frame
##   piece.moving_parts()                 # kept whole by the static fold
##
## A piece only shows the snapshot; nothing here feeds back into the
## simulation, a recording or a checkpoint. An immediate call (a seek, a retry,
## reduced motion) snaps, so live play, the memory and a replay show the same
## thing. A call a style has no use for does nothing. A part that arrives
## overshoots a little and settles (_arrive, Motion.arrival) while moving()
## stays true, then rests exactly where a snap would put it.
const Parts = preload("res://presentation/kit/pieces/parts.gd")
const Motion = preload("res://presentation/kit/motion.gd")
const ContactShadows = preload("res://presentation/kit/contact_shadows.gd")

## The style built (content/dressing/prop_styles.gd SLOTS).
var style := ""
## Everything the piece built stands under this, at its spot.
var root: Node3D
## The node a bubble's tail and a pair tag follow: a plain lever's tilting
## pivot (its knob at journey_world KNOB), else a fixed point over the spot.
var anchor: Node3D
## Reduce motion: the piece still goes where the world asks, but never
## overshoots its stop. The world sets it (an immediate call snaps anyway).
var reduced_motion := false
## The running overshoot (Motion.arrival): its age, or -1 for none, and size.
var _arrival_age := -1.0
var _arrival_size := 0.0

func set_pulled(_pulled: bool, _immediate: bool = false) -> void:
	pass

func set_value(_index: int, _immediate: bool = false) -> void:
	pass

func set_held(_on: bool, _immediate: bool = false) -> void:
	pass

func set_lit(_on: bool, _immediate: bool = false) -> void:
	pass

## The anchor's transform (parent space) without any overshoot: where a
## bubble's tail or a mark read at a present goes, so it never keeps a
## passing swing.
func anchor_rest() -> Transform3D:
	return anchor.transform

## How high the anchor stands over the spot (a handle's pivot by default).
func anchor_lift() -> float:
	return 0.2

func moving() -> bool:
	return false

func advance(_delta: float) -> void:
	pass

## The nodes that change after the build, which the static fold keeps whole;
## the rest folds with the scenery around it.
func moving_parts() -> Array[Node3D]:
	return []

## Starts the overshoot of a moving part that has just arrived: `size` past
## its stop, signed the way it was going (its own units: radians, metres or
## a share of its travel). Nothing under reduced motion.
func _arrive(size: float) -> void:
	if reduced_motion or is_zero_approx(size): return
	_arrival_age = 0.0
	_arrival_size = size

## Ends any overshoot at once (a new move, an immediate call).
func _stop_arrival() -> void:
	_arrival_age = -1.0

func _arriving() -> bool:
	return _arrival_age >= 0.0

## Ages the overshoot by `delta` and returns how far past its stop the part
## stands now: exactly 0 once it is over, when it stops counting as moving.
func _arrival_step(delta: float) -> float:
	if _arrival_age < 0.0: return 0.0
	_arrival_age += maxf(delta, 0.0)
	if _arrival_age >= Motion.ARRIVAL_SECONDS:
		_arrival_age = -1.0
		return 0.0
	return Motion.arrival(_arrival_age, _arrival_size)

## A fresh root named `name` at `at` under `parent`, with a soft contact
## shadow where it meets the ground (kit/contact_shadows.gd) unless `shadow`
## is false: a kit that is ground itself (a crossing, a lift's deck) or rides
## the water says so (test_shared_paths lists them).
func _root(name: String, at: Vector3, parent: Node3D, shadow: bool = true) -> Node3D:
	root = Node3D.new()
	root.name = name
	root.position = at
	parent.add_child(root)
	if shadow: ContactShadows.mark(root)
	return root
