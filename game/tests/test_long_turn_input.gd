extends SceneTree
## Capped input (core/physical/runtime.gd INPUT_RULES), the rules that let a new
## chapter's turns run up to 15 minutes, on Turn of the Tide @2's stages with
## input_rules 1 and the development turn limits (content/chapters/index.gd):
## - a change past the allowance holds the previous input one tick, and the
##   live turn, its replay and the partner's memory of it record the same;
## - the action button keeps a reserve, and a press held back lands later;
## - a frantic 15 minute turn stays inside the server's widest record
##   (backend protocol-physical-recording.ts widestRecordingBytes);
## - no published definition declares it, so published turns play as before
##   (their goldens are the other suites').
## Prints each turn's measured sizes, raw and deflated, for the bounds' notes.
const Simulation = preload("res://core/journey/simulation.gd")
const Catalog = preload("res://core/journey/stage_catalog.gd")
const Runtime = preload("res://core/physical/runtime.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Index = preload("res://content/chapters/index.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const BlobCodec = preload("res://services/blob_codec.gd")
const LeaderboardReplay = preload("res://services/leaderboard_replay.gd")
## The table backend turn-limits.test.ts and long-turns.test.ts also read.
const CASES := "res://tests/fixtures/journey/turn-limits-cases.json"
const KEY := "turn-of-the-tide@2"
const STAGE := "set-the-tide"
const RULES := 10
var checks := 0
var failures := 0
var level: Dictionary = {}
var initial: Dictionary = {}
var rules: Dictionary = {}

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var published: Dictionary = Catalog.definition(KEY)
	initial = Catalog.initial_checkpoint(published)
	level = published.duplicate(true)
	level.input_rules = 1
	level.turn_limits = Index.DEVELOPMENT_TURN_LIMITS.duplicate()
	rules = Runtime.input_rules(level, RULES)
	_check(Simulation.rules_allowed(level, RULES) and rules == Runtime.INPUT_RULES[1], "The capped definition plays rules 10 with INPUT_RULES 1")
	_check(Runtime.turn_ticks(level, RULES, "a") == 26700 and Runtime.turn_ticks(level, RULES, "b") == 27000, "The development turns are 14:50 and 15:00")
	_shared_table()
	_published()
	_holds()
	_presses()
	_replays()
	_fifteen_minutes()
	print("LONG TURN INPUT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## The rules, the turn cap, the entry bound and the replay cap agree with the server's, through one shared table.
func _shared_table() -> void:
	var table: Variant = JSON.parse_string(FileAccess.get_file_as_string(CASES))
	var capped: Dictionary = table.get("capped", {}) if table is Dictionary else {}
	_check(not capped.is_empty(), "The shared table has the capped input section")
	var declared: Dictionary = capped.get("input_rules", {})
	_check(declared.size() == Runtime.INPUT_RULES.size(), "The shared table lists every INPUT_RULES entry")
	for key: String in declared:
		var mine: Dictionary = Runtime.INPUT_RULES.get(int(key), {})
		_check(mine.size() == declared[key].size() and mine.keys().all(func(field: String) -> bool: return int(declared[key].get(field, -1)) == int(mine[field])), "INPUT_RULES %s matches the server's" % key)
	_check(int(capped.get("long_turn_ticks", 0)) == Runtime.LONG_TURN_TICKS, "LONG_TURN_TICKS matches the server's")
	_check(int(capped.get("max_replay_bytes", 0)) == LeaderboardReplay.MAX_BODY_BYTES, "The leaderboard replay cap matches the server's MAX_REPLAY_BYTES")
	for pair: Array in capped.get("max_action_entries", []):
		_check(Runtime.max_action_entries(Runtime.INPUT_RULES[1], int(pair[0])) == int(pair[1]), "max_action_entries(%d) is %d, as maxActionEntries" % [int(pair[0]), int(pair[1])])

## No published definition declares input_rules: every published turn plays uncapped, as before.
func _published() -> void:
	for key: String in Registry.keys():
		var definition := Registry.definition(key)
		_check(not definition.has("input_rules") and Runtime.input_rules(definition, int(definition.get("simulation_version", 0))).is_empty(), key + " declares no capped input")
	var free := _sim({}, "a", published_level())
	for index in range(400): free.step(_frantic(index))
	_check(free.export_recording().actions.size() == 400, "Uncapped, a change every tick is an entry every tick")

func published_level() -> Dictionary:
	return Catalog.definition(KEY)

## A change every tick: the allowance first, then one change every change_ticks, the input held between.
func _holds() -> void:
	var sim := _sim()
	var ticks := 3000
	for index in range(ticks): sim.step(_frantic(index))
	var record: Dictionary = sim.export_recording()
	var most := Runtime.max_action_entries(rules, ticks)
	var count: int = record.actions.size()
	_check(count <= most and count >= most - int(rules.reserve) - 2, "A change every tick records %d entries, within the bound %d less the reserve" % [count, most])
	# The last entry may still be growing.
	var tail: Array = record.actions.slice(count - 50, count - 1)
	_check(tail.all(func(entry: Dictionary) -> bool: return int(entry.ticks) == int(rules.change_ticks)), "Past the allowance each input is held change_ticks ticks")
	_check(Runtime.max_action_entries({}, 27000) == -1, "Uncapped input has no bound")

## The button may spend the reserve the stick leaves, and a press held back lands on the next tick that may change.
func _presses() -> void:
	var sim := _sim()
	for index in range(3000): sim.step(_frantic(index))
	sim.step({"move_x": 0.0, "move_z": 0.0, "interact": true})
	_check(bool(sim._actions[-1].action), "Once the stick has spent its allowance, a press still registers on its own tick")
	sim.step({"move_x": 0.0, "move_z": 0.0, "interact": false})
	# An empty allowance holds the press back; it lands as soon as one change is paid for.
	sim._input_credit = 0
	sim.step({"move_x": 0.5, "move_z": 0.0, "interact": true})
	_check(not bool(sim._actions[-1].action) and sim._pending_press, "With no allowance left the press is held back, not lost")
	var waited := 0
	while not bool(sim._actions[-1].action) and waited < 20:
		sim.step({"move_x": 0.5, "move_z": 0.0, "interact": false})
		waited += 1
	_check(bool(sim._actions[-1].action) and not sim._pending_press and waited == int(rules.change_ticks) - 1, "The held press lands once the allowance pays for it (%d ticks later)" % waited)
	var proof: RefCounted = Simulation._proof(RULES)
	var record: Dictionary = sim.export_recording()
	_check(proof._verify_raw(level, record, initial, {}).valid, "A turn with a held press replays exactly")

## Live, replayed and remembered by the partner, a capped turn records the same, and a turn past the bound is refused.
func _replays() -> void:
	var live := _sim()
	for index in range(2400): live.step(_frantic(index))
	var record: Dictionary = live.export_recording()
	var replay := _sim()
	for frame: Dictionary in Simulation.expand_recording_inputs(record): replay.step(frame)
	_check(Canonical.same(replay.export_recording(), record), "Its recorded frames replay to the same recording: the cap never holds them again")
	var proof: RefCounted = Simulation._proof(RULES)
	_check(proof._verify_raw(level, record, initial, {}).valid, "The proof replays the capped turn exactly")
	# The partner's memory plays the same frames through its own copy of the rules.
	var memory := _sim(record, "b")
	for index in range(int(record.duration_ticks)): memory.step({"move_x": 0.0, "move_z": 0.0, "interact": false})
	_check(Canonical.same(memory._source.export_recording(), record), "The partner's memory of the turn records it exactly")
	var over: Dictionary = record.duplicate(true)
	var split: Array = []
	for entry: Dictionary in over.actions:
		if int(entry.ticks) > 1 and split.size() < 2000:
			split.append({"ticks": 1, "x": entry.x, "z": entry.z, "action": entry.action})
			split.append({"ticks": int(entry.ticks) - 1, "x": entry.x, "z": entry.z, "action": entry.action})
		else:
			split.append(entry)
	over.actions = split
	over.recording_hash = Simulation.recording_hash(over)
	_check(split.size() > Runtime.max_action_entries(rules, int(over.duration_ticks)) and proof.recording_error(level, over, initial) == "Invalid action list.", "A recording with more entries than the cap allows is refused before any replay")

## A whole frantic 15 minute first turn (14:50): inside the server's widest record. Prints its sizes.
func _fifteen_minutes() -> void:
	var started := Time.get_ticks_msec()
	var sim := _sim()
	var ticks := Runtime.turn_ticks(level, RULES, "a")
	for index in range(ticks): sim.step(_frantic(index))
	var record: Dictionary = sim.export_recording()
	var played := Time.get_ticks_msec() - started
	_check(sim.finished and int(record.duration_ticks) == ticks, "The first turn runs its whole %d ticks" % ticks)
	var bytes := JSON.stringify(Canonical.normalized(record)).to_utf8_buffer()
	var ids := str(level.id).length() + str(STAGE).length()
	var digits := str(ticks).length()
	var widest := 1024 + ids + Runtime.max_action_entries(rules, ticks) * (44 + digits) + (ticks / 30 + 1) * (90 + digits)
	_check(record.actions.size() <= Runtime.max_action_entries(rules, ticks) and bytes.size() <= widest, "A frantic 15 minute turn fits the server's widest record: %d bytes of %d" % [bytes.size(), widest])
	started = Time.get_ticks_msec()
	var proof: RefCounted = Simulation._proof(RULES)
	_check(proof._verify_raw(level, record, initial, {}).valid, "The proof replays the whole 15 minute turn")
	var verified := Time.get_ticks_msec() - started
	print("LONG TURN bytes ticks=%d actions=%d checks=%d canonical=%d deflated=%d widest=%d play_ms=%d verify_ms=%d" % [ticks, record.actions.size(), record.replay_checks.size(),
		bytes.size(), BlobCodec.encode(bytes).size(), widest, played, verified])

func _sim(prior: Dictionary = {}, role: String = "a", definition: Dictionary = {}) -> RefCounted:
	var sim := Simulation.new()
	sim.simulation_version = RULES
	sim._reset_trusted(level if definition.is_empty() else definition, STAGE, initial, prior, role)
	return sim

## A trembling thumb: a new stick value every tick, each too small to move a
## spirit a whole centimetre (runtime.gd _move rounds it away), so the turn
## stays where it starts however long it runs.
func _frantic(index: int) -> Dictionary:
	return {"move_x": float((index * 37) % 13 - 6) / 100.0, "move_z": float((index * 53) % 13 - 6) / 100.0, "interact": false}

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
