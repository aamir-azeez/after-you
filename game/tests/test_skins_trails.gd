extends SceneTree
## The Pollen skins, trails and little extras (board 2026-11-12):
## - the catalogue: their slots, permanent codes, the Wardrobe's chips and the
##   Bell sound's cue;
## - the skin pattern kit (kit/skin_pattern.gd): every skin's head through the
##   pattern face shader, its marks within the shaders' room, the drift a
##   triangle that rests at 0 and holds there under Reduce motion, the eye
##   safety ovals, shared torso materials and the feet's colours;
## - the flat shapes (kit/flat_shapes.gd): a few triangles each, inside their sizes;
## - the trail kit (kit/trail_kit.gd): marks only while walking, one spacing
##   apart along the path, at most six live, the same marks at any frame rate,
##   nothing once the pip stands and its marks fade, gone on a placement and
##   under Reduce motion, no marks along a jump, a still sample in pictures,
##   and the race ghost's veil;
## - the extras: the pebble hides while a real object is carried, the ring
##   shows only on room, result and Wardrobe pips, the chime only in the
##   Wardrobe; still pictures are keyed by place.
const Spirit = preload("res://presentation/spirit_visual.gd")
const PipOutfit = preload("res://presentation/pip_outfit.gd")
const Outfit = preload("res://services/outfit.gd")
const Catalog = preload("res://services/cosmetic_catalog.gd")
const Index = preload("res://content/cosmetics/index.gd")
const SoundCues = preload("res://services/sound_cues.gd")
const SkinPattern = preload("res://presentation/kit/skin_pattern.gd")
const TrailKit = preload("res://presentation/kit/trail_kit.gd")
const FlatShapes = preload("res://presentation/kit/flat_shapes.gd")
const Look = preload("res://presentation/spirit_look.gd")
const Stage = preload("res://presentation/kit/pip_stage.gd")
const Snapshots = preload("res://presentation/kit/pip_snapshots.gd")
const RaceGhost = preload("res://presentation/race_ghost_view.gd")
const Kit = preload("res://presentation/kit/pip_wear_kit.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")

const SKINS := ["knit", "night_sky", "patchwork", "blue_pottery", "autumn", "sea_glass"]
const TRAILS := ["leaves", "seed_fluff", "rain_drops", "soft_stars", "snow_steps", "little_tune"]
const EXTRAS := {"pocket_pebble": "carry", "soft_ring": "foot_ring", "wood_chime": "bell_sound"}
## The board's drift reach (half the peak to peak) per moving skin.
const DRIFTS := {"night_sky": 0.0075, "sea_glass": 0.01}
const WALK := Vector3(TrailKit.WALK_SPEED, 0, 0)

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> bool:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
	return value

