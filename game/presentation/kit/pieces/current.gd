extends "res://presentation/kit/pieces/piece.gd"
## World kit: a current's legs (rules 16, core/physical/carried_items.gd) in one
## of its styles (content/dressing/prop_styles.gd "current"; piece_styles.gd
## picks which, a pin by the stage's first leg's control id first).
##
##   "ripples": short flat dashes on the water along each leg (the default).
##   "chevrons": small arrowheads pointing the way the leg carries.
##
## Each leg is a row of marks from its start to its end, laid on the water
## only: never on a floor, a crossing or a wall it passes over (the world's
## `keep` says where water shows). A leg on a body of water rides that body's
## level (set_level, called by the water kit's ride), so its marks sit on the
## water at every level.
## A leg whose wheel shows its value (the way the water runs now) is bright;
## the others are faint, so the screen shows where a float would go before the
## wheel turns. Every leg has its bright and faint rows built once; set_controls
## shows one of each, so a leg's two rows are its moving parts.
const STYLES := ["ripples", "chevrons"]
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

## [{"control", "value", "live": Node3D, "faint": Node3D}] per leg.
var _legs: Array = []

## A current in `current_style` under `parent`: `legs` as [{"from": Vector3,
## "to": Vector3, "control_id", "value"}] in the parent's space. `keep`
## (Callable(Vector3) -> bool, in the parent's space) says where a mark may lie:
## over open water; an empty one keeps every mark.
static func build(current_style: String, legs: Array, parent: Node3D, keep: Callable = Callable()) -> RefCounted:
	var piece: RefCounted = load("res://presentation/kit/pieces/current.gd").new()
	piece._keep = keep
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
		for shade: String in ["live", "faint"]:
			var row := Node3D.new()
			row.name = "Leg%d_%s" % [index, shade]
			root.add_child(row)
			_lay(row, leg.from, leg.to, LIVE if shade == "live" else FAINT, LIVE_LIFT if shade == "live" else 0.0)
			entry[shade] = row
		(entry.live as Node3D).visible = false
		_legs.append(entry)

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

## Leg `index`'s marks onto water standing at `level` (m, the parent's space).
func set_level(level: float, index: int) -> void:
	for shade: String in ["live", "faint"]: (_legs[index][shade] as Node3D).position.y = level

## Each leg bright while its control shows its value, faint otherwise.
func set_controls(controls: Dictionary) -> void:
	for leg: Dictionary in _legs:
		var live := str(controls.get(leg.control, "")) == str(leg.value)
		(leg.live as Node3D).visible = live
		(leg.faint as Node3D).visible = not live

func moving_parts() -> Array[Node3D]:
	var parts: Array[Node3D] = []
	for leg: Dictionary in _legs:
		parts.append(leg.live)
		parts.append(leg.faint)
	return parts
