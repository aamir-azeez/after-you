extends "res://presentation/kit/pieces/piece.gd"
## World kit: a crossing's deck that rolls up while its crossing is shut and
## unrolls across the gap as it opens: every plank or rope deck a pad, plate,
## crank or lever opens and shuts (cooperative_world _rolls_deck), one rule
## for all of them. Shut, the deck is gone and its slats lie wound round a log
## at the gap's near end (the Blender rope_bridge.glb "rope_roll", tinted the
## deck's colours), the log across the crossing and the loose end hanging
## toward the far bank. Opening, the roll runs across the gap over SECONDS
## and the deck grows behind it from the near end; shutting, it winds back.
##   var piece := BridgeRoll.build(deck, parent, place, span, across_x, low, high, near_high, colors)
##   piece.set_open(state.bridges[id], immediate)   # each snapshot
##   if piece.moving(): piece.advance(delta)       # each frame
## Presentation only: the snapshot alone says when the crossing is walkable;
## an immediate call (a seek, a retry) or reduce motion snaps, so live play,
## the memory and a replay show the same.
const Models = preload("res://presentation/kit/models.gd")
## The wound-in deck (tools/blender/models/rope_bridge.py): 1 m wide along x,
## its roll this radius (m) round the axle at its origin, its loose end at +z.
const ROLL_MODEL := "res://assets/models/rope_bridge.glb"
const ROLL_RADIUS := 0.14
## How far the roll's side stands into the gap past the bank's edge, and how
## far its top stands over the walk (m).
const ROLL_IN := 0.03
const ROLL_TOP := 0.04
## How long an unroll or a roll-up takes (s).
const SECONDS := 0.6
## How thin the roll is once all its slats are laid (a share of ROLL_RADIUS).
const LAID := 0.4

## The deck this rolls (shown while any of it is laid) and the wound roll.
var deck: Node3D
var roll: Node3D
var _across_x := true
## Deck-local metres along the crossing: the near end of the gap, the far
## end, the deck's centre along its axis in its parent, and the way across.
var _near := 0.0
var _far := 0.0
var _centre := 0.0
var _toward := 1.0
var _width := 1.0
## How much of the deck is laid (0 shut, 1 open) and where it is going.
var _laid := 0.0
var _target := 0.0

## Rolls `deck` (a crossing's deck node, `span` m across its run, along x
## when `across_x`, its gap low..high in deck-local metres) and lays its roll
## under `parent` at the deck's `place`, at the low end unless `near_high`.
## `colors` tints the roll's slots (slat, slat_dark, rope, log).
static func build(rolled: Node3D, parent: Node3D, place: Vector3, span: float, across_x: bool, low: float, high: float, near_high: bool, colors: Dictionary) -> RefCounted:
	var piece: RefCounted = load("res://presentation/kit/pieces/bridge_roll.gd").new()
	piece._make(rolled, parent, place, span, across_x, low, high, near_high, colors)
	return piece

func _make(rolled: Node3D, parent: Node3D, place: Vector3, span: float, across_x: bool, low: float, high: float, near_high: bool, colors: Dictionary) -> void:
	style = "roll"
	deck = rolled
	_across_x = across_x
	_near = high if near_high else low
	_far = low if near_high else high
	_toward = -1.0 if near_high else 1.0
	_width = span
	_centre = deck.position.x if across_x else deck.position.z
	_root("BridgeRoll", place, parent, false)
	anchor = root
	roll = Models.moving(ROLL_MODEL, "rope_roll", colors, root)
	roll.name = "RollWound"
	_apply()

## The angle the roll turns about the vertical so its axle lies across the
## crossing and its loose end faces the far bank (the model's +z): its run
## direction, as a turn of +z.
func facing() -> float:
	if _across_x: return PI * 0.5 * _toward
	return 0.0 if _toward > 0.0 else PI

## Opens or shuts the crossing; immediate (or reduce motion) snaps.
func set_open(on: bool, immediate: bool = false) -> void:
	_target = 1.0 if on else 0.0
	if immediate or reduced_motion: _laid = _target
	_apply()

## The gap's near and far ends on the crossing's middle line, in the parent's
## space (at the roll's root height).
func gap_ends() -> Array[Vector3]:
	var axis := Vector3.RIGHT if _across_x else Vector3.BACK
	return [root.position + axis * _near, root.position + axis * _far]

func is_open() -> bool:
	return _target > 0.5

func moving() -> bool:
	return _laid != _target

func advance(delta: float) -> void:
	_laid = move_toward(_laid, _target, maxf(delta, 0.0) / SECONDS)
	_apply()

func moving_parts() -> Array[Node3D]:
	return [deck, root]

## Where the deck and its roll stand at `_laid`, eased.
func _apply() -> void:
	var laid := smoothstep(0.0, 1.0, _laid)
	deck.visible = laid > 0.0
	# The deck grows from the near end: its near edge stays put. Hidden, it
	# rests whole where it was built, so no plank lies folded onto another.
	var grow := laid if laid > 0.0 else 1.0
	deck.scale = Vector3(grow, 1.0, 1.0) if _across_x else Vector3(1.0, 1.0, grow)
	var along := _centre + _near * (1.0 - grow)
	if _across_x: deck.position.x = along
	else: deck.position.z = along
	roll.visible = laid < 1.0
	var thick := lerpf(1.0, LAID, laid)
	var radius := ROLL_RADIUS * thick
	# A gap shorter than the roll keeps it on the near half.
	var inset := minf(radius + ROLL_IN, absf(_far - _near) * 0.5)
	var start := _near + _toward * inset
	var travel := absf(_far - _near) - 2.0 * inset
	var at := start + _toward * maxf(travel, 0.0) * laid
	roll.position = Vector3(at, ROLL_TOP - radius, 0.0) if _across_x else Vector3(0.0, ROLL_TOP - radius, at)
	roll.basis = Basis(Vector3.UP, facing()) * Basis.from_scale(Vector3(_width, thick, thick))
