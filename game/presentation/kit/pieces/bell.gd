extends RefCounted
## World kit: the one bell every place hangs (the goal's bell, First Steps'
## loft bell, the Lighthouse's remembered bell and every keepsake bell). A
## chapel bell cast from one profile (crown, shoulder, waist, thick flared
## lip), faceted, with its iron clapper on its own hinge inside and its hanger
## over the crown.
##
## The place keeps its own frame (the goal's posts and beam, First Steps' arm,
## the Bell Arch's crown) and gives the bell two things: the hang point (the
## underside of the beam it hangs from) and the free space under it (width,
## height) down to the next thing below or beside it. The bell sizes itself to
## that space with a margin all round, at rest and at full swing, so it never
## reaches a beam, another bell or a pip's head, and its hanger meets the beam
## at the hang point:
##
##   var bell := Bell.build(frame, beam_underside, Vector2(0.76, 0.52))
##   bell.swing        # the pivot at the hang point
##   bell.body         # the cast body (a goal glows it when lit)
##   bell.moving_parts()   # what the static fold keeps whole
##
## Ringing is one rule for every bell (RING). A bell built with a striker has a
## small timber hammer on an arm beside it, outside the bell where it always
## shows: the hammer draws back, swings in and hits the lip, the note belongs
## at that moment, and the bell swings away from the hit while its clapper
## lags inside. Without one the bell is pulled out and its clapper meets the
## lip. A keepsake rings each bell it has through its tap (ring()); a place's
## own bell rings once when it lights (set_rung(), moving(), advance()) and
## snaps to rest on a seek, a retry or a replay, so all three match.
## The hammer stands on the side the bell swings away from: +z for a bell that
## swings along the depth, -x for one that swings sideways.
##   hanger "yoke": a timber headstock with iron straps (frames with a beam);
##   "loop": a crown loop (keepsakes, a bracket);
##   "none": the bell stands on its lip (a rung bell set down).
const Primitives = preload("res://presentation/kit/primitives.gd")
const SessionRelease = preload("res://presentation/kit/session_release.gd")

const BRASS := Color("c99a4e")
const IRON := Color("4f5458")
const TIMBER := Color("6e543d")
## The largest swing a ring gives (radians), which the fit allows for.
const SWING := 0.45
## The margin kept free inside the space, as a share of it.
const MARGIN := 0.06
## How far the clapper ball hangs below the lip, as a share of the cast.
const CLAPPER_DROP := 0.12
## The striker: how far its arm stands out past the lip and its head's radius
## (shares of the bell), and how far it draws back before the hit (radians).
const HAMMER_OUT := 0.16
const HAMMER_HEAD := 0.085
const HAMMER_BACK := 0.45
## A hammer is never drawn smaller than a bell this tall (metres), so a small
## bell's hammer still shows at Home's distance.
const HAMMER_LEAST := 0.42
## Hanger height as a share of the whole bell.
const HANGER := {"yoke": 0.16, "loop": 0.12, "none": 0.0}
## The bell's outer profile from the crown (y 0) down to the lip (y -1) and
## in under its thick rim, radius as a share of its cast height: [radius, y].
## Point LIP is the lip's edge. The dark mouth closes it inside the rim.
const PROFILE := [[0.0, 0.0], [0.17, 0.0], [0.24, -0.04], [0.27, -0.12], [0.28, -0.32], [0.31, -0.52], [0.37, -0.69], [0.46, -0.83], [0.54, -0.92], [0.57, -0.97], [0.57, -1.0], [0.47, -1.0]]
const LIP := 9
const SIDES := 12
## The mouth's depth inside the lip and its share of the lip's radius.
const MOUTH := 0.985
const MOUTH_SHARE := 0.82

## The ring, from its start: when the strike is (the note's moment) and when
## everything is still again.
const STRIKE := 0.18
const RING_TIME := 1.02

static var _meshes: Dictionary = {}

