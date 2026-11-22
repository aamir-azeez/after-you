extends SceneTree
## The one look of a thrown thing (presentation/kit/throw_look.gd):
## - First Steps @1's thrown seed looks as it did before the look was shared:
##   its recorded throw, drawn at 60 Hz, poses the seed, tumbles it and draws
##   its blur frame for frame as the old island_world.gd code did (FIRST_LOOK,
##   taken from that code), and under Reduce motion it neither spins nor blurs
##   (FIRST_STILL);
## - every item kind a pip can throw on the journey engine (each carried item
##   style, through first-steps@2's real throw) flies with the same look: its
##   blur shows and it tumbles in flight, and once it lands both are gone.
const FirstWorld = preload("res://presentation/first_steps_world.gd")
const First = preload("res://core/first_steps/simulation.gd")
const ContactShadows = preload("res://presentation/kit/contact_shadows.gd")
const CarriedItemKit = preload("res://presentation/kit/pieces/carried_item.gd")
const CarriedItems = preload("res://core/physical/carried_items.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Witness = preload("res://tests/first_steps_v2_witness.gd")
const Walk = preload("res://tests/cooperative_witness.gd")
const KEY := "first-steps@2"
const STAGE := "a-place-to-grow"
const MARK := [140, -90]
## sha256 of First Steps @1's recorded throw as drawn (_first_steps_frames),
## with motion and under Reduce motion, from the code before it was shared.
const FIRST_LOOK := "da4bdf745cda04a1d0d0bb64e398e9980601700215dd67611a7a25d5a3e59a95"
const FIRST_STILL := "2d752cd2b6c5f993eb8723fc38aea13e9aab03e90235239cb1b32dfcb35a5949"
var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _run() -> void:
	var moving := _first_steps_frames(false)
	var still := _first_steps_frames(true)
	_check(moving.frames > 60 and moving.spun and moving.blurred, "First Steps @1's throw flies, tumbles and blurs (%d frames)" % moving.frames)
	_check(still.frames > 60 and not still.spun and not still.blurred, "Under Reduce motion it neither tumbles nor blurs")
	_check(moving.hash == FIRST_LOOK, "First Steps @1's thrown seed looks as it did: " + moving.hash)
	_check(still.hash == FIRST_STILL, "and as it did under Reduce motion: " + still.hash)
	await _every_kind()
	print("THROW LOOK: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

static func _fixture(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/" + path + ".json"))

## First Steps @1's recorded catch turn, two 60 Hz frames a tick, and what the
## seed and its blur show on each frame from its throw to just after its catch.
func _first_steps_frames(reduced: bool) -> Dictionary:
	var world := FirstWorld.new()
	root.add_child(world)
	world.set_process(false)
	world.reduced_motion = reduced
	var definition := Registry.definition(Registry.FIRST_STEPS)
	world.load_level(definition)
	var sim := First.new()
	sim.reset(definition, "a-place-to-grow", _fixture("first_steps/lift-checkpoint"), _fixture("first_steps/a-place-to-grow-a"), "b", 4)
	world.present(sim.snapshot(), true)
	var lines := PackedStringArray()
	var spun := false
	var blurred := false
	var after := 0
	for input: Dictionary in First.expand_recording_inputs(_fixture("first_steps/a-place-to-grow-b")):
		var state: Dictionary = sim.step(input)
		world.present(state)
		var flying := str(state.seed.status) == "flying"
		if not flying and lines.is_empty(): continue
		if not flying: after += 1
		if after > 4: break
		for frame in range(2):
			world._process(1.0 / 60.0)
			var seed: MeshInstance3D = world.seed
			var glow := seed.get_node("SeedGlow") as Node3D
			var trail: Node3D = world._seed_throw.trail
			var mesh: MeshInstance3D = trail._mesh
			var material := mesh.material_override as ShaderMaterial
			spun = spun or not seed.quaternion.is_equal_approx(Quaternion.IDENTITY)
			blurred = blurred or mesh.visible
			var drawn := [seed.position, seed.quaternion, glow.quaternion, mesh.visible]
			if mesh.visible: drawn.append_array([material.get_shader_parameter(&"count"), material.get_shader_parameter(&"width"), material.get_shader_parameter(&"trail_color"), mesh.custom_aabb])
			lines.append(_rounded(drawn))
	world.queue_free()
	return {"hash": "\n".join(lines).sha256_text(), "frames": lines.size(), "spun": spun, "blurred": blurred}

## Values as text at 4 decimals, so float noise never changes the hash.
static func _rounded(values: Array) -> String:
	var out := PackedStringArray()
	for value: Variant in values:
		if value is Vector3: out.append("%.4f,%.4f,%.4f" % [value.x, value.y, value.z])
		elif value is Quaternion: out.append("%.4f,%.4f,%.4f,%.4f" % [value.x, value.y, value.z, value.w])
		elif value is Color: out.append("%.4f,%.4f,%.4f,%.4f" % [value.r, value.g, value.b, value.a])
		elif value is AABB: out.append(_rounded([value.position, value.size]))
		elif value is float: out.append("%.4f" % value)
		else: out.append(str(value))
	return " ".join(out)

## Every item kind a pip can carry, as first-steps@2's seed (pinned to that
## style), thrown from the mark through the real engine: blurred and tumbling
## in flight, at its own size, then upright with no blur once it lands.
func _every_kind() -> void:
	var level: Dictionary = Registry.definition(KEY)
	var evidence: Dictionary = Witness.new().chapter()
	_check(evidence.error.is_empty(), "first-steps@2's witness plays: " + str(evidence.error))
	if not evidence.error.is_empty(): return
	var kinds := 0
	for kind: String in CarriedItemKit.STYLES:
		# A raft is a float nobody carries.
		if kind == "raft": continue
		kinds += 1
		var world: Node3D = Registry.world_script(KEY).new()
		world.descriptor_override = {"piece_styles": {"seed": kind}}
		root.add_child(world)
		world.set_process(false)
		await world.load_level(level)
		await world.show_stage(level.stages[1])
		var piece: RefCounted = world._item_pieces.get("seed")
		_check(piece != null and piece.style == kind and piece.throw_look != null, "The %s can be thrown and has the throw look" % kind)
		if piece == null or piece.throw_look == null:
			world.free()
			continue
		_check(is_equal_approx(piece.throw_look.trail.radius, piece.throw_radius()) and piece.throw_look.trail.get_parent() == world.terrain and world._motion_trails.has(piece.throw_look.trail), "The %s blurs at its own size, with the world's other blurs" % kind)
		var sim: RefCounted = Registry.simulation_script(KEY).new()
		_check(Registry.reset_simulation(sim, KEY, level, STAGE, evidence.checkpoints[1], {}, "a"), "The throw stage starts: " + str(sim.error))
		Walk.walk(sim, [230, -40])
		Walk.tap(sim)
		Walk.walk(sim, [140, -40])
		Walk.walk(sim, MARK)
		world.present(sim.snapshot(), true)
		Walk.tap(sim)
		_check(CarriedItems.in_flight(sim._mechanisms.items.seed), "The %s is thrown" % kind)
		world.present(sim.snapshot())
		var spun := false
		var blurred := false
		var shadowed := false
		var landed := false
		for tick in range(int(level.stages[1].throws[0].flight_ticks) + 4):
			var snap: Dictionary = sim.step({})
			world.present(snap)
			for frame in range(2): world._process(1.0 / 60.0)
			if CarriedItems.in_flight(sim._mechanisms.items.seed):
				spun = spun or not piece.root.quaternion.is_equal_approx(Quaternion.IDENTITY)
				blurred = blurred or piece.throw_look.trail._mesh.visible
				shadowed = shadowed or not bool(piece.root.get_meta(ContactShadows.OFF_META, false))
			elif "item_landed:seed" in snap.events: landed = true
		_check(spun and blurred, "The thrown %s tumbles and blurs in flight (spun %s, blurred %s)" % [kind, spun, blurred])
		_check(not shadowed, "The thrown %s casts no shadow in flight" % kind)
		_check(landed and not bool(piece.root.get_meta(ContactShadows.OFF_META, false)), "Landed, the %s has its shadow again" % kind)
		_check(landed and not piece.throw_look.flying and not piece.throw_look.trail._mesh.visible and piece.root.quaternion.is_equal_approx(Quaternion.IDENTITY), "Landed, the %s stands upright with no blur" % kind)
		world.free()
	_check(kinds >= 3, "Every carried kind is thrown: %d" % kinds)
