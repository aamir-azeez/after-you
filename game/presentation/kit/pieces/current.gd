extends "res://presentation/kit/pieces/piece.gd"
## World kit: a current's legs (rules 20, core/physical/carried_items.gd) in one
## of its styles (content/dressing/prop_styles.gd "current"; piece_styles.gd
## picks which: a pin by the stage's first leg's `from` spot id, then by its
## control id, then the dressing's pick).
##
##   "ripples": short flat dashes on the water along each leg (the default).
##   "chevrons": small arrowheads pointing the way the leg carries.
##   "bucket": a hoist for a leg that lifts an item up to another floor (a
##       wheel winding a bucket up to a ledge): a rope line overhead from a
##       post beside the leg's start to one beside its end, a cream ring on
##       the floor at the start where the item goes in, and a wide bucket
##       (models/hoist_bucket.py) on a trolley that runs along the line. While
##       the leg runs (its wheel shows its value, its `when` holds and its
##       `stop` does not) the bucket is wound up off the start, across under
##       the line and set down at the end; otherwise it rides back down to
##       the start. An item resting in it rides with it (carry).
##
## Each marks leg is a row of marks from its start to its end, laid on the water
## only: never on a floor, a crossing or a wall it passes over (the world's
## `keep` says where water shows). A leg on a body of water rides that body's
## level (set_level, called by the water kit's ride), so its marks sit on the
## water at every level.
## A leg whose wheel shows its value (the way the water runs now) is bright;
## the others are faint, so the screen shows where a float would go before the
## wheel turns. Every leg has its bright and faint rows built once; set_controls
## shows one of each, so a leg's two rows are its moving parts.
## A bucket's pose is a function of how far along its path it is (0 at the
## start, 1 at the end); each frame it runs toward where the snapshot says at
## BUCKET_SPEED, and an immediate present snaps it, so live play, the memory
## and a replay show it the same.
const Seven = preload("res://core/journey/seven_mechanisms.gd")
const Models = preload("res://presentation/kit/models.gd")
const Primitives = preload("res://presentation/kit/primitives.gd")
const STYLES := ["ripples", "chevrons", "bucket"]
## The styles that lay marks on the water.
const MARKS := ["ripples", "chevrons"]
## How far apart the marks stand along a leg (m), and how far in from its ends.
const SPACING := 0.3
const INSET := 0.18
const LIVE := Color("eef6f2")
const FAINT := Color("8fb3b4")
## A mark's middle over its leg's water (m), clear of the rings and foam. The
## bright row stands LIVE_LIFT over the faint one, so the two rows never
## share a face.
const MARK_HEIGHT := 0.035
const LIVE_LIFT := 0.012

## A bucket's model (tools/blender/models/hoist_bucket.py) and its colours.
const HOIST := "res://assets/models/hoist_bucket.glb"
const HOIST_COLORS := {"bucket_wood": Color("a07850"), "metal": Color("4f5458"), "wood": Color("7a5d45")}
const ROPE := Color("d1b98c")
## The line stands this far over the higher of its two floors, the bucket
## travels this far over it (clear of the higher floor's edge), and the posts
## stand this far beside the line (m).
const LINE_OVER := 1.15
const TRAVEL_OVER := 0.12
const POST_SIDE := 0.5
const POST := 0.09
## Where the bucket's rope ties on: its bail's top over its foot, and the
## trolley's hook under the line (m, models/hoist_bucket.py).
const BAIL_TOP := 0.36
const HOOK := 0.205
const ROPE_RADIUS := 0.012
## How fast a bucket runs along its path (m/s): up, across and down.
const BUCKET_SPEED := 2.4
## An item rides on the bucket's floor, this far over its foot (m).
const SEAT := 0.02
## The ring where the item goes in (m), when the leg gives no radius.
const RING := 0.3

## [{"control", "value", "live": Node3D, "faint": Node3D}] per marks leg;
## [{"control", "value", "when", "stop", "from_id", "to_id", "start", "end",
## "line", "travel", "trolley", "bucket", "rope", "shown", "target"}] per
## bucket leg.
var _legs: Array = []
## A bucket style's stage (Seven.predicate reads its pads and controls) and
## whether its controls are open to either pip.
var _stage: Dictionary = {}
var _open := false
## Item id -> the bucket leg it rides in now.
var _riders: Dictionary = {}

