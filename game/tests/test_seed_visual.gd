extends SceneTree
## Every world that draws a seed builds it through SeedVisual, leaves included.
const Registry = preload("res://services/chapter_registry.gd")
const Levels = preload("res://core/levels.gd")
const SeedVisual = preload("res://presentation/seed_visual.gd")
const IslandWorld = preload("res://presentation/island_world.gd")
const LighthouseWorld = preload("res://presentation/lighthouse_world.gd")
const LighthouseCatalog = preload("res://core/lighthouse/stage_catalog.gd")
const MemoryWorld = preload("res://presentation/story_memory_world.gd")
const KeepsakeVisual = preload("res://presentation/keepsake_visual.gd")
## Worlds that carry the seed. Every other world carries a lens or a ball.
const SEEDED := [Registry.FIRST_STEPS, Registry.RELAY]
const SEEDLESS := [Registry.HIGH_AND_LOW, Registry.ROLLING_HOME, Registry.HOUSE, Registry.CONSERVATORY, Registry.LONG_WAY_HOME, Registry.WISHING_WELL, Registry.LONG_WAY_HOME_V2, Registry.TURN_OF_THE_TIDE, Registry.LIGHTHOUSE_V2]
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_check_builder()
	for key: String in Registry.keys():
		_check(key in SEEDED or key in SEEDLESS, "Every chapter world is classified as seeded or seedless: " + key)
		var world: Node3D = Registry.world_script(key).new()
		root.add_child(world)
		world.set_process(false)
		world.load_level(Registry.definition(key))
		world.show_stage(Registry.definition(key).stages[0])
		if key in SEEDED: _check_seeded(world, key)
		else: _check(world.seed == null and _seeds(world).is_empty(), "A seedless chapter draws no seed: " + key)
		world.free()
	for index in range(Levels.all_levels().size()):
		var island := IslandWorld.new()
		root.add_child(island)
		island.set_process(false)
		island.load_level(Levels.get_level(index))
		_check_seeded(island, "island %d" % index)
		island.free()
	var lighthouse := LighthouseWorld.new()
	root.add_child(lighthouse)
	lighthouse.set_process(false)
	lighthouse.load_level(LighthouseCatalog.definition(LighthouseCatalog.STAGE_IDS[0]))
	_check(lighthouse.seed == null and _seeds(lighthouse).is_empty(), "The Lighthouse carries its lens, not a seed")
	lighthouse.free()
	var memory := MemoryWorld.new()
	_check(memory.configure(Registry.RELAY, "arrival"), "The Relay memory illustration is available")
	root.add_child(memory)
	var resting := _seeds(memory)
	_check(resting.size() == 1 and SeedVisual.leaves(resting[0]).size() == SeedVisual.LEAF_COUNT, "The seed resting by the empty Relay garden has its leaves")
	var host := IslandWorld.new()
	root.add_child(host)
	for shared: bool in [false, true]:
		var keepsake := KeepsakeVisual.create(host, {"stage_id": "first-light"}, shared)
		var found := _seeds(keepsake)
		_check(found.size() == 1 and SeedVisual.leaves(found[0]).size() == SeedVisual.LEAF_COUNT, "The First Light keepsake is the canonical leafed seed (shared=%s)" % shared)
		keepsake.free()
	memory.free()
	host.free()
	await process_frame
	print("AFTER YOU SEED VISUAL: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _check_builder() -> void:
	var host := IslandWorld.new()
	root.add_child(host)
	var parent := Node3D.new()
	host.add_child(parent)
	var body := SeedVisual.create(host, SeedVisual.BODY_HALF_HEIGHT, Color("efba73"), Vector3(0, 0.27, 0), parent)
	var shape := body.mesh as SphereMesh
	var leaves := SeedVisual.leaves(body)
	_check(body.has_meta(SeedVisual.META) and body.scale == Vector3.ONE and is_equal_approx(shape.radius, SeedVisual.BODY_RADIUS) and is_equal_approx(shape.height, 0.576), "At keepsake size the body matches the icon seed")
	var stem := body.get_node_or_null("SeedStem") as MeshInstance3D
	var glow := body.get_node_or_null("SeedGlow") as MeshInstance3D
	_check(leaves.size() == SeedVisual.LEAF_COUNT and leaves[0].position.is_equal_approx(SeedVisual.LEAF_AT) and stem != null and stem.position.y > 0.0, "The leaf sits on a stem above the body, as in the icon")
	_check(glow != null and (glow.material_override as StandardMaterial3D).shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED and is_equal_approx((glow.material_override as StandardMaterial3D).albedo_color.a, SeedVisual.GLOW_ALPHA), "The seed carries a soft unshaded glow")
	SeedVisual.tint_glow(body, Color("91d6c6"))
	_check(Color((glow.material_override as StandardMaterial3D).albedo_color, 1.0) == Color("91d6c6"), "The glow follows the carry colour")
	var upright := true
	for leaf: MeshInstance3D in leaves:
		upright = upright and leaf.position.y > 0.0 and absf(leaf.rotation.z) < 0.7 and is_zero_approx(leaf.rotation.x) and is_zero_approx(leaf.rotation.y)
		upright = upright and leaf.material_override != body.material_override
	_check(upright, "Leaves point up from the body and keep their own green material")
	var small := SeedVisual.create(host, 0.13, Color("ffda83"), Vector3.ZERO, parent)
	_check(is_equal_approx((small.mesh as SphereMesh).height, 0.26), "A gameplay seed keeps the old seed's vertical size")
	(small.material_override as StandardMaterial3D).albedo_color = Color("91d6c6")
	var leaf_material := SeedVisual.leaves(small)[0].material_override as StandardMaterial3D
	_check(leaf_material.albedo_color == SeedVisual.LEAF, "Carry colour changes the body only, never the leaves")
	host.free()

func _check_seeded(world: Node3D, label: String) -> void:
	_check(world.seed is MeshInstance3D and world.seed.has_meta(SeedVisual.META), "The world's seed comes from the shared builder: " + label)
	_check(SeedVisual.leaves(world.seed).size() == SeedVisual.LEAF_COUNT, "The world's seed has its leaves: " + label)
	var carried := 0
	var leafed := true
	for found: Node in _seeds(world):
		leafed = leafed and SeedVisual.leaves(found).size() == SeedVisual.LEAF_COUNT
		# The First Light keepsake landmark is the same seed on its pedestal.
		if not (is_instance_valid(world.keepsake_landmark) and world.keepsake_landmark.is_ancestor_of(found)): carried += 1
	_check(carried == 1 and leafed, "The world draws one gameplay seed and every seed it shows is leafed: " + label)

func _seeds(node: Node) -> Array[Node]:
	var found: Array[Node] = []
	if node.has_meta(SeedVisual.META): found.append(node)
	for child: Node in node.get_children(): found.append_array(_seeds(child))
	return found

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
