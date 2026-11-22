extends "res://presentation/kit/pieces/piece.gd"
## World kit: a swing (core/physical/swings.gd) in one of its styles
## (content/dressing/prop_styles.gd "swing"; content/dressing/piece_styles.gd
## picks which, a pin by the swing's id first):
##
##   "crane_bucket": an old timber crane standing on the ground at the swing's
##       pivot, its jib turned along the axis the swing crosses its lane on,
##       and a wooden bucket on a rope from the jib's tip
##       (tools/blender/models/well_crane.py).
##
## The piece draws the beat the snapshot gives ({"phase", "pass", "held"} per
## swing) where the simulation has it, tick for tick (core/physical/swings.gd):
## the bucket swings to and fro in the jib's plane, one pass a beat. A pass
## starts still at one side, swings in through the warning (it creaks),
## crosses the lane at a steady pace over the sweep, its middle on sweep tick
## i over the middle (i + 1/2) / sweep of the way across (the lane's near edge
## to its far edge on even passes, back on odd ones), then swings up and out
## to the other side over the rest, slowing to a stop: Hermite curves, still
## at each end, carry the lane's pace on smoothly past its edges. So the
## bucket is over the lane exactly on the sweep ticks, and over a pip exactly
## when the simulation knocks it off (Swings.struck). Held, it waits still at
## the top of its swing. The pose is a pure function of the pass's time
## (pose()); between snapshots the shown time runs on at the simulation's tick
## rate and never more than LEAD ticks past the last one, and falls back onto
## it smoothly (or snaps when far off or on an immediate call), so it looks
## the same at any frame rate, live, in a memory and in a replay, and stops
## when play stops. Presentation only: nothing here feeds the simulation.
const Models = preload("res://presentation/kit/models.gd")
const Swings = preload("res://core/physical/swings.gd")
const STYLES := ["crane_bucket"]
const CRANE := "res://assets/models/well_crane.glb"
const TICK_RATE := 30.0
## How far past the last snapshot the shown time may run (ticks), and how far
## behind it may be before it snaps (ticks).
const LEAD := 1.5
const SNAP := 8.0
## How far past the lane's edge a knocked pip is shoved (m).
const SHOVE_CLEAR := 0.3
const COLORS := {"stone": Color("9a8d76"), "wood": Color("7a5d45"), "wood_dark": Color("5f4a38"), "metal": Color("4f5458"), "rope": Color("d1b98c"), "bucket_wood": Color("a07850")}

## The swing's beat (ticks).
var period := 90
var sweep := 30
var warn := 30
## The node the bucket swings in (at the jib's tip, its z along the jib).
var hanger: Node3D
## The bucket's middle in the hanger's space, hanging plumb under the tip.
var bucket := Vector3.ZERO
## Along the jib from the crane's foot (m): the lane's near and far edges, and
## where a pass starts or ends still on the near and the far side.
var _near := 0.0
var _far := 0.0
var _still_near := 0.0
var _still_far := 0.0
## The shown time and the snapshot's in the two-pass cycle (ticks, 0 to
## 2 * period): the pass (0 or 1) * period + ticks since that pass started.
var _shown := 0.0
var _target := 0.0
var _held := false

## A swing in `swing_style` for the stage's `swing` (its definition entry),
## the crane standing at `ground` metres (the floor under its pivot), under
## `parent` (the terrain). `_lane_height` is the lane's floor (m).
static func build(swing_style: String, swing: Dictionary, ground: float, lane_height: float, parent: Node3D) -> RefCounted:
	var piece: RefCounted = load("res://presentation/kit/pieces/swing.gd").new()
	piece._make(swing_style if swing_style in STYLES else STYLES[0], swing, ground, lane_height, parent)
	return piece

func _make(swing_style: String, swing: Dictionary, ground: float, _lane_height: float, parent: Node3D) -> void:
	style = swing_style
	period = int(swing.period_ticks)
	sweep = int(swing.sweep_ticks)
	warn = int(swing.warn_ticks)
	var pivot := Vector3(float(swing.pivot_cm[0]) / 100.0, ground, float(swing.pivot_cm[1]) / 100.0)
	_root("Swing_" + str(swing.id), pivot, parent)
	# The jib (the model's +z) along the axis the swing crosses on, toward the
	# lane's far edge.
	var across := Swings.axis(swing)
	var ends := Swings.edges(swing)
	var foot := float(swing.pivot_cm[across])
	var out := 1.0 if float(ends[1]) >= foot else -1.0
	root.rotation.y = out * PI / 2.0 if across == 0 else (0.0 if out > 0.0 else PI)
	_near = (float(ends[0]) - foot) * out / 100.0
	_far = (float(ends[1]) - foot) * out / 100.0
	Models.still(CRANE, "crane_mast", COLORS, root)
	hanger = Node3D.new()
	hanger.name = "SwingHanger"
	hanger.transform = Models.transform(CRANE, "crane_bucket")
	root.add_child(hanger)
	Models.moving(CRANE, "crane_bucket", COLORS, hanger, false)
	anchor = hanger
	bucket = _bucket_middle()
	# Each pass swings in from still, and out to still, at the lane's pace.
	var reach := (_far - _near) / float(maxi(sweep, 1)) * float(period - sweep) / 4.0
	_still_near = _near - reach
	_still_far = _far + reach
	_pose()