## A current in `current_style` under `parent`: `legs` as [{"from": Vector3,
## "to": Vector3, "control_id", "value"}] in the parent's space (a bucket leg
## also "from_id" and "to_id", its spots, and "when" and "stop" as the stage
## gives them). `keep` (Callable(Vector3) -> bool, in the parent's space) says
## where a mark may lie: over open water; an empty one keeps every mark.
## `stage` is the stage the legs belong to, read by a bucket's `when` and `stop`.
static func build(current_style: String, legs: Array, parent: Node3D, keep: Callable = Callable(), stage: Dictionary = {}) -> RefCounted:
	var piece: RefCounted = load("res://presentation/kit/pieces/current.gd").new()
	piece._keep = keep
	piece._stage = stage
	piece._open = stage.get("pressure_pads", []).any(func(pad: Dictionary) -> bool: return str(pad.get("owner_slot", "")).is_empty())
	piece._make(current_style if current_style in STYLES else "ripples", legs, parent)
	return piece

var _keep: Callable

func _make(current_style: String, legs: Array, parent: Node3D) -> void:
	style = current_style
	_root("Current", Vector3.ZERO, parent, false)
	anchor = root
	for index in range(legs.size()):
		var leg: Dictionary = legs[index]
		var entry := {"control": str(leg.control_id), "value": str(leg.value)}
		if style == "bucket":
			_legs.append(_hoist(index, leg, entry))
			continue
		for shade: String in ["live", "faint"]:
			var row := Node3D.new()
			row.name = "Leg%d_%s" % [index, shade]
			root.add_child(row)
			_lay(row, leg.from, leg.to, LIVE if shade == "live" else FAINT, LIVE_LIFT if shade == "live" else 0.0)
			entry[shade] = row
		(entry.live as Node3D).visible = false
		_legs.append(entry)

## One bucket leg: its posts, line and ring (still, folded with the scenery)
## and its trolley, hanging rope and bucket (moving), the bucket at the start.
func _hoist(index: int, leg: Dictionary, entry: Dictionary) -> Dictionary:
	var start: Vector3 = leg.from
	var end: Vector3 = leg.to
	var line_y := maxf(start.y, end.y) + LINE_OVER
	entry.merge({"when": leg.get("when", {}), "stop": leg.get("stop", {}), "from_id": str(leg.get("from_id", "")), "to_id": str(leg.get("to_id", "")),
		"start": start, "end": end, "line": line_y, "travel": maxf(start.y, end.y) + TRAVEL_OVER, "shown": 0.0, "target": 0.0})
	var rig := Node3D.new()
	rig.name = "Hoist%d" % index
	root.add_child(rig)
	var flat := Vector3(end.x - start.x, 0, end.z - start.z)
	var along := flat.normalized() if flat.length() > 0.01 else Vector3.FORWARD
	# The posts stand beside the line, on the camera's right or, for a line
	# across the screen, behind it, so neither hides the bucket.
	var side := Vector3(-along.z, 0, along.x)
	if side.x - side.z < 0.0: side = -side
	for point: Vector3 in [start, end]:
		var foot := point + side * POST_SIDE
		var tall := line_y + 0.1 - point.y
		Parts.box(Vector3(POST, tall, POST), Parts.TIMBER, foot + Vector3(0, tall / 2.0, 0), rig)
		Parts.box(Vector3(0.2, 0.06, 0.2), Parts.STONE, foot + Vector3(0, 0.03, 0), rig)
		# The arm from the post's top out over the line's end, and its wheel.
		var arm := Parts.box(Vector3(0.07, 0.07, POST_SIDE + 0.08), Parts.TIMBER_DARK, Vector3((foot.x + point.x) / 2.0, line_y + 0.06, (foot.z + point.z) / 2.0), rig)
		arm.basis = Basis(Vector3.UP, atan2(side.x, side.z))
		var wheel := Primitives.mesh_node(Primitives.shared_mesh("cylinder", 0.07, 0.03, 0.07), Primitives.shared_material(Parts.IRON), Vector3(point.x, line_y + 0.06, point.z), rig)
		wheel.basis = Basis(Quaternion(Vector3.UP, side))
	# The line from wheel to wheel.
	var span := Vector3(end.x - start.x, 0, end.z - start.z)
	if span.length() > 0.01:
		var line := Primitives.mesh_node(Primitives.shared_mesh("cylinder", ROPE_RADIUS, span.length(), ROPE_RADIUS), Primitives.shared_material(ROPE), Vector3(start.x, line_y, start.z) + span / 2.0, rig)
		line.basis = Basis(Quaternion(Vector3.UP, span.normalized()))
	# The cream ring where the item goes in.
	Parts.ring(float(leg.get("radius", RING)), Parts.CREAM, start + Vector3(0, 0.03, 0), rig)
	var trolley := Models.moving(HOIST, "hoist_trolley", HOIST_COLORS, root, false)
	trolley.name = "HoistTrolley%d" % index
	trolley.basis = Basis(Vector3.UP, atan2(along.x, along.z))
	var bucket := Models.moving(HOIST, "hoist_bucket", HOIST_COLORS, root, false)
	# Its bail across the screen, the way a bucket is drawn.
	bucket.name = "HoistBucket%d" % index
	var rope := Primitives.mesh_node(Primitives.shared_mesh("cylinder", ROPE_RADIUS, 1.0, ROPE_RADIUS), Primitives.shared_material(ROPE), Vector3.ZERO, root)
	rope.name = "HoistRope%d" % index
	entry.merge({"trolley": trolley, "bucket": bucket, "rope": rope})
	_pose(entry)
	return entry

