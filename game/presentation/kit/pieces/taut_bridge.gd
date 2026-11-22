extends "res://presentation/kit/pieces/piece.gd"
## World kit: a crossing's deck that hangs slack while its crossing is shut and
## is pulled taut as it opens: every plank or rope deck a pad, plate, crank or
## lever opens and shuts (cooperative_world _pulls_deck), one rule for all of
## them. Shut, the deck sags between its banks along a curve its slack()
## deep in the middle (under the banks, dipping into the water where there is
## water), each plank, slat and stone dropped onto the curve and tilted to its
## slope, and each rail, rope and edge strip bent along it in short lengths.
## Opening, the ropes wind in: the sag eases out over SECONDS (Motion "inout")
## and the deck snaps level with a small bounce (Motion.arrival); shutting
## plays the same pull back, sagging down again.
##   var piece := TautBridge.build(deck, across_x, low, high)
##   piece.set_open(state.bridges[id], immediate)   # each snapshot
##   if piece.moving(): piece.advance(delta)       # each frame
## Only the deck's own parts move, and only while it changes; open, every
## part stands exactly as laid. Presentation only: the snapshot alone says
## when the crossing is walkable; an immediate call (a seek, a retry) or
## reduce motion snaps, so live play, the memory and a replay show the same.
## How long the ropes take to pull the deck taut, or to let it sag (s).
const SECONDS := 0.9
## How deep the slack deck's middle hangs under its ends: this share of the
## gap, at most SAG_MOST (m).
const SAG_SHARE := 0.4
const SAG_MOST := 1.1
## Every slack part hangs this much (m) under where it lies taut, so a deck that shuts level with
## the water's surface sinks under it instead of z-fighting with it.
const SLACK_DROP := 0.008
## A part this thin or thinner (m, a strip laid on a plank) stands off the plank THIN_LIFT (m) more
## while hung, as it tilts about its own middle.
const THIN := 0.01
const THIN_LIFT := 0.004
## How far (m) past level the deck bows up as it snaps taut, then settles.
const BOUNCE := 0.04
## A part at least this share of the gap long (a rail, a rope, an edge strip)
## bends along the curve in lengths of about BEND m, at most BENDS of them.
const LONG := 0.5
const BEND := 0.2
const BENDS := 8

## The deck this pulls (its node never moves; its parts do).
var deck: Node3D
var _across_x := true
## The gap's ends along the crossing, in deck-local metres.
var _low := 0.0
var _high := 1.0
## How taut the deck is (0 slack, 1 taut) and where it is going.
var _taut := 0.0
var _target := 0.0
## The deck's short parts: {node, rest (its own transform), to_deck (its
## parent's transform in the deck), pivot (its middle, deck space), squeeze (its
## thickness over its length along the crossing), lift (m)}.
var _parts: Array = []
## The deck's long parts and the lengths each bends in while it sags:
## {node, lengths: [{node, rest (deck space), pivot}]}.
var _long: Array = []
## Holds the bent lengths, under the deck (the piece's root).
var _bends: Node3D
## The deck's child count when its parts were found: a part laid on it later
## (a hand rope) finds them again.
var _children := -1
## The deck's parts drawn as a few merged meshes while it stands still (taut or hung): _bake()
## folds every plank, rail and rope into one mesh (a surface per look), so a deck costs a draw per
## look, not one per plank; any change unbakes it first. `_hidden` are the parts it hid.
var _merged: Array = []
var _hidden: Array = []
## The sag the parts were last put at (NAN: as laid, unplaced), so a
## snapshot that changes nothing moves nothing.
var _shown := NAN

## Pulls `deck` (a crossing's deck node, along x when `across_x`, its gap
## low..high in deck-local metres along the crossing), slack until set_open.
static func build(pulled: Node3D, across_x: bool, low: float, high: float) -> RefCounted:
	var piece: RefCounted = load("res://presentation/kit/pieces/taut_bridge.gd").new()
	piece._make(pulled, across_x, low, high)
	return piece

func _make(pulled: Node3D, across_x: bool, low: float, high: float) -> void:
	style = "taut"
	deck = pulled
	_across_x = across_x
	_low = minf(low, high)
	_high = maxf(maxf(low, high), _low + 0.01)
	# The root holds the bent lengths, at the deck's own origin.
	_bends = _root("SlackBends", Vector3.ZERO, deck, false)
	anchor = deck
	deck.visible = true
	_apply()

## How deep the slack deck's middle hangs (m).
func slack() -> float:
	return minf((_high - _low) * SAG_SHARE, SAG_MOST)

## Pulls the crossing taut or lets it sag; immediate (or reduce motion) snaps.
func set_open(on: bool, immediate: bool = false) -> void:
	_target = 1.0 if on else 0.0
	if immediate or reduced_motion:
		_taut = _target
		_stop_arrival()
	elif not on:
		_stop_arrival()
	_apply()