var swing: Node3D
var body: MeshInstance3D
## The striker (null without one) and the clapper's hinge.
var hammer: Node3D
var clapper: Node3D
## The whole bell's height from the hang point (as fitted).
var height := 0.0
## How long ago a place's bell was rung (INF: still).
var _age := INF

## A bell hung at `at` (parent space) that fits `space` (width, height) under
## it. `sideways`: the ring swings it across the width (else along the depth).
static func build(parent: Node3D, at: Vector3, space: Vector2, hanger: String = "yoke", tint: Color = BRASS, look: Material = null, sideways: bool = false, striker: bool = false) -> RefCounted:
	var bell: RefCounted = load("res://presentation/kit/pieces/bell.gd").new()
	bell._make(parent, at, fit(space, hanger, sideways, striker), hanger, tint, look)
	bell.swing.set_meta("sideways", sideways)
	if striker: bell._hammer(parent, at, hanger, sideways)
	return bell

## The bell's height that fits `space` with its margin, at rest and swung.
static func fit(space: Vector2, hanger: String = "yoke", sideways: bool = false, striker: bool = false) -> float:
	var k: float = HANGER.get(hanger, 0.12)
	var lip := float(PROFILE[LIP][0]) * (1.0 - k)
	var cast := 1.0 - k
	# Lowest reach per unit of height: the clapper at rest, or the lip's low
	# edge with the bell swung out (the clapper hangs plumb inside it).
	var drop := maxf(k + cast * (1.0 + CLAPPER_DROP), cos(SWING) + sin(SWING) * lip)
	# Widest reach: the lip, or swung sideways its low edge out past the hang point.
	var half := lip if not sideways else sin(SWING) + cos(SWING) * lip
	# A sideways bell's hammer stands in the width, past the lip.
	if sideways and striker: half = maxf(half, lip + HAMMER_OUT + HAMMER_HEAD)
	if hanger == "none": drop = 1.0
	var room := space * (1.0 - MARGIN)
	return minf(room.y / drop, room.x * 0.5 / half)

## The nodes a ring moves, which a place's static fold keeps whole.
func moving_parts() -> Array[Node3D]:
	var parts: Array[Node3D] = [swing]
	if hammer != null: parts.append(hammer)
	return parts

## Adds the bell's moving nodes to a keepsake's `parts`: its swing under
## `key` (what ring() is given), its hammer and clapper beside it, so Home's
## fold keeps each whole (a part is held; what is under it but not held folds
## into its batch and can no longer move on its own).
static func hold(parts: Dictionary, key: String, bell: RefCounted) -> void:
	parts[key] = bell.swing
	parts[key + "_clapper"] = bell.clapper
	if bell.hammer != null: parts[key + "_hammer"] = bell.hammer

## Whether `node` is one of a kit bell's moving nodes (hold()): a keepsake's
## budget counts each bell as one piece.
static func is_part(node: Node) -> bool:
	return node.name in [&"BellSwing", &"BellHammer", &"BellClapper"]

## A place's bell, each snapshot: it rings once as it lights (`on` turning
## true), unless `immediate` (a seek, a retry, reduced motion), which leaves
## it still, as does putting it out.
func set_rung(on: bool, immediate: bool = false) -> void:
	var was: bool = swing.get_meta("rung", false)
	swing.set_meta("rung", on)
	if on != was: _age = 0.0 if on and not immediate else INF
	elif immediate: _age = INF
	_pose(_age)

func moving() -> bool:
	return _age < RING_TIME

func advance(delta: float) -> void:
	_age += delta
	_pose(_age)

## Rings the bell whose swing is `bell` (hold()) from `at` in a keepsake
## tap's time (keepsake_anim.gd); its hammer stands beside it under the same
## parent, which holds only this bell. Returns the strike, when the note
## belongs.
static func ring(anim: RefCounted, bell: Node3D, at: float) -> float:
	var nodes := _nodes(bell, bell.get_parent().get_node_or_null("BellHammer"), bell.get_node_or_null("BellClapper"))
	for key: Array in _keys(nodes):
		anim.move(key[0], key[1], key[2], at + float(key[3]), key[4], key[5], key[6])
	return at + STRIKE

