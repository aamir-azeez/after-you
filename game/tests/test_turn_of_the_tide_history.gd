extends SceneTree
## turn-of-the-tide@1 stage one ("set-the-tide") beyond the three main pairs:
## the Low half-first order, Half through high water, both misplays and B's
## hybrids, each derived through the full proof; the stage-2 history each one
## leaves; and the latest admitted hold on every branch.
## Main pairs: test_turn_of_the_tide (low) and test_turn_of_the_tide_ways.
const Simulation = preload("res://core/journey/simulation.gd")
const Catalog = preload("res://core/journey/stage_catalog.gd")
const Witness = preload("res://tests/turn_of_the_tide_witness.gd")
## pair -> the end state section 3.5 promises: [tide, lock, winch, levers on, routes kept].
const HISTORY := {
	"low-jetty": ["low", "west", "slip", ["sluice"], ["wheel-step", "slipway", "jetty-1", "jetty-2"]],
	"low-half-first": ["low", "west", "slip", ["sluice"], ["wheel-step", "slipway", "sand-1"]],
	"low-half-first-stones": ["low", "east", "slip", ["sluice"], ["wheel-step", "stones-1", "stones-2", "stones-3", "lock-east"]],
	"half-early-sand": ["half", "east", "stowed", ["sluice"], ["quay-step", "sand-1", "stones-2", "stones-3", "lock-east"]],
	"half-via-high": ["half", "east", "stowed", ["sluice"], ["quay-step", "stones-1", "stones-2", "stones-3", "lock-east"]],
	"half-winch": ["half", "east", "slip", ["sluice"], ["quay-step", "stones-3", "lock-east"]],
	"high-early-sand": ["high", "west", "stowed", ["line", "gangway"], ["bollard-step", "sand-1", "jetty-1", "jetty-3"]],
	"high-sluice": ["high", "west", "stowed", ["line", "gangway", "sluice"], ["bollard-step", "jetty-1", "jetty-3"]],
	"high-spout": ["high", "west", "stowed", ["line", "gangway", "sluice"], ["bollard-step", "sand-1", "jetty-3"]],
}
var checks := 0
var failures := 0
var mismatches: Array[String] = []
var level: Dictionary = {}
var initial: Dictionary = {}

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	level = Catalog.definition(Witness.KEY)
	initial = Catalog.initial_checkpoint(level)
	for name: String in HISTORY:
		_pair(name)
	for branch: String in ["low", "half", "high"]:
		_latest(branch)
	_not_ready()
	for line: String in mismatches: print("PORT MISMATCH " + line)
	print("TURN OF THE TIDE HISTORY: %d checks, %d failures, %d port mismatches" % [checks, failures, mismatches.size()])
	quit(1 if failures else 0)

func _pair(name: String) -> void:
	var spec: Array = Witness.PAIRS[name]
	var pair := Witness.pair(level, Witness.SET, initial, Witness.a_routes()[spec[0]], Witness.b_routes()[spec[1]], true)
	_check(pair.error.is_empty(), "%s derives: %s" % [name, pair.error])
	if not pair.error.is_empty(): return
	var a: RefCounted = pair.a_sim
	var branch: String = spec[2]
	_check(a._ready_branch == branch and a.source_budget_ticks() == Witness.PORT_STAGE_ONE.budget[branch], "%s commits the %s branch with budget %d" % [name, branch, Witness.PORT_STAGE_ONE.budget[branch]])
	_check(a._hold_start <= Witness.PORT_STAGE_ONE.deadline[branch], "%s holds by tick %d (held at %d)" % [name, Witness.PORT_STAGE_ONE.deadline[branch], a._hold_start])
	if Witness.PORT_STAGE_ONE.a_ticks.has(spec[0]): _upper("stage 1 %s A ticks" % spec[0], pair.a.duration_ticks, Witness.PORT_STAGE_ONE.a_ticks[spec[0]])
	var want: Array = HISTORY[name]
	var cp: Dictionary = pair.checkpoint
	var controls: Dictionary = cp.mechanisms.controls
	_check(controls.tide == want[0] and controls.lock == want[1] and controls.winch == want[2] and controls.chamber == "half" and controls.basin == "shut", "%s leaves tide %s, lock %s, winch %s and the stage-2 controls untouched (%s)" % [name, want[0], want[1], want[2], str(controls)])
	var on: Array = []
	for lever: String in cp.mechanisms.levers:
		if cp.mechanisms.levers[lever]: on.append(lever)
	on.sort()
	var expected: Array = want[3].duplicate()
	expected.sort()
	_check(on == expected, "%s leaves levers %s on (got %s)" % [name, str(expected), str(on)])
	for route: String in want[4]:
		_check(route in cp.mechanisms.latched_bridges, "%s keeps %s" % [name, route])
	_check(cp.players.p1.surface_id == "r-terrace" and cp.players.p0.surface_id == {"low": "wheel-step", "half": "quay-step", "high": "bollard-step"}[branch], name + ": B rang from the rock terrace, A waits on its step")
	print("TIDE %s A=%d ready=%d budget=%d B=%d" % [name, pair.a.duration_ticks, a._hold_start, a.source_budget_ticks(), pair.b.duration_ticks])

