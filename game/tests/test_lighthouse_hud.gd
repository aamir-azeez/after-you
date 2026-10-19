extends SceneTree
## The Lighthouse HUD (presentation/lighthouse_hud.gd) is shared by the solo
## @1 screen and the shared chapter screen playing @2. Its outputs over every
## fixture stage, both roles and both engine rules (3 for the frozen solo
## chain, 5 for the room facade) were captured from the solo screen before the
## helper was extracted (fixtures/lighthouse/hud-v1.json). Set
## AFTER_YOU_WRITE_HUD=<absolute file> to capture again.
const LighthousePreview = preload("res://lighthouse_preview.gd")
const Native = preload("res://core/lighthouse/borrowed_light.gd")
const LightCatalog = preload("res://core/lighthouse/stage_catalog.gd")
const RoomSimulation = preload("res://core/lighthouse/room_simulation.gd")
const Golden = preload("res://tests/golden_support.gd")
const LighthouseHud = preload("res://presentation/lighthouse_hud.gd")
const RelayPreview = preload("res://relay_preview.gd")
const Registry = preload("res://services/chapter_registry.gd")
const FIXTURE := "res://tests/fixtures/lighthouse/hud-v1.json"
## Every this many ticks, plus each turn's last tick.
const SAMPLE_TICKS := 10
var checks := 0
var failures := 0

