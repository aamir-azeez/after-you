extends SceneTree
## turn-of-the-tide@1 worst-case sizes (spec 11.8). In both stages the
## recorder's input changes on every tick up to the 900-tick cap and the
## receiver's up to about 1200, so every tick is its own action entry. The
## turns are the real LOW / boom routes, replayed with a one-step wobble on
## the idle axis that never moves anyone, then derived through the full proof.
## Limits, measured as the backend does (JSON bytes and value count):
##   checkpoint: MAX_CHECKPOINT_BYTES 229,376 and 24,000 values (protocol-relay.ts boundedValue);
##   comfort recording: 65,536 bytes (protocol-physical-recording.ts);
##   receiver turn body: MAX_V2_BODY_BYTES 327,680 and 32,000 values (boundedTurnValue).
const Simulation = preload("res://core/journey/simulation.gd")
const Catalog = preload("res://core/journey/stage_catalog.gd")
const Witness = preload("res://tests/turn_of_the_tide_witness.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const RING_TICK := 1190
var checks := 0
var failures := 0
var level: Dictionary = {}
var initial: Dictionary = {}

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	level = Catalog.definition(Witness.KEY)
	initial = Catalog.initial_checkpoint(level)
	var first := _stage(Witness.SET, initial, Witness.a_routes()["low"], Witness.b_routes()["low"])
	if not first.is_empty():
		var second := _stage(Witness.SLACK, first.checkpoint, Witness.p1_home("low") + Witness.p1_way("low", "boom"), Witness.p0_way("low", "boom"))
		if not second.is_empty():
			var checkpoint: Dictionary = second.checkpoint
			var size := _bytes(checkpoint)
			var values := _values(checkpoint)
			_check(size <= 229376 and values <= 24000, "The worst stage-2 checkpoint fits: %d bytes of 229,376, %d values of 24,000" % [size, values])
			# The largest body a receiver can send: the completion proof's four
			# records plus its own record again.
			var body := {"checkpoint": checkpoint, "recording": second.b}
			var turn_size := _bytes(body)
			var turn_values := _values(body)
			_check(turn_size <= 327680 and turn_values <= 32000, "A worst receiver turn body (four records plus the receiver's again) fits: %d bytes of 327,680, %d values of 32,000" % [turn_size, turn_values])
			print("TIDE bytes checkpoint=%d values=%d turn=%d values=%d" % [size, values, turn_size, turn_values])
	print("TURN OF THE TIDE BYTES: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## One stage at full length: A wobbles to the 900 cap, B rings at tick 1190.
func _stage(stage_id: String, checkpoint: Dictionary, a_ops: Array, b_ops: Array) -> Dictionary:
	var clean_a := Witness.source(level, stage_id, checkpoint, a_ops, 0, Callable(), true)
	var frames := _wobble(Simulation.expand_recording_inputs(clean_a.export_recording()))
	while frames.size() < Simulation.MAX_TICKS: frames.append(_idle(frames.size()))
	var a := _play(stage_id, checkpoint, {}, frames)
	_check(a.can_commit() and a.tick == Simulation.MAX_TICKS, "%s: A at the 900-tick cap still commits (%s)" % [stage_id, a.commit_reason()])
	if not a.can_commit(): return {}
	var first: Dictionary = a.export_recording()
	var clean_b := Witness.receiver(level, stage_id, checkpoint, first, b_ops, Callable(), true)
	var ring := int(clean_b.get_meta("ring_tick", -1)) - 1
	_check(clean_b.complete and ring > 0 and ring < RING_TICK, stage_id + ": the clean receiver rings")
	if ring <= 0: return {}
	var inputs := Simulation.expand_recording_inputs(clean_b.export_recording())
	var b_frames := _wobble(inputs.slice(0, ring))
	while b_frames.size() < RING_TICK - 1: b_frames.append(_idle(b_frames.size()))
	b_frames.append(inputs[ring])
	var b := _play(stage_id, checkpoint, first, b_frames)
	_check(b.complete and b.tick == RING_TICK, "%s: B rings at tick %d and completes" % [stage_id, RING_TICK])
	if not b.complete: return {}
	var second: Dictionary = b.export_recording()
	for record: Dictionary in [first, second]:
		_check(record.actions.size() >= int(record.duration_ticks) - 30, "%s %s: nearly one action entry per tick (%d of %d)" % [stage_id, record.role, record.actions.size(), record.duration_ticks])
		_check(_bytes(record) <= 65536 and _values(record) <= 24000, "%s %s recording fits: %d bytes of 65,536, %d values" % [stage_id, record.role, _bytes(record), _values(record)])
		print("TIDE bytes %s %s ticks=%d actions=%d bytes=%d values=%d" % [stage_id, record.role, record.duration_ticks, record.actions.size(), _bytes(record), _values(record)])
	var derived := Simulation.derive_checkpoint(level, Witness.json(checkpoint), Witness.json(first), Witness.json(second))
	_check(derived.valid, "%s: the full-length pair derives (%s)" % [stage_id, derived.get("error", "")])
	if not derived.valid: return {}
	return {"a": first, "b": second, "checkpoint": derived.checkpoint}

func _play(stage_id: String, checkpoint: Dictionary, first: Dictionary, frames: Array) -> RefCounted:
	var sim := Simulation.new()
	sim.simulation_version = Witness.RULES
	sim._reset_trusted(level, stage_id, checkpoint, first, "a" if first.is_empty() else "b")
	for frame: Dictionary in frames:
		if sim.finished: break
		sim.step(frame)
	return sim

## Every other tick, nudge the axis the walker is not using by one step (0.01):
## the quantized input differs but the move rounds to the same centimetres.
func _wobble(frames: Array) -> Array:
	var result: Array = []
	for index in range(frames.size()):
		var frame: Dictionary = frames[index].duplicate()
		if index % 2 == 1:
			if is_zero_approx(float(frame.move_z)): frame.move_z = 0.01
			elif is_zero_approx(float(frame.move_x)): frame.move_x = 0.01
		result.append(frame)
	return result

func _idle(index: int) -> Dictionary:
	return {"move_x": 0.0, "move_z": 0.01 if index % 2 == 1 else 0.0, "interact": false}

func _bytes(value: Dictionary) -> int:
	return JSON.stringify(Canonical.normalized(value)).to_utf8_buffer().size()

## Values as the backend counts them: every object, array and leaf.
func _values(value: Variant) -> int:
	var count := 1
	if value is Dictionary:
		for key: Variant in value: count += _values(value[key])
	elif value is Array:
		for item: Variant in value: count += _values(item)
	return count

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
