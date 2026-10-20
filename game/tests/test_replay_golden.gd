extends SceneTree
## Golden G2: every pinned chapter's committed fixture recordings, re-simulated
## through the engine the registry names. Pins recording, state and checkpoint
## hashes, outcomes, the final snapshot digest and the per-tick event log, and
## checks each recording re-exports byte-for-byte in canonical form. Lighthouse
## (outside the registry) runs its six-stage chain through its own engine.
## The chapters are split over three suites (SUITES) to stay well inside CI's
## 120 s limit; each suite has its own golden, tests/fixtures/golden/<suite>.json.
## See tests/golden_support.gd to regenerate after an intended change.
const Golden = preload("res://tests/golden_support.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Light = preload("res://core/lighthouse/borrowed_light.gd")
## The tick of any engine, the Lighthouse room facade's included.
const LiveTick = preload("res://services/relay_journey.gd")
const LIGHTHOUSE := "sleeping-lighthouse@1"
## Every pinned chapter runs in exactly one suite; a newly pinned chapter must
## be added to one of them (this suite checks the split).
const SUITES := {
	"replay_golden": ["first-steps@1", "relay-isles@2", LIGHTHOUSE, "sleeping-lighthouse@2", "turn-of-the-tide@2"],
	"replay_golden_physical": ["high-and-low@1", "rolling-home@1", "a-house-for-two@1", "the-wishing-well@1"],
	"replay_golden_journey": ["conservatory@1", "long-way-home@1", "long-way-home@2", "turn-of-the-tide@1"],
}
## Per chapter, named fixture chains. "stages" lists [a, b, checkpoint after
## the pair]; "bundle" names a comfort8 file (and its entry) of pairs and
## checkpoints; "final" is the published final checkpoint for that chain.
const CHAINS := {
	"first-steps@1": {
		"rules4": {"initial": "first_steps/initial-checkpoint.json", "final": "first_steps/final-checkpoint.json", "stages": [
			["first_steps/a-little-lift-a.json", "first_steps/a-little-lift-b.json", "first_steps/lift-checkpoint.json"],
			["first_steps/a-place-to-grow-a.json", "first_steps/a-place-to-grow-b.json", "first_steps/final-checkpoint.json"]]},
		"rules5": {"initial": "first_steps/initial-checkpoint.json", "final": "first_steps/cumulative-garden-checkpoint.json", "stages": [
			["first_steps/cumulative-lift-a.json", "first_steps/cumulative-lift-b.json", "first_steps/cumulative-lift-checkpoint.json"],
			["first_steps/cumulative-garden-a.json", "first_steps/cumulative-garden-b.json", "first_steps/cumulative-garden-checkpoint.json"]]},
		"rules8": {"bundle": "comfort8/first-steps.json", "entry": ""},
	},
	"relay-isles@2": {
		"rules2": {"initial": "v2/initial-checkpoint.json", "final": "v2/final-checkpoint.json", "stages": [
			["v2/relay-a.json", "v2/relay-b.json", "v2/relay-checkpoint.json"],
			["v2/garden-a.json", "v2/garden-b.json", "v2/final-checkpoint.json"]]},
		"rules8": {"bundle": "comfort8/recordings.json", "entry": "relay"},
	},
	"high-and-low@1": {
		"rules6": {"initial": "cooperative/high-and-low-initial-checkpoint.json", "final": "cooperative/high-and-low-final-checkpoint.json", "stages": [
			["cooperative/upper-path-a.json", "cooperative/upper-path-b.json", "cooperative/upper-path-checkpoint.json"],
			["cooperative/down-and-around-a.json", "cooperative/down-and-around-b.json", "cooperative/down-and-around-checkpoint.json"]]},
		"rules8": {"bundle": "comfort8/recordings.json", "entry": "high-and-low"},
		"rules8_dense": {"bundle": "comfort8/dense-physical.json", "entry": ""},
	},
	"rolling-home@1": {
		"rules6": {"initial": "cooperative/rolling-home-initial-checkpoint.json", "final": "cooperative/rolling-home-final-checkpoint.json", "stages": [
			["cooperative/weight-of-a-friend-a.json", "cooperative/weight-of-a-friend-b.json", "cooperative/weight-of-a-friend-checkpoint.json"],
			["cooperative/bring-it-home-a.json", "cooperative/bring-it-home-b.json", "cooperative/bring-it-home-checkpoint.json"]]},
		"rules8": {"bundle": "comfort8/recordings.json", "entry": "rolling-home"},
	},
	"a-house-for-two@1": {
		"rules6": {"initial": "cooperative/a-house-for-two-initial-checkpoint.json", "final": "cooperative/a-house-for-two-final-checkpoint.json", "stages": [
			["cooperative/open-the-house-a.json", "cooperative/open-the-house-b.json", "cooperative/open-the-house-checkpoint.json"],
			["cooperative/the-room-below-a.json", "cooperative/the-room-below-b.json", "cooperative/the-room-below-checkpoint.json"]]},
		"rules8": {"bundle": "comfort8/recordings.json", "entry": "a-house-for-two"},
	},
	"conservatory@1": {
		"rules7": {"initial": "journey/conservatory-initial-checkpoint.json", "final": "journey/conservatory-final-checkpoint.json", "stages": [
			["journey/a-light-above-a.json", "journey/a-light-above-b.json", "journey/a-light-above-checkpoint.json"],
			["journey/the-way-light-returns-a.json", "journey/the-way-light-returns-b.json", "journey/the-way-light-returns-checkpoint.json"]]},
		"rules8": {"bundle": "comfort8/recordings.json", "entry": "conservatory"},
	},
	"long-way-home@1": {
		"rules7": {"initial": "journey/long-way-home-initial-checkpoint.json", "final": "journey/long-way-home-final-checkpoint.json", "stages": [
			["journey/the-path-you-leave-a.json", "journey/the-path-you-leave-b.json", "journey/the-path-you-leave-checkpoint.json"],
			["journey/a-place-beside-you-a.json", "journey/a-place-beside-you-b.json", "journey/a-place-beside-you-checkpoint.json"]]},
		"rules8": {"bundle": "comfort8/recordings.json", "entry": "long-way-home"},
	},
	"the-wishing-well@1": {
		"rules9": {"initial": "cooperative/the-wishing-well-initial-checkpoint.json", "final": "cooperative/the-wishing-well-final-checkpoint.json", "stages": [
			["cooperative/go-on-ahead-a.json", "cooperative/go-on-ahead-b.json", "cooperative/go-on-ahead-checkpoint.json"],
			["cooperative/back-for-you-a.json", "cooperative/back-for-you-b.json", "cooperative/back-for-you-checkpoint.json"]],
			# A late receiver using the extra time; replayed alone, outside the chain.
			"extra": [["cooperative/back-for-you-b-long.json", "cooperative/back-for-you-a.json", "cooperative/go-on-ahead-checkpoint.json"]]},
	},
	"long-way-home@2": {
		"rules9": {"initial": "journey/long-way-home-v2-initial-checkpoint.json", "final": "journey/long-way-home-v2-final-checkpoint.json", "stages": [
			["journey/long-way-home-v2-the-path-you-leave-a.json", "journey/long-way-home-v2-the-path-you-leave-b.json", "journey/long-way-home-v2-the-path-you-leave-checkpoint.json"],
			["journey/long-way-home-v2-a-place-beside-you-a.json", "journey/long-way-home-v2-a-place-beside-you-b.json", "journey/long-way-home-v2-a-place-beside-you-checkpoint.json"]],
			# The other finale ways and the latest admitted opening, each replayed alone.
			"extra": [["journey/long-way-home-v2-garden-a.json", "", "journey/long-way-home-v2-the-path-you-leave-checkpoint.json"], ["journey/long-way-home-v2-garden-b.json", "journey/long-way-home-v2-garden-a.json", "journey/long-way-home-v2-the-path-you-leave-checkpoint.json"],
				["journey/long-way-home-v2-latest-a.json", "", "journey/long-way-home-v2-the-path-you-leave-checkpoint.json"], ["journey/long-way-home-v2-latest-b.json", "journey/long-way-home-v2-latest-a.json", "journey/long-way-home-v2-the-path-you-leave-checkpoint.json"]]},
	},
	"turn-of-the-tide@1": {
		# The LOW history won through the sea lock; the boom and punt ways and the
		# latest admitted opening after it are replayed alone.
		"rules9": {"initial": "journey/turn-of-the-tide-initial-checkpoint.json", "final": "journey/turn-of-the-tide-final-checkpoint.json", "stages": [
			["journey/set-the-tide-a.json", "journey/set-the-tide-b.json", "journey/set-the-tide-checkpoint.json"],
			["journey/slack-water-a.json", "journey/slack-water-b.json", "journey/slack-water-checkpoint.json"]],
			"extra": [["journey/slack-water-boom-a.json", "", "journey/set-the-tide-checkpoint.json"], ["journey/slack-water-boom-b.json", "journey/slack-water-boom-a.json", "journey/set-the-tide-checkpoint.json"],
				["journey/slack-water-punt-a.json", "", "journey/set-the-tide-checkpoint.json"], ["journey/slack-water-punt-b.json", "journey/slack-water-punt-a.json", "journey/set-the-tide-checkpoint.json"],
				["journey/slack-water-latest-a.json", "", "journey/set-the-tide-checkpoint.json"], ["journey/slack-water-latest-b.json", "journey/slack-water-latest-a.json", "journey/set-the-tide-checkpoint.json"]]},
	},
	# The six Lighthouse stages on the shared format: pairs and every checkpoint.
	"sleeping-lighthouse@2": {
		"rules11": {"bundle": "lighthouse/v2-chain.json", "entry": ""},
	},
	# The chain its own suite (test_turn_of_the_tide_v2.gd) wrote.
	"turn-of-the-tide@2": {
		"rules10": {"initial": "journey/turn-of-the-tide-v2-initial-checkpoint.json", "final": "journey/turn-of-the-tide-v2-final-checkpoint.json", "stages": [
			["journey/turn-of-the-tide-v2-set-the-tide-a.json", "journey/turn-of-the-tide-v2-set-the-tide-b.json", "journey/turn-of-the-tide-v2-set-the-tide-checkpoint.json"],
			["journey/turn-of-the-tide-v2-slack-water-a.json", "journey/turn-of-the-tide-v2-slack-water-b.json", "journey/turn-of-the-tide-v2-slack-water-checkpoint.json"]]},
	},
}
const LIGHTHOUSE_FIXTURE := "lighthouse/complete-six-v3.json"
var checks := 0
var failures := 0
var _bundles: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> bool:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
	return value

func _suite() -> String:
	return "replay_golden"

func _run() -> void:
	var started := Time.get_ticks_msec()
	var suite := _suite()
	if suite == "replay_golden": _check_split()
	var chapters: Dictionary = {}
	for key: String in SUITES.get(suite, []):
		var chapter_started := Time.get_ticks_msec()
		if key == LIGHTHOUSE: chapters[key] = _lighthouse()
		elif _check(CHAINS.has(key) and key in Golden.GOLDEN_KEYS, "Pinned chapter has fixture chains: " + key): chapters[key] = _chapter(key)
		print("%s %s %d ms" % [suite, key, Time.get_ticks_msec() - chapter_started])
	var golden := suite + ".json"
	var result := Golden.check(golden, {"chapters": chapters})
	for message: String in result.messages:
		push_error(message)
	_check(result.ok, "Replay chains match golden " + golden)
	print("%s time %d ms" % [suite, Time.get_ticks_msec() - started])
	print("%s: %d checks, %d failures" % [suite.to_upper().replace("_", " "), checks, failures])
	quit(1 if failures else 0)

func _check_split() -> void:
	var counted: Dictionary = {}
	for suite: String in SUITES:
		for key: String in SUITES[suite]:
			counted[key] = int(counted.get(key, 0)) + 1
	for key: String in Golden.GOLDEN_KEYS:
		_check(counted.get(key, 0) == 1, "Pinned chapter %s runs in exactly one replay golden suite (SUITES in tests/test_replay_golden.gd)" % key)
	for key: String in counted:
		_check(key in Golden.GOLDEN_KEYS or key == LIGHTHOUSE, "Replay golden suites list only pinned chapters: " + key)

func _chapter(key: String) -> Dictionary:
	var level := Registry.definition(key)
	var engine: Script = Registry.simulation_script(key)
	var result := {"engine": engine.resource_path, "chains": {}, "events": []}
	var seen: Dictionary = {}
	for name: String in CHAINS[key]:
		var chain := _chain(key, name, CHAINS[key][name])
		if chain.is_empty(): continue
		var start: Dictionary = chain.initial
		var checkpoint := start
		var stages: Array = []
		for index in range(chain.pairs.size()):
			var pair: Dictionary = chain.pairs[index]
			var label := "%s %s stage %d" % [key, name, index]
			var a := _replay(key, level, engine, checkpoint, pair.a, {}, label + " a", seen, false)
			# The static verifier runs once per chain; derive_checkpoint verifies every pair.
			var b := _replay(key, level, engine, checkpoint, pair.b, pair.a, label + " b", seen, index == 0)
			var derived: Dictionary = engine.derive_checkpoint(level, checkpoint, pair.a, pair.b)
			if not _check(derived.get("valid", false), "Pair derives its checkpoint: " + label + " " + str(derived.get("error", ""))): break
			var next: Dictionary = derived.checkpoint
			var expected: Dictionary = chain.checkpoints[index] if index < chain.checkpoints.size() else {}
			if not expected.is_empty():
				_check(_canonical_text(next) == _canonical_text(expected), "Derived checkpoint re-exports the fixture byte-for-byte: " + label)
			_check(Canonical.same(Registry.previous_checkpoint(key, next), checkpoint), "Registry names the proof's previous checkpoint: " + label)
			stages.append({"stage_id": str(pair.a.stage_id), "a": a, "b": b, "checkpoint_hash": str(next.checkpoint_hash),
				"checkpoint_stage_index": next.stage_index, "next_stage_id": str(next.get("next_stage_id", "")),
				"checkpoint_matches_fixture": not expected.is_empty() and _canonical_text(next) == _canonical_text(expected)})
			checkpoint = next
		_check(not chain.final.is_empty() and _canonical_text(checkpoint) == _canonical_text(chain.final), "Chain ends on the published final checkpoint: %s %s" % [key, name])
		result.chains[name] = {"initial_checkpoint_hash": str(start.get("checkpoint_hash", "")), "stages": stages,
			"final_checkpoint_hash": str(checkpoint.get("checkpoint_hash", "")), "final_typed_digest": Golden.typed_digest(checkpoint)}
		# Extra recordings [record, prior or "", checkpoint]: replayed alone and re-exported.
		var extras: Dictionary = {}
		for files: Array in CHAINS[key][name].get("extra", []):
			var record := Golden.fixture(files[0])
			var prior := Golden.fixture(files[1]) if not str(files[1]).is_empty() else {}
			var at := Golden.fixture(files[2])
			if not _check(not record.is_empty() and not at.is_empty(), "Extra fixture loads: " + str(files)): continue
			extras[str(files[0])] = _replay(key, level, engine, at, record, prior, "%s %s %s" % [key, name, files[0]], seen, true)
		if not extras.is_empty(): result.chains[name]["extra"] = extras
	var names := seen.keys()
	names.sort()
	result.events = names
	return result

## {initial, pairs: [{a, b}], checkpoints: [after each pair], final} or {}.
func _chain(key: String, name: String, spec: Dictionary) -> Dictionary:
	var label := key + " " + name
	var chain := {"initial": {}, "pairs": [], "checkpoints": [], "final": {}}
	if spec.has("bundle"):
		var bundle := _bundle(spec.bundle)
		var source: Dictionary = bundle.get(spec.entry, {}) if not str(spec.entry).is_empty() else bundle
		if not _check(source.get("pairs") is Array and not source.pairs.is_empty(), "Bundle has pairs: " + label): return {}
		for pair: Dictionary in source.pairs:
			chain.pairs.append({"a": pair.a, "b": pair.b})
			if pair.has("checkpoint"): chain.checkpoints.append(pair.checkpoint)
		if source.get("checkpoints") is Array and source.checkpoints.size() == source.pairs.size() + 1:
			chain.initial = source.checkpoints[0]
			chain.checkpoints = source.checkpoints.slice(1)
		chain.final = chain.checkpoints[-1] if chain.checkpoints.size() == chain.pairs.size() else {}
	else:
		chain.initial = Golden.fixture(spec.initial)
		chain.final = Golden.fixture(spec.final)
		for files: Array in spec.stages:
			var a := Golden.fixture(files[0])
			var b := Golden.fixture(files[1])
			if not _check(not a.is_empty() and not b.is_empty(), "Fixture recordings load: " + str(files)): return {}
			chain.pairs.append({"a": a, "b": b})
			chain.checkpoints.append(Golden.fixture(files[2]))
	var registry_start := Registry.initial_checkpoint(key)
	if chain.initial.is_empty(): chain.initial = registry_start
	_check(_canonical_text(chain.initial) == _canonical_text(registry_start), "Fixture chain starts at the registry's initial checkpoint: " + label)
	_check(chain.checkpoints.size() == chain.pairs.size(), "Every pair has its fixture checkpoint: " + label)
	return chain

func _bundle(name: String) -> Dictionary:
	if not _bundles.has(name): _bundles[name] = Golden.fixture(name)
	return _bundles[name]

func _replay(key: String, level: Dictionary, engine: Script, checkpoint: Dictionary, record: Dictionary, prior: Dictionary, label: String, seen: Dictionary, verify: bool) -> Dictionary:
	if verify:
		var verified: Dictionary = engine.verify_recording(level, record, checkpoint, prior)
		_check(verified.get("valid", false), "Fixture recording verifies through the registry engine: %s %s" % [label, verified.get("error", "")])
	var sim: RefCounted = engine.new()
	sim.catch_assistance = bool(record.get("catch_assistance", true))
	var reset := Registry.reset_simulation(sim, key, level, str(record.stage_id), checkpoint, prior, str(record.role), record)
	if not _check(reset, "Registry reset accepts the fixture: %s %s" % [label, sim.get("error")]): return {"reset": false}
	return _drive(sim, engine.expand_recording_inputs(record), record, label, seen)

## Steps the inputs, pinning intermediate hashes, events and the export.
func _drive(sim: RefCounted, frames: Array, record: Dictionary, label: String, seen: Dictionary) -> Dictionary:
	var expected_checks: Dictionary = {}
	for item: Dictionary in record.get("replay_checks", []):
		expected_checks[int(item.tick)] = str(item.state_hash)
	var matched := 0
	var mismatched := 0
	var event_log: Array = []
	var counts: Dictionary = {}
	for frame: Dictionary in frames:
		var state: Dictionary = sim.step(frame)
		var tick := LiveTick.tick_of(sim)
		if expected_checks.has(tick):
			if sim.state_hash() == expected_checks[tick]: matched += 1
			else: mismatched += 1
		var events: Array = state.get("events", [])
		if events.is_empty(): continue
		event_log.append([int(state.get("tick", tick)), events.duplicate()])
		for event: Variant in events:
			counts[str(event)] = int(counts.get(str(event), 0)) + 1
			seen[str(event)] = true
	_check(mismatched == 0 and matched == expected_checks.size(), "Every recorded intermediate state hash replays: " + label)
	var exported: Dictionary = sim.export_recording()
	var exact := _canonical_text(exported) == _canonical_text(record)
	_check(exact, "Replay re-exports the fixture byte-for-byte in canonical form: " + label)
	var round_trip: Variant = JSON.parse_string(JSON.stringify(exported))
	_check(round_trip is Dictionary and _canonical_text(round_trip) == _canonical_text(exported), "Exported recording survives serialise and parse unchanged: " + label)
	var snapshot: Dictionary = sim.snapshot()
	# Engines expose `complete`; the Lighthouse room facade reports it in its snapshot.
	var complete: Variant = sim.get("complete")
	if complete == null: complete = snapshot.get("complete", false)
	_check(str(sim.error).is_empty(), "Replay ends without an engine error: " + label)
	return {"recording_hash": str(exported.get("recording_hash", "")), "fixture_recording_hash": str(record.get("recording_hash", "")),
		"final_state_hash": str(sim.state_hash()), "simulation_version": exported.get("simulation_version", null),
		"duration_ticks": LiveTick.tick_of(sim), "completed": bool(complete), "finished": bool(sim.get("finished")),
		"can_commit": bool(snapshot.get("can_commit", false)), "outcome": exported.get("outcome", null),
		"replay_checks": expected_checks.size(), "exact_reexport": exact,
		"final_snapshot_digest": Canonical.digest(snapshot), "final_snapshot_typed_digest": Golden.typed_digest(snapshot),
		"events_digest": Canonical.digest(event_log), "event_counts": counts}

func _lighthouse() -> Dictionary:
	var fixture := Golden.fixture(LIGHTHOUSE_FIXTURE)
	var pairs: Array = fixture.get("pairs", [])
	var checkpoints: Array = fixture.get("checkpoints", [])
	var result := {"engine": "res://core/lighthouse/borrowed_light.gd", "chains": {}, "events": []}
	if not _check(pairs.size() == 6 and checkpoints.size() == 7, "Six-stage Lighthouse fixture is complete"): return result
	var seen: Dictionary = {}
	var stages: Array = []
	var start := Light.checkpoint_from_pairs([])
	_check(start.get("valid", false) and _canonical_text(start.checkpoint) == _canonical_text(checkpoints[0]), "Lighthouse starts at its published first checkpoint")
	for index in range(pairs.size()):
		var prefix := pairs.slice(0, index)
		var pair: Dictionary = pairs[index]
		var label := "sleeping-lighthouse@1 stage %d" % index
		var replays: Dictionary = {}
		for role: String in ["a", "b"]:
			var record: Dictionary = pair[role]
			var prior: Dictionary = pair.a if role == "b" else {}
			var verified := Light.verify_recording(record, prior, prefix)
			_check(verified.get("valid", false), "Lighthouse fixture verifies: %s %s %s" % [label, role, verified.get("error", "")])
			var sim := Light.new()
			if not _check(sim.reset(role, prior, prefix, int(record.simulation_version)), "Lighthouse reset accepts the fixture: %s %s" % [label, role]): continue
			replays[role] = _drive(sim, Light.expand_recording_inputs(record), record, label + " " + role, seen)
		var derived := Light.checkpoint_from_pairs(pairs.slice(0, index + 1))
		if not _check(derived.get("valid", false), "Lighthouse pairs derive a checkpoint: " + label): break
		_check(_canonical_text(derived.checkpoint) == _canonical_text(checkpoints[index + 1]), "Lighthouse checkpoint re-exports the fixture byte-for-byte: " + label)
		stages.append({"stage_id": str(pair.a.stage_id), "a": replays.get("a", {}), "b": replays.get("b", {}),
			"checkpoint_hash": str(derived.checkpoint.get("checkpoint_hash", "")), "checkpoint_stage_index": derived.checkpoint.get("stage_index", null)})
	result.chains["rules3"] = {"initial_checkpoint_hash": str(checkpoints[0].get("checkpoint_hash", "")), "stages": stages}
	var names := seen.keys()
	names.sort()
	result.events = names
	return result

func _canonical_text(value: Variant) -> String:
	return JSON.stringify(Canonical.normalized(value))