class Capture extends CanvasLayer:
	var calls: Array = []
	func update_state(title: String, remaining: float, state: Dictionary, interactive: bool) -> void:
		calls.append({"title": title, "remaining": remaining, "state": state.duplicate(true), "interactive": interactive})
	func show_tries(_tries: int) -> void: pass

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var cases := _cases()
	_check(cases.size() > 200, "Enough HUD states are sampled: %d" % cases.size())
	var solo := _solo_outputs(cases)
	var target := OS.get_environment("AFTER_YOU_WRITE_HUD")
	if not target.is_empty():
		var file := FileAccess.open(target, FileAccess.WRITE)
		file.store_string(JSON.stringify(solo, "\t", false) + "\n")
		file.close()
		print("LIGHTHOUSE HUD: wrote %d states to %s" % [solo.size(), target])
	else:
		var frozen: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
		# Both sides through JSON, so integers and floats compare alike.
		solo = JSON.parse_string(JSON.stringify(solo))
		_check(frozen is Array and frozen.size() == solo.size(), "The frozen capture covers the same states")
		var same: bool = frozen is Array and frozen.size() == solo.size()
		for index in range(solo.size() if same else 0):
			if JSON.stringify(frozen[index]) != JSON.stringify(solo[index]):
				same = false
				push_error("First HUD difference at state %d: %s" % [index, JSON.stringify(solo[index])])
				break
		_check(same, "The solo Lighthouse HUD is unchanged at every sampled state")
		_shared_screen(cases, solo)
		var pure := true
		for item: Dictionary in cases:
			var before := JSON.stringify(item.state)
			LighthouseHud.display(item.state, LightCatalog.definition(str(item.stage_id)))
			pure = pure and JSON.stringify(item.state) == before
		_check(pure, "The HUD helper never changes the snapshot it reads")
	print("LIGHTHOUSE HUD: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## {stage_index, stage_id, role, rules, state} at sampled ticks of every
## fixture turn, from the frozen rules-3 solo chain and the rules-5 room chain.
func _cases() -> Array:
	var result: Array = []
	var frozen: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/lighthouse/complete-six-v3.json"))
	for index in range(frozen.pairs.size()):
		var pair: Dictionary = frozen.pairs[index]
		var prefix: Array = frozen.pairs.slice(0, index)
		for role: String in ["a", "b"]:
			var sim := Native.new()
			sim.reset(role, pair.a if role == "b" else {}, prefix, int(pair[role].simulation_version))
			_sample(result, sim, Native.expand_recording_inputs(pair[role]), index, role, int(pair[role].simulation_version))
	var chain: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/lighthouse/v2-chain.json"))
	for index in range(chain.pairs.size()):
		var pair: Dictionary = chain.pairs[index]
		for role: String in ["a", "b"]:
			var sim := RoomSimulation.new()
			sim.reset(chain.definition, str(pair[role].stage_id), chain.checkpoints[index], pair.a if role == "b" else {}, role)
			_sample(result, sim, RoomSimulation.expand_recording_inputs(pair[role]), index, role, RoomSimulation.PHYSICS)
	return result

func _sample(result: Array, sim: RefCounted, inputs: Array, index: int, role: String, rules: int) -> void:
	var stage_id: String = LightCatalog.STAGE_IDS[index]
	result.append({"stage_index": index, "stage_id": stage_id, "role": role, "rules": rules, "state": sim.snapshot()})
	for tick in range(inputs.size()):
		var state: Dictionary = sim.step(inputs[tick])
		if (tick + 1) % SAMPLE_TICKS == 0 or tick + 1 == inputs.size(): result.append({"stage_index": index, "stage_id": stage_id, "role": role, "rules": rules, "state": state})

## The solo screen's HUD for each case: the title, time left and the
## fields the shared controls read.
func _solo_outputs(cases: Array) -> Array:
	var preview: Node3D = LighthousePreview.new()
	var capture := Capture.new()
	preview.controls = capture
	var outputs: Array = []
	for item: Dictionary in cases:
		preview.stage = LightCatalog.definition(str(item.stage_id))
		preview.checkpoint = {"stage_index": item.stage_index}
		for mode: String in ["play", "replay"]:
			preview.mode = mode
			preview._update_hud(item.state)
			outputs.append(_shown(capture.calls.pop_back()))
	preview.free()
	capture.free()
	return outputs

## The shared chapter screen playing sleeping-lighthouse@2 shows the same HUD
## for the same snapshot; only its title follows the shared "n / 6" format.
func _shared_screen(cases: Array, solo: Array) -> void:
	var preview: Node3D = RelayPreview.new()
	var capture := Capture.new()
	preview.chapter_key = Registry.LIGHTHOUSE_V2
	preview.chapter = Registry.descriptor(Registry.LIGHTHOUSE_V2)
	preview.definition = Registry.definition(Registry.LIGHTHOUSE_V2)
	preview.controls = capture
	var same := true
	var titles := true
	var index := 0
	for item: Dictionary in cases:
		preview.checkpoint = {"stage_index": item.stage_index}
		preview.role = item.role
		for mode: String in ["play", "replay"]:
			preview.mode = mode
			preview._update_hud(item.state)
			var shown: Dictionary = JSON.parse_string(JSON.stringify(_shown(capture.calls.pop_back())))
			var expected: Dictionary = solo[index].duplicate()
			index += 1
			var turn := "Replay" if mode == "replay" else "Your first turn" if item.role == "a" else "Alongside a ghost"
			titles = titles and shown.title == "%s · %d / 6 · %s" % [LightCatalog.definition(str(item.stage_id)).title, int(item.stage_index) + 1, turn]
			shown.erase("title")
			expected.erase("title")
			if same and JSON.stringify(shown) != JSON.stringify(expected):
				same = false
				push_error("First shared-screen HUD difference: %s vs %s" % [JSON.stringify(shown), JSON.stringify(expected)])
	_check(same, "The shared screen shows the solo Lighthouse HUD at every sampled state")
	_check(titles, "Its title names the stage, its place out of six and the turn")
	preview.free()
	capture.free()

static func _shown(call: Dictionary) -> Dictionary:
	var state: Dictionary = call.state
	var shown := {"title": call.title, "remaining": call.remaining, "interactive": call.interactive}
	for key: String in ["message", "progress_message", "objective_display", "context_action", "can_commit", "duration_ticks"]:
		if state.has(key): shown[key] = state[key]
	return Golden.stable(shown)

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
