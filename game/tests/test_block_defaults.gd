extends SceneTree
## Puzzle blocks' defaults (content/blocks/defaults.gd):
##  - every block has a row, and every cue a row names is the one the shared
##    sound map plays for that block's moments today,
##  - default hints are PlayerCopy words in plain sentences,
##  - a descriptor naming a block source gets its stage copy, lever looks and
##    water levels filled only where it gives none, and a cooperative one
##    no stage copy,
##  - a sample journey level built from blocks opens its crossings by the
##    journey engine's own gate rule: step, switch and lever,
##  - and every registered chapter that names a block source is exactly its
##    blocks expanded (none does yet; every published descriptor is unchanged).
const Blocks = preload("res://core/blocks/stage_blocks.gd")
const Defaults = preload("res://content/blocks/defaults.gd")
const Index = preload("res://content/chapters/index.gd")
const Registry = preload("res://services/chapter_registry.gd")
const SoundMap = preload("res://services/chapter_sound_map.gd")
const SoundCues = preload("res://services/sound_cues.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const Journey = preload("res://core/journey/stage_catalog.gd")
const Seven = preload("res://core/journey/seven_mechanisms.gd")
const Sample = preload("res://tests/block_level_sample.gd")
const SAMPLE := ["res://tests/block_level_sample.gd", "source"]

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> bool:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
	return value

func _run() -> void:
	_check_rows()
	_check_cues()
	_check_hints()
	_check_fill()
	_check_sample_plays()
	_check_registered()
	print("BLOCK DEFAULTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _check_rows() -> void:
	for block: String in Blocks.NEEDS: _check(Defaults.BLOCKS.has(block), "Block %s has a defaults row" % block)
	for block: String in Defaults.BLOCKS: _check(Blocks.NEEDS.has(block), "Defaults row %s is a block" % block)

## What the shared sound map plays for each moment a block makes, with no
## chapter override: a cooperative and a journey chapter that set none.
func _check_cues() -> void:
	var heard := {}
	for cue: String in _cues("high-and-low@1", {}, {"role": "a", "events": ["drop"]}): heard[cue] = "drop"
	for cue: String in _cues("high-and-low@1", {}, {"role": "a", "events": ["bell"]}): heard[cue] = "bell"
	for cue: String in _cues("high-and-low@1", {}, {"role": "a", "events": ["bridge_opened:blue-stair"]}): heard[cue] = "route opened"
	for cue: String in _cues("high-and-low@1", {"bridges": {"blue-stair": true}}, {"role": "a", "bridges": {"blue-stair": false}}): heard[cue] = "route shut"
	for cue: String in _cues("high-and-low@1", {"levers": {}}, {"role": "a", "levers": {"shore-lever": true}}): heard[cue] = "lever"
	for cue: String in _cues("long-way-home@1", {"controls": {"path-selector": "home"}}, {"role": "a", "controls": {"path-selector": "friend"}}): heard[cue] = "switch"
	_check(heard.size() == 6, "Each probed moment has its own cue: %s" % heard)
	for block: String in Defaults.BLOCKS:
		for cue: String in Defaults.BLOCKS[block].cues:
			_check(SoundCues.CUES.has(cue) and heard.has(cue), "Block %s's cue %s is one the sound map plays" % [block, cue])
	# A look a block names brings that look's own cues.
	for look: String in SoundCues.LOOK_CUES: _check(SoundCues.look_cue(look, "lever_pulled") != "lever_pulled", "Look %s has its own cue" % look)

func _cues(key: String, before: Dictionary, after: Dictionary) -> Array:
	var seen := SoundMap.remember(before)
	return SoundMap.cues(key, after, seen).cues

func _check_hints() -> void:
	for block: String in Defaults.BLOCKS:
		for field: String in ["hint_a", "hint_b"]:
			if not Defaults.BLOCKS[block].has(field): continue
			var hint := str(Defaults.BLOCKS[block][field])
			_check(not hint.is_empty() and hint.ends_with(".") and hint[0] == hint[0].to_upper(), "Block %s's %s is a sentence" % [block, field])
			for dash: String in ["—", "–", " - "]: _check(not hint.contains(dash), "Block %s's %s has no dash" % [block, field])

func _check_fill() -> void:
	var journey := {"family": "journey", "block_source": SAMPLE, "stage_copy": {}, "lever_looks": {}, "water_levels": {}}
	Defaults.fill(journey)
	var copy: Dictionary = journey.stage_copy.get("the-yard", {})
	_check(copy == {"title": "The Yard", "hint_a": Defaults.BLOCKS.hold_door.hint_a, "hint_b": Defaults.BLOCKS.ring_bell.hint_b}, "A journey stage gets its title and its first and last blocks' hints: %s" % copy)
	_check(journey.lever_looks == {"sluice": "valve", "gate-chain": "winch"}, "Lever and selector looks come from the blocks: %s" % journey.lever_looks)
	_check(journey.water_levels == {"sluice": ["low", "high"]}, "A water switch's values become its water levels")
	var given := {"family": "journey", "block_source": SAMPLE, "stage_copy": {"the-yard": {"title": "Mine", "hint_a": "A.", "hint_b": "B."}}, "lever_looks": {"gate-chain": "bolt"}, "water_levels": {}}
	Defaults.fill(given)
	_check(given.stage_copy["the-yard"].title == "Mine" and given.lever_looks == {"sluice": "valve", "gate-chain": "bolt"}, "A descriptor's own fields win over the defaults")
	var cooperative := {"family": "cooperative", "block_source": SAMPLE, "stage_copy": {}, "lever_looks": {}, "water_levels": {}}
	Defaults.fill(cooperative)
	_check(cooperative.stage_copy.is_empty(), "A cooperative chapter shows its hashed hints, so it gets no stage copy")
	var none := {"family": "journey", "stage_copy": {}, "lever_looks": {}, "water_levels": {}}
	var before := none.duplicate(true)
	Defaults.fill(none)
	_check(none == before, "A descriptor with no block source is left alone")
	_check(not JSON.stringify(Sample.definition()).contains("look") and not JSON.stringify(Sample.definition()).contains("water"), "A block's look and water marks never reach the hashed definition")

## The sample's gates, read by the journey engine's own predicate (an
## unregistered level cannot start the engine itself; the published rewrites
## in test_stage_blocks play through it): its step holds the crossing open,
## its switch opens the ford, its lever the back gate.
func _check_sample_plays() -> void:
	var source := Sample.source()
	_check(Blocks.problems(source).is_empty(), "The sample has no block problems: %s" % [Blocks.problems(source)])
	var level := Sample.definition()
	var stage: Dictionary = Journey.stage_definition(level, "the-yard")
	var away := {"p0": {"x": 100, "z": 0, "height": 0, "surface_id": "near"}, "p1": {"x": 100, "z": 120, "height": 0, "surface_id": "near"}}
	var on_step := away.duplicate(true)
	on_step.p0.x = 200
	var start := {"controls": {"sluice": "low"}, "levers": {}}
	var turned := {"controls": {"sluice": "high"}, "levers": {}}
	var pulled := {"controls": {"sluice": "low"}, "levers": {"gate-chain": true}}
	_check(not _open(stage, "crossing", away, start) and not _open(stage, "ford", away, start) and not _open(stage, "back-gate", away, start), "Every crossing starts shut")
	_check(_open(stage, "crossing", on_step, start), "Standing on the step holds the crossing open")
	_check(_open(stage, "ford", away, turned) and not _open(stage, "crossing", away, turned), "The switch at high opens the ford alone")
	_check(_open(stage, "back-gate", away, pulled), "The pulled lever opens the back gate")

func _open(stage: Dictionary, route: String, players: Dictionary, mechanisms: Dictionary) -> bool:
	for gate: Dictionary in stage.gates:
		if gate.route_id == route and Seven.predicate(gate.get("when", {}), stage, players, mechanisms): return true
	return false

## A registered chapter built from blocks is exactly its blocks expanded.
func _check_registered() -> void:
	for key: String in Index.keys():
		var data := Index.data(key)
		if data.block_source.is_empty(): continue
		_check(Canonical.same(Blocks.expand(Defaults.source_of(data)), Registry.definition(key)), "%s is its block source expanded" % key)
		_check(Blocks.problems(Defaults.source_of(data)).is_empty(), "%s's blocks have no problems" % key)