func _run() -> void:
	Outfit.show_unreleased = true
	_catalogue()
	_skins()
	_shapes()
	_trail_walk()
	_trail_frame_rates()
	_trail_recorded_path()
	_trail_rules()
	_trail_pictures()
	_extras()
	Outfit.show_unreleased = false
	Kit.release_cached()
	print("SKINS TRAILS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _spirit(place: StringName = PipOutfit.WORLD) -> Node3D:
	var spirit: Node3D = Spirit.new(Look.PEACH)
	root.add_child(spirit)
	spirit.set_place(place)
	spirit.advance_motion(Vector3.ZERO, 0.001, false)
	return spirit

func _catalogue() -> void:
	var codes := {}
	for id: String in SKINS + TRAILS + EXTRAS.keys():
		var code := Catalog.code(id)
		_check(code >= 300 and code <= 399 and not codes.has(code), "%s has its own permanent code from 300 to 399: %d" % [id, code])
		codes[code] = id
		_check(not bool(Index.data(id).released), "%s is not released until the owner releases it" % id)
		_check(Catalog.sold(id) and Catalog.currency(id) == "pollen", "%s is sold for Pollen" % id)
	for id: String in SKINS: _check(Catalog.slot(id) == "body", "%s is a body skin" % id)
	for id: String in TRAILS: _check(Catalog.slot(id) == "trail", "%s is a trail" % id)
	for id: String in EXTRAS: _check(Catalog.slot(id) == EXTRAS[id], "%s goes in its own slot %s" % [id, EXTRAS[id]])
	_check(Catalog.chips() == ["hat", "body", "leaf", "trail", "extras"], "The Wardrobe's chips: the three extras share one: %s" % [Catalog.chips()])
	_check(Catalog.chip("carry") == "extras" and Catalog.chip("bell_sound") == "extras" and Catalog.chip("trail") == "trail", "Each slot names its chip")
	for chip: String in Catalog.chips(): _check(PlayerCopy.WARDROBE_SLOTS.has(chip), "The chip %s has its words" % chip)
	var cue := Catalog.sound("wood_chime")
	_check(SoundCues.CUES.has(cue) and SoundCues.is_fixed(cue), "The Wood chime plays a fixed cue: %s" % cue)
	_check(Outfit.bell_sound({"bell_sound": "wood_chime"}) == cue and Outfit.bell_sound({}).is_empty(), "The worn Bell sound names its cue; none plays nothing")
	for id: String in SKINS: _check(Catalog.moving(id) == DRIFTS.has(id), "%s draws live on a Wardrobe card only if it drifts" % id)
	# The tiers by how much each does: still recolours at most rare, the drifting skins epic.
	for id: String in SKINS:
		var tier := Catalog.tier(id)
		_check(tier == "epic" if DRIFTS.has(id) else tier in ["common", "uncommon", "rare"], "%s's tier fits what it does: %s" % [id, tier])

func _skins() -> void:
	_check(SkinPattern.SAFE_EYES.z >= 0.085 + SkinPattern.SAFE_MARGIN and SkinPattern.SAFE_EYES.w >= 0.098 + SkinPattern.SAFE_MARGIN and is_equal_approx(SkinPattern.SAFE_MARGIN, 0.025 * Look.HEAD_HALF.x * 2.0), "The eye safety ovals hold each eye with a 0.025 head width margin")
	var a := _spirit()
	var b := _spirit()
	for id: String in SKINS:
		a.wear(Outfit.of(id, true))
		b.wear(Outfit.of(id, true))
		var face: ShaderMaterial = a.face_art.material
		_check(face.shader == SkinPattern.FACE_SHADER, "%s draws the head with the pattern face shader" % id)
		_check(a.head.material_override == face, "%s keeps the face's own material (the eyes stay drawn)" % id)
		_check((face.get_shader_parameter(&"stamp_at") as PackedVector4Array).size() == SkinPattern.MAX_STAMPS and (face.get_shader_parameter(&"field_points") as PackedVector2Array).size() == SkinPattern.MAX_FIELD_POINTS, "%s fills the shader's arrays to size" % id)
		var art: Script = load(Catalog.art(id))
		var made := SkinPattern.recipe(art.RECIPE)
		for stamp: Dictionary in made.head.stamps:
			var spot: Vector2 = stamp.at
			_check(spot.x >= 0.0 and spot.x <= 1.0 and spot.y >= SkinPattern.CROWN_BACK and spot.y <= 1.0, "%s's stamps sit on the head, its front or its top" % id)
		_check(a.torso.material_override == b.torso.material_override, "%s's torso material is shared by every pip wearing it" % id)
		var feet: Array = made.feet
		_check((a.feet[0].get_child(0) as MeshInstance3D).material_override.albedo_color.is_equal_approx((feet[0] as Color).darkened(Look.FOOT_SHADE)), "%s's left foot takes its colour" % id)
		# The drift: 0 at rest, the board's reach a quarter of the way round, and held at 0 under Reduce motion.
		for step in range(24): a.advance_motion(Vector3.ZERO, 1.0 / 12.0, true)
		_check(is_zero_approx(float(face.get_shader_parameter(SkinPattern.DRIFT))), "%s holds still under Reduce motion" % id)
		for step in range(24): a.advance_motion(Vector3.ZERO, 1.0 / 12.0, false)
		var drift := float(face.get_shader_parameter(SkinPattern.DRIFT))
		if DRIFTS.has(id): _check(is_equal_approx(drift, DRIFTS[id]), "%s drifts out to the board's reach after 2 s: %f" % [id, drift])
		else: _check(is_zero_approx(drift), "%s never moves" % id)
	_check(is_zero_approx(SkinPattern.drift(0.01, 8.0, 0.0)) and is_equal_approx(SkinPattern.drift(0.01, 8.0, 2.0), 0.01) and is_zero_approx(SkinPattern.drift(0.01, 8.0, 4.0)) and is_equal_approx(SkinPattern.drift(0.01, 8.0, 6.0), -0.01) and is_zero_approx(SkinPattern.drift(0.01, 8.0, 8.0)), "The drift is a triangle over 8 s from 0 out and back")
	# Every skin draws on the crown too, where the chapters' high cameras look.
	for id: String in SKINS:
		var marks: Dictionary = SkinPattern.recipe((load(Catalog.art(id)) as Script).RECIPE).head
		var on_top := false
		for band: Dictionary in marks.bands: on_top = on_top or float(band.to) < 0.0
		for stamp: Dictionary in marks.stamps: on_top = on_top or (stamp.at as Vector2).y < 0.0
		for field: Dictionary in marks.fields:
			for corner: Vector2 in field.points: on_top = on_top or corner.y < -0.5
		_check(on_top, "%s has marks on the crown" % id)
	_check(SkinPattern.CROWN_BACK < -1.0, "The crown runs to v %.2f at the back of the top" % SkinPattern.CROWN_BACK)
	a.wear({})
	_check(a.face_art.material.shader != SkinPattern.FACE_SHADER, "Taking a skin off gives the plain face back")
	a.free()
	b.free()

func _shapes() -> void:
	var size := Vector3(0.05, 0.004, 0.05)
	for name: StringName in FlatShapes.NAMES:
		var one := FlatShapes.shape(name, size)
		var triangles := (one.indices as PackedInt32Array).size() / 3
		var inside := true
		for point: Vector3 in one.vertices: inside = inside and absf(point.x) <= size.x * 1.001 and absf(point.z) <= size.z * 1.001 and absf(point.y) <= size.y * 1.001
		_check(triangles > 0 and triangles <= 40 and inside, "The %s shape is a few flat triangles inside its size: %d" % [name, triangles])
		var edged := FlatShapes.with_edge(one)
		var shades: PackedFloat32Array = edged.get("shades", PackedFloat32Array())
		var banded := shades.size() == (edged.vertices as PackedVector3Array).size()
		for shade: float in shades: banded = banded and shade >= FlatShapes.RIM_SHADE and shade <= 1.0
		if one.has("shades"): _check(banded and (edged.indices as PackedInt32Array).size() >= (one.indices as PackedInt32Array).size() and shades.has(1.0), "The %s mark keeps a full colour middle and a darker edge" % name)

## Walks a pip `seconds` along +x at walking speed in steps of `dt`.
func _walk(spirit: Node3D, seconds: float, dt: float, reduced: bool = false) -> void:
	var steps := roundi(seconds / dt)
	for step in range(steps):
		spirit.position += WALK * dt
		spirit.advance_motion(WALK * dt, dt, reduced)

func _stand(spirit: Node3D, seconds: float, dt: float) -> void:
	for step in range(roundi(seconds / dt)): spirit.advance_motion(Vector3.ZERO, dt, false)

func _trail(spirit: Node3D) -> MultiMeshInstance3D:
	var found := spirit.find_children(TrailKit.NODE_NAME, "MultiMeshInstance3D", true, false)
	return found[0] if not found.is_empty() else null

## The live marks, oldest first: [position, custom data] each (the trail's
## Walk keeps what it gave each instance).
func _marks(trail: MultiMeshInstance3D) -> Array:
	return (trail.get_meta(TrailKit.WALK_META) as RefCounted).live_marks()

func _trail_walk() -> void:
	for id: String in TRAILS:
		var spirit := _spirit()
		spirit.wear(Outfit.of(id, true))
		var trail := _trail(spirit)
		var made: Dictionary = trail.get_meta(TrailKit.RECIPE_META)
		_check(trail != null and trail.top_level and trail.visible and _marks(trail).is_empty(), "%s draws its first frames with no mark, to warm its program" % id)
		_stand(spirit, 1.0, 1.0 / 60.0)
		_check(not trail.visible and _marks(trail).is_empty(), "%s then hides and leaves nothing while the pip stands" % id)
		_walk(spirit, 3.0, 1.0 / 60.0)
		var marks := _marks(trail)
		_check(trail.visible and not marks.is_empty() and marks.size() <= TrailKit.MAX_MARKS, "%s shows at most %d marks while walking: %d" % [id, TrailKit.MAX_MARKS, marks.size()])
		var spacing := TrailKit.spacing(made)
		var even := true
		for index in range(1, marks.size()):
			var gap: float = (marks[index][0] as Vector3).x - (marks[index - 1][0] as Vector3).x
			even = even and absf(gap - spacing) < 0.01 and signf((marks[index][0] as Vector3).z) != signf((marks[index - 1][0] as Vector3).z)
		_check(even, "%s drops a mark each %.2f m along the path, under alternate feet" % [id, spacing])
		_check(absf((marks[-1][0] as Vector3).y - TrailKit.LIFT) < 0.0001, "%s's marks lie just above the floor" % id)
		var behind := spirit.position.x - (marks[-1][0] as Vector3).x
		_check(behind >= 0.0 and behind <= spacing + TrailKit.WALK_SPEED * TrailKit.FOLLOW + 0.01, "%s's newest mark is behind the pip" % id)
		_stand(spirit, 0.2, 1.0 / 60.0)
		var count := _marks(trail).size()
		_stand(spirit, float(made.life) + 0.1, 1.0 / 60.0)
		_check(_marks(trail).is_empty() and not trail.visible, "%s stops the moment the pip stands and is clear within its life (%d left after 0.2 s)" % [id, count])
		var walk: RefCounted = trail.get_meta(TrailKit.WALK_META)
		var clock: float = walk.clock
		_stand(spirit, 1.0, 1.0 / 60.0)
		_check(walk.clock == clock, "%s does nothing while the pip stands with no marks" % id)
		spirit.free()

## The same walk at 30 and 60 frames a second drops the same marks.
func _trail_frame_rates() -> void:
	var runs: Array = []
	for dt: float in [1.0 / 60.0, 1.0 / 30.0, 1.0 / 45.0]:
		var spirit := _spirit()
		spirit.set_expression_role("b")
		spirit.wear(Outfit.of("leaves", true))
		spirit.advance_motion(Vector3.ZERO, dt, false)
		_walk(spirit, 1.8, dt)
		runs.append(_marks(_trail(spirit)))
		spirit.free()
	var same: bool = (runs[0] as Array).size() == (runs[1] as Array).size() and (runs[0] as Array).size() == (runs[2] as Array).size()
	for run: Array in runs.slice(1):
		for index in range(mini(run.size(), (runs[0] as Array).size())):
			var mine: Array = run[index]
			var first: Array = runs[0][index]
			same = same and (mine[0] as Vector3).distance_to(first[0]) < 0.001 and absf((mine[1] as Color).r - (first[1] as Color).r) < 0.001
			same = same and is_equal_approx((mine[1] as Color).g, (first[1] as Color).g) and is_equal_approx((mine[1] as Color).b, (first[1] as Color).b) and (mine[1] as Color).a == (first[1] as Color).a
	_check(same and not (runs[0] as Array).is_empty(), "The same walk drops the same marks at 60, 30 and 45 frames a second (memories and replays match)")
	var other := _spirit()
	other.wear(Outfit.of("leaves", true))
	other.advance_motion(Vector3.ZERO, 1.0 / 60.0, false)
	_walk(other, 1.8, 1.0 / 60.0)
	var mine: Array = _marks(_trail(other))
	_check(not mine.is_empty() and (mine[0][1] as Color).g != (runs[0][0][1] as Color).g, "The other player's pip draws its marks its own way")
	other.free()

## A turning walk, the world's way: the recorded target moves a tick at a
## time (30 a second) and the drawn pip eases after it, which differs with
## the frame rate on every corner; the trail follows the target, so the marks
## do not.
func _trail_recorded_path() -> void:
	var runs: Array = []
	for dt: float in [1.0 / 60.0, 1.0 / 30.0, 1.0 / 45.0]:
		var spirit := _spirit()
		spirit.wear(Outfit.of("little_tune", true))
		spirit.travel_target = spirit.position
		spirit.advance_motion(Vector3.ZERO, dt, false)
		var time := 0.0
		for step in range(roundi(3.0 / dt)):
			time += dt
			var tick := floori(time * 30.0 + 0.0001)
			var walked := tick * TrailKit.WALK_SPEED / 30.0
			# East, then north after 1.5 m, then west after 3 m.
			var target := Vector3(minf(walked, 1.5), 0, -clampf(walked - 1.5, 0.0, 1.5))
			if walked > 3.0: target = Vector3(1.5 - (walked - 3.0), 0, -1.5)
			spirit.travel_target = target
			var previous: Vector3 = spirit.position
			spirit.position = previous.lerp(target, minf(dt * 14.0, 1.0))
			spirit.advance_motion(spirit.position - previous, dt, false)
		var walk: RefCounted = _trail(spirit).get_meta(TrailKit.WALK_META)
		runs.append([walk.number, walk.spots.duplicate(), walk.customs.duplicate()])
		spirit.free()
	var same: bool = runs[0][0] > 3 and runs[1][0] == runs[0][0] and runs[2][0] == runs[0][0]
	var apart := 0.0
	for run: Array in runs.slice(1):
		for index in range((run[1] as PackedVector3Array).size()):
			apart = maxf(apart, (run[1][index] as Vector3).distance_to(runs[0][1][index]))
			same = same and is_equal_approx((run[2][index] as Color).g, (runs[0][2][index] as Color).g)
	_check(same and apart < 0.001, "A turning walk drops the same marks at 60, 30 and 45 frames a second, following the recorded path: %s, %.4f m apart at most" % [runs.map(func(run: Array) -> int: return run[0]), apart])

func _trail_rules() -> void:
	var spirit := _spirit()
	spirit.wear(Outfit.of("snow_steps", true))
	var trail := _trail(spirit)
	_walk(spirit, 1.0, 1.0 / 60.0)
	_check(trail.visible, "Walking shows the trail")
	spirit.reset_motion()
	_check(not trail.visible and _marks(trail).is_empty(), "A placement (a replay seek) clears every mark")
	spirit.position += Vector3(5, 0, 0)
	spirit.advance_motion(Vector3(5, 0, 0), 1.0 / 60.0, false)
	spirit.position += Vector3(0, 0, 4)
	spirit.advance_motion(Vector3(0, 0, 4), 1.0 / 60.0, false)
	_check(_marks(trail).is_empty(), "A jump leaves no marks along it")
	_walk(spirit, 2.0, 1.0 / 60.0, true)
	_check(not trail.visible and _marks(trail).is_empty(), "Reduce motion shows no trail")
	var walk: RefCounted = trail.get_meta(TrailKit.WALK_META)
	spirit.advance_motion(Vector3.ZERO, 1.0 / 60.0, false)
	for lap in range(3):
		_walk(spirit, 20.0, 1.0 / 30.0)
		_stand(spirit, 1.0, 1.0 / 30.0)
	_walk(spirit, 0.5, 1.0 / 30.0)
	_check(walk.clock < 1.0 and not _marks(trail).is_empty(), "The trail clock starts again after the marks fade, so births stay small: %.2f" % walk.clock)
	_walk(spirit, 70.0, 1.0 / 30.0)
	_check(walk.clock <= TrailKit.REBASE_AFTER + 0.1 and not _marks(trail).is_empty(), "and is moved back on a long walk: %.2f" % walk.clock)
	var material := trail.material_override as ShaderMaterial
	_check(TrailKit.OPACITY <= 0.6 and material.render_priority < -1, "Marks are at most 0.6 strong and drawn before the pair tags")
	_check(TrailKit.LIFT > 0.006 and TrailKit.LIFT < 0.0095, "Marks lie over the floor's lines and under the pair tags")
	# A world's recorded target holds for its frame only: a screen that then
	# moves the spirit itself (Home taking the pair over) still leaves marks.
	var home := _spirit()
	home.wear(Outfit.of("leaves", true))
	home.travel_target = home.position
	home.advance_motion(Vector3.ZERO, 1.0 / 60.0, false)
	_walk(home, 2.0, 1.0 / 60.0)
	_check(not _marks(_trail(home)).is_empty() and home.travel_target == Vector3.INF, "A walk with no recorded target follows the drawn pip (Home)")
	home.free()
	var other := _spirit()
	other.wear(Outfit.of("leaves", true))
	_check(_trail(other).material_override == material, "Every trail draws with one shared material")
	_check(trail.multimesh.instance_count == TrailKit.MAX_MARKS and trail.multimesh.mesh.get_surface_count() == 1, "One instanced node of six marks per pip")
	RaceGhost._veil(other, Look.PEACH)
	var veiled: Variant = _trail(other).get_instance_shader_parameter(TrailKit.VEIL)
	_check(veiled == null or is_equal_approx(float(veiled), RaceGhost.VEIL), "The race ghost's trail fades with it")
	_check(_trail(other).get_meta(TrailKit.VEIL_META) == TrailKit.VEIL, "and names its veil for the ghost")
	spirit.wear({})
	_check(_trail(spirit) == null, "Taking the trail off removes it")
	spirit.free()
	other.free()

func _trail_pictures() -> void:
	for place: StringName in [PipOutfit.STUDIO, PipOutfit.STAGE, PipOutfit.WARDROBE]:
		var pip: Node3D = Stage.pip(Look.PEACH, Outfit.of("little_tune", true), place)
		root.add_child(pip)
		var trail := _trail(pip)
		_check(trail != null and not trail.top_level and trail.visible and trail.multimesh.visible_instance_count == TrailKit.SAMPLE.size(), "A pictured pip (%s) shows still sample marks" % place)
		pip.free()

func _extras() -> void:
	var spirit := _spirit()
	spirit.wear(Outfit.of("pocket_pebble", true))
	var pebble: MeshInstance3D = spirit._wearing.nodes()[0]
	var triangles := (pebble.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	_check(pebble.visible and triangles <= 80, "The pebble shows within 80 triangles: %d" % triangles)
	# The pip tells its outfit what it carries every pose (pip_outfit.gd set_carrying).
	spirit.carrying_seed = true
	spirit.advance_motion(Vector3.ZERO, 1.0 / 60.0, false)
	_check(not pebble.visible, "The pebble hides while a seed or the lens is carried")
	spirit.carrying_seed = false
	spirit.advance_motion(Vector3.ZERO, 1.0 / 60.0, false)
	_check(pebble.visible, "and comes back once it is let go")
	spirit.carrying_seed = true
	spirit.wear({"carry": "pocket_pebble", "hat": "daisy"})
	_check(not spirit._wearing.nodes().filter(func(node: Node) -> bool: return node.get_parent() == spirit.torso)[0].visible, "A pebble put on while carrying starts hidden")
	spirit.carrying_seed = false
	spirit.wear({"foot_ring": "soft_ring", "bell_sound": "wood_chime"})
	_check(spirit.find_children("SoftRing", "", true, false).is_empty() and spirit._wearing.nodes().is_empty(), "No ring or chime in a world (chapters, Home)")
	spirit.set_place(PipOutfit.STAGE)
	_check(spirit.find_children("SoftRing", "", true, false).size() == 1 and spirit._wearing.nodes().size() == 1, "A room or result page's pip shows the ring, not the chime")
	spirit.set_place(PipOutfit.WARDROBE)
	_check(spirit._wearing.nodes().size() == 2 and spirit.outfit() == {"foot_ring": "soft_ring", "bell_sound": "wood_chime"}, "The Wardrobe shows the ring and the chime, still wearing the same")
	spirit.set_place(PipOutfit.STUDIO)
	_check(spirit._wearing.nodes().is_empty(), "Other pictures show neither")
	var plain := Camera3D.new()
	var ringed := Camera3D.new()
	root.add_child(plain)
	root.add_child(ringed)
	Stage.frame(plain, {})
	Stage.frame(ringed, {"foot_ring": "soft_ring"})
	_check(plain.transform.is_equal_approx(ringed.transform), "A ring wearer's picture elsewhere (no ring drawn) is framed as the default look")
	Stage.frame(ringed, {"foot_ring": "soft_ring"}, PipOutfit.WARDROBE)
	_check(not plain.transform.is_equal_approx(ringed.transform), "and the Wardrobe pulls back to show the ring")
	plain.free()
	ringed.free()
	var image := preload("res://presentation/pip_wear/soft_ring.gd").ring_image(64)
	_check(image.get_pixel(32, 32).a == 0.0 and image.get_pixel(32, 2).a > 0.0, "The ring is a ring: clear in the middle, drawn round the edge")
	var ring := {"foot_ring": "soft_ring"}
	_check(Snapshots.key(Look.PEACH, ring, Vector2i(10, 10), 0.0, PipOutfit.STAGE) != Snapshots.key(Look.PEACH, ring, Vector2i(10, 10), 0.0), "Still pictures of an item shown only in some places are kept apart by place")
	_check(Snapshots.key(Look.PEACH, {"trail": "leaves"}, Vector2i(10, 10), 0.0, PipOutfit.STAGE) == Snapshots.key(Look.PEACH, {"trail": "leaves"}, Vector2i(10, 10), 0.0), "and any other outfit is drawn once for every place")
	spirit.free()