## The ring as keys: [node, property, angle, at, time, trans, ease], each
## node's keys one after another, so a tween of them and _pose() agree.
static func _keys(nodes: Dictionary) -> Array:
	var bell: Node3D = nodes.swing
	var hit: Node3D = nodes.hammer
	var property := "rotation:z" if bell.get_meta("sideways", false) else "rotation:x"
	var keys: Array = []
	var out := STRIKE if hit != null else 0.0
	var push := 0.16 if hit != null else STRIKE
	if hit != null:
		var reach: float = hit.get_meta("hit", 0.2)
		keys.append([hit, property, -HAMMER_BACK, 0.0, 0.12, Tween.TRANS_SINE, Tween.EASE_IN_OUT])
		keys.append([hit, property, reach, 0.12, 0.06, Tween.TRANS_QUAD, Tween.EASE_IN])
		keys.append([hit, property, -0.12, STRIKE, 0.14, Tween.TRANS_SINE, Tween.EASE_IN_OUT])
		keys.append([hit, property, 0.0, STRIKE + 0.14, 0.2, Tween.TRANS_SINE, Tween.EASE_IN_OUT])
	keys.append([bell, property, SWING, out, push, Tween.TRANS_SINE, Tween.EASE_OUT])
	keys.append([bell, property, -SWING * 0.7, out + push, 0.24, Tween.TRANS_SINE, Tween.EASE_IN_OUT])
	keys.append([bell, property, SWING * 0.3, out + push + 0.24, 0.2, Tween.TRANS_SINE, Tween.EASE_IN_OUT])
	keys.append([bell, property, 0.0, out + push + 0.44, 0.24, Tween.TRANS_SINE, Tween.EASE_IN_OUT])
	if nodes.clapper != null:
		# The clapper hangs back as the bell swings away, meets the lip on
		# the far side, and settles with the bell.
		var hinge: Node3D = nodes.clapper
		keys.append([hinge, property, -SWING, out, push, Tween.TRANS_SINE, Tween.EASE_IN_OUT])
		keys.append([hinge, property, SWING * 0.4, out + push, 0.2, Tween.TRANS_SINE, Tween.EASE_IN_OUT])
		keys.append([hinge, property, 0.0, out + push + 0.2, 0.36, Tween.TRANS_SINE, Tween.EASE_IN_OUT])
	return keys

static func _nodes(bell: Node, hit: Node, hinge: Node) -> Dictionary:
	return {"swing": bell, "hammer": hit, "clapper": hinge}

## Sets every moving node to where the ring has it `t` seconds in (still
## before 0 and after RING_TIME).
func _pose(t: float) -> void:
	var angles := {}
	var keys := _keys(_nodes(swing, hammer, clapper))
	for key: Array in keys: angles[key[0]] = 0.0
	for key: Array in keys:
		var from: float = angles.get(key[0], 0.0)
		var start: float = key[3]
		var time: float = key[4]
		# A node's keys follow one another, so only one is under way at `t`.
		if t >= start + time: angles[key[0]] = float(key[2])
		elif t > start: angles[key[0]] = float(Tween.interpolate_value(from, float(key[2]) - from, t - start, time, key[5], key[6]))
	for node: Node3D in angles: node.set_indexed(keys[0][1], angles[node])

