extends "res://presentation/kit/pieces/piece.gd"
## World kit: a rope raft (rules 20's rope_raft block), in one of its styles
## (content/dressing/prop_styles.gd "raft"; piece_styles.gd picks which, by
## the platform's id).
##
##   "logs": a raft of lashed logs exactly the size of its stops, its top at
##       their walking height, with a short mast post at one corner. A rope
##       runs taut between a post beyond each end stop, through the mast's
##       ring, so the raft is plainly pulled along it.
##
## The raft (`root`) stands at the stop the snapshot opens and eases there
## from where it is at RATE, the live pip riding it (the simulation moves the
## pip at once; the spirit follows). Every stop has the same size, so one raft
## fits them all. It drifts OVER past a stop as it arrives and settles back
## (Motion.arrival), then rests exactly on the stop.
const STYLES := ["logs"]
const Models = preload("res://presentation/kit/models.gd")
const PiecesRules = preload("res://core/physical/pieces_rules.gd")
const MODEL := "res://assets/models/raft.glb"
const LOG := Color("8a6a4c")
const LASHING := Color("c9b48a")
const ROPE := Color("c9b48a")
## Metres a second the raft travels, the simulation's own pace for it.
const RATE := PiecesRules.RAFT_CM_A_SECOND / 100.0
## How far past its stop the raft drifts as it arrives (m).
const OVER := 0.02

var _stops: Array[Vector3] = []
var _target := Vector3.ZERO
## The way the raft was going as it arrived.
var _heading := Vector3.ZERO

## A raft in `style` over `stops` (each the stop's centre at its walking
## height, parent space) of `size` (x, z metres) under `parent`, at stop 0.
static func build(raft_style: String, stops: Array[Vector3], size: Vector2, parent: Node3D) -> RefCounted:
	var piece: RefCounted = load("res://presentation/kit/pieces/raft.gd").new()
	piece._make(raft_style if raft_style in STYLES else "logs", stops, size, parent)
	return piece

## Shows the raft at stop `index`: eased there, or at once.
func set_value(index: int, immediate: bool = false) -> void:
	if index < 0 or index >= _stops.size(): return
	if _stops[index] != _target or immediate: _stop_arrival()
	_target = _stops[index]
	if immediate: root.position = _target

func moving() -> bool:
	return _arriving() or root.position != _target

func advance(delta: float) -> void:
	if not moving(): return
	if _arriving():
		root.position = _target + _heading * _arrival_step(delta)
		return
	var was := root.position
	root.position = root.position.move_toward(_target, maxf(delta, 0.0) * RATE)
	if root.position.is_equal_approx(_target):
		root.position = _target
		_heading = (_target - was).normalized()
		_arrive(OVER)

func moving_parts() -> Array[Node3D]:
	return [root]

func _make(raft_style: String, stops: Array[Vector3], size: Vector2, parent: Node3D) -> void:
	style = raft_style
	_stops = stops
	_target = stops[0]
	_root("Raft_" + raft_style, stops[0], parent, false)
	anchor = root
	# The log raft model (built 1.0 by 0.8 m, logs along x), stretched to the
	# stop with its logs along the stop's long side.
	var across_x := size.x <= size.y
	var deck := Models.moving(MODEL, "raft", {"log_a": LOG, "log_b": LOG.darkened(0.07), "lashing": LASHING, "bearer": Parts.TIMBER_DARK}, root)
	deck.scale = Vector3(maxf(size.x, size.y) / 1.0, 1.0, minf(size.x, size.y) / 0.8)
	if across_x: deck.rotation.y = PI / 2.0
	# The mast at the corner nearest the rope's line, and the rope between
	# two posts just beyond the first and last stops, through its ring.
	var corner := Vector3(size.x * 0.5 - 0.06, 0, -size.y * 0.5 + 0.06)
	var first := stops[0] + corner + Vector3(0, 0.6, 0)
	var last := stops[stops.size() - 1] + corner + Vector3(0, 0.6, 0)
	var line := (last - first)
	var mast := Models.moving(MODEL, "raft_mast", {"mast": Parts.TIMBER_DARK, "ring": Parts.IRON}, root)
	mast.position = corner
	# The ring faces along the rope's line.
	if Vector2(line.x, line.z).length() > 0.01: mast.rotation.y = atan2(line.x, line.z)
	var reach := line.normalized() * 0.5
	for post: Vector3 in [first - reach, last + reach]:
		Parts.box(Vector3(0.07, 0.95, 0.07), Parts.TIMBER_DARK, post - Vector3(0, 0.6, 0) + Vector3(0, 0.3, 0), parent)
	var rope := Parts.box(Vector3(0.02, 0.02, line.length() + 1.0), ROPE, (first + last) * 0.5, parent)
	if line.length() > 0.01: rope.basis = Basis.looking_at(line.normalized(), Vector3.UP if absf(line.normalized().y) < 0.99 else Vector3.RIGHT)
