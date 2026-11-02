extends SceneTree
## Every keepsake builder (presentation/keepsakes/, named by the descriptors):
## each loads and builds every combination of its upgrades within the budget,
## keeps its pieces, solids, trigger and stay inside its own ground, times its
## tap within the limits, only moves its own moving parts, carries a pip only
## through its own ride and lands it clear of its solids, and draws only looks
## the GL warm-up compiles. The started outline is one draw with one shared look.
const States = preload("res://services/home_keepsake_states.gd")
const Parts = preload("res://presentation/keepsakes/keepsake_parts.gd")
const Anim = preload("res://presentation/keepsakes/keepsake_anim.gd")
const Builder = preload("res://presentation/keepsakes/keepsake_builder.gd")
const GlWarmup = preload("res://services/gl_warmup.gd")
const StaticBatch = preload("res://presentation/kit/static_batch.gd")
const Primitives = preload("res://presentation/kit/primitives.gd")
const SparkleStar = preload("res://presentation/kit/sparkle_star.gd")
const Index = preload("res://content/chapters/index.gd")
## Round 2's keepsakes are bigger: the README budget for all eleven with every
## upgrade is 45,000 triangles (Home's isles included, counted by the layer suite).
const MAX_PARTS := 90
const MAX_TRIANGLES := 6000
const ALL_TRIANGLES := 40000
const MAX_MOVING := 6
## Every beat, then the ease back to rest.
const TOTAL_MAX := 4.5
var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var warm: Array = GlWarmup.MATERIALS.map(func(key: Dictionary) -> Dictionary: return key)
	var all_parts := 0
	var all_triangles := 0
	for entry: Dictionary in _every_keepsake():
		var builder: RefCounted = load(str(entry.keepsake.builder)).new()
		_check(builder is Builder, "%s's builder extends keepsake_builder.gd" % entry.id)
		for flags in range(16):
			var state := {"together": flags & 1 != 0, "hard": flags & 2 != 0 and entry.hard, "top": flags & 4 != 0 and entry.hard}
			if entry.id == States.EARLIER: state.lanterns = [true, false, true, false, true, false, true, false] if flags & 8 else [false, false, false]
			_check_build(stage, entry, builder, state)
		var full: Dictionary = builder.full_state()
		var prop := Node3D.new()
		stage.add_child(prop)
		builder.build(prop, full)
		var counted := _count(prop)
		all_parts += counted[0]
		all_triangles += counted[1]
		prop.free()
		# Timing: base at most 2.5 s, each upgrade at most 0.8 s, all within 4.5 s.
		var beats: Array = builder.beats(full)
		var total := 0.0
		for beat: Dictionary in beats:
			total += float(beat.time)
			_check(float(beat.time) <= (Builder.BASE_MAX if beat.beat == "base" else Builder.UPGRADE_MAX), "%s's %s beat is short enough: %.2f" % [entry.id, beat.beat, beat.time])
		_check(beats[0].beat == "base" and total + Builder.SETTLE <= TOTAL_MAX, "%s plays every upgrade and settles within %.1f s: %.2f" % [entry.id, TOTAL_MAX, total + Builder.SETTLE])
		_check(beats.size() == 1 + int(full.get("together", false)) + int(full.get("hard", false)) + int(full.get("top", false)), "%s adds one beat per earned upgrade" % entry.id)
		for beat: Dictionary in beats: _check(entry.keepsake.sounds.has(beat.beat), "%s has a sound for its %s beat" % [entry.id, beat.beat])
		_check_tap_parts(stage, entry, builder, full)
		_check_explore(stage, entry, builder)
		_check_upgrades(stage, entry, builder)
		# Warm-up: every look it draws is a feature key the GL warm-up compiles.
		for look: Material in builder.materials():
			var key := GlWarmup.material_key(look as BaseMaterial3D)
			_check(warm.has(key), "%s draws a look the warm-up compiles: %s" % [entry.id, key])
		# Outline: one draw, the shared veil.
		var outline_root := Node3D.new()
		stage.add_child(outline_root)
		var veil := Parts.outline(outline_root, builder, entry.id + "|test", [[true, false], [false, true]])
		var meshes := outline_root.find_children("*", "MeshInstance3D", true, false)
		_check(veil.mesh.get_surface_count() == 1 and veil.material_override == Parts.ghost() and meshes.filter(func(node: Node) -> bool: return (node as MeshInstance3D).material_override == Parts.ghost()).size() == 1, "%s's outline is one merged mesh with the shared veil" % entry.id)
		_check(meshes.size() == 3, "%s's outline has one dot per stage" % entry.id)
		outline_root.free()
	_check_giant_steps_ride()
	print("KEEPSAKE PROPS: all eleven with every upgrade: %d parts, %d triangles before folding" % [all_parts, all_triangles])
	_check(all_triangles <= ALL_TRIANGLES, "All eleven with every upgrade stay under %d triangles: %d" % [ALL_TRIANGLES, all_triangles])
	_check(Primitives.changed_shared_looks().is_empty(), "No keepsake changes a shared look in place: %s" % [Primitives.changed_shared_looks()])
	stage.free()
	print("KEEPSAKE PROPS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## Home's keepsakes, then any registered chapter's not on Home yet (a new
## chapter not released), held to the same budget before it ships.
func _every_keepsake() -> Array:
	var result: Array = States.entries().duplicate()
	var seen: Array = result.map(func(entry: Dictionary) -> String: return entry.id)
	for key: String in Index.keys():
		var level := key.get_slice("@", 0)
		if seen.has(level) or Index.data(key).home_keepsake.is_empty(): continue
		seen.append(level)
		result.append({"id": level, "keepsake": Index.data(key).home_keepsake, "hard": true, "together": true})
	return result

func _count(node: Node) -> Array:
	var parts := 0
	var triangles := 0
	for child: Node in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := (child as MeshInstance3D).mesh
		if mesh == null: continue
		parts += mesh.get_surface_count()
		triangles += mesh.get_faces().size() / 3
	return [parts, triangles]

func _check_build(stage: Node3D, entry: Dictionary, builder: RefCounted, state: Dictionary) -> void:
	var prop := Node3D.new()
	stage.add_child(prop)
	var parts: Dictionary = builder.build(prop, state)
	var label := "%s %s" % [entry.id, state]
	var counted := _count(prop)
	_check(counted[0] <= MAX_PARTS and counted[1] <= MAX_TRIANGLES, "%s stays within %d parts and %d triangles: %s" % [label, MAX_PARTS, MAX_TRIANGLES, counted])
	var moving := parts.values().filter(func(part: Variant) -> bool: return part is Node)
	_check(moving.size() <= MAX_MOVING, "%s moves at most %d parts: %d" % [label, MAX_MOVING, moving.size()])
	_check(prop.find_children("*", "", true, false).all(func(node: Node) -> bool: return node.get_script() == null), "%s carries no script, so its still parts fold" % label)
	# Its pieces stay inside its ground: the footing under, the together piece beside, the top above.
	var area: Rect2 = builder.footprint().grow(0.06)
	var outside: Array = []
	for node: Node in prop.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var box: AABB = prop.global_transform.affine_inverse() * mesh.global_transform * mesh.get_aabb()
		for corner: Vector2 in [Vector2(box.position.x, box.position.z), Vector2(box.end.x, box.end.z)]:
			if not area.has_point(corner): outside.append(str(mesh.name))
	_check(outside.is_empty(), "%s keeps every piece inside its ground %s: %s" % [label, area, outside])
	if state.get("hard", false): _check(prop.find_child("Footing", true, false) != null, "%s stands on its footing" % label)
	prop.free()

## A tap only moves the parts build() returned (and their own pieces) or parts
## made for the tap; with Reduce motion it never builds a Tween.
func _check_tap_parts(stage: Node3D, entry: Dictionary, builder: RefCounted, state: Dictionary) -> void:
	var prop := Node3D.new()
	stage.add_child(prop)
	var parts: Dictionary = builder.build(prop, state)
	for reduced: bool in [false, true]:
		var anim := Anim.new()
		anim.reduced = reduced
		anim.fx = Node3D.new()
		prop.add_child(anim.fx)
		var holder := Node.new()
		stage.add_child(holder)
		var tween := holder.create_tween().set_parallel(true)
		if not reduced: anim.tween = tween
		for beat: Dictionary in builder.beats(state): builder.play(str(beat.beat), anim, parts, state)
		var owned: Array = parts.values().filter(func(part: Variant) -> bool: return part is Node)
		var strays: Array = []
		for node: Variant in anim.touched:
			if anim.spawned.has(node): continue
			if owned.has(node) or owned.has((node as Node).get_parent()): continue
			strays.append(str((node as Node).name))
		_check(strays.is_empty(), "%s's tap moves only its moving parts: %s" % [entry.id, strays])
		_check(anim.spawned.all(func(part: Node) -> bool: return anim.fx.is_ancestor_of(part) or owned.any(func(own: Node) -> bool: return own.is_ancestor_of(part))), "%s makes its tap parts under the tap node or a moving part" % entry.id)
		if reduced: _check(not tween.is_valid() or not tween.is_running() or tween.get_total_elapsed_time() == 0.0, "%s with Reduce motion builds no motion" % entry.id)
		tween.kill()
		holder.free()
		anim.fx.free()
	prop.free()

## In Explore: its trigger, stay and solids stand inside its ground; a trigger
## area or a stay is somewhere the pip can stand; and a ride, from any side,
## carries the pip only through anim.carry, never touches the pip as a part,
## and lands it on the grass clear of every solid.
func _check_explore(stage: Node3D, entry: Dictionary, builder: RefCounted) -> void:
	var ground: Rect2 = builder.footprint().grow(0.06)
	var trigger: Dictionary = builder.trigger()
	var stay: Rect2 = builder.stay()
	for flags in range(8):
		var state := {"together": flags & 1 != 0, "hard": flags & 2 != 0 and entry.hard, "top": flags & 4 != 0 and entry.hard}
		if entry.id == States.EARLIER: state.lanterns = [true, false, true]
		var solids: Array[Rect2] = builder.solids(state)
		_check(not solids.is_empty() and solids.all(func(rect: Rect2) -> bool: return ground.encloses(rect)), "%s %s keeps its solids inside its ground" % [entry.id, state])
		if trigger.has("area"):
			var area: Rect2 = trigger.area
			_check(ground.encloses(area), "%s's trigger is inside its ground" % entry.id)
			_check(_free_in(area, solids), "%s %s's trigger has room to stand in" % [entry.id, state])
		if trigger.has("line"):
			for point: Vector2 in trigger.line: _check(ground.has_point(point), "%s's trigger line is inside its ground" % entry.id)
		if stay.has_area():
			_check(ground.encloses(stay) and _free_in(stay, solids), "%s %s's stay is inside its ground with room to stand in" % [entry.id, state])
		# A ride from in front, from the side and from behind lands clear.
		for from: Vector3 in [Vector3(0, 0, ground.end.y + 0.3), Vector3(ground.position.x - 0.3, 0, 0), Vector3(0, 0, ground.position.y - 0.3)]:
			var prop := Node3D.new()
			stage.add_child(prop)
			var parts: Dictionary = builder.build(prop, state)
			var anim := Anim.new()
			anim.fx = Node3D.new()
			prop.add_child(anim.fx)
			var rider := Node3D.new()
			stage.add_child(rider)
			rider.position = from
			anim.rider = rider
			anim.rider_from = from
			for beat: Dictionary in builder.beats(state):
				builder.play(str(beat.beat), anim, parts, state)
				anim.start += float(beat.time)
			_check(not anim.touched.has(rider), "%s never moves the pip as one of its parts" % entry.id)
			if anim.landing != null:
				var landing: Vector3 = anim.landing
				var flat := Vector2(landing.x, landing.z)
				_check(landing.y == 0.0 and solids.all(func(rect: Rect2) -> bool: return not rect.grow(0.1).has_point(flat)), "%s %s lands the pip on the grass clear of its solids: %s" % [entry.id, state, landing])
			rider.free()
			prop.free()

## Whether a spirit (0.12 round) can stand somewhere in `area` clear of `solids`.
func _free_in(area: Rect2, solids: Array[Rect2]) -> bool:
	for x in range(9):
		for z in range(9):
			var point := area.position + area.size * Vector2(x / 8.0, z / 8.0)
			if solids.all(func(rect: Rect2) -> bool: return not rect.grow(0.12).has_point(point)): return true
	return false

## Each upgrade earned on its own draws a keepsake of its own: more pieces than
## the base look, and a look no other single upgrade draws, so the shape says
## what has been earned.
func _check_upgrades(stage: Node3D, entry: Dictionary, builder: RefCounted) -> void:
	var looks := {}
	for upgrade: String in ["", "together", "hard", "top"]:
		if upgrade in ["hard", "top"] and not entry.hard: continue
		var state := {}
		if not upgrade.is_empty(): state[upgrade] = true
		if entry.id == States.EARLIER: state.lanterns = [true, false, true]
		var prop := Node3D.new()
		stage.add_child(prop)
		builder.build(prop, state)
		var shape: Array = []
		for node: Node in prop.find_children("*", "MeshInstance3D", true, false):
			var mesh := node as MeshInstance3D
			shape.append([mesh.mesh, mesh.material_override, (prop.global_transform.affine_inverse() * mesh.global_transform).origin.snapped(Vector3.ONE * 0.001)])
		prop.free()
		looks[upgrade] = shape
	for upgrade: String in looks:
		if upgrade.is_empty(): continue
		_check(looks[upgrade].size() > looks[""].size(), "%s's %s upgrade adds pieces to the base look" % [entry.id, upgrade])
		for other: String in looks:
			if other != upgrade and not other.is_empty(): _check(looks[upgrade] != looks[other], "%s draws its %s and %s upgrades differently" % [entry.id, upgrade, other])

## The Giant Steps ride, from anywhere it is set off and from the side, as the
## shared ride moves draw it (keepsake_anim.gd hop_leg and slide_leg): one hop
## per step that clears every riser and lands on a step's top, the ladder hops
## out in front of the tower's face and over its edge onto its top on Hard,
## the slide along the chute's own bars, each leg starting where the last ended,
## and the last landing on the grass, all inside the base beat.
func _check_giant_steps_ride() -> void:
	var Steps: GDScript = load("res://presentation/keepsakes/giant_steps.gd")
	var builder: RefCounted = Steps.new()
	for hard: bool in [false, true]:
		var state := {"hard": hard}
		var times: Dictionary = Steps.TIMES[hard]
		for from: Vector3 in [Vector3(-0.95, 0, 0.8), Vector3(-0.35, 0, 0.45), Vector3(0.4, 0, 0.6)]:
			var points: Dictionary = Steps.ride_points(state, from)
			var label := "Giant Steps ride (hard %s, from %s)" % [hard, from]
			_check(points.climb.size() == 7 and points.ladder.size() == (4 if hard else 0), "%s hops once onto the grass, once per step%s" % [label, " and three times up the ladder" if hard else ""])
			var legs: Array = []
			for index in range(points.climb.size() - 1): legs.append(["hop", Anim.hop_leg(points.climb[index], points.climb[index + 1], Steps.HOP_HEIGHT), times.hop])
			for index in range(points.ladder.size() - 1): legs.append(["ladder", Anim.hop_leg(points.ladder[index], points.ladder[index + 1], Steps.LADDER_HEIGHT), times.ladder])
			var top: Vector3 = points.ladder[points.ladder.size() - 1] if hard else points.climb[points.climb.size() - 1]
			var chute: Array[Vector3] = points.chute
			legs.append(["sit", func(u: float) -> Vector3: return top.lerp(chute[0], u), times.sit])
			legs.append(["slide", Anim.slide_leg(chute), times.slide])
			legs.append(["lip", Anim.hop_leg(chute[chute.size() - 1], points.landing, 0.12), times.lip])
			var last := from
			var total := 0.0
			var clear := true
			var on_tops := true
			var on_chute := true
			var joined := true
			for leg: Array in legs:
				var path: Callable = leg[1]
				total += float(leg[2])
				joined = joined and (path.call(0.0) as Vector3).distance_to(last) < 0.001
				for sample in range(41):
					var at: Vector3 = path.call(sample / 40.0)
					match str(leg[0]):
						"hop", "lip", "ladder": clear = clear and at.y >= _steps_surface(at, hard) - 0.005
						"slide": on_chute = on_chute and _to_polyline(at, chute) < 0.005
						"sit": on_chute = on_chute and at.y >= _steps_surface(at, hard) - 0.03
				var end: Vector3 = path.call(1.0)
				if leg[0] == "hop" and end.y > 0.0: on_tops = on_tops and absf(end.y - _steps_surface(end, hard)) < 0.005
				if leg[0] == "ladder" and end.x == Steps.TOWER.x and end.z > Steps.TOWER.z + 0.3: on_tops = on_tops and end.z - (Steps.TOWER.z + 0.18) >= 0.2
				last = end
			_check(joined, "%s: each leg starts where the last one ended" % label)
			_check(clear, "%s: every hop clears the risers and the tower" % label)
			_check(on_tops, "%s: every hop lands on a step's top, and the ladder hops a pip's width out from the tower" % label)
			_check(on_chute, "%s: the sit stays on the top and the slide follows the chute's bars" % label)
			_check(absf(last.y) < 0.001 and last.distance_to(points.landing) < 0.001, "%s: lands on the grass past the chute" % label)
			_check(total <= float(builder.beats(state)[0].time) + 0.001 and float(builder.beats(state)[0].time) <= Builder.BASE_MAX, "%s fits its base beat: %.2f" % [label, total])
		# In front the pip rides and its hooks run; beside or behind the steps the
		# ball goes, and the pip is not carried.
		for side: Vector3 in [Vector3(-0.65, 0, 0.6), Vector3(-1.2, 0, 0.0), Vector3(0.2, 0, -0.7)]:
			var prop := Node3D.new()
			root.add_child(prop)
			var parts: Dictionary = builder.build(prop, state)
			var anim := Anim.new()
			anim.fx = Node3D.new()
			prop.add_child(anim.fx)
			var pip := HookedPip.new()
			prop.add_child(pip)
			anim.rider = pip
			anim.rider_from = side
			var joys := {"hearts": 0, "haptics": 0}
			anim.pop_heart = func(_pip: Node3D) -> void: joys.hearts += 1
			anim.haptic = func() -> void: joys.haptics += 1
			var holder := Node.new()
			root.add_child(holder)
			anim.tween = holder.create_tween().set_parallel(true)
			builder.play("base", anim, parts, state)
			var sparkles := anim.spawned.filter(func(part: Node) -> bool: return part is MeshInstance3D and (part as MeshInstance3D).mesh == SparkleStar.glint()).size()
			anim.tween.custom_step(5.0)
			if side.z >= 0.42:
				_check(anim.landing != null and pip.calls >= 10, "Giant Steps from in front carries the pip, hopping, sitting and bouncing: %d hooks" % pip.calls)
				_check(pip.faces == [&"happy"] and joys.hearts == 1 and joys.haptics == 1 and sparkles >= 8, "and its slide is joyful: a Happy face, one heart, one light tap and a trail of sparkles (%s, %s, %d)" % [pip.faces, joys, sparkles])
				var shown := anim.spawned.filter(func(part: Node) -> bool: return part is MeshInstance3D and (part as MeshInstance3D).mesh == SparkleStar.glint() and ((part as Node3D).visible or (part as Node3D).scale != Vector3.ZERO))
				_check(shown.is_empty(), "and every sparkle has twinkled away by the end: %d left" % shown.size())
			else: _check(anim.landing == null and not anim.spawned.is_empty() and pip.calls == 0 and pip.faces.is_empty() and joys.hearts == 0 and joys.haptics == 0, "Giant Steps from %s sends the ball, and the pip standing by neither hops, sits, smiles nor bounces: %d" % [side, pip.calls])
			anim.tween.kill()
			holder.free()
			prop.free()
		# Reduce motion keeps the Happy face and the tap, and drops the glints and the heart.
		var still := Node3D.new()
		root.add_child(still)
		var still_parts: Dictionary = builder.build(still, state)
		var calm := Anim.new()
		calm.reduced = true
		calm.fx = Node3D.new()
		still.add_child(calm.fx)
		var calm_pip := HookedPip.new()
		still.add_child(calm_pip)
		calm.rider = calm_pip
		calm.rider_from = Vector3(-0.65, 0, 0.6)
		var calm_joys := {"hearts": 0, "haptics": 0}
		calm.pop_heart = func(_pip: Node3D) -> void: calm_joys.hearts += 1
		calm.haptic = func() -> void: calm_joys.haptics += 1
		builder.play("base", calm, still_parts, state)
		var glints := calm.spawned.filter(func(part: Node) -> bool: return part is MeshInstance3D and (part as MeshInstance3D).mesh == SparkleStar.glint()).size()
		_check(calm_pip.faces == [&"happy"] and calm_joys.hearts == 0 and calm_joys.haptics == 1 and glints == 0, "With Reduce motion the slide keeps the Happy face and the one tap, with no glints or heart (%s, %s, %d)" % [calm_pip.faces, calm_joys, glints])
		still.free()
		# The hops touch down before their end, so the landing squash is on the ground.
		var hop: Callable = Anim.hop_leg(Vector3.ZERO, Vector3(0.36, 0.24, 0), Steps.HOP_HEIGHT)
		_check((hop.call(Anim.HOP_CONTACT) as Vector3).distance_to(Vector3(0.36, 0.24, 0)) < 0.001 and (hop.call(0.9) as Vector3) == (hop.call(1.0) as Vector3), "A hop touches down at its contact and holds there")
	# The Explore action beside or behind the steps hops the pip round to the
	# middle of the walk-up area, in front; from in front it rides from there.
	var Approach: GDScript = load("res://presentation/keepsakes/ride_approach.gd")
	var front: Variant = builder.ride_start({}, Vector3(1.4, 0, -1.2))
	var area: Rect2 = builder.trigger().area
	_check(front is Vector3 and area.has_point(Vector2(front.x, front.z)) and (front as Vector3).z >= Steps.FRONT_Z and builder.ride_start({}, Vector3(0.3, 0, 0.6)) == null, "Giant Steps rides from the walk-up area, and from anywhere in front as it is")
	for hard: bool in [false, true]:
		var round_state := {"hard": hard, "together": true}
		var solids: Array[Rect2] = builder.solids(round_state)
		var hops: Array[Vector3] = Approach.route(Vector3(1.4, 0, -1.2), front, solids, 0.12, func(_at: Vector2) -> bool: return true)
		var clear := hops.size() > 2 and hops[0] == Vector3(1.4, 0, -1.2) and (hops[hops.size() - 1] as Vector3).is_equal_approx(front)
		for index in range(1, hops.size()):
			clear = clear and hops[index - 1].distance_to(hops[index]) <= Approach.STRIDE + 0.001
			for rect: Rect2 in solids:
				for sample in range(11): clear = clear and not rect.grow(0.1).has_point(Vector2(hops[index - 1].x, hops[index - 1].z).lerp(Vector2(hops[index].x, hops[index].z), sample / 10.0))
		_check(clear, "From behind, the way round goes past every solid in hops of at most %.2f m (hard %s): %d hops" % [Approach.STRIDE, hard, hops.size()])
	_check(Approach.route(Vector3(1.4, 0, -1.2), front, builder.solids({}), 0.12, func(at: Vector2) -> bool: return at.x > 1.0).is_empty(), "With no ground round the steps there is no way, and the ball goes as before")

## The height of the Giant Steps' surface under a point: a step's top, the
## tower's top on Hard, else the grass.
func _steps_surface(at: Vector3, hard: bool) -> float:
	var Steps: GDScript = load("res://presentation/keepsakes/giant_steps.gd")
	var height := 0.0
	for index in range(5):
		var x: float = -0.7 + index * Steps.STEP_WIDTH
		if absf(at.x - x) <= Steps.STEP_WIDTH * 0.5 and absf(at.z) <= 0.4: height = maxf(height, 0.24 * (index + 1))
	if hard and absf(at.x - Steps.TOWER.x) <= 0.18 and absf(at.z - Steps.TOWER.z) <= 0.18: height = maxf(height, 2.24)
	return height

static func _to_polyline(at: Vector3, points: Array[Vector3]) -> float:
	var best := INF
	for index in range(points.size() - 1):
		var a: Vector3 = points[index]
		var b: Vector3 = points[index + 1]
		var t := clampf((at - a).dot(b - a) / maxf((b - a).length_squared(), 0.000001), 0.0, 1.0)
		best = minf(best, at.distance_to(a.lerp(b, t)))
	return best

## A pip that counts the ride hooks it is given.
class HookedPip extends Node3D:
	var calls := 0
	func play_hop(_duration: float, _contact: float = 0.8) -> void: calls += 1
	func set_ride_pose(_sit: float, _lean: Vector3) -> void: calls += 1
	func play_carry_release() -> void: calls += 1
	var faces: Array[StringName] = []
	func set_ride_face(face: StringName) -> void: faces.append(face)