## The bucket's middle in the hanger's space: under the tip, half its depth
## along the jib over the bottom of what hangs.
func _bucket_middle() -> Vector3:
	var box := AABB()
	var first := true
	for node: Node in hanger.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var xform := Transform3D.IDENTITY
		var walk: Node = mesh
		while walk != hanger:
			xform = (walk as Node3D).transform * xform
			walk = walk.get_parent()
		var part: AABB = xform * mesh.mesh.get_aabb()
		box = part if first else box.merge(part)
		first = false
	return Vector3(0.0, box.position.y + box.size.z / 2.0, 0.0)

## Where the bucket's middle is along the jib (m from the crane's foot) at
## `time` ticks into the two-pass cycle.
func along(time: float) -> float:
	var at := fposmod(time, float(period * 2))
	var back := at >= float(period)
	var q := at - (float(period) if back else 0.0)
	var start := _still_far if back else _still_near
	var from := _far if back else _near
	var to := _near if back else _far
	var end := _still_near if back else _still_far
	var pace := (to - from) / float(maxi(sweep, 1))
	if q < float(warn): return _hermite(start, 0.0, from, pace * float(warn), q / float(warn))
	if q <= float(warn + sweep): return from + pace * (q - float(warn))
	var rest := float(period - warn - sweep)
	return _hermite(to, pace * rest, end, 0.0, (q - float(warn + sweep)) / rest)

## The swing's angle from plumb (radians, out along the jib positive) at
## `time` ticks into the two-pass cycle: its bucket's middle where along() says.
func pose(time: float) -> float:
	var drop := maxf(-bucket.y, 0.01)
	return asin(clampf((along(time) - hanger.position.z) / drop, -0.95, 0.95))

## The bucket's middle now, in the parent's space (the terrain's).
func bucket_point() -> Vector3:
	return root.transform * (hanger.transform * bucket)

## Where a pip at `at` (parent space), knocked off by the snapshot's sweep, is
## shoved to: just past the lane's edge the bucket is heading for, the same
## height. Where it already is when it stands past that edge.
func shove(at: Vector3) -> Vector3:
	var back := _target >= float(period)
	var jib := root.transform.basis.z.normalized()
	var along_jib := (at - root.position).dot(jib)
	var push := ((_near - SHOVE_CLEAR) if back else (_far + SHOVE_CLEAR)) - along_jib
	if (push > 0.0) == back: push = 0.0
	return at + jib * push

## A cubic from `a` (slope `va`) to `b` (slope `vb`) at `t` (0 to 1).
static func _hermite(a: float, va: float, b: float, vb: float, t: float) -> float:
	var s := clampf(t, 0.0, 1.0)
	var s2 := s * s
	var s3 := s2 * s
	return (2.0 * s3 - 3.0 * s2 + 1.0) * a + (s3 - 2.0 * s2 + s) * va + (3.0 * s2 - 2.0 * s3) * b + (s3 - s2) * vb

## The cycle time of a snapshot's {"phase", "pass"}: a pass starts half a
## tick before its first warning tick, so each whole tick falls inside its part.
func time_of(view: Dictionary) -> float:
	var phase := float(int(view.get("phase", 0)))
	var start := float(period - sweep - warn) - 0.5
	var q := phase - start if phase >= start else phase + float(period) - start
	return float(int(view.get("pass", 0))) * float(period) + q

## Each snapshot: the swing's {"phase", "pass", "held"}; an immediate call snaps.
func set_beat(view: Dictionary, immediate: bool = false) -> void:
	_target = time_of(view)
	_held = bool(view.get("held", false))
	if immediate or absf(_ahead(_target, _shown)) > SNAP: _shown = _target
	_pose()

func moving() -> bool:
	return absf(_ahead(_limit(), _shown)) > 0.001

## A frame: the shown time runs on at the tick rate (not while held), never
## past LEAD ticks beyond the last snapshot.
func advance(delta: float) -> void:
	var step := maxf(delta, 0.0) * TICK_RATE
	var gap := _ahead(_limit(), _shown)
	_shown = fposmod(_shown + clampf(gap, -step, step), float(period * 2))
	_pose()

func moving_parts() -> Array[Node3D]:
	return [hanger]

func _limit() -> float:
	return _target if _held else fposmod(_target + LEAD, float(period * 2))

## How far `a` is ahead of `b` round the cycle, in (-period, period].
func _ahead(a: float, b: float) -> float:
	return fposmod(a - b + float(period), float(period * 2)) - float(period)

func _pose() -> void:
	hanger.rotation.x = -pose(_shown)
