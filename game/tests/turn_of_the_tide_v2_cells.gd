extends SceneTree
## turn-of-the-tide@2 Slack Water, every cell (stage-one history x way) with
## its posts in one row in front of the sea wheel (turn_of_the_tide_v2_catalog.gd
## ROW_*), played with real inputs on the tide rules:
## - p1's natural plan, the sea turned first, and every mooring made fast
##   each commit their own way's post; p0 then lights the lantern beside the
##   natural plan (derived through the full proof) and beside every mooring
##   made fast. The sea-first turn ends in the natural turn's state, so its p0
##   is the natural one's;
## - budgets, latest hold_starts and p1 presses are exact, p1 ticks are upper
##   bounds, all from an independent axis-walk model (MODEL);
## - p1 presses match @1's (the row moves stands, not the order of play);
## - the sea-first turn ends with the natural turn's levers and controls.
## Each test_turn_of_the_tide_v2_cells_<history> suite runs one stage-one
## history, so no suite runs long.
const KEY := "turn-of-the-tide@2"
const Registry = preload("res://services/chapter_registry.gd")
const Simulation = preload("res://core/journey/simulation.gd")
const Tide = preload("res://tests/turn_of_the_tide_witness.gd")
const V2 = preload("res://tests/turn_of_the_tide_v2_witness.gd")
const SLACK := "slack-water"
const WAYS := ["boom", "sea-lock", "punt"]
## history -> way -> [budget, latest hold_start, p1 presses, p1 ticks bound,
## the same two sea first, the same two with every mooring made fast].
const MODEL := {
	"low": {"boom": [564,2435,4,382,8,522,6,543], "sea-lock": [644,2355,3,400,7,413,5,543], "punt": [528,2471,5,500,9,530,7,546]},
	"half": {"boom": [548,2451,5,389,9,448,7,550], "sea-lock": [660,2339,8,339,8,339,10,560], "punt": [544,2455,6,417,10,456,8,554]},
	"high": {"boom": [580,2419,8,480,8,503,10,579], "sea-lock": [628,2371,7,392,7,394,9,580], "punt": [544,2455,5,409,9,511,7,573]},
}
var checks := 0
var failures := 0
## The natural turn's final levers and controls, by "history/way".
var _natural: Dictionary = {}

## The stage-one histories this suite plays; each suite file names one.
func _histories() -> Array:
	return []

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var level := Registry.definition(KEY)
	var initial := Registry.initial_checkpoint(KEY)
	for history: String in _histories():
		var one := V2.pair(level, "set-the-tide", initial, Tide.a_routes()[history], Tide.b_routes()[history])
		_check(one.error.is_empty(), "Stage one %s finishes: %s" % [history, one.error])
		if not one.error.is_empty(): continue
		for way: String in WAYS:
			var model: Array = MODEL[history][way]
			var home := Tide.p1_home(history)
			_cell(level, one.checkpoint, history, way, "natural", home + V2.p1_way(history, way), model[2], model[3], model)
			_cell(level, one.checkpoint, history, way, "sea first", home + V2.p1_way_sea_first(history, way), model[4], model[5], model)
			_cell(level, one.checkpoint, history, way, "all chains", home + V2.p1_all_chains(history, way), model[6], model[7], model)
			_check(model[2] == Tide.MODEL_CELLS[history][way][4], "%s %s: p1 presses as many times as in @1 (%d)" % [history, way, model[2]])
	_check(not _histories().is_empty(), "The suite names its stage-one histories")
	print("TURN OF THE TIDE V2 CELLS %s: %d checks, %d failures" % [str(_histories()).to_upper(), checks, failures])
	quit(1 if failures else 0)

func _cell(level: Dictionary, start: Dictionary, history: String, way: String, kind: String, ops: Array, presses: int, ticks: int, model: Array) -> void:
	var label := "%s %s (%s)" % [history.to_upper(), way, kind]
	var a := Simulation.new()
	a.reset(level, SLACK, start, {}, "a")
	var why := Tide.play(a, ops, V2.home_probe())
	_check(why.is_empty() and a.can_commit(), "%s commits: %s %s" % [label, why, a.commit_reason()])
	if not a.can_commit(): return
	_check(a._ready_branch == way and a.source_budget_ticks() == model[0], "%s commits its own post with budget %d (got %d)" % [label, model[0], a.source_budget_ticks()])
	_check(a.receiver_deadline() - 1 - a.source_budget_ticks() == model[1] and a._hold_start <= model[1], "%s: held by tick %d, the latest is %d" % [label, a._hold_start, model[1]])
	_check(Tide.count_presses(a) == presses, "%s: p1 presses %d (got %d)" % [label, presses, Tide.count_presses(a)])
	print("MODEL %s p1 ticks native=%d model=%d" % [label, a.tick, ticks])
	_check(a.tick <= ticks, "%s: p1 ticks %d within the model bound %d" % [label, a.tick, ticks])
	var final := {"levers": a._mechanisms.levers.duplicate(), "controls": a._mechanisms.controls.duplicate()}
	match kind:
		"sea first":
			_check(final == _natural.get(history + "/" + way), "%s ends with the natural turn's levers and controls, so p0 plays as beside it" % label)
		"natural":
			_natural[history + "/" + way] = final
			var played := V2.pair(level, SLACK, start, ops, V2.p0_way(history, way))
			_check(played.error.is_empty(), "%s derives: %s" % [label, played.error])
			if played.error.is_empty():
				_check(played.checkpoint.stage_index == 2 and played.checkpoint.players.p0.surface_id == "mole-terrace" and played.checkpoint.mechanisms.latched_bridges.is_empty(), "%s: the lantern is lit and no route is kept" % label)
		"all chains":
			var b := Simulation.new()
			b.reset(level, SLACK, start, a.export_recording(), "b")
			why = Tide.play(b, V2.p0_way(history, way), V2.home_probe())
			# As V2.pair: the lantern counts once the memory's turn has run out.
			for _tick in range(b.duration_limit()):
				if b.finished or not b._objective: break
				b.step({})
			_check(why.is_empty() and b.complete, "%s: p0 lights the lantern beside it: %s %s" % [label, why, b.commit_reason()])

func _check(okay: bool, label: String) -> void:
	checks += 1
	if not okay:
		failures += 1
		push_error(label)
