extends SceneTree
## World kit components (presentation/kit): material cache, cutaway, badges and
## looks. Scenery shares cached materials; nothing that changes a material may
## reach another mesh through that cache.
const Primitives = preload("res://presentation/kit/primitives.gd")
const Cutaway = preload("res://presentation/kit/cutaway.gd")
const Badges = preload("res://presentation/kit/badges.gd")
const Look = preload("res://presentation/kit/look.gd")
const LabelBubble = preload("res://presentation/kit/label_bubble.gd")
const ViewFit = preload("res://presentation/kit/view_fit.gd")
const WallFade = preload("res://presentation/kit/wall_fade.gd")
const LeverLooks = preload("res://presentation/kit/lever_looks.gd")
const LighthouseWorld = preload("res://presentation/lighthouse_world.gd")
const LightCatalog = preload("res://core/lighthouse/stage_catalog.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _run() -> void:
	_check_materials()
	_check_cutaway()
	_check_badges()
	_check_label_bubbles()
	_check_looks()
	_check_follow_angle()
	_check_view_fit()
	_check_wall_fade()
	_check_lever_looks()
	print("WORLD KIT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## A wall in front of a spot fades while a spirit stands in it, eased over
## frames or snapped, and comes back solid and opaque with its own shadow once
## the spot is empty; a shared look is copied first, never changed in place; a
## wall serving two spots shows the fainter.
func _check_wall_fade() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var look := Primitives.shared_material(Color("b8a283"))
	var wall := Primitives.mesh_node(Primitives.box_mesh(Vector3.ONE), look, Vector3.ZERO, holder)
	var side := Primitives.mesh_node(Primitives.box_mesh(Vector3.ONE), look, Vector3.ZERO, holder)
	side.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var fade := WallFade.new()
	fade.add([0, 0, 50, 50], [wall, side])
	fade.add([60, 0, 110, 50], [side])
	_check(wall.material_override != look and not Primitives.is_shared(wall.material_override) and Primitives.changed_shared_looks().is_empty(), "A faded wall takes its own copy of a shared look")
	var inside := PackedVector2Array([Vector2(25, 25)])
	var away := PackedVector2Array([Vector2(500, 500)])
	fade.occupy(inside)
	_check(fade.moving() and fade.faded_spots() == 1 and wall.material_override.albedo_color.a == 1.0, "A spirit in a spot starts its walls fading, eased")
	for frame in range(30): fade.advance(1.0 / 60.0)
	var material: StandardMaterial3D = wall.material_override
	_check(not fade.moving() and is_equal_approx(material.albedo_color.a, WallFade.FADED_ALPHA) and material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and wall.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "Half a second later the wall in front has faded")
	_check(is_equal_approx(side.material_override.albedo_color.a, WallFade.FADED_ALPHA), "A wall shared with an empty spot shows the fainter one")
	fade.occupy(away, true)
	_check(not fade.moving() and material.albedo_color.a == 1.0 and material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and wall.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON and side.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "Snapped back, the walls are solid and opaque with their own shadows")
	fade.occupy(PackedVector2Array([Vector2(80, 25)]), true)
	_check(material.albedo_color.a == 1.0 and is_equal_approx(side.material_override.albedo_color.a, WallFade.FADED_ALPHA), "Only the walls of the occupied spot fade")
	holder.free()

## Each lever look stands inside its lever's reach, east no further than the
## plain housing; its anchor's knob point sits on its top; a pull eases over
## PULL_SECONDS to the same pose a snapped pull shows (so a replay agrees),
## and a release comes back to the same pose it was built in.
func _check_lever_looks() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	for kind: String in LeverLooks.LEVER_KINDS:
		var look: RefCounted = LeverLooks.build(kind, Vector3(1, 0.5, 2), Color.RED, holder)
		var built := _look_pose(look)
		var top := _look_top(look)
		_check(_look_inside(look), "The %s look stays inside its lever's reach" % kind)
		# journey_world._knob_top: the anchor's knob centre plus KNOB_RADIUS.
		var tail: float = look.anchor.position.y + 0.4 + 0.09 - look.root.position.y
		_check(absf(tail - top) < 0.03, "The %s look's anchor puts a bubble's tail on its top (%.3f, %.3f)" % [kind, tail, top])
		look.set_pulled(true)
		_check(look.moving() and look.shown() == 0.0, "A pull eases from where the %s look stands" % kind)
		for frame in range(int(ceil(LeverLooks.PULL_SECONDS * 60.0)) + 1): look.advance(1.0 / 60.0)
		var eased := _look_pose(look)
		_check(not look.moving() and look.shown() == 1.0 and eased != built, "The %s look's pull plays out and rests pulled" % kind)
		var snapped: RefCounted = LeverLooks.build(kind, Vector3(1, 0.5, 2), Color.RED, holder)
		snapped.set_pulled(true, true)
		_check(_look_pose(snapped) == eased, "An eased and a snapped %s pull end in the same pose" % kind)
		_check(_look_inside(snapped), "Pulled, the %s look still stays inside its lever's reach" % kind)
		look.set_pulled(false, true)
		_check(_look_pose(look) == built, "Let go, the %s look is back as it was built" % kind)
	# A valve: one dial mark per value, its arrow eased or snapped to the same
	# turn for a value, a pull ignored, its sign spot up behind it.
	var valve: RefCounted = LeverLooks.build("valve", Vector3(1, 0.5, 2), Color.RED, holder, [0, 1, 2, 3])
	_check(_look_inside(valve, LeverLooks.REACH), "The valve stays inside its selector's reach")
	var wheel_top := -INF
	for node: Node in valve.wheel().find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		wheel_top = maxf(wheel_top, (valve.root.global_transform.affine_inverse() * mesh.global_transform * mesh.get_aabb()).end.y)
	_check(absf(valve.anchor.position.y + 0.49 - valve.root.position.y - wheel_top) < 0.03, "The valve's anchor puts a bubble's tail on its wheel (%.3f, %.3f)" % [valve.anchor.position.y + 0.49 - valve.root.position.y, wheel_top])
	var ticks: Array = valve.root.find_children("*", "MeshInstance3D", false, false).filter(func(node: Node) -> bool: return ((node as MeshInstance3D).material_override as StandardMaterial3D).albedo_color == LeverLooks.CREAM)
	_check(ticks.size() == 0 + 1 + 2 + 3 + 1, "The dial marks a bar for the first value and one, two, three bands for the rest (%d)" % ticks.size())
	valve.set_value(3)
	for frame in range(60): valve.advance(1.0 / 60.0)
	var eased := _look_pose(valve)
	var snapped: RefCounted = LeverLooks.build("valve", Vector3(1, 0.5, 2), Color.RED, holder, [0, 1, 2, 3])
	snapped.set_value(3, true)
	_check(not valve.moving() and is_equal_approx(valve.wheel().rotation.y, -LeverLooks.VALVE_SWEEP) and _look_pose(snapped) == eased, "The valve's arrow turns to the last value, eased or snapped alike")
	valve.set_pulled(true, true)
	_check(_look_pose(valve) == eased, "A pull leaves a valve as it is")
	var sign: Vector3 = valve.sign_point() - valve.root.position
	_check(sign.y > wheel_top and sign.z < -0.1, "The valve's sign stands up behind it, over its wheel")
	holder.free()

## Every mesh of a look inside REACH of its spot, east no further than
## EAST_SIDE, and nothing below its floor.
func _look_inside(look: RefCounted, east: float = LeverLooks.EAST_SIDE) -> bool:
	for node: Node in look.root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var box: AABB = look.root.global_transform.affine_inverse() * mesh.global_transform * mesh.get_aabb()
		if box.position.x < -LeverLooks.REACH - 0.001 or box.end.x > east + 0.001 or absf(box.position.z) > LeverLooks.REACH or absf(box.end.z) > LeverLooks.REACH or box.position.y < -0.001: return false
	return true

## The top of a look's meshes above its spot.
func _look_top(look: RefCounted) -> float:
	var top := -INF
	for node: Node in look.root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		top = maxf(top, (look.root.global_transform.affine_inverse() * mesh.global_transform * mesh.get_aabb()).end.y)
	return top

## Every mesh's transform under a look, rounded to 0.1 mm.
func _look_pose(look: RefCounted) -> Array:
	var pose: Array = []
	for node: Node in look.root.find_children("*", "MeshInstance3D", true, false):
		var t: Transform3D = (node as MeshInstance3D).global_transform
		for v: Vector3 in [t.basis.x, t.basis.y, t.basis.z, t.origin]: pose.append(Vector3i((v * 10000.0).round()))
	return pose

func _check_materials() -> void:
	var first := Primitives.shared_material(Color("8a6b4e"))
	_check(first == Primitives.shared_material(Color("8a6b4e")), "One cached material per scenery colour")
	_check(first != Primitives.shared_material(Color("8a6b4e"), 0.5), "Roughness is part of the cached look")
	_check(Primitives.is_shared(first) and not Primitives.is_shared(Primitives.fresh_material(Color.RED)), "Only cached materials carry the shared flag")
	_check(Primitives.fresh_material(Color.RED) != Primitives.fresh_material(Color.RED), "Fresh materials are never shared")
	var glow := Primitives.shared_material(Color("ffd894"), 0.9, Color("f2a94e"), 0.7)
	_check(glow.emission_enabled and glow != Primitives.shared_material(Color("ffd894")), "Glowing scenery has its own cached material")
	_check(Primitives.shared_mesh("box", 0.2, 0.3, 0.4) == Primitives.shared_mesh("box", 0.2, 0.3, 0.4), "Static scenery shares meshes")
	var holder := Node3D.new()
	root.add_child(holder)
	var one := Primitives.mesh_node(Primitives.box_mesh(Vector3.ONE), first, Vector3.ZERO, holder)
	var two := Primitives.mesh_node(Primitives.box_mesh(Vector3.ONE), first, Vector3.ZERO, holder)
	var own := Primitives.own_material(one)
	_check(own != first and not Primitives.is_shared(own) and one.material_override == own and two.material_override == first, "Taking a mesh's own material copies a shared one")
	_check(Primitives.own_material(one) == own, "A private material is kept")
	_check(Primitives.changed_shared_looks().is_empty(), "No cached look has changed in place: %s" % [Primitives.changed_shared_looks()])
	var tint := first.albedo_color
	first.albedo_color = Color.RED
	_check(Primitives.changed_shared_looks().size() == 1, "A cached look changed in place is named")
	first.albedo_color = tint
	_check(Primitives.changed_shared_looks().is_empty(), "Put back, it is no longer named")
	var shape := Primitives.cached_shape(Primitives.box_mesh(Vector3(0.123, 0.2, 0.3))) as BoxMesh
	_check(Primitives.cached_shape(Primitives.box_mesh(Vector3(0.123, 0.2, 0.3))) == shape and Primitives.cached_shape(Primitives.box_mesh(Vector3(0.124, 0.2, 0.3))) != shape, "One cached mesh per shape")
	shape.size.x = 0.5
	_check(Primitives.changed_shared_looks().size() == 1, "A shared shape resized in place is named")
	shape.size.x = 0.123
	_check(Primitives.changed_shared_looks().is_empty(), "Put back, it is no longer named either")
	_check(Primitives.shared_material(Color(1, 1, 1, 0.999)) != Primitives.shared_material(Color.WHITE), "A look that is barely see-through is not the opaque look")
	# Every world's shape helpers share one cached material per look; one
	# changed later takes its own copy first.
	var world: Node3D = LighthouseWorld.new()
	holder.add_child(world)
	var a: MeshInstance3D = world.box(Vector3.ONE, Color("8a6b4e"), Vector3.ZERO, holder)
	var b: MeshInstance3D = world.sphere(0.3, Color("8a6b4e"), Vector3.ZERO, holder)
	_check(a.material_override == first and b.material_override == first, "A world's shapes of one colour share its cached look")
	_check(world.material(Color("8a6b4e")) != first, "A world's material() is a new one of the caller's own")
	world._glow(a, Color.WHITE, 1.0)
	_check(a.material_override != first and a.material_override.emission_enabled and not first.emission_enabled and b.material_override == first, "Glowing one mesh glows its own copy, never the look")
	_check(a.material_override == Primitives.shared_material(first.albedo_color, first.roughness, Color.WHITE, 1.0), "A lit look is the kit's glowing look of its colour, shared by every mesh that glows alike")
	world._glow(b, Color.WHITE, 1.0)
	_check(b.material_override == a.material_override, "Two meshes of one look lit alike share one material")
	world._glow(a, Color.WHITE, 0.0)
	_check(not a.material_override.emission_enabled and not Primitives.is_shared(a.material_override) and b.material_override.emission_enabled, "Put out, a mesh takes its own copy; the glowing look stays lit for the rest")
	var motes: Array = world.motes
	_check(not Primitives.is_shared(motes[0].material_override) and motes.all(func(mote: MeshInstance3D) -> bool: return mote.material_override == motes[0].material_override), "The motes share one material of the world's own, which the look tints")
	_check(Primitives.changed_shared_looks().is_empty(), "Building and glowing changed no cached look: %s" % [Primitives.changed_shared_looks()])
	_check(Primitives.rect_minus_hole([0, 0, 100, 100], []) == [[0, 0, 100, 100]], "No hole keeps the floor whole")
	_check(Primitives.rect_minus_hole([0, 0, 100, 100], [40, 40, 60, 60]).size() == 4, "A hole leaves four floor pieces")
	_check(Primitives.rect_minus_hole([0, 0, 100, 100], [0, 40, 60, 100]).size() == 2, "A hole at an edge leaves only the pieces that exist")
	holder.free()

func _check_cutaway() -> void:
	var shared := Primitives.shared_material(Color("6f8b66"))
	var upstairs := Node3D.new()
	upstairs.position.y = 1.5
	upstairs.set_meta("bounds", [0, 0, 400, 300])
	var downstairs := Node3D.new()
	root.add_child(upstairs)
	root.add_child(downstairs)
	var faded := Primitives.mesh_node(Primitives.box_mesh(Vector3.ONE), shared, Vector3.ZERO, upstairs)
	var kept := Primitives.mesh_node(Primitives.box_mesh(Vector3.ONE), shared, Vector3.ZERO, downstairs)
	Cutaway.set_faded(upstairs, true)
	_check(faded.material_override != shared and is_equal_approx(faded.material_override.albedo_color.a, Cutaway.FADED_ALPHA), "Cutaway fades a floor's own copy of a shared material")
	_check(kept.material_override == shared and is_equal_approx(shared.albedo_color.a, 1.0) and shared.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED, "Cutaway never fades the same prop elsewhere")
	Cutaway.set_faded(upstairs, false)
	_check(is_equal_approx(faded.material_override.albedo_color.a, 1.0) and faded.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "Cutaway restores the floor")
	_check(Cutaway.below_raised(upstairs, {"x": 100, "height": 0}) and not Cutaway.below_raised(upstairs, {"x": 100, "height": 150}) and not Cutaway.below_raised(upstairs, {"x": 900, "height": 0}), "Below-floor rule matches the physical worlds")
	_check(Cutaway.anyone_below(upstairs, {"players": {"p0": {"x": 900, "height": 0}, "p1": {"x": 50, "height": 0}}}), "Celebration rule fades for either spirit")
	upstairs.free()
	downstairs.free()

func _check_badges() -> void:
	var spirit := Node3D.new()
	root.add_child(spirit)
	var badge := Badges.make(spirit)
	_check(badge.get_parent() == spirit and badge.no_depth_test and badge.billboard == BaseMaterial3D.BILLBOARD_ENABLED and badge.font != null and badge.get_meta("replay_role_badge", false), "One badge style builds a readable label")
	# Fixed size: letters are font_size * pixel_size / 2 of the view height.
	var share := float(badge.font_size) * badge.pixel_size / 2.0 * 720.0
	_check(badge.fixed_size and share > 20.0 and share < 28.0, "Badge letters land near 24 px on a 720 px view in every chapter: %.1f" % share)
	spirit.free()

func _check_looks() -> void:
	var world: Node3D = LighthouseWorld.new()
	root.add_child(world)
	world.set_process(false)
	var env: Environment = (world.find_children("*", "WorldEnvironment", false, false)[0] as WorldEnvironment).environment
	for name: String in Look.PRESETS:
		var look := Look.preset(name)
		for field: String in ["sky", "ambient", "ambient_energy", "sun", "sun_energy", "bounce", "bounce_energy", "mote"]:
			_check(look.has(field), "Look %s defines %s" % [name, field])
		# Applied twice, as a chapter load does after _ready: the gains never compound.
		Look.apply(world, name)
		Look.apply(world, name)
		_check(not world.sun.shadow_enabled and is_equal_approx(world.sun.light_energy, look.sun_energy * Look.SUN_GAIN) and is_equal_approx(env.ambient_light_energy, look.ambient_energy * Look.AMBIENT_GAIN),
			"Look %s lights the sun and ambient with the shared gains and no shadow pass" % name)
		var bounce: DirectionalLight3D = world.find_children("*", "DirectionalLight3D", false, false).filter(func(light: DirectionalLight3D) -> bool: return light != world.sun)[0]
		_check(bounce.visible and is_equal_approx(bounce.light_energy, look.bounce_energy), "Look %s fills the shaded sides with the bounce light" % name)
		# Without the fill (Low), the ambient carries a share of the bounce's energy.
		Look.apply(world, name, false)
		Look.apply(world, name, false)
		_check(not bounce.visible and is_equal_approx(env.ambient_light_energy, look.ambient_energy * Look.AMBIENT_GAIN + look.bounce_energy * Look.FILL_TO_AMBIENT) and is_equal_approx(world.sun.light_energy, look.sun_energy * Look.SUN_GAIN),
			"Look %s without the fill hides the bounce and raises only the ambient, once" % name)
		Look.apply(world, name)
		_check(bounce.visible and is_equal_approx(env.ambient_light_energy, look.ambient_energy * Look.AMBIENT_GAIN), "Look %s brings the fill back exactly" % name)
	world.free()

## The Lighthouse follow camera keeps the fit-all camera's angle, so live
## stick input maps to the same walking directions in every stage.
func _check_follow_angle() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	root.add_child(viewport)
	var world: Node3D = LighthouseWorld.new()
	viewport.add_child(world)
	world.set_process(false)
	world.load_level(LightCatalog.definition(LightCatalog.STAGE_IDS[0]))
	var fitted: Basis = world.camera.global_basis
	_check(not world._follows_view(), "The first Lighthouse stages fit the whole archipelago")
	world.load_level(LightCatalog.definition(LightCatalog.STAGE_IDS[4]))
	world.actors.p0.position = Vector3(5.0, 0, 0.5)
	world._follow_point = world._follow_target()
	world._frame_camera()
	_check(world._follows_view() and is_equal_approx(world.camera.size, world.FOLLOW_SIZE), "Later Lighthouse stages follow the active spirit")
	_check(world.camera.global_basis.is_equal_approx(fitted), "Following never changes the camera angle or the stick mapping")
	# A taller screen keeps the authored width in view; a phone keeps the size.
	viewport.size = Vector2i(1280, 960)
	world._frame_camera()
	_check(is_equal_approx(world.camera.size, world.FOLLOW_SIZE * 960.0 / 720.0), "A 4:3 tablet follows with the 16:9 width in view")
	viewport.size = Vector2i(1560, 720)
	world._frame_camera()
	_check(is_equal_approx(world.camera.size, world.FOLLOW_SIZE), "A phone keeps the authored follow size")
	viewport.free()

## One rule for every world camera (kit/view_fit.gd): grow only when narrower than 16:9.
func _check_view_fit() -> void:
	_check(ViewFit.fit(14.4, 16.0 / 9.0) == 14.4 and ViewFit.fit(14.4, 2340.0 / 1080.0) == 14.4, "16:9 and a phone keep the authored size exactly")
	_check(is_equal_approx(ViewFit.fit(12.0, 4.0 / 3.0), 16.0) and is_equal_approx(ViewFit.fit(12.0, 1.6), 12.0 * 16.0 / 9.0 / 1.6), "4:3 and 16:10 grow until the 16:9 width shows")
	_check(is_equal_approx(ViewFit.fit(10.0, 0.5), 10.0 * 16.0 / 9.0 / 0.5), "A portrait split screen still keeps the width (no aspect floor)")
	for bad: float in [0.0, -1.0, NAN]:
		_check(ViewFit.fit(9.2, bad) == 9.2, "An empty view keeps the authored size (%s)" % bad)
	var loose := Node.new()
	_check(ViewFit.viewport(9.2, loose) == 9.2, "A world outside the tree keeps the authored size")
	loose.free()

## One speech bubble for every lever, switch and place: raw values shown
## upper-cased, the chosen value filled, shared body pieces, own pills.
func _check_label_bubbles() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var bubble: Node3D = LabelBubble.create(holder, Vector3(1, 0.8, 0), ["low", "half", "high"], "half")
	var other: Node3D = LabelBubble.create(holder, Vector3(4, 0.8, 0), ["porch"])
	_check(bubble.get_parent() == holder and bubble.labels.size() == 3 and bubble.labels[0].text == "LOW" and other.labels[0].text == "PORCH", "A bubble shows its raw values upper-cased")
	_check(bubble.body.mesh == other.body.mesh and bubble.body.material_override == other.body.material_override and bubble.labels[0].font == other.labels[0].font, "Bubbles share their body mesh, body material and font")
	var pills: Array = []
	for label: Label3D in bubble.labels: pills.append(label.get_meta("backing"))
	_check(pills[0].mesh != pills[1].mesh and pills[0].material_override != pills[1].material_override and (pills[0].material_override as StandardMaterial3D).albedo_texture == (pills[1].material_override as StandardMaterial3D).albedo_texture, "Each pill keeps its own quad and material over one shared texture")
	var chosen := (pills[1].material_override as StandardMaterial3D).albedo_color
	_check(chosen.a > 0.9 and chosen.get_luminance() < 0.5 and bubble.labels[1].modulate.get_luminance() > 0.8, "The chosen value is a filled dark pill with cream letters")
	_check((pills[0].material_override as StandardMaterial3D).albedo_color.a == 0.0 and bubble.labels[0].modulate.a < 0.6 and bubble.labels[0].modulate.get_luminance() < 0.4, "Other values are dark, dimmed letters on the bubble")
	bubble.set_selected("high")
	_check((pills[2].material_override as StandardMaterial3D).albedo_color.a > 0.9 and (pills[1].material_override as StandardMaterial3D).albedo_color.a == 0.0, "Selecting a raw value moves the fill")
	_check(bubble.body.position.y > bubble.anchor.y and bubble.body.position.distance_to(bubble.anchor) < 1.2, "The bubble floats just above what it names")
	_check(bubble.labels[0].render_priority > (pills[0].material_override as StandardMaterial3D).render_priority and not bubble.labels[0].no_depth_test and not (pills[0].material_override as StandardMaterial3D).no_depth_test, "Letters draw over their own pill, and walls still hide a bubble")
	var before := bubble.position
	var tip: Vector2 = bubble.plane_tail()
	bubble.set_bob(false)
	bubble.set_lift(0.5)
	_check(is_equal_approx(bubble.position.y, before.y + 0.5) and bubble.plane_tail().distance_to(tip) < 0.001 and tip.distance_to(LabelBubble.plane_point(holder.to_global(bubble.anchor))) < 0.001, "A lifted bubble's body rises while its tail stretches, tip still on its anchor")
	bubble.set_lift(100.0)
	_check(bubble.lift < 100.0 and bubble.plane_tail().distance_to(tip) < 0.001, "A lift past the longest tail is cut short and the tip stays put")
	var other_tip: Vector2 = other.plane_tail()
	bubble.set_lift(0.0)
	_check(bubble.body.material_override == other.body.material_override and other.plane_tail().is_equal_approx(other_tip), "A lift stretches only that bubble's tail; the shared material is unchanged")
	_check_sentence_bubble(holder, other)
	holder.free()

## Sentence mode: the text keeps its own case, a long one takes two lines, a
## new sentence refits the body and the tail stays on its anchor.
func _check_sentence_bubble(holder: Node3D, word: Node3D) -> void:
	var short: Node3D = LabelBubble.new()
	short.build_sentence(holder, Vector3(-3, 0.8, 0), "Not quite yet…")
	_check(short.labels[0].text == "Not quite yet…" and short.values == ["Not quite yet…"], "A sentence keeps its own case on one line")
	_check(short.body.material_override == word.body.material_override and (short.labels[0].get_meta("backing").material_override as StandardMaterial3D).albedo_color.a == 0.0, "A sentence is a plain bubble: no pill is filled")
	var tip: Vector2 = short.plane_tail()
	var height: float = short.body.scale.y
	var long := "This crossing won't budge till someone's holding the far step…"
	short.set_sentence(long)
	_check(short.labels[0].text.count("\n") == 1 and short.labels[0].text.replace("\n", " ") == long, "A long sentence breaks onto two lines")
	_check(short.body.scale.y > height + 0.2 and short.plane_tail().distance_to(tip) < 0.001, "The body grows for the second line and the tail stays on its anchor")
	var lines: PackedStringArray = short.labels[0].text.split("\n")
	_check(absi(lines[0].length() - lines[1].length()) < long.length() / 4, "The break leaves two lines of about the same length (%s)" % str(lines))