## The marks of one leg along `from` to `to`, each turned along the leg: one
## mesh a row (a mark is a few boxes), so a long current is one node and one
## draw a row, however many marks it has.
func _lay(row: Node3D, from: Vector3, to: Vector3, color: Color, lift: float) -> void:
	var flat := Vector3(to.x - from.x, 0, to.z - from.z)
	var length := flat.length()
	if length < 0.01: return
	var along := flat / length
	var count := maxi(1, int(floor((length - 2.0 * INSET) / SPACING)) + 1)
	var turn := Basis(Vector3.UP, atan2(along.x, along.z))
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var laid := 0
	for index in range(count):
		var t := INSET + (length - 2.0 * INSET) * (float(index) / maxf(1.0, float(count - 1)) if count > 1 else 0.5)
		var at := from + along * t
		if _keep.is_valid() and not bool(_keep.call(at)): continue
		var mark := Transform3D(turn, Vector3(at.x, MARK_HEIGHT + lift, at.z))
		laid += 1
		if style == "chevrons":
			for side: float in [-1.0, 1.0]:
				var arm := Transform3D(Basis(Vector3.UP, side * 0.7), Vector3(side * 0.035, 0.004 * side, -0.03))
				tool.append_from(Parts.Primitives.cached_box(Vector3(0.025, 0.012, 0.11)), 0, mark * arm)
		else:
			tool.append_from(Parts.Primitives.cached_box(Vector3(0.035, 0.01, 0.16)), 0, mark)
	row.position.y = from.y
	if laid == 0: return
	var marks := Parts.Primitives.mesh_node(tool.commit(), Parts.Primitives.shared_material(color), Vector3.ZERO, row)
	marks.name = "Marks"

## Leg `index`'s marks onto water standing at `level` (m, the parent's space);
## a bucket rides no water.
func set_level(level: float, index: int) -> void:
	if style == "bucket": return
	for shade: String in ["live", "faint"]: (_legs[index][shade] as Node3D).position.y = level

## Each marks leg bright while its control shows its value, faint otherwise.
func set_controls(controls: Dictionary) -> void:
	if style == "bucket": return
	for leg: Dictionary in _legs:
		var live := str(controls.get(leg.control, "")) == str(leg.value)
		(leg.live as Node3D).visible = live
		(leg.faint as Node3D).visible = not live

## Each snapshot: the marks lit by their wheels, or each bucket sent up while
## its leg runs and back down while it does not; an immediate call snaps.
func present(state: Dictionary, immediate: bool = false) -> void:
	set_controls(state.get("controls", {}))
	if style != "bucket": return
	for leg: Dictionary in _legs:
		leg.target = 1.0 if runs(leg, state) else 0.0
		if immediate: leg.shown = leg.target
		_pose(leg)