## The latest admitted hold on each branch, B still finishing, one tick later refused.
func _latest(branch: String) -> void:
	var ops: Array = Witness.a_routes()[branch]
	var base := Witness.source(level, Witness.SET, initial, ops, 0, Callable(), true)
	var delay: int = base.receiver_deadline() - 1 - base.source_budget_ticks() - base._hold_start
	_check(base.can_commit() and delay >= 0, branch + " leaves room to start later")
	if delay < 0: return
	var delayed := Witness.source(level, Witness.SET, initial, ops, delay, Callable(), true)
	_check(delayed.can_commit() and delayed._hold_start == Witness.PORT_STAGE_ONE.deadline[branch], "%s: the latest admitted hold starts at %d (got %d)" % [branch, Witness.PORT_STAGE_ONE.deadline[branch], delayed._hold_start])
	if not delayed.can_commit(): return
	var b := Witness.receiver(level, Witness.SET, initial, delayed.export_recording(), Witness.b_routes()[branch], Callable(), true)
	_check(b.complete and b.tick <= b.receiver_deadline(), "%s: B still finishes from the latest hold (%s %s)" % [branch, b.error, b.get_meta("route_error")])
	var late := Witness.source(level, Witness.SET, initial, ops, delay + 1, Callable(), true)
	_check(not late.can_commit() and late.commit_reason() == "Try again with more time left for your partner.", "%s: one tick later is refused with the soft-fail reason" % branch)
	print("TIDE latest %s A=%d ready=%d budget=%d B=%d" % [branch, delayed.tick, delayed._hold_start, delayed.source_budget_ticks(), b.tick])

## Not on a step, or on the quay beside one: not ready, with the generic reason.
func _not_ready() -> void:
	var wheel := Witness.source(level, Witness.SET, initial, Witness.APPROACH + [Witness.T, Witness.T, ["n", 20]], 0, Callable(), true)
	_check(wheel.error.is_empty() and not wheel.can_commit() and wheel.commit_reason() == "Keep the crossing ready for your partner.", "High water alone, at the wheel, is not ready")
	var edge := Witness.source(level, Witness.SET, initial, Witness.APPROACH + [Witness.T, Witness.T, ["w",[320,-470]], ["n", 20]], 0, Callable(), true)
	_check(edge.error.is_empty() and not edge.can_commit() and not edge.walkable_at(320, -512), "Without the line the bollard step stays shut and the pad cannot be reached")
	var stub := Witness.source(level, Witness.SET, initial, Witness.APPROACH + [["w",[192,-470]], ["n", 10]], 0, Callable(), true)
	_check(not stub.walkable_at(192, -512) and not stub.can_commit(), "At low water with the winch stowed the wheel step stays shut")

## A port figure that bounds the native walk from above.
func _upper(label: String, native: int, port: int) -> void:
	print("PORT %s native=%d port=%d delta=%d" % [label, native, port, native - port])
	if native > port: mismatches.append("%s: native %d > port %d" % [label, native, port])
	_check(native <= port, "%s: native %d within the port bound %d" % [label, native, port])

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
