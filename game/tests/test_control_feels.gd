extends SceneTree
## Control haptics (presentation/control_feels.gd): every control kind has a
## feel, and through the shared stepper (presentation/memory_wait.gd) only the
## live pip's own presses buzz, once each: a pad pressed and let go, a lever
## pulled, an item caught in its own hands, a gate its press opened. A
## memory's press, a replay, a seek and a tick whose cue buzzes already never
## add one. Deterministic: stand-in world and soundscape, no frames or sleeps.
const ControlFeels = preload("res://presentation/control_feels.gd")
const MemoryWait = preload("res://presentation/memory_wait.gd")
const Styles = preload("res://content/dressing/prop_styles.gd")

var checks := 0
var failures := 0
var _made: Array[Node] = []

## Counts each buzz the stepper asks for.
class Buzzes extends Node:
	var played: Array = []
	func consume_turn_events(_events: Array, _sources: Array, _live: bool, _hold: PackedInt32Array = PackedInt32Array()) -> void: pass
	func haptic(ms: int, amplitude: float) -> void: played.append([ms, amplitude])

## One pad "step" at the origin, held when the snapshot says; levers styled.
class PadWorld extends Node:
	var held := false
	func present(state: Dictionary, _immediate: bool = false) -> void: held = bool(state.get("hold_pads", {}).get("step", false))
	func pad_spots() -> Array: return [{"id": "step", "at": Vector3.ZERO, "radius": 0.3, "held": held}]
	func piece_style(slot: String, _id: String) -> String: return "winch" if slot == "lever" else "plain"

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _run() -> void:
	_check_kinds()
	_check_stepper()
	for node: Node in _made: node.free()
	print("CONTROL FEELS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## Every kind the feels can name has a feel, a style's kind falls back to its
## slot's, and an unknown kind to the default.
func _check_kinds() -> void:
	var kinds: Array = ControlFeels.ACTIONS + ["pad", "pad_release", "gate"]
	for slot: String in ["lever", "selector"]:
		for style: String in Styles.SLOTS[slot]: kinds.append("%s:%s" % [slot, style])
	for kind: String in kinds: _check(ControlFeels.FEELS.has(ControlFeels.feel(kind)), "Control kind %s has a feel" % kind)
	for kind: String in ControlFeels.KINDS: _check(ControlFeels.FEELS.has(ControlFeels.KINDS[kind]), "Kind %s names a feel" % kind)
	_check(ControlFeels.feel("lever:teapot") == ControlFeels.feel("lever") and ControlFeels.feel("teapot") == ControlFeels.DEFAULT_FEEL, "A new style feels like its slot, a new kind like the default")
	_check(ControlFeels.feel("lever:winch") == "step" and ControlFeels.feel("selector:valve") == "step", "A crank and a wheel tick a step")
	for name: String in ControlFeels.FEELS:
		var feel: Dictionary = ControlFeels.FEELS[name]
		_check(int(feel.ms) <= 30 and float(feel.amplitude) <= 0.5, "Feel %s stays short and light" % name)

func _state(tick: int, live: Dictionary, memory: Dictionary, held: bool, extra: Dictionary = {}) -> Dictionary:
	var state := {"tick": tick, "role": "b", "active_slot": "p1", "players": {"p0": memory.merged({"ghost": true}), "p1": live}, "hold_pads": {"step": held}, "levers": {}, "events": []}
	state.merge(extra, true)
	return state

func _stepper() -> Array:
	var wait := MemoryWait.new()
	var world := PadWorld.new()
	var buzzes := Buzzes.new()
	_made.append_array([world, buzzes])
	wait.world = world
	wait.soundscape = buzzes
	wait.begin("b", 0)
	return [wait, world, buzzes]

func _check_stepper() -> void:
	var on := {"x": 0, "z": 0, "height": 0}
	var off := {"x": 300, "z": 0, "height": 0}
	# The live pip presses the pad, stands on it, and steps off.
	var run := _stepper()
	var wait: MemoryWait = run[0]
	var buzzes: Buzzes = run[2]
	wait.step(_state(0, off, off, false), {}, true, true)
	wait.step(_state(1, on, off, true), {}, true)
	for tick in range(2, 6): wait.step(_state(tick, on, off, true), {}, true)
	_check(buzzes.played.size() == 1 and buzzes.played[0][0] == ControlFeels.FEELS.press.ms, "A live press buzzes exactly once: %s" % [buzzes.played])
	wait.step(_state(6, off, off, false), {}, true)
	_check(buzzes.played.size() == 2 and buzzes.played[1][0] == ControlFeels.FEELS.release.ms, "Stepping off buzzes once, lighter: %s" % [buzzes.played])
	# The memory presses the pad and pulls a lever (its pulls carry no event).
	run = _stepper()
	wait = run[0]
	buzzes = run[2]
	wait.step(_state(0, off, off, false), {}, true, true)
	wait.step(_state(1, off, on, true), {}, true)
	wait.step(_state(2, off, on, true, {"levers": {"gate": true}}), {}, true)
	wait.step(_state(3, off, off, false, {"levers": {"gate": true}}), {}, true)
	_check(buzzes.played.is_empty(), "A memory's press never buzzes: %s" % [buzzes.played])
	# A replay or a seek of the live pip's press never buzzes.
	run = _stepper()
	wait = run[0]
	buzzes = run[2]
	wait.step(_state(0, off, off, false), {}, false)
	wait.step(_state(1, on, off, true, {"events": ["lever"], "levers": {"gate": true}}), {}, false)
	wait.step(_state(2, off, off, false), {}, true, true)
	_check(buzzes.played.is_empty(), "A replay and a seek never buzz: %s" % [buzzes.played])
	# The live pip's lever (a winch: a crank's step), its catch, and the gate a
	# press opens: one buzz a tick, the strongest.
	run = _stepper()
	wait = run[0]
	buzzes = run[2]
	wait.step(_state(0, off, off, false), {}, true, true)
	wait.step(_state(1, off, off, false, {"events": ["lever"], "levers": {"gate": true}}), {}, true)
	_check(buzzes.played.size() == 1 and buzzes.played[0][0] == ControlFeels.FEELS.step.ms, "A live winch pull ticks a step: %s" % [buzzes.played])
	wait.step(_state(2, off, off, false, {"events": ["lever", "bridge_opened:gate"], "levers": {"gate": false}}), {}, true)
	_check(buzzes.played.size() == 2 and buzzes.played[1][0] == ControlFeels.FEELS.thud.ms, "A gate the live pip's press opens thuds, once: %s" % [buzzes.played])
	wait.step(_state(3, off.merged({"carrying": ""}), off, false, {"events": ["item_caught:parcel"]}), {}, true)
	_check(buzzes.played.size() == 2, "An item the memory caught never buzzes")
	wait.step(_state(4, off.merged({"carrying": "parcel"}), off, false, {"events": ["item_caught:parcel"]}), {}, true)
	_check(buzzes.played.size() == 3, "An item the live pip caught buzzes")
	wait.step(_state(5, off, off, false, {"events": ["bridge_opened:gate"]}), {}, true)
	_check(buzzes.played.size() == 3, "A gate that opens by itself never buzzes")
	wait.step(_state(6, on, off, true), {"cues": ["seed_caught"]}, true)
	_check(buzzes.played.size() == 3, "A tick whose cue buzzes already adds none")