func _make(parent: Node3D, at: Vector3, h: float, hanger: String, tint: Color, look: Material) -> void:
	height = h
	swing = Node3D.new()
	swing.name = "BellSwing"
	swing.position = at
	parent.add_child(swing)
	var top := -float(HANGER.get(hanger, 0.12)) * h
	if hanger == "none": swing.position.y += h
	var cast := h + top
	var mat: Material = look if look != null else Primitives.shared_material(tint, 0.5)
	# A crown loop is cast with the body, one mesh.
	body = Primitives.mesh_node(_body_mesh(cast, h if hanger == "loop" else 0.0), mat, Vector3(0, top, 0), swing)
	body.name = "BellBody"
	var lip_r := float(PROFILE[LIP][0]) * cast
	var mouth := Primitives.mesh_node(Primitives.cached_shape(_disc(lip_r * MOUTH_SHARE)), Primitives.shared_material(tint.darkened(0.6)), Vector3(0, top - cast * MOUTH, 0), swing)
	mouth.name = "BellMouth"
	# The sound bow: a bright band round the flare above the lip.
	var bow := TorusMesh.new()
	var bow_r := _radius_at(cast, -0.86) + 0.006 * h
	bow.inner_radius = bow_r - 0.022 * h
	bow.outer_radius = bow_r + 0.022 * h
	bow.rings = SIDES
	bow.ring_segments = 3
	Primitives.mesh_node(Primitives.cached_shape(bow), Primitives.shared_material(tint.lightened(0.28) if look == null else tint, 0.5), Vector3(0, top - 0.86 * cast, 0), swing)
	# The clapper hangs from its own hinge under the crown, so a ring can make
	# it lag and strike the lip.
	clapper = Node3D.new()
	clapper.name = "BellClapper"
	clapper.position = Vector3(0, top - cast * 0.36, 0)
	swing.add_child(clapper)
	Primitives.mesh_node(_clapper_mesh(cast), Primitives.shared_material(IRON), Vector3.ZERO, clapper)
	match hanger:
		"yoke":
			# A timber headstock under the beam, two iron straps down the crown.
			Primitives.mesh_node(Primitives.cached_box(Vector3(lip_r * 1.3, 0.12 * h, 0.20 * h)), Primitives.shared_material(TIMBER), Vector3(0, -0.06 * h, 0), swing)
			for side: float in [-1.0, 1.0]:
				Primitives.mesh_node(Primitives.cached_box(Vector3(0.035 * h, 0.12 * h, 0.215 * h)), Primitives.shared_material(IRON), Vector3(side * 0.12 * h, -0.11 * h, 0), swing)

## The striker: a short arm from the hang point out past the lip on the side
## the bell swings away from, and a hammer hanging from it down to the lip,
## its head just clear. It never moves with the bell. Its thickness never
## goes below a HAMMER_LEAST bell's; the gap to the lip stays the bell's own.
func _hammer(parent: Node3D, at: Vector3, hanger: String, sideways: bool) -> void:
	var h := height
	var k := maxf(h, HAMMER_LEAST)
	var cast := h * (1.0 - float(HANGER.get(hanger, 0.12)))
	var lip_r := float(PROFILE[LIP][0]) * cast
	var head := HAMMER_HEAD * k
	var gap := (HAMMER_OUT - HAMMER_HEAD) * h
	var out := lip_r + head + gap
	var side := Vector3(-1, 0, 0) if sideways else Vector3(0, 0, 1)
	var wood := Primitives.shared_material(TIMBER)
	var top := at + Vector3(0, -0.03 * h, 0)
	Primitives.bar_between(top, top + side * out, 0.06 * k, wood, parent)
	hammer = Node3D.new()
	hammer.name = "BellHammer"
	hammer.position = top + side * out
	parent.add_child(hammer)
	var reach := h * 0.86
	Primitives.mesh_node(Primitives.cached_box(Vector3(0.05 * k, reach, 0.05 * k)), wood, Vector3(0, -reach * 0.5, 0), hammer)
	var face := Primitives.mesh_node(Primitives.cached_shape(Primitives.cylinder_mesh(head, 0.24 * k, -1.0, 8)), Primitives.shared_material(TIMBER.lightened(0.25)), Vector3(0, -reach, 0), hammer)
	face.rotation = Vector3(PI / 2.0, 0, 0) if not sideways else Vector3(0, 0, PI / 2.0)
	# The swing that brings the head's face to the lip: the gap over the arm.
	hammer.set_meta("hit", asin(clampf(gap / reach, 0.0, 0.9)))

