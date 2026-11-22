extends "res://presentation/kit/pieces/piece.gd"
## World kit: a swing (core/physical/swings.gd) in one of its styles
## (content/dressing/prop_styles.gd "swing"; content/dressing/piece_styles.gd
## picks which, a pin by the swing's id first):
##
##   "crane_bucket": an old timber crane standing on the ground at the swing's
##       pivot, its jib turned to reach over the lane, and a wooden bucket on a
##       rope from the jib's tip (tools/blender/models/well_crane.py).
##
## The piece draws the beat the snapshot gives ({"phase", "held"} per swing):
## hanging back out of the lane the rest of the beat (and while held), drawn
## further back as it creaks through the warning while its shadow grows on the
## lane, then swinging out across the lane and back for the sweep. The bucket
## swings in the jib's plane: back toward the mast (never as far as it) and out
## past the lane's far side, so hanging back it is off the lane. The pose is a pure
## function of the beat's phase (pose()); between snapshots the shown phase
## runs on at the simulation's tick rate and never more than LEAD ticks past
## the last one, and falls back onto it smoothly (or snaps when far off or on
## an immediate call), so it looks the same at any frame rate and stops when
## play stops. Presentation only: nothing here feeds the simulation.
const Models = preload("res://presentation/kit/models.gd")
const Primitives = preload("res://presentation/kit/primitives.gd")
const STYLES := ["crane_bucket"]
const CRANE := "res://assets/models/well_crane.glb"
const TICK_RATE := 30.0
## How far past the last snapshot the shown phase may run (ticks), and how far
## behind it may be before it snaps (ticks).
const LEAD := 1.5
const SNAP := 8.0
## The bucket's swing (radians from hanging plumb, out along the jib
## positive): hanging back between beats, drawn back at the end of the
## warning (still clear of the mast), and how far out its sweep reaches.
const BACK := 0.55
const DRAWN := 0.7
const OUT := 0.95
const SHADOW := Color(0.08, 0.07, 0.06, 0.38)
const COLORS := {"stone": Color("9a8d76"), "wood": Color("7a5d45"), "wood_dark": Color("5f4a38"), "metal": Color("4f5458"), "rope": Color("d1b98c"), "bucket_wood": Color("a07850")}

## The swing's beat (ticks).
var period := 90
var sweep := 30
var warn := 30
## The node the bucket swings in (at the jib's tip, its z along the jib) and
## the shadow on the lane.
var hanger: Node3D
var shadow: MeshInstance3D
var _shown := 0.0
var _target := 0.0
var _held := false

## A swing in `swing_style` for the stage's `swing` (its definition entry),
## the crane standing at `ground` metres (the floor under its pivot) and the
## lane's floor at `lane_height`, under `parent` (the terrain).
static func build(swing_style: String, swing: Dictionary, ground: float, lane_height: float, parent: Node3D) -> RefCounted:
	var piece: RefCounted = load("res://presentation/kit/pieces/swing.gd").new()
	piece._make(swing_style if swing_style in STYLES else STYLES[0], swing, ground, lane_height, parent)
	return piece

func _make(swing_style: String, swing: Dictionary, ground: float, lane_height: float, parent: Node3D) -> void:
	style = swing_style
	period = int(swing.period_ticks)
	sweep = int(swing.sweep_ticks)
	warn = int(swing.warn_ticks)
	var pivot := Vector3(float(swing.pivot_cm[0]) / 100.0, ground, float(swing.pivot_cm[1]) / 100.0)
	var r: Array = swing.lane.rect_cm
	var lane := Vector3(float(r[0] + r[2]) / 200.0, lane_height, float(r[1] + r[3]) / 200.0)
	_root("Swing_" + str(swing.id), pivot, parent)
	# The jib (the model's +z) turned toward the lane's middle.
	var toward := Vector2(lane.x - pivot.x, lane.z - pivot.z)
	if toward.length() > 0.01: root.rotation.y = atan2(toward.x, toward.y)
	Models.still(CRANE, "crane_mast", COLORS, root)
	hanger = Node3D.new()
	hanger.name = "SwingHanger"
	hanger.transform = Models.transform(CRANE, "crane_bucket")
	root.add_child(hanger)
	Models.moving(CRANE, "crane_bucket", COLORS, hanger, false)
	anchor = hanger
	# A soft shadow lying on the lane, as wide as the lane's narrow side.
	var size := minf(float(r[2] - r[0]), float(r[3] - r[1])) / 100.0
	var material := Primitives.fresh_material(SHADOW)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shadow = Primitives.mesh_node(Primitives.cylinder_mesh(size * 0.45, 0.004), material, lane + Vector3(0, 0.03, 0), parent)
	shadow.name = "SwingShadow_" + str(swing.id)
	_pose()

## The swing's angle from plumb (radians, out along the jib positive) and its
## shadow's size (0 to 1) at `phase` ticks into its beat.
func pose(phase: float) -> Vector2:
	var rest := float(period - sweep - warn)
	if phase < rest: return Vector2(-BACK, 0.0)
	if phase < rest + float(warn):
		var drawing := smoothstep(0.0, 1.0, (phase - rest) / float(warn))
		return Vector2(-lerpf(BACK, DRAWN, drawing), drawing)
	# Out across the lane, then back over it to hang back again.
	var t := clampf((phase - rest - float(warn)) / float(sweep), 0.0, 1.0)
	var angle := lerpf(-DRAWN, OUT, smoothstep(0.0, 1.0, t * 2.0)) if t < 0.5 else lerpf(OUT, -BACK, smoothstep(0.0, 1.0, t * 2.0 - 1.0))
	return Vector2(angle, 1.0 - smoothstep(0.85, 1.0, t))

## Each snapshot: the swing's {"phase", "held"}; an immediate call snaps.
func set_beat(view: Dictionary, immediate: bool = false) -> void:
	_target = float(int(view.get("phase", 0)))
	_held = bool(view.get("held", false))
	var behind := _ahead(_target, _shown)
	if immediate or absf(behind) > SNAP: _shown = _target
	_pose()

func moving() -> bool:
	return absf(_ahead(_limit(), _shown)) > 0.001

## A frame: the shown phase runs on at the tick rate (not while held), never
## past LEAD ticks beyond the last snapshot.
func advance(delta: float) -> void:
	var limit := _limit()
	var step := maxf(delta, 0.0) * TICK_RATE
	var gap := _ahead(limit, _shown)
	_shown = fposmod(_shown + clampf(gap, -step, step), float(period))
	_pose()

func moving_parts() -> Array[Node3D]:
	return [hanger, shadow]

func _limit() -> float:
	return _target if _held else fposmod(_target + LEAD, float(period))

## How far `a` is ahead of `b` round the beat, in (-period/2, period/2].
func _ahead(a: float, b: float) -> float:
	var half := float(period) / 2.0
	return fposmod(a - b + half, float(period)) - half

func _pose() -> void:
	var at := pose(_shown)
	hanger.rotation.x = -at.x
	shadow.scale = Vector3(maxf(at.y, 0.001), 1.0, maxf(at.y, 0.001))
	shadow.visible = at.y > 0.01
