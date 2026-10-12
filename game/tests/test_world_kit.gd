extends SceneTree
## World kit components (presentation/kit): material cache, cutaway, badges and
## looks. Scenery shares cached materials; nothing that changes a material may
## reach another mesh through that cache.
const Primitives = preload("res://presentation/kit/primitives.gd")
const Cutaway = preload("res://presentation/kit/cutaway.gd")
const Badges = preload("res://presentation/kit/badges.gd")
const Look = preload("res://presentation/kit/look.gd")
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
	_check_looks()
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
	for style: String in Badges.STYLES:
		var badge := Badges.make(spirit, style)
		_check(badge.get_parent() == spirit and badge.no_depth_test and badge.billboard == BaseMaterial3D.BILLBOARD_ENABLED and badge.font != null, "Badge style builds a readable label: " + style)
	spirit.free()

func _check_looks() -> void:
	for name: String in Look.PRESETS:
		var look := Look.preset(name)
		for field: String in ["sky", "ambient", "ambient_energy", "sun", "sun_energy", "bounce", "bounce_energy", "mote"]:
			_check(look.has(field), "Look %s defines %s" % [name, field])