func is_open() -> bool:
	return _target > 0.5

func moving() -> bool:
	return _taut != _target or _arriving()

func advance(delta: float) -> void:
	if _taut != _target:
		_taut = move_toward(_taut, _target, maxf(delta, 0.0) / SECONDS)
		if _taut == 1.0: _arrive(BOUNCE)
	else:
		_arrival_step(delta)
	_apply()

func moving_parts() -> Array[Node3D]:
	return [deck]

## How far (m) the deck's middle hangs under its ends now: negative while it
## bows up past level.
func sag() -> float:
	var bounce := Motion.arrival(_arrival_age, _arrival_size) if _arriving() else 0.0
	return slack() * (1.0 - Motion.ease("inout", _taut)) - bounce

## How far (m) the deck hangs at `along` (deck-local m along the crossing)
## under a middle sag of `depth`, and its slope there (rise per metre).
func drop_at(along: float, depth: float) -> Vector2:
	var length := _high - _low
	var share := clampf((along - _low) / length, 0.0, 1.0)
	if share <= 0.0 or share >= 1.0: return Vector2.ZERO
	return Vector2(4.0 * depth * share * (1.0 - share), -4.0 * depth * (1.0 - 2.0 * share) / length)

## Every part where the sag now puts it: as laid once taut, else dropped onto
## the curve and tilted to it, the long ones in their bent lengths.
func _apply() -> void:
	_find_parts()
	var depth := sag()
	var laid := is_zero_approx(depth)
	if (laid and is_nan(_shown)) or depth == _shown:
		if not _is_baked() and not moving(): _bake()
		return
	unbake()
	_shown = NAN if laid else depth
	for long: Dictionary in _long:
		(long.node as Node3D).visible = laid
		for length: Dictionary in long.lengths: (length.node as Node3D).visible = not laid
	for part: Dictionary in _parts:
		var node: Node3D = part.node
		node.transform = part.rest if laid else (part.to_deck as Transform3D).affine_inverse() * _hung(part.pivot, depth, false, float(part.squeeze), float(part.lift)) * (part.to_deck as Transform3D) * (part.rest as Transform3D)
	if not laid:
		for long: Dictionary in _long:
			for length: Dictionary in long.lengths: (length.node as Node3D).transform = _hung(length.pivot, depth, true, float(length.squeeze)) * (length.rest as Transform3D)
	if not moving(): _bake()

func _is_baked() -> bool:
	return not _hidden.is_empty()

## Every visible part of the deck, merged into one mesh per look, in place of its own nodes.
func _bake() -> void:
	unbake()
	var groups: Dictionary = {}
	var sources: Array = []
	for part: Dictionary in _parts: sources.append(part.node)
	for long: Dictionary in _long:
		sources.append(long.node)
		for length: Dictionary in long.lengths: sources.append(length.node)
	for node: Node in sources:
		var mesh := node as MeshInstance3D
		if mesh == null or not is_instance_valid(mesh) or not mesh.visible or mesh.mesh == null: continue
		if mesh.mesh.get_surface_count() != 1 or mesh.material_override == null or mesh.material_overlay != null: continue
		var key := mesh.material_override.get_instance_id()
		if not groups.has(key):
			var tool := SurfaceTool.new()
			tool.begin(Mesh.PRIMITIVE_TRIANGLES)
			groups[key] = {"tool": tool, "material": mesh.material_override, "shadow": mesh.cast_shadow}
		var placed := _to_deck(mesh.get_parent()) * mesh.transform
		(groups[key].tool as SurfaceTool).append_from(mesh.mesh, 0, placed)
		_hidden.append(mesh)
	if groups.is_empty(): return
	var merged_mesh := ArrayMesh.new()
	var shadow := GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for group: Dictionary in groups.values():
		(group.tool as SurfaceTool).set_material(group.material)
		(group.tool as SurfaceTool).commit(merged_mesh)
		shadow = group.shadow
	var merged := MeshInstance3D.new()
	merged.name = "Baked"
	merged.mesh = merged_mesh
	merged.cast_shadow = shadow
	_bends.add_child(merged)
	_merged.append(merged)
	for mesh: Node3D in _hidden: mesh.visible = false

## Gives the deck its own parts back.
func unbake() -> void:
	for mesh: Node3D in _hidden:
		if is_instance_valid(mesh): mesh.visible = true
	_hidden.clear()
	for merged: Node in _merged: merged.free()
	_merged.clear()

