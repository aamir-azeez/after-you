extends SceneTree
## Pair tags (presentation/kit/level_hints.gd): the | || ||| strokes, crests
## and symbols that pair a control (a pad, a lever, a valve) with the gate it
## works, built in every stage of every chapter whose world draws them:
## - every tag a control has on a stage shows the same glyph and count, at the
##   control and at its gate alike, and the control shows it at both ends;
## - no two controls on a stage show the same tag;
## - each tag lies within the stage's floors and clear of every other pair's tag.
## Tags are presentation only; the stage definition is never changed.
const Registry = preload("res://services/chapter_registry.gd")
const CooperativeCatalog = preload("res://core/cooperative/stage_catalog.gd")
const LevelHints = preload("res://presentation/kit/level_hints.gd")
const Canonical = preload("res://core/v2/canonical.gd")
## How far outside its floors a tag may lie (beside a crossing's end).
const FLOOR_MARGIN := 0.4
## Tags closer than this in height share a floor.
const SAME_FLOOR := 0.1
## Pairs drawn as they were on main when the kit came in (changing them is a
## visible change, which waits for the owner): "<chapter key>: <check> <control>"
## -> why, for every stage of that chapter. An entry no failing check matches fails.
const KNOWN := {
	"a-house-for-two@1: mixed stair-weight": "the stair weight's pad shows two route symbol bars and, as its crossing is on another floor, the floor cables' link tags too",
	"a-house-for-two@1: overlap workshop-lever": "the workshop lever's and the entry weight's tags lie on the same crossing end",
	"high-and-low@1: shared loft-lever": "the loft lever and the ledge switch open the same crossings and both show the floor cables' two link tags",
	"high-and-low@1: overlap lower-ledge-switch": "the ledge switch's and the loft lever's link tags lie on the same crossing end",
	"long-way-home@1: shared porch-shutter": "journey crests are one bar for four named controls and two for every other, so several controls share two bars",
	"long-way-home@2: shared porch-shutter": "journey crests are one bar for four named controls and two for every other, so several controls share two bars",
	"long-way-home@2: shared hall-lamp": "journey crests are one bar for four named controls and two for every other, so several controls share two bars",
	"long-way-home@2: shared walk-gate": "journey crests are one bar for four named controls and two for every other, so several controls share two bars",
	"long-way-home@1: overlap near-window": "the near window's crest at its crossing touches the porch shutter's crest",
	"long-way-home@2: overlap near-window": "the near window's crest at its crossing touches the porch shutter's crest",
	"long-way-home@2: one-sided garden-window": "the garden pad shows a crest by the pad but none at its window",
	"turn-of-the-tide@1: overlap bollard-pad": "the bollard pad's crest at its crossing touches the gangway's crest beside its machine",
	"turn-of-the-tide@2: overlap bollard-pad": "the bollard pad's crest at its crossing touches the gangway's crest beside its machine",
}
var checks := 0
var failures := 0
var _known_seen := {}

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var tagged := 0
	for key: String in Registry.keys():
		var world: Node3D = Registry.world_script(key).new()
		if not "pair_tags" in world:
			world.free()
			continue
		root.add_child(world)
		world.set_process(false)
		var level := Registry.definition(key)
		var digest := Canonical.digest(level)
		world.load_level(level)
		for stage: Dictionary in level.stages:
			world.show_stage(stage)
			tagged += _stage(world, key, CooperativeCatalog.stage_definition(level, str(stage.id)))
		_check(Canonical.digest(level) == digest, "%s: tags never change the definition" % key)
		world.free()
	_check(tagged > 40, "The sweep sees the chapters' pair tags: %d" % tagged)
	for id: String in KNOWN: _check(_known_seen.has(id), "KNOWN names '%s', which no check fails now: delete it" % id)
	print("PAIR TAGS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## One stage's checks; returns how many tags it has.
func _stage(world: Node3D, key: String, view: Dictionary) -> int:
	var where := "%s %s" % [key, world.displayed_stage_id]
	var placed: Array[Dictionary] = world.pair_tags.placed()
	var by_control: Dictionary = {}
	for tag: Dictionary in placed:
		_check(tag.side in [LevelHints.CONTROL, LevelHints.GATE, LevelHints.SIGN], "%s: tag of %s says which end it marks" % [where, tag.control])
		if not by_control.has(tag.control): by_control[tag.control] = []
		by_control[tag.control].append(tag)
	var shown: Dictionary = {}
	for control: String in by_control:
		var tags: Array = by_control[control]
		var look := _look(tags[0])
		_known_or_check(key, "mixed", control, tags.all(func(t: Dictionary) -> bool: return _look(t) == look), "%s: every tag of %s shows the same %s (%s)" % [where, control, look, tags.map(_look)])
		var sides: Array = tags.map(func(t: Dictionary) -> StringName: return t.side)
		_known_or_check(key, "one-sided", control, LevelHints.CONTROL in sides and (LevelHints.GATE in sides or LevelHints.SIGN in sides), "%s: %s shows its tag by the control and at its gate (%s)" % [where, control, sides])
		if shown.has(look): _known_or_check(key, "shared", control, false, "%s: %s shows %s, the tag of %s too" % [where, control, look, shown[look]])
		else: shown[look] = control
	_placement(key, where, view, placed)
	return placed.size()

## A tag's look: its family, glyph and count.
static func _look(tag: Dictionary) -> String:
	return "%s %s %d" % [tag.style, tag.shape[0], tag.shape[1]]

## Within the floors and clear of every other pair's tags.
func _placement(key: String, where: String, view: Dictionary, placed: Array[Dictionary]) -> void:
	var floors: Array[Rect2] = []
	for entity: Dictionary in view.get("islands", []) + view.get("bridges", []) + view.get("stairs", []): floors.append(_rect(entity.rect_cm))
	var flat: Array[Dictionary] = placed.filter(func(t: Dictionary) -> bool: return t.side != LevelHints.SIGN)
	for index in range(flat.size()):
		var tag: Dictionary = flat[index]
		var at: Vector3 = tag.at
		_known_or_check(key, "floors", tag.control, floors.any(func(r: Rect2) -> bool: return r.grow(FLOOR_MARGIN).has_point(Vector2(at.x, at.z))), "%s: %s's %s tag lies within the stage's floors at %s" % [where, tag.control, tag.side, Vector2(at.x, at.z)])
		for other in range(index + 1, flat.size()):
			var them: Dictionary = flat[other]
			if them.control == tag.control or absf((them.at as Vector3).y - at.y) > SAME_FLOOR: continue
			_known_or_check(key, "overlap", tag.control, not _footprint(tag).intersects(_footprint(them)), "%s: %s's %s tag lies clear of %s's %s tag" % [where, tag.control, tag.side, them.control, them.side])

## A tag's footprint across the floor: its glyphs side by side.
static func _footprint(tag: Dictionary) -> Rect2:
	var spec: Dictionary = LevelHints.STYLES[tag.style]
	var bar: Vector3 = spec.bar
	var half := Vector2((float(int(tag.shape[1]) - 1) * float(spec.spacing) + maxf(bar.x, bar.z)) * 0.5, maxf(bar.x, bar.z) * 0.5)
	var at: Vector3 = tag.at
	return Rect2(Vector2(at.x, at.z) - half, half * 2.0)

static func _rect(r: Array) -> Rect2:
	return Rect2(Vector2(float(r[0]), float(r[1])) / 100.0, Vector2(float(r[2] - r[0]), float(r[3] - r[1])) / 100.0)

## A check that may fail as KNOWN says ("<key>: <check>" for a whole chapter,
## or "<key>: <check> <control>" for one control).
func _known_or_check(key: String, check: String, control: String, ok: bool, message: String) -> void:
	if not ok:
		for id: String in ["%s: %s %s" % [key, check, control], "%s: %s" % [key, check]]:
			if KNOWN.has(id):
				_known_seen[id] = true
				return
	_check(ok, message)

func _check(condition: bool, message: String) -> void:
	checks += 1
	if condition: return
	failures += 1
	push_error(message)
