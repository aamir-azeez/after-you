extends SceneTree

const Beam = preload("res://core/beam_field.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_test_direct_and_bounds()
	_test_all_reflections()
	_test_active_optics()
	_test_loop()
	_test_multiple_sources_and_order()
	_test_malformed_fields()
	_test_size_limits()
	_check(checks >= 65, "All independent beam test groups reached their assertions")
	print("AFTER YOU BEAM FIELD: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _test_direct_and_bounds() -> void:
	var field := _field()
	field.emitters = [_emitter("lamp", [-300, 0], "east")]
	field.receivers = [_receiver("target", [100, 0])]
	var result := Beam.evaluate(field)
	_check(result.valid and result.signals.target and result.sources.target == ["lamp"], "A straight beam reports the receiver and its exact source")
	_check(result.segments == [{"emitter_id": "lamp", "from_cm": [-300, 0], "to_cm": [100, 0], "direction": "east", "hit_id": "target", "hit_kind": "receiver"}], "Straight output contains the actual endpoint without extending through an absorbing receiver")
	field.receivers = []
	var expected := {"north": [0, -500], "east": [500, 0], "south": [0, 500], "west": [-500, 0]}
	for direction: String in expected:
		field.emitters = [_emitter("lamp", [0, 0], direction)]
		result = Beam.evaluate(field)
		_check(result.valid and result.segments.size() == 1 and result.segments[0].to_cm == expected[direction] and result.terminations[0].reason == "bounds", "Unobstructed %s ray stops at its correct field boundary" % direction)
	field = _field()
	field.receivers = [_receiver("unpowered", [0, 0])]
	result = Beam.evaluate(field)
	_check(result.valid and not result.signals.unpowered and result.segments.is_empty() and result.terminations.is_empty(), "An empty light source set produces explicit unpowered receiver state")

func _test_all_reflections() -> void:
	# Independent geometric examples, not generated from the evaluator's map.
	var examples := [
		["north", [0, 100], "slash", [200, 0]],
		["north", [0, 100], "backslash", [-200, 0]],
		["east", [-100, 0], "slash", [0, -200]],
		["east", [-100, 0], "backslash", [0, 200]],
		["south", [0, -100], "slash", [-200, 0]],
		["south", [0, -100], "backslash", [200, 0]],
		["west", [100, 0], "slash", [0, 200]],
		["west", [100, 0], "backslash", [0, -200]]]
	for example: Array in examples:
		var field := _field()
		field.emitters = [_emitter("source", example[1], example[0])]
		field.mirrors = [_mirror("bend", [0, 0], example[2])]
		field.receivers = [_receiver("goal", example[3])]
		var result := Beam.evaluate(field)
		_check(result.valid and result.signals.goal, "%s ray reflects off %s into the expected receiver" % [example[0], example[2]])
		_check(result.segments.size() == 2 and result.segments[0].to_cm == [0, 0] and result.segments[1].from_cm == [0, 0] and result.segments[1].to_cm == example[3], "Reflection has two continuous cardinal segments with no optical teleport")
		_check(result.terminations[0].entity_id == "goal", "Reflected path terminates at its actual receiver")

func _test_active_optics() -> void:
	var field := _field()
	field.emitters = [_emitter("lamp", [-400, 0], "east")]
	field.receivers = [_receiver("near", [-100, 0]), _receiver("far", [200, 0])]
	var result := Beam.evaluate(field)
	_check(result.signals.near and not result.signals.far, "Only the nearest enabled collinear receiver absorbs the ray")
	result = Beam.evaluate(field, {"near": {"enabled": false}})
	_check(not result.signals.near and result.signals.far, "Disabled receiver is optically absent and leaves no stale signal")
	field.blockers = [_blocker("shutter", [-200, 0])]
	result = Beam.evaluate(field)
	_check(not result.signals.near and result.terminations[0].reason == "blocker" and result.segments[0].to_cm == [-200, 0], "Enabled authored shutter blocks the receiver at the correct point")
	result = Beam.evaluate(field, {"shutter": {"enabled": false}})
	_check(result.signals.near, "Opening the shutter restores the beam")
	result = Beam.evaluate(field, {"lamp": {"enabled": false}})
	_check(result.segments.is_empty() and not result.signals.near and result.terminations[0].reason == "disabled", "Inactive emitter produces no ray or stale receiver signal")
	field = _field()
	field.emitters = [_emitter("lamp", [-200, 0], "east")]
	field.mirrors = [_mirror("mirror", [0, 0], "slash")]
	field.receivers = [_receiver("north", [0, -200]), _receiver("south", [0, 200]), _receiver("straight", [200, 0])]
	var original := JSON.stringify(field)
	var overrides := {"mirror": {"orientation": "backslash"}}
	var original_overrides := JSON.stringify(overrides)
	result = Beam.evaluate(field, overrides)
	_check(result.signals.south and not result.signals.north, "Mirror override redirects the beam using the new active orientation")
	result = Beam.evaluate(field, {"mirror": {"enabled": false}})
	_check(result.signals.straight and not result.signals.north and not result.signals.south, "Disabled mirror permits straight travel rather than reflecting or blocking")
	result = Beam.evaluate(field)
	_check(result.signals.north and not result.signals.south, "A new evaluation resets signals and uses the unchanged definition")
	_check(JSON.stringify(field) == original and JSON.stringify(overrides) == original_overrides, "Evaluation never mutates definitions or active overrides")

func _test_loop() -> void:
	var field := _field()
	field.emitters = [_emitter("loop-source", [0, -200], "east")]
	field.mirrors = [_mirror("ne", [200, -200], "backslash"), _mirror("se", [200, 200], "slash"), _mirror("sw", [-200, 200], "backslash"), _mirror("nw", [-200, -200], "slash")]
	field.receivers = [_receiver("outside-path", [0, 0])]
	var result := Beam.evaluate(field)
	_check(result.valid and result.terminations[0].reason == "loop", "A closed four-mirror circuit is detected without hanging")
	_check(result.segments.size() == 5 and result.terminations[0].entity_id == "ne" and result.terminations[0].at_cm == [200, -200], "Loop closes at the repeated mirror and incoming direction, after a finite exact route")
	_check(not result.signals["outside-path"], "Loop detection does not invent receiver activation")
	var repeat := Beam.evaluate(field)
	_check(JSON.stringify(result) == JSON.stringify(repeat), "Loop output is deterministic on repeated evaluations")
	var multi := field.duplicate(true)
	multi.emitters = [
		_emitter("e0", [-100, -200], "east"), _emitter("e1", [100, -200], "east"),
		_emitter("e2", [200, -100], "south"), _emitter("e3", [200, 100], "south"),
		_emitter("e4", [100, 200], "west"), _emitter("e5", [-100, 200], "west"),
		_emitter("e6", [-200, 100], "north"), _emitter("e7", [-200, -100], "north")]
	var concurrent := Beam.evaluate(multi)
	_check(concurrent.valid and concurrent.segments.size() == 40 and concurrent.terminations.size() == 8, "Eight supported sources trace the same circuit independently with bounded output")
	var all_closed := true
	for termination: Dictionary in concurrent.terminations:
		all_closed = all_closed and termination.reason == "loop"
	_check(all_closed and not concurrent.signals["outside-path"], "Visited states belong to each source rather than suppressing subsequent beams")
	result = Beam.evaluate(field, {"se": {"orientation": "backslash"}})
	_check(result.terminations[0].reason == "bounds" and result.segments.size() == 3, "An active mirror change opens the circuit rather than retaining cached loop state")
	result = Beam.evaluate(field, {"ne": {"enabled": false}})
	_check(result.terminations[0].reason == "bounds" and result.segments.size() == 1, "Disabling a loop mirror produces a simple escaping ray")

func _test_multiple_sources_and_order() -> void:
	var field := _field()
	field.emitters = [_emitter("z-lamp", [0, 300], "north"), _emitter("a-lamp", [-300, 0], "east")]
	field.receivers = [_receiver("shared", [0, 0])]
	var result := Beam.evaluate(field)
	_check(result.signals.shared and result.sources.shared == ["a-lamp", "z-lamp"], "Independent sources combine at one receiver in stable source-ID order")
	field.emitters = [_emitter("z-lamp", [0, 0], "north"), _emitter("a-lamp", [-300, 0], "east")]
	field.receivers = [_receiver("north", [0, -200]), _receiver("east", [200, 0])]
	result = Beam.evaluate(field)
	_check(result.signals.east and result.signals.north, "Rays pass through another emitter origin without source or beam-beam collisions")
	_check(result.segments[0].from_cm == [-300, 0] and result.segments[0].to_cm == [200, 0], "The east beam remains continuous through the nonblocking source intersection")
	var before := JSON.stringify(result)
	field.emitters.reverse()
	field.receivers.reverse()
	_check(JSON.stringify(Beam.evaluate(field)) == before, "Definition array ordering cannot change segments, signals or terminations")
	var json_copy: Dictionary = JSON.parse_string(JSON.stringify(field))
	_check(JSON.stringify(Beam.evaluate(json_copy)) == before, "JSON float parsing of integer coordinates leaves exact optical output unchanged")
	field = _field()
	field.emitters = [_emitter("lamp", [-300, 0], "east")]
	field.receivers = [_receiver("behind", [-400, 0]), _receiver("off-axis", [-100, 1]), _receiver("ahead", [100, 0])]
	result = Beam.evaluate(field)
	_check(result.signals.ahead and not result.signals.behind and not result.signals["off-axis"], "Entities behind a ray or one centimetre off its axis cannot intercept it")

func _test_malformed_fields() -> void:
	_assert_invalid(null, {}, "Null field")
	_assert_invalid({}, {}, "Missing typed collections")
	var field := _field()
	field.characters = []
	_assert_invalid(field, {}, "Character state is not an optical input")
	field = _field()
	field.schema_version = 2
	_assert_invalid(field, {}, "Unknown optical schema")
	for bounds: Variant in [[], [0, 0, 0, 100], [100, 0, -100, 100], [0, 0, 100, 0], [-1.5, -100, 100, 100], [NAN, -100, 100, 100], [-1000001, -100, 100, 100], "bounds"]:
		field = _field()
		field.bounds_cm = bounds
		_assert_invalid(field, {}, "Malformed or excessive bounds")
	field = _field()
	field.emitters = [_emitter("lamp", [0, 0], "northeast")]
	_assert_invalid(field, {}, "Non-cardinal direction")
	field = _field()
	field.mirrors = [_mirror("mirror", [0, 0], "horizontal")]
	_assert_invalid(field, {}, "Unsupported mirror orientation")
	field = _field()
	field.emitters = [_emitter("duplicate", [0, 0], "east")]
	field.receivers = [_receiver("duplicate", [100, 0])]
	_assert_invalid(field, {}, "Duplicate ID across entity kinds")
	field.receivers = [_receiver("receiver", [0, 0])]
	_assert_invalid(field, {}, "Overlapping source and receiver")
	field.receivers[0].enabled = false
	_assert_invalid(field, {}, "Disabled overlap remains ambiguous when later enabled")
	for position: Variant in [[0], [0, 0, 0], [0.5, 10], [INF, 0], [500, 0], [501, 0], "point"]:
		field = _field()
		field.receivers = [_receiver("receiver", [0, 0])]
		field.receivers[0].position_cm = position
		_assert_invalid(field, {}, "Malformed or non-interior optical position")
	field = _field()
	field.emitters = [_emitter("lamp", [0, 0], "east")]
	for malformed_id: Variant in ["", "bad:id", "a".repeat(65), 10]:
		field.emitters[0].id = malformed_id
		_assert_invalid(field, {}, "Malformed optical identifier")
	field.emitters[0].id = "lamp"
	field.emitters[0].enabled = 1
	_assert_invalid(field, {}, "Enabled state is strictly boolean")
	field.emitters[0].enabled = true
	field.emitters[0].script = "not-an-optical-operation"
	_assert_invalid(field, {}, "Unknown entity behavior")
	field = _field()
	field.mirrors = [_mirror("mirror", [0, 0], "slash")]
	field.receivers = [_receiver("receiver", [100, 0])]
	for override: Variant in [[], {"unknown": {"enabled": true}}, {"mirror": true}, {"mirror": {"position_cm": [20, 0]}}, {"mirror": {"enabled": 1}}, {"mirror": {"orientation": "diagonal"}}, {"receiver": {"orientation": "slash"}}]:
		_assert_invalid(field, override, "Unknown, untyped or incompatible active override")
	field.mirrors = "mirror"
	_assert_invalid(field, {}, "Collection must be an array")

func _test_size_limits() -> void:
	var field := _field()
	for index in range(9):
		field.emitters.append(_emitter("e%d" % index, [-400 + 20 * index, 0], "east"))
	_assert_invalid(field, {}, "Emitter count bound")
	field = _field()
	for index in range(33):
		field.mirrors.append(_mirror("m%d" % index, [-400 + 20 * index, 0], "slash"))
	_assert_invalid(field, {}, "Mirror count bound")
	field = _field()
	for index in range(65):
		field.receivers.append(_receiver("r%d" % index, [-400 + 10 * index, 0]))
	_assert_invalid(field, {}, "Overall entity count bound")
	field = _field()
	for index in range(32):
		field.receivers.append(_receiver("r%d" % index, [-400 + 20 * index, 0]))
		field.blockers.append(_blocker("b%d" % index, [-400 + 20 * index, 100]))
	_check(Beam.evaluate(field).valid, "A valid field at the total entity limit still evaluates")
	field.emitters.append(_emitter("extra", [0, -100], "north"))
	_assert_invalid(field, {}, "Total count includes all typed collections")

func _field() -> Dictionary:
	return {"schema_version": 1, "bounds_cm": [-500, -500, 500, 500], "emitters": [], "mirrors": [], "receivers": [], "blockers": []}

func _emitter(id: String, position: Array, direction: String) -> Dictionary:
	return {"id": id, "position_cm": position, "direction": direction, "enabled": true}

func _mirror(id: String, position: Array, orientation: String) -> Dictionary:
	return {"id": id, "position_cm": position, "orientation": orientation, "enabled": true}

func _receiver(id: String, position: Array) -> Dictionary:
	return {"id": id, "position_cm": position, "enabled": true}

func _blocker(id: String, position: Array) -> Dictionary:
	return {"id": id, "position_cm": position, "enabled": true}

func _assert_invalid(field: Variant, overrides: Variant, description: String) -> void:
	var result := Beam.evaluate(field, overrides)
	_check(not result.valid and not result.error.is_empty() and result.segments.is_empty() and result.signals.is_empty() and result.sources.is_empty() and result.terminations.is_empty(), description + " fails closed without partial rays or signals")

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)
