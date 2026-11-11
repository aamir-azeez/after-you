extends SceneTree
## The Godot half of scripts/chapter_recording.py, chapter_recheck.py and
## chapter_turn_limits.py. It plays a chapter's routes headless through the real
## simulation and writes a JSON report to --out; it writes nothing else.
##
##   -- --mode import --key <key> --source <file> [--stage <id>] --out <file>
##      The source's recorded pairs (tests/recorded_routes.gd) become the routes
##      of their stages (only --stage's with it), merged over the chapter's
##      current routes and played through every stage.
##   -- --mode recheck --key <key> --out <file>
##      The chapter's routes (tests/routes/<key>.json), or without them its
##      stage fixtures' inputs, played through every stage.
##
## The report: {"ok", "error", "key", "source", "imported", "notes", "routes"
## (import only), "stages": [{"id", "ok", "error", "a_ticks", "b_ticks",
## "msec"}], "limits": {"a", "b"} (ticks the definition allows), "msec"}.
const Witness = preload("res://tests/chapter_witness.gd")
const Recorded = preload("res://tests/recorded_routes.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Golden = preload("res://tests/golden_support.gd")
const Canonical = preload("res://core/v2/canonical.gd")

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var args := _arguments()
	var out := str(args.get("out", ""))
	if out.is_empty():
		push_error("chapter_recordings.gd needs --out <file>")
		quit(2)
		return
	var report := _report(args)
	var file := FileAccess.open(out, FileAccess.WRITE)
	if file == null:
		push_error("Could not write the report " + out)
		quit(2)
		return
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	print("CHAPTER RECORDINGS %s: %s" % [report.key, "ok" if report.ok else report.error])
	quit(0)

func _arguments() -> Dictionary:
	var result := {}
	var user := OS.get_cmdline_user_args()
	for index in range(0, user.size() - 1):
		if user[index].begins_with("--"): result[user[index].substr(2)] = user[index + 1]
	return result

func _report(args: Dictionary) -> Dictionary:
	var started := Time.get_ticks_msec()
	var key := str(args.get("key", ""))
	var report := {"ok": false, "error": "", "key": key, "source": "", "imported": [], "notes": [], "stages": [], "limits": {}, "msec": 0}
	var level := Registry.definition(key)
	if level.is_empty():
		report.error = "%s is not a registered chapter" % key
		return report
	report.limits = _limits(key, level)
	var routes: Dictionary
	match str(args.get("mode", "")):
		"import":
			routes = _imported(key, level, str(args.get("source", "")), str(args.get("stage", "")), report)
			report["routes"] = routes
		"recheck":
			routes = Witness.routes(key)
			report.source = Witness.routes_path(key)
			if routes.is_empty():
				routes = _fixture_routes(key, level, report)
		_:
			report.error = "--mode is import or recheck"
	if report.error.is_empty():
		var played := Witness.play(key, routes)
		report.stages = played.stages
		report.error = played.error
	report.ok = report.error.is_empty()
	report.msec = Time.get_ticks_msec() - started
	return report

## Ticks the definition gives each turn, read from its engine (0 when its family has no turn_ticks).
func _limits(key: String, level: Dictionary) -> Dictionary:
	var engine: RefCounted = Registry.simulation_script(key).new()
	var rules := Registry.preferred_rules(key)
	var result := {}
	for role: String in ["a", "b"]:
		result[role] = int(engine.turn_ticks(level, rules, role)) if engine.has_method("turn_ticks") else 0
	return result

func _imported(key: String, level: Dictionary, source: String, only: String, report: Dictionary) -> Dictionary:
	report.source = source
	var problem: Array = []
	var parsed: Variant = Recorded.read_source(source, problem)
	if parsed == null:
		report.error = "%s: %s" % [key, problem[0]]
		return {}
	var found := Recorded.pairs_by_stage(parsed, str(level.id))
	# The stages the source does not give keep their routes, or without a
	# routes file (a new version) the runs in their stage fixtures.
	var routes := Witness.routes(key)
	if routes.is_empty(): routes = _fixture_routes(key, level, {"error": "", "source": ""})
	var stage_ids: Array = level.stages.map(func(stage: Dictionary) -> String: return stage.id)
	if not only.is_empty() and only not in stage_ids:
		report.error = "%s has no stage %s (its stages: %s)" % [key, only, ", ".join(stage_ids)]
		return {}
	for stage_id: String in stage_ids:
		if not only.is_empty() and stage_id != only: continue
		var pairs: Array = found.get(stage_id, [])
		if pairs.size() > 1:
			report.error = "%s/%s: the source holds %d different runs of this stage; give a file with one run" % [key, stage_id, pairs.size()]
			return {}
		if pairs.is_empty(): continue
		var pair: Dictionary = pairs[0]
		routes[stage_id] = Recorded.stage_route(key, pair)
		report.imported.append(stage_id)
		if int(pair.a.get("level_version", 0)) != int(level.version):
			report.notes.append("%s was recorded on %s@%d" % [stage_id, level.id, int(pair.a.get("level_version", 0))])
		elif str(pair.a.get("definition_hash")) != Canonical.digest(level):
			report.notes.append("%s was recorded on an earlier layout; its inputs replay on this one" % stage_id)
	if report.imported.is_empty():
		report.error = "%s: the source holds no recorded run of %s" % [key, only if not only.is_empty() else "any of its stages"]
	return routes

## Routes from the chapter's stage fixtures (golden_support.gd fixture_prefixes):
## the published chapters keep their runs there.
func _fixture_routes(key: String, level: Dictionary, report: Dictionary) -> Dictionary:
	var names := Golden.fixture_prefixes(key)
	var routes := {}
	report.source = "tests/fixtures/%s<stage>-a/-b.json" % names.get("stages", "")
	for stage: Dictionary in level.stages:
		var pair := {"a": Golden.fixture("%s%s-a.json" % [names.stages, stage.id]), "b": Golden.fixture("%s%s-b.json" % [names.stages, stage.id])}
		if pair.a.is_empty() or pair.b.is_empty():
			report.error = "%s/%s has no routes file and no stage fixtures to replay" % [key, stage.id]
			return {}
		routes[stage.id] = Recorded.stage_route(key, pair)
	return routes
