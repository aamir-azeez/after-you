extends SceneTree
## Recorded routes (tests/recorded_routes.gd) are exact: for each chapter below,
## its stage fixtures' recordings turned into input routes and played by the
## chapter witness (tests/chapter_witness.gd) give back every recording byte for
## byte and every checkpoint with the same values and hash, and routes taken
## again from what they played are the same routes. This is what lets
## scripts/chapter_recording.py make a chapter's witness and fixtures from a
## real run.
const Witness = preload("res://tests/chapter_witness.gd")
const Recorded = preload("res://tests/recorded_routes.gd")
const Registry = preload("res://services/chapter_registry.gd")
const Golden = preload("res://tests/golden_support.gd")
const Canonical = preload("res://core/v2/canonical.gd")
## Chapters whose stage fixtures are one chain from the initial checkpoint.
const KEYS := ["turn-of-the-tide@2", "turn-of-the-tide@1", "the-wishing-well@1", "long-way-home@2"]
var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func _check(ok: bool, message: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
	return ok

func _run() -> void:
	for key: String in KEYS:
		var started := Time.get_ticks_msec()
		_chapter(key)
		print("%s replayed in %d ms" % [key, Time.get_ticks_msec() - started])
	print("RECORDED ROUTES: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _chapter(key: String) -> void:
	var level := Registry.definition(key)
	var names := Golden.fixture_prefixes(key)
	var routes := {}
	for stage: Dictionary in level.stages:
		var pair := {"a": Golden.fixture("%s%s-a.json" % [names.stages, stage.id]), "b": Golden.fixture("%s%s-b.json" % [names.stages, stage.id])}
		if not _check(not pair.a.is_empty() and not pair.b.is_empty(), "%s/%s has stage fixtures" % [key, stage.id]): return
		routes[stage.id] = Recorded.stage_route(key, pair)
	var played := Witness.play(key, routes)
	if not _check(played.error.is_empty(), "%s plays through from its recorded routes: %s" % [key, played.error]): return
	for index in range(level.stages.size()):
		var stage_id: String = level.stages[index].id
		_same_file("%s%s-a" % [names.stages, stage_id], played.pairs[index].a)
		_same_file("%s%s-b" % [names.stages, stage_id], played.pairs[index].b)
		_same_checkpoint("%s%s-checkpoint" % [names.stages, stage_id], played.checkpoints[index + 1])
		var again := Recorded.stage_route(key, played.pairs[index])
		_check(JSON.stringify(again) == JSON.stringify(routes[stage_id]), "%s/%s: routes taken from the replayed run are the same routes" % [key, stage_id])
	_same_checkpoint(names.chapter + "final-checkpoint", played.checkpoints[-1])

## The value written as chapter_suite.gd writes a fixture is the fixture file, byte for byte.
func _same_file(name: String, value: Dictionary) -> void:
	var path := "res://tests/fixtures/%s.json" % name
	var text := FileAccess.get_file_as_string(path).replace("\r\n", "\n")
	_check(text == JSON.stringify(value, "\t") + "\n", "Replayed %s is byte-identical to its fixture %s" % [name, path])

## A checkpoint is the fixture's values and hash. Its bytes depend on its
## writer: one that derived it from recordings that never went through JSON
## prints whole numbers in the proof as integers, chapter_witness as JSON reads them.
func _same_checkpoint(name: String, value: Dictionary) -> void:
	var fixture := Golden.fixture(name + ".json")
	_check(Canonical.same(fixture, value) and str(fixture.get("checkpoint_hash")) == str(value.get("checkpoint_hash")), "Replayed %s is its fixture" % name)
