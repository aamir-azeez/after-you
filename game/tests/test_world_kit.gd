extends SceneTree
## World kit components (presentation/kit): material cache, cutaway, badges and
## looks. Scenery shares cached materials; nothing that changes a material may
## reach another mesh through that cache.
const Primitives = preload("res://presentation/kit/primitives.gd")
const Cutaway = preload("res://presentation/kit/cutaway.gd")
const Badges = preload("res://presentation/kit/badges.gd")
const Look = preload("res://presentation/kit/look.gd")
const LabelBubble = preload("res://presentation/kit/label_bubble.gd")
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
	print("WORLD KIT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

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
	viewport.free()

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