## The move (deck space) that hangs a part whose middle is `pivot` on the
## curve: dropped, tilted to the slope about its middle and, for a bent length
## (`stretch`), drawn out so the lengths still meet along the slope.
func _hung(pivot: Vector3, depth: float, stretch: bool, squeeze: float = 0.0, lift: float = 0.0) -> Transform3D:
	var along := pivot.x if _across_x else pivot.z
	var hang := drop_at(along, depth)
	var tilt := atan(hang.y)
	var turn := Basis(Vector3.BACK, tilt) if _across_x else Basis(Vector3.RIGHT, -tilt)
	if stretch:
		# Narrowed by the thickness the tilt swings past the next length, as a plank is.
		var out := maxf(1.0 / maxf(cos(tilt), 0.2) - squeeze * absf(sin(tilt)) - 0.04 * minf(squeeze * 4.0, 1.0), 0.5)
		turn = turn * Basis.from_scale(Vector3(out, 1.0, 1.0) if _across_x else Vector3(1.0, 1.0, out))
	elif squeeze > 0.0:
		# A short part (a plank) tilted on the slope swings its corners past its
		# neighbours' (thickness x sin of the tilt): narrowed by that, so planks
		# never overlap and their end faces never z-fight.
		var narrow := maxf(1.0 - squeeze * absf(sin(tilt)), 0.5)
		turn = turn * Basis.from_scale(Vector3(narrow, 1.0, 1.0) if _across_x else Vector3(1.0, 1.0, narrow))
	return Transform3D(Basis.IDENTITY, Vector3(0.0, lift - SLACK_DROP - hang.x, 0.0)) * Transform3D(turn, pivot - turn * pivot)

## Finds the deck's parts (again, should one have been laid since), each put
## back as laid first.
func _find_parts() -> void:
	if deck.get_child_count() == _children: return
	_children = deck.get_child_count()
	for part: Dictionary in _parts:
		if is_instance_valid(part.node): (part.node as Node3D).transform = part.rest
	for long: Dictionary in _long:
		if is_instance_valid(long.node): (long.node as Node3D).visible = true
	unbake()
	for length: Node in _bends.get_children():
		length.free()
	var known: Dictionary = {}
	for part: Dictionary in _parts: known[part.node] = part.rest
	_parts.clear()
	_long.clear()
	_shown = NAN
	for found: Node in deck.find_children("*", "GeometryInstance3D", true, false):
		var mesh := found as GeometryInstance3D
		if _bends.is_ancestor_of(mesh): continue
		var rest: Transform3D = known.get(mesh, mesh.transform)
		var to_deck := _to_deck(mesh.get_parent())
		var box: AABB = (to_deck * rest) * mesh.get_aabb()
		var from := box.position.x if _across_x else box.position.z
		var size := box.size.x if _across_x else box.size.z
		if size >= LONG * (_high - _low) and mesh is MeshInstance3D:
			_long.append({"node": mesh, "lengths": _lengths(mesh as MeshInstance3D, to_deck * rest, from, size, _long.size())})
		else:
			_parts.append({"node": mesh, "rest": rest, "to_deck": to_deck, "pivot": box.get_center(), "squeeze": minf(box.size.y / maxf(size, 0.01), 0.6), "lift": THIN_LIFT if box.size.y <= THIN else 0.0})

## The `which`th long part's bent lengths under the deck, hidden: copies of
## its mesh, each a stretch of it about BEND long (BENDS at most), at rest
## where that stretch lies.
func _lengths(mesh: MeshInstance3D, placed: Transform3D, from: float, size: float, which: int) -> Array:
	var count := clampi(ceili(size / BEND), 2, BENDS)
	var lengths: Array = []
	for index in range(count):
		var start := from + size * float(index) / float(count)
		var squeeze := Basis.from_scale(Vector3(1.0 / float(count), 1.0, 1.0) if _across_x else Vector3(1.0, 1.0, 1.0 / float(count)))
		var shift := start - from / float(count)
		var rest := Transform3D(squeeze, Vector3(shift, 0.0, 0.0) if _across_x else Vector3(0.0, 0.0, shift)) * placed
		var length := MeshInstance3D.new()
		length.name = "Bend%d_%d" % [which, index]
		length.mesh = mesh.mesh
		length.material_override = mesh.material_override
		length.cast_shadow = mesh.cast_shadow
		length.visible = false
		_bends.add_child(length)
		var box: AABB = rest * mesh.get_aabb()
		lengths.append({"node": length, "rest": rest, "pivot": box.get_center(), "squeeze": minf(box.size.y / maxf(size / float(count), 0.01), 0.6)})
	return lengths

## `node`'s transform in the deck's space.
func _to_deck(node: Node) -> Transform3D:
	var placed := Transform3D.IDENTITY
	while node != null and node != deck:
		if node is Node3D: placed = (node as Node3D).transform * placed
		node = node.get_parent()
	return placed
