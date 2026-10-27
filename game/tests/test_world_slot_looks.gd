extends SceneTree
## Each slot's pip in a chapter world wears its own player's look
## (IslandWorld.wear_slots, presentation/slot_looks.gd), in every family of
## world (First Steps, Relay and the lighthouse family), and keeps it when a
## stage is built again; a slot left out wears the default look, and the other
## slot's look never moves to it.
const Registry = preload("res://services/chapter_registry.gd")
const GraphicsPolicy = preload("res://services/graphics_policy.gd")
const Catalog = preload("res://services/cosmetic_catalog.gd")

const LEVELS := ["first-steps", "relay-isles", "the-wishing-well"]

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
		print("FAIL: " + message)

func _frames(count: int) -> void:
	for i in range(count): await process_frame

func _key(level_id: String) -> String:
	for key: String in Registry.keys():
		if str(Registry.descriptor(key).get("level_id", "")) == level_id: return key
	return ""

func _run() -> void:
	# The server's catalogue releases these (services/wardrobe.gd sets it from the wallet read).
	Catalog.set_offered(["daisy", "seashell", "tide"])
	var looks := {"p0": {"hat": "daisy"}, "p1": {"hat": "seashell", "body": "tide"}}
	for level_id: String in LEVELS:
		var key := _key(level_id)
		_check(not key.is_empty(), "%s is a chapter" % level_id)
		if key.is_empty(): continue
		var world: Node3D = Registry.world_script(key).new()
		root.add_child(world)
		GraphicsPolicy.apply(world, {"graphics_quality": "balanced"})
		_check(world.has_method("wear_slots"), "%s's world dresses its slots" % key)
		world.wear_slots(looks)
		world.load_level(Registry.definition(key))
		await _frames(4)
		_check(world.actors.has("p0") and world.actors.has("p1"), "%s builds both pips" % key)
		if not (world.actors.has("p0") and world.actors.has("p1")): continue
		_check(world.actors.p0.outfit() == looks.p0 and world.actors.p1.outfit() == looks.p1, "%s: each pip wears its own player's look from the first build" % key)
		world.wear_slots({"p1": {"body": "tide"}})
		_check(world.actors.p0.outfit().is_empty() and world.actors.p1.outfit() == {"body": "tide"}, "%s: a slot left out goes back to the default look at once" % key)
		world.load_level(Registry.definition(key))
		await _frames(4)
		_check(world.actors.p0.outfit().is_empty() and world.actors.p1.outfit() == {"body": "tide"}, "%s: a stage built again keeps each slot's look" % key)
		world.queue_free()
		await _frames(2)
	Catalog.set_offered([])
	print("AFTER YOU WORLD LOOKS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