## Whether a bucket leg runs in `state`: its wheel shows its value, its
## `when` holds and its `stop` does not (carried_items.gd, the leg's own terms).
func runs(leg: Dictionary, state: Dictionary) -> bool:
	if not str(leg.control).is_empty() and str(state.get("controls", {}).get(leg.control, "")) != str(leg.value): return false
	var mechanisms: Variant = state.get("mechanisms")
	if not mechanisms is Dictionary: return (leg.when as Dictionary).is_empty()
	var players: Dictionary = state.get("players", {})
	var signals: Dictionary = state.get("optics", {}).get("signals", {})
	if not (leg.when as Dictionary).is_empty() and not Seven.predicate(leg.when, _stage, players, mechanisms, signals, _open): return false
	return (leg.stop as Dictionary).is_empty() or not Seven.predicate(leg.stop, _stage, players, mechanisms, signals, _open)

## Where item `id`, resting at spot `spot`, is drawn when a bucket holds it
## (on the bucket's floor), else null: in the bucket at a leg's start, and at
## its end while the leg runs, once the bucket stands there or while it brings
## the item (it rode from the start). An item already resting at the end when
## the leg starts to run waits on the floor there until the bucket arrives.
func carry(id: String, spot: String, immediate: bool = false) -> Variant:
	if style == "bucket" and not spot.is_empty():
		for index in range(_legs.size()):
			var leg: Dictionary = _legs[index]
			var riding := spot == str(leg.from_id) or (spot == str(leg.to_id) and float(leg.target) == 1.0 and (float(leg.shown) >= 1.0 or (not immediate and int(_riders.get(id, -1)) == index)))
			if riding:
				_riders[id] = index
				return seat(id)
	_riders.erase(id)
	return null

## The floor of the bucket item `id` rides in now (the parent's space), or null.
func seat(id: String) -> Variant:
	if not _riders.has(id): return null
	return (_legs[int(_riders[id])].bucket as Node3D).position + Vector3(0, SEAT, 0)

func moving() -> bool:
	return style == "bucket" and _legs.any(func(leg: Dictionary) -> bool: return not is_equal_approx(float(leg.shown), float(leg.target)))

## A frame: each bucket runs on along its path toward where it is sent.
func advance(delta: float) -> void:
	for leg: Dictionary in _legs:
		var runs_m := _path(leg)
		leg.shown = move_toward(float(leg.shown), float(leg.target), delta * BUCKET_SPEED / maxf(runs_m.x + runs_m.y + runs_m.z, 0.01))
		_pose(leg)

## A bucket leg's three runs (m): up off its start, across under the line,
## down onto its end.
func _path(leg: Dictionary) -> Vector3:
	var start: Vector3 = leg.start
	var end: Vector3 = leg.end
	return Vector3(float(leg.travel) - start.y, Vector2(end.x - start.x, end.z - start.z).length(), float(leg.travel) - end.y)

## Puts a bucket leg's trolley, rope and bucket where `shown` has them: wound
## up off the start, run across, set down on the end, each run eased.
func _pose(leg: Dictionary) -> void:
	var runs_m := _path(leg)
	var walked := float(leg.shown) * maxf(runs_m.x + runs_m.y + runs_m.z, 0.01)
	var start: Vector3 = leg.start
	var end: Vector3 = leg.end
	var across := 0.0
	var foot := float(leg.travel)
	if walked < runs_m.x: foot = lerpf(start.y, float(leg.travel), smoothstep(0.0, 1.0, walked / maxf(runs_m.x, 0.001)))
	elif walked < runs_m.x + runs_m.y: across = smoothstep(0.0, 1.0, (walked - runs_m.x) / maxf(runs_m.y, 0.001))
	else:
		across = 1.0
		foot = lerpf(float(leg.travel), end.y, smoothstep(0.0, 1.0, (walked - runs_m.x - runs_m.y) / maxf(runs_m.z, 0.001)))
	var over := Vector3(lerpf(start.x, end.x, across), float(leg.line), lerpf(start.z, end.z, across))
	(leg.trolley as Node3D).position = over
	(leg.bucket as Node3D).position = Vector3(over.x, foot, over.z)
	var top := float(leg.line) - HOOK
	var low := foot + BAIL_TOP
	var rope := leg.rope as Node3D
	rope.scale = Vector3(1, maxf(top - low, 0.01), 1)
	rope.position = Vector3(over.x, (top + low) / 2.0, over.z)

func moving_parts() -> Array[Node3D]:
	var parts: Array[Node3D] = []
	for leg: Dictionary in _legs:
		for key: String in ["live", "faint", "trolley", "bucket", "rope"]:
			if leg.has(key): parts.append(leg[key])
	return parts
