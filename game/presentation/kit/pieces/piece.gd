extends RefCounted
## World kit: what every built piece answers, whatever its style. A piece kit
## (lever.gd, selector.gd, pad.gd, goal.gd) builds one style of its piece and
## returns one of these; the world keeps it and feeds it the snapshot:
##
##   var piece := Lever.build(style, at, parent, {"owner": "p0"})
##   piece.anchor                         # the point a bubble's tail follows
##   piece.set_pulled(on, immediate)      # a lever, each snapshot
##   piece.set_value(index, immediate)    # a selector, each snapshot
##   piece.set_held(on)                   # a pad, each snapshot
##   piece.set_lit(on)                    # a goal, each snapshot
##   if piece.moving(): piece.advance(delta)   # each frame
##   piece.moving_parts()                 # kept whole by the static fold
##
## A piece only shows the snapshot; nothing here feeds back into the
## simulation, a recording or a checkpoint. An immediate call (a seek, a retry,
## reduced motion) snaps, so live play, the memory and a replay show the same
## thing. A call a style has no use for does nothing.
const Parts = preload("res://presentation/kit/pieces/parts.gd")

## The style built (content/dressing/prop_styles.gd SLOTS).
var style := ""
## Everything the piece built stands under this, at its spot.
var root: Node3D
## The node a bubble's tail and a pair tag follow: a plain lever's tilting
## pivot (its knob at journey_world KNOB), else a fixed point over the spot.
var anchor: Node3D

func set_pulled(_pulled: bool, _immediate: bool = false) -> void:
	pass

func set_value(_index: int, _immediate: bool = false) -> void:
	pass

func set_held(_on: bool) -> void:
	pass

func set_lit(_on: bool) -> void:
	pass

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

## A fresh root named `name` at `at` under `parent`.
func _root(name: String, at: Vector3, parent: Node3D) -> Node3D:
	root = Node3D.new()
	root.name = name
	root.position = at
	parent.add_child(root)
	return root
