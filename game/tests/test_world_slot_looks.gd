extends SceneTree
## Each slot's pip in a chapter world wears its own player's look
## (IslandWorld.wear_slots, presentation/slot_looks.gd), in every family of
## world (First Steps, Relay and the lighthouse family), and keeps it when a
## stage is built again; a slot left out wears the default look, and the other
## slot's look never moves to it. A solo chapter (RelayPreview with no room)
## dresses both pips in the player's own look.
const Registry = preload("res://services/chapter_registry.gd")
const RelayPreview = preload("res://relay_preview.gd")
const Wardrobe = preload("res://services/wardrobe.gd")
const TurnLooks = preload("res://services/turn_looks.gd")
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
	await _solo()
	await _room()
	Catalog.set_offered([])
	print("AFTER YOU WORLD LOOKS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

## Solo play: the screen with no online session dresses both pips in the
## player's look, from the signed-in player's wardrobe, live and in replays.
func _solo() -> void:
	var server := "https://looks.example.test"
	var me := "aaaaaaaaaaaaaaaaaaaaaa"
	var path := "user://test-world-looks-wardrobe-%s.json" % Crypto.new().generate_random_bytes(6).hex_encode()
	var wardrobe: RefCounted = Wardrobe.new(path)
	Wardrobe.use_shared(wardrobe)
	wardrobe.scope_source = func() -> Dictionary: return {"server": server, "owner": me}
	wardrobe.set_enabled(server, me, true)
	wardrobe.note_view(server, me, {"name_price": 0.0, "wardrobe": {"items": ["daisy", "tide"], "packs": [], "look": {"hat": "daisy", "body": "tide"}, "look_revision": 1.0,
		"offered": ["daisy", "seashell", "tide"], "offered_packs": [], "sets": {}, "unlocked": []}})
	var key := _key("relay-isles")
	var world: Node3D = Registry.world_script(key).new()
	root.add_child(world)
	GraphicsPolicy.apply(world, {"graphics_quality": "balanced"})
	world.load_level(Registry.definition(key))
	await _frames(4)
	var screen: Node3D = RelayPreview.new()
	screen.world = world
	var worn := {"hat": "daisy", "body": "tide"}
	screen._dress([])
	_check(world.actors.p0.outfit() == worn and world.actors.p1.outfit() == worn, "Solo play: both pips wear the player's look")
	screen._dress([{"player_slot": "p0", "recording_hash": "a".repeat(64)}], true)
	_check(world.actors.p0.outfit() == worn and world.actors.p1.outfit() == worn, "A solo replay keeps the player's look on both pips")
	screen.free()
	world.queue_free()
	await _frames(2)
	Wardrobe.use_shared(null)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

## A room: the viewer (p1 here) wears their look on the ready card and in a live
## turn (_reset_live dresses both), the partner theirs, and the Watch preview of
## the viewer's turn not sent yet plays in the viewer's look, not the default.
func _room() -> void:
	var server := "https://looks.example.test"
	var me := "aaaaaaaaaaaaaaaaaaaaaa"
	var friend := "bbbbbbbbbbbbbbbbbbbbbb"
	var path := "user://test-world-looks-room-wardrobe-%s.json" % Crypto.new().generate_random_bytes(6).hex_encode()
	var looks_path := "user://test-world-looks-room-turns-%s.json" % Crypto.new().generate_random_bytes(6).hex_encode()
	var wardrobe: RefCounted = Wardrobe.new(path)
	Wardrobe.use_shared(wardrobe)
	wardrobe.scope_source = func() -> Dictionary: return {"server": server, "owner": me}
	wardrobe.set_enabled(server, me, true)
	wardrobe.note_view(server, me, {"name_price": 0.0, "wardrobe": {"items": ["daisy"], "packs": [], "look": {"hat": "daisy"}, "look_revision": 1.0,
		"offered": ["daisy", "seashell", "tide"], "offered_packs": [], "sets": {}, "unlocked": []}})
	var store: RefCounted = TurnLooks.new(looks_path)
	TurnLooks.use_shared(store)
	var partner_turn := {"player_slot": "p0", "recording_hash": "b".repeat(64)}
	store.note_member(friend, {"body": "tide"})
	store.note_turn(partner_turn.recording_hash, {"hat": "seashell"})
	var room_script := GDScript.new()
	room_script.source_code = "extends RefCounted
var room := {}
func snapshot() -> Dictionary:
	return room.duplicate(true)
func pending() -> Dictionary:
	return {}
"
	room_script.reload()
	var journey: RefCounted = room_script.new()
	journey.set("room", {"player_slot": "p1", "host_id": friend, "guest_id": me})
	var key := _key("relay-isles")
	var world: Node3D = Registry.world_script(key).new()
	root.add_child(world)
	GraphicsPolicy.apply(world, {"graphics_quality": "balanced"})
	world.load_level(Registry.definition(key))
	await _frames(4)
	var screen: Node3D = RelayPreview.new()
	screen.world = world
	screen.online_session = RefCounted.new()
	screen.journey = journey
	screen._dress([partner_turn])
	_check(world.actors.p1.outfit() == {"hat": "daisy"} and world.actors.p0.outfit() == {"hat": "seashell"}, "Room ready card and live turn: the viewer wears their look, the partner's turn its own")
	screen._dress([])
	_check(world.actors.p1.outfit() == {"hat": "daisy"} and world.actors.p0.outfit() == {"body": "tide"}, "Room waiting view: the partner wears the look they wear now")
	screen.review = {"player_slot": "p1", "recording_hash": "c".repeat(64)}
	screen._dress([screen.review, partner_turn], true)
	_check(world.actors.p1.outfit() == {"hat": "daisy"} and world.actors.p0.outfit() == {"hat": "seashell"}, "Watch preview: the viewer's unsent turn plays in their look")
	screen.review = {}
	screen._dress([{"player_slot": "p1", "recording_hash": "c".repeat(64)}, partner_turn], true)
	_check(world.actors.p1.outfit().is_empty(), "A replay of a turn this phone never heard a look for still plays in the default")
	screen.free()
	world.queue_free()
	await _frames(2)
	Wardrobe.use_shared(null)
	TurnLooks.use_shared(null)
	for file: String in [path, looks_path]: DirAccess.remove_absolute(ProjectSettings.globalize_path(file))