## A flat disc of SIDES sides, `radius` across (one ring of faces each way).
static func _disc(radius: float) -> CylinderMesh:
	var shape := Primitives.cylinder_mesh(radius, 0.01, -1.0, SIDES)
	shape.rings = 0
	return shape

## The clapper, one iron mesh from its hinge: a square rod and a low ball
## hanging CLAPPER_DROP under the lip.
static func _clapper_mesh(cast: float) -> Mesh:
	var key := "clapper|%.4f" % cast
	var found: Mesh = _meshes.get(key)
	if found != null: return found
	var reach := cast * (0.54 + CLAPPER_DROP)
	var rod := BoxMesh.new()
	rod.size = Vector3(0.035 * cast, reach, 0.035 * cast)
	var ball := SphereMesh.new()
	ball.radius = 0.10 * cast
	ball.height = 0.20 * cast
	ball.radial_segments = 8
	ball.rings = 4
	var tool := SurfaceTool.new()
	tool.append_from(rod, 0, Transform3D(Basis.IDENTITY, Vector3(0, -reach * 0.5, 0)))
	tool.append_from(ball, 0, Transform3D(Basis.IDENTITY, Vector3(0, -reach, 0)))
	return _keep(key, tool.commit())

static func _radius_at(cast: float, y: float) -> float:
	for index in range(PROFILE.size() - 1):
		var a: Array = PROFILE[index]
		var b: Array = PROFILE[index + 1]
		if float(b[1]) <= y and float(a[1]) >= y and float(b[1]) < float(a[1]):
			return lerpf(float(a[0]), float(b[0]), (y - float(a[1])) / (float(b[1]) - float(a[1]))) * cast
	return float(PROFILE[4][0]) * cast

## The cast body turned from the profile, `cast` tall, SIDES flat faces;
## with `loop` (the whole bell's height) a crown loop cast on top.
static func _body_mesh(cast: float, loop: float) -> Mesh:
	var key := "body|%.4f|%.4f" % [cast, loop]
	var found: Mesh = _meshes.get(key)
	if found != null: return found
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_smooth_group(-1)
	_turn(tool, PROFILE, SIDES, Vector3.ZERO, cast, false)
	if loop > 0.0:
		# A tube 0.018 of the bell thick bent round 0.05 of it, standing
		# upright 0.06 of the bell over the crown.
		var tube: Array = []
		for index in range(5):
			var v := PI * 0.5 - TAU * index / 4.0
			tube.append([0.05 + 0.018 * cos(v), 0.018 * sin(v)])
		_turn(tool, tube, 8, Vector3(0, 0.06 * loop, 0), loop, true)
	tool.generate_normals()
	return _keep(key, tool.commit())

## Turns `points` ([radius, y] shares of `size`) round the upright axis in
## `sides` flat faces at `at`; `upright` stands the turned ring on its edge.
static func _turn(tool: SurfaceTool, points: Array, sides: int, at: Vector3, size: float, upright: bool) -> void:
	for index in range(points.size() - 1):
		var a: Array = points[index]
		var b: Array = points[index + 1]
		for side in range(sides):
			var t0 := TAU * side / sides
			var t1 := TAU * (side + 1) / sides
			var quad: Array[Vector3] = []
			for corner: Array in [[a, t0], [b, t0], [b, t1], [a, t1]]:
				var point: Array = corner[0]
				var turn: float = corner[1]
				var p := Vector3(cos(turn) * float(point[0]), float(point[1]), sin(turn) * float(point[0])) * size
				quad.append(at + (Vector3(p.x, p.z, -p.y) if upright else p))
			for v: Vector3 in [quad[0], quad[1], quad[2], quad[0], quad[2], quad[3]]: tool.add_vertex(v)

static func _keep(key: String, mesh: Mesh) -> Mesh:
	_meshes[key] = mesh
	SessionRelease.on_exit(Callable(load("res://presentation/kit/pieces/bell.gd"), "release_cached"))
	return mesh

static func release_cached() -> void:
	_meshes.clear()
