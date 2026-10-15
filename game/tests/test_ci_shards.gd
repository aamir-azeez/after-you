extends SceneTree
## Every game/tests/test_*.gd suite has exactly one line in ci_shards.txt,
## which .github/workflows/verify.yml reads to pick each shard's suites.
const LIST := "res://tests/ci_shards.txt"
const SHARDS := ["1", "2", "3"]
var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)

func _run() -> void:
	var text := FileAccess.get_file_as_string(LIST)
	_check(not text.is_empty(), "ci_shards.txt is readable")
	var line_pattern := RegEx.create_from_string("^([a-z0-9_]+) (1|2|3|skip)(?: (\\S.*))?$")
	var assigned := {}
	var counts := {"1": 0, "2": 0, "3": 0, "skip": 0}
	var previous := ""
	for raw: String in text.split("\n"):
		var line := raw.trim_suffix("\r")
		if line.is_empty() or line.begins_with("#"): continue
		var found := line_pattern.search(line)
		_check(found != null, "Line is '<suite> <1|2|3>' or '<suite> skip <reason>': " + line)
		if found == null: continue
		var suite := found.get_string(1)
		var shard := found.get_string(2)
		var reason := found.get_string(3)
		_check(not assigned.has(suite), "Suite is listed once: " + suite)
		_check(previous < suite, "Lines are sorted by suite name: move '%s' above '%s'" % [suite, previous])
		_check((shard == "skip") == not reason.is_empty(), "Skipped suites give a reason and shard lines do not: " + line)
		_check(FileAccess.file_exists("res://tests/test_%s.gd" % suite), "Listed suite has a file: test_%s.gd" % suite)
		assigned[suite] = shard
		counts[shard] += 1
		previous = suite
	for file: String in DirAccess.get_files_at("res://tests"):
		if not file.begins_with("test_") or not file.ends_with(".gd"): continue
		var suite := file.trim_prefix("test_").trim_suffix(".gd")
		_check(assigned.has(suite), "Add '%s <shard>' to game/tests/ci_shards.txt, or '%s skip <reason>'" % [suite, suite])
	for shard: String in SHARDS:
		_check(counts[shard] > 0, "Shard %s runs at least one suite" % shard)
	_check(assigned.get("ci_shards", "skip") in SHARDS, "This guard runs in a shard")
	print("CI SHARDS: shard 1 %d, shard 2 %d, shard 3 %d, skipped %d" % [counts["1"], counts["2"], counts["3"], counts.skip])
	print("CI SHARDS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
