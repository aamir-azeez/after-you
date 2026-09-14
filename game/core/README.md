# Puzzle simulation

The core is a node-free Godot `RefCounted` model. It does not read wall-clock time,
render frames, device input, network state or random numbers. Visual code reads
snapshots and is not authoritative for puzzle outcomes.

## Units and ownership

- Positions use integer centimetres: `{x, z}` maps to Godot `Vector3(x / 100.0, height / 100.0, z / 100.0)`.
- `step()` advances exactly one of 30 simulation ticks per second. A turn ends at
  600 ticks or when the seed is planted. Pausing means not calling `step()`.
- Rendering can interpolate between snapshots without changing simulation state.
- A stays on the near island and controls the bridge, throw and optional second
  plate. B crosses, catches and plants. Neither player can physically push the other.
- A prior recording is copied on reset. After its last input, A remains at its
  final position; interaction is released. A sender can therefore save a valid
  short contribution while leaving the pressure plate held for the receiver.

`AfterYouLevels` contains eight version-1 authored definitions. The first three
are free. Later islands add a charged bridge, a second plate that latches the
garden open, a rising garden, and combinations. These fields affect simulation
rules, collision, throws and planting; they are not decorative metadata.

## Application interface

```gdscript
var island = AfterYouLevels.get_level("first-light")
var simulation = AfterYouSimulation.new()
if not simulation.reset(island, {}, "a"):
    show_error(simulation.error)
    return

# At each fixed tick, read the current joystick and button-held state.
var state = simulation.step({
    "move_x": joystick.x,
    "move_z": joystick.y,
    "interact": context_button_held,
})

if simulation.can_commit():
    var turn = simulation.export_recording()
```

Movement axes are floats in `[-1, 1]`, quantized once to integer hundredths. The
context action is edge-triggered: pass the held state, not a repeated synthetic
tap every tick. With assistance enabled, B catches automatically near the landing
window. With assistance disabled, B taps the same context action to catch.

`reset(island, first_turn, "b")` verifies the source turn's format, every stored
checkpoint, its outcome and its readiness before starting B. Check the Boolean
result and display `simulation.error` on failure. Do not continue an unsupported
or conflicting recording by silently substituting an empty one.

A contribution can commit only after a throw, with the bridge usable, garden
unlocked and lift ready. A receiving contribution can commit only after planting.
A draft that fails these criteria can still be saved locally for rehearsal.

## Recordings, replay and resume

`export_recording()` returns JSON-compatible schema version 1 containing:

- Simulation version, island ID/version, role, 30 Hz tick rate and duration.
- Run-length encoded inputs (`ticks`, `x`, `z`, `action`). Run durations sum to the
  recording duration.
- SHA-256 state checkpoints every 30 ticks and at the final tick.
- Final state hash, actual outcome, completion and catch-assistance setting.
- For B, the earlier A turn's final state hash as `source_recording_hash`.

Use `verify_recording(island, turn, first_turn)` before presenting an untrusted
recording as valid. It returns `{valid, error, snapshot}` and replays the actions;
it does not trust a supplied completion Boolean. The backend separately enforces
membership, revisions and submission order. Client replay validation is not a
claim of competitive server-side anti-cheat.

```gdscript
var check = AfterYouSimulation.verify_recording(island, draft, first_turn)
if check.valid:
    simulation.catch_assistance = draft.get("catch_assistance", true)
    simulation.reset(island, first_turn, draft.role)
    for recorded_input in AfterYouSimulation.expand_recording_inputs(draft):
        simulation.step(recorded_input)
    # An unfinished draft can now continue from its precise state.
```

Do not edit committed inputs in place. `fork_recordings(new_first)` retains a copy
of the chosen A turn and clears B and completion. Room revisions must likewise
change at the application/backend layer.

Simulation or level behavior changes require a new version and a compatible
reader for existing saves. Do not rewrite old versions while keeping their number.

## Presentation events

The most recent step may emit `bridge_opened`, `garden_opened`, `lift_ready`,
`seed_thrown`, `seed_landed`, `seed_missed`, `seed_caught`, `island_bloomed` or
`turn_finished`. Consume these once per simulation step for audio/haptics. Repeated
calls to `snapshot()` do not consume events or advance time. Messages are human
readable context hints; game decisions should use the typed state fields.

## Tests

From the repository root, using the pinned Godot executable on the path:

```text
godot --headless --editor --path game --import
godot --headless --path game --script res://tests/test_simulation.gd
```

The initial import registers global script classes. The suite includes complete
solutions for all eight islands, different rendering schedules, JSON round trips,
misses, paused time, immutable source copies, altered actions/outcomes/checkpoints,
unsupported versions, invalidated later turns and both catch modes. Mechanism
tests assert that unfinished lifts, gates and charged plates actually prevent
progress or commitment.

The first and last island's successful A/B recordings are included in
`game/tests/fixtures` for backend contract tests. Regenerate them only after an
intentional compatible update or version change:

```text
godot --headless --path game --script res://tests/test_simulation.gd -- --write-fixtures
```

These checks prove simulation behavior, not touchscreen usability, Android frame
rate, RevenueCat purchase behavior or whether a puzzle is understandable to a new
player. Those require separate native-device and player tests.
